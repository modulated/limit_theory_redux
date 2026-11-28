--- The production registry: every recipe of `res/data/recipes.toml`,
--- by key (`Productions.IronRefinery`), by id (`Productions:getDefinition(7)`)
--- and by class (`Productions:ofClass("Refinery")`).
---
--- Ids are written by hand in the definitions and are permanent: a station
--- records which recipes it runs, so a renumbering would change what every
--- station in a saved game produces. The registry refuses a missing or
--- duplicate id.
---@class Productions
local Productions = {}
---@private
Productions.byId = {}
---@private
Productions.byName = {}
---@private
Productions.byClass = {}
---@private
Productions.all = {}

--- Register one recipe (called by `ProductionDefs.lua` through `Productions:add`).
---@param def ProductionDefinition
---@return ProductionDefinition
function Productions:add(def)
    assert(type(def.id) == "number" and def.id > 0 and def.id % 1 == 0,
        "production '" .. tostring(def.name) .. "' has no id: give it the next free one in res/data/recipes.toml")
    assert(not self.byId[def.id],
        "production id " .. def.id .. " is used twice ('" .. tostring(def.name)
        .. "' and '" .. tostring(self.byId[def.id] and self.byId[def.id].name) .. "')")
    self.byId[def.id] = def
    self.byName[def.name] = def
    self.byClass[def.class] = self.byClass[def.class] or {}
    table.insert(self.byClass[def.class], def)
    table.insert(self.all, def)
    return def
end

---@param id integer
---@return ProductionDefinition|nil
function Productions:getDefinition(id)
    return self.byId[id]
end

--- A recipe by name, with or without spaces.
---@param name string
---@return ProductionDefinition|nil
function Productions:getByName(name)
    if type(name) ~= "string" then return nil end
    return self.byName[name] or self.byName[(name:gsub("[^%w]", ""))]
end

--- Every recipe of one class, in the order they were defined.
---@param class string a `ProductionDefinition.Class` value
---@return ProductionDefinition[]
function Productions:ofClass(class)
    return self.byClass[class] or {}
end

---@return ProductionDefinition[] every recipe
function Productions:getAll()
    return self.all
end

---@return integer
function Productions:getCount()
    return #self.all
end

-- Productions.IronRefinery and friends
setmetatable(Productions, {
    __index = function(_, key)
        return Productions.byName[key]
    end,
})

return Productions
