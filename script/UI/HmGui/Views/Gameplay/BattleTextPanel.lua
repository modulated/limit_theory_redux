-- Scrolling battle text, right of the middle of the screen: what the ship's
-- weapons do and what is done to it (LimitTheoryRedux:battleText).
--   "Pulse Turret hit Pirate Raider: 56 damage (2 hits, 20 to shields)"
--   "Pirate Raider hit you: 12 damage"
--   "Pirate Raider destroyed"
-- New lines come in at the bottom and push the older ones up; each fades
-- out a few seconds after its last hit. The mouse passes through it.

local BattleTextPanel = {}

local OUT = Color(1.00, 0.85, 0.55, 1.00)   -- the player's hits
local IN = Color(1.00, 0.40, 0.35, 1.00)    -- hits on the player
local KILL = Color(1.00, 0.85, 0.30, 1.00)  -- a kill
local DEATH = Color(1.00, 0.25, 0.20, 1.00)

local LIFE = 4.0 -- seconds a line stays after its last hit
local FADE = 1.2 -- of which the last are a fade
local LINES = 9

---@return number
local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

---@param size number
local function font(size)
    return Cache.Font("Unageo-Medium", size)
end

---@param n number
local function amount(n)
    if n >= 10 then return string.format("%d", math.floor(n + 0.5)) end
    return string.format("%.1f", n)
end

---@param e table a battle log entry
---@return string, Color
local function line(e)
    if e.kill then
        if e.outgoing then return string.format("%s destroyed", e.who), KILL end
        return string.format("Destroyed by %s", e.who), DEATH
    end
    local extra = {}
    if e.hits > 1 then extra[#extra + 1] = string.format("%d hits", e.hits) end
    local shields = e.damage - e.hull
    if shields > 0.05 then extra[#extra + 1] = amount(shields) .. " to shields" end
    local tail = #extra > 0 and (" (" .. table.concat(extra, ", ") .. ")") or ""
    if e.outgoing then
        return string.format("%s hit %s: %s damage%s", e.weapon, e.who, amount(e.damage), tail), OUT
    end
    return string.format("%s hit you: %s damage%s", e.who, amount(e.damage), tail), IN
end

function BattleTextPanel.render()
    local game = LimitTheoryRedux
    local log = game and game.battleLog
    if not log or #log == 0 or not game.playerShip or game.docked or game.hudHidden
        or (game.mapMode or 0) ~= 0 or game.pauseMenuOpen then
        return
    end
    local now = game.simTime or 0
    -- Drop what has gone (oldest first)
    while #log > 0 and now - log[1].updated > LIFE do table.remove(log, 1) end
    if #log == 0 then return end

    local first = math.max(1, #log - LINES + 1)
    Gui:beginStackContainer()
    Gui:setScale(hudScale())
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Right, AlignVertical.Center)
    -- Right of the crosshair, clear of the overview on the right edge
    Gui:setPadding(math.floor(Window:width() * 0.18 / hudScale()), 0)
    Gui:beginVerticalContainer()
    Gui:setChildrenAlignment(AlignHorizontal.Left, AlignVertical.Bottom)
    Gui:setSpacing(2)
    for i = first, #log do
        local e = log[i]
        if now - e.updated <= LIFE then
            local text, color = line(e)
            local left = LIFE - (now - e.updated)
            local alpha = math.min(1, left / FADE)
            -- A fresh hit is a little larger, settling in a moment
            local fresh = math.max(0, 1 - (now - e.updated) / 0.25)
            Gui:text(text, font(e.kill and 15 or math.floor(13 + 2 * fresh)),
                Color(color.r, color.g, color.b, alpha))
        end
    end
    Gui:endContainer()
    Gui:endContainer()
end

return BattleTextPanel
