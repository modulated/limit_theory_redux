---@type UIView
local LoadgameView = UICore.View {
    name = "Loadgame",
    noDarken = true -- the sidebar and the modal carry their own backgrounds
}

---@type UIRouter
local UIRouter = require("UI.HmGui.UICore.UIRouter")
local MenuStyle = require("UI.HmGui.Styles.MenuStyle")

local SaveGame = require("Shared.Save.SaveGame")

-- The saved games: every slot, what is in it, and Load. The slots are read
-- when the screen opens (SaveGame.listCached), not every frame.

function LoadgameView:onInput() end
function LoadgameView:onUpdate(dt) end
function LoadgameView:onViewOpen(isPageOpen) SaveGame.invalidate() end
function LoadgameView:onViewClose(isPageClose) end

--- The slot at a row of the list (SaveGame.SLOTS order), read when shown.
---@param index integer
---@return table|nil row
local function slotRow(index)
    return SaveGame.listCached()[index]
end

--- A save's summary over two lines: where, then what and when.
local summary = SaveGame.describeLines

local function switchToMainScreen()
    UIRouter:getCurrentPage():setView("Main")
end

local MODAL_W = 590

LoadgameView:addContent(UIComponent.MenuScreen {
    contents = {
        UIComponent.MenuSidebar {
            contents = {
                UIComponent.MenuLabel { x = 0, y = 88, w = MenuStyle.SIDEBAR_WIDTH, h = 70, size = 54, align = "center", text = "LOAD GAME", color = MenuStyle.color.text },
                UIComponent.MenuMainNav { selected = 3 },
                UIComponent.MenuVersion(),
            }
        },
        UIComponent.MenuPanel {
            x = 958, y = 108, w = MODAL_W, h = 912, band = 122,
            contents = {
                UIComponent.MenuClose { x = MODAL_W - 48, y = 6, callback = switchToMainScreen },
                UIComponent.MenuLabel { x = 0, y = 36, w = MODAL_W, h = 56, size = 40, align = "center", text = "LOAD GAME", color = MenuStyle.color.text },
                UIComponent.MenuLabel { x = 28, y = 112, w = 400, h = 30, size = 24,
                    text = function() local r = slotRow(1); return r and r.name or "" end,
                    color = function() local r = slotRow(1); return r and r.meta and MenuStyle.color.text or MenuStyle.color.dim end },
                UIComponent.MenuLabel { x = 28, y = 144, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(1); if r and r.problem then return "Unreadable: " .. r.problem end; return (summary(r and r.meta)) end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuLabel { x = 28, y = 168, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(1); local _, second = summary(r and r.meta); return second end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuButton { x = 456, y = 130, w = 106, h = 44, size = 22, title = "Load",
                    enabled = function() local r = slotRow(1); return r ~= nil and r.meta ~= nil end,
                    callback = function() local r = slotRow(1); if r then LimitTheoryRedux:loadGame(r.slot) end end },
                UIComponent.MenuLabel { x = 28, y = 212, w = 400, h = 30, size = 24,
                    text = function() local r = slotRow(2); return r and r.name or "" end,
                    color = function() local r = slotRow(2); return r and r.meta and MenuStyle.color.text or MenuStyle.color.dim end },
                UIComponent.MenuLabel { x = 28, y = 244, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(2); if r and r.problem then return "Unreadable: " .. r.problem end; return (summary(r and r.meta)) end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuLabel { x = 28, y = 268, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(2); local _, second = summary(r and r.meta); return second end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuButton { x = 456, y = 230, w = 106, h = 44, size = 22, title = "Load",
                    enabled = function() local r = slotRow(2); return r ~= nil and r.meta ~= nil end,
                    callback = function() local r = slotRow(2); if r then LimitTheoryRedux:loadGame(r.slot) end end },
                UIComponent.MenuLabel { x = 28, y = 312, w = 400, h = 30, size = 24,
                    text = function() local r = slotRow(3); return r and r.name or "" end,
                    color = function() local r = slotRow(3); return r and r.meta and MenuStyle.color.text or MenuStyle.color.dim end },
                UIComponent.MenuLabel { x = 28, y = 344, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(3); if r and r.problem then return "Unreadable: " .. r.problem end; return (summary(r and r.meta)) end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuLabel { x = 28, y = 368, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(3); local _, second = summary(r and r.meta); return second end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuButton { x = 456, y = 330, w = 106, h = 44, size = 22, title = "Load",
                    enabled = function() local r = slotRow(3); return r ~= nil and r.meta ~= nil end,
                    callback = function() local r = slotRow(3); if r then LimitTheoryRedux:loadGame(r.slot) end end },
                UIComponent.MenuLabel { x = 28, y = 412, w = 400, h = 30, size = 24,
                    text = function() local r = slotRow(4); return r and r.name or "" end,
                    color = function() local r = slotRow(4); return r and r.meta and MenuStyle.color.text or MenuStyle.color.dim end },
                UIComponent.MenuLabel { x = 28, y = 444, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(4); if r and r.problem then return "Unreadable: " .. r.problem end; return (summary(r and r.meta)) end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuLabel { x = 28, y = 468, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(4); local _, second = summary(r and r.meta); return second end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuButton { x = 456, y = 430, w = 106, h = 44, size = 22, title = "Load",
                    enabled = function() local r = slotRow(4); return r ~= nil and r.meta ~= nil end,
                    callback = function() local r = slotRow(4); if r then LimitTheoryRedux:loadGame(r.slot) end end },
                UIComponent.MenuLabel { x = 28, y = 512, w = 400, h = 30, size = 24,
                    text = function() local r = slotRow(5); return r and r.name or "" end,
                    color = function() local r = slotRow(5); return r and r.meta and MenuStyle.color.text or MenuStyle.color.dim end },
                UIComponent.MenuLabel { x = 28, y = 544, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(5); if r and r.problem then return "Unreadable: " .. r.problem end; return (summary(r and r.meta)) end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuLabel { x = 28, y = 568, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(5); local _, second = summary(r and r.meta); return second end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuButton { x = 456, y = 530, w = 106, h = 44, size = 22, title = "Load",
                    enabled = function() local r = slotRow(5); return r ~= nil and r.meta ~= nil end,
                    callback = function() local r = slotRow(5); if r then LimitTheoryRedux:loadGame(r.slot) end end },
                UIComponent.MenuLabel { x = 28, y = 612, w = 400, h = 30, size = 24,
                    text = function() local r = slotRow(6); return r and r.name or "" end,
                    color = function() local r = slotRow(6); return r and r.meta and MenuStyle.color.text or MenuStyle.color.dim end },
                UIComponent.MenuLabel { x = 28, y = 644, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(6); if r and r.problem then return "Unreadable: " .. r.problem end; return (summary(r and r.meta)) end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuLabel { x = 28, y = 668, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(6); local _, second = summary(r and r.meta); return second end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuButton { x = 456, y = 630, w = 106, h = 44, size = 22, title = "Load",
                    enabled = function() local r = slotRow(6); return r ~= nil and r.meta ~= nil end,
                    callback = function() local r = slotRow(6); if r then LimitTheoryRedux:loadGame(r.slot) end end },
                UIComponent.MenuLabel { x = 28, y = 712, w = 400, h = 30, size = 24,
                    text = function() local r = slotRow(7); return r and r.name or "" end,
                    color = function() local r = slotRow(7); return r and r.meta and MenuStyle.color.text or MenuStyle.color.dim end },
                UIComponent.MenuLabel { x = 28, y = 744, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(7); if r and r.problem then return "Unreadable: " .. r.problem end; return (summary(r and r.meta)) end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuLabel { x = 28, y = 768, w = 420, h = 24, size = 17, font = "regular",
                    text = function() local r = slotRow(7); local _, second = summary(r and r.meta); return second end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuButton { x = 456, y = 730, w = 106, h = 44, size = 22, title = "Load",
                    enabled = function() local r = slotRow(7); return r ~= nil and r.meta ~= nil end,
                    callback = function() local r = slotRow(7); if r then LimitTheoryRedux:loadGame(r.slot) end end },
                UIComponent.MenuLabel { x = 0, y = 806, w = MODAL_W, h = 24, size = 17, font = "regular", align = "center",
                    text = function() return SaveGame.lastProblem and ("Could not load " .. SaveGame.lastProblem) or "" end,
                    color = MenuStyle.color.dim },
                UIComponent.MenuButton { x = 229, y = 836, w = 132, h = 44, size = 26, title = "Close", callback = switchToMainScreen },
            }
        },
    }
})

return LoadgameView
