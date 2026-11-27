-- Types --
local ItemGroup = require("Shared.Types.ItemGroup")
local ItemDefinition = require("Shared.Types.ItemDefinition")
local Toml = require("Shared.Data.Toml")
local Fields = require("Shared.Data.Fields")

-- The items come from res/data/items.toml (its header explains every field).
-- This reads the file, checks every entry, and files the items in their
-- groups, in the order the file has them.
--
-- An id is the only part of an item that may end up in saved data, so it must
-- never change or be reused. The registry refuses a missing or duplicate id,
-- and so does this, with the line it is on.

local FIELDS = { "id", "name", "group", "mass", "energy_density", "price" }

local file = Toml.load("items.toml")
if type(file.item) ~= "table" or #file.item == 0 then
    error("res/data/items.toml has no [[item]] entries", 0)
end

local groups, order = {}, {}
local ids, names = {}, {}
for _, entry in ipairs(file.item) do
    local f = Fields.of(entry, "item", FIELDS)
    local id = f:id()
    f:unique(ids, id)
    local name = f:str("name")
    local key = name:gsub("[^%w]", "")
    if key == "" then f:fail("`name` needs letters or digits") end
    if names[key] then f:fail("has the same name as '%s' (names are compared by their letters)", names[key]) end
    names[key] = name
    local group = f:str("group")
    if not groups[group] then
        groups[group] = {}
        order[#order + 1] = group
    end
    local items = groups[group]
    items[#items + 1] = ItemDefinition {
        id = id,
        name = name,
        mass = f:num("mass", 0),
        energyDensity = f:num("energy_density", 0),
        startEquilibriumPrice = f:num("price", 0, true),
    }
end

for _, group in ipairs(order) do
    ItemGroup { name = group, items = groups[group] }
end

-- Annotations, for the editor: the groups and items as code reaches them.
-- Kept by hand beside res/data/items.toml; the game does not read them.
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
