local UIMouse = require("Input.UIMouse")
local SystemOverview = require("Modules.Navigation.Systems.SystemOverview")
local PhysicsComponents = require("Modules.Physics.Components")
local ConstructComponents = require("Modules.Constructs.Components")
local CoreComponents = require("Modules.Core.Components")
local UniverseScaleConfig = require("Config.Gen.UniverseScaleConfig")

-- The targets, top centre: a card for each thing the player has targeted
-- (LimitTheoryRedux:targetList), ships and rocks. A card shows what it is,
-- how far, and how much is left of it (shield and hull, or ore); the active
-- target (the guns' focus, or the mining laser's rock) is outlined, in red
-- while it is being attacked.
--
--   left click    make it the active target
--   X             clear it
--   right click   the menu: make active, attack / hold fire, mine, look at,
--                 approach, show on map, clear
--
-- With the cursor free (the overview open, a window up), as the action bar.

local TargetsPanel = {}

local WHITE = Color(1.00, 1.00, 1.00, 1.00)
local GREY = Color(0.75, 0.77, 0.80, 1.00)
local DIM = Color(0.51, 0.54, 0.59, 1.00)
local ACCENT = Color(0.10, 0.60, 1.00, 1.00)
local CARD_BG = Color(0.02, 0.04, 0.07, 0.80)
local CARD_HOVER = Color(0.06, 0.14, 0.22, 0.88)
local BORDER = Color(0.10, 0.60, 1.00, 0.35)
local ACTIVE = Color(1.00, 0.85, 0.35, 0.95)
local ATTACKING = Color(1.00, 0.38, 0.32, 0.95)
local HOSTILE = Color(1.00, 0.45, 0.40, 1.00)
local ROCK = Color(0.80, 0.68, 0.52, 1.00)
local SHIELD = Color(0.35, 0.70, 1.00, 0.95)
local HULL = Color(0.40, 0.95, 0.55, 0.95)
local BAR_BG = Color(1.00, 1.00, 1.00, 0.10)
local X_HOVER = Color(0.70, 0.15, 0.12, 0.90)
local MENU_BG = Color(0.03, 0.05, 0.09, 0.96)
local ROW_HOVER = Color(0.10, 0.30, 0.50, 0.55)
local NO_COLOR = Color(0, 0, 0, 0)

local CARD_W, CARD_H = 176, 64
local BAR_W = CARD_W - 16

--- The open menu: { entity, x, y }, or nil.
local menu = nil

---@return number
local function hudScale()
    return math.max(0.7, math.min(1.3, Window:height() / 1080)) * GameState.ui.hudScale
end

---@param size number
local function font(size)
    return Cache.Font("Unageo-Medium", size)
end

---@param value string
---@param limit integer
local function clip(value, limit)
    if #value <= limit then return value end
    return value:sub(1, limit - 2) .. ".."
end

---@param entity Entity
---@return Position|nil, number
local function place(entity)
    local rbCmp = entity:get(PhysicsComponents.RigidBody)
    local body = rbCmp and rbCmp:getRigidBody()
    if body then return body:getPos(), body:getBoundingRadius() or 0 end
    local t = entity:get(PhysicsComponents.Transform)
    return t and t:getPos(), 0
end

--- How far to it, surface to ship.
---@param game table
---@param entry table
---@return string
local function distanceText(game, entry)
    local here = game.playerShip and place(game.playerShip)
    local there, radius = place(entry.entity)
    if entry.kind == "rock" and entry.rock then radius = game:rockRadius(entry.rock) end
    if not here or not there then return "" end
    local dx, dy, dz = there.x - here.x, there.y - here.y, there.z - here.z
    return UniverseScaleConfig:formatDistance(math.max(0, math.sqrt(dx * dx + dy * dy + dz * dz) - radius))
end

--- A thin bar, `share` of it filled.
local function bar(share, color)
    Gui:beginStackContainer()
    Gui:setFixedSize(BAR_W, 4)
    Gui:setBackgroundColor(BAR_BG)
    Gui:beginStackContainer()
    Gui:setFixedSize(math.max(0, math.floor(BAR_W * math.max(0, math.min(1, share)))), 4)
    Gui:setBackgroundColor(color)
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
    Gui:endContainer()
    Gui:endContainer()
