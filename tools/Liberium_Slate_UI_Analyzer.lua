--[[
    LIBERIUM - SLATE UI ANALYZER v1.0
    One-shot collector of accessible Roblox GUI metadata.

    HOW TO USE:
    1. Join the game and open PulseHub's UI.
    2. Run this script once in your authorized client environment.
    3. Send the generated JSON report back for analysis.

    Collects visible GUI hierarchy and visual properties only.
    Does not read source code, closures, remote arguments, keys, or TextBox contents.
    Does not bypass protections or modify/destroy the target UI.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    warn("[Slate Analyzer] LocalPlayer unavailable; run from the client.")
    return
end

local MAX_NODES = 5000
local MAX_TEXT = 180
local MAX_OUTPUT = 1800000

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function clean(value, limit)
    local s = tostring(value or ""):gsub("[%c]", " ")
    limit = limit or MAX_TEXT
    if #s > limit then s = s:sub(1, limit) .. "...[truncated]" end
    return s
end

local function colorHex(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

local function size2(v)
    return { xs = v.X.Scale, xo = v.X.Offset, ys = v.Y.Scale, yo = v.Y.Offset }
end

local function vec2(v)
    return { x = v.X, y = v.Y }
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
        return LocalPlayer:FindFirstChildOfClass("PlayerGui")
    end))
    add("CoreGui", safe(function() return game:GetService("CoreGui") end))
    if typeof(gethui) == "function" then
        add("ExecutorUI", safe(function() return gethui() end))
    end
    return out
end

local function properties(obj)
    local d = { class = obj.ClassName, name = clean(obj.Name, 100) }
    if obj:IsA("GuiObject") then
        d.visible = safe(function() return obj.Visible end)
        d.size = safe(function() return size2(obj.Size) end)
        d.position = safe(function() return size2(obj.Position) end)
        d.anchorPoint = safe(function() return vec2(obj.AnchorPoint) end)
        d.absoluteSize = safe(function() return vec2(obj.AbsoluteSize) end)
        d.absolutePosition = safe(function() return vec2(obj.AbsolutePosition) end)
        d.zIndex = safe(function() return obj.ZIndex end)
        d.rotation = safe(function() return obj.Rotation end)
        d.backgroundColor = safe(function() return colorHex(obj.BackgroundColor3) end)
        d.backgroundTransparency = safe(function() return obj.BackgroundTransparency end)
        d.clipsDescendants = safe(function() return obj.ClipsDescendants end)
    end
    if obj:IsA("GuiButton") then
        d.active = safe(function() return obj.Active end)
        d.selectable = safe(function() return obj.Selectable end)
        d.autoButtonColor = safe(function() return obj.AutoButtonColor end)
    end
    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
        d.text = clean(safe(function() return obj.Text end, ""), MAX_TEXT)
        d.textColor = safe(function() return colorHex(obj.TextColor3) end)
        d.textSize = safe(function() return obj.TextSize end)
        d.textScaled = safe(function() return obj.TextScaled end)
        d.textWrapped = safe(function() return obj.TextWrapped end)
        d.font = safe(function() return enum(obj.Font) end)
        d.textXAlignment = safe(function() return enum(obj.TextXAlignment) end)
        d.textYAlignment = safe(function() return enum(obj.TextYAlignment) end)
        d.richText = safe(function() return obj.RichText end)
    end
    -- TextBox.Text is intentionally not collected.
    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
        d.image = clean(safe(function() return obj.Image end, ""), 300)
        d.imageColor = safe(function() return colorHex(obj.ImageColor3) end)
        d.imageTransparency = safe(function() return obj.ImageTransparency end)
        d.scaleType = safe(function() return enum(obj.ScaleType) end)
    end
    if obj:IsA("ScrollingFrame") then
        d.canvasSize = safe(function() return size2(obj.CanvasSize) end)
        d.scrollBarThickness = safe(function() return obj.ScrollBarThickness end)
        d.scrollingDirection = safe(function() return enum(obj.ScrollingDirection) end)
    end
    if obj:IsA("UICorner") then
        d.cornerRadius = safe(function()
            return { scale = obj.CornerRadius.Scale, offset = obj.CornerRadius.Offset }
        end)
    elseif obj:IsA("UIStroke") then
        d.strokeColor = safe(function() return colorHex(obj.Color) end)
        d.strokeTransparency = safe(function() return obj.Transparency end)
        d.strokeThickness = safe(function() return obj.Thickness end)
    elseif obj:IsA("UIGradient") then
        d.gradientRotation = safe(function() return obj.Rotation end)
        d.gradientColor = safe(function()
            local points = {}
            for _, p in ipairs(obj.Color.Keypoints) do
                table.insert(points, { time = p.Time, color = colorHex(p.Value) })
            end
            return points
        end)
        d.gradientTransparency = safe(function()
            local points = {}
            for _, p in ipairs(obj.Transparency.Keypoints) do
                table.insert(points, { time = p.Time, value = p.Value })
            end
            return points
        end)
    elseif obj:IsA("UIListLayout") then
        d.fillDirection = safe(function() return enum(obj.FillDirection) end)
        d.horizontalAlignment = safe(function() return enum(obj.HorizontalAlignment) end)
        d.verticalAlignment = safe(function() return enum(obj.VerticalAlignment) end)
        d.sortOrder = safe(function() return enum(obj.SortOrder) end)
        d.padding = safe(function() return { obj.Padding.Scale, obj.Padding.Offset } end)
    elseif obj:IsA("UIPadding") then
        d.padding = safe(function()
            return {
                top = { obj.PaddingTop.Scale, obj.PaddingTop.Offset },
                bottom = { obj.PaddingBottom.Scale, obj.PaddingBottom.Offset },
                left = { obj.PaddingLeft.Scale, obj.PaddingLeft.Offset },
                right = { obj.PaddingRight.Scale, obj.PaddingRight.Offset }
            }
        end)
    elseif obj:IsA("UIPageLayout") then
        d.pageLayout = {
            animated = safe(function() return obj.Animated end),
            tweenTime = safe(function() return obj.TweenTime end),
            easingStyle = safe(function() return enum(obj.EasingStyle) end),
            easingDirection = safe(function() return enum(obj.EasingDirection) end)
        }
    elseif obj:IsA("UIScale") then
        d.scale = safe(function() return obj.Scale end)
    elseif obj:IsA("UIAspectRatioConstraint") then
        d.aspectRatio = safe(function() return obj.AspectRatio end)
    end
    return d
end

local function run()
    local report = {
        tool = "Liberium Slate UI Analyzer",
        version = "1.0",
        generatedAt = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        placeId = game.PlaceId,
        gameName = clean(game.Name, 120),
        viewport = safe(function()
            local camera = workspace.CurrentCamera
            return camera and vec2(camera.ViewportSize) or nil
        end),
        roots = {}, nodeCount = 0, truncated = false,
        notes = {
            "Snapshot of accessible GUI metadata only.",
            "No source code, remote arguments, keys, or TextBox contents are collected.",
            "Protected internals and inactive animation states are not recoverable from this snapshot."
        }
    }
    local count = 0
    for _, rootInfo in ipairs(roots()) do
        local rootData = { container = rootInfo.label, children = {} }
        local function visit(obj, parent)
            if count >= MAX_NODES then report.truncated = true; return end
            count = count + 1
            local node = properties(obj)
            node.children = {}
            table.insert(parent.children, node)
            local kids = safe(function() return obj:GetChildren() end, {})
            for _, child in ipairs(kids) do
                if count >= MAX_NODES then report.truncated = true; break end
                visit(child, node)
            end
        end
        local kids = safe(function() return rootInfo.object:GetChildren() end, {})
        for _, child in ipairs(kids) do
            if count >= MAX_NODES then report.truncated = true; break end
            visit(child, rootData)
        end
        table.insert(report.roots, rootData)
    end
    report.nodeCount = count

    local encoded = HttpService:JSONEncode(report)
    if #encoded > MAX_OUTPUT then
        report.truncated = true
        report.notes[#report.notes + 1] = "Report exceeded size cap; some hierarchy nodes were omitted."
        -- Compact fallback: retain top-level containers and metadata, cap each branch.
        for _, root in ipairs(report.roots) do
            local kept = 0
            while #root.children > 350 do table.remove(root.children); kept = kept + 1 end
            if kept > 0 then root.omittedTopLevelNodes = kept end
        end
        encoded = HttpService:JSONEncode(report)
    end

    local filename = "Liberium_Slate_UI_Report_" .. os.date("%Y%m%d_%H%M%S") .. ".json"
    local saved = false
    if typeof(writefile) == "function" then
        saved = safe(function() writefile(filename, encoded); return true end, false)
    end
    local copied = false
    if typeof(setclipboard) == "function" then
        copied = safe(function() setclipboard(encoded); return true end, false)
    end
    print("[Slate Analyzer] Complete | GUI nodes: " .. tostring(count) .. " | bytes: " .. tostring(#encoded))
    print("[Slate Analyzer] File: " .. tostring(saved and filename or "not saved"))
    print("[Slate Analyzer] Clipboard: " .. tostring(copied and "copied" or "unavailable"))
    if not saved and not copied then
        warn("[Slate Analyzer] No file or clipboard export function detected. JSON follows:")
        print(encoded)
    end
end

local ok, err = pcall(run)
if not ok then warn("[Slate Analyzer] Failed: " .. tostring(err)) end