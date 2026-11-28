-- Top left of the flight HUD: where you are and how the ship is.
--
--   WATAHUSATTE
--   SECURE SPACE
--   Patrolled; pirates keep to the belts.
--   SHIELD  [==========]  100 / 100
--   HULL    [=======   ]  280 / 400
--
-- The hull bar goes amber under half and red under a quarter. Hidden with
-- the HUD, on the maps, docked and in the pause menu.

local CoreComponents = require("Modules.Core.Components")
local ConstructComponents = require("Modules.Constructs.Components")

local StatusPanel = {}

local WHITE = Color(0.92, 0.95, 0.98, 1.0)
local DIM = Color(0.62, 0.68, 0.75, 1.0)
local BG = Color(0.03, 0.05, 0.08, 0.62)
local TROUGH = Color(0.04, 0.06, 0.09, 0.85)
local EDGE = Color(0.20, 0.28, 0.36, 0.9)
local SHIELD = Color(0.31, 0.82, 0.91, 1.0)
local HULL_OK = Color(0.36, 0.84, 0.54, 1.0)
local HULL_LOW = Color(0.95, 0.66, 0.23, 1.0)
local HULL_BAD = Color(1.00, 0.36, 0.30, 1.0)

local WIDTH = 340

local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

local function font(name, size)
    return Cache.Font(name, size)
end

--- Wrap a line of text by hand at about `chars` characters
local function wrap(text, chars)
    local lines, line = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
        if #line + #word + 1 > chars and #line > 0 then
            lines[#lines + 1] = line
            line = word
        else
            line = #line > 0 and (line .. " " .. word) or word
        end
    end
    if #line > 0 then lines[#lines + 1] = line end
    return lines
end

local function bar(label, cur, max, color)
    Gui:beginHorizontalContainer()
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setSpacing(8)
    Gui:beginStackContainer()
    Gui:setFixedWidth(56)
    Gui:text(label, font("TitilliumWebSemiBold", 12), DIM)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:endContainer()
    local frac = max > 0 and math.max(0, math.min(1, cur / max)) or 0
    Gui:beginStackContainer()
    Gui:setFixedSize(170, 12)
    Gui:setBackgroundColor(TROUGH)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(EDGE)
    if frac > 0 then
        Gui:beginStackContainer()
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Stretch)
        Gui:setPercentWidth(math.max(1, frac * 100))
        Gui:setBackgroundColor(color)
        Gui:endContainer()
    end
    Gui:endContainer()
    Gui:text(string.format("%d / %d", math.floor(cur + 0.5), math.floor(max + 0.5)),
        font("FiraMono", 12), frac < 0.25 and color or WHITE)
    Gui:endContainer()
end

function StatusPanel.render()
    local game = LimitTheoryRedux
    if not (game and game.playerShip and game.playerShip:isValid() and game.isTravelGame and game:isTravelGame())
        or game.docked or game.hudHidden or (game.mapMode or 0) ~= 0 or game.pauseMenuOpen then
        return
    end

    Gui:beginStackContainer()
    Gui:setScale(hudScale())
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Top)
    Gui:setPadding(24, 22)

    Gui:beginVerticalContainer()
    Gui:setFixedWidth(WIDTH)
    Gui:setPadding(14, 12)
    Gui:setSpacing(3)
    Gui:setBackgroundColor(BG)

    -- Where
    local system = game.galaxy and game.galaxy.systems and game.galaxy.systems[game.currentSystemId]
    local level = game.currentHostility and game:currentHostility()
    if system then
        Gui:text(system.name:upper(), font("RajdhaniBold", 24), WHITE)
    end
    if level then
        local c = level.color or { 1, 1, 1 }
        Gui:text(level.name:upper() .. " SPACE", font("RajdhaniBold", 15), Color(c[1], c[2], c[3], 1))
        for _, l in ipairs(wrap(level.description, 46)) do
            Gui:text(l, font("TitilliumWeb", 13), DIM)
        end
    end

    -- How the ship is
    local health = game.playerShip:get(CoreComponents.Health)
    local defense = game.playerShip:get(ConstructComponents.Defense)
    Gui:beginStackContainer()
    Gui:setFixedHeight(8)
    Gui:endContainer()
    if defense and defense:getMaxShield() > 0 then
        bar("SHIELD", defense:getCurrentShield(), defense:getMaxShield(), SHIELD)
    end
    if health and health:getMaxHealth() > 0 then
        local frac = health:getCurrentHealth() / health:getMaxHealth()
        bar("HULL", math.max(0, health:getCurrentHealth()), health:getMaxHealth(),
            frac < 0.25 and HULL_BAD or (frac < 0.5 and HULL_LOW or HULL_OK))
    end

    Gui:endContainer()
    Gui:endContainer()
end

return StatusPanel