end

--- What the card says under the name, and its bars.
local function drawStatus(game, entry)
    if entry.kind == "rock" then
        local rock = entry.rock and entry.rock.rock
        local mining = game.miningJob and game.miningJob.rock
            and SystemOverview.same(game.miningJob.rock.entity, entry.entity)
        Gui:text(string.format("%s%s  ·  %s", mining and "MINING  ·  " or "",
            rock and string.format("%d units", math.floor(rock.yield)) or "rock",
            distanceText(game, entry)), font(11), mining and HULL or GREY)
        return
    end
    Gui:text(distanceText(game, entry), font(11), GREY)
    local defense = entry.entity:get(ConstructComponents.Defense)
    if defense and defense:getMaxShield() > 0 then
        bar(defense:getCurrentShield() / defense:getMaxShield(), SHIELD)
    end
    local health = entry.entity:get(CoreComponents.Health)
    if health and health:getMaxHealth() > 0 then
        bar(health:getCurrentHealth() / health:getMaxHealth(), HULL)
    end
end

--- One card. Returns what was clicked: "card", "x", "menu" or nil.
local function drawCard(game, entry)
    local active = game:isActiveTarget(entry)
    local attacking = entry.kind == "ship" and (entry.attack or (active and game.attacking))
    local clicked = nil

    Gui:beginStackContainer()
    Gui:setFixedSize(CARD_W, CARD_H)
    local hover = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(hover and CARD_HOVER or CARD_BG)
    Gui:setBorderWidth(active and 2 or 1)
    Gui:setBorderColor((attacking and ATTACKING) or (active and ACTIVE) or BORDER)

    Gui:beginVerticalContainer()
    Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Top)
    Gui:setPadding(8, 5)
    Gui:setSpacing(3)
    local nameColor = entry.kind == "rock" and ROCK
        or (game:isHostileFaction(entry.faction) and HOSTILE) or WHITE
    Gui:text(clip(entry.name or "target", 20), font(13), nameColor)
    drawStatus(game, entry)
    Gui:endContainer()

    -- The X, top right
    Gui:beginStackContainer()
    Gui:setFixedSize(18, 18)
    Gui:setAlignment(AlignHorizontal.Right, AlignVertical.Top)
    Gui:setMargin(2, 2)
    local overX = Gui:isMouseOver(FocusType.Mouse)
    Gui:setBackgroundColor(overX and X_HOVER or NO_COLOR)
    Gui:text("x", font(13), overX and WHITE or DIM)
    Gui:setAlignment(AlignHorizontal.Center, AlignVertical.Center)
    Gui:endContainer()

    Gui:endContainer()

    local mouse = Input:mouse()
    if overX and mouse:isPressed(MouseControl.Left) then
        clicked = "x"
    elseif hover and mouse:isPressed(MouseControl.Left) then
        clicked = "card"
    elseif (hover or overX) and mouse:isPressed(MouseControl.Right) then
        clicked = "menu"
    end
    return clicked, hover or overX
end

