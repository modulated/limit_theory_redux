-- Types --
local ItemGroup = require("Shared.Types.ItemGroup")
local ItemDefinition = require("Shared.Types.ItemDefinition")

-- Every item carries an explicit `id`. An id is the only part of an item that
-- may end up in saved data, so it must never change or be reused: a new item
-- takes the next free number (see the end of this file for the next one), and
-- a removed item leaves its number unused. The registry refuses a missing or
-- duplicate id. `name` may be reworded freely; what the UI shows is the name
-- as written here (`displayName`), spaces and all.

ItemGroup {
    name = "Virtual",
    items = {
        ItemDefinition { id = 1, name = "Credit", mass = 0, energyDensity = 0 }
    }
}

ItemGroup {
    name = "Data",
    items = {
        ItemDefinition { id = 2, name = "Data Cube", mass = 1, energyDensity = 2.1, startEquilibriumPrice = 50 },
        ItemDefinition { id = 3, name = "Info Wafer", mass = 1, energyDensity = 3.82, startEquilibriumPrice = 75 },
        ItemDefinition { id = 4, name = "Infolytic Chip", mass = 3, energyDensity = 1.35, startEquilibriumPrice = 430 }
    }
}

ItemGroup {
    name = "Raw Materials",
    items = {
        ItemDefinition { id = 5, name = "Silicate Ore", mass = 4, energyDensity = 1.3, startEquilibriumPrice = 20 },
        ItemDefinition { id = 6, name = "Iron Ore", mass = 6, energyDensity = 1.68, startEquilibriumPrice = 30 },
        ItemDefinition { id = 7, name = "Copper Ore", mass = 7, energyDensity = 1.74, startEquilibriumPrice = 35 },
        ItemDefinition { id = 8, name = "Aluminum Ore", mass = 4, energyDensity = 1.6, startEquilibriumPrice = 25 },
        ItemDefinition { id = 9, name = "Beryllium Ore", mass = 4, energyDensity = 1.45, startEquilibriumPrice = 40 },
        ItemDefinition { id = 10, name = "Thorium Ore", mass = 7, energyDensity = 7.5, startEquilibriumPrice = 100 },
        -- Carbonaceous chondrite, the carbon ore the refineries need
        ItemDefinition { id = 52, name = "Carboniferous Ore", mass = 6, energyDensity = 1.4, startEquilibriumPrice = 28 },
    }
}

ItemGroup {
    name = "Refined Materials",
    items = {
        ItemDefinition { id = 11, name = "Iron", mass = 5, energyDensity = 1, startEquilibriumPrice = 50 },
        ItemDefinition { id = 12, name = "Copper", mass = 5, energyDensity = 1, startEquilibriumPrice = 70 },
        ItemDefinition { id = 13, name = "Aluminum", mass = 3, energyDensity = 1.8, startEquilibriumPrice = 55 },
        ItemDefinition { id = 14, name = "Silver", mass = 5, energyDensity = 1.5, startEquilibriumPrice = 150 },
        ItemDefinition { id = 15, name = "Gold", mass = 6, energyDensity = 2, startEquilibriumPrice = 200 },
        ItemDefinition { id = 16, name = "Platinum", mass = 8, energyDensity = 3, startEquilibriumPrice = 250 },
        ItemDefinition { id = 17, name = "Steel", mass = 7, energyDensity = 1, startEquilibriumPrice = 150 },
        ItemDefinition { id = 18, name = "Transparent Aluminum", mass = 5, energyDensity = 1.7, startEquilibriumPrice = 165 },
        ItemDefinition { id = 19, name = "Glassiron", mass = 11, energyDensity = 1, startEquilibriumPrice = 250 },
        ItemDefinition { id = 20, name = "Plastic", mass = 3, energyDensity = 1.9, startEquilibriumPrice = 70 },
        ItemDefinition { id = 21, name = "Thorium", mass = 9, energyDensity = 27, startEquilibriumPrice = 300 },
        -- Refinery and factory feedstock: the production chains in
        -- doc/items.md need these between the ores and the built goods.
        ItemDefinition { id = 53, name = "Silicon", mass = 2, energyDensity = 1.7, startEquilibriumPrice = 55 },
        ItemDefinition { id = 54, name = "Carbon", mass = 2, energyDensity = 1.3, startEquilibriumPrice = 60 },
        ItemDefinition { id = 55, name = "Beryllium", mass = 2, energyDensity = 1.3, startEquilibriumPrice = 65 },
        ItemDefinition { id = 56, name = "Lithium", mass = 1, energyDensity = 1.2, startEquilibriumPrice = 70 },
        ItemDefinition { id = 57, name = "Boron", mass = 2, energyDensity = 1.2, startEquilibriumPrice = 50 },
        -- Legacy called this Petroleum; it is biomass cracked into fuel and
        -- plastics feedstock, so it is named for what it is.
        ItemDefinition { id = 58, name = "Hydrocarbons", mass = 6, energyDensity = 3.5, startEquilibriumPrice = 55 }
    }
}

