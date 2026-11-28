--[[----------------------------------------------------------------------------
  Convenience functions to eliminate tedious OOP idioms in Lua.

  Constructors are optional. Subclassing provides inheritance, virtualism, and
  chained constructors. Subclass is implemented with chained metatables.

  Example:

    local Ship = Class("Ship", function (self, name, hp)
      self.name = name
      self.health = hp
      self.healthMax = hp
    end)

    function Ship:addHangar (unit) assert(false, "No hangar!") end
    function Ship:getHangar () return {} end

    local Carrier = Subclass("Carrier", Ship, function (self)
      self.hanger = {}
    end)

    function Carrier:addHangar (unit) insert(self.hangar, unit) end
    function Carrier:getHangar () return self.hangar end
----------------------------------------------------------------------------]]
--

-- This function takes the class instance `self` and generates a string representation of it in
-- the form: ClassName{field1: 0, field2: 0}.
local function defaulttostring(self)
    local result = {}
    for key, value in pairs(self) do
        local keyStr = tostring(key)
        local valueStr = tostring(value)
        table.insert(result, keyStr .. ": " .. valueStr)
    end
    return typeName(self) .. "{" .. table.concat(result, ", ") .. "}"
end

function Class(name, ctor)
    -- Define the class.
    local cls = {}
    cls.__index = cls
    cls.__type = cls
    cls.__tostring = defaulttostring

    -- Define the default constructor
    -- This just invokes ctor if it is not nil.
    function cls.new(...)
        local self = {}
        setmetatable(self, cls)
        if ctor then ctor(self, ...) end
        return self
    end

    -- Set up the class metatable.
    setmetatable(cls, {
        __call = function(T, ...)
            return cls.new(...)
        end,
        __tostring = function()
            return name
        end
    })

    return cls
end

function Subclass(name, base, ctor)
    -- Define the class.
    local cls = {}
    cls.__index = cls
    cls.__type = cls
    cls.__base = base -- for isInstance
    cls.__tostring = base.__tostring or defaulttostring

    -- Define the default constructor.
    -- This just invokes ctor on an instance of base() if it is not nil.
    function cls.new(...)
        local self = base()
        setmetatable(self, cls)
        if ctor then ctor(self, ...) end
        return self
    end

    -- Set up the class metatable.
    setmetatable(cls, {
        __call = function(T, ...)
            return cls.new(...)
        end,
        __tostring = function()
            return name
        end,
        __index = base,
    })
    return cls
end

--------------------------------------------------------------------------------
-- Asking what a value is
--
-- `type` is Lua's own: a class instance is a "table", as it is. What class it
-- is, is asked with these -- never by comparing `type` to something else, and
-- never by duck-typing (`x.isValid ~= nil`), which a plain table can pass and
-- a position can crash on.
--------------------------------------------------------------------------------

--- The class a value is an instance of, or nil (a plain table, or not a table).
---@param v any
---@return table|nil
function classOf(v)
    if rawtype(v) ~= "table" then return nil end
    local mt = getmetatable(v)
    return mt and rawtype(mt) == "table" and rawget(mt, "__type") or nil
end

--- Whether a value is an instance of `cls` or of a subclass of it.
---@param v any
---@param cls table a class made by Class or Subclass
---@return boolean
function isInstance(v, cls)
    local c = classOf(v)
    while c do
        if c == cls then return true end
        c = rawget(c, "__base")
    end
    return false
end

--- Whether a value is a plain table: data, not an object. What walks into
--- tables (copies, merges, savers, writers) walks only into these.
---@param v any
---@return boolean
function isPlainTable(v)
    return rawtype(v) == "table" and classOf(v) == nil
end

