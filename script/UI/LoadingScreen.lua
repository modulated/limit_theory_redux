local DrawEx = require("UI.DrawEx")

--- The loading screens: starting a new game, loading a save, jumping between
--- systems.
---
--- Building a system is one long frame: whatever was drawn last stays on the
--- screen while it runs. So a screen is shown first (`show`) and held for a
--- moment (`ready` says when the work may start: it never just flashes);
--- the game then builds behind it, and `finish` fades it out over the new
--- scene. It is drawn over everything, menu or game (`draw`), and timed in
--- real time, not the game's.
---
--- What it shows: a starfield (streaking outward, a jump's warp, when
--- jumping), the title and a subtitle in the destination's colour, a turning
--- spinner, a progress bar with what is being done, and a tip.
local LoadingScreen = {
    current = nil, -- { kind, title, subtitle, color, minTime, shown, finished }
}

local FONT = "Unageo-Medium"
local FADE = 0.7

local TIPS = {
    "Ships too far off to identify show as signatures: louder ships are heard from further away.",
    "A jump drive (a capital's C-class module) reaches systems with no gate between them. It burns Radioactive Isotopes.",
    "Modules come in S, M, L and C classes: a hull takes its own class and smaller.",
    "Press R for the overview; right-click a row for what you can do with it.",
    "The factory's blueprints list what your hangar can make first.",
    "Stations in other systems keep trading while you are away: their prices move.",
    "Pirates lie in wait among the rocks of asteroid fields, where they are hard to hear.",
    "Bounty boards at stations post named pirates: their signatures show wherever they are.",
    "Hold the right mouse button to look around without turning the ship.",
    "The travel drive drops out on its own before a planet, moon or star.",
    "Drag one action bar slot onto another to swap them.",
    "Outposts can be guarded by drones or hired mercenaries.",
    "Escape closes what is open first; pressed again, it opens the menu.",
    "A bigger ship holds more targets, and its guns spread over them.",
}

--- A small fixed starfield: { x, y (-1..1 about the centre), b (brightness), s (speed) }.
local stars = nil
local function starfield()
    if stars then return stars end
    stars = {}
    local seed = 12345
    local function rnd()
        seed = (seed * 48271) % 2147483647
        return seed / 2147483647
    end
    for i = 1, 260 do
        local a = rnd() * math.pi * 2
        stars[i] = { a = a, r = rnd(), b = 0.25 + 0.75 * rnd() ^ 2, s = 0.4 + rnd() }
    end
    return stars
end

---@return number seconds since a timestamp
local function since(stamp)
    return stamp and stamp:getElapsed() or 0
end

