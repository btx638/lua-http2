local socket = require "socket"
local copas = require "copas"
local hpack = require "http2.hpack"

local function dispatch(conn)
  while true do
    local req = table.remove(conn.pending, 1)
    if not req then
      copas.sleep(-1)
    else
      print(req.ftype, req.flags, req.stream_id)
    end
  end
end

local function sendframe(conn, ftype, flags, stream_id, payload)
  local header = string.pack(">I3BBI4", #payload, ftype, flags, stream_id)
  conn.tcp:send(header)
  conn.tcp:send(payload)
end

local function getframe(conn)
  local header, err = copas.receive(conn.tcp, 9)
  if err then return nil, err end
  local length, ftype, flags, stream_id = string.unpack(">I3BBI4", header)
  local payload, err = copas.receive(conn.tcp, length)
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
  while true do
    local frame, err = getframe(conn)
    table.insert(conn.pending, frame)
    copas.wakeup(conn.dispatch)
    copas.sleep(0.00001)
  end
end

local function setheaders(conn)
  local headers = {}
  table.insert(headers, {[":method"] = "GET"})
  table.insert(headers, {[":path"] = "/"})
  table.insert(headers, {[":scheme"] = "http"})
  table.insert(headers, {[":authority"] = "localhost:8080"})
  local context = hpack.new(4096)
  local header_block = hpack.encode(context, headers)
  sendframe(conn, 0x1, 0x4 | 0x1, 3, header_block)
end

local function connect()
  local tcp = socket.tcp()

  tcp:connect("localhost", 8080)
  tcp:settimeout(0)
  tcp:send("PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n")

  local conn = {
    tcp = tcp,
    pending = {}
  }

  sendframe(conn, 0x4, 0x0, 0, "")
  sendframe(conn, 0x4, 0x1, 0, "")
  setheaders(conn)

  copas.addthread(function()
    copas.sleep(0.00001)

    conn.dispatch = copas.addthread(function()
      copas.sleep(0.00001)
      dispatch(conn)
    end)

    copas.addthread(function()
      copas.sleep(0.00001)
      receiver(conn)
    end)
  end)
  copas.loop()
end

connect()
