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
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 100 then return body end
end
local function parsePage(html, out)
    html = html:gsub("<script[^>]*>.-</script>"," ")
    html = html:gsub("<style[^>]*>.-</style>"," ")
    html = html:gsub("<br%s*/?>"," "):gsub("</p>"," "):gsub("</div>"," ")
    html = clean(html)

    local parsedThisPage = false
    local function add(nameText, valueText)
        local name = clean(nameText)
        -- Ignore decorative "Image: Item Stability" text before the next item.
        local finalImageName = name:match(".*Image:%s*(.+)$")
        if finalImageName then name = finalImageName end
        name = name:gsub("^Image:%s*","")
        name = name:gsub("%s*|.*$","")
        name = name:gsub("%s+Contains%s*%-%s*.*$","")
        name = name:gsub("%s+Value%s*$","")

        local normalized = key(name)
        local rawValue = clean(valueText):gsub(",","")
        local number = tonumber(rawValue:match("^[%d%.%-]+") or "")
        if normalized ~= "" and number ~= nil
            and not normalized:find("item stability",1,true)
            and not normalized:find("image stability",1,true) then
            out[normalized] = {name=name, value=number, valueText=clean(valueText)}
            parsedThisPage = true
        end
    end

    -- Supreme's accessible card text repeats the name after the pipe;
    -- set cards append "Contains - ..." after that repeated name.
    for nameText, valueText in html:gmatch("Image:%s*(.-)%s*|%s*.-%s+Value%s*%-%s*([%d,%.]+)") do
        add(nameText, valueText)
    end

    -- Fallback for cards whose accessible text has no pipe separator.
    for nameText, valueText in html:gmatch("Image:%s*(.-)%s+Value%s*%-%s*([%d,%.]+)") do
        add(nameText, valueText)
    end

    -- Last-resort fallback for text-only layouts that omit the "Image:" prefix.
    if not parsedThisPage then
        for nameText, valueText in html:gmatch("|%s*(.-)%s+Value%s*%-%s*([%d,%.]+)") do
            add(nameText, valueText)
        end
    end
end

local function refreshValues()
    local fresh = {}
    for _,cat in ipairs(CATEGORIES) do
        if stopped then return end
        local html = get(BASE .. cat)
        if html then parsePage(html,fresh) end
        task.wait(0.12)
    end
    if next(fresh) then
        for itemKey, data in pairs(fresh) do
            values[itemKey] = data
        end
        valueNames = {}
        for itemKey in pairs(values) do table.insert(valueNames,itemKey) end
        table.sort(valueNames,function(a,b) return #a > #b end)
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
diagnosticPanel.Size = UDim2.new(0.92, 0, 0, 310)
diagnosticPanel.Position = UDim2.new(0.04, 0, 0.12, 0)
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
diagnosticTitle.TextSize = 13
diagnosticTitle.TextColor3 = Color3.fromRGB(120, 220, 255)
diagnosticTitle.TextXAlignment = Enum.TextXAlignment.Left
diagnosticTitle.Text = "SUPREME — STARTING"
diagnosticTitle.ZIndex = 201
diagnosticTitle.Parent = diagnosticPanel

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
diagnosticClose.Activated:Connect(function() diagnosticPanel.Visible = false end)

local diagnosticOutput = Instance.new("TextBox")
diagnosticOutput.Name = "DiagnosticText"
diagnosticOutput.Size = UDim2.new(1, -20, 1, -44)
diagnosticOutput.Position = UDim2.new(0, 10, 0, 38)
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
                    for _, card in ipairs(list:GetChildren()) do
                        if card:IsA("GuiObject") and card.Visible then
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

-- One-shot, compact inventory structure report. This deliberately inspects only
-- a few direct item cards, not the full 33k-object PlayerGui tree.
local function reportInventoryStructure()
    local lines = {"[Supreme Trade Text] INVENTORY DIAGNOSTIC (send this short block)"}
    local emitted = 0
    local function add(line)
        if emitted >= 48 then return end
        emitted = emitted + 1
        table.insert(lines, line)
    end

    for _, guiName in ipairs({"TradeGUI", "TradeGUI_Phone"}) do
        local gui = playerGui:FindFirstChild(guiName)
        if gui then
            add("GUI: " .. guiName)
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
                            add("  CARD: " .. card.Name .. " [" .. card.ClassName .. "]")
                            local detailCount = 0
                            for _, child in ipairs(card:GetDescendants()) do
                                if detailCount >= 10 then break end
                                local line
                                if child:IsA("TextLabel") or child:IsA("TextButton") then
                                    line = "   TEXT " .. child.Name .. "=" .. string.sub(clean(child.Text), 1, 90)
                                elseif child:IsA("StringValue") then
                                    line = "   VALUE " .. child.Name .. "=" .. string.sub(clean(child.Value), 1, 90)
                                elseif child:IsA("ImageLabel") or child:IsA("ImageButton") then
                                    line = "   IMAGE " .. child.Name .. "=" .. string.sub(tostring(child.Image), 1, 70)
                                end
                                if line then add(line); detailCount = detailCount + 1 end
                            end
                            local attrs = {}
                            pcall(function() attrs = card:GetAttributes() end)
                            for k, v in pairs(attrs) do
                                if detailCount >= 12 then break end
                                add("   ATTR " .. tostring(k) .. "=" .. string.sub(tostring(v), 1, 90))
                                detailCount = detailCount + 1
                            end
                        end
                    end
                end
                add("  visible direct cards=" .. tostring(cardCount))
            end
        end
    end
    add("END DIAGNOSTIC")
    local reportText = table.concat(lines, "\n")
    diagnosticTitle.Text = "INVENTORY DIAGNOSTIC"
    diagnosticOutput.Text = reportText
    pcall(function() diagnosticOutput.CursorPosition = 1 end)
    warn(reportText)
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
    local diagOk, diagErr = pcall(reportInventoryStructure)
    if not diagOk then
        diagnosticTitle.Text = "DIAGNOSTIC ERROR"
        diagnosticOutput.Text = "The inventory scan failed before completion:\\n" .. tostring(diagErr)
    end
    local loaded = refreshValues()
    print(loaded and ("[Supreme Trade Text] Values loaded • " .. lastUpdate) or "[Supreme Trade Text] Could not load Supreme Values")
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
