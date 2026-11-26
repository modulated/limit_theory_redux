local ffi = require("ffi")
local bit = require("bit")
local SaveCodec = require("Shared.Save.SaveCodec")

--- A saved game on disk: a fixed header, a small metadata block, and the
--- state, compressed.
---
---   offset  size  what
---        0     8  magic "LTRSAVE\0"
---        8     2  format version (this file's layout; FORMAT_VERSION)
---       10     2  flags: 1 = the payload is zlib-compressed
---       12     4  metadata length
---       16     4  payload length, as stored
---       20     4  payload length, uncompressed
---       24     4  CRC-32 of the metadata
---       28     4  CRC-32 of the payload, as stored
---       32     .  metadata (SaveCodec, never compressed)
---        .     .  payload (SaveCodec, then zlib)
---
--- All integers little-endian. The metadata is what a list of saves shows
--- (the system, the credits, the ship, when) and is left uncompressed so a
--- load screen reads a dozen files without unpacking a game from any of them.
---
--- Reading never trusts the file: the magic, the version, every length
--- against the file's size and both checksums are checked before anything is
--- decoded, and the payload is only decompressed once its checksum matches --
--- the engine's zlib panics on corrupt input, which would take the game down
--- rather than refuse one bad file. The uncompressed length is checked after.
---
--- Writing never leaves a half-written save in place of a good one: the new
--- file goes to `<path>.tmp`, the old one becomes `<path>.bak`, and only then
--- does the new one take the name.
---@class SaveFile
local SaveFile = {}

SaveFile.MAGIC = "LTRSAVE\0"
SaveFile.FORMAT_VERSION = 1
SaveFile.HEADER_SIZE = 32
local FLAG_COMPRESSED = 1

------------------------------------------------------------------------------
-- CRC-32 (IEEE 802.3, as zlib and PNG)
------------------------------------------------------------------------------

local crcTable = {}
for i = 0, 255 do
    local c = i
    for _ = 1, 8 do
        if bit.band(c, 1) ~= 0 then
            c = bit.bxor(0xEDB88320, bit.rshift(c, 1))
        else
            c = bit.rshift(c, 1)
        end
    end
    crcTable[i] = c
end

--- The CRC-32 of a string, as an unsigned number.
---@param s string
---@return integer
function SaveFile.crc32(s)
    local crc = 0xFFFFFFFF
    for i = 1, #s do
        crc = bit.bxor(crcTable[bit.band(bit.bxor(crc, s:byte(i)), 0xFF)], bit.rshift(crc, 8))
    end
    crc = bit.bxor(crc, 0xFFFFFFFF)
    return crc % 4294967296 -- bit operations are signed: as unsigned
end

------------------------------------------------------------------------------
-- Little-endian integers
------------------------------------------------------------------------------

---@param n integer
---@return string
local function u16(n)
    return string.char(n % 256, math.floor(n / 256) % 256)
end

---@param n integer
---@return string
local function u32(n)
    return string.char(n % 256, math.floor(n / 256) % 256,
        math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
end

---@param s string
---@param at integer 1-based
---@return integer
local function readU16(s, at)
    local a, b = s:byte(at, at + 1)
    return a + b * 256
end

---@param s string
---@param at integer 1-based
---@return integer
local function readU32(s, at)
    local a, b, c, d = s:byte(at, at + 3)
    return a + b * 256 + c * 65536 + d * 16777216
end

------------------------------------------------------------------------------
-- Compression: the engine's zlib (Bytes), when there is an engine
------------------------------------------------------------------------------

--- A Lua string through an engine Bytes operation, back to a Lua string.
---@param data string
---@param operation string "compress" or "decompress"
---@return string
local function throughBytes(data, operation)
    local source = Bytes.FromData(ffi.cast("const uint8_t*", data), #data)
    local result = source[operation](source)
    local size = result:getSize()
    if size == 0 then return "" end
    local buffer = ffi.new("uint8_t[?]", size)
    result:rewind()
    result:read(buffer, size)
    return ffi.string(buffer, size)
end

--- How the payload is packed: zlib through the engine when it is there. A
--- tool or a test without the engine can set these (or leave the payload
--- stored as it is: the flags say which).
SaveFile.compress = function(data)
    if not Bytes or not Bytes.FromData then return nil end
    return throughBytes(data, "compress")
end
SaveFile.decompress = function(data)
    if not Bytes or not Bytes.FromData then return nil end
    return throughBytes(data, "decompress")
end

------------------------------------------------------------------------------
-- The file
------------------------------------------------------------------------------

--- A save as bytes.
---@param meta table what the save list shows
---@param state table the game
---@return string
function SaveFile.pack(meta, state)
    local metaBytes = SaveCodec.encode(meta or {})
    local raw = SaveCodec.encode(state)
    local payload, flags = raw, 0
    local packed = SaveFile.compress(raw)
    if packed and #packed < #raw then
        payload, flags = packed, FLAG_COMPRESSED
    end
    return table.concat({
        SaveFile.MAGIC,
        u16(SaveFile.FORMAT_VERSION),
        u16(flags),
        u32(#metaBytes),
        u32(#payload),
        u32(#raw),
        u32(SaveFile.crc32(metaBytes)),
        u32(SaveFile.crc32(payload)),
        metaBytes,
        payload,
    })
end

--- Read the header and check it against the bytes there are.
---@param bytes string
---@return table|nil header
---@return string|nil problem
local function header(bytes)
    if #bytes < SaveFile.HEADER_SIZE then return nil, "too short to be a save" end
    if bytes:sub(1, 8) ~= SaveFile.MAGIC then return nil, "not a save file" end
    local h = {
        version = readU16(bytes, 9),
        flags = readU16(bytes, 11),
        metaLength = readU32(bytes, 13),
        payloadLength = readU32(bytes, 17),
        rawLength = readU32(bytes, 21),
        metaCrc = readU32(bytes, 25),
        payloadCrc = readU32(bytes, 29),
    }
    if h.version > SaveFile.FORMAT_VERSION then
        return nil, string.format("saved by a newer version (format %d; this reads up to %d)",
            h.version, SaveFile.FORMAT_VERSION)
    end
    local expected = SaveFile.HEADER_SIZE + h.metaLength + h.payloadLength
    if expected ~= #bytes then
        return nil, string.format("damaged: %d bytes where the header says %d", #bytes, expected)
    end
    return h
end

--- Just the metadata, for a list of saves: nothing is decompressed.
---@param bytes string
---@return table|nil meta
---@return string|nil problem
function SaveFile.unpackMeta(bytes)
    local h, problem = header(bytes)
    if not h then return nil, problem end
    local metaBytes = bytes:sub(SaveFile.HEADER_SIZE + 1, SaveFile.HEADER_SIZE + h.metaLength)
    if SaveFile.crc32(metaBytes) ~= h.metaCrc then return nil, "damaged (the summary's checksum)" end
    local ok, meta = pcall(SaveCodec.decode, metaBytes)
    if not ok then return nil, "damaged (" .. tostring(meta) .. ")" end
    return meta
end

--- The whole save.
---@param bytes string
---@return table|nil meta
---@return table|string state, or the problem
function SaveFile.unpack(bytes)
    local meta, problem = SaveFile.unpackMeta(bytes)
    if not meta then return nil, problem end
    local h = header(bytes)
    local start = SaveFile.HEADER_SIZE + h.metaLength + 1
    local payload = bytes:sub(start, start + h.payloadLength - 1)
    -- The checksum first: the decompressor is not to see damaged data
    if SaveFile.crc32(payload) ~= h.payloadCrc then return nil, "damaged (the game's checksum)" end
    local raw = payload
    if bit.band(h.flags, FLAG_COMPRESSED) ~= 0 then
        local ok, unpacked = pcall(SaveFile.decompress, payload)
        if not ok or not unpacked then return nil, "could not be decompressed" end
        raw = unpacked
    end
    if #raw ~= h.rawLength then
        return nil, string.format("damaged: %d bytes unpacked where %d were saved", #raw, h.rawLength)
    end
    local ok, state = pcall(SaveCodec.decode, raw)
    if not ok then return nil, "damaged (" .. tostring(state) .. ")" end
    return meta, state
end

------------------------------------------------------------------------------
-- Disk
------------------------------------------------------------------------------

---@param path string
---@return string|nil bytes
local function readAll(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local bytes = file:read("*a")
    file:close()
    return bytes
end

---@param path string
---@return boolean
function SaveFile.exists(path)
    local file = io.open(path, "rb")
    if file then file:close() end
    return file ~= nil
end

--- Write a save, replacing any there was only once the new one is complete.
---@param path string
---@param meta table
---@param state table
---@return boolean ok
---@return string|nil problem
function SaveFile.write(path, meta, state)
    local okPack, bytes = pcall(SaveFile.pack, meta, state)
    if not okPack then return false, tostring(bytes) end

    local temp = path .. ".tmp"
    local file, openProblem = io.open(temp, "wb")
    if not file then return false, "cannot write " .. temp .. ": " .. tostring(openProblem) end
    local okWrite, writeProblem = file:write(bytes)
    file:close()
    if not okWrite then
        os.remove(temp)
        return false, "writing failed: " .. tostring(writeProblem)
    end
    -- Read it back before it replaces anything: a full disk can write short
    if readAll(temp) ~= bytes then
        os.remove(temp)
        return false, "the written file did not read back the same"
    end

    -- The old save steps aside (Windows will not rename onto an existing
    -- file), the new one takes its name, and the old one is the backup
    local backup = path .. ".bak"
    local hadOld = SaveFile.exists(path)
    if hadOld then
        os.remove(backup)
        local moved, moveProblem = os.rename(path, backup)
        if not moved then
            os.remove(temp)
            return false, "cannot move the old save aside: " .. tostring(moveProblem)
        end
    end
    local renamed, renameProblem = os.rename(temp, path)
    if not renamed then
        if hadOld then os.rename(backup, path) end
        os.remove(temp)
        return false, "cannot put the new save in place: " .. tostring(renameProblem)
    end
    return true
end

--- Read a save's summary (for a list of saves).
---@param path string
---@return table|nil meta
---@return string|nil problem
function SaveFile.readMeta(path)
    local bytes = readAll(path)
    if not bytes then return nil, "no file" end
    return SaveFile.unpackMeta(bytes)
end

--- Read a whole save. A damaged file is reported, never half-loaded; when the
--- file is damaged and a backup is there, the backup is read instead and the
--- third result says so.
---@param path string
---@return table|nil meta
---@return table|string state, or the problem
---@return boolean|nil fromBackup
function SaveFile.read(path)
    local bytes = readAll(path)
    if bytes then
        local meta, state = SaveFile.unpack(bytes)
        if meta then return meta, state, false end
        local backupBytes = readAll(path .. ".bak")
        if backupBytes then
            local backupMeta, backupState = SaveFile.unpack(backupBytes)
            if backupMeta then return backupMeta, backupState, true end
        end
        return nil, state
    end
    return nil, "no file"
end

return SaveFile
