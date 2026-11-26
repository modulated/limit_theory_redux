local ActionBinding = require('Input.ActionBinding')
local Control = require('Input.Control')

--- General actions shared across game states (camera cycling, map, autopilot, debug)
local GeneralActions = {
    ---@type ActionBinding
    CycleCamera = ActionBinding({
        label = "Cycle camera", group = "Camera",
        keyboard = { Control.Single(Button.KeyboardC) },
        gamepad = { Control.Single(Button.GamepadSelect) },
    }),

    ---@type ActionBinding
    CycleMapMode = ActionBinding({
        label = "Open / switch map (2D, 3D, galaxy)", group = "Map",
        keyboard = { Control.Single(Button.KeyboardM) },
    }),

    ---@type ActionBinding
    AutoPilotToggle = ActionBinding({
        label = "Autopilot / set course / cancel", group = "Map",
        keyboard = { Control.Single(Button.KeyboardN) },
    }),

    ---@type ActionBinding
    Jump = ActionBinding({
        label = "Jump through a nearby gate", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardJ) },
    }),

    ---@type ActionBinding
    Dock = ActionBinding({
        label = "Dock at a nearby station / undock", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardF) },
    }),

    ---@type ActionBinding
    Repair = ActionBinding({
        label = "Repair the hull (docked; costs credits)", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardR) },
    }),

    --- Mining: held down, not tapped (the laser runs while the key is down)
    ---@type ActionBinding
    Mine = ActionBinding({
        label = "Mine the nearest asteroid (hold)", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardE) },
    }),

    ---@type ActionBinding
    Cloak = ActionBinding({
        label = "Cloak on / off", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardX) },
    }),

    --- Save into the quicksave slot.
    ---@type ActionBinding
    QuickSave = ActionBinding({
        label = "Quicksave", group = "General",
        keyboard = { Control.Single(Button.KeyboardF4) },
    }),

    --- Load the quicksave.
    ---@type ActionBinding
    QuickLoad = ActionBinding({
        label = "Quickload", group = "General",
        keyboard = {
            Control.Combo(Button.KeyboardControlLeft, Button.KeyboardF4),
            Control.Combo(Button.KeyboardControlRight, Button.KeyboardF4),
        },
    }),

    --- Lock the nearest hostile ship; again, the next nearest.
    ---@type ActionBinding
    TargetNearest = ActionBinding({
        label = "Target nearest hostile (again: next)", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardTab) },
    }),

    --- The overview: what is in the system, nearest first. While it is open
    --- the cursor is free for it and the mouse does not steer.
    ---@type ActionBinding
    Overview = ActionBinding({
        label = "Overview on / off", group = "Map",
        keyboard = { Control.Single(Button.KeyboardO) },
    }),

    --- The four module slots: a fitted active module fires on its key
    --- (Modules/Constructs/Systems/AbilitySystem.lua)
    ---@type ActionBinding
    Module1 = ActionBinding({
        label = "Fire the module in slot 1", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey1) },
    }),

    ---@type ActionBinding
    Module2 = ActionBinding({
        label = "Fire the module in slot 2", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey2) },
    }),

    ---@type ActionBinding
    Module3 = ActionBinding({
        label = "Fire the module in slot 3", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey3) },
    }),

    ---@type ActionBinding
    Module4 = ActionBinding({
        label = "Fire the module in slot 4", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey4) },
    }),

    ---@type ActionBinding
    ReloadShaders = ActionBinding({
        label = "Reload shaders", group = "Debug",
        keyboard = { Control.Single(Button.KeyboardF5) },
    }),

    --- Render info overlay (Application): Ctrl+Shift+F3, either Ctrl and either Shift
    ---@type ActionBinding
    RenderInfoOverlay = ActionBinding({
        label = "Render info", group = "Debug",
        keyboard = {
            Control.Combo(Button.KeyboardControlLeft, Button.KeyboardShiftLeft, Button.KeyboardF3),
            Control.Combo(Button.KeyboardControlLeft, Button.KeyboardShiftRight, Button.KeyboardF3),
            Control.Combo(Button.KeyboardControlRight, Button.KeyboardShiftLeft, Button.KeyboardF3),
            Control.Combo(Button.KeyboardControlRight, Button.KeyboardShiftRight, Button.KeyboardF3),
        },
    }),

    ---@type ActionBinding
    Regenerate = ActionBinding({
        label = "Regenerate system", group = "Debug",
        keyboard = { Control.Single(Button.KeyboardB) },
    }),
}

return GeneralActions
