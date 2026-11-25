--- Base of the NPC actions (the ECS port of Legacy/GameObjects/Action.lua).
---
--- An action runs while it is on top of its pilot's stack:
---   onStart(npc, ctx)        the first time it runs
---   onUpdate(npc, ctx, dt)   every frame it is on top; pops itself when done
---   onUpdatePassive(npc, ctx, dt)  every frame it is anywhere on the stack
---                            (a job watching for hostiles while it flies)
---   onStop(npc)              when it leaves the stack
---   getName()                what the pilot is doing, for labels
---
--- `npc` is NpcSystem's record of the ship (entity, body, pilot, faction);
--- `ctx` is NpcSystem itself: what the pilot can see and where it can go
--- (hostiles, positions, the system's places, an RNG).
---@class NpcAction
local Action = Class("NpcAction", function(self) end)

function Action:getName() return "Busy" end
function Action:onStart(npc, ctx) end
function Action:onUpdate(npc, ctx, dt) end
function Action:onUpdatePassive(npc, ctx, dt) end
function Action:onStop(npc) end

--- Done: take this action off the pilot's stack.
function Action:finish(npc)
    if npc.pilot:currentAction() == self then
        npc.pilot:popAction(npc)
    end
end

return Action
