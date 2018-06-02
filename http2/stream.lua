local hpack = require "http2.hpack"
local copas = require "copas"

local mt = {__index = {}}

local function new(connection, id)
  local stream = setmetatable({
    connection = connection,
    state = "idle",
    id = nil,
    parent = nil,
    headers = {},
    data = {},
    window = 65535,
    rst_stream_error = nil
  }, mt)
  if id then
    stream.id = id
    if id % 2 == 0 then
      stream.connection.max_server_streamid = math.max(stream.connection.max_server_streamid, id)
    else
      stream.connection.max_client_streamid = math.max(stream.connection.max_client_streamid, id)
    end
  else
    stream.id = stream.connection.max_client_streamid
    stream.connection.max_client_streamid = stream.id + 2
  end
  stream.connection.streams[stream.id] = stream
  return stream
end

function mt.__index:parse_frame(ftype, flags, payload)
  if ftype == 0x0 then
    -- DATA
    local end_stream = (flags & 0x1) ~= 0
    local padded = (flags & 0x8) ~= 0
    table.insert(self.data, payload)
    if end_stream then table.insert(self.data, "end_stream") end
  elseif ftype == 0x1 then
    -- HEADERS
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
    local header_list = hpack.decode(self.connection.hpack_context, payload)
    table.insert(self.headers, header_list)
  elseif ftype == 0x2 then
    -- PRIORITY
  elseif ftype == 0x3 then
    -- RST_STREAM
    local error_code = string.unpack(">I4", payload)
    self.rst_stream_error = error_code
    self.state = "closed"
  elseif ftype == 0x4 then
    -- SETTINGS
    local settings = self.connection.default_settings
    local ack = (flags & 0x1) ~= 0
    if ack then
      return
    end
    for i = 1, #payload, 6 do
      id, v = string.unpack(">I2 I4", payload, i)
      settings[self.connection.settings_parameters[id]] = v
      settings[id] = v
    end
    self.connection.server_settings = settings
  elseif ftype == 0x5 then
    -- PUSH_PROMISE
  elseif ftype == 0x6 then
    -- PING
  elseif ftype == 0x7 then
    -- GOAWAY
    local last_stream_id = string.unpack(">I4I4", payload)
    self.connection.last_stream_id = last_stream_id
  elseif ftype == 0x8 then
    -- WINDOW_UPDATE
    local bytes = string.unpack(">I4", payload)
    local increment = bytes & 0x7fffffff
    if self.id == 0 then
      self.connection.window = self.connection.window + increment
    else
      self.window = self.window + increment
    end
  elseif ftype == 0x9 then
    -- COTINUATION
  end
end

function mt.__index:encode_window_update(size)
  local conn = self.connection
  conn:send_frame(0x8, 0x0, self.id, string.pack(">I4", size))
end

function mt.__index:encode_data(payload, end_stream, padded)
  local conn = self.connection
  local flags = 0
  local pad_length = ""
  local padding = ""
  if end_stream then
    flags = flags | 0x1
  end
  if padded then
    flags = flags | 0x8
    pad_length = string.pack(">B", padded)
    padding = ("\0"):rep(padded)
  end
  payload = pad_length .. payload .. padding
  self.window = self.window - #payload
  self.connection.window = self.connection.window - #payload
  conn:send_frame(0x0, flags, self.id, payload)
end

function mt.__index:encode_headers(headers, body)
  local conn = self.connection
  local header_block = hpack.encode(conn.hpack_context, headers)
  if body then
    local fsize = conn.server_settings.MAX_FRAME_SIZE
    conn:send_frame(0x1, 0x4, self.id, header_block)
    for i = 0, #body, fsize do
      if i + fsize >= #body then
        self:encode_data(string.sub(body, i + 1), true)
      else
        self:encode_data(string.sub(body, i + 1, i + fsize), false)
      end
    end
  else
    conn:send_frame(0x1, 0x4 | 0x1, self.id, header_block)
  end
end

function mt.__index:encode_goaway(last_stream_id, error_code, debug_data)
  local conn = self.connection
  local payload = string.pack(">I4I4", last_stream_id, error_code)
  if debug_data then payload = payload .. debug_data end
  conn:send_frame(0x7, 0x0, 0, payload)
end

function mt.__index:encode_rst_stream(error_code)
  local conn = self.connection
  local payload= string.pack(">I4", error_code)
  conn:send_frame(0x3, 0x0, self.id, payload)
  self:encode_window_update(#self.data)
end

local function headers_handler(stream)
  copas.sleep(0)
  local conn = stream.connection
  while #stream.headers == 0 do
    conn:step()
  end
end

local function body_handler(stream)
  copas.sleep(0)
  local conn = stream.connection
  while stream.data[#stream.data] ~= "end_stream" do
    conn:step()
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

local stream = {
  new = new
}

return stream
