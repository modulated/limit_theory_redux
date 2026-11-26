local SystemOverview = require("Modules.Navigation.Systems.SystemOverview")
local ConstructComponents = require("Modules.Constructs.Components")
local UniverseScaleConfig = require("Config.Gen.UniverseScaleConfig")

-- The overview: what is in the star system, nearest first, on the right of
-- the screen (O opens and closes it). Drawn by the in-game view
-- (InGame.lua); the list is SystemOverview's and the actions are the
-- game's (LimitTheoryRedux:lookAt, approach, dockAt, jumpVia).
--
--   left click     select a row
--   double click   approach it on the autopilot
--   right click    the context menu: Look at, Approach, Dock or Jump, and
--                  undoing a look or an autopilot that is already on it
--
-- While it is up the cursor is free and the mouse does not steer
-- (LimitTheoryRedux:updateOverview). The panel tells the cameras when the
-- cursor is over it (GameState.ui.mouseOverPanel), so a right click on a row
-- opens the menu rather than starting an orbit drag, the wheel does not zoom,
-- and a left click is not the fire button.
--
-- Immediate-mode HmGui: the panel asks FocusType.Scroll whether the cursor is
-- anywhere over it (nothing inside it asks for Scroll, so it gets the answer
-- for its whole area), while its rows and the menu's items ask
-- FocusType.Mouse, which goes to the innermost asker.

local OverviewPanel = {}

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.75, 0.77, 0.80, 1.00)
local DIM = Color(0.51, 0.54, 0.59, 1.00)
local ACCENT = Color(0.10, 0.60, 1.00, 1.00)
local PANEL_BG = Color(0.02, 0.04, 0.07, 0.78)
local PANEL_BORDER = Color(0.10, 0.60, 1.00, 0.35)
local ROW_HOVER = Color(0.10, 0.30, 0.50, 0.55)
local ROW_SELECTED = Color(0.10, 0.45, 0.75, 0.45)
local CHIP_ON = Color(0.10, 0.30, 0.50, 1.00)
local CHIP_OFF = Color(0.06, 0.09, 0.13, 1.00)
local MENU_BG = Color(0.03, 0.05, 0.09, 0.96)
local NO_COLOR = Color(0, 0, 0, 0)

--- Each category's colour for the name column (ships use their faction's).
local CATEGORY_COLORS = {
    celestial = Color(0.78, 0.86, 1.00, 1.00),
    station = Color(1.00, 0.65, 0.30, 1.00),
    gate = Color(0.35, 0.85, 1.00, 1.00),
    ship = Color(0.85, 0.90, 0.95, 1.00),
    asteroid = Color(0.80, 0.68, 0.52, 1.00),
}
local HOSTILE = Color(1.00, 0.38, 0.32, 1.00)

--- Column widths and the panel's size, in HUD pixels (1080p).
local WIDTH = 440
local COL_NAME, COL_KIND, COL_DIST = 230, 84, 96
local ROW_HEIGHT = 21
local DOUBLE_CLICK = 0.35 -- seconds

--- The HUD's scale, as the rest of the in-game view has it.
---@return number
local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

local clock
---@return number seconds
local function now()
    clock = clock or TimeStamp.Now()
    return clock:getElapsed()
end

--- The open context menu: { entry, x, y } (screen pixels), or nil.
local menu = nil
--- The last left click, for spotting a double click.
local lastClick = { entity = nil, time = -1 }

---@param value string
---@param limit integer
---@return string
local function clip(value, limit)
    if #value <= limit then return value end
    return value:sub(1, limit - 2) .. ".."
end

---@param entry OverviewEntry
---@return Color
local function colorOf(entry)
    if entry.category == "ship" then
        if entry.hostile then return HOSTILE end
        local c = entry.color
        if c then return Color(c[1] or 1, c[2] or 1, c[3] or 1, 1) end
    end
    return CATEGORY_COLORS[entry.category] or WHITE
end

--- The entity the autopilot is flying to, if it is flying to one.
---@return Entity|nil
local function autopilotTarget()
    local ship = LimitTheoryRedux.playerShip
    local ap = ship and ship:isValid() and ship:get(ConstructComponents.AutoPilot)
    if ap and ap:isActive() then return ap:getTargetEntity() end
    return nil
end

---@param size number
---@param name string|nil
---@return Font
local function font(size, name)
    return Cache.Font(name or "Unageo-Medium", size)
end

