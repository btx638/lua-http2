local hpack = require "hpack"

local frame_parser = {}

-- DATA frame parser
frame_parser[0x0] = function(stream, flags, payload)
  local end_stream = (flags & 0x1) ~= 0
  local padded = (flags & 0x8) ~= 0
  table.insert(stream.data, payload)
  return payload
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
  return header_list
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

local function get_headers(stream)
  while  #stream.headers == 0 do
    local ftype, flags, stream_id, payload = stream.connection.recv_frame(stream.connection)
    local s = stream.connection.streams[stream_id]
    local parser = frame_parser[ftype]
    local res = parser(s, flags, payload)
  end
  return table.remove(stream.headers, 1)
end

local function get_message_data(stream)
  local result = {}
  local s
  while true do
    local _, flags, stream_id, data_payload = stream.connection.recv_frame(stream.connection)
    s = stream.connection.streams[stream_id]
    local parser = frame_parser[0x0]
    local data = parser(s, flags, data_payload)
    if flags == 0x01 then break end
  end
  while #s.data > 0 do
    table.insert(result, table.remove(s.data, 1))
  end
  return table.concat(result)
end

local function new(connection)
  local self = {
    connection = connection,
    state = "idle",
    id = nil,
    parent = nil,
    data = {},
    headers = {},
    window = 65535
  }
  return self
end

local stream = {
  new = new,
  frame_parser = frame_parser,
  get_message_data = get_message_data,
  get_headers = get_headers
}

return stream
