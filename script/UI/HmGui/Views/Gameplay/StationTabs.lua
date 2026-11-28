-- The docked screen's tabs, laid out like the station mockups (each draws
-- the whole main area of StationFrame, in design pixels at 1920 x 1080):
--
--   Hangar        the station hangar | a transfer column | the active ship
--                 and its hold; the player's other ships and hulls here
--   Market        browse | the item: its quote, the sell and buy orders,
--                 your orders | trade: buy or sell, now or as an order
--   Ship fitting  what the hangar has to fit | the ship's mounts and slots
--                 by kind | what the fit comes to, and the selected slot
--   Bounty board  the open bounties and your contracts | the one selected
--
-- The other tabs (factory, nearby, forces) are the Station view's own, in a
-- panel of the same look.

local Items = require("Shared.Registries.Items")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local PlayerCargo = require("Modules.Economy.Managers.PlayerCargo")
local MarketSystem = require("Modules.Economy.Systems.MarketSystem")
local PlayerStations = require("Modules.Economy.Managers.PlayerStations")
local PlayerFactories = require("Modules.Economy.Managers.PlayerFactories")
local BountyBoard = require("Modules.Economy.Managers.BountyBoard")
local ShipFittingSystem = require("Modules.Constructs.Systems.ShipFittingSystem")
local PlayerFleet = require("Modules.Constructs.Managers.PlayerFleet")
local Hulls = require("Shared.Registries.Hulls")
local StationFrame = require("UI.HmGui.Views.Gameplay.StationFrame")

local C, F = StationFrame.C, StationFrame.F
local px, txt, cell = StationFrame.px, StationFrame.txt, StationFrame.cell
local grouped, clip = StationFrame.grouped, StationFrame.clip
local button, rule = StationFrame.button, StationFrame.rule
local RIGHT = AlignHorizontal.Right

local StationTabs = {}

-- What each tab has picked, kept while the screen is open
local state = {
    hangar = { where = nil, itemId = nil, qty = nil, filter = "all" },
    market = { itemId = nil, side = "buy", qty = 1, price = nil, filter = "all" },
    fitting = { slot = nil, filter = "all" },
    bounty = { index = 1 },
}
StationTabs.state = state

local function game() return LimitTheoryRedux end
local function stationKey()
    local dock = game().docked
    return dock and dock.key or nil
end
local function notify(text, ok)
    game():notify(text, ok == false and { 1.0, 0.4, 0.3 } or { 0.6, 0.9, 1.0 })
end

------------------------------------------------------------------------------
-- A typed whole number: an editable field per id, made again when a button
-- changes the number (and keeping what is typed otherwise)

local fields = {}
---@param id string
---@param value integer
---@param onTyped fun(n: integer)
---@return table UIComponent
local function numberField(id, value, onTyped)
    local f = fields[id]
    if f and f.value ~= value then f = nil end
    if not f then
        f = {
            value = value,
            view = UIComponent.TextView {
                text = tostring(value),
                editable = true,
                multiline = false,
                style = {
                    font = { size = px(16), family = "FiraMono" },
                    brush = C.TEXT,
                    selectionBrush = C.SELECT,
                    cursorBrush = C.TEXT,
                },
                width = px(90),
                backgroundColor = C.BG,
                align = { AlignHorizontal.Right, AlignVertical.Center },
                callback = function() end,
            },
        }
        fields[id] = f
    end
    local ok, typed = pcall(function() return require("ffi").string(f.view.state.textData():text()) end)
    local n = ok and tonumber((typed or ""):match("^%s*(%d+)%s*$"))
    if n and n >= 1 and n ~= f.value then
        n = math.min(n, 1000000000)
        f.value = n
        onTyped(n)
    end
    return f.view
end

------------------------------------------------------------------------------
-- Trading

local function buyNow(station, itemId, units)
    local def = Items:getDefinition(itemId)
    local result = MarketSystem:buyAtMarket(station, stationKey(), itemId, units)
    if result.filled > 0 then
        notify(string.format("Bought %d %s for %s (%.0f a unit)", result.filled, def.displayName,
            PlayerWallet.format(result.credits), result.average or 0))
    else
        notify("Nothing on offer: " .. (result.reason or "no sellers"), false)
    end
end

local function sellNow(station, itemId, units)
    local def = Items:getDefinition(itemId)
    local result = MarketSystem:sellAtMarket(station, stationKey(), itemId, units)
    local sold = result.filled + (result.scrapped or 0)
    if sold > 0 then
        local note = (result.scrapped or 0) > 0
            and string.format(" (%d of it as scrap: nobody was bidding)", result.scrapped) or ""
        notify(string.format("Sold %d %s for %s, %.0f a unit%s", sold, def.displayName,
            PlayerWallet.format(result.credits), result.average or 0, note))
    else
        notify("Could not sell: " .. (result.reason or "nothing to sell"), false)
    end
end

local function placeOrder(station, side, itemId, units, price)
    local result = MarketSystem:placeOrder(station, stationKey(), side, itemId, units, price)
    if result.filled > 0 and result.resting then
        notify(string.format("%d filled at once, %d standing at %d", result.filled, result.resting.units, price))
    elseif result.filled > 0 then
        notify(string.format("Filled %d at an average of %.0f", result.filled, result.average or 0))
    elseif result.resting then
        notify(string.format("%s order standing: %d at %d", side == "buy" and "Buy" or "Sell",
            result.resting.units, price))
    else
        notify("Order refused: " .. (result.reason or "no"), false)
    end
end

--- Move goods between two stores; says what happened
local function move(item, from, to, units, what)
    if units < 1 then return end
    local taken = from:remove(item.id, units)
    local put = to:add(item.id, taken)
    if put < taken then from:add(item.id, taken - put) end
    if put > 0 then
        notify(string.format("Moved %d %s %s", put, item.displayName, what))
    else
        notify("No room for that.", false)
    end
end

