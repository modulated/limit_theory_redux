local UIMouse = require("Input.UIMouse")
local Hulls = require("Shared.Registries.Hulls")
local Items = require("Shared.Registries.Items")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local PlayerFleet = require("Modules.Constructs.Managers.PlayerFleet")

-- The debug menu (~): for testing, not for play. Three tabs:
--   Ship   fly any hull (a new, empty ship of it), arm every mount, repair,
--          god mode, credits
--   Items  any item, 1 / 10 / 100 at a time, into the hold (or the hangar
--          when docked), page by page, group by group
--   World  reveal ships, spawn an NPC of any role beside you, jump straight
--          to any system
-- Drawn over the flight view and the station screen alike; the game's own
-- (LimitTheoryRedux:debug*) does the work.

local DebugMenu = {
    tab = "ship",
    group = nil,
    page = 1,
}

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.78, 0.80, 0.84, 1.00)
local DIM = Color(0.50, 0.53, 0.58, 1.00)
local ACCENT = Color(1.00, 0.55, 0.20, 1.00)
local GOLD = Color(1.00, 0.85, 0.35, 1.00)
local PANEL_BG = Color(0.03, 0.02, 0.01, 0.94)
local PANEL_BORDER = Color(1.00, 0.55, 0.20, 0.55)
local BUTTON_BG = Color(0.12, 0.08, 0.04, 1.00)
local BUTTON_HI = Color(0.45, 0.25, 0.08, 1.00)
local BUTTON_ON = Color(0.30, 0.18, 0.06, 1.00)
local NO_COLOR = Color(0, 0, 0, 0)

local WIDTH = 560
local PAGE = 14

local function font(size)
    return Cache.Font("Unageo-Medium", size)
end

local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

local function label(value, width, color, size, align)
    Gui:beginStackContainer()
    Gui:setFixedWidth(width)
    Gui:setChildrenAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:text(value, font(size or 13), color or GREY)
    Gui:setAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:endContainer()
end

--- A button; returns whether it was clicked.
local function button(text, width, on)
    Gui:beginStackContainer()
    Gui:setFixedSize(width, 24)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(hover and BUTTON_HI or (on and BUTTON_ON or BUTTON_BG))
    Gui:text(text, font(12), WHITE)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
    return hover and Input:mouse():isPressed(MouseControl.Left)
end

local function row(fn)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(4)
    fn()
    Gui:endContainer()
end

------------------------------------------------------------------------------

