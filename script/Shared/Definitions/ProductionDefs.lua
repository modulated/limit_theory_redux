-- Types --
local ProductionDefinition = require("Shared.Types.ProductionDefinition")
local Productions = require("Shared.Registries.Productions")
-- The recipes name items, so the item registry has to be filled first.
require("Shared.Definitions.ItemDefs")
local Items = require("Shared.Registries.Items")
local Class = ProductionDefinition.Class

-- What a station can make out of what it holds: the production chains of the
-- game, ported from Legacy's Elements/Economy/Content.lua. Read
-- doc/items.md for the chains as a whole.
--
-- Every recipe carries an explicit `id`, permanent and never reused: a
-- station records which recipes it runs, so renumbering would change what
-- every station in a saved game produces. A new recipe takes the next free
-- number (the last line of this file says which).
--
-- `duration` is Legacy's seconds for one run, from 4 s for a waste recycler
-- to 4 hours for a station fabricator. The production system scales them by
-- `Config.game.production.timeScale` so a factory does something visible
-- within a session.
--
-- Legacy's "Piracy" recipe (energy in, credits out) is not here: pirates earn
-- by raiding and by what their kills drop, not at a production line.

local defs = {
    ProductionDefinition {
        id = 1,
        name = "Solar Energy Array",
        class = Class.Powerplant,
        duration = 8.0,
        inputs = {},
        outputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 10 },
        },
    },
    ProductionDefinition {
        id = 2,
        name = "Nuclear Reactor",
        class = Class.Powerplant,
        duration = 20.0,
        inputs = {
            { item = Items.Miscellaneous.RadioactiveIsotopes, count = 6 },
        },
        outputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 240 },
            { item = Items.Waste.RadioactiveWaste, count = 8 },
        },
    },
    ProductionDefinition {
        id = 3,
        name = "Fusion Reactor",
        class = Class.Powerplant,
        duration = 40.0,
        inputs = {
            { item = Items.Consumables.LiquidWater, count = 572 },
        },
        outputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1000 },
            { item = Items.Waste.RadioactiveWaste, count = 1 },
        },
    },
    ProductionDefinition {
        id = 4,
        name = "Waste Recycler",
        class = Class.Powerplant,
        duration = 4.0,
        inputs = {
            { item = Items.Waste.Waste, count = 14 },
        },
        outputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 5 },
        },
    },
    ProductionDefinition {
        id = 5,
        name = "Water Melter",
        class = Class.Refinery,
        duration = 6.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 3 },
            { item = Items.Consumables.WaterIce, count = 15 },
        },
        outputs = {
            { item = Items.Consumables.LiquidWater, count = 20 },
        },
    },
    ProductionDefinition {
        id = 6,
        name = "Silicon Refinery",
        class = Class.Refinery,
        duration = 12.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RawMaterials.SilicateOre, count = 2 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Silicon, count = 1 },
            { item = Items.Waste.Waste, count = 6 },
        },
    },
    ProductionDefinition {
        id = 7,
        name = "Carbon Refinery",
        class = Class.Refinery,
        duration = 13.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RawMaterials.CarboniferousOre, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Carbon, count = 1 },
            { item = Items.Waste.Waste, count = 3 },
        },
    },
    ProductionDefinition {
        id = 8,
        name = "Beryllium Refinery",
        class = Class.Refinery,
        duration = 22.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RawMaterials.BerylliumOre, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Beryllium, count = 1 },
            { item = Items.Waste.Waste, count = 7 },
        },
    },
    ProductionDefinition {
        id = 9,
        name = "Aluminum Refinery",
        class = Class.Refinery,
        duration = 15.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RawMaterials.AluminumOre, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Aluminum, count = 1 },
            { item = Items.Waste.Waste, count = 5 },
        },
    },
    ProductionDefinition {
        id = 10,
        name = "Iron Refinery",
        class = Class.Refinery,
        duration = 14.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RawMaterials.IronOre, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Iron, count = 1 },
            { item = Items.Waste.Waste, count = 4 },
        },
    },
    ProductionDefinition {
        id = 11,
        name = "Copper Refinery",
        class = Class.Refinery,
        duration = 16.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RawMaterials.CopperOre, count = 3 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Copper, count = 2 },
            { item = Items.Waste.AnodeSludge, count = 1 },
            { item = Items.Waste.Waste, count = 7 },
        },
    },
    ProductionDefinition {
        id = 12,
        name = "Thorium Refinery",
        class = Class.Refinery,
        duration = 20.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RawMaterials.ThoriumOre, count = 2 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Thorium, count = 1 },
            { item = Items.Waste.RadioactiveWaste, count = 2 },
            { item = Items.Waste.Waste, count = 5 },
        },
    },
    ProductionDefinition {
        id = 13,
        name = "Hydrocarbon Refinery",
        class = Class.Refinery,
        duration = 14.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.Consumables.Biomass, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Hydrocarbons, count = 1 },
            { item = Items.Waste.Waste, count = 15 },
        },
    },
    ProductionDefinition {
        id = 14,
        name = "Water Electrolyser",
        class = Class.Factory,
        duration = 5.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.Consumables.LiquidWater, count = 1 },
        },
        outputs = {
            { item = Items.Gases.Hydrogen, count = 2 },
            { item = Items.Gases.Oxygen, count = 1 },
        },
    },
    ProductionDefinition {
        id = 15,
        name = "Steel Foundry",
        class = Class.Factory,
        duration = 13.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RefinedMaterials.Iron, count = 1 },
            { item = Items.RefinedMaterials.Carbon, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Steel, count = 1 },
            { item = Items.Waste.Waste, count = 4 },
        },
    },
    ProductionDefinition {
        id = 16,
        name = "Silver Recovery Plant",
        class = Class.Factory,
        duration = 18.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.Waste.AnodeSludge, count = 3 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Silver, count = 1 },
            { item = Items.Waste.Waste, count = 6 },
        },
    },
    ProductionDefinition {
        id = 17,
        name = "Gold Recovery Plant",
        class = Class.Factory,
        duration = 21.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 5 },
            { item = Items.Waste.AnodeSludge, count = 4 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Gold, count = 1 },
            { item = Items.Waste.Waste, count = 7 },
        },
    },
    ProductionDefinition {
        id = 18,
        name = "Platinum Recovery Plant",
        class = Class.Factory,
        duration = 25.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 7 },
            { item = Items.Waste.AnodeSludge, count = 5 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Platinum, count = 1 },
            { item = Items.Waste.Waste, count = 9 },
        },
    },
    ProductionDefinition {
        id = 19,
        name = "Isotope Factory",
        class = Class.Factory,
        duration = 11.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RefinedMaterials.Thorium, count = 2 },
        },
        outputs = {
            { item = Items.Miscellaneous.RadioactiveIsotopes, count = 1 },
            { item = Items.Waste.RadioactiveWaste, count = 7 },
            { item = Items.Waste.Waste, count = 3 },
        },
    },
    ProductionDefinition {
        id = 20,
        name = "Plastics Factory",
        class = Class.Factory,
        duration = 9.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RefinedMaterials.Hydrocarbons, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Plastic, count = 1 },
            { item = Items.Waste.Waste, count = 8 },
        },
    },
    ProductionDefinition {
        id = 21,
        name = "Infolytic Chip Factory",
        class = Class.Factory,
        duration = 11,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RefinedMaterials.Plastic, count = 1 },
            { item = Items.RefinedMaterials.Gold, count = 1 },
            { item = Items.RefinedMaterials.Silicon, count = 1 },
        },
        outputs = {
            { item = Items.Data.InfolyticChip, count = 1 },
            { item = Items.Waste.Waste, count = 2 },
        },
    },
    ProductionDefinition {
        id = 22,
        name = "Transparent Aluminum Factory",
        class = Class.Factory,
        duration = 13.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 1 },
            { item = Items.RefinedMaterials.Silicon, count = 1 },
            { item = Items.RefinedMaterials.Aluminum, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.TransparentAluminum, count = 1 },
            { item = Items.Waste.Waste, count = 3 },
        },
    },
    ProductionDefinition {
        id = 23,
        name = "Glassiron Factory",
        class = Class.Factory,
        duration = 17.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RefinedMaterials.Silicon, count = 1 },
            { item = Items.RefinedMaterials.Iron, count = 1 },
            { item = Items.RefinedMaterials.Beryllium, count = 1 },
        },
        outputs = {
            { item = Items.RefinedMaterials.Glassiron, count = 1 },
            { item = Items.Waste.Waste, count = 3 },
        },
    },
    ProductionDefinition {
        id = 24,
        name = "Ship Sensor Factory",
        class = Class.Factory,
        duration = 450.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RefinedMaterials.Glassiron, count = 3 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
            { item = Items.Data.InfolyticChip, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.ShipSensor, count = 1 },
            { item = Items.Waste.Waste, count = 55 },
        },
    },
    ProductionDefinition {
        id = 25,
        name = "Ship Computer Factory",
        class = Class.Factory,
        duration = 360.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RefinedMaterials.Glassiron, count = 2 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
            { item = Items.RefinedMaterials.Silicon, count = 2 },
            { item = Items.Data.InfolyticChip, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.ShipComputer, count = 1 },
            { item = Items.Waste.Waste, count = 70 },
        },
    },
    ProductionDefinition {
        id = 26,
        name = "Thruster Engine Factory",
        class = Class.Factory,
        duration = 900.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RefinedMaterials.Glassiron, count = 12 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
            { item = Items.Data.InfolyticChip, count = 2 },
            { item = Items.RefinedMaterials.Thorium, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.ShipEngineThruster, count = 1 },
            { item = Items.Waste.Waste, count = 55 },
        },
    },
    ProductionDefinition {
        id = 27,
        name = "Pulse Turret Weapon Factory",
        class = Class.Factory,
        duration = 790.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RefinedMaterials.Glassiron, count = 3 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
            { item = Items.Data.InfolyticChip, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.ShipWeaponPulseTurret, count = 1 },
            { item = Items.Waste.Waste, count = 40 },
        },
    },
    ProductionDefinition {
        id = 28,
        name = "Solo Ship Hull Drydock",
        class = Class.Drydock,
        duration = 1800.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.Glassiron, count = 21 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 3 },
            { item = Items.RefinedMaterials.Steel, count = 5 },
            { item = Items.RefinedMaterials.Gold, count = 1 },
            { item = Items.RefinedMaterials.Platinum, count = 1 },
            { item = Items.Data.InfolyticChip, count = 1 },
            { item = Items.RefinedMaterials.Thorium, count = 1 },
            { item = Items.Equipment.ShipSensor, count = 1 },
            { item = Items.Equipment.ShipComputer, count = 1 },
            { item = Items.Equipment.ShipEngineThruster, count = 1 },
        },
        outputs = {
            { item = Items.Constructs.ShipHullSolo, count = 1 },
            { item = Items.Waste.Waste, count = 725 },
        },
    },
    ProductionDefinition {
        id = 29,
        name = "Space Station Fabricator",
        class = Class.Drydock,
        duration = 14400.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 716 },
            { item = Items.RefinedMaterials.Glassiron, count = 2046 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 369 },
            { item = Items.RefinedMaterials.Steel, count = 809 },
            { item = Items.RefinedMaterials.Gold, count = 116 },
            { item = Items.RefinedMaterials.Platinum, count = 19 },
            { item = Items.Data.InfolyticChip, count = 18 },
            { item = Items.Equipment.ShipSensor, count = 1 },
            { item = Items.Equipment.ShipComputer, count = 1 },
            { item = Items.RefinedMaterials.Thorium, count = 1 },
        },
        outputs = {
            { item = Items.Constructs.SpaceStationSmall, count = 1 },
            { item = Items.Waste.Waste, count = 9750 },
        },
    },
    ProductionDefinition {
        id = 30,
        name = "Shield Capacitor Factory",
        class = Class.Factory,
        duration = 420.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 3 },
            { item = Items.RefinedMaterials.Glassiron, count = 1 },
            { item = Items.RefinedMaterials.Steel, count = 1 },
            { item = Items.Data.InfolyticChip, count = 1 },
        },
        outputs = {
            { item = Items.Equipment.ShieldCapacitor, count = 1 },
            { item = Items.Waste.Waste, count = 45 },
        },
    },
    ProductionDefinition {
        id = 31,
        name = "Armour Plating Mill",
        class = Class.Factory,
        duration = 300.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RefinedMaterials.Glassiron, count = 1 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.ArmourPlating, count = 1 },
            { item = Items.Waste.Waste, count = 60 },
        },
    },
    ProductionDefinition {
        id = 32,
        name = "Cargo Pod Factory",
        class = Class.Factory,
        duration = 360.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.CargoPod, count = 1 },
            { item = Items.Waste.Waste, count = 50 },
        },
    },
    ProductionDefinition {
        id = 33,
        name = "Manoeuvring Thruster Factory",
        class = Class.Factory,
        duration = 480.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.RefinedMaterials.Glassiron, count = 1 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 1 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
            { item = Items.RefinedMaterials.Silicon, count = 1 },
            { item = Items.RefinedMaterials.Plastic, count = 1 },
        },
        outputs = {
            { item = Items.Equipment.ManoeuvringThrusters, count = 1 },
            { item = Items.Waste.Waste, count = 45 },
        },
    },
    ProductionDefinition {
        id = 34,
        name = "Shield Booster Factory",
        class = Class.Factory,
        duration = 540.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.Glassiron, count = 1 },
            { item = Items.RefinedMaterials.Gold, count = 1 },
            { item = Items.RefinedMaterials.Silicon, count = 1 },
            { item = Items.Data.InfolyticChip, count = 1 },
        },
        outputs = {
            { item = Items.Equipment.ShieldBooster, count = 1 },
            { item = Items.Waste.Waste, count = 50 },
        },
    },
    ProductionDefinition {
        id = 35,
        name = "Afterburner Factory",
        class = Class.Factory,
        duration = 600.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.Glassiron, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
            { item = Items.RefinedMaterials.Plastic, count = 2 },
            { item = Items.RefinedMaterials.Thorium, count = 1 },
        },
        outputs = {
            { item = Items.Equipment.Afterburner, count = 1 },
            { item = Items.Waste.Waste, count = 60 },
        },
    },
    ProductionDefinition {
        id = 36,
        name = "Hull Repair Pulse Factory",
        class = Class.Factory,
        duration = 720.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.Glassiron, count = 1 },
            { item = Items.RefinedMaterials.Steel, count = 1 },
            { item = Items.RefinedMaterials.Gold, count = 1 },
            { item = Items.Data.InfolyticChip, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.HullRepairPulse, count = 1 },
            { item = Items.Waste.Waste, count = 55 },
        },
    },
    ProductionDefinition {
        id = 37,
        name = "Mining Laser Factory",
        class = Class.Factory,
        duration = 540.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.Glassiron, count = 1 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 1 },
            { item = Items.RefinedMaterials.Silicon, count = 1 },
            { item = Items.Data.InfolyticChip, count = 1 },
        },
        outputs = {
            { item = Items.Equipment.MiningLaser, count = 1 },
            { item = Items.Waste.Waste, count = 45 },
        },
    },
    ProductionDefinition {
        id = 38,
        name = "Survey Scanner Factory",
        class = Class.Factory,
        duration = 600.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 3 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 1 },
            { item = Items.RefinedMaterials.Silicon, count = 2 },
            { item = Items.Data.InfolyticChip, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.SurveyScanner, count = 1 },
            { item = Items.Waste.Waste, count = 40 },
        },
    },
    ProductionDefinition {
        id = 39,
        name = "Beam Turret Weapon Factory",
        class = Class.Factory,
        duration = 850.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.Glassiron, count = 2 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 2 },
            { item = Items.RefinedMaterials.Silicon, count = 1 },
            { item = Items.Data.InfolyticChip, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.ShipWeaponBeamTurret, count = 1 },
            { item = Items.Waste.Waste, count = 45 },
        },
    },
    ProductionDefinition {
        id = 40,
        name = "Launcher Turret Weapon Factory",
        class = Class.Factory,
        duration = 800.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.Glassiron, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 4 },
            { item = Items.RefinedMaterials.Silicon, count = 2 },
            { item = Items.RefinedMaterials.Plastic, count = 2 },
            { item = Items.RefinedMaterials.Copper, count = 1 },
            { item = Items.Data.InfolyticChip, count = 1 },
        },
        outputs = {
            { item = Items.Equipment.ShipWeaponLauncherTurret, count = 1 },
            { item = Items.Waste.Waste, count = 60 },
        },
    },
    ProductionDefinition {
        id = 41,
        name = "Cannon Bay Weapon Works",
        class = Class.Factory,
        duration = 1800.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 10 },
            { item = Items.RefinedMaterials.Glassiron, count = 8 },
            { item = Items.RefinedMaterials.Steel, count = 10 },
            { item = Items.RefinedMaterials.Platinum, count = 1 },
            { item = Items.RefinedMaterials.Thorium, count = 2 },
            { item = Items.Data.InfolyticChip, count = 2 },
        },
        outputs = {
            { item = Items.Equipment.ShipWeaponCannonBay, count = 1 },
            { item = Items.Waste.Waste, count = 220 },
        },
    },
    ProductionDefinition {
        id = 42,
        name = "Beam Bay Weapon Works",
        class = Class.Factory,
        duration = 2700.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 20 },
            { item = Items.RefinedMaterials.Glassiron, count = 10 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 8 },
            { item = Items.RefinedMaterials.Gold, count = 4 },
            { item = Items.RefinedMaterials.Platinum, count = 2 },
            { item = Items.RefinedMaterials.Thorium, count = 1 },
            { item = Items.Data.InfolyticChip, count = 6 },
        },
        outputs = {
            { item = Items.Equipment.ShipWeaponBeamBay, count = 1 },
            { item = Items.Waste.Waste, count = 260 },
        },
    },
    ProductionDefinition {
        id = 43,
        name = "Small Ship Hull Drydock",
        class = Class.Drydock,
        duration = 4200.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 6 },
            { item = Items.RefinedMaterials.Glassiron, count = 27 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 4 },
            { item = Items.RefinedMaterials.Steel, count = 7 },
            { item = Items.RefinedMaterials.Gold, count = 1 },
            { item = Items.RefinedMaterials.Platinum, count = 1 },
            { item = Items.Data.InfolyticChip, count = 2 },
            { item = Items.RefinedMaterials.Thorium, count = 1 },
            { item = Items.Equipment.ShipSensor, count = 1 },
            { item = Items.Equipment.ShipComputer, count = 1 },
            { item = Items.Equipment.ShipEngineThruster, count = 1 },
        },
        outputs = {
            { item = Items.Constructs.ShipHullSmall, count = 1 },
            { item = Items.Waste.Waste, count = 980 },
        },
    },
    ProductionDefinition {
        id = 44,
        name = "Compact Ship Hull Drydock",
        class = Class.Drydock,
        duration = 9000.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 14 },
            { item = Items.RefinedMaterials.Glassiron, count = 60 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 10 },
            { item = Items.RefinedMaterials.Steel, count = 18 },
            { item = Items.RefinedMaterials.Gold, count = 2 },
            { item = Items.RefinedMaterials.Platinum, count = 2 },
            { item = Items.Data.InfolyticChip, count = 4 },
            { item = Items.RefinedMaterials.Thorium, count = 3 },
            { item = Items.Equipment.ShipSensor, count = 1 },
            { item = Items.Equipment.ShipComputer, count = 2 },
            { item = Items.Equipment.ShipEngineThruster, count = 3 },
        },
        outputs = {
            { item = Items.Constructs.ShipHullCompact, count = 1 },
            { item = Items.Waste.Waste, count = 2200 },
        },
    },
    ProductionDefinition {
        id = 45,
        name = "Medium Ship Hull Drydock",
        class = Class.Drydock,
        duration = 14400.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 22 },
            { item = Items.RefinedMaterials.Glassiron, count = 90 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 16 },
            { item = Items.RefinedMaterials.Steel, count = 28 },
            { item = Items.RefinedMaterials.Gold, count = 3 },
            { item = Items.RefinedMaterials.Platinum, count = 3 },
            { item = Items.Data.InfolyticChip, count = 6 },
            { item = Items.RefinedMaterials.Thorium, count = 5 },
            { item = Items.Equipment.ShipSensor, count = 2 },
            { item = Items.Equipment.ShipComputer, count = 2 },
            { item = Items.Equipment.ShipEngineThruster, count = 4 },
        },
        outputs = {
            { item = Items.Constructs.ShipHullMedium, count = 1 },
            { item = Items.Waste.Waste, count = 3200 },
        },
    },
    ProductionDefinition {
        id = 47,
        name = "Market Datalink Factory",
        class = Class.Factory,
        duration = 660.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 1 },
            { item = Items.RefinedMaterials.Gold, count = 2 },
            { item = Items.RefinedMaterials.Silicon, count = 2 },
            { item = Items.Data.InfolyticChip, count = 3 },
        },
        outputs = {
            { item = Items.Equipment.MarketDatalink, count = 1 },
            { item = Items.Waste.Waste, count = 40 },
        },
    },
    ProductionDefinition {
        id = 46,
        name = "Impeller Engine Factory",
        class = Class.Factory,
        duration = 1100.0,
        inputs = {
            { item = Items.Miscellaneous.EnergyCell, count = 4 },
            { item = Items.RefinedMaterials.Glassiron, count = 4 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 2 },
            { item = Items.RefinedMaterials.Steel, count = 6 },
            { item = Items.RefinedMaterials.Thorium, count = 1 },
        },
        outputs = {
            { item = Items.Equipment.ShipEngineImpeller, count = 1 },
            { item = Items.Waste.Waste, count = 120 },
        },
    },
}

for _, def in ipairs(defs) do Productions:add(def) end

return Productions

-- The next free production id: 48
