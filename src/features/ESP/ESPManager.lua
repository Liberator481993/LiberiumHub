-- Liberium Hub | Advanced 2D/3D ESP manager
-- Original module for Box, Chams, Tracers and Radar overlays.

local Maid = require(script.Parent.Parent.core.Maid)

local ESPManager = {}
ESPManager.__index = ESPManager

local ROLE_COLORS = {
    murderer = Color3.fromRGB(255, 70, 70),
    killer = Color3.fromRGB(255, 70, 70),
    zombie = Color3.fromRGB(255, 70, 70),
    sheriff = Color3.fromRGB(70, 140, 255),
    hero = Color3.fromRGB(255, 225, 45),
    innocent = Color3.fromRGB(70, 220, 120),
    survivor = Color3.fromRGB(70, 220, 120),
}

local function create(className, properties, parent)
    local object = Instance.new(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function hideEntry(entry)
    entry.Box.Visible = false
    entry.Tracer.Visible = false
    entry.Dot.Visible = false
    if entry.Highlight then
        entry.Highlight.Enabled = false
    end
end

function ESPManager.new(context)
    assert(type(context) == "table", "ESPManager.new expects a context")
    assert(context.Players and context.LocalPlayer and context.RunService
        and context.Workspace and context.ParentGui,
        "ESPManager context is missing required services")

    local self = setmetatable({}, ESPManager)
    self.Players = context.Players
    self.LocalPlayer = context.LocalPlayer
    self.RunService = context.RunService
    self.Workspace = context.Workspace
    self.ParentGui = context.ParentGui
    self.GetRoleColor = context.GetRoleColor
    self.MaxDistance = math.clamp(tonumber(context.MaxDistance) or 250, 25, 1500)
    self.Enabled = {Box = false, Chams = false, Tracers = false, Radar = false}
    self._entries = {}
    self._gui = nil
    self._radar = nil
    self._destroyed = false
    self._maid = Maid.new()

    self._maid:Connect(self.Players.PlayerAdded, function(player)
        if self._gui then self:_makeEntry(player) end
    end, "player-added")
    self._maid:Connect(self.Players.PlayerRemoving, function(player)
        self:_removeEntry(player)
    end, "player-removing")
    self._maid:Connect(self.RunService.RenderStepped, function()
        self:_render()
    end, "render")

    return self
end

function ESPManager:_ensureGui()
    if self._gui and self._gui.Parent then return end

    local gui = create("ScreenGui", {
        Name = "LiberiumAdvancedESP",
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 1000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    }, self.ParentGui)
    self._gui = gui
    self._maid:Give(gui, "gui")

    for _, player in ipairs(self.Players:GetPlayers()) do
        if player ~= self.LocalPlayer then self:_makeEntry(player) end
    end
    if self.Enabled.Radar then self:_makeRadar() end
end

function ESPManager:_makeEntry(player)
    if self._entries[player] or player == self.LocalPlayer or not self._gui then
        return self._entries[player]
    end

    local box = create("Frame", {
        Name = "Box_" .. tostring(player.UserId),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 10,
    }, self._gui)
    local outline = create("UIStroke", {
        Thickness = 1.5,
        Transparency = 0.04,
        Color = Color3.new(1, 1, 1),
    }, box)

    local tracer = create("Frame", {
        Name = "Tracer_" .. tostring(player.UserId),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Visible = false,
        ZIndex = 9,
    }, self._gui)

    local dot = create("Frame", {
        Name = "Radar_" .. tostring(player.UserId),
        Size = UDim2.fromOffset(6, 6),
        BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 31,
    }, self._gui)
    create("UICorner", {CornerRadius = UDim.new(1, 0)}, dot)

    local entry = {
        Player = player,
        Box = box,
        Outline = outline,
        Tracer = tracer,
        Dot = dot,
        Highlight = nil,
        Character = nil,
    }
    self._entries[player] = entry
    return entry
end

function ESPManager:_removeEntry(player)
    local entry = self._entries[player]
    if not entry then return end

    if entry.Highlight then pcall(function() entry.Highlight:Destroy() end) end
    for _, object in ipairs({entry.Box, entry.Tracer, entry.Dot}) do
        if object then pcall(function() object:Destroy() end) end
    end
    self._entries[player] = nil
end

function ESPManager:_makeRadar()
    if not self._gui then return end
    if self._radar and self._radar.Parent then
        self._radar.Visible = self.Enabled.Radar
        return
    end

    local radar = create("Frame", {
        Name = "LiberiumRadar",
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -16, 0, 72),
        Size = UDim2.fromOffset(116, 116),
        BackgroundColor3 = Color3.fromRGB(12, 15, 22),
        BackgroundTransparency = 0.22,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Visible = true,
        ZIndex = 25,
    }, self._gui)
    create("UICorner", {CornerRadius = UDim.new(1, 0)}, radar)
    create("UIStroke", {
        Color = Color3.fromRGB(214, 68, 88),
        Transparency = 0.2,
        Thickness = 1.2,
    }, radar)
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(1, -18, 0, 1),
        BackgroundColor3 = Color3.fromRGB(130, 140, 160),
        BackgroundTransparency = 0.72,
        BorderSizePixel = 0,
        ZIndex = 26,
    }, radar)
    create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.new(0, 1, 1, -18),
        BackgroundColor3 = Color3.fromRGB(130, 140, 160),
        BackgroundTransparency = 0.72,
        BorderSizePixel = 0,
        ZIndex = 26,
    }, radar)
    local center = create("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(8, 8),
        BackgroundColor3 = Color3.fromRGB(245, 245, 245),
        BorderSizePixel = 0,
        ZIndex = 32,
    }, radar)
    create("UICorner", {CornerRadius = UDim.new(1, 0)}, center)
    self._radar = radar