ItemGroup {
    name = "Gases",
    items = {
        ItemDefinition { id = 22, name = "Hydrogen", mass = 1, energyDensity = 2, startEquilibriumPrice = 25 },
        ItemDefinition { id = 23, name = "Helium", mass = 1, energyDensity = 1.01, startEquilibriumPrice = 10 },
        ItemDefinition { id = 24, name = "Nitrogen", mass = 1, energyDensity = 1.05, startEquilibriumPrice = 12 },
        ItemDefinition { id = 25, name = "Oxygen", mass = 1, energyDensity = 1.5, startEquilibriumPrice = 30 }
    }
}

ItemGroup {
    name = "Consumables",
    items = {
        ItemDefinition { id = 26, name = "Biomass", mass = 4, energyDensity = 4, startEquilibriumPrice = 60 },
        ItemDefinition { id = 27, name = "Water Ice", mass = 5, energyDensity = 1, startEquilibriumPrice = 20 },
        ItemDefinition { id = 28, name = "Liquid Water", mass = 4, energyDensity = 1, startEquilibriumPrice = 25 }
    }
}

ItemGroup {
    name = "Equipment",
    items = {
        ItemDefinition { id = 29, name = "Ship Computer", mass = 110, energyDensity = 22, startEquilibriumPrice = 2600 },
        ItemDefinition { id = 30, name = "Ship Sensor", mass = 80, energyDensity = 19, startEquilibriumPrice = 2500 },
        ItemDefinition { id = 31, name = "Ship Engine, Thruster", mass = 600, energyDensity = 20, startEquilibriumPrice = 7200 },
        ItemDefinition { id = 32, name = "Ship Engine, Impeller", mass = 1500, energyDensity = 18, startEquilibriumPrice = 4000 },
        ItemDefinition { id = 33, name = "Ship Weapon, Pulse Turret", mass = 100, energyDensity = 10, startEquilibriumPrice = 2800 },
        ItemDefinition { id = 34, name = "Ship Weapon, Beam Turret", mass = 120, energyDensity = 10, startEquilibriumPrice = 3600 },
        ItemDefinition { id = 35, name = "Ship Weapon, Launcher Turret", mass = 90, energyDensity = 8, startEquilibriumPrice = 3200 },
        ItemDefinition { id = 36, name = "Ship Weapon, Pulse Bay", mass = 1000, energyDensity = 9, startEquilibriumPrice = 3000 },
        ItemDefinition { id = 37, name = "Ship Weapon, Beam Bay", mass = 1200, energyDensity = 9, startEquilibriumPrice = 14000 },
        ItemDefinition { id = 38, name = "Ship Weapon, Cannon Bay", mass = 2500, energyDensity = 10, startEquilibriumPrice = 9000 },
        ItemDefinition { id = 39, name = "Ship Weapon, Launcher Bay", mass = 800, energyDensity = 7, startEquilibriumPrice = 2500 },
        -- Modules a ship can be fitted with (Shared/Definitions/FittingDefs.lua).
        -- Each is a good like any other: bought on a market or made in a
        -- factory, carried in the hangar, bolted on at a station.
        ItemDefinition { id = 59, name = "Shield Booster", mass = 90, energyDensity = 12, startEquilibriumPrice = 1800 },
        ItemDefinition { id = 60, name = "Armour Plating", mass = 400, energyDensity = 2, startEquilibriumPrice = 900 },
        ItemDefinition { id = 61, name = "Shield Capacitor", mass = 120, energyDensity = 14, startEquilibriumPrice = 1500 },
        ItemDefinition { id = 62, name = "Cargo Pod", mass = 250, energyDensity = 3, startEquilibriumPrice = 1100 },
        ItemDefinition { id = 63, name = "Afterburner", mass = 180, energyDensity = 16, startEquilibriumPrice = 2200 },
        ItemDefinition { id = 64, name = "Manoeuvring Thrusters", mass = 150, energyDensity = 10, startEquilibriumPrice = 1400 },
        ItemDefinition { id = 65, name = "Hull Repair Pulse", mass = 200, energyDensity = 15, startEquilibriumPrice = 2600 },
        ItemDefinition { id = 66, name = "Mining Laser", mass = 160, energyDensity = 11, startEquilibriumPrice = 1700 },
        ItemDefinition { id = 67, name = "Survey Scanner", mass = 70, energyDensity = 18, startEquilibriumPrice = 2000 },
        ItemDefinition { id = 68, name = "Market Datalink", mass = 60, energyDensity = 21, startEquilibriumPrice = 3400 }
    }
}

