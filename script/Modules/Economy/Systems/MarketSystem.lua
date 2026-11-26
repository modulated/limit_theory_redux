local Items = require("Shared.Registries.Items")
local Economy = require("Modules.Economy.Components")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")

--- The market: every station has an order book, and what a thing is worth
--- there is what someone will pay for it.
---
--- Nothing has a price of its own. A station posts buy orders for what its
--- production lines need and sell orders for what it is sitting on, priced
--- from the item's base value and how badly it needs it
--- (`StationTradeSystem:basePrice`, which is now only the station's opinion,
--- not the price). Everyone else -- the player, the NPC haulers -- trades
--- against those orders or posts their own, and a trade happens at the price
--- of the order that was already there. Undercut the best ask by a credit and
--- you get the next buyer.
---
--- The player can trade two ways:
---  * at the market: take the best orders now, for whatever they are asking;
---  * with a limit order: name a price and wait. Credits are escrowed for a
---    buy order and the goods taken for a sell order, both refunded if it is
---    cancelled or lapses. Placing one costs a broker's fee
---    (`Config.game.market.brokerFee`), and a sale pays tax
---    (`salesTax`) -- the two reasons not to place orders carelessly.
---
--- Orders are per station: to trade a market you dock at it. The books of
--- nearby systems can be *read* from what was last seen of them
--- (`MarketIntel`), which is where the price differences worth flying for
--- show up.
---@class MarketSystem
local MarketSystem = {}

--- Who the goods and credits move through for the player's side of a trade.
--- Set by the game state (`LTheoryRedux`): `hangar(key)` is the player's
--- store at that station and `cargo()` their ship's hold.
---@type table|nil
MarketSystem.player = nil

--- Tell the market where the player's goods live.
---@param accessors table { hangar = fun(key: string): StockComponent, cargo = fun(): StockComponent }
function MarketSystem:setPlayerAccess(accessors)
    self.player = accessors
end

---@param station Entity
---@return OrderBookComponent
function MarketSystem:book(station)
    local book = station:get(Economy.OrderBook)
    if not book then book = station:add(Economy.OrderBook()) end
    return book
end

--- What the player's goods are held in at a station: the hangar, so an order
--- is backed by goods that are actually there.
---@param key string
---@return StockComponent|nil
function MarketSystem:playerStore(key)
    if not self.player or not self.player.hangar then return nil end
    return self.player.hangar(key)
end

------------------------------------------------------------------------------
-- Quotes
------------------------------------------------------------------------------

--- What an item stands at here: the best bid, the best ask, the last trade
--- and how much is wanted and offered.
---@param station Entity
---@param itemId integer
---@return table { bid, ask, last, lastAt, bidUnits, askUnits, volume }
function MarketSystem:quote(station, itemId)
    local book = self:book(station)
    local last, lastAt = book:last(itemId)
    local bidUnits, askUnits = book:depth(itemId)
    return {
        bid = book:bid(itemId),
        ask = book:ask(itemId),
        last = last,
        lastAt = lastAt,
        bidUnits = bidUnits,
        askUnits = askUnits,
        volume = book:getVolume(itemId),
    }
end

