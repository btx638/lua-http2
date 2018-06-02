local hpack = require "http2.hpack"
local stream = require "http2.stream"
local socket = require "socket"
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
  MAX_CONCURRENT_STREAMS = 100,
  INITIAL_WINDOW_SIZE    = 65535,
  MAX_FRAME_SIZE         = 16384,
  MAX_HEADER_LIST_SIZE   = 25600
}

local mt = {__index = {}}

function mt.__index:send_frame(ftype, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  self.client:send(header)
  self.client:send(payload)
end

function mt.__index:step()
  -- All frames begin with a fixed 9-octet header followed by a variable-length payload.
  local header = copas.receive(self.client, 9)
  local length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
  local payload = copas.receive(self.client, length)
  stream_id = stream_id & 0x7fffffff
  local s = self.streams[stream_id]
  if s == nil then s = stream.new(conn, stream_id) end
  s:parse_frame(ftype, flags, payload)
end

local function handle_server_settings(conn)
  copas.sleep(0)
  while #conn.server_settings == 0 do
    conn:step()
  end
end

function mt.__index:get_server_settings()
  copas.addthread(handle_server_settings, self)
  copas.loop()
end

-- The client connection preface is sent upon connection establishment
-- It MUST be followed by a SETTINGS frame
local function initiate_connection(conn, host, port)
  local i = 0
  local t = {}
  conn.client = socket.tcp()
  conn.client:connect(host, port)
  stream.new(conn, 0)
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
  conn:send_frame(0x4, 0, 0, payload)
  -- The server connection preface consists of a potentially empty SETTINGS frame
  -- It MUST be the first frame the server sends in the HTTP/2 connection
  conn:get_server_settings()
  -- The SETTINGS frames received from a peer as part of the connection preface
  -- MUST be acknowledged after sending the connection preface.]]
  conn:send_frame(0x4, 0x1, 0, "")
  local server_table_size = conn.server_settings.HEADER_TABLE_SIZE
  local default_table_size = default_settings.HEADER_TABLE_SIZE
  conn.hpack_context = hpack.new(server_table_size or default_table_size)
end

local function new(host, port)
  local connection = setmetatable({
    client = nil,
    max_client_streamid = 1,
    max_server_streamid = 2,
    hpack_context = nil,
    server_settings = {},
    streams = {},
    settings_parameters = settings_parameters,
    default_settings = default_settings,
    window = 65535
  }, mt)
  initiate_connection(connection, host, port)
  return connection
end

local connection = {
  new = new
}

return connection
