-- MM2 Supreme Trade Checker
-- Inventory and trade value overlay adapted from the proven PulseHub MM2 reader.
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

local state = {
    status = "loading",
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
    inventoryGroups = 0,
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
        local amount = tonumber(cardText:match("Value%s*%-%s*([%d%.]+)"))
        local tierText = cardText:match("Value%s*%-%s*([x×]%d+%s+T%d+%s+[%a]+)")
        if not amount and not tierText then
            local dataAmount = tonumber(card:match('data%-value="([%d%.]+)"') or "")
            if dataAmount and dataAmount > 0 then amount = dataAmount end
        end
        local nameMarkup = card:match('<div class="itemhead">(.-)</div>')
        local origin = decodeText(card:match('class="itemorigin">([^<]*)<') or "")
        local imageAlt = card:match('<img[^>]-alt="([^"]*)"')
            or card:match("<img[^>]-alt='([^']*)'")
        imageAlt = decodeText(imageAlt or "")
        local pageEvent = card:match('data%-event="([^"]+)"')
        if (amount or tierText) and (not amount or amount < 500000)
            and nameMarkup and not origin:find("Deletion", 1, true) then
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

    local icon, iconCandidates, chromaOf, byName = {}, {}, {}, {}
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
        if chroma then iconKey = mapped.chromaOf[iconKey] or iconKey end
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

            if #failed > 0 or pageCount ~= #CATEGORIES then
                error("Supreme pages incomplete; refusing to publish partial values")
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
        label.BackgroundColor3 = Color3.fromRGB(25, 30, 48)
        label.BackgroundTransparency = 0.12
        label.TextColor3 = Color3.fromRGB(248, 250, 255)
        label.TextStrokeTransparency = 1
        label.TextXAlignment = Enum.TextXAlignment.Center
        label.TextYAlignment = Enum.TextYAlignment.Center
        label.Font = Enum.Font.GothamBold
        label.TextSize = 11
        label.BorderSizePixel = 0
        label.ZIndex = 90
        label.Parent = parent
        local corner = Instance.new("UICorner")
        corner.CornerRadius = UDim.new(0, 8)
        corner.Parent = label
        local stroke = Instance.new("UIStroke")
        stroke.Name = "SupremeStroke"
        stroke.Thickness = 1
        stroke.Transparency = 0.2
        stroke.Color = Color3.fromRGB(112, 145, 255)
        stroke.Parent = label
        local gradient = Instance.new("UIGradient")
        gradient.Name = "SupremeGradient"
        gradient.Rotation = 90
        gradient.Color = ColorSequence.new(Color3.fromRGB(48, 56, 88), Color3.fromRGB(20, 24, 40))
        gradient.Parent = label
    end
    label:SetAttribute("SupremeOwner", group)
    return label
end

local VALUE_TEXT_COLORS = {
    uniques = Color3.fromRGB(255, 196, 92), godlies = Color3.fromRGB(194, 125, 255),
    chromas = Color3.fromRGB(255, 105, 205), ancients = Color3.fromRGB(255, 105, 125),
    vintages = Color3.fromRGB(255, 174, 105), legendaries = Color3.fromRGB(255, 151, 88),
    -- Swap the two low-tier accents to match the in-game item color mapping.
    rares = Color3.fromRGB(94, 220, 171), uncommons = Color3.fromRGB(104, 174, 255),
    commons = Color3.fromRGB(228, 235, 248), pets = Color3.fromRGB(116, 225, 210),
    misc = Color3.fromRGB(190, 190, 205)
}

local function updateTileBadge(tile, value, quantity, group, tierText, category, itemName)
    local container = tile and tile:FindFirstChild("Container")
    if not container then return end

    local existing = container:FindFirstChild("__SupremeItemValue")
    local hasTier = type(tierText) == "string" and tierText ~= ""
    if value == nil and not hasTier then
        -- Don't clutter the inventory with "N/A" or fake zero values.
        if existing and existing:IsA("TextLabel") then existing.Visible = false end
        return
    end

    local label = makeLabel(container, "__SupremeItemValue", group)
    label.BackgroundTransparency = 1
    label.BorderSizePixel = 0
    label.Font = Enum.Font.GothamBlack
    label.TextWrapped = false
    label.TextTruncate = Enum.TextTruncate.AtEnd
    label.TextScaled = true
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextXAlignment = Enum.TextXAlignment.Right
    label.TextSize = 13
    label.TextStrokeColor3 = Color3.fromRGB(4, 6, 10)
    label.TextStrokeTransparency = 0.12
    label.ZIndex = 100
    label.AnchorPoint = Vector2.new(1, 0)
    label.Position = UDim2.new(1, -3, 0, 3)
    label.Size = UDim2.new(1, -6, 0, 18)

    -- Remove the previous dark background treatment and use crisp text only.
    for _, child in ipairs(label:GetChildren()) do
        if child:IsA("UICorner") or child:IsA("UIStroke")
            or child:IsA("UIGradient") then
            child:Destroy()
        end
    end

    if value ~= nil then
        local accent = VALUE_TEXT_COLORS[category] or Color3.fromRGB(245, 248, 255)
        if normalize(itemName) == "emberbow" then
            accent = Color3.fromRGB(255, 75, 75)
        end
        label.Text = formatValue(value)
        label.TextColor3 = accent
    else
        label.Text = tostring(tierText):match("[Tt]%d+") or "TIER"
        label.TextColor3 = Color3.fromRGB(255, 190, 75)
    end
    label.Visible = true
end

local function scanRoot(root, group)
    local total, known, count, tierCount = 0, 0, 0, 0
    if not root then return total, known, count, tierCount end

    for _, tile in ipairs(getTiles(root)) do
        if not tile.Parent or tile.Visible == false then continue end
        local name, quantity = itemData(tile)
        local value, _, tierText, category = valueOf(tile, name)
        if value ~= nil then
            total = total + value * quantity
            known = known + quantity
        elseif tierText then
            known = known + quantity
            tierCount = tierCount + quantity
        end
        count = count + quantity
        if value == nil and not tierText and group == "inventory" then
            recordUnmatched(tile, name, quantity, state.unmatchedInventory)
        end
        updateTileBadge(tile, value, quantity, group, tierText, category, name)
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
        local value, _, tierText, category = valueOf(card, name)
        if value == nil and not tierText then
            local amountNode = card:FindFirstChild("Container")
                and card.Container:FindFirstChild("Amount")
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
        if value == nil and not tierText and group == "inventory" then
            recordUnmatched(card, name, quantity, state.unmatchedInventory)
        end
        updateTileBadge(card, value, quantity, group, tierText, category, name)
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
            if name or value ~= nil or tierText then
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
                if value == nil and not tierText then
                    recordUnmatched(tile, name, quantity, state.unmatchedTrade)
                end
                updateTileBadge(tile, value, quantity, group, tierText, category, name)
            end
        end
    end
    return items, total, known, count, tierCount
end

local function setSummary(parent, name, title, total, known, count, group, tierCount)
    if not parent then return end
    local label = makeLabel(parent, name, group)
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, 5)
    label.Size = UDim2.fromOffset(210, 22)
    label.BackgroundTransparency = 1
    label.TextSize = 14
    label.Font = Enum.Font.GothamBlack
    label.TextStrokeColor3 = Color3.fromRGB(5, 7, 12)
    label.TextStrokeTransparency = 0.14
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.TextColor3 = Color3.fromRGB(245, 250, 255)
    local gradient = label:FindFirstChild("SupremeTextGradient")
    if gradient then gradient:Destroy() end
    label.Text = title .. " " .. formatValue(total)
        .. ((tierCount or 0) > 0 and " +TIER(" .. tostring(tierCount) .. ")" or "")
        .. (known < count and " +?" or "")
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

