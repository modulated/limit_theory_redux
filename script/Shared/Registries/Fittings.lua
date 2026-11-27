--- Every weapon and module that can be bolted to a ship, from
--- `res/data/modules.toml`: by key (`Fittings.ShieldBooster`),
--- by id, and by the item it is (`Fittings:forItem(itemId)`), which is how
--- the refit screen turns the goods in a hangar into things that can be
--- fitted.
---
--- Ids are written by hand and permanent: a ship's loadout records them.
---@class Fittings
local Fittings = {}
---@private
Fittings.byId = {}
---@private
Fittings.byName = {}
---@private
Fittings.byItem = {}
---@private
Fittings.all = {}

--- Register one fitting (called by the definitions).
---@param def FittingDefinition
---@param itemId integer the item it is
---@return FittingDefinition
function Fittings:add(def, itemId)
    assert(type(def.id) == "number" and def.id > 0 and def.id % 1 == 0,
        "fitting '" .. tostring(def.name) .. "' has no id: give it the next free one in res/data/modules.toml")
    assert(not self.byId[def.id],
        "fitting id " .. def.id .. " is used twice ('" .. tostring(def.name)
        .. "' and '" .. tostring(self.byId[def.id] and self.byId[def.id].name) .. "')")
    assert(not self.byItem[itemId],
        "two fittings claim the same item: '" .. tostring(def.name) .. "'")
    def.itemId = itemId
    self.byId[def.id] = def
    self.byName[def.name] = def
    self.byItem[itemId] = def
    table.insert(self.all, def)
    return def
end

---@param id integer
---@return FittingDefinition|nil
function Fittings:get(id)
    return self.byId[id]
end

---@param name string with or without spaces
---@return FittingDefinition|nil
function Fittings:getByName(name)
    if type(name) ~= "string" then return nil end
    return self.byName[name] or self.byName[(name:gsub("[^%w]", ""))]
end

--- The fitting an item is, if it is one.
---@param itemId integer
---@return FittingDefinition|nil
function Fittings:forItem(itemId)
    return self.byItem[itemId]
end

---@return FittingDefinition[]
function Fittings:getAll()
    return self.all
end

--- Every fitting that goes in one kind of slot.
---@param slot string "weapon" or "module"
---@return FittingDefinition[]
function Fittings:ofSlot(slot)
    local list = {}
    for _, def in ipairs(self.all) do
        if def.slot == slot then list[#list + 1] = def end
    end
    return list
end

-- Fittings.ShieldBooster and friends
setmetatable(Fittings, {
    __index = function(_, key)
        return Fittings.byName[key]
    end,
})

return Fittings
