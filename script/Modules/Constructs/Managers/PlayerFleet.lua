local Hulls = require("Shared.Registries.Hulls")
local Fittings = require("Shared.Registries.Fittings")
local ConstructComponents = require("Modules.Constructs.Components")
local ShipFittingSystem = require("Modules.Constructs.Systems.ShipFittingSystem")

--- The ships the player owns, and which one is being flown.
---
--- A fit belongs to a **ship**, not to the player: take a different ship out
--- and you get that ship's guns and modules, not the ones you had on the last
--- one. So a Compact fitted for mining and a Compact fitted to fight are two
--- ships, kept apart, and swapping between them costs nothing but the walk
--- across the hangar.
---
--- A hull is an item until it is **commissioned**: taking one out of a
--- station's hangar spends the item and makes a ship with an empty fit, which
--- is the player's from then on. The other way round, **decommissioning** an
--- empty ship puts the bare hull back as an item to sell; a ship with
--- anything still in it cannot be decommissioned, so nothing is ever sold out
--- from under its own modules.
---
--- A ship that is not being flown is **parked** at the station it was left
--- at, with its fittings in it, and can be flown, stripped or decommissioned
--- from that station's refit screen and nowhere else.
---
--- The ship entity is destroyed and rebuilt on undocking, on a jump and on a
--- respawn, so none of this can live on it: like the hold (`PlayerCargo`) and
--- the credits (`PlayerWallet`), the fleet outlives the entity. `record`
--- writes an entity's fit into the ship it is, and `restore` writes a ship's
--- fit onto a freshly built entity.
---
--- Ids are sequential and permanent: a saved game records which ship is being
--- flown and what is in each one.
---@class PlayerFleet
local PlayerFleet = {
    ---@type table<integer, PlayerShip>
    ships = {},
    ---@type integer the id the next commissioned ship gets
    nextId = 1,
    ---@type integer|nil the ship being flown
    activeId = nil,
}

---@class PlayerShip
---@field id integer
---@field hullId integer
---@field name string what the refit screen calls it
---@field stationKey string|nil where it is parked (nil while it is flown)
---@field weapons table<string, integer> mount id -> fitting id
---@field modules table<integer, integer> slot -> fitting id

------------------------------------------------------------------------------
-- The fleet
------------------------------------------------------------------------------

--- A new game: one ship, in the starting hull, with nothing in it.
---@param hullName string|nil the hull to start in (default the Small Hull)
---@return PlayerShip|nil
function PlayerFleet:reset(hullName)
    self.ships = {}
    self.nextId = 1
    self.activeId = nil
    local hull = (hullName and Hulls:getByName(hullName)) or Hulls:getByName("Small Hull")
    if not hull then return nil end
    local ship = self:commission(hull, nil)
    self.activeId = ship and ship.id or nil
    return ship
end

--- Make a ship of a hull. The caller spends the hull item.
---@param hull HullDefinition
---@param stationKey string|nil where it stands
---@return PlayerShip|nil
function PlayerFleet:commission(hull, stationKey)
    if not hull then return nil end
    local id = self.nextId
    self.nextId = id + 1
    local ship = {
        id = id,
        hullId = hull.id,
        name = string.format("%s %d", hull.displayName, id),
        stationKey = stationKey,
        weapons = {},
        modules = {},
    }
    self.ships[id] = ship
    return ship
end

--- The ship being flown.
---@return PlayerShip|nil
function PlayerFleet:active()
    return self.activeId and self.ships[self.activeId] or nil
end

---@param id integer
---@return PlayerShip|nil
function PlayerFleet:get(id)
    return self.ships[id]
end

--- The hull a ship is.
---@param ship PlayerShip|nil
---@return HullDefinition|nil
function PlayerFleet.hullOf(ship)
    return ship and Hulls:get(ship.hullId) or nil
end

