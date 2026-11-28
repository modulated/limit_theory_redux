-- The docked screen's frame, its look, and the pieces its tabs are built of
-- (StationTabs draws the tabs with them):
--
--   +--------------------------------------------------------------------+
--   | STATION NAME  [SYSTEM] [OWNER] [KIND]       WALLET | SHIP  [UNDOCK]  |  header
--   +--------------------------------------------------------------------+
--   | HANGAR  MARKET  FACTORY  SHIP FITTING  NEARBY  BOUNTY      [REPAIR] |  tabs
--   +--------------------------------------------------------------------+
--   |                                                                    |
--   |   the tab: its own panels, laid out over the whole of this area    |
--   |                                                                    |
--   +--------------------------------------------------------------------+
--
-- Dark slate panels with hairline borders, amber for what you act on (the
-- current tab, the main button, a selected row), cyan for values and the
-- ship, squared headings in capitals, numbers in mono. Laid out at 1920 x
-- 1080 and scaled to the window (`StationFrame.scale`). Drawn straight with
-- Gui, so borders and colours are exact.

local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local PlayerCargo = require("Modules.Economy.Managers.PlayerCargo")
local PlayerFleet = require("Modules.Constructs.Managers.PlayerFleet")
local MarketSystem = require("Modules.Economy.Systems.MarketSystem")

local StationFrame = {}

local function hex(h, a)
    local r = tonumber(h:sub(2, 3), 16) / 255
    local g = tonumber(h:sub(4, 5), 16) / 255
    local b = tonumber(h:sub(6, 7), 16) / 255
    return Color(r, g, b, a or 1)
end

--- The palette
StationFrame.C = {
    BG = hex("#0B0F14"),        -- the screen, a field, a tile
    HEAD = hex("#070A0E"),      -- the header bar
    PANEL = hex("#111821"),     -- a panel
    SELECT = hex("#1C2836"),    -- a selected row, a pressed button
    HOVER = hex("#151E29"),     -- a row under the cursor
    RULE = hex("#1E2A36"),      -- a panel's border, a rule
    ROW_RULE = hex("#16202B"),  -- between rows
    EDGE = hex("#2A3A4A"),      -- a button's or a field's border
    DASH = hex("#3A4A5A"),      -- an empty slot's border
    TEXT = hex("#E6EDF3"),
    SUB = hex("#B7C4D1"),
    DIM = hex("#8796A6"),
    AMBER = hex("#F2A93B"),     -- what you act on
    AMBER_HI = hex("#FFD08A"),
    CYAN = hex("#4FD1E8"),      -- values, the ship
    VIOLET = hex("#A99BF5"),
    ORE = hex("#C98B4A"),
    RED = hex("#FF6B5B"),
    GREEN = hex("#5BD68A"),
    NONE = Color(0, 0, 0, 0),
}
local C = StationFrame.C

--- The fonts: squared headings, a clean body, numbers in mono
local F = {
    HEAD = "RajdhaniBold",
    HEAD_SEMI = "RajdhaniSemiBold",
    BODY = "TitilliumWeb",
    BODY_SEMI = "TitilliumWebSemiBold",
    MONO = "FiraMono",
    MONO_MED = "FiraMonoMedium",
}
StationFrame.F = F

--- The scale: the layout is drawn for 1920 x 1080
---@return number
function StationFrame.scale()
    return math.max(0.6, math.min(2.0, Window:width() / 1920, Window:height() / 1080))
end

local u = 1 -- the scale of the frame being drawn
--- Design pixels to screen pixels
local function px(n) return math.floor(n * u + 0.5) end
StationFrame.px = function(n) return px(n) end

------------------------------------------------------------------------------
-- Words and numbers

---@param n number
---@return string 1,234,567
local function grouped(n)
    n = tonumber(n) or 0
    local neg = n < 0
    local s = tostring(math.floor(math.abs(n) + 0.5))
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (neg and "-" or "") .. s
end
StationFrame.grouped = grouped

--- Cut a name to fit
function StationFrame.clip(s, n)
    s = tostring(s or "")
    if #s <= n then return s end
    return s:sub(1, n - 1) .. "."
end

