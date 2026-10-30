--[[
KITKIT HUB v2.1 | Heavyweight Fishing (Roblox, place 98502499119821)
Original, inspectable Luau client script. No external library, key, webhook,
remote loader, unknown purchases, auto-craft, paid summon or auto-roll calls.
AUTO LEVEL is a best-effort rod-aware farming assistant, NOT an XP/level bypass.
Rod purchases require manual confirmation in-game. Live behavior is untested.

Research references (mechanics / event names, not code copied):
  https://github.com/NoahTyrant/StarCrow/blob/main/Heavyweigh%20Fishing
  https://github.com/p54803322-coder/PPINGYYY-HUB-/blob/main/main.lua

UNTESTED IN LIVE ROBLOX. Game updates/executor permissions may break features.
Using a third-party executor can violate Roblox/game rules and risk your account.
Only use code you trust. This script does not request credentials.
]]

if not game:IsLoaded() then game.Loaded:Wait() end
if game.PlaceId ~= 98502499119821 then
    warn("[KITKIT] This build targets Heavyweight Fishing's main place only. PlaceId: " .. tostring(game.PlaceId))
    return
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UIS = game:GetService("UserInputService")
local StarterGui = game:GetService("StarterGui")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui", 15)
local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not PlayerGui or not Events then
    warn("[KITKIT] Main GUI or ReplicatedStorage.Events was not found.")
    return
end

local env = _G
pcall(function()
    if type(getgenv) == "function" then env = getgenv() end
end)
if type(env.KITKIT_HeavyweightFishing) == "table" and type(env.KITKIT_HeavyweightFishing.Unload) == "function" then
    pcall(function() env.KITKIT_HeavyweightFishing:Unload() end)
end

local hub = { running = true, connections = {}, esp = {}, touched = {}, originals = {} }
env.KITKIT_HeavyweightFishing = hub

local state = {
    autoLevel = false, autoRoute = true, autoFavorite = true,
    autoCodes = true, autoDailyQuest = true,
    fastSell = false, targetLevel = 500,
    autoCast = false, autoReel = false, lockBar = false,
    autoSkill = false, slam = false, charge = false,
    rhythm = false, phase2 = false, autoSell = false,
    sellNearFull = true, protectRare = true, autoEnzo = false,
    autoLong = false, bossESP = false, fogAlert = true,
    secretAlert = true, antiAFK = true, stayIsland = false,
    noclip = false, speedBoost = false,
    skillZ = true, skillX = true, skillC = true, skillV = true,
    castDelay = 0.65, bossDelay = 20, sellDelay = 30,
    speed = 24, bossMode = "Normal",
    selectedIsland = "Beginning Isle",
}
local callbacks = {}
local lastAction = "Ready | Everything that spends money is disabled."
local lastWeather = tostring(workspace:GetAttribute("Weather") or "Unknown")
local lastSecretSignature = ""
local lastBossScan = { count = 0, secret = 0, first = nil, firstSecret = nil }
local savedCFrame = nil
local pendingSellUntil = 0
local lastCast = 0
local lastEquipAttempt = 0
local lastReel = 0
local lastSkill = 0
local lastSell = os.clock()
local lastBossTry = 0
local lastTP = 0
local lastFishingEnd = 0
local lastAutoRoute = 0
local lastAutoLevelTick = 0
local lastAutoHealthCheck = 0
local lastCatchAt = os.clock()
local lastProfileLevel = nil
local lastProfileXP = nil
local levelGainAt = os.clock()
local firstProfileAt = os.clock()
local levelGained = 0
local lastCodeRequest = 0
local codesAttempted = {}
local lastDailyQuestClaim = 0
local lastRodPrompt = ""
local favoriteAttempts = {}
local routeCooldownUntil = {}
local recoveryAttempts = 0
local catchesThisSession = 0
local lastBagSize = nil
local progressionStatus = "Idle"
local lastRhythm = 0
local lastPhase2 = 0
local lastSpeed = 0
local wasFishing = false
local rhythmSeen = setmetatable({}, { __mode = "k" })
local rhythmLaneHit = { A = 0, S = 0, D = 0 }

local ISLANDS = {
    {"Beginning Isle", -297.48, 9.28, 58.78},
    {"Bamboo Isle", -1310.04, 9.28, 29.79},
    {"Fallout Isle", 76.47, 9.28, 1265.92},
    {"Sovereign Isle", -1254.18, 9.28, 1301.79},
    {"Perch Isle", -38.55, 9.28, -1343.82},
    {"Frost Isle", -1348.71, 9.28, -1446.51},
    {"Coconut Isle", 1431.00, 9.28, -1430.22},
    {"Amber Isle", 1122.07, 9.28, 1414.54},
    {"Battlefield Isle", 1249.73, 19.56, 68.87},
    {"Mistpeak Isle", 2549.02, 9.28, -80.77},
    {"World Angler Isle", -2345.67, 9.28, -203.65},
    {"Weather Isle", -2886.12, 6.76, 1199.79},
    {"Mystic Reef Isle", -2561.58, 9.28, -1288.64},
}
local BOSS_POS = {
    Enzo = CFrame.new(-114.81, 9.28, 1356.67),
    ["Long Diaohai"] = CFrame.new(-2873.62, 32.17, 1337.38),
}

local function track(c)
    if c then table.insert(hub.connections, c) end
    return c
end
local function report(msg)
    lastAction = tostring(msg)
    print("[KITKIT] " .. lastAction)
end
local function notify(msg)
    report(msg)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = "KITKIT HUB", Text = tostring(msg), Duration = 5 })
    end)
end
local function setState(k, val)
    state[k] = val
    if callbacks[k] then callbacks[k]() end
end
local function getChar()
    local c = LocalPlayer.Character
    return c, c and c:FindFirstChild("HumanoidRootPart"), c and c:FindFirstChildOfClass("Humanoid")
end
local function event(name, wanted)
    local e = Events:FindFirstChild(name)
    if e and e:IsA(wanted or "RemoteEvent") then return e end
    return nil
end
local function fire(name, ...)
    local ev = event(name)
    if not ev then return false end
    return pcall(function(...) ev:FireServer(...) end, ...)
end
local function cframeIsland(name)
    for _, data in ipairs(ISLANDS) do
        if data[1] == name then return CFrame.new(data[2], data[3], data[4]) end
    end
    return nil
end
local function teleportTo(cf, name)
    local char, root = getChar()
    if not cf or not char or not root then report("Teleport unavailable: character not ready"); return false end
    local ok = pcall(function() root.CFrame = cf end)
    if ok then report("Teleported to " .. tostring(name or "target")) end
    return ok
end
local function minigame()
    local main = PlayerGui:FindFirstChild("MainGui")
    local fg = main and main:FindFirstChild("Fishing")
    return fg, (fg and fg:IsA("GuiObject") and fg.Visible == true) or false
end
local function equipRod()
    local char = LocalPlayer.Character
    if not char then return end
    if char:GetAttribute("Type") == "Fishing Rod" then return end
    if os.clock()-lastEquipAttempt<2.0 then return end
    lastEquipAttempt=os.clock()
    local t = event("ToggleHotbar", "RemoteFunction")
    if t then pcall(function() t:InvokeServer("1") end) end
end
-- Source verified: ReplicatedStorage.Data[tostring(UserId)].FishingRod,
-- FishingRodInventory and ReplicatedStorage.Info.Inventory are used in StarCrow.
-- Live shapes are not guaranteed; all reads are guarded.
local function playerData()
    local d = ReplicatedStorage:FindFirstChild("Data")
    return d and d:FindFirstChild(tostring(LocalPlayer.UserId))
end
local function readNumber(obj)
    if not obj then return nil end
    if obj:IsA("ValueBase") then return tonumber(obj.Value) end
    return nil
end
local function candidateValue(folder, names)
    if not folder then return nil end
    for _, name in ipairs(names) do
        local v = readNumber(folder:FindFirstChild(name))
        if v then return v end
        local a = folder:GetAttribute(name)
        if tonumber(a) then return tonumber(a) end
    end
    return nil
end
local function profile()
    local d = playerData()
    local stats = d and (d:FindFirstChild("Stats") or d:FindFirstChild("Statistics"))
    local ls = LocalPlayer:FindFirstChild("leaderstats")
    local lvl = candidateValue(d, {"Level", "Lv", "PlayerLevel"})
        or candidateValue(stats, {"Level", "Lv", "PlayerLevel"})
        or candidateValue(ls, {"Level", "Lv"})
        or candidateValue(LocalPlayer, {"Level", "Lv"})
    local xp = candidateValue(d, {"Exp", "EXP", "XP", "Experience"})
        or candidateValue(stats, {"Exp", "EXP", "XP", "Experience"})
        or candidateValue(ls, {"Exp", "EXP", "XP"})
    local cash = candidateValue(d, {"Cash", "Money", "Coins"})
        or candidateValue(stats, {"Cash", "Money", "Coins"})
        or candidateValue(ls, {"Cash", "Money", "Coins"})
    local rodVal = d and d:FindFirstChild("FishingRod")
    local rodName = rodVal and rodVal:IsA("StringValue") and rodVal.Value or ""
    if rodName == "" then rodName = tostring((d and d:GetAttribute("FishingRod")) or "") end
    return {level=lvl, xp=xp, cash=cash, rod=rodName, data=d}
