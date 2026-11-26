local PhysicsComponents = require("Modules.Physics.Components")
local CoreComponents = require("Modules.Core.Components")
local AsteroidFieldSystem = require("Modules.CelestialObjects.Systems.AsteroidFieldSystem")
local Factions = require("Modules.NPC.Factions")

--- What is in the star system, nearest first: the list the overview panel
--- shows (UI/HmGui/Views/Gameplay/OverviewPanel.lua).
---
--- Five categories, each with its own source:
---   celestial  the star, the planets, their moons, the belts and rings:
---              walked out of the system's entity tree once per system, as
---              the system map does, since they never come or go
---   station    the stations the player can dock at (`npcs.places.docks`),
---              which carry the dock record the Dock action needs
---   gate       the jump gates (`game.jumpGates`), which carry their
---              destination for the Jump action
---   ship       the NPC ships in flight (`npcs:mapEntries`)
---   asteroid   the asteroids streamed in around the player
---              (AsteroidFieldSystem), and only the nearest of those: a belt
---              holds thousands, so they are listed within
---              `Config.game.overview.asteroidRange` and at most
---              `maxAsteroids` of them
---
--- The list is rebuilt a few times a second (`refreshInterval`), not every
--- frame: positions change slowly next to how often it is drawn, and the
--- asteroid stream is the expensive part.
---
--- Distances are to the object's surface (its bounding radius), so a planet
--- reads as how far its ground is rather than its centre.
---@class SystemOverview
local SystemOverview = {
    ---@type table<string, boolean> which categories are listed
    filters = { celestial = true, station = true, gate = true, ship = true, asteroid = true },
    ---@type OverviewEntry[] everything found at the last refresh, nearest first
    entries = {},
    ---@type table<string, integer> how many of each category the last refresh found
    counts = {},
    ---@type Entity|nil the row the player last clicked
    selected = nil,
    refreshTimer = 0,
    ---@private the celestials, walked once per system
    statics = nil,
    ---@private the system root the statics were walked from
    staticsRoot = nil,
}

---@class OverviewEntry
---@field entity Entity
---@field name string
---@field kind string what it is, for the Type column ("Planet", "Station"...)
---@field category string "celestial", "station", "gate", "ship" or "asteroid"
---@field distance number to its surface, in game units
---@field radius number
---@field color table|nil { r, g, b } for the name, where it has one (ships: faction)
---@field hostile boolean|nil a ship whose faction is hostile to the player
---@field dock table|nil for a station: its dock record
---@field gate JumpGatePlacement|nil for a gate

--- The order the categories are offered in.
SystemOverview.CATEGORIES = { "celestial", "station", "gate", "ship", "asteroid" }

--- What each category is called on its filter button.
SystemOverview.CATEGORY_NAMES = {
    celestial = "Celestials",
    station = "Stations",
    gate = "Gates",
    ship = "Ships",
    asteroid = "Asteroids",
}

--- Forget the system: the next refresh walks the new one.
function SystemOverview:invalidate()
    self.statics = nil
    self.staticsRoot = nil
    self.entries = {}
    self.counts = {}
    self.selected = nil
    self.refreshTimer = 0
end

---@param category string
---@param on boolean|nil nil flips it
function SystemOverview:setFilter(category, on)
    if on == nil then on = not self.filters[category] end
    self.filters[category] = on
end

------------------------------------------------------------------------------
-- Where things are
------------------------------------------------------------------------------

--- An entity's centre and radius: its rigid body when it has one, its
--- transform otherwise.
---@param entity Entity
---@return Position|nil pos
---@return number radius
local function placeOf(entity)
    if not entity or not entity:isValid() then return nil, 0 end
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if body then return body:getPos(), body:getBoundingRadius() end
    local transform = entity:get(PhysicsComponents.Transform)
    if transform then return transform:getPos(), transform:getScale() end
    return nil, 0
end

---@param a Position
---@param b Position
---@return number
local function distanceBetween(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

------------------------------------------------------------------------------
-- The celestials, once per system
------------------------------------------------------------------------------

--- The celestial kinds, by the entity's type name (the same test the
--- system map uses), in the order they are checked.
local CELESTIAL_KINDS = {
    { pattern = "StarEntity", kind = "Star" },
    { pattern = "PlanetEntity", kind = "Planet" },
    { pattern = "MoonEntity", kind = "Moon" },
    { pattern = "AsteroidBeltEntity", kind = "Belt" },
    { pattern = "AsteroidRingEntity", kind = "Ring" },
}

---@param entity Entity
---@return string|nil kind
local function celestialKind(entity)
    local typeName = tostring(entity)
    for _, rule in ipairs(CELESTIAL_KINDS) do
        if typeName:find(rule.pattern, 1, true) then return rule.kind end
    end
    return nil
end

