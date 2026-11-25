local Action = require("Modules.NPC.Actions.Action")
local Actions = require("Modules.NPC.Actions")
local Factions = require("Modules.NPC.Factions")

--- Pirate job (Legacy Jobs/Marauding + Actions/MaraudAt): roam a hunting
--- ground (a gate or a belt, where traffic passes) and attack what comes
--- close, traders first. Gives up after a number of searches, like Legacy's
--- MaraudAt, and Think picks a new hunting ground.
---@class NpcMarauding: NpcAction
local Marauding = Subclass("NpcMarauding", Action, function(self, center, radius)
    self.center = center -- {x, y, z}
    self.radius = radius
end)

local SCAN_INTERVAL = 0.5
local MAX_SEARCHES = 8
-- Who a pirate goes for first
local PREY = { Factions.Trader, Factions.Player, Factions.Security }

function Marauding:getName() return "Marauding" end

function Marauding:onStart(npc, ctx)
    self.searches = 0
    self.scan = 0
end

--- Watching for prey the whole time, also while roaming and lurking
function Marauding:onUpdatePassive(npc, ctx, dt)
    self.scan = (self.scan or 0) - dt
    if self.scan > 0 or ctx:isFighting(npc) then return end
    self.scan = SCAN_INTERVAL
    local prey = ctx:findHostile(npc, npc.pilot.stats.detectRange, PREY)
    if prey then
        npc.pilot:pushAction(Actions.Attack(prey))
    end
end

function Marauding:onUpdate(npc, ctx, dt)
    if self.searches >= MAX_SEARCHES then
        self:finish(npc)
        return
    end
    self.searches = self.searches + 1
    -- Somewhere else in the hunting ground, then lurk there a moment
    local dir = ctx.rng:getDir3()
    local r = self.radius * ctx.rng:getUniform()
    local spot = {
        x = self.center.x + dir.x * r,
        y = self.center.y + dir.y * r * 0.3,
        z = self.center.z + dir.z * r,
    }
    npc.pilot:pushAction(Actions.Wait(ctx.rng:getUniformRange(2, 5), "Lurking"))
    npc.pilot:pushAction(Actions.MoveTo(spot, 0.5, "Marauding", 0.6))
end

return Marauding
