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

local old = CoreGui:FindFirstChild("SupremeTradeChecker")
if old then old:Destroy() end
local gui = Instance.new("ScreenGui")
gui.Name = "SupremeTradeChecker"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
pcall(function() gui.Parent = CoreGui end)
if not gui.Parent then gui.Parent = playerGui end

local main = Instance.new("Frame")
main.Size = UDim2.fromOffset(340,390)
main.Position = UDim2.new(1,-352,0.30,0)
main.BackgroundColor3 = Color3.fromRGB(16,18,29)
main.BorderSizePixel = 0
main.Parent = gui
Instance.new("UICorner",main).CornerRadius = UDim.new(0,12)
local outline = Instance.new("UIStroke",main)
outline.Color = Color3.fromRGB(142,105,255)
outline.Transparency = 0.2

local function label(parent,text,size,pos,font,color)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Text = text
    l.TextSize = size
    l.Font = font or Enum.Font.Gotham
    l.TextColor3 = color or Color3.fromRGB(230,232,245)
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Position = pos
    l.Size = UDim2.new(1,-18,0,22)
    l.Parent = parent
    return l
end
local title = label(main,"SUPREME  •  MM2 TRADE CHECKER",13,UDim2.fromOffset(10,8),Enum.Font.GothamBold,Color3.fromRGB(203,184,255))
local status = label(main,"Loading Supreme Values...",10,UDim2.fromOffset(10,32),nil,Color3.fromRGB(160,170,190))
local autoStatus = label(main,"AUTO: waiting for trade window",10,UDim2.fromOffset(10,52),nil,Color3.fromRGB(115,220,195))

local yourHead = label(main,"YOUR OFFER",11,UDim2.fromOffset(10,80),Enum.Font.GothamBold,Color3.fromRGB(140,205,255))
local yourList = Instance.new("ScrollingFrame")
yourList.Position = UDim2.fromOffset(10,104)
yourList.Size = UDim2.new(1,-20,0,83)
yourList.BackgroundColor3 = Color3.fromRGB(24,27,42)
yourList.BorderSizePixel = 0
yourList.ScrollBarThickness = 3
yourList.Parent = main
Instance.new("UICorner",yourList).CornerRadius = UDim.new(0,7)
local theirHead = label(main,"THEIR OFFER",11,UDim2.fromOffset(10,195),Enum.Font.GothamBold,Color3.fromRGB(255,190,135))
local theirList = Instance.new("ScrollingFrame")
theirList.Position = UDim2.fromOffset(10,219)
theirList.Size = UDim2.new(1,-20,0,83)
theirList.BackgroundColor3 = Color3.fromRGB(24,27,42)
theirList.BorderSizePixel = 0
theirList.ScrollBarThickness = 3
theirList.Parent = main
Instance.new("UICorner",theirList).CornerRadius = UDim.new(0,7)
local yourTotal = label(main,"Your total: 0",12,UDim2.fromOffset(10,307),Enum.Font.GothamBold,Color3.fromRGB(140,205,255))
local theirTotal = label(main,"Their total: 0",12,UDim2.fromOffset(10,329),Enum.Font.GothamBold,Color3.fromRGB(255,190,135))
local difference = label(main,"Difference: 0",12,UDim2.fromOffset(10,351),Enum.Font.GothamBold,Color3.fromRGB(130,235,180))

-- Drag window with touch or mouse.
local dragging, dragInput, dragStart, startPos
title.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging,dragStart,startPos = true,input.Position,main.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
title.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
end)
UIS.InputChanged:Connect(function(input)
    if dragging and input == dragInput then
        local d = input.Position-dragStart
        main.Position = UDim2.new(startPos.X.Scale,startPos.X.Offset+d.X,startPos.Y.Scale,startPos.Y.Offset+d.Y)
    end
end)

local function clear(frame)
    for _,v in ipairs(frame:GetChildren()) do
        if v:IsA("TextLabel") then v:Destroy() end
    end
end
local function fmt(n)
    local s=tostring(math.floor(n or 0))
    while true do local a,b=s:gsub("^(-?%d+)(%d%d%d)","%1,%2"); s=a; if b==0 then break end end
    return s
