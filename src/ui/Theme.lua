-- Liberium Hub | Nova UI theme tokens
-- Original implementation based on the v92 visual specification.

local Theme = {}
Theme.__index = Theme

local function colorFromHex(value)
    assert(type(value) == "string", "color must be a hex string")
    local hex = string.gsub(value, "^#", "")
    assert(#hex == 6 and string.match(hex, "^%x+$"), "expected #RRGGBB")
    return Color3.fromRGB(
        tonumber(string.sub(hex, 1, 2), 16),
        tonumber(string.sub(hex, 3, 4), 16),
        tonumber(string.sub(hex, 5, 6), 16)
    )
end

local BASES = {
    Midnight = {
        Background = "#0C0D10",
        Sidebar = "#0F1014",
        Surface = "#14161B",
        Surface2 = "#1B1E25",
        Elevated = "#22252D",
        Line = "#1F2229",
        Text = "#ECEEF3",
        Muted = "#8A8F9E",
        Faint = "#575C69",
    },
    Obsidian = {
        Background = "#090A0D",
        Sidebar = "#0D0E12",
        Surface = "#12141A",
        Surface2 = "#191C23",
        Elevated = "#242832",
        Line = "#20232B",
        Text = "#F1F2F5",
        Muted = "#9197A5",
        Faint = "#606675",
    },
    Slate = {
        Background = "#11151B",
        Sidebar = "#151A22",
        Surface = "#1B222C",
        Surface2 = "#222B37",
        Elevated = "#2B3542",
        Line = "#303A48",
        Text = "#EFF3F8",
        Muted = "#9AA7B8",
        Faint = "#68788D",
    },
}

local ACCENTS = {
    Crimson = "#D64458",
    Orange = "#FF7A1A",
    Violet = "#A879FF",
    Cyan = "#49CFF3",
    Emerald = "#3DDC97",
    Gold = "#F5B94A",
}

local FIXED = {
    Success = "#3DDC97",
    Warning = "#F5B94A",
    Danger = "#F0506E",
    LogoGlow = "#FF7A1A",
    OnAccent = "#FFFFFF",
}

local function copy(source)
    local result = {}
    for key, value in pairs(source) do
        result[key] = value
    end
    return result
end

function Theme.create(options)
    options = options or {}

    local baseName = options.Base or "Midnight"
    if not BASES[baseName] then
        baseName = "Midnight"
    end

    local accentName = options.Accent or "Crimson"
    if not ACCENTS[accentName] then
        accentName = "Crimson"
    end

    local tokens = {}
    for key, value in pairs(BASES[baseName]) do
        tokens[key] = colorFromHex(value)
    end
    for key, value in pairs(FIXED) do
        tokens[key] = colorFromHex(value)
    end

    tokens.Accent = colorFromHex(ACCENTS[accentName])
    tokens.AccentSoft = tokens.Accent:Lerp(tokens.Background, 0.72)
    tokens.Glass = colorFromHex("#FFFFFF")
    tokens.Shadow = colorFromHex("#000000")

    if typeof(options.Panel) == "Color3" then
        tokens.Background = options.Panel
    end

    return setmetatable({
        Base = baseName,
        Accent = accentName,
        Tokens = tokens,
        Opacity = math.clamp(tonumber(options.Opacity) or 1, 0.5, 1),
        Density = options.Density == "Comfortable" and "Comfortable" or "Compact",
        CardStyle = options.CardStyle or "Glass",
        _bindings = {},
        _destroyed = false,
    }, Theme)
end

function Theme:Get(token)
    return self.Tokens[token]
end

function Theme:Bind(instance, property, token)
    assert(not self._destroyed, "cannot bind a destroyed theme")
    assert(typeof(instance) == "Instance", "Theme:Bind expects an Instance")
    assert(type(property) == "string" and property ~= "", "Theme:Bind expects a property name")
    assert(type(token) == "string" and self.Tokens[token] ~= nil, "Theme:Bind received an unknown token")

    local binding = {
        instance = instance,
        property = property,
        token = token,
    }
    table.insert(self._bindings, binding)

    pcall(function()
        instance[property] = self.Tokens[token]
    end)

    local disconnected = false
    return function()
        if disconnected then
            return
        end
        disconnected = true
        for index = #self._bindings, 1, -1 do
            if self._bindings[index] == binding then
                table.remove(self._bindings, index)
                break
            end
        end
    end
end

function Theme:Set(token, value)
    assert(not self._destroyed, "cannot update a destroyed theme")
    assert(self.Tokens[token] ~= nil, "unknown theme token: " .. tostring(token))
    assert(typeof(value) == "Color3", "theme token values must be Color3")

    self.Tokens[token] = value
    if token == "Accent" then
        self.Tokens.AccentSoft = value:Lerp(self.Tokens.Background, 0.72)
    end
    self:Refresh()
end

function Theme:SetAccent(name)
    local hex = ACCENTS[name]
    if not hex then
        return false
    end

    self.Accent = name
    self:Set("Accent", colorFromHex(hex))
    return true
end

function Theme:SetBase(name)
    local palette = BASES[name]
    if not palette then
        return false
    end

    self.Base = name
    for token, hex in pairs(palette) do
        self.Tokens[token] = colorFromHex(hex)
    end
    self.Tokens.AccentSoft = self.Tokens.Accent:Lerp(self.Tokens.Background, 0.72)
    self:Refresh()
    return true
end

function Theme:Refresh()
    if self._destroyed then
        return
    end

    for index = #self._bindings, 1, -1 do
        local binding = self._bindings[index]
        if binding.instance.Parent == nil then
            table.remove(self._bindings, index)
        else
            pcall(function()
                binding.instance[binding.property] = self.Tokens[binding.token]
            end)
        end
    end
end

function Theme:Destroy()
    if self._destroyed then
        return
    end
    self._destroyed = true
    table.clear(self._bindings)
end

Theme.BasePresets = BASES
Theme.AccentPresets = ACCENTS
Theme.ColorFromHex = colorFromHex

return Theme
