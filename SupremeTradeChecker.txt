-- BOOT DIAGNOSTICS: independent of the main checker UI.
local __bootGui, __bootFrame, __bootText
local function __bootStage(message, detail)
    pcall(function()
        if not __bootText then return end
        __bootText.Text = tostring(message or "Starting...") .. (detail and ("\n\n" .. tostring(detail)) or "")
    end)
end
local function __bootFailure(err)
    pcall(function()
        if not __bootGui then return end
        __bootGui.Enabled = true
        if __bootFrame then
            __bootFrame.Size = UDim2.new(0, 310, 0, 210)
            __bootFrame.Position = UDim2.new(0.5, -155, 0.5, -105)
        end
        __bootStage("BOOT FAILED — SEND THIS REPORT", tostring(err):sub(1, 1800))
    end)
end
pcall(function()
    local sg = Instance.new("ScreenGui")
    sg.Name = "SupremeBootDiagnostics"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    sg.DisplayOrder = 100000
    local parent
    pcall(function() parent = game:GetService("CoreGui") end)
    if parent then
        local ok = pcall(function() sg.Parent = parent end)
        if not ok then parent = nil end
    end
    if not parent then
        local p = game:GetService("Players").LocalPlayer
        parent = p and p:FindFirstChildOfClass("PlayerGui")
        if not parent and p then
            pcall(function() parent = p:WaitForChild("PlayerGui", 5) end)
        end
    end
    if not parent then error("Cannot access CoreGui or PlayerGui") end
    sg.Parent = parent
    __bootGui = sg
    local frame = Instance.new("Frame")
    frame.Name = "BootPanel"
    frame.Size = UDim2.new(0, 270, 0, 92)
    frame.Position = UDim2.new(0.5, -135, 0.5, -46)
    frame.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
    frame.BorderSizePixel = 0
    frame.Parent = sg
    __bootFrame = frame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(115, 74, 91)
    stroke.Transparency = 0.15
    stroke.Parent = frame
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -22, 1, -18)
    label.Position = UDim2.fromOffset(11, 9)
    label.BackgroundTransparency = 1
    label.Font = Enum.Font.RobotoMono
    label.TextSize = 12
    label.TextColor3 = Color3.fromRGB(235, 237, 243)
    label.TextWrapped = true
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.Text = "SUPREME CHECKER\\nBOOT 00/06 — INITIALIZING"
    label.Parent = frame
    __bootText = label
end)

local function __runSupremeChecker()
__bootStage("BOOT 01/06 — LUA STARTED", "Loading Roblox services...")
-- MM2 Supreme Trade Checker
-- Inventory and trade value overlay adapted from the proven PulseHub MM2 reader.
-- Informational only: never accepts, declines, sends, or modifies trades.
-- Value source: https://www.supremevalues.com/mm2/

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")

local player = Players.LocalPlayer
__bootStage("BOOT 02/06 — PLAYER FOUND", "Waiting for PlayerGui...")
local playerGui = player:WaitForChild("PlayerGui", 15)
if not playerGui then error("PlayerGui did not appear within 15 seconds") end
__bootStage("BOOT 03/06 — PLAYERGUI READY", "Preparing values and UI modules...")

-- Every category linked from the current Supreme Values MM2 menu.
-- Only VALUE_CATEGORIES are individual tradable-item value sources.
-- Sets are aggregate values; Evos and Untradables are reference-only pages.
local CATEGORIES = {
    "sets", "uniques", "evos", "ancients", "vintages", "chromas",
    "godlies", "legendaries", "rares", "uncommons", "commons",
    "pets", "misc", "untradables"
}
local VALUE_CATEGORIES = {
    uniques = true,
    ancients = true, vintages = true, chromas = true, godlies = true,
    legendaries = true, rares = true, uncommons = true, commons = true,
    pets = true, misc = true
}
local MINIMUM = {
    godlies = 80, chromas = 30, commons = 150, uncommons = 100,
    rares = 80, legendaries = 40, ancients = 8, pets = 40, uniques = 1
}
local RARITIES = {
    godlies = "Godly", ancients = "Ancient", legendaries = "Legendary",
    rares = "Rare", uncommons = "Uncommon", commons = "Common",
    vintages = "Classic", uniques = "Unique"
}
local BASE = "https://www.supremevalues.com/mm2/"

local state = {
    status = "loading",
    selfTestStatus = "pending",
    cacheStatus = "not checked",
    mapped = nil,
    updated = 0,
    loadDuration = 0,
    lastUpdate = "Not loaded",
    source = "",
    pageCount = 0,
    parsedPages = 0,
    entryCount = 0,
    failedPages = {},
    fetchMethods = {},
    dbItems = 0,
    dbPets = 0,
    mappedCount = 0,
    tierEntryCount = 0,
    categoryCardCounts = {},
    referenceValueCounts = {},
    iconCount = 0,
    inventoryModuleStatus = "not checked",
    inventoryModule = nil,
    inventoryModuleRetryAt = 0,
    inventoryFrames = 0,
    inventoryVisibleFrames = 0,
    inventoryGuiFrames = 0,
    inventoryGuiValued = 0,
    inventoryGuiItems = 0,
    inventoryDataEntries = 0,
    inventoryMissingFrames = 0,
    inventoryGroups = 0,
    inventoryGuiPath = "unknown",
    inventoryScreenList = "not scanned",
    inventoryFrameParents = "not scanned",
    inventoryGuiStructure = "not scanned",
    busy = false,
    latestTrade = "No active trade detected.",
    latestInventory = "Inventory not scanned yet.",
    unmatchedInventory = {},
    unmatchedTrade = {},
    coverageInventory = {},
    coverageTrade = {},
    coverageSeenInventory = {},
    coverageSeenTrade = {}
}
local stopped = false
local coreTestsPassed = false
local tileCache = setmetatable({}, {__mode = "k"})

local function clean(value)
    return tostring(value or ""):gsub("[%c]", " "):gsub("%s+", " ")
        :gsub("^%s+", ""):gsub("%s+$", "")
end

local function decodeText(value)
    local text = tostring(value or "")
    local function codepoint(number, base)
        local code = tonumber(number, base)
        if not code or code >= 1114112 or (code >= 55296 and code <= 57343) then
            return ""
        end
        return utf8.char(code)
    end
    text = text:gsub("<[^>]+>", " ")
        :gsub("&#(%d+);", function(number) return codepoint(number, 10) end)
        :gsub("&#[xX](%x+);", function(number) return codepoint(number, 16) end)
        :gsub("&amp;", "&"):gsub("&quot;", '"')
        :gsub("&apos;", "'"):gsub("&#39;", "'"):gsub("&#x27;", "'")
        :gsub("&nbsp;", " "):gsub("&lt;", "<"):gsub("&gt;", ">")
    return clean(text)
end

local function normalize(value)
    return string.lower(tostring(value or "")):gsub("[^%w]", "")
end

-- Supreme Values contains fractional values for many low-tier items.
-- Keep up to four decimals instead of rounding each item to a whole number.
local function formatValue(value)
    local number = tonumber(value) or 0
    local formatted = string.format("%.4f", number)
        :gsub("0+$", "")
        :gsub("%.$", "")
    if formatted == "-0" or formatted == "" then return "0" end

    local integer, fraction = formatted:match("^(%-?%d+)(%.%d+)$")
    if not integer then integer = formatted end
    local sign = ""
    if integer:sub(1, 1) == "-" then
        sign = "-"
        integer = integer:sub(2)
    end
    integer = integer:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return sign .. integer .. (fraction or "")
end

local function assetId(value)
    local result
    for match in tostring(value or ""):gmatch("%d%d%d%d%d+") do
        result = match
    end
    return result
end

local function fetchPage(url)
    local errors = {}
    local function attempt(fn, label)
        if type(fn) ~= "function" then return nil end
        local ok, response = pcall(fn, {
            Url = url,
            Method = "GET",
            Headers = {
                ["User-Agent"] = "Mozilla/5.0",
                ["Accept"] = "text/html,application/xhtml+xml"
            }
        })
        if not ok then
            table.insert(errors, label .. ": error")
            return nil
        end

        local statusCode
        if type(response) == "table" then
            statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
            response = response.Body or response.body or response.ResponseBody
        end
        if type(response) == "string" and #response > 5000
            and response:find("itemcolumn", 1, true)
            and (not statusCode or (statusCode >= 200 and statusCode < 300)) then
            return response, label
        end
        table.insert(errors, label .. ": invalid/empty page")
        return nil
    end

    local body, method = attempt(request, "request")
    if body then return body, method end

    body, method = attempt(http_request, "http_request")
    if body then return body, method end

    local synRequest = type(syn) == "table" and syn.request or nil
    body, method = attempt(synRequest, "syn.request")
    if body then return body, method end

    local httpRequest = type(http) == "table" and http.request or nil
    body, method = attempt(httpRequest, "http.request")
    if body then return body, method end

    local ok, gameBody = pcall(function()
        return game:HttpGet(url)
    end)
    if ok and type(gameBody) == "string" and #gameBody > 5000
        and gameBody:find("itemcolumn", 1, true) then
        return gameBody, "game:HttpGet"
    end
    table.insert(errors, "game:HttpGet: invalid/empty page")
    return nil, table.concat(errors, "; ")
end

-- Supreme Values item cards expose numeric or tier-based values as visible text.
-- Parse the displayed value first; data-value is only a numeric fallback.
local function parseNumberText(raw)
    if raw == nil then return nil end
    local normalized = tostring(raw):gsub("[,%s]", "")
    if normalized == "" or not normalized:match("^%d+%.?%d*$") then
        return nil
    end
    return tonumber(normalized)
end

-- Supreme Values displays values with grouping commas (for example 4,600).
-- Remove those separators before tonumber so a value can never be truncated
-- to the first digit group.
local function parseDisplayedValue(text)
    local raw = tostring(text or ""):match("Value%s*%-%s*([%d][%d,%.%s]*)")
    return parseNumberText(raw)
end

