local ffi = require("ffi")

--- Plain Lua data to bytes and back: the encoding a saved game is written in.
---
--- What can be encoded: nil, booleans, numbers, strings, and tables of those
--- (keys: strings, numbers and booleans). Not functions, userdata, cdata or
--- a table that contains itself -- each is an error naming where it was, so a
--- snapshot that picks up something it should not fails loudly at save time
--- rather than writing a file that cannot be read.
---
--- The format, value by value, a tag byte first:
---
---   0 nil        1 false        2 true
---   3 integer    >= 0, as an unsigned LEB128 varint
---   4 integer    < 0, the varint of its magnitude
---   5 number     anything else (fractions, huge, inf, nan): 8 bytes, IEEE
---                double, little-endian
---   6 string     a varint length and the bytes -- and it joins the string
---                table under the next index
---   7 string     seen before: the varint of its index in the string table
---   8 table      a varint count and that many array values (1..n), then a
---                varint count and that many key, value pairs
---
--- Strings are interned because a game's state repeats them endlessly: item
--- names, station keys, faction names, field names of every record. Each is
--- written once and referred to by a small number after that. Integers are
--- varints because nearly all of them are small (ids, counts, units). The
--- pairs of a table are written in sorted key order, so the same state always
--- encodes to the same bytes.
---@class SaveCodec
local SaveCodec = {}

local TAG_NIL, TAG_FALSE, TAG_TRUE = 0, 1, 2
local TAG_UINT, TAG_NINT, TAG_F64 = 3, 4, 5
local TAG_STR, TAG_STRREF, TAG_TABLE = 6, 7, 8

--- The largest integer a double holds exactly: past it, a number is a double.
local MAX_EXACT = 2 ^ 53

local doubleBox = ffi.new("double[1]")
local byteView = ffi.cast("uint8_t*", doubleBox)

------------------------------------------------------------------------------
-- Writing
------------------------------------------------------------------------------

