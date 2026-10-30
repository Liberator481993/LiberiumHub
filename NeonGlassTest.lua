-- Liberium Hub | Neon Glass UI test loader
-- UI-only preview; does not load or execute gameplay/cheat modules.
local source = "https://raw.githubusercontent.com/Liberator481993/LiberiumHub/main/NeonGlassUI.lua"
local ok, result = pcall(function()
    local body = game:HttpGet(source)
    local factory = loadstring(body)
    assert(type(factory) == "function", "UI module did not return a loader")
    return factory()
end)
if not ok then
    warn("[Liberium UI Test] " .. tostring(result))
    return
end
if type(getgenv) == "function" then
    local env = getgenv()
    if env.LiberiumNeonGlassTest and env.LiberiumNeonGlassTest.Destroy then
        pcall(function() env.LiberiumNeonGlassTest.Destroy() end)
    end
    env.LiberiumNeonGlassTest = result.new()
else
    result.new()
end
