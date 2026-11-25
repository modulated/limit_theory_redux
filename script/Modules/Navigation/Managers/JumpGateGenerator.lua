local Registry = require("Core.ECS.Registry")
local Materials = require("Shared.Registries.Materials")
local PhysicsComponents = require("Modules.Physics.Components")
local SpatialComponents = require("Modules.Spatial.Components")
local NavigationComponents = require("Modules.Navigation.Components")
local NavigationEntities = require("Modules.Navigation.Entities")
local GalaxyGenerator = require("Modules.Navigation.Managers.GalaxyGenerator")

--- Builds the jump gates of the played star system: one per link of its
--- galaxy node, gathered at one or two of the system's points of interest.
---
--- The model is a placeholder: a metal ring with a thin glowing ring on its
--- inner edge and four clamps, built here from a unit torus (ring radius 1,
--- in the XY plane, so ships fly through it along Z). The ring is turned to
--- face the direction of the system it leads to.
---@class JumpGateGenerator
local JumpGateGenerator = {}

local RING_TUBE = 0.08        -- the metal ring's tube radius (ring radius 1)
local GLOW_TUBE = 0.02        -- the glow ring's tube radius
local RING_SEGMENTS = 64      -- around the ring
local TUBE_SEGMENTS = 12      -- around the tube
local GLOW_COLOR = { 0.35, 0.85, 1.0 }

