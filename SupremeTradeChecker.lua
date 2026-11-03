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

local function updateInventory(trade)
    local inventoryItems, inventoryTotal = {}, 0
    local inventoryHeading
    local seen = {}

    local function isInsideTradeOffer(object)
        if not trade then return false end
        for _, anchor in ipairs({trade.yourAnchor, trade.theirAnchor}) do
            if anchor and object:FindFirstAncestorOfClass("ScreenGui") == anchor:FindFirstAncestorOfClass("ScreenGui") then
                local p = object.AbsolutePosition
                local a = anchor.AbsolutePosition
                local z = anchor.AbsoluteSize
                if p.Y >= a.Y - 8 and p.Y <= a.Y + z.Y + 245
                    and p.X >= a.X - 30 and p.X <= a.X + math.max(z.X, 150) + 240 then
                    return true
                end
            end
        end
        return false
    end

    for _, root in ipairs({playerGui, CoreGui}) do
        local ok, descendants = pcall(function() return root:GetDescendants() end)
        if ok then
            for _, object in ipairs(descendants) do
                if (object:IsA("TextLabel") or object:IsA("TextButton")) and object.Visible
                    and not isInsideTradeOffer(object) then
                    local raw = clean(originalText[object] or object.Text)
                    local normalized = key(raw)
                    if not inventoryHeading and (normalized == "inventory" or normalized == "weapons") then
                        inventoryHeading = object
                    end
                    if normalized ~= "" then
                        for _, itemKey in ipairs(valueNames) do
                            if normalized == itemKey or normalized:find(itemKey, 1, true) then
                                local data = values[itemKey]
                                local count = tonumber(raw:match("[xX]%s*(%d+)"))
                                    or tonumber(raw:match("(%d+)%s*[xX]")) or 1
                                local p = object.AbsolutePosition
                                local stamp = itemKey .. "@" .. math.floor(p.X/10) .. ":" .. math.floor(p.Y/10)
                                if not seen[stamp] then
                                    seen[stamp] = true
                                    local amount = (data.value or 0) * count
                                    inventoryTotal = inventoryTotal + amount
                                    table.insert(inventoryItems, {
                                        object = object, data = data, count = count,
                                        amount = amount, base = raw
                                    })
                                end
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    for _, item in ipairs(inventoryItems) do
        local base = originalText[item.object] or item.base
        local suffix = "  [" .. (item.data.value and fmt(item.amount) or "N/A") .. "]"
        base = base:gsub("%s+%[%s*[%d,]+%s*%]$", ""):gsub("%s+%[N/A%]$", "")
        rememberAndSet(item.object, base .. suffix)
    end

    if inventoryHeading then
        local base = originalText[inventoryHeading] or clean(inventoryHeading.Text)
        base = base:gsub("%s*[•|%-]%s*TOTAL:%s*[%d,]+", "")
        rememberAndSet(inventoryHeading, base .. "  |  INVENTORY TOTAL: " .. fmt(inventoryTotal))
    end
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