--- Show a loading screen.
---@param args { kind: string, title: string, subtitle: string|nil, color: number[]|nil, minTime: number|nil, steps: string[]|nil }
function LoadingScreen.show(args)
    local tipIndex = math.floor((os.time() + #(args.title or "")) % #TIPS) + 1
    LoadingScreen.current = {
        kind = args.kind or "load",
        title = args.title or "Loading",
        subtitle = args.subtitle,
        color = args.color or { 0.6, 0.9, 1.0 },
        minTime = args.minTime or 1.2,
        steps = args.steps or { "Preparing" },
        tip = TIPS[tipIndex],
        shown = TimeStamp.Now(),
        finished = nil,
    }
end

--- Whether the work behind the screen may start: it has been up long enough.
---@return boolean
function LoadingScreen.ready()
    local c = LoadingScreen.current
    return c == nil or since(c.shown) >= c.minTime
end

--- The work is done: fade out.
function LoadingScreen.finish()
    local c = LoadingScreen.current
    if c and not c.finished then c.finished = TimeStamp.Now() end
end

--- Whether a screen is up (or fading).
---@return boolean
function LoadingScreen.active()
    return LoadingScreen.current ~= nil
end

--- Draw it, over everything.
function LoadingScreen.draw()
    local c = LoadingScreen.current
    if not c then return end
    local alpha = 1
    if c.finished then
        alpha = 1 - since(c.finished) / FADE
        if alpha <= 0 then
            LoadingScreen.current = nil
            return
        end
    end
    local w, h = Window:width(), Window:height()
    local cx, cy = w * 0.5, h * 0.5
    local t = since(c.shown)
    local col = c.color

    -- The dark, and the stars
    DrawEx.SimpleRect(0, 0, w, h, Color(0.01, 0.015, 0.03, alpha))
    local reach = math.sqrt(cx * cx + cy * cy)
    local warp = c.kind == "jump"
    for _, star in ipairs(starfield()) do
        local dx, dy = math.cos(star.a), math.sin(star.a)
        if warp then
            -- Streaking out from the middle, faster and longer as the jump builds
            local speed = star.s * (0.35 + math.min(1.5, t * 0.8))
            local r = (star.r + t * speed * 0.35) % 1
            local r1 = r * r * reach
            local r0 = math.max(0, r1 - (12 + 160 * r * math.min(1, t * 0.6)) * star.s)
            local b = star.b * math.min(1, r * 2.5) * alpha
            DrawEx.SimpleLine(cx + dx * r0, cy + dy * r0, cx + dx * r1, cy + dy * r1,
                Color(0.7 + 0.3 * col[1], 0.7 + 0.3 * col[2], 0.7 + 0.3 * col[3], b), 1.5)
        else
            -- Drifting slowly, twinkling
            local r = (star.r * reach + t * 6 * star.s) % reach
            local x, y = cx + dx * r, cy + dy * r * 0.62
            local tw = 0.6 + 0.4 * math.sin(t * 2.3 * star.s + star.a * 7)
            DrawEx.SimpleRect(x, y, 2, 2, Color(0.85, 0.9, 1.0, star.b * tw * alpha * 0.8))
        end
    end

    -- A band behind the text
    DrawEx.SimpleRect(0, cy - 90, w, 180, Color(0, 0, 0, 0.45 * alpha))
    DrawEx.SimpleRect(0, cy - 90, w, 2, Color(col[1], col[2], col[3], 0.6 * alpha))
    DrawEx.SimpleRect(0, cy + 88, w, 2, Color(col[1], col[2], col[3], 0.6 * alpha))

    -- Title and subtitle
    DrawEx.TextAlpha(FONT, c.title, 34, 0, cy - 74, w, 44, 1, 1, 1, alpha, 0.5, 0.5)
    if c.subtitle then
        DrawEx.TextAlpha(FONT, c.subtitle, 18, 0, cy - 28, w, 26, col[1], col[2], col[3], alpha, 0.5, 0.5)
    end

    -- The spinner: dots round a circle, the lit one going round
    local sx, sy, sr = cx, cy + 30, 13
    for i = 0, 11 do
        local a = i / 12 * math.pi * 2 - math.pi / 2
        local phase = (t * 1.6 - i / 12) % 1
        local lit = math.max(0.15, 1 - phase * 1.6)
        DrawEx.SimpleRect(sx + math.cos(a) * sr - 2, sy + math.sin(a) * sr - 2, 4, 4,
            Color(col[1], col[2], col[3], lit * alpha))
    end

    -- Progress: it runs up toward full while held, and fills when done
    local barW = math.min(520, w * 0.5)
    local bx, by = cx - barW / 2, cy + 58
    local share = c.finished and 1 or (1 - math.exp(-t / math.max(0.4, c.minTime * 0.9))) * 0.92
    DrawEx.SimpleRect(bx, by, barW, 4, Color(1, 1, 1, 0.12 * alpha))
    DrawEx.SimpleRect(bx, by, barW * share, 4, Color(col[1], col[2], col[3], 0.9 * alpha))
    -- A glint running along it
    local gx = bx + ((t * 0.7) % 1) * barW * share
    DrawEx.SimpleRect(gx - 12, by - 1, 24, 6, Color(1, 1, 1, 0.25 * alpha))
    local step = c.finished and "Done"
        or c.steps[math.min(#c.steps, math.floor(share / 0.92 * #c.steps) + 1)]
    DrawEx.TextAlpha(FONT, step, 12, 0, by + 10, w, 18, 0.75, 0.8, 0.88, alpha, 0.5, 0.5)

    -- A tip, at the bottom
    DrawEx.TextAlpha(FONT, c.tip or "", 13, w * 0.1, h - 70, w * 0.8, 20, 0.7, 0.74, 0.8, 0.85 * alpha, 0.5, 0.5)
end

return LoadingScreen
