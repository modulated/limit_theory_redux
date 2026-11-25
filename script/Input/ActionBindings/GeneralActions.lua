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
    Cloak = ActionBinding({
        label = "Cloak on / off", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardX) },
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