end

-- Conservative community rod-power reference; for actual ownership use server data.
-- Rod stats change; prefer replicated game info modules when available.
local ROD_POWER = {
    ["Bamboo Rod"]=11, ["Iron Hook Rod"]=13, ["Steel Rod"]=17,
    ["Enchanted Steel Rod"]=19, ["Alloy Rod"]=22, ["Emerald Rod"]=25,
    ["Bloodfire Rod"]=27, ["Shadow Rod"]=29, ["Triple Steel Rod"]=32,
    ["Golden Rod"]=35, ["Grandmaster Steel Rod"]=37,
    ["Grandmaster Emerald Rod"]=39, ["Grandmaster Golden Rod"]=45,
    ["Inferno Rod"]=48, ["Steel Spine Rod"]=48, ["Golden Spine Rod"]=51,
    ["Platinum Spine Rod"]=54, ["Diamond Spine Rod"]=54,
    ["Gravisteel Rod"]=58, ["Auric Gravity Rod"]=60,
    ["Inferno Gravity Rod"]=62, ["Cryo Gravity Rod"]=65,
    ["Thunder Thorn Rod"]=67, ["Soul Thorn Rod"]=75,
    ["Starlight Rod"]=83, ["Heavenpiercer Rod"]=100,
    ["Heaven Piercer Rod"]=100, ["Pure Diamond Rod"]=100,
}
local function itemModule(name)
    if type(name)~="string" or name=="" then return nil end
    local inf=ReplicatedStorage:FindFirstChild("Info")
    local inv=inf and inf:FindFirstChild("Inventory")
    local mod=inv and inv:FindFirstChild(name)
    if mod and mod:IsA("ModuleScript") then
        local ok,v=pcall(require,mod)
        if ok and type(v)=="table" then return v end
    end
    return nil
end
local function rodPower(name)
    if type(name)~="string" or name=="" then return nil end
    local dat=itemModule(name)
    local n=dat and tonumber(dat.Power or dat.Strength or dat.MaxPower)
    if n and n>0 and n<10000 then return n end
    return ROD_POWER[name]
end
local function bestOwnedRod(p)
    p=p or profile()
    local folder=p.data and p.data:FindFirstChild("FishingRodInventory")
    if not folder then return nil,nil end
    local bestName,bestPower=nil,-1
    for _, rod in ipairs(folder:GetChildren()) do
        local n=rod.Name
        local power=rodPower(n)
        if power and power>bestPower then bestName,bestPower=n,power end
    end
    return bestName,bestPower>=0 and bestPower or nil
end
local LEVEL_ROUTE = {
    {power=0, name="Beginning Isle"},
    {power=19, name="Bamboo Isle"},
    {power=32, name="Fallout Isle"},
    {power=39, name="Sovereign Isle"},
    {power=48, name="Perch Isle"},
    {power=55, name="Frost Isle"},
    {power=65, name="Coconut Isle"},
    {power=75, name="Amber Isle"},
}
local function routeChoice(p)
    p=p or profile()
    local power=rodPower(p.rod)
    local index=1
    if power then
        for i,route in ipairs(LEVEL_ROUTE) do
            if power>=route.power then index=i end
        end
    end
    -- On a fresh account, stay on tutorial island until roughly Level 10.
    -- This is a conservative tutorial safeguard, not a claimed hard level gate.
    if p.level and p.level < 10 then return "Beginning Isle",power,1 end
    if not power then return "Beginning Isle",nil,1 end
    while index>1 and os.clock()<(routeCooldownUntil[LEVEL_ROUTE[index].name] or 0) do
        index=index-1
    end
    return LEVEL_ROUTE[index].name,power,index
end
local function nextRodSuggestion(p)
    p=p or profile()
    local power=rodPower(p.rod) or 0
    -- Cost-aware stepping stones from the August 2026 community rod catalog.
    -- Skips the 4M Diamond Spine (same 54 Power/25 Luck as 3M Platinum).
    -- Shop prices are advisory until verified in the player's actual server.
    local candidates={
        {name="Steel Rod",power=17,cost=1000,island="Beginning Isle"},
        {name="Enchanted Steel Rod",power=19,cost=2000,island="Beginning Isle"},
        {name="Shadow Rod",power=29,cost=60000,island="Bamboo Isle"},
        {name="Golden Rod",power=35,cost=200000,island="Fallout Isle"},
        {name="Grandmaster Golden Rod",power=45,cost=1000000,island="Sovereign Isle"},
        {name="Platinum Spine Rod",power=54,cost=3000000,island="Perch Isle"},
        {name="Cryo Gravity Rod",power=65,cost=8000000,island="Frost Isle"},
        {name="Thunder Thorn Rod",power=67,cost=10000000,island="Coconut Isle"},
        {name="Starlight Rod",power=83,cost=60000000,island="Amber Isle"},
    }
    for _,item in ipairs(candidates) do
        if item.power>power then return item end
    end
    return nil
end

-- Public October 2026 code trackers disagree on a few expired codes.
-- Attempts are sent once per session; FireServer success does NOT confirm reward.
local CODE_LADDER={
    {"SON",0},{"Riku",0},{"HWF",0},
    {"Welcome",20},
    {"85KLikes",100},{"80KLikes",100},{"Legendary",100},
    {"BannerShop",100},{"WeeklyUPD1",100},
    {"25KActives",500},{"VermilionBird",500},
}
local function redeemEligibleCodes(level)
    local ev=event("RedeemCode")
    if not ev then return end
    local now=os.clock()
    if now-lastCodeRequest<3 then return end
    for _,entry in ipairs(CODE_LADDER) do
        local code,minLevel=entry[1],entry[2]
        if (tonumber(level) or 0)>=minLevel and not codesAttempted[code] then
            codesAttempted[code]=true
            lastCodeRequest=now
            local sent=fire("RedeemCode",code)
            if sent then report("Code attempt: "..code..". Verify in-game reward/eligibility.") end
            return
        end
    end
end
-- Daily quest claim: only when server-replicated objectives show completion.
-- ClaimQuest and the Daily quest module layout are confirmed in StarCrow source.
local function claimCompletedDailies()
    local now=os.clock()
    if now-lastDailyQuestClaim<12 then return end
    lastDailyQuestClaim=now
    if not event("ClaimQuest") then return end
    local d=playerData()
    local q=d and d:FindFirstChild("Quest")
    local daily=q and q:FindFirstChild("Daily")
    local info=ReplicatedStorage:FindFirstChild("Info")
    local module=info and info:FindFirstChild("Quest")
    if not daily or not module or not module:IsA("ModuleScript") then return end
    local ok,defs=pcall(require,module)
    if not ok or type(defs)~="table" or type(defs.Daily)~="table" then return end
    for _,obj in ipairs(daily:GetChildren()) do
        local claim=obj:FindFirstChild("Claim")
        local progress=obj:FindFirstChild("Progression")
        local qType=obj:FindFirstChild("QuestType")
        local index=tonumber(obj.Name)
        local definition=index and defs.Daily[index]
        local goal=type(definition)=="table" and tonumber(definition[2]) or nil
        if claim and progress and qType and goal and goal>0
            and claim:IsA("BoolValue") and claim.Value==false
            and progress:IsA("NumberValue") and qType:IsA("StringValue")
            and qType.Value~="" then
            local current=progress.Value
            if qType.Value=="PlayTime" then
                current=math.floor(current/60)
                goal=math.max(1,math.floor(goal/60))
            end
            if current>=goal then
                if fire("ClaimQuest",obj.Name) then
                    report("Daily quest claim requested: #"..obj.Name)
                end
                return -- At most one claim per 12 seconds.
            end
        end
    end
end

local function getInventory()
    local data = ReplicatedStorage:FindFirstChild("Data")
    local playerData = data and data:FindFirstChild(tostring(LocalPlayer.UserId))
    local inv = playerData and playerData:FindFirstChild("Inventory")
    local maxValue = playerData and (playerData:FindFirstChild("InventoryLimit")
        or playerData:FindFirstChild("MaxInventory")
        or playerData:FindFirstChild("BagLimit")
        or playerData:FindFirstChild("MaxCapacity"))
    local maxCount = maxValue and tonumber(maxValue.Value)
        or (playerData and tonumber(playerData:GetAttribute("InventoryLimit")))
        or (playerData and tonumber(playerData:GetAttribute("MaxInventory")))
    local current = inv and #inv:GetChildren() or nil
    return inv, current, maxCount
