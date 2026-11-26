-- LTheoryRedux: the main game state. Flow: main menu (HmGui) -> New Game
-- -> startGame(seed) builds the scene through UniverseManager + Rulesets
-- + SolarSystemVisualizer, then renders via RenderCoreSystem with HUD,
-- system maps, and player ship control.
Namespace.LoadInline('Legacy')
Namespace.LoadInline('Legacy.Systems')

LimitTheoryRedux = require('States.Application')

-- Sound / persistence
local SoundManager = require('Legacy.Systems.SFX.SoundManager')
local MusicPlayer = require('Shared.Audio.MusicPlayer')
local InitFiles = require('Legacy.Systems.Files.InitFiles')
local UserSettings = require('Shared.UserSettings')

-- UI pages (HmGui): the Main_Menu page before a game, the Gameplay page in
-- game (In_Game view with the HUD text, Paused and Controls views for the pause
-- menu). The maps and world labels are still drawn by the state's onRender
-- through the rendering systems.
local UIRouter = require('UI.HmGui.UICore.UIRouter')
local UIPageMainMenu = require('UI.HmGui.Pages.MainMenu')
local UIPageGameplay = require('UI.HmGui.Pages.Gameplay')
local UIViewInGame = require('UI.HmGui.Views.Gameplay.InGame')
local ApplicationBindings = require('States.ApplicationBindings')

-- ECS registry, physics/construct/celestial components, camera manager,
-- render core, player controller, and the simulation systems the scene
-- runs on.
local Registry = require('Core.ECS.Registry')
local CoreComponents = require('Modules.Core.Components')
local PhysicsComponents = require('Modules.Physics.Components')
local ConstructComponents = require('Modules.Constructs.Components')
local CelestialComponents = require('Modules.CelestialObjects.Components')
local CameraManager = require('Modules.Cameras.Managers.CameraManager')
local CameraEntity = require('Modules.Cameras.Entities').Camera
local RenderCoreSystem = require('Modules.Rendering.Systems.RenderCoreSystem')
local PlayerController = require('Modules.Constructs.Systems.PlayerController')
local AutoPilotSystem = require('Modules.Constructs.Systems.AutoPilotSystem')
local GravityWellSystem = require('Modules.Physics.Systems.GravityWellSystem')
local CelestialLightingSystem = require('Modules.Rendering.Systems.CelestialLightingSystem')
local LensFlareSystem = require('Modules.Rendering.Systems.LensFlareSystem')
local WorldLabelRenderSystem = require('Modules.UI.Systems.WorldLabelRenderSystem')
local AsteroidFieldSystem = require('Modules.CelestialObjects.Systems.AsteroidFieldSystem')
local GeneralActions = require('Input.ActionBindings.GeneralActions')
local CursorManager = require('Input.CursorManager')
local Rulesets = require('Config.Gen.Rulesets')
local UniverseManager = require('Modules.CelestialObjects.Managers.UniverseManager')
local SolarSystemVisualizer = require('Modules.CelestialObjects.Managers.SolarSystemVisualizer')
local CoordinateRebaser = require('Modules.CelestialObjects.Managers.CoordinateRebaser')
local OrbitalSystem = require('Modules.CelestialObjects.Systems.OrbitalSystem')
local SystemMap = require('Modules.CelestialObjects.Systems.SystemMap')
local SystemMap3D = require('Modules.CelestialObjects.Systems.SystemMap3D')
local MemoryReporter = require('Modules.Profiling.MemoryReporter')
local ConstructManager = require('Modules.Constructs.Managers.ConstructManager')
local StationGenerator = require('Modules.Constructs.Managers.Generators.StationGenerator')
local GalaxyGenerator = require('Modules.Navigation.Managers.GalaxyGenerator')
local JumpGateGenerator = require('Modules.Navigation.Managers.JumpGateGenerator')
local JumpGateSystem = require('Modules.Navigation.Systems.JumpGateSystem')
local GalaxyMap = require('Modules.Navigation.Systems.GalaxyMap')
local NpcSystem = require('Modules.NPC.Systems.NpcSystem')
local Reputation = require('Modules.NPC.Reputation')
local CombatLog = require('Modules.Constructs.Systems.CombatLog')
local PlayerWallet = require('Modules.Economy.Managers.PlayerWallet')
local PlayerCargo = require('Modules.Economy.Managers.PlayerCargo')
local PlayerFactories = require('Modules.Economy.Managers.PlayerFactories')
local MarketSystem = require('Modules.Economy.Systems.MarketSystem')
local MarketIntel = require('Modules.Economy.Managers.MarketIntel')
local StationTradeSystem = require('Modules.Economy.Systems.StationTradeSystem')
local ProductionSystem = require('Modules.Economy.Systems.ProductionSystem')
local EconomyComponents = require('Modules.Economy.Components')
local AsteroidOre = require('Shared.Helpers.AsteroidOre')
local SpaceDust = require('Modules.Rendering.Systems.SpaceDust')
local CoreComponentsAll = require('Modules.Core.Components')
local RenderComponent = require('Modules.Rendering.Components').Render
local Factions = require('Modules.NPC.Factions')
local GunshipRecipe = require('Modules.NPC.Managers.GunshipRecipe')
local PlayerLoadout = require('Modules.Constructs.Managers.PlayerLoadout')
local ShipFittingSystem = require('Modules.Constructs.Systems.ShipFittingSystem')
local AbilitySystem = require('Modules.Constructs.Systems.AbilitySystem')
local PlayerShipyard = require('Modules.Constructs.Managers.PlayerShipyard')
local Hulls = require('Shared.Definitions.HullDefs')
local Fittings = require('Shared.Registries.Fittings')
local ArmedShipBuilder = require('Modules.Constructs.Managers.ArmedShipBuilder')
local WeaponBattery = require('Modules.Constructs.Systems.WeaponBattery')
local DrawEx = require('UI.DrawEx')
local MapFrame = require('UI.MapFrame')
local UniverseScaleConfig = require('Config.Gen.UniverseScaleConfig')
local WeaponCombatSystem = require('Modules.Constructs.Systems.WeaponCombatSystem')
local ExplosionEffectSystem = require('Modules.Constructs.Systems.ExplosionEffectSystem')

-- Skybox. This state also draws from the light-transport nebula, which the
-- Legacy namespace load used to register.
local Skybox = require('Shared.Generation.Skybox')
require('Shared.Generation.Nebula2')

