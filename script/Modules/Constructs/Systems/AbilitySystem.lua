local ConstructComponents = require("Modules.Constructs.Components")
local CoreComponents = require("Modules.Core.Components")

--- The modules that do something on command.
---
--- An active module (`FittingDefinition.ability`) is a key the player presses:
--- it fires, it goes on a cooldown, and some of them run for a while before
--- they do. The system holds the timers, not the modules, so a module taken
--- off and put back on is still cooling down -- the ship was refitted, the
--- part was not repaired.
---
--- What each one does lives in `HANDLERS` below, keyed by the ability's
--- `key`. A handler gets the ship, the fitting and the game state, and
--- returns true if it fired (false puts no cooldown on it: an ability that
--- could not do anything was not used).
---
--- Mining is not here: it is held down rather than triggered, so the state's
--- own mining loop reads the fitted laser directly.
---@class AbilitySystem
local AbilitySystem = {}

--- ability key -> { timer = seconds left of cooldown, active = seconds left of effect }
---@private
AbilitySystem.state = {}

--- A new game, or a new ship: nothing is cooling down.
function AbilitySystem:reset()
    self.state = {}
end

---@param key string
---@return table
local function slot(self, key)
    local entry = self.state[key]
    if not entry then
        entry = { timer = 0, active = 0 }
        self.state[key] = entry
    end
    return entry
end

------------------------------------------------------------------------------
-- What the abilities do
------------------------------------------------------------------------------

--- Each handler: fire the thing, and say whether it fired.
---@type table<string, fun(ship: Entity, fitting: FittingDefinition, game: table): boolean, string|nil>
local HANDLERS = {}

--- Shield booster: puts a share of the shield's maximum straight back.
HANDLERS.shieldBoost = function(ship, fitting, game)
    local defense = ship:get(ConstructComponents.Defense)
    if not defense then return false, "no shields to boost" end
    local maximum = defense:getMaxShield()
    local current = defense:getCurrentShield()
    if current >= maximum then return false, "the shield is already full" end
    local restored = math.min(maximum - current, maximum * (fitting.ability.magnitude or 0.5))
    defense:setCurrentShield(current + restored)
    game:notify(string.format("Shield booster: +%d shield", math.floor(restored)), { 0.6, 0.9, 1.0 })
    return true
end

--- Afterburner: a hard burn for a few seconds. The thrust multiplier is
--- written onto the flight control and taken off again when it runs out.
HANDLERS.afterburner = function(ship, fitting, game)
    local flight = ship:get(ConstructComponents.ShipFlightControl)
    if not flight then return false, "nothing to burn with" end
    flight.abilityThrustScale = fitting.ability.magnitude or 2.0
    game:notify(string.format("Afterburner: %gx thrust for %gs",
        flight.abilityThrustScale, fitting.ability.duration or 5), { 0.6, 0.9, 1.0 })
    return true
end

--- Hull repair pulse: welds back a share of the hull. The free counterpart
--- to paying a station for it.
HANDLERS.repairPulse = function(ship, fitting, game)
    local health = ship:get(CoreComponents.Health)
    if not health then return false, "no hull to weld" end
    local maximum = health:getMaxHealth()
    local current = health:getCurrentHealth()
    if current >= maximum then return false, "the hull needs no repair" end
    local repaired = math.min(maximum - current, maximum * (fitting.ability.magnitude or 0.2))
    health:setCurrentHealth(current + repaired)
    game:notify(string.format("Repair pulse: +%d hull", math.floor(repaired)), { 0.6, 0.9, 1.0 })
    return true
end

--- Survey scanner: reads the rock in reach, and says what is in it. It reads
--- further than the laser cuts, and what it reads stays known.
HANDLERS.surveyScan = function(ship, fitting, game)
    local reach = fitting.ability.magnitude or 2.5
    local info = game.mineableRock and game:mineableRock(true, reach) or nil
    if not info then return false, "nothing in scanner range" end
    local AsteroidOre = require("Shared.Helpers.AsteroidOre")
    if game.markSurveyed then game:markSurveyed(info) end
    game:notify(string.format("Survey: %s", AsteroidOre.describeEntity(info.entity)),
        { 0.5, 1.0, 0.7 })
    return true
end

------------------------------------------------------------------------------
-- Driving them
------------------------------------------------------------------------------

--- Fire an ability, if one is fitted for it and it is not cooling down.
---@param ship Entity
---@param abilityKey string
---@param game table the game state (for messages and for what it knows)
---@return boolean fired, string|nil reason
function AbilitySystem:trigger(ship, abilityKey, game)
    if not ship or not ship:isValid() then return false, "no ship" end
    local loadout = ship:get(ConstructComponents.Loadout)
    local fitting = loadout and loadout:findAbility(abilityKey)
    if not fitting then return false, "nothing fitted for that" end

    local entry = slot(self, abilityKey)
    if entry.timer > 0 then
        return false, string.format("%s: %.0fs", fitting.displayName, entry.timer)
    end
    local handler = HANDLERS[abilityKey]
    if not handler then return false, "that module does nothing yet" end

    local fired, reason = handler(ship, fitting, game)
    if not fired then return false, reason end
    entry.timer = fitting.ability.cooldown or 0
    entry.active = fitting.ability.duration or 0
    return true
end

--- Cooldowns tick down, and effects that run for a while end.
---@param ship Entity
---@param dt number
function AbilitySystem:update(ship, dt)
    for key, entry in pairs(self.state) do
        if entry.timer > 0 then entry.timer = math.max(0, entry.timer - dt) end
        if entry.active > 0 then
            entry.active = math.max(0, entry.active - dt)
            if entry.active == 0 then self:expire(ship, key) end
        end
    end
end

--- An effect that was running has run out.
---@param ship Entity
---@param abilityKey string
function AbilitySystem:expire(ship, abilityKey)
    if abilityKey == "afterburner" and ship and ship:isValid() then
        local flight = ship:get(ConstructComponents.ShipFlightControl)
        if flight then flight.abilityThrustScale = nil end
    end
end

--- What a module is doing now, for the HUD: `{ fitting, slot, ready,
--- cooldown, remaining, active }`, in slot order.
---@param ship Entity
---@return table[]
function AbilitySystem:status(ship)
    local rows = {}
    local loadout = ship and ship:isValid() and ship:get(ConstructComponents.Loadout)
    if not loadout then return rows end
    for _, row in ipairs(loadout:listAbilities()) do
        local key = row.fitting.ability.key
        local entry = self.state[key] or { timer = 0, active = 0 }
        rows[#rows + 1] = {
            fitting = row.fitting,
            slot = row.slot,
            key = key,
            cooldown = row.fitting.ability.cooldown or 0,
            remaining = entry.timer,
            active = entry.active,
            ready = entry.timer <= 0,
        }
    end
    return rows
end

return AbilitySystem
