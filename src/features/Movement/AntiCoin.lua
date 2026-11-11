-- Liberium Hub | Anti Coin
-- Disables touch collection on coin pickups while enabled, restoring original
-- CanTouch values when disabled or when the module is unloaded.

local Maid = require(script.Parent.Parent.core.Maid)

local AntiCoin = {}
AntiCoin.__index = AntiCoin

local function isCoinContainer(instance)
    local current = instance and instance.Parent
    while current do
        if current.Name == "CoinContainer" then
            return true
        end
        current = current.Parent
    end
    return false
end

function AntiCoin.new(context)
    assert(type(context) == "table", "AntiCoin.new expects a context")
    assert(context.Workspace and context.Player, "AntiCoin context is missing Workspace or Player")

    local self = setmetatable({}, AntiCoin)
    self.Workspace = context.Workspace
    self.Player = context.Player
    self.Notify = context.Notify
    self.Enabled = false
    self.Destroyed = false
    self._original = setmetatable({}, {__mode = "k"})
    self._maid = Maid.new()
    self._activeMaid = nil

    return self
end

function AntiCoin:_block(instance)
    if not self.Enabled or self.Destroyed or not instance:IsA("BasePart") then
        return
    end
    if not isCoinContainer(instance) then
        return
    end

    if self._original[instance] == nil then
        self._original[instance] = instance.CanTouch
    end

    if instance.CanTouch then
        pcall(function()
            instance.CanTouch = false
        end)
    end
end

function AntiCoin:_restore()
    for part, original in pairs(self._original) do
        if part and part.Parent then
            pcall(function()
                part.CanTouch = original
            end)
        end
        self._original[part] = nil
    end
end

function AntiCoin:_scan()
    for _, instance in ipairs(self.Workspace:GetDescendants()) do
        if instance:IsA("BasePart") and isCoinContainer(instance) then
            self:_block(instance)
        end
    end
end

function AntiCoin:SetEnabled(enabled)
    if self.Destroyed then
        return false
    end

    local nextValue = enabled == true
    if nextValue == self.Enabled then
        return true
    end
    self.Enabled = nextValue

    if nextValue then
        self._activeMaid = Maid.new()
        self._activeMaid:Connect(self.Workspace.DescendantAdded, function(instance)
            self:_block(instance)
        end, "descendant-added")
        self:_scan()
        if type(self.Notify) == "function" then
            pcall(self.Notify, "Anti Coin enabled", "Info")
        end
    else
        if self._activeMaid then
            self._activeMaid:Destroy()
            self._activeMaid = nil
        end
        self:_restore()
        if type(self.Notify) == "function" then
            pcall(self.Notify, "Anti Coin disabled", "Info")
        end
    end

    return true
end

function AntiCoin:Destroy()
    if self.Destroyed then
        return
    end
    self:SetEnabled(false)
    self.Destroyed = true
    self._maid:Destroy()
    self:_restore()
end

return AntiCoin
