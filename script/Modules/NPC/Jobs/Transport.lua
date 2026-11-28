local Action = require("Modules.NPC.Actions.Action")
local Actions = require("Modules.NPC.Actions")
local Factions = require("Modules.NPC.Factions")

--- Hauler job (Legacy Jobs/Transport, without the economy yet): a run
--- between stops, a while at each to trade, then out through a gate (or the
--- job ends and Think plans another run). Runs from the factions its role
--- fears (`fleeFrom`): traders from pirates, pirate merchants from security
--- and the player. Traders stop at stations, pirate merchants at hideouts.
---@class NpcTransport: NpcAction
local Transport = Subclass("NpcTransport", Action, function(self, stops, exitGate, name)
    self.stops = stops       -- positions {x, y, z}, or { dock = place } for a station to dock at
    self.exitGate = exitGate -- JumpGatePlacement or nil
    self.name = name or "Hauling cargo"
end)

local SCAN_INTERVAL = 0.5

--- At one of the player's outposts a trader buys from the owner's listings
--- (MarketSystem:npcBuy): what it pays goes to the owner, less nothing.
---@class NpcBuyListings: NpcAction
local BuyListings = Subclass("NpcBuyListings", Action, function(self, dock) self.dock = dock end)
function BuyListings:getName() return "Trading" end
function BuyListings:onUpdate(npc, ctx, dt)
    local dock = self.dock
    if dock and dock.entity:isValid() and npc.pilot.docked == dock then
        local MarketSystem = require("Modules.Economy.Systems.MarketSystem")
        local spent, units = MarketSystem:npcBuy(dock.entity, dock.key)
        if units > 0 then
            Log.Debug("NPC: %s bought %d units for %d at %s", npc.label, units, spent, dock.label or "an outpost")
        end
    end
    self:finish(npc)
end

function Transport:getName() return self.name end

function Transport:onStart(npc, ctx)
    self.next = 1
    self.scan = 0
end

--- Watching for threats the whole time, also on the way and while trading
function Transport:onUpdatePassive(npc, ctx, dt)
    self.scan = (self.scan or 0) - dt
    if self.scan > 0 or ctx:isFleeing(npc) or npc.pilot.docked then return end
    self.scan = SCAN_INTERVAL
    local stats = npc.pilot.stats
    local range = stats.fleeRange or 3
    local threat = ctx:findShip(npc, range, stats.fleeFrom or { Factions.Pirate })
    if threat then
        npc.pilot:pushAction(Actions.Flee(threat, range * 2.5))
    end
end

function Transport:onUpdate(npc, ctx, dt)
    local stop = self.stops[self.next]
    if stop then
        self.next = self.next + 1
        if stop.dock then
            -- A station: dock, trade a while, undock (pushed in reverse)
            npc.pilot:pushAction(Actions.Undock())
            if stop.dock.outpost then npc.pilot:pushAction(BuyListings(stop.dock)) end
            npc.pilot:pushAction(Actions.Wait(ctx.rng:getUniformRange(6, 12), "Trading"))
            npc.pilot:pushAction(Actions.DockAt(stop.dock))
        else
            npc.pilot:pushAction(Actions.Wait(ctx.rng:getUniformRange(6, 12), "Trading"))
            npc.pilot:pushAction(Actions.MoveTo(stop, 0.6, self.name))
        end
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