--- An item's colour by its group, for its badge
---@param item table ItemDefinition
---@return Color
function StationFrame.itemColor(item)
    local g = item and item.group or ""
    if g == "Raw Materials" or g == "Refined Materials" or g == "Gases" then return C.ORE end
    if g == "Equipment" or g == "Constructs" then return C.AMBER end
    if g == "Consumables" or g == "Data" then return C.VIOLET end
    return C.CYAN
end

--- Two letters for an item's badge: its words' initials, or its first two
---@param name string
---@return string
function StationFrame.itemCode(name)
    local words = {}
    for w in tostring(name):gmatch("[%a%d]+") do words[#words + 1] = w end
    if #words >= 2 then return (words[1]:sub(1, 1) .. words[2]:sub(1, 1)):upper() end
    return tostring(name):sub(1, 2):upper()
end

------------------------------------------------------------------------------
-- Pieces

--- Text in a font at a design size
local function txt(value, name, size, color)
    Gui:text(tostring(value), Cache.Font(name, math.max(8, px(size))), color or C.TEXT)
end
StationFrame.txt = txt

--- Text in a box of a fixed design width, aligned in it
function StationFrame.cell(width, value, name, size, color, align)
    Gui:beginStackContainer()
    Gui:setFixedWidth(px(width))
    txt(value, name, size, color)
    Gui:setAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:endContainer()
end
local cell = StationFrame.cell

--- A horizontal rule as wide as its parent
function StationFrame.rule(color, thickness)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(thickness or 1)
    Gui:setBackgroundColor(color or C.RULE)
    Gui:endContainer()
end
local rule = StationFrame.rule

--- A gap
function StationFrame.gap(w, h)
    Gui:beginStackContainer()
    Gui:setFixedSize(px(w or 1), px(h or 1))
    Gui:endContainer()
end

--- Whether the last-begun box was clicked (call right after beginning it)
local function clicked(hover)
    return hover and Input:mouse():isPressed(MouseControl.Left)
end

--- A button. opts: kind "primary" (amber fill), "outline" (amber edge),
--- "on" (selected: amber on slate), else plain; width, height, size,
--- enabled. Returns whether it was clicked.
---@return boolean
function StationFrame.button(label, opts)
    opts = opts or {}
    local enabled = opts.enabled ~= false
    Gui:beginStackContainer()
    if opts.width then Gui:setFixedWidth(px(opts.width)) end
    Gui:setFixedHeight(px(opts.height or 34))
    Gui:setPadding(px(opts.pad or 14), 0)
    local hover = enabled and Gui:isMouseOver(FocusType.Mouse)
    local color
    if opts.kind == "primary" then
        Gui:setBackgroundColor(enabled and (hover and C.AMBER_HI or C.AMBER) or C.SELECT)
        color = enabled and C.BG or C.DIM
    else
        local on = opts.kind == "on"
        Gui:setBackgroundColor((on or hover) and C.SELECT or C.NONE)
        Gui:setBorderWidth(1)
        Gui:setBorderColor(enabled and (opts.kind == "outline" or on) and C.AMBER or C.EDGE)
        color = not enabled and C.DIM or ((opts.kind == "outline" or on) and C.AMBER or C.SUB)
    end
    txt(label, opts.font or ((opts.kind == "primary" or opts.kind == "outline") and F.HEAD or F.BODY_SEMI),
        opts.size or 14, color)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
    return clicked(hover)
end
local button = StationFrame.button

--- A row of filter chips; returns the one clicked, if any.
---@param list table[] { id, label }
---@param current string
---@return string|nil
function StationFrame.filters(list, current, width)
    local picked = nil
    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(6))
    for _, f in ipairs(list) do
        if button(f.label, { kind = f.id == current and "on" or nil, height = 30, size = 12,
                width = width, pad = 10 }) then
            picked = f.id
        end
    end
    Gui:endContainer()
    return picked
end

--- A small bordered chip of text
local function chip(value, color)
    Gui:beginStackContainer()
    Gui:setPadding(px(10), px(3))
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.EDGE)
    txt(value, F.MONO, 13, color or C.SUB)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
end
StationFrame.chip = chip

--- A two-letter item badge
function StationFrame.badge(item, size)
    local color = StationFrame.itemColor(item)
    Gui:beginStackContainer()
    Gui:setFixedSize(px(size or 36), px(size or 36))
    Gui:setBackgroundColor(Color(color.r, color.g, color.b, 0.14))
    Gui:setBorderWidth(1)
    Gui:setBorderColor(color)
    txt(StationFrame.itemCode(item.displayName), F.MONO_MED, 12, color)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
