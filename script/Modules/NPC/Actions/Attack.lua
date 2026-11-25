local Action = require("Modules.NPC.Actions.Action")

--- Fight a ship (Legacy Actions/Attack): circle it on the attacker's side, at
--- a distance picked between close and the weapons' reach, picking a new
--- spot every few seconds so the fight keeps moving. The turrets aim and
--- fire by themselves (the ship's weapon battery engages hostile teams in
--- range); this only flies. Ends when the target is gone, or after it has
--- stayed out of reach for a while.
---@class NpcAttack: NpcAction
local Attack = Subclass("NpcAttack", Action, function(self, target)
    self.target = target
end)

local RADIUS_MIN, RADIUS_MAX = 0.8, 2.6 -- game units (weapon reach is ~3.5)
local GIVE_UP_RANGE = 12.0              -- farther than this...
local GIVE_UP_TIME = 15.0               -- ...for this long: stop chasing

-- NpcSystem:isFighting looks for this on the stack
Attack.isAttack = true

function Attack:getName() return "Attacking" end

function Attack:onStart(npc, ctx)
    self.timer = 0
    self.outOfReach = 0
end

function Attack:onUpdate(npc, ctx, dt)
    local targetPos = ctx:positionOf(self.target)
    if not targetPos or not ctx:isAlive(self.target) then
        self:finish(npc)
        return
    end

    local myPos = ctx:positionOf(npc.entity)
    local dist = ctx:distance(npc, targetPos)

    -- A new spot around the target from time to time, or once reached
    self.timer = self.timer - dt
    if self.timer <= 0 or (self.spot and self.reached) then
        local dir = ctx.rng:getDir3()
        -- On the attacker's side of the target (Legacy: sign of dot)
        local side = (myPos.x - targetPos.x) * dir.x + (myPos.y - targetPos.y) * dir.y
            + (myPos.z - targetPos.z) * dir.z
        local sign = side < 0 and -1 or 1
        local radius = RADIUS_MIN + (RADIUS_MAX - RADIUS_MIN) * ctx.rng:getUniform() ^ 2
        self.spot = { x = dir.x * sign * radius, y = dir.y * sign * radius * 0.4, z = dir.z * sign * radius }
        self.timer = ctx.rng:getUniformRange(5, 10)
        self.reached = false
    end

    local goal = {
        x = targetPos.x + self.spot.x,
        y = targetPos.y + self.spot.y,
        z = targetPos.z + self.spot.z,
    }
    npc.pilot:setGoal(goal, 0.3)
    if ctx:distance(npc, goal) < 0.3 then self.reached = true end

    if dist > GIVE_UP_RANGE then
        self.outOfReach = self.outOfReach + dt
        if self.outOfReach > GIVE_UP_TIME then self:finish(npc) end
    else
        self.outOfReach = 0
    end
end

return Attack
