local CoreComponents = require("Modules.Core.Components")
local CelestialComponents = require("Modules.CelestialObjects.Components")
local EconomyComponents = require("Modules.Economy.Components")
local Items = require("Shared.Registries.Items")

--- What a rock holds: the one place that decides which ore a given asteroid
--- is made of, and how much of it.
---
--- Both halves of mining ask this, so they agree: `MiningField` for the rocks
--- the NPC miners work, and `AsteroidFieldSystem` for the `Item`/`Quantity`
--- components of the rocks it spawns as real entities near the player. A
--- prospecting scanner can read those components, or call `forAsteroid` for a
--- rock that has not been spawned.
---
--- The ore follows from the field's generated `Composition` (item ids with
--- weights, by field type, from the ruleset) and from the asteroid's own seed,
--- so it is the same every time it is asked and needs nothing stored.
--- The `[fallback]` of res/data/ores.toml is used for a field the ruleset
--- gave no composition.
---@class AsteroidOre
local AsteroidOre = {}

--- Set by `MiningField`: how much of its ore a rock has left right now, for
--- rocks the miners are working. Without one (or for a rock it does not
--- track) a rock holds its untouched maximum.
---@type fun(field: Entity, asteroid: table): number|nil
local yieldProvider = nil

--- `MiningField` registers itself here when it builds a system's rocks, so a
--- rock the miners have been stripping reports what is left of it rather than
--- what it started with.
---@param fn fun(field: Entity, asteroid: table): number|nil nil to clear it
function AsteroidOre.setYieldProvider(fn)
    yieldProvider = fn
end

--- Per-field ore lists, built once. Weak keys: fields go with their scene.
local oresByField = setmetatable({}, { __mode = "k" })
--- Which fields fell back to the config list (same keys as above).
local fallbackFields = setmetatable({}, { __mode = "k" })
local configOresCache

--- The fallback ores (res/data/ores.toml, `[fallback]`) as a weighted list
--- of registry items.
---@return table list of { def = ItemDefinition, weight = number }, with `total`
local function configOres()
    if configOresCache then return configOresCache end
    local ores, total = {}, 0
    for _, ore in ipairs(require("Shared.Data.OreData").fallback()) do
        local def = Items:getDefinition(ore.id)
        ores[#ores + 1] = { def = def, weight = ore.weight }
        total = total + ore.weight
    end
    assert(total > 0, "no ores: res/data/ores.toml has an empty [fallback]")
    ores.total = total
    configOresCache = ores
    return ores
end

--- The field's own composition as a weighted list, or nil when it has none.
---
--- A system belt carries its `Composition` itself; a planet's ring is
--- materialized as a child belt entity whose composition is on the ring above
--- it, so this walks up the parents to find one.
---@param field Entity a belt or ring entity
---@return table|nil list of { def = ItemDefinition, weight = number }, with `total`
local function fieldComposition(field)
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
    if not composition then return nil end

    local ores, total = {}, 0
    for _, entry in ipairs(composition) do
        local def = entry.id and Items:getDefinition(entry.id)
        local weight = entry.weight or 1
        if def and weight > 0 then
            ores[#ores + 1] = { def = def, weight = weight }
            total = total + weight
        elseif entry.id then
            Log.Warn("AsteroidOre: field composition names unknown item id %s", tostring(entry.id))
        end
    end
    if total <= 0 then return nil end
    ores.total = total
    return ores
end

--- The ores a field can hold, and whether they came from its composition.
---@param field Entity a belt or ring entity
---@return table ores list of { def = ItemDefinition, weight = number }, with `total`
---@return boolean fromComposition false when the config fallback was used
function AsteroidOre.forField(field)
    local cached = oresByField[field]
    if cached then return cached, not fallbackFields[field] end
    local ores = fieldComposition(field)
    local fromComposition = ores ~= nil
    ores = ores or configOres()
    oresByField[field] = ores
    fallbackFields[field] = not fromComposition or nil
    return ores, fromComposition
end

--- The ore one asteroid of a field holds. Deterministic: it comes from the
--- asteroid's own seed, so every caller gets the same answer.
---@param field Entity a belt or ring entity
---@param asteroid table a record of the field's asteroid data { rotSeed, scale, ... }
---@return ItemDefinition ore
---@return integer units how much of it the rock holds when untouched
function AsteroidOre.forAsteroid(field, asteroid)
    local ores = AsteroidOre.forField(field)
    local rng = RNG.Create(asteroid.rotSeed or 0)
    local pick = rng:getUniformRange(0, ores.total)
    local ore = ores[#ores].def
    for _, candidate in ipairs(ores) do
        pick = pick - candidate.weight
        if pick <= 0 then
            ore = candidate.def
            break
        end
    end
    return ore, AsteroidOre.unitsLeft(field, asteroid)
end

--- How much of its ore a rock has left: what the yield provider says, else
--- its untouched maximum. (`forAsteroid` returns this too; this is the cheap
--- way to ask again for a rock whose ore is already known.)
---@param field Entity a belt or ring entity
---@param asteroid table a record of the field's asteroid data
---@return integer
function AsteroidOre.unitsLeft(field, asteroid)
    if yieldProvider then
        local left = yieldProvider(field, asteroid)
        if left then return math.floor(left) end
    end
    return AsteroidOre.units(asteroid)
end

--- How many units a rock of this size holds untouched (Legacy's Yield
--- maximum).
---@param asteroid table { scale, ... }
---@return integer
function AsteroidOre.units(asteroid)
    local perUnit = Config.game.mining.unitsPerScale
    return math.max(1, math.floor((asteroid.scale or 0) / perUnit + 0.5))
end

--- What a rock entity holds, read off the components it was spawned with.
--- This is what a prospecting scanner asks of a rock it has found.
---@param entity Entity an asteroid entity
---@return ItemDefinition|nil ore nil when the entity is not a rock that holds anything
---@return integer units
function AsteroidOre.ofEntity(entity)
    local itemCmp = entity and entity:get(EconomyComponents.Item)
    local ore = itemCmp and Items:getDefinition(itemCmp:getItem())
    if not ore then return nil, 0 end
    local quantityCmp = entity:get(EconomyComponents.Quantity)
    return ore, quantityCmp and math.floor(quantityCmp:getQuantity()) or 0
end

--- A rock's contents in words, e.g. "Siderite x1240" ("nothing" when it holds
--- no ore, "Siderite, spent" when its yield is gone).
---@param entity Entity an asteroid entity
---@return string
function AsteroidOre.describeEntity(entity)
    local ore, units = AsteroidOre.ofEntity(entity)
    if not ore then return "nothing" end
    if units < 1 then return ore.displayName .. ", spent" end
    return string.format("%s x%d", ore.displayName, units)
end

return AsteroidOre
