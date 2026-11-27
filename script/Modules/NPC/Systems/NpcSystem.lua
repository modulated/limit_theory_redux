local PhysicsComponents = require("Modules.Physics.Components")
local CoreComponents = require("Modules.Core.Components")
local ConstructComponents = require("Modules.Constructs.Components")
local NpcComponents = require("Modules.NPC.Components")
local Factions = require("Modules.NPC.Factions")
local Think = require("Modules.NPC.Jobs.Think")
local GunshipRecipe = require("Modules.NPC.Managers.GunshipRecipe")
local ArmedShipBuilder = require("Modules.Constructs.Managers.ArmedShipBuilder")
local WeaponBattery = require("Modules.Constructs.Systems.WeaponBattery")
local MiningField = require("Modules.NPC.Managers.MiningField")
local RenderComp = require("Modules.Rendering.Components").Render
local EconomyComponents = require("Modules.Economy.Components")

--- The star system's NPC ships: it builds them, gives them jobs (Think),
--- runs their action stacks, flies them, and removes the dead and the ones
--- that left. One per game (`game.npcs`), like the weapon combat system;
--- `clear()` when the scene goes.
---
--- NPC ships are kinematic: NpcSystem moves them itself (accelerate toward
--- the pilot's goal, slow down on arrival, turn toward the way it flies), so
--- they fly the same on every machine and frame rate. Their weapons are a
--- WeaponBattery like any armed ship's: it aims and fires at the hostile
--- teams in range by itself.
---
--- It is also the pilots' view of the world (`ctx` in the actions): the
--- system's places, the ships around, an RNG.
---@class NpcSystem
---@overload fun(game: table): NpcSystem
local NpcSystem = Class("NpcSystem", function(self, game)
    self.game = game
    self.records = {}
    self.places = { stations = {}, gates = {}, pointsOfInterest = {} }
    self.rng = RNG.Create(1)
    self.player = nil
    self.playerHidden = false   -- docked: not a contact at all
    self.playerDetection = 1    -- cloaked: seen only this fraction as far
    self.spawnCount = 0
    self.mining = MiningField()
    self.byEntity = {} -- entity -> record
end)

local SIZE_CLASS = {
    small = Enums.Target.SizeClass.Small,
    medium = Enums.Target.SizeClass.Medium,
    large = Enums.Target.SizeClass.Large,
}

-------------------------------------------------------------------------------
-- The world the pilots see

--- The system's places, where jobs send the pilots.
---@param places { stations: table[], docks: table[], gates: JumpGatePlacement[], pointsOfInterest: table[], belts: Entity[] }
function NpcSystem:setPlaces(places)
    self.places = places
end

--- How visible the player's ship is to the pilots: hidden (docked) or seen
--- only `detection` times as far (cloaked).
---@param hidden boolean
---@param detection number
function NpcSystem:setPlayerVisibility(hidden, detection)
    self.playerHidden = hidden
    self.playerDetection = detection
end

--- The player's ship: a contact like the NPCs (faction "player").
---@param entity Entity|nil
function NpcSystem:setPlayer(entity)
    self.player = entity and { entity = entity, faction = Factions.Player } or nil
end

local function isEntity(target)
    return type(target) == "table" and target.isValid ~= nil
end

--- Where a target is: a position {x, y, z} as it is, a ship's body
--- position; nil for a ship that is gone.
function NpcSystem:positionOf(target)
    if not isEntity(target) then return target end
    if not target:isValid() then return nil end
    local bodyComponent = target:get(PhysicsComponents.RigidBody)
    local body = bodyComponent and bodyComponent:getRigidBody()
    return body and body:getPos() or nil
end

--- A ship that exists and isn't destroyed.
function NpcSystem:isAlive(entity)
    if not isEntity(entity) or not entity:isValid() then return false end
    local health = entity:get(CoreComponents.Health)
    return not (health and health:isDestroyed())
end

---@param npc table
---@param pos table {x, y, z}
---@return number
function NpcSystem:distance(npc, pos)
    local p = npc.body:getPos()
    local dx, dy, dz = p.x - pos.x, p.y - pos.y, p.z - pos.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Every ship a pilot can see: the NPCs and the player.
function NpcSystem:contacts()
    local list = {}
    for _, record in ipairs(self.records) do
        if not record.dead and not record.pilot.docked then list[#list + 1] = record end
    end
    if self.player and not self.playerHidden and self:isAlive(self.player.entity) then
        self.player.detection = self.playerDetection
        list[#list + 1] = self.player
    end
    return list
end

--- The nearest ship within `range` whose faction is in `factions` (in that
--- order of preference: a ship of an earlier faction wins over a nearer one
--- of a later), or nil.
---@param npc table
---@param range number
---@param factions string[]
---@return Entity|nil
function NpcSystem:findShip(npc, range, factions)
    local rank = {}
    for i, faction in ipairs(factions) do rank[faction] = i end
    local best, bestRank, bestDist = nil, math.huge, math.huge
    -- Sensors (Legacy Elements/Components/Sensor): a better rating sees
    -- further; a cloaked contact is seen only a fraction as far
    local sensor = npc.pilot and npc.pilot.stats.sensor or 1
    for _, contact in ipairs(self:contacts()) do
        local r = rank[contact.faction]
        if r and contact.entity ~= npc.entity then
            local pos = self:positionOf(contact.entity)
            local d = pos and self:distance(npc, pos) or math.huge
            local reach = range * sensor * (contact.detection or 1)
            if d <= reach and (r < bestRank or (r == bestRank and d < bestDist)) then
                best, bestRank, bestDist = contact.entity, r, d
            end
        end
    end
    return best
end

--- The nearest hostile ship within `range` (preferring the factions in
--- `prefer`, in order), or nil.
---@param npc table
---@param range number
---@param prefer string[]|nil
---@return Entity|nil
function NpcSystem:findHostile(npc, range, prefer)
    local factions = {}
    for _, faction in ipairs(prefer or {}) do
        if Factions.isHostile(npc.faction, faction) then factions[#factions + 1] = faction end
    end
    for _, faction in ipairs(Factions.hostileTeams(npc.faction)) do
        local listed = false
        for _, f in ipairs(factions) do listed = listed or f == faction end
        if not listed then factions[#factions + 1] = faction end
    end
    return self:findShip(npc, range, factions)
end

local function stackHas(npc, field)
    for _, action in ipairs(npc.pilot.actions) do
        if action[field] then return true end
    end
    return false
end

function NpcSystem:isFighting(npc) return stackHas(npc, "isAttack") end
function NpcSystem:isFleeing(npc) return stackHas(npc, "isFlee") end

--- Whether a guard's charge is still there to guard (alive, in the system).
---@param charge table|nil a record
function NpcSystem:isGuarding(charge)
    return charge ~= nil and not charge.dead and not charge.removed and not charge.pilot.leaving
end

--- Whether a ship may dock at a station (Legacy Dockable: not banned): the
--- station is there and its owner isn't hostile to the ship's faction.
---@param npc table record
---@param dock table place { entity, position, radius, faction }
function NpcSystem:canDock(npc, dock)
    return dock ~= nil and dock.entity:isValid() and not Factions.isHostile(dock.faction, npc.faction)
end

--- Where ships dock and undock: above the station by its radius (Legacy
--- DockAt put the dock 1.25 radii along the station's up).
function NpcSystem:dockingPoint(dock)
    local p = dock.position
    return { x = p.x, y = p.y + dock.radius * 1.25 + 0.05, z = p.z }
end

--- The nearest station a ship may dock at, or nil.
function NpcSystem:nearestDock(npc)
    local best, bestDist = nil, math.huge
    for _, dock in ipairs(self.places.docks or {}) do
        if self:canDock(npc, dock) then
            local d = self:distance(npc, dock.position)
            if d < bestDist then best, bestDist = dock, d end
        end
    end
    return best
end

--- The nearest station a miner may sell a hold of `itemId` at: any
--- generated station (it takes all of it into its store), or one of the
--- player's outposts if the owner bids for at least `units` of it at the
--- miners' floor price or better (an outpost buys only what is bid for).
---@param npc table
---@param itemId integer|nil
---@param units integer
function NpcSystem:sellDock(npc, itemId, units)
    local MarketSystem = require("Modules.Economy.Systems.MarketSystem")
    local best, bestDist = nil, math.huge
    for _, dock in ipairs(self.places.docks or {}) do
        local ok = self:canDock(npc, dock)
        if ok and dock.outpost then
            ok = itemId ~= nil and MarketSystem:playerDemand(dock.entity, itemId,
                MarketSystem:minerFloor(itemId)) >= math.max(1, units)
        end
        if ok then
            local d = self:distance(npc, dock.position)
            if d < bestDist then best, bestDist = dock, d end
        end
    end
    return best
end

local function showLabel(self, record, shown)
    local labels = self.game.labeledEntities
    for i = #labels, 1, -1 do
        if labels[i] == record.labelEntry then table.remove(labels, i) end
    end
    if shown then table.insert(labels, record.labelEntry) end
end

--- A ship docks (Legacy Dockable:addDocked): inside the station, hidden,
--- out of reach of weapons, its own weapons quiet.
function NpcSystem:dock(npc, dock)
    npc.pilot.docked = dock
    -- A worker that docks is one of the station's hands until it leaves
    if npc.role == "worker" and dock.entity and dock.entity:isValid() then
        local workforce = dock.entity:get(EconomyComponents.Workforce)
        if workforce then workforce:arrive(npc) end
    end
    npc.pilot:clearGoal()
    npc.pilot.velocity.x, npc.pilot.velocity.y, npc.pilot.velocity.z = 0, 0, 0
    local render = npc.entity:get(RenderComp)
    if render then render:setVisible(false) end
    local targetable = npc.entity:get(ConstructComponents.Targetable)
    if targetable then targetable:setEnabled(false) end
    npc.body:setCollidable(false)
    if npc.battery then npc.battery:setAIActive(false) end
    npc.body:setPos(Position(dock.position.x, dock.position.y, dock.position.z))
    showLabel(self, npc, false)
end

--- A docked ship comes out at the docking point (Legacy Undock).
function NpcSystem:undock(npc)
    local dock = npc.pilot.docked
    if not dock then return end
    if npc.role == "worker" and dock.entity and dock.entity:isValid() then
        local workforce = dock.entity:get(EconomyComponents.Workforce)
        if workforce then workforce:leave(npc) end
    end
    npc.pilot.docked = nil
    local p = self:dockingPoint(dock)
    npc.body:setPos(Position(p.x, p.y, p.z))
    local render = npc.entity:get(RenderComp)
    if render then render:setVisible(true) end
    local targetable = npc.entity:get(ConstructComponents.Targetable)
    if targetable then targetable:setEnabled(true) end
    npc.body:setCollidable(true)
    if npc.battery then npc.battery:setAIActive(true) end
    showLabel(self, npc, true)
end

--- Whether a pilot can still see a ship it is after: the player's ship
--- vanishes when it docks, and when cloaked is seen only close by (half
--- again its cloaked detection range, so a chase isn't dropped at once).
---@param npc table
---@param entity Entity
---@return boolean
function NpcSystem:canSee(npc, entity)
    local record = self.byEntity[entity]
    if record then return not record.pilot.docked end -- inside a station
    if not self.player or entity ~= self.player.entity then return true end
    if self.playerHidden then return false end
    if self.playerDetection >= 1 then return true end
    local pos = self:positionOf(entity)
    if not pos then return false end
    local stats = npc.pilot.stats
    local reach = (stats.detectRange or 6) * (stats.sensor or 1) * self.playerDetection * 1.5
    return self:distance(npc, pos) <= reach
end

--- The NPC record of a ship, or nil (not an NPC, or gone).
---@param entity Entity
---@return table|nil
function NpcSystem:recordOf(entity)
    return self.byEntity[entity]
end

--- After the standings changed: who each armed NPC's weapons engage.
function NpcSystem:refreshHostility()
    for _, record in ipairs(self.records) do
        if record.battery then
            local set = {}
            for _, team in ipairs(Factions.hostileTeams(record.faction)) do set[team] = true end
            record.battery.hostileTeams = set
        end
    end
end

-- Where guards keep station, in the charge's frame (forward is -Z): beside
-- it and a little behind, alternating sides
local function guardSlot(index)
    local side = (index % 2 == 1) and -1 or 1
    local row = math.ceil(index / 2)
    return { x = side * 0.6 * row, y = 0.12, z = 0.45 * row }
end

--- A guard starts guarding a ship.
---@param guard table record
---@param charge table record
function NpcSystem:assignGuard(guard, charge)
    charge.guards = charge.guards or {}
    table.insert(charge.guards, guard)
    guard.isGuard = true
    guard.charge = charge
    guard.slot = guardSlot(#charge.guards)
end

--- The nearest hauler of the guard's faction that has room for another
--- guard (its role's escort count), or nil.
---@param guard table record
---@return table|nil
function NpcSystem:findUnguarded(guard)
    local best, bestDist = nil, math.huge
    for _, record in ipairs(self.records) do
        local escorts = record.pilot.stats.escorts
        if record ~= guard and record.faction == guard.faction and escorts
            and self:isGuarding(record) then
            local live = 0
            for _, g in ipairs(record.guards or {}) do
                if not g.dead and not g.removed then live = live + 1 end
            end
            if live < escorts.max then
                local d = self:distance(guard, record.body:getPos())
                if d < bestDist then best, bestDist = record, d end
            end
        end
    end
    return best
end

-------------------------------------------------------------------------------
-- Ships

--- Build an NPC ship of a role (Config.game.npc.roles) and its pilot. A
--- ship that fails to build is logged and skipped: the game goes on without
--- it.
---@param role string
---@param position table {x, y, z}
---@param seed integer
---@return table|nil record
function NpcSystem:spawn(role, position, seed)
    local stats = Config.game.npc.roles[role]
    if not stats then
        Log.Warn("NPC: no role %s in Config.game.npc.roles", tostring(role))
        return nil
    end
    local faction = stats.faction
    local game = self.game
    local sizeClass = SIZE_CLASS[stats.sizeClass] or Enums.Target.SizeClass.Medium

    local ok, result = pcall(function()
        local record = { faction = faction, role = role }
        if stats.gunship then
            local construction = ArmedShipBuilder:build(GunshipRecipe.build(seed, faction, stats), {
                constructManager = game.constructManager,
                shipConfig = {
                    position = Position(position.x, position.y, position.z),
                    scale = stats.scale,
                    isKinematic = true,
                },
            })
            construction.shipBody:setCollidable(true)
            record.handle = construction.shipHandle
            record.entity = construction.ship
            record.body = construction.shipBody
            record.entity:add(ConstructComponents.Targetable(faction, sizeClass))
            record.battery = game.weaponCombat:addBattery(WeaponBattery(construction, {
                name = (stats.label or role) .. " " .. self.spawnCount,
                aiActive = true,
                team = faction,
                hostileTeams = Factions.hostileTeams(faction),
            }))
        else
            record.handle = game.constructManager:createTarget({
                seed = seed,
                shipType = Enums.ShipType.Basic,
                hull = stats.hull,
                position = Position(position.x, position.y, position.z),
                scale = stats.scale,
                isKinematic = true,
                collidable = true,
                maxHealth = stats.maxHealth,
                maxShield = stats.maxShield,
                shieldRegen = stats.shieldRegen,
                sizeClass = sizeClass,
                team = faction,
            })
            record.entity = record.handle.root
            record.body = record.handle.rigidBody
        end
        record.pilot = NpcComponents.Pilot(faction, stats)
        record.entity:add(record.pilot)
        record.cargo = { count = 0, capacity = stats.cargo or 10 }
        return record
    end)
    if not ok then
        Log.Error("NPC: could not build a %s (seed %s): %s", role, tostring(seed), tostring(result))
        return nil
    end

    local record = result
    self.spawnCount = self.spawnCount + 1
    local r, g, b = Factions.color(faction)
    record.label = stats.label or Factions.name(faction)
    record.labelEntry = { entity = record.entity, label = record.label, color = { r, g, b } }
    table.insert(game.labeledEntities, record.labelEntry)
    table.insert(self.records, record)
    self.byEntity[record.entity] = record
    return record
end

--- Remove an NPC ship now (its battery goes with it on the next weapons step).
---@param record table
function NpcSystem:remove(record)
    record.removed = true
    self.byEntity[record.entity] = nil
    for i, r in ipairs(self.records) do
        if r == record then table.remove(self.records, i) break end
    end
    for i = #self.game.labeledEntities, 1, -1 do
        if self.game.labeledEntities[i] == record.labelEntry then
            table.remove(self.game.labeledEntities, i)
        end
    end
    if record.battery then record.battery:setAIActive(false) end
    if self.game.player and self.game.player:getOrbitTarget() == record.entity then
        self.game.player:setOrbitTarget(nil)
    end
    self.game.constructManager:destroy(record.handle)
end

--- How many live NPCs of a role the system has (guards not counted: they
--- come with their charges).
function NpcSystem:count(role)
    local n = 0
    for _, record in ipairs(self.records) do
        if record.role == role and not record.dead and not record.isGuard then n = n + 1 end
    end
    return n
end

--- The live NPCs as map entries: { entity, label, color }.
---@return table[]
function NpcSystem:mapEntries()
    local list = {}
    for _, record in ipairs(self.records) do
        if not record.dead and not record.pilot.docked then
            list[#list + 1] = { entity = record.entity, label = record.label, color = record.labelEntry.color,
                faction = record.faction }
        end
    end
    return list
end

--- Remove every NPC (the scene is going).
function NpcSystem:clear()
    for i = #self.records, 1, -1 do
        self:remove(self.records[i])
    end
    self.records = {}
    self.player = nil
end

-------------------------------------------------------------------------------
-- Populating a system

--- A spot near `pos`, spread by up to `spread`.
function NpcSystem:near(pos, spread)
    local dir = self.rng:getDir3()
    local r = spread * (0.4 + 0.6 * self.rng:getUniform())
    return { x = pos.x + dir.x * r, y = pos.y + dir.y * r * 0.3, z = pos.z + dir.z * r }
end

--- Where a ship of a role starts: haulers that stop at hideouts and armed
--- pirates at gates and belts (where traffic passes); the rest at stations.
function NpcSystem:startingSpot(role)
    local places, stats = self.places, Config.game.npc.roles[role]
    local pool = {}
    if stats.faction == Factions.Pirate then
        for _, gate in ipairs(places.gates) do pool[#pool + 1] = gate.position end
        for _, p in ipairs(places.pointsOfInterest) do pool[#pool + 1] = p end
    else
        for _, p in ipairs(places.stations) do pool[#pool + 1] = p end
        if #pool == 0 then
            for _, p in ipairs(places.pointsOfInterest) do pool[#pool + 1] = p end
        end
    end
    if #pool == 0 then return nil end
    return self:near(pool[self.rng:getInt(1, #pool)], Config.game.npc.spawnSpread)
end

--- A ship of a role and, if the role has escorts, its guards beside it.
---@param role string
---@param spot table {x, y, z}
---@return table|nil record
function NpcSystem:spawnWithEscorts(role, spot)
    local record = self:spawn(role, spot, self.rng:get64())
    local escorts = record and record.pilot.stats.escorts
    if escorts then
        for _ = 1, self.rng:getInt(escorts.min, escorts.max) do
            local guard = self:spawn(escorts.role, self:near(spot, 0.6), self.rng:get64())
            if guard then self:assignGuard(guard, record) end
        end
    end
    return record
end

-- The roles in the order a system is filled and topped up
local ROLES = { "security", "trader", "miner", "pirate", "pirateScout", "pirateMerchant" }

--- Fill the system with the NPCs its hostility level calls for.
---@param level table Config.game.hostility.levels[n]
---@param seed integer the system's seed
function NpcSystem:populate(level, seed)
    self.rng = RNG.Create(seed + 3)
    self.mining:build(self.places.belts or {}, seed + 4)
    self.level = level
    self.replenish = Config.game.npc.replenishInterval
    for _, role in ipairs(ROLES) do
        for _ = 1, level.npcs[role] or 0 do
            local spot = self:startingSpot(role)
            if spot then self:spawnWithEscorts(role, spot) end
        end
    end
    local counts = {}
    for _, record in ipairs(self.records) do
        counts[record.role] = (counts[record.role] or 0) + 1
    end
    local parts = {}
    for role, n in pairs(counts) do parts[#parts + 1] = string.format("%d %s", n, role) end
    table.sort(parts)
    Log.Info("NPC: %s system: %s", level.name, table.concat(parts, ", "))
end

--- One missing ship (below the level's count) arrives through a gate, with
--- its escorts.
function NpcSystem:replenishOne()
    local level = self.level
    if not level or #self.places.gates == 0 then return end
    for _, role in ipairs({ "pirate", "pirateScout", "pirateMerchant", "trader", "miner", "security" }) do
        if self:count(role) < (level.npcs[role] or 0) then
            local gate = self.places.gates[self.rng:getInt(1, #self.places.gates)]
            self:spawnWithEscorts(role, self:near(gate.position, gate.radius * 3))
            return
        end
    end
end

-------------------------------------------------------------------------------
-- Each frame

local function length(x, y, z) return math.sqrt(x * x + y * y + z * z) end

--- Fly a ship toward its pilot's goal: accelerate up to top speed, brake to
--- stop at the goal, turn toward the way it is going.
---@param record table
---@param dt number
local function steer(record, dt)
    local pilot, body = record.pilot, record.body
    local stats = pilot.stats
    local v = pilot.velocity
    local pos = body:getPos()

    local wx, wy, wz = 0, 0, 0
    local goal = pilot.goal
    if goal then
        local dx, dy, dz = goal.x - pos.x, goal.y - pos.y, goal.z - pos.z
        local dist = length(dx, dy, dz)
        if dist > goal.range and dist > 1e-9 then
            local top = stats.maxSpeed * goal.speedFactor
            -- Slow down so as to stop at the goal: v² = 2·a·d
            local speed = math.min(top, math.sqrt(2 * stats.accel * (dist - goal.range)))
            wx, wy, wz = dx / dist * speed, dy / dist * speed, dz / dist * speed
        end
    end

    -- Change velocity toward the wanted one, at most accel·dt
    local cx, cy, cz = wx - v.x, wy - v.y, wz - v.z
    local change = length(cx, cy, cz)
    local maxChange = stats.accel * dt
    if change > maxChange then
        local k = maxChange / change
        cx, cy, cz = cx * k, cy * k, cz * k
    end
    v.x, v.y, v.z = v.x + cx, v.y + cy, v.z + cz

    local newPos = Position(pos.x + v.x * dt, pos.y + v.y * dt, pos.z + v.z * dt)
    body:setPos(newPos)
    local transform = record.entity:get(PhysicsComponents.Transform)
    if transform then transform:setPos(newPos) end

    -- Face the way it flies
    local speed = length(v.x, v.y, v.z)
    if speed > 0.01 then
        local look = Vec3f(v.x / speed, v.y / speed, v.z / speed)
        local up = math.abs(look.y) > 0.99 and Vec3f(1, 0, 0) or Vec3f(0, 1, 0)
        local target = Quat.FromLookUp(look, up)
        local f = 1 - math.exp(-stats.turnRate * dt)
        body:setRot(body:getRot():slerp(target, f))
    end
end

--- Before the physics step: jobs, actions, flying.
---@param dt number
function NpcSystem:update(dt)
    if dt <= 0 then return end
    self.mining:update(dt)

    for _, record in ipairs(self.records) do
        if not record.dead then
            -- Shields recharge (DefenseComponent:update had no caller)
            local defense = record.entity:isValid() and record.entity:get(ConstructComponents.Defense)
            if defense and not record.dead then defense:update(dt) end

            if not self:isAlive(record.entity) then
                -- Destroyed: the weapon system explodes it; the wreck goes later
                record.dead = Config.game.npc.wreckTime
                record.pilot:clearActions(record)
                record.pilot:clearGoal()
                if record.battery then record.battery:setAIActive(false) end
            else
                local pilot = record.pilot
                -- Think: an idle pilot gets a job
                if pilot:isIdle() then
                    local job = Think.chooseJob(record, self)
                    if job then pilot:pushAction(job) end
                end
                -- Every action watches; the top one acts
                for i = #pilot.actions, 1, -1 do
                    local action = pilot.actions[i]
                    if action then action:onUpdatePassive(record, self, dt) end
                end
                local top = pilot:currentAction()
                if top then
                    if not top.started then
                        top.started = true
                        top:onStart(record, self)
                    end
                    top:onUpdate(record, self, dt)
                end
                if not pilot.docked then steer(record, dt) end
                record.labelEntry.label = record.label .. " · " .. pilot:getActivity()
            end
        end
    end

    -- Wrecks go after their explosion; ships that left through a gate go now
    for i = #self.records, 1, -1 do
        local record = self.records[i]
        if record.dead then
            record.dead = record.dead - dt
            if record.dead <= 0 then self:remove(record) end
        elseif record.pilot.leaving then
            -- Its guards jump out with it
            for _, guard in ipairs(record.guards or {}) do
                if not guard.dead and not guard.removed then guard.pilot.leaving = true end
            end
            self:remove(record)
        end
    end

    -- Reinforcements
    if self.level then
        self.replenish = self.replenish - dt
        if self.replenish <= 0 then
            self.replenish = Config.game.npc.replenishInterval
            self:replenishOne()
        end
    end
end

return NpcSystem
