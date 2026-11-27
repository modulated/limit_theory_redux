local UIMouse = require("Input.UIMouse")
local PlayerCargo = require("Modules.Economy.Managers.PlayerCargo")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local PlayerStations = require("Modules.Economy.Managers.PlayerStations")
local PlayerForces = require("Modules.Economy.Managers.PlayerForces")
local PlayerFleet = require("Modules.Constructs.Managers.PlayerFleet")
local Reputation = require("Modules.NPC.Reputation")
local Factions = require("Modules.NPC.Factions")
local Fittings = require("Shared.Registries.Fittings")
local CoreComponents = require("Modules.Core.Components")
local ConstructComponents = require("Modules.Constructs.Components")

-- The in-flight windows, opened and closed by key (LimitTheoryRedux:toggleWindow):
--
--   Inventory (I)  what is in the hold, its mass and worth, and the credits
--   Character (U)  the pilot's ship, its fit and state, and what they own
--   Standings (Y)  each faction's view of the player, and what it means
--
-- They stand side by side on the left of the screen. While one is open the
-- cursor is free and the mouse does not steer; each has a close button.

local WindowsPanel = {}

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.78, 0.80, 0.84, 1.00)
local DIM = Color(0.50, 0.53, 0.58, 1.00)
local ACCENT = Color(0.10, 0.60, 1.00, 1.00)
local GOLD = Color(1.00, 0.85, 0.35, 1.00)
local GOOD = Color(0.40, 1.00, 0.60, 1.00)
local BAD = Color(1.00, 0.40, 0.32, 1.00)
local PANEL_BG = Color(0.02, 0.04, 0.07, 0.88)
local PANEL_BORDER = Color(0.10, 0.60, 1.00, 0.40)
local RULE = Color(0.10, 0.60, 1.00, 0.20)
local CLOSE_HOVER = Color(0.55, 0.15, 0.10, 1.00)
local BAR_BG = Color(1.00, 1.00, 1.00, 0.08)
local NO_COLOR = Color(0, 0, 0, 0)

local WIDTH = 400

---@return number
local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

local function font(size, name)
    return Cache.Font(name or "Unageo-Medium", size)
end

local function cell(value, width, color, size, align)
    Gui:beginStackContainer()
    Gui:setFixedWidth(width)
    Gui:setChildrenAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:text(value, font(size or 13), color or GREY)
    Gui:setAlignment(align or AlignHorizontal.Left, AlignVertical.Center)
    Gui:endContainer()
end

local function rule()
    Gui:beginStackContainer()
    Gui:setFixedSize(WIDTH - 20, 1)
    Gui:setBackgroundColor(RULE)
    Gui:endContainer()
end

--- A bar `fraction` full, in `color`.
local function bar(fraction, color, width)
    width = width or (WIDTH - 20)
    Gui:beginStackContainer()
    Gui:setFixedSize(width, 6)
    Gui:setBackgroundColor(BAR_BG)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:beginStackContainer()
    Gui:setFixedSize(math.max(0, math.floor(width * math.max(0, math.min(1, fraction)))), 6)
    Gui:setBackgroundColor(color)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:endContainer()
    Gui:endContainer()
end

local function thousands(n)
    local s = tostring(math.floor(n + 0.5))
    local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (out:gsub("^,", ""))
end

