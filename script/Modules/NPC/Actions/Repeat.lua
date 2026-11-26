local Action = require("Modules.NPC.Actions.Action")

--- Do a sequence of actions over and over (Legacy Actions/Repeat): each time
--- it comes back on top, it pushes a fresh copy of the sequence. Legacy
--- cloned the actions; here `make` builds them anew. Ends when `make`
--- returns nothing (or is popped by a job).
---@class NpcRepeat: NpcAction
local Repeat = Subclass("NpcRepeat", Action, function(self, make, name)
    self.make = make -- fun(npc, ctx): NpcAction[]|nil, in the order they run
    self.name = name or "Working"
end)

function Repeat:getName() return self.name end

function Repeat:onUpdate(npc, ctx, dt)
    local actions = self.make(npc, ctx)
    if not actions or #actions == 0 then
        self:finish(npc)
        return
    end
    for i = #actions, 1, -1 do
        npc.pilot:pushAction(actions[i])
    end
end

return Repeat
