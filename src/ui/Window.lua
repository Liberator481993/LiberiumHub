-- Liberium Hub | Nova-style window and shared component system
-- Original UI implementation. It is designed to replace the renderer behind the
-- existing Lib.new / AddTab / AddSubTab / AddSection feature-facing API.

local ThemeFactory = require(script.Parent.Theme)
local Maid = require(script.Parent.Parent.core.Maid)

local Window = {}
Window.__index = Window

local Tab = {}
Tab.__index = Tab

local SubTab = {}
SubTab.__index = SubTab

local Section = {}
Section.__index = Section

local Control = {}
Control.__index = Control

local DEFAULT_SIZE = Vector2.new(812, 584)
local MIN_SIZE = Vector2.new(660, 420)
local SIDEBAR_WIDTH = 208
local HEADER_HEIGHT = 68

local function create(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function corner(object, radius)
    return create("UICorner", {
        CornerRadius = UDim.new(0, radius or 8),
    }, object)
end

local function stroke(object, color, transparency, thickness)
    return create("UIStroke", {
        Color = color,
        Transparency = transparency or 0,
        Thickness = thickness or 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
    }, object)
end

local function text(parent, value, size, color, font)
    return create("TextLabel", {
        BackgroundTransparency = 1,
        Text = tostring(value or ""),
        TextColor3 = color,
        Font = font or Enum.Font.GothamMedium,
        TextSize = size or 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
        Size = UDim2.fromScale(1, 1),
        ClipsDescendants = true,
    }, parent)
end

local function addPadding(object, left, right, top, bottom)
    return create("UIPadding", {
        PaddingLeft = UDim.new(0, left or 0),
        PaddingRight = UDim.new(0, right or 0),
        PaddingTop = UDim.new(0, top or 0),
        PaddingBottom = UDim.new(0, bottom or 0),
    }, object)
end

local function addList(object, padding, direction)
    return create("UIListLayout", {
        FillDirection = direction or Enum.FillDirection.Vertical,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, padding or 0),
    }, object)
end

local function makeControlHandle(section, name, instance, getValue, setValue)
    local handle = setmetatable({
        Name = name,
        Instance = instance,
        _get = getValue,
        _set = setValue,
    }, Control)
    table.insert(section.Controls, handle)
    return handle
end

function Control:Get()
    return self._get and self._get() or nil
end

function Control:Set(value, silent)
    if self._set then
        self._set(value, silent == true)
    end
end

function Control:Destroy()
    if self.Instance and self.Instance.Parent then
        self.Instance:Destroy()
    end
    self.Instance = nil
end

function Window.new(options)
    options = options or {}

    local player = game:GetService("Players").LocalPlayer
    assert(player, "Liberium UI requires a local player")

    local playerGui = options.Parent or player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        playerGui = player:WaitForChild("PlayerGui", 15)
    end
    assert(playerGui, "Liberium UI could not find PlayerGui")

    local self = setmetatable({}, Window)
    self.Options = options
    self.Title = options.Title or "LIBERIUM HUB"
    self.Subtitle = options.Subtitle or "MURDER MYSTERY 2"
    self.Version = options.Version or "v92"
    self.Size = options.Size or DEFAULT_SIZE
    self.MinSize = options.MinSize or MIN_SIZE
    self.ScaleValue = tonumber(options.Scale) or 0.86
    self.IsOpen = true
    self.Destroyed = false
    self.Tabs = {}
    self.TabList = {}
    self.Groups = {}
    self.CurrentTab = nil
    self.CurrentSubTab = nil
    self._tabOrder = 0
    self._toastOrder = 0
    self._connections = Maid.new()
    self._theme = options.ThemeObject or ThemeFactory.create(options.Theme)
    self._ownsTheme = options.ThemeObject == nil
    self._connections:Give(self._theme:Bind(self._dummy or Instance.new("Folder"), "Name", "Text"), "theme-placeholder")

    self:_mount(playerGui)
    self:_bindViewport()
    return self
end

function Window:_bindColor(object, property, token, key)
    local cleanup = self._theme:Bind(object, property, token)
    self._connections:Give(cleanup, key)
    return object
end

