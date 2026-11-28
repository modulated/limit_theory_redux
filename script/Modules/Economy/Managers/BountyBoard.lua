local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")

--- The stations' bounty board: named pirates in this system, with a price on
--- their heads and where they were last seen (Config.game.bounties).
---
--- An offer is posted for a pirate ship that is in the system now (an NPC
--- record); accepted, it becomes a contract. A contracted ship is tracked:
--- its signature shows on the maps and at the edge of the screen wherever it
--- is, in gold, even beyond sensor range (LimitTheoryRedux:mapNpcs). Killing
--- it -- the player or the player's own ships -- pays the reward on top of
--- the usual bounty. A contract whose ship is gone some other way (killed by
--- someone else, left the system) is void, and leaving the system ends them
--- all: the board is the system's.
---
--- Neither offers nor contracts are saved: the ships they name are not.
---@class BountyBoard
local BountyBoard = {
    offers = {},
    contracts = {},
}

local ADJECTIVES = { "Grim", "Rusty", "Silent", "Crooked", "Black", "Hollow", "Red", "Lucky",
    "Ragged", "Cold", "Sly", "Mad", "Iron", "Pale", "Wicked", "Lame" }
local NOUNS = { "Kestrel", "Jackal", "Magpie", "Viper", "Hound", "Crow", "Moth", "Lamprey",
    "Shrike", "Weasel", "Gull", "Stoat", "Pike", "Wasp", "Rook", "Eel" }

---@return table
local function cfg()
    return Config.game.bounties
end

--- A new game, a jump: an empty board.
function BountyBoard:reset()
    self.offers = {}
    self.contracts = {}
end

--- A pirate's callsign, the same for the same ship.
---@param record table
---@return string
local function callsign(record)
    local n = math.floor(math.abs(tonumber(record.entity.id) or 0)) % 1000003
    return ADJECTIVES[n % #ADJECTIVES + 1] .. " " .. NOUNS[math.floor(n / #ADJECTIVES) % #NOUNS + 1]
end

---@param record table
---@return boolean
local function listed(self, record)
    for _, o in ipairs(self.offers) do if o.record == record then return true end end
    for _, c in ipairs(self.contracts) do if c.record == record then return true end end
    return false
end

--- Bring the board up to `maxOffers` with pirates in the system now, and
--- drop offers whose ship is gone.
---@param game table LimitTheoryRedux
function BountyBoard:refresh(game)
    for i = #self.offers, 1, -1 do
        local r = self.offers[i].record
        if r.dead or r.removed then table.remove(self.offers, i) end
    end
    if not game.npcs then return end
    local rewards = Config.game.economy.bounties or {}
    for _, record in ipairs(game.npcs.records or {}) do
        if #self.offers >= cfg().maxOffers then break end
        local stats = record.pilot and record.pilot.stats
        if record.faction == "pirate" and not record.dead and not record.removed
            and not record.unit and not listed(self, record) then
            local base = rewards[record.role] or Config.game.economy.defaultBounty or 250
            local n = math.floor(math.abs(tonumber(record.entity.id) or 0)) % 97
            self.offers[#self.offers + 1] = {
                record = record,
                callsign = callsign(record),
                kind = (stats and stats.label) or "Pirate",
                reward = math.floor((base * cfg().rewardMultiplier + n * 10) / 50 + 0.5) * 50,
                area = game:lastSeenArea(record),
            }
        end
    end
end

--- Take an offer on.
---@param offer table
---@return boolean, string|nil reason
function BountyBoard:accept(offer)
    if #self.contracts >= cfg().maxContracts then return false, "you have as many contracts as you can work" end
    for i, o in ipairs(self.offers) do
        if o == offer then
            table.remove(self.offers, i)
            self.contracts[#self.contracts + 1] = offer
            -- Named in space once identified (NpcSystem adds what it is doing)
            offer.originalLabel = offer.record.label
            offer.record.label = string.format("BOUNTY '%s'", offer.callsign)
            return true
        end
    end
    return false, "the offer is gone"
end

--- Give a contract up.
---@param contract table
function BountyBoard:abandon(contract)
    for i, c in ipairs(self.contracts) do
        if c == contract then
            table.remove(self.contracts, i)
            if contract.originalLabel then contract.record.label = contract.originalLabel end
            return
        end
    end
end

--- The contract on a ship, or nil.
---@param record table|nil
---@return table|nil
function BountyBoard:contractOn(record)
    if not record then return nil end
    for _, c in ipairs(self.contracts) do
        if c.record == record then return c end
    end
    return nil
end

--- A contracted ship was killed by the player or their ships: pay.
---@param record table
---@return table|nil contract
function BountyBoard:claim(record)
    local contract = self:contractOn(record)
    if not contract then return nil end
    self:abandon(contract)
    PlayerWallet:add(contract.reward, "Bounty contract: " .. contract.callsign)
    return contract
end

--- Contracts whose ship is gone without the player's hand in it: void.
--- Returns their callsigns, to say so.
---@return string[]
function BountyBoard:voidGone()
    local gone = {}
    for i = #self.contracts, 1, -1 do
        local c = self.contracts[i]
        if c.record.removed or c.record.dead then
            table.remove(self.contracts, i)
            gone[#gone + 1] = c.callsign
        end
    end
    return gone
end

return BountyBoard
