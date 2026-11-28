-- `type` is Lua's own (it used to be overridden here to name a class
-- instance by its class, which made `type(entity) == "table"` false and let
-- every NPC be taken for dead; see Core/Structures/Class.lua for classOf,
-- isInstance and isPlainTable, the way to ask what a value is).
--
-- `rawtype` stays, the same function, for the code written against the old
-- override. `typeName` is for messages: a class instance's class name, or
-- the type.
rawtype = type

--- What a value is, in words: its class's name for a class instance.
---@param v any
---@return string
function typeName(v)
    local mt = rawtype(v) == "table" and getmetatable(v) or nil
    local cls = mt and rawtype(mt) == "table" and rawget(mt, "__type") or nil
    if cls then return tostring(cls) end
    return rawtype(v)
end