end

function ESPManager:_colorFor(player)
    if type(self.GetRoleColor) == "function" then
        local ok, value = pcall(self.GetRoleColor, player)
        if ok then
            if typeof(value) == "Color3" then return value end
            if type(value) == "string" then
                local color = ROLE_COLORS[string.lower(value)]
                if color then return color end
            end
        end
    end
    return Color3.fromRGB(245, 245, 245)
end

function ESPManager:_updateHighlight(entry, character, color)
    if not self.Enabled.Chams then
        if entry.Highlight then entry.Highlight.Enabled = false end
        return
    end

    local highlight = entry.Highlight
    if not highlight or not highlight.Parent or entry.Character ~= character then
        if highlight then pcall(function() highlight:Destroy() end) end
        highlight = Instance.new("Highlight")
        highlight.Name = "LiberiumAdvancedChams"
        highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        highlight.FillTransparency = 0.82
        highlight.OutlineTransparency = 0.08
        highlight.Parent = character
        entry.Highlight = highlight
        entry.Character = character
    end
    highlight.Adornee = character
    highlight.FillColor = color
    highlight.OutlineColor = color
    highlight.Enabled = true
end

function ESPManager:_updateBox(entry, character, camera, viewport, color)
    if not self.Enabled.Box and not self.Enabled.Tracers then
        entry.Box.Visible = false
        entry.Tracer.Visible = false
        return
    end

    local ok, boundsCFrame, boundsSize = pcall(function()
        return character:GetBoundingBox()
    end)
    if not ok or not boundsCFrame or not boundsSize then
        entry.Box.Visible = false
        entry.Tracer.Visible = false
        return
    end

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge
    local frontCount = 0
    for _, x in ipairs({-1, 1}) do
        for _, y in ipairs({-1, 1}) do
            for _, z in ipairs({-1, 1}) do
                local worldPoint = boundsCFrame:PointToWorldSpace(Vector3.new(
                    boundsSize.X * 0.5 * x,
                    boundsSize.Y * 0.5 * y,
                    boundsSize.Z * 0.5 * z
                ))
                local point = camera:WorldToViewportPoint(worldPoint)
                if point.Z > 0 then
                    frontCount += 1
                    minX = math.min(minX, point.X)
                    minY = math.min(minY, point.Y)
                    maxX = math.max(maxX, point.X)
                    maxY = math.max(maxY, point.Y)
                end
            end
        end
    end

    if frontCount == 0 or maxX < 0 or maxY < 0
        or minX > viewport.X or minY > viewport.Y then
        entry.Box.Visible = false
        entry.Tracer.Visible = false
        return
    end

    local width = math.max(2, maxX - minX)
    local height = math.max(2, maxY - minY)
    entry.Box.Position = UDim2.fromOffset(minX, minY)
    entry.Box.Size = UDim2.fromOffset(width, height)
    entry.Outline.Color = color
    entry.Box.Visible = self.Enabled.Box

    if self.Enabled.Tracers then
        local startX, startY = viewport.X * 0.5, viewport.Y - 2
        local endX, endY = (minX + maxX) * 0.5, maxY
        local dx, dy = endX - startX, endY - startY
        local length = math.sqrt(dx * dx + dy * dy)
        entry.Tracer.Size = UDim2.fromOffset(length, 1.5)
        entry.Tracer.Position = UDim2.fromOffset((startX + endX) * 0.5, (startY + endY) * 0.5)
        entry.Tracer.Rotation = math.deg(math.atan2(dy, dx))
        entry.Tracer.BackgroundColor3 = color
        entry.Tracer.Visible = true
    else
        entry.Tracer.Visible = false
    end
