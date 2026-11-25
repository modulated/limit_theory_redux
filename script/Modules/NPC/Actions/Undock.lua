local Action = require("Modules.NPC.Actions.Action")

--- Leave the station the ship is docked at (Legacy Actions/Undock): it comes
--- out at the docking point, visible and targetable again.
---@class NpcUndock: NpcAction
local Undock = Subclass("NpcUndock", Action, function(self) end)

function Undock:getName() return "Undocking" end

function Undock:onUpdate(npc, ctx, dt)
    ctx:undock(npc)
    self:finish(npc)
end

return Undock