local function setTradeVerdict(trade, yourTotal, theirTotal, yourKnown, theirKnown, yourCount, theirCount, yourTierCount, theirTierCount)
    if not trade then return end
    local label = makeLabel(trade, "__SupremeTradeVerdict", "trade")
    label.AnchorPoint = Vector2.new(0.5, 1)
    label.Position = UDim2.new(0.5, 0, 1, -5)
    label.Size = UDim2.fromOffset(210, 27)
    label.BackgroundTransparency = 1
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
    elseif yourTierCount > 0 or theirTierCount > 0 then
        caption, color = "TIER ITEMS", Color3.fromRGB(255, 190, 65)
    elseif yourKnown < yourCount or theirKnown < theirCount then
        caption, color = "CHECK UNKNOWN", Color3.fromRGB(255, 190, 65)
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
    label.Visible = true
end

local function scanTrade()
    state.unmatchedTrade = {}
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
    setSummary(yours, "__SupremeOfferTotal", "YOU", yourTotal, yourKnown, yourCount, "trade", yourTierCount)
    setSummary(theirs, "__SupremeOfferTotal", "THEM", theirTotal, theirKnown, theirCount, "trade", theirTierCount)
    setTradeVerdict(trade, yourTotal, theirTotal, yourKnown, theirKnown,
        yourCount, theirCount, yourTierCount, theirTierCount)

    local lines = {
        "YOUR OFFER NUMERIC: " .. formatValue(yourTotal)
            .. " (" .. tostring(yourKnown) .. "/" .. tostring(yourCount) .. " recognized, "
            .. tostring(yourTierCount) .. " tier)",
        "THEIR OFFER NUMERIC: " .. formatValue(theirTotal)
            .. " (" .. tostring(theirKnown) .. "/" .. tostring(theirCount) .. " recognized, "
            .. tostring(theirTierCount) .. " tier)"
    }
    if yourCount > 0 and theirCount > 0 then
        if yourTierCount > 0 or theirTierCount > 0 then
            table.insert(lines, "RESULT: TIER VALUES PRESENT — numeric WIN/LOSE disabled")
        elseif yourKnown < yourCount or theirKnown < theirCount then
            table.insert(lines, "RESULT: PARTIAL VALUES — check unknown items")
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
    local seen = {}

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
                local tile = entry.Frame
                if typeof(tile) ~= "Instance" or not tile:IsA("GuiObject") or seen[tile] then continue end
                seen[tile] = true
                frameCount = frameCount + 1
                if not tile.Parent then continue end
                if visible(tile) then visibleFrames = visibleFrames + 1 end

                -- Do not depend on ItemName text: PulseHub's inventory tiles
                -- are reliably identified by Container.Icon -> MM2 database.
                local name, quantity = itemData(tile)
                if type(entry.Amount) == "number" and quantity <= 1 then
                    quantity = math.max(1, math.floor(entry.Amount))
                end
                local resolvedValue, _, tierText, category = valueOf(tile, name)
                if resolvedValue ~= nil then
                    total = total + resolvedValue * quantity
                    known = known + quantity
                elseif tierText then
                    known = known + quantity
                    tierCount = tierCount + quantity
                end
                count = count + quantity
                if resolvedValue == nil and not tierText then
                    recordUnmatched(tile, name, quantity, state.unmatchedInventory)
                end
                updateTileBadge(tile, resolvedValue, quantity, "inventory", tierText, category)
            end
        end
    end

    scanCollection(data.Weapons, "Weapons")
    scanCollection(data.Pets, "Pets")

    local guiInstance = typeof(gui) == "Instance" and gui or nil
    if guiInstance then
        local guiTiles = getTiles(guiInstance)
        local _, guiKnown, guiCount = scanRoot(guiInstance, "inventoryOverlay")
        scanImageCards(guiInstance, "inventoryOverlay")
        state.inventoryGuiFrames = #guiTiles
        state.inventoryGuiValued = guiKnown or 0
        state.inventoryGuiItems = guiCount or 0
    else
        state.inventoryGuiFrames = 0
        state.inventoryGuiValued = 0
        state.inventoryGuiItems = 0
    end

    -- PulseHub's GUI reference is gui.MyInventory.Main.Weapons.Items.
    -- Put the running total on the visible inventory page when available.
    local guiInstance = typeof(gui) == "Instance" and gui or nil
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
    state.inventoryGroups = groupCount
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
panel.Position = UDim2.new(1, -12, 0, 88)
panel.AnchorPoint = Vector2.new(1, 0)
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

