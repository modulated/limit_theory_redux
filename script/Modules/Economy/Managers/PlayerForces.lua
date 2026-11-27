local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")

--- The ships that work for the player: combat drones launched from an
--- outpost's hangar, and mercenaries hired at one. Each belongs to a star
--- system and has a home outpost, and either guards it or patrols every one
--- of the player's outposts in the system.
---
--- These are records, not entities, like the outposts: a unit is flown (an
--- NPC gunship of the player's side, LimitTheoryRedux:spawnPlayerForces) only
--- while the player is in its system, and built again from here when they
--- come back. Its hull and shields are written back here as it flies, so a
--- battered drone stays battered across a jump or a save.
---
--- A drone costs nothing to keep: it was hard enough to build. A mercenary
--- costs a fee to hire and a wage for every hour of game time, wherever the
--- player is; one whose wage cannot be paid leaves.
---@class PlayerForces
local PlayerForces = {
    ---@type table<integer, PlayerUnit>
    units = {},
    nextId = 1,
    -- Game time up to which wages have been paid
    paidUntil = 0,
}

---@class PlayerUnit
---@field id integer
---@field kind string "drone" or "mercenary"
---@field name string
---@field systemId integer
---@field homeKey string the outpost's key ("p:<id>")
---@field order string "guard" or "patrol"
---@field hull number|nil the hull as last seen (nil: full)
---@field shield number|nil

PlayerForces.Kind = { Drone = "drone", Mercenary = "mercenary" }
PlayerForces.Order = { Guard = "guard", Patrol = "patrol" }

---@return table Config.game.forces
local function cfg()
    return Config.game.forces
end

--- A new game: nobody.
function PlayerForces:reset()
    self.units = {}
    self.nextId = 1
    self.paidUntil = 0
    self.owed = 0
end

---@param id integer
---@return PlayerUnit|nil
function PlayerForces:get(id)
    return self.units[id]
end

--- Units of one system, by id.
---@param systemId integer
---@return PlayerUnit[]
function PlayerForces:inSystem(systemId)
    local list = {}
    for _, unit in pairs(self.units) do
        if unit.systemId == systemId then list[#list + 1] = unit end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

--- Units whose home is one outpost.
---@param key string
---@return PlayerUnit[]
function PlayerForces:homedAt(key)
    local list = {}
    for _, unit in pairs(self.units) do
        if unit.homeKey == key then list[#list + 1] = unit end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

--- How many more units an outpost may be home to.
---@param key string
---@return integer
function PlayerForces:room(key)
    return math.max(0, cfg().maxPerOutpost - #self:homedAt(key))
end

--- The mercenaries' wages per game hour, all told.
---@return number
function PlayerForces:wageBill()
    local n = 0
    for _, unit in pairs(self.units) do
        if unit.kind == PlayerForces.Kind.Mercenary then n = n + 1 end
    end
    return n * cfg().mercenary.wagePerHour
end

---@param kind string
---@param systemId integer
---@param homeKey string
---@return PlayerUnit
local function newUnit(self, kind, systemId, homeKey)
    local id = self.nextId
    self.nextId = id + 1
    local label = kind == PlayerForces.Kind.Drone and "Drone" or "Mercenary"
    local unit = {
        id = id, kind = kind, name = string.format("%s %d", label, id),
        systemId = systemId, homeKey = homeKey, order = PlayerForces.Order.Guard,
    }
    self.units[id] = unit
    return unit
end

--- Launch a drone at an outpost. The caller has taken the drone item out of
--- the hangar.
---@param systemId integer
---@param homeKey string
---@return PlayerUnit|nil unit, string|nil reason
function PlayerForces:launchDrone(systemId, homeKey)
    if self:room(homeKey) < 1 then return nil, "this outpost has all the ships it can berth" end
    return newUnit(self, PlayerForces.Kind.Drone, systemId, homeKey)
end

--- Hire a mercenary at an outpost: the fee now, the wage from now on.
---@param systemId integer
---@param homeKey string
---@param now number game time
---@return PlayerUnit|nil unit, string|nil reason
function PlayerForces:hireMercenary(systemId, homeKey, now)
    if self:room(homeKey) < 1 then return nil, "this outpost has all the ships it can berth" end
    local fee = cfg().mercenary.hireCost
    if not PlayerWallet:remove(fee, "Mercenary hired") then
        return nil, "not enough credits for the fee"
    end
    -- Wages run from now: settle what is owed before the bill grows
    if self.paidUntil < now then self:payWages(now) end
    return newUnit(self, PlayerForces.Kind.Mercenary, systemId, homeKey)
end

--- Take a unit off the books (dismissed, recalled, or destroyed).
---@param id integer
function PlayerForces:remove(id)
    self.units[id] = nil
end

---@param id integer
---@param order string
function PlayerForces:setOrder(id, order)
    local unit = self.units[id]
    if unit and (order == PlayerForces.Order.Guard or order == PlayerForces.Order.Patrol) then
        unit.order = order
    end
end

--- Pay the mercenaries for the game time since the last pay, and send away
--- those it cannot pay (the most recently hired first). Returns what to tell
--- the player and the ids that left.
---@param now number game time (seconds)
---@return table[] events { text }, integer[] left
function PlayerForces:payWages(now)
    local events, left = {}, {}
    local elapsed = now - (self.paidUntil or 0)
    if elapsed <= 0 then
        self.paidUntil = now
        return events, left
    end
    self.paidUntil = now
    local perUnit = cfg().mercenary.wagePerHour * elapsed / 3600
    local mercs = {}
    for _, unit in pairs(self.units) do
        if unit.kind == PlayerForces.Kind.Mercenary then mercs[#mercs + 1] = unit end
    end
    if #mercs == 0 or perUnit <= 0 then return events, left end
    table.sort(mercs, function(a, b) return a.id < b.id end)
    -- Whole credits: the fraction rides on to the next payday
    self.owed = (self.owed or 0) + perUnit * #mercs
    local due = math.floor(self.owed)
    if due <= 0 then return events, left end
    if PlayerWallet:remove(due, "Mercenary wages") then
        self.owed = self.owed - due
        return events, left
    end
    -- Not enough: pay who can be paid, the longest-serving first
    local each = self.owed / #mercs
    for _, unit in ipairs(mercs) do
        if not PlayerWallet:remove(math.ceil(each), "Mercenary wages") then
            self.units[unit.id] = nil
            left[#left + 1] = unit.id
            events[#events + 1] = { text = string.format("%s left your service: their wages went unpaid.", unit.name) }
        end
    end
    self.owed = 0
    return events, left
end

------------------------------------------------------------------------------
-- Saving
------------------------------------------------------------------------------

---@return table
function PlayerForces:snapshot()
    local units = {}
    for _, unit in pairs(self.units) do
        units[#units + 1] = {
            id = unit.id, kind = unit.kind, name = unit.name, systemId = unit.systemId,
            homeKey = unit.homeKey, order = unit.order, hull = unit.hull, shield = unit.shield,
        }
    end
    table.sort(units, function(a, b) return a.id < b.id end)
    return { units = units, nextId = self.nextId, paidUntil = self.paidUntil, owed = self.owed }
end

---@param saved table|nil
function PlayerForces:restore(saved)
    self:reset()
    if not saved then return end
    for _, unit in ipairs(saved.units or {}) do
        if unit.kind == PlayerForces.Kind.Drone or unit.kind == PlayerForces.Kind.Mercenary then
            self.units[unit.id] = unit
        end
    end
    self.nextId = math.max(saved.nextId or 1, 1)
    self.paidUntil = saved.paidUntil or 0
    self.owed = saved.owed or 0
end

return PlayerForces
