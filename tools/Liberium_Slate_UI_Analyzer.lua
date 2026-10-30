--[[
LIBERIUM SLATE UI ANALYZER v1.1 - MOBILE SAFE
A throttled, size-limited snapshot of accessible ScreenGui trees.

Run only after PulseHub is open. This version intentionally avoids walking all
of CoreGui. It checks ScreenGuis under PlayerGui and, when available, gethui().
It never reads source code, closures, remote arguments, keys, or TextBox contents.
It does not bypass protection or modify the target interface.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
if not player then
    warn("[Slate Analyzer] Run from the client.")
    return
end

local MAX_TOTAL_NODES = 650
local MAX_PER_GUI = 260
local MAX_GUIS = 8
local YIELD_EVERY = 20
local MAX_TEXT = 100

local function safe(fn, fallback)
    local ok, value = pcall(fn)
    if ok then return value end
    return fallback
end

local function s(v, limit)
    local value = tostring(v or ""):gsub("[%c]", " ")
    limit = limit or MAX_TEXT
    if #value > limit then value = value:sub(1, limit) .. "..." end
    return value
end

local function color(c)
    return string.format("#%02X%02X%02X",
        math.floor(c.R * 255 + 0.5),
        math.floor(c.G * 255 + 0.5),
        math.floor(c.B * 255 + 0.5))
end

local function enum(v)
    return tostring(v):gsub("^Enum%.", "")
end

local function dim(v)
    return {xs=v.X.Scale, xo=v.X.Offset, ys=v.Y.Scale, yo=v.Y.Offset}
end

local function vec(v)
    return {x=v.X, y=v.Y}
end

local function getContainers()
    local result, seen = {}, {}
    local function add(label, obj)
        if obj and not seen[obj] then
            seen[obj] = true
            table.insert(result, {label=label, object=obj})
        end
    end
    add("PlayerGui", safe(function()
        return player:FindFirstChildOfClass("PlayerGui")
    end))
    if typeof(gethui) == "function" then
        add("ExecutorUI", safe(function() return gethui() end))
    end
    return result
end

local function properties(obj)
    local n = {class=obj.ClassName, name=s(obj.Name, 70)}

    if obj:IsA("GuiObject") then
        n.visible = safe(function() return obj.Visible end)
        n.size = safe(function() return dim(obj.Size) end)
        n.position = safe(function() return dim(obj.Position) end)
        n.absoluteSize = safe(function() return vec(obj.AbsoluteSize) end)
        n.absolutePosition = safe(function() return vec(obj.AbsolutePosition) end)
        n.zIndex = safe(function() return obj.ZIndex end)
        n.backgroundColor = safe(function() return color(obj.BackgroundColor3) end)
        n.backgroundTransparency = safe(function() return obj.BackgroundTransparency end)
        n.rotation = safe(function() return obj.Rotation end)
    end

    if obj:IsA("TextLabel") or obj:IsA("TextButton") then
        n.text = s(safe(function() return obj.Text end, ""), MAX_TEXT)
        n.textColor = safe(function() return color(obj.TextColor3) end)
        n.textSize = safe(function() return obj.TextSize end)
        n.font = safe(function() return enum(obj.Font) end)
        n.textXAlignment = safe(function() return enum(obj.TextXAlignment) end)
    end
    -- Never read TextBox.Text.

    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
        n.image = s(safe(function() return obj.Image end, ""), 180)
        n.imageColor = safe(function() return color(obj.ImageColor3) end)
        n.imageTransparency = safe(function() return obj.ImageTransparency end)
    elseif obj:IsA("ScrollingFrame") then
        n.canvasSize = safe(function() return dim(obj.CanvasSize) end)
        n.scrollBarThickness = safe(function() return obj.ScrollBarThickness end)
    elseif obj:IsA("UICorner") then
        n.corner = safe(function()
            return {scale=obj.CornerRadius.Scale, offset=obj.CornerRadius.Offset}
        end)
    elseif obj:IsA("UIStroke") then
        n.strokeColor = safe(function() return color(obj.Color) end)
        n.strokeTransparency = safe(function() return obj.Transparency end)
        n.strokeThickness = safe(function() return obj.Thickness end)
    elseif obj:IsA("UIGradient") then
        n.gradientRotation = safe(function() return obj.Rotation end)
        n.gradientColors = safe(function()
            local a = {}
            for _, p in ipairs(obj.Color.Keypoints) do
                table.insert(a, {t=p.Time, c=color(p.Value)})
            end
            return a
        end)
    elseif obj:IsA("UIListLayout") then
        n.fillDirection = safe(function() return enum(obj.FillDirection) end)
        n.horizontalAlignment = safe(function() return enum(obj.HorizontalAlignment) end)
        n.verticalAlignment = safe(function() return enum(obj.VerticalAlignment) end)
        n.sortOrder = safe(function() return enum(obj.SortOrder) end)
        n.padding = safe(function()
            return {scale=obj.Padding.Scale, offset=obj.Padding.Offset}
        end)
    elseif obj:IsA("UIPadding") then
        n.padding = safe(function()
            return {
                top={obj.PaddingTop.Scale,obj.PaddingTop.Offset},
                bottom={obj.PaddingBottom.Scale,obj.PaddingBottom.Offset},
                left={obj.PaddingLeft.Scale,obj.PaddingLeft.Offset},
                right={obj.PaddingRight.Scale,obj.PaddingRight.Offset}
            }
        end)
    elseif obj:IsA("UIScale") then
        n.scale = safe(function() return obj.Scale end)
    end
    return n
end

local function run()
    local report = {
        tool="Liberium Slate UI Analyzer",
        version="1.1-mobile-safe",
        generatedAt=os.date("!%Y-%m-%dT%H:%M:%SZ"),
        placeId=game.PlaceId,
        gameName=s(game.Name, 80),
        roots={},
        nodeCount=0,
        truncated=false,
        notes={
            "Throttled ScreenGui-only snapshot; not a source-code extractor.",
            "TextBox contents, keys, remotes and protected internals are not read.",
            "Some UI containers may be inaccessible to the client."
        }
    }

    local total = 0
    local guiCount = 0
    local sinceYield = 0

    for _, container in ipairs(getContainers()) do
        local direct = safe(function() return container.object:GetChildren() end, {})
        for _, screen in ipairs(direct) do
            if screen:IsA("ScreenGui") and guiCount < MAX_GUIS and total < MAX_TOTAL_NODES then
                guiCount = guiCount + 1
                local root = {
                    container=container.label,
                    screenGui=s(screen.Name, 80),
                    enabled=safe(function() return screen.Enabled end),
                    displayOrder=safe(function() return screen.DisplayOrder end),
                    children={}
                }
                table.insert(report.roots, root)
                local localCount = 0

                local function walk(obj, parent)
                    if total >= MAX_TOTAL_NODES or localCount >= MAX_PER_GUI then
                        report.truncated = true
                        return
                    end

                    total = total + 1
                    localCount = localCount + 1
                    local node = properties(obj)
                    node.children = {}
                    table.insert(parent.children, node)

                    sinceYield = sinceYield + 1
                    if sinceYield >= YIELD_EVERY then
                        sinceYield = 0
                        task.wait()
                    end

                    local children = safe(function() return obj:GetChildren() end, {})
                    for _, child in ipairs(children) do
                        if total >= MAX_TOTAL_NODES or localCount >= MAX_PER_GUI then
                            report.truncated = true
                            break
                        end
                        walk(child, node)
                    end
                end

                local children = safe(function() return screen:GetChildren() end, {})
                for _, child in ipairs(children) do
                    if total >= MAX_TOTAL_NODES or localCount >= MAX_PER_GUI then
                        report.truncated = true
                        break
                    end
                    walk(child, root)
                end
            end
        end
    end

    report.nodeCount = total
    report.guiCount = guiCount

    -- Keep output bounded; this is deliberately a single small JSON encode.
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

    print("[Slate Analyzer] v1.1 complete")
    print("[Slate Analyzer] ScreenGuis: " .. tostring(guiCount))
    print("[Slate Analyzer] Nodes: " .. tostring(total))
    print("[Slate Analyzer] Truncated: " .. tostring(report.truncated))
    print("[Slate Analyzer] JSON bytes: " .. tostring(#json))
    print("[Slate Analyzer] File: " .. (saved and filename or "not saved"))
    print("[Slate Analyzer] Clipboard: " .. (copied and "copied" or "unavailable"))

    if not saved and not copied then
        warn("[Slate Analyzer] Export functions unavailable; report follows in console.")
        print(json)
    end
end

local ok, err = pcall(run)
if not ok then
    warn("[Slate Analyzer] Stopped safely: " .. tostring(err))
end