end
local function flaggedRare(item)
    local n=item.Name:lower()
    local rarity=tostring(item:GetAttribute("Rarity") or item:GetAttribute("Tier") or ""):lower()
    for _,keyword in ipairs({"secret","legendary","mythic","boss","exotic","event","divine"}) do
        if n:find(keyword,1,true) or rarity:find(keyword,1,true) then return true end
    end
    return item:GetAttribute("Secret")==true or item:GetAttribute("Locked")==true
end
local function isFavorite(item)
    return item.Name:lower():find("| favorite",1,true)~=nil
       or item:GetAttribute("Favorite")==true
       or item:GetAttribute("Favorited")==true
       or item:GetAttribute("IsFavorite")==true
end
local function tryFavorite(item)
    if not state.autoFavorite or isFavorite(item) then return false end
    local ev=event("FavoriteItem")
    if not ev then return false end
    local entry=favoriteAttempts[item.Name] or {n=0,at=0}
    if entry.n>=3 or os.clock()-entry.at<2.5 then return false end
    entry.n=entry.n+1
    entry.at=os.clock()
    favoriteAttempts[item.Name]=entry
    local ok=fire("FavoriteItem",item.Name)
    if ok then report("Protecting rare catch: "..item.Name.."; waiting for favorite confirmation") end
    return ok
end
local function maySell()
    local inv,count,maximum=getInventory()
    if not inv then return false,"Inventory data unavailable" end
    if not count or count==0 then return false,"Nothing to sell" end
    if state.sellNearFull and (not maximum or maximum<=0 or count/maximum<0.88) then
        return false,"Bag below 88% or limit unknown"
    end
    if state.protectRare and not state.fastSell then
        for _,item in ipairs(inv:GetChildren()) do
            if flaggedRare(item) and not isFavorite(item) then
                tryFavorite(item)
                return false,"Rare fish is NOT confirmed favorited: "..item.Name
            end
        end
    end
    return true,"Ready"
end
local function sellNow(skipNearFull)
    local original=state.sellNearFull
    if skipNearFull then state.sellNearFull=false end
    local ok,reason=maySell()
    state.sellNearFull=original
    if not ok then
        if skipNearFull or not reason:find("Nothing to sell",1,true) then report("Sale paused: "..reason) end
        return false
    end
    local sent=fire("SellFish","All")
    if sent then report("Sell request SENT. Check actual Cash or bag count for confirmation.") end
    return sent
end

local function getPart(obj)
    if not obj then return nil end
    if obj:IsA("BasePart") then return obj end
    if obj:IsA("Model") then
        return obj:FindFirstChild("HumanoidRootPart")
            or obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart", true)
    end
    return obj:FindFirstChildWhichIsA("BasePart", true)
end
local function isSecret(obj)
    if not obj then return false end
    if obj:GetAttribute("Secret") == true or obj:GetAttribute("Rarity") == "Secret" then return true end
    local n = tostring(obj:GetAttribute("FishName") or obj:GetAttribute("Name") or obj.Name):lower()
    return n:find("secret", 1, true) ~= nil or n:find("diaohai", 1, true) ~= nil
        or n:find("wuzhi", 1, true) ~= nil
end
local function collectBosses()
    local results, seen = {}, {}
    local npc = workspace:FindFirstChild("NPC")
    local bossFolder = npc and npc:FindFirstChild("Boss")
    local candidates = {}
    if bossFolder then
        for _, o in ipairs(bossFolder:GetChildren()) do table.insert(candidates, o) end
    end
    for _, n in ipairs({ "Boss", "BossZone" }) do
        local obj = workspace:FindFirstChild(n)
        if obj then table.insert(candidates, obj) end
    end
    for _, obj in ipairs(candidates) do
        local part = getPart(obj)
        if part and part:IsDescendantOf(workspace) and not seen[obj] then
            seen[obj] = true
            table.insert(results, { object = obj, part = part, secret = isSecret(obj), name = obj.Name })
        end
    end
    return results
end
local function clearESP()
    for obj, billboard in pairs(hub.esp) do
        pcall(function() billboard:Destroy() end)
        hub.esp[obj] = nil
    end
end
local function scanBosses()
    local found = collectBosses()
    local count, secretCount, first, firstSecret = 0, 0, nil, nil
    local sigParts = {}
    for _, b in ipairs(found) do
        count = count + 1
        if not first then first = b end
        if b.secret then
            secretCount = secretCount + 1
            if not firstSecret then firstSecret = b end
            table.insert(sigParts, b.name)
        end
        if state.bossESP and not hub.esp[b.object] then
            local label = Instance.new("BillboardGui")
            label.Name = "KITKIT_BossESP"
            label.Adornee = b.part
            label.AlwaysOnTop = true
            label.Size = UDim2.fromOffset(190, 36)
            label.StudsOffset = Vector3.new(0, 5, 0)
            local text = Instance.new("TextLabel")
            text.BackgroundColor3 = Color3.fromRGB(17, 22, 34)
            text.BackgroundTransparency = 0.12
            text.Size = UDim2.fromScale(1, 1)
            text.Text = (b.secret and "SECRET: " or "BOSS: ") .. b.name
            text.TextColor3 = b.secret and Color3.fromRGB(251, 188, 79) or Color3.fromRGB(110, 235, 224)
            text.TextScaled = true
            text.Font = Enum.Font.GothamBold
            text.Parent = label
            Instance.new("UICorner", text).CornerRadius = UDim.new(0, 6)
            label.Parent = b.part
            hub.esp[b.object] = label
        end
    end
    for obj, label in pairs(hub.esp) do
        if not state.bossESP or not obj:IsDescendantOf(workspace) then
            pcall(function() label:Destroy() end)
            hub.esp[obj] = nil
        end
    end
    local sig = table.concat(sigParts, ";")
    if state.secretAlert and secretCount > 0 and sig ~= lastSecretSignature then
        notify("Secret boss object detected! Check the BOSS tab.")
    end
    lastSecretSignature = sig
    lastBossScan = { count = count, secret = secretCount, first = first, firstSecret = firstSecret }
    return lastBossScan
end
local function startBoss(name)
    equipRod()
    local started = fire("StartBossFight", name, state.bossMode)
    if started then report("Requested boss: " .. name .. " [" .. state.bossMode .. "]")
    else report("StartBossFight event not available") end
    return started
end

-- GUI creation. Built with Roblox instances; no remote UI code.
local container = PlayerGui
pcall(function()
    if type(gethui) == "function" then container = gethui()
    else container = game:GetService("CoreGui") end
end)
local GUI = Instance.new("ScreenGui")
GUI.Name = "KITKIT_HeavyweightFishing_GUI"
GUI.ResetOnSpawn = false
GUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
GUI.IgnoreGuiInset = true
local parented = pcall(function() GUI.Parent = container end)
if not parented then GUI.Parent = PlayerGui end
hub.gui = GUI

local colors = {
    bg = Color3.fromRGB(15, 20, 30), panel = Color3.fromRGB(26, 34, 48),
    row = Color3.fromRGB(33, 43, 58), outline = Color3.fromRGB(61, 75, 93),
    accent = Color3.fromRGB(81, 217, 193), gold = Color3.fromRGB(246, 185, 87),
    white = Color3.fromRGB(241, 246, 252), muted = Color3.fromRGB(165, 178, 198),
    red = Color3.fromRGB(222, 91, 93),
}
local function make(class, parent, props)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function round(o, px) make("UICorner", o, { CornerRadius = UDim.new(0, px or 9) }) end
local function edge(o, color)
    make("UIStroke", o, { Color = color or colors.outline, Thickness = 1, Transparency = 0.28 })
