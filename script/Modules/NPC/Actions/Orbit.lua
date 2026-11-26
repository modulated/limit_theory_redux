local Action = require("Modules.NPC.Actions.Action")

--- Circle a place or a ship (Legacy Actions/Orbit): around it at `radius`,
--- once every `period` seconds, in one of two planes (Legacy's two axes);
--- for `duration` seconds, or until popped.
---@class NpcOrbit: NpcAction
local Orbit = Subclass("NpcOrbit", Action, function(self, target, radius, period, duration, name)
    self.target = target
    self.radius = radius
    self.period = period
    self.duration = duration
    self.name = name or "Orbiting"
end)

function Orbit:getName() return self.name end

function Orbit:onStart(npc, ctx)
    self.time = ctx.rng:getUniformRange(0, self.period)
    self.plane = ctx.rng:getInt(1, 2)
    self.left = self.duration
end

function Orbit:onUpdate(npc, ctx, dt)
    local center = ctx:positionOf(self.target)
    if not center then
        self:finish(npc)
        return
    end
    self.time = self.time + dt
    local a = 2 * math.pi * self.time / self.period
    local cx, cy = math.cos(a) * self.radius, math.sin(a) * self.radius
    local offset = self.plane == 1 and { x = cx, y = 0, z = cy } or { x = cx, y = cy, z = 0 }
    npc.pilot:setGoal({ x = center.x + offset.x, y = center.y + offset.y, z = center.z + offset.z }, 0.02, 0.5)
    if self.left then
        self.left = self.left - dt
        if self.left <= 0 then self:finish(npc) end
    end
end

return Orbit