end
local badge = StationFrame.badge

--- A letter badge in a colour (a slot kind)
function StationFrame.letter(value, color, size)
    Gui:beginStackContainer()
    Gui:setFixedSize(px(size or 32), px(size or 32))
    Gui:setBorderWidth(1)
    Gui:setBorderColor(color)
    txt(value, F.MONO_MED, 13, color)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
end

--- A label over a value
function StationFrame.stat(label, value, valueColor, align, size)
    Gui:beginVerticalContainer()
    Gui:setChildrenAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(px(2))
    txt(label, F.BODY_SEMI, 12, C.DIM)
    txt(value, F.MONO_MED, size or 20, valueColor or C.TEXT)
    Gui:endContainer()
end
local stat = StationFrame.stat

--- A tile: a label over a value, in a dark box
function StationFrame.tile(width, label, value, color)
    Gui:beginVerticalContainer()
    if width then Gui:setFixedWidth(px(width)) end
    Gui:setPadding(px(12), px(10))
    Gui:setSpacing(px(4))
    Gui:setBackgroundColor(C.BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.RULE)
    txt(label, F.BODY_SEMI, 12, C.DIM)
    txt(value, F.MONO_MED, 16, color or C.TEXT)
    Gui:endContainer()
end

--- A bar: a share filled, in a dark trough
function StationFrame.bar(width, height, frac, color)
    frac = math.max(0, math.min(1, frac or 0))
    Gui:beginStackContainer()
    if width then Gui:setFixedWidth(px(width)) else Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top) end
    Gui:setFixedHeight(px(height or 10))
    Gui:setBackgroundColor(C.BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.EDGE)
    if frac > 0 then
        Gui:beginStackContainer()
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Stretch)
        Gui:setPercentWidth(math.max(0.5, frac * 100))
        Gui:setBackgroundColor(color or C.CYAN)
        Gui:endContainer()
    end
    Gui:endContainer()
end

--- Begin a panel of a fixed design size (nil: as its content); end it with
--- `endPanel`. opts: accent (an amber border), pad, spacing, fill (bg).
function StationFrame.panel(width, height, opts)
    opts = opts or {}
    Gui:beginVerticalContainer()
    if width then Gui:setFixedWidth(px(width)) end
    if height then Gui:setFixedHeight(px(height)) end
    Gui:setBackgroundColor(opts.fill or C.PANEL)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(opts.accent and C.AMBER or C.RULE)
    if opts.pad then Gui:setPadding(px(opts.pad), px(opts.padY or opts.pad)) end
    if opts.spacing then Gui:setSpacing(px(opts.spacing)) end
end
function StationFrame.endPanel()
    Gui:endContainer()
end

--- A panel's title bar: a heading, a note beside it, and room on the right
--- (`right`, a function drawing into it).
function StationFrame.titleBar(title, note, right, size)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(px(20), px(14))
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(px(16))
    txt(title, F.HEAD, size or 19, C.TEXT)
    if note then txt(note, F.MONO, 13, C.DIM) end
    Gui:endContainer()
    if right then
        Gui:beginHorizontalContainer()
        Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
        Gui:setChildrenAlignment(AlignHorizontal.Right, AlignVertical.Center)
        Gui:setSpacing(px(8))
        right()
        Gui:endContainer()
    end
    Gui:endContainer()
    rule()
end

--- A table's column heads. cols: { { width, label, align } }
function StationFrame.columns(cols, padX)
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(px(padX or 20), px(9))
    Gui:setSpacing(px(16))
    for _, c in ipairs(cols) do
        cell(c[1], c[2], F.BODY_SEMI, 12, C.DIM, c[3])
    end
    Gui:endContainer()
    rule()
end

--- Begin a table row: returns hovered, clicked. `selected` lights it (and
--- an amber bar on its left). End it with `endRow`.
function StationFrame.row(height, selected, padX, spacing)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(px(height))
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(selected and C.SELECT or (hover and C.HOVER or C.NONE))
    if selected then
        Gui:beginStackContainer()
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Stretch)
        Gui:setFixedWidth(px(3))
        Gui:setBackgroundColor(C.AMBER)
        Gui:endContainer()
    end
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setPadding(px(padX or 20), 0)
    Gui:setSpacing(px(spacing or 16))
    return hover, clicked(hover)
