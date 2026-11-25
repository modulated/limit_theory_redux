local Action = require("Modules.NPC.Actions.Action")
local Actions = require("Modules.NPC.Actions")
local Factions = require("Modules.NPC.Factions")

--- Trader job (Legacy Jobs/Transport, without the economy yet): a run
--- between the system's stations, a stop at each to trade, then out through
--- a gate (or the job ends and Think plans another run). Runs from pirates
--- that come close.
---@class NpcTransport: NpcAction
local Transport = Subclass("NpcTransport", Action, function(self, stops, exitGate)
    self.stops = stops       -- positions {x, y, z}
    self.exitGate = exitGate -- JumpGatePlacement or nil
end)

local SCAN_INTERVAL = 0.5

function Transport:getName() return "Hauling cargo" end

function Transport:onStart(npc, ctx)
    self.next = 1
    self.scan = 0
end

--- Watching for pirates the whole time, also on the way and while trading
function Transport:onUpdatePassive(npc, ctx, dt)
    self.scan = (self.scan or 0) - dt
    if self.scan > 0 or ctx:isFleeing(npc) then return end
    self.scan = SCAN_INTERVAL
    local threat = ctx:findShip(npc, npc.pilot.stats.fleeRange, { Factions.Pirate })
    if threat then
        npc.pilot:pushAction(Actions.Flee(threat, npc.pilot.stats.fleeRange * 2.5))
    end
end

function Transport:onUpdate(npc, ctx, dt)
    local stop = self.stops[self.next]
    if stop then
        self.next = self.next + 1
        npc.pilot:pushAction(Actions.Wait(ctx.rng:getUniformRange(6, 12), "Trading"))
        npc.pilot:pushAction(Actions.MoveTo(stop, 0.6, "Hauling cargo"))
        return
    end

    if self.exitGate then
        self.exitGate, self.leaving = nil, self.exitGate
        npc.pilot:pushAction(Actions.LeaveSystem(self.leaving))
        return
    end
    self:finish(npc)
end

return Transport
