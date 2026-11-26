-- Types --
local FittingDefinition = require("Shared.Types.FittingDefinition")
local Fittings = require("Shared.Registries.Fittings")
-- The fittings name items, so the item registry has to be filled first.
require("Shared.Definitions.ItemDefs")
local Items = require("Shared.Registries.Items")

-- What a ship can be fitted with: the weapons that go in its mounts and the
-- modules that go in its slots. Every one of them is an item you buy or make
-- (see doc/items.md), so a loadout is goods you own and had hauled to where
-- your ship is.
--
-- Every fitting carries an explicit `id`, permanent and never reused: a
-- ship's loadout records them. A new fitting takes the next free number (the
-- last line of this file says which).
--
-- Weapons name a weapon definition (Shared/Definitions/WeaponDefs.lua) and
-- the smallest mount they fit. Modules carry `effects`, added up over the
-- whole fit by ShipFittingSystem (`add` summed, `scale` multiplied), and an
-- `ability` when they do something on command.

local Slot = FittingDefinition.Slot
local Stat = FittingDefinition.Stat
local Weapon = Enums.Weapon
local Size = Weapon.MountSizeClass

---@param def FittingDefinition
---@param item ItemDefinition
local function register(def, item)
    assert(item, "a fitting names an item that is not in the registry")
    Fittings:add(def, item.id)
end

------------------------------------------------------------------------------
-- Weapons: what goes in a mount
------------------------------------------------------------------------------

register(FittingDefinition {
    id = 1,
    name = "Pulse Turret",
    description = "A plasma repeater. Good against hulls, poor at long range.",
    slot = Slot.Weapon,
    sizeClass = Size.M,
    itemName = "ShipWeaponPulseTurret",
    weaponId = Weapon.Type.Plasma,
}, Items.Equipment.ShipWeaponPulseTurret)

register(FittingDefinition {
    id = 2,
    name = "Beam Turret",
    description = "A bolt laser: accurate, steady damage, hungry for power.",
    slot = Slot.Weapon,
    sizeClass = Size.M,
    itemName = "ShipWeaponBeamTurret",
    weaponId = Weapon.Type.LaserBolt,
}, Items.Equipment.ShipWeaponBeamTurret)

register(FittingDefinition {
    id = 3,
    name = "Launcher Turret",
    description = "A flak cannon. Spreads fire; made for small, fast things.",
    slot = Slot.Weapon,
    sizeClass = Size.M,
    itemName = "ShipWeaponLauncherTurret",
    weaponId = Weapon.Type.FlakCannon,
}, Items.Equipment.ShipWeaponLauncherTurret)

register(FittingDefinition {
    id = 4,
    name = "Cannon Bay",
    description = "An assault railgun. One heavy slug at a time, a long way.",
    slot = Slot.Weapon,
    sizeClass = Size.L,
    itemName = "ShipWeaponCannonBay",
    weaponId = Weapon.Type.Railgun,
}, Items.Equipment.ShipWeaponCannonBay)

register(FittingDefinition {
    id = 5,
    name = "Beam Bay",
    description = "The XL long-charge laser: slow to charge, ruinous when it lands.",
    slot = Slot.Weapon,
    sizeClass = Size.XL,
    itemName = "ShipWeaponBeamBay",
    weaponId = Weapon.Type.XLLongChargeLaser,
}, Items.Equipment.ShipWeaponBeamBay)

------------------------------------------------------------------------------
-- Modules: what goes in a slot
------------------------------------------------------------------------------

register(FittingDefinition {
    id = 6,
    name = "Shield Capacitor",
    description = "More shield to lose before the hull starts taking it.",
    slot = Slot.Module,
    itemName = "ShieldCapacitor",
    effects = { add = { [Stat.MaxShield] = 60 }, scale = { [Stat.ShieldRegen] = 1.1 } },
}, Items.Equipment.ShieldCapacitor)

register(FittingDefinition {
    id = 7,
    name = "Armour Plating",
    description = "Plate over the hull: tougher, heavier, slower.",
    slot = Slot.Module,
    itemName = "ArmourPlating",
    effects = {
        add = { [Stat.Armor] = 4, [Stat.MaxHealth] = 150 },
        scale = { [Stat.Thrust] = 0.92, [Stat.Turn] = 0.9 },
    },
}, Items.Equipment.ArmourPlating)