function Window:_mount(parent)
    local theme = self._theme
    local accent = theme:Get("Accent")
    local gui = create("ScreenGui", {
        Name = "LiberiumNovaUI",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        DisplayOrder = 9999,
    }, parent)
    self.Gui = gui
    self._connections:Give(gui, "gui")

    local root = create("Frame", {
        Name = "Root",
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(self.Size.X, self.Size.Y),
        BackgroundTransparency = 1,
        ClipsDescendants = false,
    }, gui)
    self.Root = root
    self.Scale = create("UIScale", {Scale = self.ScaleValue}, root)

    local shadow = create("Frame", {
        Name = "Shadow",
        Position = UDim2.fromOffset(8, 10),
        Size = UDim2.new(1, -16, 1, -16),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BackgroundTransparency = 0.5,
        BorderSizePixel = 0,
        ZIndex = 0,
    }, root)
    corner(shadow, 16)

    local shell = create("Frame", {
        Name = "Window",
        Size = UDim2.fromScale(1, 1),
        BackgroundColor3 = theme:Get("Background"),
        BorderSizePixel = 0,
        ClipsDescendants = true,
        ZIndex = 1,
    }, root)
    self.Shell = shell
    corner(shell, 14)
    self:_bindColor(shell, "BackgroundColor3", "Background", "shell-color")
    self:_bindColor(stroke(shell, theme:Get("Line"), 0.12, 1.1), "Color", "Line", "shell-stroke")

    local sidebar = create("Frame", {
        Name = "Sidebar",
        Size = UDim2.new(0, SIDEBAR_WIDTH, 1, 0),
        BackgroundColor3 = theme:Get("Sidebar"),
        BorderSizePixel = 0,
        ZIndex = 2,
    }, shell)
    self.Sidebar = sidebar
    self:_bindColor(sidebar, "BackgroundColor3", "Sidebar", "sidebar-color")

    local brand = create("Frame", {
        Name = "Brand",
        Position = UDim2.fromOffset(16, 13),
        Size = UDim2.new(1, -32, 0, 52),
        BackgroundTransparency = 1,
    }, sidebar)
    self.Brand = brand

    local logo = create("Frame", {
        Name = "Logo",
        Size = UDim2.fromOffset(34, 34),
        Position = UDim2.fromOffset(0, 7),
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
    }, brand)
    corner(logo, 10)
    self:_bindColor(logo, "BackgroundColor3", "Accent", "brand-logo")
    local logoText = text(logo, "L", 20, theme:Get("OnAccent"), Enum.Font.GothamBlack)
    logoText.TextXAlignment = Enum.TextXAlignment.Center

    local titleBox = create("Frame", {
        Position = UDim2.fromOffset(44, 4),
        Size = UDim2.new(1, -44, 0, 42),
        BackgroundTransparency = 1,
    }, brand)
    local titleText = text(titleBox, self.Title, 13, theme:Get("Text"), Enum.Font.GothamBold)
    titleText.Size = UDim2.new(1, 0, 0, 19)
    titleText.TextTruncate = Enum.TextTruncate.AtEnd
    local subtitleText = text(titleBox, self.Subtitle, 9, theme:Get("Muted"), Enum.Font.GothamMedium)
    subtitleText.Position = UDim2.fromOffset(0, 20)
    subtitleText.Size = UDim2.new(1, 0, 0, 15)
    self.BrandTitle = titleText
    self.BrandSubtitle = subtitleText
    self:_bindColor(titleText, "TextColor3", "Text", "brand-title")
    self:_bindColor(subtitleText, "TextColor3", "Muted", "brand-subtitle")

    local searchWrap = create("Frame", {
        Name = "SearchWrap",
        Position = UDim2.fromOffset(13, 76),
        Size = UDim2.new(1, -26, 0, 36),
        BackgroundColor3 = theme:Get("Surface"),
        BorderSizePixel = 0,
    }, sidebar)
    self.SearchWrap = searchWrap
    corner(searchWrap, 8)
    self:_bindColor(searchWrap, "BackgroundColor3", "Surface", "search-wrap")
    local searchStroke = stroke(searchWrap, theme:Get("Line"), 0.2, 1)
    self:_bindColor(searchStroke, "Color", "Line", "search-stroke")

    local searchIcon = text(searchWrap, "⌕", 18, theme:Get("Muted"), Enum.Font.GothamBold)
    searchIcon.Position = UDim2.fromOffset(9, 0)
    searchIcon.Size = UDim2.fromOffset(22, 36)
    searchIcon.TextXAlignment = Enum.TextXAlignment.Center
    local search = create("TextBox", {
        Name = "Search",
        Position = UDim2.fromOffset(34, 0),
        Size = UDim2.new(1, -42, 1, 0),
        BackgroundTransparency = 1,
        ClearTextOnFocus = false,
        PlaceholderText = "Search tabs and sections",
        PlaceholderColor3 = theme:Get("Faint"),
        Text = "",
        TextColor3 = theme:Get("Text"),
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, searchWrap)
    self.Search = search
    self:_bindColor(search, "TextColor3", "Text", "search-text")
    self:_bindColor(search, "PlaceholderColor3", "Faint", "search-placeholder")

    local nav = create("ScrollingFrame", {
        Name = "Navigation",
        Position = UDim2.fromOffset(8, 122),
        Size = UDim2.new(1, -16, 1, -164),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 2,
        ScrollBarImageColor3 = theme:Get("Faint"),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, sidebar)
    self.Navigation = nav
    addPadding(nav, 3, 3, 4, 8)
    self.NavLayout = addList(nav, 9)

    local footer = create("Frame", {
        Name = "Footer",
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 12, 1, -10),
        Size = UDim2.new(1, -24, 0, 24),
        BackgroundTransparency = 1,
    }, sidebar)
    self.Footer = footer
    local version = text(footer, self.Version, 10, theme:Get("Faint"), Enum.Font.GothamMedium)
    version.Size = UDim2.new(0.48, 0, 1, 0)
    local status = text(footer, "●  READY", 9, theme:Get("Success"), Enum.Font.GothamBold)
    status.AnchorPoint = Vector2.new(1, 0)
    status.Position = UDim2.new(1, 0, 0, 0)
    status.Size = UDim2.new(0.52, 0, 1, 0)
    status.TextXAlignment = Enum.TextXAlignment.Right
    self.FooterStatus = status
    self:_bindColor(version, "TextColor3", "Faint", "footer-version")
    self:_bindColor(status, "TextColor3", "Success", "footer-status")

    local main = create("Frame", {
        Name = "Main",
        Position = UDim2.fromOffset(SIDEBAR_WIDTH, 0),
        Size = UDim2.new(1, -SIDEBAR_WIDTH, 1, 0),
        BackgroundTransparency = 1,
        ZIndex = 2,
    }, shell)
    self.Main = main

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, HEADER_HEIGHT),
        BackgroundTransparency = 1,
    }, main)
    self.Header = header

    local activeTitle = text(header, "Home", 20, theme:Get("Text"), Enum.Font.GothamBold)
    activeTitle.Position = UDim2.fromOffset(24, 10)
    activeTitle.Size = UDim2.new(1, -86, 0, 25)
    activeTitle.TextTruncate = Enum.TextTruncate.AtEnd
    local activeDescription = text(header, "Your session at a glance", 11, theme:Get("Muted"), Enum.Font.Gotham)
    activeDescription.Position = UDim2.fromOffset(24, 37)
    activeDescription.Size = UDim2.new(1, -86, 0, 18)
    activeDescription.TextTruncate = Enum.TextTruncate.AtEnd
    self.ActiveTitle = activeTitle
    self.ActiveDescription = activeDescription
    self:_bindColor(activeTitle, "TextColor3", "Text", "active-title")
    self:_bindColor(activeDescription, "TextColor3", "Muted", "active-description")

    local close = create("TextButton", {
        Name = "Close",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -17, 0, 17),
        Size = UDim2.fromOffset(28, 28),
        BackgroundColor3 = theme:Get("Surface2"),
        BorderSizePixel = 0,
        Text = "×",
        TextSize = 19,
        TextColor3 = theme:Get("Muted"),
        Font = Enum.Font.Gotham,
        AutoButtonColor = false,
    }, header)
    self.CloseButton = close
    corner(close, 8)
    self:_bindColor(close, "BackgroundColor3", "Surface2", "close-background")
    self:_bindColor(close, "TextColor3", "Muted", "close-text")
    self._connections:Connect(close.Activated, function()
        self:SetVisible(false)
    end, "close-click")

    local line = create("Frame", {
        Name = "HeaderLine",
        Position = UDim2.new(0, 20, 0, HEADER_HEIGHT - 1),
        Size = UDim2.new(1, -40, 0, 1),
        BorderSizePixel = 0,
        BackgroundColor3 = theme:Get("Line"),
    }, header)
    self:_bindColor(line, "BackgroundColor3", "Line", "header-line")

    local subNav = create("Frame", {
        Name = "SubNavigation",
        Position = UDim2.fromOffset(22, HEADER_HEIGHT + 5),
        Size = UDim2.new(1, -44, 0, 34),
        BackgroundTransparency = 1,
        Visible = false,
    }, main)
    self.SubNavigation = subNav
    self.SubNavLayout = addList(subNav, 7, Enum.FillDirection.Horizontal)

    local pages = create("Frame", {
        Name = "Pages",
        Position = UDim2.fromOffset(20, HEADER_HEIGHT + 46),
        Size = UDim2.new(1, -40, 1, -(HEADER_HEIGHT + 60)),
        BackgroundTransparency = 1,
        ClipsDescendants = true,
    }, main)
    self.Pages = pages

    self:_bindDragging(header)
    self:_bindSearch()
