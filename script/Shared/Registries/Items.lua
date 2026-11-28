--- The item registry: every `ItemDefinition` of every `ItemGroup`, reachable
--- by key (`Items.RawMaterials.Siderite`) or by id (`Items:getDefinition(6)`).
---
--- Ids are **written in `res/data/items.toml`, not assigned here**.
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
---@private Items by their key (the plain letters of the name), for `getByName`
Items.byName = {}

---@class ItemId

--- The key an item or a group is filed under: its name with the spaces and
--- the punctuation taken out, so "Ship Engine, Thruster" is reached as
--- `Items.Equipment.ShipEngineThruster`.
---@param name string
---@return string
local function keyOf(name)
    return (name:gsub("[^%w]", ""))
end

---@param name string
---@param itemGroup ItemGroup
function Items:new(name, itemGroup)
    name = keyOf(name)
    self[name] = {}

    for _, def in ipairs(itemGroup.items) do
        assert(type(def.id) == "number" and def.id > 0 and def.id % 1 == 0,
            "item '" .. tostring(def.name) .. "' has no id: give it the next free one in res/data/items.toml")
        assert(self[def.id] == nil,
            "item id " .. def.id .. " is used twice ('" .. tostring(def.name)
            .. "' and '" .. tostring(self[def.id] and self[def.id].name) .. "')")
        -- The key and `name` are the plain letters of the name
        -- (Items.RawMaterials.Siderite); `displayName` keeps the spaces and
        -- the punctuation, and is what the UI and the logs show.
        def.name = keyOf(def.name)
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

--- An item by name, as written or as a key ("Ship Engine, Thruster" and
--- "ShipEngineThruster" both find it). The way config and save data should
--- name an item.
---@param name string
---@return ItemDefinition|nil
function Items:getByName(name)
    if type(name) ~= "string" then return nil end
    return self.byName[name] or self.byName[keyOf(name)]
end

---@return Items
return Items
