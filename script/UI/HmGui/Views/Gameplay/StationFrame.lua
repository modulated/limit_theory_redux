-- The docked screen's frame and look (the Station view draws its tabs inside
-- it):
--
--   +--------------------------------------------------------------------+
--   | STATION NAME  [SYSTEM] [OWNER] [KIND]       WALLET | SHIP  [UNDOCK]  |  header
--   +--------------------------------------------------------------------+
--   | HANGAR  MARKET  FACTORY  SHIP FITTING  NEARBY  BOUNTY  [REPAIR] ... |  tabs
--   +--------------------------------------------------------------------+
--   | +-- the tab ---------------------------------+ +-- ACTIVE SHIP ---+ |
--   | |                                            | | name, class      | |
--   | |                                            | | HULL SHIELD FIT  | |
--   | |                                            | | CARGO HOLD ====  | |
--   | |                                            | | items...         | |
--   | +--------------------------------------------+ +------------------+ |
--   +--------------------------------------------------------------------+
--
-- Dark slate panels with hairline borders, amber for what you act on (the
-- current tab, the main button), cyan for values and the ship, squared
-- headings in capitals. Drawn straight with Gui (borders and exact colours);
-- the tabs themselves are the Station view's.

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
    BG = hex("#0B0F14"),        -- the screen
    HEAD = hex("#070A0E"),      -- the header bar
    PANEL = hex("#111821"),     -- a panel
    SELECT = hex("#1C2836"),    -- a selected row, a pressed button
    RULE = hex("#1E2A36"),      -- a panel's border, a rule
    ROW_RULE = hex("#16202B"),  -- between rows
    EDGE = hex("#2A3A4A"),      -- a button's or a field's border
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
}
local C = StationFrame.C

--- The fonts: squared headings, a clean body, numbers in mono
StationFrame.HEAD = "RajdhaniBold"
StationFrame.HEAD_SEMI = "RajdhaniSemiBold"
StationFrame.BODY = "TitilliumWeb"
StationFrame.BODY_SEMI = "TitilliumWebSemiBold"
StationFrame.MONO = "FiraMono"
StationFrame.MONO_MED = "FiraMonoMedium"

local function font(name, size)
    return Cache.Font(name, math.max(8, math.floor(size)))
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

---@param n number
---@return string 1,234,567
local function grouped(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""):gsub("^%-,", "-"))
end
StationFrame.grouped = grouped

------------------------------------------------------------------------------
-- Pieces

local function txt(value, name, size, color)
    Gui:text(value, font(name, size), color)
end

--- A horizontal rule as wide as its parent
local function rule(color, thickness)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(thickness or 1)
    Gui:setBackgroundColor(color or C.RULE)
    Gui:endContainer()
end
StationFrame.rule = rule

--- A button with a border. kind: "primary" (amber), "outline" (amber edge),
--- else plain. Returns whether it was clicked.
---@return boolean
local function button(label, s, opts)
    opts = opts or {}
    local enabled = opts.enabled ~= false
    Gui:beginStackContainer()
    if opts.width then Gui:setFixedWidth(math.floor(opts.width * s)) end
    Gui:setFixedHeight(math.floor((opts.height or 32) * s))
    Gui:setPadding(math.floor(14 * s), 0)
    local hover = enabled and Gui:isMouseOver(FocusType.Mouse)
    local textColor
    if opts.kind == "primary" then
        Gui:setBackgroundColor(enabled and (hover and C.AMBER_HI or C.AMBER) or C.SELECT)
        textColor = enabled and C.BG or C.DIM
    else
        Gui:setBackgroundColor(hover and C.SELECT or Color(0, 0, 0, 0))
        Gui:setBorderWidth(1)
        Gui:setBorderColor(opts.kind == "outline" and enabled and C.AMBER or C.EDGE)
        textColor = not enabled and C.DIM or (opts.kind == "outline" and C.AMBER or C.SUB)
    end
    txt(label, opts.kind == "primary" and StationFrame.HEAD or StationFrame.BODY_SEMI,
        (opts.size or 14) * s, textColor)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
    return hover and Input:mouse():isPressed(MouseControl.Left)