--- A window's frame: its title and a close button. Calls `body` for the
--- rest; returns whether its close button was clicked.
local function window(title, key, body)
    local closed = false
    Gui:beginVerticalContainer()
    Gui:setFixedWidth(WIDTH)
    Gui:setBackgroundColor(PANEL_BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(PANEL_BORDER)
    Gui:setPadding(10, 8)
    Gui:setSpacing(4)

    Gui:beginHorizontalContainer()
    cell(title, WIDTH - 20 - 70, ACCENT, 16, AlignHorizontal.Left)
    cell(key, 40, DIM, 11, AlignHorizontal.Right)
    Gui:beginStackContainer()
    Gui:setFixedSize(30, 22)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(hover and CLOSE_HOVER or NO_COLOR)
    Gui:text("X", font(13), WHITE)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
    if hover and Input:mouse():isPressed(MouseControl.Left) then closed = true end
    Gui:endContainer()
    rule()
    body()
    Gui:endContainer()
    return closed
end

------------------------------------------------------------------------------
-- Inventory
------------------------------------------------------------------------------

local function inventory()
    local used, capacity = PlayerCargo:getLoad()
    local rows = PlayerCargo:list()
    local worth = 0
    for _, row in ipairs(rows) do worth = worth + (row.item.startEquilibriumPrice or 0) * row.units end

    Gui:beginHorizontalContainer()
    cell("Credits", 120, GREY, 14)
    cell(PlayerWallet.format(PlayerWallet:get()), WIDTH - 20 - 120, GOLD, 16, AlignHorizontal.Right)
    Gui:endContainer()
    Gui:beginHorizontalContainer()
    cell("Cargo hold", 120, GREY, 13)
    cell(string.format("%s / %s t", thousands(used), thousands(capacity)), WIDTH - 20 - 120, WHITE, 13,
        AlignHorizontal.Right)
    Gui:endContainer()
    local fraction = capacity > 0 and used / capacity or 0
    bar(fraction, fraction > 0.9 and BAD or ACCENT)
    rule()

    Gui:beginHorizontalContainer()
    cell("Item", 190, DIM, 11)
    cell("Units", 60, DIM, 11, AlignHorizontal.Right)
    cell("Mass", 60, DIM, 11, AlignHorizontal.Right)
    cell("Worth", WIDTH - 20 - 310, DIM, 11, AlignHorizontal.Right)
    Gui:endContainer()
    if #rows == 0 then
        cell("The hold is empty.", WIDTH - 20, DIM, 13)
    end
    for _, row in ipairs(rows) do
        Gui:beginHorizontalContainer()
        local name = row.item.displayName
        if #name > 26 then name = name:sub(1, 24) .. ".." end
        cell(name, 190, WHITE, 13)
        cell(thousands(row.units), 60, GREY, 13, AlignHorizontal.Right)
        cell(thousands(row.item.mass * row.units) .. " t", 60, GREY, 13, AlignHorizontal.Right)
        cell(thousands((row.item.startEquilibriumPrice or 0) * row.units), WIDTH - 20 - 310, GREY, 13,
            AlignHorizontal.Right)
        Gui:endContainer()
    end
    rule()
    cell(string.format("Worth about %s at base prices. Sold and moved at a station.",
        PlayerWallet.format(worth)), WIDTH - 20, DIM, 11)
end

------------------------------------------------------------------------------
-- Character
------------------------------------------------------------------------------

local function character(game)
    local ship = PlayerFleet:active()
    local hull = ship and PlayerFleet.hullOf(ship)
    local entity = game.playerShip
    local health = entity and entity:isValid() and entity:get(CoreComponents.Health)
    local defense = entity and entity:isValid() and entity:get(ConstructComponents.Defense)
    local loadout = entity and entity:isValid() and entity:get(ConstructComponents.Loadout)

    cell("SHIP", WIDTH - 20, DIM, 11)
    cell(ship and ship.name or "No ship", WIDTH - 20, WHITE, 15)
    if hull then cell(hull.displayName, WIDTH - 20, GREY, 12) end
    if health then
        local f = health:getCurrentHealth() / math.max(1, health:getMaxHealth())
        Gui:beginHorizontalContainer()
        cell("Hull", 80, GREY, 12)
        cell(string.format("%d / %d", math.floor(health:getCurrentHealth()), math.floor(health:getMaxHealth())),
            WIDTH - 20 - 80, WHITE, 12, AlignHorizontal.Right)
        Gui:endContainer()
        bar(f, f < 0.35 and BAD or GOOD)
    end
    if defense and defense:getMaxShield() > 0 then
        local f = defense:getCurrentShield() / math.max(1, defense:getMaxShield())
        Gui:beginHorizontalContainer()
        cell("Shields", 80, GREY, 12)
        cell(string.format("%d / %d", math.floor(defense:getCurrentShield()), math.floor(defense:getMaxShield())),
            WIDTH - 20 - 80, WHITE, 12, AlignHorizontal.Right)
        Gui:endContainer()
        bar(f, ACCENT)
    end

    rule()
    cell("FIT", WIDTH - 20, DIM, 11)
    local any = false
    if loadout then
        local mounts = {}
        for id in pairs(loadout.weapons or {}) do mounts[#mounts + 1] = id end
        table.sort(mounts)
        for _, id in ipairs(mounts) do
            local def = loadout:getWeapon(id)
            if def then
                any = true
                cell(string.format("Mount  ·  %s", def.displayName), WIDTH - 20, WHITE, 12)
            end
        end
        for slot = 1, loadout:getModuleSlots() do
            local def = loadout:getModule(slot)
            if def then
                any = true
                cell(string.format("Slot %d  ·  %s", slot, def.displayName), WIDTH - 20, WHITE, 12)
            end
        end
    end
    if not any then cell("Nothing fitted.", WIDTH - 20, DIM, 12) end

    rule()
    cell("HOLDINGS", WIDTH - 20, DIM, 11)
    local function line(label, value, color)
        Gui:beginHorizontalContainer()
        cell(label, 200, GREY, 12)
        cell(value, WIDTH - 20 - 200, color or WHITE, 12, AlignHorizontal.Right)
        Gui:endContainer()
    end
    line("Credits", PlayerWallet.format(PlayerWallet:get()), GOLD)
    line("Ships", tostring(#PlayerFleet:all()))
    line("Outposts", tostring(#PlayerStations:all()))
    local drones, mercs = 0, 0
    for _, unit in pairs(PlayerForces.units) do
        if unit.kind == PlayerForces.Kind.Drone then drones = drones + 1 else mercs = mercs + 1 end
    end
    line("Drones / mercenaries", string.format("%d / %d", drones, mercs))
    if mercs > 0 then line("Wages", PlayerWallet.format(PlayerForces:wageBill()) .. " an hour", BAD) end
    local t = game.simTime or 0
    line("Time in this game", string.format("%dh %02dm", math.floor(t / 3600), math.floor(t % 3600 / 60)), GREY)
end

------------------------------------------------------------------------------
-- Standings
------------------------------------------------------------------------------

local WHAT_IT_MEANS = {
    hostile = "Their ships attack you on sight; their stations refuse you.",
    neutral = "They leave you be. Bounties on their enemies raise your standing.",
    friendly = "Welcome at their stations; their ships will not turn on you lightly.",
}

local function standings()
    local cfg = Config.game
    for _, faction in ipairs({ Factions.Security, Factions.Trader, Factions.Pirate }) do
        local r, g, b = Factions.color(faction)
        local value = Reputation:get(faction)
        local state = Reputation:describe(faction)
        Gui:beginHorizontalContainer()
        cell(Factions.name(faction), 160, Color(r, g, b, 1), 15)
        cell(string.format("%+.2f  ·  %s", value, state), WIDTH - 20 - 160,
            state == "hostile" and BAD or (state == "friendly" and GOOD or GREY), 13, AlignHorizontal.Right)
        Gui:endContainer()
        -- Where the standing sits between the worst and the best, with the
        -- thresholds as the bar's colour change
        local f = (value - cfg.dispoMin) / math.max(1e-6, cfg.dispoMax - cfg.dispoMin)
        bar(f, state == "hostile" and BAD or (state == "friendly" and GOOD or ACCENT))
        cell(WHAT_IT_MEANS[state] or "", WIDTH - 20, DIM, 11)
        rule()
    end
    cell(string.format("Hostile below %+.2f, friendly from %+.2f. Shooting a faction's ships costs",
        cfg.dispoHostileThreshold, cfg.dispoFriendlyThreshold), WIDTH - 20, DIM, 11)
    cell("standing with it; killing its enemies earns standing with it.", WIDTH - 20, DIM, 11)
end

------------------------------------------------------------------------------

local ORDER = {
    { id = "inventory", title = "INVENTORY", key = "I", body = function() inventory() end },
    { id = "character", title = "CHARACTER", key = "U", body = function(game) character(game) end },
    { id = "standings", title = "STANDINGS", key = "Y", body = function() standings() end },
}

function WindowsPanel.render()
    local game = LimitTheoryRedux
    if not (game and game.windowsShowing and game:windowsShowing()) then return end
    local s = hudScale()

    Gui:beginStackContainer()
    Gui:setScale(s)
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Top)
    Gui:setPadding(20, math.floor(Window:height() * 0.14 / s))
    Gui:beginHorizontalContainer()
    local over = Gui:isMouseOver(FocusType.Scroll)
    Gui:setSpacing(10)
    local close = nil
    for _, w in ipairs(ORDER) do
        if game.windows[w.id] then
            if window(w.title, w.key, function() w.body(game) end) then close = w.id end
        end
    end
    Gui:endContainer()
    Gui:endContainer()

    if over then UIMouse.claim() end
    if close then game:toggleWindow(close) end
end

return WindowsPanel
