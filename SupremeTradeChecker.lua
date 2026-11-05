-- MM2 Supreme Trade Checker
-- Informational overlay only. Does not accept, decline, send, or modify trades.
-- Source: https://www.supremevalues.com/mm2/

local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local CoreGui = game:GetService("CoreGui")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CATEGORIES = {
    "sets","uniques","evos","ancients","vintages","chromas","godlies",
    "legendaries","rares","uncommons","commons","pets","misc","untradables"
}
local BASE = "https://supremevalues.com/mm2/"
local values, valueNames = {}, {}
local lastUpdate = "loading"
local stopped = false

local function clean(s)
    s = tostring(s or ""):gsub("<[^>]->"," "):gsub("&nbsp;"," ")
    s = s:gsub("&amp;","&"):gsub("&quot;",'"'):gsub("&#39;","'")
    return (s:gsub("[%c]"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$",""))
end
local function key(s)
    local normalized = string.lower(clean(s))
    normalized = normalized:gsub("['`]", "")
    return normalized:gsub("[%p%c]"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
end
local function get(url)
    local errors = {}

    local function tryRequest(fn, label)
        if type(fn) ~= "function" then return nil end
        local ok, response = pcall(function()
            return fn({
                Url = url,
                Method = "GET",
                Headers = {
                    ["User-Agent"] = "Mozilla/5.0",
                    ["Accept"] = "text/html,application/xhtml+xml"
                }
            })
        end)
        if not ok then
            table.insert(errors, label .. " failed")
            return nil
        end

        local status
        if type(response) == "table" then
            status = tonumber(response.StatusCode or response.Status or response.status_code)
            response = response.Body or response.body or response.ResponseBody
        end
        if type(response) == "string" and #response > 100 then
            if not status or (status >= 200 and status < 300) then
                if response:find("Value", 1, true) or response:find("value", 1, true) then
                    return response, label
                end
                table.insert(errors, label .. " returned a page without values")
            else
                table.insert(errors, label .. " HTTP " .. tostring(status))
            end
        else
            table.insert(errors, label .. " returned an empty response")
        end
        return nil
    end

    local body, source = tryRequest(request, "request")
    if body then return body, source end

    body, source = tryRequest(http_request, "http_request")
    if body then return body, source end

    local synRequest = type(syn) == "table" and syn.request or nil
    body, source = tryRequest(synRequest, "syn.request")
    if body then return body, source end

    local httpServiceRequest = type(http) == "table" and http.request or nil
    body, source = tryRequest(httpServiceRequest, "http.request")
    if body then return body, source end

    local ok, gameBody = pcall(function() return game:HttpGet(url) end)
    if ok and type(gameBody) == "string" and #gameBody > 100 then
        if gameBody:find("Value", 1, true) or gameBody:find("value", 1, true) then
            return gameBody, "game:HttpGet"
        end
        table.insert(errors, "game:HttpGet returned a page without values")
    else
        table.insert(errors, "game:HttpGet failed or returned an empty response")
    end

    return nil, table.concat(errors, "; ")
end

local function parsePage(html, out)
    local parsedCount = 0

    -- Convert image alt/ARIA labels into explicit item-name markers before tags are removed.
    html = html:gsub("<[Ii][Mm][Gg]([^>]*)>", function(attributes)
        local alt = attributes:match("[Aa][Ll][Tt]%s*=%s*\"(.-)\"")
            or attributes:match("[Aa][Ll][Tt]%s*=%s*'(.-)'")
            or attributes:match("[Aa][Rr][Ii][Aa]%-[Ll][Aa][Bb][Ee][Ll]%s*=%s*\"(.-)\"")
            or attributes:match("[Tt][Ii][Tt][Ll][Ee]%s*=%s*\"(.-)\"")
        if alt and alt ~= "" then return " Image: " .. alt .. " " end
        return " "
    end)

    html = html:gsub("<[Ss][Cc][Rr][Ii][Pp][Tt][^>]*>.-</[Ss][Cc][Rr][Ii][Pp][Tt]%s*>", " ")
    html = html:gsub("<[Ss][Tt][Yy][Ll][Ee][^>]*>.-</[Ss][Tt][Yy][Ll][Ee]%s*>", " ")
    html = html:gsub("<[Bb][Rr][^>]*>", " ")
    html = html:gsub("</[Pp]>", " ")
    html = html:gsub("</[Dd][Ii][Vv]>", " ")
    html = html:gsub("<[^>]->", " ")
    html = html:gsub("&nbsp;", " "):gsub("&#160;", " ")
    html = html:gsub("&amp;", "&"):gsub("&quot;", '"')
    html = html:gsub("&#39;", "'"):gsub("&#x27;", "'")
    html = html:gsub("&apos;", "'"):gsub("&lt;", "<"):gsub("&gt;", ">")
    html = clean(html)

    local function add(nameText, valueText)
        local name = clean(nameText)
        local finalImageName = name:match(".*Image:%s*(.+)$")
        if finalImageName then name = finalImageName end
        name = name:gsub("^Image:%s*", "")
        name = name:gsub("%s*|.*$", "")
        name = name:gsub("%s+Contains%s*%-%s*.*$", "")
        name = name:gsub("%s+Value%s*$", "")

        local normalized = key(name)
        local rawValue = clean(valueText):gsub(",", "")
        local number = tonumber(rawValue:match("^[%d%.%-]+") or "")
        if normalized ~= "" and number ~= nil
            and not normalized:find("item stability", 1, true)
            and not normalized:find("image stability", 1, true)
            and not out[normalized] then
            out[normalized] = {name = name, value = number, valueText = clean(valueText)}
            parsedCount = parsedCount + 1
        end
    end

    -- The site renders each item as: Image: NAME | DISPLAY NAME Value - NUMBER.
    -- Parse one image-delimited card at a time so text from adjacent cards cannot mix.
    local cursor = 1
    while cursor <= #html do
        local markerStart, markerEnd = html:find("Image:", cursor, true)
        if not markerStart then break end
        local nextMarker = html:find("Image:", markerEnd + 1, true)
        local segment = html:sub(markerEnd + 1, (nextMarker or (#html + 1)) - 1)

        local nameText, valueText = segment:match(
            "^%s*(.-)%s*|%s*.-%s+Value%s*%-%s*([%d,%.]+)"
        )
        if not nameText then
            nameText, valueText = segment:match(
                "^%s*(.-)%s+Value%s*%-%s*([%d,%.]+)"
            )
        end
        if nameText then add(nameText, valueText) end
        cursor = nextMarker or (#html + 1)
    end

    -- Secondary whole-page pass: some site layouts put the item label and
    -- value in the same text stream but split cards with extra image markers.
    -- Run this even when the segmented pass found other items; otherwise one
    -- malformed card can silently omit a valid item such as Emberbow.
    for nameText, valueText in html:gmatch("Image:%s*(.-)%s*|%s*.-%s+Value%s*%-%s*([%d,%.]+)") do
        add(nameText, valueText)
    end

    -- Fallback for list layouts where item images have no alt text.
    for nameText, valueText in html:gmatch("|%s*(.-)%s+Value%s*%-%s*([%d,%.]+)") do
        add(nameText, valueText)
    end
    return parsedCount
end

local function refreshValues()
    local fresh = {}
    local fetchedPages, parsedPages, parsedEntries = 0, 0, 0
    local pageErrors, fetchMethods = {}, {}
    for _, cat in ipairs(CATEGORIES) do
        if stopped then return end
        local html, fetchInfo = get(BASE .. cat)
        if html then
            fetchedPages = fetchedPages + 1
            fetchMethods[fetchInfo or "unknown"] = (fetchMethods[fetchInfo or "unknown"] or 0) + 1
            local count = parsePage(html, fresh)
            if count > 0 then parsedPages = parsedPages + 1 end
            parsedEntries = parsedEntries + count
        else
            table.insert(pageErrors, cat .. ": " .. tostring(fetchInfo or "request failed"))
        end
        task.wait(0.12)
    end
    _G.__SUPREME_FETCHED_PAGES = fetchedPages
    _G.__SUPREME_PARSED_PAGES = parsedPages
    _G.__SUPREME_PARSED_ENTRIES = parsedEntries
    _G.__SUPREME_FETCH_METHODS = fetchMethods
    _G.__SUPREME_FAILED_PAGES = table.concat(pageErrors, ", ")
    if next(fresh) then
        for itemKey, data in pairs(fresh) do values[itemKey] = data end
        valueNames = {}
        for itemKey in pairs(values) do table.insert(valueNames, itemKey) end
        table.sort(valueNames, function(a, b) return #a > #b end)
        lastUpdate = os.date("%H:%M:%S")
        return true
    end
    return false
end


-- No standalone menu: annotate the native MM2 trade UI text directly.
local textGui = Instance.new("ScreenGui")
textGui.Name = "SupremeTradeText"
textGui.ResetOnSpawn = false
textGui.DisplayOrder = 999
textGui.Parent = playerGui
textGui.Enabled = true
textGui.IgnoreGuiInset = true
textGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
textGui.DisplayOrder = 9999

-- Create visible feedback immediately. Do not wait for external value-site requests.
local diagnosticPanel = Instance.new("Frame")
diagnosticPanel.Name = "SupremeInventoryDiagnostic"
diagnosticPanel.Size = UDim2.new(0, 290, 0, 245)
diagnosticPanel.Position = UDim2.new(1, -12, 0, 88)
diagnosticPanel.AnchorPoint = Vector2.new(1, 0)
diagnosticPanel.BackgroundColor3 = Color3.fromRGB(16, 19, 29)
diagnosticPanel.BackgroundTransparency = 0.08
diagnosticPanel.BorderSizePixel = 0
diagnosticPanel.ZIndex = 200
diagnosticPanel.Visible = true
diagnosticPanel.Parent = textGui

local diagnosticTitle = Instance.new("TextLabel")
diagnosticTitle.Size = UDim2.new(1, -48, 0, 34)
diagnosticTitle.Position = UDim2.new(0, 10, 0, 0)
diagnosticTitle.BackgroundTransparency = 1
diagnosticTitle.Font = Enum.Font.GothamBold
diagnosticTitle.TextSize = 12
diagnosticTitle.TextColor3 = Color3.fromRGB(120, 220, 255)
diagnosticTitle.TextXAlignment = Enum.TextXAlignment.Left
diagnosticTitle.Text = "SUPREME"
diagnosticTitle.TextTruncate = Enum.TextTruncate.AtEnd
diagnosticTitle.Active = true
diagnosticTitle.ZIndex = 201
diagnosticTitle.Parent = diagnosticPanel

local latestResults = "Supreme Trade Checker is loading..."
local iconToItem = {}

local function copyResults(text)
    text = tostring(text or "")
    local clipboardFunctions = {
        setclipboard = setclipboard,
        toclipboard = toclipboard,
        setrbxclipboard = setrbxclipboard
    }
    for _, clipboardFunction in pairs(clipboardFunctions) do
        if type(clipboardFunction) == "function" then
            local ok, result = pcall(clipboardFunction, text)
            if ok and result ~= false then return true end
        end
    end

    if type(Clipboard) == "table" and type(Clipboard.set) == "function" then
        local ok, result = pcall(Clipboard.set, text)
        if ok and result ~= false then return true end
    end
    return false
end

local function buildCopyReport()
    local lines = {
        "SUPREME TRADE CHECKER — FULL DIAGNOSTIC",
        "Time: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Values loaded: " .. tostring(#valueNames),
        "Pages fetched: " .. tostring(_G.__SUPREME_FETCHED_PAGES or 0),
        "Pages parsed: " .. tostring(_G.__SUPREME_PARSED_PAGES or 0),
        "Entries parsed: " .. tostring(_G.__SUPREME_PARSED_ENTRIES or 0),
        "Fetch methods: " .. tostring(_G.__SUPREME_FETCH_METHODS and "see details below" or "not reported"),
        "Failed pages: " .. tostring(_G.__SUPREME_FAILED_PAGES or "none")
    }

    local methods = _G.__SUPREME_FETCH_METHODS or {}
    for method, count in pairs(methods) do
        table.insert(lines, "  " .. tostring(method) .. ": " .. tostring(count))
    end

    local iconCount = 0
    for _ in pairs(iconToItem or {}) do iconCount = iconCount + 1 end
    table.insert(lines, "MM2 icon mappings: " .. tostring(iconCount))

    local emberbow = values["emberbow"]
    if emberbow then
        table.insert(lines, "Emberbow lookup: FOUND | " .. tostring(emberbow.name) .. " | Value: " .. tostring(emberbow.value))
    else
        table.insert(lines, "Emberbow lookup: NOT FOUND")
    end

    table.insert(lines, "")
    table.insert(lines, "CURRENT TRADE / SCAN RESULT:")
    table.insert(lines, tostring(latestResults or "No current result"))
    return table.concat(lines, "\n")
end

local copyResultsButton = Instance.new("TextButton")
copyResultsButton.Name = "CopySupremeResults"
copyResultsButton.Size = UDim2.new(1, -20, 0, 34)
copyResultsButton.Position = UDim2.new(0, 10, 0, 40)
copyResultsButton.BackgroundColor3 = Color3.fromRGB(35, 125, 145)
copyResultsButton.BorderSizePixel = 0
copyResultsButton.Font = Enum.Font.GothamBold
copyResultsButton.TextSize = 13
copyResultsButton.TextColor3 = Color3.new(1, 1, 1)
copyResultsButton.Text = "COPY FULL DIAGNOSTIC"
copyResultsButton.ZIndex = 205
copyResultsButton.Parent = diagnosticPanel

local function onCopyResults()
    local report = buildCopyReport()
    if copyResults(report) then
        copyResultsButton.Text = "COPIED — SEND THE TEXT"
    else
        copyResultsButton.Text = "CLIPBOARD API UNAVAILABLE"
    end
    task.delay(3, function()
        if copyResultsButton and copyResultsButton.Parent then
            copyResultsButton.Text = "COPY FULL DIAGNOSTIC"
        end
    end)
end
copyResultsButton.Activated:Connect(onCopyResults)


local diagnosticClose = Instance.new("TextButton")
diagnosticClose.Size = UDim2.new(0, 34, 0, 30)
diagnosticClose.Position = UDim2.new(1, -38, 0, 2)
diagnosticClose.BackgroundColor3 = Color3.fromRGB(65, 38, 48)
diagnosticClose.BorderSizePixel = 0
diagnosticClose.Font = Enum.Font.GothamBold
diagnosticClose.TextSize = 16
diagnosticClose.TextColor3 = Color3.new(1, 1, 1)
diagnosticClose.Text = "X"
diagnosticClose.ZIndex = 202
diagnosticClose.Parent = diagnosticPanel
-- The same button is wired below as the expand/collapse toggle.

local diagnosticOutput = Instance.new("TextBox")
diagnosticOutput.Name = "DiagnosticText"
diagnosticOutput.Size = UDim2.new(1, -20, 1, -88)
diagnosticOutput.Position = UDim2.new(0, 10, 0, 80)
diagnosticOutput.BackgroundColor3 = Color3.fromRGB(9, 11, 18)
diagnosticOutput.BackgroundTransparency = 0.1
diagnosticOutput.BorderSizePixel = 0
diagnosticOutput.ClearTextOnFocus = false
diagnosticOutput.MultiLine = true
diagnosticOutput.TextEditable = true
diagnosticOutput.TextWrapped = false
diagnosticOutput.TextXAlignment = Enum.TextXAlignment.Left
diagnosticOutput.TextYAlignment = Enum.TextYAlignment.Top
diagnosticOutput.Font = Enum.Font.Code
diagnosticOutput.TextSize = 11
diagnosticOutput.TextColor3 = Color3.fromRGB(225, 231, 242)
diagnosticOutput.Text = "Script injected. Waiting for inventory scan..."
diagnosticOutput.ZIndex = 201
diagnosticOutput.Parent = diagnosticPanel

-- Start minimized so the native MM2 trade buttons remain accessible.
local panelCollapsed = true
local diagnosticStatusText = "SUPREME — STARTING"
local expandedPanelSize = UDim2.new(0, 290, 0, 245)
local collapsedPanelSize = UDim2.new(0, 150, 0, 34)

local function setDiagnosticStatus(status)
    diagnosticStatusText = tostring(status or "SUPREME")
    diagnosticTitle.Text = panelCollapsed and "SUPREME" or diagnosticStatusText
end

local function setPanelCollapsed(collapsed)
    panelCollapsed = collapsed
    diagnosticPanel.Size = collapsed and collapsedPanelSize or expandedPanelSize
    diagnosticTitle.Text = collapsed and "SUPREME" or diagnosticStatusText
    copyResultsButton.Visible = not collapsed
    diagnosticOutput.Visible = not collapsed
    diagnosticClose.Text = collapsed and "+" or "−"
end

diagnosticClose.Name = "SupremePanelToggle"
diagnosticClose.BackgroundColor3 = Color3.fromRGB(35, 95, 125)
diagnosticClose.Text = "+"
diagnosticClose.Activated:Connect(function()
    setPanelCollapsed(not panelCollapsed)
end)
setPanelCollapsed(true)

-- Drag the panel from its title area (mouse or touchscreen).
local dragging = false
local dragStartPosition
local panelStartPosition

diagnosticTitle.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStartPosition = input.Position
        panelStartPosition = diagnosticPanel.Position
        local endedConnection
        endedConnection = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                if endedConnection then endedConnection:Disconnect() end
            end
        end)
    end
end)

UIS.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStartPosition
        diagnosticPanel.Position = UDim2.new(
            panelStartPosition.X.Scale, panelStartPosition.X.Offset + delta.X,
            panelStartPosition.Y.Scale, panelStartPosition.Y.Offset + delta.Y
        )
    end
end)


local originalText = setmetatable({}, {__mode = "k"})
local lastApplied = setmetatable({}, {__mode = "k"})
local activeText = setmetatable({}, {__mode = "k"})

local function restoreNativeText()
    for object, original in pairs(originalText) do
        if object and object.Parent then
            pcall(function() object.Text = original end)
        end
        originalText[object] = nil
        lastApplied[object] = nil
    end
end

local function rememberAndSet(object, newText)
    activeText[object] = true
    if not originalText[object] then
        originalText[object] = object.Text
    end
    if lastApplied[object] ~= newText then
        pcall(function() object.Text = newText end)
        lastApplied[object] = newText
    end
end

local function fmt(n)
    local s = tostring(math.floor(n or 0))
    while true do
        local a,b = s:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        s = a
        if b == 0 then break end
    end
    return s
end

local function normalizeGuiName(name)
    return string.lower(tostring(name or "")):gsub("[^%a%d]","")
end

local function findOfferAnchor(tradeGui, wantedName, headingText)
    -- Prefer the visible named container; some builds keep hidden templates nearby.
    local named = tradeGui:FindFirstChild(wantedName, true)
    if named and named:IsA("GuiObject") and named.Visible then return named end

    local normalizedWanted = normalizeGuiName(wantedName)
    for _, object in ipairs(tradeGui:GetDescendants()) do
        if object:IsA("GuiObject") and object.Visible
            and normalizeGuiName(object.Name) == normalizedWanted then
            return object
        end
    end

    local wanted = string.lower(headingText)
    for _, object in ipairs(tradeGui:GetDescendants()) do
        if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Visible then
            local text = string.lower(clean(object.Text))
            if text == wanted or text:find(wanted,1,true) then
                return object
            end
        end
    end
    return nil
end

-- Forward declaration: trade cards often expose only their image asset id.
local imageItemName

local function scanTrade()
    local tradeGui = playerGui:FindFirstChild("TradeGUI")
    if not tradeGui or (tradeGui:IsA("ScreenGui") and not tradeGui.Enabled) then
        tradeGui = playerGui:FindFirstChild("TradeGUI_Phone")
    end
    if not tradeGui then return nil end

    local yourAnchor = findOfferAnchor(tradeGui, "YourOffer", "your offer")
    local theirAnchor = findOfferAnchor(tradeGui, "TheirOffer", "their offer")
    if not yourAnchor and not theirAnchor then return nil end

    local function matchCandidate(candidate)
        local normalized = key(candidate)
        if normalized == "" then return nil end
        for _, itemKey in ipairs(valueNames) do
            if normalized == itemKey or normalized:find(itemKey,1,true) then
                return itemKey
            end
        end
        return nil
    end

    local function readCount(text)
        text = clean(text)
        return tonumber(text:match("[xX×]%s*(%d+)"))
            or tonumber(text:match("(%d+)%s*[xX×]")) or 1
    end

    local function offerScope(anchor, wantedName)
        if not anchor then return nil end
        local current = anchor
        while current and current ~= tradeGui do
            if normalizeGuiName(current.Name) == normalizeGuiName(wantedName) then
                return current
            end
            current = current.Parent
        end
        if anchor:IsA("TextLabel") or anchor:IsA("TextButton") then
            return anchor.Parent or anchor
        end
        return anchor
    end

    local function collect(anchor, wantedName)
        local found, total = {}, 0
        local scope = offerScope(anchor, wantedName)
        if not scope then return found, total end

        local nodes = {scope}
        local ok, descendants = pcall(function() return scope:GetDescendants() end)
        if ok then
            for _, node in ipairs(descendants) do table.insert(nodes,node) end
        end

        local seenCards = {}
        for _, object in ipairs(nodes) do
            local candidates = {}
            if object:IsA("TextLabel") or object:IsA("TextButton") then
                table.insert(candidates, clean(object.Text))
            elseif object:IsA("StringValue") then
                table.insert(candidates, clean(object.Value))
            end

            local objectName = clean(object.Name)
            if objectName ~= "" and not objectName:match("^NewItem%d+$") then
                table.insert(candidates, objectName)
            end

            -- MM2 offer slots can be image-only (NewItem1..3); resolve their
            -- Roblox image id through the replicated item database as well.
            if imageItemName and (object:IsA("ImageLabel") or object:IsA("ImageButton")) then
                local mappedName = imageItemName(object)
                if mappedName then table.insert(candidates, mappedName) end
            end

            local attrs = {}
            pcall(function() attrs = object:GetAttributes() end)
            for _, attrValue in pairs(attrs) do
                if type(attrValue) == "string" then
                    table.insert(candidates, clean(attrValue))
                end
            end

            local matchedKey, matchedText
            for _, candidate in ipairs(candidates) do
                local itemKey = matchCandidate(candidate)
                if itemKey then
                    matchedKey, matchedText = itemKey, candidate
                    break
                end
            end

            if matchedKey then
                local card = object
                local current = object
                for _ = 1, 7 do
                    if not current or current == scope then break end
                    if current:IsA("ImageButton") or current:IsA("ImageLabel")
                        or tostring(current.Name):match("^NewItem%d+$") then
                        card = current
                        break
                    end
                    current = current.Parent
                end

                if not seenCards[card] then
                    seenCards[card] = true
                    local data = values[matchedKey]
                    local count = readCount(matchedText)
                    local displayObject = (object:IsA("TextLabel") or object:IsA("TextButton")) and object or nil
                    table.insert(found, {
                        object = displayObject,
                        card = card,
                        key = matchedKey,
                        count = count,
                        data = data,
                        base = matchedText
                    })
                    total = total + (data.value or 0) * count
                end
            end
        end
        return found, total
    end

    local yours, yourTotal = collect(yourAnchor, "YourOffer")
    local theirs, theirTotal = collect(theirAnchor, "TheirOffer")
    return {
        yourAnchor = yourAnchor,
        theirAnchor = theirAnchor,
        yours = yours,
        theirs = theirs,
        yourTotal = yourTotal,
        theirTotal = theirTotal
    }
end

local tradeBadges = setmetatable({}, {__mode = "k"})
local offerTotalBadges = setmetatable({}, {__mode = "k"})

local function makeValueBadge(parent, name, size, position)
    local badge = parent:FindFirstChild(name)
    if not badge then
        badge = Instance.new("TextLabel")
        badge.Name = name
        badge.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
        badge.BackgroundTransparency = 0.12
        badge.BorderSizePixel = 0
        badge.TextColor3 = Color3.fromRGB(255, 235, 145)
        badge.TextSize = 10
        badge.Font = Enum.Font.GothamBold
        badge.TextStrokeTransparency = 0.8
        badge.TextXAlignment = Enum.TextXAlignment.Center
        badge.TextYAlignment = Enum.TextYAlignment.Center
        badge.Size = size
        badge.Position = position
        badge.ZIndex = 100
        badge.Parent = parent
    end
    return badge
end

local function annotateSide(anchor, items, total, sideName)
    if not anchor then return end
    local totalText = sideName .. " • TOTAL: " .. fmt(total)

    if anchor:IsA("TextLabel") or anchor:IsA("TextButton") then
        local base = originalText[anchor] or anchor.Text
        base = clean(base):gsub("%s*[•|%-]%s*TOTAL:%s*[%d,]+","")
        rememberAndSet(anchor, base .. "  |  " .. totalText)
    elseif anchor:IsA("GuiObject") then
        local badge = offerTotalBadges[anchor]
        if not badge or not badge.Parent then
            badge = makeValueBadge(anchor, "SupremeOfferTotal",
                UDim2.new(1,-8,0,18), UDim2.new(0,4,1,-20))
            offerTotalBadges[anchor] = badge
        end
        badge.Text = totalText
    end

    for _, item in ipairs(items) do
        local unitValue = item.data.value
        local totalValue = (unitValue or 0) * item.count
        local amountText = unitValue and
            (fmt(unitValue) .. " ×" .. tostring(item.count) .. " = " .. fmt(totalValue)) or "N/A"

        if item.object then
            local base = originalText[item.object] or item.base
            base = clean(base):gsub("%s+%[[^%]]*%]$","")
            rememberAndSet(item.object, base .. "  [" .. amountText .. "]")
        elseif item.card and item.card:IsA("GuiObject") then
            local badge = tradeBadges[item.card]
            if not badge or not badge.Parent then
                badge = makeValueBadge(item.card, "SupremeTradeValue",
                    UDim2.new(0,92,0,18), UDim2.new(1,-94,0,2))
                tradeBadges[item.card] = badge
            end
            badge.Text = "[" .. amountText .. "]"
        end
    end
end

-- Build an icon-id -> item-name index from MM2's replicated item database.
-- The inventory GUI in some mobile layouts only exposes icon images, not item names.
iconToItem = {}
local function addIconMapping(imageValue, itemName)
    if type(imageValue) ~= "string" and type(imageValue) ~= "number" then return end
    local imageText = tostring(imageValue)
    local id = imageText:match("rbxassetid://(%d+)") or imageText:match("[?&]id=(%d+)")
        or imageText:match("^(%d+)$")
    if id and type(itemName) == "string" and clean(itemName) ~= "" then
        iconToItem[id] = clean(itemName)
    end
end

local function walkItemDatabase(node, depth, inheritedName, seen)
    if depth > 7 or type(node) ~= "table" or seen[node] then return end
    seen[node] = true
    for field, value in pairs(node) do
        if type(value) == "table" then
            local candidateName = type(field) == "string" and field or inheritedName
            local image = value.Image or value.ImageId or value.Icon or value.IconId
                or value.Texture or value.AssetId or value.ImageAsset or value.ImageURL
            local displayName = value.Name or value.ItemName or value.DisplayName
                or value.name or value.itemName or candidateName
            if image and displayName then addIconMapping(image, displayName) end
            walkItemDatabase(value, depth + 1, displayName or candidateName, seen)
        end
    end
end

local function refreshIconDatabase()
    local replicated = game:GetService("ReplicatedStorage")
    local candidates = {}
    for _, node in ipairs(replicated:GetDescendants()) do
        if node:IsA("ModuleScript") then
            local n = string.lower(node.Name)
            if n == "item" or n == "items" or n == "itemdata" or n == "database"
                or n == "weapon" or n == "weapons" or n == "pets" then
                table.insert(candidates, node)
            end
        end
    end
    for _, module in ipairs(candidates) do
        local ok, data = pcall(require, module)
        if ok and type(data) == "table" then
            walkItemDatabase(data, 0, nil, {})
        end
    end
end

imageItemName = function(object)
    if not (object:IsA("ImageLabel") or object:IsA("ImageButton")) then return nil end
    local image = tostring(object.Image or "")
    local id = image:match("rbxassetid://(%d+)") or image:match("[?&]id=(%d+)")
        or image:match("^(%d+)$")
    if not id then return nil end
    return iconToItem[id]
end

local inventoryBadges = setmetatable({}, {__mode = "k"})

local function inventoryCandidate(object)
    local candidates = {}
    local function add(value)
        value = clean(value)
        if value ~= "" then table.insert(candidates, value) end
    end

    if object:IsA("TextLabel") or object:IsA("TextButton") then
        add(originalText[object] or object.Text)
    elseif object:IsA("StringValue") then
        add(object.Value)
    end
    add(object.Name)
    local iconName = imageItemName(object)
    if iconName then add(iconName) end

    local attrs = {}
    pcall(function() attrs = object:GetAttributes() end)
    for attributeName, attributeValue in pairs(attrs) do
        if type(attributeValue) == "string" then
            add(attributeValue)
        end
    end

    local parent = object.Parent
    local depth = 0
    while parent and depth < 4 do
        if parent:IsA("GuiObject") then
            add(parent.Name)
            local parentAttrs = {}
            pcall(function() parentAttrs = parent:GetAttributes() end)
            for _, attributeValue in pairs(parentAttrs) do
                if type(attributeValue) == "string" then add(attributeValue) end
            end
        end
        parent = parent.Parent
        depth = depth + 1
    end

    for _, candidate in ipairs(candidates) do
        local normalized = key(candidate)
        for _, itemKey in ipairs(valueNames) do
            if normalized == itemKey or normalized:find(itemKey, 1, true) then
                return itemKey, candidate
            end
        end
    end
end

local function findCardRoot(object)
    local current = object
    for _ = 1, 5 do
        if not current or not current.Parent then break end
        if current:IsA("ImageButton") or current:IsA("ImageLabel") then
            return current
        end
        current = current.Parent
    end
    if object.Parent and object.Parent:IsA("GuiObject") then
        return object.Parent
    end
    return object
end

local function updateInventory(trade)
    local foundCards, inventoryTotal = {}, 0
    local inventoryHeading

    local function isInsideTradeOffer(object)
        if not trade then return false end
        for _, anchor in ipairs({trade.yourAnchor, trade.theirAnchor}) do
            if anchor and object:FindFirstAncestorOfClass("ScreenGui") == anchor:FindFirstAncestorOfClass("ScreenGui") then
                local p, a, z = object.AbsolutePosition, anchor.AbsolutePosition, anchor.AbsoluteSize
                if p.Y >= a.Y - 8 and p.Y <= a.Y + z.Y + 245
                    and p.X >= a.X - 30 and p.X <= a.X + math.max(z.X, 150) + 240 then
                    return true
                end
            end
        end
        return false
    end

    local function addCard(card)
        if not card or not card.Parent or foundCards[card] then return end
        local bestKey, bestText, bestObject
        local nodes = {card}
        local ok, descendants = pcall(function() return card:GetDescendants() end)
        if ok then
            for _, node in ipairs(descendants) do table.insert(nodes, node) end
        end

        for _, node in ipairs(nodes) do
            -- MM2 item cards may store the item name in a text object, a
            -- StringValue, an attribute, or a meaningful child/parent name.
            local itemKey, matchedText = inventoryCandidate(node)
            if itemKey then
                bestKey, bestText, bestObject = itemKey, matchedText, node
                if node:IsA("TextLabel") or node:IsA("TextButton") then break end
            end
        end

        if not bestKey then return end
        local data = values[bestKey]
        local countText = (bestText or "") .. " " .. (bestObject and bestObject.Name or "")
        local count = tonumber(countText:match("[xX×]%s*(%d+)"))
            or tonumber(countText:match("(%d+)%s*[xX×]")) or 1
        foundCards[card] = {
            card = card,
            textObject = bestObject and (bestObject:IsA("TextLabel") or bestObject:IsA("TextButton")) and bestObject or nil,
            data = data,
            count = count,
            itemKey = bestKey,
            displayName = data.name
        }
    end

    -- MM2's actual inventory lives in TradeGUI/Container/Items/_mO.
    -- Scan the Weapons and Pets ScrollingFrames directly instead of guessing
    -- from every ImageLabel in PlayerGui/CoreGui.
    local tradeGui = playerGui:FindFirstChild("TradeGUI")
    if tradeGui and tradeGui:IsA("ScreenGui") and not tradeGui.Enabled then
        tradeGui = nil
    end
    if not tradeGui then
        tradeGui = playerGui:FindFirstChild("TradeGUI_Phone")
        if tradeGui and tradeGui:IsA("ScreenGui") and not tradeGui.Enabled then
            tradeGui = nil
        end
    end
    if tradeGui then
        local container = tradeGui:FindFirstChild("Container", true)
        local items = container and container:FindFirstChild("Items", true)
        local itemRoot = items and items:FindFirstChild("_mO", true)

        if itemRoot then
            for _, categoryName in ipairs({"Weapons", "Pets"}) do
                local list = itemRoot:FindFirstChild(categoryName)
                if list and list:IsA("ScrollingFrame") and list.Visible then
                    -- This build nests the actual cards under a Frame named "Items".
                    -- Walk descendants, not just the one wrapper child.
                    for _, node in ipairs(list:GetDescendants()) do
                        if node:IsA("ImageButton") or node:IsA("ImageLabel") then
                            -- Use the nearest card frame only. Climbing to the
                            -- direct child would collapse every item into "Items".
                            local root = node
                            local parent = node.Parent
                            if parent and parent ~= list and parent:IsA("Frame") then
                                root = parent
                            end
                            addCard(root)
                        end
                    end
                    for _, card in ipairs(list:GetChildren()) do
                        if card:IsA("GuiObject") and card.Visible and card.Name ~= "Items" then
                            addCard(card)
                        end
                    end
                end
            end
        end
    end

    -- Fallback for alternate MM2 layouts / phone UI variants. Only consider
    -- objects inside inventory scrolling frames; never scan unrelated HUD art.
    if next(foundCards) == nil and tradeGui then
        local ok, descendants = pcall(function() return tradeGui:GetDescendants() end)
        if ok then
            for _, object in ipairs(descendants) do
                if object:IsA("ScrollingFrame") and object.Visible
                    and (object.Name == "Weapons" or object.Name == "Pets") then
                    for _, card in ipairs(object:GetChildren()) do
                        if card:IsA("GuiObject") and card.Visible then addCard(card) end
                    end
                end
            end
        end
    end

    for card, item in pairs(foundCards) do
        local unitValue = item.data.value
        local amount = (unitValue or 0) * item.count
        inventoryTotal = inventoryTotal + amount
        local amountText = unitValue and
            (fmt(unitValue) .. " ×" .. tostring(item.count) .. " = " .. fmt(amount)) or "N/A"

        if item.textObject then
            local base = originalText[item.textObject] or clean(item.textObject.Text)
            base = base:gsub("%s+%[[^%]]*%]$", "")
            rememberAndSet(item.textObject, base .. "  [" .. amountText .. "]")
        else
            -- Image-only cards receive a small price badge on the card itself.
            local badge = inventoryBadges[card]
            if not badge or not badge.Parent then
                badge = Instance.new("TextLabel")
                badge.Name = "SupremeValueTag"
                badge.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
                badge.BackgroundTransparency = 0.15
                badge.TextColor3 = Color3.fromRGB(255, 235, 145)
                badge.TextSize = 11
                badge.Font = Enum.Font.GothamBold
                badge.TextStrokeTransparency = 0.7
                badge.Size = UDim2.new(0, 48, 0, 18)
                badge.Position = UDim2.new(1, -50, 0, 2)
                badge.AnchorPoint = Vector2.new(0, 0)
                badge.ZIndex = 100
                badge.Parent = card
                inventoryBadges[card] = badge
            end
            badge.Text = "[" .. amountText .. "]"
        end
    end

    -- Keep inventory totals off the tiny native tab labels; they can clip on mobile.

end

-- Expanded one-shot report: include nested GUI names and every item image,
-- because this MM2 build wraps the visible inventory cards in an extra Frame.
local diagnosticReport = ""
local function reportInventoryStructure()
    local lines = {"[Supreme Trade Text] INVENTORY DIAGNOSTIC"}
    local emitted = 0
    local function add(line)
        if emitted >= 100 then return end
        emitted = emitted + 1
        table.insert(lines, line)
    end

    for _, guiName in ipairs({"TradeGUI", "TradeGUI_Phone"}) do
        local gui = playerGui:FindFirstChild(guiName)
        if gui then
            add("GUI: " .. guiName .. " enabled=" .. tostring(not gui:IsA("ScreenGui") or gui.Enabled))
            local lists = {}
            for _, node in ipairs(gui:GetDescendants()) do
                if node:IsA("ScrollingFrame") and (node.Name == "Weapons" or node.Name == "Pets") then
                    table.insert(lists, node)
                end
            end
            for _, list in ipairs(lists) do
                add(" LIST: " .. list:GetFullName() .. " visible=" .. tostring(list.Visible))
                local cardCount = 0
                for _, card in ipairs(list:GetChildren()) do
                    if card:IsA("GuiObject") and card.Visible and card.Name ~= "UIListLayout" then
                        cardCount = cardCount + 1
                        if cardCount <= 2 then
                            add("  ROOT: " .. card.Name .. " [" .. card.ClassName .. "]")
                            local descendants = card:GetDescendants()
                            add("  DESCENDANTS: " .. tostring(#descendants))
                            for _, node in ipairs(descendants) do
                                local line = "   " .. node.ClassName .. " " .. node.Name
                                if node:IsA("TextLabel") or node:IsA("TextButton") then
                                    line = line .. " TEXT=" .. string.sub(clean(node.Text), 1, 70)
                                elseif node:IsA("StringValue") or node:IsA("IntValue") or node:IsA("NumberValue") then
                                    line = line .. " VALUE=" .. string.sub(clean(node.Value), 1, 70)
                                elseif node:IsA("ImageLabel") or node:IsA("ImageButton") then
                                    line = line .. " IMAGE=" .. string.sub(tostring(node.Image), 1, 90)
                                end
                                local attrs = {}
                                pcall(function() attrs = node:GetAttributes() end)
                                for attrName, attrValue in pairs(attrs) do
                                    line = line .. " ATTR[" .. tostring(attrName) .. "]=" .. string.sub(tostring(attrValue), 1, 50)
                                end
                                add(line)
                            end
                        end
                    end
                end
                add("  VISIBLE DIRECT CHILDREN: " .. tostring(cardCount))
            end
        end
    end
    add("END DIAGNOSTIC")
    diagnosticReport = table.concat(lines, "\n")
    latestResults = diagnosticReport
    setDiagnosticStatus("SUPREME — SCAN DETAILS")
    diagnosticOutput.Text = diagnosticReport
    pcall(function() diagnosticOutput.CursorPosition = 1 end)
    warn(diagnosticReport)
end

local tradeSummary = Instance.new("TextLabel")
tradeSummary.Name = "SupremeTradeSummary"
tradeSummary.Size = UDim2.new(0,300,0,28)
tradeSummary.Position = UDim2.new(0.5,-150,0.08,0)
tradeSummary.BackgroundColor3 = Color3.fromRGB(16,19,29)
tradeSummary.BackgroundTransparency = 0.08
tradeSummary.BorderSizePixel = 0
tradeSummary.Font = Enum.Font.GothamBold
tradeSummary.TextSize = 12
tradeSummary.TextColor3 = Color3.fromRGB(120,220,255)
tradeSummary.TextStrokeTransparency = 0.85
tradeSummary.Text = "SUPREME • WAITING FOR TRADE"
tradeSummary.Visible = false
tradeSummary.ZIndex = 250
tradeSummary.Parent = textGui

local function getTradeVerdict(yourTotal, theirTotal)
    local difference = theirTotal - yourTotal
    -- A difference within 5% of the higher side is treated as FAIR.
    local tolerance = math.max(1, math.max(yourTotal,theirTotal) * 0.05)
    if math.abs(difference) <= tolerance then
        return "FAIR", difference
    elseif difference > 0 then
        return "WIN", difference
    end
    return "LOSE", difference
end

local function update()
    activeText = setmetatable({}, {__mode = "k"})
    local trade = scanTrade()

    local resultLines = {"SUPREME TRADE CHECKER"}
    local function addSide(label, items, total)
        table.insert(resultLines, label .. " TOTAL: " .. fmt(total))
        for _, item in ipairs(items) do
            local unit = item.data and item.data.value
            local itemName = item.data and item.data.name or item.key or "Unknown item"
            local count = item.count or 1
            local lineValue = unit and (fmt(unit) .. " each; total " .. fmt(unit * count)) or "N/A"
            table.insert(resultLines, "  - " .. itemName .. " x" .. tostring(count) .. " | " .. lineValue)
        end
    end
    if trade then
        addSide("YOUR OFFER", trade.yours, trade.yourTotal)
        addSide("THEIR OFFER", trade.theirs, trade.theirTotal)
        if #trade.yours > 0 and #trade.theirs > 0 then
            local verdict, difference = getTradeVerdict(trade.yourTotal, trade.theirTotal)
            table.insert(resultLines, "RESULT: " .. verdict .. " | Difference: " .. (difference > 0 and "+" or "") .. fmt(difference))
        else
            table.insert(resultLines, "RESULT: Waiting for both sides of the trade.")
        end
    else
        table.insert(resultLines, "No active trade detected.")
    end
    table.insert(resultLines, "Source: Supreme Values | Updated: " .. tostring(lastUpdate))
    latestResults = table.concat(resultLines, "\n")
    if trade then
        annotateSide(trade.yourAnchor, trade.yours, trade.yourTotal, "YOUR")
        annotateSide(trade.theirAnchor, trade.theirs, trade.theirTotal, "THEIR")

        if #trade.yours > 0 and #trade.theirs > 0 then
            local verdict, difference = getTradeVerdict(trade.yourTotal,trade.theirTotal)
            local sign = difference > 0 and "+" or ""
            tradeSummary.Text = "SUPREME • " .. verdict .. "  |  YOU GET " ..
                fmt(trade.theirTotal) .. " / GIVE " .. fmt(trade.yourTotal) ..
                "  (" .. sign .. fmt(difference) .. ")"
            tradeSummary.Visible = true
        else
            tradeSummary.Visible = false
        end
    else
        tradeSummary.Visible = false
    end
    updateInventory(trade)

    -- Restore text that no longer belongs to a visible trade or inventory item.
    for object, original in pairs(originalText) do
        if not activeText[object] then
            if object and object.Parent then
                pcall(function() object.Text = original end)
            end
            originalText[object] = nil
            lastApplied[object] = nil
        end
    end
end

task.spawn(function()
    task.wait(0.25)
    setDiagnosticStatus("SUPREME — LOADING")
    diagnosticOutput.Text = "Reading MM2 item database and Supreme Values...\\nInventory scanner active."
    local iconOk, iconErr = pcall(refreshIconDatabase)
    if not iconOk then warn("[Supreme Trade Text] Item icon database scan failed: " .. tostring(iconErr)) end
    local loaded = refreshValues()
    local valueCount = #valueNames
    local iconCount = 0
    for _ in pairs(iconToItem) do iconCount = iconCount + 1 end
    local dbLine = loaded and ("VALUES: " .. tostring(valueCount) .. " loaded • " .. lastUpdate)
        or "VALUES: 0 loaded — Supreme Values request/parser failed"
    setDiagnosticStatus(loaded and "SUPREME — DATABASE READY" or "SUPREME — DATABASE ERROR")
    local fetchMethodText = ""
    for method, count in pairs(_G.__SUPREME_FETCH_METHODS or {}) do
        fetchMethodText = fetchMethodText .. method .. "=" .. tostring(count) .. " "
    end
    local parseLine = "Parsed pages: " .. tostring(_G.__SUPREME_PARSED_PAGES or 0)
        .. " • Entries: " .. tostring(_G.__SUPREME_PARSED_ENTRIES or 0)
    latestResults = dbLine .. "\nPages fetched: " .. tostring(_G.__SUPREME_FETCHED_PAGES or 0)
        .. "\n" .. parseLine .. "\nFetch: " .. fetchMethodText
        .. "\nFailed pages: " .. tostring(_G.__SUPREME_FAILED_PAGES or "none")
        .. "\nMM2 icon mappings: " .. tostring(iconCount)
    diagnosticOutput.Text = dbLine .. "\nPages fetched: " .. tostring(_G.__SUPREME_FETCHED_PAGES or 0)
        .. "\n" .. parseLine .. "\nFetch: " .. fetchMethodText
        .. "\nFailed pages: " .. tostring(_G.__SUPREME_FAILED_PAGES or "none")
        .. "\nMM2 icon mappings: " .. tostring(iconCount)
        .. "\nOpen inventory to test item prices; open a trade to test both totals."
    print(loaded and ("[Supreme Trade Text] Values loaded • " .. lastUpdate .. " • " .. tostring(valueCount) .. " items") or "[Supreme Trade Text] Could not load Supreme Values")
    while textGui.Parent and not stopped do
        pcall(update)
        task.wait(0.6)
    end
end)

task.spawn(function()
    while textGui.Parent and not stopped do
        task.wait(900)
        if textGui.Parent then
            refreshValues()
        end
    end
end)

textGui.Destroying:Connect(function()
    stopped = true
    restoreNativeText()
end)

print("[Supreme Trade Text] Loaded — native trade UI mode")