end

function Window:_bindDragging(handle)
    local inputService = game:GetService("UserInputService")
    local activeInput, startPosition, startRoot
    self._connections:Connect(handle.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseButton1
            and input.UserInputType ~= Enum.UserInputType.Touch then
            return
        end
        activeInput = input
        startPosition = input.Position
        startRoot = self.Root.Position
    end, "drag-began")

    self._connections:Connect(inputService.InputChanged, function(input)
        if not activeInput then
            return
        end
        local matchingTouch = activeInput.UserInputType == Enum.UserInputType.Touch and input == activeInput
        local matchingMouse = activeInput.UserInputType == Enum.UserInputType.MouseButton1
            and input.UserInputType == Enum.UserInputType.MouseMovement
        if not matchingTouch and not matchingMouse then
            return
        end
        local delta = input.Position - startPosition
        self.Root.Position = UDim2.new(
            startRoot.X.Scale, startRoot.X.Offset + delta.X,
            startRoot.Y.Scale, startRoot.Y.Offset + delta.Y
        )
    end, "drag-changed")

    self._connections:Connect(inputService.InputEnded, function(input)
        if activeInput and input == activeInput then
            activeInput = nil
        end
    end, "drag-ended")
end

function Window:_bindViewport()
    local workspace = game:GetService("Workspace")
    local function update()
        local camera = workspace.CurrentCamera
        if not camera or not self.Root or not self.Root.Parent then
            return
        end

        local viewport = camera.ViewportSize
        local width = math.max(1, viewport.X - 24)
        local height = math.max(1, viewport.Y - 24)
        local fit = math.min(width / self.Size.X, height / self.Size.Y)
        local scale = math.min(self.ScaleValue, fit)
        self.Scale.Scale = math.clamp(scale, 0.45, self.ScaleValue)

        local isCompact = self.Scale.Scale < 0.64
        self.BrandSubtitle.Visible = not isCompact
        self.SearchWrap.Visible = not isCompact
        self.Sidebar.Size = UDim2.new(0, isCompact and 178 or SIDEBAR_WIDTH, 1, 0)
        self.Main.Position = UDim2.fromOffset(isCompact and 178 or SIDEBAR_WIDTH, 0)
        self.Main.Size = UDim2.new(1, -(isCompact and 178 or SIDEBAR_WIDTH), 1, 0)
        self.Navigation.Position = UDim2.fromOffset(8, isCompact and 72 or 122)
        self.Navigation.Size = UDim2.new(1, -16, 1, isCompact and -112 or -164)
        if isCompact then
            self.BrandTitle.TextSize = 11
            self.ActiveTitle.TextSize = 17
        else
            self.BrandTitle.TextSize = 13
            self.ActiveTitle.TextSize = 20
        end
    end

    local camera = workspace.CurrentCamera
    if camera then
        self._connections:Connect(camera:GetPropertyChangedSignal("ViewportSize"), update, "viewport")
    end
    self._connections:Connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function()
        local nextCamera = workspace.CurrentCamera
        if nextCamera then
            self._connections:Connect(nextCamera:GetPropertyChangedSignal("ViewportSize"), update, "viewport")
        end
        update()
    end, "camera-change")
    update()