local function shipTab(game)
    local ship = PlayerFleet:active()
    local hull = PlayerFleet.hullOf(ship)
    label(string.format("Flying: %s (%s)", ship and ship.name or "-", hull and hull.displayName or "-"),
        WIDTH - 20, WHITE, 14)
    label("FLY A HULL (a new empty ship of it, where you are)", WIDTH - 20, DIM, 11)
    local hulls = Hulls:getAll()
    for i = 1, #hulls, 3 do
        row(function()
            for j = i, math.min(i + 2, #hulls) do
                local h = hulls[j]
                if button(string.format("[%s] %s", h.class or "?", h.displayName), 176,
                        hull and hull.id == h.id) then
                    game:debugFlyHull(h)
                end
            end
        end)
    end
    label("THE SHIP", WIDTH - 20, DIM, 11)
    row(function()
        if button("Arm every mount", 176) then game:debugArmShip() end
        if button("Repair & recharge", 176) then game:debugRepair() end
        if button(game.debugGod and "God mode: ON" or "God mode: off", 176, game.debugGod) then
            game.debugGod = not game.debugGod
        end
    end)
    label(string.format("CREDITS   %s", PlayerWallet.format(PlayerWallet:get())), WIDTH - 20, GOLD, 13)
    row(function()
        for _, n in ipairs({ 10000, 100000, 1000000, 10000000 }) do
            if button("+" .. PlayerWallet.format(n), 132) then game:debugGiveCredits(n) end
        end
    end)
end

--- The item groups, in item order, and each group's items.
local groupsCache = nil
local function groups()
    if groupsCache then return groupsCache end
    local byGroup, order = {}, {}
    for _, def in pairs(Items.byName) do
        if def.group and def.group ~= "Virtual" then
            if not byGroup[def.group] then
                byGroup[def.group] = {}
                order[#order + 1] = def.group
            end
            table.insert(byGroup[def.group], def)
        end
    end
    for _, list in pairs(byGroup) do table.sort(list, function(a, b) return a.id < b.id end) end
    table.sort(order, function(a, b) return byGroup[a][1].id < byGroup[b][1].id end)
    groupsCache = { order = order, byGroup = byGroup }
    return groupsCache
end

local function itemsTab(game)
    local g = groups()
    DebugMenu.group = DebugMenu.group or g.order[1]
    label(game.docked and "Into the station hangar (docked)" or "Into the ship's hold (room or not)",
        WIDTH - 20, DIM, 11)
    for i = 1, #g.order, 4 do
        row(function()
            for j = i, math.min(i + 3, #g.order) do
                local name = g.order[j]
                if button(name, 132, DebugMenu.group == name) then
                    DebugMenu.group, DebugMenu.page = name, 1
                end
            end
        end)
    end
    local list = g.byGroup[DebugMenu.group] or {}
    local pages = math.max(1, math.ceil(#list / PAGE))
    DebugMenu.page = math.max(1, math.min(DebugMenu.page, pages))
    for i = (DebugMenu.page - 1) * PAGE + 1, math.min(#list, DebugMenu.page * PAGE) do
        local def = list[i]
        row(function()
            label(def.displayName, 330, GREY, 12)
            for _, n in ipairs({ 1, 10, 100 }) do
                if button("+" .. n, 60) then game:debugGiveItem(def, n) end
            end
        end)
    end
    row(function()
        if button("< Prev", 90) then DebugMenu.page = math.max(1, DebugMenu.page - 1) end
        label(string.format("page %d of %d", DebugMenu.page, pages), 140, DIM, 12, AlignHorizontal.Center)
        if button("Next >", 90) then DebugMenu.page = math.min(pages, DebugMenu.page + 1) end
    end)
end

local function worldTab(game)
    local reveal = Config.game.debug and Config.game.debug.revealShips
    row(function()
        if button(reveal and "Reveal ships: ON" or "Reveal ships: off", 176, reveal) then
            Config.game.debug.revealShips = not reveal
        end
    end)
    label("SPAWN BESIDE YOU", WIDTH - 20, DIM, 11)
    local roles = {}
    for role in pairs(Config.game.npc.roles or {}) do roles[#roles + 1] = role end
    table.sort(roles)
    for i = 1, #roles, 4 do
        row(function()
            for j = i, math.min(i + 3, #roles) do
                if button(roles[j], 132) then game:debugSpawn(roles[j]) end
            end
        end)
    end
    label("JUMP STRAIGHT TO (no gate, no fuel)", WIDTH - 20, DIM, 11)
    local systems = game.galaxy and game.galaxy.systems or {}
    for i = 1, #systems, 3 do
        row(function()
            for j = i, math.min(i + 2, #systems) do
                local system = systems[j]
                if button(system.name, 176, system.id == game.currentSystemId) then
                    game:debugJump(system.id)
                end
            end
        end)
    end
end

local TABS = {
    { id = "ship", title = "Ship", body = shipTab },
    { id = "items", title = "Items", body = itemsTab },
    { id = "world", title = "World", body = worldTab },
}

function DebugMenu.render()
    local game = LimitTheoryRedux
    if not (game and game.debugMenuOpen and game.playerShip) or game.pauseMenuOpen then return end
    local s = hudScale()

    Gui:beginStackContainer()
    Gui:setScale(s)
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Right, AlignVertical.Top)
    Gui:setPadding(20, 60)

    Gui:beginVerticalContainer()
    local over = Gui:isMouseOver(FocusType.Scroll)
    Gui:setFixedWidth(WIDTH)
    Gui:setBackgroundColor(PANEL_BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(PANEL_BORDER)
    Gui:setPadding(10, 8)
    Gui:setSpacing(5)

    row(function()
        label("DEBUG", 90, ACCENT, 16)
        for _, t in ipairs(TABS) do
            if button(t.title, 110, DebugMenu.tab == t.id) then DebugMenu.tab = t.id end
        end
        label("~ closes", 110, DIM, 11, AlignHorizontal.Right)
    end)
    for _, t in ipairs(TABS) do
        if t.id == DebugMenu.tab then t.body(game) end
    end
    Gui:endContainer()
    Gui:endContainer()

    if over then UIMouse.claim() end
end

return DebugMenu
