--- The armed ships of the travel game: a small layered hull with three
--- weapon socket pairs, for ArmedShipBuilder. It is the Weapon Testbed's
--- capital recipe cut down (the only armed hull the game builds so far):
--- the same hull generator, socket fields, mount discovery options,
--- weapon generators and capacitor bank, with fewer and smaller mounts.
---
---     local recipe = GunshipRecipe.build(seed, "pirate")
---     local construction = ArmedShipBuilder:build(recipe, { constructManager = ..., shipConfig = {...} })
local Weapon = Enums.Weapon
local MountSurfaceBand = Weapon.MountSurfaceBand
local MountZone = Weapon.MountZone
local MountRole = Weapon.MountRole
local MountSizeClass = Weapon.MountSizeClass
local ProceduralKey = Weapon.ProceduralKey

local GunshipRecipe = {}

-- Each faction's laser colour: you see whose shots are whose
local LASER_BY_FACTION = {
    player   = { key = ProceduralKey.BurstLaserGreen, base = Weapon.Type.LaserGreen },
    security = { key = ProceduralKey.BurstLaserBlue,  base = Weapon.Type.LaserBlue },
    pirate   = { key = ProceduralKey.BurstLaser,      base = Weapon.Type.Laser },
}

--- Whether a hull has sockets bigger than M (the heavy and capital guns).
local function hasHeavySockets(hull)
    for _, socket in ipairs(hull and hull.sockets or {}) do
        local size = socket.mountSizeClass
        if size == MountSizeClass.L or size == MountSizeClass.XL
            or socket.mountRole == MountRole.Heavy or socket.mountRole == MountRole.CapitalHeavy then
            return true
        end
    end
    return false
end

