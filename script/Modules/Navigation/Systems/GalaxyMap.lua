local DrawEx = require("UI.DrawEx")
local MapLabels = require("UI.MapLabels")
local MapFrame = require("UI.MapFrame")
local UniverseScaleConfig = require("Config.Gen.UniverseScaleConfig")
local GalaxyGenerator = require("Modules.Navigation.Managers.GalaxyGenerator")

--- Galaxy Map: the galaxy's star systems from above (universe X/Z) and the
--- jump-gate links between them. Click a system to plot the shortest route
--- to it; the game sets course along it (see LTheoryRedux).
---@class GalaxyMap
local GalaxyMap = {}

local FONT = 'Unageo-Medium'
local PICK_RADIUS = 18 -- pixels

local COLORS = {
    background = Color(0.02, 0.02, 0.04, 0.97),
    link       = Color(0.35, 0.55, 0.8, 0.35),
    routeLink  = Color(1.0, 0.8, 0.3, 0.9),
    system     = { 0.85, 0.88, 0.95 },
    visited    = { 0.45, 0.75, 1.0 },
    current    = { 0.3, 1.0, 0.4 },
    route      = { 1.0, 0.8, 0.3 },
    selected   = { r = 1.0, g = 0.3, b = 0.3, a = 1.0 },
}

---@return table state
function GalaxyMap:create()
    return {
        enabled    = false,
        galaxy     = nil,   ---@type Galaxy|nil
        currentId  = 1,
        visited    = {},    ---@type table<integer, boolean>
        selectedId = nil,   ---@type integer|nil
        route      = nil,   ---@type integer[]|nil route to the selection (systems after the current one)
        course     = nil,   ---@type integer[]|nil the route the ship is following
        centerX    = 0,
        centerZ    = 0,
        panX       = 0,
        panY       = 0,
        zoom       = 1,
        zoomTarget = 1,
        zoomSpeed  = 0.15,
        dragging   = false,
        lastMouseX = 0,
        lastMouseY = 0,
    }
end

--- Show the galaxy, centred and fitted to the window.
---@param state table
---@param galaxy Galaxy
---@param currentId integer the system the ship is in
---@param course integer[]|nil the route being followed, if any
function GalaxyMap:open(state, galaxy, currentId, course)
    state.galaxy = galaxy
    state.currentId = currentId
    state.visited[currentId] = true
    state.course = course
    state.selectedId = nil
    state.route = nil

    local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
    for _, system in ipairs(galaxy.systems) do
        local p = system.position
        minX, maxX = math.min(minX, p.x), math.max(maxX, p.x)
        minZ, maxZ = math.min(minZ, p.z), math.max(maxZ, p.z)
    end
    state.centerX, state.centerZ = (minX + maxX) / 2, (minZ + maxZ) / 2
    state.panX, state.panY = 0, 0
    local span = math.max(maxX - minX, maxZ - minZ, 1)
    state.zoom = math.min(Window:width(), Window:height()) * 0.8 / span
    state.zoomTarget = state.zoom
    state.minZoom = state.zoom * 0.2
    state.maxZoom = state.zoom * 50
end

--- Forget the systems visited (a new game).
---@param state table
function GalaxyMap:reset(state)
    state.visited = {}
    state.course = nil
end

---@param state table
---@param system GalaxySystem
---@return number x, number y screen position
local function toScreen(state, system, cx, cy)
    local p = system.position
    return cx + (p.x - state.centerX + state.panX) * state.zoom,
           cy + (p.z - state.centerZ + state.panY) * state.zoom
end

--- A system's hostility level (Config.game.hostility.levels), or nil.
local function hostilityOf(system)
    return system.hostility and Config.game.hostility.levels[system.hostility] or nil
end

local function lightYears(gameUnits)
    local meters = gameUnits / UniverseScaleConfig.globalScale
    return meters / UniverseScaleConfig.units.LIGHT_YEAR_TO_METERS
end

