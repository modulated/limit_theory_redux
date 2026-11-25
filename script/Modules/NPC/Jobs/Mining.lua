local Action = require("Modules.NPC.Actions.Action")
local Actions = require("Modules.NPC.Actions")
local Factions = require("Modules.NPC.Factions")
local StationTradeSystem = require("Modules.Economy.Systems.StationTradeSystem")

--- Selling the hold at the station it is docked at (instant; the Wait before
--- it is the time it takes), the port of Legacy's sale to the station's
--- trader. The ore goes into the station's own store, which is where the ore
--- on a market comes from: mine it out of the belt, and the shelves of the
--- station fill and its prices fall.
---@class NpcSellCargo: NpcAction
local SellCargo = Subclass("NpcSellCargo", Action, function(self) end)
function SellCargo:getName() return "Selling" end
function SellCargo:onUpdate(npc, ctx, dt)
    local units = npc.cargo.count or 0
    if units > 0 then
        local dock = npc.pilot.docked
        local station = dock and dock.entity
        local delivered = 0
        if station and station:isValid() and npc.cargo.itemId then
            delivered = StationTradeSystem:deliver(station, npc.cargo.itemId, units)
        end
        Log.Debug("NPC: %s sold %d %s (%d into the station's store)",
            npc.label, units, npc.cargo.item or "ore", delivered)
    end
    npc.cargo.count = 0
    self:finish(npc)
end

--- Miner job (Legacy Jobs/Mine): over and over, find a rock with ore, fly
--- to it, mine until the hold is full (MineAt), dock at the nearest station
--- that takes the ship, sell, undock. Runs from pirates on the way, like
--- the other haulers. Ends when there is nothing left to mine.
local SCAN_INTERVAL = 0.5

---@param npc table
---@param ctx table NpcSystem
---@return NpcAction|nil
return function(npc, ctx)
    local job = Actions.Repeat(function(miner, system)
        -- Let go of the last rock; take the nearest free one with ore
        if miner.rock and miner.rock.claimed == miner then miner.rock.claimed = nil end
        local rock = system.mining:findRock(miner.body:getPos())
        if not rock then return nil end
        rock.claimed = miner
        miner.rock = rock
        local list = {
            Actions.MoveTo(rock.position, rock.radius * 1.5 + 0.1, "Flying to the belt"),
            Actions.MineAt(rock, Config.game.mining.timePerUnit),
        }
        local dock = system:nearestDock(miner)
        if dock then
            table.insert(list, Actions.DockAt(dock))
            table.insert(list, Actions.Wait(Config.game.mining.sellTime, "Selling ore"))
            table.insert(list, SellCargo())
            table.insert(list, Actions.Undock())
        end
        return list
    end, "Mining")

    -- Watching for pirates while it works, like Transport
    function job:onUpdatePassive(miner, system, dt)
        self.scan = (self.scan or 0) - dt
        if self.scan > 0 or system:isFleeing(miner) or miner.pilot.docked then return end
        self.scan = SCAN_INTERVAL
        local stats = miner.pilot.stats
        local range = stats.fleeRange or 3
        local threat = system:findShip(miner, range, stats.fleeFrom or { Factions.Pirate })
        if threat then
            miner.pilot:pushAction(Actions.Flee(threat, range * 2.5))
        end
    end
    return job
end
