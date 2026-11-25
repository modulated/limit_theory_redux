--! this can be split up better
Config.game = {
    boostCost              = 20,

    explosionSize          = 64,

    autoTarget             = false,

    droneType              = 1, -- 1 = mining drone, 2 = combat drone
    droneDamage            = 10,
    droneTarget            = nil,
    droneSize              = 75,
    droneSpeed             = 50,
    droneRange             = 5000,

    missileDamage          = 80,
    missileTarget          = nil,
    missileSize            = 100,
    missileSpeed           = 100,
    missileRange           = 10000,

    torpedoDamage          = 250,
    torpedoTarget          = nil,
    torpedoSize            = 64,
    torpedoSpeed           = 30,
    torpedoRange           = 14000,

    weaponGroup            = 1,

    shieldColor            = Color(0.2, 0.5, 1.0, 1.0),

    enemies                = 0,
    friendlies             = 0,
    squadSizeEnemy         = 8,
    squadSizeFriendly      = 8,

    spawnDistance          = 2000,
    friendlySpawnCount     = 10,
    timeScaleShipEditor    = 0.0,

    aiFire                 = function(dt, rng) return rng:getExp() ^ 2 < dt end,

    autonavRanges          = { 200, -- Unknown
        0,                          -- Reserved
        0,                          -- Star Sector
        0,                          -- Star System
        2000,                       -- Zone
        1e7,                        -- Star (TODO: radius + offset)
        10000,                      -- Planet (TODO: radius + offset)
        300,                        -- Asteroid
        500,                        -- Jumpgate
        2000,                       -- Station
        100 },                      -- Ship

    dockRange              = 50,

    shipFlight = (function()
        local ScaleConfig = require("Config.Gen.UniverseScaleConfig")

        -- Define desired real-world values
        local maxSpeedReal    = 8800     -- m/s max speed (~8.8 km/s for fighter)
        local accelTimeReal   = 8.0      -- seconds to reach max speed
        local lateralRatio    = 0.5      -- lateral/vertical thrust vs forward
        local verticalRatio   = 0.25     -- vertical thrust vs forward

        -- Convert to game units using ScaleConfig
        local maxSpeedGame = ScaleConfig:toGameUnits(maxSpeedReal, "starSystem")
        local accelGame    = maxSpeedGame / accelTimeReal

        -- Derive physics values
        -- Mass from hull config (Solo = index 1)
        local mass = 5000
        local drag = 2.0
        local thrust = maxSpeedGame * mass * drag

        -- Torque from mass: gives ~10 rad/s² angular acceleration (responsive but not spinny)
        -- Torque: tuned empirically. The equilibrium turn rate is:
        --   ω_max = torque / (I × angularDrag)
        -- where I = 2/5 × m × r² (tiny at small globalScale).
        -- angularDrag dominates the feel; torque sets responsiveness.
        local torque = 50

        return {
            -- Auto-computed from desired speed/acceleration
            thrustForward  = thrust,
            thrustRight    = thrust * lateralRatio,
            thrustUp       = thrust * verticalRatio,

            -- Rotational torques (derived from mass × desired angular acceleration)
            torquePitch    = torque,
            torqueYaw      = torque,
            torqueRoll     = torque * 0.6,

            -- Auto-computed physics
            linearDrag     = drag,
            angularDrag    = 20.0,

            -- Input inversion
            invertYaw      = false,
            invertPitch    = false,

            -- Reference values for other systems
            maxSpeedGame   = maxSpeedGame,
            maxSpeedReal   = maxSpeedReal,
        }
    end)(),

    -- Ship hull classes (from legacy, indexed by Enums.ShipHulls)
    -- Solo=1, Small=2, Compact=3, Medium=4, Large=5, VeryLarge=6
    shipHulls = {
        -- Scaled for globalScale 0.0001 (1 game unit = 10km)
        -- Solo ~50m, Small ~100m, Compact ~150m, Medium ~200m, Large ~300m, VeryLarge ~500m
        scale  = { 0.005, 0.01, 0.015, 0.02, 0.03, 0.05 },
        radius = { 0.003, 0.005, 0.008, 0.012, 0.018, 0.025 },
        mass   = { 5000, 10000, 18000, 30000, 50000, 100000 },
        drag   = { 2.0, 2.0, 2.0, 2.0, 2.0, 2.0 },
        -- Translation speed multiplier (smaller = less lateral/vertical for big ships)
        tranM  = { 0.8, 0.2, 0.1, 0.06, 0.03, 0.0 },
        -- Maneuverability multiplier (pitch/yaw/roll scaling)
        manuM  = { 0.3, 0.5, 0.2, 0.1, 0.06, 1.5 },
    },

    travelDrive = {
        chargeRequired  = 3.0,     -- seconds holding T to activate
        speedMultiplier = 40000,   -- adjusted for higher base thrust
        rampUpSpeed     = 0.3,
        rampDownSpeed   = 1.5,

        -- Max speed multiplier per zone type
        maxSpeedByZone = {
            moon      = 200,
            planet    = 2000,
            star      = 8000,
            openSpace = 40000,
        },
    },

    -- The galaxy around the played star system: other systems as nodes, and
    -- the jump-gate network between them (Modules/Navigation). Only the
    -- played system is generated in full; the others are names, seeds and
    -- positions until something travels there.
    galaxy = {
        systemCount       = { min = 10, max = 16 }, -- including the played system
        -- Nodes closer than this fraction of the universe radius are re-rolled
        -- (up to `placementTries` times), so systems don't clump.
        minSeparation     = 0.25,
        placementTries    = 30,
        -- On top of the spanning tree that keeps every system reachable: links
        -- to each system's nearest neighbours, while both ends have room.
        nearestLinks      = 2,
        maxLinksPerSystem = 4,
        -- A neighbour farther than this many times the system's nearest one
        -- gets no extra link (keeps the graph local; the tree still links it).
        maxLinkStretch    = 2.5,
        -- The star-system ruleset of each system other than the one the game
        -- started in (which is the scenario's), picked by weight from the
        -- system's seed. Standard systems need far more GPU memory.
        rulesets = {
            { name = "SinglePlanetWithBelt",       weight = 4 },
            { name = "StandardSolarSystem",        weight = 2 },
            { name = "StandardBinarySolarSystem",  weight = 1 },
            { name = "StandardTrinarySolarSystem", weight = 1 },
        },
    },

    -- Jump gates in the played system, one per link of its node.
    jumpGates = {
        -- How many of the system's points of interest (planets, asteroid
        -- belts) the gates gather at; the gates are shared out between them.
        pointsOfInterest = { min = 1, max = 2 },
        radius           = 0.4,  -- ring radius in game units (~4 km)
        -- Distance from a planet, in planet radii (stations sit at 2.5).
        planetDistance   = 4.0,
        -- Distance from an asteroid belt's centre line, in belt widths.
        beltDistance     = 0.75,
        -- Distance from the star, in star radii, when the system has no
        -- planets or belts.
        starDistance     = 6.0,
        -- Up or down from the point of interest's plane, as a fraction of
        -- the distance above.
        heightJitter     = 0.15,
        -- J jumps through the nearest gate within this distance of its
        -- centre; a course's autopilot jumps on its own once this close.
        activationRange  = 8.0,
        -- Where a jump arrives: this many ring radii out from the arrival
        -- gate, on the side away from the system the ship came from.
        arrivalDistance  = 4.0,
        -- Seconds the screen fades back in after a jump.
        fadeTime         = 1.0,
    },

    -- Factions (Modules/NPC/Factions.lua): a faction is also the ship's
    -- Targetable team. `hostileTo`: the factions its ships attack.
    factions = {
        player   = { name = "You",      color = { 0.3, 1.0, 0.45 }, hostileTo = { pirate = true } },
        security = { name = "Security", color = { 0.35, 0.65, 1.0 }, hostileTo = { pirate = true } },
        trader   = { name = "Trader",   color = { 0.85, 0.85, 0.7 }, hostileTo = {} },
        pirate   = { name = "Pirate",   color = { 1.0, 0.3, 0.25 },
                     hostileTo = { player = true, security = true, trader = true } },
    },

    -- How dangerous each star system is (galaxy map colour, arrival banner,
    -- and which NPCs it has). The first system is `homeLevel`; the others
    -- are picked by weight, with the weights moving toward the dangerous end
    -- with jumps from home (`distanceBias` per jump).
    hostility = {
        homeLevel    = 1,
        distanceBias = 0.6,
        levels = {
            { name = "Secure", description = "Security patrols. Pirates are rarely seen.",    color = { 0.35, 0.75, 1.0 }, weight = 3,
              npcs = { security = 3, trader = 3, pirate = 0 } },
            { name = "Guarded", description = "Patrolled. Expect the odd pirate.",   color = { 0.45, 0.9, 0.5 },  weight = 3,
              npcs = { security = 2, trader = 2, pirate = 1 } },
            { name = "Contested", description = "Pirates and security fight over this system.", color = { 1.0, 0.75, 0.25 }, weight = 2,
              npcs = { security = 1, trader = 1, pirate = 3 } },
            { name = "Lawless", description = "No security. Pirates attack on sight.",   color = { 1.0, 0.3, 0.25 },  weight = 1,
              npcs = { security = 0, trader = 1, pirate = 5 } },
        },
    },

    -- NPC ships (Modules/NPC). Speeds in game units/s (the player's ship
    -- tops out at ~0.9 without boost), accel in units/s², turn as a rate.
    npc = {
        pirate = {
            gunship = true, scale = 0.025, sizeClass = "medium",
            maxHealth = 500, maxShield = 80, shieldRegen = 6,
            maxSpeed = 0.7, accel = 0.25, turnRate = 1.2,
            detectRange = 6.0, -- looks for prey this close
        },
        security = {
            gunship = true, scale = 0.03, sizeClass = "medium",
            maxHealth = 700, maxShield = 150, shieldRegen = 10,
            maxSpeed = 0.6, accel = 0.2, turnRate = 1.0,
            detectRange = 7.0,
        },
        trader = {
            gunship = false, hull = 3, scale = 0.035, sizeClass = "medium",
            maxHealth = 400, maxShield = 60, shieldRegen = 4,
            maxSpeed = 0.4, accel = 0.12, turnRate = 0.8,
            fleeRange = 3.0, -- runs from pirates this close
        },
        -- An NPC whose last order ended keeps the system busy: every
        -- `replenishInterval` seconds one missing ship (below the level's
        -- count) arrives through a gate.
        replenishInterval = 45,
        -- A destroyed NPC's wreck goes after its explosion.
        wreckTime = 3.0,
        -- How far apart a system's NPCs start, and from their spot.
        spawnSpread = 1.5,
    },

    -- The player's armed ship in the travel scenarios (those with stations):
    -- a small gunship whose turrets engage hostile ships by themselves.
    playerGunship = {
        enabled = true,
        scale = 0.02,
        maxHealth = 1500, maxShield = 300, shieldRegen = 15,
        -- Turning torque multiplier: "auto" keeps the fighter's turning feel
        -- (scaled by (radius / fighter radius)², see ShipFlightSystem); a
        -- number sets it directly, if the gunship turns too fast or slow.
        turnScale = "auto",
    },

    autoPilot = {
        arrivalRange      = 500,    -- distance to target to consider arrived
        travelDriveDelay  = 5.0,    -- seconds before auto-engaging travel drive
        enableTravelDrive = true,   -- auto-engage travel drive during autopilot
    },

    chaseCamera = {
        minRadius      = 0.5,    -- Min zoom (multiplier on ship radius)
        maxRadius      = 8.0,    -- Max zoom
        defaultRadius  = 1.0,    -- Default zoom
        zoomSpeed      = 0.15,   -- Zoom per scroll tick
    },

    -- Orbit camera (chase view of the player ship)
    orbitCamera = {
        distance     = 0.015,    -- Default follow distance
        minDistance  = 0.005,
        maxDistance  = 5.0,
        smoothing    = 0.1,
        zoomSpeed    = 0.01,
        zoomRatio    = 0.15,     -- Each zoom step changes the distance by this fraction (overrides zoomSpeed)
    },

    -- Free camera (unattached fly-around view)
    freeCamera = {
        moveSpeed      = 1.0,
        fastMultiplier = 100.0,
        mouseSensitivity = 0.003,
    },

    -- Texture quality (cube map resolution for planet/moon surfaces). The game sets
    -- both from the Texture Quality setting (`UserSettings.applyTextureQuality`).
    planetTexRes       = 1024,
    moonTexRes         = 1024,

    dispoMin               = -1.0,
    dispoNeutral           = 0.0,
    dispoMax               = 1.0,
    dispoHostileThreshold  = -0.3333333,
    dispoFriendlyThreshold = 0.3333333,
    dispoName              = { "hostile",
        "neutral",
        "friendly" },
}
