--[[
Jump test: boots the real game (LTheoryRedux) and travels the gate network.

1. Starts Single Planet With Belt and checks the galaxy and its gates.
2. Opens the Galaxy Map and plots a course to the farthest system (by jumps).
3. Sets the course and jumps along it gate by gate, checking after each
   jump that the ship is in the right system, next to the gate it came
   through, and that the course carries on.
4. Flies the ship through a gate (moved across the ring's plane, through
   its opening) and checks that this jumps too.
5. Starts the Jump Gate Showcase.

It takes screenshots on the way (./screenshot/): the galaxy map, each
arrival, the showcase.

Run it from the repository root after a build:

    ./bin/ltr JumpTest

Exit code 0 and "JumpTest: passed". A failed check stops the game with its
error and exit code 1. It needs a GPU and a window, so CI does not run it.
]]

local Game = require('States.App.LTheoryRedux')
local Scenarios = require('Config.Scenarios')
local GalaxyGenerator = require('Modules.Navigation.Managers.GalaxyGenerator')
local GalaxyMap = require('Modules.Navigation.Systems.GalaxyMap')
local JumpGateSystem = require('Modules.Navigation.Systems.JumpGateSystem')
local PhysicsComponents = require('Modules.Physics.Components')
local Screenshot = require('Render.ScreenCap')

local GAME_SEED = 7
local SETTLE_FRAMES = 20 -- frames after building or jumping, before checking

Config.paths.files = Directory.GetPrefPath(Config.org, 'JumpTest')
os.remove(Config.paths.files .. Config.userInitFilename .. Config.userInitFiletype)

local function check(condition, message, ...)
    if not condition then
        error("JumpTest: " .. string.format(message, ...), 2)
    end
end

local function shipPos()
    return Game.playerShip:get(PhysicsComponents.RigidBody):getRigidBody():getPos()
end

local function systemName(id)
    return Game.galaxy.systems[id].name
end

