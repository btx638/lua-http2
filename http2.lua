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

local function dispatch(conn, frame)
  local s, s0
  s = conn.streams[frame.stream_id]
  if s == nil then s = stream.new(conn, frame.stream_id) end
  s:parse_frame(frame.ftype, frame.flags, frame.payload)
  if conn.recv_first_frame == false then
    s:encode_settings(false)
    s0 = conn.streams[0]
    if s0 == nil then s0 = stream.new(conn, 0) end
    s0:encode_window_update("1073741823")
    conn.recv_first_frame = true
    copas.wakeup(conn.callback_conn)
  end
  if s.state == "closed" then
    conn.stream_finished = true
  end
end

local function receiver(conn)
  local frame, err, s
  while true do
    if conn.stream_finished == true then
      conn.stream_finished = false
      copas.wakeup(conn.callback)
      copas.sleep(-1)
    end
    frame, err = getframe(conn)
    print(frame.ftype, frame.flags, frame.stream_id)
    dispatch(conn, frame)
  end
end

local function connect(uri, callback)
  local parsed_uri = url.parse(uri)
  local connection

  copas.addthread(function()
    copas.sleep(0)

    connection = setmetatable({
      client = nil,
      uri = parsed_uri,
      recv_first_frame = false,
      stream_finished = false,
      max_client_streamid = 3,
      max_server_streamid = 0,
      hpack_context = nil,
      server_settings = {},
      streams = {},
      settings_parameters = settings_parameters,
      default_settings = default_settings,
      window = 65535,
      last_stream_id = 0,
      header_block_fragment = nil
    }, mt)
    connection.client = copas.wrap(socket.tcp())
    connection.client:connect(parsed_uri.host, parsed_uri.port)
    connection.client:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")

    connection.callback_conn = copas.addthread(function()
      copas.sleep(-1)
      connection.callback = copas.addthread(callback, connection)
    end)

    connection.receiver = copas.addthread(function()
      receiver(connection)
    end)
  end)
end

local function request(conn, callback, headers, body)
  copas.addthread(function()
    local s0, s, h, b

    if headers == nil then
      headers = {}
      table.insert(headers, {[":method"] = "GET"})
      table.insert(headers, {[":path"] = conn.uri.path})
      table.insert(headers, {[":scheme"] = conn.uri.scheme})
      table.insert(headers, {[":authority"] = conn.uri.authority})
    end

    s = stream.new(conn)
    s:set_headers(headers, body == nil)
    s:encode_window_update("1073741823")
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
