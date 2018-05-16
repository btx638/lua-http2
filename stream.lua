local hpack = require "hpack"

local frame_parser = {}

-- DATA frame parser
frame_parser[0x0] = function(stream, flags, payload)
  local end_stream = (flags & 0x1) ~= 0
  local padded = (flags & 0x8) ~= 0
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
  local server_settings = {}
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
end

-- CONTINUATION frame parser
frame_parser[0x9] = function(stream, flags, payload)
end

local function new(connection)
  local self = {
    connection = connection,
    state = "idle",
    id = nil,
    parent = nil
  }
  return self
end

local stream = {
  new = new,
  frame_parser = frame_parser
}

return stream
