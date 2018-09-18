local http2 = require "http2"

-- todo: what if this is after on_connect?
--http2.on_error(function(err)
--  print(err)
--end)

http2.on_connect("http://localhost:8080/", function()
  local req = http2.request()

  req:on_response(function(response)
    local fd = io.open("http2_out1.html", "w")

    for k, v in ipairs(response.headers) do
      for name, value in pairs(v) do
        print(name, value)
      end
    end
      
    response:on_data(function(body)
      fd:flush()
      fd:write(body)
      fd:flush()
    end)
  end)
end)