--- A text in a column of fixed width, aligned in it. The width is on a
--- container around the text, as the Button does it: the column holds its
--- width whatever the text's length.
local function cell(value, width, color, size, align)
    Gui:beginStackContainer()
    Gui:setFixedWidth(width)
    Gui:setChildrenAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:text(value, font(size), color)
    Gui:setAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:endContainer()
end

------------------------------------------------------------------------------
-- The context menu
------------------------------------------------------------------------------

--- What can be done to an entry, in menu order: { label, enabled, run }.
---@param entry OverviewEntry
---@return table[]
local function actionsFor(entry)
    local game = LimitTheoryRedux
    local items = {}
    local function add(label, enabled, run)
        items[#items + 1] = { label = label, enabled = enabled ~= false, run = run }
    end

    if game.lookingAt == entry.entity then
        add("Stop looking", true, function() game:lookAtShip(true) end)
    else
        add("Look at", true, function() game:lookAt(entry.entity, entry.name) end)
    end

    if autopilotTarget() == entry.entity then
        add("Stop autopilot", true, function()
            local AutoPilotSystem = require("Modules.Constructs.Systems.AutoPilotSystem")
            AutoPilotSystem:disengage(game.playerShip)
            game.arrivalAction = nil
        end)
    else
        add("Approach", true, function() game:approach(entry.entity, entry.name) end)
    end

    if entry.dock then
        local inRange = game:dockInRange()
        local here = inRange and inRange.entity == entry.entity
        add(here and "Dock" or "Approach and dock", true, function() game:dockAt(entry.dock) end)
    elseif entry.gate then
        local near = game:gateInRange()
        local here = near and near.entity == entry.entity
        add(here and "Jump" or "Approach and jump", true, function() game:jumpVia(entry.gate) end)
    end
    return items
end

--- Draw the open menu, and run what is clicked in it.
---@param s number scale
---@return boolean over the cursor is over the menu
local function drawMenu(s)
    if not menu then return false end
    local entry = menu.entry
    if not entry.entity:isValid() then
        menu = nil
        return false
    end

    local items = actionsFor(entry)
    local over = false
    Gui:beginLayerAtPos(Vec2f(menu.x, menu.y))
    Gui:beginVerticalContainer()
    Gui:setScale(s)
    over = Gui:isMouseOver(FocusType.Scroll)
    Gui:setBackgroundColor(MENU_BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(PANEL_BORDER)
    Gui:setPadding(4, 4)
    Gui:setSpacing(1)

    cell(clip(entry.name, 28), 190, ACCENT, 13, AlignHorizontal.Left)

    local clicked = nil
    for _, item in ipairs(items) do
        Gui:beginStackContainer()
        Gui:setFixedSize(190, 24)
        Gui:setPadding(8, 0)
        local hover = Gui:isMouseOver(FocusType.Mouse)
        Gui:setBackgroundColor(hover and item.enabled and ROW_HOVER or NO_COLOR)
        Gui:text(item.label, font(14), item.enabled and WHITE or DIM)
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
        Gui:endContainer()
        if hover and item.enabled and Input:mouse():isPressed(MouseControl.Left) then
            clicked = item
        end
    end

    Gui:endContainer()
    Gui:endLayer()

    if clicked then
        menu = nil
        clicked.run()
    end
    return over
end

------------------------------------------------------------------------------
-- The panel
------------------------------------------------------------------------------

--- The filter buttons: one per category, with how many it holds.
local function drawFilters()
    Gui:beginHorizontalContainer()
    Gui:setSpacing(3)
    for _, category in ipairs(SystemOverview.CATEGORIES) do
        local on = SystemOverview.filters[category]
        Gui:beginStackContainer()
        Gui:setPadding(6, 3)
        local hover = Gui:isMouseOver(FocusType.Mouse)
        Gui:setBackgroundColor((hover and ROW_HOVER) or (on and CHIP_ON) or CHIP_OFF)
        Gui:text(string.format("%s %d", SystemOverview.CATEGORY_NAMES[category],
            SystemOverview.counts[category] or 0), font(12), on and WHITE or DIM)
        Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
        Gui:endContainer()
        if hover and Input:mouse():isPressed(MouseControl.Left) then
            SystemOverview:setFilter(category)
        end
    end
    Gui:endContainer()
end

--- One row; returns the click it took, if any ("left" / "right").
---@param entry OverviewEntry
---@param apTarget Entity|nil
---@return string|nil
local function drawRow(entry, apTarget)
    local game = LimitTheoryRedux
    Gui:beginHorizontalContainer()
    Gui:setFixedHeight(ROW_HEIGHT)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    local selected = SystemOverview.selected == entry.entity
    Gui:setBackgroundColor((hover and ROW_HOVER) or (selected and ROW_SELECTED) or NO_COLOR)

    -- What the player has pointed at it: the autopilot, the camera
    local marker = (apTarget == entry.entity and "> ") or (game.lookingAt == entry.entity and "o ") or "  "
    cell(marker .. clip(entry.name, 30), COL_NAME, colorOf(entry), 14)
    cell(entry.kind, COL_KIND, GREY, 13)
    cell(UniverseScaleConfig:formatDistance(entry.distance), COL_DIST, WHITE, 14, AlignHorizontal.Right)
    Gui:endContainer()

    if hover then
        if Input:mouse():isPressed(MouseControl.Right) then return "right" end
        if Input:mouse():isPressed(MouseControl.Left) then return "left" end
    end
    return nil
end

--- The whole panel, and the menu over it.
function OverviewPanel.render()
    local game = LimitTheoryRedux
    if not (game and game.overviewShowing and game:overviewShowing()) then
        menu = nil
        GameState.ui.mouseOverPanel = false
        return
    end

    local s = hudScale()
    local cfg = Config.game.overview
    local shown, hidden = SystemOverview:visible(cfg.maxRows or 30)
    local apTarget = autopilotTarget()
    local clickedEntry, clickKind = nil, nil

    -- A full-screen container that puts the panel on the right, below the
    -- credits, the hold, the modules and the standings
    Gui:beginStackContainer()
    Gui:setScale(s)
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Right, AlignVertical.Top)
    Gui:setPadding(20, math.floor(Window:height() * 0.27 / s))

    Gui:beginVerticalContainer()
    local overPanel = Gui:isMouseOver(FocusType.Scroll)
    Gui:setFixedWidth(WIDTH)
    Gui:setBackgroundColor(PANEL_BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(PANEL_BORDER)
    Gui:setPadding(8, 8)
    Gui:setSpacing(3)

    -- Heading
    Gui:beginHorizontalContainer()
    cell("OVERVIEW", 150, ACCENT, 15, AlignHorizontal.Left)
    cell("O to close  ·  right click for actions", WIDTH - 16 - 150, DIM, 11, AlignHorizontal.Right)
    Gui:endContainer()

    drawFilters()

    -- Column headings
    Gui:beginHorizontalContainer()
    cell("  Name", COL_NAME, DIM, 12)
    cell("Type", COL_KIND, DIM, 12)
    cell("Distance", COL_DIST, DIM, 12, AlignHorizontal.Right)
    Gui:endContainer()

    for _, entry in ipairs(shown) do
        local click = drawRow(entry, apTarget)
        if click then clickedEntry, clickKind = entry, click end
    end
    if #shown == 0 then
        cell("Nothing here matches the filters.", WIDTH - 16, DIM, 13)
    end
    if hidden > 0 then
        cell(string.format("+%d more: filter some out, or fly closer", hidden), WIDTH - 16, DIM, 12)
    end
    if (SystemOverview.filters.asteroid) then
        cell(string.format("Asteroids within %s", UniverseScaleConfig:formatDistance(cfg.asteroidRange or 10)),
            WIDTH - 16, DIM, 11)
    end

    Gui:endContainer()
    Gui:endContainer()

    -- The menu, over everything
    local overMenu = drawMenu(s)
    GameState.ui.mouseOverPanel = overPanel or overMenu

    -- Clicks: a press outside an open menu closes it; on a row it selects,
    -- doubles to approach, or opens the menu there
    local mouse = Input:mouse()
    if menu and not overMenu and (mouse:isPressed(MouseControl.Left) or mouse:isPressed(MouseControl.Right)) then
        menu = nil
    end
    if clickedEntry and not overMenu then
        SystemOverview.selected = clickedEntry.entity
        if clickKind == "right" then
            local pos = mouse:position()
            menu = { entry = clickedEntry, x = pos.x + 4, y = pos.y + 4 }
        else
            local t = now()
            if lastClick.entity == clickedEntry.entity and t - lastClick.time < DOUBLE_CLICK then
                lastClick.entity, lastClick.time = nil, -1
                game:approach(clickedEntry.entity, clickedEntry.name)
            else
                lastClick.entity, lastClick.time = clickedEntry.entity, t
            end
        end
    end
end

return OverviewPanel
