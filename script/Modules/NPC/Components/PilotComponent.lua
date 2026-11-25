local Component = require("Core.ECS.Component")

--- An NPC ship's pilot: its faction, how it flies, and its action stack.
---
--- The action stack is the Legacy AI's model (Legacy/GameObjects/Action.lua):
--- the top action runs; an action can push actions above itself (a job pushes
--- "move there", "attack that") and pops itself when it is done. A job is an
--- action that stays at the bottom of the stack; when the stack is empty,
--- Think gives the pilot a new job (NpcSystem).
---
--- Steering is a goal the top action sets each frame (`setGoal`): where to
--- go, how close is close enough, and how fast. NpcSystem flies the ship
--- toward it.
---@class PilotComponent: Component
---@overload fun(faction: string, stats: table): PilotComponent
local PilotComponent = Subclass("PilotComponent", Component, function(self, faction, stats)
    self:setComponentName("NPCPilot")
    self.faction = faction
    self.stats = stats -- Config.game.npc[faction]
    self.actions = {}
    self.velocity = { x = 0, y = 0, z = 0 }
    self.goal = nil
    self.job = nil
    self.leaving = false -- flew out through a gate: NpcSystem removes it
end)

---@return string
function PilotComponent:getFaction()
    return self.faction
end

--- The action on top of the stack, or nil.
function PilotComponent:currentAction()
    return self.actions[#self.actions]
end

---@param action table an NPC action (Modules/NPC/Actions)
function PilotComponent:pushAction(action)
    table.insert(self.actions, action)
    action.started = false
end

--- Remove the top action (it calls onStop).
---@param npc table the NpcSystem record (entity, body, pilot...)
function PilotComponent:popAction(npc)
    local action = table.remove(self.actions)
    if action and action.onStop then action:onStop(npc) end
end

---@param npc table
function PilotComponent:clearActions(npc)
    while #self.actions > 0 do self:popAction(npc) end
end

---@return boolean
function PilotComponent:isIdle()
    return #self.actions == 0
end

--- Fly toward `pos` until within `range`, at up to `speedFactor` of top speed.
---@param pos table {x, y, z}
---@param range number
---@param speedFactor number|nil default 1
function PilotComponent:setGoal(pos, range, speedFactor)
    self.goal = self.goal or {}
    self.goal.x, self.goal.y, self.goal.z = pos.x, pos.y, pos.z
    self.goal.range = range
    self.goal.speedFactor = speedFactor or 1
end

--- Stop flying anywhere (the ship slows to a halt).
function PilotComponent:clearGoal()
    self.goal = nil
end

--- What the pilot is doing, for its label ("Patrolling", "Attacking"...).
---@return string
function PilotComponent:getActivity()
    local top = self:currentAction()
    if top and top.getName then return top:getName() end
    return "Idle"
end

return PilotComponent
