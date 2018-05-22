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

  --print("# REQUEST\n\n## HEADERS")
  --for _, header_field in ipairs(headers) do
  --  for name, value in pairs(header_field) do
  --    print(name, value)
  --  end
  --end

  -- Request header list
  local header_block = hpack.encode(connection.hpack_context, headers)

  --print("\n## BODY")
  if request_body then
    -- TODO: correctness: may require padding to fit in a frame
    connection.send_frame(0x1, 0x4, s.id, header_block)
    local fsize = connection.server_settings.MAX_FRAME_SIZE
    for i = 1, #request_body, fsize do
      if i + fsize >= #request_body then
        connection.send_frame(0x0, 0x1, s.id, string.sub(request_body, i))
      else
        connection.send_frame(0x0, 0x0, s.id, string.sub(request_body, i, i + fsize - 1))
      end
    end
  else
    connection.send_frame(0x1, 0x4 | 0x1, s.id, header_block)
  end

  -- Receives a WINDOW_UPDATE frame
  local ftype, flags, stream_id, window_payload = connection.recv_frame()
  local parser = stream.frame_parser[ftype]
  parser(s, flags, window_payload)
  -- Server acknowledged our settings
  connection.recv_frame()
  -- Response header list
  local ftype, flags, stream_id, headers_payload = connection.recv_frame()
  s = connection.streams[stream_id]
  local parser = stream.frame_parser[ftype]
  local header_list = parser(s, flags, headers_payload)

  --print("\n\n# RESPONSE\n\n## HEADERS")
  --for _, header_field in ipairs(header_list) do
  --  for name, value in pairs(header_field) do
  --    print(name, value)
  --  end
  --end

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
  -- TODO: parse the URI
  local connection = new_connection.new(uri)
  connection.server_settings = get_server_settings(connection)
  -- Sends an WINDOW_UPDATE frame on the connection level
  connection.send_frame(0x8, 0x0, 0, string.pack(">I4", "1073741823"))
  local request_headers
  if not body then
    request_headers = {[1] = {[":method"] = "GET"},
                       [2] = {[":path"] = "/"},
                       [3] = {[":scheme"] = "http"},
                       [4] = {[":authority"] = "localhost:8080"},
                      }
  else
    request_headers = {[1] = {[":method"] = "POST"},
                       [2] = {[":path"] = "/"},
                       [3] = {[":scheme"] = "http"},
                       [4] = {[":authority"] = "localhost:8080"},
                      }
  end
  -- Performs the request
  local response_headers, s = submit_request(connection, request_headers, body)
  -- Sends an WINDOW_UPDATE frame on the stream level
  connection.send_frame(0x8, 0x0, s.id, string.pack(">I4", "1073741823"))
  -- DATA frame containing the message payload
  local payload = stream.get_message_data(s)
  io.write(payload)
end

local http2 = {
  request = request
}

return http2