register(FittingDefinition {
    id = 8,
    name = "Cargo Pod",
    description = "Hold space, bolted on outside. Nothing else fits where it goes.",
    slot = Slot.Module,
    itemName = "CargoPod",
    effects = {
        add = { [Stat.CargoMass] = 1200 },
        scale = { [Stat.Thrust] = 0.95, [Stat.Turn] = 0.93 },
    },
}, Items.Equipment.CargoPod)

register(FittingDefinition {
    id = 9,
    name = "Manoeuvring Thrusters",
    description = "Turns the ship harder. Costs nothing but the slot.",
    slot = Slot.Module,
    itemName = "ManoeuvringThrusters",
    effects = { scale = { [Stat.Turn] = 1.3 } },
}, Items.Equipment.ManoeuvringThrusters)

register(FittingDefinition {
    id = 10,
    name = "Ship Sensor",
    description = "Sees further: labels, scans and the prospecting range.",
    slot = Slot.Module,
    itemName = "ShipSensor",
    effects = { scale = { [Stat.ScanRange] = 1.5 } },
}, Items.Equipment.ShipSensor)

register(FittingDefinition {
    id = 11,
    name = "Ship Computer",
    description = "Runs the guns: steadier tracking and a shade more shield.",
    slot = Slot.Module,
    itemName = "ShipComputer",
    effects = { scale = { [Stat.ShieldRegen] = 1.2 } },
}, Items.Equipment.ShipComputer)

register(FittingDefinition {
    id = 12,
    name = "Thruster Engine",
    description = "More push, everywhere.",
    slot = Slot.Module,
    itemName = "ShipEngineThruster",
    effects = { scale = { [Stat.Thrust] = 1.25 } },
}, Items.Equipment.ShipEngineThruster)

register(FittingDefinition {
    id = 13,
    name = "Impeller Engine",
    description = "A heavy drive: a lot more push, at the cost of turning.",
    slot = Slot.Module,
    itemName = "ShipEngineImpeller",
    effects = { scale = { [Stat.Thrust] = 1.6, [Stat.Turn] = 0.85 } },
}, Items.Equipment.ShipEngineImpeller)

------------------------------------------------------------------------------
-- Modules that do something on command (AbilitySystem)
------------------------------------------------------------------------------

register(FittingDefinition {
    id = 14,
    name = "Shield Booster",
    description = "Slams the shield back up. Nothing for a while after.",
    slot = Slot.Module,
    itemName = "ShieldBooster",
    effects = { add = { [Stat.MaxShield] = 20 } },
    ability = { key = "shieldBoost", cooldown = 25.0, magnitude = 0.6 },
}, Items.Equipment.ShieldBooster)

register(FittingDefinition {
    id = 15,
    name = "Afterburner",
    description = "A hard burn for a few seconds. Turns worse while it runs.",
    slot = Slot.Module,
    itemName = "Afterburner",
    ability = { key = "afterburner", cooldown = 18.0, duration = 6.0, magnitude = 2.2 },
}, Items.Equipment.Afterburner)

register(FittingDefinition {
    id = 16,
    name = "Hull Repair Pulse",
    description = "Welds the hull back together, once in a while, for free.",
    slot = Slot.Module,
    itemName = "HullRepairPulse",
    ability = { key = "repairPulse", cooldown = 60.0, magnitude = 0.25 },
}, Items.Equipment.HullRepairPulse)

register(FittingDefinition {
    id = 17,
    name = "Mining Laser",
    description = "Cuts ore out of a rock. Without one, a rock is just a rock.",
    slot = Slot.Module,
    itemName = "MiningLaser",
    effects = { scale = { [Stat.MiningRate] = 1.0 } },
    ability = { key = "miningLaser", cooldown = 0.0 },
}, Items.Equipment.MiningLaser)

register(FittingDefinition {
    id = 18,
    name = "Survey Scanner",
    description = "Reads what a rock holds, and how much is left of it.",
    slot = Slot.Module,
    itemName = "SurveyScanner",
    effects = { scale = { [Stat.ScanRange] = 1.25 } },
    ability = { key = "surveyScan", cooldown = 8.0 },
}, Items.Equipment.SurveyScanner)

return Fittings

-- The next free fitting id: 19
