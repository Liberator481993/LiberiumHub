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

local CATEGORIES = {
    "godlies", "chromas", "ancients", "legendaries", "rares",
    "uncommons", "commons", "vintages", "misc", "pets"
}
local MINIMUM = {
    godlies = 80, chromas = 30, commons = 150, uncommons = 100,
    rares = 80, legendaries = 40, ancients = 8, pets = 40
}
local RARITIES = {
    godlies = "Godly", ancients = "Ancient", legendaries = "Legendary",
    rares = "Rare", uncommons = "Uncommon", commons = "Common",
    vintages = "Classic"
}
local BASE = "https://www.supremevalues.com/mm2/"

local state = {
    status = "loading",
    mapped = nil,
    updated = 0,
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
    iconCount = 0,
    busy = false,
    latestTrade = "No active trade detected.",
    latestInventory = "Inventory not scanned yet."
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

-- Supreme Values stores the exact item amount in data-value and the item title
-- in itemhead. This is the same card-level parser used by PulseHub.
local function parseCategory(category, html, output)
    local count, cursor, scanned = 0, 1, 0
    while true do
        local first = html:find('<div class="itemcolumn"', cursor, true)
        if not first then break end
        local nextItem = html:find('<div class="itemcolumn"', first + 23, true)
        local card = html:sub(first, (nextItem or (#html + 1)) - 1)
        cursor = nextItem or (#html + 1)
        scanned = scanned + 1
        if scanned % 60 == 0 then task.wait() end

        local amount = tonumber(card:match('data%-value="([%d%.]+)"') or "")
        local nameMarkup = card:match('<div class="itemhead">(.-)</div>')
        local origin = decodeText(card:match('class="itemorigin">([^<]*)<') or "")
        if amount and amount < 500000 and nameMarkup and not origin:find("Deletion", 1, true) then
            local name = decodeText(nameMarkup)
            if name ~= "" then
                table.insert(output, {
                    c = category,
                    n = name,
                    v = amount,
                    y = card:match('data%-year="(%d%d%d%d)'),
                    e = card:match('data%-event="([^"]+)"'),
                    o = origin ~= "" and origin or nil,
                    cl = card:match("Class %- <b>([^<]+)</b>"),
                    dm = card:match('data%-demand="(%d+)"')
                })
                count = count + 1
            end
        end
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

    local function addIndex(name, entry)
        if name == "" then return end
        index[name] = index[name] or {}
        table.insert(index[name], entry)
    end

    for id, item in pairs(weapons) do
        if type(item) ~= "table" then continue end
        local name = tostring(item.ItemName or item.Name or "")
        local entry = {kind = "i", id = tostring(id), item = item}
        addIndex(normalize(name), entry)
        local withoutYear = name:gsub("%s*%d%d%d%d%s*$", "")
        if withoutYear ~= name then addIndex(normalize(withoutYear), entry) end
    end

    for id, item in pairs(pets) do
        if type(item) ~= "table" then continue end
        local entry = {kind = "p", id = tostring(id), item = item}
        addIndex("pet:" .. normalize(item.Name), entry)
        table.insert(petEntries, entry)
    end

    local byKey, mappedCount = {}, 0
    for entryIndex, value in ipairs(entries) do
        if entryIndex % 150 == 0 then task.wait() end
        local category, amount = value.c, tonumber(value.v)
        if type(category) ~= "string" or not amount then continue end

        local name, kind = tostring(value.n or ""), nil
        local baseName, suffix = name:match("^(.-)%s*%((%a+)%)%s*$")
        if baseName and (suffix == "Knife" or suffix == "Gun") then
            name, kind = baseName, suffix
        end

        local year = value.y
        baseName, suffix = name:match("^(.-)%s*%((%d%d%d%d)%)%s*$")
        if baseName then name, year = baseName, suffix end
        if not year and value.o then year = tostring(value.o):match("(20%d%d)") end

        local chroma = category == "chromas"
        if chroma then
            name = name:gsub("^Chroma%s+", ""):gsub("^C%.%s+", "")
        end

        local aliases = {name}
        local wrapping = name:match("^(%a+) Papers$")
        if wrapping then table.insert(aliases, "Box of " .. wrapping .. " Wrapping Paper") end
        if name == "Ultra Wrap" then table.insert(aliases, "Box of Ultra Wrapping Paper") end
        if name:sub(-1) == "s" then table.insert(aliases, name:sub(1, -2)) end
        if category == "legendaries" then
            local short = name:match("^%S+%s+(.+)$")
            if short then table.insert(aliases, short) end
        end

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
            if #filtered > 0 then matches = filtered end
        end

        if kind then filterMatches(function(item) return item.ItemType == kind end) end
        if #matches > 1 and value.cl then
            filterMatches(function(item) return item.Rarity == value.cl end)
        end
        if #matches > 1 then
            local previous = #matches
            if year then
                filterMatches(function(item) return tostring(item.Year or "") == tostring(year) end)
            end
            if #matches == previous then
                filterMatches(function(item) return not item.Year end)
            end
        end
        if #matches > 1 then
            local previous = #matches
            if value.e then
                filterMatches(function(item) return tostring(item.Event or "") == tostring(value.e) end)
            end
            if #matches == previous then
                filterMatches(function(item) return not item.Event end)
            end
        end

        for _, candidate in ipairs(matches) do
            local idKey = candidate.kind .. ":" .. candidate.id
            local previous = byKey[idKey]
            if not previous then mappedCount = mappedCount + 1 end
            if not previous or previous.n >= #matches then
                byKey[idKey] = {v = amount, n = #matches, name = name, category = category}
            end
        end
    end

    local icon, chromaOf, byName = {}, {}, {}
    local function addIcon(item, idKey)
        local image = assetId(item.Image)
        if image and not icon[image] then icon[image] = idKey end
    end

    for id, item in pairs(weapons) do
        if type(item) == "table" then addIcon(item, "i:" .. tostring(id)) end
    end
    for id, item in pairs(weapons) do
        if type(item) == "table" and not item.Chroma and item.ItemID then
            local imageId = tostring(item.ItemID)
            if not icon[imageId] then icon[imageId] = "i:" .. tostring(id) end
        end
    end
    for id, item in pairs(pets) do
        if type(item) == "table" then addIcon(item, "p:" .. tostring(id)) end
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
    local container = tile and tile:FindFirstChild("Container")
    local iconObject = container and container:FindFirstChild("Icon")
    local id = iconObject and assetId(iconObject.Image)
    local idKey = id and mapped.icon[id]

    if idKey and chroma then
        idKey = mapped.chromaOf[idKey] or idKey
    end
    if idKey and mapped.byKey[idKey] then
        return mapped.byKey[idKey].v, mapped.byKey[idKey].name
    end

    for _, candidate in ipairs(mapped.byName[normalize(name)] or {}) do
        if candidate.chroma == chroma and mapped.byKey[candidate.key] then
            local entry = mapped.byKey[candidate.key]
            return entry.v, entry.name
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
        local ok, err = pcall(function()
            local entries = {}
            local pageCount, parsedPages, entryCount = 0, 0, 0
            local failed, methods = {}, {}
            local categoryCounts = {}

            for _, category in ipairs(CATEGORIES) do
                if stopped then return end
                local html, fetchInfo = fetchPage(BASE .. category)
                if not html then
                    table.insert(failed, category .. ": " .. tostring(fetchInfo))
                else
                    pageCount = pageCount + 1
                    methods[fetchInfo] = (methods[fetchInfo] or 0) + 1
                    local count = parseCategory(category, html, entries)
                    categoryCounts[category] = count
                    if count > 0 then parsedPages = parsedPages + 1 end
                    entryCount = entryCount + count
                    local minimum = MINIMUM[category] or 1
                    if count < minimum then
                        table.insert(failed, category .. ": only " .. tostring(count)
                            .. " cards parsed (expected at least " .. tostring(minimum) .. ")")
                    end
                end
                task.wait(0.15)
            end

            state.pageCount = pageCount
            state.parsedPages = parsedPages
            state.entryCount = entryCount
            state.failedPages = failed
            state.fetchMethods = methods
            state.categoryCounts = categoryCounts

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
            state.lastUpdate = os.date("%H:%M:%S")
        end)

        if not ok then
            state.status = "fail"
            state.lastError = tostring(err)
        else
            state.lastError = nil
        end
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

local function getTiles(root)
    if not root then return {} end
    local now = os.clock()
    local cached = tileCache[root]
    if not cached or now - cached.at >= 1.2 then
        cached = {at = now, tiles = {}}
        local seen = {}
        for _, node in ipairs(root:GetDescendants()) do
            if node.Name == "ItemName" then
                local tile = node.Parent
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
        label.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
        label.BackgroundTransparency = 0.15
        label.TextColor3 = Color3.new(1, 1, 1)
        label.TextStrokeTransparency = 0.45
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Font = Enum.Font.GothamBold
        label.TextSize = 12
        label.BorderSizePixel = 0
        label.ZIndex = 90
        label.Parent = parent
    end
    label:SetAttribute("SupremeOwner", group)
    return label
end

local function updateTileBadge(tile, value, quantity, group)
    local container = tile and tile:FindFirstChild("Container")
    if not container then return end
    local label = container:FindFirstChild("__SupremeItemValue")
    if value == nil then
        if label and label:IsA("TextLabel") then
            label.Text = "?"
            label.Visible = true
        end
        return
    end
    label = makeLabel(container, "__SupremeItemValue", group)
    local shown = tostring(math.floor(value + 0.5))
    local text = shown
    if quantity and quantity > 1 then
        text = text .. " x" .. tostring(quantity) .. " = " .. tostring(math.floor(value * quantity + 0.5))
    end
    local height = math.clamp(math.floor(container.AbsoluteSize.Y * 0.19 + 0.5), 14, 24)
    label.Position = UDim2.fromOffset(3, 3)
    label.Size = UDim2.fromOffset(math.max(height * 2, #text * height * 0.55 + 12), height)
    label.TextSize = math.max(10, math.floor(height * 0.82))
    label.Text = " " .. text
    label.Visible = true
end

local function scanRoot(root, group)
    local total, known, count = 0, 0, 0
    if not root then return total, known, count end

    for _, tile in ipairs(getTiles(root)) do
        if not tile.Parent or tile.Visible == false then continue end
        local name, quantity = itemData(tile)
        local value = valueOf(tile, name)
        if value ~= nil then
            total = total + value * quantity
            known = known + quantity
        end
        count = count + quantity
        updateTileBadge(tile, value, quantity, group)
    end
    return total, known, count
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
    if not container then return {}, 0, 0, 0 end

    local items, total, known, count = {}, 0, 0, 0
    local seen = {}
    for _, tile in ipairs(container:GetChildren()) do
        if tile:IsA("GuiObject") and tile.Visible and not seen[tile] then
            seen[tile] = true
            local name, quantity = itemData(tile)
            local value, resolvedName = valueOf(tile, name)
            if name or value ~= nil then
                table.insert(items, {name = resolvedName or name or "Unknown item", value = value, quantity = quantity})
                count = count + quantity
                if value ~= nil then
                    total = total + value * quantity
                    known = known + quantity
                end
                updateTileBadge(tile, value, quantity, group)
            end
        end
    end
    return items, total, known, count
end

local function setSummary(parent, name, title, total, known, count, group)
    if not parent then return end
    local label = makeLabel(parent, name, group)
    label.AnchorPoint = Vector2.new(0.5, 0)
    label.Position = UDim2.new(0.5, 0, 0, 5)
    label.Size = UDim2.fromOffset(130, 22)
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Center
    label.Text = title .. " " .. tostring(math.floor(total + 0.5))
        .. (known < count and " +?" or "")
    label.Visible = count > 0
end

local function getVerdict(give, get)
    local difference = get - give
    if math.abs(difference) <= math.max(0.02 * math.max(give, get), 0.005) then
        return "FAIR", difference
    end
    return difference > 0 and "WIN" or "LOSE", difference
end

local function scanTrade()
    local screen, container, trade = findTrade()
    if not screen then
        state.latestTrade = "No active trade detected."
        return nil
    end

    local yours = trade:FindFirstChild("YourOffer", true)
    local theirs = trade:FindFirstChild("TheirOffer", true)
    if not yours and container then yours = container:FindFirstChild("YourOffer", true) end
    if not theirs and container then theirs = container:FindFirstChild("TheirOffer", true) end

    local yourItems, yourTotal, yourKnown, yourCount = scanOffer(yours, "trade")
    local theirItems, theirTotal, theirKnown, theirCount = scanOffer(theirs, "trade")
    setSummary(yours, "__SupremeOfferTotal", "YOU", yourTotal, yourKnown, yourCount, "trade")
    setSummary(theirs, "__SupremeOfferTotal", "THEM", theirTotal, theirKnown, theirCount, "trade")

    local lines = {
        "YOUR OFFER: " .. tostring(math.floor(yourTotal + 0.5))
            .. " (" .. tostring(yourKnown) .. "/" .. tostring(yourCount) .. " valued)",
        "THEIR OFFER: " .. tostring(math.floor(theirTotal + 0.5))
            .. " (" .. tostring(theirKnown) .. "/" .. tostring(theirCount) .. " valued)"
    }
    if yourCount > 0 and theirCount > 0 then
        local verdict, difference = getVerdict(yourTotal, theirTotal)
        table.insert(lines, "RESULT: " .. verdict .. " | Difference: "
            .. (difference > 0 and "+" or "") .. tostring(math.floor(difference + 0.5)))
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
        theirCount = theirCount
    }
end

local function findActualInventory()
    for _, guiName in ipairs({"MainGUI", "MainMobile"}) do
        local screen = playerGui:FindFirstChild(guiName)
        if screen and screen:IsA("ScreenGui") and screen.Enabled then
            local gameFrame = screen:FindFirstChild("Game")
            local inventory = gameFrame and gameFrame:FindFirstChild("Inventory")
            if inventory and visible(inventory) then return inventory end
        end
    end
    return nil
end

local function scanInventory()
    local inventory = findActualInventory()
    local weaponTotal, weaponKnown, weaponCount = 0, 0, 0
    local petTotal, petKnown, petCount = 0, 0, 0

    if inventory then
        local main = inventory:FindFirstChild("Main")
        local weapons = main and main:FindFirstChild("Weapons")
        local pets = main and main:FindFirstChild("Pets")
        local weaponRoot = weapons and weapons:FindFirstChild("Items")
        local petRoot = pets and pets:FindFirstChild("Items")
        weaponTotal, weaponKnown, weaponCount = scanRoot(weaponRoot, "inventory")
        petTotal, petKnown, petCount = scanRoot(petRoot, "inventory")

        local invLabel = makeLabel(inventory, "__SupremeInventoryTotal", "inventory")
        invLabel.AnchorPoint = Vector2.new(0, 1)
        invLabel.Position = UDim2.new(0, 4, 1, -5)
        invLabel.Size = UDim2.fromOffset(290, 28)
        invLabel.TextSize = 12
        invLabel.Text = "INV " .. tostring(math.floor(weaponTotal + petTotal + 0.5))
            .. " | W " .. tostring(math.floor(weaponTotal + 0.5))
            .. " | P " .. tostring(math.floor(petTotal + 0.5))
        invLabel.Visible = weaponCount + petCount > 0
    end

    -- The trade screen has its own inventory list. Support the exact _mO path
    -- reported by this MM2 client, as well as PulseHub's Items.Main layout.
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
                end
            end
        end
    end

    local total = weaponTotal + petTotal
    local known = weaponKnown + petKnown
    local count = weaponCount + petCount
    state.latestInventory = inventory and (
        "INVENTORY TOTAL: " .. tostring(math.floor(total + 0.5))
        .. " | Weapons: " .. tostring(math.floor(weaponTotal + 0.5))
        .. " | Pets: " .. tostring(math.floor(petTotal + 0.5))
        .. " | Valued: " .. tostring(known) .. "/" .. tostring(count)
    ) or "MainGUI/MainMobile inventory not visible; trade inventory path scanned."
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

local function buildDiagnostic()
    local lines = {
        "SUPREME TRADE CHECKER — PULSEHUB MAPPING",
        "Time: " .. os.date("%Y-%m-%d %H:%M:%S"),
        "Status: " .. tostring(state.status),
        "Values source: " .. BASE,
        "Pages fetched: " .. tostring(state.pageCount) .. "/" .. tostring(#CATEGORIES),
        "Pages parsed: " .. tostring(state.parsedPages),
        "Supreme entries: " .. tostring(state.entryCount),
        "Category counts: " .. HttpService:JSONEncode(state.categoryCounts or {}),
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
        tostring(state.latestInventory)
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
