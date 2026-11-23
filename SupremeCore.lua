-- SupremeCore.lua  v1.0.0
-- Pure calculation core for the MM2 Supreme Trade Checker.
--
-- No Roblox APIs, no executor APIs, no GUI. Plain Lua 5.1+/Luau.
-- Everything (trade offer, trade receive, inventory) goes through the same
-- functions: NormalizeItem -> ResolveItem -> GetItemValue -> CalculateSide.
--
-- Terminology
--   record : one row of the value database (one exact MM2 item) built by BuildIndex
--   item   : one thing seen in a UI/inventory (may carry a quantity)
--   side   : a list of items (offer, receive or inventory)

local Core = {}
Core.VERSION = "1.0.0"

Core.STATUS = { VALUED = "valued", TIER = "tier", ZERO = "zero", UNKNOWN = "unknown" }
Core.WARNING_TEXT = "ТРЕБУЕТСЯ РУЧНАЯ ПРОВЕРКА"

Core.DEFAULTS = {
    fairTolerance = 0.02,      -- relative to the LARGER side total (2%)
    fairMinAbsolute = 0,       -- optional absolute floor for FAIR
    maxQuantity = 1000000000,  -- quantities above this are clamped AND flagged
}

local MUL = "\195\151" -- UTF-8 "×"

----------------------------------------------------------------------------
-- small helpers
----------------------------------------------------------------------------
local function isFinite(x)
    return type(x) == "number" and x == x and x ~= math.huge and x ~= -math.huge
end
Core.IsFinite = isFinite

local function trim(s)
    s = tostring(s == nil and "" or s)
    s = s:gsub("[%c]", " "):gsub("%s+", " ")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

function Core.NormalizeName(s)
    local lowered = string.lower(trim(s))
    local n = lowered:gsub("[^%w]", "")
    if n == "" then return lowered end -- non-ASCII names: keep something comparable
    return n
end

local function lowerOrNil(v)
    if v == nil then return nil end
    local s = string.lower(trim(v))
    if s == "" then return nil end
    return s
end

local function digitsOrNil(v)
    if v == nil then return nil end
    local s = tostring(v)
    local d = s:match("rbxassetid://(%d+)") or s:match("[?&]id=(%d+)")
        or s:match("[?&][Aa]sset[Ii][Dd]=(%d+)") or s:match("^%s*(%d+)%s*$")
    return d
end
Core.AssetId = digitsOrNil

--- Format a number for display: thousands separators, trims zeros, keeps tiny values visible.
function Core.FormatValue(n)
    if not isFinite(n) then return "?" end
    if n == 0 then return "0" end
    local sign = n < 0 and "-" or ""
    local a = math.abs(n)
    if a < 1e-6 then return sign .. string.format("%.3e", a) end
    local s = string.format("%.6f", a)
    local int, frac = s:match("^(%d+)%.(%d+)$")
    frac = frac:gsub("0+$", "")
    int = int:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    int = int:gsub("^,", "")
    return sign .. int .. (frac ~= "" and ("." .. frac) or "")
end

----------------------------------------------------------------------------
-- quantity
----------------------------------------------------------------------------
--- Returns quantity (>=1, finite) and an optional warning code.
--- Never silently changes a quantity: every correction yields a warning.
function Core.ParseQuantity(raw, maxQuantity)
    local maxQ = maxQuantity or Core.DEFAULTS.maxQuantity
    if raw == nil then return 1, nil end
    local n
    if type(raw) == "number" then
        if raw ~= raw or raw == -math.huge then return 1, "quantity_invalid" end
        n = raw
    elseif type(raw) == "string" then
        if raw:match("^%s*$") then return 1, nil end
        local s = raw:gsub("[%s,]", "")
        if s:sub(1, 2) == MUL then s = s:sub(3)
        elseif s:sub(-2) == MUL then s = s:sub(1, -3)
        elseif s:sub(1, 1):lower() == "x" then s = s:sub(2)
        elseif s:sub(-1):lower() == "x" then s = s:sub(1, -2) end
        if not s:match("^%d+$") then return 1, "quantity_unparsed" end
        n = tonumber(s)
        if n == nil then return 1, "quantity_unparsed" end
    else
        return 1, "quantity_invalid"
    end
    n = n + 0.0
    if n == math.huge then return maxQ + 0.0, "quantity_clamped" end
    if n < 1 then return 1, "quantity_invalid" end
    local warn
    if n ~= math.floor(n) then n = math.floor(n); warn = "quantity_fractional" end
    if n > maxQ then return maxQ + 0.0, "quantity_clamped" end
    return n, warn
