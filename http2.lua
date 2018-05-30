local connection = require "connection"
local stream = require "stream"
local hpack = require "hpack"
local socket = require "socket"
local copas = require "copas"

local semaphore = true
local conn

local function submit(host, port, body, request_headers)
  if semaphore then
    semaphore = false
    local client = copas.wrap(socket.tcp())
    client:connect(host, port)
    conn = connection.new(client)
    stream.send_window_update(conn.streams[0], "1073741823")
  end
  copas.sleep(1)
  local s = stream.new(conn)
  s.id = conn.max_stream_id + 2
  conn.max_stream_id = s.id
  conn.streams[s.id] = s
  stream.send_headers(s, request_headers, body)
  stream.send_window_update(s, "1073741823")
  local response_headers = stream.get_headers(s)
  local response_body = stream.get_body(s)
end

local function request(host, port, body, headers)
  if headers == nil then
    headers = {}
    fields = {}
    table.insert(fields, {[":method"] = "GET"})
    table.insert(fields, {[":path"] = "/"})
    table.insert(fields, {[":scheme"] = "http"})
    table.insert(fields, {[":authority"] = "localhost:8080"})
    table.insert(headers, fields)
  end
  for _, h in ipairs(headers) do copas.addthread(submit, host, port, body, h) end
  copas.loop()
end

local http2 = {
  request = request
}

return http2
