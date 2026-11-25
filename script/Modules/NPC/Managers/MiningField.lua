local PhysicsComponents = require("Modules.Physics.Components")
local CoreComponents = require("Modules.Core.Components")
local CelestialComponents = require("Modules.CelestialObjects.Components")
local Items = require("Shared.Registries.Items")

--- The rocks of the system's asteroid belts and rings that can be mined: the
--- port of Legacy's Minable and Yield (Elements/Other/Minable.lua,
--- Elements/Economy/Yield.lua). Each rock holds an ore and a yield: units
--- that mining takes one by one and that grow back slowly toward the rock's
--- maximum (Legacy's Yield:update), the maximum set by the rock's size.
---
--- The rocks are picked from the belts' rock data (a sample: belts have
--- thousands), at their positions when the system is built. What a rock is
--- made of comes from its own belt or ring: the generator gives each field a
--- `Composition` (item ids with weights, by field type, from the ruleset), so
--- an icy ring yields ice and gases and a rocky belt yields ore.
--- `Config.game.mining.ores` is the fallback for a field without one.
---@class MiningField
---@overload fun(): MiningField
local MiningField = Class("MiningField", function(self)
    self.rocks = {}
end)

---@class MiningRock
---@field position table {x, y, z}
---@field radius number
---@field item string the ore's display name ("Iron Ore")
---@field itemId integer the ore's item id
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

--- The weighted ore list of one field: its generated `Composition` (a list of
--- `{ id, weight }` from the ruleset), resolved against the item registry.
--- Returns nil when the field has none, or none of its items are known.
---@param field Entity a belt or ring
---@return table|nil list { def = ItemDefinition, weight = number }, with `total`
local function fieldOres(field)
    -- A system belt carries its own Composition; a planet's ring is
    -- materialized as a child belt entity whose Composition is on the ring
    -- above it, so walk up to find one.
    local composition
    local entity = field
    for _ = 1, 4 do
        if not entity then break end
        local cmp = entity:get(CelestialComponents.Composition)
        composition = cmp and cmp:getComposition()
        if type(composition) == "table" and #composition > 0 then break end
        composition = nil
        local parentCmp = entity:get(CoreComponents.Parent)
        entity = parentCmp and parentCmp:getParent() or nil
    end
    if type(composition) ~= "table" then return nil end
    local ores, total = {}, 0
    for _, entry in ipairs(composition) do
        local def = entry.id and Items:getDefinition(entry.id)
        local weight = entry.weight or 1
        if def and weight > 0 then
            ores[#ores + 1] = { def = def, weight = weight }
            total = total + weight
        elseif entry.id then
            Log.Warn("Mining: field composition names unknown item id %s", tostring(entry.id))
        end
    end
    if total <= 0 then return nil end
    ores.total = total
    return ores
end

--- `Config.game.mining.ores` as the same weighted list, for fields the
--- generator gave no composition.
---@return table list { def = ItemDefinition, weight = number }, with `total`
local function configOres()
    local ores, total = {}, 0
    for _, ore in ipairs(Config.game.mining.ores) do
        local def = Items:getByName(ore.name)
        if def then
            ores[#ores + 1] = { def = def, weight = ore.weight }
            total = total + ore.weight
        else
            Log.Warn("Mining: Config.game.mining.ores names unknown item '%s'", tostring(ore.name))
        end
    end
    assert(total > 0, "mining has no ores: Config.game.mining.ores names no item in the registry")
    ores.total = total
    return ores
end

---@param ores table from fieldOres/configOres
---@param rng RNG
---@return ItemDefinition
local function pickOre(ores, rng)
    local pick = rng:getUniformRange(0, ores.total)
    for _, ore in ipairs(ores) do
        pick = pick - ore.weight
        if pick <= 0 then return ore.def end
    end
    return ores[#ores].def
end

--- Pick the mineable rocks from the belts.
---@param belts Entity[] AsteroidBelt entities (belts and rings)
---@param seed integer
function MiningField:build(belts, seed)
    local cfg = Config.game.mining
    local rng = RNG.Create(seed)
    self.rocks = {}
    local fallback = configOres()
    local fallbackFields = 0

    for _, belt in ipairs(belts) do
        local beltCmp = belt:get(CelestialComponents.AsteroidBelt)
        local data = beltCmp and beltCmp:getAsteroidData() or {}
        local origin = beltOrigin(belt)
        local ores = fieldOres(belt)
        if not ores then
            ores = fallback
            fallbackFields = fallbackFields + 1
        end
        if origin and #data > 0 then
            for _ = 1, math.min(cfg.rocksPerBelt, #data) do
                local a = data[rng:getInt(1, #data)]
                local ore = pickOre(ores, rng)
                local size = math.max(1, math.floor(a.scale / cfg.unitsPerScale + 0.5))
                table.insert(self.rocks, {
                    position = { x = origin.x + a.px, y = origin.y + a.py, z = origin.z + a.pz },
                    radius = a.scale,
                    item = ore.displayName,
                    itemId = ore.id,
                    yield = size,
                    yieldMax = size,
                })
            end
        end
    end
    if fallbackFields > 0 then
        Log.Debug("Mining: %d of %d fields had no composition, used Config.game.mining.ores",
            fallbackFields, #belts)
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
