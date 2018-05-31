local socket = require "socket"
local copas = require "copas"

local tcp = socket.tcp()
tcp:connect("localhost", 8080)
tcp:settimeout(0)
tcp:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")

local length, ftype, flags, stream_id, payload

local function send_frame(skt, ftype, flags, stream_id, payload)
  copas.sleep(0)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  copas.send(skt, header)
  copas.send(skt, payload)
end

local function recv_frame(skt)
  copas.sleep(0)
  local header = copas.receive(skt, 9)
  length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
  payload = copas.receive(skt, length)
  stream_id = stream_id & 0x7fffffff
  print(length, ftype, flags, stream_id, payload)
end

copas.addthread(send_frame, tcp, 0x4, 0, 0, "")
copas.addthread(recv_frame, tcp)
copas.loop()