end
local compact = UIS.TouchEnabled and not UIS.KeyboardEnabled
local width = compact and 354 or 455
local height = compact and 388 or 445
local main = make("Frame", GUI, {
    Name = "Window", BackgroundColor3 = colors.bg, BorderSizePixel = 0,
    Size = UDim2.fromOffset(width, height), Position = UDim2.new(0.5, -width/2, 0.5, -height/2),
    ClipsDescendants = true, Active = true,
})
round(main, 13); edge(main)
local header = make("Frame", main, { BackgroundColor3 = colors.panel, Size = UDim2.new(1, 0, 0, 49), BorderSizePixel = 0, Active = true })
local title = make("TextLabel", header, {
    BackgroundTransparency = 1, Text = "KITKIT / HEAVYWEIGHT", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold, TextSize = compact and 15 or 17, TextColor3 = colors.accent,
    Position = UDim2.fromOffset(14, 5), Size = UDim2.new(1, -107, 0, 24),
})
make("TextLabel", header, {
    BackgroundTransparency = 1, Text = "v2.1   |   rod-aware auto level", TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.Gotham, TextSize = 10, TextColor3 = colors.muted,
    Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -107, 0, 16),
})
local minButton = make("TextButton", header, {
    Text = "_", Font = Enum.Font.GothamBold, TextSize = 19, TextColor3 = colors.white,
    BackgroundColor3 = colors.row, Size = UDim2.fromOffset(30, 29),
    Position = UDim2.new(1, -75, 0, 10),
})
round(minButton, 6)
local closeButton = make("TextButton", header, {
    Text = "X", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = colors.white,
    BackgroundColor3 = colors.red, Size = UDim2.fromOffset(30, 29),
    Position = UDim2.new(1, -39, 0, 10),
})
round(closeButton, 6)
local tabBar = make("Frame", main, {
    BackgroundTransparency = 1, Size = UDim2.new(1, -16, 0, 39),
    Position = UDim2.fromOffset(8, 54),
})
local tabList = make("UIListLayout", tabBar, {
    FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5),
})
local content = make("Frame", main, {
    BackgroundTransparency = 1, Position = UDim2.fromOffset(10, 97),
    Size = UDim2.new(1, -20, 1, -159),
})
local footer = make("Frame", main, {
    BackgroundColor3 = colors.panel, Position = UDim2.new(0, 0, 1, -58),
    Size = UDim2.new(1, 0, 0, 58), BorderSizePixel = 0,
})
local statusTop = make("TextLabel", footer, {
    BackgroundTransparency = 1, Font = Enum.Font.GothamMedium,
    Text = "Weather: -- | Bag: -- | Boss: --", TextColor3 = colors.accent,
    TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(12, 7), Size = UDim2.new(1, -24, 0, 18),
})
local statusBottom = make("TextLabel", footer, {
    BackgroundTransparency = 1, Font = Enum.Font.Gotham,
    Text = "Ready", TextColor3 = colors.muted, TextWrapped = true,
    TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(12, 25), Size = UDim2.new(1, -24, 0, 30),
})
local bubble = make("TextButton", GUI, {
    Text = "KK", Font = Enum.Font.GothamBold, TextSize = 13,
    BackgroundColor3 = colors.panel, TextColor3 = colors.accent,
    Size = UDim2.fromOffset(41, 41), Position = UDim2.new(0, 14, 0.4, 0), Visible = false,
})
round(bubble, 12); edge(bubble, colors.accent)

-- Dragging via titlebar, compatible with mouse and touch.
local dragging, dragStart, startPosition, dragInput = false, nil, nil, nil
track(header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        dragging = true
        dragStart = input.Position
        startPosition = main.Position
        local releaseConnection
        releaseConnection = input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
                if releaseConnection then releaseConnection:Disconnect() end
            end
        end)
        track(releaseConnection)
    end
end))
track(header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end))
track(UIS.InputChanged:Connect(function(input)
    if dragging and input == dragInput and dragStart then
        local d = input.Position - dragStart
        main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + d.X,
            startPosition.Y.Scale, startPosition.Y.Offset + d.Y)
    end
end))

local pages = {}
local tabs = {}
local activeTab = "Fish"
local function activate(name)
    activeTab = name
    for tabName, page in pairs(pages) do page.Visible = tabName == name end
    for tabName, btn in pairs(tabs) do
        btn.BackgroundColor3 = tabName == name and colors.accent or colors.panel
        btn.TextColor3 = tabName == name and colors.bg or colors.muted
    end
end
local function createTab(name)
    local btn = make("TextButton", tabBar, {
        BackgroundColor3 = colors.panel, TextColor3 = colors.muted,
        Text = name, TextSize = compact and 10 or 12, Font = Enum.Font.GothamBold,
        Size = UDim2.new(0.2, -5, 0, 32), BorderSizePixel = 0,
    })
    round(btn, 7)
    tabs[name] = btn
    track(btn.MouseButton1Click:Connect(function() activate(name) end))
    local scroll = make("ScrollingFrame", content, {
        BackgroundTransparency = 1, Visible = false, BorderSizePixel = 0,
        ScrollBarThickness = 3, ScrollBarImageColor3 = colors.accent,
        Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    })
    local layout = make("UIListLayout", scroll, {
        Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder,
    })
    make("UIPadding", scroll, {
        PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 6),
        PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 5),
    })
    track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 12)
    end))
    pages[name] = scroll
    return scroll
end
local levelPage = createTab("Level")
local fishPage = createTab("Fish")
local bossPage = createTab("Boss")
local worldPage = createTab("World")
local extraPage = createTab("Other")

local function section(parent, name)
    make("TextLabel", parent, {
        BackgroundTransparency = 1, Text = name:upper(), TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = colors.gold,
        Size = UDim2.new(1, -4, 0, 22),
    })
end
local function rowBase(parent, h)
    local row = make("Frame", parent, {
        BackgroundColor3 = colors.row, BorderSizePixel = 0,
        Size = UDim2.new(1, -4, 0, h or 36),
    })
    round(row, 7)
    return row
end
local function action(parent, label, fn, important)
    local btn = make("TextButton", parent, {
        Text = label, TextColor3 = important and colors.bg or colors.white,
        BackgroundColor3 = important and colors.accent or colors.row,
        Font = Enum.Font.GothamMedium, TextSize = compact and 11 or 12,
        Size = UDim2.new(1, -4, 0, 35), TextWrapped = true, BorderSizePixel = 0,
    })
    round(btn, 7)
    track(btn.MouseButton1Click:Connect(function()
        if not hub.running then return end
        local ok, err = pcall(fn, btn)
        if not ok then report("Button error: " .. tostring(err)) end
    end))
    return btn
end
local function toggle(parent, label, key, onChange)
    local row = rowBase(parent, 36)
    make("TextLabel", row, {
        Text = label, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = colors.white, Font = Enum.Font.GothamMedium, TextSize = compact and 11 or 12,
        Size = UDim2.new(1, -89, 1, 0), Position = UDim2.fromOffset(10, 0),
    })
    local btn = make("TextButton", row, {
        Size = UDim2.fromOffset(62, 26), Position = UDim2.new(1, -70, 0.5, -13),
        TextSize = 11, Font = Enum.Font.GothamBold, BorderSizePixel = 0,
    })
    round(btn, 6)
    local function refresh()
        btn.Text = state[key] and "ON" or "OFF"
        btn.TextColor3 = state[key] and colors.bg or colors.muted
        btn.BackgroundColor3 = state[key] and colors.accent or colors.panel
    end
    callbacks[key] = refresh
    refresh()
    track(btn.MouseButton1Click:Connect(function()
        setState(key, not state[key])
        if onChange then onChange(state[key]) end
    end))
end
local function stepper(parent, label, key, minVal, maxVal, jump, suffix)
    local row = rowBase(parent, 36)
    make("TextLabel", row, {
        Text = label, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = colors.white, Font = Enum.Font.GothamMedium, TextSize = compact and 11 or 12,
        Size = UDim2.new(1, -144, 1, 0), Position = UDim2.fromOffset(10, 0),
    })
    local minus = make("TextButton", row, {
        Text = "-", Size = UDim2.fromOffset(28, 27), Position = UDim2.new(1, -133, 0.5, -13),
        TextColor3 = colors.white, BackgroundColor3 = colors.panel, Font = Enum.Font.GothamBold, TextSize = 16,
    })
    round(minus, 6)
    local number = make("TextLabel", row, {
        BackgroundTransparency = 1, TextColor3 = colors.accent,
        Font = Enum.Font.GothamBold, TextSize = 11, Position = UDim2.new(1, -103, 0, 0),
        Size = UDim2.fromOffset(66, 36),
    })
    local plus = make("TextButton", row, {
        Text = "+", Size = UDim2.fromOffset(28, 27), Position = UDim2.new(1, -33, 0.5, -13),
        TextColor3 = colors.white, BackgroundColor3 = colors.panel, Font = Enum.Font.GothamBold, TextSize = 16,
    })
    round(plus, 6)
    local function refresh()
        number.Text = tostring(state[key]) .. (suffix or "")
    end
    refresh()
    track(minus.MouseButton1Click:Connect(function()
        state[key] = math.max(minVal, math.floor((state[key]-jump)*100+0.5)/100)
        refresh()
    end))
    track(plus.MouseButton1Click:Connect(function()
        state[key] = math.min(maxVal, math.floor((state[key]+jump)*100+0.5)/100)
        refresh()
    end))
