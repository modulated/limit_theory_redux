local StockComponent = require("Modules.Economy.Components.StockComponent")

--- The player's hold. It lives here rather than on the ship because the ship
--- entity is destroyed and built again on undocking, on a jump and on a
--- respawn; the cargo is the player's, like the credits in `PlayerWallet`.
---
--- Capacity is a mass (`Config.game.cargo.holdCapacity`): ore is heavy, data
--- cubes are not.
---@class PlayerCargo
local PlayerCargo = {
    ---@type StockComponent
    stock = nil,
}

--- A new game: an empty hold of the configured size.
function PlayerCargo:reset()
    self.stock = StockComponent(Config.game.cargo.holdCapacity)
end

--- Resize the hold: the hull's own capacity plus whatever cargo modules are
--- fitted (`ShipFittingSystem`). Goods already aboard are never thrown away,
--- so a hold that shrinks below what it holds simply takes nothing more
--- until it is unloaded.
---@param capacity number
function PlayerCargo:setCapacity(capacity)
    self:get():setCapacity(math.max(0, capacity or 0))
end

--- The hold itself, which the trade system puts goods into and takes them
--- out of.
---@return StockComponent
function PlayerCargo:get()
    if not self.stock then self:reset() end
    return self.stock
end

---@param itemId integer
---@return integer
function PlayerCargo:count(itemId)
    return self:get():count(itemId)
end

---@param itemId integer
---@param units integer
---@return integer added
function PlayerCargo:add(itemId, units)
    return self:get():add(itemId, units)
end

---@param itemId integer
---@param units integer
---@return integer removed
function PlayerCargo:remove(itemId, units)
    return self:get():remove(itemId, units)
end

--- Everything held, `{ item, units }` in item order.
---@return table[]
function PlayerCargo:list()
    return self:get():list()
end

---@return number used, number capacity
function PlayerCargo:getLoad()
    local stock = self:get()
    return stock:getUsedMass(), stock:getCapacity() or math.huge
end

--- "1,200 / 2,400 t" for the HUD.
---@return string
function PlayerCargo:describeLoad()
    local used, capacity = self:getLoad()
    local function thousands(n)
        local s = tostring(math.floor(n))
        return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
    end
    return string.format("%s / %s t", thousands(used), thousands(capacity))
end

--- How full it is, 0..1.
---@return number
function PlayerCargo:getFraction()
    local used, capacity = self:getLoad()
    if capacity <= 0 or capacity == math.huge then return 0 end
    return math.min(1, used / capacity)
end

---@return boolean
function PlayerCargo:isEmpty()
    return self:get():isEmpty()
end

return PlayerCargo
