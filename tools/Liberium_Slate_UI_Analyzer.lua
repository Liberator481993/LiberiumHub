--[[
LIBERIUM SLATE UI ANALYZER v1.0
One-shot snapshot of accessible Roblox GUI metadata.

USAGE:
1. Join MM2 and open PulseHub fully.
2. Execute this script once in your client environment.
3. It exports a JSON report using writefile, and copies it with setclipboard
   when those functions are available.

COLLECTS:
- GUI hierarchy, class/name, positions, sizes, visibility and ZIndex
- Background/text/image colors, transparency, fonts and visible button text
- UICorner, UIStroke, UIGradient, layouts, scrolling and scale constraints

DOES NOT COLLECT:
- Source code, closures, remote arguments, keys, or TextBox contents
- Protected internals or hidden library implementation

This is a read-only snapshot. It does not modify or destroy target UI.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer

if not player then
    warn("[Liberium Slate Analyzer] Run from the client.")
    return
end

local MAX_NODES = 5000
local MAX_TEXT = 180

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function str(value, limit)
    local s = tostring(value or ""):gsub("[%c]", " ")
    if #s > (limit or MAX_TEXT) then
        s = s:sub(1, limit or MAX_TEXT) .. "...[cut]"
    end
    return s
end

local function hex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

local function vec(v)
    return { x = v.X, y = v.Y }
end

local function dim(v)
    return { xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset }
end

local function enum(v)
    return tostring(v):gsub("^Enum%.", "")
end

local function roots()
    local out, seen = {}, {}
    local function add(label, obj)
        if obj and not seen[obj] then
            seen[obj] = true
            table.insert(out, { label = label, object = obj })
        end
    end

    add("PlayerGui", safe(function()
        return player:FindFirstChildOfClass("PlayerGui")
    end))
    add("CoreGui", safe(function()
        return game:GetService("CoreGui")
    end))
    if typeof(gethui) == "function" then
        add("ExecutorUI", safe(function() return gethui() end))
    end
    return out
end

local function snapshot(obj)
    local n = { class = obj.ClassName, name = str(obj.Name, 100) }

    if obj:IsA("GuiObject") then
        n.visible = safe(function() return obj.Visible end)
        n.size = safe(function() return dim(obj.Size) end)
        n.position = safe(function() return dim(obj.Position) end)
        n.absoluteSize = safe(function() return vec(obj.AbsoluteSize) end)
        n.absolutePosition = safe(function() return vec(obj.AbsolutePosition) end)
        n.anchorPoint = safe(function() return vec(obj.AnchorPoint) end)
        n.zIndex = safe(function() return obj.ZIndex end)
        n.rotation = safe(function() return obj.Rotation end)
        n.backgroundColor = safe(function() return hex(obj.BackgroundColor3) end)
        n.backgroundTransparency = safe(function() return obj.BackgroundTransparency end)
        n.clipsDescendants = safe(function() return obj.ClipsDescendants end)
    end

    if obj:IsA("GuiButton") then
        n.active = safe(function() return obj.Active end)
        n.selectable = safe(function() return obj.Selectable end)
        n.autoButtonColor = safe(function() return obj.AutoButtonColor end)
    end

    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
        n.text = str(safe(function() return obj.Text end, ""), MAX_TEXT)
        n.textColor = safe(function() return hex(obj.TextColor3) end)
        n.textSize = safe(function() return obj.TextSize end)
        n.textScaled = safe(function() return obj.TextScaled end)
        n.textWrapped = safe(function() return obj.TextWrapped end)
        n.font = safe(function() return enum(obj.Font) end)
        n.textXAlignment = safe(function() return enum(obj.TextXAlignment) end)
        n.textYAlignment = safe(function() return enum(obj.TextYAlignment) end)
        n.richText = safe(function() return obj.RichText end)
    end
    -- TextBox.Text is intentionally never read.

    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
        n.image = str(safe(function() return obj.Image end, ""), 300)
        n.imageColor = safe(function() return hex(obj.ImageColor3) end)
        n.imageTransparency = safe(function() return obj.ImageTransparency end)
        n.scaleType = safe(function() return enum(obj.ScaleType) end)
    end

    if obj:IsA("ScrollingFrame") then
        n.canvasSize = safe(function() return dim(obj.CanvasSize) end)
        n.scrollBarThickness = safe(function() return obj.ScrollBarThickness end)
        n.scrollingDirection = safe(function() return enum(obj.ScrollingDirection) end)
    elseif obj:IsA("UICorner") then
        n.cornerRadius = safe(function()
            return { scale = obj.CornerRadius.Scale, offset = obj.CornerRadius.Offset }
        end)
    elseif obj:IsA("UIStroke") then
        n.strokeColor = safe(function() return hex(obj.Color) end)
        n.strokeTransparency = safe(function() return obj.Transparency end)
        n.strokeThickness = safe(function() return obj.Thickness end)
    elseif obj:IsA("UIGradient") then
        n.gradientRotation = safe(function() return obj.Rotation end)
        n.gradientColor = safe(function()
            local a = {}
            for _, p in ipairs(obj.Color.Keypoints) do
                table.insert(a, { time = p.Time, color = hex(p.Value) })
            end
            return a
        end)
        n.gradientTransparency = safe(function()
            local a = {}
            for _, p in ipairs(obj.Transparency.Keypoints) do
                table.insert(a, { time = p.Time, value = p.Value })
            end
            return a
        end)
    elseif obj:IsA("UIListLayout") then
        n.fillDirection = safe(function() return enum(obj.FillDirection) end)
        n.horizontalAlignment = safe(function() return enum(obj.HorizontalAlignment) end)
        n.verticalAlignment = safe(function() return enum(obj.VerticalAlignment) end)
        n.sortOrder = safe(function() return enum(obj.SortOrder) end)
        n.padding = safe(function()
            return { scale = obj.Padding.Scale, offset = obj.Padding.Offset }
        end)
    elseif obj:IsA("UIPadding") then
        n.padding = safe(function()
            return {
                top = { obj.PaddingTop.Scale, obj.PaddingTop.Offset },
                bottom = { obj.PaddingBottom.Scale, obj.PaddingBottom.Offset },
                left = { obj.PaddingLeft.Scale, obj.PaddingLeft.Offset },
                right = { obj.PaddingRight.Scale, obj.PaddingRight.Offset }
            }
        end)
    elseif obj:IsA("UIScale") then
        n.scale = safe(function() return obj.Scale end)
    elseif obj:IsA("UIAspectRatioConstraint") then
        n.aspectRatio = safe(function() return obj.AspectRatio end)
    elseif obj:IsA("UITextSizeConstraint") then
        n.minTextSize = safe(function() return obj.MinTextSize end)
        n.maxTextSize = safe(function() return obj.MaxTextSize end)
    elseif obj:IsA("UIPageLayout") then
        n.animated = safe(function() return obj.Animated end)
        n.tweenTime = safe(function() return obj.TweenTime end)
        n.easingStyle = safe(function() return enum(obj.EasingStyle) end)
        n.easingDirection = safe(function() return enum(obj.EasingDirection) end)
    end

    return n
end

local function run()
    local report = {
        tool = "Liberium Slate UI Analyzer",
        version = "1.0",
        generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        placeId = game.PlaceId,
        gameName = str(game.Name, 120),
        viewport = safe(function()
            local camera = workspace.CurrentCamera
            return camera and vec(camera.ViewportSize) or nil
        end),
        roots = {},
        nodeCount = 0,
        truncated = false,
        notes = {
            "Read-only snapshot of accessible GUI metadata.",
            "No source code, remote arguments, keys, or TextBox contents are collected.",
            "Protected library internals and inactive animation states are not accessible."
        }
    }

    local count = 0
    for _, root in ipairs(roots()) do
        local rootNode = { container = root.label, children = {} }

        local function walk(obj, parent)
            if count >= MAX_NODES then
                report.truncated = true
                return
            end
            count = count + 1
            local node = snapshot(obj)
            node.children = {}
            table.insert(parent.children, node)

            local children = safe(function() return obj:GetChildren() end, {})
            for _, child in ipairs(children) do
                if count >= MAX_NODES then
                    report.truncated = true
                    break
                end
                walk(child, node)
            end
        end

        local children = safe(function() return root.object:GetChildren() end, {})
        for _, child in ipairs(children) do
            if count >= MAX_NODES then
                report.truncated = true
                break
            end
            walk(child, rootNode)
        end
        table.insert(report.roots, rootNode)
    end

    report.nodeCount = count
    local json = HttpService:JSONEncode(report)
    local filename = "Liberium_Slate_UI_Report_" .. os.date("%Y%m%d_%H%M%S") .. ".json"

    local saved = false
    if typeof(writefile) == "function" then
        saved = safe(function()
            writefile(filename, json)
            return true
        end, false)
    end

    local copied = false
    if typeof(setclipboard) == "function" then
        copied = safe(function()
            setclipboard(json)
            return true
        end, false)
    end

    print("[Liberium Slate Analyzer] Complete")
    print("[Liberium Slate Analyzer] GUI nodes: " .. tostring(count))
    print("[Liberium Slate Analyzer] JSON size: " .. tostring(#json) .. " bytes")
    print("[Liberium Slate Analyzer] File: " .. (saved and filename or "not saved"))
    print("[Liberium Slate Analyzer] Clipboard: " .. (copied and "copied" or "unavailable"))

    if not saved and not copied then
        warn("[Liberium Slate Analyzer] Export APIs unavailable; JSON printed below.")
        print(json)
    end
end

local ok, err = pcall(run)
if not ok then
    warn("[Liberium Slate Analyzer] " .. tostring(err))
end
