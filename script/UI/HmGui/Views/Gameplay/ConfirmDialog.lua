local UIMouse = require("Input.UIMouse")

-- A question in the middle of the screen with two answers: whatever the game
-- has put in LimitTheoryRedux.confirmation ({ title, lines, confirm,
-- cancel }), answered through LimitTheoryRedux:answerConfirmation. The first
-- is the warning before an attack turns a faction hostile
-- (LimitTheoryRedux:askHostilityConfirmation).
--
-- Drawn last in the in-game view (InGame.lua), over the overview. While it
-- is up the game frees the cursor and the mouse does not steer
-- (LimitTheoryRedux:updateOverview), and it is modal: it holds the mouse
-- wherever the cursor is (UIMouse.overPanel), and nothing under it takes a
-- click. It is not answered by keys: a stray Enter in a fight should not
-- start a war.

local ConfirmDialog = {}

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.80, 0.83, 0.87, 1.00)
local WARN = Color(1.00, 0.45, 0.35, 1.00)
local DIALOG_BG = Color(0.03, 0.05, 0.09, 0.97)
local DIALOG_BORDER = Color(1.00, 0.45, 0.35, 0.70)
local BUTTON_BG = Color(0.06, 0.09, 0.13, 1.00)
local BUTTON_HI = Color(0.10, 0.30, 0.50, 1.00)
local CONFIRM_HI = Color(0.55, 0.15, 0.10, 1.00)
local SCREEN_DIM = Color(0.00, 0.00, 0.00, 0.35)

local WIDTH = 520

---@return number
local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

---@param size number
---@param name string|nil
local function font(size, name)
    return Cache.Font(name or "Unageo-Medium", size)
end

--- A button; returns whether it was clicked this frame.
---@param label string
---@param highlight Color
---@return boolean
local function button(label, highlight)
    Gui:beginStackContainer()
    Gui:setFixedSize(200, 34)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(hover and highlight or BUTTON_BG)
    Gui:text(label, font(16), WHITE)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
    return hover and Input:mouse():isPressed(MouseControl.Left)
end

function ConfirmDialog.render()
    local game = LimitTheoryRedux
    if not (game and game.confirmationShowing and game:confirmationShowing()) then return end
    local question = game.confirmation

    local s = hudScale()
    local answer = nil

    -- Its own layer, so it sits over the HUD and the overview alike. The
    -- screen-filling container under it asks for the mouse too, so a click
    -- anywhere but its buttons lands on nothing: the overview's rows, the
    -- cameras and the fire button all wait for the answer.
    Gui:beginLayer()
    Gui:beginStackContainer()
    Gui:setScale(s)
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(SCREEN_DIM)

    Gui:beginVerticalContainer()
    Gui:setFixedWidth(WIDTH)
    Gui:setBackgroundColor(DIALOG_BG)
    Gui:setBorderWidth(2)
    Gui:setBorderColor(DIALOG_BORDER)
    Gui:setPadding(20, 16)
    Gui:setSpacing(6)
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Top)

    Gui:text(question.title or "Are you sure?", font(22, "Unageo-Semibold"), WARN)
    for _, line in ipairs(question.lines or {}) do
        Gui:text(line, font(14), GREY)
    end

    Gui:beginHorizontalContainer()
    Gui:setSpacing(16)
    Gui:setMarginTop(10)
    if button(question.cancel or "Cancel", BUTTON_HI) then answer = false end
    if button(question.confirm or "Confirm", CONFIRM_HI) then answer = true end
    Gui:endContainer()

    Gui:endContainer()
    Gui:endContainer()
    Gui:endLayer()

    -- Modal: the mouse is the dialog's wherever it is
    UIMouse.claim()

    if answer ~= nil then game:answerConfirmation(answer) end
end

return ConfirmDialog
