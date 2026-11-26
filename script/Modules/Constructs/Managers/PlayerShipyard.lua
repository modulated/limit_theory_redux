local Hulls = require("Shared.Registries.Hulls")
local PlayerLoadout = require("Modules.Constructs.Managers.PlayerLoadout")

--- Which hull the player flies, and swapping it for another.
---
--- A hull is an item (`Constructs` in the item registry): a station sells
--- them, a drydock builds them, and switching is a trade -- the hull you were
--- flying goes into the station's hangar and the one you are taking comes out
--- of it. You cannot fly two ships, so there is always exactly one hull in
--- hand and the rest are goods.
---
--- Switching happens at a station, because the ship has to be rebuilt around
--- the new frame; `LTheoryRedux:switchHull` does the rebuilding and this
--- keeps the record.
---@class PlayerShipyard
local PlayerShipyard = {
    ---@type integer|nil the hull being flown, by hull id
    hullId = nil,
}

--- A new game: the starting hull.
---@param hullName string|nil the hull to start in (default the Small Hull)
function PlayerShipyard:reset(hullName)
    local hull = hullName and Hulls:getByName(hullName) or Hulls:getByName("Small Hull")
    self.hullId = hull and hull.id or nil
end

--- The hull being flown.
---@return HullDefinition|nil
function PlayerShipyard:current()
    return self.hullId and Hulls:get(self.hullId) or nil
end

--- The hulls in a store that could be flown instead of this one.
---@param store StockComponent|nil
---@return table[] rows { hull, units }
function PlayerShipyard:available(store)
    local rows = {}
    if not store then return rows end
    for _, row in ipairs(store:list()) do
        local hull = Hulls:forItem(row.item.id)
        if hull and hull.id ~= self.hullId then
            rows[#rows + 1] = { hull = hull, units = row.units }
        end
    end
    table.sort(rows, function(a, b) return a.hull.id < b.hull.id end)
    return rows
end

--- Take a hull out of `store` to fly, and put the old one in. The caller
--- rebuilds the ship afterwards; the fit comes with it as far as the new hull
--- has room (`PlayerLoadout:restore`).
---@param hull HullDefinition
---@param store StockComponent the station's hangar
---@return boolean switched, string|nil reason
function PlayerShipyard:switch(hull, store)
    if not hull then return false, "no such hull" end
    if hull.id == self.hullId then return false, "you are flying that one" end
    if not store then return false, "no hangar here" end
    if store:count(hull.itemId) < 1 then return false, "that hull is not in the hangar" end
    if store:remove(hull.itemId, 1) < 1 then return false, "that hull is not in the hangar" end

    local previous = self:current()
    if previous then store:add(previous.itemId, 1) end
    self.hullId = hull.id
    PlayerLoadout:setModuleSlots(hull.moduleSlots)
    return true
end

--- The stats a hull starts from, for the ship builder.
---@return table stats { maxHealth, maxShield, shieldRegen }
function PlayerShipyard:stats()
    local hull = self:current()
    if not hull then return { maxHealth = 700, maxShield = 160, shieldRegen = 6 } end
    return {
        maxHealth = hull.stats.maxHealth,
        maxShield = hull.stats.maxShield,
        shieldRegen = hull.stats.shieldRegen,
    }
end

--- How big the generated hull is.
---@param fallback number
---@return number
function PlayerShipyard:scale(fallback)
    local hull = self:current()
    return hull and hull.scale or fallback
end

--- How many module slots the hull being flown has.
---@return integer
function PlayerShipyard:moduleSlots()
    local hull = self:current()
    return hull and hull.moduleSlots or 0
end

return PlayerShipyard