--- Walk the system's tree for its celestials.
---@param root Entity
---@return table[] { entity, name, kind }
local function walkCelestials(root)
    local found = {}
    local counters = {}
    local function walk(entity)
        if not entity or not entity:isValid() then return end
        local kind = celestialKind(entity)
        if kind then
            counters[kind] = (counters[kind] or 0) + 1
            local nameCmp = entity:get(CoreComponents.Name)
            local name = nameCmp and nameCmp:getName()
            if not name or name == "" then
                -- No name of its own: numbered by kind, as the map does
                name = kind == "Star" and "Star" or string.format("%s %d", kind, counters[kind])
            end
            found[#found + 1] = { entity = entity, name = name, kind = kind }
        end
        local children = entity:get(CoreComponents.Children)
        if children then
            for child in children:iterChildren() do walk(child) end
        end
    end
    walk(root)
    return found
end

------------------------------------------------------------------------------
-- Refreshing
------------------------------------------------------------------------------

--- Rebuild the list if it is time.
---@param game table the game state (LimitTheoryRedux)
---@param dt number
---@param force boolean|nil rebuild now regardless of the timer
function SystemOverview:update(game, dt, force)
    self.refreshTimer = self.refreshTimer - (dt or 0)
    if not force and self.refreshTimer > 0 then return end
    local cfg = Config.game.overview
    self.refreshTimer = cfg.refreshInterval or 0.25
    self:refresh(game)
end

--- Rebuild the list from what the game holds now.
---@param game table
function SystemOverview:refresh(game)
    local cfg = Config.game.overview
    local entries, counts = {}, {}
    for _, category in ipairs(self.CATEGORIES) do counts[category] = 0 end

    local ship = game.playerShip
    local here = ship and ship:isValid() and placeOf(ship)
    if not here then
        self.entries, self.counts = entries, counts
        return
    end

    local function add(entry, pos)
        if not pos then return end
        entry.distance = math.max(0, distanceBetween(here, pos) - (entry.radius or 0))
        entries[#entries + 1] = entry
        counts[entry.category] = counts[entry.category] + 1
    end

    -- Celestials: walked once, measured every refresh
    local root = game.universe
    if root and (self.staticsRoot ~= root or not self.statics) then
        self.statics = walkCelestials(root)
        self.staticsRoot = root
    end
    for _, body in ipairs(self.statics or {}) do
        local pos, radius = placeOf(body.entity)
        add({ entity = body.entity, name = body.name, kind = body.kind,
            category = "celestial", radius = radius }, pos)
    end

    -- Stations, as the docks they are
    local places = game.npcs and game.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        local pos, radius = placeOf(dock.entity)
        add({ entity = dock.entity, name = dock.label, kind = "Station",
            category = "station", radius = radius, dock = dock }, pos)
    end

    -- Gates, with where they go
    for _, gate in ipairs(game.jumpGates or {}) do
        local pos, radius = placeOf(gate.entity)
        local name = gate.destination and ("Gate to " .. gate.destination.name) or "Jump Gate"
        add({ entity = gate.entity, name = name, kind = "Gate",
            category = "gate", radius = radius or gate.radius, gate = gate }, pos)
    end

    -- Ships in flight
    for _, npc in ipairs(game.npcs and game.npcs:mapEntries() or {}) do
        local pos, radius = placeOf(npc.entity)
        local hostile = npc.faction and Factions.isHostile(npc.faction, Factions.Player) or false
        add({ entity = npc.entity, name = npc.label or "Ship", kind = "Ship",
            category = "ship", radius = radius, color = npc.color, hostile = hostile }, pos)
    end

    -- Asteroids: the nearest few, within reach of being worth listing
    local range = cfg.asteroidRange or 10
    local near = {}
    for _, info in ipairs(AsteroidFieldSystem:getSpawnedEntities()) do
        if info.entity and info.entity:isValid() and info.pos then
            local d = distanceBetween(here, info.pos) - (info.scale or 0)
            if d <= range then near[#near + 1] = { info = info, d = d } end
        end
    end
    table.sort(near, function(a, b) return a.d < b.d end)
    local mining = game.npcs and game.npcs.mining
    for i = 1, math.min(#near, cfg.maxAsteroids or 25) do
        local info = near[i].info
        -- A rock the player has surveyed (or cut into) is named by its ore.
        -- rockFor only looks: a rock nobody has touched is not tracked, and
        -- listing it must not start tracking it.
        local name = "Asteroid"
        local rock = mining and info.field and info.asteroid and mining:rockFor(info.field, info.asteroid)
        if rock and game.knowsRock and game:knowsRock({ rock = rock }) then
            name = rock.yield < 1 and "Asteroid (spent)" or string.format("Asteroid: %s", rock.item)
        end
        add({ entity = info.entity, name = name, kind = "Asteroid",
            category = "asteroid", radius = info.scale or 0 }, info.pos)
    end

    table.sort(entries, function(a, b) return a.distance < b.distance end)
    self.entries, self.counts = entries, counts

    -- A selection that has gone (a ship destroyed, an asteroid streamed out)
    if self.selected and not self.selected:isValid() then self.selected = nil end
end

--- What the panel lists: the entries whose category is switched on, nearest
--- first, no more than `limit` of them.
---@param limit integer|nil
---@return OverviewEntry[] shown
---@return integer hidden how many more matched than were shown
function SystemOverview:visible(limit)
    local shown, matched = {}, 0
    for _, entry in ipairs(self.entries) do
        if self.filters[entry.category] and entry.entity:isValid() then
            matched = matched + 1
            if not limit or #shown < limit then shown[#shown + 1] = entry end
        end
    end
    return shown, matched - #shown
end

return SystemOverview