end

function Window:_ensureGroup(name)
    local key = tostring(name or "General")
    if self.Groups[key] then
        return self.Groups[key]
    end

    local theme = self._theme
    local frame = create("Frame", {
        Name = "Group_" .. key:gsub("%W", ""),
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
    }, self.Navigation)

    local heading = create("TextButton", {
        Name = "Heading",
        Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        Text = key:upper() .. "   ▾",
        TextColor3 = theme:Get("Faint"),
        TextSize = 9,
        Font = Enum.Font.GothamBold,
        TextXAlignment = Enum.TextXAlignment.Left,
        AutoButtonColor = false,
    }, frame)

    local entries = create("Frame", {
        Name = "Entries",
        Position = UDim2.fromOffset(0, 25),
        Size = UDim2.new(1, 0, 0, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
    }, frame)
    local layout = addList(entries, 3)

    local group = {
        Name = key,
        Frame = frame,
        Heading = heading,
        Entries = entries,
        Layout = layout,
        Expanded = true,
        Tabs = {},
    }
    self.Groups[key] = group

    self._connections:Connect(heading.Activated, function()
        group.Expanded = not group.Expanded
        entries.Visible = group.Expanded
        heading.Text = key:upper() .. (group.Expanded and "   ▾" or "   ▸")
    end, "group-" .. key)

    self._connections:Give(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        entries.Size = UDim2.new(1, 0, 0, layout.AbsoluteContentSize.Y)
    end))
    return group
end

function Window:_createNavButton(tab)
    local theme = self._theme
    local group = self:_ensureGroup(tab.Group)
    local button = create("TextButton", {
        Name = "Tab_" .. tab.Name:gsub("%W", ""),
        Size = UDim2.new(1, 0, 0, 34),
        BackgroundColor3 = theme:Get("Surface2"),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
    }, group.Entries)
    corner(button, 7)

    local icon = text(button, tab.Icon, 15, theme:Get("Muted"), Enum.Font.GothamBold)
    icon.Position = UDim2.fromOffset(10, 0)
    icon.Size = UDim2.fromOffset(22, 34)
    icon.TextXAlignment = Enum.TextXAlignment.Center

    local label = text(button, tab.Name, 11, theme:Get("Muted"), Enum.Font.GothamMedium)
    label.Position = UDim2.fromOffset(40, 0)
    label.Size = UDim2.new(1, -50, 1, 0)
    label.TextTruncate = Enum.TextTruncate.AtEnd

    tab.NavButton = button
    tab.NavIcon = icon
    tab.NavLabel = label
    table.insert(group.Tabs, tab)

    self._connections:Connect(button.Activated, function()
        self:SelectTab(tab)
    end, "tab-select-" .. tab.Name)
    return button
end

