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
--- A line also needs hands: `Config.game.production.workersPerLine` of the
--- station's `Workforce`, which is its standing crew plus the workers docked
--- there (`Modules/NPC/Jobs/Work.lua`). The station's own lines claim crew
--- first and the lines the player has rented take what is left
--- (`PlayerFactories`), so a system whose worker shuttles have been shot down
--- has idle factories.
---
--- Legacy's durations are in real seconds, from 4 s for a waste recycler to
--- 4 hours for a station fabricator. `Config.game.production.timeScale`
--- compresses them so a factory does something visible within a session.
---@class ProductionSystem
local ProductionSystem = {}

--- The item group whose outputs never block a line (`ItemDefs.lua`).
local WASTE_GROUP = "Waste"

--- What a recipe's inputs are worth, at equilibrium prices: how much has to
--- reach the station for one run.
---@param recipe ProductionDefinition
---@return number
local function inputValue(recipe)
    local value = 0
    for _, entry in ipairs(recipe.inputs) do
        local price = entry.item.startEquilibriumPrice or Config.game.trade.defaultPrice
        value = value + price * entry.count
    end
    return value
end

--- The recipes of a class a lone station could actually keep running: ones
--- whose inputs are cheap enough to mine, make or import. The ship-part
--- factories and the drydocks need a supply chain (freighters hauling
--- glassiron and steel in), so they are left out until there is one -- a
--- line that can never complete a run is worse than no line at all.
---@param class string
---@return ProductionDefinition[]
local function affordableRecipes(class)
    local limit = Config.game.production.maxLineInputValue
    local list = {}
    for _, recipe in ipairs(Productions:ofClass(class)) do
        if inputValue(recipe) <= limit then list[#list + 1] = recipe end
    end
    return list
end

--- The recipes a station runs, picked from its seed: a powerplant always (it
--- needs energy, and so does everything else), plus a refinery or a factory
--- or two. Drydocks are rare: one station in a system at most, and only if
--- the seed says so.
---@param station Entity
---@param rng RNG
---@param allowDrydock boolean|nil
---@param oreIds integer[]|nil the ores of this system: a refinery that eats one of them is preferred
---@return ProductionComponent
function ProductionSystem:assign(station, rng, allowDrydock, oreIds)
    local cfg = Config.game.production
    local function pick(class)
        local list = affordableRecipes(class)
        if #list == 0 then return nil end
        return list[rng:getInt(1, #list)]
    end

    -- A refinery that runs on what the local belts hold, so the miners'
    -- ore has somewhere to go and the station is not living on imports
    local localRefineries = {}
    if oreIds and #oreIds > 0 then
        local isLocal = {}
        for _, id in ipairs(oreIds) do isLocal[id] = true end
        for _, recipe in ipairs(affordableRecipes(ProductionDefinition.Class.Refinery)) do
            for _, entry in ipairs(recipe.inputs) do
                if isLocal[entry.item.id] then
                    localRefineries[#localRefineries + 1] = recipe
                    break
                end
            end
        end
    end
    local function pickRefinery()
        if #localRefineries > 0 and rng:getUniform() < cfg.localRefineryChance then
            return localRefineries[rng:getInt(1, #localRefineries)]
        end
        return pick(ProductionDefinition.Class.Refinery)
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
        local recipe = rng:getUniform() < cfg.refineryChance
            and pickRefinery()
            or pick(Class.Factory)
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

--- Whether there is any room left for what a recipe makes. A station is a
--- warehouse, not a bottomless pit: once every output of a line is piled up
--- past `Config.game.production.stockCeiling` times what the station likes
--- to keep, the line stops until the goods move. Without this a line with no
--- inputs (a solar array) runs for ever and buries the system in its output.
---@param station Entity
---@param stock StockComponent
---@param recipe ProductionDefinition
---@return boolean
local function hasRoomForOutputs(station, stock, recipe)
    local ceiling = Config.game.production.stockCeiling
    for _, entry in ipairs(recipe.outputs) do
        -- Waste is vented when there is nowhere to put it (see storeOutputs),
        -- so a full waste bin never stops a line
        if entry.item.group ~= WASTE_GROUP then
            local target = StationTradeSystem:targetStock(station, entry.item.id)
            if stock:count(entry.item.id) >= target * ceiling then return false end
        end
    end
    return true
end

--- Put a finished run's outputs in the store. Waste past the ceiling is
--- vented rather than kept: a station is not a rubbish tip, and without this
--- the waste of every recipe would eventually block the whole floor.
---@param station Entity
---@param stock StockComponent
---@param recipe ProductionDefinition
local function storeOutputs(station, stock, recipe)
    local ceiling = Config.game.production.stockCeiling
    for _, entry in ipairs(recipe.outputs) do
        local full = entry.item.group == WASTE_GROUP
            and stock:count(entry.item.id) >= StationTradeSystem:targetStock(station, entry.item.id) * ceiling
        if not full then
            stock:add(entry.item.id, entry.count)
        end
    end
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
    local workforce = station:get(Economy.Workforce)
    local needed = Config.game.production.workersPerLine

    for _, line in ipairs(productionCmp:getLines()) do
        local recipe = Productions:getDefinition(line.id)
        -- Hands first: a line with no one on it neither starts nor advances.
        -- One already running keeps what it has taken and waits.
        line.crewed = not workforce or workforce:claim(needed)
        if recipe and line.crewed then
            if not line.running then
                -- Idle: start when the store has what the recipe needs, and
                -- somewhere to put what it makes
                if hasRoomForOutputs(station, stock, recipe) and takeInputs(stock, recipe) then
                    line.running = true
                    line.progress = 0
                end
            else
                line.progress = line.progress + dt
                if line.progress >= recipe.duration then
                    storeOutputs(station, stock, recipe)
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
        if station:isValid() then
            -- A fresh tick: nobody is claimed yet, the station's own lines
            -- claim here, and PlayerFactories claims what is left after
            local workforce = station:get(Economy.Workforce)
            if workforce then workforce:beginTick() end
            updateStation(station, scaled)
        end
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
            local stock = station:get(Economy.Stock)
            rows[#rows + 1] = {
                recipe = recipe,
                running = line.running,
                progress = recipe.duration > 0 and math.min(1, line.progress / recipe.duration) or 0,
                -- Why an idle line is idle, for the docked screen
                crewed = line.crewed ~= false,
                full = not line.running and stock ~= nil
                    and not hasRoomForOutputs(station, stock, recipe),
            }
        end
    end
    return rows
end

return ProductionSystem
