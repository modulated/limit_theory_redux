-- The weapon bar, bottom centre above the action bar: one slot per gun in
-- the ship's mounts (LimitTheoryRedux:weaponMounts), each showing
--   * the weapon, and its mount size
--   * what it is doing: firing (the slot flashes with each shot), reloading,
--     ready, aiming, no sight, out of range, no target, holding fire
--   * the reload, as a bar filling along the bottom, and the seconds left
--   * what it is shooting at
-- Looked at, not clicked: the mouse passes through it.

local WeaponsPanel = {}

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.78, 0.80, 0.84, 1.00)
local DIM = Color(0.45, 0.48, 0.53, 1.00)
local SLOT_BG = Color(0.02, 0.04, 0.07, 0.80)
local BORDER = Color(0.10, 0.60, 1.00, 0.35)
local BAR_BG = Color(0.10, 0.12, 0.16, 0.90)
local NO_COLOR = Color(0, 0, 0, 0)

-- Each state's colour: its label, the border, the reload bar
local STATE = {
    ["firing"]       = { label = "FIRING",       color = Color(1.00, 0.55, 0.20, 1.00) },
    ["reloading"]    = { label = "RELOADING",    color = Color(0.60, 0.75, 1.00, 1.00) },
    ["ready"]        = { label = "READY",        color = Color(0.30, 1.00, 0.55, 1.00) },
    ["aiming"]       = { label = "AIMING",       color = Color(0.95, 0.90, 0.40, 1.00) },
    ["no sight"]     = { label = "NO SIGHT",     color = Color(0.95, 0.65, 0.35, 1.00) },
    ["out of range"] = { label = "OUT OF RANGE", color = Color(0.95, 0.65, 0.35, 1.00) },
    ["no target"]    = { label = "NO TARGET",    color = Color(0.50, 0.53, 0.58, 1.00) },
    ["holding"]      = { label = "HOLDING",      color = Color(0.50, 0.53, 0.58, 1.00) },
}

local WIDTH = 104 -- a slot, HUD pixels at 1080p
local HEIGHT = 62
local GAP = 6
local ABOVE = 26 + 64 + 10 -- clear of the action bar (its padding and slots)

---@return number
local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

---@param size number
local function font(size)
    return Cache.Font("Unageo-Medium", size)
end

---@param s string
---@param n integer
local function clip(s, n)
    if #s <= n then return s end
    return s:sub(1, n - 1) .. "."
end

---@param c Color
---@param a number
local function withAlpha(c, a)
    return Color(c.r, c.g, c.b, a)
end

local function drawSlot(info)
    local st = STATE[info.state] or STATE["no target"]
    Gui:beginStackContainer()
    Gui:setFixedSize(WIDTH, HEIGHT)
    -- A shot lights the slot, fading out after it
    local glow = info.glow or 0
    Gui:setBackgroundColor(glow > 0 and Color(0.02 + 0.25 * glow, 0.04 + 0.12 * glow, 0.07, 0.85) or SLOT_BG)
    Gui:setBorderWidth(info.firing and 2 or 1)
    local idle = info.state == "no target" or info.state == "holding"
    Gui:setBorderColor(idle and BORDER or withAlpha(st.color, info.firing and 0.95 or 0.55))

    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setPadding(5, 3)
    Gui:setSpacing(1)
    -- The weapon, with its size
    Gui:beginHorizontalContainer()
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Top)
    Gui:text(clip(info.name or "weapon", 14), font(11), WHITE)
    if info.size then
        Gui:text(" " .. tostring(info.size):upper(), font(10), DIM)
    end
    Gui:endContainer()
    -- What it is doing
    Gui:text(st.label, font(11), st.color)
    -- What at
    Gui:text(info.target and clip(info.target, 16) or "-", font(10), info.target and GREY or DIM)
    Gui:endContainer()

    -- The reload, along the bottom, and the seconds left
    Gui:beginStackContainer()
    Gui:setFixedSize(WIDTH - 4, 3)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Bottom)
    Gui:setMargin(0, 2)
    Gui:setBackgroundColor(BAR_BG)
    Gui:beginStackContainer()
    Gui:setFixedSize(math.max(1, math.floor((WIDTH - 4) * (info.progress or 1))), 3)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:setBackgroundColor(info.state == "reloading" and STATE.reloading.color or withAlpha(st.color, 0.8))
    Gui:endContainer()
    Gui:endContainer()
    if info.state == "reloading" and (info.remaining or 0) > 0.1 then
        Gui:text(string.format("%.1fs", info.remaining), font(10), STATE.reloading.color)
        Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Top)
        Gui:setMargin(5, 3)
    end
    Gui:endContainer()
end

function WeaponsPanel.render()
    local game = LimitTheoryRedux
    if not (game and game.playerShip and game.weaponMounts and game.isTravelGame and game:isTravelGame())
        or game.docked or game.hudHidden or (game.mapMode or 0) ~= 0 or game.pauseMenuOpen then
        return
    end
    local mounts = game:weaponMounts()
    if #mounts == 0 then return end

    Gui:beginStackContainer()
    Gui:setScale(hudScale())
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Bottom)
    Gui:setPadding(0, ABOVE)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(GAP)
    Gui:setBackgroundColor(NO_COLOR)
    for _, info in ipairs(mounts) do drawSlot(info) end
    Gui:endContainer()
    Gui:endContainer()
end

return WeaponsPanel
