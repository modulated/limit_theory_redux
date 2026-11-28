--- The action bar: the number keys 1..`slots` (Config.game.actionBar), each
--- holding one thing the ship can do on command -- an active module in a
--- module slot ("m:<slot>"), or a tool on a weapon mount ("w:<mountId>"),
--- such as the mining laser.
---
--- Each ship keeps its own bar (`ship.actionBar`, slot -> ref, on the
--- PlayerFleet record), because a fit belongs to its ship. The player
--- arranges it by dragging one slot onto another (`move`); what is newly
--- fitted goes into the first free slot (`sync`), and what is no longer
--- fitted leaves it.
---@class ActionBar
local ActionBar = {}

---@return integer
function ActionBar.slots()
    return (Config.game.actionBar and Config.game.actionBar.slots) or 8
end

--- A module slot's ref.
---@param slot integer
---@return string
function ActionBar.moduleRef(slot)
    return "m:" .. tostring(slot)
end

--- A mount's ref.
---@param mountId string
---@return string
function ActionBar.mountRef(mountId)
    return "w:" .. tostring(mountId)
end

--- What a ref points at: "module", slot or "mount", mountId.
---@param ref string
---@return string|nil kind, integer|string|nil where
function ActionBar.parse(ref)
    if type(ref) ~= "string" then return nil end
    local kind, rest = ref:match("^(%a):(.+)$")
    if kind == "m" then return "module", tonumber(rest) end
    if kind == "w" then return "mount", rest end
    return nil
end

--- The ship's bar, made on first use.
---@param ship table PlayerFleet ship record
---@return table<integer, string>
function ActionBar.of(ship)
    ship.actionBar = ship.actionBar or {}
    return ship.actionBar
end

--- Bring the bar in line with what the ship can do: refs no longer there
--- leave their slots; new ones take the first free slot, in the order given.
--- Everything else stays where the player put it.
---@param ship table
---@param refs string[] what the ship can do now, in a sensible order
---@return boolean changed
function ActionBar.sync(ship, refs)
    local bar = ActionBar.of(ship)
    local present, onBar = {}, {}
    for _, ref in ipairs(refs) do present[ref] = true end
    local changed = false
    for slot, ref in pairs(bar) do
        if not present[ref] or slot > ActionBar.slots() then
            bar[slot] = nil
            changed = true
        else
            onBar[ref] = true
        end
    end
    for _, ref in ipairs(refs) do
        if not onBar[ref] then
            for slot = 1, ActionBar.slots() do
                if bar[slot] == nil then
                    bar[slot] = ref
                    onBar[ref] = true
                    changed = true
                    break
                end
            end
        end
    end
    return changed
end

--- Drag slot `from` onto slot `to`: they swap (onto an empty slot, it moves).
---@param ship table
---@param from integer
---@param to integer
---@return boolean moved
function ActionBar.move(ship, from, to)
    local bar = ActionBar.of(ship)
    local n = ActionBar.slots()
    if from == to or from < 1 or to < 1 or from > n or to > n or bar[from] == nil then return false end
    bar[from], bar[to] = bar[to], bar[from]
    return true
end

--- The slot a ref is in, or nil.
---@param ship table
---@param ref string
---@return integer|nil
function ActionBar.slotOf(ship, ref)
    for slot, r in pairs(ActionBar.of(ship)) do
        if r == ref then return slot end
    end
    return nil
end

return ActionBar