end

-- Auto XP: accepts a real in-game character and progresses by catching fish.
-- No direct XP modification, no unattended buying/summoning.
local levelingHUD=make("TextLabel",levelPage,{
    BackgroundColor3=colors.panel,TextColor3=colors.accent,
    Font=Enum.Font.GothamBold,TextSize=compact and 11 or 13,
    Text="Lv ?/500 | Rod ? | Power ?",TextWrapped=true,
    Size=UDim2.new(1,-4,0,58),
})
round(levelingHUD,8)
local routeHUD=make("TextLabel",levelPage,{
    BackgroundTransparency=1,TextColor3=colors.muted,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    Font=Enum.Font.Gotham,TextSize=11,TextWrapped=true,
    Text="Status: idle\nNext upgrade: --",Size=UDim2.new(1,-4,0,78),
})
section(levelPage,"Fresh account: XP / cash farming")
local levelBtn=action(levelPage,"START AUTO LEVEL TO 500",function(btn)
    local active=not state.autoLevel
    setState("autoLevel",active)
    if active then
        for _,k in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam","charge","rhythm","phase2","autoSell"}) do
            setState(k,true)
        end
        setState("sellNearFull",false)
        setState("protectRare",true)
        setState("fastSell",false)
        setState("autoFavorite",true)
        setState("autoEnzo",false)
        setState("autoLong",false)
        setState("stayIsland",false)
        lastCatchAt=os.clock()
        firstProfileAt=os.clock()
        lastProfileLevel=nil
        lastProfileXP=nil
        levelGained=0
        progressionStatus="Started: checking profile and rod power"
        report("Auto level started. Rod upgrades require your manual purchase at Biao Di.")
    else
        for _,k in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam","charge","rhythm","phase2","autoSell"}) do
            setState(k,false)
        end
        report("Auto level stopped. Fishing automation and selling stopped.")
    end
    btn.Text=active and "STOP AUTO LEVEL" or "START AUTO LEVEL TO 500"
end,true)
toggle(levelPage,"Auto route based on equipped rod Power","autoRoute")
toggle(levelPage,"Auto claim eligible free codes","autoCodes")
toggle(levelPage,"Auto claim completed daily quests","autoDailyQuest")
toggle(levelPage,"Favorite rare fish before selling","autoFavorite")
toggle(levelPage,"FAST SELL (can sell valuable fish!)","fastSell",function(v)
    if v then notify("FAST SELL ON: rare catches can be sold! Turn OFF to protect them.") end
end)
stepper(levelPage,"Goal level","targetLevel",50,2000,50,"")
stepper(levelPage,"Sell interval","sellDelay",15,300,15,"s")
stepper(levelPage,"Cast recovery delay","castDelay",0.4,3,0.1,"s")
section(levelPage,"Rod upgrades: manual for now")
action(levelPage,"FIND NEAREST ROD SELLER",function()
    local _,hrp=getChar()
    local npc=workspace:FindFirstChild("NPC")
    if not hrp or not npc then notify("Character/NPCs not loaded") return end
    local best,bestDistance=nil,math.huge
    for _,model in ipairs(npc:GetDescendants()) do
        local low=model.Name:lower()
        if low=="biao di" or low=="rod seller" then
            local part=getPart(model)
            if part then
                local distance=(part.Position-hrp.Position).Magnitude
                if distance<bestDistance then best,bestDistance=part,distance end
            end
        end
    end
    if best then teleportTo(best.CFrame*CFrame.new(0,0,-6),"Rod Seller (buy manually)")
    else notify("Rod Seller not loaded; use the game's island NPC list") end
end)
action(levelPage,"SHOW NEXT ROD UPGRADE",function()
    local p=profile()
    local suggestion=nextRodSuggestion(p)
    local owned,ownedPower=bestOwnedRod(p)
    if ownedPower and ownedPower>(rodPower(p.rod) or 0) then
        notify("You own a stronger rod: "..owned..". Equip it in-game.")
    elseif suggestion then
        notify("Suggested next: "..suggestion.name.." on "..suggestion.island.." (~"..suggestion.cost.." Cash)")
    else
        notify("No next rod suggestion. Check the live NPC shop.")
    end
end)
action(levelPage,"REDEEM ELIGIBLE FREE CODES (MANUAL)",function()
    local p=profile()
    redeemEligibleCodes(p.level)
    notify("Next unattempted eligible code sent, if any. Check game's Code panel.")
end)
action(levelPage,"RECHECK LEVEL/ROD NOW",function()
    local p=profile()
    local _,pow=routeChoice(p)
    notify("Level "..tostring(p.level or "?").."; Rod "..tostring(p.rod).."; Power "..tostring(pow or "?").."; Cash "..tostring(p.cash or "?"))
end)

section(fishPage, "Fishing automation")
local masterBtn = action(fishPage, "START FULL AUTO FISHING (NO SELL)", function(btn)
    local enable = not state.autoCast
    for _, k in ipairs({"autoCast", "autoReel", "lockBar", "autoSkill", "slam", "charge", "rhythm", "phase2"}) do
        setState(k, enable)
    end
    if enable then
        setState("autoEnzo", false); setState("autoLong", false)
    end
    btn.Text = enable and "STOP FULL AUTO FISHING" or "START FULL AUTO FISHING (NO SELL)"
    notify(enable and "Full auto fishing ON. Selling remains separate." or "Full auto fishing OFF.")
end, true)
toggle(fishPage, "Auto cast", "autoCast", function(v)
    if v then setState("autoEnzo", false); setState("autoLong", false) end
end)
toggle(fishPage, "Auto reel + progression", "autoReel")
toggle(fishPage, "Keep fishing bar centered", "lockBar")
toggle(fishPage, "Use equipped skills", "autoSkill")
toggle(fishPage, "Perfect slam (event)", "slam")
toggle(fishPage, "Auto charge (event)", "charge")
toggle(fishPage, "Rhythm A / S / D (experimental)", "rhythm")
toggle(fishPage, "Boss phase 2 timing (experimental)", "phase2")
stepper(fishPage, "Cast delay", "castDelay", 0.4, 10, 0.2, "s")
section(fishPage, "Skill slots")
toggle(fishPage, "Use Z skill", "skillZ")
toggle(fishPage, "Use X skill", "skillX")
toggle(fishPage, "Use C skill", "skillC")
toggle(fishPage, "Use V skill", "skillV")
section(fishPage, "Selling - separate, OFF by default")
toggle(fishPage, "AUTO SELL ALL (caution)", "autoSell", function(v)
    if v then notify("Auto Sell ON. Rare protection is best-effort, not guaranteed!") end
end)
toggle(fishPage, "Only sell when bag >= 88%", "sellNearFull")
toggle(fishPage, "Protect UNFAVORITED rare fish", "protectRare")
stepper(fishPage, "Sell interval", "sellDelay", 15, 1200, 15, "s")
action(fishPage, "SELL ALL NOW - REQUIRES DOUBLE TAP", function(btn)
    local now = os.clock()
    if now > pendingSellUntil then
        pendingSellUntil = now + 6
        btn.Text = "CONFIRM SELL ALL (6s)"
        notify("CAUTION: Sell All can sell valuable fish. Tap again to confirm.")
    else
        pendingSellUntil = 0
        btn.Text = "SELL ALL NOW - REQUIRES DOUBLE TAP"
        sellNow(true)
    end
end)

