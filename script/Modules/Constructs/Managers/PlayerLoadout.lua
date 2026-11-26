local Fittings = require("Shared.Registries.Fittings")
local ConstructComponents = require("Modules.Constructs.Components")
local ShipFittingSystem = require("Modules.Constructs.Systems.ShipFittingSystem")

--- What the player's ship is fitted with, kept across the ship being rebuilt.
---
--- The ship entity is destroyed and built again on undocking, on a jump and
--- on a respawn, so the fit cannot live on it alone -- like the hold
--- (`PlayerCargo`) and the credits (`PlayerWallet`), it is the player's, not
--- the hull's. This holds the record; `ShipFittingSystem` does the work, and
--- `restore` writes the record onto a freshly built ship.
---
--- Mount ids come from the hull's recipe and are the same every time the same
--- hull is built, so a weapon fitted to "fore-outer-left" goes back there.
---@class PlayerLoadout
local PlayerLoadout = {
    ---@type table<string, integer> mount id -> fitting id
    weapons = {},
    ---@type table<integer, integer> slot -> fitting id
    modules = {},
    moduleSlots = 0,
}

--- A new game: whatever the starting hull comes with.
---@param moduleSlots integer|nil
function PlayerLoadout:reset(moduleSlots)
    self.weapons = {}
    self.modules = {}
    self.moduleSlots = moduleSlots or 0
end

---@param count integer
function PlayerLoadout:setModuleSlots(count)
    self.moduleSlots = math.max(0, math.floor(count or 0))
    for slot in pairs(self.modules) do
        if slot > self.moduleSlots then self.modules[slot] = nil end
    end
end

--- Give the player a fitting without buying it (what a new game's ship comes
--- with). Returns false when there is nowhere to put it.
---@param def FittingDefinition
---@param slot integer|nil for a module; the first free slot otherwise
---@return boolean
function PlayerLoadout:grantModule(def, slot)
    if not def or def:isWeapon() then return false end
    if not slot then
        for candidate = 1, self.moduleSlots do
            if not self.modules[candidate] then
                slot = candidate
                break
            end
        end
    end
    if not slot or slot < 1 or slot > self.moduleSlots then return false end
    self.modules[slot] = def.id
    return true
end

--- Note what the ship is fitted with now, so the next hull gets the same.
---@param ship Entity
function PlayerLoadout:record(ship)
    local loadout = ship and ship:get(ConstructComponents.Loadout)
    if not loadout then return end
    self.weapons = {}
    for mountId, id in pairs(loadout.weapons) do self.weapons[mountId] = id end
    self.modules = {}
    for slot, id in pairs(loadout.modules) do self.modules[slot] = id end
    self.moduleSlots = loadout:getModuleSlots()
end

--- Put the record onto a ship that has just been built, and work the stats
--- out. Anything the new hull has no room for is handed back, so a smaller
--- hull does not swallow a module.
---@param ship Entity
---@param turrets table[] the builder's turret records
---@param moduleSlots integer the hull's module slots
---@param spare StockComponent|nil where fittings with nowhere to go are put
---@return integer returned how many fittings were handed back
function PlayerLoadout:restore(ship, turrets, moduleSlots, spare)
    if not ship then return 0 end
    local loadout = ship:get(ConstructComponents.Loadout)
    if not loadout then
        loadout = ship:add(ConstructComponents.Loadout(moduleSlots))
    end
    loadout:setModuleSlots(moduleSlots)
    ShipFittingSystem:setMounts(ship, turrets)

    local returned = 0
    local mounts = {}
    for _, mount in ipairs(ShipFittingSystem:mounts(ship)) do
        mounts[mount.mountId] = mount
    end

    for mountId, id in pairs(self.weapons) do
        local def = Fittings:get(id)
        local mount = mounts[mountId]
        if def and mount and ShipFittingSystem:weaponFits(def, mount.sizeClass) then
            loadout:setWeapon(mountId, def)
        elseif def then
            if spare then spare:add(def.itemId, 1) end
            returned = returned + 1
        end
    end
    for slot, id in pairs(self.modules) do
        local def = Fittings:get(id)
        if def and slot <= moduleSlots then
            loadout:setModule(slot, def)
        elseif def then
            if spare then spare:add(def.itemId, 1) end
            returned = returned + 1
        end
    end

    ShipFittingSystem:apply(ship)
    self:record(ship)
    return returned
end

--- The fit in words, for the HUD and the refit screen.
---@param ship Entity
---@return string
function PlayerLoadout:describe(ship)
    local loadout = ship and ship:get(ConstructComponents.Loadout)
    if not loadout then return "no fit" end
    local weapons, modules = 0, 0
    for _ in pairs(loadout.weapons) do weapons = weapons + 1 end
    for _ in pairs(loadout.modules) do modules = modules + 1 end
    return string.format("%d gun%s, %d of %d module%s", weapons, weapons == 1 and "" or "s",
        modules, loadout:getModuleSlots(), loadout:getModuleSlots() == 1 and "" or "s")
end

return PlayerLoadout