---@param state table
---@param dt number
function GalaxyMap:updateInput(state, dt)
    if not state.enabled or not state.galaxy then return end

    local MapActions = require("Input.ActionBindings.MapActions")
    MapActions.Zoom:update(dt)
    MapActions.Pan:update(dt)
    MapActions.Drag:update(dt)
    MapActions.Select:update(dt)

    local scrollY = MapActions.Zoom:get()
    if math.abs(scrollY) > 0.001 then
        state.zoomTarget = Math.Clamp(state.zoomTarget * math.exp(state.zoomSpeed * scrollY),
            state.minZoom, state.maxZoom)
    end
    local logCurrent, logTarget = math.log(state.zoom), math.log(state.zoomTarget)
    if math.abs(logTarget - logCurrent) > 0.0001 then
        state.zoom = math.exp(logCurrent + (logTarget - logCurrent) * math.min(1, 12 * dt))
    else
        state.zoom = state.zoomTarget
    end

    local mp = Input:mouse():position()
    if MapActions.Pan:isDown() or MapActions.Drag:isDown() then
        if state.dragging then
            state.panX = state.panX + (mp.x - state.lastMouseX) / state.zoom
            state.panY = state.panY + (mp.y - state.lastMouseY) / state.zoom
        end
        state.dragging = true
    else
        state.dragging = false
    end
    state.lastMouseX, state.lastMouseY = mp.x, mp.y

    if MapActions.Select:isPressed() then
        local cx, cy = Window:width() / 2, Window:height() / 2
        local best, bestDist = nil, PICK_RADIUS
        for _, system in ipairs(state.galaxy.systems) do
            local sx, sy = toScreen(state, system, cx, cy)
            local d = math.sqrt((sx - mp.x) ^ 2 + (sy - mp.y) ^ 2)
            if d < bestDist then best, bestDist = system, d end
        end
        state.selectedId = best and best.id or nil
        state.route = best and GalaxyGenerator:route(state.galaxy, state.currentId, best.id) or nil
    end
end

--- The route the map shows: the one to the selection, else the course.
local function shownRoute(state)
    if state.selectedId then return state.route end
    return state.course
end

---@param state table
---@param x number
---@param y number
---@param sx number
---@param sy number
function GalaxyMap:draw(state, x, y, sx, sy)
    if not state.enabled or not state.galaxy then return end
    local galaxy = state.galaxy
    local cx, cy = x + sx / 2, y + sy / 2

    DrawEx.SimpleRect(x, y, sx, sy, COLORS.background)
    -- (Title, controls: MapFrame, drawn over the map by the game state)

    -- Which systems and links are on the shown route
    local route = shownRoute(state)
    local onRoute, routeLinks = {}, {}
    if route then
        local from = state.currentId
        for _, id in ipairs(route) do
            onRoute[id] = true
            local link = GalaxyGenerator:linkBetween(galaxy, from, id)
            if link then routeLinks[link.id] = true end
            from = id
        end
    end

    -- Links
    for _, link in ipairs(galaxy.links) do
        local ax, ay = toScreen(state, galaxy.systems[link.a], cx, cy)
        local bx, by = toScreen(state, galaxy.systems[link.b], cx, cy)
        DrawEx.Line(ax, ay, bx, by, routeLinks[link.id] and COLORS.routeLink or COLORS.link)
    end

    -- Systems; their names are placed after the loop, clear of each other
    local labels = MapLabels.begin()
    for _, system in ipairs(galaxy.systems) do
        local px, py = toScreen(state, system, cx, cy)
        if px > x - 50 and px < x + sx + 50 and py > y - 50 and py < y + sy + 50 then
            -- Coloured by hostility; visited systems bigger, where you
            -- are biggest with a green ring, the route ringed in yellow
            local level = hostilityOf(system)
            local c = level and level.color or COLORS.system
            local size = state.visited[system.id] and 8 or 6
            if system.id == state.currentId then size = 10 end
            DrawEx.Rect(px - size / 2, py - size / 2, size, size, Color(c[1], c[2], c[3], 1.0))
            if system.id == state.currentId then
                DrawEx.Ring(px, py, size + 4, { r = 0.3, g = 1.0, b = 0.45, a = 1.0 }, true)
            elseif onRoute[system.id] then
                DrawEx.Ring(px, py, size + 4, { r = 1.0, g = 0.8, b = 0.3, a = 0.9 }, false)
            end
            if system.id == state.selectedId then
                DrawEx.Ring(px, py, size + 9, COLORS.selected, true)
            end
            local label = system.name
            if system.id == state.currentId then label = label .. "  (you are here)" end
            MapLabels.add(labels, {
                text = label, x = px, y = py, anchor = size / 2 + 2, size = 11,
                -- The selection and where you are always; then the route
                always = system.id == state.selectedId or system.id == state.currentId,
                priority = onRoute[system.id] and 50 or (state.visited[system.id] and 20 or 10),
                color = { c[1], c[2], c[3], 0.95 },
            })
        end
    end
    MapLabels.draw(labels, x, y + MapFrame.barHeight, sx, sy - MapFrame.barHeight)

    self:drawInfo(state, x + 10, y + sy - 170, 360)
    self:drawLegend(x + sx - 200, y + sy - 130)
