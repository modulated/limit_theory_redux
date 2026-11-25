local PhysicsComponents = require("Modules.Physics.Components")
local CoreComponents = require("Modules.Core.Components")
local CelestialComponents = require("Modules.CelestialObjects.Components")

--- The rocks of the system's asteroid belts and rings that can be mined: the
--- port of Legacy's Minable and Yield (Elements/Other/Minable.lua,
--- Elements/Economy/Yield.lua). Each rock holds an ore and a yield: units
--- that mining takes one by one and that grow back slowly toward the rock's
--- maximum (Legacy's Yield:update), the maximum set by the rock's size.
---
--- The rocks are picked from the belts' rock data (a sample: belts have
--- thousands), at their positions when the system is built.
---@class MiningField
---@overload fun(): MiningField
local MiningField = Class("MiningField", function(self)
    self.rocks = {}
end)

---@class MiningRock
---@field position table {x, y, z}
---@field radius number
---@field item string the ore
---@field yield number units left
---@field yieldMax number
---@field claimed table|nil the miner working it

--- Where a belt's rock data is measured from: the parent body when there is
--- one (rings), else the belt itself.
local function beltOrigin(belt)
    local origin = belt
    local parentCmp = belt:get(CoreComponents.Parent)
    if parentCmp then
        local p = parentCmp:getParent()
        if p and p:get(PhysicsComponents.Transform) then origin = p end
    end
    local t = origin:get(PhysicsComponents.Transform)
    return t and t:getPos() or nil
end

--- Pick the mineable rocks from the belts.
---@param belts Entity[] AsteroidBelt entities
---@param seed integer
function MiningField:build(belts, seed)
    local cfg = Config.game.mining
    local rng = RNG.Create(seed)
    self.rocks = {}
    local totalWeight = 0
    for _, ore in ipairs(cfg.ores) do totalWeight = totalWeight + ore.weight end

    for _, belt in ipairs(belts) do
        local beltCmp = belt:get(CelestialComponents.AsteroidBelt)
        local data = beltCmp and beltCmp:getAsteroidData() or {}
        local origin = beltOrigin(belt)
        if origin and #data > 0 then
            for _ = 1, math.min(cfg.rocksPerBelt, #data) do
                local a = data[rng:getInt(1, #data)]
                local pick = rng:getUniformRange(0, totalWeight)
                local ore = cfg.ores[#cfg.ores].name
                for _, o in ipairs(cfg.ores) do
                    pick = pick - o.weight
                    if pick <= 0 then ore = o.name break end
                end
                local size = math.max(1, math.floor(a.scale / cfg.unitsPerScale + 0.5))
                table.insert(self.rocks, {
                    position = { x = origin.x + a.px, y = origin.y + a.py, z = origin.z + a.pz },
                    radius = a.scale,
                    item = ore,
                    yield = size,
                    yieldMax = size,
                })
            end
        end
    end
    Log.Info("Mining: %d mineable rocks", #self.rocks)
end

--- Take one unit from a rock (Legacy decreaseYield); false when it is spent.
---@param rock MiningRock
---@return boolean
function MiningField:take(rock)
    if rock.yield < 1 then return false end
    rock.yield = rock.yield - 1
    return true
end

--- Yields grow back (Legacy Yield:update).
---@param dt number
function MiningField:update(dt)
    local regrow = Config.game.mining.regrowPerSecond * dt
    for _, rock in ipairs(self.rocks) do
        if rock.yield < rock.yieldMax then
            rock.yield = math.min(rock.yieldMax, rock.yield + regrow)
        end
    end
end

--- The nearest unclaimed rock with at least one unit, from a position.
---@param pos table {x, y, z}
---@return MiningRock|nil
function MiningField:findRock(pos)
    local best, bestDist = nil, math.huge
    for _, rock in ipairs(self.rocks) do
        if rock.yield >= 1 and not (rock.claimed and not rock.claimed.removed and not rock.claimed.dead) then
            local dx, dy, dz = rock.position.x - pos.x, rock.position.y - pos.y, rock.position.z - pos.z
            local d = dx * dx + dy * dy + dz * dz
            if d < bestDist then best, bestDist = rock, d end
        end
    end
    return best
end

return MiningField
