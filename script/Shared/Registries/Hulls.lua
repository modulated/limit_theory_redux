--- The hulls the player can fly (`Shared/Definitions/HullDefs.lua`): by id,
--- by name, and by the `Constructs` item that is the hull, which is how a
--- shipyard turns a hull in the hangar into something to fly.
---
--- Ids are permanent: a saved game records which hull is being flown.
---@class Hulls
local Hulls = {}
---@private
Hulls.byId = {}
---@private
Hulls.byName = {}
---@private
Hulls.byItem = {}
---@private
Hulls.all = {}

---@class HullDefinition
---@field id integer
---@field name string the lookup key, the plain letters of the name
---@field displayName string
---@field description string
---@field item ItemDefinition the hull itself, as a good
---@field itemId integer
---@field moduleSlots integer
---@field scale number how big the generated hull is
---@field stats table { maxHealth, maxShield, shieldRegen }
---@field capacitor table { maxCharge, chargeRate }
---@field sockets table[] the mirrored weapon socket pairs the hull carries

--- Register a hull.
---@param def table
---@return HullDefinition
function Hulls:add(def)
    assert(type(def.id) == "number" and def.id > 0,
        "hull '" .. tostring(def.name) .. "' has no id: give it the next free one in HullDefs.lua")
    assert(not self.byId[def.id], "hull id " .. def.id .. " is used twice")
    assert(def.item, "hull '" .. tostring(def.name) .. "' names no item")
    assert(def.sockets and #def.sockets > 0,
        "hull '" .. tostring(def.name) .. "' has no weapon sockets")
    def.displayName = def.displayName or def.name
    def.name = (def.name:gsub("[^%w]", ""))
    def.itemId = def.item.id
    self.byId[def.id] = def
    self.byName[def.name] = def
    self.byItem[def.itemId] = def
    table.insert(self.all, def)
    return def
end

---@param id integer
---@return HullDefinition|nil
function Hulls:get(id)
    return self.byId[id]
end

---@param name string
---@return HullDefinition|nil
function Hulls:getByName(name)
    if type(name) ~= "string" then return nil end
    return self.byName[name] or self.byName[(name:gsub("[^%w]", ""))]
end

--- The hull an item is, if it is one.
---@param itemId integer
---@return HullDefinition|nil
function Hulls:forItem(itemId)
    return self.byItem[itemId]
end

---@return HullDefinition[] every hull, smallest first
function Hulls:getAll()
    return self.all
end

--- How many mounts a hull has: every socket is a mirrored pair, so two each.
---@param def HullDefinition
---@return integer
function Hulls.mountCount(def)
    return #def.sockets * 2
end

--- A hull in one line, for a shipyard's list.
---@param def HullDefinition
---@return string
function Hulls.describe(def)
    local sizes = {}
    for _, socket in ipairs(def.sockets) do
        local size = tostring(socket.mountSizeClass):upper()
        sizes[size] = (sizes[size] or 0) + 2
    end
    local parts = {}
    for _, size in ipairs({ "XL", "L", "M", "SM" }) do
        if sizes[size] then parts[#parts + 1] = string.format("%dx%s", sizes[size], size) end
    end
    return string.format("%s mounts, %d module slots, %d hull, %d shield",
        table.concat(parts, " "), def.moduleSlots, def.stats.maxHealth, def.stats.maxShield)
end

setmetatable(Hulls, {
    __index = function(_, key)
        return Hulls.byName[key]
    end,
})

return Hulls