-- How a game starts (New Game's Scenario list)
local Scenarios = require('Config.Scenarios')

local rng = RNG.FromTime()

-- Scene tuning: spawn placement + station layout for this state. Camera
-- defaults and ship scale live in the generic game config (orbitCamera,
-- freeCamera, shipHulls).
local SceneConfig = {
    defaultSeed        = 12345,

    -- Ship spawn
    shipSpawnOffset    = 1.3,     -- Multiplier of planet radius (just outside the surface), without belt rocks
    starSpawnOffset    = 3.0,     -- Multiplier of star radius, without planets

    -- Station spawn
    maxStations        = 2,       -- Max stations to spawn (limited by planet count)
    stationScale       = 0.3,     -- ~3km station
    stationOrbitMult   = 2.5,     -- Multiplier of planet radius for station orbit distance
}

--- Free the GPU memory of a scene that was just destroyed. Its textures and
--- meshes are freed by the finalizers of their Lua objects, and the frame GC is
--- paced by Lua memory, which barely sees them (a planet's surface texture is
--- tens of MB on the GPU and a few bytes in Lua): without a full collection,
--- building a few star systems in a row runs out of GPU memory.
-- Frames between tearing a scene down and building it again (Regenerate): the
-- renderer keeps up to three frames in flight.
local REBUILD_DELAY_FRAMES = 4
-- Seconds the name and hostility of a system just entered stay on screen
local SYSTEM_BANNER_TIME = 6.0

-- Standing changes reach the game state (registered once; the state is a
-- single object)
local reputationListening = false

local function releaseGpuMemory()
    collectgarbage('collect')
    collectgarbage('collect') -- the second pass runs the finalizers queued by the first
end

local function setMenuScale()
    -- sizes for background star system
    Config.gen.scaleSystem    = Config.gen.scaleSystemBack
    Config.gen.scalePlanet    = Config.gen.scalePlanetBack
    Config.gen.scalePlanetMod = Config.gen.scalePlanetModBack
    GameState.render.zNear    = Config.gen.zNearBack
    GameState.render.zFar     = Config.gen.zFarBack
end

local function setGameScale()
    -- Use the "real" system generation sizes for a gameplay star system
    Config.gen.scaleSystem    = Config.gen.scaleSystemReal
    Config.gen.scalePlanet    = Config.gen.scalePlanetReal
    Config.gen.scalePlanetMod = Config.gen.scalePlanetModReal
    GameState.render.zNear    = Config.gen.zNearReal
    GameState.render.zFar     = Config.gen.zFarReal
end

---@diagnostic disable-next-line: duplicate-set-field
function LimitTheoryRedux:onInit()
    -- Expose the scene builder to the main menu (New Game button)
    GameState.startGame = function(seed, scenario) self:startGame(seed, scenario) end

    -- Presentation: borderless fullscreen with VSync off, unless user.ini says
    -- otherwise (exclusive mode forces a mode switch that lowers frame rates).
    UserSettings.useGameDisplayDefaults()
    -- Before user.ini: init lists the soundtracks that its menuTheme is matched
    -- against. The tracks get the saved volumes in loadMusic below.
    MusicPlayer:init()
    InitFiles:readUserInits()

    Window:setSize(GameState.render.resX, GameState.render.resY)
    Window:setCenteredPosition()
    -- Display mode, VSync, field of view, brightness, bloom, smoothing, texture quality
    UserSettings.applyAll()

    Window:setCursorPosition(Vec2f(GameState.ui.cursorX, GameState.ui.cursorY))
    SoundManager:init()
    MusicPlayer:loadMusic()
    -- Captures (LTHEORY_CAPTURE) are silent: nobody listens to them, and the
    -- render validation runs a dozen in a row. (Not saved: captures never
    -- write user.ini.)
    if os.getenv('LTHEORY_CAPTURE') then
        self:soundOff()
    end

    self:initMainMenu(true)
end

function LimitTheoryRedux:initMainMenu(isAppInit)
    GameState:SetState(Enums.GameStates.MainMenu)
    setMenuScale()

    -- Register UI pages once
    if isAppInit then
        UIRouter:addPage(UIPageMainMenu)
        UIRouter:addPage(UIPageGameplay)
    end
    Input:setCursorVisible(true)

    -- Capture variant (render validation): LTHEORY_CAPTURE_VIEW picks the menu view, only under LTHEORY_CAPTURE.
    UIPageMainMenu:setView(os.getenv('LTHEORY_CAPTURE') and os.getenv('LTHEORY_CAPTURE_VIEW') or "Title")

    -- Straight into a game, skipping the main menu: LTR_AUTOSTART=1 (with
    -- LTR_SCENARIO=<scenario id>, else the default scenario), or a test state
    -- that set `autostartScenario` (Testbeds/WeaponSystem, PlanetTest...).
    -- Under LTHEORY_CAPTURE, LTHEORY_CAPTURE_SEED fixes the seed.
    local autostart = isAppInit and self.autostartScenario
    if isAppInit and not autostart and os.getenv("LTR_AUTOSTART") == "1" then
        local id = os.getenv("LTR_SCENARIO")
        autostart = Scenarios.find(id)
        if not autostart then
            if id then Log.Warn("LTR_SCENARIO: there is no scenario '%s', starting the default one", id) end
            autostart = Scenarios.default
        end
    end
    if autostart then
        local seed = os.getenv('LTHEORY_CAPTURE') and tonumber(os.getenv('LTHEORY_CAPTURE_SEED'))
        self:startGame(seed or self.autostartSeed or rng:get64(), autostart)
    else
        -- Menu phase: spawn a star system behind the menu (the legacy
        -- GameView background path is gone; the modern pipeline renders it).
        self:createMenuBackground()
        UIRouter:setCurrentPage("Main_Menu")
    end
end

--- Spawn the menu background star system through the modern scene pipeline
--- (UniverseManager + Rulesets + SolarSystemVisualizer) with its own camera,
--- mirroring the camera pattern of the working testbed states.
function LimitTheoryRedux:createMenuBackground()
    if self.menuWorld then return end

    self.world = Physics.Create()
    self.menuWorld = self.world

    -- Skybox + universe at menu scale (Config.gen scaleSystemBack etc.)
    setMenuScale()
    -- Capture variant (render validation): LTHEORY_CAPTURE_SEED fixes the menu scene, only under LTHEORY_CAPTURE.
    self.menuSeed = os.getenv('LTHEORY_CAPTURE') and tonumber(os.getenv('LTHEORY_CAPTURE_SEED')) or rng:get64()
    self.seed = self.menuSeed
    self:createSkybox()
    self:generateUniverse(Scenarios.default.ruleset)

    -- Orbit camera around the first planet (same registration pattern as
    -- PlanetTest: no controller, transform driven by updateMenuCamera).
    local camEntity = CameraEntity()
    CameraManager:registerCamera("MenuCamera", camEntity)
    CameraManager:setActiveCamera("MenuCamera")

    local planetPos = Position(0, 0, 0)
    local planetRadius = 100
    if self.planets and self.planets[1] then
        local planet = self.planets[1]
        local t = planet:get(PhysicsComponents.Transform)
        if t then
            planetPos = t:getPos()
            planetRadius = math.max(t:getScale(), 100)
        end
    end
    self.menuPlanetPos = planetPos
    self.menuOrbitAngle = 0.0
    self.menuOrbitSpeed = 0.02
    self.menuOrbitPitch = 0.25
    self.menuOrbitRadius = planetRadius * 4.0
    self:updateMenuCamera(0)
end

--- Advance the menu camera on its orbit around the menu planet.
---@param dt number
function LimitTheoryRedux:updateMenuCamera(dt)
    if not self.menuWorld then return end

    self.menuOrbitAngle = self.menuOrbitAngle + (self.menuOrbitSpeed * (dt or 0))

    local camEntity = CameraManager:getActiveCameraEntity()
    if not camEntity then return end
    local transform = camEntity:get(PhysicsComponents.Transform)
    if not transform then return end

    local r = self.menuOrbitRadius
    local x = math.cos(self.menuOrbitAngle) * r
    local y = math.sin(self.menuOrbitPitch) * r
    local z = math.sin(self.menuOrbitAngle) * r
    local targetPos = Vec3f(self.menuPlanetPos.x, self.menuPlanetPos.y, self.menuPlanetPos.z)
    local camPos = Vec3f(targetPos.x + x, targetPos.y + y, targetPos.z + z)

    transform:setPos(Position(camPos.x, camPos.y, camPos.z))
    local lookDir = (targetPos - camPos):normalize()
    transform:setRot(Quat.FromLook(lookDir, Vec3f(0, 1, 0)))
end

--- Tear down the menu background before the game builds its own scene.
function LimitTheoryRedux:cleanupMenuBackground()
    if not self.menuWorld then return end

    if self.universe then
        -- Bodies must leave the physics world before their entities die.
        local bodies = {}
        for entity, rbCmp in Registry:iterEntities(PhysicsComponents.RigidBody) do
            local rb = rbCmp and rbCmp:getRigidBody()
            if rb then
                table.insert(bodies, { entity = entity, rb = rb })
            end
        end
        for _, b in ipairs(bodies) do
            self.menuWorld:removeRigidBody(b.rb)
        end
        Registry:destroyEntity(self.universe, Enums.Registry.EntityDestroyMode.DestroyChildren)
    end

    -- The skybox entity is standalone (not attached to the universe).
    if self.skybox then
        Registry:destroyEntity(self.skybox, Enums.Registry.EntityDestroyMode.DestroyChildren)
        self.skybox = nil
    end

    self.universe = nil
    self.planets = {}
    self.labeledEntities = {}
    self.beltEntities = {}
    self.starEntity = nil
    self.menuWorld = nil
    self.world = nil

    releaseGpuMemory()
end

--- Open the in-game pause menu (Escape). The Gameplay page's Paused view
--- provides Return to Game / Controls / Back to Main Menu / Exit.
function LimitTheoryRedux:openPauseMenu()
    self.pauseMenuOpen = true
    GameState:Pause()
    -- Free the cursor (visible, no grab): gameplay runs FPS-style Locked,
    -- which pins the cursor and makes the Paused view unclickable.
    CursorManager:free()
    UIPageGameplay:setView("Paused")
end

--- Close the in-game pause menu and resume the sim.
function LimitTheoryRedux:closePauseMenu()
    self.pauseMenuOpen = false
    self.controlsOpen = false
    GameState:Unpause()
    if self.docked then
        -- Back to the station screen, which is where the game was
        self:openStationScreen()
        return
    end
    UIPageGameplay:setView("In_Game")
    -- Re-apply the gameplay cursor state for the current camera mode
    -- (Locked/Confined/Free), same pattern as the map-mode close path.
    if self.player then
        self.player:setMode(self.player:getMode())
    end
end

--- Show the Controls (help) screen; the game stays paused.
function LimitTheoryRedux:openControls()
    self.controlsOpen = true
    UIPageGameplay:setView("Controls")
end

--- Back from the Controls screen to the pause menu.
function LimitTheoryRedux:closeControls()
    self.controlsOpen = false
    UIPageGameplay:setView("Paused")
end

--- P freezes the sim without opening the pause menu.
function LimitTheoryRedux:togglePause()
    if self.pauseMenuOpen then return end
    if GameState.paused then GameState:Unpause() else GameState:Pause() end
end

function LimitTheoryRedux:toggleHUD()
    self.hudHidden = not self.hudHidden
end

--- Tear down the gameplay scene and return to the main menu.
function LimitTheoryRedux:returnToMainMenu()
    self:closePauseMenu()

    if self._simTunnel then
        EventBus:unsubscribe(self._simTunnel)
        self._simTunnel = nil
    end
    if self._postSimTunnel then
        EventBus:unsubscribe(self._postSimTunnel)
        self._postSimTunnel = nil
    end

    self:destroyScene()
    self.weaponCombat = nil
    RenderCoreSystem:setDebugPhysics(nil)
    -- The menu makes a skybox of its own
    if self.skybox then
        Registry:destroyEntity(self.skybox, Enums.Registry.EntityDestroyMode.DestroyChildren)
        self.skybox = nil
    end

    self.scenario = nil
    self.rebuildInFrames = nil
    UIViewInGame:setPlayer(nil)
    UIViewInGame:setOverlayLines(nil)
    self.mapMode = 0

    -- The menu needs a free cursor (closePauseMenu re-applied the gameplay
    -- capture just above); Release it before switching back to the menu.
    CursorManager:free()

    self:initMainMenu()
end

--- Start a game: the scenario's star system (ruleset-driven generation, then
--- materialization of planets/rings/belts), the player's ship, the stations
--- and the scenario's own things; then the systems that run it.
---@param seed integer|nil nil = a random seed
---@param scenario Scenario|nil nil = the default scenario
function LimitTheoryRedux:startGame(seed, scenario)
    setGameScale()
    GameState:SetState(Enums.GameStates.InGame)

    -- In-game soundtrack: queue every non-menu track and play one.
    MusicPlayer:playAmbient()

    -- Drop the menu background (its universe/world/camera) before building
    -- the gameplay scene.
    self:cleanupMenuBackground()

    self.cfg = SceneConfig
    self.scenario = scenario or Scenarios.default
    -- Bodies stay at their generated positions unless the scenario has
    -- orbits (see onStateSim)
    self.staticStarSystem = not self.scenario.orbits
    -- Random universe each game: a nil seed means "surprise me", never a
    -- fixed default (the same universe on every New Game would be stale).
    self.seed = seed or rng:get64()
    self.rng = RNG.Create(self.seed)
    -- The Draw HUD setting; V still toggles the HUD during the game.
    self.hudHidden = not GameState.ui.drawHud
    self.world = Physics.Create()
    self.constructManager = ConstructManager(Registry, self.world)
    -- Every armed ship's weapons (WeaponBattery) run through this
    self.weaponCombat = WeaponCombatSystem(self.world)
    -- The star system's NPC ships (combat scenarios only)
    self.npcs = NpcSystem(self)
    if not reputationListening then
        reputationListening = true
        Reputation:onChange(function(faction, old, new) self:onReputationChanged(faction, old, new) end)
        CombatLog:onHit(function(event) self:onCombatHit(event) end)
        CombatLog:onKill(function(event) self:onCombatKill(event) end)
    end
    RenderCoreSystem:setDebugPhysics(self.world)

    self:createSkybox()
    self:resetGalaxy()
    self:buildScene()

    -- Player controller owns camera modes, input routing, and ship reference
    local orbit = Config.game.orbitCamera
    local free = Config.game.freeCamera
    self.player = PlayerController(self.playerShip, {
        orbit = {
            distance    = orbit.distance,
            minDistance = orbit.minDistance,
            maxDistance = orbit.maxDistance,
            zoomSpeed   = orbit.zoomSpeed,
            zoomRatio   = orbit.zoomRatio,
            smoothing   = orbit.smoothing,
        },
        free = {
            moveSpeed      = free.moveSpeed,
            fastMultiplier = free.fastMultiplier,
            mouseSensitivity = free.mouseSensitivity,
        },
    })
    UIViewInGame:setPlayer(self.player)

    -- System maps
    self.mapState = SystemMap:create()
    self.map3DState = SystemMap3D:create()
    SystemMap3D:setSkybox(self.map3DState, self.skybox)
    self.galaxyMapState = GalaxyMap:create()
    self.mapMode = 0  -- 0=off, 1=2D, 2=3D, 3=galaxy

    self:setupScenario()
    self:collectSceneSystems()

    self._simTunnel = EventBus:subscribe(Event.Sim, self, self.onStateSim)
    self._postSimTunnel = EventBus:subscribe(Event.PostSim, self, self.onStatePostSim)

    -- Swap the menu for the Gameplay page. Its In_Game view draws on top of
    -- the HUD and labels that the state's onRender draws.
    UIRouter:setCurrentPage("Gameplay")
    UIPageGameplay:setView("In_Game")
end

--- The skybox for a seed (default `self.seed`): nebula, stars, light direction.
---@param seed integer|nil
function LimitTheoryRedux:createSkybox(seed)
    self.skybox = Skybox.Create(seed or self.seed)
end

--- The star system, the player's ship and the stations, from the scenario.
function LimitTheoryRedux:buildScene()
    self.sceneEntities = {}
    self.sceneConstructs = {}
    self:generateUniverse(self.scenario.ruleset or Scenarios.default.ruleset, self.seed)
    self:spawnPlayerShip()
    if self.scenario.stations ~= false then
        self:spawnStations()
    else
        self.stations = {}
    end
    self.jumpGates = {}
    if self.scenario.gates ~= false and self.scenario.stations ~= false then
        self:spawnJumpGates()
    end
    self.gateWatch = JumpGateSystem:watch(self.jumpGates)
    self:populateSystem()
    -- The system's banner at the start of a game too
    self.systemBanner = self.galaxy and SYSTEM_BANNER_TIME or nil
end

--- Whether this is the travel game (the star-system scenarios): stations,
--- gates, NPCs, combat and the player's gunship. The showcases and tests
--- leave it out.
---@return boolean
function LimitTheoryRedux:isTravelGame()
    return self.scenario ~= nil and self.scenario.stations ~= false and self.scenario.combat ~= false
end

--- The current system's hostility level (Config.game.hostility.levels).
---@return table|nil level, integer|nil index
function LimitTheoryRedux:currentHostility()
    local levels = Config.game.hostility.levels
    local system = self.galaxy and self.galaxy.systems[self.currentSystemId]
    local index = system and system.hostility or Config.game.hostility.homeLevel
    return levels[index], index
end

--- A line under the HUD for a few seconds (standing changes and the like).
---@param text string
---@param color table|nil {r, g, b}
function LimitTheoryRedux:notify(text, color)
    self.messages = self.messages or {}
    table.insert(self.messages, { text = text, color = color or { 0.9, 0.9, 0.9 }, time = 5.0 })
    while #self.messages > 4 do table.remove(self.messages, 1) end
end

--- A standing changed: who shoots whom changes with it, and the player hears
--- about it.
function LimitTheoryRedux:onReputationChanged(faction, old, new)
    if self.npcs then self.npcs:refreshHostility() end
    if self.playerBattery then
        local set = {}
        for _, team in ipairs(Factions.hostileTeams(Factions.Player)) do set[team] = true end
        self.playerBattery.hostileTeams = set
    end
    local r, g, b = Factions.color(faction)
    local delta = new - old
    self:notify(string.format("%s standing %s%.2f (%s)", Factions.name(faction),
        delta >= 0 and "+" or "", delta, Reputation:describe(faction)), { r, g, b })
end

--- A hit the weapons landed (CombatLog): the player's hits on an NPC cost
--- standing with its faction (once a second per ship, not per bolt).
---@param event table
function LimitTheoryRedux:onCombatHit(event)
    if not self.playerShip or event.attacker ~= self.playerShip or not self.npcs then return end
    local record = self.npcs:recordOf(event.target)
    if not record then return end
    local now = self.simTime or 0
    if not record.blamedAt or now - record.blamedAt >= 1.0 then
        record.blamedAt = now
        Reputation:playerDamaged(record.faction)
    end
end

--- A killing blow (CombatLog). The player's: standing moves (the faction
--- likes the player less, its enemies more), and an outlaw's (a ship whose
--- faction the bounty issuer is hostile to) bounty is paid.
---@param event table
function LimitTheoryRedux:onCombatKill(event)
    if not self.playerShip or event.attacker ~= self.playerShip or not self.npcs then return end
    local record = self.npcs:recordOf(event.target)
    if not record then return end
    local economy = Config.game.economy
    if Factions.isHostile(economy.bountyIssuer, record.faction) then
        local bounty = economy.bounties[record.role] or economy.defaultBounty
        PlayerWallet:add(bounty, "Bounty: " .. record.label)
        self:notify(string.format("Bounty +%s: %s destroyed", PlayerWallet.format(bounty), record.label),
            { 1.0, 0.85, 0.35 })
    else
        self:notify(record.label .. " destroyed", { 0.9, 0.9, 0.9 })
    end
    Reputation:playerDestroyed(record.faction)
