---One thing that can be bolted to a ship: a weapon for a mount, or a module
---for a slot.
---
---A fitting is an **item** first (`res/data/items.toml`): you buy
---it on a station's market or make it in a rented factory, it sits in your
---hangar, and fitting it takes it out of the hangar and puts it on the ship.
---Unfitting puts it back. So a loadout is a pile of goods you own, and the
---economy and the ship are the same game.
---
---What a fitting does is one of:
--- * `weaponId` -- it is a weapon, and goes in a mount of its size class or
---   larger. The mount's turret resolves that weapon every frame
---   (`WeaponSystem:resolveWeapon`), so swapping one changes what the gun is.
--- * `effects` -- it is a passive module: a table of stat changes the fitting
---   system adds up and applies to the ship (`ShipFittingSystem:apply`).
---   `add` fields are summed, `scale` fields multiplied.
--- * `ability` -- it is an active module: it does something when triggered, on
---   a cooldown, driven by `AbilitySystem`.
---
---A module may be both passive and active (an afterburner's thrust is a
---scale, its burn is an ability).
---@class FittingDefinition
---@field id integer permanent, written by hand in res/data/modules.toml
---@field name string the lookup key, the plain letters of the name
---@field displayName string the name as written
---@field description string one line, for the refit screen
---@field slot string "weapon" or "module"
---@field sizeClass string|nil for a weapon: the smallest mount it fits (Enums.Weapon.MountSizeClass)
---@field moduleClass string|nil for a module: "S", "M", "L" or "C", the smallest hull class it fits
---@field itemName string the item that *is* this fitting, by registry key
---@field weaponId integer|nil the weapon it mounts (Enums.Weapon.Type)
---@field effects table|nil { add = { stat = number }, scale = { stat = number } }
---@field ability table|nil { key = string, cooldown = number, duration = number|nil, magnitude = number|nil }
---@field tool table|nil a mounted tool (not a gun): { kind = "mining", cycle = seconds, units = per cycle }
---@overload fun(args: table): FittingDefinition
local FittingDefinition = Class("FittingDefinition")

--- Where a fitting goes.
FittingDefinition.Slot = {
    Weapon = "weapon", -- a hull's weapon mount
    Module = "module", -- a hull's module slot
}

--- The stats a module can change. `add` is summed over the fit, `scale`
--- multiplied; the fitting system knows how each reaches the ship.
FittingDefinition.Stat = {
    MaxShield   = "maxShield",   -- add, and scale
    ShieldRegen = "shieldRegen", -- add, and scale
    Armor       = "armor",       -- add
    MaxHealth   = "maxHealth",   -- add, and scale
    CargoMass   = "cargoMass",   -- add: what the hold takes
    Thrust      = "thrust",      -- scale
    Turn        = "turn",        -- scale
    ScanRange   = "scanRange",   -- scale: how far the scanner and the labels reach
    MiningRate  = "miningRate",  -- scale: seconds a unit takes, divided by this
    MarketReach = "marketReach", -- add: jumps away whose order books can be read
    SignatureRange = "signatureRange",       -- scale: how far off a ship's signature shows (sensors)
    SignatureAccuracy = "signatureAccuracy", -- scale: how closely a signature is placed (sensors)
    JumpRange = "jumpRange", -- add: how far the jump drive reaches, in shares of the galaxy's radius
}

---@param args table
function FittingDefinition.new(args)
    assert(args.name, "FittingDefinition needs a name")
    assert(args.itemName, "fitting '" .. args.name .. "' needs the item it is")
    assert(args.slot == FittingDefinition.Slot.Weapon or args.slot == FittingDefinition.Slot.Module,
        "fitting '" .. args.name .. "' needs a slot of 'weapon' or 'module'")
    local self = setmetatable({}, FittingDefinition)
    self.id = args.id
    self.displayName = args.displayName or args.name
    self.name = (args.name:gsub("[^%w]", ""))
    self.description = args.description or ""
    self.slot = args.slot
    self.sizeClass = args.sizeClass
    self.moduleClass = args.moduleClass
    self.itemName = args.itemName
    self.weaponId = args.weaponId
    self.effects = args.effects
    self.ability = args.ability
    self.tool = args.tool
    return self
end

--- A tool on a mount (the mining laser): aimed, but never a gun.
---@return boolean
function FittingDefinition:isTool()
    return self.tool ~= nil
end

---@return boolean
function FittingDefinition:isWeapon()
    return self.slot == FittingDefinition.Slot.Weapon
end

---@return boolean
function FittingDefinition:isActive()
    return self.ability ~= nil
end

--- What this fitting does, in words, for the refit screen.
---@return string
function FittingDefinition:describeEffects()
    local parts = {}
    for stat, value in pairs(self.effects and self.effects.add or {}) do
        parts[#parts + 1] = string.format("%+g %s", value, stat)
    end
    for stat, value in pairs(self.effects and self.effects.scale or {}) do
        parts[#parts + 1] = string.format("%s x%.2f", stat, value)
    end
    table.sort(parts)
    if self.ability then
        parts[#parts + 1] = string.format("ability every %gs", self.ability.cooldown)
    end
    if #parts == 0 then return self.description end
    return table.concat(parts, ", ")
end

return FittingDefinition
