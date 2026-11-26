local Component = require("Core.ECS.Component")

--- A station's market: the buy and sell orders standing in it, per item.
---
--- Buy orders (bids) are kept best first, which is the highest price; sell
--- orders (asks) best first, which is the lowest. A new order that crosses
--- the book trades against the resting orders at *their* price, oldest first
--- at the same price, which is what makes undercutting worth anything.
---
--- The component only holds the book and the trade history. Who may trade,
--- where the goods and credits come from and what the station itself posts
--- are `Modules/Economy/Systems/MarketSystem.lua`.
---
---@class OrderBookComponent: Component
---@overload fun(self: OrderBookComponent): OrderBookComponent subclass internal
---@overload fun(): OrderBookComponent subclass external
local OrderBookComponent = Subclass("OrderBookComponent", Component, function(self)
    self:setComponentName("EconomyOrderBook")
    --- itemId -> orders, best first
    self.bids = {}
    self.asks = {}
    --- itemId -> { price = number, at = number } of the last trade here
    self.lastTrade = {}
    --- itemId -> units traded here, all told
    self.volume = {}
    self.nextId = 1
end)

---@class MarketOrder
---@field id integer
---@field side string "buy" or "sell"
---@field itemId integer
---@field price integer credits a unit
---@field units integer units still wanted or offered
---@field owner string "station" or "player"
---@field placedAt number the game clock when it was placed
---@field expiresAt number|nil when it lapses
---@field escrowCredits integer|nil credits held against a player's buy order
---@field escrowUnits integer|nil goods held against a player's sell order

---@param side string "buy" or "sell"
---@param itemId integer
---@return MarketOrder[]
function OrderBookComponent:orders(side, itemId)
    local book = side == "buy" and self.bids or self.asks
    return book[itemId] or {}
end

--- Every order of one side, over every item.
---@param side string
---@return MarketOrder[]
function OrderBookComponent:allOrders(side)
    local book = side == "buy" and self.bids or self.asks
    local all = {}
    for _, orders in pairs(book) do
        for _, order in ipairs(orders) do all[#all + 1] = order end
    end
    return all
end

--- Put an order in the book, in its place. Does no matching: that is
--- `MarketSystem:place`.
---@param order MarketOrder
---@return MarketOrder order the same order, with an id
function OrderBookComponent:insert(order)
    if not order.id then
        order.id = self.nextId
        self.nextId = self.nextId + 1
    end
    local book = order.side == "buy" and self.bids or self.asks
    local orders = book[order.itemId]
    if not orders then
        orders = {}
        book[order.itemId] = orders
    end
    -- Best first: the highest bid, the lowest ask. Same price keeps the
    -- order it arrived in, so the first to offer a price is the first filled.
    local index = #orders + 1
    for i, resting in ipairs(orders) do
        local better = order.side == "buy" and order.price > resting.price
            or order.side == "sell" and order.price < resting.price
        if better then
            index = i
            break
        end
    end
    table.insert(orders, index, order)
    return order
end

--- Take an order out of the book.
---@param order MarketOrder
---@return boolean removed
function OrderBookComponent:remove(order)
    local book = order.side == "buy" and self.bids or self.asks
    local orders = book[order.itemId]
    if not orders then return false end
    for index, candidate in ipairs(orders) do
        if candidate == order then
            table.remove(orders, index)
            if #orders == 0 then book[order.itemId] = nil end
            return true
        end
    end
    return false
end

--- Drop every order of one owner (a station re-posting its own, a scene going).
---@param owner string
---@return MarketOrder[] removed
function OrderBookComponent:removeOwner(owner)
    local removed = {}
    for _, side in ipairs({ "buy", "sell" }) do
        local book = side == "buy" and self.bids or self.asks
        for itemId, orders in pairs(book) do
            for index = #orders, 1, -1 do
                if orders[index].owner == owner then
                    removed[#removed + 1] = table.remove(orders, index)
                end
            end
            if #orders == 0 then book[itemId] = nil end
        end
    end
    return removed
end

--- The best order of a side, or nil.
---@param side string
---@param itemId integer
---@return MarketOrder|nil
function OrderBookComponent:best(side, itemId)
    return self:orders(side, itemId)[1]
end

--- The highest anyone here will pay.
---@param itemId integer
---@return integer|nil
function OrderBookComponent:bid(itemId)
    local order = self:best("buy", itemId)
    return order and order.price or nil
end

--- The lowest anyone here will sell for.
---@param itemId integer
---@return integer|nil
function OrderBookComponent:ask(itemId)
    local order = self:best("sell", itemId)
    return order and order.price or nil
end

--- What it last changed hands for here, and when.
---@param itemId integer
---@return integer|nil price, number|nil at
function OrderBookComponent:last(itemId)
    local trade = self.lastTrade[itemId]
    if not trade then return nil, nil end
    return trade.price, trade.at
end

--- Record a trade.
---@param itemId integer
---@param price integer
---@param units integer
---@param at number the game clock
function OrderBookComponent:recordTrade(itemId, price, units, at)
    self.lastTrade[itemId] = { price = price, at = at }
    self.volume[itemId] = (self.volume[itemId] or 0) + units
end

---@param itemId integer
---@return integer units traded here all told
function OrderBookComponent:getVolume(itemId)
    return self.volume[itemId] or 0
end

--- How much is wanted and offered, for the depth column.
---@param itemId integer
---@return integer bidUnits, integer askUnits
function OrderBookComponent:depth(itemId)
    local bidUnits, askUnits = 0, 0
    for _, order in ipairs(self:orders("buy", itemId)) do bidUnits = bidUnits + order.units end
    for _, order in ipairs(self:orders("sell", itemId)) do askUnits = askUnits + order.units end
    return bidUnits, askUnits
end

--- Every item with an order or a trade here, by id.
---@return integer[]
function OrderBookComponent:items()
    local seen, ids = {}, {}
    local function add(id)
        if not seen[id] then
            seen[id] = true
            ids[#ids + 1] = id
        end
    end
    for id in pairs(self.bids) do add(id) end
    for id in pairs(self.asks) do add(id) end
    for id in pairs(self.lastTrade) do add(id) end
    table.sort(ids)
    return ids
end

return OrderBookComponent
