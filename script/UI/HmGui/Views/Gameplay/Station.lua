---@type UIView
local Station = UICore.View {
    name = "Station"
}

local Grid = UILayout.Grid
local Items = require("Shared.Registries.Items")
local PlayerWallet = require("Modules.Economy.Managers.PlayerWallet")
local PlayerCargo = require("Modules.Economy.Managers.PlayerCargo")
local MarketSystem = require("Modules.Economy.Systems.MarketSystem")
local MarketIntel = require("Modules.Economy.Managers.MarketIntel")
local PlayerStations = require("Modules.Economy.Managers.PlayerStations")
local PlayerForces = require("Modules.Economy.Managers.PlayerForces")
local BountyBoard = require("Modules.Economy.Managers.BountyBoard")
local EconomyComponents = require("Modules.Economy.Components")
local PlayerFactories = require("Modules.Economy.Managers.PlayerFactories")
local ShipFittingSystem = require("Modules.Constructs.Systems.ShipFittingSystem")
local AbilitySystem = require("Modules.Constructs.Systems.AbilitySystem")
local Fittings = require("Shared.Registries.Fittings")
local PlayerFleet = require("Modules.Constructs.Managers.PlayerFleet")
local Hulls = require("Shared.Registries.Hulls")

-- The screen the player sees while docked: what the station has and what it
-- pays, what the hold is carrying, what its factory floor is making, and the
-- way out. Docking opens it (LimitTheoryRedux:dockPlayer) and undocking
-- closes it; F undocks as well, wherever the cursor is.
--
-- Four tabs: the Market (the station's order book: trade at the market or
-- place an order of your own), the Factory (the station's own lines and the
-- lines the player rents), the Hangar (what the player keeps here, and moving
-- it to and from the ship), Nearby (what was last seen of the markets within
-- reach, which is where the spreads worth flying for show up) and Refit (the
-- ship's mounts and module slots, fitted out of this station's hangar).
--
-- NOTE: the prices and the stock are the station's own
-- (Modules/Economy/Systems/MarketSystem.lua: a station posts orders, and a
-- price is whatever someone will pay), the leases and the hangar are
-- PlayerFactories'; this view only shows them and asks them to act.

--- Which tab is up. Kept on the view, so it survives a redraw.
---
--- The market trades out of the hangar, as it must: an order has to be backed
--- by goods that are at the station. The Hangar tab moves goods between the
--- hangar and the ship.
Station.tab = "market"