end

----------------------------------------------------------------------------
-- NormalizeItem
----------------------------------------------------------------------------
--- raw fields (all optional, but at least key/iconId/name should be present):
---   uid (any non-nil value identifying the physical slot/card; used to prevent double counting)
---   key (exact value-database key, e.g. "i:ChromaShark"), name, itemType, iconId,
---   chroma (true/false/nil=unknown), category, rarity, year, event, quantity (number|string|nil)
--- Returns a normalized item, or nil + error code.
function Core.NormalizeItem(raw, opts)
    if type(raw) ~= "table" then return nil, "item_not_table" end
    local maxQ = opts and opts.maxQuantity or Core.DEFAULTS.maxQuantity
    local qty, qwarn = Core.ParseQuantity(raw.quantity, maxQ)
    local name = trim(raw.name)
    local chroma
    if raw.chroma == true then chroma = true elseif raw.chroma == false then chroma = false end
    return {
        uid = raw.uid,
        key = (raw.key ~= nil and tostring(raw.key) ~= "") and tostring(raw.key) or nil,
        name = name ~= "" and name or nil,
        nname = name ~= "" and Core.NormalizeName(name) or nil,
        itemType = lowerOrNil(raw.itemType),
        iconId = digitsOrNil(raw.iconId),
        chroma = chroma,
        category = lowerOrNil(raw.category),
        rarity = lowerOrNil(raw.rarity),
        year = lowerOrNil(raw.year),
        event = lowerOrNil(raw.event),
        quantity = qty,
        quantityWarning = qwarn,
    }
end

