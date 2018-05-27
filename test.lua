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
    conn.send_frame(conn, 0x8, 0x0, 0, string.pack(">I4", "1073741823"))
  end
  copas.sleep(1)

  local s = stream.new(conn)
  s.id = conn.max_stream_id + 2
  conn.max_stream_id = s.id
  conn.streams[s.id] = s
  local header_block = hpack.encode(conn.hpack_context, headers)
  -- Sends a request header list
  conn.send_frame(conn, 0x1, 0x4 | 0x1, s.id, header_block)
  local header_list = stream.get_headers(s)
  -- Sends an WINDOW_UPDATE frame on the stream level
  conn.send_frame(conn, 0x8, 0x0, s.id, string.pack(">I4", "1073741823"))
  -- Receives DATA frames containing the message payload
  --local payload = stream.get_message_data(s)
  --io.write(payload)
end

local headers ={{[1] = {[":method"] = "GET"},
                 [2] = {[":path"] = "/"},
                 [3] = {[":scheme"] = "http"},
                 [4] = {[":authority"] = "localhost:8080"},
                },
                {[1] = {[":method"] = "GET"},
                 [2] = {[":path"] = "/image.jpg"},
                 [3] = {[":scheme"] = "http"},
                 [4] = {[":authority"] = "localhost:8080"},
                },
                {[1] = {[":method"] = "GET"},
                 [2] = {[":path"] = "/index2.html"},
                 [3] = {[":scheme"] = "http"},
                 [4] = {[":authority"] = "localhost:8080"},
               }}

for _, header in ipairs(headers) do copas.addthread(protocol, header) end
copas.loop()
