--- Who hit whom: every hit the weapons land, reported where the damage is
--- applied (ProjectileSystem, BeamSystem) through the firing battery
--- (WeaponBattery:reportDamage). It is the record credit and blame come
--- from: the shooter of each hit, and the shooter of the killing blow (the
--- hit that took the target's hull from above zero to zero), exactly.
---
--- Listeners: `onHit(fn)` for every hit, `onKill(fn)` for killing blows,
--- called with an event table:
---   { attacker = Entity (the firing ship), attackerTeam = string|nil,
---     target = Entity, damage = number (before shields),
---     hullDamage = number (what got through), killed = boolean,
---     mountId = string|nil (the mount that fired), weapon = string|nil
---     (its weapon's name) }
---@class CombatLog
local CombatLog = {
    hitListeners = {},
    killListeners = {},
    -- target -> the ship that hit it last (weak: entities come and go)
    lastAttacker = setmetatable({}, { __mode = "k" }),
}

---@param fn fun(event: table)
function CombatLog:onHit(fn)
    table.insert(self.hitListeners, fn)
end

---@param fn fun(event: table)
function CombatLog:onKill(fn)
    table.insert(self.killListeners, fn)
end

--- A hit landed.
---@param attacker Entity|nil the firing ship
---@param attackerTeam string|nil
---@param target Entity
---@param damage number before shields
---@param hullDamage number after shields
---@param killed boolean this hit destroyed the target
---@param mountId string|nil the mount that fired
---@param weapon string|nil the name of its weapon
function CombatLog:report(attacker, attackerTeam, target, damage, hullDamage, killed, mountId, weapon)
    if not target then return end
    self.lastAttacker[target] = attacker
    local event = {
        attacker = attacker,
        attackerTeam = attackerTeam,
        target = target,
        damage = damage,
        hullDamage = hullDamage,
        killed = killed,
        mountId = mountId,
        weapon = weapon,
    }
    for _, fn in ipairs(self.hitListeners) do fn(event) end
    if killed then
        for _, fn in ipairs(self.killListeners) do fn(event) end
    end
end

--- The ship that hit `target` last, or nil.
---@param target Entity
---@return Entity|nil
function CombatLog:getLastAttacker(target)
    return self.lastAttacker[target]
end

return CombatLog
