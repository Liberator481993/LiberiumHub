-- Liberium Hub | Movement extensions
-- Original controller integrated with the v92 feature lifecycle.

local Maid = require(script.Parent.Parent.Parent.core.Maid)

local MovementPlus = {}
MovementPlus.__index = MovementPlus

local function getCharacterParts(player)
    local character = player and player.Character
    if not character or not character.Parent then
        return nil, nil, nil
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or humanoid.Health <= 0 or not root then
        return character, nil, nil
    end

    return character, humanoid, root
end

local function flat(vector)
    local result = Vector3.new(vector.X, 0, vector.Z)
    if result.Magnitude > 0.001 then
        return result.Unit
    end
    return Vector3.zero
end

function MovementPlus:_showTouchControls()
    if not self.UserInputService.TouchEnabled or self._touchGui then
        return
    end

    local playerGui = self.Player:FindFirstChildOfClass("PlayerGui")
    if not playerGui then
        return
    end

    self._touchMaid = Maid.new()

    local gui = Instance.new("ScreenGui")
    gui.Name = "LiberiumFlyControls"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.DisplayOrder = 2002
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.Parent = playerGui
    self._touchGui = gui
    self._touchMaid:Give(gui)

    local stack = Instance.new("Frame")
    stack.Name = "VerticalFlight"
    stack.AnchorPoint = Vector2.new(1, 1)
    stack.Position = UDim2.new(1, -18, 1, -150)
    stack.Size = UDim2.fromOffset(54, 112)
    stack.BackgroundTransparency = 1
    stack.Parent = gui

    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Vertical
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 8)
    layout.Parent = stack

    local function makeButton(name, caption, order)
        local button = Instance.new("TextButton")
        button.Name = name
        button.LayoutOrder = order
        button.Size = UDim2.fromOffset(50, 50)
        button.BackgroundColor3 = Color3.fromRGB(20, 23, 32)
        button.BackgroundTransparency = 0.12
        button.BorderSizePixel = 0
        button.Text = caption
        button.TextColor3 = Color3.fromRGB(240, 242, 248)
        button.TextSize = 22
        button.Font = Enum.Font.GothamBold
        button.AutoButtonColor = false
        button.Parent = stack

        local radius = Instance.new("UICorner")
        radius.CornerRadius = UDim.new(0, 14)
        radius.Parent = button

        local outline = Instance.new("UIStroke")
        outline.Color = Color3.fromRGB(214, 68, 88)
        outline.Transparency = 0.24
        outline.Thickness = 1.25
        outline.Parent = button

        return button
    end

    local upButton = makeButton("Ascend", "↑", 1)
    local downButton = makeButton("Descend", "↓", 2)

    self._touchMaid:Connect(upButton.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            self._upInput = input
            self._touchAscend = true
        end
    end, "up-began")
    self._touchMaid:Connect(downButton.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.Touch
            or input.UserInputType == Enum.UserInputType.MouseButton1 then
            self._downInput = input
            self._touchDescend = true
        end
    end, "down-began")

    local function release(input)
        if self._upInput == input then
            self._upInput = nil
            self._touchAscend = false
        end
        if self._downInput == input then
            self._downInput = nil
            self._touchDescend = false
        end
    end

    self._touchMaid:Connect(upButton.InputEnded, release, "up-ended")
    self._touchMaid:Connect(downButton.InputEnded, release, "down-ended")
    self._touchMaid:Connect(self.UserInputService.InputEnded, release, "global-ended")
end

function MovementPlus:_hideTouchControls()
    self._touchAscend = false
    self._touchDescend = false
    self._upInput = nil
    self._downInput = nil

    if self._touchMaid then
        self._touchMaid:Destroy()
        self._touchMaid = nil
    end
    self._touchGui = nil
end

