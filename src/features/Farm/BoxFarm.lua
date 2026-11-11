-- Liberium Hub | Mystery Box Farm
-- Clean-room box catalog and opener with explicit spending controls.
-- Auto-open is opt-in and disabled by default.

local Maid = require(script.Parent.Parent.Parent.core.Maid)

local BoxFarm = {}
BoxFarm.__index = BoxFarm

local CURRENCY_ORDER = {
    "Candies2026",
    "HalloweenKey2026",
    "Key",
    "Coins",
    "Gems",
}

local CURRENCY_LABELS = {
    Auto = "Auto",
    Candies2026 = "Candies",
    HalloweenKey2026 = "Halloween Key",
    Key = "Key",
    Coins = "Coins",
    Gems = "Gems",
}

local RARE_RARITIES = {
    Legendary = true,
    Godly = true,
    Ancient = true,
    Unique = true,
    Vintage = true,
    Chroma = true,
}

function BoxFarm.new(context)
    assert(type(context) == "table", "BoxFarm.new expects a context")
    assert(context.Storage and context.Player, "BoxFarm context is missing Storage or Player")

    local self = setmetatable({}, BoxFarm)
    self.Storage = context.Storage
    self.Player = context.Player
    self.Notify = context.Notify
    self.SelectedBox = context.BoxId
    self.Currency = context.Currency or "Auto"
    self.Delay = math.clamp(tonumber(context.Delay) or 1, 0.5, 10)
    self.ShowAnimation = context.ShowAnimation == true
    self.AutoEnabled = false
    self.Busy = false
    self.Opened = 0
    self.Status = "Idle"
    self.LastDrop = "-"
    self.LastRarity = nil
    self._database = nil
    self._profile = nil
    self._worker = nil
    self._destroyed = false
    self._maid = Maid.new()

    return self
end

function BoxFarm:_loadModule(parent, name)
    if not parent then
        return nil
    end
    local module = parent:FindFirstChild(name)
    if not module then
        return nil
    end
    local ok, value = pcall(require, module)
    if ok and type(value) == "table" then
        return value
    end
    return nil
end

function BoxFarm:_getDatabase()
    if self._database then
        return self._database
    end
    self._database = self:_loadModule(self.Storage:FindFirstChild("Database"), "Sync")
    return self._database
end

function BoxFarm:_getProfile()
    if self._profile then
        return self._profile
    end
    self._profile = self:_loadModule(self.Storage:FindFirstChild("Modules"), "ProfileData")
    return self._profile
end

function BoxFarm:GetCatalog()
    local database = self:_getDatabase()
    local result = {}
    if not database then
        return result
    end

    local source = database.NewShop
    if type(source) == "table" then
        for id, item in pairs(source) do
            if type(item) ~= "table" or item.Type ~= "MysteryBox"
                or type(item.Price) ~= "table" or item.Price.Robux ~= nil then
                continue
            end
            local description = database.MysteryBox and database.MysteryBox[id]
            table.insert(result, {
                Id = tostring(id),
                Name = tostring(description and (description.ItemName or description.Name) or id),
                Price = item.Price,
                Order = tonumber(item.LayoutOrder) or 999,
            })
        end
    end

    if #result == 0 and type(database.Shop) == "table"
        and type(database.Shop.Weapons) == "table" then
        for id, item in pairs(database.Shop.Weapons) do
            local description = database.MysteryBox and database.MysteryBox[id]
            if type(description) ~= "table" or type(item) ~= "table"
                or type(item.Price) ~= "table" or item.Price.Robux ~= nil then
                continue
            end
            table.insert(result, {
                Id = tostring(id),
                Name = tostring(description.ItemName or description.Name or id),
                Price = item.Price,
                Order = tonumber(item.LayoutOrder) or 999,
            })
        end
    end

    table.sort(result, function(a, b)
        if a.Order ~= b.Order then
            return a.Order < b.Order
        end
        return a.Name < b.Name
    end)
    return result
end

function BoxFarm:GetBoxOptions()
    local options = {}
    for _, box in ipairs(self:GetCatalog()) do
        table.insert(options, box.Name)
    end
    return options
end

function BoxFarm:SetBox(value)
    if self._destroyed then
        return false
    end

    value = tostring(value or "")
    for _, box in ipairs(self:GetCatalog()) do
        if box.Id == value or box.Name == value then
            self.SelectedBox = box.Id
            self.Status = "Selected: " .. box.Name
            return true
        end
    end
    return false
end

function BoxFarm:SetCurrency(value)
    if self._destroyed then
        return false
    end
    value = tostring(value or "Auto")
    if value ~= "Auto" and CURRENCY_LABELS[value] == nil then
        for id, label in pairs(CURRENCY_LABELS) do
            if label == value then
                value = id
                break
            end
        end
    end
    if CURRENCY_LABELS[value] == nil then
        return false
    end
    self.Currency = value
    return true
end

function BoxFarm:SetDelay(value)
    if self._destroyed then
        return
    end
    self.Delay = math.clamp(tonumber(value) or 1, 0.5, 10)
end

function BoxFarm:SetShowAnimation(value)
    self.ShowAnimation = value == true
end

