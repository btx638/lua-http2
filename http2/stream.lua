local hpack = require "http2.hpack"
local copas = require "copas"

local mt = {__index = {}}

local frame_parser = {}

-- DATA frame parser
frame_parser[0x0] = function(stream, flags, payload)
  local end_stream = (flags & 0x1) ~= 0
  local padded = (flags & 0x8) ~= 0
  table.insert(stream.data, payload)
  if end_stream then table.insert(stream.data, "end_stream") end
end

-- HEADERS frame parser
frame_parser[0x1] = function(stream, flags, payload)
  local end_stream = (flags & 0x1) ~= 0
  local end_headers = (flags & 0x4) ~= 0
  local padded = (flags & 0x8) ~= 0
  local pad_length
  if padded then
    pad_length = string.unpack(">B", headers_payload)
  else
    pad_length = 0
  end
  local headers_payload_len = #payload - pad_length
  if pad_length > 0 then
    payload = payload:sub(1, - pad_length - 1)
  end
  local header_list = hpack.decode(stream.connection.hpack_context, payload)
  table.insert(stream.headers, header_list)
end

-- PRIORITY frame parser
frame_parser[0x2] = function(stream, flags, payload)
end

-- RST_STREAM frame parser
frame_parser[0x3] = function(stream, flags, payload)
end

-- SETTING frame parser
frame_parser[0x4] = function(stream, flags, payload)
  local server_settings = stream.connection.default_settings
  local ack = flags & 0x1 ~= 0
  if ack then
    return
  else
    for i = 1, #payload, 6 do
      id, v = string.unpack(">I2 I4", payload, i)
      server_settings[stream.connection.settings_parameters[id]] = v
      server_settings[id] = v
    end
  end
  return server_settings
end

-- PUSH_PROMISE frame parser
frame_parser[0x5] = function(stream, flags, payload)
end

-- PING frame parser
frame_parser[0x6] = function(stream, flags, payload)
end

-- GOAWAY frame parser
frame_parser[0x7] = function(stream, flags, payload)
end

-- WINDOW_UPDATE frame parser
frame_parser[0x8] = function(stream, flags, payload)
  local bytes = string.unpack(">I4", payload)
  local increment = bytes & 0x7fffffff
  if stream.id == 0 then
    stream.connection.window = stream.connection.window + increment
  else
    stream.window = stream.window + increment
  end
end

-- CONTINUATION frame parser
frame_parser[0x9] = function(stream, flags, payload)
end

function mt.__index:send_window_update(size)
  local conn = self.connection
  conn.send_frame(conn, 0x8, 0x0, self.id, string.pack(">I4", size))
end

function mt.__index:send_headers(headers, body)
  local conn = self.connection
  local header_block = hpack.encode(conn.hpack_context, headers)
  if body then
    local fsize = conn.server_settings.MAX_FRAME_SIZE
    for i = 1, #body, fsize do
      if i + fsize >= #body then
        conn.send_frame(conn, 0x0, 0x1, self.id, string.sub(body, i))
      else
        conn.send_frame(conn, 0x0, 0x0, self.id, string.sub(body, i, i + fsize - 1))
      end
    end
  else
    conn.send_frame(conn, 0x1, 0x4 | 0x1, self.id, header_block)
  end
end

local function headers_handler(stream)
  copas.sleep(0)
  local conn = stream.connection
  while #stream.headers == 0 do
    local header = copas.receive(conn.client, 9)
    local length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
    local payload = copas.receive(conn.client, length)
    stream_id = stream_id & 0x7fffffff
    local s = conn.streams[stream_id]
    local parser = frame_parser[ftype]
    parser(s, flags, payload)
  end
end

local function body_handler(stream)
  copas.sleep(0)
  local conn = stream.connection
  while stream.data[#stream.data] ~= "end_stream" do
    local header = copas.receive(conn.client, 9)
    local length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
    local payload = copas.receive(conn.client, length)
    stream_id = stream_id & 0x7fffffff
    local s = conn.streams[stream_id]
    local parser = frame_parser[ftype]
    parser(s, flags, payload)
  end
  table.remove(stream.data)
end

function mt.__index:get_headers()
  copas.addthread(headers_handler, self)
  copas.loop()
  return table.remove(self.headers, 1)
end

function mt.__index:get_body()
  copas.addthread(body_handler, self)
  copas.loop()
  return table.concat(self.data)
end

local function new(connection)
  local stream = setmetatable({
    connection = connection,
    state = "idle",
    id = nil,
    parent = nil,
    data = {},
    headers = {},
    window = 65535
  }, mt)
  stream.id = connection.max_stream_id + 2
  connection.max_stream_id = stream.id
  connection.streams[stream.id] = stream
  return stream
end

local stream = {
  new = new,
  frame_parser = frame_parser
}

return stream
