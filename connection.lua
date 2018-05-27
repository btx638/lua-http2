local hpack = require "hpack"
local stream = require "stream"
local copas = require "copas"

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
  MAX_CONCURRENT_STREAMS = 100, -- TODO: set to infinite
  INITIAL_WINDOW_SIZE    = 65535,
  MAX_FRAME_SIZE         = 16384,
  MAX_HEADER_LIST_SIZE   = 25600 -- TODO: set to infinite
}

local function send_frame(conn, ftype, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  conn.client:send(header)
  conn.client:send(payload)
end

local function recv_frame(conn)
  -- 4.1. Frame Format
  -- All frames begin with a fixed 9-octet header followed by a variable-length payload.
  local header = conn.client:receive(9)
  local length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
  local payload = conn.client:receive(length)
  stream_id = stream_id & 0x7fffffff
  return ftype, flags, stream_id, payload
end

local function get_server_settings(conn)
  local s = conn.streams[0]
  local _, flags, _, settings_payload = recv_frame(conn)
  local parser = stream.frame_parser[0x4]
  local server_settings = parser(s, flags, settings_payload)
  return server_settings
end

-- The client connection preface is sent upon connection establishment
-- It MUST be followed by a SETTINGS frame
local function initiate_connection(conn)
  local i = 0
  local t = {}
  -- Settings parameters indexed both as names and as hexadecimal identifiers
  for id = 0x1, 0x6 do
    settings_parameters[settings_parameters[id]] = id
    default_settings[id] = default_settings[settings_parameters[id]]
  end
  conn.client:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
  for k, v in ipairs(default_settings) do
    t[i * 2 + 1] = k
    t[i * 2 + 2] = v
    i = i + 1
  end
  local payload = string.pack(">" .. ("I2I4"):rep(i), table.unpack(t, 1, i * 2))
  send_frame(conn, 0x4, 0, 0, payload)
  -- The server connection preface consists of a potentially empty SETTINGS frame
  -- It MUST be the first frame the server sends in the HTTP/2 connection
  conn.server_settings = get_server_settings(conn)
  --[[ The SETTINGS frames received from a peer as part of the connection preface
       MUST be acknowledged after sending the connection preface.]]
  conn.send_frame(conn, 0x4, 0x1, 0, "")
end

local function new(socket)
  local self = {
    client = socket,
    max_stream_id = 1,
    hpack_context = nil,
    server_settings = {},
    send_frame = send_frame, -- TODO: move these functions to the module table
    recv_frame = recv_frame, -- TODO: move these functions to the module table
    streams = {},
    next_stream = {},
    settings_parameters = settings_parameters,
    default_settings = default_settings,
    window = 65535
  }
  local stream0 = stream.new(self)
  stream0.id = 0
  self.streams[0] = stream0
  initiate_connection(self)
  local server_table_size = self.server_settings.HEADER_TABLE_SIZE
  local default_table_size = default_settings.HEADER_TABLE_SIZE
  self.hpack_context = hpack.new(server_table_size or default_table_size)
  return self
end

local connection = {
  new = new
}

return connection
