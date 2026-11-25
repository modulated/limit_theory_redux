local Action = require("Modules.NPC.Actions.Action")

--- Hold still for a while (Legacy Actions/Wait).
---@class NpcWait: NpcAction
local Wait = Subclass("NpcWait", Action, function(self, duration, name)
    self.duration = duration
    self.name = name or "Waiting"
end)

function Wait:getName() return self.name end

function Wait:onStart(npc, ctx)
    self.left = self.duration
end

function Wait:onUpdate(npc, ctx, dt)
    npc.pilot:clearGoal()
    self.left = self.left - dt
    if self.left <= 0 then self:finish(npc) end
end

return Wait
