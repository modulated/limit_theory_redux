---@type UIView
local SaveSlots = UICore.View {
    name = "SaveSlots"
}

local SaveGame = require("Shared.Save.SaveGame")

-- The pause menu's Save Game and Load Game: the slots, what is in each, and
-- a button for each. LimitTheoryRedux.saveSlotsMode says which
-- (LimitTheoryRedux:openSaveSlots).
--
-- Saving over a slot that holds a game takes a second click within a few
-- seconds; the slot's previous save is kept as its backup regardless
-- (SaveFile). The autosave is written on docking and cannot be chosen here;
-- the quicksave can (it is what F4 writes and Ctrl+F4 reads).

function SaveSlots:onInput() end
function SaveSlots:onUpdate(dt) end
function SaveSlots:onViewOpen(isPageOpen) SaveGame.invalidate() end

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.75, 0.77, 0.80, 1.00)
local DIM = Color(0.51, 0.54, 0.59, 1.00)
local ACCENT = Color(0.10, 0.60, 1.00, 1.00)
local WARN = Color(1.00, 0.55, 0.35, 1.00)
local SCREEN_BG = Color(0.00, 0.00, 0.00, 0.75)
local ROW_BG = Color(0.06, 0.09, 0.13, 0.95)
local ROW_HOVER = Color(0.10, 0.30, 0.50, 1.00)
local ROW_ARMED = Color(0.45, 0.20, 0.08, 1.00)

local WIDTH = 760
local ARM_SECONDS = 3

--- A slot armed for overwriting: { slot, until } (seconds on the clock).
local armed = nil
local clock
local function now()
    clock = clock or TimeStamp.Now()
    return clock:getElapsed()
end

---@return number
local function scale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

local function font(size, name)
    return Cache.Font(name or "Unageo-Medium", size)
end

--- One slot's row; returns whether it was clicked.
---@param row table SaveGame.list row
---@param enabled boolean
---@param isArmed boolean
---@return boolean
local function slotRow(row, enabled, isArmed)
    Gui:beginVerticalContainer()
    Gui:setFixedWidth(WIDTH)
    Gui:setPadding(14, 8)
    local hover = enabled and Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor((isArmed and ROW_ARMED) or (hover and ROW_HOVER) or ROW_BG)
    Gui:text(row.name, font(18, "Unageo-Semibold"), enabled and WHITE or DIM)
    local line
    if isArmed then
        line = "Click again to save over this game"
    elseif row.problem then
        line = "Unreadable: " .. row.problem
    else
        line = SaveGame.describe(row.meta)
    end
    Gui:text(line, font(14), (isArmed or row.problem) and WARN or (row.meta and GREY or DIM))
    Gui:endContainer()
    return hover and Input:mouse():isPressed(MouseControl.Left)
end

--- A plain button; returns whether it was clicked.
local function button(label)
    Gui:beginStackContainer()
    Gui:setFixedSize(220, 40)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(hover and ROW_HOVER or ROW_BG)
    Gui:text(label, font(18), WHITE)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()
    return hover and Input:mouse():isPressed(MouseControl.Left)
end

SaveSlots:addContent({
    state = {},
    render = function()
        local game = LimitTheoryRedux
        local saving = game.saveSlotsMode == "save"
        if armed and now() > armed.untilTime then armed = nil end

        Gui:beginStackContainer()
        Gui:setScale(scale())
        Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
        Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Center)
        Gui:setBackgroundColor(SCREEN_BG)

        Gui:beginVerticalContainer()
        Gui:setSpacing(6)
        Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Top)
        Gui:text(saving and "SAVE GAME" or "LOAD GAME", font(30, "Unageo-Semibold"), ACCENT)
        Gui:text(saving and "Choose a slot. The autosave is written each time you dock."
            or "Choose a game to load. The game in progress will end.", font(14), DIM)

        local clicked = nil
        for _, row in ipairs(SaveGame.listCached()) do
            local offered = (not saving) or row.slot ~= "autosave"
            if offered then
                local enabled = saving or row.meta ~= nil
                local isArmed = armed ~= nil and armed.slot == row.slot
                if slotRow(row, enabled, isArmed) then clicked = row end
            end
        end
        if SaveGame.lastProblem and not saving then
            Gui:text("Could not load " .. SaveGame.lastProblem, font(14), WARN)
        end

        Gui:setSpacing(6)
        local back = button("Back")
        Gui:endContainer()
        Gui:endContainer()

        if back then
            armed = nil
            game:closeSaveSlots()
            return
        end
        if not clicked then return end
        if saving then
            -- Over a saved game: a second click within a few seconds
            if clicked.meta and not (armed and armed.slot == clicked.slot) then
                armed = { slot = clicked.slot, untilTime = now() + ARM_SECONDS }
                return
            end
            armed = nil
            if game:saveGame(clicked.slot) then
                game:closeSaveSlots()
                game:closePauseMenu()
            end
        else
            game:loadGame(clicked.slot)
        end
    end
})

return SaveSlots
