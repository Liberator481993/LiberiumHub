-- MM2 Supreme Trade Checker
-- Inventory and trade value overlay adapted from the proven MM2 MM2 reader.
-- Informational only: never accepts, declines, sends, or modifies trades.
-- Value source: https://www.supremevalues.com/mm2/

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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
local RUST_MAPPING_URL = "https://raw.githubusercontent.com/Liberator481993/LiberiumHub/supreme-values-data/data/SupremeTradeChecker.mapping.json"

local state = {
    status = "loading",
    mapped = nil,
    supremeEntries = nil,
    updated = 0,
    loadDuration = 0,
    lastUpdate = "Not loaded",
    source = "",
    dataPipeline = "not loaded",
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
    inventoryGroups = 0,
    inventoryFrameProbe = "not scanned",
    inventoryKeyStats = "not scanned",
    inventoryGuiPath = "unknown",
    inventoryScreenList = "not scanned",
    busy = false,
    latestTrade = "No active trade detected.",
    latestInventory = "Inventory not scanned yet.",
    unmatchedInventory = {},
    unmatchedTrade = {}
}
local stopped = false
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

-- Supreme's origin text sometimes says "Valentines Event 2026", while
-- MM2's Database.Sync stores the matching Event as "Valentines".
-- Canonicalize only the trailing generic word "Event"; keep the actual
-- event name intact so unrelated seasonal items cannot cross-match.
local function normalizeEvent(value)
    -- Supreme uses singular "Valentine" while Database.Sync uses
    -- plural "Valentines". Normalize year/event suffixes and this known alias.
    local normalized = normalize(value)
    normalized = normalized:gsub("%d%d%d%d$", "")
    normalized = normalized:gsub("event$", "")
    if normalized == "valentine" then normalized = "valentines" end
    return normalized
end

-- Supreme Values contains fractional values for many low-tier items.
-- Keep up to four decimals instead of rounding each item to a whole number.
local function formatValue(value)
    local number = tonumber(value) or 0
    local formatted = string.format("%.4f", number)
        :gsub("0+$", "")
        :gsub("%.$", "")
    if formatted == "-0" or formatted == "" then return "0" end
    return formatted
end

local function assetId(value)
    local result
    for match in tostring(value or ""):gmatch("%d%d%d%d%d+") do
        result = match
    end
    return result
end

local function isImageNode(node)
    return node and (node:IsA("ImageLabel") or node:IsA("ImageButton"))
end

-- Item cards vary between desktop/mobile and trade/inventory screens.
-- Prefer Container.Icon, but support ImageLabels that are the item slot itself.
local function findTileIcon(tile)
    if not tile then return nil end

    local container = tile:FindFirstChild("Container")
    local icon = container and container:FindFirstChild("Icon", true)
    if isImageNode(icon) and assetId(icon.Image) then return icon end

    if isImageNode(tile) and assetId(tile.Image) then return tile end

    for _, preferredName in ipairs({"Icon", "ItemIcon", "ItemImage", "Image"}) do
        local candidate = tile:FindFirstChild(preferredName, true)
        if isImageNode(candidate) and assetId(candidate.Image) then
            return candidate
        end
    end

    for _, candidate in ipairs(tile:GetDescendants()) do
        if isImageNode(candidate) and assetId(candidate.Image) then
            return candidate
        end
    end
    return nil
end

local function hasChromaTag(tile)
    if not tile then return false end
    local tags = tile:FindFirstChild("Tags", true)
    local tag = tags and tags:FindFirstChild("Chroma", true)
    if not tag then tag = tile:FindFirstChild("Chroma", true) end
    return tag ~= nil and tag:IsA("GuiObject") and tag.Visible == true
end

local function fetchPage(url)
    local errors = {}
    -- Some Supreme category routes intermittently reject the clean route while
    -- the legacy .php route still serves the same page.
    local urls = {url}
    if not url:match("%.php$") then table.insert(urls, url .. ".php") end
    for _, targetUrl in ipairs(urls) do
        local function attempt(fn, label)
            if type(fn) ~= "function" then return nil end
            local headers = {
                ["User-Agent"] = "Mozilla/5.0",
                ["Accept"] = "text/html,application/xhtml+xml"
            }
            -- Delta and Arceus X expose slightly different request wrappers.
            -- Try the executor-style options table first, then URL-string form.
            local ok, response = pcall(fn, {
                Url = targetUrl, URL = targetUrl, url = targetUrl,
                Method = "GET", method = "GET", Headers = headers, headers = headers
            })
            if not ok or response == nil then
                ok, response = pcall(fn, targetUrl)
            end
            if not ok then
                table.insert(errors, label .. ": error")
                return nil
            end

            local statusCode
            if type(response) == "table" then
                statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
                response = response.Body or response.body or response.ResponseBody
            end
            if type(response) == "string" and #response > 1500
                and response:find("<html", 1, true)
                and (response:find("itemcolumn", 1, true)
                    or response:find("Supreme Values", 1, true))
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
            return game:HttpGet(targetUrl)
        end)
        if ok and type(gameBody) == "string" and #gameBody > 1500
            and gameBody:find("<html", 1, true)
            and (gameBody:find("itemcolumn", 1, true)
                or gameBody:find("Supreme Values", 1, true)) then
            return gameBody, "game:HttpGet"
        end
        table.insert(errors, "game:HttpGet: invalid/empty page")
        task.wait(0.2)
    end
    return nil, table.concat(errors, "; ")
end

-- Supreme Values item cards expose numeric or tier-based values as visible text.
-- Parse the displayed value first; data-value is only a numeric fallback.
local function parseNumber(raw)
    if raw == nil then return nil end
    local value = tonumber(tostring(raw):gsub(",", ""))
    if value == nil or value ~= value or value == math.huge or value == -math.huge then
        return nil
    end
    return value
end

local function numericParserSelfTest()
    local cases = {
        {"5,000", 5000},
        {"1,000,000", 1000000},
        {"0.25", 0.25},
        {"35", 35}
    }
    for _, case in ipairs(cases) do
        local actual = parseNumber(case[1])
        if actual == nil or math.abs(actual - case[2]) > 0.000001 then return false end
    end
    return true
