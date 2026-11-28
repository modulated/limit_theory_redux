local UIMouse = require("Input.UIMouse")

-- The action bar, bottom centre: the number keys 1..8 and what is on each
-- (LimitTheoryRedux:actionSlot). A slot shows its key, what is in it, and
-- what it is doing: a module's cooldown and burn, the mining laser's cycle,
-- as a bar filling from the bottom and the seconds left.
--
-- With the cursor free (the overview open, a window up), a slot can be
-- clicked to use it, or dragged onto another slot to swap the two (onto an
-- empty slot, it moves there). The arrangement is the ship's own.

local ActionBarPanel = {}

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.78, 0.80, 0.84, 1.00)
local DIM = Color(0.45, 0.48, 0.53, 1.00)
local KEY = Color(0.55, 0.75, 1.00, 1.00)
local SLOT_BG = Color(0.02, 0.04, 0.07, 0.80)
local SLOT_EMPTY = Color(0.02, 0.04, 0.07, 0.45)
local SLOT_BORDER = Color(0.10, 0.60, 1.00, 0.35)
local SLOT_ACTIVE = Color(0.30, 1.00, 0.55, 0.85)
local SLOT_HOVER = Color(0.10, 0.60, 1.00, 0.80)
local FILL_CYCLE = Color(0.30, 1.00, 0.55, 0.28)
local FILL_COOL = Color(0.60, 0.62, 0.66, 0.25)
local GHOST_BG = Color(0.10, 0.30, 0.50, 0.85)
local NO_COLOR = Color(0, 0, 0, 0)

local SIZE = 64      -- a slot, HUD pixels at 1080p
local GAP = 6
local DRAG_START = 6 -- pixels the cursor moves before a press is a drag

---@return number
local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

---@param size number
local function font(size)
    return Cache.Font("Unageo-Medium", size)
end

--- The press being followed: { slot, x, y, dragging }.
local press = nil

---@param name string
---@return string, string the name over two lines, each short enough to fit
local function twoLines(name)
    if #name <= 10 then return name, "" end
    local cut = name:sub(1, 11):match("^.*() ") or 11
    local first = name:sub(1, cut - 1)
    local second = name:sub(cut):gsub("^%s+", "")
    if #second > 10 then second = second:sub(1, 9) .. "." end
    return first, second
end

--- One slot. Returns whether the cursor is over it.
---@param index integer
---@param info table|nil
---@param highlight boolean being dragged over
---@return boolean
local function drawSlot(index, info, highlight)
    Gui:beginStackContainer()
    Gui:setFixedSize(SIZE, SIZE)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(info and SLOT_BG or SLOT_EMPTY)
    Gui:setBorderWidth(info and info.active and 2 or 1)
    Gui:setBorderColor((highlight or (hover and press)) and SLOT_HOVER
        or (info and info.active and SLOT_ACTIVE or SLOT_BORDER))

    -- What it is doing, as a bar filling from the bottom
    if info and info.progress and info.progress > 0 then
        Gui:beginStackContainer()
        Gui:setFixedSize(SIZE - 2, math.max(1, math.floor((SIZE - 2) * info.progress)))
        Gui:setBackgroundColor(info.kind == "tool" and FILL_CYCLE or FILL_COOL)
        Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Bottom)
        Gui:endContainer()
    end

    -- The key, top left
    Gui:text(tostring(index), font(12), KEY)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Top)
    Gui:setMargin(4, 2)

    if info then
        local a, b = twoLines(info.name)
        Gui:beginVerticalContainer()
        Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
        Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Center)
        Gui:text(a, font(11), info.ready and WHITE or GREY)
        if b ~= "" then Gui:text(b, font(11), info.ready and WHITE or GREY) end
        Gui:endContainer()
        -- Seconds left (a cycle, a burn or a cooldown), bottom right
        if info.remaining and info.remaining > 0.05 then
            Gui:text(string.format("%.0fs", math.ceil(info.remaining)), font(11),
                info.active and SLOT_ACTIVE or DIM)
            Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Bottom)
            Gui:setMargin(4, 2)
        end
    end
    Gui:endContainer()
    return hover
end

function ActionBarPanel.render()
    local game = LimitTheoryRedux
    if not (game and game.playerShip and game.isTravelGame and game:isTravelGame())
        or game.docked or game.hudHidden or (game.mapMode or 0) ~= 0 or game.pauseMenuOpen then
        press = nil
        return
    end
    local n = require("Modules.Constructs.Managers.ActionBar").slots()
    local slots = {}
    for i = 1, n do slots[i] = game:actionSlot(i) end

    local s = hudScale()
    local mouse = Input:mouse()
    local hovered = nil
    local over = false

    Gui:beginStackContainer()
    Gui:setScale(s)
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Bottom)
    Gui:setPadding(0, 26)

    Gui:beginHorizontalContainer()
    over = Gui:isMouseOver(FocusType.Scroll)
    Gui:setSpacing(GAP)
    Gui:setBackgroundColor(NO_COLOR)
    for i = 1, n do
        -- The slot a drag would land on is lit (last frame's hover)
        local target = press and press.dragging and press.over == i and press.slot ~= i
        if drawSlot(i, slots[i], target) then hovered = i end
    end
    Gui:endContainer()
    Gui:endContainer()

    -- The slot being dragged, under the cursor
    if press and press.dragging and slots[press.slot] then
        local pos = mouse:position()
        Gui:beginLayerAtPos(Vec2f(pos.x + 10, pos.y + 10))
        Gui:beginStackContainer()
        Gui:setScale(s)
        Gui:setPadding(6, 4)
        Gui:setBackgroundColor(GHOST_BG)
        Gui:text(slots[press.slot].name, font(12), WHITE)
        Gui:endContainer()
        Gui:endLayer()
    end

    -- Clicks and drags
    if hovered and mouse:isPressed(MouseControl.Left) then
        local pos = mouse:position()
        press = { slot = hovered, x = pos.x, y = pos.y, dragging = false }
    end
    if press then
        press.over = hovered
        local pos = mouse:position()
        if not press.dragging and slots[press.slot]
            and math.abs(pos.x - press.x) + math.abs(pos.y - press.y) > DRAG_START then
            press.dragging = true
        end
        if not mouse:isDown(MouseControl.Left) then
            if press.dragging then
                if hovered and hovered ~= press.slot then game:moveAction(press.slot, hovered) end
            elseif hovered == press.slot then
                game:useAction(press.slot)
            end
            press = nil
        end
    end

    -- The bar has the mouse while the cursor is on it, and through a drag
    if over or hovered or press then UIMouse.claim() end
end

return ActionBarPanel