section(bossPage, "Boss farming")
local bossInfo = make("TextLabel", bossPage, {
    Text = "Enzo and Long Diaohai use the game's StartBossFight event.\nBoss phase 2 automation is EXPERIMENTAL.",
    TextWrapped = true, TextSize = 11, Font = Enum.Font.Gotham,
    TextColor3 = colors.muted, BackgroundTransparency = 1,
    Size = UDim2.new(1, -6, 0, 43), TextXAlignment = Enum.TextXAlignment.Left,
})
toggle(bossPage, "Auto Enzo boss (retries)", "autoEnzo", function(v)
    if v then
        setState("autoLong", false); setState("autoLevel",false)
        for _,k in ipairs({"autoCast","autoReel","autoSkill","autoSell"}) do setState(k,false) end
        levelBtn.Text="START AUTO LEVEL TO 500"
    end
end)
toggle(bossPage, "Auto Long Diaohai (secret)", "autoLong", function(v)
    if v then
        setState("autoEnzo", false); setState("autoLevel",false)
        for _,k in ipairs({"autoCast","autoReel","autoSkill","autoSell"}) do setState(k,false) end
        levelBtn.Text="START AUTO LEVEL TO 500"
    end
end)
stepper(bossPage, "Retry interval", "bossDelay", 10, 90, 5, "s")
action(bossPage, "Boss mode: Normal / Hard", function(btn)
    state.bossMode = (state.bossMode == "Normal") and "Hard" or "Normal"
    btn.Text = "Boss mode: " .. state.bossMode
    report("Boss mode: " .. state.bossMode)
end)
action(bossPage, "START ENZO ONCE", function() startBoss("Enzo") end)
action(bossPage, "START LONG DIAOHAI ONCE", function() startBoss("Long Diaohai") end)
action(bossPage, "TP - ENZO", function() teleportTo(BOSS_POS.Enzo, "Enzo area") end)
action(bossPage, "TP - LONG DIAOHAI", function() teleportTo(BOSS_POS["Long Diaohai"], "Long Diaohai area") end)
section(bossPage, "Boss detection / ESP")
toggle(bossPage, "Show loaded boss ESP", "bossESP", function(v)
    if not v then clearESP() else scanBosses() end
end)
toggle(bossPage, "Alert when secret boss appears", "secretAlert")
action(bossPage, "SCAN BOSSES IN THIS SERVER", function()
    local b = scanBosses()
    notify("Loaded bosses: " .. b.count .. " | Secret: " .. b.secret)
end)
action(bossPage, "TP TO DETECTED SECRET BOSS", function()
    local b = scanBosses()
    if b.firstSecret then
        teleportTo(b.firstSecret.part.CFrame * CFrame.new(0, 0, -8), b.firstSecret.name)
    else
        notify("No secret boss object currently loaded on your client")
    end
end)
action(bossPage, "TP TO FIRST DETECTED BOSS", function()
    local b = scanBosses()
    if b.first then teleportTo(b.first.part.CFrame * CFrame.new(0, 0, -8), b.first.name)
    else notify("No boss object currently loaded") end
end)

section(worldPage, "Server weather")
local weatherLabel = make("TextLabel", worldPage, {
    BackgroundColor3 = colors.panel, TextColor3 = colors.accent,
    Font = Enum.Font.GothamBold, TextSize = 13, Text = "Current weather: ...",
    Size = UDim2.new(1, -4, 0, 36),
})
round(weatherLabel, 7)
toggle(worldPage, "Notify me for fog / mist", "fogAlert")
action(worldPage, "SERVER HOP ONCE (new public server)", function()
    notify("Fetching public Roblox servers... may not work on all executors")
    task.spawn(function()
        local ok, err = pcall(function()
            local url = "https://games.roblox.com/v1/games/" .. tostring(game.PlaceId)
                .. "/servers/Public?sortOrder=Asc&limit=100"
            local raw = game:HttpGet(url)
            local json = HttpService:JSONDecode(raw)
            for _, server in ipairs(json.data or {}) do
                if server.id ~= game.JobId and (server.playing or 0) < (server.maxPlayers or 0) then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
                    return
                end
            end
            error("No eligible server in first 100 results")
        end)
        if not ok then notify("Hop failed: " .. tostring(err)) end
    end)
end)
section(worldPage, "Island teleport")
action(worldPage, "SELECTED ISLAND: Beginning Isle", function(btn)
    local nextIndex = 1
    for i, data in ipairs(ISLANDS) do
        if data[1] == state.selectedIsland then
            nextIndex = (i % #ISLANDS) + 1
            break
        end
    end
    state.selectedIsland = ISLANDS[nextIndex][1]
    btn.Text = "SELECTED ISLAND: " .. state.selectedIsland
end)
action(worldPage, "TELEPORT TO SELECTED ISLAND", function()
    teleportTo(cframeIsland(state.selectedIsland), state.selectedIsland)
end, true)
toggle(worldPage, "Return to selected island while idle", "stayIsland")
for _, item in ipairs(ISLANDS) do
    local targetName = item[1]
    local targetCF = CFrame.new(item[2], item[3], item[4])
    action(worldPage, "TP  /  " .. targetName, function()
        state.selectedIsland = targetName
        teleportTo(targetCF, targetName)
    end)
end

section(extraPage, "Quality of life")
toggle(extraPage, "Anti AFK (no spending)", "antiAFK")
toggle(extraPage, "Walk speed boost", "speedBoost")
stepper(extraPage, "Walk speed", "speed", 16, 50, 2, "")
toggle(extraPage, "Noclip (restore on OFF)", "noclip", function(v)
    if not v then
        for part, old in pairs(hub.touched) do
            if part and part.Parent then pcall(function() part.CanCollide = old end) end
        end
        hub.touched = {}
    end
end)
action(extraPage, "SAVE CURRENT POSITION", function()
    local _, root = getChar()
    if root then savedCFrame = root.CFrame; notify("Position saved for this session") end
end)
action(extraPage, "RETURN TO SAVED POSITION", function()
    if savedCFrame then teleportTo(savedCFrame, "saved position")
    else notify("No saved position yet") end
end)
action(extraPage, "TELEPORT TO WEATHER ISLE", function()
    teleportTo(cframeIsland("Weather Isle"), "Weather Isle")
end)
action(extraPage, "REJOIN GAME", function()
    TeleportService:Teleport(game.PlaceId, LocalPlayer)
end)
section(extraPage, "Safety and controls")
make("TextLabel", extraPage, {
    BackgroundTransparency = 1, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = colors.muted,
    Font = Enum.Font.Gotham, TextSize = 11,
    Text = "No automatic Cash/Crystal purchases, crafting, summons, trait rerolls or gacha. "
        .. "AUTO LEVEL requires manual rod upgrades; code redemption may fail. Rare protection is best-effort. "
        .. "RightShift to hide. All features UNTESTED in the live game.",
    Size = UDim2.new(1, -4, 0, 80),
})
action(extraPage,"COPY REDACTED FARM DIAGNOSTICS",function()
    local p=profile()
    local inv,count,maxCount=getInventory()
    local names={}
    for _,remote in ipairs(Events:GetChildren()) do
        if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
            table.insert(names,remote.Name..":"..remote.ClassName)
        end
    end
    table.sort(names)
    local d=p.data
    local dataNames={}
    if d then
        for _,child in ipairs(d:GetChildren()) do
            table.insert(dataNames,child.Name..":"..child.ClassName)
        end
    end
    table.sort(dataNames)
    local lines={
        "KITKIT HUB v2.1 REDACTED DIAGNOSTICS",
        "Level="..tostring(p.level).." XP="..tostring(p.xp).." Cash="..tostring(p.cash),
        "Rod="..tostring(p.rod).." Power="..tostring(rodPower(p.rod)),
        "Bag="..tostring(count).."/"..tostring(maxCount),
        "FishingGUI="..tostring(select(2,minigame())),
        "Known code attempts="..tostring((function() local n=0 for _ in pairs(codesAttempted) do n=n+1 end return n end)()),
        "Mode="..tostring(state.autoLevel).." State="..progressionStatus,
        "Data child keys="..table.concat(dataNames,", "),
        "Event names="..table.concat(names,", "),
        "No username, user ID, passwords, executor keys, webhooks or URLs exported.",
    }
    local t=table.concat(lines,"\n")
    if type(setclipboard)=="function" then
        local ok=pcall(setclipboard,t)
        if ok then notify("Diagnostics copied. Paste them here for troubleshooting.") return end
    end
    print(t)
    notify("Clipboard unavailable: diagnostics printed to executor console.")
end)

action(extraPage, "UNLOAD HUB + STOP ALL LOOPS", function() hub:Unload() end)

local minimized = false
local function minimize(v)
    minimized = v
    tabBar.Visible = not v
    content.Visible = not v
    footer.Visible = not v
    main.Size = UDim2.fromOffset(width, v and 49 or height)
    minButton.Text = v and "+" or "_"
end
track(minButton.MouseButton1Click:Connect(function() minimize(not minimized) end))
track(closeButton.MouseButton1Click:Connect(function() hub:Unload() end))
track(bubble.MouseButton1Click:Connect(function() main.Visible = true; bubble.Visible = false end))
track(UIS.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.RightShift then
        main.Visible = not main.Visible
        bubble.Visible = not main.Visible
    end
end))
activate("Level")

function hub:Unload()
    if not self.running then return end
    self.running = false
    for _, c in ipairs(self.connections) do
        pcall(function() c:Disconnect() end)
    end
    clearESP()
    for part, old in pairs(self.touched) do
        pcall(function() if part.Parent then part.CanCollide = old end end)
    end
    local _, _, hum = getChar()
    if hum and self.originals[hum] then
        pcall(function() hum.WalkSpeed = self.originals[hum] end)
    end
    pcall(function() if self.gui then self.gui:Destroy() end end)
    if env.KITKIT_HeavyweightFishing == self then env.KITKIT_HeavyweightFishing = nil end
    print("[KITKIT] Unloaded. All tracked loops and connections stopped.")