--- What can be done to a target, in menu order: { label, run }.
local function actionsFor(game, entry)
    local items = {}
    local function add(label, run) items[#items + 1] = { label = label, run = run } end
    local active = game:isActiveTarget(entry)

    if entry.kind == "ship" then
        if not active then add("Make active", function() game:activateTarget(entry) end) end
        local attacking = entry.attack or (active and game.attacking)
        if attacking then
            add("Hold fire", function() game:holdFire(entry) end)
        elseif not game:isHostileFaction(entry.faction) then
            add("Attack", function() game:attackTarget(entry.entity, entry.name, entry.faction) end)
        end
    else
        if not active then add("Make mining target", function() game:activateTarget(entry) end) end
        local mining = game.miningJob and game.miningJob.rock
            and SystemOverview.same(game.miningJob.rock.entity, entry.entity)
        if mining then
            add("Stop mining", function() game:stopMining("Mining stopped.") end)
        elseif game:miningMount() then
            add("Mine", function()
                game:activateTarget(entry)
                if game.miningJob then game:stopMining() end
                game:toggleMining()
            end)
        end
    end

    if SystemOverview.same(game.lookingAt, entry.entity) then
        add("Stop looking", function() game:lookAtShip(true) end)
    else
        add("Look at", function() game:lookAt(entry.entity, entry.name) end)
    end
    add("Approach", function() game:approach(entry.entity, entry.name) end)
    add("Show on map", function() game:showOnMap(entry.entity, entry.name) end)
    add("Clear target", function() game:releaseTarget(entry.entity) end)
    return items
end

--- The open menu. Returns whether the cursor is over it.
local function drawMenu(game, s)
    if not menu then return false end
    local entry = game:findTarget(menu.entity)
    if not entry or not entry.entity:isValid() then
        menu = nil
        return false
    end
    local items = actionsFor(game, entry)
    Gui:beginLayerAtPos(Vec2f(menu.x, menu.y))
    Gui:beginVerticalContainer()
    Gui:setScale(s)
    local over = Gui:isMouseOver(FocusType.Scroll)
    Gui:setBackgroundColor(MENU_BG)
    Gui:setBorderWidth(1)
    Gui:setBorderColor(BORDER)
    Gui:setPadding(4, 4)
    Gui:setSpacing(1)
    Gui:text(clip(entry.name or "target", 26), font(13), ACCENT)
    local clicked = nil
    for _, item in ipairs(items) do
        Gui:beginStackContainer()
        Gui:setFixedSize(180, 24)
        Gui:setPadding(8, 0)
        local hover = Gui:isMouseOver(FocusType.Mouse)
        Gui:setBackgroundColor(hover and ROW_HOVER or NO_COLOR)
        Gui:text(item.label, font(14), WHITE)
        Gui:setAlignment(AlignHorizontal.Left, AlignVertical.Center)
        Gui:endContainer()
        if hover and Input:mouse():isPressed(MouseControl.Left) then clicked = item end
    end
    Gui:endContainer()
    Gui:endLayer()

    local mouse = Input:mouse()
    if clicked then
        menu = nil
        clicked.run()
    elseif not over and (mouse:isPressed(MouseControl.Left) or mouse:isPressed(MouseControl.Right)) then
        -- A click anywhere else closes it (a right click on another card
        -- opens that one's, below)
        menu = nil
    end
    return over
end

--- Close the menu (Escape). Returns whether one was open.
---@return boolean
function TargetsPanel.closeMenu()
    local open = menu ~= nil
    menu = nil
    return open
end

function TargetsPanel.render()
    local game = LimitTheoryRedux
    if not (game and game.playerShip and game.isTravelGame and game:isTravelGame())
        or game.docked or game.hudHidden or (game.mapMode or 0) ~= 0 or game.pauseMenuOpen then
        menu = nil
        return
    end
    local list = game:targetList()
    if #list == 0 then
        menu = nil
        return
    end

    local s = hudScale()
    local over = false
    local action, actionEntry = nil, nil

    Gui:beginStackContainer()
    Gui:setScale(s)
    Gui:setAlignment(AlignHorizontal.Stretch, AlignVertical.Stretch)
    Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Top)
    Gui:setPadding(0, 56)

    Gui:beginVerticalContainer()
    Gui:setChildrenAlignment(AlignHorizontal.Center, AlignVertical.Top)
    Gui:setSpacing(3)
    Gui:text(string.format("TARGETS  %d / %d", #list, game:maxTargets()), font(11), DIM)
    Gui:beginHorizontalContainer()
    Gui:setSpacing(6)
    for _, entry in ipairs(list) do
        if entry.entity:isValid() then
            local clicked, hover = drawCard(game, entry)
            if hover then over = true end
            if clicked then action, actionEntry = clicked, entry end
        end
    end
    Gui:endContainer()
    Gui:endContainer()
    Gui:endContainer()

    if drawMenu(game, s) then over = true end

    if action == "x" then
        game:releaseTarget(actionEntry.entity)
    elseif action == "card" then
        game:activateTarget(actionEntry)
    elseif action == "menu" then
        local pos = Input:mouse():position()
        menu = { entity = actionEntry.entity, x = pos.x, y = pos.y }
    end

    if over or menu then UIMouse.claim() end
end

return TargetsPanel
