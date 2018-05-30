local connection = require "connection"
local stream = require "stream"
local hpack = require "hpack"
local socket = require "socket"
local copas = require "copas"

local ok = true
local conn

local function protocol(headers)
  if ok then
    ok = false
    local tcp = copas.wrap(socket.tcp())
    tcp:connect("localhost", 8080)
    conn = connection.new(tcp)
    -- Sends an WINDOW_UPDATE frame on the connection level
    stream.send_window_update(conn.streams[0], "1073741823")
  end
  copas.sleep(1)
  local s = stream.new(conn)
  s.id = conn.max_stream_id + 2
  conn.max_stream_id = s.id
  conn.streams[s.id] = s
  stream.send_headers(s, headers)
  -- Sends an WINDOW_UPDATE frame on the stream level
  stream.send_window_update(s, "1073741823")
  local header_list = stream.get_headers(s)
  -- Receives DATA frames containing the message payload
  stream.get_message_data(s)
end

local headers = {{[1] = {[":method"] = "GET"},
                  [2] = {[":path"] = "/"},
                  [3] = {[":scheme"] = "http"},
                  [4] = {[":authority"] = "localhost:8080"},
                 },
                 {[1] = {[":method"] = "GET"},
                  [2] = {[":path"] = "/index2.html"},
                  [3] = {[":scheme"] = "http"},
                  [4] = {[":authority"] = "localhost:8080"},
                 },
                 {[1] = {[":method"] = "GET"},
                  [2] = {[":path"] = "/index3.html"},
                  [3] = {[":scheme"] = "http"},
                  [4] = {[":authority"] = "localhost:8080"},
                }}

for _, header in ipairs(headers) do copas.addthread(protocol, header) end
copas.loop()

res = {}
fd = io.open("1", "w+")
while #conn.streams[3].data > 0 do
  table.insert(res, table.remove(conn.streams[3].data, 1))
end
fd:write(table.concat(res))

res = {}
fd = io.open("2", "w+")
while #conn.streams[5].data > 0 do
  table.insert(res, table.remove(conn.streams[5].data, 1))
end
fd:write(table.concat(res))

res = {}
fd = io.open("3", "w+")
while #conn.streams[7].data > 0 do
  table.insert(res, table.remove(conn.streams[7].data, 1))
end
fd:write(table.concat(res))