end
function StationFrame.endRow()
    Gui:endContainer()
    Gui:endContainer()
    rule(C.ROW_RULE)
end

--- A name with a smaller line under it
function StationFrame.twoLine(width, top, bottom, topColor, topFont)
    Gui:beginVerticalContainer()
    if width then Gui:setFixedWidth(px(width)) end
    Gui:setSpacing(px(1))
    txt(top, topFont or F.BODY_SEMI, 15, topColor or C.TEXT)
    if bottom and bottom ~= "" then txt(bottom, F.BODY, 12, C.DIM) end
    Gui:endContainer()
end

--- Scrolling lists: the first row each list shows, moved by the wheel while
--- the cursor is over it.
local scrolls = {}
--- Begin a list `visible` rows high (of `rowHeight`); returns the first and
--- last index to draw. End it with `endList`.
function StationFrame.list(id, total, visible, rowHeight)
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(px(visible * rowHeight))
    local over = Gui:isMouseOver(FocusType.Scroll)
    local first = scrolls[id] or 1
    if over then
        local wheel = Input:mouse():value(MouseControl.ScrollY)
        if math.abs(wheel) > 0.01 then first = first - (wheel > 0 and 1 or -1) * math.max(1, math.floor(math.abs(wheel))) end
    end
    first = math.max(1, math.min(first, math.max(1, total - visible + 1)))
    scrolls[id] = first
    return first, math.min(total, first + visible - 1)
end
function StationFrame.endList(total, visible)
    Gui:endContainer()
end
--- A line saying how many more there are past the list, if any
function StationFrame.more(total, last, padX)
    if total > last then
        Gui:beginStackContainer()
        Gui:setPadding(px(padX or 20), px(6))
        txt(string.format("%d more below  ·  scroll", total - last), F.BODY, 12, C.DIM)
        Gui:endContainer()
    end
end

--- A total line at a panel's foot: a label on the left, a value on the right
function StationFrame.footer(label, value, color)
    rule()
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(px(20), px(12))
    txt(label, F.MONO, 14, C.DIM)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    txt(value, F.MONO, 14, color or C.CYAN)
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:endContainer()
end

