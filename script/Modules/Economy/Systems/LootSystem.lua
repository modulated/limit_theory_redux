local Registry = require("Core.ECS.Registry")
local Items = require("Shared.Registries.Items")
local PhysicsComponents = require("Modules.Physics.Components")

--- What wrecks leave behind: cargo canisters floating where a ship died, and
--- the player's ship pulling them in.
---
--- A canister holds what the wreck's loot table rolled (res/data/loot.toml,
--- LootData). Within `tractorRange` of the player's ship it is drawn in at
--- `pullSpeed`; at `collectRange` its goods go into the hold, as much as there
--- is room for. Whatever does not fit stays in the canister, with a warning
--- (every `fullWarningInterval` seconds while the ship sits by it), until
--- room is made or the canister drifts off: they last `lifetime` seconds.
---
--- Canisters belong to their system's scene: a jump clears them.
---@class LootSystem
local LootSystem = {
    ---@type table[] { entity, body, contents = { {id, units} }, age, warnedAt }
    canisters = {},
    world = nil,
    count = 0,
}

---@return table Config.game.loot
local function cfg()
    return Config.game.loot
end

local model -- built once: a small box in a bright, flat colour

--- The canister's look: built on first use (the engine must be up).
---@return MeshWithMaterial[]
local function canisterModel()
    if model then return model end
    local Materials = require("Shared.Registries.Materials")
    local mesh = Mesh.Box(2)
    mesh:scale(1.0, 0.6, 0.6)
    local material = Materials.DebugColor:instance()
    local color = material:params().color
    local c = cfg().color
    color.x, color.y, color.z = c[1], c[2], c[3]
    material:commit()
    model = { { mesh = mesh, material = material } }
    return model
end

--- Make the entity for a canister. Replaced by the tools that run this
--- without the engine.
---@param position table {x, y, z}
---@param seed integer
---@return Entity entity, table body
function LootSystem.createEntity(position, seed)
    local PhysicalEntity = require("Modules.PhysicalEntity")
    local Rendering = require("Modules.Rendering.Components")
    local c = cfg().color
    local entity = PhysicalEntity("LootCanister", seed,
        PhysicsComponents.RigidBody(),
        Rendering.PointLight(Color(c[1], c[2], c[3], 1.0), cfg().lightRadius, cfg().lightIntensity),
        Rendering.Render(canisterModel()))
    local rb = RigidBody.CreateBox()
    rb:setKinematic(true)
    rb:setCollidable(false)
    rb:setPos(Position(position.x, position.y, position.z))
    rb:setScale(cfg().scale)
    entity:get(PhysicsComponents.RigidBody):setRigidBody(rb)
    entity:get(PhysicsComponents.Transform):setPos(Position(position.x, position.y, position.z))
    entity:get(PhysicsComponents.Transform):setScale(cfg().scale)
    return entity, rb
end

--- Take a canister's entity out of the scene. Replaced by the tools.
---@param canister table
function LootSystem.destroyEntity(canister)
    if LootSystem.world and canister.inWorld then
        LootSystem.world:removeRigidBody(canister.body)
    end
    if canister.entity and canister.entity:isValid() then
        Registry:destroyEntity(canister.entity, Enums.Registry.EntityDestroyMode.DestroyChildren)
    end
end

