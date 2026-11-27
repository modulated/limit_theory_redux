local Fittings = require("Shared.Registries.Fittings")
local FittingDefinition = require("Shared.Types.FittingDefinition")
local ConstructComponents = require("Modules.Constructs.Components")
local CoreComponents = require("Modules.Core.Components")

--- Fitting a ship out: taking a weapon or a module out of a hangar and
--- bolting it on, taking it off again, and working out what the ship is
--- after.
---
--- The rules:
---  * A fitting is an item. Fitting takes one unit out of the store it comes
---    from; unfitting puts one back. Nothing is created.
---  * A weapon goes in a mount of its size class or bigger (a railgun does
---    not fit a medium mount; a pulse turret in a large one is a waste but
---    allowed). The mount's turret then resolves that weapon every frame, so
---    the gun *is* what was fitted.
---  * A module goes in any free slot; the hull decides how many there are.
---  * `apply` works the stats out from the hull's base and the fit, every
---    time either changes: `add` effects summed, `scale` effects multiplied,
---    then written to the ship's components. Nothing else writes those, so a
---    refit can be undone exactly.
---@class ShipFittingSystem
local ShipFittingSystem = {}

local Stat = FittingDefinition.Stat

--- How big a mount is, in order, so a weapon can be put in anything at least
--- as large.
local SIZE_ORDER = { sm = 1, m = 2, l = 3, xl = 4 }

--- The base stats a ship starts from, before anything is fitted. Kept on the
--- loadout the first time `apply` runs, so taking a module off puts the ship
--- back exactly where it was.
---@param ship Entity
---@param loadout LoadoutComponent
---@return table
local function baseStats(ship, loadout)
    if loadout.base then return loadout.base end
    local defense = ship:get(ConstructComponents.Defense)
    local health = ship:get(CoreComponents.Health)
    loadout.base = {
        maxShield = defense and defense:getMaxShield() or 0,
        shieldRegen = defense and defense:getShieldRegen() or 0,
        armor = defense and defense:getArmor() or 0,
        maxHealth = health and health:getMaxHealth() or 0,
        cargoMass = loadout.baseCargoMass or 0,
    }
    return loadout.base
end

--- What the hull and everything on it come to.
---@param ship Entity
---@return table stats
function ShipFittingSystem:computeStats(ship)
    local loadout = ship:get(ConstructComponents.Loadout)
    if not loadout then return {} end
    local base = baseStats(ship, loadout)

    local stats = {
        [Stat.MaxShield] = base.maxShield,
        [Stat.ShieldRegen] = base.shieldRegen,
        [Stat.Armor] = base.armor,
        [Stat.MaxHealth] = base.maxHealth,
        [Stat.CargoMass] = base.cargoMass,
        [Stat.Thrust] = 1,
        [Stat.Turn] = 1,
        [Stat.ScanRange] = 1,
        [Stat.MiningRate] = 1,
        -- The books a trader can read from here: the configured reach, which
        -- a datalink module adds to
        [Stat.MarketReach] = Config.game.market and Config.game.market.remoteJumps or 0,
        -- Hunting: how far off signatures show, and how closely they are placed
        [Stat.SignatureRange] = 1,
        [Stat.SignatureAccuracy] = 1,
    }

    -- Every fitting's adds first, then every scale, so the order modules were
    -- fitted in cannot change the answer
    local fitted = loadout:listAll()
    for _, def in ipairs(fitted) do
        for stat, value in pairs(def.effects and def.effects.add or {}) do
            stats[stat] = (stats[stat] or 0) + value
        end
    end
    for _, def in ipairs(fitted) do
        for stat, value in pairs(def.effects and def.effects.scale or {}) do
            stats[stat] = (stats[stat] or 1) * value
        end
    end
    return stats
end

--- Work the fit out and write it to the ship. Call it after any change to
--- the loadout.
---@param ship Entity
---@return table stats
function ShipFittingSystem:apply(ship)
    local loadout = ship:get(ConstructComponents.Loadout)
    if not loadout then return {} end
    local stats = self:computeStats(ship)
    loadout:setStats(stats)

    -- Shields, armour and hull
    local defense = ship:get(ConstructComponents.Defense)
    if defense then
        local maxShield = math.max(0, math.floor(stats[Stat.MaxShield] + 0.5))
        defense:setMaxShield(maxShield)
        defense:setShieldRegen(stats[Stat.ShieldRegen])
        defense:setArmor(stats[Stat.Armor])
    end
    local health = ship:get(CoreComponents.Health)
    if health then
        health:setMaxHealth(math.max(1, math.floor(stats[Stat.MaxHealth] + 0.5)))
    end

    -- Handling: the flight system reads these scales
    local flight = ship:get(ConstructComponents.ShipFlightControl)
    if flight then
        flight.fitThrustScale = stats[Stat.Thrust]
        flight.fitTurnScale = stats[Stat.Turn]
    end

    -- The guns: each mount's turret resolves whatever is fitted
    for _, mount in ipairs(self:mounts(ship)) do
        local def = loadout:getWeapon(mount.mountId)
        if def and def.weaponId then
            mount.turret.weaponId = def.weaponId
            mount.turret.weaponRef = nil
        end
    end
    return stats
end

--- The ship's weapon mounts: `{ mountId, sizeClass, turret }` each, in a
--- stable order.
---@param ship Entity
---@return table[]
function ShipFittingSystem:mounts(ship)
    local rows = {}
    local handle = ship.turretHandles or ship.turrets
    for _, turret in ipairs(handle or {}) do
        local component = turret.component or turret
        if component and component.getMountId then
            rows[#rows + 1] = {
                mountId = component:getMountId(),
                sizeClass = component.mountSizeClass,
                turret = component,
            }
        end
    end
    table.sort(rows, function(a, b) return a.mountId < b.mountId end)
    return rows
