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

    --- The overview: what is in the system, nearest first. Always on screen
    --- in brief; expanded, the cursor is free for it and the mouse does not
    --- steer.
    ---@type ActionBinding
    Overview = ActionBinding({
        label = "Overview: expand / shrink", group = "Map",
        keyboard = { Control.Single(Button.KeyboardR) },
    }),

    --- The action bar's slots: whatever is in a slot (an active module, the
    --- mining laser) is used on its key (LimitTheoryRedux:useAction)
    ---@type ActionBinding
    Module1 = ActionBinding({
        label = "Action bar slot 1", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey1) },
    }),

    ---@type ActionBinding
    Module2 = ActionBinding({
        label = "Action bar slot 2", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey2) },
    }),

    ---@type ActionBinding
    Module3 = ActionBinding({
        label = "Action bar slot 3", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey3) },
    }),

    ---@type ActionBinding
    Module4 = ActionBinding({
        label = "Action bar slot 4", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey4) },
    }),

    ---@type ActionBinding
    Module5 = ActionBinding({
        label = "Action bar slot 5", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey5) },
    }),

    ---@type ActionBinding
    Module6 = ActionBinding({
        label = "Action bar slot 6", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey6) },
    }),

    ---@type ActionBinding
    Module7 = ActionBinding({
        label = "Action bar slot 7", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey7) },
    }),

    ---@type ActionBinding
    Module8 = ActionBinding({
        label = "Action bar slot 8", group = "Flight",
        keyboard = { Control.Single(Button.KeyboardKey8) },
    }),

    --- The windows: each opens and closes on its key; while one is open the
    --- cursor is free (UI/HmGui/Views/Gameplay/WindowsPanel.lua)
    ---@type ActionBinding
    Inventory = ActionBinding({
        label = "Inventory (hold and credits)", group = "General",
        keyboard = { Control.Single(Button.KeyboardI) },
    }),

    ---@type ActionBinding
    Character = ActionBinding({
        label = "Character (ship, fit, holdings)", group = "General",
        keyboard = { Control.Single(Button.KeyboardU) },
    }),

    ---@type ActionBinding
    Standings = ActionBinding({
        label = "Faction standings", group = "General",
        keyboard = { Control.Single(Button.KeyboardY) },
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
