-- Liberium Hub | Neon Glass UI test module
-- UI-only preview. No MM2 gameplay, automation, ESP, combat, or movement actions.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local UI = {}
local C = {
    bg = Color3.fromRGB(8, 10, 18),
    panel = Color3.fromRGB(15, 18, 30),
    surface = Color3.fromRGB(21, 24, 39),
    surface2 = Color3.fromRGB(27, 30, 48),
    violet = Color3.fromRGB(160, 112, 255),
    cyan = Color3.fromRGB(73, 218, 255),
    green = Color3.fromRGB(87, 231, 174),
    white = Color3.fromRGB(242, 244, 255),
    muted = Color3.fromRGB(145, 153, 180),
    stroke = Color3.fromRGB(91, 91, 135)
}
local function make(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function round(obj, radius)
    make("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, obj)
end
local function outline(obj, color, transparency)
    make("UIStroke", {Color = color or C.stroke, Transparency = transparency or 0.55, Thickness = 1}, obj)
end
local function text(parent, value, size, color, font)
    return make("TextLabel", {
        BackgroundTransparency = 1, Text = value, Font = font or Enum.Font.GothamMedium,
        TextSize = size or 13, TextColor3 = color or C.white,
        TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.new(1, 0, 0, 22)
    }, parent)
end
local function button(parent, value, size)
    local b = make("TextButton", {
        AutoButtonColor = false, Text = value, Font = Enum.Font.GothamSemibold,
        TextSize = 12, TextColor3 = C.white, BackgroundColor3 = C.surface2,
        Size = size or UDim2.new(1, 0, 0, 42)
    }, parent)
    round(b, 10); outline(b, C.stroke, 0.65)
    b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = Color3.fromRGB(36, 39, 60)}):Play() end)
    b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), {BackgroundColor3 = C.surface2}):Play() end)
    return b
end