function MovementPlus.new(context)
    assert(type(context) == "table", "MovementPlus.new expects a context")
    assert(context.Player and context.Workspace and context.RunService and context.UserInputService,
        "MovementPlus context is missing required services")

    local self = setmetatable({}, MovementPlus)
    self.Player = context.Player
    self.Workspace = context.Workspace
    self.RunService = context.RunService
    self.UserInputService = context.UserInputService
    self._maid = Maid.new()
    self._destroyed = false

    self._infiniteJump = false
    self._flyEnabled = false
    self._flySpeed = 60
    self._flyRoot = nil
    self._flyHumanoid = nil
    self._flyVelocity = nil
    self._flyGyro = nil
    self._oldAutoRotate = nil

    self._spinEnabled = false
    self._spinSpeed = 12
    self._spinRoot = nil
    self._oldAngularVelocity = nil

    self._gravityEnabled = false
    self._gravityValue = 196.2
    self._gravityBase = nil

    self._maid:Connect(self.UserInputService.JumpRequest, function()
        if not self._infiniteJump or self._destroyed then
            return
        end

        local _, humanoid = getCharacterParts(self.Player)
        if humanoid then
            pcall(function()
                humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
            end)
        end
    end, "infinite-jump")

    self._maid:Connect(self.RunService.Heartbeat, function()
        if self._destroyed then
            return
        end
        self:_stepFly()
        self:_stepSpin()
        self:_stepGravity()
    end, "heartbeat")

    self._maid:Connect(self.Player.CharacterAdded, function()
        if self._flyEnabled then
            task.defer(function()
                if not self._destroyed then
                    self:_attachFlight()
                end
            end)
        end
    end, "character-added")

    return self
end

function MovementPlus:SetInfiniteJump(enabled)
    if self._destroyed then
        return
    end
    self._infiniteJump = enabled == true
end

function MovementPlus:SetFlySpeed(value)
    if self._destroyed then
        return
    end
    self._flySpeed = math.clamp(tonumber(value) or 60, 10, 250)
end

function MovementPlus:_clearFlightRig()
    if self._flyVelocity then
        pcall(function() self._flyVelocity:Destroy() end)
        self._flyVelocity = nil
    end
    if self._flyGyro then
        pcall(function() self._flyGyro:Destroy() end)
        self._flyGyro = nil
    end
    if self._flyHumanoid and self._flyHumanoid.Parent and self._oldAutoRotate ~= nil then
        pcall(function()
            self._flyHumanoid.AutoRotate = self._oldAutoRotate
        end)
    end
    self._flyRoot = nil
    self._flyHumanoid = nil
    self._oldAutoRotate = nil
end

function MovementPlus:_attachFlight()
    if not self._flyEnabled or self._destroyed then
        return
    end

    local _, humanoid, root = getCharacterParts(self.Player)
    if not humanoid or not root then
        self:_clearFlightRig()
        return
    end

    if self._flyRoot == root and self._flyVelocity and self._flyVelocity.Parent == root then
        return
    end

    self:_clearFlightRig()
    self._flyRoot = root
    self._flyHumanoid = humanoid
    self._oldAutoRotate = humanoid.AutoRotate
    humanoid.AutoRotate = false

    local velocity = Instance.new("BodyVelocity")
    velocity.Name = "LiberiumFlyVelocity"
    velocity.MaxForce = Vector3.new(1e9, 1e9, 1e9)
    velocity.P = 9000
    velocity.Velocity = Vector3.zero
    velocity.Parent = root
    self._flyVelocity = velocity

    local gyro = Instance.new("BodyGyro")
    gyro.Name = "LiberiumFlyGyro"
    gyro.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
    gyro.P = 9000
    gyro.D = 500
    gyro.CFrame = root.CFrame
    gyro.Parent = root
    self._flyGyro = gyro
end

function MovementPlus:SetFly(enabled)
    if self._destroyed then
        return
    end

    self._flyEnabled = enabled == true
    if self._flyEnabled then
        self:_attachFlight()
        self:_showTouchControls()
    else
        self:_clearFlightRig()
        self:_hideTouchControls()
    end
end

