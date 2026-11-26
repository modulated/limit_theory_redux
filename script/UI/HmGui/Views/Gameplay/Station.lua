---@type UIView
local Station = UICore.View {
    name = "Station"
}

local Grid = UILayout.Grid
local Items = require("Shared.Registries.Items")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local PlayerCargo = require("Modules.Economy.Managers.PlayerCargo")
local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")
local ProductionSystem = require("Modules.Economy.Systems.ProductionSystem")
local EconomyComponents = require("Modules.Economy.Components")
local PlayerFactories = require("Modules.Economy.Managers.PlayerFactories")

-- The screen the player sees while docked: what the station has and what it
-- pays, what the hold is carrying, what its factory floor is making, and the
-- way out. Docking opens it (LimitTheoryRedux:dockPlayer) and undocking
-- closes it; F undocks as well, wherever the cursor is.
--
-- Three tabs: the Market (buy and sell, into the ship's hold or into the
-- hangar), the Factory (the station's own lines, and the lines the player
-- rents) and the Hangar (what the player keeps here, and moving it to and
-- from the ship).
--
-- NOTE: the prices and the stock are the station's own
-- (Modules/Economy/Systems/StationTradeSystem.lua), the leases and the hangar
-- are PlayerFactories'; this view only shows them and asks them to act.

--- Which tab is up, and where market trades go: the ship's hold or the
--- hangar at this station. Kept on the view, so they survive a redraw.
Station.tab = "market"
Station.target = "ship"

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.75, 0.77, 0.80, 1.00)
local DIM = Color(0.51, 0.54, 0.59, 1.00)
local ACCENT = Color(0.10, 0.60, 1.00, 1.00)
local RULE = Color(0.10, 0.60, 1.00, 0.35)
local GOLD = Color(1.00, 0.85, 0.35, 1.00)
local GREEN = Color(0.45, 0.90, 0.55, 1.00)
local BUTTON_BG = Color(0.06, 0.09, 0.13, 1.00)
local BUTTON_HI = Color(0.10, 0.30, 0.50, 1.00)

--- Column widths at 1920 px, scaled down on smaller windows.
local COL_ITEM, COL_NUM, COL_BUTTON = 260, 90, 54

---@return number
local function scale()
    return math.max(0.7, math.min(1.0, Window:width() / 1920))
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

--- The store market trades go through: the ship's hold, or the hangar here.
---@return StockComponent|nil
local function tradeStore()
    if Station.target == "hangar" then
        local key = stationKey()
        return key and PlayerFactories:hangar(key) or nil
    end
    return PlayerCargo:get()
end

---@return string
local function storeName()
    return Station.target == "hangar" and "hangar" or "hold"
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

--- Buy `units` of an item and say how it went.
---@param station Entity
---@param itemId integer
---@param units integer
local function buy(station, itemId, units)
    local store = tradeStore()
    if not store then return end
    local bought, spent = StationTradeSystem:buy(station, store, itemId, units)
    local def = Items:getDefinition(itemId)
    if bought > 0 then
        LimitTheoryRedux:notify(string.format("Bought %d %s for %s (to the %s)", bought,
            def.displayName, PlayerWallet.format(spent), storeName()), { 0.6, 0.9, 1.0 })
    else
        LimitTheoryRedux:notify("Cannot buy that: no stock, no credits or no room.", { 1.0, 0.4, 0.3 })
    end
end

--- Sell `units` of an item out of the hold.
---@param station Entity
---@param itemId integer
---@param units integer
local function sell(station, itemId, units)
    local store = tradeStore()
    if not store then return end
    local sold, earned = StationTradeSystem:sell(station, store, itemId, units)
    local def = Items:getDefinition(itemId)
    if sold > 0 then
        LimitTheoryRedux:notify(string.format("Sold %d %s for %s (from the %s)", sold,
            def.displayName, PlayerWallet.format(earned), storeName()), { 0.6, 0.9, 1.0 })
    else
        LimitTheoryRedux:notify(store:count(itemId) > 0
            and "This station will take no more of that."
            or ("Nothing of that in the " .. storeName() .. "."), { 1.0, 0.4, 0.3 })
    end
end