end
StationFrame.button = button

--- A small bordered chip of text
local function chip(value, s, color)
    Gui:beginStackContainer()
    Gui:setPadding(math.floor(10 * s), math.floor(3 * s))
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.EDGE)
    txt(value, StationFrame.MONO, 13 * s, color or C.SUB)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
end

--- A two-letter item badge
local function badge(item, s, size)
    local color = StationFrame.itemColor(item)
    size = math.floor((size or 30) * s)
    Gui:beginStackContainer()
    Gui:setFixedSize(size, size)
    Gui:setBackgroundColor(Color(color.r, color.g, color.b, 0.14))
    Gui:setBorderWidth(1)
    Gui:setBorderColor(color)
    txt(StationFrame.itemCode(item.displayName), StationFrame.MONO_MED, 11 * s, color)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
end
StationFrame.badge = badge

--- A label over a value
local function stat(label, value, s, valueColor, align)
    Gui:beginVerticalContainer()
    Gui:setChildrenAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(math.floor(1 * s))
    txt(label, StationFrame.BODY_SEMI, 11 * s, C.DIM)
    txt(value, StationFrame.MONO_MED, 18 * s, valueColor or C.TEXT)
    Gui:endContainer()
end

------------------------------------------------------------------------------
-- The header and the tab strip

local function header(s, args)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(math.floor(66 * s))
    Gui:setPadding(math.floor(32 * s), 0)
    Gui:setBackgroundColor(C.HEAD)

    -- Left: the station and where it is
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(math.floor(28 * s))
    txt(args.title or "Station", StationFrame.HEAD, 26 * s, C.TEXT)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(math.floor(8 * s))
    for _, c in ipairs(args.chips or {}) do chip(c.text, s, c.color) end
    Gui:endContainer()
    Gui:endContainer()

    -- Right: the wallet, the ship, the way out
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:setChildrenAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:setSpacing(math.floor(24 * s))
    stat("WALLET", grouped(PlayerWallet:get()) .. " CR", s, C.TEXT, AlignHorizontal.Right)
    Gui:beginStackContainer()
    Gui:setFixedSize(1, math.floor(36 * s))
    Gui:setBackgroundColor(C.RULE)
    Gui:endContainer()
    local ship = PlayerFleet:active()
    stat("SHIP", ship and ship.name or "-", s, C.TEXT)
    if button("UNDOCK", s, { kind = "primary", height = 44, size = 18 }) and args.onUndock then
        args.onUndock()
    end
    Gui:endContainer()

    Gui:endContainer()
end

local function tabStrip(s, args)
    local height = math.floor(50 * s)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(height)
    Gui:setPadding(math.floor(32 * s), 0)
    Gui:setBackgroundColor(C.BG)

    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Stretch)
    for _, tab in ipairs(args.tabs or {}) do
        local active = tab.id == args.active
        Gui:beginStackContainer()
        Gui:setFixedHeight(height)
        Gui:setPadding(math.floor(24 * s), 0)
        local hover = Gui:isMouseOver(FocusType.Mouse)
        if active then Gui:setBackgroundColor(C.PANEL)
        elseif hover then Gui:setBackgroundColor(Color(C.PANEL.r, C.PANEL.g, C.PANEL.b, 0.6)) end
        txt(tab.label, StationFrame.HEAD, 17 * s, active and C.AMBER or (hover and C.SUB or C.DIM))
        Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
        -- The current tab is underlined
        Gui:beginStackContainer()
        Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Bottom)
        Gui:setFixedHeight(2)
        Gui:setBackgroundColor(active and C.AMBER or Color(0, 0, 0, 0))
        Gui:endContainer()
        Gui:endContainer()
        if hover and not active and Input:mouse():isPressed(MouseControl.Left) and args.onTab then
            args.onTab(tab.id)
        end
    end
    Gui:endContainer()

    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:setSpacing(math.floor(8 * s))
    for _, action in ipairs(args.actions or {}) do
        if button(action.label, s, { enabled = action.enabled, height = 34, size = 13 }) and action.callback then
            action.callback()
        end
    end
    Gui:endContainer()

    Gui:endContainer()
end

