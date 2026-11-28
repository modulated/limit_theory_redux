--- Two actions on one key do both, or one of them never: Mine and Roll were
--- both on E, so mining rolled the ship. This finds every key (or chord) that
--- more than one action uses *in the same context* -- the sets of bindings
--- that are live at the same time -- and is the check a rebinding screen asks
--- before it accepts a key (`BindingConflicts.whoUses`).
---
--- The game checks at start-up and logs each clash (`BindingConflicts.report`);
--- the Controls screen marks them.
---@class BindingConflicts
local BindingConflicts = {}

--- The app-level keys Application.lua handles in every state (the rest of
--- ApplicationBindings belongs to Legacy views the game never opens).
local LIVE_APP_KEYS = {
    "Escape", "ToggleProfiler", "Screenshot", "TimeAccel", "ToggleMetrics",
    "Pause", "ToggleHUD", "ToggleWireframe",
}

--- Which binding tables are live together. Flight and the free camera are
--- separate (the free camera moves the camera, not the ship), as is the map.
--- App-level keys (pause, screenshot, debug toggles) are live everywhere.
---@return table<string, table[]> context name -> { { name, table, isRaw } }
local function contexts()
    local Ship = require("Input.ActionBindings.ShipActions")
    local General = require("Input.ActionBindings.GeneralActions")
    local Camera = require("Input.ActionBindings.CameraActions")
    local Map = require("Input.ActionBindings.MapActions")
    local App = require("States.ApplicationBindings")
    local live = {}
    for _, key in ipairs(LIVE_APP_KEYS) do live[key] = App[key] end
    local app = { name = "App", table = live, raw = true }
    return {
        Flight = { { name = "Ship", table = Ship }, { name = "General", table = General }, app },
        ["Free camera"] = { { name = "Camera", table = Camera }, { name = "General", table = General }, app },
        Map = { { name = "Map", table = Map }, { name = "General", table = General }, app },
    }
end

--- The chords one binding of an action uses: a key, a pair's two keys, a
--- combo's keys together. Each as a stable string ("57", "41+70").
---@param bind table|integer a Control (Input/Control.lua) or a raw button
---@param out string[]
local function chordsOf(bind, out)
    if type(bind) == "number" then
        out[#out + 1] = tostring(bind)
        return
    end
    if type(bind) ~= "table" then return end
    local kind = bind.type
    if kind == Enums.ControlType.Single then
        out[#out + 1] = tostring(bind.key)
    elseif kind == Enums.ControlType.Pair then
        if type(bind.positive) == "number" then out[#out + 1] = tostring(bind.positive) end
        if type(bind.negative) == "number" then out[#out + 1] = tostring(bind.negative) end
    elseif kind == Enums.ControlType.Combo then
        local keys = {}
        for _, key in ipairs(bind.keys or {}) do
            -- A button held while the mouse moves is a drag gesture, not a
            -- key (the orbit camera's right-drag): it clashes with nothing
            if type(key) ~= "number" then return end
            keys[#keys + 1] = key
        end
        table.sort(keys)
        for i, key in ipairs(keys) do keys[i] = tostring(key) end
        if #keys > 0 then out[#out + 1] = table.concat(keys, "+") end
    end
    -- Axes and mouse motion are not keys
end

--- Every (chord, action) a context uses.
---@param sources table[]
---@return table<string, string[]> chord -> actions using it ("Ship.Roll")
local function usage(sources)
    local byChord = {}
    local function add(chord, who)
        local list = byChord[chord] or {}
        for _, existing in ipairs(list) do
            if existing == who then return end
        end
        list[#list + 1] = who
        byChord[chord] = list
    end
    for _, source in ipairs(sources) do
        for name, binding in pairs(source.table) do
            local who = source.name .. "." .. name
            if source.raw then
                -- ApplicationBindings: plain buttons (and a few helper tables)
                if type(binding) == "number" then add(tostring(binding), who) end
            elseif type(binding) == "table" and binding.deviceBindings
                and not binding.deviceBindings.hidden then
                for _, device in ipairs({ "keyboard", "mouse", "gamepad" }) do
                    for _, bind in ipairs(binding.deviceBindings[device] or {}) do
                        local chords = {}
                        chordsOf(bind, chords)
                        for _, chord in ipairs(chords) do add(chord, who) end
                    end
                end
            end
        end
    end
    return byChord
end

--- A button's name for messages ("KeyboardE" -> "E").
---@param chord string
---@return string
function BindingConflicts.describe(chord)
    local names = {}
    for value in chord:gmatch("[^+]+") do
        local n = tonumber(value)
        local name = tostring(value)
        for key, v in pairs(Button) do
            if v == n and type(key) == "string" then name = key break end
        end
        names[#names + 1] = (name:gsub("^Keyboard", ""):gsub("^Key(%d)$", "%1"))
    end
    return table.concat(names, " + ")
end

--- Every clash: { context, chord, key (readable), actions }, sorted.
---@return table[]
function BindingConflicts.find()
    local found = {}
    for contextName, sources in pairs(contexts()) do
        for chord, actions in pairs(usage(sources)) do
            if #actions > 1 then
                table.sort(actions)
                found[#found + 1] = { context = contextName, chord = chord,
                    key = BindingConflicts.describe(chord), actions = actions }
            end
        end
    end
    table.sort(found, function(a, b)
        if a.context ~= b.context then return a.context < b.context end
        return a.key < b.key
    end)
    return found
end

--- Log every clash as a warning; returns how many there were.
---@return integer
function BindingConflicts.report()
    local found = BindingConflicts.find()
    for _, c in ipairs(found) do
        Log.Warn("Key %s does more than one thing in %s: %s", c.key, c.context, table.concat(c.actions, ", "))
    end
    return #found
end

--- What else uses a key in the contexts `action` is live in: for a
--- rebinding screen to refuse (or warn about) a key before it takes it.
---@param button integer
---@param action string "Ship.Roll"
---@return string[] the other actions on that key
function BindingConflicts.whoUses(button, action)
    local others = {}
    local seen = {}
    for _, sources in pairs(contexts()) do
        local inContext = false
        for _, source in ipairs(sources) do
            if action:sub(1, #source.name + 1) == source.name .. "." then inContext = true end
        end
        if inContext then
            for _, who in ipairs(usage(sources)[tostring(button)] or {}) do
                if who ~= action and not seen[who] then
                    seen[who] = true
                    others[#others + 1] = who
                end
            end
        end
    end
    table.sort(others)
    return others
end

--- The actions that clash, as a set ("General.Mine" -> true), for marking.
---@return table<string, boolean>
function BindingConflicts.clashingActions()
    local set = {}
    for _, c in ipairs(BindingConflicts.find()) do
        for _, who in ipairs(c.actions) do set[who] = true end
    end
    return set
end

return BindingConflicts
