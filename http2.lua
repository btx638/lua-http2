local new_connection = require "connection"
local stream = require "stream"
local hpack = require "hpack"

-- Send a HEADERS frame with the requested header list
-- Returns the newly created stream and the response header list
local function submit_request(connection, headers, request_body)
  local s = stream.new(connection)
  s.id = connection.max_stream_id + 2
  connection.max_stream_id = s.id
  connection.streams[s.id] = s

  print("# REQUEST\n\n## HEADERS")
  for _, header_field in ipairs(headers) do
    for name, value in pairs(header_field) do
      print(name, value)
    end
  end

  -- Request header list
  local header_block = hpack.encode(connection.hpack_context, headers)
  print("\n## BODY")
  if request_body then
    connection.send_frame(0x0, 0x1, s.id, request_body)
    print(request_body)
  end
  -- Server acknowledged our settings
  connection.recv_frame()
  ---- Response header list
  local ftype, flags, stream_id, headers_payload = connection.recv_frame()
  s = connection.streams[stream_id]
  local parser = stream.frame_parser[0x1]
  local header_list = parser(s, flags, headers_payload)
  print("\n\n# RESPONSE\n\n## HEADERS")
  for _, header_field in ipairs(header_list) do
    for name, value in pairs(header_field) do
      print(name, value)
    end
  end
  return header_list, s
end

local function get_server_settings(connection)
  local server_settings = {}
  local s = connection.streams[0]
  local _, flags, _, settings_payload = connection.recv_frame()
  local parser = stream.frame_parser[0x4]
  local server_settings = parser(s, flags, settings_payload)
  -- Acknowledging the server settings
  connection.send_frame(0x4, 0x1, 0, "")
  return server_settings
end

local function request(uri, body)
  local connection = new_connection.new(uri)
  connection.server_settings = get_server_settings(connection)
  local request_headers
  if not body then
    request_headers = {[1] = {[":method"] = "GET"},
                       [2] = {[":path"] = "/"},
                       [3] = {[":scheme"] = "http"},
                       [4] = {[":authority"] = "localhost:8080"},
                      }
  else
    request_headers = {[1] = {[":method"] = "POST"},
                       [2] = {[":path"] = "/resource"},
                       [3] = {[":scheme"] = "http"},
                       [4] = {[":authority"] = "localhost:8080"},
                      }
  end
  -- Performs the request
  local response_headers, s = submit_request(connection, request_headers, body)
  -- DATA frame containing the message payload
  local _, flags, stream_id, data_payload = connection.recv_frame()
  local end_stream = (flags & 0x1) ~= 0
  local padded = (flags & 0x8) ~= 0
  print(data_payload)
end

local http2 = {
  request = request
}

return http2
