local Toml = require("Shared.Data.Toml")

--- Checks one entry of a data file (an `[[item]]`, a `[[recipe]]`...) field
--- by field, and stops with the file, the line the entry starts on, the entry
--- and what is wrong with it:
---
---     res/data/recipes.toml:212: recipe 17 (Steel Refinery): inputs, entry 2 names no item 'Iron Or'
---
--- Unknown fields are an error too, so a misspelt key ("enrgy_density") is
--- caught rather than silently ignored.
---@class Fields
local Fields = {}
Fields.__index = Fields

---@param entry table the parsed entry
---@param kind string "item", "recipe", ...
---@param known string[] every field the entry may have
---@return Fields
function Fields.of(entry, kind, known)
    local self = setmetatable({ entry = entry, kind = kind, known = {} }, Fields)
    for _, key in ipairs(known) do self.known[key] = true end
    if type(entry) ~= "table" then self:fail("is not a table") end
    for key in pairs(entry) do
        if not self.known[key] then
            self:fail("has an unknown field '%s' (known: %s)", tostring(key), table.concat(known, ", "))
        end
    end
    return self
end

--- Stop with what is wrong, prefixed with where the entry is.
function Fields:fail(message, ...)
    local entry = type(self.entry) == "table" and self.entry or {}
    local label = self.kind
    if entry.id ~= nil then label = label .. " " .. tostring(entry.id) end
    if type(entry.name) == "string" then label = label .. " (" .. entry.name .. ")" end
    error(string.format("%s: %s: %s", Toml.where(entry), label, string.format(message, ...)), 0)
end

---@return any
function Fields:get(key)
    return self.entry[key]
end

--- A whole number above zero (the permanent ids).
function Fields:id(key)
    local v = self.entry[key or "id"]
    if type(v) ~= "number" or v < 1 or v % 1 ~= 0 then
        self:fail("needs `%s`, a whole number above 0", key or "id")
    end
    return v
end

--- A non-empty string.
function Fields:str(key, optional)
    local v = self.entry[key]
    if v == nil and optional then return nil end
    if type(v) ~= "string" or v == "" then self:fail("needs `%s`, a non-empty string", key) end
    return v
end

--- A number, at least `min` when given.
function Fields:num(key, min, optional)
    local v = self.entry[key]
    if v == nil and optional then return nil end
    if type(v) ~= "number" or v ~= v then self:fail("needs `%s`, a number", key) end
    if min and v < min then self:fail("`%s` is %s; it must be at least %s", key, tostring(v), tostring(min)) end
    return v
end

--- A whole number, at least `min` when given.
function Fields:int(key, min, optional)
    local v = self:num(key, min, optional)
    if v ~= nil and v % 1 ~= 0 then self:fail("`%s` must be a whole number", key) end
    return v
end

--- One of a set of strings.
---@param choices table<string, any> the allowed values as keys
function Fields:oneOf(key, choices, optional)
    local v = self.entry[key]
    if v == nil and optional then return nil end
    if choices[v] == nil then
        local names = {}
        for name in pairs(choices) do names[#names + 1] = name end
        table.sort(names)
        self:fail("`%s` is '%s'; it must be one of: %s", key, tostring(v), table.concat(names, ", "))
    end
    return v
end

--- A table (an inline table or a sub-table), when given.
function Fields:tbl(key, optional)
    local v = self.entry[key]
    if v == nil and optional then return nil end
    if type(v) ~= "table" then self:fail("needs `%s`, a table", key) end
    return v
end

--- Ids must not repeat across a file: `seen` collects them.
---@param seen table
---@param id integer
function Fields:unique(seen, id, what)
    if seen[id] then
        self:fail("uses the %s %s, already used by '%s'", what or "id", tostring(id), seen[id])
    end
    seen[id] = self.entry.name or "another entry"
end

return Fields
