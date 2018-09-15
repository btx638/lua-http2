local stream = require "http2.stream"
local hpack = require "http2.hpack"
local copas = require "copas"
local socket = require "socket"
local url = require "socket.url"

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
  local frame, err, s, s0
  while true do
    frame, err = getframe(conn)
    print(frame.ftype, frame.flags, frame.stream_id)
    s = conn.streams[frame.stream_id]
    if s == nil then 
      conn.last_stream_id_server = frame.stream_id
      s = stream.new(conn, frame.stream_id)
    end
    s:parse_frame(frame.ftype, frame.flags, frame.payload)
    -- error: if it's not a server preface
    if conn.recv_server_preface == false then
      conn.recv_server_preface = true
      copas.wakeup(conn.callback_connect)
      copas.sleep(-1)
    elseif s.state == "closed" then
      copas.wakeup(conn.callbacks[s.id])
      conn.requests = conn.requests - 1
      if conn.requests == 0 then copas.sleep(-1) end
    end
  end
end

local function init(conn)
  conn.client = copas.wrap(socket.tcp(), conn.surl.scheme == "https" and tls)
  conn.client:connect(conn.surl.host, conn.surl.port or 443)
  conn.client:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
  -- we are permitted to do that (3.5)
  local s = stream.new(conn, 0)
  s:encode_settings(false)
  s:encode_window_update("1073741823")
end

local function connect(surl, callback)
  local parsed_url = url.parse(surl)
  local connection

  copas.addthread(function()
    copas.sleep(0)

    connection = setmetatable({
      client = nil,
      uri = parsed_uri,
      recv_first_frame = false,
      stream_finished = nil,
      max_client_streamid = 3,
      max_server_streamid = 2,
      hpack_context = nil,
      server_settings = {},
      streams = setmetatable({}, {__mode = "v"}),
      callbacks = {},
      requests = 0,
      settings_parameters = settings_parameters,
      default_settings = default_settings,
      window = 65535,
      last_stream_id = 0,
      header_block_fragment = nil
    }, mt)

    init(connection)

    connection.callback_conn = copas.addthread(function()
      copas.sleep(-1)
      print("callback_conn woke up")
      copas.addthread(callback, connection)
      print("callback_conn finished")
      copas.wakeup(connection.receiver)
      print("waking up receiver")
    end)

    connection.receiver = copas.addthread(function()
      receiver(connection)
    end)
  end)
end

local function request(conn, callback, headers, body)
  local h, b
  local s = stream.new(conn)
  conn.requests = conn.requests + 1

  conn.callbacks[s.id] = copas.addthread(function()
    copas.sleep(0)
    print("s.id: " .. s.id)

    if headers == nil then
      headers = {}
      table.insert(headers, {[":method"] = "GET"})
      table.insert(headers, {[":path"] = conn.uri.path or '/'})
      table.insert(headers, {[":scheme"] = conn.uri.scheme})
      table.insert(headers, {[":authority"] = conn.uri.authority})
    end

    s:set_headers(headers, body == nil)
    s:encode_window_update("1073741823")
    print("all set")
    h = s:get_headers()
    b = s:get_body()

    copas.addthread(callback, h, b)
  end)
end

local http2 = {
  connect = connect,
  request = request
}

return http2
