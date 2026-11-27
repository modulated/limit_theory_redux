-- Types --
require("Shared.Definitions.ItemDefs")
local Items = require("Shared.Registries.Items")
local Hulls = require("Shared.Registries.Hulls")

-- The hulls the player can fly. Each one is a `Constructs` item: a shipyard
-- sells it, a drydock can build it, and swapping to it is a trade of one hull
-- for another, so the ship you fly is a thing you own.
--
-- A hull decides three things: the weapon mounts it has (how many, where, and
-- what size class each takes), how many module slots it carries, and the
-- stats it starts from. Everything else about a ship -- what is in those
-- mounts and slots -- is the fit (res/data/modules.toml).
--
-- `sockets` is the socket list the armed-ship builder generates mounts from
-- (Modules/NPC/Managers/GunshipRecipe.lua passes it through). Each entry is a
-- mirrored pair, so two mounts: `z` is how far forward along the hull and
-- `xFactor` how far out to the side.
--
-- Ids are permanent: a saved game records which hull is being flown.

local Weapon = Enums.Weapon
local Size = Weapon.MountSizeClass
local Pair = Weapon.MountPairId
local Zone = Weapon.MountZone
local Band = Weapon.MountSurfaceBand
local Role = Weapon.MountRole

Hulls:add({
    id = 1,
    name = "Solo Hull",
    description = "A single-seat frame: quick, cheap, and thin everywhere.",
    item = Items.Constructs.ShipHullSolo,
    moduleSlots = 3,
    scale = 0.011,
    stats = { maxHealth = 420, maxShield = 80, shieldRegen = 4 },
    capacitor = { maxCharge = 22.0, chargeRate = 16.0 },
    sockets = {
        {
            pairId = Pair.ForeOuter, zone = Zone.Fore, surfaceBand = Band.Top,
            mountSizeClass = Size.M, mountRole = Role.Line, z = 0.95, xFactor = 0.72,
        },
        {
            pairId = Pair.MidPd, zone = Zone.Mid, surfaceBand = Band.Top,
            mountSizeClass = Size.SM, mountRole = Role.PointDefense, z = 0.0, xFactor = 0.7,
        },
    },
})

Hulls:add({
    id = 2,
    name = "Small Hull",
    description = "The gunship: three pairs of mounts and room to carry something.",
    item = Items.Constructs.ShipHullSmall,
    moduleSlots = 4,
    scale = 0.014,
    stats = { maxHealth = 700, maxShield = 160, shieldRegen = 6 },
    capacitor = { maxCharge = 30.0, chargeRate = 20.0 },
    sockets = {
        {
            pairId = Pair.ForeOuter, zone = Zone.Fore, surfaceBand = Band.Top,
            mountSizeClass = Size.M, mountRole = Role.Line, z = 0.95, xFactor = 0.78,
        },
        {
            pairId = Pair.MidOuter, zone = Zone.Mid, surfaceBand = Band.Top,
            mountSizeClass = Size.M, mountRole = Role.Line, z = 0.10, xFactor = 0.88,
        },
        {
            pairId = Pair.MidPd, zone = Zone.Mid, surfaceBand = Band.Top,
            mountSizeClass = Size.SM, mountRole = Role.PointDefense, z = 0.0, xFactor = 0.78,
        },
    },
})

Hulls:add({
    id = 3,
    name = "Compact Hull",
    description = "Heavier, slower, and the first hull that takes a bay weapon.",
    item = Items.Constructs.ShipHullCompact,
    moduleSlots = 5,
    scale = 0.019,
    stats = { maxHealth = 1200, maxShield = 300, shieldRegen = 9 },
    capacitor = { maxCharge = 48.0, chargeRate = 28.0 },
    sockets = {
        {
            pairId = Pair.ForeHeavy, zone = Zone.Fore, surfaceBand = Band.Top,
            mountSizeClass = Size.L, mountRole = Role.Heavy, z = 0.88, xFactor = 0.55,
        },
        {
            pairId = Pair.ForeOuter, zone = Zone.Fore, surfaceBand = Band.Top,
            mountSizeClass = Size.M, mountRole = Role.Line, z = 0.95, xFactor = 0.84,
        },
        {
            pairId = Pair.MidOuter, zone = Zone.Mid, surfaceBand = Band.Top,
            mountSizeClass = Size.M, mountRole = Role.Line, z = 0.10, xFactor = 0.9,
        },
        {
            pairId = Pair.MidPd, zone = Zone.Mid, surfaceBand = Band.Top,
            mountSizeClass = Size.SM, mountRole = Role.PointDefense, z = 0.0, xFactor = 0.8,
        },
    },
})

Hulls:add({
    id = 4,
    name = "Medium Hull",
    description = "A warship's frame: two bays, four guns, and the turning of a barge.",
    item = Items.Constructs.ShipHullMedium,
    moduleSlots = 6,
    scale = 0.026,
    stats = { maxHealth = 2200, maxShield = 600, shieldRegen = 14 },
    capacitor = { maxCharge = 70.0, chargeRate = 38.0 },
    sockets = {
        {
            pairId = Pair.ForeHeavy, zone = Zone.Fore, surfaceBand = Band.Top,
            mountSizeClass = Size.L, mountRole = Role.Heavy, z = 0.9, xFactor = 0.5,
        },
        {
            pairId = Pair.MidHeavy, zone = Zone.Mid, surfaceBand = Band.Top,
            mountSizeClass = Size.L, mountRole = Role.Heavy, z = 0.2, xFactor = 0.62,
        },
        {
            pairId = Pair.ForeOuter, zone = Zone.Fore, surfaceBand = Band.Top,
            mountSizeClass = Size.M, mountRole = Role.Line, z = 0.96, xFactor = 0.86,
        },
        {
            pairId = Pair.MidOuter, zone = Zone.Mid, surfaceBand = Band.Top,
            mountSizeClass = Size.M, mountRole = Role.Line, z = 0.12, xFactor = 0.92,
        },
        {
            pairId = Pair.MidPd, zone = Zone.Mid, surfaceBand = Band.Top,
            mountSizeClass = Size.SM, mountRole = Role.PointDefense, z = 0.0, xFactor = 0.82,
        },
    },
})

return Hulls

-- The next free hull id: 5
