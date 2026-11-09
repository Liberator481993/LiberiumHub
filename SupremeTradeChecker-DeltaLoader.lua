-- Supreme Trade Checker compatibility bootstrap
-- Plain Luau/Lua syntax: intentionally avoids executor-specific globals at startup.
local SOURCE_URL = "https://raw.githubusercontent.com/Liberator481993/LiberiumHub/supreme-trade-checker-rust-core/SupremeTradeChecker.lua"

local Players = game:GetService("Players")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local gui = Instance.new("ScreenGui")
gui.Name = "SupremeDeltaBootstrap"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 10000
gui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(300, 116)
panel.Position = UDim2.new(1, -12, 0, 48)
panel.AnchorPoint = Vector2.new(1, 0)
panel.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
panel.BorderSizePixel = 0
panel.Parent = gui

local label = Instance.new("TextLabel")
label.Size = UDim2.new(1, -16, 1, -16)
label.Position = UDim2.fromOffset(8, 8)
label.BackgroundTransparency = 1
label.Font = Enum.Font.Code
label.TextSize = 12
label.TextColor3 = Color3.fromRGB(235, 240, 250)
label.TextWrapped = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Top
label.Text = "SUPREME BOOTSTRAP\nStarting..."
label.Parent = panel

local function show(message)
    label.Text = "SUPREME BOOTSTRAP\n" .. tostring(message)
end

local function extractBody(response)
    if type(response) == "string" then return response end
    if type(response) == "table" then
        local status = tonumber(response.StatusCode or response.Status or response.status_code)
        local body = response.Body or response.body or response.ResponseBody
        if status and (status < 200 or status >= 300) then
            return nil, "HTTP " .. tostring(status)
        end
        if type(body) == "string" then return body end
    end
    return nil, "empty response"
end

local function fetchWith(fn, labelName)
    if type(fn) ~= "function" then return nil end
    local ok, response = pcall(fn, {
        Url = SOURCE_URL,
        Method = "GET",
        Headers = {["Accept"] = "text/plain"}
    })
    if not ok then return nil, labelName .. ": " .. tostring(response) end
    local body, err = extractBody(response)
    if body and #body > 10000 then return body, labelName end
    return nil, labelName .. ": " .. tostring(err or "invalid source")
end

local source, sourceMethod, errors
errors = {}

local body, method = fetchWith(request, "request")
if body then source, sourceMethod = body, method else
    if method then table.insert(errors, method) end
end

if not source then
    body, method = fetchWith(http_request, "http_request")
    if body then source, sourceMethod = body, method else
        if method then table.insert(errors, method) end
    end
end

if not source then
    local synRequest
    pcall(function() synRequest = syn and syn.request end)
    body, method = fetchWith(synRequest, "syn.request")
    if body then source, sourceMethod = body, method else
        if method then table.insert(errors, method) end
    end
end

if not source then
    local httpRequest
    pcall(function() httpRequest = http and http.request end)
    body, method = fetchWith(httpRequest, "http.request")
    if body then source, sourceMethod = body, method else
        if method then table.insert(errors, method) end
    end
end

if not source then
    local ok, response = pcall(function()
        return game:HttpGet(SOURCE_URL)
    end)
    if ok and type(response) == "string" and #response > 10000 then
        source, sourceMethod = response, "game:HttpGet"
    else
        table.insert(errors, "game:HttpGet: " .. tostring(response))
    end
end

if not source then
    show("SOURCE DOWNLOAD FAILED\n" .. table.concat(errors, "\n"))
    warn("[Supreme Delta Bootstrap] Source download failed: " .. table.concat(errors, " | "))
    return
end

show("Downloaded " .. tostring(#source) .. " chars via " .. sourceMethod .. "\nCompiling...")
if type(loadstring) ~= "function" then
    show("LOADSTRING UNAVAILABLE\nExecutor did not expose loadstring")
    return
end

local chunk, compileError = loadstring(source)
if type(chunk) ~= "function" then
    show("COMPILE FAILED\n" .. tostring(compileError))
    warn("[Supreme Delta Bootstrap] Compile failed: " .. tostring(compileError))
    return
end

show("Compiled successfully\nStarting main script...")
local ok, runtimeError = pcall(chunk)
if not ok then
    show("STARTUP ERROR\n" .. tostring(runtimeError))
    warn("[Supreme Delta Bootstrap] Startup error: " .. tostring(runtimeError))
    return
end

show("MAIN SCRIPT STARTED\nSource: " .. sourceMethod .. "\nIf Supreme panel does not appear in 5 sec, send this status.")
task.delay(8, function()
    if gui and gui.Parent then gui:Destroy() end
end)
print("[Supreme Delta Bootstrap] Main script started via " .. sourceMethod)