-- The look is StationFrame's: slate panels, amber for what you act on,
-- cyan for values
local StationFrame = require("UI.HmGui.Views.Gameplay.StationFrame")
local StationTabs = require("UI.HmGui.Views.Gameplay.StationTabs")
-- A tab sending the player to another (the fitting screen's BUY PARTS)
StationTabs.goTo = function(id) Station.tab = id end
local C = StationFrame.C
local WHITE = C.TEXT
local GREY = C.SUB
local DIM = C.DIM
local ACCENT = C.AMBER
local RULE = C.RULE
local GOLD = C.AMBER
local GREEN = C.GREEN
local BUTTON_BG = C.BG
local BUTTON_HI = C.SELECT

--- Column widths at the design size (1500 x 950), scaled to the window.
local COL_ITEM, COL_NUM, COL_BUTTON = 260, 90, 54

--- The screen grows with the window (it used to stop at 1920 px wide's
--- size, and sat small in the middle of anything bigger): as big as fits
--- both ways, between 0.7 and 1.5.
---@return number
local function scale()
    return math.max(0.7, math.min(1.5, Window:width() / 1500, Window:height() / 950))
end

---@return Entity|nil station the station the player is docked at
local function dockedStation()
    local dock = LimitTheoryRedux.docked
    local station = dock and dock.entity
    if station and station:isValid() then return station end
    return nil
end

---@return string|nil key the station key the player's hangar is filed under
local function stationKey()
    local dock = LimitTheoryRedux.docked
    return dock and dock.key or nil
end

---@return string
local function stationName()
    local dock = LimitTheoryRedux.docked
    return dock and dock.label or "Station"
end

---@param value string
---@return UIComponentText
local function text(value, font, size, color, align)
    return UIComponent.Text {
        text = value,
        font = font,
        size = size,
        color = color,
        align = { align or AlignHorizontal.Left, AlignVertical.Center }
    }
end

---@param label string
---@param s number scale
---@param enabled boolean
---@param callback function
---@return UIComponentButton
local function smallButton(label, s, enabled, callback)
    return UIComponent.Button {
        title = label,
        width = math.floor(COL_BUTTON * s),
        height = math.floor(20 * s),
        font = { name = "TitilliumWebSemiBold", size = math.floor(12 * s) },
        color = {
            text = enabled and GREY or DIM,
            background = BUTTON_BG,
            highlight = enabled and BUTTON_HI or BUTTON_BG,
        },
        callback = enabled and callback or function() end
    }
end

---@param label string
---@param s number
---@param width number
---@param enabled boolean
---@param active boolean
---@param callback function
---@return UIComponentButton
local function wideButton(label, s, width, enabled, active, callback)
    return UIComponent.Button {
        title = label,
        width = math.floor(width * s),
        height = math.floor(28 * s),
        font = { name = "TitilliumWebSemiBold", size = math.floor(14 * s) },
        color = {
            text = not enabled and DIM or (active and ACCENT or GREY),
            background = active and BUTTON_HI or BUTTON_BG,
            highlight = enabled and BUTTON_HI or BUTTON_BG,
        },
        callback = enabled and callback or function() end
    }
end

------------------------------------------------------------------------------
-- The factory: industry, as EVE lays it out. Blueprints on the left (what
-- can be run here, what can be made now first, each with how many runs the
-- hangar holds the materials for); the chosen one on the right, its
-- materials against what is in the hangar, what it makes, and a job of so
-- many runs to start; the jobs running underneath. What the station's own
-- lines are busy with is not the player's business, and is not shown.
------------------------------------------------------------------------------

local RED = C.RED

--- The blueprint chosen, the runs asked for, and whether the list shows
--- only what can be made now.
Station.industry = { recipeId = nil, runs = 1, onlyMakeable = false }

--- The outpost's own block over the factory: what it is, its takings, and
--- its defences.
---@param key string
---@param s number
---@return table[] rows
local function outpostHeader(key, s)
    local rows = {}
    local size = math.floor(14 * s)
    local outpost = PlayerStations:byKey(key)
    if not outpost then return rows end
    local kindCfg = PlayerStations.kindOf(outpost.kind)
    local income = outpost.income
    rows[#rows + 1] = text(string.format("YOUR %s   ·   market: %s sold, %s bought, %s in taxes",
            string.upper(kindCfg.name), PlayerWallet.format(income.sales or 0),
            PlayerWallet.format(income.purchases or 0), PlayerWallet.format(income.taxes or 0)),
        "TitilliumWebSemiBold", math.floor(13 * s), ACCENT)
    local quote = LimitTheoryRedux:outpostDefenseQuote(key)
    if quote then
        local state = quote.destroyed and "Defences destroyed"
            or string.format("Defences: hull %d/%d  ·  shields %d/%d",
                math.floor(quote.hull), math.floor(quote.maxHull),
                math.floor(quote.shield), math.floor(quote.maxShield))
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(30 * s),
            cells = { Grid.Fixed(620 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
            contents = {
                text(state, "TitilliumWeb", size, quote.destroyed and GOLD or DIM),
                text(quote.cost > 0 and PlayerWallet.format(quote.cost) or "",
                    "TitilliumWeb", size, DIM, AlignHorizontal.Right),
                wideButton(quote.destroyed and "Rebuild" or "Repair", s, 110,
                    quote.cost > 0 and PlayerWallet:has(quote.cost), false, function()
                        LimitTheoryRedux:repairOutpostDefense(key)
                    end),
            }
        }
    end
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    return rows
end

--- The blueprint list: one row each, the makeable ones first.
---@param key string
---@param recipes ProductionDefinition[]
---@param s number
---@return UILayoutGrid
local function blueprintList(key, recipes, s)
    local sel = Station.industry
    local size = math.floor(13 * s)
    local rows = {
        Grid {
            fixedHeight = math.floor(30 * s),
            cells = { Grid.Fixed(250 * s), Grid.Fixed(200 * s) },
            contents = {
                text("BLUEPRINTS", "TitilliumWebSemiBold", math.floor(13 * s), DIM),
                wideButton(sel.onlyMakeable and "Showing: can make" or "Showing: all", s, 190, true,
                    sel.onlyMakeable, function() sel.onlyMakeable = not sel.onlyMakeable end),
            }
        },
        UIComponent.Divider { color = RULE },
    }
    local list = {}
    for _, recipe in ipairs(recipes) do
        local runs = PlayerFactories:runsPossible(key, recipe)
        if runs > 0 or not sel.onlyMakeable then list[#list + 1] = { recipe = recipe, runs = runs } end
    end
    table.sort(list, function(a, b)
        if (a.runs > 0) ~= (b.runs > 0) then return a.runs > 0 end
        return a.recipe.displayName < b.recipe.displayName
    end)
    if #list == 0 then
        rows[#rows + 1] = text(sel.onlyMakeable and "Nothing here can be made from your hangar yet."
            or "This station runs nothing for you.", "TitilliumWeb", size, DIM)
    end
    for _, row in ipairs(list) do
        local recipe = row.recipe
        local chosen = sel.recipeId == recipe.id
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(30 * s),
            cells = { Grid.Fixed(330 * s), Grid.Fixed(120 * s) },
            contents = {
                wideButton(recipe.displayName, s, 320, true, chosen, function()
                    sel.recipeId = recipe.id
                    sel.runs = math.max(1, math.min(sel.runs or 1, math.max(1, row.runs)))
                end),
                text(row.runs > 0 and string.format("can make %d", row.runs) or "missing materials",
                    "TitilliumWeb", size, row.runs > 0 and GREEN or DIM, AlignHorizontal.Right),
            }
        }
    end
    return Grid { layoutType = GuiLayoutType.Vertical, spacing = math.floor(2 * s), cells = Grid.Fit(), contents = rows }
end

--- The chosen blueprint: materials against the hangar, what it makes, and
--- the job to start.
---@param key string
---@param recipe ProductionDefinition|nil
---@param outpost boolean
---@param s number
---@return UILayoutGrid
local function blueprintDetail(key, recipe, outpost, s)
    local sel = Station.industry
    local size = math.floor(14 * s)
    local rows = {}
    if not recipe then
        rows[#rows + 1] = text("Choose a blueprint on the left.", "TitilliumWeb", size, DIM)
        return Grid { layoutType = GuiLayoutType.Vertical, cells = Grid.Fit(), contents = rows }
    end
    local hangar = PlayerFactories:hangar(key)
    local possible = PlayerFactories:runsPossible(key, recipe)
    local runs = math.max(1, sel.runs or 1)
    local fee = PlayerFactories:feeFor(recipe, key)
    local minutes = recipe.duration / Config.game.production.timeScale / 60

    rows[#rows + 1] = text(recipe.displayName, "TitilliumWebSemiBold", math.floor(17 * s), WHITE)
    rows[#rows + 1] = text(string.format("%s  ·  %.1f min a run%s", recipe.class, minutes,
            outpost and "" or string.format("  ·  station fee %s a run", PlayerWallet.format(fee))),
        "TitilliumWeb", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }

    -- Materials, for the runs asked for
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(22 * s),
        cells = { Grid.Fixed(250 * s), Grid.Fixed(100 * s), Grid.Fixed(100 * s) },
        contents = {
            text(string.format("MATERIALS  x%d", runs), "TitilliumWebSemiBold", math.floor(12 * s), DIM),
            text("needed", "TitilliumWebSemiBold", math.floor(12 * s), DIM, AlignHorizontal.Right),
            text("in hangar", "TitilliumWebSemiBold", math.floor(12 * s), DIM, AlignHorizontal.Right),
        }
    }
    for _, entry in ipairs(recipe.inputs) do
        local need = entry.count * runs
        local have = hangar:count(entry.item.id)
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(22 * s),
            cells = { Grid.Fixed(250 * s), Grid.Fixed(100 * s), Grid.Fixed(100 * s) },
            contents = {
                text(entry.item.displayName, "TitilliumWeb", size, GREY),
                text(tostring(need), "TitilliumWeb", size, GREY, AlignHorizontal.Right),
                text(tostring(have), "TitilliumWeb", size, have >= need and GREEN or RED, AlignHorizontal.Right),
            }
        }
    end

    -- Products
    rows[#rows + 1] = text(string.format("PRODUCES  x%d", runs), "TitilliumWebSemiBold", math.floor(12 * s), DIM)
    for _, entry in ipairs(recipe.outputs) do
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(22 * s),
            cells = { Grid.Fixed(250 * s), Grid.Fixed(100 * s) },
            contents = {
                text(entry.item.displayName, "TitilliumWeb", size, WHITE),
                text(tostring(entry.count * runs), "TitilliumWeb", size, WHITE, AlignHorizontal.Right),
            }
        }
    end
    rows[#rows + 1] = UIComponent.Divider { color = RULE }

    -- The job: so many runs, on a free line
    local free = PlayerFactories:freeLines(key)
    local function setRuns(n) sel.runs = math.max(1, math.min(999, n)) end
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(32 * s),
        cells = { Grid.Fixed(70 * s), Grid.Fixed(60 * s), Grid.Fixed(60 * s), Grid.Fixed(60 * s),
                  Grid.Fixed(60 * s), Grid.Fixed(130 * s) },
        contents = {
            text("RUNS", "TitilliumWebSemiBold", math.floor(12 * s), DIM),
            smallButton("-10", s, runs > 1, function() setRuns(runs - 10) end),
            smallButton("-1", s, runs > 1, function() setRuns(runs - 1) end),
            text(tostring(runs), "TitilliumWebSemiBold", size, WHITE, AlignHorizontal.Center),
            smallButton("+1", s, true, function() setRuns(runs + 1) end),
            smallButton(string.format("max %d", possible), s, possible > 0, function() setRuns(possible) end),
        }
    }
    local canStart = free > 0 and possible >= runs
    local why = free <= 0 and (outpost and "every line is busy" or "no line free to rent")
        or (possible < runs and (possible == 0 and "missing materials" or string.format("materials for %d run(s)", possible)))
        or nil
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(36 * s),
        cells = { Grid.Fixed(200 * s), Grid.Fixed(300 * s) },
        contents = {
            wideButton(string.format("Start job (%d run%s)", runs, runs == 1 and "" or "s"), s, 190, canStart, true,
                function()
                    local ok, reason = PlayerFactories:lease(key, recipe.id, runs)
                    LimitTheoryRedux:notify(ok
                        and string.format("Job started: %s x%d", recipe.displayName, runs)
                        or ("Cannot start: " .. (reason or "no")), ok and { 0.6, 0.9, 1.0 } or { 1.0, 0.4, 0.3 })
                end),
            text(why or (outpost and "" or string.format("total fee %s", PlayerWallet.format(fee * runs))),
                "TitilliumWeb", math.floor(13 * s), why and RED or DIM),
        }
    }
    return Grid { layoutType = GuiLayoutType.Vertical, spacing = math.floor(3 * s), cells = Grid.Fit(), contents = rows }
