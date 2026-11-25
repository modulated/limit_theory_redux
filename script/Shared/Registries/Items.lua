--- The item registry: every `ItemDefinition` of every `ItemGroup`, reachable
--- by key (`Items.RawMaterials.IronOre`) or by id (`Items:getDefinition(6)`).
---
--- Ids are **written in `Shared/Definitions/ItemDefs.lua`, not assigned here**.
--- They are the only part of an item that is allowed to end up in saved games,
--- so they must never change or be reused: adding an item means giving it the
--- next free number, and removing one means leaving its number unused. The
--- registry refuses a missing or duplicate id, so a mistake fails at load
--- rather than silently renaming someone's cargo.
---@class Items
local Items = {}
---@private
Items.itemCount = 0
---@private
Items.__index = Items
---@private Items by their space-stripped name, for `getByName`
Items.byName = {}

---@class ItemId

---@param name string
---@param itemGroup ItemGroup
function Items:new(name, itemGroup)
    name = name:gsub(" ", "")
    self[name] = {}

    for _, def in ipairs(itemGroup.items) do
        assert(type(def.id) == "number" and def.id > 0 and def.id % 1 == 0,
            "item '" .. tostring(def.name) .. "' has no id: give it the next free one in ItemDefs.lua")
        assert(self[def.id] == nil,
            "item id " .. def.id .. " is used twice ('" .. tostring(def.name)
            .. "' and '" .. tostring(self[def.id] and self[def.id].name) .. "')")
        -- The key and `name` have no spaces (Items.RawMaterials.IronOre);
        -- `displayName` keeps them, and is what the UI and the logs show.
        def.name = def.name:gsub(" ", "")
        def.group = itemGroup.name
        self[name][def.name] = def -- for string/hash api e.g. Items.Virtual.Credit
        self[def.id] = def         -- for comp (more memory usage vs string comparison computation)
        self.byName[def.name] = def
        self.itemCount = self.itemCount + 1
    end
    SetLengthMetamethod(self[name])
    return self[name]
end

---@return integer
function Items:getItemCount()
    return self.itemCount
end

---@param id integer<ItemId>
---@return ItemDefinition|nil
function Items:getDefinition(id)
    local def = self[id]
    if def then
        return def
    end
    return nil
end

--- An item by name, with or without spaces ("Iron Ore" and "IronOre" both
--- find it). The way config and save data should name an item.
---@param name string
---@return ItemDefinition|nil
function Items:getByName(name)
    if type(name) ~= "string" then return nil end
    return self.byName[name] or self.byName[(name:gsub(" ", ""))]
end

---@return Items
return Items
