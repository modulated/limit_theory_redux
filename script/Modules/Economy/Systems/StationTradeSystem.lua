local Items = require("Shared.Registries.Items")
local Economy = require("Modules.Economy.Components")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")

--- A station's own side of the economy: what it holds, what it thinks things
--- are worth, what it is short of and what arrives from off screen.
---
--- Nothing here is a price the player pays. Prices are the order book's
--- (`Modules/Economy/Systems/MarketSystem.lua`); this is the station's
--- *valuation*, which is what it posts its own orders at. Each item it deals
--- in has a target stock, and `basePrice` is the item's base value scaled by
--- how far its shelves are from that target, so a refinery drowning in iron
--- values it at less than one that has run out. Production, the ore the
--- miners bring and every trade on the book move the stock, so the
--- valuations follow what the system is actually doing.
---@class StationTradeSystem
local StationTradeSystem = {}

--- What a station trades in: everything it can make, everything those
--- recipes need, and the ores of its system. Built once per station.
---@param station Entity
---@return table<integer, boolean>
local function tradedItems(station)
    local traded = {}
    local productionCmp = station:get(Economy.Production)
    for _, recipe in ipairs(productionCmp and productionCmp:getRecipes() or {}) do
        for _, entry in ipairs(recipe.inputs) do traded[entry.item.id] = true end
        for _, entry in ipairs(recipe.outputs) do traded[entry.item.id] = true end
    end
    local stockCmp = station:get(Economy.Stock)
    for _, row in ipairs(stockCmp and stockCmp:list() or {}) do
        traded[row.item.id] = true
    end
    return traded
end

--- The station's price table, made on demand and kept on the entity.
---@param station Entity
---@return table { traded = table<integer, boolean>, target = table<integer, number> }
local function book(station)
    local cmp = station:get(Economy.Stock)
    if not cmp then return { traded = {}, target = {} } end
    if cmp.tradeBook then return cmp.tradeBook end
    local cfg = Config.game.trade
    local traded = tradedItems(station)
    local target = {}
    for id in pairs(traded) do
        local def = Items:getDefinition(id)
        -- A target by value: a station keeps about as much *worth* of each
        -- thing, so it is not sitting on a thousand ship computers.
        local price = def and def.startEquilibriumPrice or cfg.defaultPrice
        target[id] = math.max(cfg.minTargetUnits, math.floor(cfg.targetValue / math.max(1, price)))
    end
    cmp.tradeBook = { traded = traded, target = target }
    return cmp.tradeBook
end

--- Forget the price table (after its recipes or its stock change in bulk).
---@param station Entity
function StationTradeSystem:invalidate(station)
    local cmp = station:get(Economy.Stock)
    if cmp then
        cmp.tradeBook = nil
        cmp.producedItems = nil
    end
end

--- How much of an item this station likes to keep on the shelves: the
--- target its prices are measured against, and what its production lines
--- treat as a full store.
---@param station Entity
---@param itemId integer
---@return number
function StationTradeSystem:targetStock(station, itemId)
    local cfg = Config.game.trade
    local target = book(station).target[itemId]
    if target then return target end
    local def = Items:getDefinition(itemId)
    local price = def and def.startEquilibriumPrice or cfg.defaultPrice
    return math.max(cfg.minTargetUnits, math.floor(cfg.targetValue / math.max(1, price)))
end

--- Does this station deal in the item at all?
---@param station Entity
---@param itemId integer
---@return boolean
function StationTradeSystem:trades(station, itemId)
    return book(station).traded[itemId] == true
end

--- Everything the station deals in, in item order, with what it holds and
--- what it reckons each is worth: `{ item, units, value }`.
---@param station Entity
---@return table[]
function StationTradeSystem:listing(station)
    local stockCmp = station:get(Economy.Stock)
    if not stockCmp then return {} end
    local rows = {}
    for id in pairs(book(station).traded) do
        local def = Items:getDefinition(id)
        if def then
            rows[#rows + 1] = {
                item = def,
                units = stockCmp:count(id),
                value = self:basePrice(station, id),
            }
        end
    end
    table.sort(rows, function(a, b) return a.item.id < b.item.id end)
    return rows
end

