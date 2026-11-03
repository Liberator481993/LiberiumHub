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
local BASE = "https://www.supremevalues.com/mm2/"
local values, valueNames = {}, {}
local lastUpdate = "loading"
local stopped = false

local function clean(s)
    s = tostring(s or ""):gsub("<[^>]->"," "):gsub("&nbsp;"," ")
    s = s:gsub("&amp;","&"):gsub("&quot;",'"'):gsub("&#39;","'")
    return (s:gsub("[%c]"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$",""))
end
local function key(s)
    return string.lower(clean(s)):gsub("[%p%c]"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
end
local function get(url)
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" and #body > 100 then return body end
end
local function parsePage(html, out)
    html = html:gsub("<script[^>]*>.-</script>"," "):gsub("<style[^>]*>.-</style>"," ")
    html = html:gsub("<br%s*/?>","\n"):gsub("</p>","\n"):gsub("</div>","\n")
    html = clean(html)
    local function add(n,v)
        n = clean(n):gsub("^Image:%s*",""):gsub("^|%s*",""):gsub("%s*|.*$","")
        v = clean(v)
        local k = key(n)
        local number = tonumber((v:gsub(",",""):match("^[%d%.%-]+") or ""))
        if k ~= "" and v ~= "" and not k:find("image stability",1,true) then
            out[k] = {name=n, value=number, valueText=v}
        end
    end
    for n,v in html:gmatch("|%s*(.-)%s+Value%s*%-%s*(.-)%s+Range%s*%-") do add(n,v) end
    for n,v in html:gmatch("|%s*(.-)%s+Value%s*%-%s*(.-)%s+Stability%s*%-") do add(n,v) end
    if next(out) == nil then
        for n,v in html:gmatch("|%s*(.-)%s+Value%s*%-%s*([%d,%.]+)") do add(n,v) end
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
        values = fresh
        valueNames = {}
        for k in pairs(values) do table.insert(valueNames,k) end
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
pcall(function() textGui.Parent = CoreGui end)
if not textGui.Parent then textGui.Parent = playerGui end

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

local function scanTrade()
    local yourAnchor, theirAnchor
    for _, root in ipairs({playerGui, CoreGui}) do
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, object in ipairs(descendants) do
                if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Visible then
                    local t = string.lower(clean(object.Text))
                    if t == "your offer" or t:find("your offer", 1, true) then
                        yourAnchor = object
                    elseif t == "their offer" or t:find("their offer", 1, true) then
                        theirAnchor = object
                    end
                end
            end
        end
    end
    if not yourAnchor and not theirAnchor then return nil end

    local function collect(anchor)
        local found, total = {}, 0
        if not anchor then return found, total end
        local pos = anchor.AbsolutePosition
        local size = anchor.AbsoluteSize
        local top = pos.Y + size.Y
        local bottom = top + 230
        local left = pos.X - 20
        local right = pos.X + math.max(size.X, 150) + 220
        local sg = anchor:FindFirstAncestorOfClass("ScreenGui")
        if not sg then return found, total end

        local seen = {}
        for _, object in ipairs(sg:GetDescendants()) do
            if (object:IsA("TextLabel") or object:IsA("TextButton"))
                and object.Visible and object ~= anchor then
                local p = object.AbsolutePosition
                if p.X >= left and p.X <= right and p.Y >= top and p.Y <= bottom then
                    local raw = clean(object.Text)
                    local normalized = key(raw)
                    if normalized ~= "" then
                        for _, itemKey in ipairs(valueNames) do
                            if normalized == itemKey or normalized:find(itemKey, 1, true) then
                                local data = values[itemKey]
                                local count = tonumber(raw:match("[xX]%s*(%d+)")) or 1
                                local stamp = itemKey .. "@" .. math.floor(p.X/8) .. ":" .. math.floor(p.Y/8)
                                if not seen[stamp] then
                                    seen[stamp] = true
                                    table.insert(found, {
                                        object = object,
                                        key = itemKey,
                                        count = count,
                                        data = data,
                                        base = raw
                                    })
                                    total = total + (data.value or 0) * count
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
        return found, total
    end

    local yours, yourTotal = collect(yourAnchor)
    local theirs, theirTotal = collect(theirAnchor)
    return {
        yourAnchor = yourAnchor,
        theirAnchor = theirAnchor,
        yours = yours,
        theirs = theirs,
        yourTotal = yourTotal,
        theirTotal = theirTotal
    }
end

local function annotateSide(anchor, items, total, sideName)
    if not anchor then return end
    local totalText = sideName .. " • TOTAL: " .. fmt(total)
    rememberAndSet(anchor, clean(originalText[anchor] or anchor.Text):gsub("%s*[•|%-]%s*TOTAL:%s*[%d,]+", "") .. "  |  " .. totalText)

    for _, item in ipairs(items) do
        local object = item.object
        local base = originalText[object] or item.base
        local amount = item.data.value and fmt(item.data.value * item.count) or "N/A"
        local suffix = "  [" .. amount .. "]"
        rememberAndSet(object, base:gsub("%s+%[%s*[%d,]+%s*%]$", ""):gsub("%s+%[N/A%]$", "") .. suffix)
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
        local count = tonumber(countText:match("[xX]%s*(%d+)"))
            or tonumber(countText:match("(%d+)%s*[xX]")) or 1
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
        or playerGui:FindFirstChild("TradeGUI_Phone")
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
    if next(foundCards) == nil then
        for _, root in ipairs({playerGui, CoreGui}) do
            local ok, descendants = pcall(function() return root:GetDescendants() end)
            if ok then
                for _, object in ipairs(descendants) do
                    if object:IsA("ScrollingFrame") and object.Visible
                        and (object.Name == "Weapons" or object.Name == "Pets")
                        and object:FindFirstAncestor("TradeGUI") then
                        for _, card in ipairs(object:GetChildren()) do
                            if card:IsA("GuiObject") and card.Visible then addCard(card) end
                        end
                    end
                end
            end
        end
    end

    for card, item in pairs(foundCards) do
        local amount = (item.data.value or 0) * item.count
        inventoryTotal = inventoryTotal + amount
        local amountText = item.data.value and fmt(amount) or "N/A"

        if item.textObject then
            local base = originalText[item.textObject] or clean(item.textObject.Text)
            base = base:gsub("%s+%[%s*[%d,]+%s*%]$", ""):gsub("%s+%[N/A%]$", "")
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
    warn(table.concat(lines, "\\n"))
end

local function update()
    activeText = setmetatable({}, {__mode = "k"})
    local trade = scanTrade()
    if trade then
        annotateSide(trade.yourAnchor, trade.yours, trade.yourTotal, "YOUR")
        annotateSide(trade.theirAnchor, trade.theirs, trade.theirTotal, "THEIR")
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
    local loaded = refreshValues()
    task.wait(1.5)
    pcall(reportInventoryStructure)
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
