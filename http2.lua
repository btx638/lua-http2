local http2_stream = require "http2.stream"
local http2_connection = require "http2.connection"
local copas = require "copas"
local socket = require "socket"
local socket_url = require "socket.url"

copas.autoclose = false

local connection, client, url

local default_url = {
  method = "GET",
  scheme = "https",
  path = '/',
  port = 443
}

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

-- todo: remove 'conn'
local function receiver(conn)
  local frame, err, stream, s0
  while true do
    frame, err = getframe(conn)
    --print(frame.ftype, frame.flags, frame.stream_id)
    stream = conn.streams[frame.stream_id]
    if stream == nil then 
      conn.last_stream_id_server = frame.stream_id
      stream = http2_stream.new(conn, frame.stream_id)
    end
    stream:parse_frame(frame.ftype, frame.flags, frame.payload)
    -- todo: necessary?
    if conn.recv_server_preface == false then
      conn.recv_server_preface = true
      copas.wakeup(conn.callback_connect)
      copas.sleep(-1)
    elseif stream.state == "open" then
      copas.wakeup(conn.on_response[stream.id])
    elseif stream.state == "half-closed (remote)" or stream.state == "closed" then
      copas.wakeup(conn.on_data[stream.id])
      stream:encode_rst_stream(0x0)
    end
  end
end

local function on_error(callback)
end

local function request(headers, body)
  local stream = http2_stream.new(connection)

  local on_data = function(callback)
    connection.on_data[stream.id] = copas.addthread(function()
      copas.sleep(-1)
      local data = table.concat(stream.data)
      callback(data)
    end)
  end

  local on_response = function(callback)
    connection.on_response[stream.id] = copas.addthread(function()
      copas.sleep(-1)
      local headers = table.remove(stream.headers, 1)
      local res = {headers = headers, on_data = on_data}
      callback(res)
    end)
  end

  connection.request[#connection.request + 1] = copas.addthread(function()
    copas.sleep(-1)

    if headers == nil then
      headers = {}
      table.insert(headers, {[":method"] = url.method})
      table.insert(headers, {[":path"] = url.path})
      table.insert(headers, {[":scheme"] = url.scheme})
      table.insert(headers, {[":authority"] = url.authority})
      table.insert(headers, {["user-agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36"})
    end
    stream:set_headers(headers, body == nil)
    stream:encode_window_update("1073741823")
    local req = table.remove(connection.request, 1)
    if req then
      copas.wakeup(req)
    else
      copas.wakeup(connection.receiver)
    end
  end)

  return {
    on_response = on_response
  }
end

local function on_connect(callback)
  copas.addthread(function()
    copas.sleep()

    connection.callback_connect = copas.addthread(function()
      copas.sleep(-1)
      callback({request = request, on_error = on_error})
      local req = table.remove(connection.request, 1)
      copas.wakeup(req)
    end)

    connection.receiver = copas.addthread(function()
      receiver(connection)
    end)
  end)

  copas.loop()
end

local function connect(authority)
  url = socket_url.parse(authority)
  connection = http2_connection.new()

  copas.addthread(function()
    copas.sleep()

    local tls = url.scheme == "https" and connection.tls
    connection.client = copas.wrap(socket.tcp(), tls)
    connection.client:connect(url.host, url.port)
    connection.client:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    -- we are permitted to do that (3.5)
    local stream = http2_stream.new(connection, 0)
    stream:encode_settings(false)
    stream:encode_window_update("1073741823")
  end)

  return {
    on_connect = on_connect
  }
end

local http2 = {
  connect = connect,
}

return http2
