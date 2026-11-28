-- Over the flight view once the ship is lost (LimitTheoryRedux.playerDead):
-- the screen fades down, though not out, so the camera can still be swung
-- round the wreck (right mouse) to see what happened; then
--
--               SHIP DESTROYED
--          Destroyed by Pirate Raider
--     [ LOAD LAST SAVE ]   [ MAIN MENU ]
--
-- The buttons come in once the fade is most of the way down.

local UIMouse = require("Input.UIMouse")

local DeathPanel = {}

local FADE_TIME = 3.0  -- seconds to fade down
local FADE_TO = 0.72   -- how dark it gets
local BUTTONS_AT = 2.0 -- seconds before the buttons show

local AMBER = Color(0.95, 0.66, 0.23, 1.0)
local AMBER_HI = Color(1.00, 0.82, 0.54, 1.0)
local INK = Color(0.04, 0.06, 0.08, 1.0)
local EDGE = Color(0.17, 0.23, 0.29, 1.0)
local SLATE = Color(0.11, 0.16, 0.21, 1.0)

local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

local function button(label, primary)
    Gui:beginStackContainer()
    Gui:setFixedSize(230, 50)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    if primary then
        Gui:setBackgroundColor(hover and AMBER_HI or AMBER)
    else
        Gui:setBackgroundColor(hover and SLATE or Color(0, 0, 0, 0.4))
        Gui:setBorderWidth(1)
        Gui:setBorderColor(hover and AMBER or EDGE)
    end
    Gui:text(label, Cache.Font("RajdhaniBold", 19), primary and INK or Color(0.85, 0.89, 0.93, 1))
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
    return hover and Input:mouse():isPressed(MouseControl.Left)
end

function DeathPanel.render()
    local game = LimitTheoryRedux
    local dead = game and game.playerDead
    if not dead or game.pauseMenuOpen or (game.mapMode or 0) ~= 0 then return end
    local t = dead.time or 0
    local fade = math.min(1, t / FADE_TIME)

    Gui:beginStackContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setBackgroundColor(Color(0, 0, 0, FADE_TO * fade))
    Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Center)

    Gui:beginVerticalContainer()
    Gui:setScale(hudScale())
    Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:setSpacing(10)
    Gui:text("SHIP DESTROYED", Cache.Font("RajdhaniBold", 64), Color(1.0, 0.42, 0.36, fade))
    if dead.killer then
        Gui:text("Destroyed by " .. dead.killer, Cache.Font("TitilliumWebSemiBold", 20), Color(0.85, 0.89, 0.93, fade))
    end
    Gui:text("Hold the right mouse button to look around", Cache.Font("TitilliumWeb", 15),
        Color(0.62, 0.68, 0.75, fade))
    local over = false
    if t >= BUTTONS_AT then
        Gui:beginStackContainer()
        Gui:setFixedHeight(18)
        Gui:endContainer()
        Gui:beginHorizontalContainer()
        Gui:setSpacing(16)
        over = Gui:isMouseOver(FocusType.Mouse)
        if dead.canLoad and button("LOAD LAST SAVE", true) then game:loadLastSave() end
        if button("MAIN MENU", not dead.canLoad) then game:returnToMainMenu() end
        Gui:endContainer()
    end
    Gui:endContainer()
    Gui:endContainer()

    -- The buttons have the mouse; anywhere else it turns the camera
    if over then UIMouse.claim() end
end

return DeathPanel
