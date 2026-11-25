--- The player's credits (the port of Legacy Elements/Economy/Credits.lua:
--- addCredits, hasCredits, removeCredits), with a short history of what
--- they were earned and spent on. One wallet per game: `reset` on a new game.
---@class PlayerWallet
local PlayerWallet = {
    balance = 0,
    history = {},
}

--- A new game: the starting credits, no history.
function PlayerWallet:reset()
    self.balance = Config.game.economy.startingCredits
    self.history = {}
end

---@return integer
function PlayerWallet:get()
    return self.balance
end

---@param amount number
---@return boolean
function PlayerWallet:has(amount)
    return self.balance >= amount
end

---@param amount number
---@param reason string
function PlayerWallet:add(amount, reason)
    amount = math.floor(amount + 0.5)
    if amount <= 0 then return end
    self.balance = self.balance + amount
    table.insert(self.history, { amount = amount, reason = reason })
end

--- Take `amount` if the wallet holds it.
---@param amount number
---@param reason string
---@return boolean paid
function PlayerWallet:remove(amount, reason)
    amount = math.floor(amount + 0.5)
    if amount <= 0 then return true end
    if self.balance < amount then return false end
    self.balance = self.balance - amount
    table.insert(self.history, { amount = -amount, reason = reason })
    return true
end

--- "12,500 cr"
---@param amount number
---@return string
function PlayerWallet.format(amount)
    local s = tostring(math.floor(amount + 0.5))
    local sign = s:sub(1, 1) == "-" and "-" or ""
    s = s:gsub("^-", "")
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return sign .. s .. " cr"
end

return PlayerWallet
