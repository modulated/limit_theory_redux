local Component = require("Core.ECS.Component")
local Items = require("Shared.Registries.Items")

--- What a station or a ship is holding: units per item id, with an optional
--- capacity in mass (a ship's hold; a station's store is unlimited).
---
--- This is the plain store the trade and production systems move goods
--- through. `InventoryComponent` is the other one, which holds an `Entity`
--- per item for the order-book marketplace; a hold of 4,000 units of ore
--- cannot be 4,000 entities, so bulk goods live here.
---@class StockComponent: Component
---@overload fun(self: StockComponent, capacity: number|nil): StockComponent subclass internal
---@overload fun(capacity: number|nil): StockComponent subclass external
local StockComponent = Subclass("StockComponent", Component, function(self, capacity)
    self:setComponentName("EconomyStock")
    self.units = {}
    self.capacity = capacity -- nil: no limit
end)

---@param capacity number|nil mass the hold takes, nil for no limit
function StockComponent:setCapacity(capacity)
    self.capacity = capacity
end

---@return number|nil
function StockComponent:getCapacity()
    return self.capacity
end

--- The mass of everything held.
---@return number
function StockComponent:getUsedMass()
    local mass = 0
    for id, units in pairs(self.units) do
        local def = Items:getDefinition(id)
        mass = mass + (def and def.mass or 0) * units
    end
    return mass
end

--- The mass that still fits, or math.huge without a capacity.
---@return number
function StockComponent:getFreeMass()
    if not self.capacity then return math.huge end
    return math.max(0, self.capacity - self:getUsedMass())
end

--- How many units of an item would still fit.
---@param itemId integer
---@return integer
function StockComponent:getRoomFor(itemId)
    if not self.capacity then return math.huge end
    local def = Items:getDefinition(itemId)
    local mass = def and def.mass or 0
    if mass <= 0 then return math.huge end
    return math.floor(self:getFreeMass() / mass)
end

--- Put units in, as many as fit.
---@param itemId integer
---@param units integer
---@return integer added
function StockComponent:add(itemId, units)
    units = math.floor(units or 0)
    if units <= 0 then return 0 end
    local room = self:getRoomFor(itemId)
    if room < units then units = room end
    if units <= 0 then return 0 end
    self.units[itemId] = (self.units[itemId] or 0) + units
    return units
end

--- Put units back that were taken out of this store (a market order's goods,
--- cancelled or lapsed): all of them, room or not. They were here before the
--- order held them, so the store is only as full as it was.
---@param itemId integer
---@param units integer
---@return integer added
function StockComponent:restore(itemId, units)
    units = math.floor(units or 0)
    if units <= 0 then return 0 end
    self.units[itemId] = (self.units[itemId] or 0) + units
    return units
end

--- Take units out, as many as there are.
---@param itemId integer
---@param units integer
---@return integer removed
function StockComponent:remove(itemId, units)
    units = math.floor(units or 0)
    if units <= 0 then return 0 end
    local held = self.units[itemId] or 0
    if units > held then units = held end
    if units <= 0 then return 0 end
    held = held - units
    self.units[itemId] = held > 0 and held or nil
    return units
end

---@param itemId integer
---@return integer
function StockComponent:count(itemId)
    return self.units[itemId] or 0
end

---@param itemId integer
---@param units integer
function StockComponent:set(itemId, units)
    units = math.floor(units or 0)
    self.units[itemId] = units > 0 and units or nil
end

--- Every item held, as a list of `{ item = ItemDefinition, units = integer }`,
--- in a stable order (by item id) so a list on screen does not jump about.
---@return table[]
function StockComponent:list()
    local rows = {}
    for id, units in pairs(self.units) do
        local def = Items:getDefinition(id)
        if def then rows[#rows + 1] = { item = def, units = units } end
    end
    table.sort(rows, function(a, b) return a.item.id < b.item.id end)
    return rows
end

---@return boolean
function StockComponent:isEmpty()
    return next(self.units) == nil
end

--- Total units held, whatever they are.
---@return integer
function StockComponent:getTotalUnits()
    local total = 0
    for _, units in pairs(self.units) do total = total + units end
    return total
end

function StockComponent:clear()
    self.units = {}
end

return StockComponent
