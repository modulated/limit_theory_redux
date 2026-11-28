-- LTheoryRedux: the main game state. Flow: main menu (HmGui) -> New Game
-- -> startGame(seed) builds the scene through UniverseManager + Rulesets
-- + SolarSystemVisualizer, then renders via RenderCoreSystem with HUD,
-- system maps, and player ship control.
Namespace.LoadInline('Legacy')
Namespace.LoadInline('Legacy.Systems')

LimitTheoryRedux = require('States.Application')

-- Sound / persistence
local SoundManager = require('Legacy.Systems.SFX.SoundManager')
local UIMouse = require("Input.UIMouse")
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
local ShipFlightSystem = require('Modules.Constructs.Systems.ShipFlightSystem')
local GravityWellSystem = require('Modules.Physics.Systems.GravityWellSystem')
local CelestialLightingSystem = require('Modules.Rendering.Systems.CelestialLightingSystem')
local LensFlareSystem = require('Modules.Rendering.Systems.LensFlareSystem')
local WorldLabelRenderSystem = require('Modules.UI.Systems.WorldLabelRenderSystem')
local AsteroidFieldSystem = require('Modules.CelestialObjects.Systems.AsteroidFieldSystem')
local GeneralActions = require('Input.ActionBindings.GeneralActions')
local CursorManager = require('Input.CursorManager')
local SystemOverview = require('Modules.Navigation.Systems.SystemOverview')
local SaveGame = require('Shared.Save.SaveGame')
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
local PlayerStations = require('Modules.Economy.Managers.PlayerStations')
local ActionBar = require('Modules.Constructs.Managers.ActionBar')
local MiningBeam = require('Modules.Constructs.Systems.MiningBeam')
local BountyBoard = require('Modules.Economy.Managers.BountyBoard')
local PlayerForces = require('Modules.Economy.Managers.PlayerForces')
local LootSystem = require('Modules.Economy.Systems.LootSystem')
local LootData = require('Shared.Data.LootData')
local Items = require('Shared.Registries.Items')
local GalaxyGenerator = require('Modules.Navigation.Managers.GalaxyGenerator')
local JumpGateGenerator = require('Modules.Navigation.Managers.JumpGateGenerator')
local JumpGateSystem = require('Modules.Navigation.Systems.JumpGateSystem')
local GalaxyMap = require('Modules.Navigation.Systems.GalaxyMap')
local NpcSystem = require('Modules.NPC.Systems.NpcSystem')
local Reputation = require('Modules.NPC.Reputation')
local CombatLog = require('Modules.Constructs.Systems.CombatLog')
local WeaponSystem = require('Modules.Constructs.Systems.WeaponSystem')
local PlayerWallet = require('Modules.Economy.Managers.PlayerWallet')
local PlayerCargo = require('Modules.Economy.Managers.PlayerCargo')
local PlayerFactories = require('Modules.Economy.Managers.PlayerFactories')
local MarketSystem = require('Modules.Economy.Systems.MarketSystem')
local GalaxyEconomy = require('Modules.Economy.Managers.GalaxyEconomy')
local MarketIntel = require('Modules.Economy.Managers.MarketIntel')
local StationTradeSystem = require('Modules.Economy.Systems.StationTradeSystem')
local ProductionSystem = require('Modules.Economy.Systems.ProductionSystem')
local EconomyComponents = require('Modules.Economy.Components')
local AsteroidOre = require('Shared.Helpers.AsteroidOre')
local CoreComponentsAll = require('Modules.Core.Components')
local RenderComponent = require('Modules.Rendering.Components').Render
local Factions = require('Modules.NPC.Factions')
local GunshipRecipe = require('Modules.NPC.Managers.GunshipRecipe')
local PlayerFleet = require('Modules.Constructs.Managers.PlayerFleet')
local ShipFittingSystem = require('Modules.Constructs.Systems.ShipFittingSystem')
local AbilitySystem = require('Modules.Constructs.Systems.AbilitySystem')
local Hulls = require('Shared.Definitions.HullDefs')
local Fittings = require('Shared.Registries.Fittings')
local ArmedShipBuilder = require('Modules.Constructs.Managers.ArmedShipBuilder')
local WeaponBattery = require('Modules.Constructs.Systems.WeaponBattery')
local DrawEx = require('UI.DrawEx')
local LoadingScreen = require('UI.LoadingScreen')
local GameFlow = require('States.App.GameFlow')
local Phase = GameFlow.Phase
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
    -- Two actions on one key: said once, at start-up (Input/BindingConflicts)
    require("Input.BindingConflicts").report()
    -- Where the game is in its life: one state, checked moves (GameFlow)
    self.flow = GameFlow.new()
    self:traceNpcLoss()
    -- Expose the scene builder to the main menu (New Game button)
    GameState.startGame = function(seed, scenario) self:requestNewGame(seed, scenario) end

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
    self.settingsOpen = false
    require("UI.HmGui.Views.MainMenu.Settings").exit = nil
    self.saveSlotsMode = nil
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
--- The Settings screen from the pause menu (Options); its Back comes here.
function LimitTheoryRedux:openSettings()
    local SettingsView = require("UI.HmGui.Views.MainMenu.Settings")
    self.settingsOpen = true
    SettingsView.exit = function() self:closeSettings() end
    UIPageGameplay:setView("Settings")
end

function LimitTheoryRedux:closeSettings()
    local SettingsView = require("UI.HmGui.Views.MainMenu.Settings")
    self.settingsOpen = false
    SettingsView.exit = nil
    UIPageGameplay:setView("Paused")
end

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
    self:endGame()
    -- The menu needs a free cursor (closePauseMenu re-applied the gameplay
    -- capture); release it before switching back to the menu.
    CursorManager:free()
    self:initMainMenu()
end

--- End the game in progress: its systems stop and its scene goes. What
--- follows is the main menu, or (loading a save) another game.
function LimitTheoryRedux:endGame()
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
    self.playerShip = nil
    self.overviewShown = false
    self.flow:to(Phase.Menu, "game ended")
end

------------------------------------------------------------------------------
-- Saving and loading (Shared/Save/SaveGame.lua: what is kept and how)
------------------------------------------------------------------------------

--- Save the game into a slot.
---@param slot string
---@param quiet boolean|nil no message on success (the autosave)
---@return boolean ok
---@return string|nil problem
function LimitTheoryRedux:saveGame(slot, quiet)
    if not self.playerShip or not self.playerShip:isValid() then return false, "no game to save" end
    if not self.flow:is(Phase.InSystem, Phase.Docked) then
        return false, "not now (" .. self.flow.phase .. ")"
    end
    local ok, problem = SaveGame.save(self, slot)
    if ok then
        if not quiet then
            self:notify(string.format("Saved: %s", SaveGame.SLOT_NAMES[slot] or slot), { 0.6, 0.9, 1.0 })
        end
    else
        Log.Error("Save to %s failed: %s", slot, tostring(problem))
        self:notify("Could not save: " .. tostring(problem), { 1.0, 0.4, 0.3 })
    end
    return ok, problem
end

--- Load a slot: the game in progress (if any) ends, and the saved one is
--- made again from its seed and put back as it was.
---@param slot string
---@return boolean ok
---@return string|nil problem
function LimitTheoryRedux:loadGame(slot)
    if not self.flow:can(Phase.Loading) then
        return false, "not now (" .. self.flow.phase .. ")"
    end
    local meta, state, fromBackup = SaveGame.read(slot)
    if not meta then
        local problem = tostring(state)
        Log.Warn("Load of %s failed: %s", slot, problem)
        SaveGame.lastProblem = string.format("%s: %s", SaveGame.SLOT_NAMES[slot] or slot, problem)
        if self.playerShip then self:notify("Could not load: " .. problem, { 1.0, 0.4, 0.3 }) end
        return false, problem
    end
    SaveGame.lastProblem = nil

    -- The scene in hand goes now and the saved one is built a few frames
    -- later, as Regenerate and a jump do: the GPU frees the old scene's
    -- textures only once the frames that drew them are done, and building at
    -- once would need room for both
    if self._simTunnel then self:endGame() end
    self:cleanupMenuBackground()
    if GameState.paused then GameState:Unpause() end
    self.flow:to(Phase.Loading, SaveGame.SLOT_NAMES[slot] or slot)
    LoadingScreen.show({
        kind = "load",
        title = "Loading",
        subtitle = SaveGame.SLOT_NAMES[slot] or slot,
        minTime = 1.2,
        steps = { "Reading the save", "Rebuilding the star system", "Restoring your ship and holdings" },
    })
    self.pendingLoad = {
        state = state,
        seed = SaveGame.unpackSeed(state.game.seed),
        scenario = Scenarios.find(state.game and state.game.scenario) or Scenarios.default,
        slot = slot,
        fromBackup = fromBackup,
        frames = REBUILD_DELAY_FRAMES,
    }
    return true
end

--- A new game from the menu: the loading screen goes up, and the game is
--- built behind it once it has been seen (`pendingStart`, onInput).
---@param seed any
---@param scenario table|nil
function LimitTheoryRedux:requestNewGame(seed, scenario)
    if not self.flow:to(Phase.Starting, "new game") then return end
    LoadingScreen.show({
        kind = "new",
        title = "New game",
        subtitle = scenario and scenario.name and ("Scenario: " .. scenario.name) or nil,
        minTime = 1.4,
        steps = { "Charting the galaxy", "Forming the star system", "Building stations", "Fuelling your ship" },
    })
    self.pendingStart = { seed = seed, scenario = scenario, frames = REBUILD_DELAY_FRAMES }
end

--- The second half of a load: build the saved game.
function LimitTheoryRedux:finishLoadGame()
    local pending = self.pendingLoad
    self.pendingLoad = nil
    self.loading = true
    self:startGame(pending.seed, pending.scenario, pending.state)
    self.loading = false
    LoadingScreen.finish()
    local name = SaveGame.SLOT_NAMES[pending.slot] or pending.slot
    self:notify(string.format("Loaded: %s%s", name,
        pending.fromBackup and " (its last save was damaged: the one before it was loaded)" or ""),
        pending.fromBackup and { 1.0, 0.7, 0.3 } or { 0.6, 0.9, 1.0 })
end

--- Save into the autosave slot (on docking), quietly. Not while a save is
--- being loaded (that docking is the load's own).
function LimitTheoryRedux:autosave()
    if self.loading then return end
    self:saveGame("autosave", true)
end

--- The pause menu's Save and Load screens.
---@param mode string "save" or "load"
function LimitTheoryRedux:openSaveSlots(mode)
    SaveGame.invalidate()
    self.saveSlotsMode = mode
    UIPageGameplay:setView("SaveSlots")
end

--- Back from them to the pause menu.
function LimitTheoryRedux:closeSaveSlots()
    self.saveSlotsMode = nil
    UIPageGameplay:setView("Paused")
end

--- Start a game: the scenario's star system (ruleset-driven generation, then
--- materialization of planets/rings/belts), the player's ship, the stations
--- and the scenario's own things; then the systems that run it.
---@param seed integer|nil nil = a random seed
---@param scenario Scenario|nil nil = the default scenario
---@param seed any the game's seed (nil: a new one)
---@param scenario Scenario|nil
---@param load table|nil a saved game's state (SaveGame): the game is the
---  saved one, made again from its seed and put back as it was
function LimitTheoryRedux:startGame(seed, scenario, load)
    setGameScale()
    GameState:SetState(Enums.GameStates.InGame)

    -- In-game soundtrack: queue every non-menu track and play one.
    MusicPlayer:playAmbient()

    -- Drop the menu background (its universe/world/camera) before building
    -- the gameplay scene.
    self:cleanupMenuBackground()

    self.cfg = SceneConfig
    self.scenario = scenario or Scenarios.default
    -- The scenario the game began as: a jump replaces self.scenario with a
    -- plain description, and a save has to name the scenario it came from
    self.startScenarioId = self.scenario.id
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
        CombatLog:onHit(function(event) self:onCombatHit(event); self:battleText(event) end)
        CombatLog:onKill(function(event) self:onCombatKill(event) end)
    end
    RenderCoreSystem:setDebugPhysics(self.world)

    self:createSkybox()
    self:resetGalaxy()
    -- A saved game: what the player owns and has done goes back before
    -- anything is built, so the ship is built in the saved hull
    if load then SaveGame.restoreManagers(self, load) end
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

    -- The game is up (a load may now dock, or jump to its saved system)
    self.flow:to(Phase.InSystem, "game built")
    if load then self:finishLoad(load) end
end

--- The rest of loading, once the game's own start has run: into the saved
--- system the way a jump goes (if the save was elsewhere), and the ship where
--- it was.
---@param state table
function LimitTheoryRedux:finishLoad(state)
    local saved = state.game and state.game.system or 1
    if self.galaxy and saved ~= self.currentSystemId and self.galaxy.systems[saved] then
        -- The rebuild a jump does (finishJump), arriving where the save was
        -- rather than at a gate
        self.flow:to(Phase.Jumping, "to the saved system")
        self.jump = { from = nil, to = saved, name = self.galaxy.systems[saved].name,
                      frames = REBUILD_DELAY_FRAMES, arrival = state.player or {} }
        self:destroyScene(true)
        if self.skybox then
            Registry:destroyEntity(self.skybox, Enums.Registry.EntityDestroyMode.DestroyChildren)
            self.skybox = nil
        end
        UIViewInGame:setPlayer(nil)
        return
    end
    self:placeShipFromSave(state.player or {})
    self:dockFromSave(state.player or {})
end

--- The ship where the save had it (a new one of the saved kind, at rest).
---@param player table { position, forward }
function LimitTheoryRedux:placeShipFromSave(player)
    local p, f = player.position, player.forward
    if not p then return end
    self:respawnPlayerShip(Position(p.x, p.y, p.z), f and Vec3f(f.x, f.y, f.z) or nil)
end

--- Docked again at the station the save was docked at.
---@param player table { docked = station key }
function LimitTheoryRedux:dockFromSave(player)
    if not player.docked then return end
    local places = self.npcs and self.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        if dock.key == player.docked then
            self:dockPlayer(dock)
            return
        end
    end
    Log.Warn("Load: the station the save was docked at (%s) is not here", tostring(player.docked))
end

--- A saved game's stock for a station of the saved system, as it is built.
---@param station Entity
---@param key string
function LimitTheoryRedux:applySavedStationStock(station, key)
    local saved = self.savedStationStock and self.savedStationStock[key]
    if not saved then return end
    self.savedStationStock[key] = nil
    local stock = station:get(EconomyComponents.Stock)
    if not stock then return end
    stock.units = {}
    for itemId, n in pairs(saved.units or {}) do stock.units[itemId] = n end
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
    -- The outposts' guns engage whom the player is hostile to
    for _, entry in ipairs(self.playerStationEntities or {}) do
        local battery = entry.defense and entry.defense.battery
        if battery then
            local set = {}
            for _, team in ipairs(Factions.hostileTeams(Factions.Player)) do set[team] = true end
            battery.hostileTeams = set
        end
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
    -- The player's own ships: friendly fire costs no standing with anyone
    if not record or record.faction == Factions.Player then return end
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
    if not self.npcs then return end
    -- An outpost's guns or one of the player's own ships: an outlaw's
    -- bounty is the owner's; no standing moves
    if self:isOutpostDefense(event.attacker) or self:isPlayerUnit(event.attacker) then
        local record = self.npcs:recordOf(event.target)
        local economy = Config.game.economy
        local contract = BountyBoard:claim(record)
        if contract then
            self:notify(string.format("Contract on '%s' complete: +%s", contract.callsign,
                PlayerWallet.format(contract.reward)), { 1.0, 0.85, 0.35 })
        end
        if record and Factions.isHostile(economy.bountyIssuer, record.faction) then
            local bounty = economy.bounties[record.role] or economy.defaultBounty
            PlayerWallet:add(bounty, "Bounty (outpost defences): " .. record.label)
            self:notify(string.format("Your forces destroyed %s: bounty +%s", record.label,
                PlayerWallet.format(bounty)), { 1.0, 0.85, 0.35 })
        end
        return
    end
    if not self.playerShip or event.attacker ~= self.playerShip then return end
    local record = self.npcs:recordOf(event.target)
    if not record then return end
    local contract = BountyBoard:claim(record)
    if contract then
        self:notify(string.format("Contract on '%s' complete: +%s", contract.callsign,
            PlayerWallet.format(contract.reward)), { 1.0, 0.85, 0.35 })
    end
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
    if not ignoreLaser and not self:miningMount() then return nil end
    local rbCmp = self.playerShip:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if not body then return nil end
    local pos = body:getPos()
    local cfg = Config.game.mining
    local best, bestDist
    for _, info in ipairs(AsteroidFieldSystem:getSpawnedEntities()) do
        if info.field and info.asteroid then
            -- A better sensor reaches further (Survey Scanner, Ship Sensor)
            local reach = self:rockRadius(info)
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
    if self.docked or self.mapMode ~= 0 or self.jump then
        if self.miningJob then self:stopMining() end
        self.miningTarget, self.miningScan, self.miningNoLaserHint = nil, nil, false
        return
    end
    -- What is in reach, for the HUD: looking walks the spawned asteroids, so
    -- a few times a second, not once a frame
    self.miningScan = (self.miningScan or 0) - dt
    if self.miningScan <= 0 then
        self.miningScan = Config.game.mining.playerScanInterval
        if self:miningMount() then
            self.miningTarget = self:mineableRock()
            self.miningNoLaserHint = false
        else
            self.miningTarget = nil
            self.miningNoLaserHint = self:mineableRock(true) ~= nil
        end
    end

    local job = self.miningJob
    if not job then return end
    MiningBeam:update(dt)
    -- The laser has to still be there, and the rock still in reach with
    -- something left in it
    local def, mountId = self:miningMount(job.mountId)
    if not def then
        self:stopMining("The mining laser is gone.")
        return
    end
    local info = job.rock
    if not info or not info.entity or not info.entity:isValid() or info.rock.yield < 1 then
        self:stopMining("Mining stopped: nothing left in the rock.")
        return
    end
    if not self:rockInReach(info) then
        self:stopMining("Mining stopped: the rock is out of the laser's reach.")
        return
    end
    local hold = PlayerCargo:get()
    if hold:getRoomFor(info.rock.itemId) < 1 then
        self:stopMining("Mining stopped: the hold is full.", { 1.0, 0.4, 0.3 })
        return
    end

    -- A cycle at a time: at the end of each the cut ore goes into the hold,
    -- and the next cycle starts on its own
    local cycle = self:miningCycle(def)
    job.progress = job.progress + dt
    if job.progress < cycle then return end
    job.progress = 0
    local want = math.min(def.tool.units, math.floor(info.rock.yield), hold:getRoomFor(info.rock.itemId))
    local got = 0
    for _ = 1, want do
        if not self.npcs.mining:take(info.rock) then break end
        if PlayerCargo:add(info.rock.itemId, 1) < 1 then
            info.rock.yield = info.rock.yield + 1
            break
        end
        got = got + 1
    end
    if got > 0 then
        -- A unit in the hold is the rock identified, whatever the scanner said
        if not self:knowsRock(info) then self:markSurveyed(info) end
        self:notify(string.format("+%d %s  ·  hold %s", got, info.rock.item, PlayerCargo:describeLoad()),
            { 0.5, 1.0, 0.7 })
    end
