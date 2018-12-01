local framer = require "framer"
local stream = require "stream"

local mt = {__index = {}}

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
  ENABLE_PUSH            = 0,
  MAX_CONCURRENT_STREAMS = 2^32 - 1,
  INITIAL_WINDOW_SIZE    = 65535,
  MAX_FRAME_SIZE         = 16384,
  MAX_HEADER_LIST_SIZE   = 2^32 - 1
}

local tls =  {
  mode = "client",
  protocol = "any",
  options = {"all", "no_sslv2", "no_sslv3"},
  verify = "none",
  alpn = "h2"
}

-- Settings indexed both as names and as hexadecimal identifiers
for id = 0x1, 0x6 do
  settings_parameters[settings_parameters[id]] = id
  default_settings[id] = default_settings[settings_parameters[id]]
end

function mt.__index:window_update(payload)
  self.window = self.window + payload.increment
  local buffer = framer.encode({type = "WINDOW_UPDATE", streamid = 0, increment = payload.increment})
  self.skt:send(buffer)
end

function mt.__index:settings(payload)
  local buffer = framer.encode({type = "SETTINGS", streamid = 0, settings = payload.settings, ack = payload.ack})
  self.skt:send(buffer)
end

function mt.__index:goaway(payload)
  local buffer = framer.encode({type = "GOAWAY", streamid = 0, last_streamid = self.last_stream_id_server, err = payload.err})
  self.skt:send(buffer)
end

function mt.__index:parse_stream()
  local frame = framer.decode(self.skt)
  --print(frame.type, frame.flags, frame.streamid)
  local s = self.streams[frame.streamid]
  if not s then
    self.last_stream_id_server = frame.streamid
    s = self:new_stream(frame.streamid)
  end
  s:parse(frame)
  return s
end

function mt.__index:preface()
  self:settings({settings = default_settings, ack = false})
  self:parse_stream() -- error: not a server preface
end

function mt.__index:new_stream(identifier)
  local s = stream.new(self)
  if identifier then
    s.id = identifier
    if s.id ~= 0 then
      if s.id % 2 == 0 then
        self.max_server_streamid = math.max(self.max_server_streamid, s.id)
      else
        self.max_client_streamid = math.max(self.max_client_streamid, s.id)
      end
    end
  else
    self.max_client_streamid = self.max_client_streamid + 2
    s.id = self.max_client_streamid
  end
  self.streams[s.id] = s
  return s
end

local function new(o)
  local connection = setmetatable(o or {
    streams = {},
    skt = nil,
    window = 65535,
    max_client_streamid = 1,
    max_server_streamid = 2,
    hpack_context = nil,
    server_settings = {},
    settings_parameters = settings_parameters,
    default_settings = default_settings,
    last_stream_id_server = 0,
    header_block_fragment = nil,
    tls = tls
  }, mt)
  return connection
end

return {
  new = new,
}