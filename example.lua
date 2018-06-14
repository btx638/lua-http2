local http2 = require "http2"
local copas = require "copas"

function callback_req3(headers, body)
  fd = io.open("http2_out3", "w")
  for k, v in ipairs(headers) do
    for name, value in pairs(v) do
      print(name, value)
    end
  end
  fd:write(body)
end

function callback_req2(headers, body)
  fd = io.open("http2_out2", "w")
  for k, v in ipairs(headers) do
    for name, value in pairs(v) do
      print(name, value)
    end
  end
  fd:write(body)
end

function callback_req(headers, body)
  fd = io.open("http2_out1", "w")
  for k, v in ipairs(headers) do
    for name, value in pairs(v) do
      print(name, value)
    end
  end
  fd:write(body)
end

function callback_conn(conn)
  http2.request(conn, callback_req)

  h1 = {}
  table.insert(h1, {[":method"] = "GET"})
  table.insert(h1, {[":path"] = "/index2.html"})
  table.insert(h1, {[":scheme"] = "http"})
  table.insert(h1, {[":authority"] = "localhost:8080"})
  http2.request(conn, callback_req2, h1)

  h2 = {}
  table.insert(h2, {[":method"] = "GET"})
  table.insert(h2, {[":path"] = "/index3.html"})
  table.insert(h2, {[":scheme"] = "http"})
  table.insert(h2, {[":authority"] = "localhost:8080"})
  http2.request(conn, callback_req3, h2)
end

http2.connect("http://localhost:8080/", callback_conn)

copas.loop()