--- Every ship, by id.
---@return PlayerShip[]
function PlayerFleet:all()
    local list = {}
    for _, ship in pairs(self.ships) do list[#list + 1] = ship end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

--- The ships parked at a station, the one being flown aside.
---@param stationKey string|nil
---@return PlayerShip[]
function PlayerFleet:parkedAt(stationKey)
    local list = {}
    if not stationKey then return list end
    for _, ship in ipairs(self:all()) do
        if ship.id ~= self.activeId and ship.stationKey == stationKey then
            list[#list + 1] = ship
        end
    end
    return list
end

--- Leave the ship being flown at a station and take another of the player's.
--- The caller rebuilds the entity afterwards (`restore` puts the new ship's
--- fit on it).
---@param ship PlayerShip the ship to take
---@param stationKey string|nil the station both are at
---@return boolean switched, string|nil reason
function PlayerFleet:setActive(ship, stationKey)
    if not ship or not self.ships[ship.id] then return false, "no such ship" end
    if ship.id == self.activeId then return false, "you are flying it" end
    if stationKey and ship.stationKey ~= stationKey then
        return false, "that ship is not at this station"
    end
    local previous = self:active()
    if previous then previous.stationKey = stationKey end
    ship.stationKey = nil
    self.activeId = ship.id
    return true
end

--- Give the bare hull of an empty ship back as an item. A ship with anything
--- in its mounts or slots is refused: strip it first.
---@param ship PlayerShip
---@param store StockComponent|nil the station's hangar
---@return boolean done, string|nil reason
function PlayerFleet:decommission(ship, store)
    if not ship or not self.ships[ship.id] then return false, "no such ship" end
    if ship.id == self.activeId then return false, "you are flying it" end
    if self.fittingCount(ship) > 0 then
        return false, "it still has fittings in it: strip it first"
    end
    local hull = self.hullOf(ship)
    if not hull then return false, "unknown hull" end
    if not store then return false, "no hangar here" end
    if store:add(hull.itemId, 1) < 1 then return false, "no room in the hangar" end
    self.ships[ship.id] = nil
    return true
end

--- How many fittings a ship has in it.
---@param ship PlayerShip|nil
---@return integer
function PlayerFleet.fittingCount(ship)
    if not ship then return 0 end
    local count = 0
    for _ in pairs(ship.weapons) do count = count + 1 end
    for _ in pairs(ship.modules) do count = count + 1 end
    return count
end

--- Take everything out of a ship and put it in a store. For the ship being
--- flown the entity is stripped too, so the change shows at once.
---@param ship PlayerShip
---@param store StockComponent|nil where the parts go
---@param entity Entity|nil the flown ship's entity, when this is that ship
---@return integer taken how many fittings came out, string|nil reason
function PlayerFleet:strip(ship, store, entity)
    if not ship or not self.ships[ship.id] then return 0, "no such ship" end
    if not store then return 0, "no hangar here" end
    local taken = 0
    local function hand(id)
        local def = Fittings:get(id)
        if not def then return end
        if store:add(def.itemId, 1) < 1 then return end
        taken = taken + 1
    end
    -- The entity first, so a part that will not fit in the hangar stays on
    -- the ship rather than vanishing from both
    local kept = { weapons = {}, modules = {} }
    for mountId, id in pairs(ship.weapons) do
        local before = taken
        hand(id)
        if taken == before then kept.weapons[mountId] = id end
    end
    for slot, id in pairs(ship.modules) do
        local before = taken
        hand(id)
        if taken == before then kept.modules[slot] = id end
    end
    ship.weapons, ship.modules = kept.weapons, kept.modules
    if entity and entity:isValid() and ship.id == self.activeId then
        local loadout = entity:get(ConstructComponents.Loadout)
        if loadout then
            loadout.weapons, loadout.modules = {}, {}
            for mountId, id in pairs(ship.weapons) do loadout.weapons[mountId] = id end
            for slot, id in pairs(ship.modules) do loadout.modules[slot] = id end
            ShipFittingSystem:apply(entity)
        end
    end
    if taken == 0 then return 0, "there was nothing in it, or no room in the hangar" end
    return taken
end

------------------------------------------------------------------------------
-- The ship being flown, and its entity
------------------------------------------------------------------------------

--- Give the active ship a fitting without buying it (what a new game's ship
--- comes with). Returns false when there is nowhere to put it.
---@param def FittingDefinition
---@param slot integer|nil for a module; the first free slot otherwise
---@return boolean
function PlayerFleet:grantModule(def, slot)
    local ship = self:active()
    local hull = self.hullOf(ship)
    if not ship or not hull or not def or def:isWeapon() then return false end
    if not slot then
        for candidate = 1, hull.moduleSlots do
            if not ship.modules[candidate] then
                slot = candidate
                break
            end
        end
    end
    if not slot or slot < 1 or slot > hull.moduleSlots then return false end
    ship.modules[slot] = def.id
    return true
end

--- Give the flown ship a weapon (a new game's starting gun). Its mounts are
--- only known once the ship is built, so the gun waits on the ship and goes
--- in the first free mount that takes it, smallest first (`restore`).
---@param def FittingDefinition a weapon
---@return boolean
function PlayerFleet:grantWeapon(def)
    local ship = self:active()
    if not ship or not def or not def:isWeapon() then return false end
    ship.pendingWeapons = ship.pendingWeapons or {}
    table.insert(ship.pendingWeapons, def.id)
    return true
end

--- Note what the flown entity is fitted with, so the ship keeps it.
---@param entity Entity|nil
function PlayerFleet:record(entity)
    local ship = self:active()
    local loadout = entity and entity:isValid() and entity:get(ConstructComponents.Loadout)
    if not ship or not loadout then return end
    ship.weapons = {}
    for mountId, id in pairs(loadout.weapons) do ship.weapons[mountId] = id end
    ship.modules = {}
    for slot, id in pairs(loadout.modules) do ship.modules[slot] = id end
end

--- Put the active ship's fit onto an entity that has just been built, and
--- work the stats out. Anything the hull has no room for is handed back --
--- which should not happen, since a fit is made on the hull it is for, but a
--- changed hull definition should not swallow a module.
---@param entity Entity
---@param turrets table[] the builder's turret records
---@param spare StockComponent|nil where fittings with nowhere to go are put
---@return integer returned how many were handed back
---@return integer lost how many of those `spare` had no room for
function PlayerFleet:restore(entity, turrets, spare)
    if not entity then return 0, 0 end
    local ship = self:active()
    local hull = self.hullOf(ship)
    local moduleSlots = hull and hull.moduleSlots or 0
    local loadout = entity:get(ConstructComponents.Loadout)
    if not loadout then
        loadout = entity:add(ConstructComponents.Loadout(moduleSlots))
    end
    loadout:setModuleSlots(moduleSlots)
    ShipFittingSystem:setMounts(entity, turrets)
    if not ship then
        ShipFittingSystem:apply(entity)
        return 0, 0
    end

    local returned, lost = 0, 0
    local function handBack(def)
        returned = returned + 1
        if not spare or spare:add(def.itemId, 1) < 1 then lost = lost + 1 end
    end

    local mounts = {}
    for _, mount in ipairs(ShipFittingSystem:mounts(entity)) do
        mounts[mount.mountId] = mount
    end
    for mountId, id in pairs(ship.weapons) do
        local def = Fittings:get(id)
        local mount = mounts[mountId]
        if def and mount and ShipFittingSystem:weaponFits(def, mount.sizeClass) then
            loadout:setWeapon(mountId, def)
        elseif def then
            handBack(def)
        end
    end
    -- A mount fitting found in a module slot (a save from before the mining
    -- laser moved to a mount): it goes to a mount instead
    for slot, id in pairs(ship.modules) do
        local def = Fittings:get(id)
        if def and def:isWeapon() then
            ship.modules[slot] = nil
            ship.pendingWeapons = ship.pendingWeapons or {}
            table.insert(ship.pendingWeapons, id)
        end
    end
    -- A starting gun: in the smallest free mount that takes it
    if ship.pendingWeapons then
        local ordered = ShipFittingSystem:mounts(entity)
        local order = { sm = 1, m = 2, l = 3, xl = 4 }
        table.sort(ordered, function(a, b)
            local sa, sb = order[a.sizeClass] or 9, order[b.sizeClass] or 9
            if sa ~= sb then return sa < sb end
            return a.mountId < b.mountId
        end)
        for _, id in ipairs(ship.pendingWeapons) do
            local def = Fittings:get(id)
            local placed = false
            for _, mount in ipairs(ordered) do
                if def and not loadout:getWeapon(mount.mountId) and ShipFittingSystem:weaponFits(def, mount.sizeClass) then
                    loadout:setWeapon(mount.mountId, def)
                    placed = true
                    break
                end
            end
            if def and not placed then handBack(def) end
        end
        ship.pendingWeapons = nil
    end
    for slot, id in pairs(ship.modules) do
        local def = Fittings:get(id)
        if def and slot <= moduleSlots then
            loadout:setModule(slot, def)
        elseif def then
            handBack(def)
        end
    end

    ShipFittingSystem:apply(entity)
    self:record(entity)
    return returned, lost
end

------------------------------------------------------------------------------
-- What the screens show
------------------------------------------------------------------------------

--- The stats the active ship's hull starts from, for the ship builder.
---@return table stats { maxHealth, maxShield, shieldRegen }
function PlayerFleet:stats()
    local hull = self.hullOf(self:active())
    if not hull then return { maxHealth = 700, maxShield = 160, shieldRegen = 6 } end
    return {
        maxHealth = hull.stats.maxHealth,
        maxShield = hull.stats.maxShield,
        shieldRegen = hull.stats.shieldRegen,
    }
end

--- How big the active ship's hull is.
---@param fallback number
---@return number
function PlayerFleet:scale(fallback)
    local hull = self.hullOf(self:active())
    return hull and hull.scale or fallback
end

--- How many module slots the active ship has.
---@return integer
function PlayerFleet:moduleSlots()
    local hull = self.hullOf(self:active())
    return hull and hull.moduleSlots or 0
end

--- A ship's fit in words, from the record (so a parked ship can be described
--- without an entity).
---@param ship PlayerShip|nil
---@return string
function PlayerFleet.describe(ship)
    if not ship then return "no ship" end
    local hull = PlayerFleet.hullOf(ship)
    local weapons, modules = 0, 0
    for _ in pairs(ship.weapons) do weapons = weapons + 1 end
    for _ in pairs(ship.modules) do modules = modules + 1 end
    local slots = hull and hull.moduleSlots or 0
    return string.format("%d gun%s, %d of %d module%s", weapons, weapons == 1 and "" or "s",
        modules, slots, slots == 1 and "" or "s")
end

return PlayerFleet