function BoxFarm:_balance(currency)
    local profile = self:_getProfile()
    if type(profile) ~= "table" then
        return 0
    end

    local value = profile[currency]
    if type(value) ~= "number" and type(profile.Materials) == "table"
        and type(profile.Materials.Owned) == "table" then
        value = profile.Materials.Owned[currency]
    end
    if type(value) ~= "number" and type(profile.Weapons) == "table"
        and type(profile.Weapons.Owned) == "table" then
        value = profile.Weapons.Owned[currency]
    end
    return tonumber(value) or 0
end

function BoxFarm:GetBalance(currency)
    if currency == nil or currency == "Auto" then
        local box = self:_findBox(self.SelectedBox)
        local selected = box and self:_chooseCurrency(box)
        if not selected then
            return 0
        end
        return self:_balance(selected)
    end
    return self:_balance(currency)
end

function BoxFarm:_findBox(id)
    for _, box in ipairs(self:GetCatalog()) do
        if box.Id == id or box.Name == id then
            return box
        end
    end
    return nil
end

function BoxFarm:_chooseCurrency(box)
    if not box then
        return nil, nil
    end

    if self.Currency ~= "Auto" then
        local price = tonumber(box.Price[self.Currency])
        if price and self:_balance(self.Currency) >= price then
            return self.Currency, price
        end
        return nil, price
    end

    local fallback
    for _, currency in ipairs(CURRENCY_ORDER) do
        local price = tonumber(box.Price[currency])
        if not price then
            continue
        end
        fallback = fallback or currency
        if self:_balance(currency) >= price then
            return currency, price
        end
    end
    return nil, nil, fallback
end

function BoxFarm:_notify(title, message, kind)
    if type(self.Notify) == "function" then
        pcall(self.Notify, title, message, kind or "Info")
    end
end

function BoxFarm:OpenOnce()
    if self._destroyed then
        return false, "Destroyed"
    end
    if self.Busy then
        return false, "Busy"
    end

    local box = self:_findBox(self.SelectedBox)
    if not box then
        self.Status = "Choose a box"
        return false, self.Status
    end

    local currency, _, fallback = self:_chooseCurrency(box)
    if not currency then
        self.Status = "Not enough currency"
        if fallback then
            self.Status = "Not enough " .. (CURRENCY_LABELS[fallback] or fallback)
        end
        return false, self.Status
    end

    local remotes = self.Storage:FindFirstChild("Remotes")
    local shop = remotes and remotes:FindFirstChild("Shop")
    local openRemote = shop and shop:FindFirstChild("OpenCrate")
    if not openRemote or not openRemote:IsA("RemoteFunction") then
        self.Status = "OpenCrate unavailable"
        return false, self.Status
    end

    self.Busy = true
    self.Status = "Opening"
    local ok, reward = pcall(function()
        return openRemote:InvokeServer(box.Id, "MysteryBox", currency)
    end)
    self.Busy = false

    if not ok or reward == nil or reward == false then
        self.Status = "Open failed"
        return false, self.Status
    end

    self.Opened += 1
    self.LastDrop = tostring(reward)
    local database = self:_getDatabase()
    local weapon = database and database.Weapons and database.Weapons[reward]
    local rarity = weapon and tostring(weapon.Rarity or "") or ""
    self.LastRarity = rarity ~= "" and rarity or nil
    self.Status = "Opened " .. box.Name

    if self.ShowAnimation and shop then
        local controller = shop:FindFirstChild("BoxController")
        if controller and controller:IsA("BindableEvent") then
            pcall(function()
                controller:Fire({{MysteryBoxId = box.Id, RewardedItemId = reward}})
            end)
        end
    end

    if self.LastRarity and RARE_RARITIES[self.LastRarity] then
        self:_notify(self.LastRarity .. " drop", self.LastDrop, "Success")
    end
    return true, self.LastDrop
end

function BoxFarm:SetAuto(enabled)
    if self._destroyed then
        return false
    end

    local nextValue = enabled == true
    if nextValue == self.AutoEnabled then
        return true
    end
    self.AutoEnabled = nextValue

    if not nextValue then
        if self._worker then
            self._maid:Remove("auto-worker")
            self._worker = nil
        end
        if not self.Busy then
            self.Status = "Idle"
        end
        return true
    end

    self._worker = task.spawn(function()
        while self.AutoEnabled and not self._destroyed do
            local ok = self:OpenOnce()
            task.wait(ok and self.Delay or 2.5)
        end
        self._worker = nil
    end)
    self._maid:Give(self._worker, "auto-worker")
    return true
end

function BoxFarm:GetStats()
    local box = self:_findBox(self.SelectedBox)
    local currency = box and self:_chooseCurrency(box) or nil
    return {
        Opened = self.Opened,
        Status = self.Status,
        LastDrop = self.LastDrop,
        LastRarity = self.LastRarity,
        Balance = currency and self:_balance(currency) or 0,
        Currency = currency and (CURRENCY_LABELS[currency] or currency) or "—",
        Box = box and box.Name or "—",
        Auto = self.AutoEnabled,
    }
end

function BoxFarm:Destroy()
    if self._destroyed then
        return
    end
    self:SetAuto(false)
    self._destroyed = true
    self._maid:Destroy()
end

BoxFarm.CurrencyLabels = CURRENCY_LABELS

return BoxFarm