end

--- The hull points missing, and what repairing them all would cost.
---@return number missing, number cost
function LimitTheoryRedux:hullRepairQuote()
    local health = self.playerShip and self.playerShip:get(CoreComponentsAll.Health)
    if not health then return 0, 0 end
    local missing = health:getMaxHealth() - health:getCurrentHealth()
    return missing, math.ceil(missing * Config.game.economy.hullRepairCost)
end

--- Repair the hull at the station (docked): as much as the credits pay for.
function LimitTheoryRedux:repairHull()
    local health = self.playerShip:get(CoreComponentsAll.Health)
    local missing, cost = self:hullRepairQuote()
    if missing <= 0 then
        self:notify("The hull needs no repair.", { 0.6, 0.9, 1.0 })
        return
    end
    local rate = Config.game.economy.hullRepairCost
    local points = missing
    if not PlayerWallet:has(cost) then
        points = math.floor(PlayerWallet:get() / rate)
        cost = math.ceil(points * rate)
    end
    if points <= 0 then
        self:notify("Not enough credits to repair the hull.", { 1.0, 0.4, 0.3 })
        return
    end
    PlayerWallet:remove(cost, "Hull repair")
    health:setCurrentHealth(health:getCurrentHealth() + points)
    self:notify(string.format("Hull repaired %d/%d for %s", math.floor(health:getCurrentHealth()),
        math.floor(health:getMaxHealth()), PlayerWallet.format(cost)), { 0.6, 0.9, 1.0 })
end

--- The rock the player's ship could mine now: the nearest spawned asteroid
--- within range of the ship, with something left in it.
---@param ignoreLaser boolean|nil true to find a rock even with nothing to cut it with
---@param reachScale number|nil further than the laser can cut (a scanner reads at range)
---@return table|nil info { entity, field, asteroid, pos, scale, rock }
function LimitTheoryRedux:mineableRock(ignoreLaser, reachScale)
    if self.docked or not self.playerShip or not self.npcs or not self.npcs.mining then return nil end
    -- A rock is just a rock without something to cut it with
    if not ignoreLaser and not self:fittedAbility("miningLaser") then return nil end
    local rbCmp = self.playerShip:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if not body then return nil end
    local pos = body:getPos()
    local cfg = Config.game.mining
    local best, bestDist
    for _, info in ipairs(AsteroidFieldSystem:getSpawnedEntities()) do
        if info.field and info.asteroid then
            -- A better sensor reaches further (Survey Scanner, Ship Sensor)
            local reach = info.scale
                + cfg.playerRange * self:fitStat("scanRange", 1) * (reachScale or 1)
            local d = pos:distance(info.pos)
            if d <= reach and (not bestDist or d < bestDist) then
                best, bestDist = info, d
            end
        end
    end
    if not best then return nil end
    local rock = self.npcs.mining:trackAsteroid(best.field, best.asteroid,
        { x = best.pos.x, y = best.pos.y, z = best.pos.z })
    if rock.yield < 1 then return nil end
    return {
        entity = best.entity, field = best.field, asteroid = best.asteroid,
        pos = best.pos, scale = best.scale, rock = rock,
    }
end

--- Mining (E held): a unit of ore a second or so out of the nearest rock and
--- into the hold, while the key is down and the rock is in reach. The same
--- yield the NPC miners take from (`MiningField`), so a stripped rock is
--- stripped for everyone.
---@param dt number
function LimitTheoryRedux:updateMining(dt)
    if not self:isTravelGame() then return end
    if self.docked or self.mapMode ~= 0 then
        self.miningProgress, self.miningTarget, self.miningScan = nil, nil, nil
        self.miningFullWarned, self.miningNoLaserHint = false, false
        return
    end
    -- Looking for a rock in reach walks the spawned asteroids, so it is done
    -- a few times a second, not once a frame: the HUD reads what it found.
    self.miningScan = (self.miningScan or 0) - dt
    if self.miningScan <= 0 or (self.miningTarget and self.miningTarget.rock.yield < 1) then
        self.miningScan = Config.game.mining.playerScanInterval
        if self:fittedAbility("miningLaser") then
            self.miningTarget = self:mineableRock()
            self.miningNoLaserHint = false
        else
            -- Nothing to cut with: say so when a rock is close enough to matter
            self.miningTarget = nil
            self.miningNoLaserHint = self:mineableRock(true) ~= nil
        end
    end
    local mining = GeneralActions.Mine:isDown()
    local info = self.miningTarget
    if not mining or not info then
        self.miningProgress = nil
        return
    end
    local cfg = Config.game.mining
    local hold = PlayerCargo:get()
    -- Said once, not once a tick, while the key is held against a full hold
    local function holdFull()
        self.miningProgress = nil
        if not self.miningFullWarned then
            self.miningFullWarned = true
            self:notify("The hold is full.", { 1.0, 0.4, 0.3 })
        end
    end
    if hold:getRoomFor(info.rock.itemId) < 1 then
        holdFull()
        return
    end
    self.miningFullWarned = false
    -- A better laser cuts faster
    local perUnit = cfg.playerTimePerUnit / math.max(0.1, self:fitStat("miningRate", 1))
    self.miningProgress = (self.miningProgress or 0) + dt
    while self.miningProgress >= perUnit do
        self.miningProgress = self.miningProgress - perUnit
        if not self.npcs.mining:take(info.rock) then
            self:notify(info.rock.item .. ": nothing left in this rock.", { 1.0, 0.7, 0.3 })
            self.miningTarget = nil
            break
        end
        if PlayerCargo:add(info.rock.itemId, 1) < 1 then
            -- No room after all: put it back
            info.rock.yield = info.rock.yield + 1
            holdFull()
            break
        end
        -- Whatever the scanner said or did not say, a unit in the hold is
        -- the rock identified
        if not self:knowsRock(info) then
            self:markSurveyed(info)
            self:notify(string.format("The rock is %s.", info.rock.item), { 0.5, 1.0, 0.7 })
        end
    end
end

--- What the pilots can see of the player's ship: nothing while it is docked,
--- a fraction of their range while it is cloaked.
function LimitTheoryRedux:updatePlayerVisibility()
    if not self.npcs then return end
    local cloaked = self.cloak and self.cloak.active
    self.npcs:setPlayerVisibility(self.docked ~= nil, cloaked and Config.game.cloak.detection or 1)
end

--- The station the player can dock at now: the nearest one in range whose
--- owner isn't hostile to the player. Second result: the nearest in range
--- that refuses (to say why).
---@return table|nil dock, table|nil refused
function LimitTheoryRedux:dockInRange()
    local places = self.npcs and self.npcs.places
    if not places or not places.docks or not self.playerShip then return nil end
    local pos = self.playerShip:get(PhysicsComponents.RigidBody):getRigidBody():getPos()
    local best, refused, bestDist = nil, nil, math.huge
    for _, dock in ipairs(places.docks) do
        if dock.entity:isValid() then
            local d = pos:distance(dock.position)
            if d <= dock.radius * Config.game.docking.rangeFactor and d < bestDist then
                if Factions.isHostile(dock.faction, Factions.Player) then
                    refused = dock
                else
                    best, bestDist = dock, d
                end
            end
        end
    end
    return best, refused
end

--- Dock the player's ship (Legacy Dockable:addDocked): inside the station,
--- hidden, out of reach; hull and shields repaired; the camera orbits the
--- station.
---@param dock table
function LimitTheoryRedux:dockPlayer(dock)
    if self.cloak.active then self:setCloak(false) end
    AutoPilotSystem:disengage(self.playerShip)
    self.course = nil
    local rb = self.playerShip:get(PhysicsComponents.RigidBody):getRigidBody()
    rb:setKinematic(true)
    rb:setPos(Position(dock.position.x, dock.position.y, dock.position.z))
    local render = self.playerShip:get(RenderComponent)
    if render then render:setVisible(false) end
    local targetable = self.playerShip:get(ConstructComponents.Targetable)
    if targetable then targetable:setEnabled(false) end
    if self.playerBattery then self.playerBattery:setAIActive(false) end

    -- Shields recharge free at a station; the hull costs (R, repairHull)
    local defense = self.playerShip:get(ConstructComponents.Defense)
    if defense then defense:setCurrentShield(defense:getMaxShield()) end

    self.docked = dock
    self:updatePlayerVisibility()
    self:setOrbitFocus(dock.entity, self:orbitDistances(dock.radius))
    self:notify("Docked. Shields recharged.", { 0.6, 0.9, 1.0 })
    self:recordMarketIntel()
    -- The station's own screen: its market, its production and the way out
    self:openStationScreen()
end

--- Where the market moves the player's goods: the hangar at the station
--- being traded with, and the ship's hold. Set once, before any trading.
function LimitTheoryRedux:connectMarket()
    MarketSystem:setPlayerAccess({
        hangar = function(key) return key and PlayerFactories:hangar(key) or nil end,
        cargo = function() return PlayerCargo:get() end,
    })
end

