---@type UIView
local Station = UICore.View {
    name = "Station"
}

local Grid = UILayout.Grid
local Items = require("Shared.Registries.Items")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local PlayerCargo = require("Modules.Economy.Managers.PlayerCargo")
local MarketSystem = require("Modules.Economy.Systems.MarketSystem")
local MarketIntel = require("Modules.Economy.Managers.MarketIntel")
local PlayerStations = require("Modules.Economy.Managers.PlayerStations")
local PlayerForces = require("Modules.Economy.Managers.PlayerForces")
local BountyBoard = require("Modules.Economy.Managers.BountyBoard")
local EconomyComponents = require("Modules.Economy.Components")
local PlayerFactories = require("Modules.Economy.Managers.PlayerFactories")
local ShipFittingSystem = require("Modules.Constructs.Systems.ShipFittingSystem")
local AbilitySystem = require("Modules.Constructs.Systems.AbilitySystem")
local Fittings = require("Shared.Registries.Fittings")
local PlayerFleet = require("Modules.Constructs.Managers.PlayerFleet")
local Hulls = require("Shared.Registries.Hulls")

-- The screen the player sees while docked: what the station has and what it
-- pays, what the hold is carrying, what its factory floor is making, and the
-- way out. Docking opens it (LimitTheoryRedux:dockPlayer) and undocking
-- closes it; F undocks as well, wherever the cursor is.
--
-- Four tabs: the Market (the station's order book: trade at the market or
-- place an order of your own), the Factory (the station's own lines and the
-- lines the player rents), the Hangar (what the player keeps here, and moving
-- it to and from the ship), Nearby (what was last seen of the markets within
-- reach, which is where the spreads worth flying for show up) and Refit (the
-- ship's mounts and module slots, fitted out of this station's hangar).
--
-- NOTE: the prices and the stock are the station's own
-- (Modules/Economy/Systems/MarketSystem.lua: a station posts orders, and a
-- price is whatever someone will pay), the leases and the hangar are
-- PlayerFactories'; this view only shows them and asks them to act.

--- Which tab is up. Kept on the view, so it survives a redraw.
---
--- The market trades out of the hangar, as it must: an order has to be backed
--- by goods that are at the station. The Hangar tab moves goods between the
--- hangar and the ship.
Station.tab = "market"

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.75, 0.77, 0.80, 1.00)
local DIM = Color(0.51, 0.54, 0.59, 1.00)
local ACCENT = Color(0.10, 0.60, 1.00, 1.00)
local RULE = Color(0.10, 0.60, 1.00, 0.35)
local GOLD = Color(1.00, 0.85, 0.35, 1.00)
local GREEN = Color(0.45, 0.90, 0.55, 1.00)
local BUTTON_BG = Color(0.06, 0.09, 0.13, 1.00)
local BUTTON_HI = Color(0.10, 0.30, 0.50, 1.00)

--- Column widths at the design size (1500 x 950), scaled to the window.
local COL_ITEM, COL_NUM, COL_BUTTON = 260, 90, 54
--- The tab's column and the sidebar beside it, at the design size.
local MAIN_WIDTH, SIDE_WIDTH = 1000, 380

--- The screen grows with the window (it used to stop at 1920 px wide's
--- size, and sat small in the middle of anything bigger): as big as fits
--- both ways, between 0.7 and 1.5.
---@return number
local function scale()
    return math.max(0.7, math.min(1.5, Window:width() / 1500, Window:height() / 950))
end

---@return Entity|nil station the station the player is docked at
local function dockedStation()
    local dock = LimitTheoryRedux.docked
    local station = dock and dock.entity
    if station and station:isValid() then return station end
    return nil
end

---@return string|nil key the station key the player's hangar is filed under
local function stationKey()
    local dock = LimitTheoryRedux.docked
    return dock and dock.key or nil
end

---@return string
local function stationName()
    local dock = LimitTheoryRedux.docked
    return dock and dock.label or "Station"
end

---@param value string
---@return UIComponentText
local function text(value, font, size, color, align)
    return UIComponent.Text {
        text = value,
        font = font,
        size = size,
        color = color,
        align = { align or AlignHorizontal.Left, AlignVertical.Center }
    }
end

---@param label string
---@param s number scale
---@param enabled boolean
---@param callback function
---@return UIComponentButton
local function smallButton(label, s, enabled, callback)
    return UIComponent.Button {
        title = label,
        width = math.floor(COL_BUTTON * s),
        height = math.floor(20 * s),
        font = { name = "Unageo-Medium", size = math.floor(12 * s) },
        color = {
            text = enabled and WHITE or DIM,
            background = BUTTON_BG,
            highlight = enabled and BUTTON_HI or BUTTON_BG,
        },
        callback = enabled and callback or function() end
    }
end

---@param label string
---@param s number
---@param width number
---@param enabled boolean
---@param active boolean
---@param callback function
---@return UIComponentButton
local function wideButton(label, s, width, enabled, active, callback)
    return UIComponent.Button {
        title = label,
        width = math.floor(width * s),
        height = math.floor(28 * s),
        font = { name = "Unageo-Medium", size = math.floor(14 * s) },
        color = {
            text = enabled and WHITE or DIM,
            background = active and BUTTON_HI or BUTTON_BG,
            highlight = enabled and BUTTON_HI or BUTTON_BG,
        },
        callback = enabled and callback or function() end
    }
end

--- Which item the order panel is working on, and what it is set to.
Station.order = { itemId = nil, side = "buy", price = nil, units = 1 }

--- Point the order panel at an item, starting from the market's own price.
---@param station Entity
---@param itemId integer
---@param side string
local function selectOrder(station, itemId, side)
    local quote = MarketSystem:quote(station, itemId)
    local start = side == "buy" and (quote.bid or quote.ask or quote.last)
        or (quote.ask or quote.bid or quote.last)
    Station.order = {
        itemId = itemId,
        side = side,
        price = math.max(1, math.floor(start or 10)),
        units = Station.order.units or 1,
    }
end

--- Buy at the market: take the best asks there are.
---@param station Entity
---@param itemId integer
---@param units integer
local function buyAtMarket(station, itemId, units)
    local key = stationKey()
    local def = Items:getDefinition(itemId)
    local result = MarketSystem:buyAtMarket(station, key, itemId, units)
    if result.filled > 0 then
        LimitTheoryRedux:notify(string.format("Bought %d %s for %s (%.0f a unit)",
            result.filled, def.displayName, PlayerWallet.format(result.credits),
            result.average or 0), { 0.6, 0.9, 1.0 })
    else
        LimitTheoryRedux:notify("Nothing on offer: " .. (result.reason or "no sellers"),
            { 1.0, 0.4, 0.3 })
    end
end

--- Sell at the market: hit the best bids there are.
---@param station Entity
---@param itemId integer
---@param units integer
local function sellAtMarket(station, itemId, units)
    local key = stationKey()
    local def = Items:getDefinition(itemId)
    local result = MarketSystem:sellAtMarket(station, key, itemId, units)
    local sold = result.filled + (result.scrapped or 0)
    if sold > 0 then
        local note = ""
        if (result.scrapped or 0) > 0 then
            note = string.format(" (%d of it as scrap: nobody was bidding)", result.scrapped)
        end
        LimitTheoryRedux:notify(string.format("Sold %d %s for %s, %.0f a unit%s",
            sold, def.displayName, PlayerWallet.format(result.credits),
            result.average or 0, note), { 0.6, 0.9, 1.0 })
    else
        LimitTheoryRedux:notify("Could not sell: " .. (result.reason or "nothing to sell"),
            { 1.0, 0.4, 0.3 })
    end
end

--- One row of the book: what it last traded for, the best bid and ask with
--- how much is behind them, what the hangar holds, and the way in.
---@param station Entity
---@param row table from MarketSystem:listing
---@param s number scale
---@return UILayoutGrid
local function marketRow(station, row, s)
    local key = stationKey()
    local hangar = key and PlayerFactories:hangar(key)
    local held = hangar and hangar:count(row.item.id) or 0
    local size = math.floor(15 * s)
    local selected = Station.order.itemId == row.item.id

    return Grid {
        fixedHeight = math.floor(24 * s),
        cells = {
            Grid.Fixed(COL_ITEM * s), Grid.Fixed(COL_NUM * s), Grid.Fixed(COL_NUM * s),
            Grid.Fixed(COL_NUM * s), Grid.Fixed(COL_NUM * s),
            Grid.Fixed((COL_BUTTON + 14) * s), Grid.Fixed((COL_BUTTON + 14) * s),
            Grid.Fixed((COL_BUTTON + 14) * s),
        },
        contents = {
            text(row.item.displayName, "Unageo-Regular", size, selected and WHITE or GREY),
            text(row.last and tostring(row.last) or "-", "Unageo-Regular", size,
                row.last and WHITE or DIM, AlignHorizontal.Right),
            text(row.bid and string.format("%d (%d)", row.bid, row.bidUnits) or "-",
                "Unageo-Regular", size, row.bid and GREEN or DIM, AlignHorizontal.Right),
            text(row.ask and string.format("%d (%d)", row.ask, row.askUnits) or "-",
                "Unageo-Regular", size, row.ask and GOLD or DIM, AlignHorizontal.Right),
            text(held > 0 and tostring(held) or "-", "Unageo-Regular", size,
                held > 0 and WHITE or DIM, AlignHorizontal.Right),
            smallButton("Buy 10", s, row.ask ~= nil, function()
                buyAtMarket(station, row.item.id, 10)
            end),
            smallButton("Sell all", s, row.bid ~= nil and held >= 1, function()
                sellAtMarket(station, row.item.id, held)
            end),
            smallButton("Order", s, true, function()
                selectOrder(station, row.item.id, held > 0 and "sell" or "buy")
            end),
        }
    }
