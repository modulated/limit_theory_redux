local Action = require("Modules.NPC.Actions.Action")

--- Mine a rock (Legacy Actions/MineAt): orbit it close and take one unit of
--- its ore every `timePerUnit` seconds, until the hold is full or the rock
--- is spent. Legacy mined for a station's bids; with no economy yet, the
--- miner fills its hold and sells it all when it docks.
---@class NpcMineAt: NpcAction
local MineAt = Subclass("NpcMineAt", Action, function(self, rock, timePerUnit)
    self.rock = rock -- a MiningField rock
    self.timePerUnit = timePerUnit
end)

function MineAt:getName() return "Mining " .. self.rock.item end

function MineAt:onStart(npc, ctx)
    self.timer = 0
    self.time = ctx.rng:getUniformRange(0, 30)
end

function MineAt:onUpdate(npc, ctx, dt)
    local cargo = npc.cargo
    if cargo.count >= cargo.capacity or self.rock.yield < 1 then
        self:finish(npc)
        return
    end

    -- Orbit the rock (Legacy: 30 s a turn, at 1.25 rock radii)
    self.time = self.time + dt
    local a = 2 * math.pi * self.time / 30
    local r = self.rock.radius * 1.25 + 0.05
    local p = self.rock.position
    npc.pilot:setGoal({ x = p.x + math.cos(a) * r, y = p.y, z = p.z + math.sin(a) * r }, 0.02, 0.3)

    self.timer = self.timer + dt
    if self.timer >= self.timePerUnit then
        self.timer = 0
        if ctx.mining:take(self.rock) then
            cargo.count = cargo.count + 1
            -- The hold keeps both: the id for whoever buys it later, the
            -- display name for the HUD and the logs.
            cargo.item = self.rock.item
            cargo.itemId = self.rock.itemId
        end
    end
end

return MineAt