end

--- The jobs running here.
---@param key string
---@param outpost boolean
---@param s number
---@return table[] rows
local function jobRows(key, outpost, s)
    local size = math.floor(13 * s)
    local total = outpost and PlayerStations:lines(key) or Config.game.factory.rentableLines
    local leases = PlayerFactories:status(key)
    local rows = {
        text(string.format("JOBS   %d of %d line(s) in use%s", #leases, total,
                outpost and "" or string.format("  ·  the station takes %d%% of each run as its fee",
                    math.floor(Config.game.factory.rentShare * 100))),
            "TitilliumWebSemiBold", math.floor(13 * s), DIM),
        UIComponent.Divider { color = RULE },
    }
    if #leases == 0 then
        rows[#rows + 1] = text("No jobs running. Choose a blueprint and start one.", "TitilliumWeb", size, DIM)
    end
    for _, lease in ipairs(leases) do
        local state
        if lease.running then
            state = string.format("%d%%", math.floor(lease.progress * 100))
        elseif not lease.crewed then
            state = "no crew"
        elseif lease.hangarFull then
            state = "hangar full"
        else
            state = "waiting: " .. (PlayerFactories:missingFor(key, lease.recipe) or "inputs")
        end
        local index = lease.index
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(28 * s),
            cells = { Grid.Fixed(330 * s), Grid.Fixed(140 * s), Grid.Fixed(340 * s), Grid.Fixed(120 * s) },
            contents = {
                text(lease.recipe.displayName, "TitilliumWeb", size, WHITE),
                text(lease.runs and string.format("%d run(s) left", lease.runs) or "repeating",
                    "TitilliumWeb", size, GREY),
                text(state, "TitilliumWeb", size,
                    lease.running and ACCENT or (not lease.crewed and GOLD or DIM)),
                wideButton("Stop", s, 110, true, false, function()
                    PlayerFactories:release(key, index)
                    LimitTheoryRedux:notify("Job stopped.", { 0.6, 0.9, 1.0 })
                end),
            }
        }
    end
    return rows