--- Everything with an order or a trade at this station, best first by item id.
---@param station Entity
---@return table[] rows { item, bid, ask, last, bidUnits, askUnits }
function MarketSystem:listing(station)
    local book = self:book(station)
    local rows = {}
    for _, itemId in ipairs(book:items()) do
        local def = Items:getDefinition(itemId)
        if def then
            local quote = self:quote(station, itemId)
            quote.item = def
            rows[#rows + 1] = quote
        end
    end
    return rows
end

------------------------------------------------------------------------------
-- Settlement
------------------------------------------------------------------------------

--- Hand `units` of an item to the buyer and the credits to the seller, for
--- one fill at `price`. Returns what the player paid or was paid, after tax.
---@param station Entity
---@param key string the station key, for the player's store
---@param buy MarketOrder
---@param sell MarketOrder
---@param units integer
---@param price integer
---@return integer playerCredits what the player's wallet moved by (negative: paid)
local function settle(station, key, buy, sell, units, price)
    local cfg = Config.game.market
    local stock = station:get(Economy.Stock)
    local hangar = MarketSystem:playerStore(key)
    local gross = price * units
    local walletChange = 0

    -- The seller hands over the goods
    if sell.owner == "station" then
        if stock then stock:remove(sell.itemId, units) end
    else
        -- A player's sell order holds its goods already (escrowUnits)
        sell.escrowUnits = math.max(0, (sell.escrowUnits or units) - units)
        local tax = math.floor(gross * cfg.salesTax)
        PlayerWallet:add(gross - tax, "Market sale")
        walletChange = walletChange + (gross - tax)
    end

    -- The buyer takes them
    if buy.owner == "station" then
        if stock then stock:add(buy.itemId, units) end
        StationTradeSystem:invalidate(station)
    else
        if hangar then
            local added = hangar:add(buy.itemId, units)
            if added < units and stock then
                -- Nowhere to put the rest: the station keeps it
                stock:add(buy.itemId, units - added)
            end
        end
        -- Paid out of the credits the order escrowed
        buy.escrowCredits = math.max(0, (buy.escrowCredits or gross) - gross)
    end
    return walletChange
end

------------------------------------------------------------------------------
-- Orders
------------------------------------------------------------------------------

--- How many units a station could still honour of its own order: it sells
--- only what it has, and buys only up to what it wants to hold.
---@param station Entity
---@param order MarketOrder
---@return integer
local function stationCapacity(station, order)
    local stock = station:get(Economy.Stock)
    if not stock then return 0 end
    if order.side == "sell" then
        return stock:count(order.itemId)
    end
    local ceiling = math.floor(StationTradeSystem:targetStock(station, order.itemId)
        * Config.game.trade.buyCeiling)
    return math.max(0, ceiling - stock:count(order.itemId))
end

--- Match an incoming order against the book, and rest what is left of it (a
--- market order rests nothing).
---
--- `price` of nil means "at the market": take whatever the other side is
--- asking, best first.
---@param station Entity
---@param key string
---@param side string "buy" or "sell"
---@param itemId integer
---@param units integer
---@param price integer|nil the worst price acceptable, nil for the market
---@param owner string "player" or "station"
---@param rest boolean|nil rest the remainder in the book (a limit order)
---@return table result { filled, units, credits, average, resting, fee, reason }
function MarketSystem:submit(station, key, side, itemId, units, price, owner, rest)
    local cfg = Config.game.market
    local book = self:book(station)
    local result = { filled = 0, credits = 0, fee = 0 }
    units = math.floor(units or 0)
    if units <= 0 then
        result.reason = "nothing to trade"
        return result
    end
    local def = Items:getDefinition(itemId)
    if not def then
        result.reason = "no such item"
        return result
    end

    local incoming = {
        side = side, itemId = itemId, price = price, units = units, owner = owner,
        placedAt = self.now or 0,
    }
    local otherSide = side == "buy" and "sell" or "buy"
    local hangar = self:playerStore(key)

    -- The player's own goods and credits have to be there before anything
    -- trades: a sell takes the goods out of the hangar, a buy holds credits.
    if owner == "player" then
        if side == "sell" then
            if not hangar then
                result.reason = "no hangar here"
                return result
            end
            local held = hangar:count(itemId)
            if held < units then units = held end
            if units <= 0 then
                result.reason = "none of that in the hangar"
                return result
            end
            incoming.units = units
            incoming.escrowUnits = hangar:remove(itemId, units)
        end
    end

    -- Cross the book: trade against what is already there, at its price
    while incoming.units > 0 do
        local resting = book:best(otherSide, itemId)
        if not resting then break end
        local crosses = price == nil
            or (side == "buy" and resting.price <= price)
            or (side == "sell" and resting.price >= price)
        if not crosses then break end

        local available = resting.units
        if resting.owner == "station" then
            -- A station sells only what it has and buys only up to what it
            -- wants to hold; an order it can no longer honour comes off
            available = math.min(available, stationCapacity(station, resting))
            if available <= 0 then
                book:remove(resting)
                goto continue
            end
        end
        local fill = math.min(incoming.units, available)

        -- The player pays for each fill as it happens, at the resting price,
        -- which is never worse than the limit they named
        if side == "buy" and owner == "player" then
            local affordable = math.floor(PlayerWallet:get() / resting.price)
            fill = math.min(fill, affordable)
            if fill <= 0 then
                result.reason = "not enough credits"
                break
            end
            PlayerWallet:remove(resting.price * fill, "Market purchase: " .. def.displayName)
            incoming.escrowCredits = (incoming.escrowCredits or 0) + resting.price * fill
        end

        local buyOrder = side == "buy" and incoming or resting
        local sellOrder = side == "buy" and resting or incoming
        settle(station, key, buyOrder, sellOrder, fill, resting.price)
        book:recordTrade(itemId, resting.price, fill, self.now or 0)

        result.filled = result.filled + fill
        result.credits = result.credits + resting.price * fill
        incoming.units = incoming.units - fill
        resting.units = resting.units - fill
        if resting.units <= 0 then book:remove(resting) end
        ::continue::
    end

    -- What is left of a limit order waits in the book, backed by credits (a
    -- buy) or by the goods already taken (a sell), and costs a broker's fee
    if rest and incoming.units > 0 and price then
        if owner == "player" then
            local value = price * incoming.units
            local fee = math.ceil(value * cfg.brokerFee)
            local needed = side == "buy" and value + fee or fee
            if not PlayerWallet:remove(needed, side == "buy"
                    and "Market order and broker fee" or "Broker fee") then
                -- Cannot back the rest of it: give back what it was holding
                if incoming.escrowUnits and incoming.escrowUnits > 0 and hangar then
                    hangar:add(itemId, incoming.escrowUnits)
                    incoming.escrowUnits = 0
                end
                result.reason = result.filled > 0
                    and "filled what it could; no credits for the rest"
                    or "not enough credits for the order and the fee"
                return result
            end
            if side == "buy" then incoming.escrowCredits = value end
            result.fee = fee
        end
        incoming.escrowCredits = incoming.escrowCredits or 0
        incoming.expiresAt = (self.now or 0) + cfg.orderLifetime
        book:insert(incoming)
        result.resting = incoming
    elseif incoming.escrowUnits and incoming.escrowUnits > 0 and hangar then
        -- A market sell with nobody left to buy: the rest goes back
        hangar:add(itemId, incoming.escrowUnits)
        incoming.escrowUnits = 0
    end

    if result.filled > 0 then
        result.average = result.credits / result.filled
    end
    return result
end

--- Buy at the market: take the best asks until `units` are bought or nothing
--- is cheap enough.
---@param station Entity
---@param key string
---@param itemId integer
---@param units integer
---@return table result
function MarketSystem:buyAtMarket(station, key, itemId, units)
    return self:submit(station, key, "buy", itemId, units, nil, "player", false)
end

--- Sell at the market: hit the best bids. Whatever nobody bids for the
--- station will take as scrap (`Config.game.market.scrapFactor` of what it
--- reckons the thing is worth), so a hold of something unwanted is never
--- simply stuck -- but a scrap sale is not a market price and does not go in
--- the book's history.
---@param station Entity
---@param key string
---@param itemId integer
---@param units integer
---@return table result with `scrapped` and `scrapCredits` when some went for scrap
function MarketSystem:sellAtMarket(station, key, itemId, units)
    local result = self:submit(station, key, "sell", itemId, units, nil, "player", false)
    local hangar = self:playerStore(key)
    local left = math.min(units - result.filled, hangar and hangar:count(itemId) or 0)
    if left <= 0 then return result end

    local cfg = Config.game.market
    local price = math.max(1, math.floor(StationTradeSystem:basePrice(station, itemId)
        * cfg.scrapFactor))
    local taken = hangar:remove(itemId, left)
    if taken <= 0 then return result end
    StationTradeSystem:deliver(station, itemId, taken)
    local gross = price * taken
    local tax = math.floor(gross * cfg.salesTax)
    PlayerWallet:add(gross - tax, "Sold as scrap")
    result.scrapped = taken
    result.scrapCredits = gross - tax
    result.credits = result.credits + gross
    if result.filled + taken > 0 then
        result.average = result.credits / (result.filled + taken)
    end
    return result
end

--- Place a limit order at a price of the player's choosing.
---@param station Entity
---@param key string
---@param side string
---@param itemId integer
---@param units integer
---@param price integer
---@return table result
function MarketSystem:placeOrder(station, key, side, itemId, units, price)
    return self:submit(station, key, side, itemId, units, math.max(1, math.floor(price)),
        "player", true)
end

--- Cancel an order and give back what it was holding.
---@param station Entity
---@param key string
---@param order MarketOrder
---@return boolean cancelled
function MarketSystem:cancel(station, key, order)
    local book = self:book(station)
    if not book:remove(order) then return false end
    if order.owner ~= "player" then return true end
    if order.side == "buy" and (order.escrowCredits or 0) > 0 then
        PlayerWallet:add(order.escrowCredits, "Cancelled order")
    elseif order.side == "sell" and (order.escrowUnits or 0) > 0 then
        local hangar = self:playerStore(key)
        if hangar then hangar:add(order.itemId, order.escrowUnits) end
    end
    order.escrowCredits, order.escrowUnits = 0, 0
    return true
end

--- The player's orders here.
---@param station Entity
---@return MarketOrder[]
function MarketSystem:playerOrders(station)
    local book = self:book(station)
    local mine = {}
    for _, side in ipairs({ "buy", "sell" }) do
        for _, order in ipairs(book:allOrders(side)) do
            if order.owner == "player" then mine[#mine + 1] = order end
        end
    end
    table.sort(mine, function(a, b)
        if a.itemId ~= b.itemId then return a.itemId < b.itemId end
        return a.side < b.side
    end)
    return mine
end

------------------------------------------------------------------------------
-- What the station itself posts
------------------------------------------------------------------------------

--- Re-post a station's own orders: a bid for everything it deals in until it
--- holds all it wants of it, and an offer of whatever it has beyond the
--- reserve it keeps back. Both sit either side of its own valuation
--- (`StationTradeSystem:basePrice`, the base value scaled by how short it
--- is), so a station short of ore bids over the odds for it and one drowning
--- in iron offers it cheap and bids next to nothing. The price anyone trades
--- at is then whatever these and everyone else's orders come to.
---@param station Entity
---@param now number the game clock
function MarketSystem:refreshStation(station, now)
    local cfg = Config.game.market
    local book = self:book(station)
    local stock = station:get(Economy.Stock)
    if not stock then return end
    book:removeOwner("station")

    local reserve = cfg.reserveShare
    for _, row in ipairs(StationTradeSystem:listing(station)) do
        local itemId = row.item.id
        local target = StationTradeSystem:targetStock(station, itemId)
        local held = stock:count(itemId)
        local base = StationTradeSystem:basePrice(station, itemId)
        local ceiling = math.floor(target * Config.game.trade.buyCeiling)

        -- It bids for anything it deals in until it is sitting on all it
        -- wants. The price is its own valuation less a margin, and that
        -- valuation falls as the shelves fill, so a station awash with ore
        -- still bids -- just insultingly.
        if held < ceiling then
            local wanted = math.max(1, math.floor((ceiling - held) * cfg.orderShare))
            book:insert({
                side = "buy", itemId = itemId, price = math.max(1, math.floor(base * (1 - cfg.stationMargin))),
                units = wanted, owner = "station", placedAt = now,
            })
        end

        -- And offers whatever it holds beyond the reserve it keeps back, at
        -- its valuation plus the margin.
        local keeping = math.floor(target * reserve)
        if held > keeping then
            local offered = math.max(1, math.floor((held - keeping) * cfg.orderShare))
            book:insert({
                side = "sell", itemId = itemId, price = math.max(1, math.ceil(base * (1 + cfg.stationMargin))),
                units = offered, owner = "station", placedAt = now,
            })
        end
    end
    station.marketRefreshedAt = now
end

--- Keep the books honest: the station's orders are re-posted every so often
--- as its stock moves, and orders that have lapsed are taken out and what
--- they held given back.
---@param stations Entity[]
---@param keys table<Entity, string> each station's key, for the player's store
---@param dt number real seconds
---@param now number the game clock
function MarketSystem:update(stations, keys, dt, now)
    self.now = now
    local cfg = Config.game.market
    for _, station in ipairs(stations) do
        if station:isValid() then
            local book = self:book(station)
            local key = keys and keys[station] or nil

            -- Lapsed orders
            for _, side in ipairs({ "buy", "sell" }) do
                for _, order in ipairs(book:allOrders(side)) do
                    if order.expiresAt and now >= order.expiresAt then
                        self:cancel(station, key, order)
                    end
                end
            end

            if not station.marketRefreshedAt
                or now - station.marketRefreshedAt >= cfg.refreshInterval then
                self:refreshStation(station, now)
            end
        end
    end
end

return MarketSystem
