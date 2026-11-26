# TODO

Everything still open for Limit Theory Redux, in one place. Collected on 2026-11-25 from
`ai/ideas.md`, the design docs under `doc/engine/`, `ai/*.md` and the `TODO`/`FIXME` comments in
`engine/` and `script/` (except `script/Legacy/`, `script/jit/` and `_outdated` tests). Each item was
checked against the code; finished items are left out (see [Done since the plans were
written](#done-since-the-plans-were-written)).

When you finish an item, delete it here. When you find new work, add it here, not in a new plan doc.

## 1. Gameplay

In order: each step builds on the one before. The design for 1-4 is in `ai/ideas.md` §3.

1. **Routes and waypoints.** Autopilot only flies to one target. Add a `NavigationComponent`
   (ordered waypoints, current leg, route state) and a `NavigationSystem` that feeds
   `AutoPilotSystem` one leg at a time. On `SystemMap`/`SystemMap3D`, shift-click appends a
   waypoint and the route is drawn with an ETA per leg. Add a `ClearRoute` binding. Pure Lua.
2. **Docking** (started). F docks at a station in range (repair), NPC traders and miners
   dock on their runs (Legacy DockAt/Undock). Still to do: docking ports and an approach
   path (ships now appear inside the station), a station screen, docking as a route
   waypoint.
3. **Travel between star systems.** The universe generates many systems but only one is ever
   simulated.
   - Jump gates (`JumpGateEntity` + `JumpLinkComponent`) and a gate graph built at generation
     (k-nearest links plus a spanning tree, so every system is reachable).
   - Switching the active system: despawn the current system's meshes and bodies, keep the
     entity tree, spawn the next one, behind a transit or loading screen.
   - Route planning across systems (Dijkstra/A* over the gate graph, in Lua).
   - A galaxy map, as a third state of `CycleMapMode`.
4. **Obstacle avoidance.** Autopilot flies straight lines and can fly through a planet. Expose
   `Physics::shape_cast`/`shape_overlap` (`engine/lib/phx/src/physics/physics.rs`) to Lua, then
   steer around bodies' bounding spheres. Optional: smooth routes with a 3D Catmull-Rom or
   Bézier curve.
5. **Save and load.** Nothing is saved. Start with the universe seed and player state
   (`script/Types/GameState.lua:123` has a placeholder for world state).
6. **Economy.** Stations hold stock, price it by scarcity, run the production chains against it
   and trade with the player on the docked station screen; the player has a hold, a mining laser
   and credits; NPC miners deliver their ore. Legacy's economy is deleted. The item list, the
   chains and what is left are in [doc/items.md](doc/items.md). Still to do:
   - [ ] NPC traders that haul goods between stations instead of waiting at a stop, trading on the
         order books (they are the other side of the player's orders).
   - [ ] Workers are only hands: never paid, never hired, their cargo irrelevant. Wages and a
         labour market would make a station's crew a real cost.
   - [x] Equipment and hulls that can be fitted and flown, not just bought (0.2.0: weapons go in
         mounts, modules in slots, actives on the number keys, hulls bought and switched into at a
         station, and every part has a recipe). Left over: modules that extend market reach
         (`market.remoteJumps` is still a flat 3), and fittings as loot from a kill.
   - [ ] Biomass has no source, so the hydrocarbon chain runs on imports.
   - [ ] Saving the hold, the wallet, station stock and production progress.
   - [ ] Balance: tune with `luajit tools/economy-sim.lua --seeds 8 --prospector --trader`
         (it runs the economy headless). Income swings more than tenfold between systems
         depending on whether the local refineries want the local ore; mining and hauling pay
         about 1,600 and 900 credits an hour in a median system.
7. **NPCs and combat** (started: `script/Modules/NPC/`). Security, trader and pirate ships
   by each system's hostility, flying jobs ported from Legacy (Patrolling, Marauding,
   Transport, Think; actions MoveTo, Wait, Attack, Flee, LeaveSystem); the player flies an
   armed gunship. Still to do:
   - [ ] Confirm the gunship recipe builds and the fights play well (untested at the time).
   - [ ] Manual fire and target lock for the player (turrets only fire automatically, whatever is
         fitted in their mounts).
   - [ ] CriminalThink's black-market jobs (needs the economy).
   - [ ] Prospecting scanner: the Survey Scanner module reads a rock (`AsteroidOre.ofEntity`) on a
         key, but the HUD still names the ore as soon as a rock is in reach, so the module tells
         you nothing new. The HUD should go quiet without one, and the scanner should reach
         further than the mining laser. See [doc/items.md](doc/items.md).
   - [ ] Legacy's dust clouds (only the flecks are ported; the clouds need their texture
         pass and shader converted).
   - [ ] Reputation from more than kills and hits (escorting, trading) once there is more
         to do; the player can't attack neutral ships yet, so standing mostly rises.
   - [ ] Credits only come from bounties, trading and mining sales; they go on hull repairs,
         factory leases, fittings and hulls. Insurance, fuel and ammunition are the obvious sinks
         still missing.
   - [ ] Armor: DefenseComponent has an armor value no damage path reads yet, so Armour Plating's
         armour does nothing (its hull and thrust changes do).
   - [ ] Jobs chosen by payout and threat, as Legacy's Think did, once there is an economy.
   - [ ] Respawn or a way back after the player's ship is destroyed (now: GAME OVER).
8. **Scenario list.** The New Game test-seed list is a stopgap
   (`script/UI/HmGui/Views/MainMenu/Newgame.lua:15`).

## 2. Retiring `script/Legacy/`

132 of the 169 files are gone (the economy, the universe and star-system simulation, the Jobs and
Actions trees, the NPC elements, the old overlay, command view, menus, cameras and controls, and
the dead `Ship_Creation` view, `LoadingScreen` page and `_outdated` test states that still reached
them). 37 files are left, all of them live code:

- [ ] **The procedural generators** are the big one: `Legacy.Systems.Gen.{ShipBasic, ShipCapital,
      ShipFighter, StationOld, Primitive, Boxes, GenUtil, MeshUtil, MathUtil, UVMap}` with
      `ShapeLib/` and `ShipLib/`, used by `script/Modules/Constructs/Managers/Generators/` and by
      `SolarSystemVisualizer`. Port the shape library and the hull generators into
      `script/Shared/Generation/`.
- [ ] **`Legacy.Systems.Events`** (`EventManager`, `EventListener`, `OldEvent`) is still loaded by
      `script/Init.lua` as the `Core.Events` namespace; the Rust `EventBus` replaces it.
- [ ] **`Legacy.Systems.SFX.SoundManager`** is required by `LTheoryRedux`, `Types/SFXObject.lua`,
      `Types/MusicObject.lua` and the audio test.
- [ ] **`Legacy.Systems.Files.InitFiles`** (user.ini and the save folders) and
      `Legacy.Systems.Controls.Control` (the binding base the UI and application bindings use).
- [ ] **The leftovers**: `GameObjects/{Entity, Material, LegacyEntityComponent}`,
      `Entities/Effects/Pulse` (the weapon pulse light), `Systems/Camera/Camera`.

- [ ] `PlanetaryRingMotionComponent` and `CloudMotionComponent` subscribe to events themselves;
      move that logic into a system (`script/Modules/CelestialObjects/Components/Simulation/`).
- [ ] Move `AutoNav`, `ToggleHUD` and `ToggleSensors` to `ShipBindings.lua`
      (`script/States/ApplicationBindings.lua:14-17`).

## 3. Performance

- [x] **WeaponSystem Lua hot path** (`doc/engine/lua-workers.md`, step plan A; L1 in
      `doc/engine/parallel-recording.md`). Aim-point sampling is a Rust `TargetSurface`
      (triangles, normals and a cumulative-area CDF built once), the tracking config is cached
      per turret, and the JIT is on again on macOS ARM64. Left: a batched per-battery
      line-of-sight call, and re-profiling a Lawless combat scene to record the new numbers.
- [x] **Permanent per-handler profiler scopes** in `EventBus:subscribe`
      (`Lua.<Subscriber>.<Event>`) plus `Sim.*` scopes per system in `LTheoryRedux:onStateSim`,
      so gameplay Lua shows up by system (`doc/engine/parallel-recording.md` §4.2).
- [ ] **Worker-based ship generation**, only if a spawn measures over ~20 ms
      (`doc/engine/lua-workers.md`, step plan B, steps 1 and 3-6).
- [ ] **Earlier wgpu submit (P1):** submit after the last scene pass, not only at
      `SwapBuffers`, if GPU timing shows the GPU idling at the start of the frame.
- [ ] **Parallel wgpu pass encoding (R1):** deferred until render-thread CPU time exceeds ~70%
      of the frame (`doc/engine/parallel-recording.md` §5).
- [ ] **Mesh batching:** merge LOD meshes into one vertex and index buffer
      (`engine/lib/phx/src/render/lod_mesh.rs:4`); 16-bit indices where they fit.
- [ ] **HmGui:** skip layout and drawing of widgets outside the screen or a clipped container;
      reuse unchanged widgets instead of clearing all layers
      (`engine/lib/phx/src/ui/hmgui/gui.rs:240,279,287,340`, `container.rs:514`,
      `widget.rs:345`).
- [ ] **Text:** a texture per large text block costs memory (`hmgui/text/text_data.rs:285`).
- [ ] **Octree:** drop the `Option<Box<>>` nodes (`engine/lib/phx/src/math/octree.rs:4`).
- [ ] **Distribution sampling** is O(n); use the alias method (`script/Core/Util/Distribution.lua:8`).
- [ ] **glam `scalar-math`:** check whether SIMD can be turned on without breaking the Lua FFI
      struct layouts.

## 4. Engine robustness

- [ ] **Contain panics at the FFI boundary.** Make `luajit-ffi-gen` wrap generated `extern "C"`
      bodies in `catch_unwind`, log the panic and return a default. One generator change covers
      every binding.
- [ ] **Fewer `unwrap()`s and panics** in `phx`, worst first: `physics/` (raw rigid-body
      pointers, `rigid_body.rs:61,214`), `render/`, `engine/task_queue/`. Return `Result`s;
      `render/mesh.rs:508` asks for an error enum.
- [ ] **Remove `#[allow(unsafe_code)]`** where marked `TODO: remove`: `physics/rigid_body.rs`,
      `physics/trigger.rs`, `render/mesh.rs:184,551`, `render/ui_renderer/layer.rs:151`,
      `system/mem_pool.rs`, `system/memory.rs`, `error.rs:53`, `engine/engine.rs:67`,
      `engine/task_queue/lua_worker.rs:40,113`, `ui/hmgui/mod.rs:54`, and the
      `luajit-ffi-gen` tests.
- [ ] **Bad indices return silent defaults** in input state (`input/button_state.rs`,
      `input/axis_state.rs`, `input/devices/gamepad/state.rs:241-283`); decide on errors or
      warnings.
- [ ] **Hanging worker threads** have no handling (`engine/task_queue/worker_instance.rs:67`).
- [ ] **Intersection tests** need proper epsilons and the parallel/degenerate cases
      (`engine/lib/phx/src/math/intersect.rs`); `math/mod.rs:57,79` have conditions that are
      always true or false.
- [ ] **BSP:** soft abort on bad meshes, better split heuristics
      (`render/bsp.rs:27,355,663`, `render/bsp_build.rs:123-260`).
- [ ] **Trigger offsets** go stale when a child moves (`physics/trigger.rs:67`).
- [ ] **Unimplemented window and touch events** in `engine/main_loop.rs:180-251`.
- [ ] **Window position:** `Automatic` and `Centered` do not work (`window/mod.rs:215`).
- [ ] **Input:** only one device per type except gamepads (`input/mod.rs:37`).
- [ ] **Lua error handler** does not print locals (`script/Core/Util/ErrorHandler.lua:94`).
- [ ] **Lua FFI `Type` hacks** (`script/Core/CFFI/Type.lua:50,176`) and
      `PayloadConverter` cache slots that are never reused (`script/Core/Util/PayloadConverter.lua:4,166`).
- [ ] **MeshStorage** cleanup is unverified (`script/Core/ECS/MeshStorage.lua:57`).

## 5. Rendering (wgpu)

Left over from the wgpu port (`doc/engine/wgpu-migration-gaps.md`, "Left after S11", and
`doc/engine/render-api-v2.md`, "What is not covered").

- [ ] `Tex2D::deep_clone` (`CopyTexture2DFromFramebufferByResource`) is a logged no-op. Nothing
      active calls it.
- [ ] Depth textures cannot be read back.
- [ ] No multisampling; `MirrorClamp` behaves as clamp-to-edge; wireframe needs
      `POLYGON_MODE_LINE`.
- [ ] The 16F fallback for adapters without `FLOAT32_FILTERABLE`/`FLOAT32_BLENDABLE` has never
      been run.
- [ ] Effect shaders that write only `outColor` leave other MRT attachments undefined.
- [ ] Procedural shaders built on `fract(sin(x) * 4137)` (planet ring, moon craters, nebulae)
      change with the compiler's `sin`; replace with an integer hash.
- [ ] The window renders to an offscreen backbuffer and blits at present: one extra full-screen
      copy per frame.
- [ ] The stats dashboard's per-category timing is not collected on wgpu (gap 17).
- [ ] Untested: a lost or outdated swapchain, resizing with a pass open, shader hot reload
      (`tools/render_validation/hot_reload_probe.py` not run), the `GenerateMips` grow path on
      cube and 3D textures.
- [ ] 3D layer attachments use the whole volume view (`depth_slice`,
      `doc/engine/render-api-v2.md` S2 notes).
- [ ] Text rendering works around a 1-pixel shift from `swash`/`zeno`
      (`ui/hmgui/text/text_render.rs:19`, `text_data.rs:32`).
- [ ] UI font caching (`script/Render/Cache.lua:112`).

## 6. Build, CI and tooling

- [ ] **Confirm on PR #1's CI:** the macOS bundle's ad-hoc signature is valid.
- [ ] **Fast CI gate:** one Linux job running `cargo check`, clippy and the
      `luajit-ffi-gen` tests before the three platform builds.
- [ ] **Generated-bindings drift check:** fail CI if building `phx` changes
      `engine/lib/phx/script/ffi_gen` or `meta/`.
- [ ] **Intel Macs:** CI builds arm64 only. Build `x86_64-apple-darwin` too and combine the two
      with `lipo`, or document that Intel Macs are unsupported.
- [ ] **Cargo manifest warnings:** unused `ltr` workspace dependency, `ltr`'s unused `phx`
      dependency (it links `libphx` itself), `luajit-ffi-gen`'s unused `internal` dependency,
      and `engine/lib/internal` missing `[lints] workspace = true`.
- [ ] **Duplicate font crates:** `parley` 0.13 and `swash` 0.2 need different `skrifa`,
      `read-fonts` and `font-types` versions. Unify when `swash` accepts `skrifa` 0.49.
- [ ] **Release CPU target:** decide whether shipped x86_64 builds should target `x86-64-v2`.
- [ ] **Tests for pure logic:** `math/` (intersections, octree, frustum planes) and golden
      tests for the FFI generator's Lua output.
- [ ] **Generator TODOs:** enum `repr` from `#[repr(...)]`, copyable-type marking, the
      `OUT_DIR` workaround (`engine/lib/luajit-ffi-gen/src/`).
- [ ] **HmGui tests** are disabled on Windows and macOS (`engine/lib/phx/src/ui/hmgui/mod.rs:30`).
- [ ] **Split large files:** `render/bsp.rs`, `ui/hmgui/gui.rs`, the wgpu executor.
- [ ] **Old UI code** (`script/UI/*.lua`, not HmGui) has open TODOs for focus tracking,
      disabled containers and scroll views (`State.lua:111,196,200`, `ScrollView.lua:78,137`,
      `Panel.lua:89`, `NavGroup.lua:50`, `Slider.lua:30`, `Collapsible.lua:50`,
      `Canvas.lua:47`). Port the remaining users to HmGui or drop it.

## Done since the plans were written

For reference, so these don't get re-added:

- OpenGL removed; wgpu is the only renderer, on the render thread (`doc/engine/render-thread.md`).
- Render API v2 steps S2-S11, the glyph atlas and GPU timing per pass (G1).
- Belt cull in Rust with rayon (`render/instance_field.rs`, D1).
- Lua worker plumbing fixes (`doc/engine/lua-workers.md` step plan B, step 2).
- The black main-game background (`ai/legacy_background_rendering_bug.md`): `LTheoryRedux`
  no longer uses the Legacy `GameView` path.
- One audio crate: `rodio` removed, `kira` kept (PR #1).
- CI cancels superseded PR runs; release packages include `doc/` (PR #1).
