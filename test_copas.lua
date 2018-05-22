local socket = require "socket"
local copas = require "copas"
local tcp

local mt = {__index = {}}

local function open(uri)
  local h = setmetatable({tcp = tcp}, mt)
  tcp:connect(uri, 80)
  return h
end

function mt.__index:close()
  return self.tcp:close()
end

function mt.__index:send_preface()
  return self.tcp:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")
end

function mt.__index:send_settings_header(ftype, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  return self.tcp:send(header)
end

function mt.__index:send_settings_payload(payload)
  return self.tcp:send(payload)
end

function mt.__index:recv_server_settings()
  local header = self.tcp:receive(9)
  local length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
  local payload = self.tcp:receive(length)
  stream_id = stream_id & 0x7fffffff
  return ftype, flags, stream_id, payload
end

local function go(uri)
  local h = open(uri)
  h:send_preface()
  h:send_settings_header(0x4, 0, 0, "")
  h:send_settings_payload("")
  local ftype, flags, stream_id, payload = h:recv_server_settings()
  print(ftype, flags, stream_id, payload)
end

local request = socket.protect(function(uri)
  tcp = socket.try(copas.wrap(socket.tcp()))
  go(uri)
end)

local function handler(host)
  request(host)
  print("Host done: " .. host)
end

copas.addthread(handler, "www.google.com")
copas.loop()
