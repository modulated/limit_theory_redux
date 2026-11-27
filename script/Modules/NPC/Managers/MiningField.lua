local PhysicsComponents = require("Modules.Physics.Components")
local CoreComponents = require("Modules.Core.Components")
local CelestialComponents = require("Modules.CelestialObjects.Components")
local AsteroidOre = require("Shared.Helpers.AsteroidOre")

--- The rocks of the system's asteroid belts and rings that can be mined: the
--- port of Legacy's Minable and Yield (Elements/Other/Minable.lua,
--- Elements/Economy/Yield.lua). Each rock holds an ore and a yield: units
--- that mining takes one by one and that grow back slowly toward the rock's
--- maximum (Legacy's Yield:update), the maximum set by the rock's size.
---
--- The rocks are picked from the belts' rock data (a sample: belts have
--- thousands), at their positions when the system is built. What a rock is
--- made of is `AsteroidOre`'s answer for that asteroid of that field, which
--- the rocks `AsteroidFieldSystem` spawns near the player carry as their
--- `Item`/`Quantity` components: the same rock holds the same ore whichever
--- way you look at it.
---@class MiningField
---@overload fun(): MiningField
local MiningField = Class("MiningField", function(self)
    self.rocks = {}
    -- field entity -> asteroid seed -> rock, for AsteroidOre's yield provider
    self.rocksByField = setmetatable({}, { __mode = "k" })
end)

---@class MiningRock
---@field position table {x, y, z}
---@field radius number
---@field item string the ore's display name ("Iron Ore")
---@field itemId integer the ore's item id
---@field field Entity the belt or ring the rock belongs to
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
---@param belts Entity[] AsteroidBelt entities (belts and the belt bands of rings)
---@param seed integer
function MiningField:build(belts, seed)
    local cfg = Config.game.mining
    local rng = RNG.Create(seed)
    self.rocks = {}
    self.rocksByField = setmetatable({}, { __mode = "k" })
    local fallbackFields = 0
    -- The rocks of the system that just went are nobody's answer any more:
    -- the ones below are to be built from their untouched maximum
    AsteroidOre.setYieldProvider(nil)

    for _, belt in ipairs(belts) do
        local beltCmp = belt:get(CelestialComponents.AsteroidBelt)
        local data = beltCmp and beltCmp:getAsteroidData() or {}
        local origin = beltOrigin(belt)
        local _, fromComposition = AsteroidOre.forField(belt)
        if not fromComposition then fallbackFields = fallbackFields + 1 end
        if origin and #data > 0 then
            local bySeed = {}
            self.rocksByField[belt] = bySeed
            for _ = 1, math.min(cfg.rocksPerBelt, #data) do
                local a = data[rng:getInt(1, #data)]
                -- The same asteroid can come up twice: one rock each, or the
                -- two would hold the same ore with two separate yields
                if not bySeed[a.rotSeed] then
                    -- The ore and the size are the asteroid's own, so the
                    -- entity AsteroidFieldSystem spawns for this rock, and a
                    -- scanner reading it, say the same
                    local ore, units = AsteroidOre.forAsteroid(belt, a)
                    local rock = {
                        position = { x = origin.x + a.px, y = origin.y + a.py, z = origin.z + a.pz },
                        radius = a.scale,
                        item = ore.displayName,
                        itemId = ore.id,
                        field = belt,
                        yield = units,
                        yieldMax = units,
                    }
                    table.insert(self.rocks, rock)
                    bySeed[a.rotSeed] = rock
                end
            end
        end
    end
    if fallbackFields > 0 then
        Log.Debug("Mining: %d of %d fields had no composition, used the ores.toml fallback",
            fallbackFields, #belts)
    end
    Log.Info("Mining: %d mineable rocks", #self.rocks)

    -- A rock the miners have been stripping should say what is left of it,
    -- wherever it is asked (the entity AsteroidFieldSystem spawns for it, a
    -- scanner reading that entity), so this field is now the live answer.
    AsteroidOre.setYieldProvider(function(field, asteroid)
        local rock = self:rockFor(field, asteroid)
        return rock and rock.yield or nil
    end)
end

--- The tracked rock of one asteroid of one field, or nil: the sample is small
--- (`rocksPerBelt`), so most asteroids have none.
---@param field Entity a belt or ring
---@param asteroid table a record of the field's asteroid data
---@return MiningRock|nil
function MiningField:rockFor(field, asteroid)
    local bySeed = self.rocksByField[field]
    return bySeed and asteroid and bySeed[asteroid.rotSeed] or nil
end

--- The rock of one asteroid, tracked from now on if it was not already: what
--- the player mines. The NPC miners work a sample of each field, but a player
--- can fly up to any rock, and once its yield is being taken from it, it has
--- to be remembered like the others.
---@param field Entity a belt or ring
---@param asteroid table a record of the field's asteroid data
---@param position table|nil {x, y, z} in the world, for findRock
---@return MiningRock
function MiningField:trackAsteroid(field, asteroid, position)
    local rock = self:rockFor(field, asteroid)
    if rock then return rock end
    local ore, units = AsteroidOre.forAsteroid(field, asteroid)
    rock = {
        position = position or { x = 0, y = 0, z = 0 },
        radius = asteroid.scale,
        item = ore.displayName,
        itemId = ore.id,
        field = field,
        yield = units,
        yieldMax = AsteroidOre.units(asteroid),
    }
    table.insert(self.rocks, rock)
    local bySeed = self.rocksByField[field]
    if not bySeed then
        bySeed = {}
        self.rocksByField[field] = bySeed
    end
    bySeed[asteroid.rotSeed] = rock
    return rock
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
