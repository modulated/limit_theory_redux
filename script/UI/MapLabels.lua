local DrawEx = require("UI.DrawEx")

--- Map labels that don't overlap. A map adds the labels of a frame, then draws
--- them: in priority order, each label takes the first of four spots around
--- its marker (right, left, above, below) that is on screen and clear of the
--- labels already placed. A label with no clear spot is left out, unless it
--- is `always` shown (the selection).
---
---     local labels = MapLabels.begin()
---     MapLabels.add(labels, { text = "Planet 1", x = sx, y = sy, anchor = 4,
---         priority = MapLabels.priorityOf(entity), color = { 0.3, 0.6, 1.0 } })
---     MapLabels.draw(labels, 0, 0, Window:width(), Window:height())
---@class MapLabels
local MapLabels = {}

local FONT = 'Unageo-Medium'
local GAP = 4      -- pixels between a marker and its label
local PADDING = 2  -- pixels kept clear around each placed label

-- How much a label matters, by the entity's kind (its name, e.g.
-- "PlanetEntity(12)"). First match wins; the selection comes before all of
-- them. The player's ship has no label: `playerMarker`.
local PRIORITIES = {
    { "StarEntity", 100 },
    { "SpaceshipEntity", 90 },
    { "PlanetEntity", 80 },
    { "JumpGateEntity", 70 },
    { "SpaceStationEntity", 60 },
    { "AsteroidBeltEntity", 50 },
    { "AsteroidRingEntity", 50 },
    { "MoonEntity", 40 },
    { "AsteroidEntity", 10 },
}

--- A label priority for an entity, from its kind.
---@param entity Entity|nil
---@return number
function MapLabels.priorityOf(entity)
    local name = entity and tostring(entity) or ""
    for _, p in ipairs(PRIORITIES) do
        if name:find(p[1], 1, true) then return p[2] end
    end
    return 20
end

---@return table layout
function MapLabels.begin()
    return { items = {}, reserved = {} }
end

local PLAYER_COLOR = Color(0.3, 1.0, 0.45, 1.0)
local PLAYER_RADIUS = 7

--- The player's ship: a green ring with a dot, no text. Always drawn: off
--- the screen area it sits at the area's edge, toward the ship. Labels keep
--- clear of it. Call before `draw`.
---@param layout table
---@param px number the ship's screen position
---@param py number
---@param x number the screen area
---@param y number
---@param w number
---@param h number
function MapLabels.playerMarker(layout, px, py, x, y, w, h)
    local m = PLAYER_RADIUS + 4
    local cx = math.max(x + m, math.min(x + w - m, px))
    local cy = math.max(y + m, math.min(y + h - m, py))
    local offScreen = cx ~= px or cy ~= py
    DrawEx.Ring(cx, cy, PLAYER_RADIUS, PLAYER_COLOR, true)
    DrawEx.SimpleRect(cx - 1.5, cy - 1.5, 3, 3, PLAYER_COLOR)
    if offScreen then
        -- A second ring: the ship is beyond the edge in this direction
        DrawEx.Ring(cx, cy, PLAYER_RADIUS + 4, Color(0.3, 1.0, 0.45, 0.5), false)
    end
    table.insert(layout.reserved, { x = cx - m, y = cy - m, w = 2 * m, h = 2 * m })
end

---@class MapLabel
---@field text string
---@field x number marker position on screen
---@field y number
---@field anchor number|nil half the marker's size: labels keep clear of it (default 4)
---@field priority number|nil higher is placed first (default 0)
---@field always boolean|nil shown even when it overlaps (the selection)
---@field color table { r, g, b[, a] } or a Color
---@field size number|nil font size (default 10)

---@param layout table
---@param label MapLabel
function MapLabels.add(layout, label)
    label.order = #layout.items + 1
    table.insert(layout.items, label)
end

local function overlaps(a, b)
    return a.x < b.x + b.w + PADDING and b.x < a.x + a.w + PADDING
        and a.y < b.y + b.h + PADDING and b.y < a.y + a.h + PADDING
end

local function rgba(color)
    if color.r then return color.r, color.g, color.b, color.a or 1 end
    return color[1], color[2], color[3], color[4] or 1
end

--- Place and draw the frame's labels inside the screen area (x, y, w, h).
---@param layout table
---@param x number
---@param y number
---@param w number
---@param h number
function MapLabels.draw(layout, x, y, w, h)
    local items = layout.items
    table.sort(items, function(a, b)
        local pa = (a.always and 1e6 or 0) + (a.priority or 0)
        local pb = (b.always and 1e6 or 0) + (b.priority or 0)
        if pa ~= pb then return pa > pb end
        return a.order < b.order
    end)

    local placed = {}
    for _, rect in ipairs(layout.reserved) do table.insert(placed, rect) end
    for _, label in ipairs(items) do
        local size = label.size or 10
        local bound = Cache.Font(FONT, size):getSize(label.text)
        local tw, th = bound.z, math.max(bound.w, size)
        local a = (label.anchor or 4) + GAP
        local spots = {
            { x = label.x + a,           y = label.y - th / 2 }, -- right
            { x = label.x - a - tw,      y = label.y - th / 2 }, -- left
            { x = label.x - tw / 2,      y = label.y - a - th }, -- above
            { x = label.x - tw / 2,      y = label.y + a },      -- below
        }

        local chosen = nil
        for _, spot in ipairs(spots) do
            local rect = { x = spot.x, y = spot.y, w = tw, h = th }
            local inside = rect.x >= x and rect.y >= y and rect.x + tw <= x + w and rect.y + th <= y + h
            if inside then
                local clear = true
                for _, other in ipairs(placed) do
                    if overlaps(rect, other) then clear = false; break end
                end
                if clear then chosen = rect; break end
            end
        end
        if not chosen and label.always then
            chosen = { x = spots[1].x, y = spots[1].y, w = tw, h = th }
        end

        if chosen then
            table.insert(placed, chosen)
            local r, g, b, alpha = rgba(label.color)
            DrawEx.TextAlpha(FONT, label.text, size, chosen.x, chosen.y, tw, th, r, g, b, alpha, 0.0, 0.5)
        end
    end
end

return MapLabels