--- The weapons and the capacitor bank of those sockets: plasma on L, the
--- long-charge laser on XL (the policy's rules pick them by size and role).
local function addHeavyArmament(recipe)
    local weapons = recipe.proceduralWeapons
    for _, weapon in ipairs({
        {
            key = ProceduralKey.FastPlasma,
            args = {
                family = Weapon.Family.Plasma,
                variant = Weapon.Variant.FastSmall,
                baseWeaponId = Weapon.Type.Plasma,
                mountSizeClass = MountSizeClass.L,
            },
        },
        {
            key = ProceduralKey.LongChargeXL,
            args = {
                family = Weapon.Family.Laser,
                variant = Weapon.Variant.LongCharge,
                baseWeaponId = Weapon.Type.XLLongChargeLaser,
                mountSizeClass = MountSizeClass.XL,
                fireMode = Weapon.FireMode.Volley,
                laserProfileId = Weapon.LaserProfile.Violet,
                duration = 1.10,
            },
        },
    }) do
        weapons[#weapons + 1] = weapon
    end
    local banks = recipe.capacitors.banks
    banks[#banks + 1] = {
        id = "plasma_heavy",
        groupId = Weapon.CapacitorGroup.Plasma,
        supportedSizeClasses = { MountSizeClass.SM, MountSizeClass.M,
                                 MountSizeClass.L, MountSizeClass.XL },
        maxCharge = 24.0,
        chargeRate = 6.0,
    }
end

--- An ArmedShipBuilder recipe for a gunship of `faction`.
---
--- With a `hull` (`Shared/Definitions/HullDefs.lua`) the recipe takes that
--- hull's weapon sockets and capacitor instead of the built-in gunship ones,
--- which is how the player flies something other than the starting ship. The
--- NPCs pass none and get the gunship as before.
---@param seed integer
---@param faction string
---@param stats { maxHealth: number, maxShield: number, shieldRegen: number }
---@param hull HullDefinition|nil
---@return table recipe
function GunshipRecipe.build(seed, faction, stats, hull)
    local laser = LASER_BY_FACTION[faction] or LASER_BY_FACTION.pirate
    local recipe = {
        seed = seed,
        defaultWeapon = { generatedKey = laser.key },
        ship = {
            shipType = Enums.ShipType.Capital,
            stats = {
                maxHealth = stats.maxHealth,
                engine = {},
                defense = {
                    maxHealth = stats.maxHealth,
                    maxShield = stats.maxShield or 0,
                    armor = 0,
                    shieldRegen = stats.shieldRegen or 0,
                },
            },
            config = {
                generation = {
                    id = Enums.ShipGeneration.LayeredCapital,
                    mountDecks = {
                        sockets = hull and hull.sockets or {
                            -- Main guns: forward, either side
                            {
                                pairId = Weapon.MountPairId.ForeOuter,
                                zone = MountZone.Fore,
                                surfaceBand = MountSurfaceBand.Top,
                                mountSizeClass = MountSizeClass.M,
                                mountRole = MountRole.Line,
                                z = 0.95,
                                xFactor = 0.78,
                            },
                            {
                                pairId = Weapon.MountPairId.MidOuter,
                                zone = MountZone.Mid,
                                surfaceBand = MountSurfaceBand.Top,
                                mountSizeClass = MountSizeClass.M,
                                mountRole = MountRole.Line,
                                z = 0.10,
                                xFactor = 0.88,
                            },
                            -- Point defence amidships
                            {
                                pairId = Weapon.MountPairId.MidPd,
                                zone = MountZone.Mid,
                                surfaceBand = MountSurfaceBand.Top,
                                mountSizeClass = MountSizeClass.SM,
                                mountRole = MountRole.PointDefense,
                                z = 0.00,
                                xFactor = 0.78,
                            },
                        },
                    },
                },
            },
        },
        mountDiscovery = {
            options = {
                minNormalDot = 0.35,
                mirrorTolerance = 0.0001,
                requireStructuralSockets = true,
            },
        },
        mountPlacement = {
            clearanceMultiplier = 0.04,
            minimumClearanceFraction = 0.02,
        },
        proceduralWeapons = {
            {
                key = laser.key,
                args = {
                    family = Weapon.Family.Laser,
                    variant = Weapon.Variant.ShortBurst,
                    baseWeaponId = laser.base,
                    burstCount = 3,
                    duration = 0.30,
                },
            },
            {
                key = ProceduralKey.FastBolt,
                args = {
                    family = Weapon.Family.Laser,
                    variant = Weapon.Variant.FastBolt,
                    baseWeaponId = Weapon.Type.LaserBolt,
                    burstCount = 3,
                },
            },
        },
        tracking = { tier = 2 },
        trackingComponent = {},
        control = { active = true },
        capacitors = {
            banks = {
                {
                    id = "laser_small_medium",
                    groupId = Weapon.CapacitorGroup.Laser,
                    -- A bay weapon draws from the same bank on these hulls
                    supportedSizeClasses = { MountSizeClass.SM, MountSizeClass.M,
                                             MountSizeClass.L, MountSizeClass.XL },
                    maxCharge = hull and hull.capacitor.maxCharge or 30.0,
                    chargeRate = hull and hull.capacitor.chargeRate or 20.0,
                },
            },
            policies = {
                [Weapon.FireMode.Volley] = { id = Weapon.CapacityPolicy.Burst },
                [Weapon.FireMode.Sequence] = { id = Weapon.CapacityPolicy.Sustain },
            },
        },
        targeting = {},
        loadoutPolicy = {
            mirrorPairs = true,
            allowAsymmetricOverrides = true,
            quotas = {
                [MountRole.PointDefense] = {
                    minimumPairs = 1,
                    generatedKey = ProceduralKey.FastBolt,
                },
            },
            rules = {
                {
                    when = { mountRole = MountRole.PointDefense },
                    entry = { generatedKey = ProceduralKey.FastBolt },
                },
                {
                    when = { mountRole = MountRole.Line },
                    entry = { generatedKey = laser.key },
                },
                -- Heavy sockets: the XL long-charge laser on an XL socket,
                -- plasma on the rest; a capital socket the same
                {
                    when = { mountSizeClass = MountSizeClass.XL },
                    entry = { generatedKey = ProceduralKey.LongChargeXL },
                },
                {
                    when = { mountRole = MountRole.Heavy },
                    entry = { generatedKey = ProceduralKey.FastPlasma },
                },
                {
                    when = { mountRole = MountRole.CapitalHeavy },
                    entry = { generatedKey = ProceduralKey.FastPlasma },
                },
                {
                    when = { mountRole = MountRole.Missile },
                    entry = { generatedKey = laser.key },
                },
            },
        },
    }
    if hasHeavySockets(hull) then
        addHeavyArmament(recipe)
    end
    return recipe
end

return GunshipRecipe