end

--- Tell the system where a ship's mounts live (the armed-ship builder knows;
--- the ship entity does not).
---@param ship Entity
---@param turrets table[] the builder's turret records ({ component = ..., mountId = ... })
function ShipFittingSystem:setMounts(ship, turrets)
    ship.turretHandles = turrets
end

--- Whether a weapon can go in a mount: its size class or larger.
---@param def FittingDefinition
---@param sizeClass string|nil
---@return boolean
function ShipFittingSystem:weaponFits(def, sizeClass)
    if not def or not def:isWeapon() then return false end
    if not sizeClass or not def.sizeClass then return true end
    return (SIZE_ORDER[sizeClass] or 0) >= (SIZE_ORDER[def.sizeClass] or 0)
end

--- Fit a weapon into a mount, out of `store`. Whatever was there goes back
--- into the store.
---@param ship Entity
---@param store StockComponent where the goods come from and go back to
---@param mountId string
---@param def FittingDefinition
---@return boolean fitted, string|nil reason
function ShipFittingSystem:fitWeapon(ship, store, mountId, def)
    local loadout = ship:get(ConstructComponents.Loadout)
    if not loadout then return false, "this ship cannot be refitted" end
    local mount
    for _, candidate in ipairs(self:mounts(ship)) do
        if candidate.mountId == mountId then mount = candidate end
    end
    if not mount then return false, "no such mount" end
    if not self:weaponFits(def, mount.sizeClass) then
        return false, string.format("a %s mount will not take it", tostring(mount.sizeClass))
    end
    if not store or store:count(def.itemId) < 1 then return false, "none in the hangar" end
    if store:remove(def.itemId, 1) < 1 then return false, "none in the hangar" end

    local previous = loadout:getWeapon(mountId)
    loadout:setWeapon(mountId, def)
    if previous then store:add(previous.itemId, 1) end
    self:apply(ship)
    return true
end

--- Take the weapon out of a mount, into `store`. A mount with nothing in it
--- keeps the gun it was built with, so the ship is never unarmed by a refit.
---@param ship Entity
---@param store StockComponent
---@param mountId string
---@return boolean removed, string|nil reason
function ShipFittingSystem:unfitWeapon(ship, store, mountId)
    local loadout = ship:get(ConstructComponents.Loadout)
    local def = loadout and loadout:getWeapon(mountId)
    if not def then return false, "nothing fitted there" end
    loadout:setWeapon(mountId, nil)
    if store then store:add(def.itemId, 1) end
    self:apply(ship)
    return true
end

--- Fit a module into a slot, out of `store`.
---@param ship Entity
---@param store StockComponent
---@param slot integer
---@param def FittingDefinition
---@return boolean fitted, string|nil reason
function ShipFittingSystem:fitModule(ship, store, slot, def)
    local loadout = ship:get(ConstructComponents.Loadout)
    if not loadout then return false, "this ship cannot be refitted" end
    if def:isWeapon() then return false, "that goes in a weapon mount" end
    if slot < 1 or slot > loadout:getModuleSlots() then return false, "no such slot" end
    if not store or store:count(def.itemId) < 1 then return false, "none in the hangar" end
    if store:remove(def.itemId, 1) < 1 then return false, "none in the hangar" end

    local previous = loadout:getModule(slot)
    loadout:setModule(slot, def)
    if previous then store:add(previous.itemId, 1) end
    self:apply(ship)
    return true
end

--- Take a module out of a slot, into `store`.
---@param ship Entity
---@param store StockComponent
---@param slot integer
---@return boolean removed, string|nil reason
function ShipFittingSystem:unfitModule(ship, store, slot)
    local loadout = ship:get(ConstructComponents.Loadout)
    local def = loadout and loadout:getModule(slot)
    if not def then return false, "nothing fitted there" end
    loadout:setModule(slot, nil)
    if store then store:add(def.itemId, 1) end
    self:apply(ship)
    return true
end

--- Everything in `store` that could be fitted somewhere on this ship, for
--- the refit screen: `{ fitting, units, fitsHere }`.
---@param ship Entity
---@param store StockComponent
---@return table[]
function ShipFittingSystem:fittableFrom(ship, store)
    local rows = {}
    if not store then return rows end
    for _, row in ipairs(store:list()) do
        local def = Fittings:forItem(row.item.id)
        if def then
            rows[#rows + 1] = { fitting = def, units = row.units }
        end
    end
    table.sort(rows, function(a, b)
        if a.fitting.slot ~= b.fitting.slot then return a.fitting.slot < b.fitting.slot end
        return a.fitting.id < b.fitting.id
    end)
    return rows
end

--- Put everything on the ship back into a store (changing hulls).
---@param ship Entity
---@param store StockComponent
---@return integer stripped how many fittings came off
function ShipFittingSystem:strip(ship, store)
    local loadout = ship:get(ConstructComponents.Loadout)
    if not loadout then return 0 end
    local count = 0
    for _, mount in ipairs(self:mounts(ship)) do
        if self:unfitWeapon(ship, store, mount.mountId) then count = count + 1 end
    end
    for slot = 1, loadout:getModuleSlots() do
        if self:unfitModule(ship, store, slot) then count = count + 1 end
    end
    return count
end

return ShipFittingSystem
