local connection = require "connection"
local copas = require "copas"
local socket = require "socket"
local socket_url = require "socket.url"

copas.autoclose = false

local conn = connection.new()

local callbacks = {
  on_response = {},
  on_data = {},
  on_close = {}
}

local function dispatcher()
  local stream
  while true do
    stream = conn:parse_stream()
    if stream.state == "open" then
      local on_response = callbacks.on_response[stream.id]
      if on_response then
        copas.wakeup(on_response)
      end
    end
    if stream.state == "closed" then
      local on_data = callbacks.on_data[stream.id]
      if on_data then
        copas.wakeup(on_data)
      end
      break
    end
  end
end

local function request(headers, body)
  local s = conn:new_stream()

  local on_response = function(callback)
    callbacks.on_response[s.id] = copas.addthread(function()
      copas.sleep(-1)
      local headers = table.remove(s.frames.headers, 1)
      callback(headers)
    end)
  end

  local on_data = function(callback)
    callbacks.on_data[s.id] = copas.addthread(function()
      copas.sleep(-1)
      local data = s.frames.data
      callback(data)
    end)
  end

  if headers == nil then
    headers = {}
    table.insert(headers, {[":method"] = "GET"})
    table.insert(headers, {[":path"] = conn.url.path or '/'})
    table.insert(headers, {[":scheme"] = conn.url.scheme})
    table.insert(headers, {[":authority"] = conn.url.authority})
  end

  s:headers({headers = headers, end_stream = body == nil})

  return {on_data = on_data, on_response = on_response}
end

local function on_connect(gurl, callback)
  callbacks.dispatcher = copas.addthread(function()
    copas.sleep()

    conn.url = socket_url.parse(gurl)
    conn.skt = copas.wrap(socket.tcp())
    conn.skt:connect(conn.url.host, conn.url.port)
    conn.skt:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
    conn:settings({settings = conn.default_settings, ack = false})
    conn:parse_stream() -- error: not a server preface
    callback({request = request})
    dispatcher()
  end)

  copas.loop()
end

local http2 = {
  on_connect = on_connect
}

return http2