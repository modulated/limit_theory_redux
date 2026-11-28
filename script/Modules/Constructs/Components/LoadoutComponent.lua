local Component = require("Core.ECS.Component")
local Fittings = require("Shared.Registries.Fittings")

--- What a ship is fitted with: a weapon in each of its mounts and a module in
--- each of its slots, by fitting id (`Shared/Registries/Fittings.lua`).
---
--- The component is only the record. Taking the goods out of a hangar, seeing
--- that a weapon fits the mount, and working the stats out of the fit are
--- `Modules/Constructs/Systems/ShipFittingSystem.lua`.
---@class LoadoutComponent: Component
---@overload fun(self: LoadoutComponent, moduleSlots: integer|nil): LoadoutComponent subclass internal
---@overload fun(moduleSlots: integer|nil): LoadoutComponent subclass external
local LoadoutComponent = Subclass("LoadoutComponent", Component, function(self, moduleSlots)
    self:setComponentName("ConstructLoadout")
    --- mount id -> fitting id
    self.weapons = {}
    --- slot number (1..moduleSlots) -> fitting id
    self.modules = {}
    self.moduleSlots = moduleSlots or 0
    --- The stats the fit comes to, worked out by ShipFittingSystem:apply.
    self.stats = {}
end)

---@param count integer how many module slots the hull has
function LoadoutComponent:setModuleSlots(count)
    self.moduleSlots = math.max(0, math.floor(count or 0))
    for slot in pairs(self.modules) do
        if slot > self.moduleSlots then self.modules[slot] = nil end
    end
end

---@return integer
function LoadoutComponent:getModuleSlots()
    return self.moduleSlots
end

--- The fitting in a module slot.
---@param slot integer
---@return FittingDefinition|nil
function LoadoutComponent:getModule(slot)
    local id = self.modules[slot]
    return id and Fittings:get(id) or nil
end

---@param slot integer
---@param def FittingDefinition|nil nil to empty the slot
function LoadoutComponent:setModule(slot, def)
    if slot < 1 or slot > self.moduleSlots then return end
    self.modules[slot] = def and def.id or nil
end

--- The weapon in a mount.
---@param mountId string
---@return FittingDefinition|nil
function LoadoutComponent:getWeapon(mountId)
    local id = self.weapons[mountId]
    return id and Fittings:get(id) or nil
end

---@param mountId string
---@param def FittingDefinition|nil nil to strip the mount
function LoadoutComponent:setWeapon(mountId, def)
    self.weapons[mountId] = def and def.id or nil
end

--- Every module fitted, slot order.
---@return table[] rows { slot, fitting }
function LoadoutComponent:listModules()
    local rows = {}
    for slot = 1, self.moduleSlots do
        local def = self:getModule(slot)
        if def then rows[#rows + 1] = { slot = slot, fitting = def } end
    end
    return rows
end

--- Every fitting on the ship, weapons and modules both: what would go back
--- to the hangar if the ship were stripped.
---@return FittingDefinition[]
function LoadoutComponent:listAll()
    local all = {}
    for _, id in pairs(self.weapons) do
        local def = Fittings:get(id)
        if def then all[#all + 1] = def end
    end
    for _, row in ipairs(self:listModules()) do all[#all + 1] = row.fitting end
    return all
end

--- The modules that do something on command, with their slot.
---@return table[] rows { slot, fitting }
function LoadoutComponent:listAbilities()
    local rows = {}
    for _, row in ipairs(self:listModules()) do
        if row.fitting:isActive() then rows[#rows + 1] = row end
    end
    return rows
end

--- Whether a module of this kind is fitted (one mining laser is enough).
---@param abilityKey string
---@return FittingDefinition|nil
function LoadoutComponent:findAbility(abilityKey)
    for _, row in ipairs(self:listAbilities()) do
        if row.fitting.ability.key == abilityKey then return row.fitting, row.slot end
    end
    return nil
end

--- A stat the fit came to, after `ShipFittingSystem:apply`.
---@param stat string
---@param fallback number|nil
---@return number
function LoadoutComponent:getStat(stat, fallback)
    local value = self.stats[stat]
    if value == nil then return fallback or 0 end
    return value
end

---@param stats table
function LoadoutComponent:setStats(stats)
    self.stats = stats or {}
end

return LoadoutComponent