function MovementPlus:_stepFly()
    if not self._flyEnabled then
        return
    end

    self:_attachFlight()
    local root, humanoid = self._flyRoot, self._flyHumanoid
    local velocity, gyro = self._flyVelocity, self._flyGyro
    if not (root and root.Parent and humanoid and humanoid.Parent and velocity and velocity.Parent == root and gyro and gyro.Parent == root) then
        return
    end

    local camera = self.Workspace.CurrentCamera
    if not camera then
        velocity.Velocity = Vector3.zero
        return
    end

    local input = self.UserInputService
    local forwardInput = 0
    local sideInput = 0
    local keyboardActive = false

    local okW, keyW = pcall(function() return input:IsKeyDown(Enum.KeyCode.W) end)
    local okS, keyS = pcall(function() return input:IsKeyDown(Enum.KeyCode.S) end)
    local okA, keyA = pcall(function() return input:IsKeyDown(Enum.KeyCode.A) end)
    local okD, keyD = pcall(function() return input:IsKeyDown(Enum.KeyCode.D) end)
    if okW and keyW then forwardInput += 1; keyboardActive = true end
    if okS and keyS then forwardInput -= 1; keyboardActive = true end
    if okD and keyD then sideInput += 1; keyboardActive = true end
    if okA and keyA then sideInput -= 1; keyboardActive = true end

    local horizontal
    if keyboardActive then
        local forward = flat(camera.CFrame.LookVector)
        local right = flat(camera.CFrame.RightVector)
        horizontal = forward * forwardInput + right * sideInput
    else
        horizontal = flat(humanoid.MoveDirection)
    end
    if horizontal.Magnitude > 1 then
        horizontal = horizontal.Unit
    end

    local vertical = 0
    local okUp, keyUp = pcall(function() return input:IsKeyDown(Enum.KeyCode.Space) end)
    local okDown, keyDown = pcall(function() return input:IsKeyDown(Enum.KeyCode.LeftControl) end)
    local okDownAlt, keyDownAlt = pcall(function() return input:IsKeyDown(Enum.KeyCode.Q) end)
    if (okUp and keyUp) or humanoid.Jump or self._touchAscend then
        vertical += 1
    end
    if (okDown and keyDown) or (okDownAlt and keyDownAlt) or self._touchDescend then
        vertical -= 1
    end

    velocity.Velocity = horizontal * self._flySpeed + Vector3.new(0, vertical * self._flySpeed, 0)
    gyro.CFrame = camera.CFrame
end

function MovementPlus:SetSpinSpeed(value)
    if self._destroyed then
        return
    end
    self._spinSpeed = math.clamp(tonumber(value) or 12, 0, 60)
end

function MovementPlus:_restoreSpin()
    local root = self._spinRoot
    if root and root.Parent and self._oldAngularVelocity then
        pcall(function()
            root.AssemblyAngularVelocity = self._oldAngularVelocity
        end)
    end
    self._spinRoot = nil
    self._oldAngularVelocity = nil
end

function MovementPlus:SetSpin(enabled)
    if self._destroyed then
        return
    end
    self._spinEnabled = enabled == true
    if not self._spinEnabled then
        self:_restoreSpin()
    end
end

function MovementPlus:_stepSpin()
    if not self._spinEnabled then
        return
    end

    local _, humanoid, root = getCharacterParts(self.Player)
    if not humanoid or not root then
        self:_restoreSpin()
        return
    end

    if root ~= self._spinRoot then
        self:_restoreSpin()
        self._spinRoot = root
        self._oldAngularVelocity = root.AssemblyAngularVelocity
    end

    root.AssemblyAngularVelocity = Vector3.new(0, self._spinSpeed, 0)
end

function MovementPlus:SetGravityValue(value)
    if self._destroyed then
        return
    end
    self._gravityValue = math.clamp(tonumber(value) or 196.2, 5, 400)
    if self._gravityEnabled then
        self.Workspace.Gravity = self._gravityValue
    end
end

function MovementPlus:SetGravity(enabled)
    if self._destroyed then
        return
    end

    local nextValue = enabled == true
    if nextValue and not self._gravityEnabled then
        self._gravityBase = self.Workspace.Gravity
    elseif not nextValue and self._gravityEnabled and self._gravityBase ~= nil then
        pcall(function()
            self.Workspace.Gravity = self._gravityBase
        end)
        self._gravityBase = nil
    end

    self._gravityEnabled = nextValue
    if self._gravityEnabled then
        self.Workspace.Gravity = self._gravityValue
    end
end

function MovementPlus:_stepGravity()
    if self._gravityEnabled and math.abs(self.Workspace.Gravity - self._gravityValue) > 0.05 then
        self.Workspace.Gravity = self._gravityValue
    end
end

function MovementPlus:Destroy()
    if self._destroyed then
        return
    end

    self:SetFly(false)
    self:SetSpin(false)
    self:SetGravity(false)
    self._infiniteJump = false
    self._destroyed = true
    self._maid:Destroy()
end

return MovementPlus
