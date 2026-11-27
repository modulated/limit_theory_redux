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
    ---@type string the column the list is sorted by ("distance", "name", "type")
    sortKey = "distance",
    sortDescending = false,
    settingsLoaded = false,
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
---@field faction string|nil a ship's faction
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

--- The columns the list can be sorted by.
SystemOverview.SORTS = { name = true, type = true, distance = true }

--- Whether two handles are the same entity. Handles are not unique: the
--- registry hands out a fresh `Entity(id)` wrapper each time it is walked,
--- and Entity has no `__eq`, so `==` between handles from different places
--- is false for the same ship.
---@param a Entity|nil
---@param b Entity|nil
---@return boolean
function SystemOverview.same(a, b)
    return a ~= nil and b ~= nil and a.id == b.id
end

--- Forget the system: the next refresh walks the new one.
function SystemOverview:invalidate()
    self.statics = nil
    self.staticsRoot = nil
    self.entries = {}
    self.counts = {}
    self.selected = nil
    self.refreshTimer = 0
end

------------------------------------------------------------------------------
-- The player's choices, remembered in user.ini (GameState.ui.overview*)
------------------------------------------------------------------------------

--- Read the filters and the sort from the settings. Called on first use,
--- after user.ini has been read.
function SystemOverview:loadSettings()
    local ui = GameState.ui
    local shown = {}
    for name in string.gmatch(ui.overviewFilters or "", "[%a]+") do shown[name] = true end
    for _, category in ipairs(self.CATEGORIES) do
        self.filters[category] = shown[category] == true
    end
    self.sortKey = self.SORTS[ui.overviewSort] and ui.overviewSort or "distance"
    self.sortDescending = ui.overviewSortDescending == true
    self.settingsLoaded = true
end

--- Write the filters and the sort back to the settings (user.ini has them
--- the next time it is saved: leaving the game, or the Settings screen).
function SystemOverview:saveSettings()
    local shown = {}
    for _, category in ipairs(self.CATEGORIES) do
        if self.filters[category] then shown[#shown + 1] = category end
    end
    GameState.ui.overviewFilters = table.concat(shown, ",")
    GameState.ui.overviewSort = self.sortKey
    GameState.ui.overviewSortDescending = self.sortDescending
end

---@private
function SystemOverview:ensureSettings()
    if not self.settingsLoaded then self:loadSettings() end
end

---@param category string
---@param on boolean|nil nil flips it
function SystemOverview:setFilter(category, on)
    self:ensureSettings()
    if on == nil then on = not self.filters[category] end
    self.filters[category] = on
    self:saveSettings()
end

--- Sort by a column: the same column again reverses it, a new one starts
--- ascending (nearest, A to Z, or the category order).
---@param key string "name", "type" or "distance"
function SystemOverview:setSort(key)
    if not self.SORTS[key] then return end
    self:ensureSettings()
    if self.sortKey == key then
        self.sortDescending = not self.sortDescending
    else
        self.sortKey, self.sortDescending = key, false
    end
    self:saveSettings()
end

--- The category order, for sorting by type, and within the celestials the
--- order a chart reads them in: the star, then planets, moons, rings, belts.
local CATEGORY_RANK = { celestial = 1, station = 2, gate = 3, ship = 4, asteroid = 5 }
local KIND_RANK = { Star = 1, Planet = 2, Moon = 3, Ring = 4, Belt = 5 }

--- The comparison for a sort: ties always fall back to distance, so the
--- order is stable as the ship moves.
---@param key string
---@param descending boolean
---@return fun(a: OverviewEntry, b: OverviewEntry): boolean
local function comparator(key, descending)
    local function less(a, b)
        if key == "name" then
            local an, bn = a.name:lower(), b.name:lower()
            if an ~= bn then return an < bn end
        elseif key == "type" then
            local ar, br = CATEGORY_RANK[a.category] or 9, CATEGORY_RANK[b.category] or 9
            if ar ~= br then return ar < br end
            local ak, bk = KIND_RANK[a.kind] or 9, KIND_RANK[b.kind] or 9
            if ak ~= bk then return ak < bk end
            if a.kind ~= b.kind then return a.kind < b.kind end
        end
        return a.distance < b.distance
    end
    if not descending then return less end
    return function(a, b) return less(b, a) end
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

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
                "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX" }

---@param n integer
---@return string
local function roman(n)
    return ROMAN[n] or tostring(n)
