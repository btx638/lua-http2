local hpack = require "http2.hpack"

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
  local conn = stream.connection
  if id then
    stream.id = id
    if id ~= 0 then
      if id % 2 == 0 then
        conn.max_server_streamid = math.max(conn.max_server_streamid, id)
      else
        conn.max_client_streamid = math.max(conn.max_client_streamid, id)
      end
    end
  else
    stream.id = conn.max_client_streamid
    conn.max_client_streamid = stream.id + 2
  end
  conn.streams[stream.id] = stream
  return stream
end

function mt.__index:parse_frame(ftype, flags, payload)
  if ftype == 0x0 then
    -- DATA
    local end_stream = (flags & 0x1) ~= 0
    local padded = (flags & 0x8) ~= 0
    if padded then
      local pad_length = string.unpack(">B", payload)
      payload = payload:sub(2, - pad_length - 1)
    end
    table.insert(self.data, payload)
    if end_stream then
      self.state = "closed"
    end
  elseif ftype == 0x1 then
    -- HEADERS
    local end_stream = (flags & 0x1) ~= 0
    local end_headers = (flags & 0x4) ~= 0
    local padded = (flags & 0x8) ~= 0
    local seek
    local pad_length
    if padded then
      seek = 2
      pad_length = string.unpack(">B", payload)
    else
      seek = 1
      pad_length = 0
    end
    if pad_length > 0 then
      payload = payload:sub(1, - pad_length - 1)
    end
    if end_headers then
      local header_list = hpack.decode(self.connection.hpack_context, payload)
      table.insert(self.headers, header_list)
    else
      self.connection.header_block_fragment = {payload}
    end
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
    local server_table_size = self.connection.server_settings.HEADER_TABLE_SIZE
    local default_table_size = self.connection.default_settings.HEADER_TABLE_SIZE
    self.connection.hpack_context = hpack.new(server_table_size or default_table_size)
    self:encode_settings(true)
  elseif ftype == 0x5 then
    -- PUSH_PROMISE
  elseif ftype == 0x6 then
    -- PING
  elseif ftype == 0x7 then
    -- GOAWAY
    local last_stream_id_client = string.unpack(">I4I4", payload)
    self.connection.last_stream_id_client = last_stream_id_client
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
    local end_headers = (flags & 0x4) ~= 0
    table.insert(self.connection.header_block_fragment, payload)
    if end_headers then
      payload = table.concat(self.connection.header_block_fragment)
      local header_list = hpack.decode(self.connection.hpack_context, payload)
      table.insert(self.headers, header_list)
    end
  end
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

function mt.__index:encode_headers(payload, end_stream, end_headers, padded)
  local conn = self.connection
  local flags = 0x0
  local pad_length = ""
  local padding = ""
  if end_stream then
    flags = flags | 0x1
  end
  if end_headers then
    flags = flags | 0x4
  end
  if padded then
    flags = flags | 0x8
    pad_length = string.pack(">B", padded)
    padding = ("\0"):rep(padded)
  end
  payload = pad_length .. payload .. padding
  conn:send_frame(0x1, flags, self.id, payload)
end

function mt.__index:encode_rst_stream(error_code)
  local conn = self.connection
  local payload= string.pack(">I4", error_code)
  conn:send_frame(0x3, 0x0, self.id, payload)
  self:encode_window_update(#self.data)
end

function mt.__index:encode_settings(ack, settings)
  local conn = self.connection
  local flags, payload
  local t = {}
  local i = 0
  if ack then
    flags = 0x1
    payload = ""
    conn:send_frame(0x4, flags, 0, payload)
  else
    flags = 0x0
    for k, v in ipairs(conn.default_settings) do
      t[i * 2 + 1] = k
      t[i * 2 + 2] = v
      i = i + 1
    end
    payload = string.pack(">" .. ("I2I4"):rep(i), table.unpack(t, 1, i * 2))
    conn:send_frame(0x4, flags, self.id, payload)
  end
end

function mt.__index:encode_goaway(last_stream_id, error_code, debug_data)
  local conn = self.connection
  local payload = string.pack(">I4I4", last_stream_id, error_code)
  if debug_data then payload = payload .. debug_data end
  conn:send_frame(0x7, 0x0, 0, payload)
end

function mt.__index:encode_window_update(size)
  local conn = self.connection
  conn:send_frame(0x8, 0x0, self.id, string.pack(">I4", size))
end

function mt.__index:encode_continuation(payload, end_stream)
  local conn = self.connection
  local flags = 0x0
  if end_stream then flags = flags | 0x4 end
  conn:send_frame(0x9, flags, self.id, payload)
end

function mt.__index:set_headers(headers, end_stream)
  local conn = self.connection
  local header_block = hpack.encode(conn.hpack_context, headers)
  local max_fsize = conn.server_settings.MAX_FRAME_SIZE
  local payload
  if #header_block <= max_fsize then
    self:encode_headers(header_block, end_stream, true)
  else
    payload = header_block:sub(1, max_fsize)
    self:encode_headers(payload, end_stream, false)
    local remain = #header_block - max_fsize
    local fsize = max_fsize
    while fsize < remain do
      payload = header_block:sub(fsize + 1, fsize + max_fsize)
      fsize = fsize + max_fsize
      self:encode_continuation(payload, false)
    end
    payload = header_block:sub(fsize + 1)
    self:encode_continuation(payload, true)
  end
end

function mt.__index:set_body(body)
  local conn = self.connection
  if body then
    local max_fsize = conn.server_settings.MAX_FRAME_SIZE
    for i = 0, #body, max_fsize do
      if i + max_fsize >= #body then
        self:encode_data(string.sub(body, i + 1), true)
      else
        self:encode_data(string.sub(body, i + 1, i + max_fsize), false)
      end
    end
  end
end

local stream = {
  new = new
}

return stream
