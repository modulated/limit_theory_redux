--- A TOML reader, enough of TOML 1.0 for the game's data files
--- (`res/data/*.toml`), with errors that name the file and the line.
---
--- Supported:
---   * comments (`#` to the end of the line)
---   * `key = value`, with bare (`max_shield`), quoted (`"Ship Hull, Small"`)
---     and dotted (`effects.add.maxShield`) keys
---   * `[table]` and `[[array.of.tables]]` headers, dotted, nested
---   * strings: basic ("...", with \" \\ \n \t \r \b \f \uXXXX \UXXXXXXXX),
---     literal ('...'), and both kinds of multi-line ("""...""", '''...''')
---   * integers (decimal, with `_`, signed, and 0x/0o/0b), floats
---     (fractions, exponents, inf, nan), booleans
---   * arrays (over several lines, trailing comma, comments inside) and
---     inline tables (`{ item = "Iron Ore", count = 4 }`)
---
--- Not supported (refused with an error, never misread): dates and times.
---
--- Defining a key twice is an error, as TOML says, so a copy-pasted entry
--- that forgot to change a field is caught rather than silently winning.
---@class Toml
local Toml = {}

local sub, byte, find, format = string.sub, string.byte, string.find, string.format

------------------------------------------------------------------------------
-- The parser state: the text, where we are, and which line that is
------------------------------------------------------------------------------

local Parser = {}
Parser.__index = Parser

local function newParser(text, source)
    return setmetatable({ text = text, pos = 1, line = 1, source = source or "toml" }, Parser)
end

function Parser:fail(message, ...)
    error(format("%s:%d: %s", self.source, self.line, format(message, ...)), 0)
end

function Parser:peek(n)
    return sub(self.text, self.pos, self.pos + (n or 1) - 1)
end

function Parser:atEnd()
    return self.pos > #self.text
end

function Parser:advance(n)
    for _ = 1, n or 1 do
        if byte(self.text, self.pos) == 10 then self.line = self.line + 1 end
        self.pos = self.pos + 1
    end
end

--- Spaces and tabs (not newlines).
function Parser:skipBlank()
    local _, last = find(self.text, "^[ \t]*", self.pos)
    self.pos = last + 1
end

function Parser:skipComment()
    if self:peek() == "#" then
        local nl = find(self.text, "\n", self.pos, true)
        self.pos = nl or (#self.text + 1)
    end
end

--- Blank space, comments and newlines: between entries, and inside arrays.
function Parser:skipAll()
    while not self:atEnd() do
        self:skipBlank()
        self:skipComment()
        local c = self:peek()
        if c == "\n" then
            self:advance()
        elseif c == "\r" and self:peek(2) == "\r\n" then
            self:advance(2)
        else
            return
        end
    end
end

--- The end of a line: nothing but blanks and a comment may follow.
function Parser:expectLineEnd()
    self:skipBlank()
    self:skipComment()
    if self:atEnd() then return end
    local c = self:peek()
    if c == "\n" then
        self:advance()
    elseif self:peek(2) == "\r\n" then
        self:advance(2)
    else
        self:fail("unexpected '%s' after a value (one entry per line)", c)
    end
end

------------------------------------------------------------------------------
-- Strings
------------------------------------------------------------------------------

local function utf8(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    if code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40,
            0x80 + code % 0x40)
    end
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + math.floor(code / 0x1000) % 0x40,
        0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local ESCAPES = { b = "\b", t = "\t", n = "\n", f = "\f", r = "\r", ['"'] = '"', ["\\"] = "\\" }

function Parser:basicString(multiline)
    local quote = multiline and '"""' or '"'
    self:advance(#quote)
    if multiline then
        -- A newline straight after the opening quotes is not part of it
        if self:peek() == "\n" then self:advance()
        elseif self:peek(2) == "\r\n" then self:advance(2) end
    end
    local parts = {}
    while true do
        if self:atEnd() then self:fail("a string is not closed") end
        if self:peek(#quote) == quote then
            self:advance(#quote)
            return table.concat(parts)
        end
        local c = self:peek()
        if c == "\\" then
            self:advance()
            local e = self:peek()
            if ESCAPES[e] then
                parts[#parts + 1] = ESCAPES[e]
                self:advance()
            elseif e == "u" or e == "U" then
                local digits = e == "u" and 4 or 8
                local hex = sub(self.text, self.pos + 1, self.pos + digits)
                if not hex:match("^%x+$") or #hex ~= digits then self:fail("bad \\%s escape", e) end
                local code = tonumber(hex, 16)
                -- A Unicode scalar value: no surrogates, nothing past U+10FFFF
                if code > 0x10FFFF or (code >= 0xD800 and code <= 0xDFFF) then
                    self:fail("bad \\%s escape: %s is not a Unicode character", e, hex)
                end
                parts[#parts + 1] = utf8(code)
                self:advance(1 + digits)
            elseif multiline and (e == "\n" or e == " " or e == "\t" or e == "\r") then
                -- A line-ending backslash: the newline and the blanks after
                -- it go. Only at a line's end: blanks after the backslash
                -- must run to a newline, or it is an escape TOML has not got
                local look = self.pos
                while sub(self.text, look, look):match("^[ \t]$") do look = look + 1 end
                local after = sub(self.text, look, look)
                if after ~= "\n" and sub(self.text, look, look + 1) ~= "\r\n" then
                    self:fail("unknown escape \\%s", e == "\t" and "t (a tab)" or "(a space)")
                end
                while not self:atEnd() and self:peek():match("[ \t\r\n]") do self:advance() end
            else
                self:fail("unknown escape \\%s", e)
            end
        elseif c == "\n" and not multiline then
            self:fail("a string is not closed on its line")
        else
            parts[#parts + 1] = c
            self:advance()
        end
    end
end

function Parser:literalString(multiline)
    local quote = multiline and "'''" or "'"
    self:advance(#quote)
    if multiline then
        if self:peek() == "\n" then self:advance()
        elseif self:peek(2) == "\r\n" then self:advance(2) end
    end
    local close = find(self.text, quote, self.pos, true)
    if not close then self:fail("a string is not closed") end
    local value = sub(self.text, self.pos, close - 1)
    if not multiline and find(value, "\n", 1, true) then self:fail("a string is not closed on its line") end
    self:advance(close - self.pos + #quote)
    return value
end

function Parser:string()
    if self:peek(3) == '"""' then return self:basicString(true) end
    if self:peek(3) == "'''" then return self:literalString(true) end
    if self:peek() == '"' then return self:basicString(false) end
    return self:literalString(false)
end

------------------------------------------------------------------------------
-- Keys
------------------------------------------------------------------------------

--- A key, dotted or not, as a list of parts.
function Parser:key()
    local parts = {}
    while true do
        self:skipBlank()
        local c = self:peek()
        if c == '"' or c == "'" then
            if self:peek(3) == '"""' or self:peek(3) == "'''" then self:fail("a key cannot be a multi-line string") end
            parts[#parts + 1] = self:string()
        else
            local _, last, bare = find(self.text, "^([%w_%-]+)", self.pos)
            if not bare then self:fail("expected a key, found '%s'", c ~= "" and c or "the end") end
            parts[#parts + 1] = bare
            self.pos = last + 1
        end
        self:skipBlank()
        if self:peek() ~= "." then return parts end
        self:advance()
    end
end

------------------------------------------------------------------------------
-- Values
------------------------------------------------------------------------------

function Parser:number()
    local _, last, token = find(self.text, "^([%w%+%-%._]+)", self.pos)
    if not token then self:fail("expected a value") end
    self.pos = last + 1
    if token:match("^%d%d%d%d%-%d%d") or token:match("^%d%d:%d%d") then
        self:fail("dates and times are not supported")
    end
    local plain = token:gsub("_", "")
    local sign, rest = plain:match("^([%+%-]?)(.*)$")
    local value
    if rest == "inf" then
        value = math.huge
    elseif rest == "nan" then
        value = 0 / 0
    elseif rest:match("^0x%x+$") then
        value = tonumber(rest:sub(3), 16)
    elseif rest:match("^0o[0-7]+$") then
        value = tonumber(rest:sub(3), 8)
    elseif rest:match("^0b[01]+$") then
        value = tonumber(rest:sub(3), 2)
    elseif rest:match("^%d+$") or rest:match("^%d+%.%d+$") or rest:match("^%d+[eE][%+%-]?%d+$")
        or rest:match("^%d+%.%d+[eE][%+%-]?%d+$") then
        value = tonumber(rest)
    end
    if value == nil or (token:find("__", 1, true)) then
        self:fail("'%s' is not a value (strings need quotes)", token)
    end
    if sign == "-" then value = -value end
    return value
end

function Parser:array()
    self:advance() -- [
    local list = {}
    while true do
        self:skipAll()
        if self:peek() == "]" then
            self:advance()
            return list
        end
        list[#list + 1] = self:value()
        self:skipAll()
        local c = self:peek()
        if c == "," then
            self:advance()
        elseif c == "]" then
            self:advance()
            return list
        else
            self:fail("expected ',' or ']' in an array, found '%s'", c ~= "" and c or "the end")
        end
    end
end

function Parser:inlineTable()
    self:advance() -- {
    local tbl = {}
    self:skipBlank()
    if self:peek() == "}" then
        self:advance()
        return tbl
    end
    while true do
        local parts = self:key()
        if self:peek() ~= "=" then self:fail("expected '=' after the key '%s'", table.concat(parts, ".")) end
        self:advance()
        self:skipBlank()
        self:assign(tbl, parts, self:value())
        self:skipBlank()
        local c = self:peek()
        if c == "," then
            self:advance()
        elseif c == "}" then
            self:advance()
            return tbl
        else
            self:fail("expected ',' or '}' in an inline table (it must stay on one line)")
        end
    end
end

function Parser:value()
    self:skipBlank()
    local c = self:peek()
    if c == '"' or c == "'" then return self:string() end
    if c == "[" then return self:array() end
    if c == "{" then return self:inlineTable() end
    if sub(self.text, self.pos, self.pos + 3) == "true" and not sub(self.text, self.pos + 4, self.pos + 4):match("[%w_]") then
        self:advance(4)
        return true
    end
    if sub(self.text, self.pos, self.pos + 4) == "false" and not sub(self.text, self.pos + 5, self.pos + 5):match("[%w_]") then
        self:advance(5)
        return false
    end
    if c == "" or c == "\n" then self:fail("a key with no value") end
    return self:number()
end

------------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------------

-- Tables made by a header or a dotted key, as opposed to values: an inline
-- table or an array is closed and may not be added to later.
local defined = setmetatable({}, { __mode = "k" })

-- Where each table began (file and line), for errors about its contents
local origins = setmetatable({}, { __mode = "k" })

--- Set `parts` (a dotted key) in `tbl` to `value`; a key set twice is an error.
function Parser:assign(tbl, parts, value)
    for i = 1, #parts - 1 do
        local part = parts[i]
        local next = tbl[part]
        if next == nil then
            next = {}
            defined[next] = true
            tbl[part] = next
        elseif type(next) ~= "table" or not defined[next] then
            self:fail("'%s' is already a value, not a table", table.concat(parts, ".", 1, i))
        end
        tbl = next
    end
    local last = parts[#parts]
    if tbl[last] ~= nil then self:fail("'%s' is defined twice", table.concat(parts, ".")) end
    tbl[last] = value
end

--- The table a `[header]` or `[[header]]` names, made as needed. Through an
--- array of tables, a path goes on from its last element.
function Parser:tableAt(root, parts, isArray)
    local tbl = root
    for i = 1, #parts do
        local part = parts[i]
        local last = i == #parts
        local next = tbl[part]
        if last and isArray then
            if next == nil then
                next = {}
                defined[next] = "array"
                tbl[part] = next
            elseif defined[next] ~= "array" then
                self:fail("'%s' is not an array of tables", table.concat(parts, "."))
            end
            local element = {}
            defined[element] = true
            origins[element] = { source = self.source, line = self.line }
            next[#next + 1] = element
            return element
        end
        if next == nil then
            next = {}
            defined[next] = true
            tbl[part] = next
        elseif type(next) ~= "table" or not defined[next] then
            self:fail("'%s' is already a value, not a table", table.concat(parts, ".", 1, i))
        elseif defined[next] == "array" then
            next = next[#next]
        elseif last and self.headers[next] then
            self:fail("the table [%s] is defined twice", table.concat(parts, "."))
        end
        tbl = next
    end
    self.headers[tbl] = true
    origins[tbl] = origins[tbl] or { source = self.source, line = self.line }
    return tbl
end

--- Parse a whole document.
function Parser:document()
    local root = {}
    defined[root] = true
    self.headers = setmetatable({}, { __mode = "k" })
    local current = root
    while true do
        self:skipAll()
        if self:atEnd() then return root end
        if self:peek(2) == "[[" then
            self:advance(2)
            local parts = self:key()
            if self:peek(2) ~= "]]" then self:fail("expected ']]' to close the header") end
            self:advance(2)
            current = self:tableAt(root, parts, true)
        elseif self:peek() == "[" then
            self:advance()
            local parts = self:key()
            if self:peek() ~= "]" then self:fail("expected ']' to close the header") end
            self:advance()
            current = self:tableAt(root, parts, false)
        else
            local parts = self:key()
            if self:peek() ~= "=" then self:fail("expected '=' after the key '%s'", table.concat(parts, ".")) end
            self:advance()
            self:assign(current, parts, self:value())
        end
        self:expectLineEnd()
    end
end

------------------------------------------------------------------------------
-- The API
------------------------------------------------------------------------------

--- Parse TOML text. Errors (raised) read "source:line: what is wrong".
---@param text string
---@param source string|nil the file name, for errors
---@return table
function Toml.parse(text, source)
    -- A byte order mark is allowed at the start
    if sub(text, 1, 3) == "\239\187\191" then text = sub(text, 4) end
    return newParser(text, source):document()
end

--- Where a table from a header (`[x]`, `[[x]]`) began: "file:line", or the
--- `fallback` when it did not come from one.
---@param tbl table
---@param fallback string|nil
---@return string
function Toml.where(tbl, fallback)
    local o = origins[tbl]
    if not o then return fallback or "toml" end
    return o.source .. ":" .. o.line
end

--- Where the data files live: `res/data/` beside the game, as the engine's
--- resource lookup has it (`./res`, then `../shared/res`). The tools run
--- from the repository root, which is the same place.
local SEARCH = { "res/data/", "../shared/res/data/" }

--- Look in `dir` (ending in a slash) first: a tool run from outside the
--- repository root points this at its `res/data/`.
---@param dir string
function Toml.addSearchPath(dir)
    table.insert(SEARCH, 1, dir)
end

--- The path of a data file, or nil.
---@param name string e.g. "items.toml"
---@return string|nil
function Toml.find(name)
    for _, dir in ipairs(SEARCH) do
        local f = io.open(dir .. name, "rb")
        if f then
            f:close()
            return dir .. name
        end
    end
    return nil
end

--- Read and parse a data file (`res/data/<name>`). A file that is missing or
--- does not parse stops the game with the reason: data the game cannot read
--- is not something to carry on without.
---@param name string
---@return table
function Toml.load(name)
    local path = Toml.find(name)
    if not path then error("data file res/data/" .. name .. " not found", 0) end
    local f = assert(io.open(path, "rb"))
    local text = f:read("*a")
    f:close()
    return Toml.parse(text, path)
end

return Toml