end

local function skillReady(char, key, fg)
    local skills = char and char:FindFirstChild("Skills")
    local obj = nil
    if skills then
        for _, s in ipairs(skills:GetChildren()) do
            if s:IsA("NumberValue") and tostring(s:GetAttribute("Key") or s.Name) == key then
                obj = s
                break
            end
        end
    end
    if skills and #skills:GetChildren() > 0 and not obj then return false end
    if obj then
        if obj.Value > 0 or (tonumber(obj:GetAttribute("UsingSkill")) or 0) > 0 then return false end
    end
    local sb = fg and fg:FindFirstChild("SkillButton")
    local frame = sb and sb:FindFirstChild("Frame")
    local btn = frame and frame:FindFirstChild(key)
    if btn then
        if btn:IsA("GuiObject") and not btn.Visible then return false end
        local lock = btn:FindFirstChild("Lock")
        local cd = btn:FindFirstChild("CD")
        if lock and lock:IsA("GuiObject") and lock.Visible then return false end
        if cd and cd:IsA("TextLabel") and cd.Visible and (tonumber(cd.Text:match("%d+%.?%d*")) or 0) > 0 then
            return false
        end
    end
    return obj ~= nil or btn ~= nil
end
local skillOrder = { "V", "X", "C", "Z" }
local skillIndex = 1
local function handleSkill(fg, char, now)
    if now - lastSkill < 0.30 then return end
    if char:GetAttribute("Phase2") == true then return end
    local rhythm = fg:FindFirstChild("Rhythm")
    local bossBar = fg:FindFirstChild("BossFightBar")
    if (rhythm and rhythm.Visible) or (bossBar and bossBar.Visible) then return end
    for step = 1, #skillOrder do
        local idx = ((skillIndex + step - 2) % #skillOrder) + 1
        local key = skillOrder[idx]
        if state["skill" .. key] and skillReady(char, key, fg) then
            if fire("UseSkill", key) then
                lastSkill = now
                skillIndex = (idx % #skillOrder) + 1
                break
            end
        end
    end
end
local function isTrap(obj)
    if obj:GetAttribute("Trap") == true or obj:GetAttribute("IsTrap") == true then return true end
    if obj.Name:lower():find("trap", 1, true) then return true end
    local col = obj.BackgroundColor3
    local redBG = col.R > 0.7 and col.G < 0.4 and col.B < 0.4
    local redImage = false
    if obj:IsA("ImageLabel") or obj:IsA("ImageButton") then
        local ic = obj.ImageColor3
        redImage = ic.R > 0.7 and ic.G < 0.4 and ic.B < 0.4
    end
    return redBG or redImage
end
local function handleRhythm(fg, now)
    if now - lastRhythm < 0.055 then return end
    lastRhythm = now
    local rhythm = fg:FindFirstChild("Rhythm")
    if not rhythm or not rhythm.Visible then return end
    for _, lane in ipairs({ "A", "S", "D" }) do
        if now - rhythmLaneHit[lane] > 0.11 then
            local lf = rhythm:FindFirstChild("Progression" .. lane)
            local target = lf and lf:FindFirstChild("BarFrame")
            if lf then
                local hitY = target and target.AbsolutePosition.Y + target.AbsoluteSize.Y/2 or nil
                local best, bestDist = nil, math.huge
                for _, child in ipairs(lf:GetChildren()) do
                    if child.Name == "Note_FX" and child:IsA("GuiObject") and child.Visible
                        and not rhythmSeen[child] and not isTrap(child) then
                        local dist = hitY and math.abs((child.AbsolutePosition.Y + child.AbsoluteSize.Y/2)-hitY)
                            or math.abs(child.Position.Y.Scale - (target and target.Position.Y.Scale or 0.85))*100
                        if dist < bestDist then best, bestDist = child, dist end
                    end
                end
                local tolerance = target and math.max(12, target.AbsoluteSize.Y + 9) or 16
                if best and bestDist <= tolerance then
                    rhythmSeen[best] = true
                    rhythmLaneHit[lane] = now
                    if not fire("RhythmHit", "hit") then
                        -- Not all executors expose VirtualInputManager, so this is a fallback only.
                        pcall(function()
                            local vim = game:GetService("VirtualInputManager")
                            local code = Enum.KeyCode[lane]
                            vim:SendKeyEvent(true, code, false, game)
                            task.delay(0.03, function()
                                if hub.running then vim:SendKeyEvent(false, code, false, game) end
                            end)
                        end)
                    end
                end
            end
        end
    end
end
local function phase2Click(fg, now)
    if now - lastPhase2 < 0.12 then return end
    local boss = fg:FindFirstChild("BossFightBar")
    if not boss or not boss.Visible then return end
    local bar, hit = boss:FindFirstChild("Bar"), boss:FindFirstChild("Hitbox")
    if not bar or not hit or not bar:IsA("GuiObject") or not hit:IsA("GuiObject") then return end
    local x = bar.AbsolutePosition.X + bar.AbsoluteSize.X / 2
    local left, right = hit.AbsolutePosition.X, hit.AbsolutePosition.X + hit.AbsoluteSize.X
    local bad = boss:FindFirstChild("HitboxBad")
    if bad and bad:IsA("GuiObject") and bad.Visible then
        if x >= bad.AbsolutePosition.X and x <= bad.AbsolutePosition.X + bad.AbsoluteSize.X then return end
    end
    if x > left + 2 and x < right - 2 then
        lastPhase2 = now
        local done = false
        local mg = PlayerGui:FindFirstChild("MainGui")
        local mobile = mg and mg:FindFirstChild("Mobile")
        local fishButton = mobile and mobile:FindFirstChild("Fishing")
        if fishButton and fishButton:IsA("GuiButton") and type(getconnections) == "function" then
            pcall(function()
                for _, connection in ipairs(getconnections(fishButton.MouseButton1Down)) do
                    if connection.Function then task.spawn(connection.Function); done = true; break end
                    if connection.Fire then connection:Fire(); done = true; break end
                end
            end)
        end
        if not done then
            pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendMouseButtonEvent(0, 0, 0, true, game, 0)
                task.delay(0.015, function()
                    if hub.running then vim:SendMouseButtonEvent(0, 0, 0, false, game, 0) end
                end)
            end)
        end
    end
end

-- Session progression and watchdog data (no XP spoofing).
local function trackInventory()
    local inv=getInventory()
    if inv==hub.trackedInventory then return end
    if hub.inventoryConnection then
        hub.inventoryConnection:Disconnect()
        hub.inventoryConnection=nil
    end
    hub.trackedInventory=inv
    if inv then
        lastBagSize=#inv:GetChildren()
        hub.inventoryConnection=track(inv.ChildAdded:Connect(function(child)
            if not hub.running then return end
            catchesThisSession=catchesThisSession+1
            lastCatchAt=os.clock()
            if flaggedRare(child) and state.autoLevel and state.protectRare then
                task.defer(function()
                    if hub.running and child.Parent then tryFavorite(child) end
                end)
            end
        end))
    end
end
local function stopAutoLevel(reason)
    state.autoLevel=false
    for _,k in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam","charge","rhythm","phase2","autoSell"}) do
        setState(k,false)
    end
    progressionStatus=reason
    if levelBtn then levelBtn.Text="START AUTO LEVEL TO 500" end
    notify(reason)
end
local function progressionTick()
    if not state.autoLevel then return end
    local now=os.clock()
    if now-lastAutoLevelTick<3 then return end
    lastAutoLevelTick=now
    local p=profile()
    if not p.data then
        progressionStatus="Waiting for replicated profile data"
        return
    end
    if state.autoCodes and p.data then redeemEligibleCodes(p.level) end
    if state.autoDailyQuest then claimCompletedDailies() end
    if p.level and p.level>=state.targetLevel then
        stopAutoLevel("GOAL HIT: Level "..p.level.."! Farming/selling stopped.")
        return
    end
    if p.level then
        if lastProfileLevel and p.level>lastProfileLevel then
            levelGained=levelGained+(p.level-lastProfileLevel)
            levelGainAt=now
            lastCatchAt=now
        end
        lastProfileLevel=p.level
    end
    if p.xp and p.xp~=lastProfileXP then
        lastCatchAt=now
        lastProfileXP=p.xp
    end
    trackInventory()
    local desired,power,index=routeChoice(p)
    if not power then
        progressionStatus="Rod Power unknown: staying on Beginning Isle"
    else
        progressionStatus="Farming "..desired.." (Power "..power..")"
    end
    if state.autoRoute and (now-lastAutoRoute>=18) then
        lastAutoRoute=now
        local _,root,hum=getChar()
        local _,active=minigame()
        local cf=cframeIsland(desired)
        if root and hum and hum.Health>0 and not active and not root.Parent:GetAttribute("Fishing") and cf
            and (root.Position-cf.Position).Magnitude>230 then
            teleportTo(cf,desired)
            lastCatchAt=now
        end
    end
    -- If we've made no XP and caught nothing on a higher island, back off one
    -- island temporarily. This avoids repeatedly failing catches on over-tier rods.
    if index>1 and now-lastCatchAt>155 then
        routeCooldownUntil[desired]=now+360
        local prev=LEVEL_ROUTE[index-1].name
        notify("No catch/XP progress for 155s. Trying "..prev.." for 6 minutes.")
        lastCatchAt=now
        lastAutoRoute=0
    elseif index==1 and now-lastCatchAt>180 then
        progressionStatus="Stalled: check tutorial / rod / reel / inventory"
        if now-lastAutoHealthCheck>120 then
            lastAutoHealthCheck=now
            notify("No XP/catches after 3 min. Check tutorial, rod purchase, and fishing GUI.")
        end
        -- do not force server remote spam or fabricate XP.
        lastCatchAt=now
    end
    local suggestion=nextRodSuggestion(p)
    if suggestion then
        local owned,pow=bestOwnedRod(p)
        if pow and pow>(rodPower(p.rod) or 0) then
            if lastRodPrompt~=("owned:"..owned) then
                lastRodPrompt="owned:"..owned
                notify("Equip your better owned rod: "..owned.." (Power "..pow..")")
            end
        elseif p.cash and p.cash>=suggestion.cost then
            if lastRodPrompt~=("buy:"..suggestion.name) then
                lastRodPrompt="buy:"..suggestion.name
                notify("Upgrade available: buy "..suggestion.name.." at "..suggestion.island.."'s Rod Seller")
            end
        end
    end
end

local function useFishingTools()
    return state.autoReel or state.lockBar or state.autoEnzo or state.autoLong
end
track(RunService.Heartbeat:Connect(function()
    if not hub.running then return end
    local now = os.clock()
    progressionTick()
    local fg, active = minigame()
    local char = LocalPlayer.Character
    if wasFishing and not active then lastFishingEnd = now end
    wasFishing = active
    local workingBoss = state.autoEnzo or state.autoLong
    if fg and active then
        if (state.lockBar or workingBoss) then
            local bf = fg:FindFirstChild("BarFrame")
            local bar = bf and bf:FindFirstChild("Bar")
            if bar and bar:IsA("GuiObject") then
                local p = bar.Position
                if p.X.Scale ~= 0.5 or p.Y.Scale ~= 0.5 then
                    bar.Position = UDim2.new(0.5, 0, 0.5, 0)
                end
            end
        end
        if (state.autoReel or workingBoss) and now - lastReel >= 0.12 then
            lastReel = now
            fire("UpdateFishProgression")
        end
        if (state.autoSkill or workingBoss) and char then handleSkill(fg, char, now) end
        if state.rhythm or workingBoss then handleRhythm(fg, now) end
        if state.phase2 or workingBoss then phase2Click(fg, now) end
    elseif workingBoss then
        if now - lastBossTry > state.bossDelay then
            lastBossTry = now
            task.spawn(function()
                if hub.running then startBoss(state.autoLong and "Long Diaohai" or "Enzo") end
            end)
        end
    elseif state.autoCast and char and now - lastCast > math.max(0.4, state.castDelay)
        and now - lastFishingEnd > math.max(0.4, state.castDelay) then
        lastCast = now
        if char:GetAttribute("Type") ~= "Fishing Rod" then
            task.spawn(equipRod)
        elseif not char:GetAttribute("Fishing") then
            local _, hrp = getChar()
            if hrp then fire("Fishing", hrp.CFrame) end
        end
    end
    if state.speedBoost and now - lastSpeed > 1 then
        local _, _, hum = getChar()
        if hum then
            if hub.originals[hum] == nil then hub.originals[hum] = hum.WalkSpeed end
            hum.WalkSpeed = state.speed
        end
        lastSpeed = now
    elseif not state.speedBoost and now - lastSpeed > 1 then
        local _, _, hum = getChar()
        if hum and hub.originals[hum] then
            hum.WalkSpeed = hub.originals[hum]
            hub.originals[hum] = nil
        end
        lastSpeed = now
    end
    if state.noclip and char then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                if hub.touched[part] == nil then hub.touched[part] = true end
                part.CanCollide = false
            end
        end
    end
end))

local slamEv = event("Slam")
if slamEv then
    track(slamEv.OnClientEvent:Connect(function(remote)
        if not hub.running or not (state.slam or state.autoEnzo or state.autoLong) then return end
        if remote and remote:IsA("RemoteEvent") then
            task.delay(0.05, function()
                if hub.running then pcall(function() remote:FireServer("Perfect") end) end
            end)
        end
    end))
end
local chargeEv = event("Charge")
if chargeEv then
    track(chargeEv.OnClientEvent:Connect(function(remote)
        if not hub.running or not (state.charge or state.autoEnzo or state.autoLong) then return end
        if remote and remote:IsA("RemoteEvent") then
            task.delay(1.05, function()
                if hub.running then pcall(function() remote:FireServer() end) end
            end)
        end
    end))
end
track(LocalPlayer.Idled:Connect(function()
    if not hub.running or not state.antiAFK then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new(0, 0))
    end)
end))
track(workspace:GetAttributeChangedSignal("Weather"):Connect(function()
    local weather = tostring(workspace:GetAttribute("Weather") or "Unknown")
    if weather ~= lastWeather then
        lastWeather = weather
        if state.fogAlert and (weather:lower():find("fog", 1, true)
            or weather:lower():find("mist", 1, true)) then
            notify("FOG / MIST detected in this server: " .. weather)
        end
    end
end))

