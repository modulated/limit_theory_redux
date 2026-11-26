local Action = require("Modules.NPC.Actions.Action")

--- Fly out of the system through a gate: to the gate, then gone (NpcSystem
--- removes a pilot that is `leaving`, as if it had jumped).
---@class NpcLeaveSystem: NpcAction
local LeaveSystem = Subclass("NpcLeaveSystem", Action, function(self, gate)
    self.gate = gate -- a JumpGatePlacement
end)

function LeaveSystem:getName()
    return "Leaving for " .. self.gate.destination.name
end

function LeaveSystem:onUpdate(npc, ctx, dt)
    npc.pilot:setGoal(self.gate.position, self.gate.radius * 0.5)
    if ctx:distance(npc, self.gate.position) <= self.gate.radius * 0.8 then
        npc.pilot.leaving = true
        npc.pilot:clearGoal()
    end
end

return LeaveSystem
