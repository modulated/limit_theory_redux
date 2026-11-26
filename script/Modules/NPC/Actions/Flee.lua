local Action = require("Modules.NPC.Actions.Action")

--- Run from a ship: straight away from it, at full speed, for a while or
--- until it is far enough behind.
---@class NpcFlee: NpcAction
local Flee = Subclass("NpcFlee", Action, function(self, threat, safeDistance, duration)
    self.threat = threat
    self.safeDistance = safeDistance
    self.duration = duration or 12
end)

-- NpcSystem:isFleeing looks for this on the stack
Flee.isFlee = true

function Flee:getName() return "Fleeing" end

function Flee:onStart(npc, ctx)
    self.left = self.duration
end

function Flee:onUpdate(npc, ctx, dt)
    self.left = self.left - dt
    local threatPos = ctx:positionOf(self.threat)
    if not threatPos or not ctx:isAlive(self.threat) or self.left <= 0
        or ctx:distance(npc, threatPos) > self.safeDistance then
        self:finish(npc)
        return
    end
    local myPos = ctx:positionOf(npc.entity)
    local dx, dy, dz = myPos.x - threatPos.x, myPos.y - threatPos.y, myPos.z - threatPos.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len < 1e-6 then dx, dy, dz, len = 1, 0, 0, 1 end
    local far = self.safeDistance * 2
    npc.pilot:setGoal({
        x = myPos.x + dx / len * far, y = myPos.y + dy / len * far, z = myPos.z + dz / len * far,
    }, 0.1)
end

return Flee
