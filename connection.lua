local hpack = require "hpack"
local stream = require "stream"
local socket = require "socket"

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
  MAX_CONCURRENT_STREAMS = 1, -- TODO: set to infinite
  INITIAL_WINDOW_SIZE    = 65535,
  MAX_FRAME_SIZE         = 16384,
  MAX_HEADER_LIST_SIZE   = 25600
}

local function send_frame(ftype, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  tcp:send(header)
  tcp:send(payload)
end

local function recv_frame()
  -- 4.1. Frame Format
  -- All frames begin with a fixed 9-octet header followed by a variable-length payload.
  local header = tcp:receive(9)
  local length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
  local payload = tcp:receive(length)
  stream_id = stream_id & 0x7fffffff
  return ftype, flags, stream_id, payload
end


local function get_server_settings()
  local server_settings = {}
  -- Receives the Server Connection Preface
  local ftype, flags, stream_id, settings_payload = recv_frame()
  for i = 1, #settings_payload, 6 do
    id, v = string.unpack(">I2 I4", settings_payload, i)
    server_settings[settings_parameters[id]] = v
    server_settings[id] = v
  end
  -- Acknowledging the server settings
  send_frame(0x4, 0x1, 0, "")
  return server_settings
end

local function initiate_connection()
  local i = 0
  local t = {}
  -- Settings parameters indexed both as names and as hexadecimal identifiers
  for id = 0x1, 0x6 do
    settings_parameters[settings_parameters[id]] = id
    default_settings[id] = default_settings[settings_parameters[id]]
  end
  tcp:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
  for k, v in ipairs(default_settings) do
    t[i * 2 + 1] = k
    t[i * 2 + 2] = v
    i = i + 1
  end
  local payload = string.pack(">" .. ("I2I4"):rep(i), table.unpack(t, 1, i * 2))
  send_frame(0x4, 0, 0, payload)
end

-- TODO: move this thing to the stream module
local function create_stream()
  local self = {
    state = "idle",
    id = nil
  }
  return self
end

local function new(uri)
  local self = {
    max_stream_id = 1,
    hpack_context = nil,
    server_settings = {},
    send_frame = send_frame,
    recv_frame = recv_frame,
    create_stream = create_stream
  }
  tcp:connect(uri, 8080)
  initiate_connection()
  self.server_settings = get_server_settings()
  local server_table_size = self.server_settings.HEADER_TABLE_SIZE
  local default_table_size = default_settings.HEADER_TABLE_SIZE
  self.hpack_context = hpack.new(server_table_size or default_table_size)
  return self
end

local connection = {
  new = new
}

return connection
