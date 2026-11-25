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
            { item = Items.Miscellaneous.RadioactiveIsotopes, count = 1 },
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
            { item = Items.Consumables.LiquidWater, count = 320 },
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
            { item = Items.Waste.Waste, count = 20 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 2 },
            { item = Items.Consumables.WaterIce, count = 10 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 3 },
            { item = Items.RawMaterials.SilicateOre, count = 12 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 3 },
            { item = Items.RawMaterials.CarboniferousOre, count = 4 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 8 },
            { item = Items.RawMaterials.BerylliumOre, count = 13 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 6 },
            { item = Items.RawMaterials.AluminumOre, count = 8 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 5 },
            { item = Items.RawMaterials.IronOre, count = 7 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 7 },
            { item = Items.RawMaterials.CopperOre, count = 11 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 13 },
            { item = Items.RawMaterials.ThoriumOre, count = 12 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 6 },
            { item = Items.Consumables.Biomass, count = 22 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 3 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 8 },
            { item = Items.RefinedMaterials.Iron, count = 8 },
            { item = Items.RefinedMaterials.Carbon, count = 2 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 12 },
            { item = Items.Waste.AnodeSludge, count = 8 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 14 },
            { item = Items.Waste.AnodeSludge, count = 11 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 20 },
            { item = Items.Waste.AnodeSludge, count = 16 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 5 },
            { item = Items.RefinedMaterials.Thorium, count = 12 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 11 },
            { item = Items.RefinedMaterials.Hydrocarbons, count = 7 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 10 },
            { item = Items.RefinedMaterials.Plastic, count = 8 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 5 },
            { item = Items.RefinedMaterials.Silicon, count = 5 },
            { item = Items.RefinedMaterials.Aluminum, count = 3 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 18 },
            { item = Items.RefinedMaterials.Silicon, count = 5 },
            { item = Items.RefinedMaterials.Iron, count = 3 },
            { item = Items.RefinedMaterials.Beryllium, count = 3 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 210 },
            { item = Items.RefinedMaterials.Glassiron, count = 500 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 30 },
            { item = Items.RefinedMaterials.Steel, count = 75 },
            { item = Items.Data.InfolyticChip, count = 35 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 240 },
            { item = Items.RefinedMaterials.Glassiron, count = 420 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 28 },
            { item = Items.RefinedMaterials.Steel, count = 65 },
            { item = Items.RefinedMaterials.Silicon, count = 25 },
            { item = Items.Data.InfolyticChip, count = 150 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 120 },
            { item = Items.RefinedMaterials.Glassiron, count = 1000 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 20 },
            { item = Items.RefinedMaterials.Steel, count = 170 },
            { item = Items.Data.InfolyticChip, count = 12 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 180 },
            { item = Items.RefinedMaterials.Glassiron, count = 800 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 32 },
            { item = Items.RefinedMaterials.Steel, count = 210 },
            { item = Items.Data.InfolyticChip, count = 12 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 1500 },
            { item = Items.RefinedMaterials.Glassiron, count = 10000 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 900 },
            { item = Items.RefinedMaterials.Steel, count = 1850 },
            { item = Items.RefinedMaterials.Gold, count = 285 },
            { item = Items.RefinedMaterials.Platinum, count = 95 },
            { item = Items.Data.InfolyticChip, count = 165 },
            { item = Items.RefinedMaterials.Thorium, count = 35 },
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
            { item = Items.Miscellaneous.EnergyCell, count = 350000 },
            { item = Items.RefinedMaterials.Glassiron, count = 1000000 },
            { item = Items.RefinedMaterials.TransparentAluminum, count = 180000 },
            { item = Items.RefinedMaterials.Steel, count = 395000 },
            { item = Items.RefinedMaterials.Gold, count = 57000 },
            { item = Items.RefinedMaterials.Platinum, count = 9100 },
            { item = Items.Data.InfolyticChip, count = 8500 },
            { item = Items.Equipment.ShipSensor, count = 100 },
            { item = Items.Equipment.ShipComputer, count = 100 },
            { item = Items.RefinedMaterials.Thorium, count = 640 },
        },
        outputs = {
            { item = Items.Constructs.SpaceStationSmall, count = 1 },
            { item = Items.Waste.Waste, count = 9750 },
        },
    },
}

for _, def in ipairs(defs) do Productions:add(def) end

return Productions

-- The next free production id: 30
