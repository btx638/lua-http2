local frame_parser = {}

local function frame_parser.ftypes.DATA
end

local function frame_parser.ftypes.HEADERS

-- DATA frame parser
local function parse_frame[0x0]
end

-- HEADER frame parser
local function parse_frame[0x1]
end

-- PRIORITY frame parser
local function parse_frame[0x2]
end

-- RST_STREAM frame parser
local function parse_frame[0x3]
end

-- SETTING frame parser
local function parse_frame[0x4]
end

-- PUSH_PROMISE frame parser
local function parse_frame[0x5]
end

-- PING frame parser
local function parse_frame[0x6]
end

-- GOAWAY frame parser
local function parse_frame[0x7]
end

-- WINDOW_UPDATE frame parser
local function parse_frame[0x8]
end

-- CONTINUATION frame parser
local function parse_frame[0x9]
end

local stream = {
}

return stream
