local UIMouse = require("Input.UIMouse")
local SystemOverview = require("Modules.Navigation.Systems.SystemOverview")
local ConstructComponents = require("Modules.Constructs.Components")
local UniverseScaleConfig = require("Config.Gen.UniverseScaleConfig")

-- The overview: what is in the star system, on the right of the screen (O
-- opens and closes it). Drawn by the in-game view (InGame.lua); the list is
-- SystemOverview's and the actions are the game's (LimitTheoryRedux:lookAt,
-- approach, dockAt, jumpVia, lockTarget, attackTarget, showOnMap).
--
--   left click     select a row
--   double click   approach it on the autopilot
--   right click    the context menu
--   wheel          scroll the list
--   column heads   sort by that column; again to reverse it
--   filter buttons show or hide a category
--
-- The filters and the sort are remembered (GameState.ui.overview*, saved in
-- user.ini). While the panel is up the cursor is free and the mouse does not
-- steer (LimitTheoryRedux:updateOverview), and the panel tells the cameras
-- when the cursor is over it (UIMouse.overPanel), so a right click on a row
-- opens the menu rather than starting an orbit drag, the wheel scrolls the
-- list rather than zooming, and a left click is not the fire button.
--
-- Immediate-mode HmGui: the panel asks FocusType.Scroll whether the cursor is
-- anywhere over it (nothing inside it asks for Scroll, so it gets the answer
-- for its whole area), while its rows, buttons and menu items ask
-- FocusType.Mouse, which goes to the innermost asker.

local OverviewPanel = {}

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.75, 0.77, 0.80, 1.00)
local DIM = Color(0.51, 0.54, 0.59, 1.00)
local ACCENT = Color(0.10, 0.60, 1.00, 1.00)
local GOLD = Color(1.00, 0.85, 0.35, 1.00)
local PANEL_BG = Color(0.02, 0.04, 0.07, 0.78)
local PANEL_BORDER = Color(0.10, 0.60, 1.00, 0.35)
local ROW_HOVER = Color(0.10, 0.30, 0.50, 0.55)
local ROW_SELECTED = Color(0.10, 0.45, 0.75, 0.45)
local ROW_TARGET = Color(0.55, 0.40, 0.05, 0.40)
local CHIP_ON = Color(0.10, 0.30, 0.50, 1.00)
local CHIP_OFF = Color(0.06, 0.09, 0.13, 1.00)
local MENU_BG = Color(0.03, 0.05, 0.09, 0.96)
local BAR_BG = Color(0.10, 0.60, 1.00, 0.12)
local BAR_KNOB = Color(0.10, 0.60, 1.00, 0.70)
local BAR_KNOB_HELD = Color(0.35, 0.75, 1.00, 0.95)
local BAR_HOVER = Color(0.10, 0.60, 1.00, 0.25)
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

--- Sizes in HUD pixels (1080p): the panel, its columns, its rows.
local WIDTH = 440
local COL_NAME, COL_KIND, COL_DIST = 224, 84, 96
local BAR_WIDTH = 10      -- wide enough to grab
local ROW_HEIGHT = 21
local DOUBLE_CLICK = 0.35 -- seconds
local WHEEL_ROWS = 3      -- rows a notch of the wheel scrolls

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
--- The first row shown (0 = the top of the list).
local scroll = 0
--- The knob being dragged: where the cursor and the list were when it was
--- grabbed, or nil.
local drag = nil

local same = SystemOverview.same

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

