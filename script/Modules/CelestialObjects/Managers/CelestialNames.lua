local CoreComponents = require("Modules.Core.Components")
local PhysicsComponents = require("Modules.Physics.Components")

--- The names of a star system's celestials, the way star charts give them:
--- the star after its system (Vega), the planets after the system with a
--- numeral counted out from the star (Vega I is the innermost), moons after
--- their planet with a letter counted out from it (Vega II a), a planet's
--- ring after it (Vega II Ring), the belts round the star numbered out from
--- it (Vega Belt 1).
---
--- A celestial's own Name component is its entity type ("PlanetEntity",
--- which the maps classify by), so it is no name to show; everything that
--- shows one asks here (`of`): the overview, the maps, the labels in space,
--- the gravity wells. Named once per system (`name`), when it is built.
---@class CelestialNames
local CelestialNames = {
    names = {},
    kinds = {},
}

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X",
                "XI", "XII", "XIII", "XIV", "XV", "XVI", "XVII", "XVIII", "XIX", "XX" }

---@param n integer
---@return string
local function roman(n)
    return ROMAN[n] or tostring(n)
end

--- The celestial kinds, by the entity's type name, in the order checked.
local KINDS = {
    { pattern = "StarEntity", kind = "Star" },
    { pattern = "PlanetEntity", kind = "Planet" },
    { pattern = "MoonEntity", kind = "Moon" },
    { pattern = "AsteroidBeltEntity", kind = "Belt" },
    { pattern = "AsteroidRingEntity", kind = "Ring" },
}

---@param entity Entity
---@return string|nil
function CelestialNames.kindOf(entity)
    local typeName = tostring(entity)
    for _, rule in ipairs(KINDS) do
        if typeName:find(rule.pattern, 1, true) then return rule.kind end
    end
    return nil
end

---@param entity Entity
---@return string
local function key(entity)
    return tostring(entity.id)
end

---@param entity Entity
---@return Position|nil
local function posOf(entity)
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if body then return body:getPos() end
    local t = entity:get(PhysicsComponents.Transform)
    return t and t:getPos() or nil
end

---@param a Position|nil
---@param b Position|nil
---@return number
local function dist(a, b)
    if not a or not b then return 0 end
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
end

--- Name a system's celestials (a new system, a jump).
---@param root Entity the system's root
---@param systemName string|nil nil outside a galaxy: generic names
function CelestialNames:name(root, systemName)
    self.names, self.kinds = {}, {}
    local found = {} -- { entity, kind, parent }
    local function walk(entity, parent)
        if not entity or not entity:isValid() then return end
        local kind = CelestialNames.kindOf(entity)
        if kind then found[#found + 1] = { entity = entity, kind = kind, parent = parent } end
        local children = entity:get(CoreComponents.Children)
        if children then
            -- A planet's or moon's children are its own; others pass theirs on
            local passOn = (kind == "Planet" or kind == "Moon") and entity or parent
            for child in children:iterChildren() do walk(child, passOn) end
        end
    end
    walk(root, nil)

    local star = nil
    for _, f in ipairs(found) do
        if f.kind == "Star" then star = f.entity break end
    end
    local starPos = star and posOf(star)
    local base = systemName or "Star"

    local function set(entity, kind, name)
        self.names[key(entity)] = name
        self.kinds[key(entity)] = kind
    end
    if star then set(star, "Star", base) end

    -- Planets and the star's belts, counted out from the star
    local planets, belts = {}, {}
    for _, f in ipairs(found) do
        local d = dist(posOf(f.entity), starPos)
        if f.kind == "Planet" then planets[#planets + 1] = { f = f, d = d } end
        if f.kind == "Belt" and not f.parent then belts[#belts + 1] = { f = f, d = d } end
    end
    table.sort(planets, function(a, b) return a.d < b.d end)
    table.sort(belts, function(a, b) return a.d < b.d end)
    for i, p in ipairs(planets) do
        set(p.f.entity, "Planet", systemName and string.format("%s %s", base, roman(i))
            or string.format("Planet %d", i))
    end
    for i, b in ipairs(belts) do
        set(b.f.entity, "Belt", systemName and string.format("%s Belt %d", base, i)
            or string.format("Belt %d", i))
    end

    -- Moons, counted out from their planet; rings and belts after it
    local moonsOf = {}
    for _, f in ipairs(found) do
        local parentName = f.parent and self.names[key(f.parent)]
        if f.kind == "Moon" then
            local k = f.parent and key(f.parent) or "?"
            moonsOf[k] = moonsOf[k] or { parent = f.parent, list = {} }
            table.insert(moonsOf[k].list, { f = f, d = dist(posOf(f.entity), f.parent and posOf(f.parent)) })
        elseif f.kind == "Ring" or (f.kind == "Belt" and f.parent) then
            set(f.entity, f.kind, parentName and (parentName .. " Ring") or "Ring")
        end
    end
    for _, group in pairs(moonsOf) do
        table.sort(group.list, function(a, b) return a.d < b.d end)
        local parentName = group.parent and self.names[key(group.parent)]
        for i, m in ipairs(group.list) do
            local letter = i <= 26 and string.char(string.byte("a") + i - 1) or tostring(i)
            set(m.f.entity, "Moon", parentName and string.format("%s %s", parentName, letter)
                or string.format("Moon %s", letter))
        end
    end
end

--- A celestial's name, or `fallback` (nil) for anything not named.
---@param entity Entity|nil
---@param fallback string|nil
---@return string|nil
function CelestialNames:of(entity, fallback)
    if not entity then return fallback end
    return self.names[key(entity)] or fallback
end

return CelestialNames
