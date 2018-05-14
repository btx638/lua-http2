local socket = require "socket"
local hpack = require "hpack"

local tcp = assert(socket.tcp())

local settings_parameters = {
  [0x1] = "HEADER_TABLE_SIZE",
  [0x2] = "ENABLE_PUSH",
  [0x3] = "MAX_CONCURRENT_STREAMS",
  [0x4] = "INITIAL_WINDOW_SIZE",
  [0x5] = "MAX_FRAME_SIZE",
  [0x6] = "MAX_HEADER_LIST_SIZE"
}

local default_settings = {
  HEADER_TABLE_SIZE      = 4096,
  ENABLE_PUSH            = 1,
  MAX_CONCURRENT_STREAMS = math.huge, -- can math.huge be the max?
  INITIAL_WINDOW_SIZE    = 65535,
  MAX_FRAME_SIZE         = 16384,
  MAX_HEADER_LIST_SIZE   = math.huge -- can math.huge be the max?
}

local function send_frame(frame_type, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, frame_type, flags, stream_id)
  tcp:send(header)
  tcp:send(payload)
end

local function recv_frame()
  -- 4.1. Frame Format
  -- All frames begin with a fixed 9-octet header followed by a variable-length payload.
  local header = tcp:receive(9)
  local length, frame_type, flags, stream_id = string.unpack(">I3BBI4", header)
  local payload = tcp:receive(length)
  return frame_type, flags, stream_id, payload
end

local function create_stream()
  local self = {
    state = "idle",
    id = nil
  }
  return self
end

-- 1) Send a HEADERS frame with the requested headers
-- 2) Returns the newly created stream and the response headers
local function submit_request(connection, headers)
  -- Request headers
  local flags = 0x4 | 0x1
  local max_frame_size = default_settings.HEADER_TABLE_SIZE
  local encoding_context = hpack.new(max_frame_size)
  local header_block = hpack.encode(encoding_context, headers)
  local payload = header_block
  send_frame(0x1, flags, 3, payload)
  -- Server ACKed our settings
  recv_frame()
  ---- Response headers
  local _, flags, stream_id, headers_payload = recv_frame()
  local end_stream = (flags & 0x1) ~= 0
  local end_headers = (flags & 0x4) ~= 0
  local padded = (flags & 0x8) ~= 0
  local pad_length
  if padded then
    pad_length = string.unpack(">B", headers_payload)
  else
    pad_length = 0
  end
  local headers_payload_len = #headers_payload - pad_length
  if end_headers then
    if pad_length > 0 then
      headers_payload = headers_payload:sub(1, - pad_length - 1)
    end
    local header_list = hpack.decode(connection.hpack_context, headers_payload)
    for _, header_field in ipairs(header_list) do
      for name, value in pairs(header_field) do
        print(name, value)
      end
    end
  end
  local stream = create_stream()
  stream.id = connection.max_stream_id + 2
  connection.max_stream_id = stream_id
  return header_list, stream
end

-- TODO: treat errors
local function settings()
  -- SETTINGS parameters indexed both as names and identifiers
  for id = 0x1, 0x6 do
    settings_parameters[settings_parameters[id]] = id
    default_settings[id] = default_settings[settings_parameters[id]]
  end
  local i = 0
  local p = {}
  local server_settings = {}
  -- Sends the Client Connection Preface
  tcp:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")

  --to send a non-empty SETTINGS frame (default settings):
  --for k, v in ipairs(default_settings) do
  --  p[i * 2 + 1] = k
  --  p[i * 2 + 2] = v
  --  i = i + 1
  --end
  --local settings_payload = string.pack(">" .. ("I2I4"):rep(i), table.unpack(p, 1, i * 2))
  --send_frame(0x4, 0, 0, settings_payload)

  -- Sends an empty SETTINGS frame
  send_frame(0x4, 0, 0, "")
  -- Receives the Server Connection Preface
  local _, _, _, settings_payload = recv_frame()
  for i = 1, #settings_payload, 6 do
    id, v = string.unpack(">I2 I4", settings_payload, i)
    server_settings[settings_parameters[id]] = v
    server_settings[id] = v
  end
  -- Acknowledge the server settings
  send_frame(0x4, 0x1, 0, "")
  return server_settings
end

local function request(uri)
  local connection = {
    max_stream_id = 1,
    hpack_context = nil,
    server_settings = nil
  }
  -- TODO: change port to 80
  tcp:connect(uri, 5000)
  --[[ If starting an HTTP/2 connection with prior knowledge of server support
      for the protocol, the client connection preface is sent upon connection
      establishment.
  ]]
  connection.server_settings = settings()
  local server_table_size = connection.server_settings.HEADER_TABLE_SIZE
  local default_table_size = default_settings.HEADER_TABLE_SIZE
  local header_table_size = server_table_size or default_table_size
  connection.hpack_context = hpack.new(header_table_size)
  local request_header_list = {[1] = {[":method"] = "GET"},
                               [2] = {[":path"] = "/"},
                               [3] = {[":scheme"] = "http"},
                               [4] = {[":authority"] = "localhost:8080"},
                               [5] = {["accept"] = "*/*"},
                               [6] = {["user-agent"] = "http2_client"},
                               [7] = {["accept-encoding"] = "gzip, deflate"}
                              }
  -- Performs the request
  local response_header_list, stream = submit_request(connection, request_header_list)
  -- DATA frame containing the message payload
  local _, flags, stream_id, headers_payload = recv_frame()
  local end_stream = (flags & 0x1) ~= 0
  local padded = (flags & 0x8) ~= 0
  tcp:close()
end

local http2 = {
  request = request
}

return http2