end
local function renderSide(frame,items)
    clear(frame)
    local rows,total={},0
    for k,count in pairs(items) do
        local data=values[k]
        if data then
            total=total+(data.value or 0)*count
            table.insert(rows,{name=data.name,count=count,data=data})
        end
    end
    table.sort(rows,function(a,b) return a.name < b.name end)
    for i,row in ipairs(rows) do
        local l=Instance.new("TextLabel")
        l.BackgroundTransparency=1
        l.Size=UDim2.new(1,-8,0,19)
        l.Position=UDim2.fromOffset(5,(i-1)*20)
        l.Font=Enum.Font.Gotham
        l.TextSize=10
        l.TextXAlignment=Enum.TextXAlignment.Left
        l.TextColor3=Color3.fromRGB(230,232,245)
        local valueText=row.data.value and fmt(row.data.value*row.count) or ("N/A ("..row.data.valueText..")")
        l.Text=row.name..(row.count>1 and (" x"..row.count) or "").."  •  "..valueText
        l.Parent=frame
    end
    frame.CanvasSize=UDim2.fromOffset(0,#rows*20)
    return total,#rows
end

local function isTradeText(s)
    s=string.lower(clean(s))
    return s:find("your offer",1,true) or s:find("their offer",1,true)
        or s:find("trade",1,true) or s:find("accept",1,true)
end
local function scanTrade()
    local found=false
    local yourAnchor,theirAnchor
    local candidateGuis={}
    for _,sg in ipairs(playerGui:GetChildren()) do
        if sg:IsA("ScreenGui") and sg.Enabled then
            local has=false
            for _,o in ipairs(sg:GetDescendants()) do
                if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Visible then
                    local t=string.lower(clean(o.Text))
                    if t:find("your offer",1,true) then yourAnchor=o; has=true end
                    if t:find("their offer",1,true) then theirAnchor=o; has=true end
                    if isTradeText(t) then has=true end
                end
            end
            if has then table.insert(candidateGuis,sg) end
        end
    end
    found=yourAnchor~=nil or theirAnchor~=nil
    local yours,theirs={},{}
    if not found then return yours,theirs,false end

    -- Find text objects spatially beneath each offer heading; inventory list is ignored.
    local function collect(anchor,out)
        if not anchor then return end
        local root=anchor.Parent
        local rootPos=anchor.AbsolutePosition
        local rootSize=anchor.AbsoluteSize
        local regionX=rootPos.X-12
        local regionRight=rootPos.X+math.max(rootSize.X,130)+180
        local regionTop=rootPos.Y+rootSize.Y
        local regionBottom=regionTop+210
        local sg=anchor:FindFirstAncestorOfClass("ScreenGui")
        if not sg then return end
        for _,o in ipairs(sg:GetDescendants()) do
            if (o:IsA("TextLabel") or o:IsA("TextButton")) and o.Visible and o~=anchor then
                local p=o.AbsolutePosition
                if p.X>=regionX and p.X<=regionRight and p.Y>=regionTop and p.Y<=regionBottom then
                    local t=key(o.Text)
                    if t~="" then
                        for _,k in ipairs(valueNames) do
                            if t==k or t:find(k,1,true) then
                                local count=tonumber(t:match("[xX]%s*(%d+)")) or 1
                                out[k]=(out[k] or 0)+count
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    collect(yourAnchor,yours)
    collect(theirAnchor,theirs)
    return yours,theirs,true
end

local function update()
    local yours,theirs,detected=scanTrade()
    if detected then
        autoStatus.Text="AUTO: trade window detected"
    else
        autoStatus.Text="AUTO: open an MM2 trade"
    end
    local yt,yc=renderSide(yourList,yours)
    local tt,tc=renderSide(theirList,theirs)
    yourTotal.Text="Your total: "..fmt(yt).."  ("..yc.." items)"
    theirTotal.Text="Their total: "..fmt(tt).."  ("..tc.." items)"
    difference.Text="Difference: "..fmt(yt-tt)
    if not detected then
        status.Text=ValuesLoaded and ("Supreme updated "..lastUpdate) or "Supreme values unavailable"
    elseif yc+tc==0 then
        status.Text="Trade found; item names not recognized yet"
    else
        status.Text="Recognized "..(yc+tc).." item entries • Supreme Values"
    end
end

task.spawn(function()
    ValuesLoaded=refreshValues() or false
    status.Text=ValuesLoaded and ("Supreme values loaded • "..lastUpdate) or "Could not load Supreme Values pages"
    while gui.Parent and not stopped do
        pcall(update)
        task.wait(0.8)
    end
end)

task.spawn(function()
    while gui.Parent and not stopped do
        task.wait(900)
        if gui.Parent then
            local ok=refreshValues()
            if ok then status.Text="Supreme values refreshed • "..lastUpdate end
        end
    end
end)

gui.Destroying:Connect(function()
    stopped=true
end)
print("[Supreme Trade Checker] Loaded")
