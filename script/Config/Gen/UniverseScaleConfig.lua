-- Manages scale conversions and unit transformations for universe generation

---@class gameunit ---engine units (m)

---@class UniverseScaleConfig
local UniverseScaleConfig = {
    -- Global scale factor (1.0 = real scale, smaller = compressed universe)
    -- 0.0001 = 1:10,000 scale - Solar system fits in ~30km
    -- 0.00001 = 1:100,000 scale - Solar system fits in ~3km
    globalScale = 0.0001,

    -- Physical unit conversions (real-world meters)
    units = {
        AU_TO_METERS = 1.496e11,             -- Astronomical Unit (Earth-Sun distance)
        SOLAR_RADIUS_TO_METERS = 6.96e8,     -- Sun's radius
        EARTH_RADIUS_TO_METERS = 6.371e6,    -- Earth's radius
        LIGHT_YEAR_TO_METERS = 9.461e15,     -- Light year
        JUPITER_RADIUS_TO_METERS = 6.9911e7, -- Jupiter's radius
    },

    -- Specific scale multipliers for different object types
    -- These are applied ON TOP of globalScale for visibility
    objectScales = {
        starSystem = 1.0,
        star = 1.0,
        planet = 1.0,
        moon = 1.0,
        asteroidRing = 1.0,
        asteroidBelt = 1.0,
        zone = 1.0,
    },

    -- Orbit visualization scale (can be different from physical scale)
    orbitScale = 1.0,

    -- Universe distribution settings
    universe = {
        distributionType = "sphere", -- "sphere", "cube", "grid"
        radius = 1e16,               -- 1e16 meters (~1.06 light years)
        gridSpacing = 1e15,          -- For grid distribution
        gridJitter = 0.3,            -- Randomization factor for grid (0-1)
    },
}

--- Fake game unit return, cause lua ls doesnt allow us to create a real "type"
---@param number number
---@return gameunit gameUnits
function UniverseScaleConfig:asGameUnits(number)
    return number
end

---Convert real meters to game units with object-specific scaling
---@param realMeters number Real-world meters
---@param objectType string Type of object ("star", "planet", "moon", etc.)
---@return gameunit gameUnits Scaled value in game units (meters)
function UniverseScaleConfig:toGameUnits(realMeters, objectType)
    local typeScale = self.objectScales[objectType] or 1.0
    return realMeters * self.globalScale * typeScale
end

---Convert Astronomical Units to game units
---@param au number Distance in AU
---@param objectType string|nil Type of object (default: "starSystem")
---@return gameunit gameUnits Scaled value in game units (meters)
function UniverseScaleConfig:auToGameUnits(au, objectType)
    local meters = au * self.units.AU_TO_METERS
    return self:toGameUnits(meters, objectType or "starSystem")
end

---Convert solar radii to game units
---@param solarRadii number Radius in solar radii
---@param objectType string|nil Type of object (default: "star")
---@return gameunit gameUnits Scaled value in game units (meters)
function UniverseScaleConfig:solarRadiiToGameUnits(solarRadii, objectType)
    local meters = solarRadii * self.units.SOLAR_RADIUS_TO_METERS
    return self:toGameUnits(meters, objectType or "star")
end

---Convert Earth radii to game units
---@param earthRadii number Radius in Earth radii
---@param objectType string|nil Type of object (default: "planet")
---@return gameunit gameUnits Scaled value in game units (meters)
function UniverseScaleConfig:earthRadiiToGameUnits(earthRadii, objectType)
    local meters = earthRadii * self.units.EARTH_RADIUS_TO_METERS
    return self:toGameUnits(meters, objectType or "planet")
end

---Convert Jupiter radii to game units (for gas giants)
---@param jupiterRadii number Radius in Jupiter radii
---@param objectType string|nil Type of object (default: "planet")
---@return gameunit gameUnits Scaled value in game units (meters)
function UniverseScaleConfig:jupiterRadiiToGameUnits(jupiterRadii, objectType)
    local meters = jupiterRadii * self.units.JUPITER_RADIUS_TO_METERS
    return self:toGameUnits(meters, objectType or "planet")
end

---Convert kilometers to game units (for moons)
---@param km number Distance in kilometers
---@param objectType string|nil Type of object (default: "moon")
---@return gameunit gameUnits Scaled value in game units (meters)
function UniverseScaleConfig:kmToGameUnits(km, objectType)
    local meters = km * 1000
    return self:toGameUnits(meters, objectType or "moon")
end

