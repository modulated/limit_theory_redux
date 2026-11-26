local Action = require("Modules.NPC.Actions.Action")

--- Fly to a station and dock (Legacy Actions/DockAt): to its docking point
--- (above it, by its radius, as Legacy put it), then inside: the ship is
--- hidden, can't be targeted and doesn't move until it undocks. A station
--- that refuses the ship (its owner is hostile to the ship's faction) or is
--- gone ends the action without docking.
---@class NpcDockAt: NpcAction
local DockAt = Subclass("NpcDockAt", Action, function(self, dock)
    self.dock = dock -- a place: { entity, position, radius, faction }
end)

function DockAt:getName() return "Docking" end

function DockAt:onUpdate(npc, ctx, dt)
    if not ctx:canDock(npc, self.dock) then
        self:finish(npc)
        return
    end
    local point = ctx:dockingPoint(self.dock)
    npc.pilot:setGoal(point, 0.05, 0.6)
    if ctx:distance(npc, point) <= self.dock.radius * 0.5 + 0.1 then
        ctx:dock(npc, self.dock)
        self:finish(npc)
    end
end

return DockAt