--- An empty box: a gap, or a bar.
local function box(width, height, color)
    Gui:beginStackContainer()
    Gui:setFixedSize(width, math.max(0, height))
    Gui:setBackgroundColor(color or NO_COLOR)
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
    local function add(label, run, enabled)
        items[#items + 1] = { label = label, enabled = enabled ~= false, run = run }
    end

    -- Ships: lock, attack, release
    if entry.category == "ship" then
        if game:isTarget(entry.entity) then
            if not game.attacking and not entry.hostile then
                add("Attack", function() game:attackTarget(entry.entity, entry.name, entry.faction) end)
            end
            add("Release target", function() game:clearTarget() end)
        else
            add("Target", function() game:lockTarget(entry.entity, entry.name, entry.faction) end)
            if not entry.hostile then
                add("Attack", function() game:attackTarget(entry.entity, entry.name, entry.faction) end)
            end
        end
    end

    if same(game.lookingAt, entry.entity) then
        add("Stop looking", function() game:lookAtShip(true) end)
    else
        add("Look at", function() game:lookAt(entry.entity, entry.name) end)
    end

    if same(autopilotTarget(), entry.entity) then
        add("Stop autopilot", function()
            local AutoPilotSystem = require("Modules.Constructs.Systems.AutoPilotSystem")
            AutoPilotSystem:disengage(game.playerShip)
            game.arrivalAction = nil
        end)
    else
        add("Approach", function() game:approach(entry.entity, entry.name) end)
    end

    if entry.dock then
        local inRange = game:dockInRange()
        local here = inRange and same(inRange.entity, entry.entity)
        add(here and "Dock" or "Approach and dock", function() game:dockAt(entry.dock) end)
    elseif entry.gate then
        local near = game:gateInRange()
        local here = near and same(near.entity, entry.entity)
        add(here and "Jump" or "Approach and jump", function() game:jumpVia(entry.gate) end)
    end

    add("Show on map", function() game:showOnMap(entry.entity, entry.name) end)
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
    Gui:beginLayerAtPos(Vec2f(menu.x, menu.y))
    Gui:beginVerticalContainer()
    Gui:setScale(s)
    local over = Gui:isMouseOver(FocusType.Scroll)
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
            scroll = 0
        end
    end
    Gui:endContainer()
end

--- A column heading that sorts by its column when clicked.
---@param label string
---@param key string
---@param width number
---@param align integer|nil
local function heading(label, key, width, align)
    local active = SystemOverview.sortKey == key
    local arrow = active and (SystemOverview.sortDescending and " v" or " ^") or ""
    Gui:beginStackContainer()
    Gui:setFixedWidth(width)
    Gui:setChildrenAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(hover and ROW_HOVER or NO_COLOR)
    Gui:text(label .. arrow, font(12), active and WHITE or DIM)
    Gui:setAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:endContainer()
    if hover and Input:mouse():isPressed(MouseControl.Left) then
        SystemOverview:setSort(key)
        scroll = 0
    end
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
    local selected = same(SystemOverview.selected, entry.entity)
    local targeted = game:isTarget(entry.entity)
    Gui:setBackgroundColor((hover and ROW_HOVER) or (targeted and ROW_TARGET)
        or (selected and ROW_SELECTED) or NO_COLOR)

    -- What the player has pointed at it: weapons, the autopilot, the camera
    local marker = "  "
    if targeted then
        marker = game.attacking and "X " or "+ "
    elseif same(apTarget, entry.entity) then
        marker = "> "
    elseif same(game.lookingAt, entry.entity) then
        marker = "o "
    end
    cell(marker .. clip(entry.name, 30), COL_NAME, targeted and GOLD or colorOf(entry), 14)
    cell(entry.kind, COL_KIND, GREY, 13)
    cell(UniverseScaleConfig:formatDistance(entry.distance), COL_DIST, WHITE, 14, AlignHorizontal.Right)
    Gui:endContainer()

    if hover then
        if Input:mouse():isPressed(MouseControl.Right) then return "right" end
        if Input:mouse():isPressed(MouseControl.Left) then return "left" end
    end
    return nil
end

--- The knob's size and place on the track, in HUD pixels.
---@param total integer
---@param rows integer
---@return number trackHeight, number knob, number top
local function knobGeometry(total, rows)
    local trackHeight = rows * ROW_HEIGHT
    if total <= rows then return trackHeight, trackHeight, 0 end
    local knob = math.max(14, math.floor(trackHeight * rows / total))
    local top = math.floor((trackHeight - knob) * scroll / math.max(1, total - rows))
    return trackHeight, knob, top
end

--- One piece of the track; returns whether it was pressed this frame.
local function trackPiece(height, color, hoverColor)
    Gui:beginStackContainer()
    Gui:setFixedSize(BAR_WIDTH, math.max(0, height))
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(hover and hoverColor or color)
    Gui:endContainer()
    return hover and Input:mouse():isPressed(MouseControl.Left)
end

--- The scroll bar beside the rows: a track the height of the rows shown and
--- a knob whose size and place are the share of the list in view. Drag the
--- knob to scroll; click the track above or below it for a page.
---
--- The track is three pieces -- above the knob, the knob, below it -- each
--- asking for the mouse, so where a click lands needs no screen coordinates.
---@param total integer
---@param rows integer
local function drawScrollbar(total, rows)
    local trackHeight, knob, top = knobGeometry(total, rows)
    Gui:beginVerticalContainer()
    Gui:setFixedSize(BAR_WIDTH, trackHeight)
    if total > rows then
        local dragging = drag ~= nil
        if trackPiece(top, BAR_BG, BAR_HOVER) then
            scroll = scroll - rows
        end
        if trackPiece(knob, dragging and BAR_KNOB_HELD or BAR_KNOB, BAR_KNOB_HELD) then
            drag = { y = Input:mouse():position().y, scroll = scroll }
        end
        if trackPiece(trackHeight - top - knob, BAR_BG, BAR_HOVER) then
            scroll = scroll + rows
        end
    end
    Gui:endContainer()
end

--- While the knob is held: the list follows the cursor, the knob's travel
--- standing for the whole list. Let go and the drag ends.
---@param total integer
---@param rows integer
---@param s number the HUD scale (the cursor moves in screen pixels)
local function followDrag(total, rows, s)
    if not drag then return end
    if not Input:mouse():isDown(MouseControl.Left) or total <= rows then
        drag = nil
        return
    end
    local trackHeight, knob = knobGeometry(total, rows)
    local travel = math.max(1, trackHeight - knob)
    local moved = (Input:mouse():position().y - drag.y) / s
    scroll = drag.scroll + math.floor(moved * (total - rows) / travel + 0.5)
end

--- The whole panel, and the menu over it.
function OverviewPanel.render()
    local game = LimitTheoryRedux
    if not (game and game.overviewShowing and game:overviewShowing()) then
        menu = nil
        UIMouse.overPanel = false
        return
    end

    local s = hudScale()
    local cfg = Config.game.overview
    local list = SystemOverview:visible()
    local rows = math.max(1, cfg.maxRows or 18)
    local total = #list
    -- A question on screen has the mouse: the list waits for it
    local modal = game.confirmationShowing and game:confirmationShowing()
    if modal then drag = nil end
    -- The wheel scrolls the list while the cursor is over the panel (last
    -- frame's answer: the panel has not been laid out yet this frame)
    if UIMouse.overPanel and not menu and not modal and not drag then
        local wheel = Input:mouse():value(MouseControl.ScrollY)
        if math.abs(wheel) > 0.001 then
            -- Notches, rounded away from zero symmetrically (floor(x - 0.5)
            -- would make one notch down two)
            local notches = wheel > 0 and math.floor(wheel + 0.5) or -math.floor(-wheel + 0.5)
            if notches == 0 then notches = wheel > 0 and 1 or -1 end
            scroll = scroll - notches * WHEEL_ROWS
        end
    end
    followDrag(total, rows, s)
    scroll = math.max(0, math.min(scroll, math.max(0, total - rows)))
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

    -- Column headings: click to sort
    Gui:beginHorizontalContainer()
    heading("  Name", "name", COL_NAME)
    heading("Type", "type", COL_KIND)
    heading("Distance", "distance", COL_DIST, AlignHorizontal.Right)
    Gui:endContainer()

    -- The rows in view, with the scroll bar beside them
    Gui:beginHorizontalContainer()
    Gui:beginVerticalContainer()
    Gui:setFixedWidth(COL_NAME + COL_KIND + COL_DIST)
    for i = scroll + 1, math.min(total, scroll + rows) do
        local entry = list[i]
        local click = drawRow(entry, apTarget)
        if click then clickedEntry, clickKind = entry, click end
    end
    if total == 0 then
        cell("Nothing here matches the filters.", COL_NAME + COL_KIND + COL_DIST, DIM, 13)
    end
    Gui:endContainer()
    box(4, 1, nil)
    drawScrollbar(total, rows)
    Gui:endContainer()
    -- A page click on the track may have gone past an end
    scroll = math.max(0, math.min(scroll, math.max(0, total - rows)))

    -- Where the list is, and what it leaves out
    local footer
    if total > rows then
        footer = string.format("%d-%d of %d  ·  wheel or drag to scroll", scroll + 1, math.min(total, scroll + rows), total)
    else
        footer = string.format("%d listed", total)
    end
    if SystemOverview.filters.asteroid then
        footer = footer .. string.format("  ·  asteroids within %s",
            UniverseScaleConfig:formatDistance(cfg.asteroidRange or 10))
    end
    cell(footer, WIDTH - 16, DIM, 11)

    Gui:endContainer()
    Gui:endContainer()

    -- The menu, over everything
    local overMenu = drawMenu(s)
    -- A drag holds the mouse wherever the cursor wanders: the left button is
    -- also the fire button, and the cameras have no business with it either
    UIMouse.overPanel = overPanel or overMenu or drag ~= nil

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
            if same(lastClick.entity, clickedEntry.entity) and t - lastClick.time < DOUBLE_CLICK then
                lastClick.entity, lastClick.time = nil, -1
                game:approach(clickedEntry.entity, clickedEntry.name)
            else
                lastClick.entity, lastClick.time = clickedEntry.entity, t
            end
        end
    end
end

return OverviewPanel
