--[[
MM2 INVENTORY DETECTIVE v1.0
Read-only diagnostic for MM2 inventory UI.
Does NOT modify trades, inventory items, remotes, or game state.
Run while the MM2 inventory is OPEN. Press SCAN, then COPY REPORT.
]]

local Players = game:GetService("Players")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local UserInputService = game:GetService("UserInputService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[MM2 DETECTIVE] LocalPlayer unavailable.")
    return
end

local old = nil
pcall(function()
    old = CoreGui:FindFirstChild("MM2InventoryDetective")
end)
if old then pcall(function() old:Destroy() end) end

local COLORS = {
    bg = Color3.fromRGB(13, 16, 25),
    panel = Color3.fromRGB(22, 27, 41),
    panel2 = Color3.fromRGB(29, 36, 53),
    text = Color3.fromRGB(235, 241, 255),
    muted = Color3.fromRGB(145, 158, 184),
    cyan = Color3.fromRGB(75, 218, 255),
    green = Color3.fromRGB(104, 230, 170),
    red = Color3.fromRGB(255, 112, 126)
}

local function make(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do
        pcall(function() obj[k] = v end)
    end
    obj.Parent = parent
    return obj
end

local gui = make("ScreenGui", {
    Name = "MM2InventoryDetective",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
})

local parented = false
pcall(function()
    gui.Parent = CoreGui
    parented = true
end)
if not parented then
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")
end

local frame = make("Frame", {
    Name = "Window",
    Size = UDim2.new(0, 330, 0, 205),
    Position = UDim2.new(0.5, -165, 0.5, -102),
    BackgroundColor3 = COLORS.bg,
    BorderSizePixel = 0,
    Active = true
}, gui)
make("UICorner", {CornerRadius = UDim.new(0, 12)}, frame)
make("UIStroke", {Color = COLORS.cyan, Transparency = 0.55, Thickness = 1}, frame)

local top = make("Frame", {
    Size = UDim2.new(1, 0, 0, 38),
    BackgroundColor3 = COLORS.panel,
    BorderSizePixel = 0
}, frame)
make("UICorner", {CornerRadius = UDim.new(0, 12)}, top)
make("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 0),
    Size = UDim2.new(1, -52, 1, 0),
    Font = Enum.Font.GothamBold,
    Text = "MM2  /  INVENTORY DETECTIVE",
    TextColor3 = COLORS.cyan,
    TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left
}, top)

local close = make("TextButton", {
    Size = UDim2.new(0, 32, 0, 28),
    Position = UDim2.new(1, -36, 0, 5),
    BackgroundColor3 = COLORS.panel2,
    Text = "×",
    TextColor3 = COLORS.text,
    TextSize = 20,
    Font = Enum.Font.GothamBold,
    BorderSizePixel = 0
}, top)
make("UICorner", {CornerRadius = UDim.new(0, 7)}, close)

local status = make("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 47),
    Size = UDim2.new(1, -24, 0, 35),
    Font = Enum.Font.Gotham,
    Text = "Открой инвентарь MM2 и нажми SCAN.",
    TextColor3 = COLORS.text,
    TextSize = 12,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left
}, frame)

local scan = make("TextButton", {
    Position = UDim2.new(0, 12, 0, 91),
    Size = UDim2.new(0.5, -18, 0, 38),
    BackgroundColor3 = Color3.fromRGB(35, 113, 145),
    Text = "SCAN INVENTORY",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    BorderSizePixel = 0
}, frame)
make("UICorner", {CornerRadius = UDim.new(0, 8)}, scan)

local copy = make("TextButton", {
    Position = UDim2.new(0.5, 6, 0, 91),
    Size = UDim2.new(0.5, -18, 0, 38),
    BackgroundColor3 = Color3.fromRGB(42, 112, 82),
    Text = "COPY REPORT",
    TextColor3 = Color3.new(1, 1, 1),
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    BorderSizePixel = 0
}, frame)
make("UICorner", {CornerRadius = UDim.new(0, 8)}, copy)

local hint = make("TextLabel", {
    BackgroundTransparency = 1,
    Position = UDim2.new(0, 12, 0, 139),
    Size = UDim2.new(1, -24, 0, 53),
    Font = Enum.Font.Gotham,
    Text = "Отчёт содержит только структуру UI и найденные подписи. Никакие игровые действия не выполняются.",
    TextColor3 = COLORS.muted,
    TextSize = 10,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top
}, frame)

local report = ""
local scanning = false

local function safeGet(obj, key)
    local value
    local ok = pcall(function() value = obj[key] end)
    if ok then return value end
    return nil
end

local function clean(value, maxLen)
    local s = tostring(value or "")
    s = s:gsub("[%c]", " "):gsub("%s+", " ")
    if #s > (maxLen or 100) then
        s = s:sub(1, maxLen or 100) .. "..."
    end
    return s
end

local function isInventoryText(s)
    s = string.lower(s or "")
    local keys = {
        "inventory", "weapons", "effects", "pets", "radio",
        "classic", "vintage", "legendary", "godly", "ancient",
        "common", "uncommon", "rare", "search", "sort",
        "equipped", "unbox", "trade"
    }
    for _, key in ipairs(keys) do
        if string.find(s, key, 1, true) then return true end
    end
    return false
end

local function getRoots()
    local roots = {}
    local seen = {}
    local function add(root, label)
        if root and not seen[root] then
            seen[root] = true
            table.insert(roots, {instance = root, label = label})
        end
    end
    add(safeGet(LocalPlayer, "PlayerGui"), "PlayerGui")
    add(CoreGui, "CoreGui")
    return roots
end

