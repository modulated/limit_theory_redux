local Factions = require("Modules.NPC.Factions")

--- The player's standing with each faction (the port of Legacy's
--- Dispositions, Elements/NPC/Dispositions.lua): -1 is maximal hostility, 0
--- neutral, +1 maximal friendliness, on the same scale and thresholds as
--- Legacy (Config.game.dispoHostileThreshold / dispoFriendlyThreshold).
---
--- It decides who fights the player: a faction whose standing is below the
--- hostile threshold attacks the player's ship, and the player's turrets
--- engage it (Factions.isHostile asks here for anything involving the
--- player). Standing moves with what the player does: destroying a ship of
--- a faction lowers the standing with that faction and raises it with the
--- factions that are its enemies. Docking needs a standing that isn't
--- hostile.
---
--- One standing table per game: `reset` on a new game.
---@class Reputation
local Reputation = {
    standing = {},
    listeners = {},
}

--- Standings back to Config.game.reputation.initial.
function Reputation:reset()
    self.standing = {}
    for faction, value in pairs(Config.game.reputation.initial) do
        self.standing[faction] = value
    end
end

---@param faction string
---@return number standing -1..1
function Reputation:get(faction)
    return self.standing[faction] or Config.game.dispoNeutral
end

---@param faction string
---@return boolean
function Reputation:isHostile(faction)
    return self:get(faction) < Config.game.dispoHostileThreshold
end

---@param faction string
---@return boolean
function Reputation:isFriendly(faction)
    return self:get(faction) >= Config.game.dispoFriendlyThreshold
end

--- "hostile", "neutral" or "friendly" (Config.game.dispoName).
---@param faction string
---@return string
function Reputation:describe(faction)
    local names = Config.game.dispoName
    if self:isHostile(faction) then return names[1] end
    if self:isFriendly(faction) then return names[3] end
    return names[2]
end

--- Called with (faction, old, new) whenever a standing changes.
---@param fn fun(faction: string, old: number, new: number)
function Reputation:onChange(fn)
    table.insert(self.listeners, fn)
end

--- Change a standing by `amount`, clamped to Config.game.dispoMin..dispoMax.
---@param faction string
---@param amount number
function Reputation:modify(faction, amount)
    if faction == Factions.Player then return end
    local old = self:get(faction)
    local new = math.min(math.max(old + amount, Config.game.dispoMin), Config.game.dispoMax)
    if new == old then return end
    self.standing[faction] = new
    for _, fn in ipairs(self.listeners) do fn(faction, old, new) end
end

--- The player destroyed a ship of `faction`: that faction likes the player
--- less, its enemies more.
---@param faction string
function Reputation:playerDestroyed(faction)
    local cfg = Config.game.reputation
    self:modify(faction, -cfg.killPenalty)
    for other, relation in pairs(Config.game.factions) do
        if other ~= faction and other ~= Factions.Player and relation.hostileTo
            and relation.hostileTo[faction] then
            self:modify(other, cfg.enemyKillBonus)
        end
    end
end

--- The player damaged a ship of `faction` (per hit).
---@param faction string
function Reputation:playerDamaged(faction)
    self:modify(faction, -Config.game.reputation.damagePenalty)
end

Reputation:reset()
return Reputation
