local Component = require("Core.ECS.Component")

--- The hands a station has: the crew that lives there, plus the workers that
--- have flown in and docked. A production line needs
--- `Config.game.production.workersPerLine` of them to run, so a station with
--- no one aboard makes nothing, and shooting down the worker shuttles of a
--- system slows its factories.
---
--- `beginTick` / `claim` are how a tick hands the crew out: the station's own
--- lines claim first (`ProductionSystem`), then what is left goes to the
--- lines the player has rented (`PlayerFactories`).
---@class WorkforceComponent: Component
---@overload fun(self: WorkforceComponent, crew: integer|nil): WorkforceComponent subclass internal
---@overload fun(crew: integer|nil): WorkforceComponent subclass external
local WorkforceComponent = Subclass("WorkforceComponent", Component, function(self, crew)
    self:setComponentName("EconomyWorkforce")
    --- The station's own standing crew (never leaves).
    self.crew = crew or 0
    --- Workers docked right now, by their NPC record: a count would drift
    --- when a ship is destroyed or a scene is torn down.
    self.docked = setmetatable({}, { __mode = "k" })
    self.dockedCount = 0
    --- Claimed this tick.
    self.used = 0
end)

---@param crew integer the standing crew
function WorkforceComponent:setCrew(crew)
    self.crew = math.max(0, math.floor(crew or 0))
end

---@return integer
function WorkforceComponent:getCrew()
    return self.crew
end

--- A worker docked and started a shift.
---@param worker table the NPC record
function WorkforceComponent:arrive(worker)
    if not worker or self.docked[worker] then return end
    self.docked[worker] = true
    self.dockedCount = self.dockedCount + 1
end

--- A worker undocked, or is gone.
---@param worker table the NPC record
function WorkforceComponent:leave(worker)
    if not worker or not self.docked[worker] then return end
    self.docked[worker] = nil
    self.dockedCount = math.max(0, self.dockedCount - 1)
end

---@return integer workers docked right now
function WorkforceComponent:getDockedCount()
    return self.dockedCount
end

--- Everyone aboard: the standing crew and the workers who have flown in.
---@return integer
function WorkforceComponent:getTotal()
    return self.crew + self.dockedCount
end

--- Start a tick: nobody is claimed yet.
function WorkforceComponent:beginTick()
    self.used = 0
end

--- Claim `count` hands for a line, if there are that many left.
---@param count integer
---@return boolean claimed
function WorkforceComponent:claim(count)
    count = math.max(0, math.floor(count or 0))
    if count == 0 then return true end
    if self.used + count > self:getTotal() then return false end
    self.used = self.used + count
    return true
end

---@return integer hands not claimed this tick
function WorkforceComponent:getFree()
    return math.max(0, self:getTotal() - self.used)
end

--- "3 of 4" for the docked screen.
---@return string
function WorkforceComponent:describe()
    return string.format("%d of %d", self.used, self:getTotal())
end

return WorkforceComponent