end

--- Walk the system's tree for its celestials, and name them.
---
--- A celestial's Name component is its entity type ("PlanetEntity": it is
--- what the system map classifies by), so it is no name to show. They are
--- named the way star charts do it instead: the star after its system, the
--- planets after the system with a numeral in the order they were made
--- (Vega I, Vega II), their moons after the planet with a letter (Vega II a),
--- rings after their planet, belts numbered.
---@param root Entity
---@param systemName string|nil the star system's name; nil outside a galaxy
---@return table[] { entity, name, kind }
local function walkCelestials(root, systemName)
    local found = {}
    local counters = {}
    local function walk(entity, parentName)
        if not entity or not entity:isValid() then return end
        local kind = celestialKind(entity)
        local name = nil
        if kind then
            counters[kind] = (counters[kind] or 0) + 1
            local n = counters[kind]
            if kind == "Star" then
                name = systemName or "Star"
            elseif kind == "Planet" then
                name = systemName and string.format("%s %s", systemName, roman(n))
                    or string.format("Planet %d", n)
            elseif kind == "Moon" then
                -- Lettered per planet, not across the system
                counters.moonOf = counters.moonOf or {}
                local key = parentName or "?"
                counters.moonOf[key] = (counters.moonOf[key] or 0) + 1
                local letter = string.char(string.byte("a") + counters.moonOf[key] - 1)
                name = parentName and string.format("%s %s", parentName, letter)
                    or string.format("Moon %d", n)
            elseif kind == "Ring" then
                name = parentName and (parentName .. " Ring") or string.format("Ring %d", n)
            else
                name = string.format("Belt %d", n)
            end
            -- The shared names (CelestialNames) when the system was named
            name = require("Modules.CelestialObjects.Managers.CelestialNames"):of(entity, name)
            found[#found + 1] = { entity = entity, name = name, kind = kind }
        end
        local children = entity:get(CoreComponents.Children)
        if children then
            -- A planet's children are named after it; anything else passes
            -- on the name it was given
            local passOn = (kind == "Planet" or kind == "Moon") and name or parentName
            for child in children:iterChildren() do walk(child, passOn) end
        end
    end
    walk(root, nil)
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
    if root and (not SystemOverview.same(self.staticsRoot, root) or not self.statics) then
        local system = game.galaxy and game.galaxy.systems and game.currentSystemId
            and game.galaxy.systems[game.currentSystemId]
        self.statics = walkCelestials(root, system and system.name or nil)
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
        add({ entity = dock.entity, name = dock.label, kind = dock.outpost and "Outpost" or "Station",
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
    -- Ships, through the sensors: beyond their range, a signature at a rough
    -- place, unnamed (LimitTheoryRedux:mapNpcs)
    for _, npc in ipairs(game.mapNpcs and game:mapNpcs() or {}) do
        local pos, radius = placeOf(npc.entity)
        if npc.signature then
            if pos and npc.offset then
                pos = Position(pos.x + npc.offset.x, pos.y + npc.offset.y, pos.z + npc.offset.z)
            end
            add({ entity = npc.entity, name = npc.label, kind = "Signature",
                category = "ship", radius = 0, color = npc.color, hostile = false,
                signature = true }, pos)
        else
            local hostile = npc.faction and Factions.isHostile(npc.faction, Factions.Player) or false
            add({ entity = npc.entity, name = npc.label or "Ship", kind = "Ship",
                category = "ship", radius = radius, color = npc.color, hostile = hostile,
                faction = npc.faction }, pos)
        end
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

    -- Nearest first here; the panel's own sort is applied in `visible`
    table.sort(entries, function(a, b) return a.distance < b.distance end)
    self.entries, self.counts = entries, counts

    -- A selection that has gone (a ship destroyed, an asteroid streamed out)
    if self.selected and not self.selected:isValid() then self.selected = nil end
end

--- What the panel lists: the entries whose category is switched on, in the
--- player's sort order. The panel scrolls through it.
---@return OverviewEntry[]
function SystemOverview:visible()
    self:ensureSettings()
    local shown = {}
    for _, entry in ipairs(self.entries) do
        if self.filters[entry.category] and entry.entity:isValid() then
            shown[#shown + 1] = entry
        end
    end
    table.sort(shown, comparator(self.sortKey or "distance", self.sortDescending == true))
    return shown
end

return SystemOverview
