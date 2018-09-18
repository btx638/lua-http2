local http2_stream = require "http2.stream"
local hpack = require "http2.hpack"
local copas = require "copas"
local socket = require "socket"
local socket_url = require "socket.url"

copas.autoclose = false

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
  MAX_CONCURRENT_STREAMS = 100,
  INITIAL_WINDOW_SIZE    = 65535,
  MAX_FRAME_SIZE         = 16384,
  MAX_HEADER_LIST_SIZE   = 25600
}

local tls = {
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

local mt = {__index = {}}

function mt.__index:send_frame(ftype, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  self.client:send(header)
  self.client:send(payload)
end

local function getframe(conn)
  local header, payload, err
  local length, ftype, flags, stream_id
  header, err = conn.client:receive(9)
  if err then return nil, err end
  length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
  payload, err = conn.client:receive(length)
  if err then return nil, err end
  stream_id = stream_id & 0x7fffffff
  return {
    ftype = ftype,
    flags = flags,
    stream_id = stream_id,
    payload = payload
  }
end

local function receiver(conn)
  local frame, err, stream, s0
  while true do
    frame, err = getframe(conn)
    print(frame.ftype, frame.flags, frame.stream_id)
    stream = conn.streams[frame.stream_id]
    if stream == nil then 
      conn.last_stream_id_server = frame.stream_id
      stream = http2_stream.new(conn, frame.stream_id)
    end
    stream:parse_frame(frame.ftype, frame.flags, frame.payload)
    -- error: if it's not a server preface
    -- todo: necessary?
    if conn.recv_server_preface == false then
      conn.recv_server_preface = true
      copas.wakeup(conn.callback_connect)
      copas.sleep(-1)
    elseif stream.state == "open" then
      copas.wakeup(conn.responses[stream.id])
    elseif stream.state == "half-closed (remote)" or stream.state == "closed" then
      copas.wakeup(conn.data[stream.id])
      conn.requests = conn.requests - 1
      stream:encode_rst_stream(0x0)
      if conn.requests == 0 then 
        s0 = conn.streams[0]
        s0:encode_goaway(conn.last_stream_id_server, 0x0)
        --copas.sleep(-1)
      end
    end
  end
end

local function init(conn)
  conn.client = copas.wrap(socket.tcp(), conn.url.scheme == "https" and tls)
  conn.client:connect(conn.url.host, conn.url.port or 443)
  conn.client:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
  -- we are permitted to do that (3.5)
  local stream = http2_stream.new(conn, 0)
  stream:encode_settings(false)
  stream:encode_window_update("1073741823")
end

local function on_connect(url, callback)
  local parsed_url = type(url) == "string" and socket_url.parse(url)
  -- todo: url as a table of options
  -- error: if url is neither a string nor a table

  copas.addthread(function()
    copas.sleep()

    local connection = setmetatable({
      responses = {},
      data = {},
      client = nil,
      url = parsed_url,
      recv_server_preface = false,
      stream_finished = nil,
      max_client_streamid = 3,
      max_server_streamid = 2,
      hpack_context = nil,
      server_settings = {},
      streams = {},
      requests = 0,
      settings_parameters = settings_parameters,
      default_settings = default_settings,
      window = 65535,
      last_stream_id_server = 0,
      header_block_fragment = nil
    }, mt)

    init(connection)

    connection.callback_connect = copas.addthread(function()
      copas.sleep(-1)
      copas.addthread(callback)
      copas.wakeup(connection.receiver)
    end)

    connection.receiver = copas.addthread(function()
      receiver(connection)
    end)
  end)

  copas.loop()
end

local rmt = {__index = {}}

function rmt.__index:on_response(callback)
  self.conn.responses[self.stream.id] = copas.addthread(function()
    copas.sleep(-1)
    copas.addthread(callback, table.remove(self.stream.headers, 1))
  end)
end

function rmt.__index:on_data(callback)
  self.conn.data[self.stream.id] = copas.addthread(function()
    copas.sleep(-1)
    copas.addthread(callback, table.concat(self.stream.data))
  end)
end

local function request(headers, body)
  local stream = http2_stream.new(conn)
  conn.requests = conn.requests + 1

  if headers == nil then
    headers = {}
    table.insert(headers, {[":method"] = "GET"})
    table.insert(headers, {[":path"] = conn.url.path or '/'})
    table.insert(headers, {[":scheme"] = conn.url.scheme})
    table.insert(headers, {[":authority"] = conn.url.authority})
  end

  stream:set_headers(headers, body == nil)
  stream:encode_window_update("1073741823")

  return setmetatable({
    on_response = on_response,
  }, rmt)
end

local http2 = {
  on_connect = on_connect,
  request = request
}

return http2