end

--- The factory tab.
---@param station Entity
---@param s number
---@return UILayoutGrid
local function factory(station, s)
    local key = stationKey()
    if not key then
        return Grid { cells = Grid.Fit(), contents = {
            text("This station runs no jobs for you.", "TitilliumWeb", math.floor(14 * s), DIM) } }
    end
    local outpost = PlayerStations:byKey(key) ~= nil
    local recipes = PlayerFactories:offered(station, key)
    local sel = Station.industry
    -- A choice from another station, or none: the first that can be made
    local chosen = nil
    for _, recipe in ipairs(recipes) do
        if recipe.id == sel.recipeId then chosen = recipe end
    end
    if not chosen then
        for _, recipe in ipairs(recipes) do
            if PlayerFactories:runsPossible(key, recipe) > 0 then chosen = recipe break end
        end
        chosen = chosen or recipes[1]
        sel.recipeId = chosen and chosen.id or nil
        sel.runs = 1
    end

    local rows = outpostHeader(key, s)
    rows[#rows + 1] = Grid {
        cells = { Grid.Fixed(470 * s), Grid.Fixed(20 * s), Grid.Fixed(510 * s) },
        contents = {
            blueprintList(key, recipes, s),
            text("", "TitilliumWeb", 10, DIM),
            blueprintDetail(key, chosen, outpost, s),
        }
    }
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    for _, row in ipairs(jobRows(key, outpost, s)) do rows[#rows + 1] = row end
    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(4 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- What is known of the markets within reach: the best spreads first, then
--- every station whose book has been seen, with how stale the note is. Only
--- the system you are in is live, so this is memory, not a live feed -- which
--- is the point: you have to go and look.
---@param s number
---@return UILayoutGrid
local function nearby(s)
    local size = math.floor(14 * s)
    local galaxy = LimitTheoryRedux.galaxy
    local systemId = LimitTheoryRedux.currentSystemId or 1
    local now = LimitTheoryRedux.simTime or 0
    local rows = {
        text(string.format("MARKETS WITHIN %d JUMPS        what was last seen of them",
                MarketIntel:getRange()),
            "TitilliumWebSemiBold", math.floor(13 * s), DIM),
        UIComponent.Divider { color = RULE },
    }

    local spreads = MarketIntel:bestSpreads(galaxy, systemId, now, 8)
    if #spreads > 0 then
        rows[#rows + 1] = text("BEST SPREADS", "TitilliumWebSemiBold", math.floor(13 * s), ACCENT)
        for _, spread in ipairs(spreads) do
            rows[#rows + 1] = Grid {
                fixedHeight = math.floor(22 * s),
                cells = { Grid.Fixed(COL_ITEM * s), Grid.Fixed(330 * s), Grid.Fixed(330 * s),
                          Grid.Fixed(120 * s) },
                contents = {
                    text(spread.item.displayName, "TitilliumWeb", size, GREY),
                    text(string.format("buy %d at %s, %s", spread.buyPrice, spread.buyAt.label,
                        spread.buyAt.systemName), "TitilliumWeb", size, GOLD),
                    text(string.format("sell %d at %s, %s", spread.sellPrice, spread.sellAt.label,
                        spread.sellAt.systemName), "TitilliumWeb", size, GREEN),
                    text(string.format("+%d a unit", spread.margin), "TitilliumWebSemiBold", size,
                        WHITE, AlignHorizontal.Right),
                }
            }
        end
        rows[#rows + 1] = UIComponent.Divider { color = RULE }
    end

    local known = MarketIntel:nearby(galaxy, systemId, now)
    if #known == 0 then
        rows[#rows + 1] = text("No market has been seen yet. Dock at one.",
            "TitilliumWeb", size, DIM)
    end
    for _, record in ipairs(known) do
        local counted = 0
        for _ in pairs(record.quotes) do counted = counted + 1 end
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(22 * s),
            cells = { Grid.Fixed(300 * s), Grid.Fixed(240 * s), Grid.Fixed(180 * s),
                      Grid.Fixed(180 * s) },
            contents = {
                text(string.format("%s, %s", record.label, record.systemName),
                    "TitilliumWeb", size, GREY),
                text(record.jumps == 0 and "this system"
                    or string.format("%d jump%s away", record.jumps, record.jumps == 1 and "" or "s"),
                    "TitilliumWeb", size, DIM),
                text(string.format("%d goods quoted", counted), "TitilliumWeb", size, DIM),
                text(record.jumps == 0 and "live" or MarketIntel.describeAge(record.age),
                    "TitilliumWeb", size, record.jumps == 0 and ACCENT or DIM,
                    AlignHorizontal.Right),
            }
        }
    end

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- The Forces tab, at one of the player's outposts: launch a drone from the
--- hangar, hire a mercenary, and give every unit in the system its order.
---@param s number
---@return UILayoutGrid
local function forces(s)
    local game = LimitTheoryRedux
    local key = stationKey()
    local size = math.floor(14 * s)
    local cfg = Config.game.forces
    local rows = {}

    local droneDef, hangarStock = game:droneStock()
    local drones = droneDef and hangarStock and hangarStock:count(droneDef.id) or 0
    local room = PlayerForces:room(key)
    rows[#rows + 1] = text(string.format("FORCES              %d of %d berths free here  ·  wages %s an hour",
            room, cfg.maxPerOutpost, PlayerWallet.format(PlayerForces:wageBill())),
        "TitilliumWebSemiBold", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(30 * s),
        cells = { Grid.Fixed(620 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
        contents = {
            text(string.format("Combat drone: built, not hired. %d in this hangar.", drones),
                "TitilliumWeb", size, GREY),
            text("no upkeep", "TitilliumWeb", size, DIM, AlignHorizontal.Right),
            wideButton("Launch", s, 110, drones > 0 and room > 0, false, function() game:launchDrone() end),
        }
    }
    rows[#rows + 1] = Grid {
        fixedHeight = math.floor(30 * s),
        cells = { Grid.Fixed(620 * s), Grid.Fixed(200 * s), Grid.Fixed(120 * s) },
        contents = {
            text(string.format("Mercenary: %s to hire, then %s an hour while they serve.",
                    PlayerWallet.format(cfg.mercenary.hireCost), PlayerWallet.format(cfg.mercenary.wagePerHour)),
                "TitilliumWeb", size, GREY),
            text("", "TitilliumWeb", size, DIM, AlignHorizontal.Right),
            wideButton("Hire", s, 110, room > 0 and PlayerWallet:has(cfg.mercenary.hireCost), false,
                function() game:hireMercenary() end),
        }
    }

    local units = PlayerForces:inSystem(game.currentSystemId or 1)
    rows[#rows + 1] = text(#units > 0 and "IN THIS SYSTEM" or "IN THIS SYSTEM      none yet",
        "TitilliumWebSemiBold", math.floor(13 * s), DIM)
    rows[#rows + 1] = UIComponent.Divider { color = RULE }
    for _, unit in ipairs(units) do
        local status = game:unitStatus(unit)
        local home = PlayerStations:byKey(unit.homeKey)
        local guarding = unit.order == PlayerForces.Order.Guard
        local orderText = guarding and ("guarding " .. (home and home.name or "its outpost"))
            or "patrolling your outposts"
        local here = unit.homeKey == key
        rows[#rows + 1] = Grid {
            fixedHeight = math.floor(28 * s),
            cells = { Grid.Fixed(500 * s), Grid.Fixed(200 * s), Grid.Fixed(110 * s), Grid.Fixed(110 * s) },
            contents = {
                text(string.format("%s  ·  %s", unit.name, orderText), "TitilliumWeb", size, GREY),
                text(string.format("hull %d%%  shield %d%%",
                        math.floor(100 * status.hull / math.max(1, status.maxHull)),
                        math.floor(100 * status.shield / math.max(1, status.maxShield))),
                    "TitilliumWeb", size, status.hull < status.maxHull * 0.4 and GOLD or DIM, AlignHorizontal.Right),
                wideButton(guarding and "Patrol" or "Guard", s, 100, true, false, function()
                    game:setUnitOrder(unit, guarding and PlayerForces.Order.Patrol or PlayerForces.Order.Guard)
                end),
                wideButton(unit.kind == PlayerForces.Kind.Drone and "Recall" or "Dismiss", s, 100,
                    unit.kind ~= PlayerForces.Kind.Drone or (here and status.here), false,
                    function() game:releaseUnit(unit) end),
            }
        }
    end
    rows[#rows + 1] = text("A drone is recalled into its own outpost's hangar. Guards fly around their outpost; "
        .. "patrols make the round of all your outposts here.", "TitilliumWeb", math.floor(12 * s), DIM)

    return Grid {
        layoutType = GuiLayoutType.Vertical,
        spacing = math.floor(2 * s),
        cells = Grid.Fit(),
        contents = rows
    }
end

--- The tabs, in the strip's order
local function tabList()
    local list = {
        { id = "hangar", label = "HANGAR" },
        { id = "market", label = "MARKET" },
        { id = "factory", label = "FACTORY" },
        { id = "refit", label = "SHIP FITTING" },
        { id = "nearby", label = "NEARBY" },
    }
    -- The bounty board at the system's stations; the player's own ships are
    -- commanded from their outposts
    if PlayerStations.isOwnedKey(stationKey()) then
        list[#list + 1] = { id = "forces", label = "FORCES" }
    else
        list[#list + 1] = { id = "bounties", label = "BOUNTY BOARD" }
    end
    return list
end

--- Draw the current tab into the main area (W x H design pixels).
local function drawTab(station, W, H)
    local s = scale()
    if not station then
        StationTabs.panelled("NOT DOCKED", nil, nil, W, H)
        return
    end
    local owned = PlayerStations.isOwnedKey(stationKey())
    if Station.tab == "hangar" then
        StationTabs.hangar(station, W, H)
    elseif Station.tab == "refit" then
        StationTabs.fitting(station, W, H)
    elseif Station.tab == "bounties" and not owned then
        StationTabs.bounties(station, W, H)
    elseif Station.tab == "factory" then
        StationTabs.panelled("INDUSTRY", "blueprints, materials and jobs at this station", factory(station, s), W, H)
    elseif Station.tab == "nearby" then
        StationTabs.panelled("MARKETS NEARBY", "what was last seen of them", nearby(s), W, H)
    elseif Station.tab == "forces" and owned then
        StationTabs.panelled("YOUR FORCES", "drones and hired ships of this outpost", forces(s), W, H)
    else
        Station.tab = "market"
        StationTabs.market(station, W, H)
    end
end

local function screen()
    local game = LimitTheoryRedux
    local station = dockedStation()
    local dock = game.docked
    local missing, repairCost = game:hullRepairQuote()

    -- Where: the system, the owner, what kind of place
    local chips = {}
    local system = game.galaxy and game.galaxy.systems and game.galaxy.systems[game.currentSystemId]
    if system and system.name then chips[#chips + 1] = { text = system.name:upper() } end
    if dock and dock.faction then
        local Factions = require("Modules.NPC.Factions")
        local r, g, b = Factions.color(dock.faction)
        chips[#chips + 1] = { text = Factions.name(dock.faction):upper(), color = Color(r, g, b, 1) }
    end
    chips[#chips + 1] = { text = dock and dock.outpost and "YOUR OUTPOST" or "STATION", color = C.CYAN }

    StationFrame.draw({
        title = stationName(),
        chips = chips,
        tabs = tabList(),
        active = Station.tab,
        onTab = function(id) Station.tab = id end,
        actions = {
            {
                label = missing > 0 and string.format("REPAIR HULL  %s", PlayerWallet.format(repairCost))
                    or "HULL INTACT",
                enabled = missing > 0,
                callback = function() game:repairHull() end,
            },
        },
        onUndock = function() game:undockPlayer() end,
        body = function(W, H) drawTab(station, W, H) end,
    })
end

function Station:onViewOpen(isPageOpen) end

-- Rebuilt every frame: the stock, the prices and the hold all move while the
-- screen is open (the station's factory floor is running), and the buttons
-- have to be enabled or disabled with them. One station's worth of rows is
-- about twenty, so this is cheap enough and always right.
Station:addContent({
    state = {},
    render = function()
        screen()
    end
})

-- The debug menu (~) over the station screen too
local DebugMenu = require("UI.HmGui.Views.Gameplay.DebugMenu")
Station:addContent({ state = {}, render = function() DebugMenu.render() end })

return Station