ItemGroup {
    name = "Constructs",
    items = {
        ItemDefinition { id = 40, name = "Ship Hull, Solo", mass = 15000, energyDensity = 50, startEquilibriumPrice = 24000 },
        ItemDefinition { id = 41, name = "Ship Hull, Small", mass = 32000, energyDensity = 49, startEquilibriumPrice = 30000 },
        ItemDefinition { id = 42, name = "Ship Hull, Compact", mass = 75000, energyDensity = 47, startEquilibriumPrice = 70000 },
        ItemDefinition { id = 43, name = "Ship Hull, Medium", mass = 102500, energyDensity = 46, startEquilibriumPrice = 100000 },
        ItemDefinition { id = 44, name = "Ship Hull, Large", mass = 237250, energyDensity = 45, startEquilibriumPrice = 200000 },
        ItemDefinition { id = 45, name = "Ship Hull, Very Large", mass = 518000, energyDensity = 42, startEquilibriumPrice = 500000 },
        ItemDefinition { id = 46, name = "Space Station, Small", mass = 1550000, energyDensity = 40, startEquilibriumPrice = 1000000 },
        -- Outpost kits: a station's core, prefabricated, that grows the rest
        -- on site. Light enough to carry in a hold (the Space Station, Small
        -- is deployed from a hangar in the system instead).
        ItemDefinition { id = 69, name = "Refinery Outpost Kit", mass = 2000, energyDensity = 30, startEquilibriumPrice = 450000 },
        ItemDefinition { id = 70, name = "Manufacturing Outpost Kit", mass = 2000, energyDensity = 30, startEquilibriumPrice = 650000 }
    }
}

ItemGroup {
    name = "Waste",
    items = {
        ItemDefinition { id = 47, name = "Waste", mass = 1, energyDensity = 1, startEquilibriumPrice = 5 },
        ItemDefinition { id = 48, name = "Radioactive Waste", mass = 10, energyDensity = 2.5, startEquilibriumPrice = 30 },
        ItemDefinition { id = 49, name = "Anode Sludge", mass = 9, energyDensity = 1, startEquilibriumPrice = 15 }
    }
}

ItemGroup {
    name = "Miscellaneous",
    items = {
        ItemDefinition { id = 50, name = "Energy Cell", mass = 1, energyDensity = 1, startEquilibriumPrice = 20 },
        ItemDefinition { id = 51, name = "Radioactive Isotopes", mass = 13, energyDensity = 50, startEquilibriumPrice = 600 }
    }
}