--- After a jump from `fromId`: the ship sits by the gate back to `fromId`.
local function checkArrival(fromId)
    local back = JumpGateSystem:gateTo(Game.gateWatch, fromId)
    check(back, "%s has no gate back to %s", systemName(Game.currentSystemId), systemName(fromId))
    local d = shipPos():distance(back.position)
    local expected = back.radius * Config.game.jumpGates.arrivalDistance
    check(math.abs(d - expected) < back.radius, "ship arrived %.3f from the gate (expected %.3f)", d, expected)
    check(#Game.jumpGates == #Game.galaxy.systems[Game.currentSystemId].links,
        "%s has %d gates for %d links", systemName(Game.currentSystemId), #Game.jumpGates,
        #Game.galaxy.systems[Game.currentSystemId].links)
end

-- The steps, each a function run once; it returns the frames to wait before
-- the next one, or `wait` to be called again next frame.
local steps = {}
local state = {}

local function step(name, fn)
    steps[#steps + 1] = { name = name, fn = fn }
end

step("start", function()
    Game:startGame(GAME_SEED, Scenarios.find("SinglePlanetWithBelt"))
    return SETTLE_FRAMES
end)

step("galaxy", function()
    local galaxy = Game.galaxy
    check(galaxy, "no galaxy")
    local cfg = Config.game.galaxy
    check(#galaxy.systems >= cfg.systemCount.min and #galaxy.systems <= cfg.systemCount.max,
        "%d systems", #galaxy.systems)
    for _, system in ipairs(galaxy.systems) do
        check(#system.links >= 1, "%s has no links", system.name)
        check(#system.links <= cfg.maxLinksPerSystem, "%s has %d links", system.name, #system.links)
        check(GalaxyGenerator:route(galaxy, 1, system.id), "%s unreachable", system.name)
    end
    check(#Game.jumpGates == #galaxy.systems[1].links, "%d gates for %d links",
        #Game.jumpGates, #galaxy.systems[1].links)
    Log.Info("JumpTest: %d systems, %d links, %d gates here", #galaxy.systems, #galaxy.links, #Game.jumpGates)

    -- The farthest system, in jumps
    local best, bestRoute = nil, {}
    for _, system in ipairs(galaxy.systems) do
        local route = GalaxyGenerator:route(galaxy, 1, system.id)
        if #route > #bestRoute then best, bestRoute = system, route end
    end
    state.target, state.route = best.id, bestRoute
    Log.Info("JumpTest: course to %s, %d jumps", best.name, #bestRoute)
    return 1
end)

step("galaxy map", function()
    -- As M pressed three times would (2D, 3D, galaxy), then a click on the target
    Game.mapMode = 3
    Game.galaxyMapState.enabled = true
    GalaxyMap:open(Game.galaxyMapState, Game.galaxy, Game.currentSystemId, nil)
    Game.galaxyMapState.selectedId = state.target
    Game.galaxyMapState.route = GalaxyGenerator:route(Game.galaxy, Game.currentSystemId, state.target)
    return 5
end)

step("galaxy map screenshot", function()
    Screenshot()
    Game.mapMode = 0
    Game.galaxyMapState.enabled = false
    Game.mapClosedFrame = true
    Game:setCourse(state.route)
    check(Game.course and #Game.course == #state.route, "course not set")
    return 2
end)

-- One jump along the course per call, until it is done
step("course", function()
    if Game.jump then return "wait" end
    if state.arrivedFrom then
        if (state.settle or 0) < SETTLE_FRAMES then
            state.settle = (state.settle or 0) + 1
            return "wait"
        end
        checkArrival(state.arrivedFrom)
        Log.Info("JumpTest: arrived in %s", systemName(Game.currentSystemId))
        Screenshot()
        state.arrivedFrom, state.settle = nil, 0
    end

    if not Game.course then
        check(Game.currentSystemId == state.target, "course ended in %s, not %s",
            systemName(Game.currentSystemId), systemName(state.target))
        return 1
    end

    -- Instead of the autopilot's flight: put the ship in range of the gate
    -- it heads for; the course jumps on its own from there.
    local gate = JumpGateSystem:gateTo(Game.gateWatch, Game.course[1])
    check(gate, "no gate to the course's next system")
    local rb = Game.playerShip:get(PhysicsComponents.RigidBody):getRigidBody()
    local a = gate.axis
    rb:setPos(Position(gate.position.x - a.x * gate.radius * 2, gate.position.y - a.y * gate.radius * 2,
        gate.position.z - a.z * gate.radius * 2))
    state.arrivedFrom = Game.currentSystemId
    return "wait"
end)

step("fly through", function()
    if state.flyFrom == nil then
        local gate = Game.jumpGates[1]
        state.flyFrom, state.flyTo = Game.currentSystemId, gate.destination.id
        local rb = Game.playerShip:get(PhysicsComponents.RigidBody):getRigidBody()
        local a = gate.axis
        -- In front of the ring, off-centre but inside the opening...
        local off = gate.radius * 0.4
        local side = math.abs(a.y) < 0.9 and Vec3f(0, 1, 0) or Vec3f(1, 0, 0)
        state.flyCross = function(t)
            return Position(gate.position.x + a.x * t + side.x * off,
                gate.position.y + a.y * t + side.y * off,
                gate.position.z + a.z * t + side.z * off)
        end
        rb:setPos(state.flyCross(-gate.radius))
        state.flyRadius = gate.radius
        return "wait"
    end
    if not state.flyMoved then
        -- ...then behind it: the path crossed the plane inside the opening
        Game.playerShip:get(PhysicsComponents.RigidBody):getRigidBody():setPos(state.flyCross(state.flyRadius))
        state.flyMoved = true
        return "wait"
    end
    if Game.jump or (state.flyWait or 0) < SETTLE_FRAMES then
        state.flyWait = (state.flyWait or 0) + 1
        return "wait"
    end
    check(Game.currentSystemId == state.flyTo, "flying through the gate to %s left the ship in %s",
        systemName(state.flyTo), systemName(Game.currentSystemId))
    checkArrival(state.flyFrom)
    Log.Info("JumpTest: flew through to %s", systemName(state.flyTo))
    return 1
end)

step("showcase", function()
    Game:returnToMainMenu()
    return 3
end)

step("showcase start", function()
    Game:startGame(GAME_SEED, Scenarios.find("JumpGateShowcase"))
    return SETTLE_FRAMES
end)

step("showcase screenshot", function()
    Screenshot()
    return 2
end)

local current, waitFrames = 0, 0

local function advance()
    if current > #steps then return end
    if waitFrames > 0 then
        waitFrames = waitFrames - 1
        return
    end
    if current == 0 or steps[current].done then
        current = current + 1
        if current > #steps then
            Log.Info("JumpTest: passed")
            Engine:exit()
            return
        end
        Log.Info("JumpTest: %s", steps[current].name)
    end
    local result = steps[current].fn()
    if result == "wait" then return end
    steps[current].done = true
    waitFrames = result or 0
end

local gameOnInit = Game.onInit
function Game:onInit()
    gameOnInit(self)
    GameState.render.fullscreen = false
    Window:setFullscreen(false, false)
    self:soundOff()
end

local gameOnPreRender = Game.onPreRender
function Game:onPreRender(data)
    gameOnPreRender(self, data)
    advance()
end

return Game