end

--- The order panel: name a price, name a quantity, place it. Credits are
--- held for a buy order and the goods for a sell order until it fills, is
--- cancelled or lapses.
---@param station Entity
---@param s number
---@return UILayoutGrid|nil
--- The order's units, typed: an editable field holding the number. It is
--- made again when a button changes the units (and keeps what is typed
--- otherwise); anything typed that is a whole number of 1 or more is the
--- order's units.
local unitsView, unitsViewValue = nil, nil

---@param order table
---@param s number
---@return UIComponentTextView
local function unitsField(order, s)
    if unitsView and unitsViewValue ~= order.units then unitsView = nil end
    if not unitsView then
        unitsView = UIComponent.TextView {
            text = tostring(order.units),
            editable = true,
            multiline = false,
            style = {
                font = { size = math.floor(15 * s), family = "Unageo" },
                brush = WHITE,
                selectionBrush = BUTTON_HI,
                cursorBrush = WHITE,
            },
            width = math.floor(80 * s),
            backgroundColor = BUTTON_BG,
            align = { AlignHorizontal.Right, AlignVertical.Center },
            -- with a callback, the view copies what is typed into its text data
            callback = function() end,
        }
        unitsViewValue = order.units
    end
    -- What is typed, when it is a natural number
    local ok, typed = pcall(function() return require("ffi").string(unitsView.state.textData():text()) end)
    local n = ok and tonumber((typed or ""):match("^%s*(%d+)%s*$"))
    if n and n >= 1 and n ~= order.units then
        order.units = math.min(n, 1000000000)
        unitsViewValue = order.units
    end
    return unitsView
end

local function orderPanel(station, s)
    local order = Station.order
    if not order.itemId then return nil end
    local def = Items:getDefinition(order.itemId)
    if not def then return nil end
    local key = stationKey()
    local hangar = key and PlayerFactories:hangar(key)
    local held = hangar and hangar:count(order.itemId) or 0
    local quote = MarketSystem:quote(station, order.itemId)
    local cfg = Config.game.market
    local size = math.floor(14 * s)

    local value = order.price * order.units
    -- No broker and no tax at the player's own outpost
    local owned = PlayerStations.isOwnedKey(key)
    local fee = owned and 0 or math.ceil(value * cfg.brokerFee)
    local needed = order.side == "buy" and value + fee or fee
    local can = order.side == "buy" and PlayerWallet:has(needed) or (held >= order.units
        and PlayerWallet:has(fee))

    local function step(label, delta, field, minimum)
        return smallButton(label, s, true, function()
            local next = field == "price"
                and math.floor(order.price * (1 + delta) + (delta > 0 and 0.5 or -0.5))
                or order.units + delta
            if field == "price" and next == order.price then
                next = order.price + (delta > 0 and 1 or -1)
            end
            order[field] = math.max(minimum, next)
        end)
    end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(4 * s),
        cells = Grid.Fit(),
        contents = {
            UIComponent.Divider { color = RULE },
            Grid {
                fixedHeight = math.floor(26 * s),
                cells = { Grid.Fixed(300 * s), Grid.Fixed(150 * s), Grid.Fixed(150 * s),
                          Grid.Fixed(220 * s) },
                contents = {
                    text(string.format("ORDER: %s", def.displayName), "Unageo-Medium",
                        math.floor(13 * s), ACCENT),
                    wideButton("Buy order", s, 130, true, order.side == "buy",
                        function() order.side = "buy" end),
                    wideButton("Sell order", s, 130, true, order.side == "sell",
                        function() order.side = "sell" end),
                    text(string.format("market: bid %s / ask %s",
                        quote.bid and tostring(quote.bid) or "-",
                        quote.ask and tostring(quote.ask) or "-"),
                        "Unageo-Regular", size, DIM, AlignHorizontal.Right),
                }
            },
            Grid {
                fixedHeight = math.floor(26 * s),
                cells = { Grid.Fixed(120 * s), Grid.Fixed(90 * s), Grid.Fixed(70 * s),
                          Grid.Fixed(70 * s), Grid.Fixed(70 * s), Grid.Fixed(70 * s),
                          Grid.Fixed(130 * s), Grid.Fixed(90 * s), Grid.Fixed(70 * s),
                          Grid.Fixed(70 * s), Grid.Fixed(70 * s), Grid.Fixed(70 * s) },
                contents = {
                    text("price", "Unageo-Regular", size, DIM),
                    text(tostring(order.price), "Unageo-Medium", size, WHITE, AlignHorizontal.Right),
                    step("-10%", -0.1, "price", 1),
                    step("-1%", -0.01, "price", 1),
                    step("+1%", 0.01, "price", 1),
                    step("+10%", 0.1, "price", 1),
                    text("        units", "Unageo-Regular", size, DIM),
                    unitsField(order, s),
                    step("-10", -10, "units", 1),
                    step("-1", -1, "units", 1),
                    step("+1", 1, "units", 1),
                    step("+10", 10, "units", 1),
                }
            },
            Grid {
                fixedHeight = math.floor(28 * s),
                cells = { Grid.Fixed(620 * s), Grid.Fixed(150 * s), Grid.Fixed(130 * s) },
                contents = {
                    text(order.side == "buy"
                        and string.format("%s held for the order, %s broker's fee%s",
                            PlayerWallet.format(value), PlayerWallet.format(fee),
                            quote.ask and order.price >= quote.ask and "  ·  fills at once" or "")
                        or string.format("%d of %d in the hangar, %s broker's fee, %d%% tax on the sale",
                            held, order.units, PlayerWallet.format(fee),
                            owned and 0 or math.floor(cfg.salesTax * 100)),
                        "Unageo-Regular", size, can and GREY or GOLD),
                    wideButton("Place", s, 120, can, false, function()
                        local result = MarketSystem:placeOrder(station, key, order.side,
                            order.itemId, order.units, order.price)
                        if result.filled > 0 and result.resting then
                            LimitTheoryRedux:notify(string.format(
                                "%d filled at once, %d standing at %d",
                                result.filled, result.resting.units, order.price), { 0.6, 0.9, 1.0 })
                        elseif result.filled > 0 then
                            LimitTheoryRedux:notify(string.format("Filled %d at an average of %.0f",
                                result.filled, result.average or 0), { 0.6, 0.9, 1.0 })
                        elseif result.resting then
                            LimitTheoryRedux:notify(string.format("%s order standing: %d at %d",
                                order.side == "buy" and "Buy" or "Sell", result.resting.units,
                                order.price), { 0.6, 0.9, 1.0 })
                        else
                            LimitTheoryRedux:notify("Order refused: " .. (result.reason or "no"),
                                { 1.0, 0.4, 0.3 })
                        end
                    end),
                    wideButton("Close", s, 110, true, false, function()
                        Station.order = { itemId = nil, side = "buy", units = order.units }
                    end),
                }
            },
        }
    }
end

