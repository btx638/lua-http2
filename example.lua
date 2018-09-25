local http2 = require "http2"

local headers2 = {}
table.insert(headers2, {[":method"] = "GET"})
table.insert(headers2, {[":path"] = "/index2.html"})
table.insert(headers2, {[":scheme"] = "http"})
table.insert(headers2, {[":authority"] = "localhost:8080"})
table.insert(headers2, {["user-agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36"})

local headers3 = {}
table.insert(headers3, {[":method"] = "GET"})
table.insert(headers3, {[":path"] = "/index3.html"})
table.insert(headers3, {[":scheme"] = "http"})
table.insert(headers3, {[":authority"] = "localhost:8080"})
table.insert(headers3, {["user-agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/69.0.3497.100 Safari/537.36"})

--local client = http2.connect("www.facebook.com/")
local client = http2.connect("http://localhost:8080/")

client.on_connect(function(session)
  local req = session.request()
  local req2 = session.request(headers2)
  local req3 = session.request(headers3)

  req.on_response(function(res)
    local fd = io.open("http2_out1.html", "w")

    for k, v in ipairs(res.headers) do
      for name, value in pairs(v) do
        print(name, value)
      end
    end
      
    res.on_data(function(body)
      fd:flush()
      fd:write(body)
      fd:flush()
    end)
  end)

  req2.on_response(function(res)
    local fd = io.open("http2_out2.html", "w")

    for k, v in ipairs(res.headers) do
      for name, value in pairs(v) do
        print(name, value)
      end
    end
      
    res.on_data(function(body)
      fd:flush()
      fd:write(body)
      fd:flush()
    end)
  end)

  req3.on_response(function(res)
    local fd = io.open("http2_out3.html", "w")

    for k, v in ipairs(res.headers) do
      for name, value in pairs(v) do
        print(name, value)
      end
    end
      
    res.on_data(function(body)
      fd:flush()
      fd:write(body)
      fd:flush()
    end)
  end)
end)