function Window:AddTab(name, icon, options)
    assert(not self.Destroyed, "cannot add a tab to a destroyed window")
    options = options or {}
    name = tostring(name or ("Tab " .. tostring(#self.TabList + 1)))
    assert(not self.Tabs[name], "duplicate tab name: " .. name)

    self._tabOrder += 1
    local tab = setmetatable({
        Window = self,
        Name = name,
        Icon = tostring(icon or "•"),
        Group = options.Group or "General",
        Description = options.Description or "",
        Order = self._tabOrder,
        SubTabs = {},
        Pages = {},
        _defaultSub = nil,
    }, Tab)

    self.Tabs[name] = tab
    table.insert(self.TabList, tab)
    self:_createNavButton(tab)
    tab:_createDefaultPage()

    if not self.CurrentTab then
        self:SelectTab(tab)
    end
    self:_applySearch(self.Search.Text)
    return tab
end

function Tab:_createPage(name, description)
    local window = self.Window
    local page = create("ScrollingFrame", {
        Name = "Page_" .. tostring(name):gsub("%W", ""),
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = window._theme:Get("Faint"),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, window.Pages)
    addPadding(page, 2, 7, 4, 14)
    local layout = addList(page, 12)
    window._connections:Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        page.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 10)
    end)
    return page
end

function Tab:_createDefaultPage()
    if self._defaultSub then
        return self._defaultSub
    end
    local page = self:_createPage(self.Name, self.Description)
    local sub = setmetatable({
        Tab = self,
        Name = self.Name,
        Page = page,
        Button = nil,
        IsDefault = true,
    }, SubTab)
    self._defaultSub = sub
    self.SubTabs[1] = sub
    return sub
end

function Tab:AddSubTab(name, description)
    name = tostring(name or ("Page " .. tostring(#self.SubTabs + 1)))
    if self._defaultSub and self._defaultSub.IsDefault and #self._defaultSub.Page:GetChildren() == 1 then
        self._defaultSub.Page:Destroy()
        self.SubTabs = {}
        self._defaultSub = nil
    end

    for _, existing in ipairs(self.SubTabs) do
        if existing.Name == name then
            return existing
        end
    end

    local page = self:_createPage(name, description)
    local button = create("TextButton", {
        Name = "SubTab_" .. name:gsub("%W", ""),
        Size = UDim2.fromOffset(112, 28),
        BackgroundColor3 = self.Window._theme:Get("Surface2"),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Text = name,
        TextColor3 = self.Window._theme:Get("Muted"),
        TextSize = 10,
        Font = Enum.Font.GothamSemibold,
        AutoButtonColor = false,
    }, self.Window.SubNavigation)
    corner(button, 7)

    local sub = setmetatable({
        Tab = self,
        Name = name,
        Description = description or self.Description,
        Page = page,
        Button = button,
        IsDefault = false,
    }, SubTab)
    table.insert(self.SubTabs, sub)

    self.Window._connections:Connect(button.Activated, function()
        self.Window:SelectSubTab(sub)
    end, "subtab-" .. self.Name .. "-" .. name)

    self.Window.SubNavigation.Visible = true
    if #self.SubTabs == 1 then
        self.Window:SelectSubTab(sub)
    else
        self.Window:_refreshSubTabs(self)
    end
    return sub
end

function SubTab:AddSection(name, options)
    assert(not self.Tab.Window.Destroyed, "cannot add a section to a destroyed window")
    options = options or {}
    name = tostring(name or "Section")

    local theme = self.Tab.Window._theme
    local card = create("Frame", {
        Name = "Section_" .. name:gsub("%W", ""),
        Size = UDim2.new(1, -4, 0, 46),
        BackgroundColor3 = theme:Get("Surface"),
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        ClipsDescendants = false,
    }, self.Page)
    corner(card, 10)
    local cardStroke = stroke(card, theme:Get("Line"), 0.24, 1)
    self.Tab.Window:_bindColor(card, "BackgroundColor3", "Surface")
    self.Tab.Window:_bindColor(cardStroke, "Color", "Line")

    local header = create("Frame", {
        Name = "Header",
        Size = UDim2.new(1, 0, 0, 38),
        BackgroundTransparency = 1,
    }, card)
    local heading = text(header, name, 11, theme:Get("Text"), Enum.Font.GothamBold)
    heading.Position = UDim2.fromOffset(14, 0)
    heading.Size = UDim2.new(1, -28, 1, 0)
    self.Tab.Window:_bindColor(heading, "TextColor3", "Text")

    local content = create("Frame", {
        Name = "Content",
        Position = UDim2.fromOffset(10, 38),
        Size = UDim2.new(1, -20, 0, 0),
        BackgroundTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.Y,
    }, card)
    local layout = addList(content, 7)
    addPadding(content, 0, 0, 0, 10)

    local section = setmetatable({
        Tab = self.Tab,
        SubTab = self,
        Name = name,
        Card = card,
        Header = header,
        Content = content,
        Layout = layout,
        Controls = {},
        _connections = Maid.new(),
    }, Section)

    self.Tab.Window._connections:Give(section._connections)
    section._connections:Connect(layout:GetPropertyChangedSignal("AbsoluteContentSize"), function()
        content.Size = UDim2.new(1, -20, 0, layout.AbsoluteContentSize.Y + 10)
        card.Size = UDim2.new(1, -4, 0, 38 + layout.AbsoluteContentSize.Y + 10)
    end)
    table.insert(self.Tab.Pages, card)
    return section
end

function Section:_row(name, height)
    local theme = self.Tab.Window._theme
    local row = create("Frame", {
        Name = "Control_" .. tostring(name):gsub("%W", ""),
        Size = UDim2.new(1, 0, 0, height or 36),
        BackgroundColor3 = theme:Get("Surface2"),
        BackgroundTransparency = 0.48,
        BorderSizePixel = 0,
    }, self.Content)
    corner(row, 7)
    self.Tab.Window:_bindColor(row, "BackgroundColor3", "Surface2")
    return row
end

function Section:AddLabel(name, description)
    local row = self:_row(name, description and 48 or 30)
    local title = text(row, name, 11, self.Tab.Window._theme:Get("Text"), Enum.Font.GothamSemibold)
    title.Position = UDim2.fromOffset(11, description and 5 or 0)
    title.Size = UDim2.new(1, -22, 0, description and 18 or 30)
    self.Tab.Window:_bindColor(title, "TextColor3", "Text")
    if description then
        local desc = text(row, description, 9, self.Tab.Window._theme:Get("Muted"), Enum.Font.Gotham)
        desc.Position = UDim2.fromOffset(11, 24)
        desc.Size = UDim2.new(1, -22, 0, 16)
        self.Tab.Window:_bindColor(desc, "TextColor3", "Muted")
    end
    return makeControlHandle(self, name, row, function() return name end, function() end)
end

function Section:AddToggle(name, defaultValue, callback)
    local value = defaultValue == true
    local row = self:_row(name, 38)
    local title = text(row, name, 11, self.Tab.Window._theme:Get("Text"), Enum.Font.GothamMedium)
    title.Position = UDim2.fromOffset(11, 0)
    title.Size = UDim2.new(1, -76, 1, 0)
    self.Tab.Window:_bindColor(title, "TextColor3", "Text")

    local track = create("Frame", {
        Name = "Track",
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(38, 21),
        BackgroundColor3 = value and self.Tab.Window._theme:Get("Accent") or self.Tab.Window._theme:Get("Elevated"),
        BorderSizePixel = 0,
    }, row)
    corner(track, 11)

    local knob = create("Frame", {
        Name = "Knob",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, value and 20 or 3, 0.5, 0),
        Size = UDim2.fromOffset(15, 15),
        BackgroundColor3 = Color3.fromRGB(245, 246, 250),
        BorderSizePixel = 0,
    }, track)
    corner(knob, 8)

    local function update(nextValue, silent)
        value = nextValue == true
        track.BackgroundColor3 = value and self.Tab.Window._theme:Get("Accent") or self.Tab.Window._theme:Get("Elevated")
        knob.Position = UDim2.new(0, value and 20 or 3, 0.5, 0)
        if not silent and type(callback) == "function" then
            callback(value)
        end
    end

    local hitbox = create("TextButton", {
        Name = "Hitbox",
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
    }, row)
    self._connections:Connect(hitbox.Activated, function()
        update(not value, false)
    end)
    update(value, true)
    return makeControlHandle(self, name, row, function() return value end, update)
end

function Section:AddButton(name, callback)
    local row = self:_row(name, 38)
    local button = create("TextButton", {
        Size = UDim2.new(1, -14, 1, -8),
        Position = UDim2.fromOffset(7, 4),
        BackgroundColor3 = self.Tab.Window._theme:Get("Elevated"),
        BorderSizePixel = 0,
        Text = tostring(name),
        TextColor3 = self.Tab.Window._theme:Get("Text"),
        TextSize = 10,
        Font = Enum.Font.GothamSemibold,
        AutoButtonColor = false,
    }, row)
    corner(button, 7)
    self.Tab.Window:_bindColor(button, "BackgroundColor3", "Elevated")
    self.Tab.Window:_bindColor(button, "TextColor3", "Text")
    self._connections:Connect(button.Activated, function()
        if type(callback) == "function" then
            callback()
        end
    end)
    return makeControlHandle(self, name, row, function() return button end, function() end)
end

function Section:AddSlider(name, minimum, maximum, defaultValue, callback, increment)
    minimum = tonumber(minimum) or 0
    maximum = tonumber(maximum) or 100
    if maximum < minimum then
        minimum, maximum = maximum, minimum
    end
    increment = tonumber(increment) or 1
    if increment <= 0 then
        increment = 1
    end
    local value = math.clamp(tonumber(defaultValue) or minimum, minimum, maximum)
    local row = self:_row(name, 58)
    local title = text(row, name, 10, self.Tab.Window._theme:Get("Text"), Enum.Font.GothamMedium)
    title.Position = UDim2.fromOffset(10, 4)
    title.Size = UDim2.new(1, -76, 0, 18)
    self.Tab.Window:_bindColor(title, "TextColor3", "Text")

    local valueLabel = text(row, tostring(value), 10, self.Tab.Window._theme:Get("Accent"), Enum.Font.GothamBold)
    valueLabel.AnchorPoint = Vector2.new(1, 0)
    valueLabel.Position = UDim2.new(1, -10, 0, 4)
    valueLabel.Size = UDim2.fromOffset(58, 18)
    valueLabel.TextXAlignment = Enum.TextXAlignment.Right
    self.Tab.Window:_bindColor(valueLabel, "TextColor3", "Accent")

    local bar = create("Frame", {
        Position = UDim2.new(0, 10, 0, 34),
        Size = UDim2.new(1, -20, 0, 6),
        BackgroundColor3 = self.Tab.Window._theme:Get("Elevated"),
        BorderSizePixel = 0,
    }, row)
    corner(bar, 4)
    self.Tab.Window:_bindColor(bar, "BackgroundColor3", "Elevated")

    local fill = create("Frame", {
        Size = UDim2.new(0, 0, 1, 0),
        BackgroundColor3 = self.Tab.Window._theme:Get("Accent"),
        BorderSizePixel = 0,
    }, bar)
    corner(fill, 4)
    self.Tab.Window:_bindColor(fill, "BackgroundColor3", "Accent")

    local knob = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(13, 13),
        BackgroundColor3 = Color3.fromRGB(244, 245, 249),
        BorderSizePixel = 0,
    }, bar)
    corner(knob, 8)

    local inputService = game:GetService("UserInputService")
    local dragging = false
    local function snap(nextValue)
        nextValue = math.clamp(tonumber(nextValue) or minimum, minimum, maximum)
        local steps = math.floor(((nextValue - minimum) / increment) + 0.5)
        return math.clamp(minimum + steps * increment, minimum, maximum)
    end
    local function update(nextValue, silent)
        value = snap(nextValue)
        local alpha = maximum == minimum and 0 or (value - minimum) / (maximum - minimum)
        fill.Size = UDim2.new(alpha, 0, 1, 0)
        knob.Position = UDim2.new(alpha, 0, 0.5, 0)
        valueLabel.Text = tostring(value)
        if not silent and type(callback) == "function" then
            callback(value)
        end
    end
    local function setFromInput(input)
        local width = math.max(1, bar.AbsoluteSize.X)
        local alpha = math.clamp((input.Position.X - bar.AbsolutePosition.X) / width, 0, 1)
        update(minimum + (maximum - minimum) * alpha, false)
    end
    self._connections:Connect(bar.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            setFromInput(input)
        end
    end)
    self._connections:Connect(inputService.InputChanged, function(input)
        if not dragging then return end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            setFromInput(input)
        end
    end)
    self._connections:Connect(inputService.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    update(value, true)

    return makeControlHandle(self, name, row, function() return value end, update)
end

function Section:AddDropdown(name, options, defaultValue, callback)
    options = options or {}
    local labels = {}
    for _, option in ipairs(options) do
        if type(option) == "table" then
            table.insert(labels, tostring(option.label or option.Name or option.value or option.Value or "Option"))
        else
            table.insert(labels, tostring(option))
        end
    end

    local value = tostring(defaultValue or labels[1] or "")
    local row = self:_row(name, 58)
    local title = text(row, name, 10, self.Tab.Window._theme:Get("Text"), Enum.Font.GothamMedium)
    title.Position = UDim2.fromOffset(10, 4)
    title.Size = UDim2.new(1, -20, 0, 17)
    self.Tab.Window:_bindColor(title, "TextColor3", "Text")

    local button = create("TextButton", {
        Position = UDim2.fromOffset(8, 25),
        Size = UDim2.new(1, -16, 0, 27),
        BackgroundColor3 = self.Tab.Window._theme:Get("Elevated"),
        BorderSizePixel = 0,
        Text = value .. "   ▾",
        TextColor3 = self.Tab.Window._theme:Get("Text"),
        TextSize = 10,
        Font = Enum.Font.GothamMedium,
        AutoButtonColor = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    corner(button, 6)
    addPadding(button, 9, 7, 0, 0)
    self.Tab.Window:_bindColor(button, "BackgroundColor3", "Elevated")
    self.Tab.Window:_bindColor(button, "TextColor3", "Text")

    local popup
    local function closePopup()
        if popup then
            popup:Destroy()
            popup = nil
        end
    end
    local function choose(nextValue)
        value = tostring(nextValue)
        button.Text = value .. "   ▾"
        closePopup()
        if type(callback) == "function" then
            callback(value)
        end
    end
    local function openPopup()
        closePopup()
        local root = self.Tab.Window.Root
        local screenPosition = button.AbsolutePosition
        local screenSize = button.AbsoluteSize
        local scale = self.Tab.Window.Scale.Scale
        local viewport = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(800, 600)
        local height = math.min(180, #labels * 30 + 8)
        local below = viewport.Y - (screenPosition.Y + screenSize.Y)
        local above = screenPosition.Y
        local y = screenPosition.Y + screenSize.Y + 3
        if below < height and above > below then
            y = screenPosition.Y - height - 3
        end
        local x = math.clamp(screenPosition.X, 4, math.max(4, viewport.X - screenSize.X - 4))
        popup = create("ScrollingFrame", {
            Name = "DropdownPopup",
            Position = UDim2.fromOffset(x, y),
            Size = UDim2.fromOffset(screenSize.X, height),
            BackgroundColor3 = self.Tab.Window._theme:Get("Elevated"),
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            CanvasSize = UDim2.fromOffset(0, #labels * 30 + 8),
            ZIndex = 100,
        }, self.Tab.Window.Gui)
        corner(popup, 8)
        stroke(popup, self.Tab.Window._theme:Get("Line"), 0.08, 1)
        local list = addList(popup, 2)
        addPadding(popup, 4, 4, 4, 4)
        for index, labelText in ipairs(labels) do
            local optionButton = create("TextButton", {
                LayoutOrder = index,
                Size = UDim2.new(1, -4, 0, 28),
                BackgroundColor3 = labelText == value and self.Tab.Window._theme:Get("Surface2") or self.Tab.Window._theme:Get("Elevated"),
                BorderSizePixel = 0,
                Text = (labelText == value and "✓  " or "   ") .. labelText,
                TextColor3 = self.Tab.Window._theme:Get("Text"),
                TextSize = 10,
                Font = Enum.Font.GothamMedium,
                TextXAlignment = Enum.TextXAlignment.Left,
                AutoButtonColor = false,
                ZIndex = 101,
            }, popup)
            corner(optionButton, 5)
            addPadding(optionButton, 7, 5, 0, 0)
            optionButton.Activated:Connect(function()
                choose(labelText)
            end)
        end
        local total = list.AbsoluteContentSize.Y + 8
        popup.CanvasSize = UDim2.fromOffset(0, total)
    end

    self._connections:Connect(button.Activated, openPopup)
    self._connections:Give(function()
        closePopup()
    end)
    return makeControlHandle(self, name, row, function() return value end, function(nextValue, silent)
        if silent then
            value = tostring(nextValue)
            button.Text = value .. "   ▾"
        else
            choose(nextValue)
        end
    end)
end

function Section:AddKeybind(name, defaultKey, callback)
    local value = defaultKey or Enum.KeyCode.RightShift
    local row = self:_row(name, 38)
    local label = text(row, name, 10, self.Tab.Window._theme:Get("Text"), Enum.Font.GothamMedium)
    label.Position = UDim2.fromOffset(10, 0)
    label.Size = UDim2.new(1, -100, 1, 0)
    self.Tab.Window:_bindColor(label, "TextColor3", "Text")

    local capture = create("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -9, 0.5, 0),
        Size = UDim2.fromOffset(78, 25),
        BackgroundColor3 = self.Tab.Window._theme:Get("Elevated"),
        BorderSizePixel = 0,
        Text = value.Name,
        TextColor3 = self.Tab.Window._theme:Get("Text"),
        TextSize = 9,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = false,
    }, row)
    corner(capture, 6)
    self.Tab.Window:_bindColor(capture, "BackgroundColor3", "Elevated")
    self.Tab.Window:_bindColor(capture, "TextColor3", "Text")

    local listening = false
    local inputService = game:GetService("UserInputService")
    self._connections:Connect(capture.Activated, function()
        listening = true
        capture.Text = "PRESS KEY"
    end)
    self._connections:Connect(inputService.InputBegan, function(input, processed)
        if not listening or processed then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        value = input.KeyCode
        listening = false
        capture.Text = value.Name
        if type(callback) == "function" then callback(value) end
    end)
    return makeControlHandle(self, name, row, function() return value end, function(nextValue, silent)
        if typeof(nextValue) == "EnumItem" and nextValue.EnumType == Enum.KeyCode then
            value = nextValue
            capture.Text = value.Name
            if not silent and type(callback) == "function" then callback(value) end
        end
    end)
end

function Window:_refreshSubTabs(tab)
    local current = self.CurrentSubTab
    for _, sub in ipairs(tab.SubTabs) do
        if sub.Button then
            local selected = sub == current
            sub.Button.BackgroundTransparency = selected and 0 or 1
            sub.Button.BackgroundColor3 = selected and self._theme:Get("AccentSoft") or self._theme:Get("Surface2")
            sub.Button.TextColor3 = selected and self._theme:Get("Accent") or self._theme:Get("Muted")
        end
    end
end

function Window:SelectTab(tab)
    if type(tab) == "string" then
        tab = self.Tabs[tab]
    end
    if not tab or self.Destroyed then
        return false
    end

    self.CurrentTab = tab
    self.ActiveTitle.Text = tab.Name
    self.ActiveDescription.Text = tab.Description or ""
    self.SubNavigation.Visible = #tab.SubTabs > 1

    for _, item in ipairs(self.TabList) do
        local selected = item == tab
        item.NavButton.BackgroundTransparency = selected and 0 or 1
        item.NavButton.BackgroundColor3 = selected and self._theme:Get("AccentSoft") or self._theme:Get("Surface2")
        item.NavIcon.TextColor3 = selected and self._theme:Get("Accent") or self._theme:Get("Muted")
        item.NavLabel.TextColor3 = selected and self._theme:Get("Text") or self._theme:Get("Muted")
        for _, sub in ipairs(item.SubTabs) do
            sub.Page.Visible = selected and (sub == (tab == item and self.CurrentSubTab or nil))
        end
    end

    local activeSub = tab.SubTabs[1]
    if activeSub then
        self:SelectSubTab(activeSub)
    end
    return true
end

function Window:SelectSubTab(sub)
    if not sub or self.Destroyed then
        return false
    end

    self.CurrentTab = sub.Tab
    self.CurrentSubTab = sub
    self.ActiveTitle.Text = sub.Tab.Name
    self.ActiveDescription.Text = sub.Description or sub.Tab.Description or ""
    self.SubNavigation.Visible = #sub.Tab.SubTabs > 1

    for _, tab in ipairs(self.TabList) do
        for _, item in ipairs(tab.SubTabs) do
            item.Page.Visible = tab == sub.Tab and item == sub
        end
    end
    self:_refreshSubTabs(sub.Tab)
    return true
end

function Window:_bindSearch()
    self._connections:Connect(self.Search:GetPropertyChangedSignal("Text"), function()
        self:_applySearch(self.Search.Text)
    end, "search-change")
end

function Window:_applySearch(query)
    query = string.lower(tostring(query or ""))
    local searching = query ~= ""

    for _, tab in ipairs(self.TabList) do
        local matched = not searching
            or string.find(string.lower(tab.Name), query, 1, true) ~= nil
            or string.find(string.lower(tab.Description or ""), query, 1, true) ~= nil
        tab.NavButton.Visible = matched
        local group = self.Groups[tab.Group]
        if group and searching and matched then
            group.Expanded = true
            group.Entries.Visible = true
            group.Heading.Text = group.Name:upper() .. "   ▾"
        end
    end

    for _, group in pairs(self.Groups) do
        local anyVisible = false
        for _, tab in ipairs(group.Tabs) do
            if tab.NavButton.Visible then anyVisible = true break end
        end
        group.Frame.Visible = anyVisible
        if not searching then
            group.Entries.Visible = group.Expanded
            group.Heading.Text = group.Name:upper() .. (group.Expanded and "   ▾" or "   ▸")
        end
    end
end

function Window:SetVisible(visible)
    if self.Destroyed then return end
    self.IsOpen = visible ~= false
    self.Root.Visible = self.IsOpen
end

function Window:Toggle()
    self:SetVisible(not self.IsOpen)
end

function Window:SetKey(key)
    if typeof(key) == "EnumItem" and key.EnumType == Enum.KeyCode then
        self.Key = key
        return true
    end
    return false
end

function Window:Notify(options)
    options = options or {}
    if self.Destroyed then return nil end
    self._toastOrder += 1

    local toast = create("Frame", {
        Name = "Toast",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -18, 0, 18 + (self._toastOrder - 1) * 72),
        Size = UDim2.fromOffset(250, 62),
        BackgroundColor3 = self._theme:Get("Surface"),
        BorderSizePixel = 0,
        ZIndex = 200,
    }, self.Gui)
    corner(toast, 9)
    stroke(toast, self._theme:Get("Line"), 0.1, 1)
    local title = text(toast, options.Title or "Liberium Hub", 11, self._theme:Get("Text"), Enum.Font.GothamBold)
    title.Position = UDim2.fromOffset(12, 7)
    title.Size = UDim2.new(1, -24, 0, 19)
    local body = text(toast, options.Text or options.Description or "", 10, self._theme:Get("Muted"), Enum.Font.Gotham)
    body.Position = UDim2.fromOffset(12, 28)
    body.Size = UDim2.new(1, -24, 0, 25)
    body.TextWrapped = true
    local accent = create("Frame", {
        Size = UDim2.new(0, 3, 1, -12),
        Position = UDim2.fromOffset(5, 6),
        BackgroundColor3 = options.Color or self._theme:Get("Accent"),
        BorderSizePixel = 0,
        ZIndex = 201,
    }, toast)
    corner(accent, 2)

    local duration = math.clamp(tonumber(options.Duration) or 3, 1, 10)
    task.delay(duration, function()
        if toast and toast.Parent then
            toast:Destroy()
        end
    end)
    return toast
end

function Window:OnKeyChanged(callback)
    self._onKeyChanged = callback
end

function Window:SetThemeToken(token, value)
    self._theme:Set(token, value)
end

function Window:Destroy()
    if self.Destroyed then return end
    self.Destroyed = true

    if self._connections then
        self._connections:Destroy()
    end
    if self._ownsTheme and self._theme then
        self._theme:Destroy()
    end
    if self.Gui and self.Gui.Parent then
        self.Gui:Destroy()
    end
    self.Gui, self.Root, self.Shell = nil, nil, nil
end

Window.Tab = Tab
Window.SubTab = SubTab
Window.Section = Section
Window.Control = Control
Window.ThemeFactory = ThemeFactory

return Window