--- This system's stations by key, for the market and the player's lines.
---@return Entity[] stations, table<Entity, string> keys
function LimitTheoryRedux:marketStations()
    local stations, keys = {}, {}
    local places = self.npcs and self.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        if dock.key and dock.entity:isValid() then
            stations[#stations + 1] = dock.entity
            keys[dock.entity] = dock.key
        end
    end
    return stations, keys
end

--- What the player knows of this system's books, written down so the markets
--- of nearby systems can be read from the station screen later.
function LimitTheoryRedux:recordMarketIntel()
    local places = self.npcs and self.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        if dock.key and dock.entity:isValid() then
            local book = dock.entity:get(EconomyComponents.OrderBook)
            if book then
                MarketIntel:record(dock.key, self.currentSystemId or 1, dock.label,
                    book, self.simTime or 0)
            end
        end
    end
end

--- Fly a different hull: the one in hand goes into this station's hangar and
--- the new one comes out of it, then the ship is rebuilt around it. The fit
--- comes across as far as the new hull has room for it; the rest goes into
--- the hold (PlayerLoadout:restore says how much).
---@param hull HullDefinition
---@return boolean switched
function LimitTheoryRedux:switchHull(hull)
    local dock = self.docked
    if not dock then
        self:notify("Hulls are swapped at a station.", { 1.0, 0.7, 0.3 })
        return false
    end
    if not hull then return false end
    -- The button that calls this is drawn by the station screen, and the swap
    -- destroys the ship the screen is reading: it happens on the next
    -- simulation step instead, with the screen between frames.
    self.pendingHullSwitch = hull
    return true
end

--- Carry out a queued hull switch (`switchHull`), between frames.
function LimitTheoryRedux:processHullSwitch()
    local hull = self.pendingHullSwitch
    if not hull then return end
    self.pendingHullSwitch = nil
    local dock = self.docked
    if not dock then
        self:notify("Hulls are swapped at a station.", { 1.0, 0.7, 0.3 })
        return false
    end
    -- What is on the ship now is what comes across, whoever fitted it
    PlayerLoadout:record(self.playerShip)
    local hangar = dock.key and PlayerFactories:hangar(dock.key)
    local previous = PlayerShipyard:current()
    local ok, reason = PlayerShipyard:switch(hull, hangar)
    if not ok then
        self:notify("Cannot take that hull: " .. (reason or "no"), { 1.0, 0.4, 0.3 })
        return false
    end

    -- Rebuild the ship where it is docked, in the new frame
    local body = self.playerShip and self.playerShip:get(PhysicsComponents.RigidBody)
    local rb = body and body:getRigidBody()
    local position = rb and rb:getPos() or Position(dock.position.x, dock.position.y, dock.position.z)
    self:respawnPlayerShip(Position(position.x, position.y, position.z), nil)
    -- Docked again: the new ship is inside the station, as the old one was
    self:dockPlayer(dock)
    self:notify(string.format("Now flying the %s (was the %s)", hull.displayName,
        previous and previous.displayName or "none"), { 0.6, 0.9, 1.0 })
    return true
end

--- Fire the active module in a slot (the number keys). A slot with nothing
--- in it, or a passive module, says so rather than doing nothing silently.
---@param slot integer
function LimitTheoryRedux:fireModule(slot)
    if not self.playerShip or not self.playerShip:isValid() then return end
    local loadout = self.playerShip:get(ConstructComponents.Loadout)
    local fitting = loadout and loadout:getModule(slot)
    if not fitting then
        self:notify(string.format("Slot %d is empty.", slot), { 0.7, 0.7, 0.7 })
        return
    end
    if not fitting:isActive() then
        self:notify(string.format("%s works on its own.", fitting.displayName), { 0.7, 0.7, 0.7 })
        return
    end
    if fitting.ability.key == "miningLaser" then
        self:notify("Hold E to mine.", { 0.7, 0.7, 0.7 })
        return
    end
    local fired, reason = AbilitySystem:trigger(self.playerShip, fitting.ability.key, self)
    if not fired and reason then
        self:notify(reason, { 1.0, 0.7, 0.3 })
    end
end

--- What the fit changes beyond the ship's own components: the hold's
--- capacity, which lives with the player, not the hull.
function LimitTheoryRedux:applyFitToShip()
    if not self.playerShip or not self.playerShip:isValid() then return end
    local loadout = self.playerShip:get(ConstructComponents.Loadout)
    if not loadout then return end
    local added = loadout:getStat("cargoMass", 0)
    PlayerCargo:setCapacity(Config.game.cargo.holdCapacity + added)
    -- How far out the order books can be read is a fitted thing too: a
    -- datalink in a module slot buys a wider view of the market
    MarketIntel:setRange(math.floor(loadout:getStat("marketReach",
        Config.game.market.remoteJumps)))
end

--- What the fit says about a stat, or the default when nothing is fitted.
---@param stat string
---@param fallback number
---@return number
function LimitTheoryRedux:fitStat(stat, fallback)
    local loadout = self.playerShip and self.playerShip:isValid()
        and self.playerShip:get(ConstructComponents.Loadout)
    if not loadout then return fallback end
    return loadout:getStat(stat, fallback)
end

--- Whether the player knows what a rock holds. A rock is just a rock until
--- a Survey Scanner reads it, or until the laser has cut a unit out of it
--- and the hold says what came up.
---@param info table|nil the rock, from `mineableRock`
---@return boolean
function LimitTheoryRedux:knowsRock(info)
    if not info or not info.rock then return false end
    return (self.surveyedRocks or {})[info.rock] == true
end

--- Note that a rock's contents are known (a survey, or a unit mined out).
---@param info table|nil
function LimitTheoryRedux:markSurveyed(info)
    if not info or not info.rock then return end
    self.surveyedRocks = self.surveyedRocks or {}
    self.surveyedRocks[info.rock] = true
end

--- The module the player has fitted for an ability, or nil.
---@param abilityKey string
---@return FittingDefinition|nil fitting, integer|nil slot the key it is on
function LimitTheoryRedux:fittedAbility(abilityKey)
    local loadout = self.playerShip and self.playerShip:isValid()
        and self.playerShip:get(ConstructComponents.Loadout)
    if not loadout then return nil end
    return loadout:findAbility(abilityKey)
end

--- The player's rented lines at this system's stations, after the stations'
--- own lines have claimed the crew (ProductionSystem:update).
---@param dt number
function LimitTheoryRedux:updatePlayerFactories(dt)
    local places = self.npcs and self.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        if dock.key and dock.entity:isValid() then
            for _, event in ipairs(PlayerFactories:update(dock.entity, dock.key, dt)) do
                self:notify(event.text, { 1.0, 0.7, 0.3 })
            end
            PlayerFactories:mark(dock.key, self.simTime or 0)
        end
    end
end

--- Open the docked station's screen (the market). The cursor is freed: the
--- screen is clicked, not flown.
function LimitTheoryRedux:openStationScreen()
    if not self.docked then return end
    self:closeMap()
    CursorManager:free()
    UIPageGameplay:setView("Station")
end

--- Whether the station screen is the view that should be up.
---@return boolean
function LimitTheoryRedux:stationScreenOpen()
    return self.docked ~= nil and not self.pauseMenuOpen
end

--- Undock (Legacy Undock): the ship (a new one of the same kind, at rest)
--- comes out above the station, and the chase camera takes over again.
function LimitTheoryRedux:undockPlayer()
    local dock = self.docked
    if not dock then return end
    local p = dock.position
    local position = Position(p.x, p.y + dock.radius * 1.5 + 0.05, p.z + dock.radius * 0.5)
    self.docked = nil
    UIPageGameplay:setView("In_Game")
    self:respawnPlayerShip(position, Vec3f(0, 0, -1))
    self.player:setShip(self.playerShip)
    self.player:setOrbitTarget(nil)
    self.player:setMode(Enums.CameraMode.Chase)
    self.npcs:setPlayer(self.playerShip)
    self:updatePlayerVisibility()
    self.mapState._entityListBuilt = false
end

--- Switch the cloak on or off (Legacy Elements/Components/Cloak): while on,
--- weapons can't lock on to the ship, NPCs notice it only close by, and its
--- turrets hold fire.
---@param active boolean
function LimitTheoryRedux:setCloak(active)
    if active and (self.docked or self.cloak.charge < Config.game.cloak.minCharge) then return end
    self.cloak.active = active
    local targetable = self.playerShip and self.playerShip:get(ConstructComponents.Targetable)
    if targetable then targetable:setEnabled(not active) end
    if self.playerBattery then self.playerBattery:setAIActive(not active) end
    self:updatePlayerVisibility()
end

--- The cloak's charge drains while it is on and refills while it is off.
---@param dt number
function LimitTheoryRedux:updateCloak(dt)
    local cloak, cfg = self.cloak, Config.game.cloak
    if not cloak then return end
    if cloak.active then
        cloak.charge = cloak.charge - dt
        if cloak.charge <= 0 then
            cloak.charge = 0
            self:setCloak(false)
            self:notify("Cloak drained.", { 0.7, 0.7, 1.0 })
        end
    else
        cloak.charge = math.min(cfg.maxCharge, cloak.charge + cfg.rechargeRate * dt)
    end
end

--- The NPC ships for the system maps ({entity, label, color} each).
---@return table[]
function LimitTheoryRedux:mapNpcs()
    return self.npcs and self.npcs:mapEntries() or {}
end

--- The NPC ships the current system's hostility calls for.
function LimitTheoryRedux:populateSystem()
    self.npcs:clear()
    if not self:isTravelGame() then return end
    local places = { stations = {}, gates = self.jumpGates or {}, pointsOfInterest = {} }
    for _, station in ipairs(self.stations or {}) do
        local rbCmp = station:get(PhysicsComponents.RigidBody)
        if rbCmp and rbCmp:getRigidBody() then
            table.insert(places.stations, rbCmp:getRigidBody():getPos())
        end
    end
    for _, list in ipairs({ self.planets or {}, self.beltEntities or {} }) do
        for _, entity in ipairs(list) do
            local transform = entity:get(PhysicsComponents.Transform)
            if transform then table.insert(places.pointsOfInterest, transform:getPos()) end
        end
    end
    -- Stations are docks (Legacy Dockable), owned by Config.game.docking.owner
    places.docks = {}
    for index, station in ipairs(self.stations or {}) do
        local rbCmp = station:get(PhysicsComponents.RigidBody)
        local body = rbCmp and rbCmp:getRigidBody()
        if body then
            -- The key the player's hangar and leases are filed under: the
            -- system and the station's place in it, which is stable because
            -- a system's stations are built from the system's own seed
            local key = string.format("%d:%d", self.currentSystemId or 1, index)
            table.insert(places.docks, {
                entity = station,
                label = "Station " .. index,
                key = key,
                position = body:getPos(),
                radius = body:getBoundingRadius(),
                faction = Config.game.docking.owner,
            })
            -- What the player's lines made here while they were away
            for _, event in ipairs(PlayerFactories:catchUp(station, key, self.simTime or 0)) do
                self:notify(event.text, { 0.6, 0.9, 1.0 })
            end
        end
    end
    places.belts = self.beltEntities or {}
    self.npcs:setPlaces(places)
    self.npcs:setPlayer(self.playerShip)
    self:updatePlayerVisibility()

    -- Space dust around the camera, streaking with the ship's speed
    if Config.game.dust.enabled then
        self:addSceneEntity(SpaceDust.create(function()
            if self.docked or not self.playerShip or not self.playerShip:isValid() then return nil end
            local rbCmp = self.playerShip:get(PhysicsComponents.RigidBody)
            return rbCmp and rbCmp:getRigidBody() and rbCmp:getVelocity() or nil
        end))
    end
    local system = self.galaxy and self.galaxy.systems[self.currentSystemId]
    local level = self:currentHostility()
    if level then
        self.npcs:populate(level, system and system.seed or self.seed)
    end
end

--- A new game or a regenerated one starts in a new galaxy, in its first
--- system, with no course.
function LimitTheoryRedux:resetGalaxy()
    self.galaxy = nil
    self.currentSystemId = 1
    self.course = nil
    self.jump = nil
    Reputation:reset()
    PlayerWallet:reset()
    PlayerCargo:reset()
    PlayerFactories:reset()
    MarketIntel:reset()
    self:connectMarket()
    -- A new galaxy's rocks are all unread
    self.surveyedRocks = {}
    -- The ship a new game starts in: empty slots but for what it comes with
    AbilitySystem:reset()
    PlayerShipyard:reset(Config.game.fitting.startingHull)
    PlayerLoadout:reset(PlayerShipyard:moduleSlots())
    for _, name in ipairs(Config.game.fitting.startingModules) do
        local def = Fittings:getByName(name)
        if def then
            PlayerLoadout:grantModule(def)
        else
            Log.Warn("Config.game.fitting.startingModules names no fitting: %s", tostring(name))
        end
    end
    self.simTime = 0
    self.messages = {}
    self.docked = nil
    self.cloak = { charge = Config.game.cloak.maxCharge, active = false }
    if self.galaxyMapState then GalaxyMap:reset(self.galaxyMapState) end
end

--- Run the scenario's setup (after the scene and the player controller exist).
function LimitTheoryRedux:setupScenario()
    self.scenarioData = {}
    if self.scenario.setup then
        self.scenario.setup(self)
    end
    -- The scenario's text, which the HUD shows under its zone line
    local overlayLines = self.scenario.overlayLines
    UIViewInGame:setOverlayLines(overlayLines and function() return overlayLines(self) end or nil)
end

--- Orbits, gravity wells and the maps' entity lists, after the scene changed.
function LimitTheoryRedux:collectSceneSystems()
    self.orbiters, self.followers = OrbitalSystem:collectOrbiters(self.universe)
    GravityWellSystem:collectZones(self.universe)
    self.mapState._entityListBuilt = false
    self.mapState._dotCache = nil
    SystemMap:collectEntities(self.mapState, self.universe, self.playerShip, self:mapNpcs())
    SystemMap3D:collectEntities(self.map3DState, self.universe, self.playerShip, self:mapNpcs())
end

--- Generate the universe through UniverseManager + SolarSystemVisualizer.
---@param ruleset Ruleset
---@param seed integer the star system's seed
function LimitTheoryRedux:generateUniverse(ruleset, seed)
    self.universe = UniverseManager:createUniverse(ruleset, seed)

    if not self.universe then
        Log.Error("Failed to generate universe!")
        return
    end

    -- Rebase all entities to star-system-local coordinates (near origin)
    self.systemOrigin = CoordinateRebaser:rebaseStarSystem(self.universe)
    self.starSystem = nil
    local universeChildren = self.universe:get(CoreComponents.Children)
    if universeChildren then
        for child in universeChildren:iterChildren() do
            if tostring(child):find("StarSystemEntity") then
                self.starSystem = child
                break
            end
        end
    end

    SolarSystemVisualizer:materialize(self.universe, self.world)

    self.planets = {}
    self.labeledEntities = {}
    self.beltEntities = {}
    self.starEntity = nil
    self:collectEntities(self.universe)
end

--- Something a scenario added to the scene: it is removed with the scene
--- (Back to Main Menu, Regenerate), and labelled if it has a label.
---@param entity Entity
---@param options { label: string|nil, addBody: boolean|nil, bodyAdded: boolean|nil }|nil addBody: put its rigid body into the physics world (and take it out again on removal); bodyAdded: it is in the world already (take it out on removal)
function LimitTheoryRedux:addSceneEntity(entity, options)
    options = options or {}
    local ownsBody = options.bodyAdded == true
    if options.addBody then
        local rbCmp = entity:get(PhysicsComponents.RigidBody)
        if rbCmp and rbCmp:getRigidBody() then
            self.world:addRigidBody(rbCmp:getRigidBody())
            ownsBody = true
        end
    end
    table.insert(self.sceneEntities, { entity = entity, ownsBody = ownsBody })
    if options.label then
        table.insert(self.labeledEntities, { entity = entity, label = options.label })
    end
end

--- A construct (ConstructManager handle) a scenario added: destroyed with the
--- scene, and labelled if it has a label.
---@param handle table
---@param label string|nil
function LimitTheoryRedux:addSceneConstruct(handle, label)
    table.insert(self.sceneConstructs, handle)
    if label then
        table.insert(self.labeledEntities, { entity = handle.root, label = label })
    end
end

local function forgetLabel(labels, entity)
    for i = #labels, 1, -1 do
        if labels[i].entity == entity then
            table.remove(labels, i)
        end
    end
end

--- Remove something `addSceneEntity` added, now.
---@param entity Entity
function LimitTheoryRedux:removeSceneEntity(entity)
    for i, item in ipairs(self.sceneEntities) do
        if item.entity == entity then
            if item.ownsBody then
                local rbCmp = entity:get(PhysicsComponents.RigidBody)
                if rbCmp and rbCmp:getRigidBody() then
                    self.world:removeRigidBody(rbCmp:getRigidBody())
                end
            end
            table.remove(self.sceneEntities, i)
            break
        end
    end
    forgetLabel(self.labeledEntities, entity)
    if self.player and self.player:getOrbitTarget() == entity then
        self.player:setOrbitTarget(nil)
    end
    Registry:destroyEntity(entity, Enums.Registry.EntityDestroyMode.DestroyChildren)
end

--- Destroy a construct `addSceneConstruct` added, now.
---@param handle table
function LimitTheoryRedux:removeSceneConstruct(handle)
    for i, h in ipairs(self.sceneConstructs) do
        if h == handle then
            table.remove(self.sceneConstructs, i)
            break
        end
    end
    forgetLabel(self.labeledEntities, handle.root)
    if self.player and self.player:getOrbitTarget() == handle.root then
        self.player:setOrbitTarget(nil)
    end
    self.constructManager:destroy(handle)
end

--- Start the orbit camera around an entity (a scenario's planet, station...).
---@param entity Entity
---@param distances table|nil zoom range, see `orbitDistances`
function LimitTheoryRedux:setOrbitFocus(entity, distances)
    self.player:setOrbitTarget(entity, distances)
    -- From the lit side: a little off the sun's direction, from slightly above
    local sun = CameraManager:getStarDir()
    self.player:setOrbitAngles(math.atan2(sun.x, sun.z) + 0.5, 0.25)
    self.player:setMode(Enums.CameraMode.Orbit)
end

--- A zoom range for orbiting something of this radius.
---@param radius number
---@return table
function LimitTheoryRedux:orbitDistances(radius)
    return {
        distance    = radius * 3.0,
        minDistance = radius * 1.2,
        maxDistance = radius * 40.0,
        zoomRatio   = 0.15,
    }
end

--- Remove what a game built: the scenario's things, the stations, the star
--- system and (unless kept) the player's ship.
---@param keepShip boolean|nil
function LimitTheoryRedux:destroyScene(keepShip)
    if self.scenario and self.scenario.teardown then
        self.scenario.teardown(self)
    end
    -- Beams, projectiles and effect lights, before the ships they came from
    if self.weaponCombat then
        self.weaponCombat:clear()
    end
    if self.npcs then
        self.npcs:clear()
    end
    -- Before the things it may follow go
    if self.player then
        self.player:setOrbitTarget(nil)
    end

    for i = #(self.sceneEntities or {}), 1, -1 do
        self:removeSceneEntity(self.sceneEntities[i].entity)
    end
    for i = #(self.sceneConstructs or {}), 1, -1 do
        self:removeSceneConstruct(self.sceneConstructs[i])
    end

    for _, station in ipairs(self.stations or {}) do
        local rbCmp = station:get(PhysicsComponents.RigidBody)
        if rbCmp and rbCmp:getRigidBody() then
            self.world:removeRigidBody(rbCmp:getRigidBody())
        end
        Registry:destroyEntity(station, Enums.Registry.EntityDestroyMode.DestroyChildren)
    end
    self.stations = {}

    -- The gates are children of the star system: the universe takes their
    -- entities with it below, but their bodies have to leave the world first.
    for _, gate in ipairs(self.jumpGates or {}) do
        local rbCmp = gate.entity:get(PhysicsComponents.RigidBody)
        if rbCmp and rbCmp:getRigidBody() then
            self.world:removeRigidBody(rbCmp:getRigidBody())
        end
    end
    self.jumpGates = {}
    self.gateWatch = nil
    self.starSystem = nil

    if self.universe then
        Registry:destroyEntity(self.universe, Enums.Registry.EntityDestroyMode.DestroyChildren)
        self.universe = nil
    end

    if not keepShip then
        if self.playerShipHandle then
            self.constructManager:destroy(self.playerShipHandle)
        elseif self.playerShip then
            Registry:destroyEntity(self.playerShip, Enums.Registry.EntityDestroyMode.DestroyChildren)
        end
        self.playerShipHandle = nil
        self.playerShip = nil
    end

    self.planets = {}
    self.labeledEntities = {}
    self.starEntity = nil
    self.beltEntities = {}
    AsteroidFieldSystem:cleanup(self.world)

    releaseGpuMemory()
end

--- Walk the generated universe and collect planets/labels/star/belts.
---@param entity Entity
function LimitTheoryRedux:collectEntities(entity)
    local name = tostring(entity)

    if name:find("PlanetEntity") then
        table.insert(self.planets, entity)
        table.insert(self.labeledEntities, { entity = entity, label = name })
    elseif name:find("MoonEntity") then
        table.insert(self.labeledEntities, { entity = entity, label = name })
    elseif name:find("StarEntity") then
        self.starEntity = entity
    elseif name:find("AsteroidBeltEntity") then
        table.insert(self.beltEntities, entity)
    end

    local childrenCmp = entity:get(CoreComponents.Children)
    if childrenCmp then
        for child in childrenCmp:iterChildren() do
            self:collectEntities(child)
        end
    end
end

--- Where the player's ship starts when the scenario doesn't say: next to the
--- belt rock nearest the first planet (so the first thing the player sees is
--- a rock up close, with the ring/planet nearby); without rocks, just outside
--- the first planet; without planets, well clear of the star.
---@return Position
function LimitTheoryRedux:defaultShipSpawn()
    local cfg = self.cfg
    local planet = self.planets and self.planets[1]

    if planet then
        local planetPos = planet:get(PhysicsComponents.Transform):getPos()

        -- Nearest belt asteroid to the planet: belt data is baked
        -- relative to the belt's render origin (the parent body when one
        -- exists, else the belt's own transform).
        local beltEntity = self.beltEntities and self.beltEntities[1]
        local beltCmp = beltEntity and beltEntity:get(CelestialComponents.AsteroidBelt)
        local asteroids = beltCmp and beltCmp:getAsteroidData() or {}

        local ox, oy, oz = 0, 0, 0
        if beltEntity then
            local originEntity = beltEntity
            local parentCmp = beltEntity:get(CoreComponents.Parent)
            if parentCmp then
                local p = parentCmp:getParent()
                if p and p:get(PhysicsComponents.Transform) then originEntity = p end
            end
            local t = originEntity:get(PhysicsComponents.Transform)
            if t then local p = t:getPos() ox, oy, oz = p.x, p.y, p.z end
        end

        local bestIdx, bestDistSq = 1, math.huge
        for i = 1, #asteroids do
            local a = asteroids[i]
            local dx = (ox + a.px) - planetPos.x
            local dy = (oy + a.py) - planetPos.y
            local dz = (oz + a.pz) - planetPos.z
            local d = dx * dx + dy * dy + dz * dz
            if d < bestDistSq then bestDistSq = d; bestIdx = i end
        end

        local a = asteroids[bestIdx]
        if a then
            -- Just off the rock's surface, on the side away from the planet
            local ax, ay, az = ox + a.px, oy + a.py, oz + a.pz
            local clearDist = a.scale * 2.0
            local px, py, pz = planetPos.x, planetPos.y, planetPos.z
            local nx, ny, nz = ax - px, ay - py, az - pz
            local len = math.sqrt(nx * nx + ny * ny + nz * nz)
            if len > 1e-9 then nx, ny, nz = nx / len, ny / len, nz / len end
            return Position(ax + nx * clearDist, ay + ny * clearDist, az + nz * clearDist)
        end

        -- No rocks: just outside the planet, on its side away from the star
        local radius = planet:get(PhysicsComponents.Transform):getScale()
        local sx, sy, sz = 0, 0, 0
        if self.starEntity then
            local p = self.starEntity:get(PhysicsComponents.Transform):getPos()
            sx, sy, sz = p.x, p.y, p.z
        end
        local nx, ny, nz = planetPos.x - sx, planetPos.y - sy, planetPos.z - sz
        local len = math.sqrt(nx * nx + ny * ny + nz * nz)
        if len > 1e-9 then nx, ny, nz = nx / len, ny / len, nz / len else nx, ny, nz = 1, 0, 0 end
        local d = radius * cfg.shipSpawnOffset
        return Position(planetPos.x + nx * d, planetPos.y + ny * d, planetPos.z + nz * d)
    end

    -- No planets: well clear of the star (it sits at the origin otherwise)
    if self.starEntity then
        local t = self.starEntity:get(PhysicsComponents.Transform)
        local p = t:getPos()
        return Position(p.x + t:getScale() * cfg.starSpawnOffset, p.y, p.z)
    end
    return Position(0, 0, 0)
end

--- Spawn the player's ship where the scenario says, or at the default spot.
function LimitTheoryRedux:spawnPlayerShip()
    local spawnPos = self.scenario.spawnShip and self.scenario.spawnShip(self) or self:defaultShipSpawn()
    self:createPlayerShip(spawnPos, Enums.ShipType.Fighter, 1, self.rng:get31())
end

--- Build a flyable ship for the player.
---@param position Position
---@param shipType integer Enums.ShipType
---@param hullIdx integer index into Config.game.shipHulls (size and mass)
---@param seed integer
function LimitTheoryRedux:createPlayerShip(position, shipType, hullIdx, seed)
    local flightCfg = Config.game.shipFlight
    local hullCfg = Config.game.shipHulls

    -- The travel game: an armed gunship (its turrets engage hostile ships by
    -- themselves). Anything else, or a gunship that fails to build: the
    -- plain ship asked for.
    self.playerBattery = nil
    local gunship = self:isTravelGame() and Config.game.playerGunship.enabled
        and self:buildPlayerGunship(position, seed)
    if gunship then
        self.playerShipHandle = gunship.shipHandle
    else
        self.playerShipHandle = self.constructManager:createShip({
            seed = seed,
            shipType = shipType,
            config = {
                position = position,
                scale = hullCfg.scale[hullIdx],
                isKinematic = false,
                -- The Legacy basic and capital generators size the hull by its
                -- index; the fighter's has its own size
                hull = shipType ~= Enums.ShipType.Fighter and hullIdx or nil,
            },
        })
    end
    self.playerShip = self.playerShipHandle.root
    -- What placeShipAtArrival rebuilds after a jump
    self.playerShipSpec = { shipType = shipType, hullIdx = hullIdx, seed = seed }

    self.playerShip:add(ConstructComponents.TravelDrive())
    self.playerShip:add(ConstructComponents.AutoPilot())
    local flightCtrl = ConstructComponents.ShipFlightControl()
    self.playerShip:add(flightCtrl)

    local rbCmp = self.playerShip:get(PhysicsComponents.RigidBody)
    local rb = rbCmp:getRigidBody()
    rb:setMass(hullCfg.mass[hullIdx])
    rb:setDrag(flightCfg.linearDrag, flightCfg.angularDrag)
    rb:setFriction(0)
    rb:setSleepThreshold(0, 0)

    if self:isTravelGame() then
        -- NPCs see it, pirates shoot at it, and its death ends the game
        self.playerShip:add(ConstructComponents.Targetable(Factions.Player, Enums.Target.SizeClass.Medium))
        if self.npcs then self.npcs:setPlayer(self.playerShip) end
    end
    if gunship then
        -- Turn like the fighter: torque scaled by the size difference
        local turnScale = Config.game.playerGunship.turnScale
        if turnScale == "auto" then
            local ratio = rb:getBoundingRadius() / hullCfg.radius[hullIdx]
            turnScale = math.max(1, math.min(400, ratio * ratio))
        end
        flightCtrl.torqueScale = turnScale
        -- The fit comes back onto the new hull: its guns, its modules and the
        -- stats they come to (PlayerLoadout outlives the ship entity)
        -- Anything the new hull has no room for goes into the station's
        -- hangar when there is one, and into the hold otherwise
        local spare = self.docked and self.docked.key and PlayerFactories:hangar(self.docked.key)
            or PlayerCargo:get()
        local returned, lost = PlayerLoadout:restore(self.playerShip, gunship.turrets,
            PlayerShipyard:moduleSlots(), spare)
        if returned > lost then
            self:notify(string.format("%d fitting(s) would not fit this hull; they are in %s.",
                returned - lost, spare == PlayerCargo:get() and "the hold" or "the hangar"),
                { 1.0, 0.7, 0.3 })
        end
        if lost > 0 then
            self:notify(string.format("No room for %d unfitted part(s) -- they are gone.", lost),
                { 1.0, 0.4, 0.3 })
        end
        self:applyFitToShip()
        self.playerBattery = self.weaponCombat:addBattery(WeaponBattery(gunship, {
            name = "Your ship",
            aiActive = true,
            team = Factions.Player,
            hostileTeams = Factions.hostileTeams(Factions.Player),
        }))
    end

    Log.Info("Player ship spawned at (%.1f, %.1f, %.1f)", position.x, position.y, position.z)
end

--- The player's gunship (an ArmedShipBuilder construction), or nil if it
--- could not be built (logged; the caller builds the plain ship instead).
---@param position Position
---@param seed integer
---@return table|nil construction
function LimitTheoryRedux:buildPlayerGunship(position, seed)
    local cfg = Config.game.playerGunship
    -- The hull being flown decides the mounts, the capacitor, the stats and
    -- the size; the fit decides everything else (PlayerShipyard, HullDefs)
    local hull = PlayerShipyard:current()
    local stats = hull and PlayerShipyard:stats() or cfg
    local ok, result = pcall(function()
        return ArmedShipBuilder:build(GunshipRecipe.build(seed, Factions.Player, stats, hull), {
            constructManager = self.constructManager,
            shipConfig = {
                position = position,
                scale = PlayerShipyard:scale(cfg.scale),
                isKinematic = false,
            },
        })
    end)
    if not ok then
        Log.Error("Player gunship could not be built, flying the plain ship: %s", tostring(result))
        return nil
    end
    result.shipBody:setCollidable(true)
    return result
end

--- Swap the player's ship for a new one in the same place (a scenario's
--- showcase of hulls, say).
---@param shipType integer Enums.ShipType
---@param hullIdx integer index into Config.game.shipHulls
---@param seed integer
function LimitTheoryRedux:replacePlayerShip(shipType, hullIdx, seed)
    local oldBody = self.playerShip:get(PhysicsComponents.RigidBody):getRigidBody()
    local position = oldBody:getPos()
    -- The orbit camera goes back to following the ship (the new one)
    if self.player:getOrbitTarget() == self.playerShip then
        self.player:setOrbitTarget(nil)
    end
    self.constructManager:destroy(self.playerShipHandle)
    self:createPlayerShip(Position(position.x, position.y, position.z), shipType, hullIdx, seed)
    self.player:setShip(self.playerShip)
end

--- Spawn stations near planets.
function LimitTheoryRedux:spawnStations()
    self.stations = {}
    local cfg = self.cfg

    local numStations = math.min(cfg.maxStations, #self.planets)
    for i = 1, numStations do
        local planet = self.planets[i]
        local transform = planet:get(PhysicsComponents.Transform)
        local planetPos = transform:getPos()
        local planetScale = transform:getScale()

        local orbitDist = planetScale * cfg.stationOrbitMult
        local angle = (i - 1) * math.pi * 0.7
        local stationPos = Position(
            planetPos.x + math.cos(angle) * orbitDist,
            planetPos.y,
            planetPos.z + math.sin(angle) * orbitDist
        )

        local station = StationGenerator:createStation(self.rng:get31(), {
            position = stationPos,
            scale = cfg.stationScale,
            isKinematic = true,
        })

        local stationRbCmp = station:get(PhysicsComponents.RigidBody)
        if stationRbCmp and stationRbCmp:getRigidBody() then
            self.world:addRigidBody(stationRbCmp:getRigidBody())
        end

        -- A shop and a factory floor: what it makes, and what it opens with
        -- (the ores of this system, so there is something to trade on day one)
        station:add(EconomyComponents.Stock())
        station:add(EconomyComponents.Workforce(Config.game.production.stationCrew))
        station:add(EconomyComponents.OrderBook())
        local oreIds = self:systemOreIds()
        ProductionSystem:assign(station, self.rng, i == 1, oreIds)
        StationTradeSystem:stock(station, self.rng, oreIds)

        table.insert(self.stations, station)
        table.insert(self.labeledEntities, { entity = station, label = "Station " .. i })
    end
end

--- The ores of this system's belts and rings, by item id: what its stations
--- deal in besides what they make.
---@return integer[]
function LimitTheoryRedux:systemOreIds()
    local seen, ids = {}, {}
    for _, belt in ipairs(self.beltEntities or {}) do
        for _, ore in ipairs(AsteroidOre.forField(belt)) do
            if not seen[ore.def.id] then
                seen[ore.def.id] = true
                ids[#ids + 1] = ore.def.id
            end
        end
    end
    return ids
end

--- The galaxy around the first star system (made once per game: jumps keep
--- it) and the current system's jump gates, one per link, gathered at one or
--- two planets or belts.
function LimitTheoryRedux:spawnJumpGates()
    if not self.starSystem then return end

    if not self.galaxy then
        -- A seed of its own, next to the game seed (RNG.Create mixes the
        -- seed, so neighbouring seeds give unrelated streams)
        self.galaxy = GalaxyGenerator:generate(self.seed + 1, { position = self.systemOrigin },
            UniverseScaleConfig.universe, Config.game.galaxy)
        self:assignRulesets()
        for _, line in ipairs(GalaxyGenerator:describe(self.galaxy)) do
            Log.Info("Galaxy: %s", line)
        end
    end

    local system = self.galaxy.systems[self.currentSystemId]
    self.jumpGates = JumpGateGenerator:createGates({
        seed = system.seed + 2,
        galaxy = self.galaxy,
        systemId = system.id,
        starSystem = self.starSystem,
        planets = self.planets or {},
        belts = self.beltEntities or {},
        star = self.starEntity,
        world = self.world,
        cfg = Config.game.jumpGates,
    })
    -- Each gate's label says, in its colour, how dangerous the other side is
    local levels = Config.game.hostility.levels
    for _, gate in ipairs(self.jumpGates) do
        local level = levels[gate.destination.hostility] or levels[1]
        table.insert(self.labeledEntities, {
            entity = gate.entity,
            label = string.format("Gate to %s · %s", gate.destination.name, level.name),
            color = level.color,
        })
    end
end

--- Each galaxy system's seed and ruleset: the first is the game's own star
--- system (the game seed, the scenario's ruleset); the others pick a ruleset
--- by weight (Config.game.galaxy.rulesets) from their seed.
function LimitTheoryRedux:assignRulesets()
    local choices = Config.game.galaxy.rulesets
    local total = 0
    for _, choice in ipairs(choices) do total = total + choice.weight end

    for _, system in ipairs(self.galaxy.systems) do
        if system.id == 1 then
            system.seed = self.seed
            system.ruleset = self.scenario.ruleset or Scenarios.default.ruleset
        else
            local pick = RNG.Create(system.seed):getUniformRange(0, total)
            for _, choice in ipairs(choices) do
                pick = pick - choice.weight
                if pick <= 0 or choice == choices[#choices] then
                    system.ruleset = Rulesets[choice.name]
                    break
                end
            end
        end
    end
    self:assignHostility()
end

--- Each galaxy system's hostility level (an index into
--- Config.game.hostility.levels): the first system's is `homeLevel`; the
--- others pick by weight, the weights leaning toward the dangerous levels
--- the more jumps a system is from the first.
function LimitTheoryRedux:assignHostility()
    local cfg = Config.game.hostility
    for _, system in ipairs(self.galaxy.systems) do
        if system.id == 1 then
            system.hostility = cfg.homeLevel
        else
            local route = GalaxyGenerator:route(self.galaxy, 1, system.id)
            local jumps = route and #route or 1
            local weights, total = {}, 0
            for i, level in ipairs(cfg.levels) do
                weights[i] = level.weight * (1 + cfg.distanceBias * jumps) ^ (i - 1)
                total = total + weights[i]
            end
            local pick = RNG.Create(system.seed + 5):getUniformRange(0, total)
            system.hostility = #cfg.levels
            for i, w in ipairs(weights) do
                pick = pick - w
                if pick <= 0 then
                    system.hostility = i
                    break
                end
            end
        end
    end
end

--- Follow a route through the galaxy: autopilot to the gate of the next
--- system on it; arriving there jumps (see `updateJumps`), and in each new
--- system the course carries on until the last.
---@param route integer[] the systems after the current one
function LimitTheoryRedux:setCourse(route)
    if not route or #route == 0 then
        self.course = nil
        return
    end
    self.course = route
    self:continueCourse()
end

--- Autopilot to the gate of the course's next system, if there is one here.
function LimitTheoryRedux:continueCourse()
    if not self.course or #self.course == 0 or not self.gateWatch then
        self.course = nil
        return
    end
    local gate = JumpGateSystem:gateTo(self.gateWatch, self.course[1])
    if not gate then
        Log.Warn("Course: no gate to %s here", self.galaxy.systems[self.course[1]].name)
        self.course = nil
        return
    end
    AutoPilotSystem:engageEntity(self.playerShip, gate.entity,
        Config.game.jumpGates.activationRange * 0.5)
end

--- Each simulation step: a jump when the ship flew through a gate, or when
--- the course's autopilot brought it in range of the gate it heads for.
function LimitTheoryRedux:updateJumps()
    if self.jump or not self.gateWatch or #self.gateWatch.gates == 0 then return end
    local rb = self.playerShip:get(PhysicsComponents.RigidBody):getRigidBody()
    local pos = rb:getPos()

    local lastPos = self.gateWatch.lastPos
    local crossed = JumpGateSystem:update(self.gateWatch, pos)
    if crossed then
        self:startJump(crossed)
        return
    end

    if self.course and #self.course > 0 then
        local gate = JumpGateSystem:gateTo(self.gateWatch, self.course[1])
        if gate and JumpGateSystem:passedWithin(gate, lastPos, pos, Config.game.jumpGates.activationRange) then
            self:startJump(gate)
        end
    end
end

--- The nearest gate, if it is close enough to jump through with J.
---@return JumpGatePlacement|nil
function LimitTheoryRedux:gateInRange()
    if not self.gateWatch or not self.playerShip then return nil end
    local pos = self.playerShip:get(PhysicsComponents.RigidBody):getRigidBody():getPos()
    local gate, dist = JumpGateSystem:nearest(self.gateWatch, pos)
    if gate and dist < Config.game.jumpGates.activationRange then return gate end
    return nil
end

--- Jump through a gate: the screen goes dark, this star system goes, and a
--- few frames later (the GPU frees the old system's memory meanwhile) the
--- destination is built and the ship arrives at its gate back.
---@param gate JumpGatePlacement
function LimitTheoryRedux:startJump(gate)
    local from = self.currentSystemId
    local to = gate.destination.id
    Log.Info("Jump: %s -> %s", self.galaxy.systems[from].name, gate.destination.name)

    if self.course and self.course[1] == to then
        table.remove(self.course, 1)
        if #self.course == 0 then self.course = nil end
    elseif self.course then
        self.course = nil -- flew off course
    end
    AutoPilotSystem:disengage(self.playerShip)

    -- Close any map (a course can jump while one is open)
    self:closeMap()

    -- Leaving the scenario's own system ends the scenario: its things go
    -- with the scene (destroyScene runs its teardown), and from the next
    -- system on it is plain travel (finishJump).
    self.jump = { from = from, to = to, name = gate.destination.name, frames = REBUILD_DELAY_FRAMES }
    self:destroyScene(true)
    if self.skybox then
        Registry:destroyEntity(self.skybox, Enums.Registry.EntityDestroyMode.DestroyChildren)
        self.skybox = nil
    end
    UIViewInGame:setPlayer(nil)
end

--- The second half of a jump: build the destination system around the ship.
function LimitTheoryRedux:finishJump()
    local jump = self.jump
    local system = self.galaxy.systems[jump.to]
    self.currentSystemId = jump.to

    self.scenario = {
        name = self.scenario.name,
        ruleset = self.scenario.ruleset,
        orbits = self.scenario.orbits,
    }
    UIViewInGame:setOverlayLines(nil)

    self.rng = RNG.Create(system.seed)
    self:createSkybox(system.seed)
    SystemMap3D:setSkybox(self.map3DState, self.skybox)

    self.sceneEntities = {}
    self.sceneConstructs = {}
    self:generateUniverse(system.ruleset, system.seed)
    self:spawnStations()
    self:spawnJumpGates()
    self.gateWatch = JumpGateSystem:watch(self.jumpGates)

    self:placeShipAtArrival(jump.from)
    self.player:setShip(self.playerShip)
    UIViewInGame:setPlayer(self.player)
    self:populateSystem()
    self:collectSceneSystems()

    self.jump = nil
    self.jumpFade = Config.game.jumpGates.fadeTime
    self.systemBanner = SYSTEM_BANNER_TIME
    self:continueCourse()
end

--- Put the player's ship (a new one of the same kind: it arrives at rest)
--- just outside the gate that leads back to `fromId`, on the far side from
--- that system, facing away from the gate.
---@param fromId integer
function LimitTheoryRedux:placeShipAtArrival(fromId)
    local cfg = Config.game.jumpGates
    local gate = JumpGateSystem:gateTo(self.gateWatch, fromId)
    local position, facing
    if gate then
        local a, d = gate.axis, gate.radius * cfg.arrivalDistance
        position = Position(gate.position.x - a.x * d, gate.position.y - a.y * d, gate.position.z - a.z * d)
        facing = Vec3f(-a.x, -a.y, -a.z)
    else
        position = self:defaultShipSpawn()
    end

    self:respawnPlayerShip(position, facing)

    -- Where and by which gate the ship arrived (for JumpTest)
    self.lastArrival = { position = position, gate = gate }
    JumpGateSystem:reset(self.gateWatch)
end

--- Replace the player's ship with a new one of the same kind (at rest,
--- whole) at `position`, facing `facing` (nil: as built).
---@param position Position
---@param facing Vec3f|nil
function LimitTheoryRedux:respawnPlayerShip(position, facing)
    local spec = self.playerShipSpec
    if self.player:getOrbitTarget() == self.playerShip then
        self.player:setOrbitTarget(nil)
    end
    if self.playerBattery then
        self.weaponCombat:removeBattery(self.playerBattery)
        self.playerBattery = nil
    end
    self.constructManager:destroy(self.playerShipHandle)
    self:createPlayerShip(position, spec.shipType, spec.hullIdx, spec.seed)
    if facing then
        local up = math.abs(facing.y) > 0.99 and Vec3f(1, 0, 0) or Vec3f(0, 1, 0)
        self.playerShip:get(PhysicsComponents.RigidBody):getRigidBody():setRot(Quat.FromLookUp(facing, up))
    end
    if self.cloak then self.cloak.active = false end
end

--- The frame over an open map: which map, its controls, how to leave.
function LimitTheoryRedux:drawMapFrame()
    if self.mapMode == 0 or self.pauseMenuOpen then return end
    MapFrame.draw(self.mapMode, self.galaxy and 3 or 2, 0, 0, Window:width(), Window:height())
end

--- Close whichever map is open; the ship's controls come back next frame.
function LimitTheoryRedux:closeMap()
    if self.mapMode == 0 then return end
    SystemMap3D:deactivate(self.map3DState)
    self.mapState.enabled = false
    self.map3DState.enabled = false
    self.galaxyMapState.enabled = false
    self.mapMode = 0
    self.mapClosedFrame = true
end

--- The navigation overlay: the jump's fade, the banner of the system just
--- entered (its name and how dangerous it is), and the lines under the HUD
--- (the system and its hostility, a gate in range, the course).
function LimitTheoryRedux:drawNavigation()
    local w, h = Window:width(), Window:height()
    local levels = Config.game.hostility.levels
    local font = 'Unageo-Medium'

    if self.jump or (self.jumpFade and self.jumpFade > 0) then
        local alpha = self.jump and 1.0 or math.min(1.0, self.jumpFade / Config.game.jumpGates.fadeTime)
        DrawEx.SimpleRect(0, 0, w, h, Color(0, 0, 0, alpha))
        if self.jump then
            local destination = self.galaxy.systems[self.jump.to]
            local level = levels[destination.hostility] or levels[1]
            DrawEx.TextAlpha(font, "Jumping to " .. self.jump.name, 24,
                0, h * 0.42, w, 40, 0.6, 0.9, 1.0, alpha, 0.5, 0.5)
            DrawEx.TextAlpha(font, level.name:upper() .. " SPACE", 18,
                0, h * 0.42 + 44, w, 30, level.color[1], level.color[2], level.color[3], alpha, 0.5, 0.5)
            return
        end
    end

    if not self.galaxy then return end
    local level = self:currentHostility() or levels[1]
    local c = level.color
    local name = self.galaxy.systems[self.currentSystemId].name

    -- The banner after arriving: fades out over its last second
    if self.systemBanner and self.systemBanner > 0 and self.mapMode == 0 and not self.pauseMenuOpen then
        local alpha = math.min(1.0, self.systemBanner)
        local y = h * 0.16
        DrawEx.SimpleRect(0, y - 12, w, 104, Color(0, 0, 0, 0.45 * alpha))
        DrawEx.SimpleRect(0, y - 12, w, 2, Color(c[1], c[2], c[3], 0.8 * alpha))
        DrawEx.SimpleRect(0, y + 90, w, 2, Color(c[1], c[2], c[3], 0.8 * alpha))
        DrawEx.TextAlpha(font, name, 30, 0, y, w, 40, 1.0, 1.0, 1.0, alpha, 0.5, 0.5)
        DrawEx.TextAlpha(font, level.name:upper() .. " SPACE", 20, 0, y + 40, w, 26,
            c[1], c[2], c[3], alpha, 0.5, 0.5)
        DrawEx.TextAlpha(font, level.description or "", 13, 0, y + 66, w, 20,
            0.85, 0.85, 0.85, alpha, 0.5, 0.5)
    end

    if self.mapMode ~= 0 or self.hudHidden or self.pauseMenuOpen then return end
    local lines = {}
    table.insert(lines, { text = string.format("%s  ·  %s", name, level.name), color = c })
    if self.docked then
        local missing, cost = self:hullRepairQuote()
        local repair = missing > 0 and string.format("R: repair hull (%s)", PlayerWallet.format(cost))
            or "Hull intact"
        table.insert(lines, { text = "Docked  ·  " .. repair .. "  ·  F: undock", color = { 0.6, 0.9, 1.0 } })
    elseif self:isTravelGame() then
        local dock = self:dockInRange()
        if dock then
            table.insert(lines, { text = "F: dock", color = { 0.6, 0.9, 1.0 } })
        end
        -- Mining: what the rock in reach holds, and how the hold is doing
        local rock = self.miningTarget
        if not rock and not self:fittedAbility("miningLaser") and self.miningNoLaserHint then
            table.insert(lines, { text = "A rock, and nothing fitted to cut it: a Mining Laser goes in a module slot",
                color = { 1.0, 0.7, 0.3 } })
        end
        if rock then
            local mining = GeneralActions.Mine:isDown()
            -- An unread rock is just a rock: a Survey Scanner says what is in
            -- it, and so does cutting a unit out of it
            if self:knowsRock(rock) then
                table.insert(lines, {
                    text = mining
                        and string.format("Mining %s  ·  %d left in the rock  ·  hold %s",
                            rock.rock.item, math.floor(rock.rock.yield), PlayerCargo:describeLoad())
                        or string.format("E: mine %s (%d left)", rock.rock.item, math.floor(rock.rock.yield)),
                    color = mining and { 0.5, 1.0, 0.7 } or { 0.6, 0.9, 1.0 },
                })
            else
                local scanner, scannerSlot = self:fittedAbility("surveyScan")
                table.insert(lines, {
                    text = mining and string.format("Mining an unsurveyed rock  ·  hold %s",
                            PlayerCargo:describeLoad())
                        or (scanner
                            and string.format("E: mine an unsurveyed rock  ·  %d: survey it",
                                scannerSlot or 1)
                            or "E: mine an unsurveyed rock  ·  a Survey Scanner would say what is in it"),
                    color = mining and { 0.5, 1.0, 0.7 } or { 0.7, 0.75, 0.8 },
                })
            end
        end
    end
    if self.cloak and self:isTravelGame() then
        local cfg = Config.game.cloak
        if self.cloak.active then
            table.insert(lines, { text = string.format("CLOAKED  %.0fs  ·  X: decloak", self.cloak.charge),
                color = { 0.7, 0.7, 1.0 } })
        elseif self.cloak.charge < cfg.maxCharge then
            table.insert(lines, { text = string.format("Cloak charging %d%%", math.floor(100 * self.cloak.charge / cfg.maxCharge)),
                color = { 0.55, 0.55, 0.8 } })
        end
    end
    local gate = self:gateInRange()
    if gate and not self.docked then
        local gl = levels[gate.destination.hostility] or levels[1]
        table.insert(lines, {
            text = string.format("J: jump to %s (%s)", gate.destination.name, gl.name),
            color = { 0.6, 0.9, 1.0 },
        })
    end
    if self.course and #self.course > 0 then
        local names = {}
        for _, id in ipairs(self.course) do table.insert(names, self.galaxy.systems[id].name) end
        table.insert(lines, { text = "Course: " .. table.concat(names, " > "), color = { 0.6, 0.9, 1.0 } })
    end
    for _, message in ipairs(self.messages or {}) do
        table.insert(lines, { text = message.text, color = message.color, alpha = math.min(1, message.time) })
    end
    local top = h - 140 - math.max(0, #lines - 3) * 20
    for i, line in ipairs(lines) do
        DrawEx.TextAlpha(font, line.text, 14, 0, top + (i - 1) * 20, w, 18,
            line.color[1], line.color[2], line.color[3], 0.9 * (line.alpha or 1), 0.5, 0.5)
    end

    -- Credits and standing with each faction, top right
    if self:isTravelGame() then
        DrawEx.TextAlpha(font, PlayerWallet.format(PlayerWallet:get()), 15,
            w - 290, 48, 270, 18, 1.0, 0.85, 0.35, 0.95, 1.0, 0.5)
        local hold = PlayerCargo:describeLoad()
        if not PlayerCargo:isEmpty() then
            local rows = PlayerCargo:list()
            hold = string.format("%s  ·  %s", hold, rows[1].item.displayName)
            if #rows > 1 then hold = hold .. string.format(" +%d", #rows - 1) end
        end
        DrawEx.TextAlpha(font, hold, 12, w - 290, 66, 270, 16, 0.75, 0.85, 0.9, 0.85, 1.0, 0.5)
        -- The modules on the number keys, and what they are doing
        local modules = AbilitySystem:status(self.playerShip)
        local moduleY = 84
        for _, row in ipairs(modules) do
            local label, cr, cg, cb
            if row.active > 0 then
                label = string.format("%d  %s  %.0fs", row.slot, row.fitting.displayName, row.active)
                cr, cg, cb = 0.5, 1.0, 0.7
            elseif row.ready then
                label = string.format("%d  %s", row.slot, row.fitting.displayName)
                cr, cg, cb = 0.85, 0.9, 0.95
            else
                label = string.format("%d  %s  %.0fs", row.slot, row.fitting.displayName, row.remaining)
                cr, cg, cb = 0.55, 0.57, 0.62
            end
            DrawEx.TextAlpha(font, label, 12, w - 290, moduleY, 270, 16, cr, cg, cb, 0.9, 1.0, 0.5)
            moduleY = moduleY + 16
        end
        local y = math.max(88, moduleY + 4)
        for _, faction in ipairs({ Factions.Security, Factions.Trader, Factions.Pirate }) do
            local r, g, b = Factions.color(faction)
            DrawEx.TextAlpha(font, string.format("%s  %+.2f  %s", Factions.name(faction),
                Reputation:get(faction), Reputation:describe(faction)), 12,
                w - 290, y, 270, 16, r, g, b, 0.85, 1.0, 0.5)
            y = y + 18
        end
    end
end

---@param data EventData
function LimitTheoryRedux:onRender(data)
    if not self.playerShip then
        -- Menu phase: the background star system renders through the modern
        -- core first; the HmGui pages draw on top via Gui:draw below.
        if self.menuWorld then
            self:updateMenuCamera(data:deltaTime())
            CelestialLightingSystem:update(self.starEntity)
            RenderCoreSystem:render(data)
        end
        self:immediateUI(function()
            Gui:draw()
        end)
        return
    end

    CelestialLightingSystem:update(self.starEntity)
    if self.jumpFade then
        self.jumpFade = self.jumpFade - data:deltaTime()
        if self.jumpFade <= 0 then self.jumpFade = nil end
    end
    for i = #(self.messages or {}), 1, -1 do
        local message = self.messages[i]
        message.time = message.time - data:deltaTime()
        if message.time <= 0 then table.remove(self.messages, i) end
    end
    if self.systemBanner and not self.jump then
        self.systemBanner = self.systemBanner - data:deltaTime()
        if self.systemBanner <= 0 then self.systemBanner = nil end
    end

    -- The HUD text (In_Game view) hides with the HUD toggle and in the 3D map.
    UIViewInGame:setHudShown(not self.hudHidden and self.mapMode ~= 2)

    if self.mapMode == 2 then
        SystemMap3D:collectEntities(self.map3DState, self.universe, self.playerShip, self:mapNpcs())
        SystemMap3D:render(self.map3DState, data)

        self:immediateUI(function()
            -- The flare goes under the HUD and the pause menu
            LensFlareSystem:draw(self.starEntity, self.labeledEntities)
            Gui:draw()
            SystemMap3D:renderOverlay(self.map3DState, 0, 0, Window:width(), Window:height())
            self:drawMapFrame()
        end)
    else
        RenderCoreSystem:render(data)

        self:immediateUI(function()
            -- The flares go under the HUD and the pause menu
            LensFlareSystem:draw(self.starEntity, self.labeledEntities)
            ExplosionEffectSystem:drawFlares()
            Gui:draw()
            -- These draw after Gui:draw, so they'd sit on top of the pause menu
            -- and the Controls screen: hide them while those are open.
            local showHud = not self.hudHidden and not self.pauseMenuOpen
            -- Name labels next to planets, stations and the nearest asteroids:
            -- the Show HUD Indicator Names setting.
            local showLabels = showHud and GameState.ui.showIndicatorNames
            if showLabels then
                WorldLabelRenderSystem:draw(self.labeledEntities)
            end

            local spawned = AsteroidFieldSystem:getSpawnedEntities()
            if #spawned > 0 and showLabels then
                local eye = CameraManager:getEye()
                if eye then
                    for _, aInfo in ipairs(spawned) do
                        aInfo._dist = (aInfo.pos.x - eye.x)^2 + (aInfo.pos.z - eye.z)^2
                    end
                    table.sort(spawned, function(a, b) return a._dist < b._dist end)
                end
                local asteroidLabels = {}
                for i = 1, math.min(10, #spawned) do
                    table.insert(asteroidLabels, {
                        entity = spawned[i].entity,
                        label = spawned[i].label,
                    })
                end
                WorldLabelRenderSystem:draw(asteroidLabels, 20000)
            end

            self:drawNavigation()
            if self.mapMode == 3 then
                GalaxyMap:draw(self.galaxyMapState, 0, 0, Window:width(), Window:height())
            end

            if self.mapMode == 1 then
                local ap = self.playerShip:get(ConstructComponents.AutoPilot)
                if ap and ap:isActive() then
                    local tPos = ap:getTargetPos()
                    local tEnt = ap:getTargetEntity()
                    if tEnt then
                        local tRb = tEnt:get(PhysicsComponents.RigidBody)
                        if tRb and tRb:getRigidBody() then tPos = tRb:getRigidBody():getPos() end
                    end
                    self.mapState.autopilotTargetPos = tPos
                    self.mapState.autopilotPos = ap.interceptPos or tPos
                else
                    self.mapState.autopilotPos = nil
                    self.mapState.autopilotTargetPos = nil
                end
                SystemMap:collectEntities(self.mapState, self.universe, self.playerShip, self:mapNpcs())
                SystemMap:draw(self.mapState, 0, 0, Window:width(), Window:height())
            end
            self:drawMapFrame()
        end)
    end
end

---@param data EventData
function LimitTheoryRedux:onInput(data)
    if self:handleAppInput() then return end

    -- Regenerate waits a few frames between tearing down and building
    if self.rebuildInFrames then
        self.rebuildInFrames = self.rebuildInFrames - 1
        if self.rebuildInFrames <= 0 then
            self.rebuildInFrames = nil
            self:finishRegenerate()
        end
    end

    if self.jump then
        self.jump.frames = self.jump.frames - 1
        if self.jump.frames <= 0 then
            self:finishJump()
        end
        return
    end

    if not self.playerShip then return end
    local dt = data:deltaTime()

    -- Escape toggles the pause menu (Return to Game / Controls / Back to Main
    -- Menu / Exit); from the Controls screen it goes back to the pause menu.
    if Input:isPressed(ApplicationBindings.Escape) then
        if self.controlsOpen then
            self:closeControls()
        elseif self.mapMode ~= 0 and not self.pauseMenuOpen then
            self:closeMap()
        elseif self.pauseMenuOpen then
            self:closePauseMenu()
        else
            self:openPauseMenu()
        end
    end
    if self.pauseMenuOpen then return end

    GeneralActions.CycleMapMode:update(dt)
    GeneralActions.AutoPilotToggle:update(dt)
    GeneralActions.Regenerate:update(dt)
    GeneralActions.ReloadShaders:update(dt)
    GeneralActions.Jump:update(dt)
    GeneralActions.Dock:update(dt)
    GeneralActions.Cloak:update(dt)
    GeneralActions.Mine:update(dt)
    GeneralActions.Repair:update(dt)
    for slot, binding in ipairs({ GeneralActions.Module1, GeneralActions.Module2,
                                  GeneralActions.Module3, GeneralActions.Module4 }) do
        binding:update(dt)
        if binding:isPressed() and not self.docked then
            self:fireModule(slot)
        end
    end

    if GeneralActions.CycleMapMode:isPressed() then
        -- 2D map, 3D map, then the galaxy map when there is a galaxy
        self.mapMode = (self.mapMode + 1) % (self.galaxy and 4 or 3)
        self.mapState.enabled = (self.mapMode == 1)
        self.map3DState.enabled = (self.mapMode == 2)
        self.galaxyMapState.enabled = (self.mapMode == 3)

        if self.mapMode == 1 then
            self.mapState._entityListBuilt = false
            self.mapState._dotCache = nil
            SystemMap:collectEntities(self.mapState, self.universe, self.playerShip, self:mapNpcs())
            CursorManager:free()
        elseif self.mapMode == 2 then
            SystemMap3D:collectEntities(self.map3DState, self.universe, self.playerShip, self:mapNpcs())
            SystemMap3D:activate(self.map3DState)
        else
            SystemMap3D:deactivate(self.map3DState)
            if self.mapMode == 3 then
                GalaxyMap:open(self.galaxyMapState, self.galaxy, self.currentSystemId, self.course)
                CursorManager:free()
            else
                self.mapClosedFrame = true
            end
        end
    end

    if self.mapClosedFrame and self.mapMode == 0 then
        self.mapClosedFrame = false
        self.player:setMode(self.player:getMode())
    end

    if self.mapMode > 0 then
        local ctrl = self.player:getActiveController()
        if ctrl and ctrl:isEnabled() then ctrl:disable() end
        self.player:setInputBlocked(true)

        if self.mapMode == 3 then
            GalaxyMap:updateInput(self.galaxyMapState, dt)

            local route = self.galaxyMapState.route
            if GeneralActions.AutoPilotToggle:isPressed() and route and #route > 0 then
                self:setCourse(route)
                self.mapMode = 0
                self.galaxyMapState.enabled = false
                self.mapClosedFrame = true
            end
        elseif self.mapMode == 1 then
            SystemMap:updateInput(self.mapState, dt)

            if GeneralActions.AutoPilotToggle:isPressed() and self.mapState.selected then
                local sel = self.mapState.selected
                if sel.clickPos then
                    local parentEnt = sel._parentEntity
                    local localX = sel._clickLocalX
                    local localZ = sel._clickLocalZ
                    AutoPilotSystem:engagePosition(self.playerShip, sel.clickPos, nil, parentEnt, localX, localZ)
                else
                    AutoPilotSystem:engageEntity(self.playerShip, sel.entity)
                end
                self.mapMode = 0
                self.mapState.enabled = false
                self.mapClosedFrame = true
            end
        else
            SystemMap3D:updateInput(self.map3DState, dt)

            if GeneralActions.AutoPilotToggle:isPressed() and self.map3DState.selected then
                AutoPilotSystem:engageEntity(self.playerShip, self.map3DState.selected.entity)
                self.mapMode = 0
                self.map3DState.enabled = false
                SystemMap3D:deactivate(self.map3DState)
                self.mapClosedFrame = true
            end
        end
        return
    else
        self.player:setInputBlocked(false)
    end

    if GeneralActions.AutoPilotToggle:isPressed() then
        if AutoPilotSystem:isActive(self.playerShip) then
            AutoPilotSystem:disengage(self.playerShip)
            self.course = nil -- cancelling the autopilot cancels the course
        end
    end

    if GeneralActions.Jump:isPressed() and not self.docked then
        local gate = self:gateInRange()
        if gate then self:startJump(gate) end
    end

    if GeneralActions.Dock:isPressed() and self:isTravelGame() then
        if self.docked then
            self:undockPlayer()
        else
            local dock, refused = self:dockInRange()
            if dock then
                self:dockPlayer(dock)
            elseif refused then
                self:notify(Factions.name(refused.faction) .. " refuse you docking.", { 1.0, 0.4, 0.3 })
            end
        end
    end

    if GeneralActions.Repair:isPressed() and self.docked then
        self:repairHull()
    end

    if GeneralActions.Cloak:isPressed() and self:isTravelGame() then
        if self.cloak.active then
            self:setCloak(false)
        elseif self.cloak.charge < Config.game.cloak.minCharge then
            self:notify("Cloak still charging.", { 0.7, 0.7, 1.0 })
        else
            self:setCloak(true)
        end
    end

    if self.scenario.onInput then
        self.scenario.onInput(self, dt)
    end

    if GeneralActions.Regenerate:isPressed() then
        self:regenerateScenario()
    end

    if GeneralActions.ReloadShaders:isPressed() then
        local Material = require("Shared.Rendering.Material")
        Cache.ReloadShaders()
        Material.ReloadAll()
    end
end

---@param data EventData
function LimitTheoryRedux:onStateSim(data)
    if not self.playerShip or self.jump then return end
    local dt = data:deltaTime()

    -- Static star system: skip orbital motion so bodies stay at their
    -- generated positions (deterministic scene while orbital mechanics
    -- are still being developed). Asteroid fields still follow parents.
    -- Every step of the sim is its own profiler scope (F10, or the stats
    -- server's /profile.json): the gameplay scripts are the main thread's
    -- largest cost, and without these the whole frame reads as one block.
    if not self.staticStarSystem then
        Profiler.Begin('Sim.Orbits')
        OrbitalSystem:update(self.orbiters, dt, self.followers)
        Profiler.End()
    end
    Profiler.Begin('Sim.AsteroidFields')
    AsteroidFieldSystem:updatePositions()
    Profiler.End()
    Profiler.Begin('Sim.GravityWells')
    GravityWellSystem:update(dt, self.playerShip)
    Profiler.End()
    Profiler.Begin('Sim.AsteroidSpawns')
    AsteroidFieldSystem:update(dt, self.beltEntities, self.world, self.playerShip)
    Profiler.End()
    Profiler.Begin('Sim.MapTrails')
    SystemMap3D:updateTrails(self.map3DState, dt)
    Profiler.End()

    MemoryReporter:update(dt)

    Profiler.Begin('Sim.Player')
    self.player:update(dt)
    self:updateCloak(dt)
    self:updateMining(dt)
    AbilitySystem:update(self.playerShip, dt)
    -- A hull the refit screen asked for: the ship is rebuilt here, not inside
    -- the screen's own draw
    self:processHullSwitch()
    self.simTime = (self.simTime or 0) + dt
    -- The player's shields recharge (DefenseComponent:update had no caller)
    local playerDefense = self.playerShip:get(ConstructComponents.Defense)
    if playerDefense and not self.docked then playerDefense:update(dt) end
    Profiler.End()
    -- NPC ships fly (kinematic) before the physics step, like scenario things
    Profiler.Begin('Sim.NPCs')
    self.npcs:update(dt)
    Profiler.End()
    -- The stations' factory floors, and the goods they cannot make arriving
    Profiler.Begin('Sim.Economy')
    ProductionSystem:update(self.stations or {}, dt)
    self:updatePlayerFactories(dt)
    StationTradeSystem:update(self.stations or {}, dt)
    -- The books: lapsed orders go, and the stations re-post theirs as their
    -- stock moves
    local stations, keys = self:marketStations()
    MarketSystem:update(stations, keys, dt, self.simTime or 0)
    self.marketIntelTimer = (self.marketIntelTimer or 0) - dt
    if self.marketIntelTimer <= 0 then
        self.marketIntelTimer = Config.game.market.refreshInterval
        self:recordMarketIntel()
    end
    Profiler.End()
    if self.scenario.update then
        Profiler.Begin('Sim.Scenario')
        self.scenario.update(self, dt)
        Profiler.End()
    end
    -- Weapons: targets and turrets before the physics step, AI, aim and
    -- firing right after it (shots in flight: onStatePostSim)
    Profiler.Begin('Sim.Weapons.PreUpdate')
    self.weaponCombat:preUpdate(dt)
    Profiler.End()
    Profiler.Begin('Sim.Physics')
    self.world:update(dt)
    Profiler.End()
    self:updateJumps()
    if self.jump then return end -- the scene (and the scenario) just went
    Profiler.Begin('Sim.Weapons.Turrets')
    self.weaponCombat:syncTurrets()
    Profiler.End()
    Profiler.Begin('Sim.Weapons.Update')
    self.weaponCombat:update(dt)
    Profiler.End()
    if self.scenario.postUpdate then
        Profiler.Begin('Sim.Scenario.Post')
        self.scenario.postUpdate(self, dt)
        Profiler.End()
    end
end

---@param data EventData
function LimitTheoryRedux:onStatePostSim(data)
    if not self.playerShip then return end
    -- Projectiles, beams, expired effect lights
    Profiler.Begin('Sim.Weapons.PostUpdate')
    self.weaponCombat:postUpdate(data:deltaTime())
    Profiler.End()
    -- Explosions age, and go when they are done
    Profiler.Begin('Sim.Explosions')
    ExplosionEffectSystem:update(data:deltaTime())
    Profiler.End()
end

--- Regenerate (B): what the scenario does for it, or by default a new seed
--- and everything built again.
function LimitTheoryRedux:regenerateScenario()
    if self.scenario.regenerate then
        self.scenario.regenerate(self)
    else
        self.seed = self.rng:get31()
        self:regenerate()
    end
end

--- Build the star system, the player's ship, the stations and the scenario's
--- things again from `self.seed` (Regenerate picks a new seed first).
---
--- The old scene goes now and the new one comes a few frames later: the GPU
--- frees the old scene's textures only once the frames that drew them are
--- done, and building at once would need room for both (a Standard Solar
--- System alone takes about 4 GB).
function LimitTheoryRedux:regenerate()
    self:destroyScene()
    UIViewInGame:setPlayer(nil) -- no ship for the HUD meanwhile
    self.rebuildInFrames = REBUILD_DELAY_FRAMES
end

--- The second half of `regenerate`: build the scene again.
function LimitTheoryRedux:finishRegenerate()
    self.rng = RNG.Create(self.seed)
    self:resetGalaxy()
    self:buildScene()
    self.player:setShip(self.playerShip)
    UIViewInGame:setPlayer(self.player)
    self:setupScenario()
    self:collectSceneSystems()
end

function LimitTheoryRedux:soundOn()
    GameState.audio.soundEnabled = true
    MusicPlayer:setVolume(MusicPlayer.lastVolume)
end

function LimitTheoryRedux:soundOff()
    GameState.audio.soundEnabled = false
    MusicPlayer:setVolume(0)
end

--* any operations we want to do before exiting the game
function LimitTheoryRedux:exit()
    -- Update Session vars ; temporary until we have a save state
    GameState.player.startupCamera = GameState.player.currentCamera
    -- Write player-specific game variables to preserve them across gameplay sessions
    InitFiles:writeUserInits()

    Engine:exit()
end

return LimitTheoryRedux
