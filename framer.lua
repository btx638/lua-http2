local types = {
  [0x0] = "DATA",
  [0x1] = "HEADERS",
  [0x3] = "RST_STREAM",
  [0x4] = "SETTINGS",
  [0x7] = "GOAWAY",
  [0x8] = "WINDOW_UPDATE",
  [0x9] = "CONTINUATION"
}

-- types indexed both as names and as hexadecimal identifiers
for id = 0x1, 0x9 do
  if types[id] then
    types[types[id]] = id
  end
end

local function encode(frame)
  local payload = ""
  local padding = ""
  local paddlen = ""
  frame.flags = 0x0

  -- WINDOW_UPDATE
  if frame.type == "WINDOW_UPDATE" then
    payload = string.pack(">I4", frame.increment)
  end
  
  -- SETTINGS
  if frame.type == "SETTINGS" then
    local t = {}
    local i = 0
    if frame.ack then
      frame.flags = 0x1
    else
      for k, v in ipairs(frame.settings) do
        t[i * 2 + 1] = k
        t[i * 2 + 2] = v
        i = i + 1
      end
      payload = string.pack(">" .. ("I2I4"):rep(i), table.unpack(t, 1, i * 2))
    end
  end

  -- GOAWAY
  if frame.type == "GOAWAY" then
    payload = string.pack(">I4I4", frame.last_streamid, frame.err)
    if frame.debug then
      payload = payload .. debug
    end
  end

  if frame.end_stream then
    frame.flags = frame.flags | 0x1
  end

  if frame.end_headers then
    frame.flags = frame.flags | 0x4
    payload = frame.header_block
  end

  -- Process padding
  if frame.padded then
    frame.flags = frame.flags | 0x8
    paddlen = string.pack(">B", padded)
    padding = ("\0"):rep(padded)
    payload = paddlen .. payload .. padding
  end

  local header = string.pack(">I3BBI4", #payload, types[frame.type], frame.flags, frame.streamid)
  return header .. payload
end

local function decode(lock, buffer)
  local header, err = buffer:receive(9)
  local length, type, flags, streamid = string.unpack(">I3BBI4", header)
  local payload = buffer:receive(length)
  streamid = streamid & 0x7fffffff
  return {
    length = length,
    type = type,
    flags = flags,
    streamid =  streamid,
    payload = payload
  }
end

local frame = {
  encode = encode,
  decode = decode,
  types = types
}

return frame