--- Add a torus around the Z axis to `mesh`: ring radius `R`, tube radius `r`.
---@param mesh Mesh
local function addTorus(mesh, R, r, ringSegments, tubeSegments)
    local base = mesh:getVertexCount()
    for i = 0, ringSegments do
        local u = (i / ringSegments) * 2 * math.pi
        local cu, su = math.cos(u), math.sin(u)
        for j = 0, tubeSegments do
            local v = (j / tubeSegments) * 2 * math.pi
            local cv, sv = math.cos(v), math.sin(v)
            local nx, ny, nz = cv * cu, cv * su, sv
            mesh:addVertex(R * cu + r * nx, R * su + r * ny, r * nz, nx, ny, nz,
                i / ringSegments, j / tubeSegments)
        end
    end
    -- Quads in increasing u then v: their normal is du × dv, which points out
    -- of the tube (the winding Mesh's own planes use).
    local stride = tubeSegments + 1
    for i = 0, ringSegments - 1 do
        for j = 0, tubeSegments - 1 do
            local a = base + i * stride + j
            mesh:addQuad(a, a + stride, a + stride + 1, a + 1)
        end
    end
end

--- Four blocks on the ring, like the clamps of a frame.
---@param mesh Mesh
local function addClamps(mesh)
    for k = 0, 3 do
        local angle = k * math.pi / 2 + math.pi / 4
        local clamp = Mesh.Box(2)
        clamp:scale(0.07, 0.16, 0.14)
        clamp:translate(1.0, 0, 0)
        clamp:rotateZ(angle)
        mesh:addMesh(clamp)
    end
end

--- The placeholder gate model, at unit size.
---@return MeshWithMaterial[] meshes
---@return Mesh frame the metal frame (for the physics shape)
function JumpGateGenerator:createModel()
    local frame = Mesh.Create()
    addTorus(frame, 1.0, RING_TUBE, RING_SEGMENTS, TUBE_SEGMENTS)
    addClamps(frame)

    local glow = Mesh.Create()
    addTorus(glow, 1.0 - RING_TUBE, GLOW_TUBE, RING_SEGMENTS, 6)
    local glowMaterial = Materials.DebugColor:instance()
    local color = glowMaterial:params().color
    color.x, color.y, color.z = GLOW_COLOR[1], GLOW_COLOR[2], GLOW_COLOR[3]
    glowMaterial:commit()

    return {
        { mesh = frame, material = Materials.Metal:instance() },
        { mesh = glow,  material = glowMaterial },
    }, frame
end

--- What a point of interest is and how big, for placing gates around it.
---@param entity Entity
---@param cfg table Config.game.jumpGates
---@return { entity: Entity, label: string, position: Position, distance: number }|nil
local function pointOfInterest(entity, cfg)
    local transform = entity:get(PhysicsComponents.Transform)
    if not transform then return nil end
    local name = tostring(entity)

    -- Bodies with a rigid body may have moved off their generated position
    local position = transform:getPos()
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    if rbCmp and rbCmp:getRigidBody() then
        position = rbCmp:getRigidBody():getPos()
    end

    if name:find("PlanetEntity") then
        return { entity = entity, label = name, position = position,
            distance = transform:getScale() * cfg.planetDistance }
    elseif name:find("AsteroidBeltEntity") then
        local widthCmp = entity:get(SpatialComponents.Width)
        local width = widthCmp and widthCmp:getWidth() or transform:getScale()
        return { entity = entity, label = name, position = position,
            distance = width * cfg.beltDistance }
    elseif name:find("StarEntity") then
        return { entity = entity, label = name, position = position,
            distance = transform:getScale() * cfg.starDistance }
    end
    return nil
end

--- The system's planets and asteroid belts as points of interest; the star
--- only when there are none.
---@param planets Entity[]
---@param belts Entity[]
---@param star Entity|nil
---@param cfg table
local function collectPointsOfInterest(planets, belts, star, cfg)
    local pois = {}
    for _, list in ipairs({ planets, belts }) do
        for _, entity in ipairs(list) do
            local poi = pointOfInterest(entity, cfg)
            if poi then table.insert(pois, poi) end
        end
    end
    if #pois == 0 and star then
        table.insert(pois, pointOfInterest(star, cfg))
    end
    return pois
end

--- Pick `count` distinct entries of `list` at random (partial Fisher-Yates).
local function pickDistinct(rng, list, count)
    local pool = {}
    for i, item in ipairs(list) do pool[i] = item end
    local picked = {}
    for i = 1, math.min(count, #pool) do
        local j = rng:getInt(i, #pool)
        pool[i], pool[j] = pool[j], pool[i]
        picked[i] = pool[i]
    end
    return picked
end

---@param from Position
---@param to Position
---@return Vec3f|nil unit direction, nil if the points coincide
local function direction(from, to)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local len = math.sqrt(dx * dx + dy * dy + dz * dz)
    if len <= 0 then return nil end
    return Vec3f(dx / len, dy / len, dz / len)
end

--- One gate: a kinematic body (a triangle mesh, so ships can fly through
--- the ring) at `position`, with its axis along `facing`. The caller adds the
--- body to the physics world.
---@param seed integer
---@param gateCmp JumpGateComponent where it leads
---@param position Position
---@param facing Vec3f|nil unit direction of the ring's axis (nil: +Z)
---@param radius number ring radius in game units
---@param model { meshes: MeshWithMaterial[], frame: Mesh }|nil a shared model (nil: a new one)
---@return Entity
function JumpGateGenerator:createGate(seed, gateCmp, position, facing, radius, model)
    if not model then
        local meshes, frame = self:createModel()
        model = { meshes = meshes, frame = frame }
    end
    local gate = NavigationEntities.JumpGate(seed, model.meshes, gateCmp)

    local rb = RigidBody.CreateTrimeshFromMesh(model.frame)
    rb:setKinematic(true)
    rb:setPos(position)
    rb:setScale(radius)
    if facing then
        rb:setRot(Quat.FromRotateTo(Vec3f(0, 0, 1), facing))
    end
    gate:get(PhysicsComponents.RigidBody):setRigidBody(rb)
    gate:get(PhysicsComponents.Transform):setPos(position)
    gate:get(PhysicsComponents.Transform):setScale(radius)
    return gate
end

---@class JumpGatePlacement
---@field entity Entity the gate
---@field poi string the point of interest it stands at
---@field destination GalaxySystem
---@field position Position its centre
---@field axis Vec3f unit axis of the ring: points toward the destination
---@field radius number ring radius

--- Create the played system's gates and add them to the physics world. They
--- are attached to the star system entity, so they go with it (and the maps
--- find them); remove their rigid bodies from the world before destroying it.
---@param args { seed: integer, galaxy: Galaxy, systemId: integer, starSystem: Entity, planets: Entity[], belts: Entity[], star: Entity|nil, world: Physics, cfg: table }
---@return JumpGatePlacement[]
function JumpGateGenerator:createGates(args)
    local galaxy, cfg = args.galaxy, args.cfg
    local system = galaxy.systems[args.systemId]
    local gates = {}
    if #system.links == 0 then
        Log.Info("JumpGates: %s has no links; no gates", system.name)
        return gates
    end

    local rng = RNG.Create(args.seed)
    assert(rng, "JumpGateGenerator: could not create an RNG")

    local pois = collectPointsOfInterest(args.planets, args.belts, args.star, cfg)
    if #pois == 0 then
        Log.Warn("JumpGates: %s has nothing to place gates at", system.name)
        return gates
    end
    local poiCount = rng:getInt(cfg.pointsOfInterest.min, cfg.pointsOfInterest.max)
    local chosen = pickDistinct(rng, pois, poiCount)

    -- Share the gates out between the chosen points, round robin, and spread
    -- each point's gates evenly around it from a random starting angle.
    local perPoi = {}
    for i, linkId in ipairs(system.links) do
        local slot = ((i - 1) % #chosen) + 1
        perPoi[slot] = perPoi[slot] or {}
        table.insert(perPoi[slot], linkId)
    end

    local meshes, frame = self:createModel()
    local model = { meshes = meshes, frame = frame }
    for slot, links in ipairs(perPoi) do
        local poi = chosen[slot]
        local startAngle = rng:getUniformRange(0, 2 * math.pi)
        for k, linkId in ipairs(links) do
            local link = galaxy.links[linkId]
            local destination = GalaxyGenerator:otherEnd(galaxy, link, system.id)

            local angle = startAngle + (k - 1) * (2 * math.pi / #links)
            local height = poi.distance * rng:getUniformRange(-cfg.heightJitter, cfg.heightJitter)
            local position = Position(
                poi.position.x + math.cos(angle) * poi.distance,
                poi.position.y + height,
                poi.position.z + math.sin(angle) * poi.distance)

            -- Facing the destination: the ring's axis points along the
            -- direction to the other system in the galaxy.
            local gateCmp = NavigationComponents.JumpGate(linkId, system.id, destination.id, destination.name)
            local axis = direction(system.position, destination.position) or Vec3f(0, 0, 1)
            local gate = self:createGate(rng:get64(), gateCmp, position, axis, cfg.radius, model)
            args.world:addRigidBody(gate:get(PhysicsComponents.RigidBody):getRigidBody())

            Registry:attachEntity(args.starSystem, gate)
            table.insert(gates, {
                entity = gate,
                poi = poi.label,
                destination = destination,
                position = position,
                axis = axis,
                radius = cfg.radius,
            })
            Log.Info("JumpGate to %s at %s (%.0f, %.0f, %.0f)",
                destination.name, poi.label, position.x, position.y, position.z)
        end
    end
    return gates
end

return JumpGateGenerator