----------------------------------------------------------------------------
-- value index
----------------------------------------------------------------------------
local function addTo(map, k, rec)
    if k == nil or k == "" then return end
    local list = map[k]
    if not list then list = {}; map[k] = list end
    if list[#list] ~= rec then list[#list + 1] = rec end
end

local function sameValueData(a, b)
    return tostring(a.value) == tostring(b.value) and a.tier == b.tier
end

local indexCounter = 0

--- records: array of {key, name, aliases?, itemType?, iconId?, chroma?, category?,
---                    rarity?, year?, event?, value?, tier?}
--- `key` is the unique MM2 database id and MUST be unique per exact item.
--- Duplicate keys with different values are marked as conflicts (never guessed).
function Core.BuildIndex(records)
    indexCounter = indexCounter + 1
    local index = {
        version = indexCounter,
        byKey = {}, byIcon = {}, byName = {},
        count = 0, rejected = {}, conflicts = {},
    }
    for i, rec in ipairs(records or {}) do
        if type(rec) ~= "table" then
            index.rejected[#index.rejected + 1] = { index = i, reason = "record_not_table" }
        elseif rec.key == nil or tostring(rec.key) == "" then
            index.rejected[#index.rejected + 1] = { index = i, reason = "missing_key" }
        elseif trim(rec.name) == "" then
            index.rejected[#index.rejected + 1] = { index = i, reason = "missing_name" }
        else
            local key = tostring(rec.key)
            local r = {
                key = key,
                name = trim(rec.name),
                itemType = lowerOrNil(rec.itemType),
                iconId = digitsOrNil(rec.iconId),
                chroma = rec.chroma == true,
                category = lowerOrNil(rec.category),
                rarity = lowerOrNil(rec.rarity),
                year = lowerOrNil(rec.year),
                event = lowerOrNil(rec.event),
                value = rec.value,
                tier = (type(rec.tier) == "string" and trim(rec.tier) ~= "") and trim(rec.tier) or nil,
                nameSet = {},
            }
            local existing = index.byKey[key]
            if existing then
                if not sameValueData(existing, r) then
                    existing.conflict = true
                    index.conflicts[#index.conflicts + 1] = key
                end
            else
                index.byKey[key] = r
                index.count = index.count + 1
                addTo(index.byIcon, r.iconId, r)
                local names = { r.name }
                if type(rec.aliases) == "table" then
                    for _, a in ipairs(rec.aliases) do names[#names + 1] = a end
                end
                for _, nm in ipairs(names) do
                    local nn = Core.NormalizeName(nm)
                    if nn ~= "" and not r.nameSet[nn] then
                        r.nameSet[nn] = true
                        addTo(index.byName, nn, r)
                    end
                end
            end
        end
    end
    return index
end

----------------------------------------------------------------------------
-- GetItemValue
----------------------------------------------------------------------------
local function numericFromValue(v)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local s = v:gsub("[%s,]", "")
        if s:match("^%d+%.?%d*$") then return tonumber(s) end
    end
    return nil
end

--- Returns status, value, tier, reason for ONE record.
function Core.GetItemValue(record)
    local S = Core.STATUS
    if type(record) ~= "table" then return S.UNKNOWN, nil, nil, "no_record" end
    if record.conflict then return S.UNKNOWN, nil, nil, "value_conflict" end
    local tier = record.tier
    local n = numericFromValue(record.value)
    if n ~= nil and isFinite(n) then
        if n > 0 then return S.VALUED, n + 0.0, nil, nil end
        if n == 0 then
            if tier then return S.TIER, nil, tier, nil end
            return S.ZERO, nil, nil, "zero_value"
        end
    end
    if tier then return S.TIER, nil, tier, nil end
    if record.value ~= nil then return S.UNKNOWN, nil, nil, "invalid_value" end
    return S.UNKNOWN, nil, nil, "no_value"
end

----------------------------------------------------------------------------
-- ResolveItem
----------------------------------------------------------------------------
local function passes(rec, item)
    if item.chroma ~= nil and rec.chroma ~= item.chroma then return false end
    if item.itemType and rec.itemType and item.itemType ~= rec.itemType then return false end
    if item.category and rec.category and item.category ~= rec.category then return false end
    if item.rarity and rec.rarity and item.rarity ~= rec.rarity then return false end
    if item.year and rec.year and item.year ~= rec.year then return false end
    if item.event and rec.event and item.event ~= rec.event then return false end
    return true
end

local function filter(list, item)
    local out = {}
    for _, rec in ipairs(list or {}) do
        if passes(rec, item) then out[#out + 1] = rec end
    end
    return out
end

local function finish(rec, matchedBy)
    local status, value, tier, reason = Core.GetItemValue(rec)
    return { status = status, record = rec, matchedBy = matchedBy,
             value = value, tier = tier, reason = reason }
end

local function unknown(reason, extra)
    local r = { status = Core.STATUS.UNKNOWN, reason = reason }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end

--- Strongest identifier first: exact key -> icon -> normalized name.
--- An identifier that points to something NEVER falls through to a weaker one
--- (so an unvalued chroma can't inherit the regular item's price).
--- Ambiguity is never guessed: it returns status "unknown".
function Core.ResolveItem(index, item)
    if type(index) ~= "table" or type(index.byKey) ~= "table" then
        return unknown("no_index")
    end
    if type(item) ~= "table" then return unknown("bad_item") end

    -- 1. unique MM2 database id
    if item.key then
        local rec = index.byKey[item.key]
        if not rec then return unknown("id_without_value") end
        if item.chroma ~= nil and rec.chroma ~= item.chroma then return unknown("chroma_mismatch") end
        if item.itemType and rec.itemType and item.itemType ~= rec.itemType then
            return unknown("type_mismatch")
        end
        return finish(rec, "id")
    end

    -- 2. icon asset id (+ chroma/type/category/rarity/year/event filters)
    local pool
    if item.iconId then
        local byIcon = index.byIcon[item.iconId]
        if byIcon then
            local f = filter(byIcon, item)
            if #f == 1 then return finish(f[1], "icon") end
            if #f == 0 then return unknown("icon_filter_mismatch") end
            pool = f -- several records share the icon: narrow down by name below
        end
    end

    -- 3. normalized name, only as a fallback and only if it yields exactly one record
    if item.nname then
        local base = pool
        if not base then
            base = index.byName[item.nname]
        else
            local narrowed = {}
            for _, rec in ipairs(pool) do
                if rec.nameSet[item.nname] then narrowed[#narrowed + 1] = rec end
            end
            base = narrowed
        end
        local f = filter(base, item)
        if #f == 1 then return finish(f[1], "name") end
        if #f == 0 then return unknown("no_match") end
        return unknown("ambiguous_name", { candidates = #f })
    end
    if pool then return unknown("ambiguous_icon", { candidates = #pool }) end
    return unknown(item.iconId and "icon_not_in_values" or "no_identifiers")
end

----------------------------------------------------------------------------
-- CalculateSide
----------------------------------------------------------------------------
local function newSide()
    return {
        total = 0.0, itemCount = 0,
        valuedCount = 0, tierCount = 0, zeroCount = 0, unknownCount = 0,
        lines = {}, warnings = {}, duplicatesSkipped = 0, invalidSkipped = 0,
        needsReview = false, complete = true,
    }
end

--- items: array of raw items (see NormalizeItem). Returns a side table.
--- contribution = unit value * quantity; only VALUED items add to `total`.
function Core.CalculateSide(index, items, opts)
    local side = newSide()
    local seenUid, lineMap = {}, {}
    local S = Core.STATUS
    for i, raw in ipairs(items or {}) do
        local item, err = Core.NormalizeItem(raw, opts)
        if not item then
            side.invalidSkipped = side.invalidSkipped + 1
            side.warnings[#side.warnings + 1] = { code = err, index = i }
        elseif item.uid ~= nil and seenUid[item.uid] then
            side.duplicatesSkipped = side.duplicatesSkipped + 1
        else
            if item.uid ~= nil then seenUid[item.uid] = true end
            if item.quantityWarning then
                side.warnings[#side.warnings + 1] =
                    { code = item.quantityWarning, index = i, name = item.name }
            end
            local res = Core.ResolveItem(index, item)
            local status, reason, contribution = res.status, res.reason, 0.0
            if status == S.VALUED then
                contribution = res.value * item.quantity
                local newTotal = side.total + contribution
                if not isFinite(contribution) or not isFinite(newTotal) then
                    status, reason, contribution = S.UNKNOWN, "overflow", 0.0
                    side.warnings[#side.warnings + 1] = { code = "overflow", index = i, name = item.name }
                end
            end
            local rec = res.record
            local base = rec and rec.key
                or ("?|" .. (item.nname or "") .. "|" .. (item.iconId or "") .. "|" .. tostring(item.chroma))
            local lineKey = status .. "|" .. base
            local line = lineMap[lineKey]
            if not line then
                line = {
                    key = rec and rec.key or nil,
                    name = (rec and rec.name) or item.name or "?",
                    status = status, reason = reason, matchedBy = res.matchedBy,
                    unitValue = (status == S.VALUED) and res.value or nil,
                    tier = (status == S.TIER) and res.tier or nil,
                    chroma = rec and rec.chroma or item.chroma,
                    quantity = 0.0, contribution = 0.0,
                }
                lineMap[lineKey] = line
                side.lines[#side.lines + 1] = line
            end
            line.quantity = line.quantity + item.quantity
            line.contribution = line.contribution + contribution
            side.itemCount = side.itemCount + item.quantity
            side.total = side.total + contribution
            if status == S.VALUED then side.valuedCount = side.valuedCount + item.quantity
            elseif status == S.TIER then side.tierCount = side.tierCount + item.quantity
            elseif status == S.ZERO then side.zeroCount = side.zeroCount + item.quantity
            else side.unknownCount = side.unknownCount + item.quantity end
        end
    end
    local quantityProblem = false
    for _, w in ipairs(side.warnings) do
        if w.code ~= "quantity_fractional" or true then quantityProblem = true end
    end
    side.needsReview = side.tierCount > 0 or side.zeroCount > 0 or side.unknownCount > 0
        or quantityProblem
    side.complete = not side.needsReview
    return side
end
Core.CalculateInventory = Core.CalculateSide -- inventory uses the very same path

----------------------------------------------------------------------------
-- verdict
----------------------------------------------------------------------------
local function resolveConfig(opts)
    local cfg = {
        fairTolerance = Core.DEFAULTS.fairTolerance,
        fairMinAbsolute = Core.DEFAULTS.fairMinAbsolute,
        maxQuantity = Core.DEFAULTS.maxQuantity,
    }
    local warnings = {}
    if type(opts) == "table" then
        if opts.fairTolerance ~= nil then
            if isFinite(opts.fairTolerance) and opts.fairTolerance >= 0 and opts.fairTolerance <= 1 then
                cfg.fairTolerance = opts.fairTolerance
            else
                warnings[#warnings + 1] = "fairTolerance_invalid_default_used"
            end
        end
        if opts.fairMinAbsolute ~= nil then
            if isFinite(opts.fairMinAbsolute) and opts.fairMinAbsolute >= 0 then
                cfg.fairMinAbsolute = opts.fairMinAbsolute
            else
                warnings[#warnings + 1] = "fairMinAbsolute_invalid_default_used"
            end
        end
        if opts.maxQuantity ~= nil then
            if isFinite(opts.maxQuantity) and opts.maxQuantity >= 1 then
                cfg.maxQuantity = math.floor(opts.maxQuantity)
            else
                warnings[#warnings + 1] = "maxQuantity_invalid_default_used"
            end
        end
    end
    return cfg, warnings
end

--- difference = receive - offer. Tolerance is relative to the larger side.
--- Returns "WIN"|"FAIR"|"LOSE", difference   (or nil, nil, "invalid_totals")
function Core.GetTradeVerdict(offerTotal, receiveTotal, opts)
    if not isFinite(offerTotal) or not isFinite(receiveTotal) then
        return nil, nil, "invalid_totals"
    end
    local cfg = resolveConfig(opts)
    local diff = receiveTotal - offerTotal
    local larger = math.max(math.abs(offerTotal), math.abs(receiveTotal))
    local tol = math.max(larger * cfg.fairTolerance, cfg.fairMinAbsolute) + larger * 1e-12
    if math.abs(diff) <= tol then return "FAIR", diff end
    return (diff > 0) and "WIN" or "LOSE", diff
end

----------------------------------------------------------------------------
-- CalculateTrade
----------------------------------------------------------------------------
--- offerItems = what the player GIVES, receiveItems = what the player GETS.
--- state: "empty" | "one_sided" | "no_numeric" | "ready"
--- A verdict exists only when state == "ready". `reliable` is true only when
--- the verdict is based on complete data (nothing unknown/tier/zero/invalid).
function Core.CalculateTrade(index, offerItems, receiveItems, opts)
    local cfg, cfgWarnings = resolveConfig(opts)
    local calcOpts = { maxQuantity = cfg.maxQuantity }
    local offer = Core.CalculateSide(index, offerItems, calcOpts)
    local receive = Core.CalculateSide(index, receiveItems, calcOpts)

    local result = {
        offer = offer, receive = receive, config = cfg,
        configWarnings = cfgWarnings, reviewReasons = {},
    }
    result.difference = receive.total - offer.total

    if offer.itemCount == 0 and receive.itemCount == 0 then result.state = "empty"
    elseif offer.itemCount == 0 or receive.itemCount == 0 then result.state = "one_sided"
    elseif offer.valuedCount == 0 and receive.valuedCount == 0 then result.state = "no_numeric"
    else result.state = "ready" end

    if result.state == "ready" then
        result.verdict, result.difference = Core.GetTradeVerdict(offer.total, receive.total, cfg)
    end

    local reasons = result.reviewReasons
    if offer.unknownCount + receive.unknownCount > 0 then reasons[#reasons + 1] = "unknown_items" end
    if offer.tierCount + receive.tierCount > 0 then reasons[#reasons + 1] = "tier_only_items" end
    if offer.zeroCount + receive.zeroCount > 0 then reasons[#reasons + 1] = "zero_value_items" end
    if #offer.warnings + #receive.warnings > 0 then reasons[#reasons + 1] = "data_warnings" end
    if #cfgWarnings > 0 then reasons[#reasons + 1] = "config_warnings" end
    result.needsReview = #reasons > 0 and result.state ~= "empty"

    local ok, errors = Core.ValidateCalculation(result)
    result.validation = { ok = ok, errors = errors }
    if not ok then
        reasons[#reasons + 1] = "validation_failed"
        result.needsReview = true
    end
    result.reliable = (result.state == "ready") and not result.needsReview
    result.warning = result.needsReview and Core.WARNING_TEXT or nil
    return result
end

----------------------------------------------------------------------------
-- ValidateCalculation
----------------------------------------------------------------------------
local function near(a, b)
    if not isFinite(a) or not isFinite(b) then return false end
    return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(a), math.abs(b))
end

local function validateSide(side, label, errs)
    if type(side) ~= "table" then errs[#errs + 1] = label .. ": missing side"; return end
    local sumTotal, sumQty = 0.0, 0.0
    local counts = { valued = 0.0, tier = 0.0, zero = 0.0, unknown = 0.0 }
    for _, line in ipairs(side.lines or {}) do
        if not isFinite(line.quantity) or line.quantity < 1 then
            errs[#errs + 1] = label .. ": bad line quantity for " .. tostring(line.name)
        end
        if not isFinite(line.contribution) or line.contribution < 0 then
            errs[#errs + 1] = label .. ": bad contribution for " .. tostring(line.name)
        end
        if line.status == "valued" then
            if not near(line.contribution, (line.unitValue or 0) * line.quantity) then
                errs[#errs + 1] = label .. ": contribution != value*quantity for " .. tostring(line.name)
            end
        elseif line.contribution ~= 0 then
            errs[#errs + 1] = label .. ": non-valued line has contribution: " .. tostring(line.name)
        end
        if counts[line.status] == nil then
            errs[#errs + 1] = label .. ": bad status " .. tostring(line.status)
        else
            counts[line.status] = counts[line.status] + line.quantity
        end
        sumTotal = sumTotal + (isFinite(line.contribution) and line.contribution or 0)
        sumQty = sumQty + (isFinite(line.quantity) and line.quantity or 0)
    end
    if not isFinite(side.total) or side.total < 0 then errs[#errs + 1] = label .. ": bad total" end
    if not near(sumTotal, side.total) then errs[#errs + 1] = label .. ": total != sum of lines" end
    if not near(sumQty, side.itemCount) then errs[#errs + 1] = label .. ": itemCount != sum of quantities" end
    if not near(counts.valued, side.valuedCount) or not near(counts.tier, side.tierCount)
        or not near(counts.zero, side.zeroCount) or not near(counts.unknown, side.unknownCount) then
        errs[#errs + 1] = label .. ": status counts do not match lines"
    end
end

--- Re-derives every number from the lines and checks invariants.
--- Returns ok(boolean), errors(array of strings).
function Core.ValidateCalculation(result)
    local errs = {}
    if type(result) ~= "table" then return false, { "result is not a table" } end
    validateSide(result.offer, "offer", errs)
    validateSide(result.receive, "receive", errs)
    if #errs == 0 then
        if not near(result.difference, result.receive.total - result.offer.total) then
            errs[#errs + 1] = "difference != receive - offer"
        end
        local o, r = result.offer, result.receive
        local expectState
        if o.itemCount == 0 and r.itemCount == 0 then expectState = "empty"
        elseif o.itemCount == 0 or r.itemCount == 0 then expectState = "one_sided"
        elseif o.valuedCount == 0 and r.valuedCount == 0 then expectState = "no_numeric"
        else expectState = "ready" end
        if result.state ~= expectState then errs[#errs + 1] = "state inconsistent" end
        if result.state == "ready" then
            local v = Core.GetTradeVerdict(o.total, r.total, result.config)
            if v ~= result.verdict then errs[#errs + 1] = "verdict inconsistent" end
        elseif result.verdict ~= nil then
            errs[#errs + 1] = "verdict present while state is " .. tostring(result.state)
        end
    end
    return #errs == 0, errs
end

----------------------------------------------------------------------------
-- BuildTradeReport
----------------------------------------------------------------------------
local function describeLine(line)
    local qty = Core.FormatValue(line.quantity)
    local head = "  " .. tostring(line.name) .. (line.chroma and " [Chroma]" or "") .. " ×" .. qty
    if line.status == "valued" then
        return head .. " — " .. Core.FormatValue(line.unitValue) .. " = " .. Core.FormatValue(line.contribution)
    elseif line.status == "tier" then
        return head .. " — TIER (" .. tostring(line.tier) .. ")"
    elseif line.status == "zero" then
        return head .. " — VALUE 0 (не подтверждено)"
    end
    return head .. " — НЕИЗВЕСТНО"
end

local function sideLines(title, side, out)
    out[#out + 1] = title .. ":"
    if #side.lines == 0 then out[#out + 1] = "  (пусто)" end
    for _, line in ipairs(side.lines) do out[#out + 1] = describeLine(line) end
    out[#out + 1] = string.format("  Итого: %s  (оценено %s, tier %s, неизвестно %s)",
        Core.FormatValue(side.total), Core.FormatValue(side.valuedCount),
        Core.FormatValue(side.tierCount), Core.FormatValue(side.unknownCount + side.zeroCount))
end

--- Presentation-ready summary (plain data + text). Does no UI work.
function Core.BuildTradeReport(result)
    if type(result) ~= "table" or not result.offer then
        return { state = "none", text = "Нет активного обмена.", lines = { "Нет активного обмена." } }
    end
    local o, r = result.offer, result.receive
    local lines = {}
    sideLines("ОТДАЁШЬ", o, lines)
    sideLines("ПОЛУЧАЕШЬ", r, lines)

    local headline
    if result.state == "empty" then headline = "ОЖИДАНИЕ ПРЕДМЕТОВ"
    elseif result.state == "one_sided" then headline = "ОДНА СТОРОНА ПУСТА"
    elseif result.state == "no_numeric" then headline = "НЕТ ЧИСЛОВЫХ VALUE"
    else
        local sign = result.difference > 0 and "+" or ""
        headline = result.verdict .. "  " .. sign .. Core.FormatValue(result.difference)
        if not result.reliable then headline = headline .. "  (предварительно)" end
    end
    lines[#lines + 1] = "РЕЗУЛЬТАТ: " .. headline
    lines[#lines + 1] = string.format("Неизвестных: %s | Tier-only: %s | Value 0: %s",
        Core.FormatValue(o.unknownCount + r.unknownCount),
        Core.FormatValue(o.tierCount + r.tierCount),
        Core.FormatValue(o.zeroCount + r.zeroCount))
    if result.warning then lines[#lines + 1] = "!!! " .. result.warning end

    return {
        state = result.state, verdict = result.verdict, difference = result.difference,
        headline = headline,
        offerTotal = o.total, receiveTotal = r.total,
        unknownCount = o.unknownCount + r.unknownCount,
        tierCount = o.tierCount + r.tierCount,
        zeroCount = o.zeroCount + r.zeroCount,
        reliable = result.reliable, needsReview = result.needsReview,
        warning = result.warning,
        lines = lines, text = table.concat(lines, "\n"),
    }
end

----------------------------------------------------------------------------
-- Session: change detection and clean reset when the trade closes
----------------------------------------------------------------------------
local Session = {}
Session.__index = Session

function Core.NewSession(opts)
    return setmetatable({ opts = opts, result = nil, signature = nil, indexRef = nil, version = 0 }, Session)
end

local function sideSignature(items)
    local parts = {}
    for i, it in ipairs(items or {}) do
        if type(it) == "table" then
            parts[i] = table.concat({
                tostring(it.uid), tostring(it.key), tostring(it.name), tostring(it.iconId),
                tostring(it.chroma), tostring(it.quantity), tostring(it.itemType),
            }, "~")
        else
            parts[i] = "?"
        end
    end
    return table.concat(parts, "|")
end

function Session:Reset()
    local had = self.result ~= nil
    self.result, self.signature, self.indexRef = nil, nil, nil
    if had then self.version = self.version + 1 end
    return had
end
Session.Close = Session.Reset

--- snapshot = {offer = {items...}, receive = {items...}} or nil when no trade is open.
--- Returns result (nil when no trade), changed(boolean).
function Session:Update(index, snapshot)
    if snapshot == nil then
        return nil, self:Reset()
    end
    local sig = sideSignature(snapshot.offer) .. "##" .. sideSignature(snapshot.receive)
    if self.result and sig == self.signature and index == self.indexRef then
        return self.result, false
    end
    self.result = Core.CalculateTrade(index, snapshot.offer or {}, snapshot.receive or {}, self.opts)
    self.signature, self.indexRef = sig, index
    self.version = self.version + 1
    return self.result, true
end

return Core
