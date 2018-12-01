local http2 = require "http2"

local url = "https://www.google.com.br/"

http2.on_connect(url, function(session)
  local req = session.request()

  req.on_response(function(headers)
    for _, field in ipairs(headers) do
      for name, value in pairs(field) do
        print(name, value)
      end
    end
  end)

  req.on_data(function(data)
    print(data)
  end)
end)