--- One row of the market: the item, the station's stock and prices, what the
--- hold holds, and the buttons.
---@param station Entity
---@param row table from StationTradeSystem:listing
---@param s number scale
---@return UILayoutGrid
local function marketRow(station, row, s)
    local store = tradeStore() or PlayerCargo:get()
    local held = store:count(row.item.id)
    local canBuy = StationTradeSystem:maxBuyable(station, store, row.item.id)
    local canSell = StationTradeSystem:maxSellable(station, store, row.item.id)
    local size = math.floor(15 * s)

    return Grid {
        fixedHeight = math.floor(24 * s),
        cells = {
            Grid.Fixed(COL_ITEM * s), Grid.Fixed(COL_NUM * s), Grid.Fixed(COL_NUM * s),
            Grid.Fixed(COL_NUM * s), Grid.Fixed(COL_NUM * s),
            Grid.Fixed((COL_BUTTON + 6) * s), Grid.Fixed((COL_BUTTON + 6) * s),
            Grid.Fixed((COL_BUTTON + 6) * s), Grid.Fixed((COL_BUTTON + 6) * s),
        },
        contents = {
            text(row.item.displayName, "Unageo-Regular", size, GREY),
            text(tostring(row.units), "Unageo-Regular", size, WHITE, AlignHorizontal.Right),
            text(tostring(row.buy), "Unageo-Regular", size, GOLD, AlignHorizontal.Right),
            text(tostring(row.sell), "Unageo-Regular", size, GREEN, AlignHorizontal.Right),
            text(held > 0 and tostring(held) or "-", "Unageo-Regular", size,
                held > 0 and WHITE or DIM, AlignHorizontal.Right),
            smallButton("Buy", s, canBuy >= 1, function() buy(station, row.item.id, 1) end),
            smallButton("Buy 10", s, canBuy >= 1, function() buy(station, row.item.id, 10) end),
            smallButton("Sell", s, canSell >= 1, function() sell(station, row.item.id, 1) end),
            smallButton("Sell all", s, canSell >= 1, function() sell(station, row.item.id, held) end),
        }
    }
end

