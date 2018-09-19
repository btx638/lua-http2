local http2_stream = require "http2.stream"
local http2_connection = require "http2.connection"
local copas = require "copas"
local socket = require "socket"
local socket_url = require "socket.url"

copas.autoclose = false

local cmt = {__index = {}}
local reqmt = {__index = {}}
local resmt = {__index = {}}
local connection, client

function resmt.__index:on_error(callback)
end

function resmt.__index:on_data(callback)
  local stream_id = connection.max_client_streamid
  connection.data[stream_id] = copas.addthread(function()
    copas.sleep(-1)
    local data = table.concat(connection.streams[stream_id].data)
    copas.addthread(callback, data)
  end)
end

function reqmt.__index:on_response(callback)
  local stream_id = connection.max_client_streamid
  connection.responses[stream_id] = copas.addthread(function()
    copas.sleep(-1)
    local headers = table.remove(connection.streams[stream_id].headers, 1)
    local response = setmetatable({headers = headers}, resmt)
    copas.addthread(callback, response)
  end)
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
      print("sleeping")
      copas.sleep(-1)
      print("waking up")
    elseif stream.state == "open" then
      copas.wakeup(conn.responses[stream.id])
    elseif stream.state == "half-closed (remote)" or stream.state == "closed" then
      copas.wakeup(conn.data[stream.id])
      conn.requests = conn.requests - 1
      stream:encode_rst_stream(0x0)
      if conn.requests == 0 then 
        s0 = conn.streams[0]
        s0:encode_goaway(conn.last_stream_id_server, 0x0)
        copas.sleep(-1)
      end
    end
  end
end

local function init(conn)
  local https = conn.url.scheme == "https" and conn.tls
  conn.client = copas.wrap(socket.tcp(), https)
  conn.client:connect(conn.url.host, conn.url.port or 443)
  conn.client:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
  -- we are permitted to do that (3.5)
  local stream = http2_stream.new(conn, 0)
  stream:encode_settings(false)
  stream:encode_window_update("1073741823")
end

function cmt.__index:request(headers, body)
  connection.max_client_streamid = connection.max_client_streamid + 2
  connection.requests = connection.requests + 1
  local stream = http2_stream.new(connection)
  
  if headers == nil then
    headers = {}
    table.insert(headers, {[":method"] = "GET"})
    table.insert(headers, {[":path"] = connection.url.path or '/'})
    table.insert(headers, {[":scheme"] = connection.url.scheme})
    table.insert(headers, {[":authority"] = connection.url.authority})
  end
  stream:set_headers(headers, body == nil)
  stream:encode_window_update("1073741823")
  return setmetatable({}, reqmt)
end

function cmt.__index:on_error(callback)
  connection.cerror = copas.addthread(function()
    copas.sleep(-1)
  end)
end

function cmt.__index:on_connect(callback)
  copas.addthread(function()
    copas.sleep()

    connection.callback_connect = copas.addthread(function()
      copas.sleep(-1)
      copas.addthread(callback, client)
      copas.wakeup(connection.receiver)
    end)

    connection.receiver = copas.addthread(function()
      receiver(connection)
    end)
  end)

  copas.loop()
end

local function connect(url)
  -- error: if url is neither a string nor a table
  local parsed_url = type(url) == "string" and socket_url.parse(url)
  connection = http2_connection.new(parsed_url)

  copas.addthread(function()
    copas.sleep()
    init(connection)
  end)

  client = setmetatable({}, cmt)
  return client
end

local http2 = {
  connect = connect,
}

return http2