------------------------------------------------------------------------------
-- The active ship column

---@param s number
---@param args table { ship stats... }
local function activeShip(s, args)
    local game = LimitTheoryRedux
    local pad = math.floor(18 * s)
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setBackgroundColor(C.PANEL)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.RULE)

    -- Who
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(pad, pad)
    Gui:setSpacing(math.floor(10 * s))
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(math.floor(10 * s))
    txt("ACTIVE SHIP", StationFrame.BODY_SEMI, 12 * s, C.CYAN)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Center)
    Gui:setFixedHeight(1)
    Gui:setBackgroundColor(C.RULE)
    Gui:endContainer()
    Gui:endContainer()
    local ship = PlayerFleet:active()
    local hull = PlayerFleet.hullOf(ship)
    txt(ship and ship.name or "No ship", StationFrame.HEAD, 28 * s, C.TEXT)
    txt(hull and string.format("%s  ·  class %s", hull.displayName or "?", hull.class or "?") or "-",
        StationFrame.BODY, 14 * s, C.DIM)

    -- Three tiles
    local entity = game.playerShip
    local CoreComponents = require("Modules.Core.Components")
    local ConstructComponents = require("Modules.Constructs.Components")
    local health = entity and entity:isValid() and entity:get(CoreComponents.Health)
    local defense = entity and entity:isValid() and entity:get(ConstructComponents.Defense)
    local loadout = entity and entity:isValid() and entity:get(ConstructComponents.Loadout)
    local function pct(cur, max)
        if not max or max <= 0 then return "-" end
        return string.format("%d%%", math.floor(100 * cur / max + 0.5))
    end
    local fitted, slots = 0, 0
    if loadout then
        for _ in pairs(loadout.weapons or {}) do fitted = fitted + 1 end
        for _ in pairs(loadout.modules or {}) do fitted = fitted + 1 end
        slots = (loadout.moduleSlots or 0)
    end
    local tiles = {
        { "HULL", health and pct(health:getCurrentHealth(), health:getMaxHealth()) or "-",
          health and health:getCurrentHealth() < health:getMaxHealth() and C.AMBER or C.TEXT },
        { "SHIELDS", defense and pct(defense:getCurrentShield(), defense:getMaxShield()) or "-", C.TEXT },
        { "FITTED", string.format("%d", fitted) .. (slots > 0 and string.format(" · %d slots", slots) or ""), C.TEXT },
    }
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setSpacing(math.floor(10 * s))
    for _, t in ipairs(tiles) do
        Gui:beginVerticalContainer()
        Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
        Gui:setPadding(math.floor(10 * s), math.floor(8 * s))
        Gui:setSpacing(math.floor(2 * s))
        Gui:setBackgroundColor(C.BG)
        Gui:setBorderWidth(1)
        Gui:setBorderColor(C.RULE)
        txt(t[1], StationFrame.BODY_SEMI, 11 * s, C.DIM)
        txt(t[2], StationFrame.MONO_MED, 16 * s, t[3])
        Gui:endContainer()
    end
    Gui:endContainer()
    Gui:endContainer()
    rule()

    -- The hold
    local used, capacity = PlayerCargo:getLoad()
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setPadding(pad, math.floor(14 * s))
    Gui:setSpacing(math.floor(8 * s))
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    txt("CARGO HOLD", StationFrame.HEAD, 17 * s, C.TEXT)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    txt(grouped(used), StationFrame.MONO, 14 * s, C.TEXT)
    txt(" / " .. grouped(capacity) .. " t", StationFrame.MONO, 14 * s, C.DIM)
    Gui:endContainer()
    Gui:endContainer()
    local frac = capacity > 0 and math.max(0, math.min(1, used / capacity)) or 0
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:setFixedHeight(math.floor(10 * s))
    Gui:setBackgroundColor(C.BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.EDGE)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Stretch)
    Gui:setPercentWidth(math.max(0.5, frac * 100))
    Gui:setBackgroundColor(frac > 0.9 and C.AMBER or C.CYAN)
    Gui:endContainer()
    Gui:endContainer()
    Gui:endContainer()
    rule()

    -- What is in it
    local rows = PlayerCargo:list()
    local station = args.station
    local value = 0
    local rowH = math.floor(40 * s)
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    if #rows == 0 then
        Gui:beginStackContainer()
        Gui:setPadding(pad, math.floor(14 * s))
        txt("The hold is empty.", StationFrame.BODY, 14 * s, C.DIM)
        Gui:endContainer()
    end
    local shown = args.maxRows or 9
    for i, row in ipairs(rows) do
        local quote = station and MarketSystem:quote(station, row.item.id)
        local price = quote and (quote.bid or quote.last) or 0
        value = value + price * row.units
        if i <= shown then
            Gui:beginStackContainer()
            Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
            Gui:setFixedHeight(rowH)
            Gui:setPadding(pad, 0)
            Gui:beginHorizontalContainer()
            Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
            Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
            Gui:setSpacing(math.floor(12 * s))
            badge(row.item, s, 30)
            Gui:beginVerticalContainer()
            local name = row.item.displayName
            if #name > 24 then name = name:sub(1, 23) .. "." end
            txt(name, StationFrame.BODY_SEMI, 14 * s, C.TEXT)
            txt(row.item.group or "", StationFrame.BODY, 11 * s, C.DIM)
            Gui:endContainer()
            Gui:endContainer()
            Gui:beginHorizontalContainer()
            Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
            Gui:setSpacing(math.floor(16 * s))
            txt(grouped(row.units), StationFrame.MONO, 14 * s, C.TEXT)
            Gui:beginStackContainer()
            Gui:setFixedWidth(math.floor(70 * s))
            txt(grouped((row.item.mass or 0) * row.units) .. " t", StationFrame.MONO, 13 * s, C.SUB)
            Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
            Gui:endContainer()
            Gui:endContainer()
            Gui:endContainer()
            rule(C.ROW_RULE)
        end
    end
    if #rows > shown then
        Gui:beginStackContainer()
        Gui:setPadding(pad, math.floor(8 * s))
        txt(string.format("... and %d more (Hangar tab)", #rows - shown), StationFrame.BODY, 13 * s, C.DIM)
        Gui:endContainer()
    end
    Gui:endContainer()

    -- Its worth here, and what the station makes
    rule()
    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Bottom)
    Gui:setPadding(pad, math.floor(12 * s))
    Gui:setSpacing(math.floor(6 * s))
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    txt("CARGO VALUE HERE", StationFrame.MONO, 13 * s, C.DIM)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    txt(grouped(value) .. " CR", StationFrame.MONO, 14 * s, C.CYAN)
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Center)
    Gui:endContainer()
    if args.makes then
        txt(args.makes, StationFrame.BODY, 12 * s, C.DIM)
    end
    Gui:endContainer()

    Gui:endContainer()