task.spawn(function()
    while hub.running do
        local now = os.clock()
        local _, bagCount, bagMax = getInventory()
        local emergencySell = state.autoLevel and bagMax and bagMax>0
            and bagCount and bagCount>=bagMax-2 and now-lastSell>=10
        if state.autoSell and (now-lastSell>=state.sellDelay or emergencySell) then
            lastSell = now
            local ok, reason = maySell()
            if ok then
                local _,active=minigame()
                if not active then sellNow(false) end
            elseif reason:find("Rare fish",1,true) or reason:find("NOT confirmed",1,true) then
                if now-lastAutoHealthCheck>45 then
                    lastAutoHealthCheck=now
                    report("Auto-sell waiting: "..reason)
                end
            end
        end
        if state.stayIsland and not state.autoEnzo and not state.autoLong and now - lastTP >= 5 then
            lastTP = now
            local _, root = getChar()
            local _, active = minigame()
            local cf = cframeIsland(state.selectedIsland)
            if cf and root and not active and (root.Position - cf.Position).Magnitude > 70 then
                teleportTo(cf, state.selectedIsland)
            end
        end
        task.wait(1)
    end
end)
task.spawn(function()
    while hub.running do
        local b = scanBosses()
        local _, count, cap = getInventory()
        local weather = tostring(workspace:GetAttribute("Weather") or "Unknown")
        local p=profile()
        local route,power=routeChoice(p)
        local activeTime=math.max(1,(os.clock()-firstProfileAt)/3600)
        local gainRate=levelGained/activeTime
        statusTop.Text="Lv "..tostring(p.level or "?").."/"..state.targetLevel
            .." | Bag "..tostring(count or "?").."/"..tostring(cap or "?")
            .." | "..weather.." | Boss "..b.count
        weatherLabel.Text="Current weather: "..weather
        statusBottom.Text=lastAction
        levelingHUD.Text="Lv "..tostring(p.level or "?").." / "..state.targetLevel
            .." | "..tostring(p.rod~="" and p.rod or "Rod unknown")
            .."\nPower "..tostring(power or "?").." | "..tostring(p.cash or "?").." Cash"
            .." | "..string.format("%.1f",gainRate).." Lv/h"
        local suggested=nextRodSuggestion(p)
        routeHUD.Text="Status: "..progressionStatus
            .."\nRoute: "..route.." | Catches since load: "..catchesThisSession
            .."\nNext rod: "..(suggested and (suggested.name.." (~"..suggested.cost.." Cash)") or "Check live game")
        task.wait(3)
    end
end)

notify("KITKIT HUB v2.1 loaded. Use LEVEL > START AUTO LEVEL TO 500. Purchases are MANUAL.")
if state.fogAlert and (lastWeather:lower():find("fog", 1, true)
    or lastWeather:lower():find("mist", 1, true)) then
    task.delay(0.7, function()
        if hub.running then notify("This server is already foggy: " .. lastWeather) end
    end)
end
