local Items = require("Shared.Registries.Items")
local Economy = require("Modules.Economy.Components")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")

--- The station's shop: what it holds, what it pays, what it charges.
---
--- A station's prices come from its own shelves. Each item it trades in has a
--- target stock; the price is the item's equilibrium price scaled by how far
--- the shelves are from that target, so a refinery that is drowning in iron
--- sells it cheap, and a station whose energy cells have run out pays over
--- the odds for them. Production and the ore the miners bring in move the
--- stock, so the prices follow what the system is actually doing. The spread
--- between what a station pays and what it charges is the house's cut.
---
--- This is the port of Legacy's Elements/Economy/Market.lua and Trader.lua,
--- in the shape the rest of the new code works in: stock on the station
--- entity, credits through `PlayerWallet`, no per-unit order entities. The
--- order-book `MarketplaceSystem` is still there for NPC-to-NPC trading.
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

--- Everything the station deals in, in item order, with its stock and prices:
--- `{ item, units, buy, sell }` (`buy`: what you pay it per unit; `sell`:
--- what it pays you).
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
                buy = self:buyPrice(station, id),
                sell = self:sellPrice(station, id),
            }
        end
    end
    table.sort(rows, function(a, b) return a.item.id < b.item.id end)
    return rows
end

--- The item's price here before the spread: its equilibrium price, scaled by
--- how short of its target the shelves are.
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

--- What the player pays the station for one unit.
---@param station Entity
---@param itemId integer
---@return integer
function StationTradeSystem:buyPrice(station, itemId)
    local spread = Config.game.trade.spread
    return math.max(1, math.ceil(self:basePrice(station, itemId) * (1 + spread)))
end

--- What the station pays the player for one unit.
---@param station Entity
---@param itemId integer
---@return integer
function StationTradeSystem:sellPrice(station, itemId)
    local spread = Config.game.trade.spread
    return math.max(1, math.floor(self:basePrice(station, itemId) * (1 - spread)))
end

--- How many units the player could buy: what is on the shelves, what the
--- credits cover and what the hold can take.
---@param station Entity
---@param hold StockComponent
---@param itemId integer
---@return integer
function StationTradeSystem:maxBuyable(station, hold, itemId)
    local stockCmp = station:get(Economy.Stock)
    if not stockCmp or not self:trades(station, itemId) then return 0 end
    local units = stockCmp:count(itemId)
    local price = self:buyPrice(station, itemId)
    local affordable = math.floor(PlayerWallet:get() / price)
    local room = hold:getRoomFor(itemId)
    return math.max(0, math.min(units, affordable, room))
end

--- Buy from the station into `hold`, paying out of the player's wallet. Buys
--- fewer units than asked when the shelves, the credits or the hold run out.
---@param station Entity
---@param hold StockComponent
---@param itemId integer
---@param units integer
---@return integer bought, integer spent
function StationTradeSystem:buy(station, hold, itemId, units)
    units = math.min(math.floor(units or 0), self:maxBuyable(station, hold, itemId))
    if units <= 0 then return 0, 0 end
    local def = Items:getDefinition(itemId)
    local stockCmp = station:get(Economy.Stock)
    -- Unit by unit: each one bought makes the next one dearer, so a big
    -- order moves the price instead of clearing the shelves at the first one
    local spent, bought = 0, 0
    for _ = 1, units do
        local price = self:buyPrice(station, itemId)
        if not PlayerWallet:has(price) then break end
        if stockCmp:remove(itemId, 1) < 1 then break end
        if hold:add(itemId, 1) < 1 then
            stockCmp:add(itemId, 1)
            break
        end
        PlayerWallet:remove(price, "Bought " .. def.displayName)
        spent = spent + price
        bought = bought + 1
    end
    return bought, spent
end

--- How many units the station will still take: it stops buying a thing once
--- it is sitting on `Config.game.trade.buyCeiling` times what it likes to
--- keep, so a hold full of one ore cannot be dumped on one station for ever.
---@param station Entity
---@param hold StockComponent
---@param itemId integer
---@return integer
function StationTradeSystem:maxSellable(station, hold, itemId)
    local stockCmp = station:get(Economy.Stock)
    if not stockCmp then return 0 end
    local ceiling = math.floor(self:targetStock(station, itemId) * Config.game.trade.buyCeiling)
    return math.max(0, math.min(hold:count(itemId), ceiling - stockCmp:count(itemId)))
end

--- Sell out of `hold` to the station.
---@param station Entity
---@param hold StockComponent
---@param itemId integer
---@param units integer
---@return integer sold, integer earned
function StationTradeSystem:sell(station, hold, itemId, units)
    local stockCmp = station:get(Economy.Stock)
    if not stockCmp then return 0, 0 end
    units = math.min(math.floor(units or 0), self:maxSellable(station, hold, itemId))
    if units <= 0 then return 0, 0 end
    local def = Items:getDefinition(itemId)
    -- A station buys anything that can be mined or made, whether it deals in
    -- it or not, but at a loss to the seller when it has no use for it
    local wanted = self:trades(station, itemId)
    local sold, earned = 0, 0
    for _ = 1, units do
        local price = self:sellPrice(station, itemId)
        if not wanted then
            price = math.max(1, math.floor(price * Config.game.trade.unwantedFactor))
        end
        if hold:remove(itemId, 1) < 1 then break end
        stockCmp:add(itemId, 1)
        PlayerWallet:add(price, "Sold " .. def.displayName)
        earned = earned + price
        sold = sold + 1
    end
    if sold > 0 and not wanted then
        -- It deals in it now: it has some
        self:invalidate(station)
    end
    return sold, earned
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
