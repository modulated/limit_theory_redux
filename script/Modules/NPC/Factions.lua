--- Factions: who is hostile to whom. A faction is also the ship's Targetable
--- team, so the weapon batteries use the same names (a battery engages the
--- teams its faction is hostile to; see WeaponBattery's `hostileTeams`).
---
--- The relations and colours are in Config.game.factions.
---@class Factions
local Factions = {
    Player = "player",
    Security = "security",
    Trader = "trader",
    Pirate = "pirate",
}

---@param faction string
---@return table config Config.game.factions[faction] (empty when unknown)
local function config(faction)
    return Config.game.factions[faction] or {}
end

--- Whether ships of faction `a` attack ships of faction `b`. Between the
--- player and a faction it is the player's standing with that faction
--- (Reputation); between NPC factions, Config.game.factions.
---@param a string
---@param b string
---@return boolean
function Factions.isHostile(a, b)
    if a == b then return false end
    if a == Factions.Player then return Factions.reputation():isHostile(b) end
    if b == Factions.Player then return Factions.reputation():isHostile(a) end
    local hostile = config(a).hostileTo
    return hostile ~= nil and hostile[b] == true
end

--- The teams a faction's weapons engage, as a list.
---@param faction string
---@return string[]
function Factions.hostileTeams(faction)
    local teams = {}
    for team in pairs(Config.game.factions) do
        if Factions.isHostile(faction, team) then teams[#teams + 1] = team end
    end
    table.sort(teams)
    return teams
end

--- Reputation, required late (it requires Factions).
function Factions.reputation()
    return require("Modules.NPC.Reputation")
end

---@param faction string
---@return string
function Factions.name(faction)
    return config(faction).name or faction
end

---@param faction string
---@return number r, number g, number b
function Factions.color(faction)
    local c = config(faction).color or { 0.8, 0.8, 0.8 }
    return c[1], c[2], c[3]
end

return Factions
