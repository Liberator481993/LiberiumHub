-- Liberium Observer v1.0
-- Standalone, opt-in diagnostics for visible Roblox client state.
-- Does NOT inspect executor internals, closures, remote payloads, keys, or another script's source.
-- Start/Stop controls what is recorded. Export writes a local TXT report when writefile is available.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Stats = game:GetService("Stats")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
if not player then return end

local ENV = (getgenv and getgenv()) or _G
if ENV.LiberiumObserver and ENV.LiberiumObserver.Destroy then
    pcall(function() ENV.LiberiumObserver:Destroy() end)
end

local Observer = {
    Version = "1.0",
    Running = false,
    Destroyed = false,
    StartedAt = 0,
    Events = {},
    Connections = {},
    Seen = {},
    MaxEvents = 1200
}
ENV.LiberiumObserver = Observer

local function now()
    return os.date("%H:%M:%S")
end

local function safeText(value)
    value = tostring(value or "")
    value = value:gsub("[%c]", " ")
    if #value > 100 then value = value:sub(1, 100) end
    return value
end

function Observer:Log(kind, detail)
    if not self.Running or self.Destroyed then return end
    if #self.Events >= self.MaxEvents then
        table.remove(self.Events, 1)
    end
    table.insert(self.Events, {
        time = now(),
        kind = safeText(kind),
        detail = safeText(detail)
    })
end

local function guiSummary(root)
    local count, visible = 0, 0
    local classes = {}
    for _, item in ipairs(root:GetDescendants()) do
        if item:IsA("GuiObject") then
            count += 1
            if item.Visible then visible += 1 end
            classes[item.ClassName] = (classes[item.ClassName] or 0) + 1
        end
    end
    local parts = {}
    for className, amount in pairs(classes) do
        table.insert(parts, className .. "=" .. amount)
    end
    table.sort(parts)
    return "gui=" .. count .. ", visible=" .. visible .. ", types={" .. table.concat(parts, ",") .. "}"
end

local function inspectScreenGui(gui)
    if not gui:IsA("ScreenGui") then return end
    local key = gui.Name .. "|" .. gui:GetFullName()
    if Observer.Seen[key] then return end
    Observer.Seen[key] = true
    Observer:Log("UI_ADDED", gui.Name .. " | " .. guiSummary(gui))
end

local function bindVisibleUi()
    local pg = player:FindFirstChildOfClass("PlayerGui")
    if not pg then return end
    for _, child in ipairs(pg:GetChildren()) do
        inspectScreenGui(child)
    end
    table.insert(Observer.Connections, pg.ChildAdded:Connect(function(child)
        if child:IsA("ScreenGui") then
            task.wait(0.15)
            inspectScreenGui(child)
        end
    end))
    table.insert(Observer.Connections, pg.ChildRemoved:Connect(function(child)
        if child:IsA("ScreenGui") then
            Observer:Log("UI_REMOVED", child.Name)
        end
    end))
end

local function getPing()
    local ok, value = pcall(function()
        return Stats.Network.ServerStatsItem["Data Ping"]:GetValueString()
    end)
    return ok and safeText(value) or "unavailable"
end

local function getFps()
    local ok, value = pcall(function()
        return Stats:GetValue("FrameRate")
    end)
    return ok and tostring(math.floor(value + 0.5)) or "unavailable"
end

function Observer:Start()
    if self.Destroyed or self.Running then return end
    self.Running = true
    self.StartedAt = os.clock()
    self:Log("SESSION", "Recording started; visible client diagnostics only")
    bindVisibleUi()
    self:Log("SNAPSHOT", "PlayerGui " .. (player:FindFirstChildOfClass("PlayerGui") and guiSummary(player:FindFirstChildOfClass("PlayerGui")) or "unavailable"))
    self:Log("SNAPSHOT", "Ping=" .. getPing() .. ", FPS=" .. getFps())
end

