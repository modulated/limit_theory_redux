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

            -- Steering is a rate request, not an acceleration one
            -- (ShipFlightSystem.applySteering): the fastest the ship will
            -- turn, in radians a second, and how hard it pushes to get there
            -- (torque = clamp(rate error x gain) x torque). The rate is what
            -- stops a held turn from winding the ship up into a spin; the
            -- gain is the responsiveness -- higher snaps to the rate, lower
            -- eases into it.
            maxTurnRate    = 1.8,
            turnRateGain   = 6.0,
            -- How fast the turn rate can change (rad/s²; fitted modules
            -- scale it), and the roll rate as a share of maxTurnRate. The
            -- rate is set on the body directly, so the hull's size and
            -- shape do not change how it handles.
            maxTurnAccel   = 8.0,
            rollRateShare  = 0.6,

            -- How the mouse steers (chase and first person).
            --   "virtual": a virtual joystick. Moving the mouse moves a stick
            --     (shown on the HUD); how far it is from the centre is the
            --     turn rate, so centred is straight ahead and the same place
            --     is always the same turn. It stays where it is left. Full
            --     deflection is `stickRadius` of the window height of mouse
            --     travel; within `stickDeadZone` of the centre the ship holds
            --     its heading. Reads only the mouse's movement, so it works
            --     with a confined cursor and over remote desktop.
            --   "movement": push the mouse to hold a turn, which decays back
            --     to straight when the mouse stops (`steeringDecay`).
            --   "cursor": the OS cursor's distance from the middle of the
            --     screen is the turn rate (chase only; needs a cursor that
            --     stays where it is put).
            chaseSteering  = "virtual",
            stickRadius    = 0.22,
            stickDeadZone  = 0.08,
            steeringDecay  = 4.0,

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

        -- The drive drops out by itself just short of a planet, moon or star
        -- in the ship's path (TravelDriveSystem): far enough out that the
        -- ship, coasting down under its drag, stops clear of the surface.
        -- Smaller things -- stations, rocks, ships -- the ship passes
        -- through while the drive is engaged.
        dropOut = {
            margin   = 0.25, -- clearance kept above the surface, in radii
            reaction = 0.4,  -- seconds of travel allowed on top of the coast
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

    -- The jump drive (a capital's C module, res/data/modules.toml): from the
    -- galaxy map, to any system within its reach (the fit's jumpRange, in
    -- shares of the galaxy's radius), gate or no gate. It charges for
    -- `spoolTime` seconds (docking calls it off), burns `fuelPerRadius` of
    -- the fuel item per galaxy radius jumped (at least `minFuel`) from the
    -- hold, and needs `cooldown` seconds before it can jump again. The ship
    -- arrives in the system's open space, not at a gate.
    jumpDrive = {
        spoolTime     = 10,
        cooldown      = 120,
        fuelItem      = "Radioactive Isotopes",
        fuelPerRadius = 120,
        minFuel       = 10,
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
        -- Traders' own ships are unarmed; their mercenaries fight pirates
        trader   = { name = "Trader",   color = { 0.85, 0.85, 0.7 }, hostileTo = { pirate = true } },
        pirate   = { name = "Pirate",   color = { 1.0, 0.3, 0.25 },
                     hostileTo = { player = true, security = true, trader = true } },
    },

    -- The player's standing with each faction (Modules/NPC/Reputation.lua),
    -- on Legacy's disposition scale (dispoMin..dispoMax, thresholds below).
    reputation = {
        initial = { security = 0.2, trader = 0.3, pirate = -0.6 },
        killPenalty    = 0.25, -- destroying a ship of a faction
        enemyKillBonus = 0.05, -- ...to each faction hostile to it
        damagePenalty  = 0.01, -- per hit on a ship of a faction
        -- An attack asks before it can turn a faction hostile: when the next
        -- kill plus this many hits would cross Config.game.dispoHostileThreshold
        hostilityWarningHits = 3,
    },

    -- How dangerous each star system is (galaxy map colour, arrival banner,
    -- and which NPCs it has: ships per role of Config.game.npc.roles; escorts
    -- come with the ships they guard). The first system is `homeLevel`; the
    -- others are picked by weight, with the weights moving toward the
    -- dangerous end with jumps from home (`distanceBias` per jump).
    hostility = {
        homeLevel    = 1,
        distanceBias = 0.6,
        levels = {
            -- Level 0, below the rest: only a start asks for it (the Sandbox's
            -- home system). Index 0 keeps it out of the random picks for the
            -- other systems, which go through levels 1 and up.
            [0] = { name = "Peaceful", description = "Quiet space. The odd pirate scout, easily seen off.",
              color = { 0.55, 0.95, 0.85 }, weight = 0,
              npcs = { security = 3, trader = 6, pirate = 0, pirateScout = 2, pirateMerchant = 0,
                       miner = 6, worker = 6 } },
            { name = "Secure", description = "Security patrols. Pirates are rarely seen.",
              color = { 0.35, 0.75, 1.0 }, weight = 3,
              npcs = { security = 3, trader = 3, pirate = 0, pirateMerchant = 0, miner = 2, worker = 4 } },
            { name = "Guarded", description = "Patrolled. Expect the odd pirate.",
              color = { 0.45, 0.9, 0.5 },  weight = 3,
              npcs = { security = 2, trader = 2, pirate = 1, pirateMerchant = 0, miner = 2, worker = 3 } },
            { name = "Contested", description = "Pirates and security fight over this system.",
              color = { 1.0, 0.75, 0.25 }, weight = 2,
              npcs = { security = 1, trader = 1, pirate = 3, pirateMerchant = 1, miner = 1, worker = 1 } },
            { name = "Lawless", description = "No security. Pirates attack on sight.",
              color = { 1.0, 0.3, 0.25 },  weight = 1,
              npcs = { security = 0, trader = 1, pirate = 4, pirateMerchant = 2, miner = 0, worker = 0 } },
        },
    },

    -- NPC ships (Modules/NPC), by role: each role is a faction's kind of ship
    -- with its job (NPC/Jobs/Think). Speeds in game units/s (the player's
    -- ship tops out at ~0.9 without boost), accel in units/s², turn as a rate.
    --   faction     Config.game.factions entry (who it fights, its colour)
    --   label       shown on the ship and the maps
    --   gunship     armed (GunshipRecipe); otherwise an unarmed hauler
    --   detectRange armed ships attack hostiles this close
    --   fleeFrom, fleeRange   haulers run from these factions this close
    --   stops       haulers' trade stops: "stations" or "hideouts" (gates, belts, planets)
    --   escorts     {min, max, role}: ships of `role` guarding each one
    --   sensor      detection range multiplier (Legacy Sensor rating; default 1)
    --   job         "mine" for miners, "work" for workers; otherwise by role (Jobs/Think)
    --   cargo       units a hauler's hold takes (miners)
    npc = {
        roles = {
            security = {
                faction = "security", label = "Security",
                gunship = true, scale = 0.03, sizeClass = "medium",
                maxHealth = 700, maxShield = 150, shieldRegen = 10,
                maxSpeed = 0.6, accel = 0.2, turnRate = 1.0,
                detectRange = 7.0, sensor = 1.25,
            },
            miner = {
                faction = "trader", label = "Miner", job = "mine",
                gunship = false, hull = 3, scale = 0.03, sizeClass = "medium",
                maxHealth = 350, maxShield = 50, shieldRegen = 4,
                maxSpeed = 0.35, accel = 0.12, turnRate = 0.8,
                fleeFrom = { "pirate" }, fleeRange = 3.0,
                cargo = 12,
                escorts = { min = 0, max = 1, role = "mercenary" },
            },
            worker = {
                -- The hands that keep the stations' factory floors running:
                -- they fly in, dock, work a shift and move on (Jobs/Work).
                faction = "trader", label = "Worker", job = "work",
                gunship = false, hull = 3, scale = 0.022, sizeClass = "small",
                maxHealth = 250, maxShield = 40, shieldRegen = 4,
                maxSpeed = 0.4, accel = 0.14, turnRate = 1.0,
                fleeFrom = { "pirate" }, fleeRange = 3.0,
                escorts = { min = 0, max = 1, role = "mercenary" },
            },
            trader = {
                faction = "trader", label = "Trader",
                gunship = false, hull = 3, scale = 0.035, sizeClass = "medium",
                maxHealth = 400, maxShield = 60, shieldRegen = 4,
                maxSpeed = 0.4, accel = 0.12, turnRate = 0.8,
                fleeFrom = { "pirate" }, fleeRange = 3.0,
                stops = "stations",
                escorts = { min = 0, max = 2, role = "mercenary" },
            },
            mercenary = {
                faction = "trader", label = "Mercenary",
                gunship = true, scale = 0.022, sizeClass = "medium",
                maxHealth = 450, maxShield = 100, shieldRegen = 8,
                -- A little faster than the haulers, to keep up and catch up
                maxSpeed = 0.55, accel = 0.25, turnRate = 1.3,
                detectRange = 5.0,
                -- Guards stay this close to their charge (chasing no further)
                leash = 4.0,
            },
            pirate = {
                faction = "pirate", label = "Pirate",
                gunship = true, scale = 0.025, sizeClass = "medium",
                maxHealth = 500, maxShield = 80, shieldRegen = 6,
                maxSpeed = 0.7, accel = 0.25, turnRate = 1.2,
                detectRange = 6.0,
            },
            -- The player's own (Modules/Economy/Managers/PlayerForces.lua):
            -- an unmanned gunship launched from an outpost, and a gun for hire
            drone = {
                faction = "player", label = "Drone",
                gunship = true, scale = 0.022, sizeClass = "small",
                maxHealth = 650, maxShield = 220, shieldRegen = 12,
                maxSpeed = 0.75, accel = 0.3, turnRate = 1.4,
                detectRange = 6.0, sensor = 1.2,
            },
            hiredMercenary = {
                faction = "player", label = "Mercenary",
                gunship = true, scale = 0.025, sizeClass = "medium",
                maxHealth = 500, maxShield = 120, shieldRegen = 8,
                maxSpeed = 0.6, accel = 0.25, turnRate = 1.2,
                detectRange = 5.5,
            },
            -- A green pirate in a light ship: what a peaceful system sees
            pirateScout = {
                faction = "pirate", label = "Pirate scout",
                gunship = true, scale = 0.02, sizeClass = "small",
                maxHealth = 220, maxShield = 30, shieldRegen = 3,
                maxSpeed = 0.55, accel = 0.2, turnRate = 1.0,
                detectRange = 3.5,
            },
            pirateMerchant = {
                faction = "pirate", label = "Pirate merchant",
                gunship = false, hull = 3, scale = 0.03, sizeClass = "medium",
                maxHealth = 350, maxShield = 40, shieldRegen = 3,
                maxSpeed = 0.45, accel = 0.14, turnRate = 0.9,
                fleeFrom = { "security", "player" }, fleeRange = 3.5,
                stops = "hideouts",
                escorts = { min = 0, max = 1, role = "pirate" },
            },
        },
        -- Every `replenishInterval` seconds one missing ship (below the
        -- level's count) arrives through a gate, with its escorts.
        replenishInterval = 45,
        -- A destroyed NPC's wreck goes after its explosion.
        wreckTime = 3.0,
        -- How far a system's NPCs start from their spot.
        spawnSpread = 1.5,
    },

    -- The player's targets (LimitTheoryRedux:maxTargets, TargetsPanel): how
    -- many the ship can hold, base + perMount for each weapon or tool mount,
    -- kept within min..cap. The guns spread over the ones being attacked.
    targeting = {
        base     = 1,
        perMount = 1,
        min      = 2,
        cap      = 8,
    },

    -- Mining (Modules/NPC/Managers/MiningField.lua, Jobs/Mining.lua): rocks
    -- picked from each belt, their ore by weight, units by rock size.
    mining = {
        rocksPerBelt    = 24,
        unitsPerScale   = 0.004, -- a rock of this scale holds one unit
        regrowPerSecond = 0.02,  -- units a rock grows back per second
        timePerUnit     = 3.0,   -- seconds a miner takes per unit
        sellTime        = 8.0,   -- seconds docked to sell the hold
        playerRange     = 0.9,   -- how close the player's ship mines a rock from (beyond its surface)
        rockRadiusScale = 1.4,   -- a rock's surface reaches this far out, in its scale (the
                                 -- meshes are lumpy: well past a sphere of radius `scale`)
        playerTimePerUnit = 3.0, -- seconds the player's laser takes per unit (as the NPC miners)
        playerScanInterval = 0.3, -- seconds between looks for a rock in reach
        -- What the rocks hold is data: res/data/ores.toml
    },

    -- Credits (Modules/Economy/Managers/PlayerWallet.lua): bounties and repairs.
    -- A bounty is paid for the killing blow on a ship whose faction the
    -- `bountyIssuer` is hostile to (an outlaw), by the ship's role.
    -- The economies of the systems the player is not in, kept going cheaply
    -- (Modules/Economy/Managers/GalaxyEconomy.lua): every `interval` seconds
    -- each station of a visited system runs its lines off its own stock,
    -- takes in imports, and has its shelves drift toward their targets over
    -- `settleTime` seconds (+-`noise` of the target, so prices wander). At
    -- most `maxCatchUp` seconds are made up at a time.
    galaxyEconomy = {
        interval       = 60,
        settleTime     = 3600,
        noise          = 0.15,
        maxCatchUp     = 6 * 3600,
        maxRunsPerStep = 200,
    },

    economy = {
        startingCredits = 1000,
        hullRepairCost  = 2.0,   -- credits per point of hull; shields recharge free
        bountyIssuer    = "security",
        bounties        = { pirate = 600, pirateMerchant = 300, pirateScout = 200 },
        defaultBounty   = 250,   -- an outlaw of a role not listed
    },

    -- Station shops (Modules/Economy/Systems/StationTradeSystem.lua). A
    -- station's price for a thing is its equilibrium price (ItemDefs) scaled
    -- by how far its shelves are from the target it likes to keep, so what
    -- its factories make gets cheaper and what they eat gets dearer.
    --
    -- These were set with `luajit tools/economy-sim.lua --seeds 8 --prospector
    -- --trader`, which runs this economy headless. At these values a day of
    -- mining pays about 1,600 credits an hour in a median system and a day of
    -- hauling about 900, with a long tail upward in systems whose refineries
    -- happen to want what the belts hold. Retune with the tool, not by eye.
    trade = {
        targetValue     = 12000, -- credits' worth of each thing a station likes to keep
        minTargetUnits  = 4,     -- ...but at least this many units of it
        priceSoftness   = 25,    -- units added to both sides of the scarcity ratio
        minScarcity     = 0.35,  -- a glut never takes the price below this much of equilibrium
        maxScarcity     = 2.5,   -- ...nor a shortage above this much
        spread          = 0.09,  -- the house's cut either side of the price
        unwantedFactor  = 0.5,   -- what a station pays for something it has no use for
        buyCeiling      = 4.0,   -- a station stops buying a thing at this many targets
        defaultPrice    = 100,   -- for an item with no equilibrium price
        startStockMin   = 0.4,   -- a new station opens with this fraction of target...
        startStockMax   = 1.4,   -- ...to this much
        importPerSecond = 0.02,  -- units a station imports per second of what it cannot make
        importFloor     = 0.35,  -- ...up to this fraction of its target, and no further
    },

    -- The market (Modules/Economy/Systems/MarketSystem.lua). Every station
    -- has an order book and a price is whatever someone will pay: a station
    -- bids for what its lines need and offers what it is sitting on, priced
    -- from `trade` below (its own opinion of what things are worth), and
    -- everyone else trades against those orders or posts their own. A trade
    -- happens at the price of the order that was already there, so
    -- undercutting works.
    market = {
        brokerFee      = 0.02,   -- of an order's value, to place it (not refunded)
        salesTax       = 0.03,   -- of what a sale brings in
        orderLifetime  = 3600.0, -- game seconds an order stands for
        refreshInterval = 45.0,  -- game seconds between a station re-posting its orders
        stationMargin  = 0.08,   -- how far a station's own orders sit either side of its valuation
        orderShare     = 0.5,    -- the share of its shortfall or surplus it puts on the book at once
        reserveShare   = 0.5,    -- the share of its target it keeps back rather than offering
        scrapFactor    = 0.25,   -- what a station pays for something nobody bid for
        remoteJumps    = 3,      -- jumps away whose books can still be read (a module may raise it)
    },

    -- Stations making things (Modules/Economy/Systems/ProductionSystem.lua).
    -- The recipes are res/data/recipes.toml; `timeScale`
    -- compresses Legacy's durations (4 s to 4 hours) into a session.
    production = {
        timeScale      = 20.0, -- game seconds of production per real second
        stockCeiling   = 3.0,  -- a line stops once its outputs pile past this many targets
        maxLineInputValue = 6000, -- credits' worth of input per run a station can keep up with
        -- Hands. A line runs only when it has `workersPerLine` of them: a
        -- station's own standing crew plus the workers docked there
        -- (Jobs/Work). A Lawless system spawns none, so its factories stand
        -- idle until someone flies workers in.
        workersPerLine = 1,
        stationCrew    = 2,     -- hands a station has of its own
        shiftSeconds   = 240.0, -- how long a worker stays docked
        linesMin       = 1,    -- recipes besides the powerplant
        linesMax       = 2,
        refineryChance = 0.6,  -- a line is a refinery this often, else a factory
        solarChance    = 0.75, -- the powerplant is a solar array this often (it needs no fuel)
        localRefineryChance = 0.85, -- a refinery line runs on a locally mined ore this often
        drydockChance  = 0.25, -- the chance the one allowed station also builds hulls
    },

    -- Fitting out a ship (Modules/Constructs/Systems/ShipFittingSystem.lua).
    -- Weapons go in the hull's mounts, modules in its slots; every one of
    -- them is an item bought or made (res/data/modules.toml).
    -- Refitting is free, but only at a station, out of its hangar.
    fitting = {
        startingHull  = "Small Hull", -- the hull a new game flies (Shared/Definitions/HullDefs.lua)
        -- What a new game's first ship comes fitted with, by fitting name.
        -- Every ship after it starts empty: a fit belongs to the ship it is
        -- on (Modules/Constructs/Managers/PlayerFleet.lua).
        startingModules = { "Shield Capacitor" },
        -- ...and on its mounts (the mining laser is a tool on a mount)
        startingWeapons = { "Mining Laser" },
    },

    -- The player's own industry (Modules/Economy/Managers/PlayerFactories.lua):
    -- a hangar at every station used, and lines rented from the station's own
    -- floor. A rented line takes its inputs from the hangar and puts the
    -- outputs back in it; the station takes a cut of each finished run.
    factory = {
        rentableLines     = 2,     -- lines a station will rent out
        rentChoices       = 6,     -- recipes it offers to rent them for
        rentShare         = 0.15,  -- the station's cut of what a run is worth
        rentMinFee        = 5,     -- ...but never less than this
        hangarCapacity    = 20000, -- mass a hangar holds (the ship's hold is 2,400)
        offlineCatchUpMax = 3600,  -- seconds of production credited on coming back
    },

    -- What the player's ship can carry (mass, Modules/Economy/Components/StockComponent).
    cargo = {
        holdCapacity = 2400, -- the gunship's hold: ~400 units of ore
    },

    -- Docking (F): stations belong to `owner` and take ships whose faction
    -- it isn't hostile to (for the player: standing with the owner).
    docking = {
        owner       = "security",
        rangeFactor = 4.0, -- dock from this many station radii away
    },

    -- The player's cloak (X; Legacy Elements/Components/Cloak): while it is
    -- on, weapons can't lock on, NPCs notice the ship only at a fraction of
    -- their range, and the ship's own turrets hold fire. It runs on its own
    -- charge, which drains while cloaked and refills while not.
    cloak = {
        maxCharge      = 15.0, -- seconds of cloak when full
        rechargeRate   = 0.5,  -- seconds of cloak regained per second
        minCharge      = 3.0,  -- needed to switch it on
        detection      = 0.2,  -- NPCs see a cloaked ship this fraction as far
    },

    -- The player's own stations (Modules/Economy/Managers/PlayerStations.lua).
    -- Each kind is deployed from its kit; all have a hangar, a market whose
    -- orders are the owner's (NPCs that are not hostile to the player trade
    -- there), and the owner's own production lines in its specialisation.
    outposts = {
        kinds = {
            refinery = {
                name = "Refinery Outpost", kit = "RefineryOutpostKit",
                classes = { "Refinery", "Powerplant" }, lines = 4,
                description = "Refines ore and makes energy: four lines of its own.",
            },
            manufacturing = {
                name = "Manufacturing Outpost", kit = "ManufacturingOutpostKit",
                classes = { "Factory", "Drydock" }, lines = 4,
                description = "Builds parts, modules, weapons and hulls: four lines of its own.",
            },
            trading = {
                name = "Trading Post", kit = "SpaceStationSmall",
                classes = {}, lines = 0,
                description = "A market and storage, and nothing else to run.",
            },
        },
        -- The order the kinds are offered in
        order = { "refinery", "manufacturing", "trading" },
        -- Where they may stand: slots on the ring generated stations sit on
        -- around each planet, and along each asteroid belt
        orbitSlots = 6,
        beltSlots = 8,
        -- How close the ship must be to a slot to deploy there, and how far a
        -- slot must be from any other station or gate to be free (game units)
        deployRange = 4.0,
        minSpacing = 1.2,
        -- The market: miners sell into the owner's bids for their ore at or
        -- above this share of its base price (they go elsewhere for less);
        -- traders buy from the owner's listings at up to this share of the
        -- base price, spending up to `traderBudget` a visit
        minerMinPrice = 0.6,
        traderMaxMarkup = 1.3,
        traderBudget = 20000,
        -- An outpost's size, as a share of a generated station's
        scale = 0.8,
        -- Its defences: an armed platform beside it, in the player's colours,
        -- that engages whatever the player is hostile to. The outpost itself
        -- cannot be destroyed; the platform can. Repairs at the outpost cost
        -- the hull rate (economy.hullRepairCost), and a platform shot down
        -- costs `rebuildCost` to put back.
        defense = {
            maxHealth = 1500, maxShield = 400, shieldRegen = 12,
            scale = 0.04, sizeClass = "large",
            offset = 2.2,         -- from the outpost's centre, in its radii
            rebuildCost = 60000,
        },
    },

    -- Sensors (LimitTheoryRedux:mapNpcs): a ship within `range` game units
    -- (10 km each; times the fitted scanRange stat) is identified on the maps,
    -- the overview and in space. Beyond it, it is only a signature: a marker at
    -- a rough position (off by `noiseShare` of the distance, at most
    -- `maxNoise`, drawn afresh every `refresh` seconds) with a strength by
    -- hull size, and no name or faction -- something to hunt down.
    --
    -- How loud a ship is (NpcSystem:loudness, 0..1: its size, and firing,
    -- mining, running hard; a pirate lying in wait among the rocks is quiet)
    -- scales all three: it is identified within range x (0.6 + 0.8 x loud),
    -- shows as a signature at all within detectRange x (0.25 + loud), and is
    -- placed off by noiseShare x (1.5 - loud) of the distance. The fit's
    -- scanRange widens both ranges, signatureRange the second,
    -- signatureAccuracy divides the error.
    --
    -- To scale: 1 AU is about 15 million game units, so these are a planet's
    -- neighbourhood (identify, ~1M km) and a good part of the system (detect,
    -- ~3 AU for an ordinary ship, ~1.4 AU for a pirate hiding in a field).
    sensors = {
        range       = 1.0e5,  -- 1M km
        detectRange = 6.0e7,  -- 4 AU
        noiseShare  = 0.10,
        maxNoise    = 1.0e6,  -- 10M km
        refresh     = 5,
        markers     = 6,   -- signatures marked at the screen's edge, nearest first
        -- Loudness under each threshold reads as this word
        strength    = { { 0.25, "Faint" }, { 0.5, "Moderate" }, { 0.8, "Strong" }, { 9, "Loud" } },
    },

    -- The stations' bounty board (Modules/Economy/Managers/BountyBoard.lua):
    -- named pirates in the system, at this many times their usual bounty
    bounties = {
        maxOffers        = 3,
        maxContracts     = 3,
        rewardMultiplier = 3,
    },

    -- The action bar (Modules/Constructs/Managers/ActionBar.lua): how many
    -- slots, on the number keys from 1
    actionBar = {
        slots = 8,
    },

    -- What wrecks leave (Modules/Economy/Systems/LootSystem.lua; what is in
    -- them: res/data/loot.toml). The player's ship draws canisters in from
    -- `tractorRange` and loads them at `collectRange` (game units).
    loot = {
        lifetime            = 300,   -- seconds a canister floats before it is gone
        tractorRange        = 1.5,
        collectRange        = 0.12,
        pullSpeed           = 0.6,   -- units/s at the edge of the range (3x close in)
        fullWarningInterval = 5,     -- seconds between "hold full" warnings at one canister
        scale               = 0.006,
        color               = { 1.0, 0.75, 0.25 },
        lightRadius         = 0.08,
        lightIntensity      = 2.0,
    },

    -- The ships that work for the player (Modules/Economy/Managers/
    -- PlayerForces.lua): combat drones, built (res/data/recipes.toml: the
    -- Combat Drone Drydock) and launched from an outpost's hangar, and
    -- mercenaries hired at an outpost. Each guards its home outpost or
    -- patrols all of the player's outposts in the system (the Forces tab).
    -- They fly as npc.roles.drone and npc.roles.hiredMercenary.
    forces = {
        maxPerOutpost = 6,         -- ships one outpost can be home to
        guardRadius   = 3.0,       -- how far around its outpost a guard flies
        wageInterval  = 60,        -- seconds of game time between paydays
        drone = { item = "Combat Drone", role = "drone" },
        mercenary = {
            role = "hiredMercenary",
            hireCost = 8000,       -- credits, once
            wagePerHour = 1500,    -- credits per hour of game time
        },
    },

    -- The overview (O): what is in the system, nearest first
    -- (Modules/Navigation/Systems/SystemOverview.lua,
    -- UI/HmGui/Views/Gameplay/OverviewPanel.lua).
    overview = {
        refreshInterval = 0.25, -- seconds between rebuilds of the list
        -- A belt holds thousands of rocks, so only the nearest are listed:
        -- those within this many game units (about twenty times the mining
        -- laser's reach), and no more than `maxAsteroids` of them.
        asteroidRange   = 10.0,
        maxAsteroids    = 25,
        maxRows         = 18,   -- rows in view at once; the wheel scrolls the rest
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
        -- The nearest the autopilot stops to a target, in game units (10 km
        -- each), whatever its size, unless the caller asks for closer (a
        -- dock, a gate, a deploy). Otherwise it stops at 1.5 target radii.
        minStandOff       = 0.5,
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
