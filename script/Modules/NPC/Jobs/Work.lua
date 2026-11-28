local Action = require("Modules.NPC.Actions.Action")
local Actions = require("Modules.NPC.Actions")
local Factions = require("Modules.NPC.Factions")

--- A shift at a station: the worker is docked and counted as one of its hands
--- (`WorkforceComponent`), so the station's production lines can run. The
--- shift is a wait; `NpcSystem:dock` is what puts the worker on the station's
--- books, and undocking takes it off again.
---@class NpcShift: NpcAction
local Shift = Subclass("NpcShift", Action, function(self, seconds)
    self.seconds = seconds
    self.left = seconds
end)

function Shift:getName() return "On shift" end

function Shift:onUpdate(npc, ctx, dt)
    -- Only a docked worker is working; one that never made it in gives up
    if not npc.pilot.docked then
        self:finish(npc)
        return
    end
    self.left = self.left - dt
    if self.left <= 0 then
        self:finish(npc)
    end
end

--- Worker job: fly to a station that will take the ship, dock, work a shift,
--- undock, and do it again somewhere else. Workers are what make a station's
--- factory floor run, so a system whose worker shuttles are picked off by
--- pirates grinds to a halt. They run from the factions their role fears,
--- like the other haulers.
local SCAN_INTERVAL = 0.5

---@param npc table
---@param ctx table NpcSystem
---@return NpcAction|nil
return function(npc, ctx)
    local cfg = Config.game.production
    local job = Actions.Repeat(function(worker, system)
        -- Somewhere to work: a station that takes the ship, the nearest one
        -- unless another is picked at random (so they spread out)
        local docks = {}
        for _, dock in ipairs(system.places.docks or {}) do
            -- Not the player's outposts: they have no crew to join
            if not dock.outpost and system:canDock(worker, dock) then docks[#docks + 1] = dock end
        end
        if #docks == 0 then return nil end
        local dock = docks[system.rng:getInt(1, #docks)]
        local shift = system.rng:getUniformRange(cfg.shiftSeconds * 0.6, cfg.shiftSeconds * 1.4)
        return {
            Actions.DockAt(dock),
            Shift(shift),
            Actions.Undock(),
        }
    end, "Working a shift")

    -- Watching for trouble on the way, like the other unarmed ships
    function job:onUpdatePassive(worker, system, dt)
        self.scan = (self.scan or 0) - dt
        if self.scan > 0 or system:isFleeing(worker) or worker.pilot.docked then return end
        self.scan = SCAN_INTERVAL
        local stats = worker.pilot.stats
        local range = stats.fleeRange or 3
        local threat = system:findShip(worker, range, stats.fleeFrom or { Factions.Pirate })
        if threat then
            worker.pilot:pushAction(Actions.Flee(threat, range * 2.5))
        end
    end

    return job
end