function Observer:Stop()
    if not self.Running then return end
    self:Log("SESSION", "Recording stopped")
    self.Running = false
    for _, connection in ipairs(self.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(self.Connections)
end

function Observer:Export()
    local lines = {
        "LIBERIUM OBSERVER v" .. self.Version,
        "Generated: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "PlaceId: " .. tostring(game.PlaceId),
        "JobId: " .. safeText(game.JobId),
        "Player: " .. safeText(player.Name),
        "Ping: " .. getPing(),
        "FPS: " .. getFps(),
        "Events: " .. tostring(#self.Events),
        "NOTE: This report contains visible UI metadata and local performance readings only.",
        "------------------------------------------------------------"
    }
    for _, event in ipairs(self.Events) do
        table.insert(lines, "[" .. event.time .. "] " .. event.kind .. " | " .. event.detail)
    end
    local report = table.concat(lines, "\n")
    local filename = "LiberiumObserver_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
    local saved = false
    if type(writefile) == "function" then
        saved = pcall(writefile, filename, report)
    end
    if not saved and type(setclipboard) == "function" then
        pcall(setclipboard, report)
    end
    return saved and filename or (type(setclipboard) == "function" and "copied-to-clipboard" or report)
end

function Observer:Destroy()
    if self.Destroyed then return end
    self:Stop()
    self.Destroyed = true
    if self.Gui then pcall(function() self.Gui:Destroy() end) end
    if ENV.LiberiumObserver == self then ENV.LiberiumObserver = nil end
end

-- Small mobile-friendly control panel.
local gui = Instance.new("ScreenGui")
gui.Name = "LiberiumObserver"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
pcall(function() gui.Parent = game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = player:WaitForChild("PlayerGui") end
Observer.Gui = gui

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.fromOffset(220, 154)
panel.Position = UDim2.new(0, 12, 0.5, -77)
panel.BackgroundColor3 = Color3.fromRGB(15, 18, 30)
panel.BorderSizePixel = 0
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 12)
local stroke = Instance.new("UIStroke", panel)
stroke.Color = Color3.fromRGB(120, 95, 210)
stroke.Transparency = 0.25

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -16, 0, 28)
title.Position = UDim2.fromOffset(8, 5)
title.BackgroundTransparency = 1
title.Text = "LIBERIUM OBSERVER"
title.TextColor3 = Color3.fromRGB(220, 225, 245)
title.Font = Enum.Font.GothamBold
title.TextSize = 13
title.Parent = panel

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -16, 0, 20)
status.Position = UDim2.fromOffset(8, 31)
status.BackgroundTransparency = 1
status.Text = "Status: idle"
status.TextColor3 = Color3.fromRGB(160, 170, 195)
status.Font = Enum.Font.Gotham
status.TextSize = 11
status.Parent = panel

local function makeButton(label, y, callback, color)
    local button = Instance.new("TextButton")
    button.Size = UDim2.new(1, -16, 0, 27)
    button.Position = UDim2.fromOffset(8, y)
    button.BackgroundColor3 = color
    button.BorderSizePixel = 0
    button.Text = label
    button.TextColor3 = Color3.fromRGB(245, 245, 255)
    button.Font = Enum.Font.GothamSemibold
    button.TextSize = 12
    button.Parent = panel
    Instance.new("UICorner", button).CornerRadius = UDim.new(0, 7)
    button.Activated:Connect(callback)
    return button
end

makeButton("START RECORDING", 55, function()
    Observer:Start()
    status.Text = "Status: recording"
    status.TextColor3 = Color3.fromRGB(100, 225, 170)
end, Color3.fromRGB(42, 92, 78))

makeButton("STOP RECORDING", 86, function()
    Observer:Stop()
    status.Text = "Status: stopped"
    status.TextColor3 = Color3.fromRGB(240, 190, 100)
end, Color3.fromRGB(95, 68, 48))

makeButton("EXPORT REPORT", 117, function()
    Observer:Stop()
    local result = Observer:Export()
    status.Text = "Export: " .. safeText(result)
end, Color3.fromRGB(70, 65, 125))

-- Start in idle mode: nothing is recorded until the user presses Start.
