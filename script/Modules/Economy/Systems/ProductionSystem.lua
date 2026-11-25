local Productions = require("Shared.Registries.Productions")
local ProductionDefinition = require("Shared.Types.ProductionDefinition")
local Economy = require("Modules.Economy.Components")
local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")

--- Stations making things: the port of Legacy's Elements/Economy/Factory.lua.
---
--- A station runs the recipes of its `Production` component against its own
--- `Stock`. A line takes its inputs out of the store the moment it starts
--- (so two lines cannot spend the same iron), counts down its duration, and
--- puts the outputs in when it is done. Nothing is produced out of nothing:
--- a refinery that runs out of ore stops until a miner brings some, which is
--- what makes the prices in `StationTradeSystem` mean anything.
---
--- Legacy's durations are in real seconds, from 4 s for a waste recycler to
--- 4 hours for a station fabricator. `Config.game.production.timeScale`
--- compresses them so a factory does something visible within a session.
---@class ProductionSystem
local ProductionSystem = {}

--- The recipes a station runs, picked from its seed: a powerplant always (it
--- needs energy, and so does everything else), plus a refinery or a factory
--- or two. Drydocks are rare: one station in a system at most, and only if
--- the seed says so.
---@param station Entity
---@param rng RNG
---@param allowDrydock boolean|nil
---@return ProductionComponent
function ProductionSystem:assign(station, rng, allowDrydock)
    local cfg = Config.game.production
    local function pick(class)
        local list = Productions:ofClass(class)
        if #list == 0 then return nil end
        return list[rng:getInt(1, #list)]
    end

    local recipes = {}
    local Class = ProductionDefinition.Class
    -- Mostly a solar array: it needs nothing but the sun, so a station can
    -- always make energy. The reactors want fuel or water hauled in, which
    -- only works once something is hauling.
    local power = rng:getUniform() < cfg.solarChance
        and Productions:getByName("Solar Energy Array")
        or pick(Class.Powerplant)
    if power then recipes[#recipes + 1] = power end
    for _ = 1, rng:getInt(cfg.linesMin, cfg.linesMax) do
        local class = rng:getUniform() < cfg.refineryChance and Class.Refinery or Class.Factory
        local recipe = pick(class)
        if recipe then recipes[#recipes + 1] = recipe end
    end
    if allowDrydock and rng:getUniform() < cfg.drydockChance then
        local recipe = pick(Class.Drydock)
        if recipe then recipes[#recipes + 1] = recipe end
    end

    local ids = {}
    for _, recipe in ipairs(recipes) do ids[#ids + 1] = recipe.id end
    local cmp = station:get(Economy.Production)
    if cmp then
        for _, id in ipairs(ids) do cmp:addRecipe(id) end
    else
        cmp = station:add(Economy.Production(ids))
    end
    StationTradeSystem:invalidate(station)
    return cmp
end

--- Whether the store holds everything a recipe needs.
---@param stock StockComponent
---@param recipe ProductionDefinition
---@return boolean
local function hasInputs(stock, recipe)
    for _, entry in ipairs(recipe.inputs) do
        if stock:count(entry.item.id) < entry.count then return false end
    end
    return true
end

--- Take a recipe's inputs out of the store, or nothing at all.
---@param stock StockComponent
---@param recipe ProductionDefinition
---@return boolean taken
local function takeInputs(stock, recipe)
    if not hasInputs(stock, recipe) then return false end
    for _, entry in ipairs(recipe.inputs) do
        stock:remove(entry.item.id, entry.count)
    end
    return true
end

--- One station's lines move on.
---@param station Entity
---@param dt number seconds, already scaled
local function updateStation(station, dt)
    local productionCmp = station:get(Economy.Production)
    local stock = station:get(Economy.Stock)
    if not productionCmp or not stock then return end

    for _, line in ipairs(productionCmp:getLines()) do
        local recipe = Productions:getDefinition(line.id)
        if recipe then
            if not line.running then
                -- Idle: start when the store has what the recipe needs
                if takeInputs(stock, recipe) then
                    line.running = true
                    line.progress = 0
                end
            else
                line.progress = line.progress + dt
                if line.progress >= recipe.duration then
                    for _, entry in ipairs(recipe.outputs) do
                        stock:add(entry.item.id, entry.count)
                    end
                    line.running = false
                    line.progress = 0
                end
            end
        end
    end
end

--- Move every station's production on.
---@param stations Entity[]
---@param dt number real seconds
function ProductionSystem:update(stations, dt)
    local scaled = dt * Config.game.production.timeScale
    if scaled <= 0 then return end
    for _, station in ipairs(stations) do
        if station:isValid() then updateStation(station, scaled) end
    end
end

--- What a station is doing, for the docked screen: one row per line,
--- `{ recipe, running, progress (0..1) }`.
---@param station Entity
---@return table[]
function ProductionSystem:status(station)
    local productionCmp = station:get(Economy.Production)
    if not productionCmp then return {} end
    local rows = {}
    for _, line in ipairs(productionCmp:getLines()) do
        local recipe = Productions:getDefinition(line.id)
        if recipe then
            rows[#rows + 1] = {
                recipe = recipe,
                running = line.running,
                progress = recipe.duration > 0 and math.min(1, line.progress / recipe.duration) or 0,
            }
        end
    end
    return rows
end

return ProductionSystem