end
state.numericParserStatus = numericParserSelfTest() and "passed" or "failed"

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
        -- Read the displayed value first: tier cards may carry data-value="0",
        -- which is a placeholder and must never become a numeric price.
        local amountText = cardText:match("Value%s*%-%s*([%d,%.]+)")
        local amount = parseNumber(amountText)
        local tierText = cardText:match("Value%s*%-%s*([x×]%d+%s+T%d+%s+[%a]+)")
        if not amount and not tierText then
            local dataAmount = parseNumber(card:match('data%-value="([%d%.]+)"'))
            if dataAmount and dataAmount > 0 then amount = dataAmount end
        end
        local nameMarkup = card:match('<div class="itemhead">(.-)</div>')
        local origin = decodeText(card:match('class="itemorigin">([^<]*)<') or "")
        local imageAlt = card:match('<img[^>]-alt="([^"]*)"')
            or card:match("<img[^>]-alt='([^']*)'")
        imageAlt = decodeText(imageAlt or "")
        local pageEvent = card:match('data%-event="([^"]+)"')
        if (amount or tierText) and nameMarkup and not origin:find("Deletion", 1, true) then
            local name = decodeText(nameMarkup)
            if name ~= "" then
                table.insert(output, {
                    c = category,
                    n = name,
                    im = imageAlt,
                    v = amount,
                    t = tierText,
                    y = card:match('data%-year="(%d%d%d%d)'),
                    e = pageEvent,
                    o = origin ~= "" and origin or nil,
                    cl = card:match("Class %- <b>([^<]+)</b>"),
                    dm = card:match('data%-demand="(%d+)"')
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

local function buildMapping(entries, database, rustIndexData)
    if type(database) ~= "table" or type(database.Item) ~= "table" then
        return nil, "invalid MM2 item database"
    end

    local weapons = database.Item
    local pets = type(database.Pets) == "table" and database.Pets or {}
    local index, petEntries = {}, {}
    local dbByName, dbByImage = {}, {}
    local dbIds = {}
    local supremeByName = {}
    local function addSupremeCandidate(key, value)
        if key == "" then return end
        supremeByName[key] = supremeByName[key] or {}
        table.insert(supremeByName[key], {
            category = tostring(value.c or ""),
            title = tostring(value.n or ""),
            imageAlt = tostring(value.im or ""),
            year = tostring(value.y or ""),
            event = tostring(value.e or ""),
            origin = tostring(value.o or ""),
            class = tostring(value.cl or ""),
            value = tostring(value.v or ""),
            tier = tostring(value.t or "")
        })
    end

    -- Prefer the indexes generated by Rust. This makes the same normalized
    -- keys that Rust validated available to the Luau matching/diagnostic layer.
    local usedRustIndexes = false
    if type(rustIndexData) == "table"
        and type(rustIndexData.by_name) == "table"
        and type(rustIndexData.by_image_alt) == "table" then
        usedRustIndexes = true
        for key, sourceIds in pairs(rustIndexData.by_name) do
            for _, sourceId in ipairs(sourceIds) do
                local value = entries[(tonumber(sourceId) or -1) + 1]
                if value then addSupremeCandidate(tostring(key), value) end
            end
        end
        for key, sourceIds in pairs(rustIndexData.by_image_alt) do
            for _, sourceId in ipairs(sourceIds) do
                local value = entries[(tonumber(sourceId) or -1) + 1]
                if value then addSupremeCandidate(tostring(key), value) end
            end
        end
    end
    if not usedRustIndexes then
        for _, value in ipairs(entries) do
            local key = normalize(value.n)
            addSupremeCandidate(key, value)
            local altKey = normalize(value.im)
            if altKey ~= key then addSupremeCandidate(altKey, value) end
        end
    end

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
                year = tostring(item.Year or tostring(id):match("(20%d%d)$") or ""),
                event = tostring(item.Event or ""),
                image = assetId(item.Image) or "",
                itemId = tostring(item.ItemID or "")
            })
        end
        local function addImageCandidate(image)
            if not image then return end
            dbByImage[image] = dbByImage[image] or {}
            table.insert(dbByImage[image], {
                id = tostring(id),
                kind = kind,
                name = tostring(item.ItemName or item.Name or ""),
                itemType = tostring(item.ItemType or ""),
                rarity = tostring(item.Rarity or ""),
                chroma = item.Chroma == true,
                year = tostring(item.Year or tostring(id):match("(20%d%d)$") or ""),
                event = tostring(item.Event or "")
            })
        end
        addImageCandidate(assetId(item.Image))
        -- Some MM2 GUI builds expose ItemID as the card image asset instead
        -- of Image; index both identifiers for the same database record.
        addImageCandidate(assetId(item.ItemID))
    end

    -- MM2 trophy skins are untradable leaderboard rewards. They may be
    -- identified either by a color prefix in ItemName or by a color suffix
    -- in the database key (for example VampireAxe_Gold). Require Unique
    -- rarity in both cases; ordinary tradeable items remain indexed.
    local TROPHY_PREFIXES = {"Gold", "Silver", "Bronze", "Red", "Blue", "Purple"}
    local TROPHY_KEY_SUFFIXES = {
        gold = true, silver = true, bronze = true,
        red = true, blue = true, purple = true
    }
    local function isTrophyRecord(item, recordKey)
        if type(item) ~= "table" or clean(item.Rarity) ~= "Unique" then return false end

        local keySuffix = tostring(recordKey or ""):match("_([^_]+)$")
        if keySuffix and TROPHY_KEY_SUFFIXES[keySuffix:lower()] then
            return true
        end

        local itemName = clean(item.ItemName or item.Name or "")
        for _, prefix in ipairs(TROPHY_PREFIXES) do
            if itemName:lower():sub(1, #prefix) == prefix:lower()
                and itemName:sub(#prefix + 1, #prefix + 1):match("[%s%-']") then
                return true
            end
        end
        return false
    end

    local function addIndex(name, entry)
        if name == "" then return end
        index[name] = index[name] or {}
        table.insert(index[name], entry)
    end

    for id, item in pairs(weapons) do
        dbIds[tostring(id)] = "Item"
        if type(item) ~= "table" then continue end
        local name = tostring(item.ItemName or item.Name or "")
        local entry = {kind = "i", id = tostring(id), item = item}
        addDiagnosticCandidate(item, id, "Item")
        if not isTrophyRecord(item, id) then
            addIndex(normalize(name), entry)
            local withoutYear = name:gsub("%s*%d%d%d%d%s*$", "")
            if withoutYear ~= name then addIndex(normalize(withoutYear), entry) end
        end
    end

    for id, item in pairs(pets) do
        dbIds[tostring(id)] = "Pet"
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
        -- MM2's Database.Sync sometimes stores the item name with its type
        -- suffix (for example "Swirly Gun"), while Supreme titles may be
        -- parsed into base name + kind ("Swirly", "Gun"). Keep both forms:
        -- the base form handles entries such as "Frozen (Gun)" -> "Frozen",
        -- and the typed form handles DB names such as "Swirly Gun".
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

        local function preferExactMetadata(field, wanted, normalizer)
            if not wanted or clean(wanted) == "" then return end
            normalizer = normalizer or normalize
            local exact, unknown = {}, {}
            for _, candidate in ipairs(matches) do
                local actual = clean(candidate.item[field])
                if actual == "" and field == "Year" then
                    actual = tostring(candidate.id):match("(20%d%d)$") or ""
                end
                if actual == "" then
                    table.insert(unknown, candidate)
                elseif normalizer(actual) == normalizer(wanted) then
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
        preferExactMetadata("Event", event, normalizeEvent)

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
                    category = category,
                    itemType = tostring(candidate.item.ItemType or ""),
                    year = tostring(candidate.item.Year or "")
                }
            end
        end
    end

    local icon, iconCandidates, chromaOf, byName, chromaKeys = {}, {}, {}, {}, {}
    local function addIcon(item, idKey)
        local image = assetId(item.Image)
        if image then
            iconCandidates[image] = iconCandidates[image] or {}
            table.insert(iconCandidates[image], idKey)
        end
    end

    for id, item in pairs(weapons) do
        if type(item) == "table" then
            local idKey = "i:" .. tostring(id)
            addIcon(item, idKey)
            if item.Chroma == true then chromaKeys[idKey] = true end
        end
    end
    for id, item in pairs(weapons) do
        if type(item) == "table" and not item.Chroma and item.ItemID then
            local imageId = tostring(item.ItemID)
            iconCandidates[imageId] = iconCandidates[imageId] or {}
            table.insert(iconCandidates[imageId], "i:" .. tostring(id))
        end
    end
    for id, item in pairs(pets) do
        if type(item) == "table" then
            local idKey = "p:" .. tostring(id)
            addIcon(item, idKey)
            if item.Chroma == true then chromaKeys[idKey] = true end
        end
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
            if type(item) == "table" and not item.Chroma then
                local regularKey = normalize(item[group.field])
                    .. (group.kind == "i" and "|" .. tostring(item.ItemType) or "")
                if not regular[regularKey] then
                    regular[regularKey] = group.kind .. ":" .. tostring(id)
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
                table.insert(byName[nameKey], {
                    key = idKey,
                    chroma = item.Chroma == true,
                    itemType = tostring(item.ItemType or ""),
                    year = tostring(item.Year or "")
                })
            end
        end
    end

    local iconCount = 0
    for _ in pairs(icon) do iconCount = iconCount + 1 end

    -- Full database coverage audit: every MM2 catalog record is recognized
    -- by its canonical key, whether or not Supreme publishes a value for it.
    local dbTotal, dbUnmapped, dbUnmappedSample = 0, 0, {}
    local dbUnmappedAll, dbUniqueUnmapped = {}, {}
    local dbNumericMapped, dbTierMapped, dbExcludedNoValue, dbExcludedTrophy = 0, 0, 0, 0
    -- These two built-in defaults have no Supreme value by design.
    -- They remain part of the MM2 database total but are not coverage failures.
    local intentionalNoValue = {DefaultGun = true, DefaultKnife = true}
    local function auditDatabase(items, kind, nameField)
        for id, item in pairs(items) do
            if type(item) ~= "table" then continue end
            dbTotal = dbTotal + 1
            local idText = tostring(id)
            local idKey = kind .. ":" .. idText
            local mappedEntry = byKey[idKey]
            if mappedEntry then
                if clean(mappedEntry.t) ~= "" then
                    dbTierMapped = dbTierMapped + 1
                elseif tonumber(mappedEntry.v) ~= nil then
                    dbNumericMapped = dbNumericMapped + 1
                end
            elseif kind == "i" and intentionalNoValue[idText] then
                dbExcludedNoValue = dbExcludedNoValue + 1
            elseif kind == "i" and isTrophyRecord(item, idText) then
                dbExcludedTrophy = dbExcludedTrophy + 1
            else
                dbUnmapped = dbUnmapped + 1
                local row = idText .. "=" .. tostring(item[nameField] or item.Name or "")
                    .. "{itemId=" .. tostring(item.ItemID or "none")
                    .. ",type=" .. tostring(item.ItemType or "Pet")
                    .. ",rarity=" .. tostring(item.Rarity or "none")
                    .. ",chroma=" .. tostring(item.Chroma == true)
                    .. ",year=" .. tostring(item.Year or idText:match("(20%d%d)$") or "none")
                    .. ",event=" .. tostring(item.Event or "none") .. "}"
                table.insert(dbUnmappedAll, row)
                if clean(item.Rarity) == "Unique" then
                    table.insert(dbUniqueUnmapped, row)
                end
                if #dbUnmappedSample < 40 then table.insert(dbUnmappedSample, row) end
            end
        end
    end
    auditDatabase(weapons, "i", "ItemName")
    auditDatabase(pets, "p", "Name")

    return {
        byKey = byKey,
        icon = icon,
        chromaOf = chromaOf,
        chromaKeys = chromaKeys,
        dbByName = dbByName,
        dbByImage = dbByImage,
        dbIds = dbIds,
        dbTotal = dbTotal,
        dbNumericMapped = dbNumericMapped,
        dbTierMapped = dbTierMapped,
        dbExcludedNoValue = dbExcludedNoValue,
        dbExcludedTrophy = dbExcludedTrophy,
        dbUnmapped = dbUnmapped,
        dbUnmappedSample = dbUnmappedSample,
        dbUnmappedAll = dbUnmappedAll,
        dbUniqueUnmapped = dbUniqueUnmapped,
        supremeByName = supremeByName,
        byName = byName,
        n = mappedCount,
        iconCount = iconCount,
        dbItems = (function() local n = 0; for _ in pairs(weapons) do n = n + 1 end; return n end)(),
        dbPets = (function() local n = 0; for _ in pairs(pets) do n = n + 1 end; return n end)()
    }
end

local function valueOf(tile, name)
    local mapped = state.mapped
    if not mapped or state.status ~= "ok" then return nil end

    local chroma = hasChromaTag(tile)
    local iconObject = findTileIcon(tile)
    local imageId = iconObject and assetId(iconObject.Image)
    local iconKey = imageId and mapped.icon[imageId]

    -- Prefer the exact, globally unique icon mapping, as PulseHub does.
    -- Never fall through from a known-but-unvalued record to another skin.
    if iconKey then
        if chroma and not (mapped.chromaKeys and mapped.chromaKeys[iconKey]) then
            iconKey = mapped.chromaOf[iconKey]
            if not iconKey then return nil end
        end
        local entry = mapped.byKey[iconKey]
        if entry then return entry.v, entry.name, entry.t, entry.category end
        return nil, nil, nil, nil, "NO VALUE"
    end

    -- Some MM2 skins share an image asset. In that case, intersect the icon
    -- candidates with the visible card name instead of choosing the first
    -- database entry (the unsafe behavior in the old PulseHub resolver).
    local displayName = clean(name)
    local explicitKind, explicitYear
    local base, suffix = displayName:match("^(.-)%s*%((%a+)%)%s*$")
    if base and (suffix == "Knife" or suffix == "Gun") then
        displayName, explicitKind = clean(base), suffix
    else
        base, suffix = displayName:match("^(.-)%s+(%a+)$")
        if base and (suffix == "Knife" or suffix == "Gun") then
            displayName, explicitKind = clean(base), suffix
        end
    end
    base, suffix = displayName:match("^(.-)%s*%((%d%d%d%d)%)%s*$")
    if base then displayName, explicitYear = clean(base), suffix end

    local normalizedName = normalize(displayName)
    local function eligible(candidate)
        if candidate.chroma ~= chroma then return false end
        if explicitKind and normalize(candidate.itemType) ~= normalize(explicitKind) then return false end
        if explicitYear and tostring(candidate.year or "") ~= explicitYear then return false end
        return true
    end
    local function mappedValue(candidate)
        local key = (candidate.kind == "Pet" and "p:" or "i:") .. candidate.id
        local entry = mapped.byKey[key]
        if entry then return entry.v, entry.name, entry.t, entry.category end
        return nil, nil, nil, nil, "NO VALUE"
    end

    if normalizedName ~= "" then
        local nameCandidates = mapped.dbByName[normalizedName] or {}
        local imageCandidates = imageId and mapped.dbByImage and mapped.dbByImage[imageId] or nil

        if imageCandidates and #imageCandidates > 0 then
            local nameSet, matches = {}, {}
            for _, candidate in ipairs(nameCandidates) do
                if eligible(candidate) then
                    nameSet[candidate.kind .. ":" .. candidate.id] = true
                end
            end
            for _, candidate in ipairs(imageCandidates) do
                local key = candidate.kind .. ":" .. candidate.id
                if nameSet[key] and eligible(candidate) then
                    matches[key] = candidate
                end
            end
            local only, count = nil, 0
            for _, candidate in pairs(matches) do only, count = candidate, count + 1 end
            if count == 1 then return mappedValue(only) end
        end

        -- Name-only fallback is allowed only when the complete MM2 database
        -- leaves one candidate after Chroma/type/year filters.
        local matches = {}
        for _, candidate in ipairs(nameCandidates) do
            if eligible(candidate) then table.insert(matches, candidate) end
        end
        if #matches == 1 then return mappedValue(matches[1]) end
    end
    return nil
end

local function fetchRustMapping()
    local errors = {}
    local function acceptBody(body, method)
        if type(body) ~= "string" or #body < 1000 then
            table.insert(errors, method .. ": empty mapping response")
            return nil
        end
        local ok, decoded = pcall(function()
            return HttpService:JSONDecode(body)
        end)
        if not ok or type(decoded) ~= "table" then
            table.insert(errors, method .. ": invalid JSON")
            return nil
        end
        if tonumber(decoded.schema_version) ~= 1
            or type(decoded.entries) ~= "table"
            or #decoded.entries < 300
            or type(decoded.by_name) ~= "table"
            or type(decoded.by_image_alt) ~= "table" then
            table.insert(errors, method .. ": unsupported schema or incomplete mapping")
            return nil
        end
        local generated = tonumber(decoded.generated_at_unix)
        if generated and os.time() - generated > 7 * 24 * 60 * 60 then
            table.insert(errors, method .. ": mapping is older than 7 days")
            return nil
        end
        return decoded
    end

    local function attempt(fn, method)
        if type(fn) ~= "function" then return nil end
        local headers = {
            ["User-Agent"] = "Mozilla/5.0",
            ["Accept"] = "application/json"
        }
        -- Support both common executor request signatures (options table / URL string).
        local ok, response = pcall(fn, {
            Url = RUST_MAPPING_URL, URL = RUST_MAPPING_URL, url = RUST_MAPPING_URL,
            Method = "GET", method = "GET", Headers = headers, headers = headers
        })
        if not ok or response == nil then
            ok, response = pcall(fn, RUST_MAPPING_URL)
        end
        if not ok then
            table.insert(errors, method .. ": request error")
            return nil
        end
        local statusCode
        if type(response) == "table" then
            statusCode = tonumber(response.StatusCode or response.Status or response.status_code)
            response = response.Body or response.body or response.ResponseBody
        end
        if statusCode and (statusCode < 200 or statusCode >= 300) then
            table.insert(errors, method .. ": HTTP " .. tostring(statusCode))
            return nil
        end
        return acceptBody(response, method)
    end

    local mapping = attempt(request, "request")
    if mapping then return mapping, "Rust Core JSON / request" end
    mapping = attempt(http_request, "http_request")
    if mapping then return mapping, "Rust Core JSON / http_request" end
    local synRequest = type(syn) == "table" and syn.request or nil
    mapping = attempt(synRequest, "syn.request")
    if mapping then return mapping, "Rust Core JSON / syn.request" end
    local httpRequest = type(http) == "table" and http.request or nil
    mapping = attempt(httpRequest, "http.request")
    if mapping then return mapping, "Rust Core JSON / http.request" end

    local ok, body = pcall(function()
        return game:HttpGet(RUST_MAPPING_URL)
    end)
    if ok then
        mapping = acceptBody(body, "game:HttpGet")
        if mapping then return mapping, "Rust Core JSON / game:HttpGet" end
    else
        table.insert(errors, "game:HttpGet: request error")
    end
    return nil, table.concat(errors, "; ")
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
            local rustPayload, rustMethod = fetchRustMapping()
            local pageCount, parsedPages, entryCount, tierEntryCount = 0, 0, 0, 0
            local failed, methods = {}, {}
            local categoryCounts, referenceValueCounts, categoryCardCounts = {}, {}, {}
            local requiredPageCount = 0

            if rustPayload then
                -- Rust fetches and parses all Supreme categories, validates
                -- minimum page counts, and publishes this immutable snapshot.
                entries = rustPayload.entries
                entryCount = #entries
                pageCount = #CATEGORIES
                parsedPages = #CATEGORIES
                categoryCounts = type(rustPayload.category_counts) == "table"
                    and rustPayload.category_counts or {}
                categoryCardCounts = type(rustPayload.page_card_counts) == "table"
                    and rustPayload.page_card_counts or {}
                methods[rustMethod] = 1
                for _, entry in ipairs(entries) do
                    if clean(entry.t) ~= "" then tierEntryCount = tierEntryCount + 1 end
                end
                requiredPageCount = 0
                state.dataPipeline = "Rust Core snapshot (" .. rustMethod .. ")"
            else
                -- Offline/availability fallback: preserve the prior in-game
                -- scraper so the checker still works if GitHub JSON is down.
                state.dataPipeline = "Luau fallback scraper; Rust JSON unavailable: "
                    .. tostring(rustMethod)
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
                        if VALUE_CATEGORIES[category] then
                            table.insert(failed, category .. ": " .. tostring(fetchInfo or "request cancelled"))
                        end
                    else
                        pageCount = pageCount + 1
                        if VALUE_CATEGORIES[category] then requiredPageCount = requiredPageCount + 1 end
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

                if #failed > 0 then
                    error("Supreme value pages incomplete; refusing to publish partial values")
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

            state.supremeEntries = entries
            local database, dbSource = loadGameDatabase()
            if not database then error(dbSource) end
            local mapping, mapError = buildMapping(entries, database, rustPayload)
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
            state.source = dbSource
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
    -- Inventory and trade cards are not identical across MM2 desktop/mobile
    -- layouts; ItemName and Amount can be nested one or more levels down.
    local nameNode = tile:FindFirstChild("ItemName", true)
    local label = nameNode and (nameNode:FindFirstChild("Label", true) or nameNode)
    local name = label and (label:IsA("TextLabel") or label:IsA("TextButton")) and clean(label.Text) or ""
    if name == "" or name:find("^Loading") then name = nil end

    local container = tile:FindFirstChild("Container", true)
    local amountNode = container and container:FindFirstChild("Amount", true)
    if not amountNode then amountNode = tile:FindFirstChild("Amount", true) end
    local quantity = 1
    if amountNode and (amountNode:IsA("TextLabel") or amountNode:IsA("TextButton")) then
        quantity = tonumber(tostring(amountNode.Text):match("%d+")) or 1
    end
    return name, quantity, label
end

local function recordUnmatched(tile, name, quantity, target)
    if type(target) ~= "table" then return end
    local iconObject = findTileIcon(tile)
    local imageId = iconObject and assetId(iconObject.Image) or "no-icon"
    local chroma = hasChromaTag(tile)
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
        local supremeCandidates = mapped and mapped.supremeByName
            and mapped.supremeByName[normalize(itemName)] or {}
        local supremeSummary = {}
        for index = 1, math.min(#supremeCandidates, 6) do
            local candidate = supremeCandidates[index]
            table.insert(supremeSummary, candidate.category .. ":" .. candidate.title
                .. "{alt=" .. candidate.imageAlt
                .. ",year=" .. candidate.year
                .. ",event=" .. candidate.event
                .. ",origin=" .. candidate.origin
                .. ",class=" .. candidate.class
                .. ",value=" .. candidate.value
                .. (candidate.tier ~= "" and ",tier=" .. candidate.tier or "")
                .. "}")
        end
        entry.supremeMatches = #supremeSummary > 0
            and table.concat(supremeSummary, "; ") or "none"
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
        label.BackgroundTransparency = 1
        label.BorderSizePixel = 0
        label.TextColor3 = Color3.fromRGB(255, 255, 255)
        label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
        label.TextStrokeTransparency = 0.18
        label.TextXAlignment = Enum.TextXAlignment.Right
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Font = Enum.Font.GothamBold
        label.TextSize = 12
        label.ZIndex = 90
        label.Parent = parent
    end
    -- Remove decorations left behind by older versions: values are plain text,
    -- never dark pills, gradients, rounded boxes, or colored borders.
    for _, child in ipairs(label:GetChildren()) do
        if child:IsA("UICorner") or child:IsA("UIStroke") or child:IsA("UIGradient") then
            child:Destroy()
        end
    end
    label:SetAttribute("SupremeOwner", group)
    return label
end

local VALUE_TEXT_COLORS = {
    uniques = Color3.fromRGB(255, 220, 150), godlies = Color3.fromRGB(220, 190, 255),
    chromas = Color3.fromRGB(255, 190, 235), ancients = Color3.fromRGB(255, 185, 190),
    vintages = Color3.fromRGB(255, 210, 170), legendaries = Color3.fromRGB(255, 210, 175),
    rares = Color3.fromRGB(190, 245, 220), uncommons = Color3.fromRGB(190, 220, 255),
    commons = Color3.fromRGB(245, 245, 245), pets = Color3.fromRGB(190, 240, 235),
    misc = Color3.fromRGB(220, 220, 225)
}

local function updateTileBadge(tile, value, quantity, group, tierText, category, itemName, statusText)
    if not tile or not tile:IsA("GuiObject") then return end

    local existing = tile:FindFirstChild("__SupremeItemValue")
    local hasTier = type(tierText) == "string" and tierText ~= ""
    if value == nil and not hasTier and not statusText then
        if existing and existing:IsA("TextLabel") then existing.Visible = false end
        return
    end

    local label = makeLabel(tile, "__SupremeItemValue", group)
    local accent = statusText and value == nil and not hasTier
        and Color3.fromRGB(170, 180, 195)
        or (hasTier and Color3.fromRGB(255, 225, 165)
        or VALUE_TEXT_COLORS[category] or Color3.fromRGB(255, 255, 255))
    if normalize(itemName) == "emberbow" and value ~= nil then
        accent = Color3.fromRGB(255, 175, 175)
    end

    local badgeText = value ~= nil and formatValue(value) or (hasTier and tostring(tierText) or tostring(statusText))
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBold
    label.Text = badgeText
    label.TextColor3 = accent
    label.TextWrapped = false
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextScaled = false
    label.TextSize = hasTier and 10 or 12
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextXAlignment = Enum.TextXAlignment.Right
    label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
    label.TextStrokeTransparency = 0.12
    label.AnchorPoint = Vector2.new(1, 0)
    label.Position = UDim2.new(1, -7, 0, 5)
    label.Size = UDim2.fromOffset(math.max(38, math.min(132, #badgeText * 6 + 8)), 16)

    local highestZ = tile.ZIndex
    for _, descendant in ipairs(tile:GetDescendants()) do
        if descendant:IsA("GuiObject") and descendant ~= label and descendant.Visible then
            highestZ = math.max(highestZ, descendant.ZIndex)
        end
    end
    label.ZIndex = math.min(1000, highestZ + 2)
    label.Visible = true
end

local function scanRoot(root, group)
    local total, known, count, tierCount = 0, 0, 0, 0
    if not root then return total, known, count, tierCount end

    for _, tile in ipairs(getTiles(root)) do
        if not tile.Parent or tile.Visible == false then continue end
        local name, quantity = itemData(tile)
        local value, _, tierText, category, resolveStatus = valueOf(tile, name)
        if value ~= nil then
            total = total + value * quantity
            known = known + quantity
        elseif tierText then
            known = known + quantity
            tierCount = tierCount + quantity
        end
        count = count + quantity
        if value == nil and not tierText and not resolveStatus and group == "inventory" then
            recordUnmatched(tile, name, quantity, state.unmatchedInventory)
        end
        updateTileBadge(tile, value, quantity, group, tierText, category, name, resolveStatus)
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
                local icon = container and container:FindFirstChild("Icon", true)
                if isImageNode(icon) and assetId(icon.Image) then
                    return current
                end

                -- Trade/inventory slots such as NewItem1 can be the image node.
                if current.Name:match("^NewItem%d+$") and findTileIcon(current) then
                    return current
                end

                local hasName = current:FindFirstChild("ItemName", true) ~= nil
                if hasName and findTileIcon(current) then
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
        -- Cards with an ItemName node were handled by scanRoot, even while
        -- the text is temporarily blank or still says Loading.
        if card:FindFirstChild("ItemName", true) then continue end
        local value, _, tierText, category, resolveStatus = valueOf(card, name)
        if value == nil and not tierText then
            local amountContainer = card:FindFirstChild("Container", true)
            local amountNode = amountContainer and amountContainer:FindFirstChild("Amount", true)
            if not amountNode then amountNode = card:FindFirstChild("Amount", true) end
            local rawAmount = amountNode and tonumber(tostring(amountNode.Text):match("%d+"))
            quantity = rawAmount or quantity
        end
        if value ~= nil then
            total = total + value * quantity
            known = known + quantity
        elseif tierText then
            known = known + quantity
            tierCount = tierCount + quantity
        end
        count = count + quantity
        if value == nil and not tierText and not resolveStatus and group == "inventory" then
            recordUnmatched(card, name, quantity, state.unmatchedInventory)
        end
        updateTileBadge(card, value, quantity, group, tierText, category, name, resolveStatus)
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
            if (yourOffer and visible(yourOffer)) or (theirOffer and visible(theirOffer)) then
                return screen, container or screen, screen
            end
        end
    end
    return nil
end

local function scanOffer(offer, group)
    if not offer or not visible(offer) then return {}, 0, 0, 0, 0 end
    local container = offer:FindFirstChild("Container")
    if not container then return {}, 0, 0, 0, 0 end

    local items, total, known, count, tierCount = {}, 0, 0, 0, 0
    local seen = {}
    -- Normal MM2 cards own Container.Icon. In the compact offer layout,
    -- NewItem1..NewItem3 may be the ImageLabel/ImageButton themselves.
    for _, tile in ipairs(container:GetDescendants()) do
        if not tile:IsA("GuiObject") or not visible(tile) or seen[tile] then continue end

        local cardContainer = tile:FindFirstChild("Container")
        local normalCard = cardContainer and findTileIcon(tile) ~= nil
        local directSlot = tile.Name:match("^NewItem%d+$") ~= nil
            and findTileIcon(tile) ~= nil

        if normalCard or directSlot then
            seen[tile] = true
            local name, quantity = itemData(tile)
            local value, resolvedName, tierText, category, resolveStatus = valueOf(tile, name)

            table.insert(items, {
                name = resolvedName or name or "Unknown item",
                value = value,
                tier = tierText,
                quantity = quantity
            })
            count = count + quantity
            if value ~= nil then
                total = total + value * quantity
                known = known + quantity
            elseif tierText then
                known = known + quantity
                tierCount = tierCount + quantity
            end
            if value == nil and not tierText and not resolveStatus then
                recordUnmatched(tile, name, quantity, state.unmatchedTrade)
            end
            updateTileBadge(tile, value, quantity, group, tierText, category, name, resolveStatus)
        end
    end
    return items, total, known, count, tierCount
end

local function setSummary(parent, name, title, total, known, count, group, tierCount, tierText)
    if not parent then return end
    local label = makeLabel(parent, name, group)
    local accent = title == "YOU"
        and Color3.fromRGB(77, 224, 191)
        or Color3.fromRGB(177, 139, 255)

    -- Keep the offer total in the header strip, never over the item thumbnails.
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, 30)
    label.Size = UDim2.fromOffset(210, 20)
    label.BackgroundColor3 = Color3.fromRGB(11, 15, 27)
    label.BackgroundTransparency = 0.22
    label.BorderSizePixel = 0
    label.TextSize = (tierCount or 0) > 0 and 9 or 11
    label.TextScaled = false
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.Font = Enum.Font.GothamBlack
    label.TextStrokeColor3 = Color3.fromRGB(3, 5, 10)
    label.TextStrokeTransparency = 0.55
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextColor3 = accent
    label.ZIndex = 150

    local corner = label:FindFirstChildOfClass("UICorner")
    if not corner then
        corner = Instance.new("UICorner")
        corner.Parent = label
    end
    corner.CornerRadius = UDim.new(0, 7)

    local stroke = label:FindFirstChild("SupremeStroke")
    if not stroke or not stroke:IsA("UIStroke") then
        if stroke then stroke:Destroy() end
        stroke = Instance.new("UIStroke")
        stroke.Name = "SupremeStroke"
        stroke.Parent = label
    end
    stroke.Color = accent
    stroke.Thickness = 1
    stroke.Transparency = 0.3

    local gradient = label:FindFirstChild("SupremeGradient")
    if not gradient or not gradient:IsA("UIGradient") then
        if gradient then gradient:Destroy() end
        gradient = Instance.new("UIGradient")
        gradient.Name = "SupremeGradient"
        gradient.Parent = label
    end
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new(
        Color3.fromRGB(37, 43, 61),
        Color3.fromRGB(10, 13, 23)
    )

    local tierSuffix = (tierCount or 0) > 0 and tierText and tierText ~= "none"
        and ("  |  " .. tierText) or ""
    label.Text = title .. "  " .. formatValue(total)
        .. tierSuffix
        .. (known < count and "  +?" or "")
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

-- A tier expression is a quantity of a specific target class/tier, not a
-- universal numeric price. Only compare offers when both sides use the same
-- exact unit set (for example, T1 Commons on both sides).
local function parseTierUnit(tierText)
    local multiplier, tier, class = clean(tierText):match("^[x×](%d+)%s+(T%d+)%s+([%a]+)$")
    if not multiplier or not tier or not class then return nil, nil end
    -- Supreme's card text is not perfectly consistent about singular/plural
    -- class names (for example, "T1 Rare" and "T1 Rares").
    local classAliases = {
        common = "Commons", commons = "Commons",
        rare = "Rares", rares = "Rares",
        uncommon = "Uncommons", uncommons = "Uncommons",
        legendary = "Legendaries", legendaries = "Legendaries",
        ancient = "Ancients", ancients = "Ancients",
        godly = "Godlies", godlies = "Godlies",
        vintage = "Vintages", vintages = "Vintages",
        unique = "Uniques", uniques = "Uniques",
        pet = "Pets", pets = "Pets"
    }
    class = classAliases[string.lower(class)] or class
    return tonumber(multiplier), tier .. " " .. class
end

local function summarizeTierOffer(items)
    local units, hasTier, hasNumeric, hasUnknown = {}, false, false, false
    for _, item in ipairs(items or {}) do
        local quantity = math.max(1, math.floor(tonumber(item.quantity) or 1))
        if tonumber(item.value) ~= nil then
            hasNumeric = true
        elseif type(item.tier) == "string" and item.tier ~= "" then
            local multiplier, unit = parseTierUnit(item.tier)
            if multiplier and unit then
                units[unit] = (units[unit] or 0) + multiplier * quantity
                hasTier = true
            else
                hasUnknown = true
            end
        else
            hasUnknown = true
        end
    end
    return units, hasTier, hasNumeric, hasUnknown
end

local function formatTierUnits(units)
    local keys = {}
    for key in pairs(units or {}) do table.insert(keys, key) end
    table.sort(keys)
    local rows = {}
    for _, key in ipairs(keys) do
        table.insert(rows, tostring(units[key]) .. " " .. key)
    end
    return #rows > 0 and table.concat(rows, " + ") or "none"
end

local function compareTierOffers(yourItems, theirItems)
    local yours, yourTier, yourNumeric, yourUnknown = summarizeTierOffer(yourItems)
    local theirs, theirTier, theirNumeric, theirUnknown = summarizeTierOffer(theirItems)
    local yourText, theirText = formatTierUnits(yours), formatTierUnits(theirs)

    if yourUnknown or theirUnknown then
        return "CHECK UNKNOWN", "At least one item has no resolved value", yourText, theirText
    end
    if yourNumeric or theirNumeric then
        return "MIXED VALUES", "Numeric values and tier units cannot be added safely", yourText, theirText
    end
    if not yourTier or not theirTier then
        return "NO TIER DATA", "Both offers need recognized tier values", yourText, theirText
    end

    local keys = {}
    for key in pairs(yours) do keys[key] = true end
    for key in pairs(theirs) do keys[key] = true end
    for key in pairs(keys) do
        if yours[key] == nil or theirs[key] == nil then
            return "UNCOMPARABLE", "The offers use different tier units", yourText, theirText
        end
    end

    local receivedMore, receivedLess = false, false
    for key in pairs(keys) do
        if theirs[key] > yours[key] then receivedMore = true end
        if theirs[key] < yours[key] then receivedLess = true end
    end
    if receivedMore and receivedLess then
        return "MIXED", "One side gains in some tier units and loses in others", yourText, theirText
    elseif receivedMore then
        return "WIN", "The received offer has more of every comparable tier unit", yourText, theirText
    elseif receivedLess then
        return "LOSE", "The received offer has less of every comparable tier unit", yourText, theirText
    end
    return "FAIR", "Both offers have equal comparable tier units", yourText, theirText
end

local function runTierSelfTests()
    local function item(tier, quantity)
        return {tier = tier, quantity = quantity or 1}
    end
    local cases = {
        {name = "win", yours = {item("x2 T1 Commons")}, theirs = {item("x3 T1 Commons")}, expected = "WIN"},
        {name = "lose", yours = {item("x3 T1 Commons")}, theirs = {item("x2 T1 Commons")}, expected = "LOSE"},
        {name = "fair", yours = {item("x2 T1 Commons")}, theirs = {item("x2 T1 Commons")}, expected = "FAIR"},
        {name = "different units", yours = {item("x2 T1 Commons")}, theirs = {item("x2 T1 Rares")}, expected = "UNCOMPARABLE"},
        {name = "mixed directions", yours = {item("x1 T1 Commons"), item("x3 T1 Rares")}, theirs = {item("x2 T1 Commons"), item("x2 T1 Rares")}, expected = "MIXED"},
        {name = "duplicate quantity", yours = {item("x2 T1 Commons", 2)}, theirs = {item("x3 T1 Commons")}, expected = "LOSE"},
        {name = "singular/plural alias", yours = {item("x2 T1 Rare")}, theirs = {item("x2 T1 Rares")}, expected = "FAIR"},
        {name = "tier vs numeric", yours = {{value = 10}}, theirs = {item("x2 T1 Commons")}, expected = "MIXED VALUES"},
        {name = "unknown item blocks tier verdict", yours = {item("x2 T1 Commons")}, theirs = {{name = "unknown"}}, expected = "CHECK UNKNOWN"}
    }
    for _, case in ipairs(cases) do
        local result = compareTierOffers(case.yours, case.theirs)
        if result ~= case.expected then
            return "FAIL (" .. case.name .. ": expected " .. case.expected .. ", got " .. tostring(result) .. ")"
        end
    end
    return "PASS (" .. tostring(#cases) .. " cases)"
end

local TIER_SELF_TEST = runTierSelfTests()

local function setTradeVerdict(trade, yourTotal, theirTotal, yourKnown, theirKnown, yourCount, theirCount, yourTierCount, theirTierCount, yourItems, theirItems)
    if not trade then return end
    local label = makeLabel(trade, "__SupremeTradeVerdict", "trade")
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 1, -35)
    label.Size = UDim2.fromOffset(245, 25)
    label.BackgroundColor3 = Color3.fromRGB(11, 15, 27)
    label.BackgroundTransparency = 0.1
    label.BorderSizePixel = 0
    label.ZIndex = 150
    label.Font = Enum.Font.GothamBlack
    label.TextSize = 16
    label.TextScaled = true
    label.TextWrapped = false
    label.TextStrokeColor3 = Color3.fromRGB(4, 6, 10)
    label.TextStrokeTransparency = 0.12
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextYAlignment = Enum.TextYAlignment.Center

    local verdict, difference, caption, color
    if yourCount == 0 or theirCount == 0 then
        caption, color = "WAITING", Color3.fromRGB(225, 232, 245)
    elseif yourKnown < yourCount or theirKnown < theirCount then
        caption, color = "NUMERIC VALUES NEEDED", Color3.fromRGB(255, 190, 65)
    elseif yourTierCount > 0 or theirTierCount > 0 then
        -- Compare tier units only against the same tier units on the other
        -- side. Tier quantities are not converted into numeric market prices.
        local tierVerdict, _, yourTierText, theirTierText =
            compareTierOffers(yourItems, theirItems)
        caption = "TIER " .. tierVerdict .. "  |  " .. yourTierText .. " → " .. theirTierText
        color = (tierVerdict == "WIN" and Color3.fromRGB(45, 255, 135))
            or (tierVerdict == "LOSE" and Color3.fromRGB(255, 65, 85))
            or (tierVerdict == "FAIR" and Color3.fromRGB(75, 195, 255))
            or Color3.fromRGB(255, 190, 65)
    else
        verdict, difference = getVerdict(yourTotal, theirTotal)
        local sign = difference > 0 and "+" or ""
        caption = verdict .. "  " .. sign .. formatValue(difference)
        color = verdict == "WIN" and Color3.fromRGB(45, 255, 135)
            or verdict == "LOSE" and Color3.fromRGB(255, 65, 85)
            or Color3.fromRGB(75, 195, 255)
    end

    local gradient = label:FindFirstChild("SupremeTextGradient")
    if gradient then gradient:Destroy() end
    label.TextColor3 = color
    label.Text = caption
    label.TextSize = 14
    label.TextScaled = true

    local corner = label:FindFirstChildOfClass("UICorner")
    if not corner then
        corner = Instance.new("UICorner")
        corner.Parent = label
    end
    corner.CornerRadius = UDim.new(0, 8)

    local stroke = label:FindFirstChild("SupremeStroke")
    if not stroke or not stroke:IsA("UIStroke") then
        if stroke then stroke:Destroy() end
        stroke = Instance.new("UIStroke")
        stroke.Name = "SupremeStroke"
        stroke.Parent = label
    end
    stroke.Color = color
    stroke.Thickness = 1.15
    stroke.Transparency = 0.2

    local gradient = label:FindFirstChild("SupremeGradient")
    if not gradient or not gradient:IsA("UIGradient") then
        if gradient then gradient:Destroy() end
        gradient = Instance.new("UIGradient")
        gradient.Name = "SupremeGradient"
        gradient.Parent = label
    end
    gradient.Rotation = 90
    gradient.Color = ColorSequence.new(
        Color3.fromRGB(37, 43, 61),
        Color3.fromRGB(10, 13, 23)
    )
    label.Visible = true
end

local lastTradeRoot
local function clearTradeLabels(root)
    if not root then return end
    for _, node in ipairs(root:GetDescendants()) do
        if node.Name == "__SupremeOfferTotal" or node.Name == "__SupremeTradeVerdict" then
            node:Destroy()
        end
    end
end

local function scanTrade()
    state.unmatchedTrade = {}
    local screen, container, trade = findTrade()
    if not screen then
        clearTradeLabels(lastTradeRoot)
        lastTradeRoot = nil
        state.latestTrade = "No active trade detected."
        return nil
    end
    if lastTradeRoot and lastTradeRoot ~= trade then
        clearTradeLabels(lastTradeRoot)
    end
    lastTradeRoot = trade

    local yours = trade:FindFirstChild("YourOffer", true)
    local theirs = trade:FindFirstChild("TheirOffer", true)
    if not yours and container then yours = container:FindFirstChild("YourOffer", true) end
    if not theirs and container then theirs = container:FindFirstChild("TheirOffer", true) end

    local yourItems, yourTotal, yourKnown, yourCount, yourTierCount = scanOffer(yours, "trade")
    local theirItems, theirTotal, theirKnown, theirCount, theirTierCount = scanOffer(theirs, "trade")
    local yourTierUnits = summarizeTierOffer(yourItems)
    local theirTierUnits = summarizeTierOffer(theirItems)
    local yourTierText = formatTierUnits(yourTierUnits)
    local theirTierText = formatTierUnits(theirTierUnits)
    setSummary(yours, "__SupremeOfferTotal", "YOU", yourTotal, yourKnown, yourCount,
        "trade", yourTierCount, yourTierText)
    setSummary(theirs, "__SupremeOfferTotal", "THEM", theirTotal, theirKnown, theirCount,
        "trade", theirTierCount, theirTierText)
    setTradeVerdict(trade, yourTotal, theirTotal, yourKnown, theirKnown,
        yourCount, theirCount, yourTierCount, theirTierCount, yourItems, theirItems)

    local lines = {
        "YOUR OFFER NUMERIC: " .. formatValue(yourTotal)
            .. " (" .. tostring(yourKnown) .. "/" .. tostring(yourCount) .. " recognized, "
            .. tostring(yourTierCount) .. " tier)",
        "THEIR OFFER NUMERIC: " .. formatValue(theirTotal)
            .. " (" .. tostring(theirKnown) .. "/" .. tostring(theirCount) .. " recognized, "
            .. tostring(theirTierCount) .. " tier)"
    }
    if yourCount > 0 and theirCount > 0 then
        if yourKnown < yourCount or theirKnown < theirCount then
            table.insert(lines, "RESULT: NUMERIC VALUES NEEDED — unresolved item")
        elseif yourTierCount > 0 or theirTierCount > 0 then
            local tierVerdict, tierReason, yourTierText, theirTierText =
                compareTierOffers(yourItems, theirItems)
            table.insert(lines, "RESULT: " .. tierVerdict .. " | YOU: "
                .. yourTierText .. " | THEM: " .. theirTierText
                .. " | " .. tierReason)
        else
            local verdict, difference = getVerdict(yourTotal, theirTotal)
            table.insert(lines, "RESULT: " .. verdict .. " | Difference: "
                .. (difference > 0 and "+" or "") .. formatValue(difference))
        end
    else
        table.insert(lines, "RESULT: Waiting for both sides of the trade.")
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

-- MM2 does not guess the inventory ScreenGui name. It reads the
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
    local frameProbe, probeCount = {}, 0
    local seen = {}
    local keyHits, keyMisses, keySamples = 0, 0, {}
    local exactNumericQty, exactTierQty, knownNoSupremeQty, dbKeyMissQty = 0, 0, 0, 0
    local intentionalDefaultQty = 0
    local noSupremeSamples, dbMissSamples, intentionalDefaultSamples = {}, {}, {}
    local mappedIds = state.mapped and state.mapped.dbIds or nil

    -- MM2's actual structure is Data.Weapons[group][itemId] = entry.
    -- itemKey is the exact key in Database.Sync.Item/Pets, so resolve
    -- inventory values directly instead of guessing from icon or UI text.
    local function scanCollection(collection, collectionName)
        if type(collection) ~= "table" then return end
        for subgroupName, subgroup in pairs(collection) do
            if type(subgroup) ~= "table" then continue end
            groupCount = groupCount + 1
            for itemKey, entry in pairs(subgroup) do
                if type(entry) ~= "table" then continue end
                dataEntries = dataEntries + 1
                local keyText = tostring(itemKey)
                local dbKind = mappedIds and mappedIds[keyText] or nil
                if dbKind then keyHits = keyHits + 1 else
                    keyMisses = keyMisses + 1
                    dbKeyMissQty = dbKeyMissQty + math.max(1, tonumber(entry.Amount) or 1)
                    if #dbMissSamples < 20 then
                        table.insert(dbMissSamples, tostring(collectionName) .. "/" .. tostring(subgroupName)
                            .. "/" .. keyText .. " name=" .. tostring(entry.Name or entry.ItemName or "nil")
                            .. " amount=" .. tostring(entry.Amount or 1))
                    end
                end
                if #keySamples < 12 then
                    local fields = {}
                    for fieldName in pairs(entry) do
                        table.insert(fields, tostring(fieldName))
                    end
                    table.sort(fields)
                    table.insert(keySamples,
                        tostring(collectionName) .. "/" .. tostring(subgroupName)
                        .. " key=" .. keyText
                        .. " db=" .. tostring(dbKind or "MISS")
                        .. " fields={" .. table.concat(fields, ",") .. "}"
                        .. " ItemID=" .. tostring(entry.ItemID or entry.ItemId or "nil")
                        .. " ItemKey=" .. tostring(entry.ItemKey or entry.Key or "nil")
                        .. " Name=" .. tostring(entry.Name or entry.ItemName or "nil"))
                end
                local tile = entry.Frame
                if typeof(tile) ~= "Instance" or not tile:IsA("GuiObject") or seen[tile] then continue end
                seen[tile] = true
                frameCount = frameCount + 1
                if not tile.Parent then continue end
                local isVisible = visible(tile)
                if isVisible then visibleFrames = visibleFrames + 1 end
                if isVisible and probeCount < 5 then
                    probeCount = probeCount + 1
                    local icon = findTileIcon(tile)
                    local container = tile:FindFirstChild("Container", true)
                    local badge = tile:FindFirstChild("__SupremeItemValue", true)
                    local amountNode = tile:FindFirstChild("Amount", true)
                    local nameNode = tile:FindFirstChild("ItemName", true)
                    table.insert(frameProbe,
                        tostring(tile.Name)
                        .. "{class=" .. tile.ClassName
                        .. ",size=" .. tostring(tile.AbsoluteSize.X) .. "x" .. tostring(tile.AbsoluteSize.Y)
                        .. ",z=" .. tostring(tile.ZIndex)
                        .. ",clip=" .. tostring(tile.ClipsDescendants)
                        .. ",container=" .. tostring(container and container.Name or "none")
                        .. ",icon=" .. tostring(icon and assetId(icon.Image) or "none")
                        .. ",nameNode=" .. tostring(nameNode ~= nil)
                        .. ",amount=" .. tostring(amountNode and amountNode.Text or "none")
                        .. ",badge=" .. tostring(badge ~= nil)
                        .. ",badgeVisible=" .. tostring(badge and badge.Visible or false)
                        .. ",badgeText=" .. tostring(badge and badge.Text or "none")
                        .. ",nameText=" .. tostring(nameNode and (nameNode:IsA("TextLabel") and nameNode.Text or (nameNode:FindFirstChildWhichIsA("TextLabel", true) and nameNode:FindFirstChildWhichIsA("TextLabel", true).Text)) or "none")
                        .. ",badgeParent=" .. tostring(badge and badge.Parent and badge.Parent.Name or "none")
                        .. "}")
                end

                -- Do not depend on ItemName text: MM2's inventory tiles
                -- are reliably identified by Container.Icon -> MM2 database.
                local name, quantity = itemData(tile)
                local dataAmount = tonumber(entry.Amount)
                if dataAmount and dataAmount > 0 then
                    quantity = math.max(1, math.floor(dataAmount))
                end

                local exactPrefix = dbKind == "Pet" and "p:"
                    or dbKind == "Item" and "i:"
                    or (collectionName == "Pets" and "p:" or "i:")
                local exactValue = mappedIds and state.mapped
                    and state.mapped.byKey[exactPrefix .. keyText] or nil
                local resolvedValue, resolvedName, tierText, category
                if exactValue then
                    resolvedValue = exactValue.v
                    resolvedName = exactValue.name
                    tierText = exactValue.t
                    category = exactValue.category
                elseif not dbKind then
                    -- Unknown keys may come from a UI-specific data wrapper;
                    -- only those use the cautious icon/name resolver fallback.
                    resolvedValue, resolvedName, tierText, category = valueOf(tile, name)
                end
                if resolvedValue ~= nil then
                    total = total + resolvedValue * quantity
                    known = known + quantity
                    if dbKind then exactNumericQty = exactNumericQty + quantity end
                elseif tierText then
                    known = known + quantity
                    tierCount = tierCount + quantity
                    if dbKind then exactTierQty = exactTierQty + quantity end
                elseif dbKind then
                    -- Default Knife and Default Gun are built-in placeholders,
                    -- not Supreme-priced skins; do not report them as missing values.
                    if keyText == "DefaultKnife" or keyText == "DefaultGun" then
                        intentionalDefaultQty = intentionalDefaultQty + quantity
                        if #intentionalDefaultSamples < 10 then
                            table.insert(intentionalDefaultSamples,
                                tostring(collectionName) .. "/" .. tostring(subgroupName)
                                .. "/" .. keyText .. " qty=" .. tostring(quantity))
                        end
                    else
                        knownNoSupremeQty = knownNoSupremeQty + quantity
                        if #noSupremeSamples < 30 then
                            local image = findTileIcon(tile)
                            table.insert(noSupremeSamples,
                                tostring(collectionName) .. "/" .. tostring(subgroupName)
                                .. "/" .. keyText .. " name=" .. tostring(entry.Name or entry.ItemName or name)
                                .. " type=" .. tostring(dbKind)
                                .. " icon=" .. tostring(image and assetId(image.Image) or "none")
                                .. " qty=" .. tostring(quantity))
                        end
                    end
                end
                count = count + quantity
                local dbRecognized = dbKind ~= nil
                if resolvedValue == nil and not tierText and not dbRecognized then
                    recordUnmatched(tile, name, quantity, state.unmatchedInventory)
                end
                updateTileBadge(tile, resolvedValue, quantity, "inventory", tierText, category,
                    resolvedName or name, dbRecognized and "NO VALUE" or nil)
            end
        end
    end

    scanCollection(data.Weapons, "Weapons")
    scanCollection(data.Pets, "Pets")

    local guiInstance = typeof(gui) == "Instance" and gui or nil
    if guiInstance then
        local guiTiles = getTiles(guiInstance)
        state.inventoryGuiFrames = #guiTiles

        if frameCount > 0 then
            -- InventoryModule.Data frames were already resolved by their exact
            -- database keys above. Do not rescan and hide those badges using
            -- the less reliable display-name/icon resolver.
            state.inventoryGuiValued = known
            state.inventoryGuiItems = count
        else
            local _, guiKnown, guiCount = scanRoot(guiInstance, "inventoryOverlay")
            scanImageCards(guiInstance, "inventoryOverlay")
            state.inventoryGuiValued = guiKnown or 0
            state.inventoryGuiItems = guiCount or 0
        end
    else
        state.inventoryGuiFrames = 0
        state.inventoryGuiValued = 0
        state.inventoryGuiItems = 0
    end

    -- Attach the total to the actual visible inventory panel, including
    -- mobile layouts where MyInventory is a ScreenGui rather than a Frame.
    local totalParent
    if guiInstance then
        local main = guiInstance:FindFirstChild("Main", true)
        if main and main:IsA("GuiObject") then
            totalParent = main
        elseif guiInstance:IsA("GuiObject") then
            totalParent = guiInstance
        else
            for _, descendant in ipairs(guiInstance:GetDescendants()) do
                if descendant:IsA("Frame") and descendant.Visible
                    and descendant.AbsoluteSize.X > 0 and descendant.AbsoluteSize.Y > 0 then
                    totalParent = descendant
                    break
                end
            end
        end
    end
    if totalParent then
        local label = makeLabel(totalParent, "__SupremeInventoryTotal", "inventory")
        label.AnchorPoint = Vector2.new(0, 0)
        label.Position = UDim2.new(0, 8, 0, 8)
        label.Size = UDim2.fromOffset(250, 26)
        label.TextSize = 12
        label.ZIndex = 1000
        label.Text = "INV " .. formatValue(total)
            .. (tierCount > 0 and " + TIER(" .. tostring(tierCount) .. ")" or "")
            .. " | KNOWN " .. tostring(known) .. "/" .. tostring(count)
            .. (intentionalDefaultQty > 0 and " | DEFAULT " .. tostring(intentionalDefaultQty) or "")
        label.Visible = count > 0
    end

    state.inventoryFrameProbe = #frameProbe > 0 and table.concat(frameProbe, " | ") or "no visible data Frames"
    state.inventoryKeyStats = "HITS=" .. tostring(keyHits)
        .. " MISSES=" .. tostring(keyMisses)
        .. " | samples: " .. (#keySamples > 0 and table.concat(keySamples, " || ") or "none")
        .. (mappedIds and "" or " | MM2 database index unavailable")
    state.inventoryFrames = frameCount
    state.inventoryVisibleFrames = visibleFrames
    state.inventoryDataEntries = dataEntries
    state.inventoryGroups = groupCount
    state.inventoryResolutionStats =
        "EXACT_NUMERIC=" .. tostring(exactNumericQty)
        .. " EXACT_TIER=" .. tostring(exactTierQty)
        .. " DB_KNOWN_NO_SUPREME=" .. tostring(knownNoSupremeQty)
        .. " DB_KEY_MISS=" .. tostring(dbKeyMissQty)
        .. " INTENTIONAL_DEFAULTS=" .. tostring(intentionalDefaultQty)
        .. " | default samples: " .. (#intentionalDefaultSamples > 0 and table.concat(intentionalDefaultSamples, " || ") or "none")
        .. " | no-Supreme samples: " .. (#noSupremeSamples > 0 and table.concat(noSupremeSamples, " || ") or "none")
        .. " | DB-key misses: " .. (#dbMissSamples > 0 and table.concat(dbMissSamples, " || ") or "none")
    state.inventoryGuiPath = gui and "InventoryModule.GUI.MyInventory"
        or "InventoryModule.GUI.MyInventory unavailable"

    return total, known, count, visibleFrames, myInventory, tierCount
end

local function scanInventory()
    state.unmatchedInventory = {}
    local weaponTotal, weaponKnown, weaponCount, visibleFrames = 0, 0, 0, 0
    local moduleTotal, moduleKnown, moduleCount, moduleVisible, _, moduleTierCount = scanModuleInventory()
    local weaponTierCount = moduleTierCount or 0
    weaponTotal, weaponKnown, weaponCount, visibleFrames = moduleTotal, moduleKnown, moduleCount, moduleVisible

    -- Fallback for UI-only builds where InventoryModule does not expose frames.
    -- Keep the explicit MainGUI/MainMobile paths as a secondary option.
    if visibleFrames == 0 then
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
                    scanRoot(list, "tradeInventory")
                    -- Supplement text-based cards with image-only cards.
                    -- scanImageCards has its own per-pass deduplication.
                    scanImageCards(list, "tradeInventory")
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
        .. " | Frames: " .. tostring(state.inventoryFrames)
        .. " | Visible: " .. tostring(state.inventoryVisibleFrames)
        .. " | GUI cards: " .. tostring(state.inventoryGuiFrames)
        .. " | GUI valued: " .. tostring(state.inventoryGuiValued) .. "/" .. tostring(state.inventoryGuiItems)
        .. " | Groups: " .. tostring(state.inventoryGroups)
        .. " | GUI: " .. tostring(state.inventoryGuiPath)
        .. " | Data path: MyInventory.Data.Weapons[group][itemId].Frame"
        .. " | Numeric total: " .. formatValue(weaponTotal)
        .. " | Tier items: " .. tostring(weaponTierCount)
        .. " | Valued: " .. tostring(weaponKnown) .. "/" .. tostring(weaponCount)
        .. " | itemKey vs MM2 DB: " .. tostring(state.inventoryKeyStats)
        .. " | Resolution: " .. tostring(state.inventoryResolutionStats)
        .. " | Frame probe: " .. tostring(state.inventoryFrameProbe)
        .. " | PlayerGui: " .. tostring(state.inventoryScreenList)
end

-- Minimal diagnostics panel.
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
-- Keep the diagnostics control away from MM2's Accept/Decline buttons.
panel.AnchorPoint = Vector2.new(0, 1)
panel.Position = UDim2.new(0, 12, 1, -12)
panel.BackgroundColor3 = Color3.fromRGB(16, 19, 29)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.ZIndex = 200
panel.Parent = textGui

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -48, 0, 34)
title.Position = UDim2.fromOffset(10, 0)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 12
title.TextColor3 = Color3.fromRGB(120, 220, 255)
title.TextXAlignment = Enum.TextXAlignment.Left
title.Text = "SUPREME — LOADING"
title.Active = true
title.ZIndex = 201
title.Parent = panel

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.fromOffset(34, 30)
toggle.Position = UDim2.new(1, -38, 0, 2)
toggle.BackgroundColor3 = Color3.fromRGB(35, 95, 125)
toggle.BorderSizePixel = 0
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 16
toggle.TextColor3 = Color3.new(1, 1, 1)
toggle.Text = "+"
toggle.ZIndex = 202
toggle.Parent = panel

local output = Instance.new("TextBox")
output.Name = "DiagnosticText"
output.Size = UDim2.new(1, -20, 1, -82)
output.Position = UDim2.fromOffset(10, 78)
output.BackgroundColor3 = Color3.fromRGB(9, 11, 18)
output.BackgroundTransparency = 0.1
output.BorderSizePixel = 0
output.ClearTextOnFocus = false
output.MultiLine = true
output.TextEditable = true
output.TextWrapped = false
output.TextXAlignment = Enum.TextXAlignment.Left
output.TextYAlignment = Enum.TextYAlignment.Top
output.Font = Enum.Font.Code
output.TextSize = 10
output.TextColor3 = Color3.fromRGB(225, 231, 242)
output.Text = "Connecting to Supreme Values..."
output.ZIndex = 201
output.Parent = panel

local testButton = Instance.new("TextButton")
testButton.Name = "OpenTradeTest"
testButton.Size = UDim2.new(0, 82, 0, 32)
testButton.Position = UDim2.new(0, 8, 1, -39)
testButton.BackgroundColor3 = Color3.fromRGB(105, 75, 165)
testButton.BorderSizePixel = 0
testButton.Font = Enum.Font.GothamBold
testButton.TextSize = 10
testButton.TextColor3 = Color3.new(1, 1, 1)
testButton.Text = "СИМУЛЯТОР"
testButton.ZIndex = 205
testButton.Parent = panel

local copyButton = Instance.new("TextButton")
copyButton.Name = "CopySupremeDiagnostic"
copyButton.Size = UDim2.new(0, 88, 0, 32)
copyButton.Position = UDim2.new(0, 96, 1, -39)
copyButton.BackgroundColor3 = Color3.fromRGB(35, 125, 145)
copyButton.BorderSizePixel = 0
copyButton.Font = Enum.Font.GothamBold
copyButton.TextSize = 11
copyButton.TextColor3 = Color3.new(1, 1, 1)
copyButton.Text = "COPY REPORT"
copyButton.ZIndex = 205
copyButton.Parent = panel

local exportButton = Instance.new("TextButton")
exportButton.Name = "ExportSupremeData"
exportButton.Size = UDim2.new(0, 88, 0, 32)
exportButton.Position = UDim2.new(0, 190, 1, -39)
exportButton.BackgroundColor3 = Color3.fromRGB(45, 115, 85)
exportButton.BorderSizePixel = 0
exportButton.Font = Enum.Font.GothamBold
exportButton.TextSize = 11
exportButton.TextColor3 = Color3.new(1, 1, 1)
exportButton.Text = "EXPORT JSON"
exportButton.ZIndex = 205
exportButton.Parent = panel

local collapsed = true
local expandedSize = UDim2.fromOffset(290, 225)
local collapsedSize = UDim2.fromOffset(126, 34)
local function setCollapsed(value)
    collapsed = value
    panel.Size = collapsed and collapsedSize or expandedSize
    output.Visible = not collapsed
    testButton.Visible = not collapsed
    copyButton.Visible = not collapsed
    exportButton.Visible = not collapsed
    toggle.Text = collapsed and "+" or "−"
    title.Text = collapsed and "SUPREME" or (state.status == "ok" and "SUPREME — READY" or "SUPREME — " .. string.upper(state.status))
end
toggle.Activated:Connect(function()
    setCollapsed(not collapsed)
end)
setCollapsed(true)

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

-- Offline trade simulator: resolves exact MM2 database names through the
-- already-built Supreme mapping. Only numeric Supreme prices are accepted.
local testFrame = Instance.new("Frame")
testFrame.Name = "OfflineTradeSimulator"
testFrame.Size = UDim2.fromOffset(310, 390)
testFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
testFrame.AnchorPoint = Vector2.new(0.5, 0.5)
testFrame.BackgroundColor3 = Color3.fromRGB(16, 19, 29)
testFrame.BackgroundTransparency = 0.03
testFrame.BorderSizePixel = 0
testFrame.Visible = false
testFrame.ZIndex = 400
testFrame.Parent = textGui

local testTitle = Instance.new("TextLabel")
testTitle.Size = UDim2.new(1, -48, 0, 34)
testTitle.Position = UDim2.fromOffset(12, 4)
testTitle.BackgroundTransparency = 1
testTitle.Font = Enum.Font.GothamBold
testTitle.TextSize = 14
testTitle.TextColor3 = Color3.fromRGB(120, 220, 255)
testTitle.TextXAlignment = Enum.TextXAlignment.Left
testTitle.Text = "ОФЛАЙН СИМУЛЯТОР"
testTitle.ZIndex = 401
testTitle.Parent = testFrame

local closeTest = Instance.new("TextButton")
closeTest.Size = UDim2.fromOffset(32, 30)
closeTest.Position = UDim2.new(1, -38, 0, 4)
closeTest.BackgroundColor3 = Color3.fromRGB(80, 45, 55)
closeTest.BorderSizePixel = 0
closeTest.Font = Enum.Font.GothamBold
closeTest.TextSize = 16
closeTest.TextColor3 = Color3.new(1, 1, 1)
closeTest.Text = "×"
closeTest.ZIndex = 402
closeTest.Parent = testFrame

local function makeOfferInput(name, labelText, y)
    local heading = Instance.new("TextLabel")
    heading.Size = UDim2.new(1, -24, 0, 20)
    heading.Position = UDim2.fromOffset(12, y)
    heading.BackgroundTransparency = 1
    heading.Font = Enum.Font.GothamBold
    heading.TextSize = 11
    heading.TextColor3 = Color3.fromRGB(210, 220, 238)
    heading.TextXAlignment = Enum.TextXAlignment.Left
    heading.Text = labelText
    heading.ZIndex = 401
    heading.Parent = testFrame

    local box = Instance.new("TextBox")
    box.Name = name
    box.Size = UDim2.new(1, -24, 0, 82)
    box.Position = UDim2.fromOffset(12, y + 22)
    box.BackgroundColor3 = Color3.fromRGB(8, 11, 19)
    box.BorderSizePixel = 0
    box.ClearTextOnFocus = false
    box.MultiLine = true
    box.TextEditable = true
    box.TextWrapped = true
    box.TextXAlignment = Enum.TextXAlignment.Left
    box.TextYAlignment = Enum.TextYAlignment.Top
    box.Font = Enum.Font.Code
    box.TextSize = 12
    box.TextColor3 = Color3.fromRGB(235, 240, 250)
    box.PlaceholderColor3 = Color3.fromRGB(130, 140, 160)
    box.PlaceholderText = "Например: Laser x2\nSeer\nx2 T1 Commons"
    box.Text = ""
    box.ZIndex = 401
    box.Parent = testFrame
    return box
end

local yourTestInput = makeOfferInput("YourTestOffer", "ТЫ ОТДАЁШЬ (каждый предмет с новой строки)", 42)
local theirTestInput = makeOfferInput("TheirTestOffer", "ТЫ ПОЛУЧАЕШЬ (каждый предмет с новой строки)", 150)

local testResult = Instance.new("TextLabel")
testResult.Size = UDim2.new(1, -24, 0, 58)
testResult.Position = UDim2.fromOffset(12, 260)
testResult.BackgroundColor3 = Color3.fromRGB(8, 11, 19)
testResult.BorderSizePixel = 0
testResult.Font = Enum.Font.GothamBold
testResult.TextSize = 12
testResult.TextWrapped = true
testResult.TextColor3 = Color3.fromRGB(230, 235, 245)
testResult.Text = "Впиши точные названия предметов на английском. Количество: Laser x2. Затем нажми «СРАВНИТЬ»."
testResult.ZIndex = 401
testResult.Parent = testFrame

local compareTest = Instance.new("TextButton")
compareTest.Size = UDim2.new(1, -24, 0, 38)
compareTest.Position = UDim2.fromOffset(12, 326)
compareTest.BackgroundColor3 = Color3.fromRGB(65, 105, 155)
compareTest.BorderSizePixel = 0
compareTest.Font = Enum.Font.GothamBold
compareTest.TextSize = 13
compareTest.TextColor3 = Color3.new(1, 1, 1)
compareTest.Text = "СРАВНИТЬ"
compareTest.ZIndex = 402
compareTest.Parent = testFrame

local function resolveTestItem(rawName)
    local name = clean(rawName)
    local tierMultiplier, tierLevel, tierClass =
        name:match("^[x×](%d+)%s+(T%d+)%s+([%a]+)$")
    if tierMultiplier and tierLevel and tierClass then
        local tierText = "x" .. tostring(tonumber(tierMultiplier)) .. " "
            .. tierLevel .. " " .. tierClass
        return {name = tierText, tier = tierText, quantity = 1}
    end

    local quantity = 1
    local base, amount = name:match("^(.-)%s+[x×](%d+)$")
    if base then name, quantity = clean(base), math.max(1, math.floor(tonumber(amount) or 1)) end

    local isChromaInput = name:lower():match("^chroma%s+") ~= nil
    local lookupName = clean(name:gsub("^[Cc][Hh][Rr][Oo][Mm][Aa]%s+", ""))
    local requestedType, requestedYear

    -- Accept explicit discriminators so duplicate MM2 names can be resolved:
    -- "Laser Gun", "Laser Knife", "Laser (Gun)", "Laser (Knife)", and years.
    local yearBase, yearSuffix = lookupName:match("^(.-)%s*%((%d%d%d%d)%)$")
    if yearBase then
        lookupName, requestedYear = clean(yearBase), yearSuffix
    else
        local trailingYearBase, trailingYear = lookupName:match("^(.-)%s+(20%d%d)$")
        if trailingYearBase then lookupName, requestedYear = clean(trailingYearBase), trailingYear end
    end

    local typeBase, typeSuffix = lookupName:match("^(.-)%s*%((%a+)%)$")
    if typeBase and (typeSuffix == "Knife" or typeSuffix == "Gun") then
        lookupName, requestedType = clean(typeBase), typeSuffix
    else
        local trailingTypeBase, trailingType = lookupName:match("^(.-)%s+(%a+)$")
        if trailingTypeBase and (trailingType == "Knife" or trailingType == "Gun") then
            lookupName, requestedType = clean(trailingTypeBase), trailingType
        end
    end

    local normalizedInput = normalize(lookupName)
    local candidates = state.mapped and state.mapped.byName[normalizedInput] or nil
    local matches = {}
    local rejectedNames = {}
    for _, candidate in ipairs(candidates or {}) do
        local entry = state.mapped.byKey[candidate.key]
        if entry and tonumber(entry.v) ~= nil then
            local mappedName = normalize(entry.name)
            local typeMatches = not requestedType or candidate.itemType == requestedType
            local yearMatches = not requestedYear or candidate.year == requestedYear
            if mappedName == normalizedInput
                and candidate.chroma == isChromaInput
                and typeMatches and yearMatches then
                table.insert(matches, {entry = entry, key = candidate.key})
            elseif mappedName ~= normalizedInput then
                rejectedNames[mappedName] = true
            end
        end
    end
    if #matches == 0 then
        local rejected = {}
        for rejectedName in pairs(rejectedNames) do
            table.insert(rejected, rejectedName)
        end
        table.sort(rejected)
        if #rejected > 0 then
            return nil, name .. ": совпадение MM2/Supreme не подтверждено (найдено другое название: "
                .. table.concat(rejected, ", ") .. "). Предмет не будет оценён."
        end
        if requestedType or requestedYear then
            return nil, name .. ": вариант с указанным типом/годом не найден в числовых оценках Supreme."
        end
        return nil, name .. ": нет числовой оценки Supreme (предмет не найден или у него только тир)"
    end
    if #matches > 1 then
        local hint = "Уточни тип предмета: добавь Gun или Knife"
        if requestedType then hint = "Уточни год, например 2023 или 2024" end
        return nil, name .. ": найдено несколько вариантов. " .. hint .. "."
    end
    return {name = matches[1].entry.name, value = tonumber(matches[1].entry.v), quantity = quantity}
end

local function parseTestOffer(textValue)
    local items, total = {}, 0
    for line in tostring(textValue or ""):gmatch("[^\r\n]+") do
        local raw = clean(line)
        if raw ~= "" then
            local item, err = resolveTestItem(raw)
            if not item then return nil, nil, err end
            table.insert(items, item)
            if tonumber(item.value) ~= nil then
                total = total + item.value * item.quantity
            end
        end
    end
    if #items == 0 then return nil, nil, "Добавь хотя бы один предмет в каждую сторону." end
    return items, total
end

closeTest.Activated:Connect(function()
    testFrame.Visible = false
end)

testButton.Activated:Connect(function()
    testFrame.Visible = not testFrame.Visible
end)

compareTest.Activated:Connect(function()
    if state.status ~= "ok" or type(state.mapped) ~= "table" then
        testResult.Text = "Данные Supreme ещё загружаются. Подожди, пока появится READY."
        return
    end
    local yourItems, yourTotal, yourError = parseTestOffer(yourTestInput.Text)
    if not yourItems then
        testResult.Text = "ТЫ ОТДАЁШЬ: " .. tostring(yourError)
        return
    end
    local theirItems, theirTotal, theirError = parseTestOffer(theirTestInput.Text)
    if not theirItems then
        testResult.Text = "ТЫ ПОЛУЧАЕШЬ: " .. tostring(theirError)
        return
    end
    local hasTier = false
    for _, item in ipairs(yourItems) do
        if item.tier then hasTier = true break end
    end
    if not hasTier then
        for _, item in ipairs(theirItems) do
            if item.tier then hasTier = true break end
        end
    end

    if hasTier then
        local tierVerdict, tierReason, yourTierText, theirTierText =
            compareTierOffers(yourItems, theirItems)
        testResult.Text = "TIER " .. tierVerdict .. "\nТЫ: " .. yourTierText
            .. "\nПОЛУЧАЕШЬ: " .. theirTierText .. "\n" .. tierReason
        testResult.TextColor3 = tierVerdict == "WIN" and Color3.fromRGB(65, 240, 145)
            or tierVerdict == "LOSE" and Color3.fromRGB(255, 90, 105)
            or tierVerdict == "FAIR" and Color3.fromRGB(105, 195, 255)
            or Color3.fromRGB(255, 190, 65)
    else
        local verdict, difference = getVerdict(yourTotal, theirTotal)
        local sign = difference > 0 and "+" or ""
        testResult.Text = (verdict == "WIN" and "ВЫИГРЫШ" or verdict == "LOSE" and "ПРОИГРЫШ" or "РАВНО")
            .. "  " .. sign .. formatValue(difference)
            .. "\nТВОЁ: " .. formatValue(yourTotal)
            .. "  |  ПОЛУЧАЕШЬ: " .. formatValue(theirTotal)
        testResult.TextColor3 = verdict == "WIN" and Color3.fromRGB(65, 240, 145)
            or verdict == "LOSE" and Color3.fromRGB(255, 90, 105)
            or Color3.fromRGB(105, 195, 255)
    end
end)


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
            .. ", DB-icon={" .. tostring(entry.dbImageMatches or "not-scanned") .. "}"
            .. ", Supreme={" .. tostring(entry.supremeMatches or "not-scanned") .. "}]")
    end
    if #rows > 25 then
        table.insert(output, "... +" .. tostring(#rows - 25) .. " more unique items")
    end
    return #output > 0 and table.concat(output, " | ") or "none"
end

local function buildPhase1Dump()
    local lines = {"PHASE 1 — MM2 DATABASE RECORD DUMP"}
    local database, dbError = loadGameDatabase()
    local ids = {
        "SlouseClownGun", "Clown", "Clown_G_2024", "SlouseClown",
        "Clown_G", "Carrot_K_2023", "Carrot_K_2024", "Carrot",
        "Carrot_G_2024", "DefaultGun", "DefaultKnife"
    }
    if type(database) ~= "table" or type(database.Item) ~= "table" then
        table.insert(lines, "Database unavailable: " .. tostring(dbError))
    else
        for _, id in ipairs(ids) do
            local record = database.Item[id]
            if type(record) ~= "table" then
                table.insert(lines, id .. ": NOT FOUND")
            else
                local fields = {}
                for key, value in pairs(record) do
                    local valueType = typeof(value)
                    local rendered
                    if type(value) == "table" then
                        local keys = {}
                        for childKey in pairs(value) do
                            table.insert(keys, tostring(childKey))
                            if #keys >= 8 then break end
                        end
                        table.sort(keys)
                        rendered = "table{" .. table.concat(keys, ",") .. "}"
                    elseif valueType == "Instance" then
                        rendered = "Instance(" .. value.ClassName .. ":" .. value.Name .. ")"
                    else
                        rendered = tostring(value)
                    end
                    table.insert(fields, tostring(key) .. "=" .. rendered)
                end
                table.sort(fields)
                table.insert(lines, id .. ": " .. table.concat(fields, " | "))
            end
        end
    end

    table.insert(lines, "")
    table.insert(lines, "PHASE 1 — TRADE CARD INTERNAL DATA")
    local screen, container, trade = findTrade()
    if not screen then
        table.insert(lines, "No active trade. Open a trade and put at least one item into either offer before copying the report.")
        return table.concat(lines, "\n")
    end

    local offers = {
        {name = "YourOffer", root = trade:FindFirstChild("YourOffer", true)},
        {name = "TheirOffer", root = trade:FindFirstChild("TheirOffer", true)}
    }
    local foundCard = false
    for _, offerInfo in ipairs(offers) do
        local offer = offerInfo.root
        local offerContainer = offer and offer:FindFirstChild("Container")
        if offerContainer then
            for _, tile in ipairs(offerContainer:GetDescendants()) do
                if tile:IsA("GuiObject") and visible(tile) then
                    local icon = findTileIcon(tile)
                    local directSlot = tile.Name:match("^NewItem%d+$") ~= nil and icon ~= nil
                    local normalCard = tile:FindFirstChild("Container") and icon ~= nil
                    if directSlot or normalCard then
                        foundCard = true
                        table.insert(lines, offerInfo.name .. " card=" .. tile:GetFullName()
                            .. " class=" .. tile.ClassName
                            .. " displayName=" .. tostring((itemData(tile)))
                            .. " icon=" .. tostring(icon and assetId(icon.Image) or "none"))
                        local okAttributes, attributes = pcall(function() return tile:GetAttributes() end)
                        if okAttributes then
                            local attributeRows = {}
                            for key, value in pairs(attributes) do
                                table.insert(attributeRows, tostring(key) .. "=" .. tostring(value))
                            end
                            table.sort(attributeRows)
                            table.insert(lines, "  ATTRIBUTES: " .. (#attributeRows > 0 and table.concat(attributeRows, " | ") or "none"))
                        else
                            table.insert(lines, "  ATTRIBUTES: read failed")
                        end
                        local valueRows, viewportRows = {}, {}
                        for _, node in ipairs(tile:GetDescendants()) do
                            if node:IsA("StringValue") or node:IsA("ObjectValue")
                                or node:IsA("IntValue") or node:IsA("NumberValue") then
                                local valueText = node:IsA("ObjectValue")
                                    and (node.Value and node.Value:GetFullName() or "nil")
                                    or tostring(node.Value)
                                table.insert(valueRows, node.ClassName .. " " .. node.Name .. "=" .. valueText)
                            elseif node:IsA("ViewportFrame") then
                                local models = {}
                                for _, nested in ipairs(node:GetDescendants()) do
                                    if nested:IsA("Model") then
                                        table.insert(models, nested.Name)
                                    end
                                end
                                table.insert(viewportRows, node:GetFullName() .. " models={" .. table.concat(models, ",") .. "}")
                            end
                        end
                        table.sort(valueRows)
                        table.sort(viewportRows)
                        table.insert(lines, "  VALUE OBJECTS: " .. (#valueRows > 0 and table.concat(valueRows, " | ") or "none"))
                        table.insert(lines, "  VIEWPORTS: " .. (#viewportRows > 0 and table.concat(viewportRows, " | ") or "none"))
                        table.insert(lines, "  CHILD TREE: " .. tile.Name .. "{" .. table.concat((function()
                            local rows = {}
                            for _, child in ipairs(tile:GetChildren()) do
                                table.insert(rows, child.Name .. ":" .. child.ClassName)
                            end
                            table.sort(rows)
                            return rows
                        end)(), ",") .. "}")
                        break
                    end
                end
            end
        end
        if foundCard then break end
    end
    if not foundCard then
        table.insert(lines, "Trade is open but no visible offer card found. Add one item to either side and copy again.")
    end
    return table.concat(lines, "\n")
end

local function buildDiagnostic(includeDeepDump)
    local lines = {
        "SUPREME TRADE CHECKER — MM2 MAPPING",
        "Time: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Status: " .. tostring(state.status),
        "Load time: " .. string.format("%.2f", tonumber(state.loadDuration) or 0) .. "s",
        "Values source: " .. BASE,
        "Pages fetched: " .. tostring(state.pageCount) .. "/" .. tostring(#CATEGORIES),
        "Pages parsed: " .. tostring(state.parsedPages),
        "Supreme entries: " .. tostring(state.entryCount),
        "Export-ready entries: " .. tostring(type(state.supremeEntries) == "table" and #state.supremeEntries or 0),
        "Supreme tier entries: " .. tostring(state.tierEntryCount or 0),
        "Value entries by category: " .. HttpService:JSONEncode(state.categoryCounts or {}),
        "Reference-page value cards (not mapped as single items): "
            .. HttpService:JSONEncode(state.referenceValueCounts or {}),
        "All page card counts: " .. HttpService:JSONEncode(state.categoryCardCounts or {}),
        "Data pipeline: " .. tostring(state.dataPipeline or "not loaded"),
        "MM2 DB source: " .. tostring(state.source ~= "" and state.source or "not loaded"),
        "MM2 weapon records: " .. tostring(state.dbItems),
        "MM2 pet records: " .. tostring(state.dbPets),
        "Matched item records: " .. tostring(state.mappedCount),
        "MM2 database coverage: " .. tostring(state.mapped and state.mapped.dbTotal or 0)
            .. " catalog records total; numeric=" .. tostring(state.mapped and state.mapped.dbNumericMapped or 0)
            .. ", tier=" .. tostring(state.mapped and state.mapped.dbTierMapped or 0)
            .. ", intentionally no-value defaults=" .. tostring(state.mapped and state.mapped.dbExcludedNoValue or 0)
            .. ", untradable trophy skins excluded=" .. tostring(state.mapped and state.mapped.dbExcludedTrophy or 0)
            .. ", unmapped=" .. tostring(state.mapped and state.mapped.dbUnmapped or 0),
        "Unmapped MM2 database records (trophy skins excluded; remaining Unique-rarity entries are candidates only): "
            .. table.concat(state.mapped and state.mapped.dbUnmappedAll or {}, " | "),
        "Unmapped Unique-rarity candidate count: "
            .. tostring(state.mapped and #(state.mapped.dbUniqueUnmapped or {}) or 0),
        "Unmapped Unique-rarity candidates: "
            .. table.concat(state.mapped and state.mapped.dbUniqueUnmapped or {}, " | "),
        "Icon mappings: " .. tostring(state.iconCount),
        "Fetch methods: " .. HttpService:JSONEncode(state.fetchMethods),
        "Failed pages: " .. (#state.failedPages > 0 and table.concat(state.failedPages, " | ") or "none"),
        "Last error: " .. tostring(state.lastError or "none"),
        "Tier comparator self-test: " .. TIER_SELF_TEST,
        "Numeric parser self-test: " .. tostring(state.numericParserStatus or "not run"),
        "Tier comparator mode: same-unit comparison only; no tier-to-numeric conversion",
        "",
        "CURRENT TRADE:",
        tostring(state.latestTrade),
        "",
        "CURRENT INVENTORY:",
        tostring(state.latestInventory),
        "INVENTORY INTERNAL KEY AUDIT: " .. tostring(state.inventoryKeyStats),
        "INVENTORY RESOLUTION BREAKDOWN: " .. tostring(state.inventoryResolutionStats or "not available"),
        includeDeepDump and buildPhase1Dump()
            or "PHASE 1 DUMP: skipped during live refresh (tap COPY REPORT to include)",
        "UNMATCHED INVENTORY (top 25): " .. formatUnmatchedItems(state.unmatchedInventory),
        "UNMATCHED TRADE (top 25): " .. formatUnmatchedItems(state.unmatchedTrade)
    }
    return table.concat(lines, "\n")
end

exportButton.Activated:Connect(function()
    local entries = state.supremeEntries
    if type(entries) ~= "table" or #entries < 300 then
        exportButton.Text = "DATA NOT READY"
        task.delay(3, function()
            if exportButton and exportButton.Parent then exportButton.Text = "EXPORT JSON" end
        end)
        return
    end

    local ok, encoded = pcall(function()
        return HttpService:JSONEncode({
            schema_version = 1,
            source = "Supreme Values MM2 via Delta / Arceus X",
            exported_at = os.date("%Y-%m-%d %H:%M:%S"),
            category_counts = state.categoryCounts or {},
            page_card_counts = state.categoryCardCounts or {},
            entries = entries
        })
    end)
    if not ok or type(encoded) ~= "string" then
        exportButton.Text = "JSON ENCODE FAILED"
        warn("[Supreme Trade Checker] JSON encode failed: " .. tostring(encoded))
        return
    end

    -- Save a real file when the executor supports writefile, and also copy
    -- the JSON so Android users still have a fallback if filesystem APIs fail.
    local saved = false
    if type(writefile) == "function" then
        local writeOk, writeResult = pcall(writefile, "SupremeTradeChecker_export.json", encoded)
        saved = writeOk and writeResult ~= false
        if not saved then
            warn("[Supreme Trade Checker] writefile failed: " .. tostring(writeResult))
        end
    end

    local copied = copyText(encoded)
    if saved and copied then
        exportButton.Text = "SAVED + COPIED"
    elseif saved then
        exportButton.Text = "JSON SAVED " .. tostring(#entries)
    elseif copied then
        exportButton.Text = "JSON COPIED " .. tostring(#entries)
    else
        exportButton.Text = "EXPORT FAILED"
    end

    if saved or copied then
        warn("[Supreme Trade Checker] Export ready: " .. tostring(#entries)
            .. " entries, " .. tostring(#encoded) .. " bytes; file saved="
            .. tostring(saved) .. ", clipboard copied=" .. tostring(copied))
    else
        warn("[Supreme Trade Checker] Export failed: no usable writefile or clipboard API.")
    end

    task.delay(7, function()
        if exportButton and exportButton.Parent then exportButton.Text = "EXPORT JSON" end
    end)
end)

copyButton.Activated:Connect(function()
    local report = buildDiagnostic(true)
    copyButton.Text = copyText(report) and "REPORT COPIED" or "COPY UNAVAILABLE"
    task.delay(3, function()
        if copyButton and copyButton.Parent then
            copyButton.Text = "COPY REPORT"
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

local inputChangedConnection = UserInputService.InputChanged:Connect(function(input)
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
        title.Text = collapsed and "SUPREME" or "SUPREME — READY"
    else
        title.Text = collapsed and "SUPREME" or "SUPREME — " .. string.upper(state.status)
    end
    output.Text = buildDiagnostic(false)
end

textGui.Destroying:Connect(function()
    stopped = true
    if inputChangedConnection then
        inputChangedConnection:Disconnect()
        inputChangedConnection = nil
    end
end)

task.spawn(function()
    task.wait(0.25)
    loadValues(true)
    while textGui.Parent and not stopped do
        pcall(scanTrade)
        pcall(scanInventory)
        updateUi()
        if state.status == "fail" and not state.busy then
            task.wait(20)
            loadValues(true)
        elseif state.status == "ok" and os.clock() - state.updated >= 900 and not state.busy then
            loadValues(false)
        end
        task.wait(0.6)
    end
end)

print("[Supreme Trade Checker] MM2-style item mapping loaded.")