--- The player's standing orders here, with the way out of them.
---@param station Entity
---@param s number
---@return UILayoutGrid|nil
local function myOrders(station, s)
    local orders = MarketSystem:playerOrders(station)
    if #orders == 0 then return nil end
    local key = stationKey()
    local size = math.floor(14 * s)
    local rows = {
        text("YOUR ORDERS", "Unageo-Medium", math.floor(13 * s), DIM),
        UIComponent.Divider { color = RULE },
    }
    for _, order in ipairs(orders) do
        local def = Items:getDefinition(order.itemId)
        local quote = MarketSystem:quote(station, order.itemId)
        local best = order.side == "buy" and quote.bid or quote.ask
        local leading = best == order.price
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(24 * s),
            cells = { Grid.Fixed(120 * s), Grid.Fixed(COL_ITEM * s), Grid.Fixed(120 * s),
                      Grid.Fixed(100 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
            contents = {
                text(order.side == "buy" and "BUY" or "SELL", "Unageo-Medium", size,
                    order.side == "buy" and GREEN or GOLD),
                text(def and def.displayName or "?", "Unageo-Regular", size, GREY),
                text(string.format("%d at %d", order.units, order.price), "Unageo-Regular",
                    size, WHITE, AlignHorizontal.Right),
                text(leading and "best" or "outbid", "Unageo-Regular", size,
                    leading and ACCENT or DIM, AlignHorizontal.Right),
                text(order.side == "buy"
                    and string.format("  %s held", PlayerWallet.format(order.escrowCredits or 0))
                    or string.format("  %d units held", order.escrowUnits or 0),
                    "Unageo-Regular", size, DIM),
                wideButton("Cancel", s, 110, true, false, function()
                    MarketSystem:cancel(station, key, order)
                    LimitTheoryRedux:notify("Order cancelled; the broker keeps the fee.",
                        { 0.6, 0.9, 1.0 })
                end),
            }
        }
    end
    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- The market: the book here, the order panel, your orders, and what is known
--- of the markets within reach.
---@param station Entity
---@param s number
---@return UILayoutGrid
local function market(station, s)
    local headerSize = math.floor(13 * s)
    local header = Grid {
        fixedHeight = math.floor(20 * s),
        cells = {
            Grid.Fixed(COL_ITEM * s), Grid.Fixed(COL_NUM * s), Grid.Fixed(COL_NUM * s),
            Grid.Fixed(COL_NUM * s), Grid.Fixed(COL_NUM * s),
        },
        contents = {
            text("GOODS", "Unageo-Medium", headerSize, DIM),
            text("LAST", "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
            text("BID (QTY)", "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
            text("ASK (QTY)", "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
            text("IN HANGAR", "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
        }
    }

    local rows = { header, UIComponent.Divider { color = RULE } }
    local listing = MarketSystem:listing(station)
    for _, row in ipairs(listing) do
        rows[#rows + 1] = marketRow(station, row, s)
    end
    if #listing == 0 then
        rows[#rows + 1] = text("No orders standing here.", "Unageo-Regular", math.floor(15 * s), DIM)
    end
    local panel = orderPanel(station, s)
    if panel then rows[#rows + 1] = panel end

    -- What the player has here that this station does not deal in: it only
    -- buys that as scrap
    local key = stationKey()
    local hangarStock = key and PlayerFactories:hangar(key)
    local listed = {}
    for _, row in ipairs(listing) do listed[row.item.id] = true end
    local untraded = {}
    for _, store in ipairs({ hangarStock, PlayerCargo:get() }) do
        for _, row in ipairs(store and store:list() or {}) do
            if not listed[row.item.id] then
                untraded[row.item.id] = untraded[row.item.id] or { item = row.item, units = 0 }
                untraded[row.item.id].units = untraded[row.item.id].units + row.units
            end
        end
    end
    local ids = {}
    for id in pairs(untraded) do ids[#ids + 1] = id end
    table.sort(ids)
    if #ids > 0 then
        rows[#rows + 1] = text(string.format("NOT TRADED HERE     sold only as scrap, at %d%% of base price",
                math.floor(Config.game.market.scrapFactor * 100)),
            "Unageo-Medium", headerSize, DIM)
        rows[#rows + 1] = UIComponent.Divider { color = RULE }
        local size = math.floor(14 * s)
        for _, id in ipairs(ids) do
            local u = untraded[id]
            local inHangar = hangarStock and hangarStock:count(id) or 0
            rows[#rows + 1] = Grid {
                fixedHeight = math.floor(24 * s),
                cells = { Grid.Fixed(COL_ITEM * s), Grid.Fixed(COL_NUM * 2 * s), Grid.Fixed(COL_NUM * 2 * s),
                          Grid.Fixed((COL_BUTTON + 40) * s) },
                contents = {
                    text(u.item.displayName, "Unageo-Regular", size, GREY),
                    text(string.format("%d held (%d in hangar)", u.units, inHangar), "Unageo-Regular", size, DIM,
                        AlignHorizontal.Right),
                    text(string.format("scrap ~%d a unit", math.max(1, math.floor(
                        (u.item.startEquilibriumPrice or 0) * Config.game.market.scrapFactor))),
                        "Unageo-Regular", size, DIM, AlignHorizontal.Right),
                    smallButton("Scrap all", s, inHangar > 0, function()
                        sellAtMarket(station, id, inHangar)
                    end),
                }
            }
        end
        rows[#rows + 1] = text("A station deals in what its recipes use and make, and the ores of its system. "
            .. "Move goods to the hangar to sell them; better prices are where they are made or used (Nearby tab).",
            "Unageo-Regular", math.floor(12 * s), DIM)
    end

    local mine = myOrders(station, s)
    if mine then rows[#rows + 1] = mine end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

------------------------------------------------------------------------------
-- The factory: industry, as EVE lays it out. Blueprints on the left (what
-- can be run here, what can be made now first, each with how many runs the
-- hangar holds the materials for); the chosen one on the right, its
-- materials against what is in the hangar, what it makes, and a job of so
-- many runs to start; the jobs running underneath. What the station's own
-- lines are busy with is not the player's business, and is not shown.
------------------------------------------------------------------------------

local RED = Color(1.00, 0.42, 0.36, 1.00)

--- The blueprint chosen, the runs asked for, and whether the list shows
--- only what can be made now.
Station.industry = { recipeId = nil, runs = 1, onlyMakeable = false }

--- The outpost's own block over the factory: what it is, its takings, and
--- its defences.
---@param key string
---@param s number
---@return table[] rows
local function outpostHeader(key, s)
    local rows = {}
    local size = math.floor(14 * s)
    local outpost = PlayerStations:byKey(key)
    if not outpost then return rows end
    local kindCfg = PlayerStations.kindOf(outpost.kind)
    local income = outpost.income
    rows[#rows + 1] = text(string.format("YOUR %s   ·   market: %s sold, %s bought, %s in taxes",
            string.upper(kindCfg.name), PlayerWallet.format(income.sales or 0),
            PlayerWallet.format(income.purchases or 0), PlayerWallet.format(income.taxes or 0)),
        "Unageo-Medium", math.floor(13 * s), ACCENT)
    local quote = LimitTheoryRedux:outpostDefenseQuote(key)
    if quote then
        local state = quote.destroyed and "Defences destroyed"
            or string.format("Defences: hull %d/%d  ·  shields %d/%d",
                math.floor(quote.hull), math.floor(quote.maxHull),
                math.floor(quote.shield), math.floor(quote.maxShield))
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(30 * s),
            cells = { Grid.Fixed(620 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
            contents = {
                text(state, "Unageo-Regular", size, quote.destroyed and GOLD or DIM),
                text(quote.cost > 0 and PlayerWallet.format(quote.cost) or "",
                    "Unageo-Regular", size, DIM, AlignHorizontal.Right),
                wideButton(quote.destroyed and "Rebuild" or "Repair", s, 110,
                    quote.cost > 0 and PlayerWallet:has(quote.cost), false, function()
                        LimitTheoryRedux:repairOutpostDefense(key)
                    end),
            }
        }
    end
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    return rows
end

--- The blueprint list: one row each, the makeable ones first.
---@param key string
---@param recipes ProductionDefinition[]
---@param s number
---@return UILayoutGrid
local function blueprintList(key, recipes, s)
    local sel = Station.industry
    local size = math.floor(13 * s)
    local rows = {
        Grid {
            fixedHeight = math.floor(30 * s),
            cells = { Grid.Fixed(250 * s), Grid.Fixed(200 * s) },
            contents = {
                text("BLUEPRINTS", "Unageo-Medium", math.floor(13 * s), DIM),
                wideButton(sel.onlyMakeable and "Showing: can make" or "Showing: all", s, 190, true,
                    sel.onlyMakeable, function() sel.onlyMakeable = not sel.onlyMakeable end),
            }
        },
        UIComponent.Divider { color = RULE },
    }
    local list = {}
    for _, recipe in ipairs(recipes) do
        local runs = PlayerFactories:runsPossible(key, recipe)
        if runs > 0 or not sel.onlyMakeable then list[#list + 1] = { recipe = recipe, runs = runs } end
    end
    table.sort(list, function(a, b)
        if (a.runs > 0) ~= (b.runs > 0) then return a.runs > 0 end
        return a.recipe.displayName < b.recipe.displayName
    end)
    if #list == 0 then
        rows[#rows + 1] = text(sel.onlyMakeable and "Nothing here can be made from your hangar yet."
            or "This station runs nothing for you.", "Unageo-Regular", size, DIM)
    end
    for _, row in ipairs(list) do
        local recipe = row.recipe
        local chosen = sel.recipeId == recipe.id
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(30 * s),
            cells = { Grid.Fixed(330 * s), Grid.Fixed(120 * s) },
            contents = {
                wideButton(recipe.displayName, s, 320, true, chosen, function()
                    sel.recipeId = recipe.id
                    sel.runs = math.max(1, math.min(sel.runs or 1, math.max(1, row.runs)))
                end),
                text(row.runs > 0 and string.format("can make %d", row.runs) or "missing materials",
                    "Unageo-Regular", size, row.runs > 0 and GREEN or DIM, AlignHorizontal.Right),
            }
        }
    end
    return Grid { layoutType = GuiLayoutType.Vertical, spacing = math.floor(2 * s), cells = Grid.Fit(), contents = rows }
end

--- The chosen blueprint: materials against the hangar, what it makes, and
--- the job to start.
---@param key string
---@param recipe ProductionDefinition|nil
---@param outpost boolean
---@param s number
---@return UILayoutGrid
local function blueprintDetail(key, recipe, outpost, s)
    local sel = Station.industry
    local size = math.floor(14 * s)
    local rows = {}
    if not recipe then
        rows[#rows + 1] = text("Choose a blueprint on the left.", "Unageo-Regular", size, DIM)
        return Grid { layoutType = GuiLayoutType.Vertical, cells = Grid.Fit(), contents = rows }
    end
    local hangar = PlayerFactories:hangar(key)
    local possible = PlayerFactories:runsPossible(key, recipe)
    local runs = math.max(1, sel.runs or 1)
    local fee = PlayerFactories:feeFor(recipe, key)
    local minutes = recipe.duration / Config.game.production.timeScale / 60

    rows[#rows + 1] = text(recipe.displayName, "Unageo-Medium", math.floor(17 * s), WHITE)
    rows[#rows + 1] = text(string.format("%s  ·  %.1f min a run%s", recipe.class, minutes,
            outpost and "" or string.format("  ·  station fee %s a run", PlayerWallet.format(fee))),
        "Unageo-Regular", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }

    -- Materials, for the runs asked for
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(22 * s),
        cells = { Grid.Fixed(250 * s), Grid.Fixed(100 * s), Grid.Fixed(100 * s) },
        contents = {
            text(string.format("MATERIALS  x%d", runs), "Unageo-Medium", math.floor(12 * s), DIM),
            text("needed", "Unageo-Medium", math.floor(12 * s), DIM, AlignHorizontal.Right),
            text("in hangar", "Unageo-Medium", math.floor(12 * s), DIM, AlignHorizontal.Right),
        }
    }
    for _, entry in ipairs(recipe.inputs) do
        local need = entry.count * runs
        local have = hangar:count(entry.item.id)
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(22 * s),
            cells = { Grid.Fixed(250 * s), Grid.Fixed(100 * s), Grid.Fixed(100 * s) },
            contents = {
                text(entry.item.displayName, "Unageo-Regular", size, GREY),
                text(tostring(need), "Unageo-Regular", size, GREY, AlignHorizontal.Right),
                text(tostring(have), "Unageo-Regular", size, have >= need and GREEN or RED, AlignHorizontal.Right),
            }
        }
    end

    -- Products
    rows[#rows + 1] = text(string.format("PRODUCES  x%d", runs), "Unageo-Medium", math.floor(12 * s), DIM)
    for _, entry in ipairs(recipe.outputs) do
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(22 * s),
            cells = { Grid.Fixed(250 * s), Grid.Fixed(100 * s) },
            contents = {
                text(entry.item.displayName, "Unageo-Regular", size, WHITE),
                text(tostring(entry.count * runs), "Unageo-Regular", size, WHITE, AlignHorizontal.Right),
            }
        }
    end
    rows[#rows + 1] = UIComponent.Divider { color = RULE }

    -- The job: so many runs, on a free line
    local free = PlayerFactories:freeLines(key)
    local function setRuns(n) sel.runs = math.max(1, math.min(999, n)) end
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(32 * s),
        cells = { Grid.Fixed(70 * s), Grid.Fixed(60 * s), Grid.Fixed(60 * s), Grid.Fixed(60 * s),
                  Grid.Fixed(60 * s), Grid.Fixed(130 * s) },
        contents = {
            text("RUNS", "Unageo-Medium", math.floor(12 * s), DIM),
            smallButton("-10", s, runs > 1, function() setRuns(runs - 10) end),
            smallButton("-1", s, runs > 1, function() setRuns(runs - 1) end),
            text(tostring(runs), "Unageo-Medium", size, WHITE, AlignHorizontal.Center),
            smallButton("+1", s, true, function() setRuns(runs + 1) end),
            smallButton(string.format("max %d", possible), s, possible > 0, function() setRuns(possible) end),
        }
    }
    local canStart = free > 0 and possible >= runs
    local why = free <= 0 and (outpost and "every line is busy" or "no line free to rent")
        or (possible < runs and (possible == 0 and "missing materials" or string.format("materials for %d run(s)", possible)))
        or nil
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(36 * s),
        cells = { Grid.Fixed(200 * s), Grid.Fixed(300 * s) },
        contents = {
            wideButton(string.format("Start job (%d run%s)", runs, runs == 1 and "" or "s"), s, 190, canStart, true,
                function()
                    local ok, reason = PlayerFactories:lease(key, recipe.id, runs)
                    LimitTheoryRedux:notify(ok
                        and string.format("Job started: %s x%d", recipe.displayName, runs)
                        or ("Cannot start: " .. (reason or "no")), ok and { 0.6, 0.9, 1.0 } or { 1.0, 0.4, 0.3 })
                end),
            text(why or (outpost and "" or string.format("total fee %s", PlayerWallet.format(fee * runs))),
                "Unageo-Regular", math.floor(13 * s), why and RED or DIM),
        }
    }
    return Grid { layoutType = GuiLayoutType.Vertical, spacing = math.floor(3 * s), cells = Grid.Fit(), contents = rows }
end

--- The jobs running here.
---@param key string
---@param outpost boolean
---@param s number
---@return table[] rows
local function jobRows(key, outpost, s)
    local size = math.floor(13 * s)
    local total = outpost and PlayerStations:lines(key) or Config.game.factory.rentableLines
    local leases = PlayerFactories:status(key)
    local rows = {
        text(string.format("JOBS   %d of %d line(s) in use%s", #leases, total,
                outpost and "" or string.format("  ·  the station takes %d%% of each run as its fee",
                    math.floor(Config.game.factory.rentShare * 100))),
            "Unageo-Medium", math.floor(13 * s), DIM),
        UIComponent.Divider { color = RULE },
    }
    if #leases == 0 then
        rows[#rows + 1] = text("No jobs running. Choose a blueprint and start one.", "Unageo-Regular", size, DIM)
    end
    for _, lease in ipairs(leases) do
        local state
        if lease.running then
            state = string.format("%d%%", math.floor(lease.progress * 100))
        elseif not lease.crewed then
            state = "no crew"
        elseif lease.hangarFull then
            state = "hangar full"
        else
            state = "waiting: " .. (PlayerFactories:missingFor(key, lease.recipe) or "inputs")
        end
        local index = lease.index
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(28 * s),
            cells = { Grid.Fixed(330 * s), Grid.Fixed(140 * s), Grid.Fixed(340 * s), Grid.Fixed(120 * s) },
            contents = {
                text(lease.recipe.displayName, "Unageo-Regular", size, WHITE),
                text(lease.runs and string.format("%d run(s) left", lease.runs) or "repeating",
                    "Unageo-Regular", size, GREY),
                text(state, "Unageo-Regular", size,
                    lease.running and ACCENT or (not lease.crewed and GOLD or DIM)),
                wideButton("Stop", s, 110, true, false, function()
                    PlayerFactories:release(key, index)
                    LimitTheoryRedux:notify("Job stopped.", { 0.6, 0.9, 1.0 })
                end),
            }
        }
    end
    return rows
end

--- The factory tab.
---@param station Entity
---@param s number
---@return UILayoutGrid
local function factory(station, s)
    local key = stationKey()
    if not key then
        return Grid { cells = Grid.Fit(), contents = {
            text("This station runs no jobs for you.", "Unageo-Regular", math.floor(14 * s), DIM) } }
    end
    local outpost = PlayerStations:byKey(key) ~= nil
    local recipes = PlayerFactories:offered(station, key)
    local sel = Station.industry
    -- A choice from another station, or none: the first that can be made
    local chosen = nil
    for _, recipe in ipairs(recipes) do
        if recipe.id == sel.recipeId then chosen = recipe end
    end
    if not chosen then
        for _, recipe in ipairs(recipes) do
            if PlayerFactories:runsPossible(key, recipe) > 0 then chosen = recipe break end
        end
        chosen = chosen or recipes[1]
        sel.recipeId = chosen and chosen.id or nil
        sel.runs = 1
    end

    local rows = outpostHeader(key, s)
    rows[#rows + 1] = Grid {
        cells = { Grid.Fixed(470 * s), Grid.Fixed(20 * s), Grid.Fixed(510 * s) },
        contents = {
            blueprintList(key, recipes, s),
            text("", "Unageo-Regular", 10, DIM),
            blueprintDetail(key, chosen, outpost, s),
        }
    }
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    for _, row in ipairs(jobRows(key, outpost, s)) do rows[#rows + 1] = row end
    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(4 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- The hangar: what the player keeps at this station, and moving it to and
--- from the ship.
---@param station Entity
---@param s number
---@return UILayoutGrid
local function hangar(station, s)
    local key = stationKey()
    local size = math.floor(15 * s)
    local rows = {}
    if not key then
        return Grid { cells = Grid.Fit(), contents = { text("No hangar here.", "Unageo-Regular", size, DIM) } }
    end
    local store = PlayerFactories:hangar(key)
    local hold = PlayerCargo:get()

    rows[#rows + 1] = text(string.format("HANGAR              %d / %d t used, the hold has %d t free",
            math.floor(store:getUsedMass()), math.floor(store:getCapacity() or 0),
            math.floor(hold:getFreeMass())),
        "Unageo-Medium", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }

    local columns = {
        Grid.Fixed(COL_ITEM * s), Grid.Fixed(COL_NUM * s), Grid.Fixed(COL_NUM * s),
        Grid.Fixed((COL_BUTTON + 30) * s), Grid.Fixed((COL_BUTTON + 30) * s),
        Grid.Fixed((COL_BUTTON + 30) * s),
    }
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(20 * s),
        cells = columns,
        contents = {
            text("GOODS", "Unageo-Medium", math.floor(13 * s), DIM),
            text("HANGAR", "Unageo-Medium", math.floor(13 * s), DIM, AlignHorizontal.Right),
            text("HOLD", "Unageo-Medium", math.floor(13 * s), DIM, AlignHorizontal.Right),
            text("", "Unageo-Medium", math.floor(13 * s), DIM),
            text("", "Unageo-Medium", math.floor(13 * s), DIM),
            text("", "Unageo-Medium", math.floor(13 * s), DIM),
        }
    }

    -- Everything either side holds, so goods can be moved both ways
    local seen, items = {}, {}
    for _, row in ipairs(store:list()) do
        seen[row.item.id] = true
        items[#items + 1] = row.item
    end
    for _, row in ipairs(hold:list()) do
        if not seen[row.item.id] then
            seen[row.item.id] = true
            items[#items + 1] = row.item
        end
    end
    table.sort(items, function(a, b) return a.id < b.id end)

    if #items == 0 then
        rows[#rows + 1] = text("Nothing here and nothing in the hold.", "Unageo-Regular", size, DIM)
    end
    for _, item in ipairs(items) do
        local inHangar = store:count(item.id)
        local inHold = hold:count(item.id)
        local function move(from, to, units, what)
            local taken = from:remove(item.id, units)
            local put = to:add(item.id, taken)
            if put < taken then from:add(item.id, taken - put) end
            if put > 0 then
                LimitTheoryRedux:notify(string.format("Moved %d %s %s", put, item.displayName, what),
                    { 0.6, 0.9, 1.0 })
            else
                LimitTheoryRedux:notify("No room for that.", { 1.0, 0.4, 0.3 })
            end
        end
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(24 * s),
            cells = columns,
            contents = {
                text(item.displayName, "Unageo-Regular", size, GREY),
                text(inHangar > 0 and tostring(inHangar) or "-", "Unageo-Regular", size,
                    inHangar > 0 and WHITE or DIM, AlignHorizontal.Right),
                text(inHold > 0 and tostring(inHold) or "-", "Unageo-Regular", size,
                    inHold > 0 and WHITE or DIM, AlignHorizontal.Right),
                wideButton("To ship", s, 78, inHangar >= 1, false, function()
                    move(store, hold, inHangar, "to the ship")
                end),
                wideButton("To hangar", s, 78, inHold >= 1, false, function()
                    move(hold, store, inHold, "to the hangar")
                end),
                wideButton("Sell", s, 78, inHangar >= 1, false, function()
                    sellAtMarket(station, item.id, inHangar)
                end),
            }
        }
    end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- What is known of the markets within reach: the best spreads first, then
--- every station whose book has been seen, with how stale the note is. Only
--- the system you are in is live, so this is memory, not a live feed -- which
--- is the point: you have to go and look.
---@param s number
---@return UILayoutGrid
local function nearby(s)
    local size = math.floor(14 * s)
    local galaxy = LimitTheoryRedux.galaxy
    local systemId = LimitTheoryRedux.currentSystemId or 1
    local now = LimitTheoryRedux.simTime or 0
    local rows = {
        text(string.format("MARKETS WITHIN %d JUMPS        what was last seen of them",
                MarketIntel:getRange()),
            "Unageo-Medium", math.floor(13 * s), DIM),
        UIComponent.Divider { color = RULE },
    }

    local spreads = MarketIntel:bestSpreads(galaxy, systemId, now, 8)
    if #spreads > 0 then
        rows[#rows + 1] = text("BEST SPREADS", "Unageo-Medium", math.floor(13 * s), ACCENT)
        for _, spread in ipairs(spreads) do
            rows[#rows + 1] = Grid {
                fixedHeight = math.floor(22 * s),
                cells = { Grid.Fixed(COL_ITEM * s), Grid.Fixed(330 * s), Grid.Fixed(330 * s),
                          Grid.Fixed(120 * s) },
                contents = {
                    text(spread.item.displayName, "Unageo-Regular", size, GREY),
                    text(string.format("buy %d at %s, %s", spread.buyPrice, spread.buyAt.label,
                        spread.buyAt.systemName), "Unageo-Regular", size, GOLD),
                    text(string.format("sell %d at %s, %s", spread.sellPrice, spread.sellAt.label,
                        spread.sellAt.systemName), "Unageo-Regular", size, GREEN),
                    text(string.format("+%d a unit", spread.margin), "Unageo-Medium", size,
                        WHITE, AlignHorizontal.Right),
                }
            }
        end
        rows[#rows + 1] = UIComponent.Divider { color = RULE }
    end

    local known = MarketIntel:nearby(galaxy, systemId, now)
    if #known == 0 then
        rows[#rows + 1] = text("No market has been seen yet. Dock at one.",
            "Unageo-Regular", size, DIM)
    end
    for _, record in ipairs(known) do
        local counted = 0
        for _ in pairs(record.quotes) do counted = counted + 1 end
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(22 * s),
            cells = { Grid.Fixed(300 * s), Grid.Fixed(240 * s), Grid.Fixed(180 * s),
                      Grid.Fixed(180 * s) },
            contents = {
                text(string.format("%s, %s", record.label, record.systemName),
                    "Unageo-Regular", size, GREY),
                text(record.jumps == 0 and "this system"
                    or string.format("%d jump%s away", record.jumps, record.jumps == 1 and "" or "s"),
                    "Unageo-Regular", size, DIM),
                text(string.format("%d goods quoted", counted), "Unageo-Regular", size, DIM),
                text(record.jumps == 0 and "live" or MarketIntel.describeAge(record.age),
                    "Unageo-Regular", size, record.jumps == 0 and ACCENT or DIM,
                    AlignHorizontal.Right),
            }
        }
    end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- Refitting the ship: its mounts, its module slots, and what the hangar
--- here has that could go in them. Fitting takes the part out of the hangar
--- and bolts it on; taking one off puts it back. The station charges nothing
--- for the work.
---@param s number
---@return UILayoutGrid
local function refit(s)
    local size = math.floor(14 * s)
    local key = stationKey()
    local ship = LimitTheoryRedux.playerShip
    local rows = {}
    if not ship or not ship:isValid() then
        return Grid { cells = Grid.Fit(), contents = { text("No ship.", "Unageo-Regular", size, DIM) } }
    end
    local loadout = ship:get(require("Modules.Constructs.Components").Loadout)
    if not loadout then
        return Grid { cells = Grid.Fit(), contents = {
            text("This hull cannot be refitted.", "Unageo-Regular", size, DIM) } }
    end
    local hangar = key and PlayerFactories:hangar(key)

    --- What is in the hangar that would go in this kind of slot.
    ---@param slotKind string
    ---@param sizeClass string|nil
    ---@return table[]
    local function available(slotKind, sizeClass)
        local list = {}
        for _, row in ipairs(ShipFittingSystem:fittableFrom(ship, hangar)) do
            if row.fitting.slot == slotKind
                and (slotKind ~= "weapon" or ShipFittingSystem:weaponFits(row.fitting, sizeClass))
                and (slotKind ~= "module" or ShipFittingSystem:moduleFits(row.fitting, loadout.hullClass)) then
                list[#list + 1] = row
            end
        end
        return list
    end

    -- This ship, the player's others parked here, and hulls to make ships of
    local flying = PlayerFleet:active()
    local hull = PlayerFleet.hullOf(flying)
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(26 * s),
        cells = { Grid.Fixed(700 * s), Grid.Fixed(190 * s) },
        contents = {
            text(hull
                    and string.format("THIS SHIP           %s   ·   %s", flying.name, Hulls.describe(hull))
                    or "THIS SHIP           unknown",
                "Unageo-Medium", math.floor(13 * s), ACCENT),
            wideButton("Strip everything", s, 170, PlayerFleet.fittingCount(flying) > 0, false,
                function() LimitTheoryRedux:stripShip(flying) end),
        }
    }

    local parked = PlayerFleet:parkedAt(key)
    if #parked > 0 then
        rows[#rows + 1] = text("YOUR SHIPS HERE     each keeps its own fit",
            "Unageo-Medium", math.floor(13 * s), DIM)
        for _, other in ipairs(parked) do
            local otherHull = PlayerFleet.hullOf(other)
            local empty = PlayerFleet.fittingCount(other) == 0
            rows[#rows + 1] = Grid {
                fixedHeight = math.floor(26 * s),
                cells = { Grid.Fixed(200 * s), Grid.Fixed(330 * s), Grid.Fixed(150 * s),
                          Grid.Fixed(120 * s), Grid.Fixed(150 * s) },
                contents = {
                    text(other.name, "Unageo-Regular", size, GREY),
                    text(otherHull and Hulls.describe(otherHull) or "unknown hull",
                        "Unageo-Regular", size, DIM),
                    text(PlayerFleet.describe(other), "Unageo-Regular", size, WHITE),
                    wideButton("Fly it", s, 110, true, false, function()
                        LimitTheoryRedux:flyShip(other)
                    end),
                    empty
                        and wideButton("Break up", s, 140, true, false, function()
                            LimitTheoryRedux:decommissionShip(other)
                        end)
                        or wideButton("Strip it", s, 140, true, false, function()
                            LimitTheoryRedux:stripShip(other)
                        end),
                }
            }
        end
    end

    -- A hull in the hangar is a good until it is made into a ship
    local spareHulls = {}
    for _, row in ipairs(hangar and hangar:list() or {}) do
        local itsHull = Hulls:forItem(row.item.id)
        if itsHull then spareHulls[#spareHulls + 1] = { hull = itsHull, units = row.units } end
    end
    if #spareHulls > 0 then
        rows[#rows + 1] = text("HULLS IN THE HANGAR  a new ship starts with nothing in it",
            "Unageo-Medium", math.floor(13 * s), DIM)
        for _, row in ipairs(spareHulls) do
            rows[#rows + 1] = Grid {
                fixedHeight = math.floor(26 * s),
                cells = { Grid.Fixed(200 * s), Grid.Fixed(480 * s), Grid.Fixed(210 * s) },
                contents = {
                    text(string.format("%s (x%d)", row.hull.displayName, row.units),
                        "Unageo-Regular", size, GREY),
                    text(Hulls.describe(row.hull), "Unageo-Regular", size, DIM),
                    wideButton("Fit out and fly", s, 190, true, false, function()
                        LimitTheoryRedux:commissionHull(row.hull)
                    end),
                }
            }
        end
    elseif #parked == 0 then
        rows[#rows + 1] = text("No other ship or hull here. Buy a hull on the market, or have a drydock build one.",
            "Unageo-Regular", size, DIM)
    end
    rows[#rows + 1] = UIComponent.Divider { color = RULE }

    -- What the ship comes to with what is on it now
    local stats = loadout.stats or {}
    rows[#rows + 1] = text(string.format(
            "THE FIT             %s   ·   shield %d, armour %.0f, hull %d   ·   thrust x%.2f, turn x%.2f   ·   hold +%d t",
            PlayerFleet.describe(flying), stats.maxShield or 0, stats.armor or 0,
            stats.maxHealth or 0, stats.thrust or 1, stats.turn or 1, stats.cargoMass or 0),
        "Unageo-Medium", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }

    -- The guns
    rows[#rows + 1] = text("MOUNTS", "Unageo-Medium", math.floor(13 * s), ACCENT)
    local mounts = ShipFittingSystem:mounts(ship)
    if #mounts == 0 then
        rows[#rows + 1] = text("This hull has no mounts.", "Unageo-Regular", size, DIM)
    end
    for _, mount in ipairs(mounts) do
        local fitted = loadout:getWeapon(mount.mountId)
        local offers = available("weapon", mount.sizeClass)
        local buttons = {}
        for _, row in ipairs(offers) do
            if not fitted or fitted.id ~= row.fitting.id then
                buttons[#buttons + 1] = wideButton(
                    string.format("%s (%d)", row.fitting.displayName, row.units), s, 190, true, false,
                    function()
                        local ok, reason = ShipFittingSystem:fitWeapon(ship, hangar, mount.mountId, row.fitting)
                        LimitTheoryRedux:notify(ok
                            and string.format("%s fitted to %s", row.fitting.displayName, mount.mountId)
                            or ("Cannot fit: " .. (reason or "no")), ok and { 0.6, 0.9, 1.0 } or { 1.0, 0.4, 0.3 })
                        if ok then
                            PlayerFleet:record(ship)
                            LimitTheoryRedux:applyFitToShip()
                        end
                    end)
            end
        end
        if fitted then
            buttons[#buttons + 1] = wideButton("Remove", s, 110, true, false, function()
                local ok = ShipFittingSystem:unfitWeapon(ship, hangar, mount.mountId)
                if ok then
                    PlayerFleet:record(ship)
                    LimitTheoryRedux:applyFitToShip()
                    LimitTheoryRedux:notify("Stripped " .. mount.mountId, { 0.6, 0.9, 1.0 })
                end
            end)
        end
        local cells = { Grid.Fixed(220 * s), Grid.Fixed(260 * s) }
        local contents = {
            text(string.format("%s  (%s)", mount.mountId, tostring(mount.sizeClass or "any")),
                "Unageo-Regular", size, GREY),
            text(fitted and fitted.displayName or "as built", "Unageo-Regular", size,
                fitted and WHITE or DIM),
        }
        for _, button in ipairs(buttons) do
            cells[#cells + 1] = Grid.Fixed(200 * s)
            contents[#contents + 1] = button
        end
        rows[#rows + 1] = Grid { fixedHeight = math.floor(26 * s), cells = cells, contents = contents }
    end

    -- The slots
    rows[#rows + 1] = text(string.format("MODULE SLOTS        %s-class hull: takes modules of class %s   ·   active ones go on the action bar (keys 1-8)",
            loadout.hullClass or "?", ({ S = "S", M = "S and M", L = "S, M and L", C = "any" })[loadout.hullClass or "C"] or "any"),
        "Unageo-Medium", math.floor(13 * s), ACCENT)
    for slot = 1, loadout:getModuleSlots() do
        local fitted = loadout:getModule(slot)
        local buttons = {}
        for _, row in ipairs(available("module")) do
            if not fitted or fitted.id ~= row.fitting.id then
                buttons[#buttons + 1] = wideButton(
                    string.format("[%s] %s (%d)", row.fitting.moduleClass or "S", row.fitting.displayName, row.units),
                    s, 200, true, false,
                    function()
                        local ok, reason = ShipFittingSystem:fitModule(ship, hangar, slot, row.fitting)
                        LimitTheoryRedux:notify(ok
                            and string.format("%s fitted in slot %d", row.fitting.displayName, slot)
                            or ("Cannot fit: " .. (reason or "no")), ok and { 0.6, 0.9, 1.0 } or { 1.0, 0.4, 0.3 })
                        if ok then
                            PlayerFleet:record(ship)
                            LimitTheoryRedux:applyFitToShip()
                        end
                    end)
            end
        end
        if fitted then
            buttons[#buttons + 1] = wideButton("Remove", s, 110, true, false, function()
                local ok = ShipFittingSystem:unfitModule(ship, hangar, slot)
                if ok then
                    PlayerFleet:record(ship)
                    LimitTheoryRedux:applyFitToShip()
                    LimitTheoryRedux:notify(string.format("Slot %d emptied", slot), { 0.6, 0.9, 1.0 })
                end
            end)
        end
        local cells = { Grid.Fixed(90 * s), Grid.Fixed(230 * s), Grid.Fixed(360 * s) }
        local contents = {
            text(string.format("slot %d", slot), "Unageo-Regular", size, GREY),
            text(fitted and string.format("[%s] %s", fitted.moduleClass or "S", fitted.displayName) or "empty",
                "Unageo-Regular", size, fitted and WHITE or DIM),
            text(fitted and fitted:describeEffects() or "", "Unageo-Regular", size, DIM),
        }
        for _, button in ipairs(buttons) do
            cells[#cells + 1] = Grid.Fixed(210 * s)
            contents[#contents + 1] = button
        end
        rows[#rows + 1] = Grid { fixedHeight = math.floor(26 * s), cells = cells, contents = contents }
    end

    -- What the hangar is holding that goes nowhere yet
    local spare = ShipFittingSystem:fittableFrom(ship, hangar)
    if #spare > 0 then
        rows[#rows + 1] = text("IN THE HANGAR", "Unageo-Medium", math.floor(13 * s), DIM)
        rows[#rows + 1] = UIComponent.Divider { color = RULE }
        for _, row in ipairs(spare) do
            rows[#rows + 1] = Grid {
                fixedHeight = math.floor(22 * s),
                cells = { Grid.Fixed(230 * s), Grid.Fixed(90 * s), Grid.Fixed(100 * s), Grid.Fixed(460 * s) },
                contents = {
                    text(row.fitting.displayName, "Unageo-Regular", size, GREY),
                    text(string.format("x%d", row.units), "Unageo-Regular", size, WHITE,
                        AlignHorizontal.Right),
                    text(row.fitting.slot == "weapon"
                        and string.format("  %s mount", tostring(row.fitting.sizeClass))
                        or "  module", "Unageo-Regular", size, DIM),
                    text(row.fitting:describeEffects(), "Unageo-Regular", size, DIM),
                }
            }
        end
    else
        rows[#rows + 1] = text("Nothing in this hangar to fit. Buy parts on the market, or make them.",
            "Unageo-Regular", size, DIM)
    end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- The tab row.
---@param s number
---@return UILayoutGrid
local function tabs(s)
    local function tab(label, name)
        return wideButton(label, s, 150, true, Station.tab == name, function() Station.tab = name end)
    end
    return Grid {
        spacing = math.floor(10 * s),
        cells = Grid.Fit(),
        contents = {
            tab("Market", "market"),
            tab("Factory", "factory"),
            tab("Hangar", "hangar"),
            tab("Nearby", "nearby"),
            tab("Refit", "refit"),
            -- The bounty board at the system's stations; the player's own ships
            -- are commanded from their outposts
            PlayerStations.isOwnedKey(stationKey()) and tab("Forces", "forces") or tab("Bounties", "bounties"),
        }
    }
end

--- The Bounties tab: named pirates in this system with a price on their
--- heads (BountyBoard). A contract tracks its ship on the maps and the HUD,
--- in gold, wherever it is in the system; the reward is paid on the kill.
---@param s number
---@return UILayoutGrid
local function bounties(s)
    local game = LimitTheoryRedux
    BountyBoard:refresh(game)
    local size = math.floor(14 * s)
    local head = math.floor(13 * s)
    local rows = {}
    local cells = { Grid.Fixed(220 * s), Grid.Fixed(150 * s), Grid.Fixed(110 * s), Grid.Fixed(370 * s),
                    Grid.Fixed(120 * s) }

    rows[#rows + 1] = text(string.format("WANTED              %d posted  ·  contracts %d of %d",
            #BountyBoard.offers, #BountyBoard.contracts, Config.game.bounties.maxContracts),
        "Unageo-Medium", head, DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    if #BountyBoard.offers == 0 then
        rows[#rows + 1] = text("No pirate in this system has a price on its head just now.", "Unageo-Regular", size, DIM)
    end
    for _, offer in ipairs(BountyBoard.offers) do
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(28 * s),
            cells = cells,
            contents = {
                text("'" .. offer.callsign .. "'", "Unageo-Semibold", size, WHITE),
                text(offer.kind, "Unageo-Regular", size, GREY),
                text(PlayerWallet.format(offer.reward), "Unageo-Regular", size, GOLD, AlignHorizontal.Right),
                text("last seen " .. offer.area, "Unageo-Regular", size, DIM),
                wideButton("Accept", s, 110, #BountyBoard.contracts < Config.game.bounties.maxContracts, false,
                    function()
                        local ok, why = BountyBoard:accept(offer)
                        game:notify(ok and string.format("Contract taken: '%s' -- tracked in gold on the maps and HUD.",
                            offer.callsign) or ("Cannot take it: " .. (why or "no")),
                            ok and { 1.0, 0.85, 0.35 } or { 1.0, 0.4, 0.3 })
                    end),
            }
        }
    end

    rows[#rows + 1] = text("YOUR CONTRACTS", "Unageo-Medium", head, DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    if #BountyBoard.contracts == 0 then
        rows[#rows + 1] = text("None. Take one above; it ends if you leave the system.", "Unageo-Regular", size, DIM)
    end
    for _, contract in ipairs(BountyBoard.contracts) do
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(28 * s),
            cells = cells,
            contents = {
                text("'" .. contract.callsign .. "'", "Unageo-Semibold", size, GOLD),
                text(contract.kind, "Unageo-Regular", size, GREY),
                text(PlayerWallet.format(contract.reward), "Unageo-Regular", size, GOLD, AlignHorizontal.Right),
                text("hunt it: its signature is marked in gold", "Unageo-Regular", size, DIM),
                wideButton("Abandon", s, 110, true, false, function() BountyBoard:abandon(contract) end),
            }
        }
    end
    rows[#rows + 1] = text("Pirates lie quiet among the rocks of asteroid fields; firing, mining and running hard "
        .. "make any ship louder. Sensor modules hear further and place signatures closer.",
        "Unageo-Regular", math.floor(12 * s), DIM)

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(3 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- The Forces tab, at one of the player's outposts: launch a drone from the
--- hangar, hire a mercenary, and give every unit in the system its order.
---@param s number
---@return UILayoutGrid
local function forces(s)
    local game = LimitTheoryRedux
    local key = stationKey()
    local size = math.floor(14 * s)
    local cfg = Config.game.forces
    local rows = {}

    local droneDef, hangarStock = game:droneStock()
    local drones = droneDef and hangarStock and hangarStock:count(droneDef.id) or 0
    local room = PlayerForces:room(key)
    rows[#rows + 1] = text(string.format("FORCES              %d of %d berths free here  ·  wages %s an hour",
            room, cfg.maxPerOutpost, PlayerWallet.format(PlayerForces:wageBill())),
        "Unageo-Medium", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(30 * s),
        cells = { Grid.Fixed(620 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
        contents = {
            text(string.format("Combat drone: built, not hired. %d in this hangar.", drones),
                "Unageo-Regular", size, GREY),
            text("no upkeep", "Unageo-Regular", size, DIM, AlignHorizontal.Right),
            wideButton("Launch", s, 110, drones > 0 and room > 0, false, function() game:launchDrone() end),
        }
    }
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(30 * s),
        cells = { Grid.Fixed(620 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
        contents = {
            text(string.format("Mercenary: %s to hire, then %s an hour while they serve.",
                    PlayerWallet.format(cfg.mercenary.hireCost), PlayerWallet.format(cfg.mercenary.wagePerHour)),
                "Unageo-Regular", size, GREY),
            text("", "Unageo-Regular", size, DIM, AlignHorizontal.Right),
            wideButton("Hire", s, 110, room > 0 and PlayerWallet:has(cfg.mercenary.hireCost), false,
                function() game:hireMercenary() end),
        }
    }

    local units = PlayerForces:inSystem(game.currentSystemId or 1)
    rows[#rows + 1] = text(#units > 0 and "IN THIS SYSTEM" or "IN THIS SYSTEM      none yet",
        "Unageo-Medium", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    for _, unit in ipairs(units) do
        local status = game:unitStatus(unit)
        local home = PlayerStations:byKey(unit.homeKey)
        local guarding = unit.order == PlayerForces.Order.Guard
        local orderText = guarding and ("guarding " .. (home and home.name or "its outpost"))
            or "patrolling your outposts"
        local here = unit.homeKey == key
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(28 * s),
            cells = { Grid.Fixed(500 * s), Grid.Fixed(200 * s), Grid.Fixed(110 * s), Grid.Fixed(110 * s) },
            contents = {
                text(string.format("%s  ·  %s", unit.name, orderText), "Unageo-Regular", size, GREY),
                text(string.format("hull %d%%  shield %d%%",
                        math.floor(100 * status.hull / math.max(1, status.maxHull)),
                        math.floor(100 * status.shield / math.max(1, status.maxShield))),
                    "Unageo-Regular", size, status.hull < status.maxHull * 0.4 and GOLD or DIM, AlignHorizontal.Right),
                wideButton(guarding and "Patrol" or "Guard", s, 100, true, false, function()
                    game:setUnitOrder(unit, guarding and PlayerForces.Order.Patrol or PlayerForces.Order.Guard)
                end),
                wideButton(unit.kind == PlayerForces.Kind.Drone and "Recall" or "Dismiss", s, 100,
                    unit.kind ~= PlayerForces.Kind.Drone or (here and status.here), false,
                    function() game:releaseUnit(unit) end),
            }
        }
    end
    rows[#rows + 1] = text("A drone is recalled into its own outpost's hangar. Guards fly around their outpost; "
        .. "patrols make the round of all your outposts here.", "Unageo-Regular", math.floor(12 * s), DIM)

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- The whole screen.
---@param s number
---@return UILayoutGrid
--- The sidebar: the ship and what it carries, and what this station is, so
--- the state of things is on screen whichever tab is up.
---@param station Entity|nil
---@param s number
---@return UILayoutGrid
local function sidebar(station, s)
    local game = LimitTheoryRedux
    local rows = {}
    local head = math.floor(13 * s)
    local size = math.floor(14 * s)
    local function heading(value)
        rows[#rows + 1] = text(value, "Unageo-Medium", head, DIM)
        rows[#rows + 1] = UIComponent.Divider { color = RULE }
    end
    local function pair(label, value, color)
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(20 * s),
            cells = { Grid.Fixed(170 * s), Grid.Fixed((SIDE_WIDTH - 190) * s) },
            contents = {
                text(label, "Unageo-Regular", size, GREY),
                text(value, "Unageo-Regular", size, color or WHITE, AlignHorizontal.Right),
            }
        }
    end

    heading("YOUR SHIP")
    local ship = PlayerFleet:active()
    rows[#rows + 1] = text(ship and ship.name or "-", "Unageo-Semibold", math.floor(16 * s), WHITE)
    local entity = game.playerShip
    local CoreComponents = require("Modules.Core.Components")
    local ConstructComponents = require("Modules.Constructs.Components")
    local health = entity and entity:isValid() and entity:get(CoreComponents.Health)
    local defense = entity and entity:isValid() and entity:get(ConstructComponents.Defense)
    if health then
        pair("Hull", string.format("%d / %d", math.floor(health:getCurrentHealth()), math.floor(health:getMaxHealth())),
            health:getCurrentHealth() < health:getMaxHealth() and GOLD or GREEN)
    end
    if defense and defense:getMaxShield() > 0 then
        pair("Shields", string.format("%d / %d", math.floor(defense:getCurrentShield()),
            math.floor(defense:getMaxShield())))
    end
    pair("Credits", PlayerWallet.format(PlayerWallet:get()), GOLD)

    local used, capacity = PlayerCargo:getLoad()
    heading(string.format("HOLD  %d / %d t", math.floor(used), math.floor(capacity)))
    local holdRows = PlayerCargo:list()
    if #holdRows == 0 then rows[#rows + 1] = text("Empty", "Unageo-Regular", size, DIM) end
    for i, row in ipairs(holdRows) do
        if i > 10 then
            rows[#rows + 1] = text(string.format("... and %d more (Hangar tab)", #holdRows - 10),
                "Unageo-Regular", size, DIM)
            break
        end
        pair(row.item.displayName, tostring(row.units))
    end

    local key = stationKey()
    local hangarStock = key and PlayerFactories:hangar(key)
    local hangarRows = hangarStock and hangarStock:list() or {}
    heading(string.format("HANGAR HERE  %d kind(s)", #hangarRows))
    for i, row in ipairs(hangarRows) do
        if i > 6 then
            rows[#rows + 1] = text(string.format("... and %d more", #hangarRows - 6), "Unageo-Regular", size, DIM)
            break
        end
        pair(row.item.displayName, tostring(row.units))
    end

    if station then
        heading("THIS STATION")
        local productionCmp = station:get(EconomyComponents.Production)
        local makes, seen = {}, {}
        for _, recipe in ipairs(productionCmp and productionCmp:getRecipes() or {}) do
            for _, out in ipairs(recipe.outputs) do
                if out.item.group ~= "Waste" and not seen[out.item.id] then
                    seen[out.item.id] = true
                    makes[#makes + 1] = out.item.displayName
                end
            end
        end
        rows[#rows + 1] = text(#makes > 0 and ("Makes: " .. table.concat(makes, ", ")) or "Makes nothing of its own",
            "Unageo-Regular", size, GREY)
        rows[#rows + 1] = text(string.format("Deals in %d goods (Market tab)", #MarketSystem:listing(station)),
            "Unageo-Regular", size, DIM)
    end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(3 * s),
        cells = Grid.Fit(),
        color = { background = Color(0.03, 0.05, 0.09, 0.85) },
        padding = { math.floor(12 * s), math.floor(10 * s) },
        contents = rows
    }
end

local function screen(s)
    local station = dockedStation()
    local used, capacity = PlayerCargo:getLoad()
    local missing, repairCost = LimitTheoryRedux:hullRepairQuote()

    local headline = Grid {
        cells = { Grid.Fixed((MAIN_WIDTH + SIDE_WIDTH - 420) * s), Grid.Fixed(420 * s) },
        contents = {
            text(stationName(), "Unageo-Semibold", math.floor(34 * s), WHITE),
            text(string.format("%s   ·   hold %d / %d t", PlayerWallet.format(PlayerWallet:get()),
                math.floor(used), math.floor(capacity)), "Unageo-Medium", math.floor(17 * s),
                GOLD, AlignHorizontal.Right),
        }
    }

    local footer = Grid {
        spacing = math.floor(14 * s),
        cells = Grid.Fit(),
        contents = {
            UIComponent.Button {
                title = missing > 0
                    and string.format("Repair hull (%s)", PlayerWallet.format(repairCost))
                    or "Hull intact",
                width = math.floor(260 * s),
                height = math.floor(34 * s),
                font = { name = "Unageo-Medium", size = math.floor(16 * s) },
                color = { text = missing > 0 and WHITE or DIM, background = BUTTON_BG, highlight = BUTTON_HI },
                callback = function() LimitTheoryRedux:repairHull() end
            },
            UIComponent.Button {
                title = "Undock  (F)",
                width = math.floor(200 * s),
                height = math.floor(34 * s),
                font = { name = "Unageo-Medium", size = math.floor(16 * s) },
                color = { text = WHITE, background = BUTTON_BG, highlight = BUTTON_HI },
                callback = function() LimitTheoryRedux:undockPlayer() end
            },
        }
    }

    local contents = { headline, UIComponent.Divider { color = RULE } }
    if station then
        contents[#contents + 1] = tabs(s)
        local body
        if Station.tab == "factory" then
            body = factory(station, s)
        elseif Station.tab == "hangar" then
            body = hangar(station, s)
        elseif Station.tab == "nearby" then
            body = nearby(s)
        elseif Station.tab == "refit" then
            body = refit(s)
        elseif Station.tab == "forces" and PlayerStations.isOwnedKey(stationKey()) then
            body = forces(s)
        elseif Station.tab == "bounties" and not PlayerStations.isOwnedKey(stationKey()) then
            body = bounties(s)
        else
            body = market(station, s)
        end
        -- The tab on the left, the ship and the station on the right
        contents[#contents + 1] = Grid {
            spacing = math.floor(20 * s),
            cells = { Grid.Fixed(MAIN_WIDTH * s), Grid.Fixed(SIDE_WIDTH * s) },
            cellAlign = { AlignHorizontal.Left, AlignVertical.Top },
            contents = { body, sidebar(station, s) },
        }
    else
        contents[#contents + 1] = text("Not docked.", "Unageo-Regular", math.floor(16 * s), DIM)
    end
    contents[#contents + 1] = footer

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        align = { AlignHorizontal.Stretch, AlignVertical.Stretch },
        childrenAlign = { AlignHorizontal.Center, AlignVertical.Center },
        cellAlign = { AlignHorizontal.Center, AlignVertical.Center },
        color = { background = Color(0.01, 0.02, 0.04, 0.92) },
        padding = { math.floor(60 * s), math.floor(36 * s) },
        spacing = math.floor(18 * s),
        cells = Grid.Fit(),
        contents = contents
    }
end

function Station:onViewOpen(isPageOpen) end

-- Rebuilt every frame: the stock, the prices and the hold all move while the
-- screen is open (the station's factory floor is running), and the buttons
-- have to be enabled or disabled with them. One station's worth of rows is
-- about twenty, so this is cheap enough and always right.
Station:addContent({
    state = {},
    render = function()
        screen(scale()):render()
    end
})

return Station