end

--- The mining laser on a mount (the given one, or the first), or nil.
---@param mountId string|nil
---@return FittingDefinition|nil def, string|nil mountId
function LimitTheoryRedux:miningMount(mountId)
    local loadout = self.playerShip and self.playerShip:isValid()
        and self.playerShip:get(ConstructComponents.Loadout)
    if not loadout then return nil end
    local ids = {}
    for id in pairs(loadout.weapons or {}) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        if not mountId or id == mountId then
            local def = loadout:getWeapon(id)
            if def and def.tool and def.tool.kind == "mining" then return def, id end
        end
    end
    return nil
end

--- How long a mining cycle takes with this laser and this fit.
---@param def FittingDefinition
---@return number seconds
function LimitTheoryRedux:miningCycle(def)
    return def.tool.cycle / math.max(0.1, self:fitStat("miningRate", 1))
end

--- Whether a rock is within the laser's reach of the ship.
---@param info table
---@return boolean
function LimitTheoryRedux:rockInReach(info)
    local rbCmp = self.playerShip and self.playerShip:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if not body or not info.pos then return false end
    local reach = self:rockRadius(info) + Config.game.mining.playerRange * self:fitStat("scanRange", 1)
    return body:getPos():distance(info.pos) <= reach * 1.05
end

--- How far a rock's surface reaches from its centre: the reach is measured
--- from there, so a big rock is mined from as far off its face as a small one.
---@param info table
---@return number
function LimitTheoryRedux:rockRadius(info)
    return (info.scale or 0) * (Config.game.mining.rockRadiusScale or 1.4)
end

--- The rock an asteroid entity is, as mineableRock describes it (nil if it
--- is not one of the spawned rocks).
---@param entity Entity
---@return table|nil
function LimitTheoryRedux:rockInfoFor(entity)
    if not entity or not self.npcs or not self.npcs.mining then return nil end
    for _, info in ipairs(AsteroidFieldSystem:getSpawnedEntities()) do
        if info.entity and info.entity.id == entity.id and info.field and info.asteroid then
            local rock = self.npcs.mining:trackAsteroid(info.field, info.asteroid,
                { x = info.pos.x, y = info.pos.y, z = info.pos.z })
            return { entity = info.entity, field = info.field, asteroid = info.asteroid,
                     pos = info.pos, scale = info.scale, rock = rock }
        end
    end
    return nil
end

