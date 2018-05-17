local http2 = require "http2"
local request_body = "<html><head><title>ko</title></head><body><h1>KO</h1><hr><address>nghttpd nghttp2/1.30.0 at port 8080</address></body></html>"
http2.request("localhost")
