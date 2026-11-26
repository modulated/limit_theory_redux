local Action = require("Modules.NPC.Actions.Action")
local Actions = require("Modules.NPC.Actions")

--- Security job (Legacy Jobs/Patrolling): fly a round of the system's
--- stations and gates; attack any hostile seen on the way. The job ends
--- after its round, and Think gives the pilot its next one.
---@class NpcPatrolling: NpcAction
local Patrolling = Subclass("NpcPatrolling", Action, function(self, nodes)
    self.nodes = nodes -- positions {x, y, z}
end)

local SCAN_INTERVAL = 0.5

function Patrolling:getName() return "Patrolling" end

function Patrolling:onStart(npc, ctx)
    self.next = 1
    self.scan = 0
end

--- Watching for hostiles the whole time, also while flying between nodes
function Patrolling:onUpdatePassive(npc, ctx, dt)
    self.scan = (self.scan or 0) - dt
    if self.scan > 0 or ctx:isFighting(npc) then return end
    self.scan = SCAN_INTERVAL
    local hostile = ctx:findHostile(npc, npc.pilot.stats.detectRange)
    if hostile then
        npc.pilot:pushAction(Actions.Attack(hostile))
    end
end

function Patrolling:onUpdate(npc, ctx, dt)
    local node = self.nodes[self.next]
    if not node then
        self:finish(npc) -- round done
        return
    end
    self.next = self.next + 1
    npc.pilot:pushAction(Actions.MoveTo(node, 0.8, "Patrolling"))
end

return Patrolling