local copyButton = Instance.new("TextButton")
copyButton.Name = "CopySupremeDiagnostic"
copyButton.Size = UDim2.new(1, -20, 0, 32)
copyButton.Position = UDim2.new(0, 10, 1, -39)
copyButton.BackgroundColor3 = Color3.fromRGB(35, 125, 145)
copyButton.BorderSizePixel = 0
copyButton.Font = Enum.Font.GothamBold
copyButton.TextSize = 12
copyButton.TextColor3 = Color3.new(1, 1, 1)
copyButton.Text = "COPY FULL DIAGNOSTIC"
copyButton.ZIndex = 205
copyButton.Parent = panel

local collapsed = true
local expandedSize = UDim2.fromOffset(290, 225)
local collapsedSize = UDim2.fromOffset(150, 34)
local function setCollapsed(value)
    collapsed = value
    panel.Size = collapsed and collapsedSize or expandedSize
    output.Visible = not collapsed
    copyButton.Visible = not collapsed
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

local function buildDiagnostic()
    local lines = {
        "SUPREME TRADE CHECKER — PULSEHUB MAPPING",
        "Time: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Status: " .. tostring(state.status),
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
        "MM2 weapon records: " .. tostring(state.dbItems),
        "MM2 pet records: " .. tostring(state.dbPets),
        "Matched item records: " .. tostring(state.mappedCount),
        "Icon mappings: " .. tostring(state.iconCount),
        "Fetch methods: " .. HttpService:JSONEncode(state.fetchMethods),
        "Failed pages: " .. (#state.failedPages > 0 and table.concat(state.failedPages, " | ") or "none"),
        "Last error: " .. tostring(state.lastError or "none"),
        "",
        "CURRENT TRADE:",
        tostring(state.latestTrade),
        "",
        "CURRENT INVENTORY:",
        tostring(state.latestInventory),
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
        title.Text = collapsed and "SUPREME" or "SUPREME — READY"
    else
        title.Text = collapsed and "SUPREME" or "SUPREME — " .. string.upper(state.status)
    end
    output.Text = buildDiagnostic()
end

textGui.Destroying:Connect(function()
    stopped = true
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

print("[Supreme Trade Checker] PulseHub-style item mapping loaded.")