end

--- What the colours mean, in the bottom-right corner.
function GalaxyMap:drawLegend(x, y)
    local levels = Config.game.hostility.levels
    DrawEx.Rect(x - 8, y - 8, 196, 26 + #levels * 18, Color(0.1, 0.1, 0.12, 0.9))
    DrawEx.TextAlpha(FONT, "Hostility", 12, x, y, 180, 16, 0.85, 0.85, 0.85, 0.9, 0.0, 0.5)
    for i, level in ipairs(levels) do
        local ly = y + 4 + i * 18
        local c = level.color
        DrawEx.Rect(x + 2, ly + 4, 8, 8, Color(c[1], c[2], c[3], 1.0))
        DrawEx.TextAlpha(FONT, level.name, 11, x + 18, ly, 160, 16, c[1], c[2], c[3], 0.95, 0.0, 0.5)
    end
end

--- The selected system (or the course) in the bottom-left corner.
function GalaxyMap:drawInfo(state, x, y, w)
    local galaxy = state.galaxy
    local id = state.selectedId or (state.course and state.course[#state.course])
    if not id then
        DrawEx.TextAlpha(FONT, string.format("%s: %d systems, %d gate links",
            galaxy.systems[state.currentId].name, #galaxy.systems, #galaxy.links),
            11, x, y + 120, w, 16, 0.8, 0.8, 0.8, 0.8, 0.0, 0.5)
        return
    end

    local system = galaxy.systems[id]
    local route = state.selectedId and state.route or state.course
    DrawEx.Rect(x - 5, y - 5, w + 10, 158, Color(0.1, 0.1, 0.12, 0.9))
    local lineH, ty = 18, y
    DrawEx.TextAlpha(FONT, system.name, 14, x, ty, w, lineH, 1.0, 0.8, 0.3, 1.0, 0.0, 0.5)
    ty = ty + lineH + 4

    local here = galaxy.systems[state.currentId]
    local function line(text, color)
        local c = color or { 0.85, 0.85, 0.85 }
        DrawEx.TextAlpha(FONT, text, 10, x, ty, w, lineH, c[1], c[2], c[3], 0.9, 0.0, 0.5)
        ty = ty + lineH
    end

    local level = hostilityOf(system)
    if level then
        line(string.format("%s: %s", level.name, level.description or ""), level.color)
    end

    if id == state.currentId then
        line("You are here")
    elseif not route then
        line("No route")
    else
        local dx, dy, dz = system.position.x - here.position.x, system.position.y - here.position.y,
            system.position.z - here.position.z
        line(string.format("Distance: %.0f ly", lightYears(math.sqrt(dx * dx + dy * dy + dz * dz))))
        line(string.format("Jumps: %d", #route))
        local names, worst = {}, nil
        for _, rid in ipairs(route) do
            table.insert(names, galaxy.systems[rid].name)
            local h = galaxy.systems[rid].hostility
            if h and (not worst or h > worst) then worst = h end
        end
        line("Route: " .. table.concat(names, " > "))
        local worstLevel = worst and Config.game.hostility.levels[worst]
        if worstLevel and #route > 1 then
            line("Most dangerous stop: " .. worstLevel.name, worstLevel.color)
        end
        if state.selectedId then
            line("N: set course")
        else
            line("Course set")
        end
    end
    line(string.format("Gate links: %d", #system.links))
end

return GalaxyMap