end

------------------------------------------------------------------------------

--- Draw the docked screen.
---@param s number the scale
---@param args table { title, chips = {{text, color}}, tabs = {{id, label}},
---   active, onTab(id), actions = {{label, enabled, callback}}, onUndock(),
---   body (a Station tab, :render()), station, makes (string|nil) }
function StationFrame.draw(s, args)
    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setBackgroundColor(C.BG)

    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    header(s, args)
    rule()
    tabStrip(s, args)
    rule()

    -- The tab and the ship, side by side
    local sideW = math.floor(400 * s)
    local gap = math.floor(24 * s)
    local padX, padY = math.floor(32 * s), math.floor(22 * s)
    local bodyW = Window:width() - sideW - gap - padX * 2
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setPadding(padX, padY)
    Gui:setSpacing(gap)

    Gui:beginVerticalContainer()
    Gui:setFixedWidth(bodyW)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Stretch)
    Gui:setBackgroundColor(C.PANEL)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(C.RULE)
    Gui:setPadding(math.floor(20 * s), math.floor(16 * s))
    if args.body then args.body:render() end
    Gui:endContainer()

    Gui:beginVerticalContainer()
    Gui:setFixedWidth(sideW)
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Stretch)
    activeShip(s, args)
    Gui:endContainer()

    Gui:endContainer()
    Gui:endContainer()
    Gui:endContainer()
end

return StationFrame
