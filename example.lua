local http2 = require "http2"

--local client = http2.connect("https://www.facebook.com/")
local client = http2.connect("http://localhost:8080/")

-- todo: what if this is after the last callback?
client:on_error(function(err)
  print(err)
end)

client:on_connect(function()
  local req = client:request()
  
  req:on_response(function(res)
    local fd = io.open("http2_out1.html", "w")

    for k, v in ipairs(res.headers) do
      for name, value in pairs(v) do
        print(name, value)
      end
    end
      
    res:on_data(function(body)
      fd:flush()
      fd:write(body)
      fd:flush()
    end)
  end)
end)