--- What filling `units` at the market would cost (buying) or bring
--- (selling): walks the book's best orders. Returns credits, units filled.
local function marketFill(station, side, itemId, units)
    local book = MarketSystem:book(station)
    local orders = book:orders(side == "buy" and "sell" or "buy", itemId)
    local sorted = {}
    for _, o in ipairs(orders) do sorted[#sorted + 1] = o end
    table.sort(sorted, function(a, b)
        if side == "buy" then return a.price < b.price end
        return a.price > b.price
    end)
    local credits, filled = 0, 0
    for _, o in ipairs(sorted) do
        if filled >= units then break end
        if o.owner ~= "player" then
            local take = math.min(units - filled, o.units)
            credits = credits + take * o.price
            filled = filled + take
        end
    end
    return credits, filled
end

--- Who an order is from, in a word
local function ownerName(order)
    if order.owner == "player" then return "you" end
    if order.owner == "station" then return "this station" end
    if order.owner == "npc" then return "trader" end
    return tostring(order.owner or "-")
end

------------------------------------------------------------------------------
-- HANGAR

local HANGAR_FILTERS = {
    { id = "all", label = "ALL" },
    { id = "ore", label = "ORE & METALS" },
    { id = "equip", label = "EQUIPMENT" },
    { id = "cons", label = "CONSUMABLES" },
    { id = "other", label = "OTHER" },
}
local function hangarKind(item)
    local g = item.group or ""
    if g == "Raw Materials" or g == "Refined Materials" or g == "Gases" then return "ore" end
    if g == "Equipment" or g == "Constructs" then return "equip" end
    if g == "Consumables" or g == "Data" then return "cons" end
    return "other"
end

function StationTabs.hangar(station, W, H)
    local st = state.hangar
    local key = stationKey()
    local store = key and PlayerFactories:hangar(key)
    local hold = PlayerCargo:get()
    if not store then
        StationFrame.panel(W, H, { pad = 24 })
        txt("No hangar here.", F.BODY, 16, C.DIM)
        StationFrame.endPanel()
        return
    end

    local midW = 132
    local leftW = math.floor((W - midW - 48) * 0.58)
    local rightW = W - midW - 48 - leftW

    -- What the player's other ships and spare hulls here are
    local parked = PlayerFleet:parkedAt(key)
    local spareHulls = {}
    for _, row in ipairs(store:list()) do
        local itsHull = Hulls:forItem(row.item.id)
        if itsHull then spareHulls[#spareHulls + 1] = { hull = itsHull, units = row.units } end
    end
    local shipCards = #parked + #spareHulls
    local shipsH = shipCards > 0 and (70 + math.ceil(shipCards / 2) * 76) or 0
    local listH = H - (shipsH > 0 and shipsH + 16 or 0)

    -- The station hangar
    local all = store:list()
    local rows = {}
    for _, row in ipairs(all) do
        if st.filter == "all" or hangarKind(row.item) == st.filter then rows[#rows + 1] = row end
    end
    local totalValue = 0
    for _, row in ipairs(all) do
        local q = station and MarketSystem:quote(station, row.item.id)
        totalValue = totalValue + (q and (q.bid or q.last) or 0) * row.units
    end

    Gui:beginVerticalContainer()
    Gui:setFixedWidth(px(leftW))
    Gui:setSpacing(px(16))
    StationFrame.panel(leftW, listH)
    StationFrame.titleBar("STATION HANGAR", string.format("%d stacks  ·  %s / %s t", #all,
        grouped(store:getUsedMass()), grouped(store:getCapacity() or 0)))
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(px(20), px(12))
    local pick = StationFrame.filters(HANGAR_FILTERS, st.filter)
    if pick then st.filter = pick end
    Gui:endContainer()
    rule()
    local nameW = leftW - 40 - 36 - 110 - 110 - 150 - 64
    StationFrame.columns({ { 36, "" }, { nameW, "ITEM" }, { 110, "QTY", RIGHT }, { 110, "MASS", RIGHT },
        { 150, "EST. VALUE", RIGHT } })
    local visible = math.max(1, math.floor((listH - 62 - 56 - 36 - 50 - 24) / 56))
    local first, last = StationFrame.list("hangar", #rows, visible, 56)
    if #rows == 0 then
        Gui:beginStackContainer()
        Gui:setPadding(px(20), px(14))
        txt(#all == 0 and "Nothing in your hangar here." or "Nothing of that kind.", F.BODY, 14, C.DIM)
        Gui:endContainer()
    end
    for i = first, last do
        local row = rows[i]
        local q = station and MarketSystem:quote(station, row.item.id)
        local price = q and (q.bid or q.last)
        local _, click = StationFrame.row(56, st.where == "hangar" and st.itemId == row.item.id)
        StationFrame.badge(row.item, 36)
        StationFrame.twoLine(nameW, clip(row.item.displayName, 34), row.item.group)
        cell(110, grouped(row.units), F.MONO, 14, C.TEXT, RIGHT)
        cell(110, grouped((row.item.mass or 0) * row.units) .. " t", F.MONO, 14, C.SUB, RIGHT)
        cell(150, price and grouped(price * row.units) or "-", F.MONO, 14, price and C.CYAN or C.DIM, RIGHT)
        StationFrame.endRow()
        if click then st.where, st.itemId, st.qty = "hangar", row.item.id, nil end
    end
    StationFrame.endList()
    StationFrame.more(#rows, last)
    StationFrame.footer("HANGAR TOTAL", grouped(totalValue) .. " CR")
    StationFrame.endPanel()

    -- Stored ships and hulls
    if shipsH > 0 then
        StationFrame.panel(leftW, shipsH, { pad = 20, padY = 16, spacing = 12 })
        txt("STORED SHIPS", F.HEAD, 16, C.SUB)
        local cards = {}
        for _, other in ipairs(parked) do
            local otherHull = PlayerFleet.hullOf(other)
            cards[#cards + 1] = {
                name = other.name,
                line = string.format("%s  ·  %s", otherHull and otherHull.displayName or "?", PlayerFleet.describe(other)),
                label = "BOARD",
                act = function() game():flyShip(other) end,
            }
        end
        for _, row in ipairs(spareHulls) do
            cards[#cards + 1] = {
                name = string.format("%s hull  x%d", row.hull.displayName, row.units),
                line = "A new ship starts with nothing in it",
                label = "FIT OUT",
                act = function() game():commissionHull(row.hull) end,
            }
        end
        local cardW = math.floor((leftW - 40 - 12) / 2)
        for i = 1, #cards, 2 do
            Gui:beginHorizontalContainer()
            Gui:setSpacing(px(12))
            for j = i, math.min(i + 1, #cards) do
                local card = cards[j]
                Gui:beginStackContainer()
                Gui:setFixedSize(px(cardW), px(64))
                Gui:setBackgroundColor(C.BG)
                Gui:setBorderWidth(1)
                Gui:setBorderColor(C.RULE)
                Gui:setPadding(px(16), 0)
                Gui:beginVerticalContainer()
                Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
                txt(clip(card.name, 30), F.HEAD_SEMI, 16, C.TEXT)
                txt(clip(card.line, 46), F.BODY, 12, C.DIM)
                Gui:endContainer()
                Gui:beginStackContainer()
                Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
                if button(card.label, { kind = "outline", height = 40, size = 14 }) then card.act() end
                Gui:endContainer()
                Gui:endContainer()
            end
            Gui:endContainer()
        end
        StationFrame.endPanel()
    end
    Gui:endContainer()

    -- The transfer column
    local item = st.itemId and Items:getDefinition(st.itemId)
    local from = st.where == "hold" and hold or store
    local have = item and from:count(item.id) or 0
    if item and have == 0 then st.itemId, item = nil, nil end
    Gui:beginVerticalContainer()
    Gui:setFixedSize(px(midW), px(H))
    Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:setSpacing(px(14))
    txt("SELECTED", F.BODY_SEMI, 12, C.DIM)
    if item then
        StationFrame.badge(item, 44)
        txt(clip(item.displayName, 16), F.HEAD_SEMI, 15, C.AMBER)
        txt(st.where == "hold" and "in your hold" or "in the hangar", F.BODY, 12, C.DIM)
        st.qty = math.max(1, math.min(st.qty or have, have))
        txt("QTY", F.BODY_SEMI, 12, C.DIM)
        Gui:beginStackContainer()
        Gui:setFixedSize(px(110), px(40))
        Gui:setBackgroundColor(C.BG)
        Gui:setBorderWidth(1)
        Gui:setBorderColor(C.EDGE)
        numberField("hangarQty", st.qty, function(n) st.qty = math.min(n, have) end):render()
        Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
        Gui:endContainer()
        Gui:beginHorizontalContainer()
        Gui:setSpacing(px(4))
        if button("1", { width = 34, height = 30, size = 12, pad = 2 }) then st.qty = 1 end
        if button("½", { width = 34, height = 30, size = 12, pad = 2 }) then st.qty = math.max(1, math.floor(have / 2)) end
        if button("ALL", { width = 34, height = 30, size = 11, pad = 2 }) then st.qty = have end
        Gui:endContainer()
    else
        txt("Pick a row", F.BODY, 13, C.DIM)
    end
    if button("SHIP  >", { kind = "primary", width = 120, height = 52, size = 15,
            enabled = item ~= nil and st.where == "hangar" }) then
        move(item, store, hold, st.qty, "to the ship")
    end
    if button("<  HANGAR", { kind = "outline", width = 120, height = 52, size = 15,
            enabled = item ~= nil and st.where == "hold" }) then
        move(item, hold, store, st.qty, "to the hangar")
    end
    if item and st.where == "hangar" and station then
        if button("SELL ALL", { width = 120, height = 36, size = 12 }) then sellNow(station, item.id, have) end
    end
    Gui:endContainer()

    -- The active ship and its hold
    StationFrame.activeShip(rightW, H, {
        station = station,
        selected = st.where == "hold" and st.itemId or nil,
        onPick = function(id) st.where, st.itemId, st.qty = "hold", id, nil end,
        rows = math.floor((H - 380) / 56),
    })
end

------------------------------------------------------------------------------
-- MARKET

local MARKET_FILTERS = {
    { id = "all", label = "ALL" },
    { id = "hangar", label = "IN HANGAR" },
    { id = "cargo", label = "IN CARGO" },
}

function StationTabs.market(station, W, H)
    local st = state.market
    local key = stationKey()
    local store = key and PlayerFactories:hangar(key)
    local hold = PlayerCargo:get()
    local cfg = Config.game.market
    local owned = PlayerStations.isOwnedKey(key)

    -- Everything traded here, and what the player holds that is not
    local rows, seen = {}, {}
    for _, row in ipairs(MarketSystem:listing(station)) do
        seen[row.item.id] = true
        rows[#rows + 1] = { item = row.item, bid = row.bid, ask = row.ask, last = row.last }
    end
    for _, src in ipairs({ store, hold }) do
        for _, r in ipairs(src and src:list() or {}) do
            if not seen[r.item.id] then
                seen[r.item.id] = true
                rows[#rows + 1] = { item = r.item, scrap = true }
            end
        end
    end
    local shown = {}
    for _, row in ipairs(rows) do
        local inH = store and store:count(row.item.id) or 0
        local inC = hold:count(row.item.id)
        if st.filter == "all" or (st.filter == "hangar" and inH > 0) or (st.filter == "cargo" and inC > 0) then
            shown[#shown + 1] = row
        end
    end
    if not st.itemId or not seen[st.itemId] then st.itemId = rows[1] and rows[1].item.id or nil end

    local browseW, tradeW = 340, 400
    local midW = W - browseW - tradeW - 48

    -- Browse
    StationFrame.panel(browseW, H)
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(px(16), px(16))
    Gui:setSpacing(px(12))
    txt("BROWSE", F.HEAD, 19, C.TEXT)
    local pick = StationFrame.filters(MARKET_FILTERS, st.filter)
    if pick then st.filter = pick end
    Gui:endContainer()
    rule()
    local visible = math.max(1, math.floor((H - 120 - 30) / 58))
    local first, last = StationFrame.list("market", #shown, visible, 58)
    if #shown == 0 then
        Gui:beginStackContainer()
        Gui:setPadding(px(16), px(14))
        txt("Nothing here.", F.BODY, 14, C.DIM)
        Gui:endContainer()
    end
    for i = first, last do
        local row = shown[i]
        local _, click = StationFrame.row(58, st.itemId == row.item.id, 16, 10)
        StationFrame.twoLine(browseW - 32 - 100 - 10, clip(row.item.displayName, 24),
            row.scrap and "not traded here: scrap only" or row.item.group)
        local label = row.ask and ("ask " .. grouped(row.ask)) or (row.bid and ("bid " .. grouped(row.bid)) or "-")
        cell(100, label, F.MONO, 13, row.scrap and C.DIM or C.CYAN, RIGHT)
        StationFrame.endRow()
        if click and st.itemId ~= row.item.id then st.itemId, st.price = row.item.id, nil end
    end
    StationFrame.endList()
    StationFrame.more(#shown, last, 16)
    StationFrame.endPanel()

    local item = st.itemId and Items:getDefinition(st.itemId)
    local quote = item and MarketSystem:quote(station, item.id) or {}
    local inH = item and store and store:count(item.id) or 0
    local inC = item and hold:count(item.id) or 0

    -- The item, its orders, your orders
    Gui:beginVerticalContainer()
    Gui:setFixedSize(px(midW), px(H))
    Gui:setSpacing(px(16))
    local cardH = 210
    StationFrame.panel(midW, cardH)
    Gui:beginHorizontalContainer()
    Gui:setPadding(px(24), px(20))
    Gui:setSpacing(px(24))
    Gui:beginVerticalContainer()
    Gui:setFixedWidth(px(math.floor(midW * 0.46)))
    Gui:setSpacing(px(6))
    if item then
        txt((item.group or ""):upper(), F.BODY_SEMI, 12, C.DIM)
        txt(clip(item.displayName, 28), F.HEAD, 30, C.TEXT)
        txt(string.format("%s t / unit    Hangar %s    Cargo %s", grouped(item.mass or 0), grouped(inH), grouped(inC)),
            F.MONO, 13, C.SUB)
        StationFrame.gap(1, 8)
        Gui:beginHorizontalContainer()
        Gui:setSpacing(px(32))
        StationFrame.stat("BEST SELL", quote.ask and grouped(quote.ask) or "-", C.AMBER)
        StationFrame.stat("BEST BUY", quote.bid and grouped(quote.bid) or "-", C.CYAN)
        StationFrame.stat("LAST TRADE", quote.last and grouped(quote.last) or "-", C.TEXT)
        Gui:endContainer()
    else
        txt("Pick something to trade.", F.BODY, 15, C.DIM)
    end
    Gui:endContainer()
    -- Your orders here
    local mine = MarketSystem:playerOrders(station)
    Gui:beginVerticalContainer()
    Gui:setSpacing(px(6))
    txt(string.format("YOUR ORDERS HERE  ·  %d", #mine), F.BODY_SEMI, 12, C.DIM)
    if #mine == 0 then
        txt("None standing. Place one from the trade panel.", F.BODY, 13, C.DIM)
    end
    for i, order in ipairs(mine) do
        if i > 4 then
            txt(string.format("... and %d more", #mine - 4), F.BODY, 12, C.DIM)
            break
        end
        local def = Items:getDefinition(order.itemId)
        Gui:beginHorizontalContainer()
        Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
        Gui:setSpacing(px(10))
        cell(44, order.side == "buy" and "BUY" or "SELL", F.HEAD, 14, order.side == "buy" and C.CYAN or C.AMBER)
        cell(150, clip(def and def.displayName or "?", 18), F.BODY, 13, C.TEXT)
        cell(120, string.format("%s @ %s", grouped(order.units), grouped(order.price)), F.MONO, 13, C.SUB, RIGHT)
        if button("CANCEL", { height = 26, size = 11, pad = 8 }) then
            MarketSystem:cancel(station, key, order)
            notify("Order cancelled; the broker keeps the fee.")
        end
        Gui:endContainer()
    end
    Gui:endContainer()
    Gui:endContainer()
    StationFrame.endPanel()

    -- The sell and buy orders
    local bookW = math.floor((midW - 16) / 2)
    local bookH = H - cardH - 16
    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(16))
    local book = MarketSystem:book(station)
    for _, side in ipairs({ "sell", "buy" }) do
        local orders = {}
        for _, o in ipairs(item and book:orders(side, item.id) or {}) do orders[#orders + 1] = o end
        table.sort(orders, function(a, b)
            if side == "sell" then return a.price < b.price end
            return a.price > b.price
        end)
        local color = side == "sell" and C.AMBER or C.CYAN
        StationFrame.panel(bookW, bookH)
        Gui:beginHorizontalContainer()
        Gui:setPadding(px(20), px(14))
        Gui:setSpacing(px(10))
        Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
        Gui:beginStackContainer()
        Gui:setFixedSize(px(10), px(10))
        Gui:setBackgroundColor(color)
        Gui:endContainer()
        txt(side == "sell" and "SELL ORDERS" or "BUY ORDERS", F.HEAD, 16, C.TEXT)
        txt(side == "sell" and "you buy from these" or "you sell to these", F.BODY, 13, C.DIM)
        Gui:endContainer()
        rule()
        local fromW = bookW - 40 - 110 - 100 - 32
        StationFrame.columns({ { 110, "PRICE", RIGHT }, { 100, "QTY", RIGHT }, { fromW, "FROM" } })
        local vis = math.max(1, math.floor((bookH - 52 - 36 - 10) / 34))
        local f1, l1 = StationFrame.list("book" .. side, #orders, vis, 34)
        if #orders == 0 then
            Gui:beginStackContainer()
            Gui:setPadding(px(20), px(12))
            txt("None.", F.BODY, 13, C.DIM)
            Gui:endContainer()
        end
        for i = f1, l1 do
            local o = orders[i]
            local mineRow = o.owner == "player"
            local _, click = StationFrame.row(34, false)
            cell(110, grouped(o.price), F.MONO, 14, color, RIGHT)
            cell(100, grouped(o.units), F.MONO, 14, C.TEXT, RIGHT)
            cell(fromW, ownerName(o), F.BODY, 13, mineRow and C.AMBER or C.SUB)
            StationFrame.endRow()
            -- Clicking an order trades against it at its price
            if click then
                st.side = side == "sell" and "buy" or "sell"
                st.price = o.price
            end
        end
        StationFrame.endList()
        StationFrame.more(#orders, l1)
        StationFrame.endPanel()
    end
    Gui:endContainer()
    Gui:endContainer()

    -- Trade
    StationFrame.panel(tradeW, H, { pad = 20, spacing = 18 })
    Gui:beginHorizontalContainer()
    for _, side in ipairs({ "buy", "sell" }) do
        local on = st.side == side
        Gui:beginStackContainer()
        Gui:setFixedSize(px((tradeW - 40) / 2), px(44))
        local hover = Gui:isMouseOver(FocusType.Mouse)
        Gui:setBackgroundColor(on and (side == "buy" and C.CYAN or C.AMBER) or (hover and C.SELECT or C.NONE))
        Gui:setBorderWidth(1)
        Gui:setBorderColor(C.EDGE)
        txt(side:upper(), F.HEAD, 17, on and C.BG or C.SUB)
        Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
        Gui:endContainer()
        if hover and Input:mouse():isPressed(MouseControl.Left) and not on then st.side, st.price = side, nil end
    end
    Gui:endContainer()

    if not item then
        txt("Pick something to trade.", F.BODY, 14, C.DIM)
        StationFrame.endPanel()
        return
    end
    local buying = st.side == "buy"

    -- Where the goods are
    Gui:beginVerticalContainer()
    Gui:setSpacing(px(8))
    txt(buying and "DELIVERED TO" or "SOLD FROM", F.BODY_SEMI, 12, C.DIM)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(8))
    local boxW = math.floor((tradeW - 40 - 8) / 2)
    StationFrame.tile(boxW, "STATION HANGAR", grouped(inH), buying and C.CYAN or C.TEXT)
    StationFrame.tile(boxW, "SHIP CARGO", grouped(inC), C.TEXT)
    Gui:endContainer()
    if not buying and inC > 0 then
        if button(string.format("MOVE %s FROM CARGO TO HANGAR", grouped(inC)), { height = 32, size = 12 }) then
            move(item, hold, store, inC, "to the hangar")
        end
    end
    Gui:endContainer()

    -- How many, at what
    local maxUnits = buying and 1000000 or math.max(1, inH)
    st.qty = math.max(1, math.min(st.qty or 1, buying and 1000000000 or math.max(1, inH)))
    local best = buying and (quote.ask or quote.bid or quote.last) or (quote.bid or quote.ask or quote.last)
    st.price = math.max(1, st.price or math.floor(best or item.startEquilibriumPrice or 10))
    Gui:beginVerticalContainer()
    Gui:setSpacing(px(8))
    txt("QUANTITY", F.BODY_SEMI, 12, C.DIM)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(6))
    st.qty = math.max(1, StationFrame.stepper(st.qty, { { "-10", -10 }, { "-", -1 }, { "+", 1 }, { "+10", 10 } },
        numberField("marketQty", st.qty, function(n) st.qty = n end), 110))
    if button("MAX", { height = 40, size = 12, pad = 8 }) then
        if buying then
            local unitPrice = quote.ask or st.price
            st.qty = math.max(1, math.floor(PlayerWallet:get() / math.max(1, unitPrice)))
        else
            st.qty = math.max(1, inH)
        end
    end
    Gui:endContainer()
    txt("PRICE PER UNIT  (for an order)", F.BODY_SEMI, 12, C.DIM)
    local stepPrice = math.max(1, math.floor(st.price * 0.1))
    st.price = math.max(1, StationFrame.stepper(st.price,
        { { "-10%", -stepPrice, width = 56 }, { "-1", -1 }, { "+1", 1 }, { "+10%", stepPrice, width = 56 } }, nil, 110))
    Gui:endContainer()
    st.qty = math.min(st.qty, buying and 1000000000 or math.max(1, inH))

    -- What it comes to
    local now, nowUnits = marketFill(station, st.side, item.id, st.qty)
    local orderValue = st.price * st.qty
    local fee = owned and 0 or math.ceil(orderValue * cfg.brokerFee)
    local tax = (buying or owned) and 0 or math.ceil(orderValue * cfg.salesTax)
    local total = buying and (orderValue + fee) or (orderValue - fee - tax)
    StationFrame.panel(tradeW - 40, nil, { pad = 16, spacing = 10, fill = C.BG })
    local function line(label, value, color, size)
        Gui:beginStackContainer()
        Gui:setFixedWidth(px(tradeW - 72))
        txt(label, F.MONO, size or 14, C.DIM)
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
        txt(value, F.MONO, size or 14, color or C.TEXT)
        Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
        Gui:endContainer()
    end
    line(buying and "Market now" or "Market now",
        nowUnits > 0 and string.format("%s for %s", grouped(nowUnits), grouped(now)) or "no one", nowUnits > 0 and C.TEXT or C.DIM)
    line("Order subtotal", grouped(orderValue))
    line(string.format("Broker fee %.1f%%", owned and 0 or cfg.brokerFee * 100), grouped(fee))
    if not buying then line(string.format("Sales tax %.1f%%", owned and 0 or cfg.salesTax * 100), grouped(tax)) end
    line("Mass", grouped((item.mass or 0) * st.qty) .. " t")
    rule()
    line(buying and "ORDER TOTAL" or "ORDER NETS", grouped(total) .. " CR", buying and C.CYAN or C.AMBER, 17)
    StationFrame.endPanel()

    -- Do it
    local canNow = buying and (quote.ask ~= nil) or (inH > 0)
    if button(buying and string.format("BUY %s NOW", grouped(st.qty)) or string.format("SELL %s NOW", grouped(st.qty)),
            { kind = "primary", width = tradeW - 40, height = 52, size = 18, enabled = canNow }) then
        if buying then buyNow(station, item.id, st.qty) else sellNow(station, item.id, math.min(st.qty, inH)) end
    end
    local canOrder = buying and PlayerWallet:has(orderValue + fee) or (not buying and inH >= st.qty and PlayerWallet:has(fee))
    if button(string.format("PLACE %s ORDER AT %s", buying and "BUY" or "SELL", grouped(st.price)),
            { kind = "outline", width = tradeW - 40, height = 46, size = 15, enabled = canOrder }) then
        placeOrder(station, st.side, item.id, st.qty, st.price)
    end
    StationFrame.para(tradeW - 40, buying
        and "Bought goods go to your hangar here. Credits for an order are held until it fills, is cancelled or lapses."
        or "You sell from your hangar here: move goods out of the hold first. Goods for an order are held until it fills.",
        12, C.DIM)
    StationFrame.endPanel()
end

------------------------------------------------------------------------------
-- SHIP FITTING

local FIT_FILTERS = {
    { id = "all", label = "ALL" },
    { id = "weapon", label = "GUNS" },
    { id = "tool", label = "TOOLS" },
    { id = "module", label = "MODULES" },
}
local function fitKind(def)
    if def.slot ~= "weapon" then return "module" end
    return def.tool and "tool" or "weapon"
end
local KIND_COLOR = { weapon = C.AMBER, tool = C.ORE, module = C.CYAN }
local KIND_LETTER = { weapon = "W", tool = "T", module = "M" }
local SIZE_ORDER = { sm = 1, m = 2, l = 3, xl = 4 }

function StationTabs.fitting(station, W, H)
    local st = state.fitting
    local g = game()
    local key = stationKey()
    local ship = g.playerShip
    local ConstructComponents = require("Modules.Constructs.Components")
    local loadout = ship and ship:isValid() and ship:get(ConstructComponents.Loadout)
    if not loadout then
        StationFrame.panel(W, H, { pad = 24 })
        txt("This ship cannot be refitted.", F.BODY, 16, C.DIM)
        StationFrame.endPanel()
        return
    end
    local hangar = key and PlayerFactories:hangar(key)
    local flying = PlayerFleet:active()
    local hull = PlayerFleet.hullOf(flying)

    local function refresh()
        PlayerFleet:record(ship)
        g:applyFitToShip()
    end

    -- The slots: mounts by size, then the module slots
    local slots = {}
    for _, mount in ipairs(ShipFittingSystem:mounts(ship)) do
        slots[#slots + 1] = { kind = "mount", id = "mount:" .. mount.mountId, mountId = mount.mountId,
            size = mount.sizeClass, fitted = loadout:getWeapon(mount.mountId) }
    end
    for slot = 1, loadout:getModuleSlots() do
        slots[#slots + 1] = { kind = "module", id = "module:" .. slot, slot = slot, fitted = loadout:getModule(slot) }
    end
    local selected = nil
    for _, s in ipairs(slots) do if s.id == st.slot then selected = s end end
    if not selected then selected = slots[1]; st.slot = selected and selected.id end

    local function fits(def, s)
        if s.kind == "mount" then return def.slot == "weapon" and ShipFittingSystem:weaponFits(def, s.size) end
        return def.slot == "module" and ShipFittingSystem:moduleFits(def, loadout.hullClass)
    end
    local function fitInto(def, s)
        local ok, reason
        if s.kind == "mount" then
            ok, reason = ShipFittingSystem:fitWeapon(ship, hangar, s.mountId, def)
        else
            ok, reason = ShipFittingSystem:fitModule(ship, hangar, s.slot, def)
        end
        notify(ok and string.format("%s fitted", def.displayName) or ("Cannot fit: " .. (reason or "no")), ok)
        if ok then refresh() end
    end
    local function unfit(s)
        local ok
        if s.kind == "mount" then ok = ShipFittingSystem:unfitWeapon(ship, hangar, s.mountId)
        else ok = ShipFittingSystem:unfitModule(ship, hangar, s.slot) end
        if ok then
            refresh()
            notify(string.format("%s back in the hangar", s.fitted and s.fitted.displayName or "It"))
        end
    end

    local leftW, rightW = 380, 400
    local midW = W - leftW - rightW - 48

    -- Modules in the hangar
    local avail = {}
    for _, row in ipairs(ShipFittingSystem:fittableFrom(ship, hangar)) do
        if st.filter == "all" or fitKind(row.fitting) == st.filter then avail[#avail + 1] = row end
    end
    StationFrame.panel(leftW, H)
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(px(16), px(16))
    Gui:setSpacing(px(12))
    txt("IN THE HANGAR", F.HEAD, 19, C.TEXT)
    local pick = StationFrame.filters(FIT_FILTERS, st.filter, 80)
    if pick then st.filter = pick end
    Gui:endContainer()
    rule()
    local visible = math.max(1, math.floor((H - 120 - 70) / 58))
    local first, last = StationFrame.list("fitAvail", #avail, visible, 58)
    if #avail == 0 then
        Gui:beginStackContainer()
        Gui:setPadding(px(16), px(14))
        txt("Nothing here to fit. Buy parts on the market.", F.BODY, 14, C.DIM)
        Gui:endContainer()
    end
    for i = first, last do
        local row = avail[i]
        local kind = fitKind(row.fitting)
        local good = selected and fits(row.fitting, selected)
        local _, click = StationFrame.row(58, false, 16, 12)
        StationFrame.letter(KIND_LETTER[kind], KIND_COLOR[kind], 32)
        StationFrame.twoLine(leftW - 32 - 32 - 60 - 24,
            clip(row.fitting.displayName, 26),
            kind == "module" and string.format("class %s  ·  %s", row.fitting.moduleClass or "S",
                clip(row.fitting:describeEffects(), 26))
                or string.format("%s mount", tostring(row.fitting.sizeClass or "any"):upper()),
            good and C.TEXT or C.SUB)
        cell(60, "x" .. grouped(row.units), F.MONO, 14, C.SUB, RIGHT)
        StationFrame.endRow()
        if click then
            -- Into the selected slot if it takes it, else the first free one that does
            local target = good and selected or nil
            if not target then
                for _, s in ipairs(slots) do
                    if not s.fitted and fits(row.fitting, s) then target = s break end
                end
            end
            if target then fitInto(row.fitting, target)
            else notify(string.format("No %s slot here takes %s", kind == "module" and "module" or "mount",
                row.fitting.displayName), false) end
        end
    end
    StationFrame.endList()
    StationFrame.more(#avail, last, 16)
    rule()
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Bottom)
    Gui:setPadding(px(16), px(12))
    StationFrame.para(leftW - 32, "Click a part to fit it into the selected slot, or the first free slot that takes it.",
        13, C.DIM)
    Gui:endContainer()
    StationFrame.endPanel()

    -- The ship and its slots
    Gui:beginVerticalContainer()
    Gui:setFixedSize(px(midW), px(H))
    Gui:setSpacing(px(16))
    StationFrame.panel(midW, 96)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setPadding(px(24), px(18))
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    txt(flying and flying.name or "Your ship", F.HEAD, 28, C.TEXT)
    txt(hull and Hulls.describe(hull) or "", F.BODY, 14, C.DIM)
    Gui:endContainer()
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:setSpacing(px(16))
    txt(string.format("FIT: %s", PlayerFleet.describe(flying)), F.MONO, 13, C.CYAN)
    if button("STRIP ALL", { height = 38, size = 13, enabled = PlayerFleet.fittingCount(flying) > 0 }) then
        g:stripShip(flying)
    end
    Gui:endContainer()
    Gui:endContainer()
    StationFrame.endPanel()

    -- Groups: mounts by size, then modules
    local groups, byKey = {}, {}
    for _, s in ipairs(slots) do
        local gk = s.kind == "mount" and ("mount:" .. tostring(s.size)) or "module"
        if not byKey[gk] then
            byKey[gk] = {
                key = gk,
                label = s.kind == "mount" and string.format("%s MOUNTS  ·  GUNS & TOOLS", tostring(s.size or "any"):upper())
                    or string.format("MODULE SLOTS  ·  CLASS %s HULL", loadout.hullClass or "?"),
                color = s.kind == "mount" and C.AMBER or C.CYAN,
                order = s.kind == "mount" and (SIZE_ORDER[s.size] or 5) or 9,
                slots = {},
            }
            groups[#groups + 1] = byKey[gk]
        end
        table.insert(byKey[gk].slots, s)
    end
    table.sort(groups, function(a, b) return a.order < b.order end)
    local colW = math.floor((midW - 16) / 2)
    local columns = { {}, {} }
    local heights = { 0, 0 }
    for _, grp in ipairs(groups) do
        local hgt = 50 + #grp.slots * 60
        local c = heights[1] <= heights[2] and 1 or 2
        table.insert(columns[c], grp)
        heights[c] = heights[c] + hgt + 16
    end
    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(16))
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Top)
    for c = 1, 2 do
        Gui:beginVerticalContainer()
        Gui:setFixedWidth(px(colW))
        Gui:setSpacing(px(16))
        for _, grp in ipairs(columns[c]) do
            local used = 0
            for _, s in ipairs(grp.slots) do if s.fitted then used = used + 1 end end
            StationFrame.panel(colW, nil, { pad = 16, padY = 14, spacing = 8 })
            Gui:beginStackContainer()
            Gui:setFixedWidth(px(colW - 32))
            txt(grp.label, F.HEAD, 15, grp.color)
            Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
            txt(string.format("%d / %d", used, #grp.slots), F.MONO, 12, C.DIM)
            Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
            Gui:endContainer()
            for _, s in ipairs(grp.slots) do
                local on = s.id == st.slot
                Gui:beginStackContainer()
                Gui:setFixedSize(px(colW - 32), px(52))
                local hover = Gui:isMouseOver(FocusType.Mouse)
                Gui:setBackgroundColor(on and C.SELECT or (hover and C.HOVER or C.BG))
                Gui:setBorderWidth(1)
                Gui:setBorderColor(on and grp.color or (s.fitted and C.EDGE or C.DASH))
                if s.fitted then
                    Gui:beginStackContainer()
                    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Stretch)
                    Gui:setFixedWidth(px(3))
                    Gui:setBackgroundColor(grp.color)
                    Gui:endContainer()
                end
                Gui:beginVerticalContainer()
                Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
                Gui:setPadding(px(12), 0)
                txt(s.fitted and clip(s.fitted.displayName, 34) or (s.kind == "mount" and "Empty mount" or "Empty module slot"),
                    F.BODY_SEMI, 14, s.fitted and C.TEXT or C.DIM)
                txt(s.kind == "mount" and string.format("%s  ·  %s", s.mountId, tostring(s.size or "any"):upper())
                    or (s.fitted and clip(s.fitted:describeEffects(), 44) or string.format("slot %d", s.slot)),
                    F.MONO, 12, C.DIM)
                Gui:endContainer()
                Gui:endContainer()
                if hover and Input:mouse():isPressed(MouseControl.Left) then st.slot = s.id end
            end
            StationFrame.endPanel()
        end
        Gui:endContainer()
    end
    Gui:endContainer()
    Gui:endContainer()

    -- What the fit comes to, and the selected slot
    Gui:beginVerticalContainer()
    Gui:setFixedSize(px(rightW), px(H))
    Gui:setSpacing(px(16))
    local mountsUsed, mountsAll, modsUsed, modsAll = 0, 0, 0, 0
    for _, s in ipairs(slots) do
        if s.kind == "mount" then
            mountsAll = mountsAll + 1
            if s.fitted then mountsUsed = mountsUsed + 1 end
        else
            modsAll = modsAll + 1
            if s.fitted then modsUsed = modsUsed + 1 end
        end
    end
    local used, capacity = PlayerCargo:getLoad()
    StationFrame.panel(rightW, nil, { pad = 20, padY = 18, spacing = 12 })
    txt("RESOURCES", F.HEAD, 16, C.TEXT)
    for _, r in ipairs({
        { "MOUNTS", mountsUsed, mountsAll, "" },
        { "MODULE SLOTS", modsUsed, modsAll, "" },
        { "CARGO HOLD", used, capacity, " t" },
    }) do
        Gui:beginVerticalContainer()
        Gui:setSpacing(px(6))
        Gui:beginStackContainer()
        Gui:setFixedWidth(px(rightW - 40))
        txt(r[1], F.BODY_SEMI, 13, C.DIM)
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
        txt(string.format("%s / %s%s", grouped(r[2]), grouped(r[3]), r[4]), F.MONO, 13, C.TEXT)
        Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
        Gui:endContainer()
        local frac = r[3] > 0 and r[2] / r[3] or 0
        StationFrame.bar(rightW - 40, 8, frac, frac > 0.85 and C.AMBER or C.CYAN)
        Gui:endContainer()
    end
    StationFrame.endPanel()

    local stats = loadout.stats or {}
    StationFrame.panel(rightW, nil)
    for _, grp in ipairs({
        { "DEFENCE", { { grouped(stats.maxShield or 0), "Shield" }, { grouped(stats.armor or 0), "Armour" },
            { grouped(stats.maxHealth or 0), "Hull" } } },
        { "FLIGHT", { { string.format("x%.2f", stats.thrust or 1), "Thrust" }, { string.format("x%.2f", stats.turn or 1), "Turn" },
            { string.format("+%s t", grouped(stats.cargoMass or 0)), "Hold" } } },
    }) do
        Gui:beginVerticalContainer()
        Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
        Gui:setPadding(px(20), px(14))
        Gui:setSpacing(px(8))
        txt(grp[1], F.BODY_SEMI, 12, C.DIM)
        Gui:beginHorizontalContainer()
        for _, v in ipairs(grp[2]) do
            Gui:beginVerticalContainer()
            Gui:setFixedWidth(px(math.floor((rightW - 40) / 3)))
            txt(v[1], F.MONO_MED, 16, C.TEXT)
            txt(v[2], F.BODY, 12, C.DIM)
            Gui:endContainer()
        end
        Gui:endContainer()
        Gui:endContainer()
        rule()
    end
    StationFrame.endPanel()

    -- The selected slot
    StationFrame.panel(rightW, nil, { pad = 20, padY = 18, spacing = 10, accent = true })
    if selected then
        local f = selected.fitted
        txt(string.format("SELECTED SLOT  ·  %s", selected.kind == "mount"
            and (tostring(selected.size or "any"):upper() .. " MOUNT") or "MODULE"), F.BODY_SEMI, 12, C.AMBER)
        txt(f and clip(f.displayName, 28) or "Empty slot", F.HEAD, 22, C.TEXT)
        txt(f and (f.slot == "weapon" and string.format("%s mount%s", tostring(f.sizeClass or "any"):upper(),
                f.tool and "  ·  tool" or "") or string.format("class %s  ·  %s", f.moduleClass or "S", f:describeEffects()))
            or (selected.kind == "mount" and string.format("%s  ·  takes a %s gun or tool", selected.mountId,
                tostring(selected.size or "any"):upper()) or "Takes a module"), F.MONO, 13, C.SUB)
        StationFrame.para(rightW - 40, f and (f.description or "") or
            "Pick a part from the hangar on the left to fit it here.", 14, C.SUB)
        Gui:beginHorizontalContainer()
        Gui:setSpacing(px(8))
        if f then
            if button("UNFIT", { width = (rightW - 48) / 2, height = 44, size = 14 }) then unfit(selected) end
        end
        if button("BUY PARTS", { kind = "primary", width = (rightW - 48) / 2, height = 44, size = 14 }) then
            if StationTabs.goTo then StationTabs.goTo("market") end
        end
        Gui:endContainer()
    else
        txt("This hull has no slots.", F.BODY, 14, C.DIM)
    end
    StationFrame.endPanel()
    Gui:endContainer()
end

------------------------------------------------------------------------------
-- BOUNTY BOARD

local function threatOf(reward)
    if reward >= 4000 then return "HIGH", C.RED end
    if reward >= 1500 then return "MEDIUM", C.AMBER end
    return "LOW", C.GREEN
end

function StationTabs.bounties(station, W, H)
    local st = state.bounty
    local g = game()
    BountyBoard:refresh(g)
    local offers = BountyBoard.offers
    local contracts = BountyBoard.contracts
    local maxC = Config.game.bounties.maxContracts
    local detailW = 480
    local leftW = W - detailW - 24
    st.index = math.max(1, math.min(st.index or 1, math.max(1, #offers)))

    local contractsH = 80 + math.max(1, #contracts) * 64
    local tableH = H - contractsH - 16

    Gui:beginVerticalContainer()
    Gui:setFixedSize(px(leftW), px(H))
    Gui:setSpacing(px(16))
    StationFrame.panel(leftW, tableH)
    StationFrame.titleBar("OPEN BOUNTIES", string.format("%d posted  ·  in this system", #offers))
    local nameW = leftW - 40 - 170 - 260 - 110 - 130 - 64
    StationFrame.columns({ { nameW, "TARGET" }, { 170, "TYPE" }, { 260, "LAST SEEN" }, { 110, "THREAT" },
        { 130, "REWARD", RIGHT } })
    local visible = math.max(1, math.floor((tableH - 62 - 36 - 20) / 58))
    local first, last = StationFrame.list("bounties", #offers, visible, 58)
    if #offers == 0 then
        Gui:beginStackContainer()
        Gui:setPadding(px(20), px(14))
        txt("No pirate in this system has a price on its head just now.", F.BODY, 14, C.DIM)
        Gui:endContainer()
    end
    for i = first, last do
        local o = offers[i]
        local threat, tColor = threatOf(o.reward)
        local _, click = StationFrame.row(58, st.index == i)
        StationFrame.twoLine(nameW, "'" .. clip(o.callsign, 24) .. "'", "Pirate", C.TEXT, F.HEAD_SEMI)
        cell(170, clip(o.kind, 20), F.BODY, 14, C.SUB)
        cell(260, clip(o.area or "-", 32), F.BODY, 14, C.SUB)
        Gui:beginHorizontalContainer()
        Gui:setFixedWidth(px(110))
        Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
        Gui:setSpacing(px(8))
        Gui:beginStackContainer()
        Gui:setFixedSize(px(8), px(8))
        Gui:setBackgroundColor(tColor)
        Gui:endContainer()
        txt(threat, F.BODY_SEMI, 13, tColor)
        Gui:endContainer()
        cell(130, grouped(o.reward), F.MONO, 15, C.AMBER, RIGHT)
        StationFrame.endRow()
        if click then st.index = i end
    end
    StationFrame.endList()
    StationFrame.more(#offers, last)
    StationFrame.endPanel()

    StationFrame.panel(leftW, contractsH)
    StationFrame.titleBar("MY ACTIVE CONTRACTS", string.format("%d of %d", #contracts, maxC), nil, 17)
    Gui:beginVerticalContainer()
    Gui:setPadding(px(20), px(12))
    Gui:setSpacing(px(10))
    if #contracts == 0 then
        txt("None. Take one from the board; a contract ends if you leave the system.", F.BODY, 14, C.DIM)
    end
    for _, c in ipairs(contracts) do
        Gui:beginStackContainer()
        Gui:setFixedSize(px(leftW - 40), px(54))
        Gui:setBackgroundColor(C.BG)
        Gui:setBorderWidth(1)
        Gui:setBorderColor(C.RULE)
        Gui:setPadding(px(16), 0)
        Gui:beginVerticalContainer()
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
        txt("'" .. c.callsign .. "'  ·  " .. c.kind, F.HEAD_SEMI, 16, C.TEXT)
        txt("Hunt it: its signature is marked in gold on the maps and the HUD", F.BODY, 12, C.DIM)
        Gui:endContainer()
        Gui:beginHorizontalContainer()
        Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
        Gui:setChildrenAlignment(AlignHorizontal.Right, AlignVertical.Center)
        Gui:setSpacing(px(16))
        txt(grouped(c.reward) .. " CR", F.MONO, 15, C.AMBER)
        if button("ABANDON", { height = 34, size = 12 }) then BountyBoard:abandon(c) end
        Gui:endContainer()
        Gui:endContainer()
    end
    Gui:endContainer()
    StationFrame.endPanel()
    Gui:endContainer()

    -- The one selected
    local o = offers[st.index]
    StationFrame.panel(detailW, H, { pad = 24, padY = 22, spacing = 16 })
    if not o then
        txt("Nothing selected.", F.BODY, 15, C.DIM)
        StationFrame.endPanel()
        return
    end
    local threat, tColor = threatOf(o.reward)
    local record = o.record
    txt(string.format("%s THREAT  ·  %s", threat, o.kind:upper()), F.BODY_SEMI, 12, tColor)
    txt("'" .. o.callsign .. "'", F.HEAD, 32, C.TEXT)
    txt(record and record.label or "Pirate", F.BODY, 14, C.DIM)
    Gui:beginVerticalContainer()
    Gui:setSpacing(px(2))
    txt("REWARD", F.BODY_SEMI, 12, C.DIM)
    Gui:beginHorizontalContainer()
    txt(grouped(o.reward), F.MONO_MED, 34, C.AMBER)
    txt(" CR", F.MONO, 18, C.DIM)
    Gui:endContainer()
    Gui:endContainer()
    rule()
    local function pair(label, value, color)
        Gui:beginStackContainer()
        Gui:setFixedWidth(px(detailW - 48))
        txt(label, F.BODY_SEMI, 12, C.DIM)
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
        txt(value, F.BODY_SEMI, 14, color or C.TEXT)
        Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
        Gui:endContainer()
    end
    pair("TARGET SHIP", o.kind)
    pair("LAST SEEN", o.area or "-")
    pair("ROUTE", "In this system")
    pair("EXPIRES", "When you leave the system")
    rule()
    txt("BRIEFING", F.BODY_SEMI, 12, C.DIM)
    StationFrame.para(detailW - 48, string.format("'%s' flies a %s and was last seen near %s. Pirates lie quiet among "
        .. "the rocks of asteroid fields; firing, mining and running hard make any ship louder. Sensor modules hear "
        .. "further and place signatures closer.", o.callsign, o.kind, o.area or "the belts"), 14, C.SUB)
    txt("OBJECTIVES", F.BODY_SEMI, 12, C.DIM)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(10))
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:beginStackContainer()
    Gui:setFixedSize(px(14), px(14))
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.CYAN)
    Gui:endContainer()
    txt(string.format("Destroy '%s'", o.callsign), F.BODY, 14, C.TEXT)
    Gui:endContainer()

    -- A word of warning when the ship cannot fight
    if not g.playerBattery then
        Gui:beginHorizontalContainer()
        Gui:setPadding(px(14), px(12))
        Gui:setBackgroundColor(Color(C.AMBER.r, C.AMBER.g, C.AMBER.b, 0.10))
        Gui:setBorderWidth(1)
        Gui:setBorderColor(C.AMBER)
        StationFrame.para(detailW - 80, string.format("Your active ship %s has no guns fitted. Fit some before you engage.",
            PlayerFleet:active() and PlayerFleet:active().name or ""), 13, C.AMBER)
        Gui:endContainer()
    end

    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(8))
    local half = math.floor((detailW - 48 - 8) / 2)
    if button("SHOW ON MAP", { width = half, height = 48, size = 14, enabled = record and record.entity ~= nil }) then
        g:showOnMap(record.entity, "'" .. o.callsign .. "'")
    end
    if button("ACCEPT CONTRACT", { kind = "primary", width = half, height = 48, size = 15,
            enabled = #contracts < maxC }) then
        local ok, why = BountyBoard:accept(o)
        g:notify(ok and string.format("Contract taken: '%s' -- tracked in gold on the maps and HUD.", o.callsign)
            or ("Cannot take it: " .. (why or "no")), ok and { 1.0, 0.85, 0.35 } or { 1.0, 0.4, 0.3 })
    end
    Gui:endContainer()
    StationFrame.endPanel()
end

------------------------------------------------------------------------------
-- The Station view's own tabs, in a panel

---@param title string
---@param note string|nil
---@param body table a UILayoutGrid
function StationTabs.panelled(title, note, body, W, H)
    StationFrame.panel(W, H)
    StationFrame.titleBar(title, note)
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setPadding(px(20), px(16))
    if body then body:render() end
    Gui:endContainer()
    StationFrame.endPanel()
end

return StationTabs