local function parseCategory(category, html, output)
    local count, tierCount, cursor, scanned = 0, 0, 1, 0
    while true do
        local first = html:find('<div class="itemcolumn"', cursor, true)
        if not first then break end
        local nextItem = html:find('<div class="itemcolumn"', first + 23, true)
        local card = html:sub(first, (nextItem or (#html + 1)) - 1)
        cursor = nextItem or (#html + 1)
        scanned = scanned + 1
        if scanned % 60 == 0 then task.wait() end

        local cardText = decodeText(card)
        -- Tier values are labels, not numeric prices. Do not interpret their
        -- tier multiplier as a normal value.
        local tierText = cardText:match("Value%s*%-%s*([x×]%s*[%d,%.]+%s+T%d+%s+[%a]+)")
        local amount = not tierText and parseDisplayedValue(cardText) or nil
        if not amount and not tierText then
            local dataValue = card:match('data%-value="([^"]+)"')
                or card:match("data%-value='([^']+)'")
            local dataAmount = parseNumberText(dataValue)
            if dataAmount and dataAmount > 0 then amount = dataAmount end
        end

        local nameMarkup = card:match('<div[^>]-class="[^"]*itemhead[^"]*"[^>]*>(.-)</div>')
            or card:match("<div[^>]-class='[^']*itemhead[^']*'[^>]*>(.-)</div>")
        local originMarkup = card:match('<[^>]-class="[^"]*itemorigin[^"]*"[^>]*>(.-)</[^>]+>')
            or card:match("<[^>]-class='[^']*itemorigin[^']*'[^>]*>(.-)</[^>]+>")
        local origin = decodeText(originMarkup or "")
        local imageAlt = card:match('<img[^>]-alt="([^"]*)"')
            or card:match("<img[^>]-alt='([^']*)'")
        imageAlt = decodeText(imageAlt or "")
        local pageEvent = card:match('data%-event="([^"]+)"')
            or card:match("data%-event='([^']+)'")
        local classMarkup = card:match("Class%s*%-%s*<b>(.-)</b>")
            or card:match('data%-class="([^"]+)"')
            or card:match("data%-class='([^']+)'")
        local year = card:match('data%-year="(%d%d%d%d)')
            or card:match("data%-year='(%d%d%d%d)")

        if (amount or tierText) and (not amount or amount < 500000)
            and nameMarkup and not string.find(string.lower(origin), "deletion", 1, true) then
            local name = decodeText(nameMarkup)
            if name ~= "" then
                table.insert(output, {
                    c = category,
                    n = name,
                    im = imageAlt,
                    v = amount,
                    t = tierText,
                    y = year,
                    e = pageEvent,
                    o = origin ~= "" and origin or nil,
                    cl = classMarkup and decodeText(classMarkup) or nil,
                    dm = card:match('data%-demand="(%d+)"')
                        or card:match("data%-demand='(%d+)'")
                })
                count = count + 1
                if tierText then tierCount = tierCount + 1 end
            end
        end
    end
    return count, tierCount
end
-- Count every visible item card on a page, including reference-only cards
-- that intentionally have no tradable value (Evos and Untradables).
local function countItemCards(html)
    local count, cursor = 0, 1
    while true do
        local first = html:find('<div class="itemcolumn"', cursor, true)
        if not first then break end
        count = count + 1
        cursor = first + 23
    end
    return count
end

local function loadGameDatabase()
    local databaseFolder = ReplicatedStorage:FindFirstChild("Database")
    local module = databaseFolder and databaseFolder:FindFirstChild("Sync")
    if not module and databaseFolder then
        for _, child in ipairs(databaseFolder:GetDescendants()) do
            if child:IsA("ModuleScript") and child.Name == "Sync" then
                module = child
                break
            end
        end
    end
    if not module then
        return nil, "ReplicatedStorage.Database.Sync not found"
    end
    local ok, data = pcall(require, module)
    if not ok or type(data) ~= "table" then
        return nil, "Database.Sync require failed: " .. tostring(data)
    end
    if type(data.Item) ~= "table" then
        return nil, "Database.Sync has no Item table"
    end
    return data, "ReplicatedStorage.Database.Sync"
end

-- Cache parsed Supreme entries locally so temporary site/network failures do
-- not leave the overlay without prices. Cache is data-only and expires in 7 days.
local VALUES_CACHE_FILE = "SupremeTradeChecker_values.json"
local VALUES_CACHE_TTL = 604800

local function readValuesCache()
    if type(readfile) ~= "function" then return nil end
    if type(isfile) == "function" then
        local ok, exists = pcall(isfile, VALUES_CACHE_FILE)
        if not ok or not exists then return nil end
    end
    local ok, raw = pcall(readfile, VALUES_CACHE_FILE)
    if not ok or type(raw) ~= "string" or raw == "" then return nil end
    local decodedOk, decoded = pcall(function()
        return HttpService:JSONDecode(raw)
    end)
    if not decodedOk or type(decoded) ~= "table" or type(decoded.items) ~= "table" then
        return nil
    end
    local timestamp = tonumber(decoded.t)
    if not timestamp or os.time() - timestamp > VALUES_CACHE_TTL or timestamp > os.time() + 300 then
        return nil
    end
    if #decoded.items < 300 then return nil end
    return decoded
end

local function writeValuesCache(entries)
    if type(writefile) ~= "function" or type(entries) ~= "table" or #entries < 300 then
        return false
    end
    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({v = 1, t = os.time(), items = entries})
    end)
    if not ok or type(encoded) ~= "string" then return false end
    local saved = pcall(writefile, VALUES_CACHE_FILE, encoded)
    return saved
end


local function buildMapping(entries, database)
    if type(database) ~= "table" or type(database.Item) ~= "table" then
        return nil, "invalid MM2 item database"
    end

    local weapons = database.Item
    local pets = type(database.Pets) == "table" and database.Pets or {}
    local index, petEntries = {}, {}
    local dbByName, dbByImage = {}, {}

    local function addDiagnosticCandidate(item, id, kind)
        local name = normalize(item.ItemName or item.Name or "")
        if name ~= "" then
            dbByName[name] = dbByName[name] or {}
            table.insert(dbByName[name], {
                id = tostring(id),
                kind = kind,
                name = tostring(item.ItemName or item.Name or ""),
                itemType = tostring(item.ItemType or ""),
                rarity = tostring(item.Rarity or ""),
                chroma = item.Chroma == true,
                year = tostring(item.Year or ""),
                event = tostring(item.Event or ""),
                image = assetId(item.Image) or "",
                itemId = tostring(item.ItemID or "")
            })
        end
        local image = assetId(item.Image)
        if image then
            dbByImage[image] = dbByImage[image] or {}
            table.insert(dbByImage[image], {
                id = tostring(id),
                kind = kind,
                name = tostring(item.ItemName or item.Name or ""),
                itemType = tostring(item.ItemType or ""),
                rarity = tostring(item.Rarity or ""),
                chroma = item.Chroma == true,
                year = tostring(item.Year or ""),
                event = tostring(item.Event or "")
            })
        end
    end

    local function addIndex(name, entry)
        if name == "" then return end
        index[name] = index[name] or {}
        table.insert(index[name], entry)
    end

    for id, item in pairs(weapons) do
        if type(item) ~= "table" then continue end
        local name = tostring(item.ItemName or item.Name or "")
        local entry = {kind = "i", id = tostring(id), item = item}
        addDiagnosticCandidate(item, id, "Item")
        addIndex(normalize(name), entry)
        local withoutYear = name:gsub("%s*%d%d%d%d%s*$", "")
        if withoutYear ~= name then addIndex(normalize(withoutYear), entry) end
    end

    for id, item in pairs(pets) do
        if type(item) ~= "table" then continue end
        local entry = {kind = "p", id = tostring(id), item = item}
        addDiagnosticCandidate(item, id, "Pet")
        addIndex("pet:" .. normalize(item.Name), entry)
        table.insert(petEntries, entry)
    end

    local byKey, mappedCount = {}, 0
    for entryIndex, value in ipairs(entries) do
        if entryIndex % 150 == 0 then task.wait() end
        local category, amount = value.c, tonumber(value.v)
        local tierText = clean(value.t)
        if type(category) ~= "string" or (not amount and tierText == "") then continue end

        -- Parse both the value title and image label; the image label often
        -- carries the exact weapon type/year while the value title is generic.
        local function splitVariant(raw)
            local text = clean(raw):gsub("%s*%[[^%]]*%]%s*$", "")
            local year
            local base, suffix = text:match("^(.-)%s*%((%d%d%d%d)%)%s*$")
            if base then text, year = clean(base), suffix end

            local kind
            base, suffix = text:match("^(.-)%s*%((%a+)%)%s*$")
            if base and (suffix == "Knife" or suffix == "Gun") then
                text, kind = clean(base), suffix
            else
                base, suffix = text:match("^(.-)%s+(%a+)$")
                if base and (suffix == "Knife" or suffix == "Gun") then
                    text, kind = clean(base), suffix
                end
            end
            return text, kind, year
        end

        local name, kind, titleYear = splitVariant(value.n)
        local year = value.y or titleYear
        if value.y and titleYear and tostring(value.y) ~= tostring(titleYear) then
            continue
        end
        if not year and value.o then year = tostring(value.o):match("(20%d%d)") end

        local _, altKind, altYear = splitVariant(value.im)
        if altKind then
            if kind and kind ~= altKind then continue end
            kind = altKind
        end
        if altYear then
            if year and tostring(year) ~= tostring(altYear) then continue end
            year = altYear
        end

        local event = clean(value.e)
        if event == "" and value.o then
            event = clean(tostring(value.o):match("^(.-)%s+20%d%d") or "")
        end

        local chroma = category == "chromas"
        if chroma then
            name = name:gsub("^Chroma%s+", ""):gsub("^C%.%s+", "")
        end

        local aliases = {name}
        -- Supreme titles can split the weapon suffix from the base name:
        -- "Swirly Gun" becomes name="Swirly", kind="Gun". Database.Sync may
        -- store ItemName with or without that suffix, so test both exact forms.
        if kind then
            table.insert(aliases, name .. " " .. kind)
            table.insert(aliases, name .. " (" .. kind .. ")")
        end
        local wrapping = name:match("^(%a+) Papers$")
        if wrapping then table.insert(aliases, "Box of " .. wrapping .. " Wrapping Paper") end
        if name == "Ultra Wrap" then table.insert(aliases, "Box of Ultra Wrapping Paper") end
        if name:sub(-1) == "s" then table.insert(aliases, name:sub(1, -2)) end
        -- Do not strip the first word from legendary names: that can
        -- collide with a different weapon and assign its value incorrectly.

        local matches = {}
        for _, alias in ipairs(aliases) do
            local prefix = category == "pets" and "pet:" or ""
            local candidates = index[prefix .. normalize(alias)] or {}
            for _, candidate in ipairs(candidates) do
                local item = candidate.item
                local eligible = false
                if candidate.kind == "p" then
                    eligible = (item.Chroma == true) == chroma
                        and (category == "pets" or category == "chromas")
                elseif category ~= "pets" then
                    if category == "misc" then
                        eligible = item.ItemType == "Misc"
                            or item.Rarity == "Christmas" or item.Rarity == "Halloween"
                    elseif chroma then
                        eligible = item.Chroma == true
                    else
                        eligible = item.Chroma ~= true and item.Rarity == RARITIES[category]
                    end
                end
                if eligible then table.insert(matches, candidate) end
            end
            if #matches > 0 then break end
        end

        if category == "pets" and year then
            local correct = {}
            for _, candidate in ipairs(matches) do
                if tostring(candidate.item.Year or "") == tostring(year) then
                    table.insert(correct, candidate)
                end
            end
            if #correct == 0 then
                local prefix = normalize(name)
                for _, candidate in ipairs(petEntries) do
                    if normalize(candidate.id):sub(1, #prefix) == prefix
                        and tostring(candidate.item.Year or "") == tostring(year)
                        and not candidate.item.Chroma then
                        table.insert(correct, candidate)
                    end
                end
            end
            if #correct > 0 then matches = correct end
        end

        local function filterMatches(predicate)
            local filtered = {}
            for _, candidate in ipairs(matches) do
                if predicate(candidate.item) then table.insert(filtered, candidate) end
            end
            -- A supplied discriminator that does not match must reject the
            -- candidate set; never silently fall back to a different skin.
            matches = filtered
        end

        if kind then filterMatches(function(item) return item.ItemType == kind end) end
        if value.cl then
            filterMatches(function(item)
                return normalize(item.Rarity) == normalize(value.cl)
            end)
        end

        local function preferExactMetadata(field, wanted)
            if not wanted or clean(wanted) == "" then return end
            local exact, unknown = {}, {}
            for _, candidate in ipairs(matches) do
                local actual = clean(candidate.item[field])
                if actual == "" then
                    table.insert(unknown, candidate)
                elseif normalize(actual) == normalize(wanted) then
                    table.insert(exact, candidate)
                end
            end
            if #exact > 0 then
                matches = exact
            else
                matches = unknown
            end
        end
        preferExactMetadata("Year", year)
        preferExactMetadata("Event", event)

        -- Never fan one Supreme value out to several MM2 records. Ambiguous
        -- names remain unvalued until metadata makes the match unique.
        if #matches == 1 then
            local candidate = matches[1]
            local idKey = candidate.kind .. ":" .. candidate.id
            if not byKey[idKey] then
                mappedCount = mappedCount + 1
                byKey[idKey] = {
                    v = amount,
                    t = tierText ~= "" and tierText or nil,
                    n = 1,
                    name = name,
                    category = category
                }
            end
        end
    end

    local icon, iconCandidates, chromaOf, byName, isChromaKey = {}, {}, {}, {}, {}
    local function addIcon(item, idKey)
        local image = assetId(item.Image)
        if image then
            iconCandidates[image] = iconCandidates[image] or {}
            table.insert(iconCandidates[image], idKey)
        end
    end

    for id, item in pairs(weapons) do
        if type(item) == "table" then addIcon(item, "i:" .. tostring(id)) end
    end
    for id, item in pairs(weapons) do
        if type(item) == "table" and not item.Chroma and item.ItemID then
            local imageId = tostring(item.ItemID)
            iconCandidates[imageId] = iconCandidates[imageId] or {}
            table.insert(iconCandidates[imageId], "i:" .. tostring(id))
        end
    end
    for id, item in pairs(pets) do
        if type(item) == "table" then addIcon(item, "p:" .. tostring(id)) end
    end
    -- Only unique asset IDs are safe for icon-based identification.
    for image, candidates in pairs(iconCandidates) do
        local unique = {}
        for _, idKey in ipairs(candidates) do
            if not unique[idKey] then unique[idKey] = true end
        end
        local onlyKey, count = nil, 0
        for idKey in pairs(unique) do
            onlyKey, count = idKey, count + 1
        end
        if count == 1 then icon[image] = onlyKey end
    end

    for _, group in ipairs({
        {kind = "i", items = weapons, field = "ItemName"},
        {kind = "p", items = pets, field = "Name"}
    }) do
        local regular = {}
        for id, item in pairs(group.items) do
            if type(item) == "table" then
                local idKey = group.kind .. ":" .. tostring(id)
                isChromaKey[idKey] = item.Chroma == true
                if not item.Chroma then
                    local regularKey = normalize(item[group.field])
                        .. (group.kind == "i" and "|" .. tostring(item.ItemType) or "")
                    if not regular[regularKey] then
                        regular[regularKey] = idKey
                    end
                end
            end
        end

        for id, item in pairs(group.items) do
            if type(item) ~= "table" then continue end
            local idKey = group.kind .. ":" .. tostring(id)
            local nameKey = normalize(item[group.field])
            if item.Chroma then
                local regularKey = nameKey
                    .. (group.kind == "i" and "|" .. tostring(item.ItemType) or "")
                local base = regular[regularKey]
                if base then chromaOf[base] = idKey end
            end
            if byKey[idKey] then
                byName[nameKey] = byName[nameKey] or {}
                table.insert(byName[nameKey], {key = idKey, chroma = item.Chroma == true})
            end
        end
    end

    local iconCount = 0
    for _ in pairs(icon) do iconCount = iconCount + 1 end
    return {
        byKey = byKey,
        icon = icon,
        chromaOf = chromaOf,
        dbByName = dbByName,
        dbByImage = dbByImage,
        byName = byName,
        isChromaKey = isChromaKey,
        n = mappedCount,
        iconCount = iconCount,
        dbItems = (function() local n = 0; for _ in pairs(weapons) do n = n + 1 end; return n end)(),
        dbPets = (function() local n = 0; for _ in pairs(pets) do n = n + 1 end; return n end)()
    }
end

local function valueOf(tile, name)
    local mapped = state.mapped
    if not mapped then return nil end

    local tags = tile and tile:FindFirstChild("Tags")
    local chromaTag = tags and tags:FindFirstChild("Chroma")
    local chroma = chromaTag ~= nil and chromaTag.Visible == true

    -- A globally unique database icon is the strongest identifier. Resolve it
    -- before the visible name because seasonal skins often share one label.
    local container = tile and tile:FindFirstChild("Container")
    local iconObject = container and container:FindFirstChild("Icon")
    local imageId = iconObject and assetId(iconObject.Image)
    local iconKey = imageId and mapped.icon[imageId]
    if iconKey then
        -- Never fall back to the regular weapon's price when a Chroma tile
        -- has no mapped Chroma counterpart.
        if chroma and not mapped.isChromaKey[iconKey] then
            iconKey = mapped.chromaOf[iconKey]
            if not iconKey then return nil end
        end
        local entry = mapped.byKey[iconKey]
        -- The icon identifies the exact MM2 record. Do not fall through to a
        -- different same-name item when Supreme has no value for this record.
        if entry then return entry.v, entry.name, entry.t, entry.category end
        return nil
    end

    -- Use a name only when it identifies exactly one database record after
    -- applying the visible Chroma state. A unique mapped-name candidate alone
    -- is insufficient: other same-name skins may simply be unmapped.
    local normalizedName = normalize(name)
    if normalizedName ~= "" then
        local databaseMatches = {}
        for _, candidate in ipairs(mapped.dbByName[normalizedName] or {}) do
            if candidate.chroma == chroma then
                table.insert(databaseMatches, candidate)
            end
        end
        if #databaseMatches == 1 then
            local candidate = databaseMatches[1]
            local key = (candidate.kind == "Pet" and "p:" or "i:") .. candidate.id
            local entry = mapped.byKey[key]
            if entry then return entry.v, entry.name, entry.t, entry.category end
        end
    end
    return nil
end

local function recordCoverage(tile, name, quantity, group, value, tierText, resolvedName)
    local isTrade = group == "trade"
    local seen = isTrade and state.coverageSeenTrade or state.coverageSeenInventory
    if tile and seen[tile] then return end
    if tile then seen[tile] = true end
    local target = isTrade and state.coverageTrade or state.coverageInventory
    local displayName = clean(resolvedName or name)
    if displayName == "" then displayName = "UNKNOWN ITEM" end
    local container = tile and tile:FindFirstChild("Container")
    local iconObject = container and container:FindFirstChild("Icon")
    local imageId = iconObject and assetId(iconObject.Image) or "no-icon"
    local tags = tile and tile:FindFirstChild("Tags")
    local chromaTag = tags and tags:FindFirstChild("Chroma")
    local chroma = chromaTag ~= nil and chromaTag.Visible == true
    local status, detail
    if isTrackedValue(value) then
        status, detail = "VALUED", formatValue(value)
    elseif tierText and tostring(tierText) ~= "" then
        status, detail = "TIER", tostring(tierText)
    elseif tonumber(value) then
        status, detail = "BELOW_MIN", formatValue(value)
    else
        status, detail = "NO_VALUE", "not mapped"
    end
    local key = normalize(displayName) .. "|" .. tostring(imageId) .. "|"
        .. tostring(chroma) .. "|" .. status .. "|" .. tostring(detail)
    local entry = target[key]
    if not entry then
        entry = {name = displayName, image = tostring(imageId), chroma = chroma,
            status = status, detail = detail, count = 0}
        target[key] = entry
    end
    entry.count = entry.count + math.max(1, tonumber(quantity) or 1)
end

local function loadValues(force)
    if state.busy then return end
    if not force and state.status == "ok" and os.clock() - state.updated < 900 then return end
    state.busy = true
    state.status = "loading"
    task.spawn(function()
        local loadStarted = os.clock()
        local ok, err = pcall(function()
            local entries = {}
            local pageCount, parsedPages, entryCount, tierEntryCount = 0, 0, 0, 0
            local failed, methods = {}, {}
            local categoryCounts, referenceValueCounts, categoryCardCounts = {}, {}, {}

            -- Four concurrent workers reduce the sequential network wait without
            -- flooding the executor with all 14 requests at once.
            local fetched = {}
            local nextIndex = 1
            for worker = 1, 4 do
                task.spawn(function()
                    while not stopped do
                        local index = nextIndex
                        nextIndex = nextIndex + 1
                        local category = CATEGORIES[index]
                        if not category then break end
                        local ok, html, fetchInfo = pcall(fetchPage, BASE .. category)
                        if not ok then
                            fetched[index] = {html = nil, info = "request worker error: " .. tostring(html)}
                        else
                            fetched[index] = {html = html, info = fetchInfo}
                        end
                    end
                end)
            end
            while not stopped do
                local complete = true
                for index = 1, #CATEGORIES do
                    if fetched[index] == nil then complete = false break end
                end
                if complete then break end
                task.wait(0.05)
            end

            for index, category in ipairs(CATEGORIES) do
                if stopped then return end
                local result = fetched[index]
                local html, fetchInfo = result and result.html, result and result.info
                if not html then
                    table.insert(failed, category .. ": " .. tostring(fetchInfo or "request cancelled"))
                else
                    pageCount = pageCount + 1
                    methods[fetchInfo] = (methods[fetchInfo] or 0) + 1
                    local pageEntries = {}
                    local count, tierCount = parseCategory(category, html, pageEntries)
                    local cardCount = countItemCards(html)
                    categoryCardCounts[category] = cardCount
                    if cardCount > 0 then parsedPages = parsedPages + 1 end
                    if VALUE_CATEGORIES[category] then
                        categoryCounts[category] = count
                        for _, entry in ipairs(pageEntries) do table.insert(entries, entry) end
                        entryCount = entryCount + count
                        tierEntryCount = tierEntryCount + (tierCount or 0)
                        local minimum = MINIMUM[category] or 1
                        if count < minimum then
                            table.insert(failed, category .. ": only " .. tostring(count)
                                .. " value cards parsed (expected at least " .. tostring(minimum) .. ")")
                        end
                    else
                        referenceValueCounts[category] = count
                        if cardCount < 1 then
                            table.insert(failed, category .. ": no reference cards detected")
                        end
                    end
                end
            end

            state.pageCount = pageCount
            state.parsedPages = parsedPages
            state.entryCount = entryCount
            state.tierEntryCount = tierEntryCount
            state.failedPages = failed
            state.fetchMethods = methods
            state.categoryCounts = categoryCounts
            state.referenceValueCounts = referenceValueCounts
            state.categoryCardCounts = categoryCardCounts

            local cacheUsed = false
            if #failed > 0 or pageCount ~= #CATEGORIES then
                local cached = readValuesCache()
                if cached then
                    entries = cached.items
                    cacheUsed = true
                    state.cacheStatus = "using local cache (" .. os.date("%Y-%m-%d", tonumber(cached.t)) .. ")"
                else
                    state.cacheStatus = "unavailable"
                    error("Supreme pages incomplete and no valid local cache; refusing partial values")
                end
            end

            local database, dbSource = loadGameDatabase()
            if not database then error(dbSource) end
            local mapping, mapError = buildMapping(entries, database)
            if not mapping then error(mapError or "value mapping failed") end
            if mapping.n < 300 then
                error("only " .. tostring(mapping.n) .. " MM2 records matched Supreme Values")
            end

            state.mapped = mapping
            state.dbItems = mapping.dbItems
            state.dbPets = mapping.dbPets
            state.mappedCount = mapping.n
            state.iconCount = mapping.iconCount
            state.status = "ok"
            state.source = dbSource .. (cacheUsed and " (local Supreme cache)" or "")
            if not cacheUsed then
                state.cacheStatus = writeValuesCache(entries) and "saved" or "write unavailable"
            end
            state.updated = os.clock()
            state.loadDuration = state.updated - loadStarted
            state.lastUpdate = os.date("%H:%M:%S")
        end)

        if not ok then
            state.status = "fail"
            state.lastError = tostring(err)
        else
            state.lastError = nil
        end
        state.loadDuration = os.clock() - loadStarted
        state.busy = false
    end)
end

local function itemData(tile)
    if not tile then return nil, 1, nil end
    local nameNode = tile:FindFirstChild("ItemName")
    local label = nameNode and (nameNode:FindFirstChild("Label", true) or nameNode)
    local name = label and (label:IsA("TextLabel") or label:IsA("TextButton")) and clean(label.Text) or ""
    if name == "" or name:find("^Loading") then name = nil end

    local container = tile:FindFirstChild("Container")
    local amountNode = container and container:FindFirstChild("Amount")
    local quantity = 1
    if amountNode and (amountNode:IsA("TextLabel") or amountNode:IsA("TextButton")) then
        quantity = tonumber(tostring(amountNode.Text):match("%d+")) or 1
    end
    return name, quantity, label
end

local function recordUnmatched(tile, name, quantity, target)
    if type(target) ~= "table" then return end
    local container = tile and tile:FindFirstChild("Container")
    local iconObject = container and container:FindFirstChild("Icon")
    local imageId = iconObject and assetId(iconObject.Image) or "no-icon"
    local tags = tile and tile:FindFirstChild("Tags")
    local chromaTag = tags and tags:FindFirstChild("Chroma")
    local chroma = chromaTag ~= nil and chromaTag.Visible == true
    local itemName = clean(name)
    if itemName == "" then itemName = "NO_NAME" end
    local key = normalize(itemName) .. "|" .. tostring(imageId) .. "|" .. tostring(chroma)
    local entry = target[key]
    if not entry then
        entry = {name = itemName, image = tostring(imageId), chroma = chroma, count = 0}
        local mapped = state.mapped
        local nameCandidates = mapped and mapped.dbByName and mapped.dbByName[normalize(itemName)] or {}
        local imageCandidates = mapped and mapped.dbByImage and mapped.dbByImage[tostring(imageId)] or {}
        local function summarize(candidates)
            local result = {}
            for index = 1, math.min(#candidates, 8) do
                local candidate = candidates[index]
                table.insert(result, candidate.kind .. ":" .. candidate.id
                    .. "=" .. candidate.name
                    .. "{type=" .. candidate.itemType
                    .. ",rarity=" .. candidate.rarity
                    .. ",chroma=" .. tostring(candidate.chroma)
                    .. (candidate.year ~= "" and ",year=" .. candidate.year or "")
                    .. (candidate.event ~= "" and ",event=" .. candidate.event or "")
                    .. "}")
            end
            if #candidates > 8 then
                table.insert(result, "...+" .. tostring(#candidates - 8))
            end
            return #result > 0 and table.concat(result, "; ") or "none"
        end
        entry.dbNameMatches = summarize(nameCandidates)
        entry.dbImageMatches = summarize(imageCandidates)
        target[key] = entry
    end
    entry.count = entry.count + math.max(1, tonumber(quantity) or 1)
end

local function getTiles(root)
    if not root then return {} end
    local now = os.clock()
    local cached = tileCache[root]
    if not cached or now - cached.at >= 1.2 then
        cached = {at = now, tiles = {}}
        local seen = {}
        for _, node in ipairs(root:GetDescendants()) do
            if node.Name == "ItemName" then
                local current = node.Parent
                local tile
                while current and current ~= root do
                    if current:IsA("GuiObject") then
                        local container = current:FindFirstChild("Container")
                        if container and container:FindFirstChild("Icon") then
                            tile = current
                            break
                        end
                    end
                    current = current.Parent
                end
                tile = tile or node.Parent
                if tile and tile:FindFirstChild("Container") and not seen[tile] then
                    seen[tile] = true
                    table.insert(cached.tiles, tile)
                end
            end
        end
        tileCache[root] = cached
    end
    return cached.tiles
end

local function makeLabel(parent, name, group)
    local label = parent:FindFirstChild(name)
    if label and not label:IsA("TextLabel") then
        label:Destroy()
        label = nil
    end
    if not label then
        label = Instance.new("TextLabel")
        label.Name = name
        label.BackgroundColor3 = Color3.fromRGB(27, 30, 37)
        label.BackgroundTransparency = 0.06
        label.TextColor3 = Color3.fromRGB(236, 238, 243)
        label.TextStrokeTransparency = 1
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Font = Enum.Font.Roboto
        label.TextSize = 11
        label.BorderSizePixel = 0
        label.ZIndex = 90
        label.Parent = parent
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = label
        local stroke = Instance.new("UIStroke")
        stroke.Name = "SupremeStroke"
        stroke.Thickness = 0.8
        stroke.Transparency = 0.28
        stroke.Color = Color3.fromRGB(62, 66, 77)
        stroke.Parent = label
    end
    label:SetAttribute("SupremeOwner", group)
    return label
end

local function stripDefaultLabelDecorations(label)
    for _, child in ipairs(label:GetChildren()) do
        if child.Name == "SupremeGradient" or child.Name == "SupremeStroke"
            or child:IsA("UICorner") then
            child:Destroy()
        end
    end
end

local function ensureTextGradient(label)
    stripDefaultLabelDecorations(label)
    local gradient = label:FindFirstChild("SupremeTextGradient")
    if not gradient then
        gradient = Instance.new("UIGradient")
        gradient.Name = "SupremeTextGradient"
        gradient.Parent = label
    end
    return gradient
end

-- Restrained category tints, matching PulseHub's dark surfaces and muted accents.
local VALUE_TEXT_COLORS = {
    uniques = Color3.fromRGB(198, 164, 108), godlies = Color3.fromRGB(177, 151, 204),
    chromas = Color3.fromRGB(190, 139, 170), ancients = Color3.fromRGB(194, 132, 142),
    vintages = Color3.fromRGB(190, 151, 119), legendaries = Color3.fromRGB(190, 139, 108),
    rares = Color3.fromRGB(119, 177, 150), uncommons = Color3.fromRGB(130, 155, 187),
    commons = Color3.fromRGB(196, 201, 211), pets = Color3.fromRGB(126, 174, 166),
    misc = Color3.fromRGB(165, 166, 178)
}

local MIN_TRACKED_VALUE = 0.1

local function isTrackedValue(value)
    local numeric = tonumber(value)
    return numeric ~= nil and numeric >= MIN_TRACKED_VALUE
end

local function updateTileBadge(tile, value, quantity, group, tierText, category, itemName)
    local container = tile and tile:FindFirstChild("Container")
    if not container then return end

    local existing = container:FindFirstChild("__SupremeItemValue")
    local hasTier = false
    if not isTrackedValue(value) then
        -- Don't clutter the inventory with "N/A" or fake zero values.
        if existing and existing:IsA("TextLabel") then existing.Visible = false end
        return
    end

    local label = makeLabel(container, "__SupremeItemValue", group)
    label.BackgroundTransparency = 0.06
    label.BackgroundColor3 = Color3.fromRGB(27, 30, 37)
    label.BorderSizePixel = 0
    label.Font = Enum.Font.Roboto
    label.TextWrapped = false
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextScaled = true
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextSize = 11
    label.TextStrokeTransparency = 1
    label.ZIndex = 100
    label.AnchorPoint = Vector2.new(1, 0)
    label.Position = UDim2.new(1, -3, 0, 3)
    label.Size = UDim2.new(0, 58, 0, 19)

    if value ~= nil then
        local accent = VALUE_TEXT_COLORS[category] or Color3.fromRGB(190, 196, 207)
        if normalize(itemName) == "emberbow" then
            accent = Color3.fromRGB(194, 132, 142)
        end
        local oldGradient = label:FindFirstChild("SupremeGradient")
        if oldGradient then oldGradient:Destroy() end
        local stroke = label:FindFirstChild("SupremeStroke")
        if stroke and stroke:IsA("UIStroke") then
            stroke.Color = Color3.fromRGB(62, 66, 77)
            stroke.Transparency = 0.28
            stroke.Thickness = 0.8
        end
        label.Text = formatValue(value)
            .. (quantity > 1 and (" ×" .. tostring(quantity)) or "")
        label.TextColor3 = accent
    else
        stripDefaultLabelDecorations(label)
        local oldGradient = label:FindFirstChild("SupremeTextGradient")
        if oldGradient then oldGradient:Destroy() end
        label.Text = tostring(tierText):match("[Tt]%d+") or "TIER"
        label.TextColor3 = Color3.fromRGB(198, 164, 108)
    end
    label.Visible = true
end

local function scanRoot(root, group)
    local total, known, count, tierCount = 0, 0, 0, 0
    if not root then return total, known, count, tierCount end

    for _, tile in ipairs(getTiles(root)) do
        if not tile.Parent or tile.Visible == false then continue end
        local name, quantity = itemData(tile)
        local value, resolvedName, tierText, category = valueOf(tile, name)
        recordCoverage(tile, name, quantity, group, value, tierText, resolvedName)
        if not isTrackedValue(value) then
            updateTileBadge(tile, nil, quantity, group, nil, category, name)
            recordUnmatched(tile, name, quantity,
                group == "trade" and state.unmatchedTrade or state.unmatchedInventory)
            continue
        end
        total = total + tonumber(value) * quantity
        known = known + quantity
        count = count + quantity
        updateTileBadge(tile, value, quantity, group, nil, category, name)
    end
    return total, known, count, tierCount
end

-- Some mobile MM2 builds omit ItemName nodes from the inventory list and expose
-- only an image card. Resolve the nearest card from its Container.Icon instead.
local function scanImageCards(root, group)
    if not root then return 0, 0, 0, 0 end
    local seen = {}
    local total, known, count, tierCount = 0, 0, 0, 0

    -- This helper is local here because the shared visible() helper is declared
    -- later in the file, after the trade-offer scanner.
    local function cardVisible(object)
        local current = object
        while current and current:IsA("GuiObject") do
            if not current.Visible then return false end
            current = current.Parent
        end
        if current and current:IsA("ScreenGui") then return current.Enabled end
        return current ~= nil
    end

    local function cardForImage(image)
        local current = image
        while current and current ~= root do
            if current:IsA("GuiObject") then
                local container = current:FindFirstChild("Container")
                local icon = container and container:FindFirstChild("Icon")
                if icon and (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
                    return current
                end
            end
            current = current.Parent
        end
        return nil
    end

    for _, node in ipairs(root:GetDescendants()) do
        if not (node:IsA("ImageLabel") or node:IsA("ImageButton")) then continue end
        local card = cardForImage(node)
        if not card or seen[card] or not card.Parent then continue end
        seen[card] = true
        if not cardVisible(card) then continue end

        local name, quantity = itemData(card)
        local value, resolvedName, tierText, category = valueOf(card, name)
        recordCoverage(card, name, quantity, group, value, tierText, resolvedName)
        if not isTrackedValue(value) then
            updateTileBadge(card, nil, quantity, group, nil, category, name)
            recordUnmatched(card, name, quantity,
                group == "trade" and state.unmatchedTrade or state.unmatchedInventory)
            continue
        end
        total = total + tonumber(value) * quantity
        known = known + quantity
        count = count + quantity
        updateTileBadge(card, value, quantity, group, nil, category, name)
    end
    return total, known, count, tierCount
end

local function visible(object)
    local current = object
    while current and current:IsA("GuiObject") do
        if not current.Visible then return false end
        current = current.Parent
    end
    if current and current:IsA("ScreenGui") then return current.Enabled end
    return current ~= nil
end

local function findTrade()
    for _, guiName in ipairs({"TradeGUI", "TradeGUI_Phone"}) do
        local screen = playerGui:FindFirstChild(guiName)
        if screen and screen:IsA("ScreenGui") and screen.Enabled then
            local container = screen:FindFirstChild("Container")
            local trade = container and container:FindFirstChild("Trade")
            if trade and visible(trade) then return screen, container, trade end
            -- Fallback for layouts where the Trade frame is nested or renamed.
            local yourOffer = screen:FindFirstChild("YourOffer", true)
            local theirOffer = screen:FindFirstChild("TheirOffer", true)
            if yourOffer or theirOffer then return screen, container or screen, screen end
        end
    end
    return nil
end

local function hasItemIcon(tile)
    local container = tile and tile:FindFirstChild("Container")
    local icon = container and container:FindFirstChild("Icon")
    if not icon or not (icon:IsA("ImageLabel") or icon:IsA("ImageButton")) then
        return false
    end
    return assetId(icon.Image) ~= nil
end

local function scanOffer(offer, group)
    local container = offer and offer:FindFirstChild("Container")
    if not container then return {}, 0, 0, 0, 0 end

    local items, total, known, count, tierCount = {}, 0, 0, 0, 0
    local seen = {}
    for _, tile in ipairs(container:GetChildren()) do
        if tile:IsA("GuiObject") and tile.Visible and not seen[tile] then
            seen[tile] = true
            local name, quantity = itemData(tile)
            local value, resolvedName, tierText, category = valueOf(tile, name)
            -- Some mobile trade slots briefly have no ItemName node.
            -- A real item asset still counts as an item, even while unmatched.
            recordCoverage(tile, name, quantity, group, value, tierText, resolvedName)
            if isTrackedValue(value) then
                value = tonumber(value)
                table.insert(items, {
                    name = resolvedName or name or "Unknown item",
                    value = value,
                    tier = nil,
                    quantity = quantity
                })
                count = count + quantity
                total = total + value * quantity
                known = known + quantity
                updateTileBadge(tile, value, quantity, group, nil, category, name)
            else
                updateTileBadge(tile, nil, quantity, group, nil, category, name)
                recordUnmatched(tile, name, quantity, state.unmatchedTrade)
            end
        end
    end
    return items, total, known, count, tierCount
end

local function setSummary(parent, name, title, total, known, count, group, tierCount)
    if not parent then return end
    local label = makeLabel(parent, name, group)
    stripDefaultLabelDecorations(label)
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, 5)
    label.Size = UDim2.new(1, -12, 0, 32)
    label.BackgroundTransparency = 0.04
    label.BackgroundColor3 = title == "ОТДАЁШЬ"
        and Color3.fromRGB(43, 34, 31) or Color3.fromRGB(29, 40, 43)
    label.TextSize = 17
    label.TextScaled = false
    label.Font = Enum.Font.Roboto
    label.TextStrokeTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextColor3 = title == "ОТДАЁШЬ"
        and Color3.fromRGB(226, 164, 119) or Color3.fromRGB(119, 196, 190)
    label.Text = title .. ": " .. formatValue(total)
        .. ((tierCount or 0) > 0 and " + TIER(" .. tostring(tierCount) .. ")" or "")
        .. (known < count and " + ?" or "")
    local corner = label:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 9)
    corner.Parent = label
    local stroke = label:FindFirstChild("SupremeStroke") or Instance.new("UIStroke")
    stroke.Name = "SupremeStroke"
    stroke.Color = title == "ОТДАЁШЬ"
        and Color3.fromRGB(151, 105, 78) or Color3.fromRGB(77, 139, 137)
    stroke.Transparency = 0.35
    stroke.Thickness = 1
    stroke.Parent = label
    label.Visible = count > 0
end

local function getVerdict(giveValue, receiveValue)
    local give = tonumber(giveValue) or 0
    local receive = tonumber(receiveValue) or 0
    local difference = receive - give
    local tolerance = math.max(math.max(math.abs(give), math.abs(receive)) * 0.02, 0.005)
    if math.abs(difference) <= tolerance then
        return "FAIR", difference
    end
    return difference > 0 and "WIN" or "LOSE", difference
end

local function runCoreSelfTests()
    local numericCases = {
        {"Value - 4,600", 4600},
        {"Value - 1,000,000", 1000000},
        {"Value - 0.025", 0.025},
        {"Value - 14,250.75", 14250.75}
    }
    for _, testCase in ipairs(numericCases) do
        assert(parseDisplayedValue(testCase[1]) == testCase[2],
            "numeric parser failed: " .. testCase[1])
    end
    assert(formatValue(4600) == "4,600", "thousands formatting failed")
    assert(formatValue(1000000) == "1,000,000", "large value formatting failed")
    assert(formatValue(0.025) == "0.025", "fraction formatting failed")
    assert(formatValue(-4600) == "-4,600", "negative difference formatting failed")

    local syntheticHtml =
        '<div class="itemcolumn"><div class="itemhead">Test Gun</div><span>Value - 4,600</span></div>' ..
        '<div class="itemcolumn"><div class="itemhead">Fractional Knife</div><span>Value - 0.025</span></div>' ..
        '<div class="itemcolumn"><div class="itemhead">Tier Item</div><span>Value - x1 T3 Godly</span></div>'
    local parsedEntries = {}
    local parsedCount, parsedTierCount = parseCategory("godlies", syntheticHtml, parsedEntries)
    assert(parsedCount == 3 and parsedTierCount == 1, "synthetic Supreme card parsing failed")
    assert(parsedEntries[1].v == 4600, "comma-separated card value was not preserved")
    assert(parsedEntries[2].v == 0.025, "fractional card value was not preserved")
    assert(parsedEntries[3].v == nil and parsedEntries[3].t ~= nil,
        "tier card was treated as a numeric value")

    local testDatabase = {
        Item = {
            TestGun = {
                ItemName = "Test",
                ItemType = "Gun",
                Rarity = "Godly",
                Image = "rbxassetid://111111",
                ItemID = "111111"
            },
            ChromaTestGun = {
                ItemName = "Test",
                ItemType = "Gun",
                Rarity = "Godly",
                Image = "rbxassetid://222222",
                Chroma = true
            }
        },
        Pets = {}
    }
    local regularEntry = {
        c = "godlies", n = "Test Gun", im = "Test Gun (Gun)",
        v = 10, cl = "Godly"
    }
    local chromaEntry = {
        c = "chromas", n = "Chroma Test Gun", im = "Chroma Test Gun (Gun)",
        v = 100, cl = "Godly"
    }

    local function fakeTile(image, isChroma)
        local icon = {Image = image}
        local container = {
            FindFirstChild = function(_, childName)
                if childName == "Icon" then return icon end
                return nil
            end
        }
        local chromaTag = {Visible = isChroma}
        local tags = {
            FindFirstChild = function(_, childName)
                if childName == "Chroma" then return chromaTag end
                return nil
            end
        }
        return {
            FindFirstChild = function(_, childName)
                if childName == "Container" then return container end
                if childName == "Tags" then return tags end
                return nil
            end
        }
    end

    local previousMapping = state.mapped
    local mappingOk, mappingError = pcall(function()
        local fullMapping = buildMapping({regularEntry, chromaEntry}, testDatabase)
        state.mapped = fullMapping
        local regularValue = valueOf(fakeTile("rbxassetid://111111", false), "Test Gun")
        local chromaValue = valueOf(fakeTile("rbxassetid://111111", true), "Test Gun")
        assert(regularValue == 10, "regular icon mapping failed")
        assert(chromaValue == 100, "Chroma icon mapping failed")

        local regularOnlyMapping = buildMapping({regularEntry}, testDatabase)
        state.mapped = regularOnlyMapping
        local missingChromaValue = valueOf(fakeTile("rbxassetid://111111", true), "Test Gun")
        assert(missingChromaValue == nil,
            "unmapped Chroma incorrectly inherited the regular item's value")

        -- Regression: Supreme parses "Swirly Gun" into base name "Swirly"
        -- plus kind "Gun", while some MM2 DB builds store ItemName as "Swirly Gun".
        local swirlyDatabase = {
            Item = {
                SwirlyGun = {
                    ItemName = "Swirly Gun",
                    ItemType = "Gun",
                    Rarity = "Godly",
                    Image = "rbxassetid://333333"
                }
            },
            Pets = {}
        }
        local swirlyEntry = {
            c = "godlies", n = "Swirly Gun", im = "Swirly Gun (Gun)",
            v = 55, cl = "Godly"
        }
        local swirlyMapping = buildMapping({swirlyEntry}, swirlyDatabase)
        state.mapped = swirlyMapping
        local swirlyValue = valueOf(fakeTile("rbxassetid://333333", false), "Swirly Gun")
        assert(swirlyValue == 55, "weapon name/type suffix alias mapping failed")
    end)
    state.mapped = previousMapping
    if not mappingOk then error(mappingError) end

    assert(isTrackedValue(0.1), "minimum 0.1 value should be included")
    assert(isTrackedValue(0.5), "fractional value should be included")
    assert(isTrackedValue(1), "integer value should be included")
    assert(not isTrackedValue(0), "zero value should be excluded")
    assert(not isTrackedValue(0.099), "values below 0.1 should be excluded")
    assert(not isTrackedValue(nil), "unvalued items should be excluded")

    local duplicateTotal = 10 * 2 + 100 * 3
    assert(duplicateTotal == 320, "duplicate quantity aggregation failed")
    local verdict, difference = getVerdict(200, duplicateTotal)
    assert(verdict == "WIN" and difference == 120, "trade verdict calculation failed")
    local fairVerdict = getVerdict(100, 101)
    assert(fairVerdict == "FAIR", "fair tolerance calculation failed")
    return true
end

local function setTradeVerdict(trade, yourTotal, theirTotal, yourKnown, theirKnown, yourCount, theirCount, yourTierCount, theirTierCount)
    if not trade then return end
    local label = makeLabel(trade, "__SupremeTradeVerdict", "trade")
    stripDefaultLabelDecorations(label)
    local oldGradient = label:FindFirstChild("SupremeTextGradient")
    if oldGradient then oldGradient:Destroy() end
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 1, -34)
    label.Size = UDim2.new(0.86, 0, 0, 34)
    label.BackgroundTransparency = 0.05
    label.BackgroundColor3 = Color3.fromRGB(27, 30, 37)
    label.ZIndex = 150
    label.Font = Enum.Font.Roboto
    label.TextSize = 18
    label.TextScaled = false
    label.TextWrapped = false
    label.TextStrokeTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center

    local verdict, difference, caption, color
    if yourCount == 0 or theirCount == 0 then
        caption, color = "ОЖИДАНИЕ ПРЕДМЕТОВ", Color3.fromRGB(196, 201, 211)
    elseif yourTierCount > 0 or theirTierCount > 0 then
        caption, color = "TIER — НУЖНА РУЧНАЯ ПРОВЕРКА", Color3.fromRGB(198, 164, 108)
    elseif yourKnown < yourCount or theirKnown < theirCount then
        caption, color = "ЕСТЬ ПРЕДМЕТЫ БЕЗ ОЦЕНКИ", Color3.fromRGB(198, 164, 108)
    else
        verdict, difference = getVerdict(yourTotal, theirTotal)
        if verdict == "WIN" then
            caption = "ПЛЮС  +" .. formatValue(difference)
            color = Color3.fromRGB(102, 183, 143)
        elseif verdict == "LOSE" then
            caption = "МИНУС  " .. formatValue(difference)
            color = Color3.fromRGB(201, 111, 124)
        else
            caption = "РОВНЫЙ ОБМЕН  " .. formatValue(difference)
            color = Color3.fromRGB(130, 166, 190)
        end
    end

    label.TextColor3 = color
    label.Text = caption
    local corner = label:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = label
    local stroke = label:FindFirstChild("SupremeStroke") or Instance.new("UIStroke")
    stroke.Name = "SupremeStroke"
    stroke.Color = color
    stroke.Transparency = 0.4
    stroke.Thickness = 1.1
    stroke.Parent = label
    label.Visible = true
end

local function setTradeAdvice(trade, yourItems, yourTotal, theirTotal, yourKnown, theirKnown, yourCount, theirCount, yourTierCount, theirTierCount)
    if not trade then return end
    local label = makeLabel(trade, "__SupremeTradeAdvice", "trade")
    stripDefaultLabelDecorations(label)
    local gradient = label:FindFirstChild("SupremeTextGradient")
    if gradient then gradient:Destroy() end
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 1, -8)
    label.Size = UDim2.new(0.94, 0, 0, 24)
    label.BackgroundTransparency = 0.10
    label.BackgroundColor3 = Color3.fromRGB(24, 27, 33)
    label.ZIndex = 150
    label.Font = Enum.Font.Roboto
    label.TextSize = 13
    label.TextScaled = false
    label.TextWrapped = false
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextStrokeTransparency = 1
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center

    local advice, color
    if yourCount == 0 or theirCount == 0 then
        advice, color = "Добавь предметы с обеих сторон для сравнения", Color3.fromRGB(196, 201, 211)
    elseif yourTierCount > 0 or theirTierCount > 0 then
        advice, color = "Tier-предметы: числовой совет отключён", Color3.fromRGB(198, 164, 108)
    elseif yourKnown < yourCount or theirKnown < theirCount then
        advice, color = "Сначала проверь предметы без точной оценки", Color3.fromRGB(198, 164, 108)
    else
        local verdict, difference = getVerdict(yourTotal, theirTotal)
        if verdict == "LOSE" then
            local bestItem, bestGap = nil, math.abs(difference)
            for _, item in ipairs(yourItems or {}) do
                local itemValue = tonumber(item.value)
                if isTrackedValue(itemValue) then
                    local nextGap = math.abs((yourTotal - itemValue) - theirTotal)
                    if nextGap + 0.000001 < bestGap then
                        bestItem, bestGap = item, nextGap
                    end
                end
            end
            if bestItem then
                advice = "УБРАТЬ/ЗАМЕНИТЬ: " .. tostring(bestItem.name)
                    .. (bestItem.quantity > 1 and " (1 шт.)" or "")
                color = Color3.fromRGB(194, 151, 105)
            else
                advice = "ПОПРОСИ ДОПЛАТУ: +" .. formatValue(math.abs(difference))
                color = Color3.fromRGB(194, 151, 105)
            end
        elseif verdict == "WIN" then
            advice, color = "Ты в плюсе — не добавляй предметы без необходимости", Color3.fromRGB(102, 183, 143)
        else
            advice, color = "Баланс ровный — менять предметы не требуется", Color3.fromRGB(105, 195, 255)
        end
    end
    label.TextColor3 = color
    label.Text = advice
    local corner = label:FindFirstChildOfClass("UICorner") or Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 8)
    corner.Parent = label
    label.Visible = true
end

local function scanTrade()
    state.unmatchedTrade = {}
    state.coverageTrade = {}
    state.coverageSeenTrade = {}
    local screen, container, trade = findTrade()
    if not screen then
        state.latestTrade = "No active trade detected."
        return nil
    end

    local yours = trade:FindFirstChild("YourOffer", true)
    local theirs = trade:FindFirstChild("TheirOffer", true)
    if not yours and container then yours = container:FindFirstChild("YourOffer", true) end
    if not theirs and container then theirs = container:FindFirstChild("TheirOffer", true) end

    local yourItems, yourTotal, yourKnown, yourCount, yourTierCount = scanOffer(yours, "trade")
    local theirItems, theirTotal, theirKnown, theirCount, theirTierCount = scanOffer(theirs, "trade")
    setSummary(yours, "__SupremeOfferTotal", "ОТДАЁШЬ", yourTotal, yourKnown, yourCount, "trade", yourTierCount)
    setSummary(theirs, "__SupremeOfferTotal", "ПОЛУЧАЕШЬ", theirTotal, theirKnown, theirCount, "trade", theirTierCount)
    setTradeVerdict(trade, yourTotal, theirTotal, yourKnown, theirKnown,
        yourCount, theirCount, yourTierCount, theirTierCount)
    setTradeAdvice(trade, yourItems, yourTotal, theirTotal, yourKnown, theirKnown,
        yourCount, theirCount, yourTierCount, theirTierCount)

    local lines = {
        "ОТДАЁШЬ: " .. formatValue(yourTotal)
            .. " (" .. tostring(yourKnown) .. "/" .. tostring(yourCount) .. " оценено, "
            .. tostring(yourTierCount) .. " tier)",
        "ПОЛУЧАЕШЬ: " .. formatValue(theirTotal)
            .. " (" .. tostring(theirKnown) .. "/" .. tostring(theirCount) .. " оценено, "
            .. tostring(theirTierCount) .. " tier)"
    }
    if yourCount > 0 and theirCount > 0 then
        if yourTierCount > 0 or theirTierCount > 0 then
            table.insert(lines, "РЕЗУЛЬТАТ: TIER-ПРЕДМЕТЫ — числовое сравнение отключено")
        elseif yourKnown < yourCount or theirKnown < theirCount then
            table.insert(lines, "РЕЗУЛЬТАТ: НЕПОЛНЫЕ ОЦЕНКИ — проверь неизвестные предметы")
        else
            local verdict, difference = getVerdict(yourTotal, theirTotal)
            table.insert(lines, "РЕЗУЛЬТАТ: " .. verdict .. " | Разница: "
                .. (difference > 0 and "+" or "") .. formatValue(difference))
        end
    else
        table.insert(lines, "РЕЗУЛЬТАТ: ожидаются предметы с обеих сторон.")
    end
    state.latestTrade = table.concat(lines, "\n")
    return {
        yourTotal = yourTotal,
        theirTotal = theirTotal,
        yourKnown = yourKnown,
        theirKnown = theirKnown,
        yourCount = yourCount,
        theirCount = theirCount,
        yourTierCount = yourTierCount,
        theirTierCount = theirTierCount
    }
end

-- PulseHub does not guess the inventory ScreenGui name. It reads the
-- live InventoryModule singleton and its MyInventory.Data.Weapons entries.
local function getInventoryModule()
    if state.inventoryModule then return state.inventoryModule end
    if os.clock() < (state.inventoryModuleRetryAt or 0) then return nil end
    state.inventoryModuleRetryAt = os.clock() + 5

    local modules = ReplicatedStorage:FindFirstChild("Modules")
    if not modules then
        state.inventoryModuleStatus = "ReplicatedStorage.Modules missing"
        return nil
    end

    local moduleScript = modules:FindFirstChild("InventoryModule")
    if not moduleScript then
        state.inventoryModuleStatus = "Modules.InventoryModule missing"
        return nil
    end

    local ok, result = pcall(require, moduleScript)
    if not ok then
        state.inventoryModuleStatus = "require failed: " .. tostring(result)
        return nil
    end
    if type(result) ~= "table" then
        state.inventoryModuleStatus = "require returned " .. typeof(result)
        return nil
    end

    state.inventoryModule = result
    state.inventoryModuleStatus = "loaded"
    return result
end

local function scanModuleInventory()
    local module = getInventoryModule()
    if not module then return 0, 0, 0, 0, nil end

    local myInventory = module.MyInventory
    local data = type(myInventory) == "table" and myInventory.Data or nil
    if type(data) ~= "table" or type(data.Weapons) ~= "table" then
        state.inventoryModuleStatus = "loaded, MyInventory.Data.Weapons unavailable"
        return 0, 0, 0, 0, nil
    end

    local gui = type(module.GUI) == "table" and module.GUI.MyInventory or nil
    local total, known, count, frameCount, tierCount = 0, 0, 0, 0, 0
    local visibleFrames, groupCount, dataEntries = 0, 0, 0
    local parentedFrames, detachedFrames, missingFrameEntries = 0, 0, 0
    local frameSamples = {}
    local seen = {}

    local function instancePath(object, stopAt)
        local names = {}
        local current = object
        while current and current ~= stopAt and #names < 7 do
            table.insert(names, 1, current.Name)
            current = current.Parent
        end
        return table.concat(names, ".")
    end

    -- PulseHub's actual structure is Data.Weapons[group][itemId] = entry.
    -- The previous scanner stopped one level too early and counted only the
    -- category/group tables (5 in the user's diagnostic), not item entries.
    local function scanCollection(collection, collectionName)
        if type(collection) ~= "table" then return end
        for subgroupName, subgroup in pairs(collection) do
            if type(subgroup) ~= "table" then continue end
            groupCount = groupCount + 1
            for itemKey, entry in pairs(subgroup) do
                if type(entry) ~= "table" then continue end
                dataEntries = dataEntries + 1
                local storedAmount = tonumber(entry.Amount)
                local entryQuantity = storedAmount and math.max(1, math.floor(storedAmount)) or 1
                local tile = entry.Frame
                if typeof(tile) ~= "Instance" or not tile:IsA("GuiObject") then
                    -- No tile means no reliable Supreme value lookup; exclude it.
                    missingFrameEntries = missingFrameEntries + 1
                    continue
                end
                if seen[tile] then continue end
                seen[tile] = true
                frameCount = frameCount + 1
                if not tile.Parent then
                    detachedFrames = detachedFrames + 1
                    missingFrameEntries = missingFrameEntries + 1
                    if #frameSamples < 8 then
                        table.insert(frameSamples, tostring(itemKey) .. "=>DETACHED:" .. tile.Name)
                    end
                    continue
                end
                parentedFrames = parentedFrames + 1
                local tileIsVisible = visible(tile)
                if tileIsVisible then
                    visibleFrames = visibleFrames + 1
                elseif #frameSamples < 8 then
                    table.insert(frameSamples, tostring(itemKey) .. "=>" .. instancePath(tile, playerGui)
                        .. "{Visible=" .. tostring(tile.Visible) .. "}")
                end

                -- Do not depend on ItemName text: PulseHub's inventory tiles
                -- are reliably identified by Container.Icon -> MM2 database.
                local name, quantity = itemData(tile)
                if storedAmount and quantity <= 1 then
                    quantity = entryQuantity
                end
                local resolvedValue, resolvedName, tierText, category = valueOf(tile, name)
                recordCoverage(tile, name, quantity, "inventory", resolvedValue, tierText, resolvedName)
                if isTrackedValue(resolvedValue) then
                    resolvedValue = tonumber(resolvedValue)
                    total = total + resolvedValue * quantity
                    known = known + quantity
                    count = count + quantity
                    updateTileBadge(tile, resolvedValue, quantity, "inventory", nil, category)
                else
                    updateTileBadge(tile, nil, quantity, "inventory", nil, category, name)
                    recordUnmatched(tile, name, quantity, state.unmatchedInventory)
                end
            end
        end
    end

    scanCollection(data.Weapons, "Weapons")
    scanCollection(data.Pets, "Pets")

    -- InventoryModule.GUI.MyInventory can be a Lua table on mobile,
    -- while its Data entries still hold the real, parented item-card Frames.
    -- Recover the visible GUI root from one of those Frames instead of treating
    -- the table as an Instance (which previously produced GUI cards = 0).
    local guiInstance = typeof(gui) == "Instance" and gui or nil
    if not guiInstance then
        for _, subgroup in pairs(data.Weapons) do
            if type(subgroup) == "table" then
                for _, entry in pairs(subgroup) do
                    local frame = type(entry) == "table" and entry.Frame or nil
                    if typeof(frame) == "Instance" and frame:IsA("GuiObject") and frame.Parent then
                        local current = frame
                        while current and current ~= playerGui do
                            if current:IsA("GuiObject") and current.Name == "Main" then
                                guiInstance = current
                                break
                            end
                            current = current.Parent
                        end
                        if guiInstance then break end
                    end
                end
            end
            if guiInstance then break end
        end
    end

    if guiInstance then
        -- Only scan actual inventory item grids. Scanning the whole Main frame
        -- also catches Craft/Recycle/action previews and inflates GUI totals.
        local main = guiInstance:FindFirstChild("Main")
        local weapons = main and main:FindFirstChild("Weapons")
        local pets = main and main:FindFirstChild("Pets")
        local weaponRoot = weapons and weapons:FindFirstChild("Items")
        local petRoot = pets and pets:FindFirstChild("Items")
        local guiTiles = {}
        local guiKnown, guiCount = 0, 0
        for _, root in ipairs({weaponRoot, petRoot}) do
            if root and root:IsA("GuiObject") then
                for _, tile in ipairs(getTiles(root)) do
                    table.insert(guiTiles, tile)
                end
                local _, known, count = scanRoot(root, "inventoryOverlay")
                guiKnown = guiKnown + (known or 0)
                guiCount = guiCount + (count or 0)
                scanImageCards(root, "inventoryOverlay")
            end
        end
        state.inventoryGuiFrames = #guiTiles
        state.inventoryGuiValued = guiKnown
        state.inventoryGuiItems = guiCount
        state.inventoryGuiPath = "InventoryModule.GUI.MyInventory.Main.Weapons.Items"
            .. (petRoot and " + Pets.Items" or "")

        local classCounts, samples = {}, {}
        local descendants = guiInstance:GetDescendants()
        for _, node in ipairs(descendants) do
            classCounts[node.ClassName] = (classCounts[node.ClassName] or 0) + 1
            if #samples < 18 and (node.Name == "ItemName" or node.Name == "Container"
                or node.Name == "Icon" or node:IsA("ImageLabel") or node:IsA("ImageButton")) then
                table.insert(samples, instancePath(node, guiInstance)
                    .. ((node:IsA("ImageLabel") or node:IsA("ImageButton"))
                        and ("=" .. tostring(assetId(node.Image) or "no-image")) or ""))
            end
        end
        state.inventoryGuiStructure = "Type=" .. guiInstance.ClassName
            .. " | InferredFromFrame=" .. tostring(typeof(gui) ~= "Instance")
            .. " | Descendants=" .. tostring(#descendants)
            .. " | Classes=" .. HttpService:JSONEncode(classCounts)
            .. " | Samples=" .. table.concat(samples, "; ")
    else
        state.inventoryGuiFrames = 0
        state.inventoryGuiValued = 0
        state.inventoryGuiItems = 0
        state.inventoryGuiStructure = "GUI reference type=" .. typeof(gui) .. " | Frame root not found"
    end
    state.inventoryFrameParents = "parented=" .. tostring(parentedFrames)
        .. ", detached=" .. tostring(detachedFrames)
        .. ", visible=" .. tostring(visibleFrames)
        .. " | samples=" .. (#frameSamples > 0 and table.concat(frameSamples, "; ") or "none")

    -- PulseHub's GUI reference is gui.MyInventory.Main.Weapons.Items.
    -- Put the running total on the visible inventory page when available.
    local main = guiInstance and guiInstance:FindFirstChild("Main")
    local totalParent = main or guiInstance
    if totalParent and totalParent:IsA("GuiObject") then
        local label = makeLabel(totalParent, "__SupremeInventoryTotal", "inventory")
        label.AnchorPoint = Vector2.new(0, 0)
        label.Position = UDim2.new(0, 8, 0, 8)
        label.Size = UDim2.fromOffset(250, 26)
        label.TextSize = 12
        label.Text = "INV " .. formatValue(total)
            .. (tierCount > 0 and " + TIER(" .. tostring(tierCount) .. ")" or "")
            .. " | KNOWN " .. tostring(known) .. "/" .. tostring(count)
        label.Visible = count > 0
    end

    state.inventoryFrames = frameCount
    state.inventoryVisibleFrames = visibleFrames
    state.inventoryDataEntries = dataEntries
    state.inventoryMissingFrames = missingFrameEntries
    state.inventoryGroups = groupCount
    if state.inventoryGuiPath == "unknown" then
        state.inventoryGuiPath = gui and "InventoryModule.GUI.MyInventory (root unresolved)"
            or "InventoryModule.GUI.MyInventory unavailable"
    end

    return total, known, count, visibleFrames, myInventory, tierCount
end

local function scanInventory()
    state.unmatchedInventory = {}
    state.coverageInventory = {}
    state.coverageSeenInventory = {}
    state.inventoryMissingFrames = 0
    local weaponTotal, weaponKnown, weaponCount, visibleFrames = 0, 0, 0, 0
    local moduleTotal, moduleKnown, moduleCount, moduleVisible, _, moduleTierCount = scanModuleInventory()
    local weaponTierCount = moduleTierCount or 0
    weaponTotal, weaponKnown, weaponCount, visibleFrames = moduleTotal, moduleKnown, moduleCount, moduleVisible

    -- Fallback for UI-only builds where InventoryModule does not expose frames.
    -- Keep the explicit MainGUI/MainMobile paths as a secondary option.
    if weaponCount == 0 then
        for _, guiName in ipairs({"MainGUI", "MainMobile"}) do
            local screen = playerGui:FindFirstChild(guiName)
            if screen and screen:IsA("ScreenGui") and screen.Enabled then
                local gameFrame = screen:FindFirstChild("Game")
                local inventory = gameFrame and gameFrame:FindFirstChild("Inventory")
                if inventory and visible(inventory) then
                    local main = inventory:FindFirstChild("Main")
                    local weapons = main and main:FindFirstChild("Weapons")
                    local pets = main and main:FindFirstChild("Pets")
                    local weaponRoot = weapons and weapons:FindFirstChild("Items")
                    local petRoot = pets and pets:FindFirstChild("Items")
                    local a,b,c,at = scanRoot(weaponRoot, "inventory")
                    local d,e,f,dt = scanRoot(petRoot, "inventory")
                    weaponTotal, weaponKnown, weaponCount = a+d, b+e, c+f
                    weaponTierCount = (at or 0) + (dt or 0)
                    local label = makeLabel(inventory, "__SupremeInventoryTotal", "inventory")
                    label.AnchorPoint = Vector2.new(0, 1)
                    label.Position = UDim2.new(0, 4, 1, -5)
                    label.Size = UDim2.fromOffset(290, 28)
                    label.TextSize = 12
                    label.Text = "INV " .. formatValue(weaponTotal)
                        .. (weaponTierCount > 0 and " + TIER(" .. tostring(weaponTierCount) .. ")" or "")
                        .. " | KNOWN " .. tostring(weaponKnown) .. "/" .. tostring(weaponCount)
                    label.Visible = weaponCount > 0
                    state.inventoryGuiPath = guiName .. ".Game.Inventory"
                    break
                end
            end
        end
    end

    -- Also scan the inventory cards embedded in the trade window.
    local screen = playerGui:FindFirstChild("TradeGUI")
    if not screen or not screen:IsA("ScreenGui") or not screen.Enabled then
        screen = playerGui:FindFirstChild("TradeGUI_Phone")
    end
    if screen and screen:IsA("ScreenGui") and screen.Enabled then
        local container = screen:FindFirstChild("Container")
        local items = container and container:FindFirstChild("Items")
        local main = items and items:FindFirstChild("Main")
        if main and visible(main) then
            local extraWeapons = main:FindFirstChild("Weapons")
            local extraPets = main:FindFirstChild("Pets")
            scanRoot(extraWeapons and extraWeapons:FindFirstChild("Items"), "tradeInventory")
            scanRoot(extraPets and extraPets:FindFirstChild("Items"), "tradeInventory")
        end

        local itemRoot = items and items:FindFirstChild("_mO", true)
        if itemRoot and visible(itemRoot) then
            for _, category in ipairs({"Weapons", "Pets"}) do
                local list = itemRoot:FindFirstChild(category)
                if list and list:IsA("GuiObject") and visible(list) then
                    local _, _, namedCount = scanRoot(list, "tradeInventory")
                    if namedCount == 0 then
                        scanImageCards(list, "tradeInventory")
                    else
                        -- Supplement text-based cards with image-only cards.
                        scanImageCards(list, "tradeInventory")
                    end
                end
            end
        end
    end

    local screenNames = {}
    for _, child in ipairs(playerGui:GetChildren()) do
        if child:IsA("LayerCollector") then
            table.insert(screenNames, child.Name .. "=" .. tostring(child.Enabled))
        end
    end
    state.inventoryScreenList = table.concat(screenNames, ", ")

    state.latestInventory =
        "InventoryModule: " .. tostring(state.inventoryModuleStatus)
        .. " | Data entries: " .. tostring(state.inventoryDataEntries)
        .. " | Missing frames: " .. tostring(state.inventoryMissingFrames)
        .. " | Frames: " .. tostring(state.inventoryFrames)
        .. " | Visible: " .. tostring(state.inventoryVisibleFrames)
        .. " | GUI cards: " .. tostring(state.inventoryGuiFrames)
        .. " | GUI valued: " .. tostring(state.inventoryGuiValued) .. "/" .. tostring(state.inventoryGuiItems)
        .. " | Groups: " .. tostring(state.inventoryGroups)
        .. " | GUI: " .. tostring(state.inventoryGuiPath)
        .. " | Data path: MyInventory.Data.Weapons[group][itemId].Frame"
        .. " | Frame refs: " .. tostring(state.inventoryFrameParents)
        .. " | GUI structure: " .. tostring(state.inventoryGuiStructure)
        .. " | Min value: 0.1+"
        .. " | Numeric total: " .. formatValue(weaponTotal)
        .. " | Tier items: " .. tostring(weaponTierCount)
        .. " | Valued: " .. tostring(weaponKnown) .. "/" .. tostring(weaponCount)
        .. " | PlayerGui: " .. tostring(state.inventoryScreenList)
end

__bootStage("BOOT 04/06 — BUILDING MAIN UI", "Creating the Supreme panel...")
-- PulseHub-inspired compact panel: Midnight surfaces, restrained Crimson accent, Roboto typography.
local oldGui = playerGui:FindFirstChild("SupremeTradeText")
if oldGui then pcall(function() oldGui:Destroy() end) end

local textGui = Instance.new("ScreenGui")
textGui.Name = "SupremeTradeText"
textGui.ResetOnSpawn = false
textGui.IgnoreGuiInset = true
textGui.DisplayOrder = 9999
textGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
textGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "SupremePanel"
panel.Size = UDim2.fromOffset(290, 225)
panel.Position = UDim2.new(1, -12, 0, 88)
panel.AnchorPoint = Vector2.new(1, 0)
panel.BackgroundColor3 = Color3.fromRGB(20, 22, 27)
panel.BackgroundTransparency = 0.06
panel.BorderSizePixel = 0
panel.ZIndex = 200
panel.Parent = textGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 15)
panelCorner.Parent = panel
local panelStroke = Instance.new("UIStroke")
panelStroke.Thickness = 1
panelStroke.Transparency = 0.16
panelStroke.Color = Color3.fromRGB(45, 48, 56)
panelStroke.Parent = panel

local headerLine = Instance.new("Frame")
headerLine.Size = UDim2.new(1, -22, 0, 1)
headerLine.Position = UDim2.fromOffset(11, 37)
headerLine.BackgroundColor3 = Color3.fromRGB(48, 51, 59)
headerLine.BackgroundTransparency = 0.18
headerLine.BorderSizePixel = 0
headerLine.ZIndex = 201
headerLine.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -48, 0, 34)
title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.Roboto
title.TextSize = 13
title.TextColor3 = Color3.fromRGB(236, 238, 243)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "SUPREME CHECKER"
title.Active = true
title.ZIndex = 201
title.Parent = panel

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(34, 30)
toggle.Position = UDim2.new(1, -38, 0, 2)
toggle.BackgroundColor3 = Color3.fromRGB(34, 37, 45)
toggle.BorderSizePixel = 0
toggle.Font = Enum.Font.Roboto
toggle.TextSize = 16
toggle.TextColor3 = Color3.fromRGB(196, 201, 211)
toggle.Text = "+"
toggle.ZIndex = 202
toggle.Parent = panel
local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(0, 9)
toggleCorner.Parent = toggle

local output = Instance.new("TextBox")
output.Name = "DiagnosticText"
output.Size = UDim2.new(1, -20, 1, -164)
output.Position = UDim2.fromOffset(10, 78)
output.BackgroundColor3 = Color3.fromRGB(15, 16, 20)
output.BackgroundTransparency = 0.04
output.BorderSizePixel = 0
output.ClearTextOnFocus = false
output.MultiLine = true
output.TextEditable = true
output.TextWrapped = false
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.Font = Enum.Font.RobotoMono
output.TextSize = 10
output.TextColor3 = Color3.fromRGB(196, 201, 211)
output.Text = "Connecting to Supreme Values..."
output.ZIndex = 201
output.Parent = panel
local outputCorner = Instance.new("UICorner")
outputCorner.CornerRadius = UDim.new(0, 9)
outputCorner.Parent = output
local outputStroke = Instance.new("UIStroke")
outputStroke.Color = Color3.fromRGB(45, 48, 56)
outputStroke.Transparency = 0.24
outputStroke.Parent = output

local hopButton = Instance.new("TextButton")
hopButton.Name = "SupremeHopServer"
hopButton.Size = UDim2.new(1, -20, 0, 34)
hopButton.Position = UDim2.new(0, 10, 1, -79)
hopButton.BackgroundColor3 = Color3.fromRGB(112, 48, 61)
hopButton.BorderSizePixel = 0
hopButton.Font = Enum.Font.Roboto
hopButton.TextSize = 12
hopButton.TextColor3 = Color3.fromRGB(244, 238, 240)
hopButton.Text = "↗   HOP SERVER"
hopButton.AutoButtonColor = false
hopButton.ZIndex = 205
hopButton.Parent = panel
local hopCorner = Instance.new("UICorner")
hopCorner.CornerRadius = UDim.new(0, 9)
hopCorner.Parent = hopButton
local hopStroke = Instance.new("UIStroke")
hopStroke.Color = Color3.fromRGB(150, 83, 96)
hopStroke.Transparency = 0.42
hopStroke.Thickness = 1
hopStroke.Parent = hopButton

local copyButton = Instance.new("TextButton")
copyButton.Name = "CopySupremeDiagnostic"
copyButton.Size = UDim2.new(1, -20, 0, 32)
copyButton.Position = UDim2.new(0, 10, 1, -39)
copyButton.BackgroundColor3 = Color3.fromRGB(27, 30, 37)
copyButton.BorderSizePixel = 0
copyButton.AutoButtonColor = false
copyButton.Font = Enum.Font.Roboto
copyButton.TextSize = 12
copyButton.TextColor3 = Color3.fromRGB(210, 213, 220)
copyButton.Text = "COPY FULL DIAGNOSTIC"
copyButton.ZIndex = 205
copyButton.Parent = panel
local copyCorner = Instance.new("UICorner")
copyCorner.CornerRadius = UDim.new(0, 9)
copyCorner.Parent = copyButton
local copyStroke = Instance.new("UIStroke")
copyStroke.Color = Color3.fromRGB(62, 66, 77)
copyStroke.Transparency = 0.34
copyStroke.Parent = copyButton

__bootStage("BOOT 05/06 — MAIN UI CREATED", "Starting buttons and inventory/trade scanners...")
local collapsed = true
local expandedSize = UDim2.fromOffset(290, 274)
local collapsedSize = UDim2.fromOffset(176, 38)
local function setCollapsed(value)
    collapsed = value
    local targetSize = collapsed and collapsedSize or expandedSize
    TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
        Size = targetSize
    }):Play()
    output.Visible = not collapsed
    hopButton.Visible = not collapsed
    copyButton.Visible = not collapsed
    headerLine.Visible = not collapsed
    toggle.Text = collapsed and "+" or "−"
    title.Text = collapsed and "SUPREME" or (state.status == "ok" and "SUPREME CHECKER  /  READY" or "SUPREME CHECKER  /  " .. string.upper(state.status))
end
toggle.Activated:Connect(function()
    setCollapsed(not collapsed)
end)
setCollapsed(true)

local hopBusy = false
local hopStatus = "Ready to find a new public server"

local function httpGetJson(url)
    local body
    local requestFn
    if type(request) == "function" then
        requestFn = request
    elseif type(http_request) == "function" then
        requestFn = http_request
    elseif type(syn) == "table" and type(syn.request) == "function" then
        requestFn = syn.request
    end

    if requestFn then
        local ok, response = pcall(requestFn, {Url = url, Method = "GET"})
        if ok and type(response) == "table" then
            local statusCode = tonumber(response.StatusCode or response.Status or 200)
            if statusCode and statusCode >= 200 and statusCode < 300 then
                body = response.Body or response.body
            end
        end
    end
    if type(body) ~= "string" or body == "" then
        local ok, response = pcall(function() return game:HttpGet(url) end)
        if ok and type(response) == "string" then body = response end
    end
    if type(body) ~= "string" or body == "" then
        error("HTTP request unavailable in this executor")
    end
    return HttpService:JSONDecode(body)
end

local function findHopServer()
    -- Roblox's public-server endpoint only sorts by player count (Asc/Desc).
    -- Sample both ends of the list, deduplicate, then choose uniformly at random.
    local candidates = {}
    local seen = {}
    local sortOrders = {"Asc", "Desc"}
    for _, sortOrder in ipairs(sortOrders) do
        local cursor = nil
        -- Sample more of both ends; never stop after a few low-population servers.
        for page = 1, 8 do
            local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
                .. "/servers/Public?sortOrder=" .. sortOrder .. "&limit=100&excludeFullGames=true"
            if cursor and cursor ~= "" then
                url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
            end
            local payload = httpGetJson(url)
            for _, server in ipairs(payload.data or {}) do
                local serverId = tostring(server.id or "")
                local playing = tonumber(server.playing) or 0
                local maximum = tonumber(server.maxPlayers) or 0
                if serverId ~= "" and serverId ~= game.JobId
                    and not seen[serverId] and playing < maximum and maximum > 0 then
                    seen[serverId] = true
                    table.insert(candidates, server)
                end
            end
            cursor = payload.nextPageCursor
            if not cursor or cursor == "" then break end
        end
    end
    if #candidates == 0 then
        error("No available public servers found")
    end
    local rng = Random.new()
    return candidates[rng:NextInteger(1, #candidates)]
end

TeleportService.TeleportInitFailed:Connect(function(failedPlayer, teleportResult, errorMessage)
    if failedPlayer ~= player then return end
    hopStatus = "Teleport failed: " .. tostring(teleportResult) .. " / " .. tostring(errorMessage)
    hopButton.Text = "↻   TRY AGAIN"
    hopBusy = false
end)

hopButton.Activated:Connect(function()
    if hopBusy then return end
    hopBusy = true
    hopButton.Text = "◌   SEARCHING SERVERS..."
    hopButton.BackgroundColor3 = Color3.fromRGB(82, 43, 53)
    hopStatus = "Searching public servers..."
    task.spawn(function()
        local ok, result = pcall(function()
            local server = findHopServer()
            hopStatus = "Found server • " .. tostring(server.playing) .. "/" .. tostring(server.maxPlayers)
            hopButton.Text = "↗   TELEPORTING..."
            TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, player)
            return server.id
        end)
        if not ok then
            hopStatus = "Hop failed: " .. tostring(result)
            hopButton.Text = "↻   TRY AGAIN"
            hopBusy = false
            warn("[Supreme Trade Checker] Hop server failed: " .. tostring(result))
        end
    end)
end)

hopButton.MouseButton1Down:Connect(function()
    TweenService:Create(hopButton, TweenInfo.new(0.09), {Size = UDim2.new(1, -24, 0, 32)}):Play()
end)
hopButton.MouseButton1Up:Connect(function()
    TweenService:Create(hopButton, TweenInfo.new(0.12, Enum.EasingStyle.Back), {Size = UDim2.new(1, -20, 0, 34)}):Play()
end)

local function copyText(text)
    local methods = {
        {"setclipboard", setclipboard},
        {"toclipboard", toclipboard},
        {"setrbxclipboard", setrbxclipboard}
    }
    for _, entry in ipairs(methods) do
        local method = entry[2]
        if type(method) == "function" then
            local ok, result = pcall(method, text)
            if ok and result ~= false then return true end
        end
    end
    if type(Clipboard) == "table" and type(Clipboard.set) == "function" then
        local ok, result = pcall(Clipboard.set, text)
        if ok and result ~= false then return true end
    end
    return false
end

local function formatUnmatchedItems(items)
    local rows = {}
    for _, entry in pairs(items or {}) do
        table.insert(rows, entry)
    end
    table.sort(rows, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return a.name < b.name
    end)
    local output = {}
    for index = 1, math.min(#rows, 25) do
        local entry = rows[index]
        table.insert(output, entry.name .. " [x" .. tostring(entry.count)
            .. ", icon=" .. tostring(entry.image)
            .. (entry.chroma and ", chroma" or "")
            .. ", DB-name={" .. tostring(entry.dbNameMatches or "not-scanned") .. "}"
            .. ", DB-icon={" .. tostring(entry.dbImageMatches or "not-scanned") .. "}]")
    end
    if #rows > 25 then
        table.insert(output, "... +" .. tostring(#rows - 25) .. " more unique items")
    end
    return #output > 0 and table.concat(output, " | ") or "none"
end

local function formatCoverageItems(items)
    local rows = {}
    local totals = {VALUED = 0, NO_VALUE = 0, TIER = 0, BELOW_MIN = 0}
    for _, entry in pairs(items or {}) do
        table.insert(rows, entry)
        totals[entry.status] = (totals[entry.status] or 0) + entry.count
    end
    table.sort(rows, function(a, b)
        local order = {NO_VALUE = 1, BELOW_MIN = 2, TIER = 3, VALUED = 4}
        if order[a.status] ~= order[b.status] then
            return order[a.status] < order[b.status]
        end
        return a.name < b.name
    end)
    local output = {}
    for _, entry in ipairs(rows) do
        table.insert(output, entry.name .. " [x" .. tostring(entry.count) .. "]="
            .. entry.status .. (entry.status == "VALUED" and " " or " ")
            .. tostring(entry.detail)
            .. (entry.chroma and " | CHROMA" or "")
            .. " | icon=" .. tostring(entry.image))
    end
    local summary = "VALUED=" .. tostring(totals.VALUED)
        .. ", NO_VALUE=" .. tostring(totals.NO_VALUE)
        .. ", TIER_ONLY=" .. tostring(totals.TIER)
        .. ", BELOW_0.1=" .. tostring(totals.BELOW_MIN)
        .. ", UNIQUE=" .. tostring(#rows)
    return summary .. (#output > 0 and "\n" .. table.concat(output, "\n") or "\nnone")
end

local function buildDiagnostic()
    local lines = {
        "SUPREME TRADE CHECKER — PULSEHUB MAPPING",
        "Time: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Status: " .. tostring(state.status),
        "Core self-tests: " .. tostring(state.selfTestStatus),
        "Load time: " .. string.format("%.2f", tonumber(state.loadDuration) or 0) .. "s",
        "Values source: " .. BASE,
        "Pages fetched: " .. tostring(state.pageCount) .. "/" .. tostring(#CATEGORIES),
        "Pages parsed: " .. tostring(state.parsedPages),
        "Supreme entries: " .. tostring(state.entryCount),
        "Supreme tier entries: " .. tostring(state.tierEntryCount or 0),
        "Value entries by category: " .. HttpService:JSONEncode(state.categoryCounts or {}),
        "Reference-page value cards (not mapped as single items): "
            .. HttpService:JSONEncode(state.referenceValueCounts or {}),
        "All page card counts: " .. HttpService:JSONEncode(state.categoryCardCounts or {}),
        "MM2 DB source: " .. tostring(state.source ~= "" and state.source or "not loaded"),
        "Local values cache: " .. tostring(state.cacheStatus or "not checked"),
        "MM2 weapon records: " .. tostring(state.dbItems),
        "MM2 pet records: " .. tostring(state.dbPets),
        "Matched item records: " .. tostring(state.mappedCount),
        "Icon mappings: " .. tostring(state.iconCount),
        "Fetch methods: " .. HttpService:JSONEncode(state.fetchMethods),
        "Failed pages: " .. (#state.failedPages > 0 and table.concat(state.failedPages, " | ") or "none"),
        "Last error: " .. tostring(state.lastError or "none"),
        "",
        "Hop server: " .. tostring(hopStatus),
        "",
        "CURRENT TRADE:",
        tostring(state.latestTrade),
        "",
        "CURRENT INVENTORY:",
        tostring(state.latestInventory),
        "INVENTORY VALUE COVERAGE (all visible item types):",
        formatCoverageItems(state.coverageInventory),
        "TRADE VALUE COVERAGE (all visible offered items):",
        formatCoverageItems(state.coverageTrade),
        "UNMATCHED INVENTORY (top 25): " .. formatUnmatchedItems(state.unmatchedInventory),
        "UNMATCHED TRADE (top 25): " .. formatUnmatchedItems(state.unmatchedTrade)
    }
    return table.concat(lines, "\n")
end

copyButton.Activated:Connect(function()
    local report = buildDiagnostic()
    copyButton.Text = copyText(report) and "COPIED — SEND THE TEXT" or "CLIPBOARD API UNAVAILABLE"
    task.delay(3, function()
        if copyButton and copyButton.Parent then
            copyButton.Text = "COPY FULL DIAGNOSTIC"
        end
    end)
end)

-- Drag the panel from its title bar (mouse or touchscreen).
local dragging, dragStart, panelStart = false, nil, nil
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        panelStart = panel.Position
        local connection
        connection = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                if connection then connection:Disconnect() end
            end
        end)
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragStart
        panel.Position = UDim2.new(
            panelStart.X.Scale, panelStart.X.Offset + delta.X,
            panelStart.Y.Scale, panelStart.Y.Offset + delta.Y
        )
    end
end)

local function updateUi()
    if state.status == "ok" then
        title.Text = collapsed and "SUPREME" or "SUPREME  /  READY"
    else
        title.Text = collapsed and "SUPREME" or "SUPREME  /  " .. string.upper(state.status)
    end
    output.Text = buildDiagnostic()
end

textGui.Destroying:Connect(function()
    stopped = true
end)

__bootStage("BOOT 06/06 — SCRIPT RUNNING", "Main panel created. Running self-tests...")
task.spawn(function()
    task.wait(0.25)
    local testsOk, testsError = pcall(runCoreSelfTests)
    coreTestsPassed = testsOk
    state.selfTestStatus = testsOk and "passed" or ("FAILED: " .. tostring(testsError))
    if testsOk then
        loadValues(true)
    else
        state.status = "fail"
        state.lastError = "Core self-tests failed: " .. tostring(testsError)
        warn("[Supreme Trade Checker] Core self-tests failed; values loading is blocked: " .. tostring(testsError))
    end
    local nextInventoryScan = 0
    while textGui.Parent and not stopped do
        pcall(scanTrade)
        if os.clock() >= nextInventoryScan then
            pcall(scanInventory)
            nextInventoryScan = os.clock() + 1.25
        end
        updateUi()
        if coreTestsPassed and state.status == "fail" and not state.busy then
            task.wait(20)
            loadValues(true)
        elseif coreTestsPassed and state.status == "ok"
            and os.clock() - state.updated >= 900 and not state.busy then
            loadValues(false)
        end
        task.wait(0.6)
    end
end)

print("[Supreme Trade Checker] PulseHub-style item mapping loaded.")

end

local __ok, __err = xpcall(__runSupremeChecker, function(err)
    local trace = tostring(err)
    pcall(function()
        if debug and debug.traceback then trace = debug.traceback(trace, 2) end
    end)
    return trace
end)
if not __ok then
    __bootFailure(__err)
    warn("[Supreme Trade Checker BOOT ERROR] " .. tostring(__err))
else
    task.delay(8, function()
        pcall(function()
            local parent = __bootGui and __bootGui.Parent
            local mainGui = parent and parent:FindFirstChild("SupremeTradeText")
            if mainGui then
                if __bootGui and __bootGui.Parent then __bootGui:Destroy() end
            else
                if __bootFrame then
                    __bootFrame.Size = UDim2.new(0, 310, 0, 170)
                    __bootFrame.Position = UDim2.new(0.5, -155, 0.5, -85)
                end
                __bootStage("BOOT WARNING — MAIN UI NOT FOUND",
                    "Lua finished without a runtime error, but SupremeTradeText is missing. Send this screen.")
            end
        end)
    end)
end