function UI.new()
    local player = Players.LocalPlayer
    local playerGui = player:WaitForChild("PlayerGui")
    local old = playerGui:FindFirstChild("LiberiumNeonGlassTest")
    if old then old:Destroy() end

    local gui = make("ScreenGui", {
        Name = "LiberiumNeonGlassTest", ResetOnSpawn = false,
        IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 100
    }, playerGui)

    local scale = make("UIScale", {Scale = 1}, gui)
    local camera = workspace.CurrentCamera
    local function resize()
        local vp = camera and camera.ViewportSize or Vector2.new(800, 600)
        scale.Scale = math.clamp(math.min(vp.X / 760, vp.Y / 590), 0.68, 1)
    end
    resize()
    if camera then camera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end

    local shell = make("Frame", {
        Name = "Window", AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(720, 500),
        BackgroundColor3 = C.bg, BorderSizePixel = 0, ClipsDescendants = true
    }, gui)
    round(shell, 18); outline(shell, C.violet, 0.25)
    make("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(17, 19, 34)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(8, 10, 18))
        }), Rotation = 35
    }, shell)

    local top = make("Frame", {BackgroundColor3 = C.panel, BackgroundTransparency = 0.08, Size = UDim2.new(1, 0, 0, 66), BorderSizePixel = 0}, shell)
    local brand = text(top, "LIBERIUM", 17, C.white, Enum.Font.GothamBlack)
    brand.Position = UDim2.fromOffset(20, 8); brand.Size = UDim2.fromOffset(180, 24)
    local subtitle = text(top, "NEON GLASS  /  UI PREVIEW", 9, C.muted)
    subtitle.Position = UDim2.fromOffset(21, 34); subtitle.Size = UDim2.fromOffset(240, 16)
    local status = make("TextLabel", {
        BackgroundTransparency = 1, Text = "●  UI TEST BUILD", Font = Enum.Font.GothamBold,
        TextSize = 9, TextColor3 = C.green, TextXAlignment = Enum.TextXAlignment.Right,
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -105, 0, 23), Size = UDim2.fromOffset(150, 18)
    }, top)
    local close = button(top, "×", UDim2.fromOffset(34, 34))
    close.Position = UDim2.new(1, -48, 0, 16); close.TextSize = 20
    local minimize = button(top, "—", UDim2.fromOffset(34, 34))
    minimize.Position = UDim2.new(1, -88, 0, 16); minimize.TextSize = 16

    local sidebar = make("Frame", {BackgroundColor3 = C.panel, BackgroundTransparency = 0.08, Position = UDim2.fromOffset(0, 66), Size = UDim2.new(0, 174, 1, -66), BorderSizePixel = 0}, shell)
    local sidePad = make("UIPadding", {PaddingTop = UDim.new(0, 17), PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12)}, sidebar)
    local sideList = make("UIListLayout", {Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder}, sidebar)
    local content = make("Frame", {BackgroundTransparency = 1, Position = UDim2.fromOffset(190, 82), Size = UDim2.new(1, -208, 1, -98)}, shell)

    local pages, navButtons = {}, {}
    local toast = make("TextLabel", {
        BackgroundColor3 = C.surface2, BackgroundTransparency = 0.04,
        Position = UDim2.new(0.5, 0, 1, -18), AnchorPoint = Vector2.new(0.5, 1),
        Size = UDim2.fromOffset(270, 34), Visible = false, Text = "",
        TextColor3 = C.white, TextSize = 11, Font = Enum.Font.GothamMedium
    }, shell)
    round(toast, 9); outline(toast, C.cyan, 0.35)
    local toastToken = 0
    local function notify(message)
        toastToken += 1
        local token = toastToken
        toast.Text = message; toast.Visible = true
        task.delay(1.8, function() if toastToken == token then toast.Visible = false end end)
    end

    local function showPage(name)
        for pageName, page in pairs(pages) do page.Visible = pageName == name end
        for navName, nav in pairs(navButtons) do
            local active = navName == name
            nav.BackgroundColor3 = active and Color3.fromRGB(43, 35, 68) or C.surface
            nav.TextColor3 = active and C.white or C.muted
            local rail = nav:FindFirstChild("ActiveRail")
            if rail then rail.BackgroundTransparency = active and 0 or 1 end
        end
    end

    local function addPage(name, icon, description)
        local nav = button(sidebar, icon .. "   " .. name, UDim2.new(1, 0, 0, 43))
        nav.TextXAlignment = Enum.TextXAlignment.Left
        nav.TextSize = 12
        local inset = make("UIPadding", {PaddingLeft = UDim.new(0, 12)}, nav)
        local rail = make("Frame", {Name = "ActiveRail", BackgroundColor3 = C.cyan, BackgroundTransparency = 1, Size = UDim2.new(0, 3, 1, -12), Position = UDim2.fromOffset(0, 6), BorderSizePixel = 0}, nav)
        round(rail, 3)
        local page = make("ScrollingFrame", {
            Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
            AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3,
            ScrollBarImageColor3 = C.violet, Visible = false
        }, content)
        make("UIPadding", {PaddingTop = UDim.new(0, 3), PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 5)}, page)
        make("UIListLayout", {Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder}, page)
        local heading = text(page, name, 20, C.white, Enum.Font.GothamBold)
        heading.Size = UDim2.new(1, 0, 0, 30)
        local desc = text(page, description, 11, C.muted)
        desc.Size = UDim2.new(1, 0, 0, 23)
        pages[name], navButtons[name] = page, nav
        nav.MouseButton1Click:Connect(function() showPage(name) end)
        return page
    end

    local function section(parent, titleText, note)
        local card = make("Frame", {BackgroundColor3 = C.surface, Size = UDim2.new(1, -4, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BorderSizePixel = 0}, parent)
        round(card, 12); outline(card, C.stroke, 0.72)
        make("UIPadding", {PaddingTop = UDim.new(0, 13), PaddingBottom = UDim.new(0, 13), PaddingLeft = UDim.new(0, 13), PaddingRight = UDim.new(0, 13)}, card)
        local list = make("UIListLayout", {Padding = UDim.new(0, 9), SortOrder = Enum.SortOrder.LayoutOrder}, card)
        local title = text(card, titleText, 12, C.cyan, Enum.Font.GothamBold)
        title.Size = UDim2.new(1, 0, 0, 20)
        if note then local n = text(card, note, 10, C.muted); n.Size = UDim2.new(1, 0, 0, 18) end
        return card
    end

    local function demoToggle(parent, labelText, default)
        local row = make("Frame", {BackgroundColor3 = C.surface2, Size = UDim2.new(1, 0, 0, 42), BorderSizePixel = 0}, parent)
        round(row, 9)
        local label = text(row, labelText, 11, C.white)
        label.Position = UDim2.fromOffset(11, 0); label.Size = UDim2.new(1, -70, 1, 0)
        local toggle = make("TextButton", {Text = "", AutoButtonColor = false, BackgroundColor3 = default and C.violet or C.stroke, Position = UDim2.new(1, -48, 0.5, -10), Size = UDim2.fromOffset(37, 20)}, row)
        round(toggle, 10)
        local knob = make("Frame", {BackgroundColor3 = C.white, Position = default and UDim2.fromOffset(19, 2) or UDim2.fromOffset(2, 2), Size = UDim2.fromOffset(16, 16)}, toggle)
        round(knob, 8)
        local state = default
        toggle.MouseButton1Click:Connect(function()
            state = not state
            TweenService:Create(toggle, TweenInfo.new(0.14), {BackgroundColor3 = state and C.violet or C.stroke}):Play()
            TweenService:Create(knob, TweenInfo.new(0.14), {Position = state and UDim2.fromOffset(19, 2) or UDim2.fromOffset(2, 2)}):Play()
            notify(labelText .. (state and "  ON" or "  OFF"))
        end)
    end

    local home = addPage("Dashboard", "⌂", "A clean preview of the redesigned hub interface.")
    local homeCard = section(home, "WELCOME BACK", "Liberium Hub • Neon Glass interface test")
    local welcome = text(homeCard, "This is a UI-only build. Controls below are visual demonstrations and do not affect the game.", 11, C.white)
    welcome.Size = UDim2.new(1, 0, 0, 42); welcome.TextWrapped = true; welcome.TextYAlignment = Enum.TextYAlignment.Top
    local testCard = section(home, "INTERACTION CHECK", "Tap each control to verify touch input.")
    local testButton = button(testCard, "TEST NOTIFICATION")
    testButton.MouseButton1Click:Connect(function() notify("Touch input is working ✓") end)
    demoToggle(testCard, "Demo toggle", false)

    local farm = addPage("Farm", "◈", "Demo controls only — no collection or movement code.")
    local farmCard = section(farm, "AUTOFARM PREVIEW", "Visual-only state controls")
    demoToggle(farmCard, "AutoFarm UI state", false)
    demoToggle(farmCard, "AutoPickup UI state", false)

    local visuals = addPage("Visuals", "◉", "Preview the spacing and touch targets.")
    local visualCard = section(visuals, "ESP PREVIEW", "These switches only demonstrate the interface.")
    demoToggle(visualCard, "Outline toggle", false)
    demoToggle(visualCard, "Fill toggle", false)
    demoToggle(visualCard, "Candy ESP toggle", false)

    local settings = addPage("Settings", "⚙", "Window behavior and test information.")
    local settingsCard = section(settings, "WINDOW", "Use the top-right controls to minimize or close.")
    local info = text(settingsCard, "Drag the top bar to move the window. Re-run the loader to reopen this preview.", 11, C.white)
    info.Size = UDim2.new(1, 0, 0, 36); info.TextWrapped = true
    local resetButton = button(settingsCard, "RESET WINDOW POSITION")
    resetButton.MouseButton1Click:Connect(function()
        shell.Position = UDim2.fromScale(0.5, 0.5); notify("Window position reset")
    end)

    showPage("Dashboard")
    local minimized = false
    minimize.MouseButton1Click:Connect(function()
        minimized = not minimized
        sidebar.Visible = not minimized; content.Visible = not minimized
        shell.Size = minimized and UDim2.fromOffset(720, 66) or UDim2.fromOffset(720, 500)
        minimize.Text = minimized and "□" or "—"
    end)
    close.MouseButton1Click:Connect(function() gui:Destroy() end)

    local dragging, dragInput, dragStart, startPos
    top.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true; dragStart = input.Position; startPos = shell.Position
            input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
        end
    end)
    top.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input == dragInput or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            shell.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)

    return {
        Gui = gui,
        Destroy = function() if gui then gui:Destroy() end end
    }
end

return UI