end

function ESPManager:_updateRadar(entry, playerRoot, localRoot, camera, distance, color)
    if not self.Enabled.Radar or not self._radar or distance > self.MaxDistance then
        entry.Dot.Visible = false
        return
    end

    local relative = camera.CFrame:VectorToObjectSpace(playerRoot.Position - localRoot.Position)
    local radius = 48
    local scale = radius / self.MaxDistance
    local x = math.clamp(relative.X * scale, -radius, radius)
    local y = math.clamp(-relative.Z * scale, -radius, radius)
    entry.Dot.Position = UDim2.fromOffset(58 + x - 3, 58 + y - 3)
    entry.Dot.BackgroundColor3 = color
    entry.Dot.Visible = distance > 1
end

function ESPManager:_render()
    if self._destroyed then return end
    if not (self.Enabled.Box or self.Enabled.Chams or self.Enabled.Tracers or self.Enabled.Radar) then
        return
    end

    self:_ensureGui()
    local camera = self.Workspace.CurrentCamera
    local localCharacter = self.LocalPlayer.Character
    local localRoot = localCharacter and localCharacter:FindFirstChild("HumanoidRootPart")
    if not camera or not localRoot then
        for _, entry in pairs(self._entries) do hideEntry(entry) end
        return
    end

    local viewport = camera.ViewportSize
    for player, entry in pairs(self._entries) do
        if not player.Parent then
            self:_removeEntry(player)
            continue
        end

        local character = player.Character
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")
        local root = character and character:FindFirstChild("HumanoidRootPart")
        if not character or not character.Parent or not humanoid or humanoid.Health <= 0 or not root then
            hideEntry(entry)
            continue
        end

        local distance = (root.Position - localRoot.Position).Magnitude
        if distance > self.MaxDistance then
            hideEntry(entry)
            continue
        end

        local color = self:_colorFor(player)
        self:_updateHighlight(entry, character, color)
        self:_updateBox(entry, character, camera, viewport, color)
        self:_updateRadar(entry, root, localRoot, camera, distance, color)
    end
end

function ESPManager:_set(kind, enabled)
    if self._destroyed then return false end
    self.Enabled[kind] = enabled == true
    if enabled then self:_ensureGui() end

    if kind == "Radar" and self._radar then
        self._radar.Visible = self.Enabled.Radar
    end
    if not enabled then
        for _, entry in pairs(self._entries) do
            if kind == "Box" then entry.Box.Visible = false end
            if kind == "Tracers" then entry.Tracer.Visible = false end
            if kind == "Radar" then entry.Dot.Visible = false end
            if kind == "Chams" and entry.Highlight then entry.Highlight.Enabled = false end
        end
    end
    return true
end

function ESPManager:SetBox(enabled)
    return self:_set("Box", enabled)
end

function ESPManager:SetChams(enabled)
    return self:_set("Chams", enabled)
end

function ESPManager:SetTracers(enabled)
    return self:_set("Tracers", enabled)
end

function ESPManager:SetRadar(enabled)
    local ok = self:_set("Radar", enabled)
    if enabled then self:_makeRadar() end
    return ok
end

function ESPManager:SetMaxDistance(value)
    self.MaxDistance = math.clamp(tonumber(value) or 250, 25, 1500)
end

function ESPManager:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    for player in pairs(self._entries) do
        self:_removeEntry(player)
    end
    self._maid:Destroy()
    self._gui = nil
    self._radar = nil
end

return ESPManager
