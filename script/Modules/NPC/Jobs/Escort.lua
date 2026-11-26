local Action = require("Modules.NPC.Actions.Action")
local Actions = require("Modules.NPC.Actions")

--- Guard job (Legacy Actions/Escort): keep station at a slot beside the
--- ship being guarded (its "charge"), a little ahead of where it is going,
--- and attack hostiles that come near it, without straying further than the
--- leash from it. Legacy's Escort had "attack nearby hostiles" as a TODO;
--- this does it. Ends when the charge is gone; a charge leaving the system
--- takes its guards along (NpcSystem).
---@class NpcEscort: NpcAction
local Escort = Subclass("NpcEscort", Action, function(self, charge, slot)
    self.charge = charge -- NpcSystem record of the guarded ship
    self.slot = slot     -- {x, y, z} in the charge's frame (ship radii don't matter: game units)
end)

local SCAN_INTERVAL = 0.5
local LEAD_TIME = 1.0 -- aim for where the charge will be in a second

function Escort:getName() return "Escorting" end

--- Watching for hostiles near the charge (and near itself)
function Escort:onUpdatePassive(npc, ctx, dt)
    self.scan = (self.scan or 0) - dt
    if self.scan > 0 or ctx:isFighting(npc) or not ctx:isGuarding(self.charge) then return end
    self.scan = SCAN_INTERVAL
    local range = npc.pilot.stats.detectRange
    local hostile = ctx:findHostile(self.charge, range) or ctx:findHostile(npc, range)
    if hostile then
        npc.pilot:pushAction(Actions.Attack(hostile, {
            entity = self.charge.entity,
            distance = npc.pilot.stats.leash or range,
        }))
    end
end

function Escort:onUpdate(npc, ctx, dt)
    if not ctx:isGuarding(self.charge) then
        self:finish(npc)
        return
    end
    local charge = self.charge
    local pos = charge.body:getPos()
    local rot = charge.body:getRot()
    local offset = rot:mulV(Vec3f(self.slot.x, self.slot.y, self.slot.z))
    local v = charge.pilot.velocity
    npc.pilot:setGoal({
        x = pos.x + offset.x + v.x * LEAD_TIME,
        y = pos.y + offset.y + v.y * LEAD_TIME,
        z = pos.z + offset.z + v.z * LEAD_TIME,
    }, 0.15)
end

return Escort