-- Annotations
---@class Items
---@field Virtual ItemsVirtual
---@field Data ItemsData
---@field RawMaterials ItemsRawMaterials
---@field RefinedMaterials ItemsRefinedMaterials
---@field Gases ItemsGases
---@field Consumables ItemsConsumables
---@field Equipment ItemsEquipment
---@field Constructs ItemsConstructs
---@field Waste ItemsWaste
---@field Miscellaneous ItemsMiscellaneous

---@class ItemsVirtual
---@field Credit ItemDefinition

---@class ItemsData
---@field DataCube ItemDefinition
---@field InfoWafer ItemDefinition
---@field InfolyticChip ItemDefinition

---@class ItemsRawMaterials
---@field SilicateOre ItemDefinition
---@field IronOre ItemDefinition
---@field CopperOre ItemDefinition
---@field AluminumOre ItemDefinition
---@field BerylliumOre ItemDefinition
---@field ThoriumOre ItemDefinition
---@field CarboniferousOre ItemDefinition

---@class ItemsRefinedMaterials
---@field Iron ItemDefinition
---@field Copper ItemDefinition
---@field Aluminum ItemDefinition
---@field Silver ItemDefinition
---@field Gold ItemDefinition
---@field Platinum ItemDefinition
---@field Steel ItemDefinition
---@field TransparentAluminum ItemDefinition
---@field Glassiron ItemDefinition
---@field Plastic ItemDefinition
---@field Thorium ItemDefinition
---@field Silicon ItemDefinition
---@field Carbon ItemDefinition
---@field Beryllium ItemDefinition
---@field Lithium ItemDefinition
---@field Boron ItemDefinition
---@field Hydrocarbons ItemDefinition

---@class ItemsGases
---@field Hydrogen ItemDefinition
---@field Helium ItemDefinition
---@field Nitrogen ItemDefinition
---@field Oxygen ItemDefinition

---@class ItemsConsumables
---@field Biomass ItemDefinition
---@field WaterIce ItemDefinition
---@field LiquidWater ItemDefinition

---@class ItemsEquipment
---@field ShipComputer ItemDefinition
---@field ShipSensor ItemDefinition
---@field ShipEngineThruster ItemDefinition
---@field ShipEngineImpeller ItemDefinition
---@field ShipWeaponPulseTurret ItemDefinition
---@field ShipWeaponBeamTurret ItemDefinition
---@field ShipWeaponLauncherTurret ItemDefinition
---@field ShipWeaponPulseBay ItemDefinition
---@field ShipWeaponBeamBay ItemDefinition
---@field ShipWeaponCannonBay ItemDefinition
---@field ShipWeaponLauncherBay ItemDefinition
---@field ShieldBooster ItemDefinition
---@field ArmourPlating ItemDefinition
---@field ShieldCapacitor ItemDefinition
---@field CargoPod ItemDefinition
---@field Afterburner ItemDefinition
---@field ManoeuvringThrusters ItemDefinition
---@field HullRepairPulse ItemDefinition
---@field MiningLaser ItemDefinition
---@field SurveyScanner ItemDefinition
---@field MarketDatalink ItemDefinition

---@class ItemsConstructs
---@field ShipHullSolo ItemDefinition
---@field ShipHullSmall ItemDefinition
---@field ShipHullCompact ItemDefinition
---@field ShipHullMedium ItemDefinition
---@field ShipHullLarge ItemDefinition
---@field ShipHullVeryLarge ItemDefinition
---@field SpaceStationSmall ItemDefinition
---@field RefineryOutpostKit ItemDefinition
---@field ManufacturingOutpostKit ItemDefinition

---@class ItemsWaste
---@field Waste ItemDefinition
---@field RadioactiveWaste ItemDefinition
---@field AnodeSludge ItemDefinition

---@class ItemsMiscellaneous
---@field EnergyCell ItemDefinition
---@field RadioactiveIsotopes ItemDefinition

-- The next free item id: 71