---Get star radius in game units from mass (rough approximation)
---@param massInSolarMasses number Star mass in solar masses
---@return gameunit radius Radius in game units
function UniverseScaleConfig:getStarRadius(massInSolarMasses)
    -- Rough approximation: R ∝ M^0.8 for main sequence stars
    local radiusInSolarRadii = massInSolarMasses ^ 0.8
    return self:solarRadiiToGameUnits(radiusInSolarRadii, "star")
end

---Convert game units back to real meters
function UniverseScaleConfig:toRealMeters(gameUnits, objectType)
    local typeScale = self.objectScales[objectType] or 1.0
    return gameUnits / (self.globalScale * typeScale)
end

---Convert meters ➜ Earth radii
function UniverseScaleConfig:metersToEarthRadii(meters)
    return meters / self.units.EARTH_RADIUS_TO_METERS
end

---Convert meters ➜ Jupiter radii
function UniverseScaleConfig:metersToJupiterRadii(meters)
    return meters / self.units.JUPITER_RADIUS_TO_METERS
end

---Convert meters ➜ Solar radii
function UniverseScaleConfig:metersToSolarRadii(meters)
    return meters / self.units.SOLAR_RADIUS_TO_METERS
end

---Convert meters ➜ AU
function UniverseScaleConfig:metersToAU(meters)
    return meters / self.units.AU_TO_METERS
end

--- Pretty-print scale information for any celestial body
---@param label string Name of body (e.g., "Earth", "Europa")
---@param gameUnits gameunit Scaled radius (in-game meters)
---@param objectType string "star" | "planet" | "moon" | ...
function UniverseScaleConfig:debugSize(label, gameUnits, objectType)
    local realMeters = self:toRealMeters(gameUnits, objectType)
    print(("--- %s ---"):format(label))
    print(("Scaled radius: %.2f m"):format(gameUnits))
    print(("Real radius: %.2f m"):format(realMeters))

    if objectType == "star" then
        print(("Real size: %.3f R☉"):format(self:metersToSolarRadii(realMeters)))
    elseif objectType == "planet" then
        print(("Real size: %.3f R⊕"):format(self:metersToEarthRadii(realMeters)))
    elseif objectType == "moon" then
        print(("Real size: %.3f RJ"):format(self:metersToJupiterRadii(realMeters)))
    else
        print("No reference unit available for this type.")
    end

    print("-------------------------")
end

--- `n` with about three significant figures, digits grouped in thousands:
--- 1.25, 12.5, 125, 1,250, 12,500.
---@param n number
---@return string
local function figures(n)
    local text
    if n < 10 then
        text = string.format("%.2f", n)
    elseif n < 100 then
        text = string.format("%.1f", n)
    else
        text = string.format("%.0f", n)
    end
    local int, frac = text:match("^(%d+)(.*)$")
    if not int then return text end
    int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return int .. frac
end

local SPEED_OF_LIGHT = 299792458 -- m/s

---A distance in the unit that reads best, with about three significant
---figures: m, km, thousands and millions of km, AU, then light years
---("850 m", "4,820 km", "125k km", "1.25M km", "5.20 AU", "2.50 ly").
---@param gameUnits gameunit
---@return string
function UniverseScaleConfig:formatDistance(gameUnits)
    local m = math.abs(gameUnits) / self.globalScale
    local km = m / 1000
    local au = m / self.units.AU_TO_METERS
    if m < 1000 then
        return string.format("%.0f m", m)
    elseif km < 10000 then
        return figures(km) .. " km"
    elseif km < 1e6 then
        return figures(km / 1000) .. "k km"
    elseif au < 0.1 then
        return figures(km / 1e6) .. "M km"
    elseif au < 10000 then
        return figures(au) .. " AU"
    end
    return figures(m / self.units.LIGHT_YEAR_TO_METERS) .. " ly"
end

---A speed in the unit that reads best: m/s, km/s, then multiples of the
---speed of light from a tenth of it on ("850 m/s", "8.80 km/s",
---"1,250 km/s", "1.17 c").
---@param gameUnitsPerSec number
---@return string
function UniverseScaleConfig:formatSpeed(gameUnitsPerSec)
    local mps = math.abs(gameUnitsPerSec) / self.globalScale
    if mps < 1000 then
        return string.format("%.0f m/s", mps)
    elseif mps < 0.1 * SPEED_OF_LIGHT then
        return figures(mps / 1000) .. " km/s"
    end
    return figures(mps / SPEED_OF_LIGHT) .. " c"
end

return UniverseScaleConfig