--- The market table: a header row and one row per thing the station deals in.
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
            text("IN STOCK", "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
            text("BUY", "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
            text("SELL", "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
            text(Station.target == "hangar" and "IN HANGAR" or "IN HOLD",
                "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
        }
    }

    local rows = { header, UIComponent.Divider { color = RULE } }
    local listing = StationTradeSystem:listing(station)
    for _, row in ipairs(listing) do
        rows[#rows + 1] = marketRow(station, row, s)
    end
    if #listing == 0 then
        rows[#rows + 1] = text("This station has nothing to trade.", "Unageo-Regular", math.floor(15 * s), DIM)
    end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- What the station is making, one line per production line.
---@param station Entity
---@param s number
---@return UILayoutGrid|nil
local function production(station, s)
    local status = ProductionSystem:status(station)
    if #status == 0 then return nil end
    local size = math.floor(14 * s)
    -- The hands: the station's standing crew plus the workers docked here,
    -- and what its lines are using of them
    local workforce = station:get(EconomyComponents.Workforce)
    local crewLine = workforce
        and string.format("PRODUCTION          crew %s on shift", workforce:describe())
        or "PRODUCTION"
    local rows = {
        text(crewLine, "Unageo-Medium", math.floor(13 * s), DIM),
        UIComponent.Divider { color = RULE },
    }
    for _, line in ipairs(status) do
        local state = line.running
            and string.format("%d%%", math.floor(line.progress * 100))
            or (not line.crewed and "no crew"
                or (line.full and "store full" or "waiting for stock"))
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(22 * s),
            cells = { Grid.Fixed(640 * s), Grid.Fixed(160 * s) },
            contents = {
                text(line.recipe:describe(), "Unageo-Regular", size, GREY),
                text(state, "Unageo-Regular", size,
                    line.running and ACCENT or (not line.crewed and GOLD or DIM), AlignHorizontal.Right),
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

--- The player's own floor here: the lines rented, and what the station will
--- rent out. A rented line eats from the hangar and fills it back up, and the
--- station takes its cut of each run.
---@param station Entity
---@param s number
---@return UILayoutGrid
local function factory(station, s)
    local key = stationKey()
    local size = math.floor(14 * s)
    local rows = {}

    -- The station's own lines first: what the floor is busy with
    local own = production(station, s)
    if own then rows[#rows + 1] = own end

    rows[#rows + 1] = text(string.format("YOUR LINES          %d of %d rented",
            key and #PlayerFactories:leases(key) or 0, Config.game.factory.rentableLines),
        "Unageo-Medium", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }

    if not key then
        rows[#rows + 1] = text("This station does not rent lines.", "Unageo-Regular", size, DIM)
    else
        for _, lease in ipairs(PlayerFactories:status(key)) do
            local state
            if lease.running then
                state = string.format("%d%%", math.floor(lease.progress * 100))
            elseif not lease.crewed then
                state = "no crew"
            elseif lease.hangarFull then
                state = "hangar full"
            else
                state = "needs " .. (PlayerFactories:missingFor(key, lease.recipe) or "inputs")
            end
            local index = lease.index
            rows[#rows + 1] = Grid {
                fixedHeight = math.floor(26 * s),
                cells = { Grid.Fixed(620 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
                contents = {
                    text(lease.recipe:describe(), "Unageo-Regular", size, GREY),
                    text(string.format("%s  ·  fee %d", state, lease.fee), "Unageo-Regular", size,
                        lease.running and ACCENT or (not lease.crewed and GOLD or DIM),
                        AlignHorizontal.Right),
                    wideButton("Give back", s, 110, true, false, function()
                        PlayerFactories:release(key, index)
                        LimitTheoryRedux:notify("The line is the station's again.", { 0.6, 0.9, 1.0 })
                    end),
                }
            }
        end

        local free = PlayerFactories:freeLines(key)
        rows[#rows + 1] = text(free > 0
                and string.format("TO RENT             %d line(s) free, the station takes %d%% of each run",
                    free, math.floor(Config.game.factory.rentShare * 100))
                or "TO RENT             no lines free",
            "Unageo-Medium", math.floor(13 * s), DIM)
        rows[#rows + 1] = UIComponent.Divider { color = RULE }
        for _, recipe in ipairs(PlayerFactories:offered(station)) do
            local fee = PlayerFactories:feeFor(recipe)
            rows[#rows + 1] = Grid {
                fixedHeight = math.floor(26 * s),
                cells = { Grid.Fixed(620 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
                contents = {
                    text(recipe:describe(), "Unageo-Regular", size, GREY),
                    text(string.format("%.0fs a run  ·  fee %d", recipe.duration, fee),
                        "Unageo-Regular", size, DIM, AlignHorizontal.Right),
                    wideButton("Rent", s, 110, free > 0, false, function()
                        local ok, reason = PlayerFactories:lease(key, recipe.id)
                        LimitTheoryRedux:notify(ok
                            and ("Rented a line for the " .. recipe.displayName)
                            or ("Cannot rent: " .. (reason or "no")),
                            ok and { 0.6, 0.9, 1.0 } or { 1.0, 0.4, 0.3 })
                    end),
                }
            }
        end
    end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
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
                    local sold, earned = StationTradeSystem:sell(station, store, item.id, inHangar)
                    LimitTheoryRedux:notify(sold > 0
                        and string.format("Sold %d %s for %s", sold, item.displayName,
                            PlayerWallet.format(earned))
                        or "This station will take no more of that.",
                        sold > 0 and { 0.6, 0.9, 1.0 } or { 1.0, 0.4, 0.3 })
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

--- The tab row, and where market trades go.
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
            text("        trade with:", "Unageo-Regular", math.floor(13 * s), DIM),
            wideButton("Ship hold", s, 120, true, Station.target == "ship",
                function() Station.target = "ship" end),
            wideButton("Hangar", s, 120, true, Station.target == "hangar",
                function() Station.target = "hangar" end),
        }
    }
end

--- The whole screen.
---@param s number
---@return UILayoutGrid
local function screen(s)
    local station = dockedStation()
    local used, capacity = PlayerCargo:getLoad()
    local missing, repairCost = LimitTheoryRedux:hullRepairQuote()

    local headline = Grid {
        cells = { Grid.Fixed(700 * s), Grid.Fixed(420 * s) },
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
        if Station.tab == "factory" then
            contents[#contents + 1] = factory(station, s)
        elseif Station.tab == "hangar" then
            contents[#contents + 1] = hangar(station, s)
        else
            contents[#contents + 1] = market(station, s)
        end
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
