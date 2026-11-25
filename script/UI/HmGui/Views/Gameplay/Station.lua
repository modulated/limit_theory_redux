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

-- The screen the player sees while docked: what the station has and what it
-- pays, what the hold is carrying, what its factory floor is making, and the
-- way out. Docking opens it (LimitTheoryRedux:dockPlayer) and undocking
-- closes it; F undocks as well, wherever the cursor is.
--
-- NOTE: the prices and the stock are the station's own
-- (Modules/Economy/Systems/StationTradeSystem.lua); this view only shows them
-- and asks it to buy and sell.

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
    local bought, spent = StationTradeSystem:buy(station, PlayerCargo:get(), itemId, units)
    local def = Items:getDefinition(itemId)
    if bought > 0 then
        LimitTheoryRedux:notify(string.format("Bought %d %s for %s", bought, def.displayName,
            PlayerWallet.format(spent)), { 0.6, 0.9, 1.0 })
    else
        LimitTheoryRedux:notify("Cannot buy that: no stock, no credits or no room.", { 1.0, 0.4, 0.3 })
    end
end

--- Sell `units` of an item out of the hold.
---@param station Entity
---@param itemId integer
---@param units integer
local function sell(station, itemId, units)
    local sold, earned = StationTradeSystem:sell(station, PlayerCargo:get(), itemId, units)
    local def = Items:getDefinition(itemId)
    if sold > 0 then
        LimitTheoryRedux:notify(string.format("Sold %d %s for %s", sold, def.displayName,
            PlayerWallet.format(earned)), { 0.6, 0.9, 1.0 })
    else
        LimitTheoryRedux:notify("Nothing of that in the hold.", { 1.0, 0.4, 0.3 })
    end
end

--- One row of the market: the item, the station's stock and prices, what the
--- hold holds, and the buttons.
---@param station Entity
---@param row table from StationTradeSystem:listing
---@param s number scale
---@return UILayoutGrid
local function marketRow(station, row, s)
    local held = PlayerCargo:count(row.item.id)
    local hold = PlayerCargo:get()
    local canBuy = StationTradeSystem:maxBuyable(station, hold, row.item.id)
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
            smallButton("Sell", s, held >= 1, function() sell(station, row.item.id, 1) end),
            smallButton("Sell all", s, held >= 1, function() sell(station, row.item.id, held) end),
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
            text("IN HOLD", "Unageo-Medium", headerSize, DIM, AlignHorizontal.Right),
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
    local rows = {
        text("PRODUCTION", "Unageo-Medium", math.floor(13 * s), DIM),
        UIComponent.Divider { color = RULE },
    }
    for _, line in ipairs(status) do
        local state = line.running
            and string.format("%d%%", math.floor(line.progress * 100))
            or "waiting for stock"
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(22 * s),
            cells = { Grid.Fixed(640 * s), Grid.Fixed(160 * s) },
            contents = {
                text(line.recipe:describe(), "Unageo-Regular", size, GREY),
                text(state, "Unageo-Regular", size, line.running and ACCENT or DIM, AlignHorizontal.Right),
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
        contents[#contents + 1] = market(station, s)
        local lines = production(station, s)
        if lines then contents[#contents + 1] = lines end
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
