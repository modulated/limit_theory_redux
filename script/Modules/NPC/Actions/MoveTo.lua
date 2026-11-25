local Action = require("Modules.NPC.Actions.Action")

--- Fly to a place or a ship (Legacy Actions/MoveTo and MoveToPos).
---@class NpcMoveTo: NpcAction
local MoveTo = Subclass("NpcMoveTo", Action, function(self, target, range, name, speedFactor)
    self.target = target -- {x, y, z}, or an Entity to follow
    self.range = range
    self.name = name or "Travelling"
    self.speedFactor = speedFactor
end)

function MoveTo:getName() return self.name end

function MoveTo:onUpdate(npc, ctx, dt)
    local pos = ctx:positionOf(self.target)
    if not pos then
        self:finish(npc) -- the ship it was going to is gone
        return
    end
    npc.pilot:setGoal(pos, self.range, self.speedFactor)
    if ctx:distance(npc, pos) <= self.range then
        npc.pilot:clearGoal()
        self:finish(npc)
    end
end

return MoveTo