--- Target a rock for the mining laser (the overview's Target on an asteroid).
---@param entity Entity
---@param name string|nil
function LimitTheoryRedux:targetRock(entity, name)
    local info = self:rockInfoFor(entity)
    if not info then return end
    if not self:addTarget({ entity = entity, kind = "rock", rock = info,
        name = self:knowsRock(info) and info.rock.item or (name or "Rock") }) then return end
    self.rockTarget = info
    self:notify(string.format("Rock targeted: %s%s", self:knowsRock(info) and info.rock.item or (name or "an unsurveyed rock"),
        self:rockInReach(info) and "" or "  ·  out of the laser's reach"), { 0.8, 0.68, 0.52 })
end

--- The mining laser, on or off (its action bar slot). It mines the targeted
--- rock, or the nearest in reach (which it then targets).
---@param mountId string
function LimitTheoryRedux:toggleMining(mountId)
    if self.miningJob then
        self:stopMining("Mining stopped.")
        return
    end
    if self.docked then
        self:notify("Undock first.", { 1.0, 0.7, 0.3 })
        return
    end
    local def, laserMount = self:miningMount(mountId)
    if not def then return end
    mountId = laserMount
    local info = self.rockTarget
    if info and (not info.entity:isValid() or info.rock.yield < 1) then
        self:releaseTarget(info.entity, true)
        info = nil
    end
    -- The rock targeted for mining, if there is one (targets are only ever
    -- the player's choice); else the nearest in reach, untargeted
    if info and not self:rockInReach(info) then
        self:notify("The targeted rock is out of the laser's reach: approach it, or clear it from the targets to mine the nearest.",
            { 1.0, 0.7, 0.3 })
        return
    end
    info = info or self:mineableRock()
    if not info then
        self:notify("No rock in the mining laser's reach.", { 1.0, 0.7, 0.3 })
        return
    end
    if PlayerCargo:get():getRoomFor(info.rock.itemId) < 1 then
        self:notify("The hold is full.", { 1.0, 0.4, 0.3 })
        return
    end
    self.miningJob = { mountId = mountId, rock = info, progress = 0 }
    MiningBeam:start(self.playerShip, info.entity, function()
        return self:mountPosition(mountId)
    end)
    self:notify(string.format("Mining %s: a cycle every %.1fs",
        self:knowsRock(info) and info.rock.item or "an unsurveyed rock", self:miningCycle(def)),
        { 0.5, 1.0, 0.7 })
end

--- Where a mount on the player's ship is in the world now, or nil.
---@param mountId string|nil
---@return Position|nil
function LimitTheoryRedux:mountPosition(mountId)
    local mount = mountId and self.playerMounts and self.playerMounts[mountId]
    local rbCmp = self.playerShip and self.playerShip:isValid()
        and self.playerShip:get(PhysicsComponents.RigidBody)
    if not mount or not rbCmp or not rbCmp:getRigidBody() then return nil end
    local localPos = mount.bodyLocalPosition or mount.localPosition
    if not localPos then return nil end
    return rbCmp:toWorldScaled(localPos)
end

--- Stop the mining laser, with a word why (nil: say nothing).
---@param why string|nil
---@param color table|nil
function LimitTheoryRedux:stopMining(why, color)
    self.miningJob = nil
    MiningBeam:stop()
    if why then self:notify(why, color or { 0.75, 0.8, 0.85 }) end
end

------------------------------------------------------------------------------
-- The action bar (Modules/Constructs/Managers/ActionBar.lua)
------------------------------------------------------------------------------

--- What the ship can do on command, in bar order: tools on mounts, then
--- active modules by slot.
---@return string[] refs
function LimitTheoryRedux:actionRefs()
    local refs = {}
    local loadout = self.playerShip and self.playerShip:isValid()
        and self.playerShip:get(ConstructComponents.Loadout)
    if not loadout then return refs end
    local mounts = {}
    for id in pairs(loadout.weapons or {}) do mounts[#mounts + 1] = id end
    table.sort(mounts)
    for _, id in ipairs(mounts) do
        local def = loadout:getWeapon(id)
        if def and def.tool then refs[#refs + 1] = ActionBar.mountRef(id) end
    end
    for slot = 1, loadout:getModuleSlots() do
        local def = loadout:getModule(slot)
        if def and def:isActive() then refs[#refs + 1] = ActionBar.moduleRef(slot) end
    end
    return refs
end

--- Keep the flown ship's bar in step with its fit (cheap: called each frame).
function LimitTheoryRedux:syncActionBar()
    local ship = PlayerFleet:active()
    if ship then ActionBar.sync(ship, self:actionRefs()) end
end

--- What is in a bar slot and what it is doing, for the HUD:
--- { ref, name, kind ("module"|"tool"), ready, active, progress (0..1),
---   remaining (s) } or nil for an empty slot.
---@param index integer
---@return table|nil
function LimitTheoryRedux:actionSlot(index)
    local ship = PlayerFleet:active()
    local ref = ship and ActionBar.of(ship)[index]
    if not ref then return nil end
    local loadout = self.playerShip and self.playerShip:isValid()
        and self.playerShip:get(ConstructComponents.Loadout)
    if not loadout then return nil end
    local kind, where = ActionBar.parse(ref)
    if kind == "mount" then
        local def = loadout:getWeapon(where)
        if not def then return nil end
        local job = self.miningJob
        local running = job ~= nil and job.mountId == where
        return {
            ref = ref, name = def.displayName, kind = "tool", ready = true, active = running,
            progress = running and math.min(1, job.progress / self:miningCycle(def)) or 0,
            remaining = running and math.max(0, self:miningCycle(def) - job.progress) or 0,
        }
    elseif kind == "module" then
        local def = loadout:getModule(where)
        if not def then return nil end
        for _, row in ipairs(AbilitySystem:status(self.playerShip)) do
            if row.slot == where then
                local cooling = not row.ready and row.cooldown > 0
                return {
                    ref = ref, name = def.displayName, kind = "module", ready = row.ready,
                    active = row.active > 0,
                    progress = cooling and (1 - row.remaining / row.cooldown) or 0,
                    remaining = row.active > 0 and row.active or row.remaining,
                }
            end
        end
        return { ref = ref, name = def.displayName, kind = "module", ready = true, active = false,
                 progress = 0, remaining = 0 }
    end
    return nil
end

--- What to call a ship or station in the HUD: an NPC's label, a station's,
--- "you" for the player's ship.
---@param entity Entity|nil
---@return string
function LimitTheoryRedux:contactName(entity)
    if not entity then return "?" end
    if self.playerShip and entity.id == self.playerShip.id then return "you" end
    local record = self.npcs and self.npcs:recordOf(entity)
    if record and record.label then return record.label end
    local places = self.npcs and self.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        if dock.entity and dock.entity.id == entity.id then return dock.label or "station" end
    end
    for _, entry in ipairs(self.targets or {}) do
        if entry.entity and entry.entity.id == entity.id and entry.name then return entry.name end
    end
    return "target"
end

--- The weapons in the ship's mounts and what each is doing, for the HUD's
--- weapon bar: { mountId, name, size, state, firing, progress (reload,
--- 0..1), remaining (s), target (name) }, in mount order.
---
--- state is one of "firing", "reloading", "ready", "aiming", "no sight",
--- "out of range", "no target", "holding" (weapons off, the trigger free).
---@return table[]
function LimitTheoryRedux:weaponMounts()
    local battery = self.playerBattery
    if not battery or not battery.mountIds then return {} end
    local loadout = self.playerShip and self.playerShip:isValid()
        and self.playerShip:get(ConstructComponents.Loadout)
    local beaming = {}
    for _, beam in ipairs(battery.beams or {}) do
        if beam.mountId then beaming[beam.mountId] = true end
    end
    local aiOn = battery.control and battery.control:isActive()
    local triggerHeld = battery.control and battery.control.triggerHeld
    local list = {}
    for _, mountId in ipairs(battery.mountIds) do
        local mount = battery.turretsById[mountId]
        local turret = mount and mount.component
        if turret then
            local def = loadout and loadout:getWeapon(mountId)
            local ok, weapon = pcall(WeaponSystem.resolveWeapon, WeaponSystem, turret)
            weapon = ok and weapon or nil
            local cooldownMax = weapon and weapon.cooldown or 0
            local cooldown = turret.cooldown or 0
            local targetEntity = battery:getMountTarget(mountId)
            local firing = (turret.shotGlow or 0) > 0 or beaming[mountId] == true
            local state
            if firing then
                state = "firing"
            elseif cooldown > 0.05 then
                state = "reloading"
            elseif not targetEntity then
                state = "no target"
            elseif not aiOn and not triggerHeld then
                state = "holding"
            elseif turret.inRange == false then
                state = "out of range"
            elseif turret.hasLineOfSight == false then
                state = "no sight"
            elseif turret.ready == false then
                state = "aiming"
            else
                state = "ready"
            end
            list[#list + 1] = {
                mountId = mountId,
                name = def and def.name or (weapon and weapon.name) or mountId,
                size = weapon and weapon.mountSizeClass,
                state = state,
                firing = firing,
                glow = turret.shotGlow or 0,
                progress = cooldownMax > 0 and math.max(0, math.min(1, 1 - cooldown / cooldownMax)) or 1,
                remaining = cooldown,
                target = targetEntity and self:contactName(targetEntity) or nil,
                hostile = targetEntity ~= nil,
            }
        end
    end
    return list
end

--- A hit for the battle text: the player's weapons' hits on others, others'
--- on the player, and kills either way. Hits from one weapon on one target
--- in quick succession (a beam's ticks, a burst) are added up into one line.
---@param event table CombatLog's
function LimitTheoryRedux:battleText(event)
    local ship = self.playerShip
    if not ship or not event.target then return end
    local outgoing = event.attacker and event.attacker.id == ship.id
    local incoming = event.target.id == ship.id
    if not outgoing and not incoming then return end
    self.battleLog = self.battleLog or {}
    local now = self.simTime or 0
    local weaponName = event.weapon
    if outgoing and event.mountId then
        local loadout = ship:get(ConstructComponents.Loadout)
        local def = loadout and loadout:getWeapon(event.mountId)
        weaponName = def and def.name or weaponName
    end
    local who = outgoing and self:contactName(event.target) or self:contactName(event.attacker)
    local key = string.format("%s|%s|%s", outgoing and "out" or "in",
        tostring(event.mountId or weaponName), who)
    local entry
    for i = #self.battleLog, 1, -1 do
        local e = self.battleLog[i]
        if e.key == key and now - e.updated < 0.6 and not e.killed then entry = e break end
    end
    if not entry then
        entry = { key = key, born = now, damage = 0, hull = 0, hits = 0,
                  outgoing = outgoing, weapon = weaponName or "weapon", who = who }
        table.insert(self.battleLog, entry)
        if #self.battleLog > 24 then table.remove(self.battleLog, 1) end
    end
    entry.updated = now
    entry.damage = entry.damage + (event.damage or 0)
    entry.hull = entry.hull + (event.hullDamage or 0)
    entry.hits = entry.hits + 1
    if event.killed then
        entry.killed = true
        table.insert(self.battleLog, {
            key = key .. "|kill", born = now, updated = now, kill = true, outgoing = outgoing,
            weapon = weaponName or "weapon", who = who, damage = 0, hull = 0, hits = 0,
        })
    end
end

--- Use what is in a bar slot (its number key, or a click on it).
---@param index integer
function LimitTheoryRedux:useAction(index)
    local ship = PlayerFleet:active()
    local ref = ship and ActionBar.of(ship)[index]
    if not ref then
        self:notify(string.format("Slot %d of the action bar is empty.", index), { 0.7, 0.7, 0.7 })
        return
    end
    local kind, where = ActionBar.parse(ref)
    if kind == "mount" then
        self:toggleMining(where)
    elseif kind == "module" then
        self:fireModule(where)
    end
end

--- Drag one bar slot onto another (the HUD's action bar).
---@param from integer
---@param to integer
function LimitTheoryRedux:moveAction(from, to)
    local ship = PlayerFleet:active()
    if ship then ActionBar.move(ship, from, to) end
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
    if not self.flow:to(Phase.Docked, dock.label) then return end
    -- The travel drive cannot stay engaged (nor the ship passing through
    -- things) inside a station
    require("Modules.Constructs.Systems.TravelDriveSystem"):reset(self.playerShip)
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

--- Take one of the player's other ships, parked at this station. The ship
--- being flown is left here with its fittings in it, and the one taken comes
--- with whatever is in its own mounts and slots: a fit belongs to a ship, so
--- nothing moves between them (`PlayerFleet`).
---@param ship PlayerShip
---@return boolean taken
function LimitTheoryRedux:flyShip(ship)
    if not ship then return false end
    if not self.docked then
        self:notify("Ships are changed at a station.", { 1.0, 0.7, 0.3 })
        return false
    end
    -- The button that calls this is drawn by the station screen, and the
    -- change destroys the ship the screen is reading: it happens on the next
    -- simulation step instead, with the screen between frames.
    self.pendingShipChange = { ship = ship }
    return true
end

--- Make a ship of a hull in this station's hangar and fly it. The hull item
--- is spent, the new ship has nothing in it, and the ship being flown stays
--- here with its fit.
---@param hull HullDefinition
---@return boolean commissioned
function LimitTheoryRedux:commissionHull(hull)
    if not hull then return false end
    if not self.docked then
        self:notify("A hull is fitted out at a station.", { 1.0, 0.7, 0.3 })
        return false
    end
    self.pendingShipChange = { hull = hull }
    return true
end

------------------------------------------------------------------------------
-- The debug menu (~, UI/HmGui/Views/Gameplay/DebugMenu.lua): for testing
------------------------------------------------------------------------------

function LimitTheoryRedux:toggleDebugMenu()
    self.debugMenuOpen = not self.debugMenuOpen
end

---@param n number
function LimitTheoryRedux:debugGiveCredits(n)
    PlayerWallet:add(n, "Debug")
    self:notify(string.format("Debug: +%s", PlayerWallet.format(n)), { 1.0, 0.6, 0.25 })
end

--- Units of an item into the hold (the hangar when docked), room or not.
---@param def ItemDefinition
---@param n integer
function LimitTheoryRedux:debugGiveItem(def, n)
    local store = self.docked and self.docked.key and PlayerFactories:hangar(self.docked.key) or PlayerCargo:get()
    store:restore(def.id, n)
    self:notify(string.format("Debug: +%d %s (%s)", n, def.displayName, self.docked and "hangar" or "hold"),
        { 1.0, 0.6, 0.25 })
end

--- A new, empty ship of a hull, flown where the ship is now (docked or not).
---@param hull HullDefinition
function LimitTheoryRedux:debugFlyHull(hull)
    self.pendingShipChange = { debugHull = hull }
end

--- The best weapon that fits in every mount of the ship (tools stay), then
--- the ship rebuilt so every mount is in its battery.
function LimitTheoryRedux:debugArmShip()
    local ship = PlayerFleet:active()
    if not ship or not self.playerShip then return end
    PlayerFleet:record(self.playerShip)
    local order = { sm = 1, m = 2, l = 3, xl = 4 }
    local weapons = {}
    for _, def in ipairs(Fittings:getAll()) do
        if def:isWeapon() and not def:isTool() then weapons[#weapons + 1] = def end
    end
    local armed = 0
    for _, mount in ipairs(ShipFittingSystem:mounts(self.playerShip)) do
        local current = ship.weapons[mount.mountId] and Fittings:get(ship.weapons[mount.mountId])
        if not (current and current:isTool()) then
            local best = nil
            for _, def in ipairs(weapons) do
                if ShipFittingSystem:weaponFits(def, mount.sizeClass) and (not best
                        or (order[def.sizeClass] or 0) > (order[best.sizeClass] or 0)) then
                    best = def
                end
            end
            if best then
                ship.weapons[mount.mountId] = best.id
                armed = armed + 1
            end
        end
    end
    self.pendingShipChange = { debugRebuild = true }
    self:notify(string.format("Debug: %d mount(s) armed", armed), { 1.0, 0.6, 0.25 })
end

function LimitTheoryRedux:debugRepair()
    if not self.playerShip then return end
    local health = self.playerShip:get(CoreComponentsAll.Health)
    if health then health:setCurrentHealth(health:getMaxHealth()) end
    local defense = self.playerShip:get(ConstructComponents.Defense)
    if defense then defense:setCurrentShield(defense:getMaxShield()) end
end

--- An NPC of a role beside the ship.
---@param role string
function LimitTheoryRedux:debugSpawn(role)
    local here = self:shipPosition()
    if not (here and self.npcs) then return end
    self.npcs:spawnWithEscorts(role, self.npcs:near(here, 3))
    self:notify("Debug: spawned a " .. role, { 1.0, 0.6, 0.25 })
end

--- Straight to a system: no gate, no drive, no fuel.
---@param systemId integer
function LimitTheoryRedux:debugJump(systemId)
    if systemId == self.currentSystemId or not self.galaxy then return end
    if self.docked then
        self:notify("Debug: undock first.", { 1.0, 0.6, 0.25 })
        return
    end
    self.debugMenuOpen = false
    self:startJump({ destination = self.galaxy.systems[systemId] }, true)
end

--- Carry out a queued change of ship (`flyShip`, `commissionHull`), between
--- frames.
function LimitTheoryRedux:processShipChange()
    local pending = self.pendingShipChange
    if not pending then return end
    self.pendingShipChange = nil
    -- The debug menu's: a new ship of a hull, or the same one rebuilt, where
    -- it is, docked or not
    if pending.debugHull or pending.debugRebuild then
        local rb = self.playerShip and self.playerShip:get(PhysicsComponents.RigidBody)
        rb = rb and rb:getRigidBody()
        if not rb then return end
        local p, facing = rb:getPos(), rb:getRot():getForward()
        if pending.debugHull then
            PlayerFleet:record(self.playerShip)
            local ship = PlayerFleet:commission(pending.debugHull, nil)
            if ship then PlayerFleet:setActive(ship, nil) end
        end
        local dock = self.docked
        self:respawnPlayerShip(Position(p.x, p.y, p.z), facing)
        if dock then self:dockPlayer(dock) end
        if pending.debugHull then
            self:notify("Debug: now flying a " .. pending.debugHull.displayName, { 1.0, 0.6, 0.25 })
        end
        return
    end
    local dock = self.docked
    if not dock then
        self:notify("Ships are changed at a station.", { 1.0, 0.7, 0.3 })
        return false
    end
    local hangar = dock.key and PlayerFactories:hangar(dock.key)
    -- What is on the ship now is what it keeps, whoever fitted it
    PlayerFleet:record(self.playerShip)
    local previous = PlayerFleet:active()

    local ship = pending.ship
    if pending.hull then
        -- A hull out of the hangar becomes a ship of the player's
        if not hangar or hangar:count(pending.hull.itemId) < 1 then
            self:notify("That hull is not in this hangar.", { 1.0, 0.4, 0.3 })
            return false
        end
        if hangar:remove(pending.hull.itemId, 1) < 1 then
            self:notify("That hull is not in this hangar.", { 1.0, 0.4, 0.3 })
            return false
        end
        ship = PlayerFleet:commission(pending.hull, dock.key)
        if not ship then
            hangar:add(pending.hull.itemId, 1)
            self:notify("That hull cannot be made into a ship.", { 1.0, 0.4, 0.3 })
            return false
        end
    end

    local ok, reason = PlayerFleet:setActive(ship, dock.key)
    if not ok then
        self:notify("Cannot take that ship: " .. (reason or "no"), { 1.0, 0.4, 0.3 })
        return false
    end

    -- Rebuild the ship where it is docked, in the new frame
    local body = self.playerShip and self.playerShip:get(PhysicsComponents.RigidBody)
    local rb = body and body:getRigidBody()
    local position = rb and rb:getPos() or Position(dock.position.x, dock.position.y, dock.position.z)
    self:respawnPlayerShip(Position(position.x, position.y, position.z), nil)
    -- Docked again: the new ship is inside the station, as the old one was
    self:dockPlayer(dock)
    self:notify(string.format("Now flying %s (%s stays here%s)", ship.name,
        previous and previous.name or "nothing",
        previous and PlayerFleet.fittingCount(previous) > 0 and ", fitted as it is" or ""),
        { 0.6, 0.9, 1.0 })
    return true
end

--- Take everything out of one of the player's ships and leave it in this
--- station's hangar.
---@param ship PlayerShip
---@return boolean stripped
function LimitTheoryRedux:stripShip(ship)
    local dock = self.docked
    if not ship then return false end
    if not dock then
        self:notify("A ship is stripped at a station.", { 1.0, 0.7, 0.3 })
        return false
    end
    local hangar = dock.key and PlayerFactories:hangar(dock.key)
    if ship.id == (PlayerFleet.activeId or -1) then PlayerFleet:record(self.playerShip) end
    local taken, reason = PlayerFleet:strip(ship, hangar, self.playerShip)
    if taken < 1 then
        self:notify("Nothing came off: " .. (reason or "no"), { 1.0, 0.7, 0.3 })
        return false
    end
    if ship.id == (PlayerFleet.activeId or -1) then self:applyFitToShip() end
    self:notify(string.format("%s stripped: %d fitting(s) in the hangar.", ship.name, taken),
        { 0.6, 0.9, 1.0 })
    return true
end

--- Give a ship's bare hull back as an item to sell. Only an empty ship, and
--- not the one being flown.
---@param ship PlayerShip
---@return boolean done
function LimitTheoryRedux:decommissionShip(ship)
    local dock = self.docked
    if not ship or not dock then return false end
    local hangar = dock.key and PlayerFactories:hangar(dock.key)
    local ok, reason = PlayerFleet:decommission(ship, hangar)
    if not ok then
        self:notify("Cannot break that ship up: " .. (reason or "no"), { 1.0, 0.4, 0.3 })
        return false
    end
    self:notify(string.format("%s broken up: the hull is in the hangar.", ship.name),
        { 0.6, 0.9, 1.0 })
    return true
end

--- The autopilot's colour in the messages the overview's actions leave.
local AUTOPILOT_MESSAGE_COLOR = { 0.51, 0.92, 1.0 }

------------------------------------------------------------------------------
-- The overview: what is in the system, and what to do about it
-- (Modules/Navigation/Systems/SystemOverview.lua lists it,
-- UI/HmGui/Views/Gameplay/OverviewPanel.lua draws it)
------------------------------------------------------------------------------

--- Whether the overview can be up at all: in flight, with no map, no pause
--- menu and no jump under way. Docked, the station screen has the cursor.
---@return boolean
function LimitTheoryRedux:overviewAvailable()
    return self.playerShip ~= nil and self.playerShip:isValid()
        and not self.docked and (self.mapMode or 0) == 0
        and not self.pauseMenuOpen and not self.jump
end

--- Whether the overview is on the screen now.
---@return boolean
function LimitTheoryRedux:overviewShowing()
    return self.overviewShown == true and self:overviewAvailable()
end

--- The in-flight windows (WindowsPanel): which are open.
---@param id string "inventory", "character" or "standings"
function LimitTheoryRedux:toggleWindow(id)
    self.windows = self.windows or {}
    self.windows[id] = not self.windows[id]
end

--- Whether any window is on the screen now (in flight, no map or menu).
---@return boolean
function LimitTheoryRedux:windowsShowing()
    if not (self.windows and self:overviewAvailable()) then return false end
    for _, open in pairs(self.windows) do
        if open then return true end
    end
    return false
end

--- Escape in flight: put away what is open on the screen, one layer a
--- press -- a question (answered no), the overview's context menu, then
--- every window and the expanded overview together. Returns whether there
--- was anything; with nothing open, Escape brings up the game menu instead.
---@return boolean
function LimitTheoryRedux:dismissOpenUI()
    if self.debugMenuOpen then
        self.debugMenuOpen = false
        return true
    end
    if self:confirmationShowing() then
        self:answerConfirmation(false)
        return true
    end
    if require("UI.HmGui.Views.Gameplay.OverviewPanel").closeMenu() then
        return true
    end
    if require("UI.HmGui.Views.Gameplay.TargetsPanel").closeMenu() then
        return true
    end
    local closed = false
    if self:windowsShowing() then
        for id, open in pairs(self.windows) do
            if open then self.windows[id] = false end
        end
        closed = true
    end
    if self:overviewShowing() then
        self:setOverview(false)
        closed = true
    end
    return closed
end

--- Open or close the overview.
---@param shown boolean
function LimitTheoryRedux:setOverview(shown)
    self.overviewShown = shown and true or false
    if self.overviewShown then SystemOverview:update(self, 0, true) end
end

--- Each frame: the cursor and the mouse go to the overview while it shows
--- and back to the camera when it goes, the list stays current, and the
--- things the overview started (a look, a dock or a jump on arrival) are
--- seen through.
---@param dt number
function LimitTheoryRedux:updateOverview(dt)
    -- The cursor is the UI's while the overview or a question is on screen
    local overview = self:overviewShowing()
    local showing = overview or self:confirmationShowing() or self:windowsShowing()
        or (self.debugMenuOpen and not self.docked)
    if showing ~= (self.overviewHoldsCursor == true) then
        self.overviewHoldsCursor = showing
        if self.player then self.player:setMouseSteering(not showing) end
        -- Closed in flight: the camera's own cursor comes back. (Closed by
        -- docking or a map: whatever opened takes the cursor itself.)
        if not showing and self.player and not self.docked and (self.mapMode or 0) == 0 then
            self.player:setMode(self.player:getMode())
        end
    end
    if showing then
        -- Freed every frame, since a camera switch re-grabs it
        CursorManager:free()
    end
    -- The list is kept current whenever it is on screen, brief or expanded
    if self:overviewAvailable() then SystemOverview:update(self, dt) end

    -- A look at something ends when it goes, or when the camera leaves it.
    -- Docking and jumping take the camera themselves: the look is just
    -- forgotten, and the camera left to them.
    if self.lookingAt then
        if self.docked or self.jump then
            self.lookingAt, self.lookReturnMode = nil, nil
        elseif not self.lookingAt:isValid()
                or (self.player and self.player:getMode() ~= Enums.CameraMode.Orbit) then
            self:lookAtShip()
        end
    end
    self:processArrivalAction()
    self:updateTargeting()
end

--- The radius to frame an entity by.
---@param entity Entity
---@return number
local function radiusOf(entity)
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if body then return body:getBoundingRadius() end
    local transform = entity:get(PhysicsComponents.Transform)
    return transform and transform:getScale() or 1
end

--- Point the orbit camera at something: it circles that, framed by its size,
--- until the player stops looking (the overview's menu) or switches camera.
--- The orbit camera is not a piloting one, so the ship flies on its
--- autopilot or not at all while the player looks.
---@param entity Entity
---@param name string|nil for the message
function LimitTheoryRedux:lookAt(entity, name)
    if not entity or not entity:isValid() or not self.player then return end
    if SystemOverview.same(entity, self.playerShip) then
        self:lookAtShip(true)
        return
    end
    -- The camera to go back to: the one the player was in before the first
    -- look, not a look before this one
    if not self.lookingAt then self.lookReturnMode = self.player:getMode() end
    self.lookingAt = entity
    self:setOrbitFocus(entity, self:orbitDistances(math.max(radiusOf(entity), 1e-3)))
    if name then
        self:notify(string.format("Looking at %s  ·  Stop looking from the overview", name),
            { 0.6, 0.9, 1.0 })
    end
end

--- The orbit camera back on the player's own ship.
---@param returnToCamera boolean|nil also go back to the camera the player
---  was in before looking (Stop looking); nil when the player has already
---  switched camera themselves
function LimitTheoryRedux:lookAtShip(returnToCamera)
    local mode = self.lookReturnMode
    self.lookingAt, self.lookReturnMode = nil, nil
    if not self.player then return end
    self.player:setOrbitTarget(nil)
    if returnToCamera and mode and mode ~= self.player:getMode() then
        self.player:setMode(mode)
    end
end

--- Fly to something on the autopilot. It stops short of it by its size.
---@param entity Entity
---@param name string|nil for the message
---@param arrivalRange number|nil stop this close (default: by the target's size)
---@return boolean engaged
function LimitTheoryRedux:approach(entity, name, arrivalRange)
    if not entity or not entity:isValid() or not self.playerShip then return false end
    if self.docked then
        self:notify("Undock first.", { 1.0, 0.7, 0.3 })
        return false
    end
    self.arrivalAction = nil
    -- A course between systems is left alone: if this is the course's gate
    -- the jump keeps it, and any other gate drops it (startJump)
    AutoPilotSystem:engageEntity(self.playerShip, entity, arrivalRange)
    if name then self:notify("Autopilot: approaching " .. name, AUTOPILOT_MESSAGE_COLOR) end
    return true
end

--- Dock at a station: now, if it is in range; otherwise fly there and dock
--- on arrival.
---@param dock table the station's dock record (npcs.places.docks)
function LimitTheoryRedux:dockAt(dock)
    if not dock or not dock.entity:isValid() then return end
    local inRange, refused = self:dockInRange()
    if inRange and SystemOverview.same(inRange.entity, dock.entity) then
        self:dockPlayer(dock)
        self:autosave()
        return
    end
    if refused and SystemOverview.same(refused.entity, dock.entity) then
        self:notify(Factions.name(refused.faction) .. " refuse you docking.", { 1.0, 0.4, 0.3 })
        return
    end
    -- Stop well inside docking range, so the dock happens on arrival
    if self:approach(dock.entity, nil, dock.radius * Config.game.docking.rangeFactor * 0.7) then
        self.arrivalAction = { kind = "dock", entity = dock.entity }
        self:notify(string.format("Autopilot: docking at %s", dock.label), AUTOPILOT_MESSAGE_COLOR)
    end
end

--- Jump through a gate: now, if it is in range; otherwise fly there and
--- jump on arrival.
---@param gate JumpGatePlacement
function LimitTheoryRedux:jumpVia(gate)
    if not gate or not gate.entity:isValid() then return end
    local near = self:gateInRange()
    if near and SystemOverview.same(near.entity, gate.entity) then
        self:startJump(near)
        return
    end
    -- Into the gate's activation range, where the jump happens
    if self:approach(gate.entity, nil, Config.game.jumpGates.activationRange * 0.5) then
        self.arrivalAction = { kind = "jump", entity = gate.entity }
        self:notify(string.format("Autopilot: jumping to %s", gate.destination.name),
            AUTOPILOT_MESSAGE_COLOR)
    end
end

--- What the overview asked to happen on arrival: dock or jump the moment
--- the ship is in range, and let it go if the autopilot stops short (it
--- arrived somewhere else, or the player took the controls).
function LimitTheoryRedux:processArrivalAction()
    local action = self.arrivalAction
    if not action then return end
    if self.docked or self.jump or not action.entity:isValid() or not self.playerShip then
        self.arrivalAction = nil
        return
    end
    if action.kind == "dock" then
        local dock, refused = self:dockInRange()
        if dock and SystemOverview.same(dock.entity, action.entity) then
            self.arrivalAction = nil
            AutoPilotSystem:disengage(self.playerShip)
            self:dockPlayer(dock)
            self:autosave()
            return
        end
        if refused and SystemOverview.same(refused.entity, action.entity) then
            self.arrivalAction = nil
            AutoPilotSystem:disengage(self.playerShip)
            self:notify(Factions.name(refused.faction) .. " refuse you docking.", { 1.0, 0.4, 0.3 })
            return
        end
    elseif action.kind == "deploy" then
        if self:shipDistanceTo(action.anchor.position) <= Config.game.outposts.deployRange then
            self.arrivalAction = nil
            AutoPilotSystem:disengage(self.playerShip)
            self:finishDeploy(action.kind_, action.anchor)
            return
        end
    elseif action.kind == "jump" then
        local gate = self:gateInRange()
        if gate and SystemOverview.same(gate.entity, action.entity) then
            self.arrivalAction = nil
            self:startJump(gate)
            return
        end
    end
    if not AutoPilotSystem:isActive(self.playerShip) then
        self.arrivalAction = nil
        local stopped = {
            dock = "Stopped short of the station: not docking.",
            jump = "Stopped short of the gate: not jumping.",
            deploy = "Stopped short of the slot: not deploying.",
        }
        self:notify(stopped[action.kind] or "Autopilot stopped.", { 1.0, 0.7, 0.3 })
    end
end

------------------------------------------------------------------------------
-- Deploying an outpost (PlayerStations): a kit, a free slot on a planet's
-- station ring or along a belt, and the ship there
------------------------------------------------------------------------------

--- How far the player's ship is from a position (math.huge without a ship).
---@param p table { x, y, z }
---@return number
function LimitTheoryRedux:shipDistanceTo(p)
    local rbCmp = self.playerShip and self.playerShip:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if not body then return math.huge end
    local pos = body:getPos()
    local dx, dy, dz = pos.x - p.x, pos.y - p.y, pos.z - p.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Where a kind's kit is to be had in this system: the hold first, then
--- the player's hangars at the stations here.
---@param kind string
---@return table|nil source { kind ("hold"|"hangar"), stock (StockComponent), key, label }
function LimitTheoryRedux:kitSource(kind)
    local def = PlayerStations.kitOf(kind)
    if not def then return nil end
    if PlayerCargo:count(def.id) > 0 then
        return { kind = "hold", stock = PlayerCargo:get(), label = "your hold" }
    end
    local places = self.npcs and self.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        local record = dock.key and PlayerFactories.stations[dock.key]
        if record and record.hangar:count(def.id) > 0 then
            return { kind = "hangar", stock = record.hangar, key = dock.key,
                     label = "your hangar at " .. dock.label }
        end
    end
    return nil
end

--- The outpost kinds the player could deploy here and now, in
--- Config.game.outposts.order: { kind, name, source }.
---@return table[]
function LimitTheoryRedux:deployableKinds()
    local list = {}
    if not self:isTravelGame() then return list end
    for _, kind in ipairs(Config.game.outposts.order) do
        local cfg = PlayerStations.kindOf(kind)
        local source = cfg and self:kitSource(kind)
        if source then list[#list + 1] = { kind = kind, name = cfg.name, source = source } end
    end
    return list
end

--- Deploy an outpost of `kind` at the nearest free slot of a planet or a
--- belt: now, if the ship is at it; otherwise fly there and deploy on
--- arrival (processArrivalAction).
---@param kind string
---@param parent Entity a planet or an asteroid belt
---@param parentName string|nil
function LimitTheoryRedux:deployOutpost(kind, parent, parentName)
    local cfg = PlayerStations.kindOf(kind)
    if not cfg or not parent or not parent:isValid() or not self.playerShip then return end
    if self.docked then
        self:notify("Undock first.", { 1.0, 0.7, 0.3 })
        return
    end
    if not self:kitSource(kind) then
        self:notify(string.format("No %s here: carry one in your hold, or keep one in a hangar in this system.",
            PlayerStations.kitOf(kind).name), { 1.0, 0.7, 0.3 })
        return
    end
    local rbCmp = self.playerShip:get(PhysicsComponents.RigidBody)
    local from = rbCmp:getRigidBody():getPos()
    local anchor = PlayerStations:nearestFreeAnchor(self, parent, from)
    if not anchor then
        self:notify(string.format("No free slot at %s.", parentName or "that"), { 1.0, 0.7, 0.3 })
        return
    end
    if self:shipDistanceTo(anchor.position) <= Config.game.outposts.deployRange then
        self:finishDeploy(kind, anchor)
        return
    end
    self.arrivalAction = nil
    local p = anchor.position
    AutoPilotSystem:engagePosition(self.playerShip, Position(p.x, p.y, p.z),
        Config.game.outposts.deployRange * 0.5)
    self.arrivalAction = { kind = "deploy", kind_ = kind, anchor = anchor, entity = parent }
    self:notify(string.format("Autopilot: deploying a %s at %s", cfg.name, parentName or "the slot"),
        AUTOPILOT_MESSAGE_COLOR)
end

--- The ship is at the slot: spend the kit, record the outpost and build it.
---@param kind string
---@param anchor table
function LimitTheoryRedux:finishDeploy(kind, anchor)
    local source = self:kitSource(kind)
    local def = PlayerStations.kitOf(kind)
    if not source or not def then
        self:notify("The kit is gone: not deploying.", { 1.0, 0.7, 0.3 })
        return
    end
    -- Someone may have taken the slot meanwhile (another outpost)
    for _, other in ipairs(PlayerStations:anchors(self)) do
        if other.id == anchor.id and not other.free then
            self:notify("That slot is taken now: not deploying.", { 1.0, 0.7, 0.3 })
            return
        end
    end
    if source.stock:remove(def.id, 1) < 1 then return end
    local system = self.galaxy and self.galaxy.systems[self.currentSystemId]
    local record = PlayerStations:deploy(kind, self.currentSystemId or 1, anchor, system and system.name)
    if not record then
        source.stock:add(def.id, 1)
        return
    end
    local station = self:buildPlayerStation(record)
    local entry = self.playerStationEntities[#self.playerStationEntities]
    local places = self.npcs and self.npcs.places
    if places then
        local dock = self:openPlayerStation(entry, places.docks)
        if dock then table.insert(places.stations, dock.position) end
    end
    SystemOverview:invalidate()
    if self.mapState then
        self.mapState._entityListBuilt = false
        self.mapState._dotCache = nil
    end
    self:notify(string.format("%s deployed (the kit from %s). Dock to set up its lines and market.",
        record.name, source.label), { 0.3, 1.0, 0.45 })
    Log.Info("Outpost: %s (%s) at %s in system %d", record.name, kind, anchor.id, record.systemId)
    self:autosave()
    return station
end

------------------------------------------------------------------------------
-- Targeting: the ship the player has locked, and whether to attack it
------------------------------------------------------------------------------

--- Lock a ship. The player's turrets put every mount that can reach it on
--- it, instead of spreading over whatever is near -- if it is a ship they
--- would engage anyway (one whose faction is hostile). A ship that is not
--- hostile is only marked and followed on the HUD: shooting it is Attack.
---@param entity Entity
---@param name string|nil
---@param faction string|nil the ship's faction (Attack's warning needs it)
function LimitTheoryRedux:lockTarget(entity, name, faction)
    if not entity or not entity:isValid() then return end
    if SystemOverview.same(entity, self.playerShip) then return end
    if not self:addTarget({ entity = entity, kind = "ship", name = name or "target", faction = faction }) then
        return
    end
    self.target = entity
    self.targetName = name or "target"
    self.targetFaction = faction
    -- A new lock is not an attack on it, even if the last one was
    self.attacking = false
    self:notify(string.format("Target locked: %s", self.targetName), { 1.0, 0.85, 0.35 })
end

--- Lock a ship and open fire on it, hostile or not. Shooting a ship whose
--- faction is not hostile costs standing with that faction, hit by hit
--- (Reputation), and enough of it turns the whole faction against the
--- player -- which the player is asked to confirm before it can happen
--- (see `updateTargeting`).
---@param entity Entity
---@param name string|nil
---@param faction string|nil the ship's faction
function LimitTheoryRedux:attackTarget(entity, name, faction)
    if not entity or not entity:isValid() then return end
    self:lockTarget(entity, name, faction)
    if not SystemOverview.same(self.target, entity) then return end
    self.attacking = true
    local entry = self:findTarget(entity)
    if entry then entry.attack = true end
    local who = faction and Factions.name(faction) or "its faction"
    self:notify(string.format("Attacking %s: every hit costs standing with %s", self.targetName, who),
        { 1.0, 0.45, 0.35 })
end

--- Let go of the active ship target.
function LimitTheoryRedux:clearTarget()
    if self.target then
        self:releaseTarget(self.target)
    end
    self.target, self.targetName, self.targetFaction, self.attacking = nil, nil, nil, false
end

--- Whether an entity is among the targets.
---@param entity Entity|nil
---@return boolean
function LimitTheoryRedux:isTarget(entity)
    return self:findTarget(entity) ~= nil
end

------------------------------------------------------------------------------
-- The target list (TargetsPanel): what the player has targeted, ships and
-- rocks, only ever by their own choice (the overview's Target, Tab). One
-- ship is the active target -- the guns' focus, `self.target` -- and one
-- rock the mining laser's, `self.rockTarget`. A target goes when it is
-- cleared (its X, or Clear target), destroyed or mined out, and they all go
-- on docking or jumping.
------------------------------------------------------------------------------

---@return table[] { entity, kind = "ship"|"rock", name, faction, rock }
function LimitTheoryRedux:targetList()
    self.targets = self.targets or {}
    return self.targets
end

---@param entity Entity|nil
---@return table|nil entry, integer|nil index
function LimitTheoryRedux:findTarget(entity)
    if not entity then return nil end
    for i, t in ipairs(self:targetList()) do
        if SystemOverview.same(t.entity, entity) then return t, i end
    end
    return nil
end

--- Add a target (or refresh it). With the list full, the oldest that is not
--- active makes room. Returns the entry.
---@param entry table
---@return table|nil
function LimitTheoryRedux:addTarget(entry)
    if not entry.entity or not entry.entity:isValid() then return nil end
    local list = self:targetList()
    local existing = self:findTarget(entry.entity)
    if existing then
        for k, v in pairs(entry) do existing[k] = v end
        return existing
    end
    local max = self:maxTargets()
    if #list >= max then
        for i, t in ipairs(list) do
            if not self:isActiveTarget(t) then
                table.remove(list, i)
                break
            end
        end
        if #list >= max then
            self:notify("The target list is full.", { 1.0, 0.7, 0.3 })
            return nil
        end
    end
    list[#list + 1] = entry
    return entry
end

--- How many targets the ship can hold: more for a ship with more mounts
--- (Config.game.targeting) -- a bigger, better-armed hull tracks more, and
--- its guns spread over them.
---@return integer
function LimitTheoryRedux:maxTargets()
    local cfg = Config.game.targeting or {}
    local mounts = 0
    local loadout = self.playerShip and self.playerShip:isValid()
        and self.playerShip:get(ConstructComponents.Loadout)
    if loadout then
        for _ in pairs(loadout.weapons or {}) do mounts = mounts + 1 end
    end
    local n = (cfg.base or 1) + (cfg.perMount or 1) * mounts
    return math.max(cfg.min or 2, math.min(cfg.cap or 8, math.floor(n)))
end

--- Whether a target entry is the active ship target or the mining target.
---@param entry table
---@return boolean
function LimitTheoryRedux:isActiveTarget(entry)
    if entry.kind == "rock" then
        return self.rockTarget ~= nil and SystemOverview.same(self.rockTarget.entity, entry.entity)
    end
    return SystemOverview.same(self.target, entry.entity)
end

--- Make a target the active one of its kind.
---@param entry table
function LimitTheoryRedux:activateTarget(entry)
    if not entry or not entry.entity:isValid() then return end
    if entry.kind == "rock" then
        self.rockTarget = entry.rock or self:rockInfoFor(entry.entity)
    elseif not SystemOverview.same(self.target, entry.entity) then
        self.target, self.targetName, self.targetFaction = entry.entity, entry.name, entry.faction
        self.attacking = false
    end
end

--- Clear a target (its X). Clearing the rock being mined stops the laser;
--- clearing the active ship stops the attack on it.
---@param entity Entity
---@param quiet boolean|nil say nothing
function LimitTheoryRedux:releaseTarget(entity, quiet)
    local entry, index = self:findTarget(entity)
    if index then table.remove(self:targetList(), index) end
    if SystemOverview.same(self.target, entity) then
        self.target, self.targetName, self.targetFaction, self.attacking = nil, nil, nil, false
    end
    if self.rockTarget and SystemOverview.same(self.rockTarget.entity, entity) then
        self.rockTarget = nil
    end
    local job = self.miningJob
    if job and job.rock and SystemOverview.same(job.rock.entity, entity) then
        self:stopMining()
    end
    if entry and not quiet then
        self:notify(string.format("Target cleared: %s", entry.name or "target"), { 0.75, 0.8, 0.85 })
    end
end

--- Stop shooting at a target the player chose to attack (it stays a target).
---@param entry table
function LimitTheoryRedux:holdFire(entry)
    entry.attack = false
    if SystemOverview.same(self.target, entry.entity) then self.attacking = false end
    self:notify(string.format("Holding fire on %s.", entry.name or "the target"), { 0.75, 0.8, 0.85 })
end

--- Every target gone (docking, a jump, a new scene).
function LimitTheoryRedux:clearAllTargets()
    self.targets = {}
    self.rockTarget = nil
    self.target, self.targetName, self.targetFaction, self.attacking = nil, nil, nil, false
end

--- Each frame: targets that have gone (destroyed, mined out) leave the list.
function LimitTheoryRedux:pruneTargets()
    local list = self:targetList()
    if #list == 0 then return end
    if self.docked or self.jump then
        self:clearAllTargets()
        return
    end
    -- A smaller ship (a change of hull, a gun taken out) holds fewer
    local max = self:maxTargets()
    for i = #list, 1, -1 do
        if #list <= max then break end
        if not self:isActiveTarget(list[i]) then table.remove(list, i) end
    end
    for i = #list, 1, -1 do
        local t = list[i]
        local gone = not t.entity:isValid()
        local minedOut = not gone and t.kind == "rock" and t.rock and t.rock.rock and t.rock.rock.yield < 1
        if gone or minedOut then
            table.remove(list, i)
            if self.rockTarget and SystemOverview.same(self.rockTarget.entity, t.entity) then
                self.rockTarget = nil
            end
            if minedOut then
                self:notify(string.format("Target cleared: %s, mined out", t.name or "rock"), { 0.75, 0.8, 0.85 })
            end
        end
    end
end

--- Lock the nearest hostile ship (Tab). Pressed again with one locked, the
--- next nearest after it, round to the nearest again: a way through every
--- hostile in the system without the mouse.
function LimitTheoryRedux:targetNearestHostile()
    if not self.playerShip or not self.playerShip:isValid() or not self.npcs then return end
    local rbCmp = self.playerShip:get(PhysicsComponents.RigidBody)
    local here = rbCmp and rbCmp:getRigidBody() and rbCmp:getRigidBody():getPos()
    if not here then return end
    local hostiles = {}
    -- Only what the sensors have identified (a signature is not a target yet)
    for _, npc in ipairs(self:mapNpcs()) do
        if not npc.signature and npc.faction and npc.entity:isValid() and Factions.isHostile(npc.faction, Factions.Player) then
            local body = npc.entity:get(PhysicsComponents.RigidBody)
            local pos = body and body:getRigidBody() and body:getRigidBody():getPos()
            if pos then
                local dx, dy, dz = pos.x - here.x, pos.y - here.y, pos.z - here.z
                hostiles[#hostiles + 1] = { npc = npc, d = dx * dx + dy * dy + dz * dz }
            end
        end
    end
    if #hostiles == 0 then
        self:notify("No hostile ship within sensor range.", { 0.75, 0.8, 0.85 })
        return
    end
    table.sort(hostiles, function(a, b) return a.d < b.d end)
    local pick = 1
    for i, h in ipairs(hostiles) do
        if SystemOverview.same(self.target, h.npc.entity) then
            pick = i % #hostiles + 1
            break
        end
    end
    local npc = hostiles[pick].npc
    self:lockTarget(npc.entity, npc.label, npc.faction)
end

--- Whether attacking a ship of this faction could turn the faction hostile
--- soon: the next kill, and a few hits besides, would take the standing
--- past the hostile line. A kill is the big step (Config.game.reputation
--- .killPenalty against 0.01 a hit), so the question has to be asked before
--- the ship dies, not when the line is already crossed.
---@param faction string|nil
---@return boolean
function LimitTheoryRedux:attackRisksHostility(faction)
    if not faction or Reputation:isHostile(faction) then return false end
    local cfg = Config.game.reputation
    local margin = cfg.killPenalty + (cfg.hostilityWarningHits or 3) * cfg.damagePenalty
    return Reputation:get(faction) - margin < Config.game.dispoHostileThreshold
end

--- Ask before an attack turns a faction hostile. The turrets hold fire on
--- the target until the player answers: Keep attacking accepts that faction
--- turning (it is not asked about again this game), Hold fire stops the
--- attack and keeps the lock.
function LimitTheoryRedux:askHostilityConfirmation()
    local faction, name = self.targetFaction, self.targetName or "the target"
    local factionName = Factions.name(faction)
    -- The stations belong to one faction (Config.game.docking.owner): only
    -- turning that one closes them
    local docking = Config.game.docking and Config.game.docking.owner
    local consequence = faction == docking
        and "their ships will attack you on sight, and the stations will refuse you docking."
        or "their ships will attack you on sight."
    self.confirmation = {
        kind = "hostility",
        faction = faction,
        title = string.format("Turn %s hostile?", factionName),
        lines = {
            string.format("Keep attacking %s, and %s will turn hostile:", name, factionName),
            consequence,
            string.format("Standing now %+.2f; hostile below %+.2f.",
                Reputation:get(faction), Config.game.dispoHostileThreshold),
            "Your guns hold fire on it until you choose.",
        },
        confirm = "Keep attacking",
        cancel = "Hold fire",
        onConfirm = function()
            self.hostilityAccepted[faction] = true
            self:notify(string.format("Attacking %s: %s will turn hostile.", name, factionName),
                { 1.0, 0.45, 0.35 })
        end,
        onCancel = function()
            self.attacking = false
            self:notify(string.format("Holding fire on %s.", name), { 0.75, 0.8, 0.85 })
        end,
    }
end

--- The player answered the confirmation on screen.
---@param confirmed boolean
function LimitTheoryRedux:answerConfirmation(confirmed)
    local confirmation = self.confirmation
    if not confirmation then return end
    self.confirmation = nil
    local run = confirmed and confirmation.onConfirm or confirmation.onCancel
    if run then run() end
end

--- Whether a confirmation is on the screen now (in flight; it waits through
--- a map or the pause menu).
---@return boolean
function LimitTheoryRedux:confirmationShowing()
    return self.confirmation ~= nil and self.playerShip ~= nil
        and not self.docked and (self.mapMode or 0) == 0 and not self.pauseMenuOpen
end

--- Each frame: drop a target that has gone, and tell the turrets about the
--- one that has not. The battery is rebuilt with the ship (an undock, a
--- jump, a change of ship), so this is set every frame rather than once.
function LimitTheoryRedux:updateTargeting()
    self:pruneTargets()
    if self.target and (not self.target:isValid() or self.docked or self.jump) then
        local name = self.targetName
        local destroyed = not self.target:isValid()
        self.target, self.targetName, self.targetFaction, self.attacking = nil, nil, nil, false
        if destroyed and name then
            self:notify(string.format("Target lost: %s", name), { 0.75, 0.8, 0.85 })
        end
    end

    -- Before an attack can turn a faction hostile, hold fire and ask
    local firing = self.attacking and self.target ~= nil
    self.hostilityAccepted = self.hostilityAccepted or {}
    local faction = self.targetFaction
    if firing and faction and not self.hostilityAccepted[faction]
            and self:attackRisksHostility(faction) then
        firing = false
        if not self.confirmation then self:askHostilityConfirmation() end
    end
    -- A question about an attack that is no longer going on is withdrawn
    local asking = self.confirmation
    if asking and asking.kind == "hostility"
            and (not self.attacking or not self.target or asking.faction ~= faction) then
        self.confirmation = nil
    end

    local battery = self.playerBattery
    if battery then
        battery.focusTargetEntity = self.target
        battery.attackEntity = firing and self.target or nil
        -- The guns spread over every ship target they may shoot: hostile
        -- ones, and the others the player chose to attack (once any question
        -- of turning their faction hostile is answered). The active target
        -- comes first, so with more mounts than targets it gets the spare.
        local engaged, extra = {}, battery.attackEntities
        for i = #extra, 1, -1 do extra[i] = nil end
        if self.target and (firing or self:isHostileFaction(self.targetFaction)) then
            engaged[1] = self.target
        end
        for _, t in ipairs(self:targetList()) do
            if t.kind == "ship" and t.entity:isValid() and not SystemOverview.same(t.entity, self.target) then
                if self:isHostileFaction(t.faction) then
                    engaged[#engaged + 1] = t.entity
                elseif t.attack and t.faction and (self.hostilityAccepted[t.faction]
                        or not self:attackRisksHostility(t.faction)) then
                    engaged[#engaged + 1] = t.entity
                    extra[#extra + 1] = t.entity
                end
            end
        end
        local focus = battery.mountFocus
        for k in pairs(focus) do focus[k] = nil end
        if #engaged > 1 then
            for i, mountId in ipairs(battery.mountIds or {}) do
                focus[mountId] = engaged[(i - 1) % #engaged + 1]
            end
        end
    end
end

---@param faction string|nil
---@return boolean
function LimitTheoryRedux:isHostileFaction(faction)
    return faction ~= nil and Factions.isHostile(faction, Factions.Player) == true
end

--- What the HUD says about the target: its name, how far, and how much
--- shield and hull it has left.
---@return string|nil text
---@return table|nil color
function LimitTheoryRedux:targetReadout()
    local target = self.target
    if not target or not target:isValid() or not self.playerShip then return nil end
    local function place(entity)
        local rbCmp = entity:get(PhysicsComponents.RigidBody)
        local body = rbCmp and rbCmp:getRigidBody()
        return body and body:getPos(), body and body:getBoundingRadius() or 0
    end
    local here = place(self.playerShip)
    local there, radius = place(target)
    local parts = { (self.attacking and "ATTACKING  " or "TARGET  ") .. (self.targetName or "") }
    if here and there then
        local dx, dy, dz = there.x - here.x, there.y - here.y, there.z - here.z
        local d = math.max(0, math.sqrt(dx * dx + dy * dy + dz * dz) - radius)
        parts[#parts + 1] = UniverseScaleConfig:formatDistance(d)
    end
    local defense = target:get(ConstructComponents.Defense)
    if defense and defense:getMaxShield() > 0 then
        parts[#parts + 1] = string.format("shield %d%%",
            math.floor(100 * defense:getCurrentShield() / defense:getMaxShield() + 0.5))
    end
    local health = target:get(CoreComponents.Health)
    if health and health:getMaxHealth() > 0 then
        parts[#parts + 1] = string.format("hull %d%%",
            math.floor(100 * health:getCurrentHealth() / health:getMaxHealth() + 0.5))
    end
    return table.concat(parts, "  ·  "),
        self.attacking and { 1.0, 0.45, 0.35 } or { 1.0, 0.85, 0.35 }
end

------------------------------------------------------------------------------
-- The system map, from elsewhere
------------------------------------------------------------------------------

--- Open the 2D system map, its list of things rebuilt. (The M key's first
--- step, and Show on map.)
function LimitTheoryRedux:openSystemMap()
    SystemMap3D:deactivate(self.map3DState)
    self.mapMode = 1
    self.mapState.enabled = true
    self.map3DState.enabled = false
    self.galaxyMapState.enabled = false
    self.mapState._entityListBuilt = false
    self.mapState._dotCache = nil
    SystemMap:collectEntities(self.mapState, self.universe, self.playerShip, self:mapNpcs())
    CursorManager:free()
end

--- Open the system map with something selected: the map follows the
--- selection, so it is centred and its details are up, and the autopilot
--- key there flies to it as usual.
---@param entity Entity
---@param name string|nil
function LimitTheoryRedux:showOnMap(entity, name)
    if not entity or not entity:isValid() or not self.mapState then return end
    self:openSystemMap()
    -- The map's own entry for it when it has one (planets, stations, gates,
    -- ships); an asteroid streamed in around the ship is not in the map's
    -- list, so it gets an entry of its own to follow
    for _, entry in ipairs(self.mapState.entities or {}) do
        if SystemOverview.same(entry.entity, entity) then
            self.mapState.selected = entry
            return
        end
    end
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    local transform = entity:get(PhysicsComponents.Transform)
    local pos = body and body:getPos() or (transform and transform:getPos())
    if not pos then return end
    self.mapState.selected = {
        entity = entity,
        label = name or "Selected",
        pos = pos,
        scale = body and body:getBoundingRadius() or 0,
        color = { 0.8, 0.7, 0.5 },
        size = 3,
    }
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
    self.flow:to(Phase.InSystem, "undocked")
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
    local entries = self.npcs and self.npcs:mapEntries() or {}
    local here = self:shipPosition()
    if not here then return entries end
    local cfg = Config.game.sensors
    local scan = self:fitStat("scanRange", 1)
    local reach = self:fitStat("signatureRange", 1)
    local accuracy = math.max(0.1, self:fitStat("signatureAccuracy", 1))
    local bucket = math.floor((self.simTime or 0) / cfg.refresh)
    local out = {}
    for _, npc in ipairs(entries) do
        local record = npc.record
        local rbCmp = npc.entity:get(PhysicsComponents.RigidBody)
        local body = rbCmp and rbCmp:getRigidBody()
        local p = body and body:getPos()
        local d = p and math.sqrt((p.x - here.x) ^ 2 + (p.y - here.y) ^ 2 + (p.z - here.z) ^ 2) or 0
        local loud = record and self.npcs:loudness(record) or 0.5
        local contract = BountyBoard:contractOn(record)
        local identifyAt = cfg.range * scan * (0.6 + 0.8 * loud)
        local detectAt = cfg.detectRange * scan * reach * (0.25 + loud)
        local reveal = Config.game.debug and Config.game.debug.revealShips
        if reveal or npc.faction == Factions.Player or d <= identifyAt then
            if contract then
                -- Identified: named for the contract, in gold
                npc = {
                    entity = npc.entity, faction = npc.faction, role = npc.role, record = record,
                    sizeClass = npc.sizeClass, color = { 1.0, 0.82, 0.3 },
                    label = string.format("BOUNTY: %s '%s'", npc.label or "Pirate", contract.callsign),
                    bounty = true,
                }
            end
            out[#out + 1] = npc
        elseif contract or d <= detectAt then
            -- A signature: a rough place (the same for `refresh` seconds, then
            -- drawn afresh), a strength by how loud it is, nothing else. A
            -- contracted ship is tracked wherever it is.
            local noise = math.min(d * cfg.noiseShare * (1.5 - loud), cfg.maxNoise) / accuracy
            -- Entity ids are 64-bit integers (FFI cdata): reduced and made a
            -- plain number before any maths
            local idNum = tonumber(npc.entity.id % 1000003) or 0
            local function jitter(channel)
                local v = math.sin(idNum * 12.9898 + bucket * 78.233 + channel * 37.719) * 43758.5453
                return (v - math.floor(v)) * 2 - 1
            end
            local strength = "Moderate"
            for _, step in ipairs(cfg.strength) do
                if loud < step[1] then strength = step[2] break end
            end
            out[#out + 1] = {
                entity = npc.entity, signature = true, sizeClass = npc.sizeClass, loudness = loud,
                label = contract and string.format("Bounty '%s' (%s signature)", contract.callsign, strength:lower())
                    or (strength .. " signature"),
                color = contract and { 1.0, 0.82, 0.3 } or { 0.85, 0.75, 0.45 },
                offset = { x = jitter(1) * noise, y = jitter(2) * noise * 0.3, z = jitter(3) * noise },
                bounty = contract ~= nil,
            }
        end
    end
    return out
end

--- The sensors' signatures on the HUD: the nearest `markers` of them (and
--- every bounty target), as a small diamond where the sensors put it when it
--- is on screen, and as an arrow at the screen's edge pointing the way to it
--- when it is not, with the distance. Bounty targets in gold.
---@param w number
---@param h number
---@param font string
function LimitTheoryRedux:drawSignatureMarkers(w, h, font)
    local contacts = self.sensorContacts
    local here = self:shipPosition()
    if not contacts or #contacts == 0 or not here then return end
    local camEntity = CameraManager:getActiveCameraEntity()
    local camTransform = camEntity and camEntity:get(PhysicsComponents.Transform)
    if not camTransform then return end
    local cam = camTransform:getPos()
    local rot = CameraManager:getViewRot()
    local fwd, rt, up = rot:getForward(), rot:getRight(), rot:getUp()
    local tanHalf = math.tan(math.rad(CameraManager:getFov()) / 2)
    local aspect = w / h

    -- Nearest first, bounty targets always
    local list = {}
    for _, c in ipairs(contacts) do
        local rbCmp = c.entity:isValid() and c.entity:get(PhysicsComponents.RigidBody)
        local body = rbCmp and rbCmp:getRigidBody()
        if body then
            local p = body:getPos()
            local x, y, z = p.x + c.offset.x, p.y + c.offset.y, p.z + c.offset.z
            local d = math.sqrt((x - here.x) ^ 2 + (y - here.y) ^ 2 + (z - here.z) ^ 2)
            list[#list + 1] = { c = c, x = x, y = y, z = z, d = d }
        end
    end
    table.sort(list, function(a, b)
        local ap, bp = a.c.bounty or a.c.hostile, b.c.bounty or b.c.hostile
        if ap ~= bp then return ap == true end
        return a.d < b.d
    end)

    local margin = 46
    local cx, cy = w / 2, h / 2
    for i, m in ipairs(list) do
        if i > Config.game.sensors.markers and not (m.c.bounty or m.c.hostile) then break end
        local color = (m.c.hostile and { r = 1.0, g = 0.25, b = 0.2, a = 1.0 })
            or (m.c.bounty and { r = 1.0, g = 0.82, b = 0.3, a = 0.95 }) or { r = 0.9, g = 0.78, b = 0.45, a = 0.8 }
        local rx, ry, rz = m.x - cam.x, m.y - cam.y, m.z - cam.z
        local depth = rx * fwd.x + ry * fwd.y + rz * fwd.z
        local sx = (rx * rt.x + ry * rt.y + rz * rt.z)
        local sy = (rx * up.x + ry * up.y + rz * up.z)
        local px, py
        local onScreen = false
        if depth > 0 then
            px = cx + sx / (depth * tanHalf * aspect) * cx
            py = cy - sy / (depth * tanHalf) * cy
            onScreen = px > margin and px < w - margin and py > margin and py < h - margin
        end
        local dist = UniverseScaleConfig:formatDistance(m.d)
        if onScreen then
            -- Where the sensors put it: a diamond, the strength and distance
            DrawEx.Ring(px, py, 9, color, m.c.bounty)
            DrawEx.Point(px, py, 3, color)
            DrawEx.TextAlpha(font, m.c.label .. "  " .. dist, 11, px - 140, py + 10, 280, 14,
                color.r, color.g, color.b, color.a, 0.5, 0.5)
        else
            -- Off screen (or behind): an arrow at the edge, pointing the way
            local dx, dy = sx, -sy
            if depth <= 0 then dx, dy = -dx, -dy end
            local len = math.sqrt(dx * dx + dy * dy)
            if len < 1e-6 then dx, dy, len = 0, 1, 1 end
            dx, dy = dx / len, dy / len
            -- The edge of the screen, less the margin, along that direction
            local tx = dx ~= 0 and (cx - margin) / math.abs(dx) or math.huge
            local ty = dy ~= 0 and (cy - margin) / math.abs(dy) or math.huge
            local t = math.min(tx, ty)
            local ex, ey = cx + dx * t, cy + dy * t
            local nx, ny = -dy, dx
            DrawEx.Tri(ex + dx * 12, ey + dy * 12, ex + nx * 7, ey + ny * 7, ex - nx * 7, ey - ny * 7, color)
            DrawEx.TextAlpha(font, dist, 10, ex - dx * 26 - 60, ey - dy * 22 - 7, 120, 14,
                color.r, color.g, color.b, color.a, 0.5, 0.5)
        end
    end
end

--- Testing (debug.traceNpcLoss): anything other than NpcSystem that
--- destroys an NPC ship's entity is logged with its call stack.
function LimitTheoryRedux:traceNpcLoss()
    if not (Config.game.debug and Config.game.debug.traceNpcLoss) or self.npcLossHooked then return end
    self.npcLossHooked = true
    local Reg = require("Core.ECS.Registry")
    local original = Reg.destroyEntity
    local game = self
    Reg.destroyEntity = function(registry, entity, mode)
        local npcs = game.npcs
        if npcs and entity and entity.id then
            for _, record in ipairs(npcs.records or {}) do
                if record.entity and record.entity.id == entity.id and not record.removing then
                    Log.Warn("NPC ship destroyed from outside NpcSystem: %s (%s)\n%s",
                        tostring(record.label), tostring(record.role), debug.traceback("", 2))
                    break
                end
            end
        end
        return original(registry, entity, mode)
    end
end

--- Every `debug.censusInterval` seconds, a line in the log: how many NPC
--- ships there are and in what state, how many reach the maps and the
--- overview, and the nearest hostile. Where ships go missing shows here.
---@param dt number
function LimitTheoryRedux:npcCensus(dt)
    local cfg = Config.game.debug
    if not (cfg and cfg.censusInterval and cfg.censusInterval > 0) then return end
    self.censusTimer = (self.censusTimer or 0) - dt
    if self.censusTimer > 0 then return end
    self.censusTimer = cfg.censusInterval
    local records = self.npcs and self.npcs.records or {}
    local alive, docked, dead, invalid = 0, 0, 0, 0
    for _, r in ipairs(records) do
        if r.dead then dead = dead + 1
        elseif not r.entity:isValid() then invalid = invalid + 1
        elseif r.pilot.docked then docked = docked + 1
        else alive = alive + 1 end
    end
    local listed, identified, hostile, nearest = 0, 0, 0, math.huge
    local here = self:shipPosition()
    for _, entry in ipairs(self:mapNpcs()) do
        listed = listed + 1
        if not entry.signature then identified = identified + 1 end
        if not entry.signature and self:isHostileFaction(entry.faction) then
            hostile = hostile + 1
            local rbCmp = entry.entity:get(PhysicsComponents.RigidBody)
            local p = rbCmp and rbCmp:getRigidBody() and rbCmp:getRigidBody():getPos()
            if p and here then
                nearest = math.min(nearest, math.sqrt((p.x - here.x) ^ 2 + (p.y - here.y) ^ 2 + (p.z - here.z) ^ 2))
            end
        end
    end
    Log.Info("NPC census: %d records (%d flying, %d docked, %d wrecks, %d invalid)  ·  maps list %d "
        .. "(%d identified, %d hostile)  ·  nearest hostile %s  ·  ship at %s",
        #records, alive, docked, dead, invalid, listed, identified, hostile,
        nearest < math.huge and UniverseScaleConfig:formatDistance(nearest) or "none",
        here and string.format("(%.0f, %.0f, %.0f)", here.x, here.y, here.z) or "nowhere")
end

--- Where a ship was last seen, in words, for the bounty board.
---@param record table
---@return string
function LimitTheoryRedux:lastSeenArea(record)
    local p = record.body and record.body:getPos()
    if not p then return "somewhere in the system" end
    local best, bestD = nil, math.huge
    local places = self.npcs and self.npcs.places or {}
    for _, dock in ipairs(places.docks or {}) do
        local q = dock.position
        local d = (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 + (p.z - q.z) ^ 2
        if d < bestD then best, bestD = dock.label, d end
    end
    for _, gate in ipairs(places.gates or {}) do
        local q = gate.position
        local d = (p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 + (p.z - q.z) ^ 2
        if d < bestD then best, bestD = "the gate to " .. (gate.destination and gate.destination.name or "?"), d end
    end
    if record.lurkSpot then
        return "in an asteroid field" .. (best and (", nearest " .. best) or "")
    end
    return best and ("near " .. best) or "somewhere in the system"
end

--- How far the ship's sensors identify a ship (Config.game.sensors; a
--- better sensor fit reaches further).
---@return number game units
function LimitTheoryRedux:sensorRange()
    return Config.game.sensors.range * self:fitStat("scanRange", 1)
end

--- The player's ship's position, or nil.
---@return Position|nil
function LimitTheoryRedux:shipPosition()
    local rbCmp = self.playerShip and self.playerShip:isValid() and self.playerShip:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    return body and body:getPos() or nil
end

--- A few times a second: ships beyond sensor range lose their labels in
--- space (they are only signatures on the maps and the overview).
---@param dt number
function LimitTheoryRedux:updateSensors(dt)
    self.sensorTimer = (self.sensorTimer or 0) - dt
    if self.sensorTimer > 0 or not self.npcs then return end
    self.sensorTimer = 0.25
    -- What the sensors make of every ship: identified ones keep their label
    -- in space; signatures lose it (and a lock on one is dropped)
    local identified = {}
    local contacts = {}
    for _, entry in ipairs(self:mapNpcs()) do
        if entry.signature then
            contacts[#contacts + 1] = entry
        else
            identified[entry.entity.id] = true
        end
    end
    -- Testing (debug.revealShips): every hostile is marked like a contact,
    -- in red, wherever it is
    local reveal = Config.game.debug and Config.game.debug.revealShips
    if reveal then
        for _, entry in ipairs(self:mapNpcs()) do
            if not entry.signature and self:isHostileFaction(entry.faction) then
                contacts[#contacts + 1] = {
                    entity = entry.entity, label = entry.label or "Hostile", hostile = true,
                    offset = { x = 0, y = 0, z = 0 },
                }
            end
        end
    end
    self.sensorContacts = contacts
    self:npcCensus(0.25)
    for _, npc in ipairs(self.npcs:mapEntries()) do
        local entry = npc.record and npc.record.labelEntry
        if entry then
            local hidden = not identified[npc.entity.id]
            if hidden and not entry.hidden then
                if self.target and self:isTarget(npc.entity) then self:clearTarget() end
            end
            entry.hidden = hidden
        end
    end
    for _, gone in ipairs(BountyBoard:voidGone()) do
        self:notify(string.format("Bounty contract void: '%s' is gone.", gone), { 0.75, 0.75, 0.75 })
    end
end

--- The key a generated station's player-side things are filed under (its
--- hangar, leases and waiting orders): the system and the station's place in
--- it, which is stable because a system's stations are built from the
--- system's own seed, in the same order every time.
---@param index integer
---@param systemId integer|nil default the current system
---@return string
function LimitTheoryRedux:stationKey(index, systemId)
    return string.format("%d:%d", systemId or self.currentSystemId or 1, index)
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
            local key = self:stationKey(index)
            table.insert(places.docks, {
                entity = station,
                label = "Station " .. index,
                key = key,
                position = body:getPos(),
                radius = body:getBoundingRadius(),
                faction = Config.game.docking.owner,
            })
            -- The orders the player left here, back in the book, and (loading)
            -- the stock the save had
            MarketSystem:unpark(station, key)
            -- Back in a system: the shelves as the background economy left
            -- them (a save's, for the system it was saved in, win)
            GalaxyEconomy:restore(key, station, self.simTime or 0)
            self:applySavedStationStock(station, key)
            -- What the player's lines made here while they were away
            for _, event in ipairs(PlayerFactories:catchUp(station, key, self.simTime or 0)) do
                self:notify(event.text, { 0.6, 0.9, 1.0 })
            end
        end
    end
    -- The player's outposts are docks too, filed under their own keys
    for _, entry in ipairs(self.playerStationEntities or {}) do
        local dock = self:openPlayerStation(entry, places.docks)
        if dock then table.insert(places.stations, dock.position) end
    end
    places.belts = self.beltEntities or {}
    -- The background economy: this system's live now (its stations took
    -- their ledgers above), every other system has stations to keep going,
    -- visited or not
    GalaxyEconomy:dropSystem(self.currentSystemId or 1)
    GalaxyEconomy:seedGalaxy(self.galaxy, self.currentSystemId or 1, self.simTime or 0)
    self.npcs:setPlaces(places)
    self.npcs:setPlayer(self.playerShip)
    self:updatePlayerVisibility()

    local system = self.galaxy and self.galaxy.systems[self.currentSystemId]
    local level = self:currentHostility()
    if level then
        self.npcs:populate(level, system and system.seed or self.seed)
    end
    -- The player's own ships in this system, back at their posts
    self:spawnPlayerForces()
end

--- A new game or a regenerated one starts in a new galaxy, in its first
--- system, with no course.
function LimitTheoryRedux:resetGalaxy()
    self.galaxy = nil
    self.currentSystemId = 1
    self.course = nil
    self.jump = nil
    Reputation:reset()
    MarketSystem:resetParked()
    -- Which factions the player chose to turn against: asked afresh each game
    self.hostilityAccepted = {}
    PlayerWallet:reset()
    -- What the start gives (Config/Scenarios: `start`), else GameConfig's
    local start = self.scenario and self.scenario.start or {}
    if start.credits then PlayerWallet.balance = start.credits end
    PlayerCargo:reset()
    PlayerFactories:reset()
    PlayerStations:reset()
    PlayerForces:reset()
    MarketIntel:reset()
    GalaxyEconomy:reset()
    self:connectMarket()
    -- A new galaxy's rocks are all unread
    self.surveyedRocks = {}
    -- The ship a new game starts in: empty slots but for what it comes with
    AbilitySystem:reset()
    PlayerFleet:reset(start.hull or Config.game.fitting.startingHull)
    for _, name in ipairs(start.modules or Config.game.fitting.startingModules) do
        local def = Fittings:getByName(name)
        if def then
            PlayerFleet:grantModule(def)
        else
            Log.Warn("The starting modules name no fitting: %s", tostring(name))
        end
    end
    -- Guns go in mounts, which only exist once the ship is built: they are
    -- put in the first that takes them then (PlayerFleet:restore)
    for _, name in ipairs(start.weapons or Config.game.fitting.startingWeapons or {}) do
        local def = Fittings:getByName(name)
        if not (def and PlayerFleet:grantWeapon(def)) then
            Log.Warn("The starting weapons name no weapon: %s", tostring(name))
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
    -- The speed effects, as Settings has them (a scenario may try others)
    require('Modules.Rendering.Systems.SpeedFeelSystem'):enable(self)
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
    self.travelBodies = {}
    self:nameCelestials()
    self:collectEntities(self.universe)
    -- The planets, moons and star the travel drive drops out short of
    require("Modules.Constructs.Systems.TravelDriveSystem"):setBodies(self.travelBodies)
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
    require('Modules.Rendering.Systems.SpeedFeelSystem'):disable()
    -- The overview's list and anything it set going belong to this system
    SystemOverview:invalidate()
    -- What the ship was doing goes with the scene: the laser's rock and its
    -- beam, a jump drive's charge
    if self.miningJob then self:stopMining() end
    MiningBeam:stop()
    self.driveJump = nil
    self.lookingAt, self.arrivalAction = nil, nil
    self:clearAllTargets()
    self.confirmation = nil
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
    self.forceRecords = {}
    -- The bounty board is the system's: its contracts end with it
    if #BountyBoard.contracts > 0 and self.playerShip then
        self:notify("Bounty contracts end on leaving the system.", { 0.75, 0.75, 0.75 })
    end
    BountyBoard:reset()
    -- Canisters float in this system's space, and go with it
    LootSystem:clear()
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

    for index, station in ipairs(self.stations or {}) do
        -- The player's orders here wait for the station to come back (their
        -- escrow with them), rather than going with its book
        MarketSystem:park(station, self:stationKey(index))
        local rbCmp = station:get(PhysicsComponents.RigidBody)
        if rbCmp and rbCmp:getRigidBody() then
            self.world:removeRigidBody(rbCmp:getRigidBody())
        end
        Registry:destroyEntity(station, Enums.Registry.EntityDestroyMode.DestroyChildren)
    end
    self.stations = {}
    for _, entry in ipairs(self.playerStationEntities or {}) do
        self:removeOutpostDefense(entry)
        MarketSystem:park(entry.entity, PlayerStations.keyOf(entry.record.id))
        local rbCmp = entry.entity:get(PhysicsComponents.RigidBody)
        if rbCmp and rbCmp:getRigidBody() then
            self.world:removeRigidBody(rbCmp:getRigidBody())
        end
        Registry:destroyEntity(entry.entity, Enums.Registry.EntityDestroyMode.DestroyChildren)
    end
    self.playerStationEntities = {}

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

--- Name the system's celestials (Vega, Vega II, Vega II a) after its star
--- system; everything that shows one asks CelestialNames. Run when the
--- system is built, and again once a new game's galaxy exists (it is made
--- after the first system, and gives the system its name): the labels in
--- space and the overview take the names then.
function LimitTheoryRedux:nameCelestials()
    if not self.universe then return end
    local CelestialNames = require("Modules.CelestialObjects.Managers.CelestialNames")
    local system = self.galaxy and self.galaxy.systems and self.galaxy.systems[self.currentSystemId]
    CelestialNames:name(self.universe, system and system.name or nil)
    for _, entry in ipairs(self.labeledEntities or {}) do
        entry.label = CelestialNames:of(entry.entity, entry.label)
    end
    SystemOverview:invalidate()
end

--- Walk the generated universe and collect planets/labels/star/belts.
---@param entity Entity
function LimitTheoryRedux:collectEntities(entity)
    local name = tostring(entity)
    -- The label in space: the celestial's name (its type name otherwise)
    local label = require("Modules.CelestialObjects.Managers.CelestialNames"):of(entity, name)

    local bodies = self.travelBodies or {}
    self.travelBodies = bodies
    if name:find("PlanetEntity") then
        table.insert(self.planets, entity)
        table.insert(self.labeledEntities, { entity = entity, label = label })
        table.insert(bodies, { entity = entity, kind = "planet" })
    elseif name:find("MoonEntity") then
        table.insert(self.labeledEntities, { entity = entity, label = label })
        table.insert(bodies, { entity = entity, kind = "moon" })
    elseif name:find("StarEntity") then
        self.starEntity = entity
        table.insert(bodies, { entity = entity, kind = "star" })
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
        -- This ship's own fit goes back on: its guns, its modules and the
        -- stats they come to (PlayerFleet outlives the entity). Anything the
        -- hull has no room for goes into the station's hangar when there is
        -- one, and into the hold otherwise.
        local spare = self.docked and self.docked.key and PlayerFactories:hangar(self.docked.key)
            or PlayerCargo:get()
        local returned, lost = PlayerFleet:restore(self.playerShip, gunship.turrets, spare)
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
        -- Only the mounts with a gun in them shoot: an empty mount has no
        -- weapon to resolve, so the battery is built from the armed ones. A
        -- ship with nothing fitted flies unarmed.
        -- Every mount, tools included (the battery has only the guns): the
        -- mining beam starts from its laser's
        self.playerMounts = gunship and gunship.turretsById or nil
        local armed = self:armedConstruction(gunship)
        if armed then
            self.playerBattery = self.weaponCombat:addBattery(WeaponBattery(armed, {
                name = "Your ship",
                aiActive = true,
                team = Factions.Player,
                hostileTeams = Factions.hostileTeams(Factions.Player),
            }))
        end
    end

    Log.Info("Player ship spawned at (%.1f, %.1f, %.1f)", position.x, position.y, position.z)
end

--- The construction a weapon battery should be built from: the same ship,
--- with only the mounts that have a gun in them.
---
--- A turret has to name a weapon it can resolve, so an empty mount cannot
--- simply be left blank -- it is left out of the battery instead, and its
--- turret neither tracks nor fires. Nothing fitted at all means no battery:
--- the ship is unarmed until something goes in a mount.
---@param construction table the ArmedShipBuilder construction
---@return table|nil
function LimitTheoryRedux:armedConstruction(construction)
    if not construction then return nil end
    local loadout = self.playerShip and self.playerShip:get(ConstructComponents.Loadout)
    if not loadout then return construction end
    local turrets, turretsById, mountIds = {}, {}, {}
    for _, turret in ipairs(construction.turrets or {}) do
        local mountId = turret.component and turret.component:getMountId() or turret.mountId
        -- A gun, not a tool: the mining laser's mount is not in the battery
        local def = mountId and loadout:getWeapon(mountId)
        if def and def.weaponId then
            turrets[#turrets + 1] = turret
            turretsById[mountId] = turret
            mountIds[#mountIds + 1] = mountId
        end
    end
    if #turrets == 0 then
        Log.Info("The player's ship has nothing in its mounts: flying unarmed")
        return nil
    end
    if #turrets == #(construction.turrets or {}) then return construction end
    local armed = {}
    for key, value in pairs(construction) do armed[key] = value end
    armed.turrets = turrets
    armed.turretsById = turretsById
    armed.mountIds = mountIds
    return armed
end

--- The player's gunship (an ArmedShipBuilder construction), or nil if it
--- could not be built (logged; the caller builds the plain ship instead).
---@param position Position
---@param seed integer
---@return table|nil construction
function LimitTheoryRedux:buildPlayerGunship(position, seed)
    local cfg = Config.game.playerGunship
    -- The hull being flown decides the mounts, the capacitor, the stats and
    -- the size; the fit decides everything else (PlayerFleet, HullDefs)
    local hull = PlayerFleet.hullOf(PlayerFleet:active())
    local stats = hull and PlayerFleet:stats() or cfg
    local ok, result = pcall(function()
        return ArmedShipBuilder:build(GunshipRecipe.build(seed, Factions.Player, stats, hull), {
            constructManager = self.constructManager,
            shipConfig = {
                position = position,
                scale = PlayerFleet:scale(cfg.scale),
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
    self:spawnPlayerStations()
end

--- The player's outposts in this system (PlayerStations), built from their
--- records where they were deployed. They are kept apart from
--- `self.stations`, whose keys are their places in the generated list.
function LimitTheoryRedux:spawnPlayerStations()
    self.playerStationEntities = self.playerStationEntities or {}
    for _, record in ipairs(PlayerStations:inSystem(self.currentSystemId or 1)) do
        self:buildPlayerStation(record)
    end
end

--- Build one outpost's entity: a station of its own seed, a book for its
--- market and a store (empty: an outpost's goods are the owner's, in its
--- hangar). No crew and no production of its own: its lines are the owner's.
---@param record PlayerStation
---@return Entity station
function LimitTheoryRedux:buildPlayerStation(record)
    local p = record.position
    local station = StationGenerator:createStation(1000003 * record.id + 17, {
        position = Position(p.x, p.y, p.z),
        scale = self.cfg.stationScale * (Config.game.outposts.scale or 0.8),
        isKinematic = true,
    })
    local rbCmp = station:get(PhysicsComponents.RigidBody)
    if rbCmp and rbCmp:getRigidBody() then
        self.world:addRigidBody(rbCmp:getRigidBody())
    end
    station:add(EconomyComponents.Stock())
    station:add(EconomyComponents.OrderBook())
    local entry = { entity = station, record = record }
    table.insert(self.playerStationEntities, entry)
    local r, g, b = Factions.color(Factions.Player)
    table.insert(self.labeledEntities, { entity = station, label = record.name, color = { r, g, b } })
    self:buildOutpostDefense(entry)
    return station
end

------------------------------------------------------------------------------
-- An outpost's defences: an armed platform beside it. The station is safe;
-- its guns can fall, and are repaired or rebuilt at the station.
------------------------------------------------------------------------------

local DEFENSE_SIZE_CLASS = {
    small = Enums.Target.SizeClass.Small,
    medium = Enums.Target.SizeClass.Medium,
    large = Enums.Target.SizeClass.Large,
}

--- Build an outpost's defence platform, unless it was shot down (then it
--- waits for a rebuild). Its hull and shields are the record's, as saved.
---@param entry table { entity, record }
function LimitTheoryRedux:buildOutpostDefense(entry)
    local record = entry.record
    record.defense = record.defense or {}
    if record.defense.destroyed or not self.weaponCombat or not self.constructManager then return end
    local cfg = Config.game.outposts.defense
    local rbCmp = entry.entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if not body then return end
    local p, radius = body:getPos(), body:getBoundingRadius()
    local position = Position(p.x + radius * cfg.offset, p.y, p.z)
    local ok, construction = pcall(function()
        return ArmedShipBuilder:build(GunshipRecipe.build(1000003 * record.id + 29, Factions.Player, cfg), {
            constructManager = self.constructManager,
            shipConfig = { position = position, scale = cfg.scale, isKinematic = true },
        })
    end)
    if not ok then
        Log.Error("Outpost %s: its defences could not be built: %s", record.name, tostring(construction))
        return
    end
    construction.shipBody:setCollidable(true)
    local ship = construction.ship
    ship:add(ConstructComponents.Targetable(Factions.Player,
        DEFENSE_SIZE_CLASS[cfg.sizeClass] or Enums.Target.SizeClass.Large))
    local battery = self.weaponCombat:addBattery(WeaponBattery(construction, {
        name = record.name .. " defences",
        aiActive = true,
        team = Factions.Player,
        hostileTeams = Factions.hostileTeams(Factions.Player),
    }))
    -- As saved: a battered platform comes back battered
    local health = ship:get(CoreComponentsAll.Health)
    local defense = ship:get(ConstructComponents.Defense)
    if health and record.defense.hull then
        health:setCurrentHealth(math.max(1, math.min(record.defense.hull, health:getMaxHealth())))
    end
    if defense and record.defense.shield then
        defense:setCurrentShield(math.min(record.defense.shield, defense:getMaxShield()))
    end
    local r, g, b = Factions.color(Factions.Player)
    local label = { entity = ship, label = record.name .. " Defences", color = { r, g, b } }
    table.insert(self.labeledEntities, label)
    entry.defense = { handle = construction.shipHandle, entity = ship, battery = battery, label = label }
end

--- Take an outpost's platform out of the scene (a jump, or a wreck cleared).
---@param entry table
function LimitTheoryRedux:removeOutpostDefense(entry)
    local d = entry.defense
    if not d then return end
    entry.defense = nil
    for i = #(self.labeledEntities or {}), 1, -1 do
        if self.labeledEntities[i] == d.label then table.remove(self.labeledEntities, i) end
    end
    if d.battery then d.battery:setAIActive(false) end
    if self.player and self.player:getOrbitTarget() == d.entity then self.player:setOrbitTarget(nil) end
    if self.constructManager and d.handle then self.constructManager:destroy(d.handle) end
end

--- Each frame: the platforms' shields recharge, their state is kept on the
--- records (what a save writes), and one shot down goes after its wreck.
---@param dt number
function LimitTheoryRedux:updateOutpostDefenses(dt)
    for _, entry in ipairs(self.playerStationEntities or {}) do
        local d = entry.defense
        if d then
            if d.wreck then
                d.wreck = d.wreck - dt
                if d.wreck <= 0 then self:removeOutpostDefense(entry) end
            elseif d.entity:isValid() then
                local health = d.entity:get(CoreComponentsAll.Health)
                local defense = d.entity:get(ConstructComponents.Defense)
                if defense then defense:update(dt) end
                local state = entry.record.defense
                state.hull = health and health:getCurrentHealth() or state.hull
                state.shield = defense and defense:getCurrentShield() or state.shield
                if health and health:isDestroyed() then
                    state.destroyed, state.hull, state.shield = true, 0, 0
                    if d.battery then d.battery:setAIActive(false) end
                    d.wreck = Config.game.npc.wreckTime
                    self:notify(string.format("%s: its defences have been destroyed. Rebuild them there.",
                        entry.record.name), { 1.0, 0.4, 0.3 })
                end
            end
        end
    end
end

------------------------------------------------------------------------------
-- The player's forces (PlayerForces): drones and mercenaries, flown as NPC
-- gunships of the player's side while the player is in their system
------------------------------------------------------------------------------

--- Where an outpost is, for its units.
---@param key string
---@return table|nil position, number radius
function LimitTheoryRedux:outpostPlace(key)
    local entry = self:outpostEntry(key)
    local rbCmp = entry and entry.entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if not body then return nil, 0 end
    return body:getPos(), body:getBoundingRadius()
end

--- The round a unit flies: four points about its outpost (guard), or every
--- outpost of the player's in the system (patrol).
---@param unit PlayerUnit
---@return table[] positions
function LimitTheoryRedux:unitNodes(unit)
    local nodes = {}
    local function around(key, reach)
        local p, radius = self:outpostPlace(key)
        if not p then return end
        local r = math.max(reach, radius * 2)
        -- Each unit starts its round at a different quarter, so they spread out
        for i = 0, 3 do
            local a = (i + unit.id) * math.pi / 2
            nodes[#nodes + 1] = { x = p.x + math.cos(a) * r, y = p.y, z = p.z + math.sin(a) * r }
        end
    end
    if unit.order == PlayerForces.Order.Patrol then
        for _, entry in ipairs(self.playerStationEntities or {}) do
            local p, radius = self:outpostPlace(PlayerStations.keyOf(entry.record.id))
            if p then
                local a = unit.id * 1.7
                local r = radius * 2.5
                nodes[#nodes + 1] = { x = p.x + math.cos(a) * r, y = p.y, z = p.z + math.sin(a) * r }
            end
        end
        if #nodes > 1 then return nodes end
        nodes = {}
    end
    around(unit.homeKey, Config.game.forces.guardRadius)
    return nodes
end

--- Fly one unit: an NPC gunship of its role near its outpost, with its
--- order as its job and its hull and shields as last seen.
---@param unit PlayerUnit
---@return table|nil record
function LimitTheoryRedux:spawnUnit(unit)
    if not self.npcs or not self:isTravelGame() then return nil end
    local home, radius = self:outpostPlace(unit.homeKey)
    if not home then
        Log.Warn("Forces: %s has no outpost to come back to (%s)", unit.name, tostring(unit.homeKey))
        return nil
    end
    local forces = Config.game.forces
    local role = unit.kind == PlayerForces.Kind.Drone and forces.drone.role or forces.mercenary.role
    local a = unit.id * 2.39996
    local r = radius * 2.2
    local spot = { x = home.x + math.cos(a) * r, y = home.y + radius * 0.5, z = home.z + math.sin(a) * r }
    local record = self.npcs:spawn(role, spot, 7919 * unit.id + 101)
    if not record then return nil end
    record.unit = unit
    record.label = unit.name
    record.assignment = { nodes = function() return self:unitNodes(unit) end }
    local health = record.entity:get(CoreComponentsAll.Health)
    local defense = record.entity:get(ConstructComponents.Defense)
    if health and unit.hull then health:setCurrentHealth(math.max(1, math.min(unit.hull, health:getMaxHealth()))) end
    if defense and unit.shield then defense:setCurrentShield(math.min(unit.shield, defense:getMaxShield())) end
    self.forceRecords = self.forceRecords or {}
    self.forceRecords[unit.id] = record
    return record
end

--- The player's units in this system, after it was built.
function LimitTheoryRedux:spawnPlayerForces()
    self.forceRecords = {}
    for _, unit in ipairs(PlayerForces:inSystem(self.currentSystemId or 1)) do
        self:spawnUnit(unit)
    end
end

--- Each frame: wages, the units' state onto their records, and the ones
--- that were destroyed off the books.
---@param dt number
function LimitTheoryRedux:updatePlayerForces(dt)
    self.wageTimer = (self.wageTimer or 0) - dt
    if self.wageTimer <= 0 then
        self.wageTimer = Config.game.forces.wageInterval
        local events, left = PlayerForces:payWages(self.simTime or 0)
        for _, event in ipairs(events) do self:notify(event.text, { 1.0, 0.6, 0.3 }) end
        for _, id in ipairs(left) do
            local record = self.forceRecords and self.forceRecords[id]
            if record and not record.removed then self.npcs:remove(record, "wages unpaid") end
            if self.forceRecords then self.forceRecords[id] = nil end
        end
    end
    for id, record in pairs(self.forceRecords or {}) do
        local unit = PlayerForces:get(id)
        if not unit or record.removed then
            self.forceRecords[id] = nil
        elseif record.dead then
            PlayerForces:remove(id)
            self.forceRecords[id] = nil
            self:notify(string.format("%s was destroyed.", unit.name), { 1.0, 0.4, 0.3 })
        elseif record.entity:isValid() then
            local health = record.entity:get(CoreComponentsAll.Health)
            local defense = record.entity:get(ConstructComponents.Defense)
            unit.hull = health and health:getCurrentHealth() or unit.hull
            unit.shield = defense and defense:getCurrentShield() or unit.shield
        end
    end
end

--- A ship died: it leaves a canister of what its role's loot table rolls
--- (res/data/loot.toml). The player's own ships leave nothing.
---@param record table NpcSystem's record
function LimitTheoryRedux:onNpcDestroyed(record)
    -- Only a ship that was shot to pieces: one whose entity is already gone
    -- (removed, not killed) has no wreck, and its body may be freed with it
    if record.unit or not record.body or not record.entity:isValid() then return end
    local health = record.entity:get(CoreComponentsAll.Health)
    if not (health and health:isDestroyed()) then return end
    self.lootRng = self.lootRng or RNG.Create((self.seed or 1) + 77)
    local ok, contents = pcall(LootData.roll, record.role, self.lootRng)
    if not ok then
        Log.Error("Loot: %s", tostring(contents))
        return
    end
    local p = record.body:getPos()
    LootSystem:attach(self.world, self)
    LootSystem:drop({ x = p.x, y = p.y, z = p.z }, contents)
end

--- Each frame: canisters drift in to the ship and into the hold, with a
--- word when something was collected or would not fit.
---@param dt number
function LimitTheoryRedux:updateLoot(dt)
    if #LootSystem.canisters == 0 then return end
    local shipPos
    if self.playerShip and not self.docked and not self.jump then
        local rbCmp = self.playerShip:get(PhysicsComponents.RigidBody)
        local body = rbCmp and rbCmp:getRigidBody()
        shipPos = body and body:getPos()
    end
    for _, event in ipairs(LootSystem:update(dt, shipPos, PlayerCargo:get(), self.simTime or 0)) do
        self:notify(event.text, event.color)
    end
end

--- Whether an entity is one of the player's units.
---@param entity Entity|nil
---@return boolean
function LimitTheoryRedux:isPlayerUnit(entity)
    if not entity or not entity.id then return false end
    for _, record in pairs(self.forceRecords or {}) do
        if record.entity and record.entity.id == entity.id then return true end
    end
    return false
end

--- A unit's state for the Forces tab: { hull, maxHull, shield, maxShield,
--- here (flying in this system) }.
---@param unit PlayerUnit
---@return table
function LimitTheoryRedux:unitStatus(unit)
    local record = self.forceRecords and self.forceRecords[unit.id]
    local status = { here = record ~= nil }
    local stats = Config.game.npc.roles[unit.kind == PlayerForces.Kind.Drone
        and Config.game.forces.drone.role or Config.game.forces.mercenary.role]
    status.maxHull, status.maxShield = stats.maxHealth, stats.maxShield
    status.hull, status.shield = unit.hull or stats.maxHealth, unit.shield or stats.maxShield
    if record and record.entity:isValid() then
        local health = record.entity:get(CoreComponentsAll.Health)
        local defense = record.entity:get(ConstructComponents.Defense)
        if health then status.hull, status.maxHull = health:getCurrentHealth(), health:getMaxHealth() end
        if defense then status.shield, status.maxShield = defense:getCurrentShield(), defense:getMaxShield() end
    end
    return status
end

--- The drone item, and the hangar of the outpost the player is docked at.
---@return ItemDefinition|nil, StockComponent|nil, string|nil key
function LimitTheoryRedux:droneStock()
    local key = self.docked and self.docked.key
    if not PlayerStations.isOwnedKey(key) then return nil, nil, nil end
    return Items:getByName(Config.game.forces.drone.item), PlayerFactories:hangar(key), key
end

--- Launch a drone from the docked outpost's hangar.
function LimitTheoryRedux:launchDrone()
    local def, hangar, key = self:droneStock()
    if not def or not hangar then return end
    if hangar:count(def.id) < 1 then
        self:notify("No " .. def.displayName .. " in this hangar.", { 1.0, 0.7, 0.3 })
        return
    end
    local unit, reason = PlayerForces:launchDrone(self.currentSystemId or 1, key)
    if not unit then
        self:notify("Cannot launch: " .. reason, { 1.0, 0.4, 0.3 })
        return
    end
    hangar:remove(def.id, 1)
    self:spawnUnit(unit)
    self:notify(string.format("%s launched: guarding %s.", unit.name, self.docked.label), { 0.3, 1.0, 0.45 })
end

--- Hire a mercenary at the docked outpost.
function LimitTheoryRedux:hireMercenary()
    local key = self.docked and self.docked.key
    if not PlayerStations.isOwnedKey(key) then return end
    local unit, reason = PlayerForces:hireMercenary(self.currentSystemId or 1, key, self.simTime or 0)
    if not unit then
        self:notify("Cannot hire: " .. reason, { 1.0, 0.4, 0.3 })
        return
    end
    self:spawnUnit(unit)
    local cfg = Config.game.forces.mercenary
    self:notify(string.format("%s hired for %s, at %s an hour: guarding %s.", unit.name,
        PlayerWallet.format(cfg.hireCost), PlayerWallet.format(cfg.wagePerHour), self.docked.label),
        { 0.3, 1.0, 0.45 })
end

--- Guard or patrol.
---@param unit PlayerUnit
---@param order string
function LimitTheoryRedux:setUnitOrder(unit, order)
    PlayerForces:setOrder(unit.id, order)
    local record = self.forceRecords and self.forceRecords[unit.id]
    -- The current round is dropped; Think gives the new one
    if record and not record.dead and not record.removed then
        record.pilot:clearActions(record)
        record.pilot:clearGoal()
    end
end

--- A drone back into its outpost's hangar (it must be here and docked with
--- the player at its outpost), or a mercenary paid off.
---@param unit PlayerUnit
function LimitTheoryRedux:releaseUnit(unit)
    local record = self.forceRecords and self.forceRecords[unit.id]
    if unit.kind == PlayerForces.Kind.Drone then
        local def, hangar, key = self:droneStock()
        if not def or key ~= unit.homeKey or not record then
            self:notify("A drone is recalled at its own outpost, while it is in the system.", { 1.0, 0.7, 0.3 })
            return
        end
        if hangar:add(def.id, 1) < 1 then
            self:notify("No room in the hangar for the drone.", { 1.0, 0.4, 0.3 })
            return
        end
        self:notify(unit.name .. " recalled to the hangar.", { 0.6, 0.9, 1.0 })
    else
        self:notify(unit.name .. " paid off and gone.", { 0.6, 0.9, 1.0 })
    end
    PlayerForces:remove(unit.id)
    if record and not record.removed then self.npcs:remove(record, "recalled or paid off") end
    if self.forceRecords then self.forceRecords[unit.id] = nil end
end

--- Whether an entity is one of the outposts' defence platforms.
---@param entity Entity|nil
---@return boolean
function LimitTheoryRedux:isOutpostDefense(entity)
    if not entity then return false end
    for _, entry in ipairs(self.playerStationEntities or {}) do
        if entry.defense and entry.defense.entity.id == entity.id then return true end
    end
    return false
end

--- The scene entry of the outpost at `key`, if it is in this system.
---@param key string
---@return table|nil
function LimitTheoryRedux:outpostEntry(key)
    for _, entry in ipairs(self.playerStationEntities or {}) do
        if PlayerStations.keyOf(entry.record.id) == key then return entry end
    end
    return nil
end

--- The state of an outpost's defences and what putting them right costs.
---@param key string
---@return table|nil { destroyed, hull, maxHull, shield, maxShield, cost }
function LimitTheoryRedux:outpostDefenseQuote(key)
    local entry = self:outpostEntry(key)
    if not entry then return nil end
    local cfg = Config.game.outposts.defense
    local state = entry.record.defense or {}
    if state.destroyed or not entry.defense then
        return { destroyed = true, hull = 0, maxHull = cfg.maxHealth, shield = 0,
                 maxShield = cfg.maxShield, cost = cfg.rebuildCost }
    end
    local health = entry.defense.entity:get(CoreComponentsAll.Health)
    local defense = entry.defense.entity:get(ConstructComponents.Defense)
    local hull = health and health:getCurrentHealth() or 0
    local maxHull = health and health:getMaxHealth() or cfg.maxHealth
    return {
        destroyed = false, hull = hull, maxHull = maxHull,
        shield = defense and defense:getCurrentShield() or 0,
        maxShield = defense and defense:getMaxShield() or cfg.maxShield,
        cost = math.ceil((maxHull - hull) * Config.game.economy.hullRepairCost),
    }
end

--- Repair an outpost's platform, or rebuild one that was shot down.
---@param key string
function LimitTheoryRedux:repairOutpostDefense(key)
    local entry = self:outpostEntry(key)
    local quote = self:outpostDefenseQuote(key)
    if not entry or not quote then return end
    if quote.cost <= 0 then
        self:notify("The defences need no repair.", { 0.6, 0.9, 1.0 })
        return
    end
    if not PlayerWallet:remove(quote.cost, quote.destroyed and "Outpost defences rebuilt"
            or "Outpost defences repaired") then
        self:notify("Not enough credits.", { 1.0, 0.4, 0.3 })
        return
    end
    if quote.destroyed then
        self:removeOutpostDefense(entry)
        entry.record.defense = {}
        self:buildOutpostDefense(entry)
        self:notify(string.format("%s: defences rebuilt for %s", entry.record.name,
            PlayerWallet.format(quote.cost)), { 0.3, 1.0, 0.45 })
    else
        local health = entry.defense.entity:get(CoreComponentsAll.Health)
        health:setCurrentHealth(health:getMaxHealth())
        entry.record.defense.hull = health:getMaxHealth()
        self:notify(string.format("%s: defences repaired for %s", entry.record.name,
            PlayerWallet.format(quote.cost)), { 0.6, 0.9, 1.0 })
    end
end

--- The dock record of an outpost, as `npcs.places.docks` keeps them.
---@param entry table { entity, record }
---@return table|nil dock
function LimitTheoryRedux:playerStationDock(entry)
    local rbCmp = entry.entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if not body then return nil end
    return {
        entity = entry.entity,
        label = entry.record.name,
        key = PlayerStations.keyOf(entry.record.id),
        position = body:getPos(),
        radius = body:getBoundingRadius(),
        faction = Factions.Player,
        outpost = entry.record,
    }
end

--- Open the doors of an outpost that has just been built: its dock, the
--- owner's orders back in its book, what its lines made meanwhile.
---@param entry table { entity, record }
---@param docks table[] the list to add the dock to
---@return table|nil dock
function LimitTheoryRedux:openPlayerStation(entry, docks)
    local dock = self:playerStationDock(entry)
    if not dock then return nil end
    table.insert(docks, dock)
    MarketSystem:unpark(entry.entity, dock.key)
    for _, event in ipairs(PlayerFactories:catchUp(entry.entity, dock.key, self.simTime or 0)) do
        self:notify(event.text, { 0.6, 0.9, 1.0 })
    end
    return dock
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
        -- The first system has its name now
        self:nameCelestials()
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
            -- The start may ask for its own (the Sandbox's: Peaceful)
            local start = self.scenario and self.scenario.start
            system.hostility = start and start.homeLevel or cfg.homeLevel
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

------------------------------------------------------------------------------
-- The jump drive (Config.game.jumpDrive): a capital's way between systems
-- without a gate
------------------------------------------------------------------------------

--- How far the fitted jump drive reaches, in shares of the galaxy's radius
--- (0: no drive).
---@return number
function LimitTheoryRedux:jumpDriveReach()
    return self:fitStat("jumpRange", 0) or 0
end

--- How far a system is from this one, in shares of the galaxy's radius.
---@param targetId integer
---@return number|nil
function LimitTheoryRedux:galaxyDistance(targetId)
    local galaxy = self.galaxy
    local here = galaxy and galaxy.systems[self.currentSystemId]
    local there = galaxy and galaxy.systems[targetId]
    if not here or not there or not galaxy.radius or galaxy.radius <= 0 then return nil end
    local a, b = here.position, there.position
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2) / galaxy.radius
end

--- The fuel a jump to a system takes.
---@param targetId integer
---@return integer units, ItemDefinition|nil fuel
function LimitTheoryRedux:jumpDriveFuel(targetId)
    local cfg = Config.game.jumpDrive
    local fuel = Items:getByName(cfg.fuelItem)
    local d = self:galaxyDistance(targetId) or 0
    return math.max(cfg.minFuel or 0, math.ceil(d * cfg.fuelPerRadius)), fuel
end

--- Whether the drive can jump to a system now, and if not, why.
---@param targetId integer|nil
---@return boolean, string|nil reason
function LimitTheoryRedux:canDriveJump(targetId)
    local reach = self:jumpDriveReach()
    if reach <= 0 then return false, "no jump drive fitted (a capital's C module)" end
    if self.flow and not self.flow:is(Phase.InSystem) then return false, "not now" end
    if not targetId or targetId == self.currentSystemId then return false, "you are in that system" end
    if self.docked then return false, "undock first" end
    if self.jump then return false, "already jumping" end
    local d = self:galaxyDistance(targetId)
    if not d then return false, "no such system" end
    if d > reach then
        return false, string.format("out of reach (%.0f%% of the drive's range)", 100 * d / reach)
    end
    local left = (self.jumpDriveReady or 0) - (self.simTime or 0)
    if left > 0 then return false, string.format("the drive is cooling down: %ds", math.ceil(left)) end
    local units, fuel = self:jumpDriveFuel(targetId)
    if not fuel or PlayerCargo:get():count(fuel.id) < units then
        return false, string.format("needs %d %s in the hold", units, Config.game.jumpDrive.fuelItem)
    end
    return true
end

--- What the galaxy map says about jumping to a system with the drive.
---@param targetId integer
---@return string|nil text, table|nil color
function LimitTheoryRedux:jumpDriveLine(targetId)
    if self:jumpDriveReach() <= 0 or targetId == self.currentSystemId then return nil end
    if self.driveJump then
        return string.format("Jump drive charging: %ds", math.ceil(self.driveJump.time)), { 0.6, 0.9, 1.0 }
    end
    local ok, reason = self:canDriveJump(targetId)
    if ok then
        local units = self:jumpDriveFuel(targetId)
        return string.format("J: jump drive (%d %s)", units, Config.game.jumpDrive.fuelItem), { 0.4, 1.0, 0.6 }
    end
    return "Jump drive: " .. reason, { 1.0, 0.6, 0.4 }
end

--- Start the drive's charge toward a system.
---@param targetId integer
function LimitTheoryRedux:engageJumpDrive(targetId)
    if self.driveJump then
        self.driveJump = nil
        self:notify("Jump drive charge cancelled.", { 0.75, 0.8, 0.85 })
        return
    end
    local ok, reason = self:canDriveJump(targetId)
    if not ok then
        self:notify("Jump drive: " .. reason, { 1.0, 0.6, 0.4 })
        return
    end
    self.driveJump = { to = targetId, time = Config.game.jumpDrive.spoolTime }
    self:notify(string.format("Jump drive charging for %s: %ds", self.galaxy.systems[targetId].name,
        Config.game.jumpDrive.spoolTime), { 0.6, 0.9, 1.0 })
end

--- Each frame: the charge runs down, and at its end the ship jumps.
---@param dt number
function LimitTheoryRedux:updateJumpDrive(dt)
    local charge = self.driveJump
    if not charge then return end
    if self.docked or self.jump or not self.playerShip then
        self.driveJump = nil
        return
    end
    charge.time = charge.time - dt
    if charge.time > 0 then return end
    self.driveJump = nil
    -- Checked again: the hold or the fit may have changed while it charged
    local ok, reason = self:canDriveJump(charge.to)
    if not ok then
        self:notify("Jump drive: " .. reason, { 1.0, 0.6, 0.4 })
        return
    end
    local units, fuel = self:jumpDriveFuel(charge.to)
    PlayerCargo:get():remove(fuel.id, units)
    self.jumpDriveReady = (self.simTime or 0) + Config.game.jumpDrive.cooldown
    self:startJump({ destination = self.galaxy.systems[charge.to] }, true)
end

--- Jump through a gate: the screen goes dark, this star system goes, and a
--- few frames later (the GPU frees the old system's memory meanwhile) the
--- destination is built and the ship arrives at its gate back.
---@param gate JumpGatePlacement|{ destination: table } (the jump drive: no gate)
---@param drive boolean|nil by the jump drive: the ship arrives in open space
function LimitTheoryRedux:startJump(gate, drive)
    if not self.flow:to(Phase.Jumping, gate.destination and gate.destination.name) then return end
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

    -- The stations left behind go on in the background (GalaxyEconomy)
    local places = self.npcs and self.npcs.places
    for _, dock in ipairs(places and places.docks or {}) do
        if dock.key and dock.entity:isValid() and not PlayerStations.isOwnedKey(dock.key) then
            GalaxyEconomy:record(dock.key, from, dock.label, dock.entity, self.simTime or 0)
        end
    end

    -- Close any map (a course can jump while one is open)
    self:closeMap()

    -- Leaving the scenario's own system ends the scenario: its things go
    -- with the scene (destroyScene runs its teardown), and from the next
    -- system on it is plain travel (finishJump).
    self.jump = { from = from, to = to, name = gate.destination.name, frames = REBUILD_DELAY_FRAMES, drive = drive }
    local destination = self.galaxy.systems[to]
    local levels = Config.game.hostility.levels
    local level = destination and levels[destination.hostility] or levels[1]
    LoadingScreen.show({
        kind = "jump",
        title = (drive and "Jump drive: " or "Jumping to ") .. gate.destination.name,
        subtitle = level and (level.name:upper() .. " SPACE" .. (level.description and ("  ·  " .. level.description) or "")) or nil,
        color = level and level.color or nil,
        minTime = 1.6,
        steps = { "Entering the gate's field", "Crossing", "Forming " .. gate.destination.name, "Arriving" },
    })
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

    if jump.arrival then
        -- A loaded game arriving where it was saved
        self:placeShipFromSave(jump.arrival)
        if not jump.arrival.position then self:placeShipAtArrival(nil) end
    elseif jump.drive then
        -- The jump drive: in the system's open space, no gate
        self:placeShipAtArrival(nil)
    else
        self:placeShipAtArrival(jump.from)
    end
    self.player:setShip(self.playerShip)
    UIViewInGame:setPlayer(self.player)
    self:populateSystem()
    self:collectSceneSystems()

    self.jump = nil
    self.flow:to(Phase.InSystem, "arrived")
    self.jumpFade = nil -- the loading screen fades out over the arrival
    self.systemBanner = SYSTEM_BANNER_TIME
    if jump.arrival then
        self:dockFromSave(jump.arrival)
    else
        self:continueCourse()
    end
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
    -- The controls, the camera, the NPCs and the HUD follow the new ship:
    -- left on the old (destroyed) one, nothing the player pressed moved it
    self.player:setShip(self.playerShip)
    if self.npcs then self.npcs:setPlayer(self.playerShip) end
    UIViewInGame:setPlayer(self.player)
    self:updatePlayerVisibility()
end

--- The frame over an open map: which map, its controls, how to leave.
function LimitTheoryRedux:drawMapFrame()
    if self.mapMode == 0 or self.pauseMenuOpen then return end
    MapFrame.draw(self.mapMode, self.galaxy and 3 or 2, 0, 0, Window:width(), Window:height())
end

--- Close whichever map is open; the ship's controls come back next frame.
--- Open a map by number (1 the 2D system map, 2 the 3D one, 3 the galaxy;
--- 0 closes): M cycles through them, the map's tabs pick one.
---@param mode integer
function LimitTheoryRedux:setMapMode(mode)
    self.mapMode = mode
    self.mapState.enabled = (self.mapMode == 1)
    self.map3DState.enabled = (self.mapMode == 2)
    self.galaxyMapState.enabled = (self.mapMode == 3)

    if self.mapMode == 1 then
        self:openSystemMap()
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

    -- The loading screen covers the jump itself
    if self.jump and LoadingScreen.active() then return end
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
    -- The locked target, under the system line: who, how far, how hurt
    -- The target and the notifications go nearer the middle of the screen
    -- (below the reticle), the standing lines above the action bar
    local centre = {}
    if self.docked then
        local missing, cost = self:hullRepairQuote()
        local repair = missing > 0 and string.format("hull repair %s on the station screen", PlayerWallet.format(cost))
            or "Hull intact"
        table.insert(lines, { text = "Docked  ·  " .. repair .. "  ·  F: undock", color = { 0.6, 0.9, 1.0 } })
    elseif self:isTravelGame() then
        local dock = self:dockInRange()
        if dock then
            table.insert(lines, { text = "F: dock", color = { 0.6, 0.9, 1.0 } })
        end
        if self.driveJump and self.galaxy then
            table.insert(lines, { text = string.format("JUMP DRIVE  ·  %s in %ds  ·  J on the galaxy map cancels",
                self.galaxy.systems[self.driveJump.to].name, math.ceil(self.driveJump.time)), color = { 0.6, 0.9, 1.0 } })
        end
        -- Mining: the laser's cycle, or what is in reach of it
        local job = self.miningJob
        local laser, laserMount = self:miningMount()
        local barSlot = laserMount and PlayerFleet:active()
            and ActionBar.slotOf(PlayerFleet:active(), ActionBar.mountRef(laserMount))
        if job then
            local def = self:miningMount(job.mountId)
            local info = job.rock
            local pct = def and math.floor(100 * job.progress / self:miningCycle(def)) or 0
            table.insert(lines, {
                text = string.format("Mining %s  %d%%  ·  %d left in the rock  ·  hold %s%s",
                    self:knowsRock(info) and info.rock.item or "an unsurveyed rock", pct,
                    math.floor(info.rock.yield), PlayerCargo:describeLoad(),
                    barSlot and string.format("  ·  %d: stop", barSlot) or ""),
                color = { 0.5, 1.0, 0.7 },
            })
        else
            local rock = self.miningTarget
            if not rock and not laser and self.miningNoLaserHint then
                table.insert(lines, { text = "A rock, and nothing fitted to cut it: a Mining Laser goes on a weapon mount",
                    color = { 1.0, 0.7, 0.3 } })
            end
            if rock and laser then
                local what = self:knowsRock(rock)
                    and string.format("%s (%d left)", rock.rock.item, math.floor(rock.rock.yield))
                    or "an unsurveyed rock"
                local scanner, scannerSlot = self:fittedAbility("surveyScan")
                local scan = (not self:knowsRock(rock) and scanner)
                    and string.format("  ·  survey it from the action bar") or ""
                table.insert(lines, {
                    text = string.format("In reach: %s  ·  %s%s", what,
                        barSlot and string.format("%d: mine", barSlot) or "put the mining laser on the action bar",
                        scan),
                    color = { 0.6, 0.9, 1.0 },
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
        table.insert(centre, { text = message.text, color = message.color, alpha = math.min(1, message.time) })
    end
    -- Above the action bar (bottom centre: its slots and margin, at the
    -- HUD's scale), growing upward
    local hudScale = math.max(0.7, math.min(1.3, h / 1080)) * GameState.ui.hudScale
    local bottom = h - (26 + 64 + 18) * hudScale
    local top = bottom - #lines * 20
    for i, line in ipairs(lines) do
        DrawEx.TextAlpha(font, line.text, 14, 0, top + (i - 1) * 20, w, 18,
            line.color[1], line.color[2], line.color[3], 0.9 * (line.alpha or 1), 0.5, 0.5)
    end
    -- The target and the notifications: a block from just below the middle
    local centreTop = math.min(h * 0.60, top - #centre * 20 - 10)
    for i, line in ipairs(centre) do
        DrawEx.TextAlpha(font, line.text, 15, 0, centreTop + (i - 1) * 21, w, 19,
            line.color[1], line.color[2], line.color[3], 0.95 * (line.alpha or 1), 0.5, 0.5)
    end

    -- Signatures: the nearest few marked on screen, or at its edge
    if self:isTravelGame() and not self.docked then self:drawSignatureMarkers(w, h, font) end

    -- The virtual stick (shipFlight.chaseSteering = "virtual"): where the
    -- mouse has the stick, about the centre, and the dead zone round it
    if self.player and self.player:isPiloting() and not self.player.mouseSteeringOff
        and (Config.game.shipFlight.chaseSteering or "virtual") == "virtual"
        and not require("Modules.Cameras.FreeLook").held
        and not AutoPilotSystem:isActive(self.playerShip) then
        local sx, sy, dead = ShipFlightSystem:stick(self.playerShip)
        local radius = h * (Config.game.shipFlight.stickRadius or 0.22)
        local cx, cy = w / 2, h / 2
        DrawEx.Ring(cx, cy, math.max(4, dead * radius), { r = 0.6, g = 0.85, b = 1.0, a = 0.35 }, false)
        DrawEx.Ring(cx, cy, radius, { r = 0.6, g = 0.85, b = 1.0, a = 0.10 }, false)
        local live = math.sqrt(sx * sx + sy * sy) >= dead
        local px, py = cx + sx * radius, cy - sy * radius
        if live then
            DrawEx.Line(cx, cy, px, py, { r = 0.6, g = 0.85, b = 1.0, a = 0.30 }, false)
        end
        DrawEx.Point(px, py, 5, live and { r = 0.5, g = 1.0, b = 0.75, a = 0.9 }
            or { r = 0.6, g = 0.85, b = 1.0, a = 0.6 })
    end

    -- Credits, the hold and the standings are in their windows (I, U, Y);
    -- the modules are on the action bar
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
            LoadingScreen.draw()
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
            LoadingScreen.draw()
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
            LoadingScreen.draw()
        end)
    end
end

---@param data EventData
function LimitTheoryRedux:onInput(data)
    -- The flow and the flags it stands for agree (logged once if not)
    if self.flow then self.flow:check(self) end
    -- A load waits a few frames between the old scene going and the saved one
    -- being built (loadGame); nothing else happens meanwhile
    if self.pendingLoad then
        self.pendingLoad.frames = self.pendingLoad.frames - 1
        if self.pendingLoad.frames <= 0 and LoadingScreen.ready() then self:finishLoadGame() end
        return
    end
    -- A new game from the menu: built once its loading screen has been seen
    if self.pendingStart then
        self.pendingStart.frames = self.pendingStart.frames - 1
        if self.pendingStart.frames <= 0 and LoadingScreen.ready() then
            local pending = self.pendingStart
            self.pendingStart = nil
            self:startGame(pending.seed, pending.scenario)
            LoadingScreen.finish()
        end
        return
    end

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
        if self.jump.frames <= 0 and LoadingScreen.ready() then
            self:finishJump()
            LoadingScreen.finish()
        end
        return
    end

    if not self.playerShip then return end
    local dt = data:deltaTime()

    -- Escape first puts away what is open (dismissOpenUI), then toggles the
    -- pause menu (Return to Game / Controls / Back to Main Menu / Exit); from
    -- the Controls screen it goes back to the pause menu.
    if Input:isPressed(ApplicationBindings.Escape) then
        if self.controlsOpen then
            self:closeControls()
        elseif self.settingsOpen then
            -- Back, asking about unsaved changes first
            require("UI.HmGui.Views.MainMenu.Settings").back()
        elseif self.saveSlotsMode then
            self:closeSaveSlots()
        elseif self.mapMode ~= 0 and not self.pauseMenuOpen then
            self:closeMap()
        elseif self.pauseMenuOpen then
            self:closePauseMenu()
        elseif not self:dismissOpenUI() then
            -- Nothing open to put away: the game menu
            self:openPauseMenu()
        end
    end
    if self.pauseMenuOpen then return end
    -- Typing in a field (an order's units): the keys are the field's
    if Gui:hasActiveInput() then return end
    -- ~: the debug menu
    if Input:isPressed(Button.KeyboardBackquote) then self:toggleDebugMenu() end

    GeneralActions.CycleMapMode:update(dt)
    GeneralActions.AutoPilotToggle:update(dt)
    GeneralActions.Regenerate:update(dt)
    GeneralActions.ReloadShaders:update(dt)
    GeneralActions.Jump:update(dt)
    GeneralActions.Dock:update(dt)
    GeneralActions.Cloak:update(dt)
    GeneralActions.Overview:update(dt)
    GeneralActions.Inventory:update(dt)
    GeneralActions.Character:update(dt)
    GeneralActions.Standings:update(dt)
    GeneralActions.TargetNearest:update(dt)
    GeneralActions.QuickSave:update(dt)
    GeneralActions.QuickLoad:update(dt)
    for slot, binding in ipairs({ GeneralActions.Module1, GeneralActions.Module2,
                                  GeneralActions.Module3, GeneralActions.Module4,
                                  GeneralActions.Module5, GeneralActions.Module6,
                                  GeneralActions.Module7, GeneralActions.Module8 }) do
        binding:update(dt)
        if binding:isPressed() and not self.docked then
            self:useAction(slot)
        end
    end

    if GeneralActions.CycleMapMode:isPressed() then
        -- 2D map, 3D map, then the galaxy map when there is a galaxy
        self:setMapMode((self.mapMode + 1) % (self.galaxy and 4 or 3))
    elseif self.mapMode ~= 0 and Input:mouse():isPressed(MouseControl.Left) then
        -- A click on a tab of the map's top bar opens that map
        local pos = Input:mouse():position()
        local tab = MapFrame.tabAt(pos.x, pos.y)
        if tab and tab ~= self.mapMode then self:setMapMode(tab) end
    end

    if self.mapClosedFrame and self.mapMode == 0 then
        self.mapClosedFrame = false
        self.player:setMode(self.player:getMode())
    end

    -- The jump drive charges with a map open too (it is set from the galaxy map)
    self:updateJumpDrive(dt)

    if self.mapMode > 0 then
        local ctrl = self.player:getActiveController()
        if ctrl and ctrl:isEnabled() then ctrl:disable() end
        self.player:setInputBlocked(true)

        if self.mapMode == 3 then
            GalaxyMap:updateInput(self.galaxyMapState, dt)

            -- J: the jump drive to the selected system
            if GeneralActions.Jump:isPressed() and self.galaxyMapState.selectedId then
                self:engageJumpDrive(self.galaxyMapState.selectedId)
            end
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

    if GeneralActions.Jump:isPressed() and not self.docked and self.mapMode == 0 then
        local gate = self:gateInRange()
        if gate then self:startJump(gate) end
    end

    for _, w in ipairs({ { GeneralActions.Inventory, "inventory" }, { GeneralActions.Character, "character" },
                         { GeneralActions.Standings, "standings" } }) do
        if w[1]:isPressed() and self:overviewAvailable() and self:isTravelGame() then self:toggleWindow(w[2]) end
    end

    if GeneralActions.Overview:isPressed() and self:overviewAvailable() then
        self:setOverview(not self.overviewShown)
    end

    if GeneralActions.TargetNearest:isPressed() and self:isTravelGame() and not self.docked then
        self:targetNearestHostile()
    end

    -- F4 quicksaves, Ctrl+F4 quickloads (checked first: F4 alone is down too)
    local ctrl = Input:isDown(Button.KeyboardControlLeft) or Input:isDown(Button.KeyboardControlRight)
    if GeneralActions.QuickLoad:isPressed() then
        self:loadGame("quicksave")
        return
    elseif GeneralActions.QuickSave:isPressed() and not ctrl then
        self:saveGame("quicksave")
    end

    if GeneralActions.Dock:isPressed() and self:isTravelGame() then
        if self.docked then
            self:undockPlayer()
        else
            local dock, refused = self:dockInRange()
            if dock then
                self:dockPlayer(dock)
                self:autosave()
            elseif refused then
                self:notify(Factions.name(refused.faction) .. " refuse you docking.", { 1.0, 0.4, 0.3 })
            end
        end
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
    self:syncActionBar()
    self:updateSensors(dt)
    self:updateMining(dt)
    AbilitySystem:update(self.playerShip, dt)
    -- A ship the refit screen asked for: the rebuild happens here, not inside
    -- the screen's own draw
    self:processShipChange()
    -- The overview: its list, the cursor it holds, and what it set going
    self:updateOverview(dt)
    self.simTime = (self.simTime or 0) + dt
    -- The other systems' markets, in the background
    GalaxyEconomy:update(dt, self.simTime, self.currentSystemId or 1)
    -- The player's shields recharge (DefenseComponent:update had no caller)
    local playerDefense = self.playerShip:get(ConstructComponents.Defense)
    if playerDefense and not self.docked then playerDefense:update(dt) end
    -- Debug: nothing hurts the ship
    if self.debugGod then self:debugRepair() end
    Profiler.End()
    -- NPC ships fly (kinematic) before the physics step, like scenario things
    Profiler.Begin('Sim.NPCs')
    self.npcs:update(dt)
    self:updateOutpostDefenses(dt)
    self:updatePlayerForces(dt)
    self:updateLoot(dt)
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
    if not self.flow:to(Phase.Rebuilding, "regenerate") then return end
    self:destroyScene()
    UIViewInGame:setPlayer(nil) -- no ship for the HUD meanwhile
    self.rebuildInFrames = REBUILD_DELAY_FRAMES
end

--- The second half of `regenerate`: build the scene again.
function LimitTheoryRedux:finishRegenerate()
    self.rng = RNG.Create(self.seed)
    self:resetGalaxy()
    self:buildScene()
    self.flow:to(Phase.InSystem, "rebuilt")
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