--- What a list of goods says: "Hull Scrap x12, Pulse Turret".
---@param contents table[] { {id, units} }
---@return string
function LootSystem.describe(contents)
    local parts = {}
    for _, entry in ipairs(contents) do
        if entry.units > 0 then
            local def = Items:getDefinition(entry.id)
            local name = def and def.displayName or ("item " .. entry.id)
            parts[#parts + 1] = entry.units > 1 and string.format("%s x%d", name, entry.units) or name
        end
    end
    return table.concat(parts, ", ")
end

--- The world canisters' bodies go into, and the game whose labelled things
--- they are listed with (`game.labeledEntities`, which a scene replaces).
---@param world table|nil Physics
---@param game table|nil
function LootSystem:attach(world, game)
    self.world = world
    LootSystem.world = world
    self.game = game
end

local function labels(self)
    return self.game and self.game.labeledEntities
end

--- Drop a canister of `contents` at `position`. Nothing to drop, no canister.
---@param position table {x, y, z}
---@param contents table[] { {id, units} }
---@return table|nil canister
function LootSystem:drop(position, contents)
    local any = false
    for _, entry in ipairs(contents) do
        if entry.units > 0 then any = true end
    end
    if not any then return nil end
    self.count = self.count + 1
    local entity, body = LootSystem.createEntity(position, 104729 * self.count + 7)
    local canister = { entity = entity, body = body, contents = contents, age = 0 }
    if self.world and body then
        self.world:addRigidBody(body)
        canister.inWorld = true
    end
    canister.label = { entity = entity, label = "Cargo: " .. LootSystem.describe(contents),
                       color = cfg().color }
    local list = labels(self)
    if list then list[#list + 1] = canister.label end
    self.canisters[#self.canisters + 1] = canister
    return canister
end

---@param index integer
function LootSystem:removeAt(index)
    local canister = table.remove(self.canisters, index)
    if not canister then return end
    local list = labels(self)
    for i = #(list or {}), 1, -1 do
        if list[i] == canister.label then table.remove(list, i) end
    end
    LootSystem.destroyEntity(canister)
end

--- Every canister gone (a jump, a new game).
function LootSystem:clear()
    for i = #self.canisters, 1, -1 do self:removeAt(i) end
    self.canisters = {}
end

--- Each frame: canisters age, the ones near the ship are drawn in, and the
--- ones that reach it are emptied into the hold.
---@param dt number
---@param shipPos table|nil the player's ship's position (nil: docked, jumping, dead)
---@param hold StockComponent|nil where collected goods go
---@param now number game time (for the hold-full warning)
---@return table[] events { text, color }
function LootSystem:update(dt, shipPos, hold, now)
    local c = cfg()
    local events = {}
    for i = #self.canisters, 1, -1 do
        local canister = self.canisters[i]
        canister.age = canister.age + dt
        if canister.age > c.lifetime or not (canister.entity and canister.entity:isValid()) then
            self:removeAt(i)
        elseif shipPos and hold then
            local p = canister.body:getPos()
            local dx, dy, dz = shipPos.x - p.x, shipPos.y - p.y, shipPos.z - p.z
            local dist = math.sqrt(dx * dx + dy * dy + dz * dz)
            if dist <= c.collectRange then
                self:collect(canister, hold, now, events)
                if canister.empty then self:removeAt(i) end
            elseif dist <= c.tractorRange then
                -- Drawn in, faster the closer it gets, never past the ship
                local step = math.min(dist - c.collectRange * 0.5,
                    c.pullSpeed * dt * (1 + 2 * (1 - dist / c.tractorRange)))
                if not canister.full or canister.full ~= hold:getUsedMass() then
                    local f = step / dist
                    local np = { x = p.x + dx * f, y = p.y + dy * f, z = p.z + dz * f }
                    canister.body:setPos(Position(np.x, np.y, np.z))
                    local transform = canister.entity:get(PhysicsComponents.Transform)
                    if transform then transform:setPos(Position(np.x, np.y, np.z)) end
                end
            end
        end
    end
    return events
end

--- Put what fits of a canister into the hold.
---@param canister table
---@param hold StockComponent
---@param now number
---@param events table[]
function LootSystem:collect(canister, hold, now, events)
    local taken, left = {}, {}
    for _, entry in ipairs(canister.contents) do
        if entry.units > 0 then
            local added = hold:add(entry.id, entry.units)
            if added > 0 then taken[#taken + 1] = { id = entry.id, units = added } end
            entry.units = entry.units - added
            if entry.units > 0 then left[#left + 1] = entry end
        end
    end
    if #taken > 0 then
        events[#events + 1] = { text = "Collected: " .. LootSystem.describe(taken), color = { 0.55, 1.0, 0.6 } }
    end
    if #left == 0 then
        canister.empty = true
        return
    end
    canister.label.label = "Cargo: " .. LootSystem.describe(left)
    -- What is left waits for room; the ship is told so, now and then
    canister.full = hold:getUsedMass()
    if not canister.warnedAt or now - canister.warnedAt >= cfg().fullWarningInterval then
        canister.warnedAt = now
        events[#events + 1] = {
            text = "Hold full: " .. LootSystem.describe(left) .. " left in the canister.",
            color = { 1.0, 0.55, 0.3 },
            warning = true,
        }
    end
end

return LootSystem