--- Text that wraps at a design width
function StationFrame.para(width, value, size, color)
    -- Wrap by hand: about 0.5 em a character
    local perLine = math.max(10, math.floor(width / ((size or 14) * 0.52)))
    local lines, line = {}, ""
    for word in tostring(value):gmatch("%S+") do
        if #line + #word + 1 > perLine and #line > 0 then
            lines[#lines + 1] = line
            line = word
        else
            line = #line > 0 and (line .. " " .. word) or word
        end
    end
    if #line > 0 then lines[#lines + 1] = line end
    Gui:beginVerticalContainer()
    Gui:setSpacing(px(3))
    for _, l in ipairs(lines) do txt(l, F.BODY, size or 14, color or C.SUB) end
    Gui:endContainer()
end

--- A number stepper: [-] value [+] ... ; returns the new value.
---@param value integer
---@param steps table[] { label, delta } on either side (negatives first)
---@param field table|nil a UIComponent to render in the middle (a text field)
function StationFrame.stepper(value, steps, field, valueWidth)
    Gui:beginHorizontalContainer()
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(px(6))
    local result = value
    for _, st in ipairs(steps) do
        if st[2] < 0 and button(st[1], { height = 40, width = st.width or 44, size = 14, pad = 4 }) then
            result = result + st[2]
        end
    end
    Gui:beginStackContainer()
    Gui:setFixedSize(px(valueWidth or 110), px(40))
    Gui:setBackgroundColor(C.BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.EDGE)
    if field then
        field:render()
    else
        txt(grouped(value), F.MONO, 16, C.TEXT)
    end
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:setPadding(px(10), 0)
    Gui:endContainer()
    for _, st in ipairs(steps) do
        if st[2] > 0 and button(st[1], { height = 40, width = st.width or 44, size = 14, pad = 4 }) then
            result = result + st[2]
        end
    end
    Gui:endContainer()
    return result
end

------------------------------------------------------------------------------
-- The active ship: who, how it is, and its hold (the Hangar tab's right side)

--- opts: station, selected (item id picked in the hold), onPick(itemId),
--- rows (how many hold rows fit)
function StationFrame.activeShip(width, height, opts)
    opts = opts or {}
    local game = LimitTheoryRedux
    StationFrame.panel(width, height)

    -- Who
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(px(20), px(18))
    Gui:setSpacing(px(12))
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(px(12))
    txt("ACTIVE SHIP", F.BODY_SEMI, 12, C.CYAN)
    Gui:beginStackContainer()
    Gui:setFixedSize(px(width - 160), 1)
    Gui:setBackgroundColor(C.RULE)
    Gui:endContainer()
    Gui:endContainer()
    local ship = PlayerFleet:active()
    local hull = PlayerFleet.hullOf(ship)
    txt(ship and ship.name or "No ship", F.HEAD, 28, C.TEXT)
    txt(hull and string.format("%s  ·  class %s", hull.displayName or "?", hull.class or "?") or "-",
        F.BODY, 14, C.DIM)

    local entity = game.playerShip
    local CoreComponents = require("Modules.Core.Components")
    local ConstructComponents = require("Modules.Constructs.Components")
    local valid = entity and entity:isValid()
    local health = valid and entity:get(CoreComponents.Health)
    local defense = valid and entity:get(ConstructComponents.Defense)
    local loadout = valid and entity:get(ConstructComponents.Loadout)
    local function pct(cur, max)
        if not max or max <= 0 then return "-" end
        return string.format("%d%%", math.floor(100 * cur / max + 0.5))
    end
    local fitted = 0
    if loadout then
        for _ in pairs(loadout.weapons or {}) do fitted = fitted + 1 end
        for _ in pairs(loadout.modules or {}) do fitted = fitted + 1 end
    end
    local tileW = math.floor((width - 40 - 24) / 3)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(12))
    StationFrame.tile(tileW, "HULL", health and pct(health:getCurrentHealth(), health:getMaxHealth()) or "-",
        health and health:getCurrentHealth() < health:getMaxHealth() and C.AMBER or C.TEXT)
    StationFrame.tile(tileW, "SHIELDS", defense and pct(defense:getCurrentShield(), defense:getMaxShield()) or "-")
    StationFrame.tile(tileW, "FITTED", tostring(fitted))
    Gui:endContainer()
    Gui:endContainer()
    rule()

    -- The hold
    local used, capacity = PlayerCargo:getLoad()
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(px(20), px(14))
    Gui:setSpacing(px(10))
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    txt("CARGO HOLD", F.HEAD, 17, C.TEXT)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    txt(grouped(used), F.MONO, 14, C.TEXT)
    txt(" / " .. grouped(capacity) .. " t", F.MONO, 14, C.DIM)
    Gui:endContainer()
    Gui:endContainer()
    local frac = capacity > 0 and used / capacity or 0
    StationFrame.bar(nil, 10, frac, frac > 0.9 and C.AMBER or C.CYAN)
    Gui:endContainer()
    rule()
    local nameW = width - 40 - 44 - 90 - 80 - 48
    StationFrame.columns({ { 36, "" }, { nameW, "ITEM" }, { 90, "QTY", AlignHorizontal.Right },
        { 80, "MASS", AlignHorizontal.Right } })

    local rows = PlayerCargo:list()
    local value = 0
    for _, row in ipairs(rows) do
        local quote = opts.station and MarketSystem:quote(opts.station, row.item.id)
        value = value + (quote and (quote.bid or quote.last) or 0) * row.units
    end
    local visible = math.max(1, opts.rows or 6)
    local first, last = StationFrame.list("hold", #rows, visible, 56)
    if #rows == 0 then
        Gui:beginStackContainer()
        Gui:setPadding(px(20), px(14))
        txt("The hold is empty.", F.BODY, 14, C.DIM)
        Gui:endContainer()
    end
    for i = first, last do
        local row = rows[i]
        local _, click = StationFrame.row(56, opts.selected == row.item.id)
        badge(row.item, 36)
        StationFrame.twoLine(nameW, StationFrame.clip(row.item.displayName, 26), row.item.group)
        cell(90, grouped(row.units), F.MONO, 14, C.TEXT, AlignHorizontal.Right)
        cell(80, grouped((row.item.mass or 0) * row.units) .. " t", F.MONO, 14, C.SUB, AlignHorizontal.Right)
        StationFrame.endRow()
        if click and opts.onPick then opts.onPick(row.item.id) end
    end
    StationFrame.endList()
    StationFrame.more(#rows, last)
    StationFrame.footer("CARGO VALUE HERE", grouped(value) .. " CR")

    StationFrame.endPanel()
end

------------------------------------------------------------------------------
-- The header and the tab strip

local HEADER_H, TABS_H = 72, 56

local function header(args)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(px(HEADER_H))
    Gui:setPadding(px(32), 0)
    Gui:setBackgroundColor(C.HEAD)

    -- Left: the station and where it is
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(px(32))
    txt(args.title or "Station", F.HEAD, 26, C.TEXT)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(px(8))
    for _, c in ipairs(args.chips or {}) do chip(c.text, c.color) end
    Gui:endContainer()
    Gui:endContainer()

    -- Right: the wallet, the ship, the way out
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:setChildrenAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:setSpacing(px(28))
    stat("WALLET", grouped(PlayerWallet:get()) .. " CR", C.TEXT, AlignHorizontal.Right)
    Gui:beginStackContainer()
    Gui:setFixedSize(1, px(40))
    Gui:setBackgroundColor(C.RULE)
    Gui:endContainer()
    local ship = PlayerFleet:active()
    Gui:beginVerticalContainer()
    Gui:setSpacing(px(2))
    txt("SHIP", F.BODY_SEMI, 12, C.DIM)
    txt(ship and ship.name or "-", F.HEAD, 19, C.TEXT)
    Gui:endContainer()
    if button("UNDOCK", { kind = "primary", height = 48, size = 19, pad = 32 }) and args.onUndock then
        args.onUndock()
    end
    Gui:endContainer()

    Gui:endContainer()
end

local function tabStrip(args)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(px(TABS_H))
    Gui:setPadding(px(32), 0)
    Gui:setBackgroundColor(C.BG)

    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Stretch)
    for _, tab in ipairs(args.tabs or {}) do
        local active = tab.id == args.active
        Gui:beginStackContainer()
        Gui:setFixedHeight(px(TABS_H))
        Gui:setPadding(px(28), 0)
        local hover = Gui:isMouseOver(FocusType.Mouse)
        Gui:setBackgroundColor(active and C.PANEL or (hover and C.HOVER or C.NONE))
        txt(tab.label, F.HEAD, 17, active and C.AMBER or (hover and C.SUB or C.DIM))
        Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
        Gui:beginStackContainer()
        Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Bottom)
        Gui:setFixedHeight(px(2))
        Gui:setBackgroundColor(active and C.AMBER or C.NONE)
        Gui:endContainer()
        Gui:endContainer()
        if clicked(hover) and not active and args.onTab then args.onTab(tab.id) end
    end
    Gui:endContainer()

    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:setSpacing(px(8))
    for _, action in ipairs(args.actions or {}) do
        if button(action.label, { enabled = action.enabled, height = 36, size = 13 }) and action.callback then
            action.callback()
        end
    end
    Gui:endContainer()

    Gui:endContainer()
end

------------------------------------------------------------------------------

--- The main area's size, in design pixels: what a tab lays itself out in.
---@return number width, number height
function StationFrame.area()
    local sw, sh = Window:width() / u, Window:height() / u
    return math.floor(sw - 64), math.floor(sh - HEADER_H - TABS_H - 2 - 24 - 32)
end

--- Draw the docked screen.
---@param args table { title, chips = {{text, color}}, tabs = {{id, label}},
---   active, onTab(id), actions = {{label, enabled, callback}}, onUndock(),
---   body = function(width, height) drawing the tab in the main area }
function StationFrame.draw(args)
    u = StationFrame.scale()
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setBackgroundColor(C.BG)

    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    header(args)
    rule()
    tabStrip(args)
    rule()

    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setPadding(px(32), px(24))
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Top)
    Gui:setSpacing(px(24))
    if args.body then
        local w, h = StationFrame.area()
        args.body(w, h)
    end
    Gui:endContainer()

    Gui:endContainer()
    Gui:endContainer()
end

return StationFrame