local function scanNow()
    if scanning then return end
    scanning = true
    status.Text = "Сканирую интерфейс... не закрывай инвентарь."
    task.wait(0.15)

    local lines = {}
    local counts = {
        roots = 0, descendants = 0, gui = 0, text = 0,
        images = 0, buttons = 0, inventoryHints = 0, errors = 0
    }
    local maxLines = 650
    local function addLine(line)
        if #lines < maxLines then
            table.insert(lines, line)
        end
    end

    addLine("MM2 INVENTORY DETECTIVE REPORT")
    addLine("Time: " .. os.date("!%Y-%m-%d %H:%M:%S UTC"))
    addLine("PlaceId: " .. tostring(game.PlaceId))
    addLine("JobId: " .. clean(game.JobId, 80))
    addLine("Executor/UI read-only inspection")
    addLine("")

    for _, rootInfo in ipairs(getRoots()) do
        counts.roots = counts.roots + 1
        local root = rootInfo.instance
        addLine("===== ROOT: " .. rootInfo.label .. " / " .. clean(root.Name, 80) .. " =====")

        local descendants = {}
        local ok, result = pcall(function() return root:GetDescendants() end)
        if ok and type(result) == "table" then
            descendants = result
        else
            counts.errors = counts.errors + 1
        end

        local rootLines = {}
        for _, obj in ipairs(descendants) do
            counts.descendants = counts.descendants + 1
            local class = safeGet(obj, "ClassName") or "?"
            local name = clean(safeGet(obj, "Name"), 70)
            local pathParts = {}
            local cursor = obj
            for _ = 1, 5 do
                if not cursor then break end
                table.insert(pathParts, 1, clean(safeGet(cursor, "Name"), 35))
                cursor = safeGet(cursor, "Parent")
            end
            local path = table.concat(pathParts, "/")
            local textValue = safeGet(obj, "Text")
            local image = safeGet(obj, "Image")
            local visible = safeGet(obj, "Visible")
            local layoutOrder = safeGet(obj, "LayoutOrder")
            local size = safeGet(obj, "AbsoluteSize")
            local attrs = {}
            pcall(function()
                for attrName, attrValue in pairs(obj:GetAttributes()) do
                    if #attrs < 8 then
                        table.insert(attrs, clean(attrName, 30) .. "=" .. clean(attrValue, 60))
                    end
                end
            end)

            local isGui = pcall(function() return obj:IsA("GuiObject") end)
            if isGui then counts.gui = counts.gui + 1 end

            local details = {}
            if type(textValue) == "string" and textValue ~= "" then
                counts.text = counts.text + 1
                table.insert(details, 'Text="' .. clean(textValue, 90) .. '"')
                if isInventoryText(textValue) then
                    counts.inventoryHints = counts.inventoryHints + 1
                end
            end
            if type(image) == "string" and image ~= "" then
                counts.images = counts.images + 1
                table.insert(details, 'Image="' .. clean(image, 100) .. '"')
            end
            if class == "ImageButton" or class == "ImageLabel" then
                counts.images = counts.images + 0
            end
            if class == "TextButton" or class == "ImageButton" then
                counts.buttons = counts.buttons + 1
            end
            if visible ~= nil then table.insert(details, "Visible=" .. tostring(visible)) end
            if layoutOrder ~= nil then table.insert(details, "Order=" .. tostring(layoutOrder)) end
            if size then
                table.insert(details, "Size=" .. tostring(math.floor(size.X)) .. "x" .. tostring(math.floor(size.Y)))
            end
            if #attrs > 0 then table.insert(details, "Attrs={" .. table.concat(attrs, "; ") .. "}") end

            local line = "[" .. class .. "] " .. path
            if #details > 0 then line = line .. " | " .. table.concat(details, " | ") end

            local likely = isInventoryText(name) or (type(textValue) == "string" and isInventoryText(textValue))
                or class == "ImageButton" or class == "ImageLabel"
            if likely and #rootLines < 500 then
                table.insert(rootLines, line)
            end
        end

        addLine("Descendants: " .. tostring(#descendants))
        addLine("Potential inventory/UI nodes (filtered): " .. tostring(#rootLines))
        for _, line in ipairs(rootLines) do addLine(line) end
        addLine("")
    end

    addLine("===== SUMMARY =====")
    for key, value in pairs(counts) do
        addLine(key .. ": " .. tostring(value))
    end
    addLine("Report line cap: " .. tostring(maxLines))
    addLine("Note: this scan can only inspect replicated/client-visible UI objects.")
    report = table.concat(lines, "\n")
    status.Text = "Готово. Найдено объектов: " .. tostring(counts.descendants) .. ". Нажми COPY REPORT."
    scanning = false
end

scan.MouseButton1Click:Connect(scanNow)

copy.MouseButton1Click:Connect(function()
    if report == "" then
        status.Text = "Сначала нажми SCAN INVENTORY."
        return
    end
    local copied = false
    if type(setclipboard) == "function" then
        copied = pcall(setclipboard, report)
    end
    if copied then
        status.Text = "Отчёт скопирован. Вставь его сюда."
    else
        status.Text = "Clipboard недоступен. Отчёт отправлен в консоль через warn."
        warn(report)
    end
end)

close.MouseButton1Click:Connect(function()
    pcall(function() gui:Destroy() end)
end)

-- Drag window (mouse + touch)
local dragging, dragInput, dragStart, startPos
top.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPos = frame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
top.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local delta = input.Position - dragStart
        frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
            startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)

warn("[MM2 DETECTIVE] Loaded. Open MM2 inventory, press SCAN INVENTORY, then COPY REPORT.")