--- What the station reckons an item is worth here: its base value, scaled by
--- how short of its target the shelves are. The station's own orders are
--- posted either side of this; the price anyone actually trades at is the
--- book's.
---@param station Entity
---@param itemId integer
---@return number
function StationTradeSystem:basePrice(station, itemId)
    local cfg = Config.game.trade
    local def = Items:getDefinition(itemId)
    local base = def and def.startEquilibriumPrice or cfg.defaultPrice
    local b = book(station)
    local target = b.target[itemId]
    if not target or target <= 0 then return base end
    local stockCmp = station:get(Economy.Stock)
    local units = stockCmp and stockCmp:count(itemId) or 0
    -- Scarcity: 1 at the target, above it when short, below when flooded.
    -- Bounded both ways so nothing becomes free or priceless.
    local scarcity = (target + cfg.priceSoftness) / (units + cfg.priceSoftness)
    scarcity = math.max(cfg.minScarcity, math.min(cfg.maxScarcity, scarcity))
    return base * scarcity
end







--- Put goods in a station's store without money changing hands (an NPC
--- miner unloading its hold, the initial stock).
---@param station Entity
---@param itemId integer
---@param units integer
---@return integer added
function StationTradeSystem:deliver(station, itemId, units)
    local stockCmp = station:get(Economy.Stock)
    if not stockCmp then return 0 end
    local added = stockCmp:add(itemId, units)
    if added > 0 and not self:trades(station, itemId) then
        self:invalidate(station)
    end
    return added
end

--- What a station's own lines can make.
---@param station Entity
---@return table<integer, boolean>
local function produced(station)
    local cmp = station:get(Economy.Stock)
    if cmp and cmp.producedItems then return cmp.producedItems end
    local made = {}
    local productionCmp = station:get(Economy.Production)
    for _, recipe in ipairs(productionCmp and productionCmp:getRecipes() or {}) do
        for _, entry in ipairs(recipe.outputs) do made[entry.item.id] = true end
    end
    if cmp then cmp.producedItems = made end
    return made
end

--- The trickle of goods a station cannot make itself and nothing local
--- brings it: what the freighters nobody sees unload. It only reaches a
--- fraction of the station's target, so an imported thing stays dear and a
--- local one stays the better buy — and it keeps a refinery from dying for
--- want of an input no station in the system produces.
---@param stations Entity[]
---@param dt number real seconds
function StationTradeSystem:update(stations, dt)
    local cfg = Config.game.trade
    local rate = cfg.importPerSecond * dt
    if rate <= 0 then return end
    for _, station in ipairs(stations) do
        if station:isValid() then
            local stockCmp = station:get(Economy.Stock)
            if stockCmp then
                local b = book(station)
                local made = produced(station)
                stockCmp.importAcc = stockCmp.importAcc or {}
                for id, target in pairs(b.target) do
                    local ceiling = math.floor(target * cfg.importFloor)
                    local held = stockCmp:count(id)
                    if not made[id] and held < ceiling then
                        local acc = (stockCmp.importAcc[id] or 0) + rate
                        local whole = math.floor(acc)
                        stockCmp.importAcc[id] = acc - whole
                        -- Never past the ceiling, however long the step was
                        whole = math.min(whole, ceiling - held)
                        if whole > 0 then stockCmp:add(id, whole) end
                    end
                end
            end
        end
    end
end

--- Give a station its shop: the stock it opens with, around the target for
--- everything it deals in, and a little of the system's ore.
---@param station Entity
---@param rng RNG
---@param oreIds integer[]|nil the ores of this system, from its belts
function StationTradeSystem:stock(station, rng, oreIds)
    local stockCmp = station:get(Economy.Stock)
    if not stockCmp then
        stockCmp = station:add(Economy.Stock())
    end
    local cfg = Config.game.trade
    self:invalidate(station)

    -- The ore of the system, so there is something to buy on day one
    for _, id in ipairs(oreIds or {}) do
        local def = Items:getDefinition(id)
        if def then
            local price = def.startEquilibriumPrice or cfg.defaultPrice
            local target = math.max(cfg.minTargetUnits, math.floor(cfg.targetValue / math.max(1, price)))
            stockCmp:set(id, math.floor(target * rng:getUniformRange(cfg.startStockMin, cfg.startStockMax)))
        end
    end

    -- Whatever its recipes deal in
    self:invalidate(station)
    local b = book(station)
    for id, target in pairs(b.target) do
        if stockCmp:count(id) == 0 then
            stockCmp:set(id, math.floor(target * rng:getUniformRange(cfg.startStockMin, cfg.startStockMax)))
        end
    end
    self:invalidate(station)
end

return StationTradeSystem
