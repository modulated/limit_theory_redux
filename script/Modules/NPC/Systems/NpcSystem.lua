local PhysicsComponents = require("Modules.Physics.Components")
local CoreComponents = require("Modules.Core.Components")
local ConstructComponents = require("Modules.Constructs.Components")
local NpcComponents = require("Modules.NPC.Components")
local Factions = require("Modules.NPC.Factions")
local Think = require("Modules.NPC.Jobs.Think")
local GunshipRecipe = require("Modules.NPC.Managers.GunshipRecipe")
local ArmedShipBuilder = require("Modules.Constructs.Managers.ArmedShipBuilder")
local WeaponBattery = require("Modules.Constructs.Systems.WeaponBattery")

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
    self.spawnCount = 0
end)

local SIZE_CLASS = {
    small = Enums.Target.SizeClass.Small,
    medium = Enums.Target.SizeClass.Medium,
    large = Enums.Target.SizeClass.Large,
}

-------------------------------------------------------------------------------
-- The world the pilots see

--- The system's places, where jobs send the pilots.
---@param places { stations: table[], gates: JumpGatePlacement[], pointsOfInterest: table[] }
function NpcSystem:setPlaces(places)
    self.places = places
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
        if not record.dead then list[#list + 1] = record end
    end
    if self.player and self:isAlive(self.player.entity) then
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
    for _, contact in ipairs(self:contacts()) do
        local r = rank[contact.faction]
        if r and contact.entity ~= npc.entity then
            local pos = self:positionOf(contact.entity)
            local d = pos and self:distance(npc, pos) or math.huge
            if d <= range and (r < bestRank or (r == bestRank and d < bestDist)) then
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

-------------------------------------------------------------------------------
-- Ships

--- Build an NPC ship and its pilot. A ship that fails to build is logged
--- and skipped: the game goes on without it.
---@param faction string
---@param position table {x, y, z}
---@param seed integer
---@return table|nil record
function NpcSystem:spawn(faction, position, seed)
    local stats = Config.game.npc[faction]
    if not stats then
        Log.Warn("NPC: no ship stats for faction %s", tostring(faction))
        return nil
    end
    local game = self.game
    local sizeClass = SIZE_CLASS[stats.sizeClass] or Enums.Target.SizeClass.Medium

    local ok, result = pcall(function()
        local record = { faction = faction }
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
                name = Factions.name(faction) .. " " .. self.spawnCount,
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
        return record
    end)
    if not ok then
        Log.Error("NPC: could not build a %s ship (seed %s): %s", faction, tostring(seed), tostring(result))
        return nil
    end

    local record = result
    self.spawnCount = self.spawnCount + 1
    local r, g, b = Factions.color(faction)
    record.labelEntry = { entity = record.entity, label = Factions.name(faction), color = { r, g, b } }
    table.insert(game.labeledEntities, record.labelEntry)
    table.insert(self.records, record)
    return record
end

--- Remove an NPC ship now (its battery goes with it on the next weapons step).
---@param record table
function NpcSystem:remove(record)
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

--- How many live NPCs of a faction the system has.
function NpcSystem:count(faction)
    local n = 0
    for _, record in ipairs(self.records) do
        if record.faction == faction and not record.dead then n = n + 1 end
    end
    return n
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

--- Where a ship of a faction starts: security and traders at stations,
--- pirates at gates and belts (where traffic passes).
function NpcSystem:startingSpot(faction)
    local places = self.places
    local pool = {}
    if faction == Factions.Pirate then
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

--- Fill the system with the NPCs its hostility level calls for.
---@param level table Config.game.hostility.levels[n]
---@param seed integer the system's seed
function NpcSystem:populate(level, seed)
    self.rng = RNG.Create(seed + 3)
    self.level = level
    self.replenish = Config.game.npc.replenishInterval
    for _, faction in ipairs({ Factions.Security, Factions.Trader, Factions.Pirate }) do
        for _ = 1, level.npcs[faction] or 0 do
            local spot = self:startingSpot(faction)
            if spot then self:spawn(faction, spot, self.rng:get64()) end
        end
    end
    Log.Info("NPC: %s system: %d security, %d traders, %d pirates", level.name,
        self:count(Factions.Security), self:count(Factions.Trader), self:count(Factions.Pirate))
end

--- One missing ship (below the level's count) arrives through a gate.
function NpcSystem:replenishOne()
    local level = self.level
    if not level or #self.places.gates == 0 then return end
    for _, faction in ipairs({ Factions.Pirate, Factions.Trader, Factions.Security }) do
        if self:count(faction) < (level.npcs[faction] or 0) then
            local gate = self.places.gates[self.rng:getInt(1, #self.places.gates)]
            self:spawn(faction, self:near(gate.position, gate.radius * 3), self.rng:get64())
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

    for _, record in ipairs(self.records) do
        if not record.dead then
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
                steer(record, dt)
                record.labelEntry.label = Factions.name(record.faction) .. " · " .. pilot:getActivity()
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
