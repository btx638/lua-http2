local hpack = require "hpack"
local framer = require "framer"

local mt = {__index = {}}

function mt.__index:parse(frame)
  -- DATA
  if framer.types[frame.type] == "DATA" then
    local end_stream = (frame.flags & 0x1) ~= 0
    local padded = (frame.flags & 0x8) ~= 0
    if padded then
      local pad_length = string.unpack(">B", frame.payload)
      frame.payload = frame.payload:sub(2, - pad_length - 1)
    end
    self.frames.data = self.frames.data .. frame.payload
    self.connection.window = self.connection.window - frame.length
    self.window = self.window - frame.length
    if end_stream then
      self.state = "closed"
    else
      self.connection:window_update({increment = frame.length})
      self:window_update({increment = frame.length})
    end

  -- HEADERS
  elseif framer.types[frame.type] == "HEADERS" then
    local end_stream = (frame.flags & 0x1) ~= 0
    local end_headers = (frame.flags & 0x4) ~= 0
    local padded = (frame.flags & 0x8) ~= 0
    local seek
    local pad_length
    if padded then
      seek = 2
      pad_length = string.unpack(">B", frame.payload)
    else
      seek = 1
      pad_length = 0
    end
    if pad_length > 0 then
      frame.payload = frame.payload:sub(1, - pad_length - 1)
    end
    if end_headers then
      local header_list = hpack.decode(self.connection.hpack_context, frame.payload)
      table.insert(self.frames.headers, header_list)
      self.state = "open"
    else
      self.connection.header_block_fragment = {frame.payload}
    end

  -- SETTINGS
  elseif framer.types[frame.type] == "SETTINGS" then
    local settings = self.connection.default_settings
    local ack = (frame.flags & 0x1) ~= 0
    if ack then
      return
    end
    for i = 1, #frame.payload, 6 do
      id, v = string.unpack(">I2 I4", frame.payload, i)
      settings[self.connection.settings_parameters[id]] = v
      settings[id] = v
    end
    self.connection.server_settings = settings
    local server_table_size = self.connection.server_settings.HEADER_TABLE_SIZE
    local default_table_size = self.connection.default_settings.HEADER_TABLE_SIZE
    self.connection.hpack_context = hpack.new(server_table_size or default_table_size)
    self.connection:settings({settings = "", ack = true})
  
  -- WINDOW_UPDATE
  elseif framer.types[frame.type] == "WINDOW_UPDATE" then
    local bytes = string.unpack(">I4", frame.payload)
    local increment = bytes & 0x7fffffff
    if self.id == 0 then
      self.connection.window = self.connection.window + increment
    else
      self.window = self.window + increment
    end
  end
end

function mt.__index:headers(payload)
  local conn = self.connection
  local header_block = hpack.encode(conn.hpack_context, payload.headers)
  local buffer = framer.encode({type = "HEADERS", header_block = header_block, end_stream = payload.end_stream, end_headers = true, streamid = self.id})
  --conn.l:acquire()
  conn.skt:send(buffer)
  --conn.l:release()
  -- todo: #header_block > max_fsize
end

function mt.__index:window_update(payload)
  local conn = self.connection
  self.window = self.window + payload.increment
  local buffer = framer.encode({type = "WINDOW_UPDATE", streamid = self.id, increment = payload.increment})
  --conn.l:acquire()
  conn.skt:send(buffer)
  --conn.l:release()
end

local function new(conn, o)
  local stream = setmetatable(o or {
    connection = conn,
    state = "idle",
    frames = {data = "", headers = {}},
    window = 65535,
  }, mt)
  return stream
end

return {new = new}