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

--- An ArmedShipBuilder recipe for a gunship of `faction`.
---@param seed integer
---@param faction string
---@param stats { maxHealth: number, maxShield: number, shieldRegen: number }
---@return table recipe
function GunshipRecipe.build(seed, faction, stats)
    local laser = LASER_BY_FACTION[faction] or LASER_BY_FACTION.pirate
    return {
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
                        sockets = {
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
                    supportedSizeClasses = { MountSizeClass.SM, MountSizeClass.M },
                    maxCharge = 30.0,
                    chargeRate = 20.0,
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
            },
        },
    }
end

return GunshipRecipe
