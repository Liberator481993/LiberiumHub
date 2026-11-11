-- Liberium Hub | legacy API bridge for the Nova UI
-- Keeps the current Keyless feature modules using their established API.

local Adapter = {}

local GROUPS = {
    Home = "OVERVIEW",
    Farm = "AUTOMATION",
    Visuals = "VISUALS",
    Player = "PLAYER",
    Combat = "COMBAT",
    Settings = "SYSTEM",
}

local DESCRIPTIONS = {
    Home = "Your MM2 session at a glance",
    Farm = "Coin collection and pickup controls",
    Visuals = "Player, role and world visual tools",
    Player = "Movement and character controls",
    Combat = "Round combat and aim utilities",
    Settings = "Configuration and session management",
}

function Adapter.create(WindowModule)
    assert(type(WindowModule) == "table" and type(WindowModule.new) == "function",
        "LegacyAdapter requires the Nova Window module")

    local Lib = {}

    function Lib.new(title)
        local window = WindowModule.new({
            Title = tostring(title or "LIBERIUM HUB"),
            Subtitle = "MURDER MYSTERY 2",
            Version = "v92 • NOVA",
            Size = Vector2.new(812, 584),
            MinSize = Vector2.new(660, 420),
            Scale = 0.86,
            Theme = {
                Base = "Midnight",
                Accent = "Crimson",
                Density = "Compact",
            },
        })

        -- Existing v91 feature pages call AddTab(name, icon). The bridge adds
        -- Nova navigation groups and descriptions without changing that API.
        local addTab = WindowModule.AddTab
        function window:AddTab(name, icon)
            name = tostring(name or "Tab")
            return addTab(self, name, icon, {
                Group = GROUPS[name] or "GENERAL",
                Description = DESCRIPTIONS[name] or "",
            })
        end

        -- Compatibility fields used by LiberiumAPI and the existing cleanup path.
        window.Conns = window.Conns or {}
        window.Version = "v92 • NOVA"
        return window
    end

    return Lib
end

return Adapter
