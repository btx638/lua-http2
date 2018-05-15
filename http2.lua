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

-- 1) Send a HEADERS frame with the requested header list
-- 2) Returns the newly created stream and the response header list
local function submit_request(connection, headers, request_body)
  -- TODO: stream flow control
  local stream = create_stream()
  stream.id = connection.max_stream_id + 2
  connection.max_stream_id = stream.id

  print("# REQUEST\n\n## HEADERS")
  for _, header_field in ipairs(headers) do
    for name, value in pairs(header_field) do
      print(name, value)
    end
  end

  -- Request header list
  local flags = 0x4 | 0x1
  local header_block = hpack.encode(connection.hpack_context, headers)
  send_frame(0x1, flags, stream.id, header_block)
  if request_body then
    send_frame(0x0, 0x1, stream.id, request_body)
  end
  -- Server ACKed our settings
  recv_frame()
  ---- Response header list
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
  -- TODO: Only one HEADERS frame is sent (END_HEADERS flag set and no CONTINUATION frames)
  if pad_length > 0 then
    headers_payload = headers_payload:sub(1, - pad_length - 1)
  end
  local header_list = hpack.decode(connection.hpack_context, headers_payload)
  print("\n\n# RESPONSE\n\n## HEADERS")
  for _, header_field in ipairs(header_list) do
    for name, value in pairs(header_field) do
      print(name, value)
    end
  end
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
  tcp:connect(uri, 8080)
  connection.server_settings = settings()
  local server_table_size = connection.server_settings.HEADER_TABLE_SIZE
  local default_table_size = default_settings.HEADER_TABLE_SIZE
  connection.hpack_context = hpack.new(server_table_size or default_table_size)
  --local request_headers = {[1] = {[":method"] = "GET"},
  --                         [2] = {[":path"] = "/"},
  --                         [3] = {[":scheme"] = "http"},
  --                         [4] = {[":authority"] = "localhost:8080"},
  --                        }
  local request_headers = {[1] = {[":method"] = "GET"},
                           [2] = {[":path"] = "/ko.html"},
                           [3] = {[":scheme"] = "http"},
                           [4] = {[":authority"] = "localhost:8080"},
                           [5] = {["content-type"] = "text/html"},
                           [6] = {["content-length"] = "126"},
                          }
  local request_body = "<html><head><title>ko</title></head><body><h1>KO</h1><hr><address>nghttpd nghttp2/1.30.0 at port 8080</address></body></html>"
  -- Performs the request
  local response_headers, stream = submit_request(connection, request_headers, request_body)
  -- DATA frame containing the message payload
  local _, flags, stream_id, data_payload = recv_frame()
  local end_stream = (flags & 0x1) ~= 0
  local padded = (flags & 0x8) ~= 0
  print(data_payload)
  tcp:close()
end

local http2 = {
  request = request
}

return http2
