local DrawEx = require("UI.DrawEx")

--- The frame every map draws over itself, so it is plain that a map is open
--- (the 3D map shows the scene, which looks like flying otherwise) and why
--- the ship's keys don't fly the ship: a bar across the top with the maps as
--- tabs, the open map's controls and how to close it, and a border around
--- the screen.
---@class MapFrame
local MapFrame = {}

local FONT = 'Unageo-Medium'
local BAR_HEIGHT = 52
local BORDER = 2
local ACCENT = Color(0.35, 0.75, 1.0, 0.9)
local BAR = Color(0.03, 0.05, 0.08, 0.92)

--- The maps in M's order: tab name and each map's own controls.
local MAPS = {
    { tab = "2D",     controls = "Left click: select  ·  N: autopilot to it  ·  Wheel: zoom  ·  Right drag: pan  ·  Amber: unidentified signatures" },
    { tab = "3D",     controls = "Left click: select  ·  N: autopilot to it  ·  WASD: move  ·  Right drag: rotate  ·  Wheel: zoom" },
    { tab = "GALAXY", controls = "Left click: plot a route  ·  N: set course  ·  Wheel: zoom  ·  Right drag: pan" },
}

--- Height of the top bar: what a map keeps clear at the top of its area.
MapFrame.barHeight = BAR_HEIGHT

--- Where each tab was last drawn, for clicks: { mode, x, y, w, h }.
local tabRects = {}

--- The map whose tab is under a screen position, or nil.
---@param px number
---@param py number
---@return integer|nil mode
function MapFrame.tabAt(px, py)
    for _, t in ipairs(tabRects) do
        if px >= t.x and px <= t.x + t.w and py >= t.y and py <= t.y + t.h then return t.mode end
    end
    return nil
end

---@param mode integer 1 = 2D, 2 = 3D, 3 = galaxy
---@param mapCount integer how many maps M cycles through (no galaxy map without a galaxy)
---@param x number
---@param y number
---@param w number
---@param h number
function MapFrame.draw(mode, mapCount, x, y, w, h)
    local map = MAPS[mode]
    if not map then return end

    -- Border
    DrawEx.SimpleRect(x, y, w, BORDER, ACCENT)
    DrawEx.SimpleRect(x, y + h - BORDER, w, BORDER, ACCENT)
    DrawEx.SimpleRect(x, y, BORDER, h, ACCENT)
    DrawEx.SimpleRect(x + w - BORDER, y, BORDER, h, ACCENT)

    -- Bar
    DrawEx.SimpleRect(x, y, w, BAR_HEIGHT, BAR)
    DrawEx.SimpleRect(x, y + BAR_HEIGHT - 1, w, 1, ACCENT)

    -- Tabs: MAP  2D  3D  GALAXY, the open one lit
    local tx = x + 14
    DrawEx.TextAlpha(FONT, "MAP", 16, tx, y + 6, 60, 22, 0.6, 0.7, 0.8, 0.9, 0.0, 0.5)
    tx = tx + 60
    tabRects = {}
    local mouse = Input:mouse():position()
    for i = 1, mapCount do
        local lit = i == mode
        local label = MAPS[i].tab
        local tw = Cache.Font(FONT, 16):getSize(label).z
        local rect = { mode = i, x = tx - 8, y = y + 4, w = tw + 16, h = 28 }
        tabRects[#tabRects + 1] = rect
        local hover = mouse.x >= rect.x and mouse.x <= rect.x + rect.w and mouse.y >= rect.y and mouse.y <= rect.y + rect.h
        if lit then
            DrawEx.SimpleRect(tx - 8, y + 6, tw + 16, 24, Color(0.35, 0.75, 1.0, 0.25))
        elseif hover then
            DrawEx.SimpleRect(tx - 8, y + 6, tw + 16, 24, Color(0.35, 0.75, 1.0, 0.12))
        end
        local c = lit and 1.0 or 0.5
        DrawEx.TextAlpha(FONT, label, 16, tx, y + 6, tw, 24, c, c, c, 1.0, 0.0, 0.5)
        tx = tx + tw + 28
    end

    -- How to leave, on the right
    DrawEx.TextAlpha(FONT, "Click a tab or M: switch map  ·  Esc: close", 13, x + w - 414, y + 8, 400, 20,
        0.85, 0.85, 0.85, 0.9, 1.0, 0.5)

    -- The map's controls, and why the ship doesn't respond
    DrawEx.TextAlpha(FONT, map.controls .. "   |   Ship controls paused: the autopilot keeps flying", 11,
        x + 14, y + 32, w - 28, 16, 0.65, 0.75, 0.85, 0.85, 0.0, 0.5)
end

return MapFrame