---@param out string[]
---@param n integer >= 0
local function writeVarint(out, n)
    -- Arithmetic rather than bit operations: LuaJIT's are 32 bit, and an
    -- integer here may be up to 2^53
    repeat
        local byte = n % 128
        n = (n - byte) / 128
        if n > 0 then byte = byte + 128 end
        out[#out + 1] = string.char(byte)
    until n == 0
end

---@param a any
---@param b any
---@return boolean
local function keyLess(a, b)
    local ta, tb = type(a), type(b)
    if ta ~= tb then return ta < tb end
    if ta == "boolean" then return (not a) and b end
    return a < b
end

---@param out string[]
---@param value any
---@param strings { index: table<string, integer>, count: integer } the string table so far
--- (the strings in a table of their own: a counter beside them would be
--- found by a string that spells its name, "count")
---@param seen table<table, boolean> tables being written (for cycles)
---@param path string where in the data this is, for errors
local function writeValue(out, value, strings, seen, path)
    local kind = type(value)
    if value == nil then
        out[#out + 1] = string.char(TAG_NIL)
    elseif kind == "boolean" then
        out[#out + 1] = string.char(value and TAG_TRUE or TAG_FALSE)
    elseif kind == "number" then
        -- (-0 goes as a double: as an integer it would come back +0)
        if value == math.floor(value) and value > -MAX_EXACT and value < MAX_EXACT
            and not (value == 0 and 1 / value < 0) then
            if value >= 0 then
                out[#out + 1] = string.char(TAG_UINT)
                writeVarint(out, value)
            else
                out[#out + 1] = string.char(TAG_NINT)
                writeVarint(out, -value)
            end
        else
            doubleBox[0] = value
            out[#out + 1] = string.char(TAG_F64) .. ffi.string(byteView, 8)
        end
    elseif kind == "string" then
        local index = strings.index[value]
        if index then
            out[#out + 1] = string.char(TAG_STRREF)
            writeVarint(out, index)
        else
            strings.count = strings.count + 1
            strings.index[value] = strings.count
            out[#out + 1] = string.char(TAG_STR)
            writeVarint(out, #value)
            out[#out + 1] = value
        end
    elseif kind == "table" then
        -- An object is not data: saved, it would come back a plain table
        -- without its methods
        -- (asked here directly: the codec runs in the tools too, without
        -- the game's class library)
        local mt = getmetatable(value)
        local cls = type(mt) == "table" and rawget(mt, "__type") or nil
        if cls then
            error(string.format("SaveCodec: %s is a %s object, which cannot be saved", path, tostring(cls)), 0)
        end
        if seen[value] then
            error(string.format("SaveCodec: %s contains itself", path), 0)
        end
        seen[value] = true
        -- The array part: 1..n without a gap
        local n = 0
        while value[n + 1] ~= nil do n = n + 1 end
        out[#out + 1] = string.char(TAG_TABLE)
        writeVarint(out, n)
        for i = 1, n do
            writeValue(out, value[i], strings, seen, path .. "[" .. i .. "]")
        end
        -- The rest, sorted, so the same data is the same bytes
        local keys = {}
        for key in pairs(value) do
            local isArray = type(key) == "number" and key >= 1 and key <= n and key == math.floor(key)
            if not isArray then
                local keyKind = type(key)
                if keyKind ~= "string" and keyKind ~= "number" and keyKind ~= "boolean" then
                    error(string.format("SaveCodec: %s has a key of type %s", path, keyKind), 0)
                end
                keys[#keys + 1] = key
            end
        end
        table.sort(keys, keyLess)
        writeVarint(out, #keys)
        for _, key in ipairs(keys) do
            writeValue(out, key, strings, seen, path)
            writeValue(out, value[key], strings, seen, path .. "." .. tostring(key))
        end
        seen[value] = nil
    else
        error(string.format("SaveCodec: %s is a %s, which cannot be saved", path, kind), 0)
    end
end

--- Encode a value.
---@param value any
---@return string bytes
function SaveCodec.encode(value)
    local out = {}
    writeValue(out, value, { index = {}, count = 0 }, {}, "save")
    return table.concat(out)
end

------------------------------------------------------------------------------
-- Reading
------------------------------------------------------------------------------

--- Decode what `encode` wrote. Any inconsistency -- a tag that does not
--- exist, a length past the end, bytes left over -- is an error, never a
--- half-read value.
---@param bytes string
---@return any value
function SaveCodec.decode(bytes)
    local pos = 1
    local size = #bytes
    local strings = {}

    local function fail(what)
        error(string.format("SaveCodec: %s at byte %d of %d", what, pos - 1, size), 0)
    end

    local function readByte()
        if pos > size then fail("ran out of data") end
        local b = bytes:byte(pos)
        pos = pos + 1
        return b
    end

    local function readVarint()
        local n, scale = 0, 1
        while true do
            local b = readByte()
            n = n + (b % 128) * scale
            if b < 128 then return n end
            scale = scale * 128
            if scale > MAX_EXACT then fail("a varint too long") end
        end
    end

    local readValue
    readValue = function(depth)
        if depth > 200 then fail("data nested too deep") end
        local tag = readByte()
        if tag == TAG_NIL then return nil end
        if tag == TAG_FALSE then return false end
        if tag == TAG_TRUE then return true end
        if tag == TAG_UINT then return readVarint() end
        if tag == TAG_NINT then return -readVarint() end
        if tag == TAG_F64 then
            if pos + 7 > size then fail("ran out of data in a number") end
            ffi.copy(byteView, bytes:sub(pos, pos + 7), 8)
            pos = pos + 8
            return doubleBox[0]
        end
        if tag == TAG_STR then
            local length = readVarint()
            if pos + length - 1 > size then fail("ran out of data in a string") end
            local value = bytes:sub(pos, pos + length - 1)
            pos = pos + length
            strings[#strings + 1] = value
            return value
        end
        if tag == TAG_STRREF then
            local index = readVarint()
            local value = strings[index]
            if value == nil then fail("a reference to string " .. index .. " before it was seen") end
            return value
        end
        if tag == TAG_TABLE then
            local result = {}
            local n = readVarint()
            for i = 1, n do result[i] = readValue(depth + 1) end
            local pairsCount = readVarint()
            for _ = 1, pairsCount do
                local key = readValue(depth + 1)
                if key == nil then fail("a nil key") end
                result[key] = readValue(depth + 1)
            end
            return result
        end
        fail("an unknown tag " .. tag)
    end

    local value = readValue(0)
    if pos <= size then fail(string.format("%d bytes left over", size - pos + 1)) end
    return value
end

return SaveCodec
