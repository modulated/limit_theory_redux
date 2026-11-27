---@type UIView
local Paused = UICore.View {
    name = "Paused"
}

---@type ResponsiveSize
local ResponsiveSize = require("Types.ResponsiveSize")

-- NOTE: Escape handling is owned by LimitTheoryRedux:onInput (single
-- toggle point); the Paused view only provides the buttons. Pausing and the
-- cursor are owned by LimitTheoryRedux too (open/closePauseMenu), so
-- switching to the Controls, Options or save screens and back doesn't
-- unpause the game.
--
-- The menu answers the keyboard as well as the mouse: Up and Down move the
-- focus (lit like a hovered button), Enter chooses it.

local ENTRIES = {
    { title = "Return to Game", run = function() LimitTheoryRedux:closePauseMenu() end },
    { title = "Save Game", run = function() LimitTheoryRedux:openSaveSlots("save") end },
    { title = "Load Game", run = function() LimitTheoryRedux:openSaveSlots("load") end },
    { title = "Options", run = function() LimitTheoryRedux:openSettings() end },
    { title = "Controls", run = function() LimitTheoryRedux:openControls() end },
    { title = "Back to Main Menu", run = function() LimitTheoryRedux:returnToMainMenu() end },
    -- Run the pre-exit operations, then exit
    { title = "Exit", run = function() LimitTheoryRedux:exit() end },
}

--- The entry the keyboard is on.
Paused.focus = 1

function Paused:onInput()
    if Input:isPressed(Button.KeyboardDown) then
        Paused.focus = Paused.focus % #ENTRIES + 1
    elseif Input:isPressed(Button.KeyboardUp) then
        Paused.focus = (Paused.focus - 2) % #ENTRIES + 1
    elseif (Input:isPressed(Button.KeyboardEnter) or Input:isPressed(Button.KeyboardNumpadEnter))
        and not (Input:isDown(Button.KeyboardAltLeft) or Input:isDown(Button.KeyboardAltRight)) then
        local entry = ENTRIES[Paused.focus]
        if entry then entry.run() end
    end
end

function Paused:onUpdate(dt) end

--- The menu opens on its first entry.
function Paused:onViewOpen(isPageOpen)
    Paused.focus = 1
end

local buttons = {}
for index, entry in ipairs(ENTRIES) do
    buttons[#buttons + 1] = UIComponent.Button_MainMenu {
        title = entry.title,
        size = ResponsiveSize(200, 40, true),
        font = { name = "Unageo-Medium", size = 20 },
        align = { AlignHorizontal.Center, AlignVertical.Center },
        focused = function() return Paused.focus == index end,
        callback = function()
            Paused.focus = index
            entry.run()
        end,
    }
end

local menuContainer = UIComponent.Container {
    align = { AlignHorizontal.Stretch, AlignVertical.Stretch },
    childrenAlign = { AlignHorizontal.Center, AlignVertical.Center },
    padding = { 0, 0 },
    layoutType = GuiLayoutType.Vertical,
    color = {
        background = Color(0, 0, 0, 0.75)
    },
    contents = buttons,
}

Paused:addContent(menuContainer)

return Paused
