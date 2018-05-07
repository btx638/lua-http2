local socket = require "socket"
local hpack = require "hpack"
local tcp = assert(socket.tcp())

local settings_parameters = {
  HEADER_TABLE_SIZE      = 0x1,
  ENABLE_PUSH            = 0x2,
  MAX_CONCURRENT_STREAMS = 0x3,
  INITIAL_WINDOW_SIZE    = 0x4,
  MAX_FRAME_SIZE         = 0x5,
  MAX_HEADER_LIST_SIZE   = 0x6
}

local initial_settings_parameters = {
  HEADER_TABLE_SIZE      = 4096,
  ENABLE_PUSH            = 1,
  MAX_CONCURRENT_STREAMS = math.huge,
  INITIAL_WINDOW_SIZE    = 65535,
  MAX_FRAME_SIZE         = 16384,
  MAX_HEADER_LIST_SIZE   = math.huge
}

-- 1) Send a HEADERS frame with the requested headers
-- 2) Returns the newly created stream
local function create_stream(headers)
  local flags = 0x4 | 0x1
  local header_block = hpack.serialize(headers)
  local payload
  return stream
end

local function send_frame(frame_type, flags, stream_id, payload)
  local header = string.pack(">I3 B B I4", #payload, frame_type, flags, stream_id)
  tcp:send(header)
  tcp:send(payload)
end

local function start(host, port, param)
  local i = 0
  local p = {}
  local server_settings = {}
  tcp:connect(host, port)
  -- Client Connection Preface
  tcp:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
  for k, v in pairs(param) do
    p[i * 2 + 1] = settings_parameters[k]
    p[i * 2 + 2] = v
    i = i + 1
  end
  local settings_payload = string.pack(">" .. ("I2 I4"):rep(i), table.unpack(p, 1, i * 2))
  send_frame(0x4, 0, 0, settings_payload)
  -- Server Connection Preface
  local settings_header = tcp:receive(9)
  local length, frame_type, flags, stream_id = string.unpack(">I3 B B I4", settings_header)
  --Id = Id & 0x7fffffff
  local settings_payload = tcp:receive(length)
  for i = 1, #settings_payload, 6 do
    id, v = string.unpack(">I2 I4", settings_payload, i)
    server_settings[id] = v
  end
  send_frame(0x4, 0x1, 0, "") -- ACK
  local stream = create_stream({method = "GET"})
  tcp:close()
end

start("localhost", 5000, {ENABLE_PUSH = 0})
