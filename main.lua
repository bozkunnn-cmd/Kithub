--[[
KITKIT HUB v2.7 | Heavyweight Fishing (Roblox, place 98502499119821)
Original, inspectable Luau client script. No external library, key, webhook,
remote loader, speculative purchase remotes, paid summons or auto-rolls.
AUTO LEVEL is a best-effort farming assistant, NOT an XP/level bypass.
Quest and crafting requests are subject to server verification and may fail.
Rod buying uses game UI ONLY, targets one shop rod per island, and verifies ownership.
UI access and purchases are not guaranteed. Live behavior is untested.

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

local hub = { running = true, connections = {}, esp = {}, touched = {}, originals = {}, manualTravelUntil=0 }
env.KITKIT_HeavyweightFishing = hub

local state = {
    autoLevel = false, autoRoute = true, autoFavorite = true,
    autoBuyRod = true, autoSeaFacing = true,
    autoCodes = true, autoDailyQuest = true,
    autoQuests = false, autoTicketQuests = false, autoZengQuest = false,
    autoSageAfterAmber = true, ticketQuestMode = "Easy",
    autoCraftRod = false, autoFarmMaterials = false, autoCraftBait = false,
    protectMaterials = true, craftTarget = "Heavenpiercer Rod",
    merchantAlerts = true,
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
local reelRequests = 0
local lastSkill = 0
local lastSell = os.clock()
local lastBossTry = 0
local lastTP = 0
local lastFishingEnd = 0
local lastAutoRoute = 0
-- Explicit travel gate: Autolevel never casts until it has verified the intended dock.
-- Kept independent of the rod-shop and quest/craft route state machines.
hub.routeGate = {ready=false, island=nil, status="Idle", lastAttempt=-math.huge,
    lastTeleport=0, attempts=0, confirms=0, blockedCasts=0, lastBlockedLog=0}

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
local isCraftIngredient -- populated by the verified recipe engine (declared later)
local routeCooldownUntil = {}
local recoveryAttempts = 0
local catchesThisSession = 0
local lastBagSize = nil
local progressionStatus = "Idle"
local sellTracker = {status="Not attempted", attempts=0, confirmed=0, failed=0, pending=nil, lastResult=0,
    streak=0, buyerPhase="idle", buyerAt=0, lastBuyerTrip=0, returnCF=nil}
local facingTracker = {status="Waiting", checks=0, verified=0, fallbacks=0, lastAt=0, corrected=0, island="", failedCasts=0}
local rodShop = {phase="idle", status="Waiting to save", target=nil, phaseAt=0,
    lastVisit=0, untilAt=0, savedReturn=nil, clicks=0, cashBefore=nil, lastShopTarget="",
    failures={}, lastEquipAt=0, equipFailures=0, equipName="", equipStatus=""}
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
-- v2.4: retain the sea-facing orientation from the public StarCrow island
-- farm CFrames. v2.2 accidentally copied coordinates but dropped this rotation.
-- The sea raycast below validates and adjusts this orientation when possible.
local FARM_CFRAMES = {
    ["Beginning Isle"] = CFrame.new(-297.48,9.28,58.78, 0,0,1, 0,1,0, -1,0,0),
    ["Bamboo Isle"] = CFrame.new(-1310.04,9.28,29.79, -0.28,0,0.96, 0,1,0, -0.96,0,-0.28),
    ["Fallout Isle"] = CFrame.new(76.47,9.28,1265.92, -1,0,0.01, 0,1,0, -0.01,0,-1),
    ["Sovereign Isle"] = CFrame.new(-1254.18,9.28,1301.79, -1,0,-0.07, 0,1,0, 0.07,0,-1),
    ["Perch Isle"] = CFrame.new(-38.55,9.28,-1343.82, 0.99,0,-0.12, 0,1,0, 0.12,0,0.99),
    ["Frost Isle"] = CFrame.new(-1348.71,9.28,-1446.51, -1,0,-0.03, 0,1,0, 0.03,0,-1),
    ["Coconut Isle"] = CFrame.new(1431,9.28,-1430.22, -0.17,0,0.98, 0,1,0, -0.98,0,-0.17),
    ["Amber Isle"] = CFrame.new(1122.07,9.28,1414.54, 0.03,0,1, 0,1,0, -1,0,0.03),
    ["Battlefield Isle"] = CFrame.new(1249.73,19.56,68.87, 0.01,0,1, 0,1,0, -1,0,0.01),
    ["Mistpeak Isle"] = CFrame.new(2549.02,9.28,-80.77, -0.03,0,1, 0,1,0, -1,0,-0.03),
    ["World Angler Isle"] = CFrame.new(-2345.67,9.28,-203.65, -0.09,0,-1, 0,1,0, 1,0,-0.09),
    ["Weather Isle"] = CFrame.new(-2886.12,6.76,1199.79, -0.04,0,-1, 0,1,0, 1,0,-0.04),
    ["Mystic Reef Isle"] = CFrame.new(-2561.58,9.28,-1288.64, -0.07,0,-1, 0,1,0, 1,0,-0.07),
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
    if FARM_CFRAMES[name] then return FARM_CFRAMES[name] end
    for _, data in ipairs(ISLANDS) do
        if data[1] == name then return CFrame.new(data[2], data[3], data[4]) end
    end
    return nil
end
local function teleportTo(cf, name)
    local char, root = getChar()
    if not cf or not char or not root then report("Teleport unavailable: character not ready"); return false end
    local ok = pcall(function() root.CFrame = cf end)
    if ok then
        if state.autoLevel then
            -- Any external trip (buyer, shop, user teleport) invalidates the old dock.
            hub.routeGate.ready=false
            hub.routeGate.status="Checking location after teleport"
        end
        report("Teleported to " .. tostring(name or "target"))
    end
    return ok
end
-- Check several points in front of the dock. Raycasts are advisory because
-- some servers render water with non-queryable meshes, so retain the trusted
-- per-island orientation if none of the directions can be verified.
local function flatUnit(v)
    local flat=Vector3.new(v.X,0,v.Z)
    if flat.Magnitude<0.001 then return Vector3.new(0,0,-1) end
    return flat.Unit
end
local SEA_DISTANCES={35,65,95}
local SEA_ANGLES={0, -24, 24, -50, 50, -85, 85, 180}
local function waterAhead(pos,dir,char)
    local score=0
    local rayParams=RaycastParams.new()
    rayParams.FilterType=Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances=char and {char} or {}
    rayParams.IgnoreWater=false
    local ocean=workspace:FindFirstChild("Ocean")
    for _,dist in ipairs(SEA_DISTANCES) do
        local from=pos+dir*dist+Vector3.new(0,32,0)
        local ok,result=pcall(function()
            return workspace:Raycast(from,Vector3.new(0,-155,0),rayParams)
        end)
        if ok and result then
            local part=result.Instance
            local n=part and part.Name:lower() or ""
            if result.Material==Enum.Material.Water
                or (part and ocean and part:IsDescendantOf(ocean) and n:find("water",1,true))
                or n=="water" then
                score=score+1
            end
        end
    end
    return score
end
local function faceSea(island,force)
    if not state.autoSeaFacing then return true end
    local _,root,hum=getChar()
    if not root or not hum or hum.Health<=0 then return false end
    local target=cframeIsland(island)
    if not target then return true end
    if (root.Position-target.Position).Magnitude>185 then return true end
    local now=os.clock()
    if not force and facingTracker.island==island and now-facingTracker.lastAt<2.5 then return true end
    facingTracker.lastAt=now
    facingTracker.island=island
    facingTracker.checks=facingTracker.checks+1
    local base=flatUnit(target.LookVector)
    local bestDir,bestScore=base,-1
    for _,degrees in ipairs(SEA_ANGLES) do
        local dir=flatUnit(CFrame.fromAxisAngle(Vector3.new(0,1,0),math.rad(degrees)):VectorToWorldSpace(base))
        local score=waterAhead(root.Position,dir,root.Parent)
        -- Prefer the original, tested dock heading when water scores tie.
        local weighted=score*10-math.abs(degrees)/38
        if weighted>bestScore then bestScore=weighted; bestDir=dir end
    end
    local verified=waterAhead(root.Position,bestDir,root.Parent)>0
    if not verified then
        bestDir=base
        facingTracker.fallbacks=facingTracker.fallbacks+1
        facingTracker.status="Reference heading (water not raycastable)"
    else
        facingTracker.verified=facingTracker.verified+1
        facingTracker.status="Sea detected: "..island
    end
    local forward=flatUnit(root.CFrame.LookVector)
    if forward:Dot(bestDir)<0.975 then
        local here=root.Position
        local ok=pcall(function() root.CFrame=CFrame.lookAt(here,here+bestDir) end)
        if ok then facingTracker.corrected=facingTracker.corrected+1 end
        return ok
    end
    return true
end
local function minigame()
    local main = PlayerGui:FindFirstChild("MainGui")
    local fg = main and main:FindFirstChild("Fishing")
    return fg, (fg and fg:IsA("GuiObject") and fg.Visible == true) or false
end
-- Robust fishing-bar controller (v2.2).
-- The game can continuously tween this UI object. A single Heartbeat assignment
-- can be overwritten before the next rendered frame. Correct on changes and on
-- three frame phases, while doing nothing when the feature is switched off.
local BAR_CENTER = UDim2.new(0.5, 0, 0.5, 0)
local barGuard = {
    bar = nil, positionConnection = nil, changing = false,
    status = "OFF", corrections = 0, positionEvents = 0, errors = 0,
    lastCorrection = "none", lastError = "none", lastSeen = 0,
    missingSince = nil, lastWarning = 0,
}
local function wantsBarLock()
    return hub.running and (state.lockBar or state.autoEnzo or state.autoLong)
end
local function disconnectBarListener()
    if barGuard.positionConnection then
        pcall(function() barGuard.positionConnection:Disconnect() end)
    end
    barGuard.positionConnection = nil
    barGuard.bar = nil
    barGuard.changing = false
end
local function moveBarToCenter(bar, reason)
    if not wantsBarLock() or not bar or not bar.Parent or barGuard.changing then return end
    local _, active = minigame()
    if not active then return end
    local pos = bar.Position
    if pos == BAR_CENTER then
        barGuard.status = "LOCKED"
        return
    end
    barGuard.changing = true
    -- Cancel competing client tweens when supported, but do not let an
    -- unavailable TweenPosition stop the direct fallback assignment.
    pcall(function()
        bar:TweenPosition(BAR_CENTER, Enum.EasingDirection.InOut, Enum.EasingStyle.Linear, 0, true)
    end)
    local ok, err = pcall(function()
        bar.Position = BAR_CENTER
    end)
    barGuard.changing = false
    if ok then
        barGuard.corrections = barGuard.corrections + 1
        barGuard.lastCorrection = tostring(reason) .. " (from " .. tostring(pos) .. ")"
        barGuard.status = "LOCKED"
    else
        barGuard.errors = barGuard.errors + 1
        barGuard.lastError = tostring(err)
        barGuard.status = "ERROR"
    end
end
local function monitorFishingBar()
    if not wantsBarLock() then
        barGuard.status = "OFF"
        if barGuard.bar then disconnectBarListener() end
        return
    end
    local fg, active = minigame()
    if not active then
        barGuard.status = "WAITING FOR FISH"
        barGuard.missingSince = nil
        if barGuard.bar and not barGuard.bar.Parent then disconnectBarListener() end
        return
    end
    local frame = fg:FindFirstChild("BarFrame")
    local bar = frame and frame:FindFirstChild("Bar")
    if not bar or not bar:IsA("GuiObject") then
        barGuard.status = "BAR OBJECT MISSING"
        local now = os.clock()
        if not barGuard.missingSince then barGuard.missingSince = now end
        if now - barGuard.missingSince >= 4 and now - barGuard.lastWarning >= 25 then
            barGuard.lastWarning = now
            report("Bar guard cannot find Fishing.BarFrame.Bar. Copy diagnostics in Other tab.")
        end
        return
    end
    barGuard.missingSince = nil
    barGuard.lastSeen = os.clock()
    if bar ~= barGuard.bar then
        disconnectBarListener()
        barGuard.bar = bar
        local ok, connection = pcall(function()
            return bar:GetPropertyChangedSignal("Position"):Connect(function()
                if not wantsBarLock() or barGuard.changing then return end
                barGuard.positionEvents = barGuard.positionEvents + 1
                moveBarToCenter(bar, "position event")
            end)
        end)
        if ok then
            barGuard.positionConnection = connection
        else
            barGuard.errors = barGuard.errors + 1
            barGuard.lastError = tostring(connection)
        end
    end
    moveBarToCenter(bar, "frame")
end
local function reelDiagnostics()
    local b = barGuard.bar
    local info = {
        "ReelLockEnabled=" .. tostring(wantsBarLock()),
        "ReelLockStatus=" .. barGuard.status,
        "BarListenerBound=" .. tostring(barGuard.positionConnection ~= nil),
        "BarCorrections=" .. tostring(barGuard.corrections),
        "BarPositionEvents=" .. tostring(barGuard.positionEvents),
        "BarErrors=" .. tostring(barGuard.errors),
        "ReelRemoteRequests=" .. tostring(reelRequests),
        "LastBarCorrection=" .. barGuard.lastCorrection,
        "LastBarError=" .. barGuard.lastError,
    }
    if b and b.Parent then
        local parent = b.Parent
        local actualCenter = b.AbsolutePosition.X + b.AbsoluteSize.X / 2
        local parentCenter = parent.AbsolutePosition.X + parent.AbsoluteSize.X / 2
        table.insert(info, "BarPosition=" .. tostring(b.Position))
        table.insert(info, "BarAnchorPoint=" .. tostring(b.AnchorPoint))
        table.insert(info, "VisualOffsetFromParentCenterPx=" .. string.format("%.1f", actualCenter - parentCenter))
        table.insert(info, "BarAbsoluteSize=" .. tostring(b.AbsoluteSize))
        table.insert(info, "BarParentAbsoluteSize=" .. tostring(parent.AbsoluteSize))
    end
    return table.concat(info, "\n")
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
    -- Islands are selected by the equipped rod's Power, not an invented level-10 gate.
    -- Rods for the NEXT island may be sold there before the current rod can fish there.
    if not power then return "Beginning Isle",nil,1 end
    while index>1 and os.clock()<(routeCooldownUntil[LEVEL_ROUTE[index].name] or 0) do
        index=index-1
    end
    return LEVEL_ROUTE[index].name,power,index
end
-- Only the strongest practical cash-buyable target per island. No intermediate shop rods.
-- Quest-only Cryo Gravity and Soul Thorn require quests. The cash ladder
-- instead selects Inferno Gravity and Thunder Thorn until quests are done.
-- Perch: Diamond Spine is chosen ONLY when the live game module confirms it
-- has more Power than Platinum; otherwise skip the redundant 4M purchase.
-- Quest/crafted rods are not guessed as cash purchases.
local ROD_LADDER={
    {name="Enchanted Steel Rod",fallbackPower=19, cost=2000,island="Beginning Isle"},
    {name="Shadow Rod",fallbackPower=29, cost=60000,island="Bamboo Isle"},
    {name="Golden Rod",fallbackPower=35, cost=200000,island="Fallout Isle"},
    {name="Inferno Rod",fallbackPower=48, cost=1500000,island="Sovereign Isle"},
    {name="Platinum Spine Rod",fallbackPower=54, cost=3000000,island="Perch Isle"},
    {name="Inferno Gravity Rod",fallbackPower=62, cost=7000000,island="Frost Isle"},
    {name="Thunder Thorn Rod",fallbackPower=67, cost=10000000,island="Coconut Isle"},
    {name="Starlight Rod",fallbackPower=83, cost=60000000,island="Amber Isle"},
}
local function shopPrice(rod,fallback)
    local data=itemModule(rod)
    if data and not data.Ingredient then
        for _,key in ipairs({"Price","CashPrice","Cost","BuyPrice"}) do
            local val=tonumber(data[key])
            if val and val>0 and val<1e12 then return val,true end
        end
    end
    return fallback,false
end
local function perIslandTarget(entry)
    if entry.island=="Perch Isle" then
        local platinum=rodPower("Platinum Spine Rod") or 54
        local diamondData=itemModule("Diamond Spine Rod")
        local diamond=diamondData and tonumber(diamondData.Power or diamondData.Strength or diamondData.MaxPower)
        if diamond and diamond>platinum then
            local cost,live=shopPrice("Diamond Spine Rod",4000000)
            return {name="Diamond Spine Rod",power=diamond,cost=cost,island=entry.island,
                verifiedPrice=live}
        end
    end
    local cost,live=shopPrice(entry.name,entry.cost)
    return {name=entry.name,power=rodPower(entry.name) or entry.fallbackPower,
        cost=cost,island=entry.island,verifiedPrice=live,
        mayRequireQuest=entry.mayRequireQuest}
end
local function nextRodSuggestion(p)
    p=p or profile()
    local current=rodPower(p.rod) or 0
    local ownedName,ownedPower=bestOwnedRod(p)
    current=math.max(current,ownedPower or 0)
    for _,tier in ipairs(ROD_LADDER) do
        local item=perIslandTarget(tier)
        if item.power>current then return item end
    end
    return nil
end
-- Shows the next island/shop goal without pretending that buying the previous
-- island's best rod meets the next island's minimum catch Power.
function hub.nextIslandGoal(p)
    local island,power,index=routeChoice(p)
    local nextEntry=LEVEL_ROUTE[index+1]
    local target=nextRodSuggestion(p)
    return island, nextEntry and nextEntry.name or nil,
        nextEntry and nextEntry.power or nil, target, power
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
    -- Craft protection always requires server-replicated inventory data.
    if not inv then
        if state.protectMaterials and (state.autoFarmMaterials or state.autoCraftRod) then
            return false,"No inventory data; cannot protect crafting fish"
        end
        if state.protectRare and not state.fastSell then
            return false,"No inventory data to check rare fish"
        end
        return true,"Blind timed sale; inventory not replicated"
    end
    if count==0 then return false,"Nothing to sell" end
    -- Sell All does NOT sell favorites, but do not send it until every
    -- crafting ingredient has confirmed favorite status in replicated data.
    if state.protectMaterials then
        for _,item in ipairs(inv:GetChildren()) do
            if isCraftIngredient and isCraftIngredient(item) and not isFavorite(item) then
                tryFavorite(item)
                return false,"Craft fish not favorited yet: "..item.Name
            end
        end
    end
    if state.sellNearFull and (not maximum or maximum<=0 or count/maximum<0.88) then
        return false,"Bag below 88% or limit unknown"
    end
    if state.protectRare and not state.fastSell then
        for _,item in ipairs(inv:GetChildren()) do
            if flaggedRare(item) and not isFavorite(item) then
                tryFavorite(item)
                return false,"Rare fish NOT confirmed favorite: "..item.Name
            end
        end
    end
    return true,"Ready"
end
local function checkSellResult()
    local pending=sellTracker.pending
    if not pending or os.clock()-pending.at<5 then return end
    local _,count=getInventory()
    local cash=profile().cash
    local cashRaised=(pending.cash~=nil and cash~=nil and cash>pending.cash)
    local bagShrunk=(pending.count~=nil and count~=nil and count<pending.count)
    if cashRaised or bagShrunk then
        sellTracker.confirmed=sellTracker.confirmed+1
        sellTracker.streak=0
        sellTracker.status="CONFIRMED: "..(cashRaised and "Cash increased" or "bag decreased")
    elseif (pending.cash==nil or cash==nil) and (pending.count==nil or count==nil) then
        sellTracker.status="UNVERIFIED: game data unavailable"
    else
        sellTracker.failed=sellTracker.failed+1
        sellTracker.streak=sellTracker.streak+1
        sellTracker.status="UNCONFIRMED: no visible Cash/bag change"
    end
    sellTracker.lastResult=os.clock()
    sellTracker.pending=nil
end
local function sellNow(skipNearFull)
    if sellTracker.pending then return false end
    local original=state.sellNearFull
    if skipNearFull then state.sellNearFull=false end
    local ok,reason=maySell()
    state.sellNearFull=original
    if not ok then
        sellTracker.status="Blocked: "..reason
        if skipNearFull and not reason:find("Nothing to sell",1,true) then report(sellTracker.status) end
        return false
    end
    local _,count=getInventory()
    local cash=profile().cash
    local sent=fire("SellFish","All")
    if sent then
        sellTracker.attempts=sellTracker.attempts+1
        sellTracker.status="Sent to server; awaiting verification"
        sellTracker.pending={at=os.clock(),count=count,cash=cash}
        report("Sell All sent; checking whether Cash or bag count changes.")
    else
        sellTracker.status="SellFish remote unavailable or errored"
    end
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

-- v2.4 guarded UI-driven rod purchasing. We do not guess/forge an
-- undocumented purchase RemoteEvent or invoke a random remote with Cash.
-- The in-game shop must expose an exact matching rod name and Buy button.
local function isShopping()
    return rodShop.phase~="idle" and rodShop.phase~="cooldown"
end
local function ownedRod(name,p)
    p=p or profile()
    local inv=p.data and p.data:FindFirstChild("FishingRodInventory")
    return inv and inv:FindFirstChild(name)~=nil or false
end
local function cleanName(txt)
    return tostring(txt or ""):lower():gsub("[^%w]","")
end
local function guiVisible(obj)
    local cur=obj
    while cur and cur~=PlayerGui do
        if cur:IsA("ScreenGui") and not cur.Enabled then return false end
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        cur=cur.Parent
    end
    return cur==PlayerGui
end
local function buttonActionText(btn)
    local words={btn.Name}
    if btn:IsA("TextButton") then table.insert(words,btn.Text) end
    for _,x in ipairs(btn:GetDescendants()) do
        if x:IsA("TextLabel") then table.insert(words,x.Text) end
    end
    return table.concat(words," "):lower()
end
local function actionButtonForRod(name,action)
    local gui=PlayerGui:FindFirstChild("MainGui")
    if not gui then return nil end
    local wanted=cleanName(name)
    local matching={}
    for _,obj in ipairs(gui:GetDescendants()) do
        if guiVisible(obj) and obj:IsA("GuiObject") then
            local shown=(obj:IsA("TextLabel") or obj:IsA("TextButton")) and obj.Text or obj.Name
            local norm=cleanName(shown)
            if norm==wanted or (norm:sub(1,#wanted)==wanted
                and #norm-#wanted<=18) then table.insert(matching,obj) end
        end
    end
    local best,bestDepth=nil,1e9
    for _,match in ipairs(matching) do
        local ancestor=match
        for depth=0,4 do
            if not ancestor or ancestor==gui then break end
            -- Never click a generic Buy button from an entire multi-rod
            -- shop page; only use the exact rod's local item/card hierarchy.
            local unrelated=0
            for _,node in ipairs(ancestor:GetDescendants()) do
                if node:IsA("TextLabel") and node~=match then
                    if ROD_POWER[node.Text] and cleanName(node.Text)~=wanted then
                        unrelated=unrelated+1
                        break
                    end
                end
            end
            for _,btn in ipairs(ancestor:GetDescendants()) do
                if unrelated==0 and depth<=3 and btn:IsA("GuiButton") and guiVisible(btn) then
                    local caption=buttonActionText(btn)
                    local isBuy=caption:find("buy",1,true) or caption:find("purchase",1,true)
                    local isEquip=caption:find("equip",1,true) or caption:find("use",1,true)
                    if (action=="buy" and isBuy) or (action=="equip" and isEquip) then
                        if depth<bestDepth then best=btn;bestDepth=depth end
                    end
                end
            end
            if bestDepth==depth then break end
            ancestor=ancestor.Parent
        end
    end
    return best
end
local function clickGameButton(btn,secondMethod)
    if not btn or not guiVisible(btn) then return false end
    if not secondMethod then
        local ok=pcall(function() btn:Activate() end)
        if ok then return true end
    end
    local ok=pcall(function()
        local center=btn.AbsolutePosition+btn.AbsoluteSize/2
        local vim=game:GetService("VirtualInputManager")
        vim:SendMouseButtonEvent(center.X,center.Y,0,true,game,0)
        task.delay(0.06,function()
            if hub.running then
                pcall(function() vim:SendMouseButtonEvent(center.X,center.Y,0,false,game,0) end)
            end
        end)
    end)
    return ok
end
local function findInventoryNavigation()
    local gameGui=PlayerGui:FindFirstChild("MainGui")
    if not gameGui then return nil end
    for _,btn in ipairs(gameGui:GetDescendants()) do
        if btn:IsA("GuiButton") and guiVisible(btn) then
            local n=cleanName(btn.Name)
            local label=cleanName(buttonActionText(btn))
            if n=="inventory" or n=="openinventory" or n=="inventorybutton"
                or n=="rods" or label=="inventory" or label=="rods" then
                return btn
            end
        end
    end
    return nil
end
local function findRodVendor()
    local from=cframeIsland(rodShop.target and rodShop.target.island or "Beginning Isle")
    local best,bestDist=nil,math.huge
    for _,folderName in ipairs({"NPC","NPCs","Merchant","NPCDialogue"}) do
        local folder=workspace:FindFirstChild(folderName)
        if folder then
            for _,obj in ipairs(folder:GetDescendants()) do
                local n=cleanName(obj.Name)
                if n=="biaodi" or n=="rodseller" or n=="buyfishingrod" then
                    local p=getPart(obj)
                    if p then
                        local dist=from and (p.Position-from.Position).Magnitude or 0
                        if dist<bestDist and dist<450 then best,bestDist=obj,dist end
                    end
                end
            end
        end
    end
    return best
end
-- Some servers accept SellFish from anywhere; others may reject it away
-- from Nana, the Fish Buyer. Travel after repeated unconfirmed sales
-- (or one failure when the bag is nearly full),
-- verify again at close range and return to the saved fishing location.
local function buyerTripActive()
    return sellTracker.buyerPhase~="idle"
end
function hub.shopNeedsPause(p)
    if not state.autoLevel or not state.autoBuyRod then return false,nil end
    if rodShop.phase~="idle" and rodShop.phase~="cooldown" then
        return true,"Rod shop: "..rodShop.phase
    end
    if rodShop.phase=="cooldown" and os.clock()<rodShop.untilAt then
        return false,nil
    end
    if buyerTripActive() or sellTracker.pending or os.clock()<(hub.manualTravelUntil or 0) then
        return false,nil
    end
    p=p or profile()
    local owned,power=bestOwnedRod(p)
    if power and power>(rodPower(p.rod) or 0) then
        if (rodShop.equipFailures or 0)<3 then
            return true,"Equip owned "..owned
        end
        return false,nil -- UI cannot equip it; continue farming with a diagnostic
    end
    local target=nextRodSuggestion(p)
    if target and p.cash and p.cash>=target.cost and not ownedRod(target.name,p)
        and (rodShop.failures[target.name] or 0)<2 then
        return true,"Buy "..target.name.." at "..target.island
    end
    return false,nil
end
local function findFishBuyer()
    local _,root=getChar()
    if not root then return nil end
    local best,bestDistance=nil,math.huge
    for _,folderName in ipairs({"NPC","NPCs","Merchant","NPCDialogue"}) do
        local folder=workspace:FindFirstChild(folderName)
        if folder then
            for _,obj in ipairs(folder:GetDescendants()) do
                local n=cleanName(obj.Name)
                -- Nana is the actual fish buyer; Biao Ge sets spawn and is NOT a buyer.
                if n=="nana" or n=="sellfish" or n=="fishbuyer" then
                    local part=getPart(obj)
                    if part then
                        local dist=(part.Position-root.Position).Magnitude
                        if dist<bestDistance and dist<400 then
                            best,bestDistance=part,dist
                        end
                    end
                end
            end
        end
    end
    return best
end
local function buyerTick()
    local now=os.clock()
    local _,root,hum=getChar()
    if not root or not hum or hum.Health<=0 then return end
    if sellTracker.buyerPhase=="idle" then
        if not state.autoSell or isShopping() or sellTracker.pending
            or now-sellTracker.lastBuyerTrip<120 then return end
        local _,count,maximum=getInventory()
        local bagNearlyFull=count and maximum and maximum>0 and count>=maximum-1
        -- If the bag is blocking XP, try Nana after ONE unsuccessful remote.
        if sellTracker.streak<2 and not (bagNearlyFull and sellTracker.streak>=1) then return end
        local _,active=minigame()
        if not count or count<1 or active then return end
        local buyer=findFishBuyer()
        sellTracker.lastBuyerTrip=now
        if not buyer then
            sellTracker.status="No nearby Fish Buyer loaded (direct selling unconfirmed)"
            return
        end
        sellTracker.returnCF=root.CFrame
        sellTracker.buyerPhase="travel"
        sellTracker.buyerAt=now
        sellTracker.prompted=false
        teleportTo(buyer.CFrame*CFrame.new(0,0,-5),"Nana / Fish Buyer recovery")
        sellTracker.status="At Fish Buyer: retrying sale"
        return
    end
    if sellTracker.buyerPhase=="travel" and now-sellTracker.buyerAt>=1.3 then
        if sellTracker.pending then return end
        if not sellTracker.prompted then
            sellTracker.prompted=true
            local buyer=findFishBuyer()
            local obj=buyer and buyer.Parent
            local prompt=obj and obj:FindFirstChildWhichIsA("ProximityPrompt",true)
            if prompt and prompt.Enabled and type(fireproximityprompt)=="function" then
                local ok=pcall(function() fireproximityprompt(prompt) end)
                if ok then
                    sellTracker.status="Interacting with Nana before sale"
                    sellTracker.buyerAt=now
                    sellTracker.buyerPhase="settle"
                    return
                end
            end
        end
        sellTracker.buyerPhase="settle"
        sellTracker.buyerAt=now-1
    end
    if sellTracker.buyerPhase=="settle" and now-sellTracker.buyerAt>=0.8 then
        if sellNow(true) then
            sellTracker.buyerPhase="verify"
            sellTracker.buyerAt=now
        else
            sellTracker.buyerPhase="return"
        end
    end
    if sellTracker.buyerPhase=="verify" and sellTracker.pending==nil then
        sellTracker.buyerPhase="return"
    end
    if now-sellTracker.buyerAt>14 then sellTracker.buyerPhase="return" end
    if sellTracker.buyerPhase=="return" then
        local returnCF=sellTracker.returnCF
        sellTracker.returnCF=nil
        sellTracker.buyerPhase="idle"
        sellTracker.streak=0
        if returnCF then teleportTo(returnCF,"resume fishing"); facingTracker.lastAt=0 end
    end
end

local function finishRodShop(reason,delay)
    rodShop.status=reason
    rodShop.lastShopTarget=rodShop.target and rodShop.target.name or ""
    if rodShop.target and (reason:find("did not",1,true)
        or reason:find("Cannot",1,true) or reason:find("unverified",1,true)) then
        local n=rodShop.target.name
        rodShop.failures[n]=(rodShop.failures[n] or 0)+1
    end
    rodShop.lastVisit=os.clock()
    rodShop.untilAt=os.clock()+(delay or 65)
    rodShop.phase="cooldown"
    rodShop.target=nil
    rodShop.clicks=0
    local pos=rodShop.savedReturn
    rodShop.savedReturn=nil
    if pos and hub.running then
        local _,root=getChar()
        local _,active=minigame()
        if root and not active then
            teleportTo(pos,"return to fishing")
            facingTracker.lastAt=0
        end
    end
    report("Rod shop: "..reason)
end
local function shopTick()
    if not hub.running or not state.autoLevel or not state.autoBuyRod then return end
    if os.clock()<(hub.manualTravelUntil or 0) then return end
    local now=os.clock()
    local p=profile()
    if rodShop.phase=="cooldown" then
        if now<rodShop.untilAt then return end
        rodShop.phase="idle"
    end
    local _,active=minigame()
    local char,root,hum=getChar()
    if not root or not hum or hum.Health<=0 then return end
    if rodShop.phase=="idle" then
        if buyerTripActive() or sellTracker.pending or active or char:GetAttribute("Fishing") then return end
        local owned,power=bestOwnedRod(p)
        if power and power>(rodPower(p.rod) or 0) then
            if rodShop.equipName~=owned then
                rodShop.equipName=owned
                rodShop.equipFailures=0
            end
            if rodShop.equipFailures>=3 then
                rodShop.status="Manual equip needed: "..owned.." (UI tried 3 times)"
                return
            end
            rodShop.status="Equipping owned rod: "..owned
            if now-rodShop.lastEquipAt>=8 then
                local equipBtn=actionButtonForRod(owned,"equip")
                local nav=not equipBtn and findInventoryNavigation() or nil
                if equipBtn then
                    clickGameButton(equipBtn)
                    rodShop.status="Equip clicked: "..owned.."; checking replicated data"
                elseif nav then
                    clickGameButton(nav)
                    rodShop.status="Opened inventory for "..owned
                else
                    rodShop.status="Cannot find equip UI for "..owned
                end
                rodShop.lastEquipAt=now
                rodShop.equipFailures=rodShop.equipFailures+1
            end
            return
        else
            rodShop.equipFailures=0
            rodShop.equipName=""
        end
        local target=nextRodSuggestion(p)
        if not target then rodShop.status="All shop targets passed";return end
        if not p.cash or p.cash<target.cost then
            rodShop.status="Saving for "..target.name.." ("..tostring(target.cost).." Cash)"
            return
        end
        if ownedRod(target.name,p) then return end
        if (rodShop.failures[target.name] or 0)>=2 then
            rodShop.status="Shop UI failed twice for "..target.name.."; manual purchase needed"
            return
        end
        rodShop.target=target
        rodShop.savedReturn=root.CFrame
        rodShop.phase="travel"
        rodShop.phaseAt=now
        rodShop.clicks=0
        rodShop.status="Traveling to "..target.island.." Rod Seller"
    end
    local target=rodShop.target
    if not target then finishRodShop("Missing rod target",90); return end
    if (rodPower(p.rod) or 0)>=target.power or ownedRod(target.name,p) then
        local equip=actionButtonForRod(target.name,"equip")
        if equip then clickGameButton(equip) end
        finishRodShop("Owned "..target.name.."; "
            ..(equip and "Equip clicked" or "open Inventory to equip"),3)
        return
    end
    if now-rodShop.phaseAt>57 then
        finishRodShop("Shop UI did not complete "..target.name.."; manual check needed",120)
        return
    end
    if rodShop.phase=="travel" then
        local islandCF=cframeIsland(target.island)
        if islandCF and (root.Position-islandCF.Position).Magnitude>160 then
            teleportTo(islandCF,target.island.." rod shop")
            return
        end
        rodShop.phase="open"
        rodShop.phaseAt=now
        rodShop.status="Opening Rod Seller for "..target.name
        return
    end
    if rodShop.phase=="open" then
        if not p.cash or p.cash<target.cost then
            finishRodShop("Insufficient Cash for "..target.name.."; no purchase",60)
            return
        end
        local buy=actionButtonForRod(target.name,"buy")
        if buy then
            -- One button interaction, then WAIT for server-owned data.
            rodShop.clicks=rodShop.clicks+1
            local ok=clickGameButton(buy,rodShop.clicks>=2)
            rodShop.cashBefore=p.cash
            rodShop.phase="pending"
            rodShop.phaseAt=now
            rodShop.status=ok and ("Buy clicked: "..target.name.."; verifying ownership")
                or ("Shop button could not activate: "..target.name)
            if not ok then finishRodShop("Cannot activate shop Buy button",120) end
            return
        end
        local vendor=findRodVendor()
        if not vendor then
            rodShop.status="Waiting for Rod Seller NPC to stream in"
            return
        end
        local part=getPart(vendor)
        if part and (root.Position-part.Position).Magnitude>10 then
            teleportTo(part.CFrame*CFrame.new(0,0,-5),"Rod Seller")
            return
        end
        if now-rodShop.lastVisit>3 then
            local prompt=vendor:FindFirstChildWhichIsA("ProximityPrompt",true)
            if prompt and type(fireproximityprompt)=="function" then
                rodShop.lastVisit=now
                pcall(function() fireproximityprompt(prompt) end)
                rodShop.status="Interacting with "..target.island.." Rod Seller"
            else
                rodShop.status="Open Rod Seller manually: shop prompt not available"
            end
        end
        return
    end
    if rodShop.phase=="pending" and now-rodShop.phaseAt>8 then
        if p.cash and rodShop.cashBefore and p.cash<rodShop.cashBefore then
            finishRodShop("Cash changed but rod ownership unverified; STOPPED retries",180)
            return
        end
        if rodShop.clicks>=2 then
            finishRodShop("Buy UI did not confirm ownership; STOPPED retries",180)
        else
            rodShop.phase="open"
            rodShop.phaseAt=now
            rodShop.status="Retrying UI click once via input event"
        end
    end
end
local ext=(function()
-- v2.4 progression and quest/craft engine. Only server-replicated data may
-- confirm purchases, quests or crafts. Research URLs are in the patch notes.
local questTracker = {status="Idle", sage="waiting", sageRoute=nil, nextAt=0,
    lastInteract=-math.huge, lastTicket=-math.huge, lastUI=-math.huge, ticketStatus="Idle", side="Idle",
    lastDaily=0, pausedUntil=0, lastSageVisit=0, lastProgress="", lastZeng=-math.huge, zengStatus="OFF", routeLockUntil=0}
local craftTracker = {status="Idle", route=nil, fish=nil, lastAt=-math.huge,
    attempts=0, lastBefore=nil, pendingAt=0, lastBaitAt=-math.huge,
    lastEquipBaitAt=-math.huge, lastSuccessful=nil, fishCount=0}
local merchantTracker = {Maoshan=nil,Taoist=nil, lastSeen={}, lastScan=-math.huge,
    alerts=0, seenThisSession={}}
local QUESTRUN_CATALOG = {
    -- autoKey points only to handlers that already exist in this build.
    {id="SageDiamond",npc="Sage Yijiu",island="Battlefield Isle",reward="Diamond Rod",rewardType="Rod",type="Sage 1",objective="Catch 5 fish of at least 1,500,000 kg each",autoKey="autoSageAfterAmber",automation="Auto: accept / farm / turn-in attempt"},
    {id="SagePhoenix",npc="Sage Yijiu",island="Battlefield Isle",reward="Phoenix Annihilation Art",rewardType="Skill",type="Sage 2",objective="Own Phoenix Strive Art v2; catch 250 fish; catch Scarlet Fish and Elder Scarlet Fish at 1.5M kg in Bamboo Thunderstorm",automation="Track only: later Sage stage not implemented"},
    {id="SageFivefold",npc="Sage Yijiu",island="Battlefield Isle",reward="Fivefold Ascension",rewardType="Skill",type="Sage 3",objective="Catch a 2M kg Draconic Koi; own Sever The Gate v3; catch 10 fish of 1M kg",automation="Track only: later Sage stage not implemented"},
    {id="SageTenfold",npc="Sage Yijiu",island="Battlefield Isle",reward="Tenfold Convergence",rewardType="Skill",type="Sage 4",objective="Catch a 6M kg Rainbow Dragon Fish; use Fivefold Ascension 50 times",automation="Track only: later Sage stage not implemented"},
    {id="SageOneHook",npc="Sage Yijiu",island="Battlefield Isle",reward="One Hook Dominance",rewardType="Skill",type="Sage 5",objective="Catch a 5M kg Frost Kingfish and 6.5M kg Frost Queen Fish; use Tenfold Convergence 100 times",automation="Track only: later Sage stage not implemented"},
    {id="CryoGravity",npc="Biao Di",island="Frost Isle",reward="Cryo Gravity Rod",rewardType="Rod",type="Rod quest",objective="100 Frost catches; two 1M+ kg Primordial Kunfish Overlords; four Primordial Kunfish",automation="Track only: seller quest dialogue not verified"},
    {id="SoulThorn",npc="Biao Di",island="Coconut Isle",reward="Soul Thorn Rod",rewardType="Rod",type="Rod quest",objective="Three 1M+ kg Mutated Koi Whales; five Warbringer Sharks; five Dreadscale Groupers",automation="Track only: seller quest dialogue not verified"},
    {id="GiangBamboo",npc="Giang Lao",island="Bamboo Isle",reward="Shadowless Taiji Strike",rewardType="Skill",type="NPC quest",objective="Quest objectives are server-defined; inspect live quest module",automation="Track only: live dialogue not mapped"},
    {id="GiangBattlefield",npc="Giang Lao",island="Battlefield Isle",reward="Ascended Taiji Art",rewardType="Skill",type="NPC quest",objective="Quest objectives are server-defined; inspect live quest module",automation="Track only: live dialogue not mapped"},
    {id="HaDieuDe",npc="Ha Dieu De",island="Frost Isle",reward="Sever The Gate v3",rewardType="Skill",type="NPC quest",objective="Quest objectives are server-defined; inspect live quest module",automation="Track only: live dialogue not mapped"},
    {id="LaoNgo",npc="Lao Ngo",island="Battlefield Isle",reward="Heartbreaker Cleave v2",rewardType="Skill",type="NPC quest",objective="Quest objectives are server-defined; inspect live quest module",automation="Track only: live dialogue not mapped"},
    {id="BlindGrandAngler",npc="Blind Grand Angler",island="Battlefield Isle",reward="Astral Grand Art Zenith",rewardType="Skill",type="NPC quest",objective="Quest objectives are server-defined; inspect live quest module",automation="Track only: live dialogue not mapped"},
    {id="BacMinh",npc="Bac Minh",island="Coconut Isle",reward="Bac Minh Orb",rewardType="Orb",type="NPC quest",objective="Quest objectives are server-defined; inspect live quest module",automation="Track only: live dialogue not mapped"},
    {id="TicketQuest",npc="Ticket Quest Giver",island="Beginning Isle",reward="Easy / Hard Tickets",rewardType="Ticket",type="Daily",objective="Complete the selected daily ticket quest; daily limit applies",autoKey="autoTicketQuests",automation="Auto: accept / progress-check / turn-in attempt"},
    {id="ZengRepeatable",npc="Zeng Tianguo",island="Beginning Isle",reward="Variable server-defined reward",rewardType="Other",type="Repeatable",objective="Objectives and reward are server-defined; turn in only when replicated goals are complete",autoKey="autoZengQuest",automation="Auto: accept / progress-check / turn-in attempt"},
    {id="DailyClaims",npc="Daily Quest System",island="Any",reward="Server-defined daily reward",rewardType="Daily",type="Daily claim",objective="Claims only already-completed daily objectives; does not complete them",autoKey="autoDailyQuest",automation="Auto: claim completed rewards only"},
    {id="ChuXinDivine",npc="Chu Xin",island="Varies",reward="Divine Rod",rewardType="Rod",type="Main quest",objective="Public rod index lists this as a Chu Xin quest reward; live steps not verified",automation="Track only: live dialogue not mapped"},
    {id="YaxuoUnknown",npc="Yaxuo",island="Varies",reward="Unknown Rod",rewardType="Rod",type="Main quest",objective="Public rod index lists an Unknown Rod; exact reward name and live steps need in-game confirmation",automation="Track only: reward details uncertain"},
    {id="SambaQuest",npc="Samba / Samba Quest NPC",island="New update area",reward="Nautilus Dance; Samba Charge; Centerpiece Samba; Wavebreaker; Samba character unlock (requires Nautilus Dance)",rewardType="Skill",type="Weekly update",objective="Samba questline from the 2026-10-30 update; live objectives and NPC dialogue not yet verified",automation="New: track only until live quest data is mapped",source="User-provided Weekly UPD log"},
    {id="HalloweenEvent",npc="Halloween Event NPC",island="Event location",reward="Cursed Lantern Rod skin",rewardType="Seasonal",type="Seasonal event",objective="Halloween NPC event from the 2026-10-30 update; live objectives and expiry not yet verified",automation="New: track only until live quest data is mapped",source="User-provided Weekly UPD log"},
    {id="PureGoldenRodInfo",npc="Rod Seller / unknown",island="Unknown",reward="Pure Golden Rod",rewardType="Rod",type="New rod info",objective="New rod announced in the 2026-10-30 update; not confirmed as a quest reward or its acquisition route",automation="Info only: not listed as a confirmed quest",source="User-provided Weekly UPD log"},
}
local CRAFT_PLAN = {
    ["Heavenpiercer Rod"] = {
        cost=50,
        fish={
            {name="Flying Fish Emperor",island="Perch Isle",weather="Windy"},
            {name="Flying Fish Empress",island="Perch Isle",weather="Windy"},
            {name="Heavenpiercer Turtle",island="Coconut Isle",weather="Foggy"},
            {name="Rainbow Dragonfish",island=nil,weather=nil,bait="Rainbow Bait"},
        },
    },
    ["Pure Diamond Rod"] = {
        cost=50,
        fish={
            {name="Frost Kingfish",island="Frost Isle",weather="Snowy"},
            {name="Frost QueenFish",island=nil,weather=nil,bait="Frost Bait"},
            {name="Sanguine Fish",island="Amber Isle",weather="Blazing Sun"},
            {name="Draconic Koi",island="Amber Isle",weather="Blazing Sun"},
        },
    },
}
local function fold(s)
    return tostring(s or ""):lower():gsub("[^%w]", "")
end
local fishDecoder = nil
local function normalizeFish(item)
    if not item then return "" end
    local name=type(item)=="string" and item or item.Name
    name=tostring(name or "")
    if not fishDecoder then
        local cm=ReplicatedStorage:FindFirstChild("ClientModule")
        local gs=cm and cm:FindFirstChild("GameService")
        if gs and gs:IsA("ModuleScript") then
            local ok,mod=pcall(require,gs)
            if ok and type(mod)=="table" and type(mod.DestringFish)=="function" then
                fishDecoder=mod.DestringFish
            end
        end
    end
    if fishDecoder then
        local ok,decoded=pcall(fishDecoder,name)
        if ok and type(decoded)=="table" and type(decoded.FishName)=="string" then
            return fold(decoded.FishName)
        end
    end
    local before=name:match("^([^,|]+)") or name
    return fold(before)
end
local function ownedFishCount(fishName)
    local inv=getInventory()
    if not inv then return nil end
    local count=0
    for _,item in ipairs(inv:GetChildren()) do
        if normalizeFish(item)==fold(fishName) then count=count+1 end
    end
    return count
end
local function recipeForTarget()
    local n=state.craftTarget
    return CRAFT_PLAN[n],n
end
isCraftIngredient = function(item)
    if not state.protectMaterials then return false end
    local recipe=CRAFT_PLAN[state.craftTarget]
    if not recipe then return false end
    local name=normalizeFish(item)
    for _,entry in ipairs(recipe.fish) do
        if name==fold(entry.name) then return true end
    end
    return false
end
local function currentWeather()
    return tostring(workspace:GetAttribute("Weather") or "Unknown")
end
local function matchingWeather(got,needed)
    local a,b=fold(got),fold(needed)
    if b=="windy" then return a:find("wind",1,true)~=nil end
    if b=="snowy" then return a:find("snow",1,true)~=nil end
    if b=="foggy" then return a:find("fog",1,true)~=nil or a:find("mist",1,true)~=nil end
    if b=="blazingsun" then return a:find("blazing",1,true)~=nil end
    return a==b
end
local function knownFishForWeather()
    local recipe=CRAFT_PLAN[state.craftTarget]
    if not recipe then return nil,nil,nil end
    local weather=currentWeather()
    local nextUnowned=nil
    local baitMissing=nil
    for _,entry in ipairs(recipe.fish) do
        local owned=ownedFishCount(entry.name)
        if owned==nil then return nil,nil,"Fish inventory not replicated" end
        if owned<1 then
            nextUnowned=nextUnowned or entry
            if entry.bait then baitMissing=baitMissing or entry end
            if entry.island and matchingWeather(weather,entry.weather) then
                return entry.island,entry,"Weather match "..weather
            end
        end
    end
    if not nextUnowned then return nil,nil,"All four recipe fish present" end
    if baitMissing then return nil,baitMissing,"Needs "..baitMissing.bait.." (summoned fish)" end
    return nil,nextUnowned,("Waiting for "..nextUnowned.weather.." on "..nextUnowned.island)
end
local function ownedBaitCount(name)
    local pd=playerData()
    if not pd then return nil end
    for _,folderName in ipairs({"Bait","BaitInventory","Inventory"}) do
        local folder=pd:FindFirstChild(folderName)
        if folder then
            for _,obj in ipairs(folder:GetChildren()) do
                if fold(obj.Name)==fold(name) or fold(obj.Name:match("^([^,|]+)") or obj.Name)==fold(name) then
                    if obj:IsA("ValueBase") then return tonumber(obj.Value) or 0 end
                    return tonumber(obj:GetAttribute("Quantity") or obj:GetAttribute("Count") or 1) or 1
                end
            end
        end
    end
    return 0
end
local function equipSpecialBait(name)
    if os.clock()-craftTracker.lastEquipBaitAt<15 then return false end
    local available=ownedBaitCount(name)
    if not available or available<1 then return false end
    local remote=Events:FindFirstChild("EquipBait")
    if not remote then return false end
    craftTracker.lastEquipBaitAt=os.clock()
    local ok=false
    if remote:IsA("RemoteFunction") then ok=pcall(function() remote:InvokeServer(name) end)
    elseif remote:IsA("RemoteEvent") then ok=pcall(function() remote:FireServer(name) end) end
    if ok then craftTracker.status="Requested bait equip: "..name.." (check hotbar slot 2)" end
    return ok
end
local function parseRequirements(data)
    if type(data)~="table" then return nil end
    local ing=data.Ingredient
    if type(ing)~="table" then return nil end
    local requirements={}
    local found=0
    for key,val in pairs(ing) do
        local name,qty=nil,nil
        if type(key)=="string" and tonumber(val) then
            name,qty=key,tonumber(val)
        elseif type(val)=="table" then
            name=val.Name or val.Item or val.Fish or val[1]
            qty=tonumber(val.Count or val.Amount or val.Quantity or val[2])
        end
        if type(name)~="string" or not qty or qty<=0 or qty>10000 then return nil end
        requirements[name]=(requirements[name] or 0)+qty
        found=found+1
    end
    return found>0 and requirements or nil
end
local function liveCraftModule(target)
    local info=ReplicatedStorage:FindFirstChild("Info")
    local inv=info and info:FindFirstChild("Inventory")
    if not inv then return nil end
    for _,m in ipairs(inv:GetChildren()) do
        if m:IsA("ModuleScript") and fold(m.Name)==fold(target) then
            local data=itemModule(m.Name)
            if data and data.Ingredient and (not data.Type or fold(data.Type):find("rod",1,true)) then return m.Name,data end
        end
    end
    return nil
end
local function maybeCraftBait(name)
    if not state.autoCraftBait or os.clock()-craftTracker.lastBaitAt<90 then return false end
    if (ownedBaitCount(name) or 0)>0 then return false end
    local inf=ReplicatedStorage:FindFirstChild("Info")
    local fld=inf and inf:FindFirstChild("Bait")
    local mod=fld and fld:FindFirstChild(name)
    if not mod or not mod:IsA("ModuleScript") then
        craftTracker.status="Bait recipe missing: "..name
        return false
    end
    local ok,data=pcall(require,mod)
    local req=ok and parseRequirements(data) or nil
    if not req then
        craftTracker.status="Bait recipe format unverified: craft "..name.." manually"
        return false
    end
    for material,qty in pairs(req) do
        local count=ownedFishCount(material) or ownedBaitCount(material)
        if not count or count<qty then
            craftTracker.status="Bait material missing: "..material.." x"..qty
            return false
        end
    end
    craftTracker.lastBaitAt=os.clock()
    if fire("CraftBait",name,1) then
        craftTracker.status="Craft bait requested: "..name.." (verify inventory)"
        return true
    end
    craftTracker.status="CraftBait remote not available"
    return false
end
local function beginCraftAttempt()
    if not state.autoCraftRod or craftTracker.pendingAt>0 or os.clock()-craftTracker.lastAt<135 then return end
    if sellTracker.pending or isShopping() or buyerTripActive() then return end
    local recipe,target=recipeForTarget()
    if not recipe then return end
    if ownedRod(target) then
        craftTracker.status="OWNED: "..target
        return
    end
    local actualName,data=liveCraftModule(target)
    if not actualName then
        craftTracker.status="Game has not replicated craftable "..target.."; no spend"
        return
    end
    -- We require the game to expose the recipe and match its fish list.
    local req=parseRequirements(data)
    if not req then
        craftTracker.status="Live recipe structure unknown; spend blocked"
        return
    end
    local expected={}
    for _,fish in ipairs(recipe.fish) do expected[fold(fish.name)]=true end
    local confirmed=0
    for material,qty in pairs(req) do
        if expected[fold(material)] then
            confirmed=confirmed+1
            if (ownedFishCount(material) or 0)<qty then
                craftTracker.status="Missing "..material.." x"..qty
                return
            end
        end
    end
    if confirmed<4 then
        craftTracker.status="Live recipe does not confirm all 4 fish; no spend"
        return
    end
    local dataRoot=playerData()
    local gems=candidateValue(dataRoot,{"Crystals","Crystal","Gems","Gem"})
    if not gems then
        craftTracker.status="Gem balance not replicated; craft blocked"
        return
    end
    local price=tonumber(data.Crystals or data.CrystalPrice or data.Gems or data.GemPrice or data.CraftPrice) or recipe.cost
    if gems<price then
        craftTracker.status="Saving Gems for craft: "..gems.." / "..price
        return
    end
    local snapshot={}
    for _,fish in ipairs(recipe.fish) do snapshot[fish.name]=ownedFishCount(fish.name) end
    craftTracker.lastAt=os.clock()
    if fire("CraftRod",actualName) then
        craftTracker.pendingAt=os.clock()
        craftTracker.lastBefore={gem=gems,fish=snapshot,rod=actualName}
        craftTracker.attempts=craftTracker.attempts+1
        craftTracker.status="Craft request sent; checking rod and materials (chance of failure)"
        report("Craft "..actualName.." request #"..craftTracker.attempts.." sent; no success assumed")
    else
        craftTracker.status="CraftRod remote missing or errored"
    end
end
local function craftTick()
    if not (state.autoCraftRod or state.autoFarmMaterials) then
        craftTracker.route=nil
        craftTracker.status="OFF"
        return
    end
    if state.autoFarmMaterials and not state.protectMaterials then
        craftTracker.route=nil
        craftTracker.status="STOPPED: turn ON Protect Craft Materials before farming"
        return
    end
    local recipe,target=recipeForTarget()
    if not recipe then craftTracker.status="No recognized recipe";return end
    if state.protectMaterials and state.autoFavorite then
        local inv=getInventory()
        if inv then
            for _,fish in ipairs(inv:GetChildren()) do
                if isCraftIngredient(fish) and not isFavorite(fish) then
                    tryFavorite(fish)
                    break
                end
            end
        end
    end
    if craftTracker.pendingAt>0 then
        if ownedRod(target) then
            craftTracker.pendingAt=0
            craftTracker.lastSuccessful=target
            craftTracker.status="CRAFT SUCCESS verified: "..target
            notify("Crafted "..target.."! Server inventory confirms ownership.")
            return
        end
        if os.clock()-craftTracker.pendingAt<12 then return end
        local changed=false
        if craftTracker.lastBefore then
            local old=craftTracker.lastBefore
            local newGems=candidateValue(playerData(),{"Crystals","Crystal","Gems","Gem"})
            if newGems and old.gem and newGems<old.gem then changed=true end
            for fish,qty in pairs(old.fish) do
                local current=ownedFishCount(fish)
                if current and qty and current<qty then changed=true end
            end
        end
        craftTracker.status=changed and "Craft consumed resources but no rod: likely failed (check UI)"
            or "Craft not confirmed; retry blocked until resources and cooldown"
        craftTracker.pendingAt=0
    end
    if ownedRod(target) then
        craftTracker.route=nil
        craftTracker.status="CRAFTED/OWNED: "..target
        return
    end
    craftTracker.route=nil
    local island,missing,note=knownFishForWeather()
    if state.autoFarmMaterials then
        craftTracker.route=island
        craftTracker.fish=missing and missing.name or nil
        craftTracker.status=note or "Scanning ingredients"
        if island then
            local p=profile()
            local _,ownedPower=bestOwnedRod(p)
            local power=math.max(rodPower(p.rod) or 0,ownedPower or 0)
            local gate=0
            for _,entry in ipairs(LEVEL_ROUTE) do
                if entry.name==island then gate=entry.power;break end
            end
            if power<gate then
                craftTracker.route=nil
                craftTracker.status=("Need %d Power for %s (current %d). Keep leveling."):format(gate,island,power)
            end
        end
        if missing and missing.bait then
            maybeCraftBait(missing.bait)
            if (ownedBaitCount(missing.bait) or 0)>0 then equipSpecialBait(missing.bait) end
        end
    end
    if note=="All four recipe fish present" then
        if state.autoCraftRod then beginCraftAttempt() else craftTracker.status="Ready to craft "..target.." (Auto Craft OFF)" end
    end
end
local function findQuestNPC(query,location)
    local folder=workspace:FindFirstChild("NPC") or workspace:FindFirstChild("NPCs")
    if not folder then return nil,nil end
    local aliases= (query=="sage") and {"sageyijiu","sageyiju","sageeugene"}
        or (query=="ticket") and {"ticketquestgiver"}
        or (query=="zeng") and {"zengtianguo"}
        or {fold(query)}
    local best,bestDist=nil,math.huge
    local reference=location and cframeIsland(location)
    for _,model in ipairs(folder:GetDescendants()) do
        if model:IsA("Model") or model:IsA("BasePart") then
            local name=fold(model.Name)..fold(model:GetAttribute("Name") or "")
            local matches=false
            for _,alias in ipairs(aliases) do
                if name:find(alias,1,true) then matches=true;break end
            end
            if matches then
                local part=getPart(model)
                if part then
                    local distance=reference and (part.Position-reference.Position).Magnitude or 0
                    if distance<bestDist and (not reference or distance<550) then
                        best,bestDist=part,distance
                    end
                end
            end
        end
    end
    return best,bestDist
end
local function findMainQuest(name)
    local p=playerData()
    local q=p and p:FindFirstChild("Quest")
    local main=q and q:FindFirstChild("Main")
    if not main then return nil end
    local n=fold(name)
    for _,obj in ipairs(main:GetChildren()) do
        if fold(obj.Name):find(n,1,true) then return obj end
    end
    return nil
end
local function replicatedObjectivesComplete(q)
    if not q then return false,"Quest not active" end
    local info=ReplicatedStorage:FindFirstChild("Info")
    local defs=info and info:FindFirstChild("MainQuest")
    local module=defs and defs:FindFirstChild(q.Name)
    if not module or not module:IsA("ModuleScript") then return false,"Objective module unavailable" end
    local ok,rows=pcall(require,module)
    if not ok or type(rows)~="table" then return false,"Cannot read objective module" end
    local found=0
    for _,obj in ipairs(q:GetChildren()) do
        if obj:IsA("NumberValue") and tonumber(obj.Name) then
            local definition=rows[tonumber(obj.Name)]
            local goal=type(definition)=="table" and tonumber(definition[2]) or nil
            if not goal then return false,"Unrecognized objective "..obj.Name end
            found=found+1
            if obj.Value<goal then
                return false,obj.Name.." "..math.floor(obj.Value).."/"..math.floor(goal)
            end
        end
    end
    return found>0, found>0 and "All server goals met" or "No numeric goals replicated"
end
local function startNPCDialogue(part)
    if not part then return false end
    local p=part.Parent
    local prompt=p and p:FindFirstChildWhichIsA("ProximityPrompt",true)
    if not prompt then prompt=part:FindFirstChildWhichIsA("ProximityPrompt",true) end
    if prompt and prompt.Enabled and type(fireproximityprompt)=="function" then
        return pcall(function() fireproximityprompt(prompt) end)
    end
    local detector=p and p:FindFirstChildWhichIsA("ClickDetector",true)
    if detector and type(fireclickdetector)=="function" then
        return pcall(function() fireclickdetector(detector) end)
    end
    return false
end
local function clickQuestDialogue(wanted)
    local mg=PlayerGui:FindFirstChild("MainGui")
    local menu=mg and mg:FindFirstChild("Menu")
    local dialogue=menu and menu:FindFirstChild("Dialogue")
    if not dialogue or not dialogue:IsA("GuiObject") or not dialogue.Visible then return false end
    local text=""
    for _,obj in ipairs(dialogue:GetDescendants()) do
        if obj:IsA("TextLabel") and guiVisible(obj) then text=text.." "..obj.Text end
    end
    local lower=text:lower()
    if not (lower:find("sage",1,true) or lower:find("diamond",1,true)
        or (wanted=="ticket" and lower:find("ticket",1,true))) then return false end
    if wanted=="sage" and not (lower:find("sage",1,true) or lower:find("diamond",1,true)) then return false end
    local candidate=nil
    for _,obj in ipairs(dialogue:GetDescendants()) do
        if obj:IsA("GuiButton") and guiVisible(obj) then
            local label=buttonActionText(obj)
            if label:find("accept",1,true) or label:find("claim",1,true)
                or label:find("complete",1,true) or label:find("quest",1,true) then
                candidate=obj; break
            end
        end
    end
    if not candidate then return false end
    return clickGameButton(candidate)
end
local function diamondOwned()
    return ownedRod("Diamond Rod") or profile().rod=="Diamond Rod"
end
local function sageActiveQuest()
    for _,tag in ipairs({"Sage Yijiu","Sage Yiju","Sage Eugene","Diamond Rod"}) do
        local quest=findMainQuest(tag)
        if quest then return quest end
    end
    return nil
end
local function finishSageRoute()
    questTracker.sage="DONE - Diamond Rod owned"
    questTracker.sageRoute=nil
    questTracker.status="Diamond Rod: verified owned"
end
local function sageQuestTick()
    if not state.autoQuests or not state.autoSageAfterAmber then
        questTracker.sageRoute=nil
        return
    end
    if os.clock() < (hub.manualTravelUntil or 0) then return end
    if diamondOwned() then finishSageRoute(); return end
    local p=profile()
    local owned,bestPower=bestOwnedRod(p)
    local ready=math.max(bestPower or 0,rodPower(p.rod) or 0)>=83
    if not ready then
        questTracker.sage="Waiting for Starlight Rod / Amber tier"
        questTracker.sageRoute=nil
        return
    end
    local q=sageActiveQuest()
    local complete,summary=replicatedObjectivesComplete(q)
    if q and not complete then
        questTracker.sage="ACTIVE: "..summary
        questTracker.sageRoute="Amber Isle"
        questTracker.status="Sage Diamond quest: fishing heavy Amber catches; game records weights"
        return
    end
    questTracker.sageRoute="Battlefield Isle"
    -- Avoid interrupting the independent crafting-material mode. Its route
    -- takes priority only while a matching weather fish can be farmed.
    if state.autoFarmMaterials and craftTracker.route then
        questTracker.status="Sage conversation paused for weather fish farming"
        return
    end
    local phase=q and "TURN IN" or "ACCEPT"
    questTracker.sage=phase.." Diamond Rod quest at Sage"
    questTracker.status=phase.." Sage quest (requires actual dialogue/quest confirmation)"
    if os.clock()-questTracker.lastInteract<16 then return end
    if isShopping() or buyerTripActive() or sellTracker.pending then return end
    local _,root,hum=getChar()
    local _,active=minigame()
    if not root or not hum or hum.Health<=0 or active then return end
    local sage=findQuestNPC("sage","Battlefield Isle")
    questTracker.lastInteract=os.clock()
    if sage then
        if (sage.Position-root.Position).Magnitude>11 then
            teleportTo(sage.CFrame*CFrame.new(0,0,-5),"Battlefield Sage")
        else
            local triggered=startNPCDialogue(sage)
            if triggered then questTracker.status=phase..": Sage dialogue prompted; waiting for quest data" end
        end
    else
        local cf=cframeIsland("Battlefield Isle")
        if cf and (root.Position-cf.Position).Magnitude>130 then
            teleportTo(cf,"Battlefield (load Sage)")
        else
            questTracker.status="Sage NPC not loaded; speak to him once if necessary"
        end
    end
    if os.clock()-questTracker.lastUI>7 then
        if clickQuestDialogue("sage") then
            questTracker.lastUI=os.clock()
            questTracker.status="Sage quest GUI clicked; verifying server quest folder"
        end
    end
end
-- Match the exact server-recognized NPC instance when available.
-- StarCrow passes workspace.NPC.Function["Ticket Quest Giver"] to the remote.
local function dialogueGiver(name)
    local npc=workspace:FindFirstChild("NPC")
    local fun=npc and npc:FindFirstChild("Function")
    local exact=fun and fun:FindFirstChild(name)
    if exact then return exact,getPart(exact) end
    local pt=findQuestNPC(name=="Ticket Quest Giver" and "ticket" or "zeng")
    return pt,pt
end
local function currentTicketQuest()
    local p=playerData()
    local quests=p and p:FindFirstChild("Quest")
    local main=quests and quests:FindFirstChild("Main")
    if not main then return nil end
    for _,name in ipairs({"Hard Ticket Quest","Easy Ticket Quest","Ticket Quest"}) do
        local match=main:FindFirstChild(name)
        if match then return match end
    end
    return nil
end
local function ticketQuestTick()
    if not (state.autoQuests and state.autoTicketQuests) then return end
    if questTracker.sageRoute then return end
    if os.clock()-questTracker.lastTicket<20 then return end
    local dialog=PlayerGui:FindFirstChild("MainGui")
    local menu=dialog and dialog:FindFirstChild("Menu")
    local box=menu and menu:FindFirstChild("Dialogue")
    if box and box.Visible then
        for _,obj in ipairs(box:GetDescendants()) do
            if obj:IsA("TextLabel") and obj.Text:lower():find("daily limit",1,true) then
                questTracker.ticketStatus="Daily ticket limit reached (paused)"
                state.autoTicketQuests=false
                if callbacks.autoTicketQuests then callbacks.autoTicketQuests() end
                if hub.refreshQuestPicker then hub.refreshQuestPicker() end
                return
            end
        end
    end
    local giver,giverPart=dialogueGiver("Ticket Quest Giver")
    local ev=event("ChooseDialogueOption")
    if not giver or not giverPart or not ev then
        questTracker.ticketStatus="Ticket NPC or dialogue remote not loaded"
        return
    end
    local q=currentTicketQuest()
    if q then
        local done,summary=replicatedObjectivesComplete(q)
        if not done then questTracker.ticketStatus="Active "..q.Name..": "..summary;return end
    end
    local _,root=getChar()
    local _,active=minigame()
    if not root or active or isShopping() or buyerTripActive() then return end
    questTracker.lastTicket=os.clock()
    if (root.Position-giverPart.Position).Magnitude>13 then
        hub.manualTravelUntil=os.clock()+25
        teleportTo(giverPart.CFrame*CFrame.new(0,0,-5),"Ticket Quest Giver")
        questTracker.ticketStatus="Traveling to ticket quest NPC"
        return
    end
    -- The two argument formats below are directly documented in the public
    -- readable StarCrow source. Never loop them more often than cooldown.
    local success=false
    if q then
        success=fire("ChooseDialogueOption","Ticket Quest Giver",1,"Quest",{giver})
        questTracker.ticketStatus=success and "Ticket turn-in requested; check reward" or "Ticket turn-in failed"
    else
        local mode=state.ticketQuestMode=="Easy" and "Easy" or "Hard"
        local index=mode=="Easy" and 1 or 2
        success=fire("ChooseDialogueOption","Ticket Quest Giver",index,mode.."AcceptQuest",{giver,"Ticket Quest"})
        questTracker.ticketStatus=success and (mode.." ticket accept requested; verify quest") or "Ticket accept failed"
    end
end

-- Zeng repeatable: both ChooseDialogueOption variants were verified against
-- the public readable StarCrow source. Turn in ONLY if progress says complete.
local function zengQuestTick()
    if not (state.autoQuests and state.autoZengQuest) then return end
    if questTracker.sageRoute then return end
    if os.clock()-questTracker.lastZeng<27 then return end
    local npc,part=dialogueGiver("Zeng Tianguo")
    if not npc or not part or not event("ChooseDialogueOption") then
        questTracker.zengStatus="NPC or dialogue event not loaded"
        return
    end
    local active=findMainQuest("Zeng Tianguo")
    if active then
        local done,summary=replicatedObjectivesComplete(active)
        if not done then
            questTracker.zengStatus="Active: "..summary
            return
        end
    end
    local _,root=getChar()
    local _,fishing=minigame()
    if not root or fishing or isShopping() or buyerTripActive() then return end
    questTracker.lastZeng=os.clock()
    if (root.Position-part.Position).Magnitude>13 then
        hub.manualTravelUntil=os.clock()+27
        teleportTo(part.CFrame*CFrame.new(0,0,-5),"Zeng Tianguo quest giver")
        questTracker.zengStatus="Travel to repeatable quest giver"
        return
    end
    if active then
        local sent=fire("ChooseDialogueOption","Zeng Tianguo",1,"Quest",{npc})
        questTracker.zengStatus=sent and "Zeng turn-in requested; verify reward" or "Turn-in request failed"
    else
        local sent=fire("ChooseDialogueOption","Zeng Tianguo",1,"AcceptQuest",{npc,"Zeng Tianguo Quest"})
        questTracker.zengStatus=sent and "Zeng accepted? Checking replicated quest" or "Accept failed"
    end
end

local function sideQuestStatus()
    local p=playerData()
    local q=p and p:FindFirstChild("Quest")
    local main=q and q:FindFirstChild("Main")
    if not main then return "Main quests not replicated" end
    local total,done=0,0
    local activeNames={}
    for _,obj in ipairs(main:GetChildren()) do
        total=total+1
        local complete=replicatedObjectivesComplete(obj)
        if complete then done=done+1 end
        if #activeNames<4 then table.insert(activeNames,obj.Name) end
    end
    return ("Active main quests %d (verified finished %d): %s"):format(total,done,table.concat(activeNames,", "))
end
local function discoverLiveQuestModules()
    local info=ReplicatedStorage:FindFirstChild("Info")
    local defs=info and info:FindFirstChild("MainQuest")
    if not defs then return nil,"ReplicatedStorage.Info.MainQuest is not replicated" end
    local found={}
    local function rewardHint(value,depth)
        if depth>3 or type(value)~="table" then return nil end
        for key,item in pairs(value) do
            local keyText=fold(key)
            if keyText:find("reward",1,true) or keyText=="prize" or keyText=="item" then
                if type(item)=="string" and item~="" then return item end
                if type(item)=="table" then
                    for _,nested in pairs(item) do
                        if type(nested)=="string" and nested~="" then return nested end
                    end
                end
            end
            if type(item)=="table" then
                local nested=rewardHint(item,depth+1)
                if nested then return nested end
            end
        end
        return nil
    end
    for _,module in ipairs(defs:GetChildren()) do
        if module:IsA("ModuleScript") then
            local ok,rows=pcall(require,module)
            local objectiveCount=(ok and type(rows)=="table") and #rows or 0
            local reward=module:GetAttribute("Reward")
            if type(reward)~="string" or reward=="" then
                reward=(ok and type(rows)=="table") and rewardHint(rows,0) or nil
            end
            table.insert(found,{
                name=module.Name,
                objectiveCount=objectiveCount,
                reward=(type(reward)=="string" and reward~="") and reward or "Not exposed by live objective module",
                readable=ok and type(rows)=="table",
            })
        end
    end
    table.sort(found,function(a,b) return a.name:lower()<b.name:lower() end)
    return found
end
local function questTick()
    if not state.autoQuests then
        questTracker.status="OFF"
        questTracker.sageRoute=nil
        return
    end
    if state.autoDailyQuest then claimCompletedDailies() end
    sageQuestTick()
    -- Independent Auto Quest mode can start fishing when Sage goals need catches.
    if state.autoSageAfterAmber and questTracker.sageRoute=="Amber Isle" then
        for _,flag in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam",
                              "charge","rhythm","phase2"}) do
            if not state[flag] then setState(flag,true) end
        end
    end
    ticketQuestTick()
    zengQuestTick()
    questTracker.side=sideQuestStatus()
end
local function activeFarmOverride()
    if os.clock()<(hub.manualTravelUntil or 0) then return nil end
    if state.autoFarmMaterials and craftTracker.route then
        return craftTracker.route,"craft"
    end
    if state.autoQuests and state.autoSageAfterAmber and questTracker.sageRoute then
        return questTracker.sageRoute,"sage"
    end
    return nil
end
local lastAuxRoute=-math.huge
local function auxiliaryFarmTick()
    if state.autoLevel or not state.autoRoute then return end
    local island,reason=activeFarmOverride()
    if not island or (os.clock()<(hub.manualTravelUntil or 0)) then return end
    local now=os.clock()
    if now-lastAuxRoute<12 or isShopping() or buyerTripActive() or sellTracker.pending then return end
    local _,root,hum=getChar()
    local _,fishing=minigame()
    local cf=cframeIsland(island)
    if not root or not hum or hum.Health<=0 or fishing or not cf then return end
    if (root.Position-cf.Position).Magnitude>230 then
        lastAuxRoute=now
        teleportTo(cf,reason.." fishing at "..island)
        facingTracker.lastAt=0
    end
end
local function scanMerchants()
    local npc=workspace:FindFirstChild("NPC") or workspace:FindFirstChild("NPCs")
    merchantTracker.Maoshan=nil
    merchantTracker.Taoist=nil
    if not npc then return end
    for _,obj in ipairs(npc:GetDescendants()) do
        if obj:IsA("Model") or obj:IsA("BasePart") then
            local name=fold(obj.Name)..fold(obj:GetAttribute("Name") or "")
            local kind=nil
            if name:find("maoshan",1,true) or name:find("maosan",1,true) then kind="Maoshan"
            elseif name:find("taoist",1,true) or name:find("taosi",1,true) then kind="Taoist" end
            if kind then
                local part=getPart(obj)
                if part and part:IsDescendantOf(workspace) then
                    if not merchantTracker[kind] then merchantTracker[kind]=part end
                end
            end
        end
    end
    for _,kind in ipairs({"Maoshan","Taoist"}) do
        local part=merchantTracker[kind]
        if state.merchantAlerts and part and not merchantTracker.lastSeen[kind] then
            merchantTracker.alerts=merchantTracker.alerts+1
            notify(kind.." merchant detected! TAP the popup to teleport; loaded server NPC only.")
        end
        merchantTracker.lastSeen[kind]=part~=nil
    end
end
local function tpMerchant(kind)
    local part=merchantTracker[kind]
    if not part or not part.Parent or not part:IsDescendantOf(workspace) then
        scanMerchants()
        part=merchantTracker[kind]
    end
    if not part then
        notify(kind.." not loaded on this server (can't teleport)")
        return false
    end
    hub.manualTravelUntil=os.clock()+95
    return teleportTo(part.CFrame*CFrame.new(0,0,-7),kind.." merchant")
end

return {questTracker=questTracker, craftTracker=craftTracker, merchantTracker=merchantTracker, QUESTRUN_CATALOG=QUESTRUN_CATALOG, CRAFT_PLAN=CRAFT_PLAN, ownedFishCount=ownedFishCount, recipeForTarget=recipeForTarget, liveCraftModule=liveCraftModule, beginCraftAttempt=beginCraftAttempt, craftTick=craftTick, questTick=questTick, findQuestNPC=findQuestNPC, sideQuestStatus=sideQuestStatus, discoverLiveQuestModules=discoverLiveQuestModules, scanMerchants=scanMerchants, tpMerchant=tpMerchant, diamondOwned=diamondOwned, activeFarmOverride=activeFarmOverride, auxiliaryFarmTick=auxiliaryFarmTick}
end)()

function hub.armAutoRoute()
    hub.routeGate.ready=false
    hub.routeGate.island=nil
    hub.routeGate.status="Locating fishing island"
    hub.routeGate.lastAttempt=-math.huge
    hub.routeGate.lastTeleport=0
    lastAutoLevelTick=-math.huge -- first route evaluation must run before the first cast
    lastAutoRoute=0
end
function hub.dockDistance(root, cf)
    local p=root.Position
    local t=cf.Position
    local x,z=p.X-t.X,p.Z-t.Z
    return math.sqrt(x*x+z*z),math.abs(p.Y-t.Y)
end
function hub.routeReadyForCast(island)
    if not state.autoLevel or not state.autoRoute then return true end
    if not hub.routeGate.ready or hub.routeGate.island~=island then return false end
    local _,root,hum=getChar()
    local cf=cframeIsland(island)
    if not root or not hum or hum.Health<=0 or not cf then return false end
    local horizontal,vertical=hub.dockDistance(root,cf)
    if horizontal>80 or vertical>65 then
        hub.routeGate.ready=false
        hub.routeGate.status="Moved away from "..island
        return false
    end
    return true
end
function hub.routeTravelTick(now,island)
    if not state.autoRoute then
        hub.routeGate.ready=true
        hub.routeGate.status="Auto route disabled"
        return
    end
    if hub.routeGate.island~=island then
        hub.routeGate.island=island
        hub.routeGate.ready=false
        hub.routeGate.lastAttempt=-math.huge
        hub.routeGate.status="Routing to "..island
    end
    local char,root,hum=getChar()
    local cf=cframeIsland(island)
    if not cf then
        hub.routeGate.ready=false
        hub.routeGate.status="No known safe dock for "..island
        return
    end
    if not root or not hum or hum.Health<=0 then
        hub.routeGate.ready=false
        hub.routeGate.status="Waiting for character"
        return
    end
    if now<(hub.manualTravelUntil or 0) then
        hub.routeGate.ready=false
        hub.routeGate.status="Manual teleport active"
        return
    end
    if isShopping() or buyerTripActive() or sellTracker.pending then
        hub.routeGate.ready=false
        hub.routeGate.status=isShopping() and "Waiting for rod shop" or "Waiting for fish sale"
        return
    end
    local horizontal,vertical=hub.dockDistance(root,cf)
    if horizontal>80 or vertical>65 then
        hub.routeGate.ready=false
        local _,active=minigame()
        if active or char:GetAttribute("Fishing") then
            hub.routeGate.status="Finishing catch before travel to "..island
            return
        end
        if now-hub.routeGate.lastAttempt>=2.5 then
            hub.routeGate.lastAttempt=now
            hub.routeGate.attempts=hub.routeGate.attempts+1
            local success=teleportTo(cf,island.." dock")
            if success then
                hub.routeGate.lastTeleport=now
                hub.routeGate.status="Teleported to "..island.."; verifying"
            else
                hub.routeGate.status="Teleport failed; retrying"
            end
        else
            hub.routeGate.status="Waiting for teleport to "..island
        end
        return
    end
    if now-hub.routeGate.lastTeleport<0.25 then
        hub.routeGate.ready=false
        hub.routeGate.status="Landing at "..island
        return
    end
    if state.autoSeaFacing and not faceSea(island,true) then
        hub.routeGate.ready=false
        hub.routeGate.status="Waiting for safe sea-facing angle"
        return
    end
    hub.routeGate.ready=true
    hub.routeGate.confirms=hub.routeGate.confirms+1
    hub.routeGate.status="Ready at "..island
end

local function buildInterface()
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
GUI.DisplayOrder = 1000
GUI.IgnoreGuiInset = true
local parented = pcall(function() GUI.Parent = container end)
if not parented then GUI.Parent = PlayerGui end
hub.gui = GUI

local colors = {
    bg = Color3.fromRGB(16, 28, 42),          -- #101C2A
    panel = Color3.fromRGB(22, 36, 54),       -- #162436
    row = Color3.fromRGB(32, 51, 74),         -- #20334A
    rowHover = Color3.fromRGB(42, 65, 88),
    outline = Color3.fromRGB(57, 79, 101),
    accent = Color3.fromRGB(66, 214, 195),    -- #42D6C3
    accentSoft = Color3.fromRGB(29, 78, 80),
    gold = Color3.fromRGB(231, 181, 103),     -- #E7B567
    white = Color3.fromRGB(242, 245, 248),    -- #F2F5F8
    muted = Color3.fromRGB(178, 193, 208),
    red = Color3.fromRGB(228, 125, 131),      -- #E47D83
    green = Color3.fromRGB(109, 205, 155),
}
local function make(class, parent, props)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function round(o, px)
    make("UICorner", o, { CornerRadius = UDim.new(0, px or 9) })
end
local function edge(o, color, transparency)
    make("UIStroke", o, {
        Color = color or colors.outline,
        Thickness = 1,
        Transparency = transparency == nil and 0.38 or transparency,
    })
end

local compact = UIS.TouchEnabled and not UIS.KeyboardEnabled
local camera = workspace.CurrentCamera
local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
local width, height
if compact then
    width = math.max(300, math.min(620, viewport.X - 24))
    height = math.max(420, math.min(720, viewport.Y - 48))
else
    width = math.max(520, math.min(680, viewport.X - 80))
    height = math.max(500, math.min(680, viewport.Y - 80))
end
local headerHeight = 62
local footerHeight = 38
local sidebarWidth = compact and 112 or 136

local main = make("Frame", GUI, {
    Name = "Window",
    BackgroundColor3 = colors.bg,
    BorderSizePixel = 0,
    Size = UDim2.fromOffset(width, height),
    Position = UDim2.new(0.5, -width / 2, 0.5, -height / 2),
    ClipsDescendants = true,
    Active = true,
    Visible = false,
})
round(main, 14)
edge(main, colors.outline, 0.18)

local header = make("Frame", main, {
    Name = "Header",
    BackgroundColor3 = colors.panel,
    Size = UDim2.new(1, 0, 0, headerHeight),
    BorderSizePixel = 0,
    Active = true,
})
local brandMark = make("Frame", header, {
    BackgroundColor3 = colors.accentSoft,
    BorderSizePixel = 0,
    Size = UDim2.fromOffset(38, 38),
    Position = UDim2.fromOffset(14, 12),
})
round(brandMark, 11)
local brandLetter = make("TextLabel", brandMark, {
    BackgroundTransparency = 1,
    Text = "K",
    Font = Enum.Font.GothamBold,
    TextSize = 21,
    TextColor3 = colors.accent,
    Size = UDim2.fromScale(1, 1),
})
local title = make("TextLabel", header, {
    BackgroundTransparency = 1,
    Text = "KITKIT / HEAVYWEIGHT",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamBold,
    TextSize = compact and 15 or 17,
    TextColor3 = colors.white,
    Position = UDim2.fromOffset(62, 9),
    Size = UDim2.new(1, -150, 0, 24),
})
local headerSubtitle = make("TextLabel", header, {
    BackgroundTransparency = 1,
    Text = "FISHING AUTOMATION  /  2.7",
    TextXAlignment = Enum.TextXAlignment.Left,
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = colors.muted,
    Position = UDim2.fromOffset(63, 34),
    Size = UDim2.new(1, -150, 0, 16),
})
local closeButton = make("TextButton", header, {
    Text = "X",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = colors.white,
    BackgroundColor3 = colors.row,
    Size = UDim2.fromOffset(34, 34),
    Position = UDim2.new(1, -48, 0, 14),
    BorderSizePixel = 0,
    AutoButtonColor = false,
})
round(closeButton, 9)
track(closeButton.MouseEnter:Connect(function() closeButton.BackgroundColor3 = colors.red end))
track(closeButton.MouseLeave:Connect(function() closeButton.BackgroundColor3 = colors.row end))

local sidebar = make("Frame", main, {
    Name = "Sidebar",
    BackgroundColor3 = colors.panel,
    BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, headerHeight),
    Size = UDim2.new(0, sidebarWidth, 1, -headerHeight - footerHeight),
})
make("TextLabel", sidebar, {
    BackgroundTransparency = 1,
    Text = "WORKSPACE",
    TextColor3 = colors.muted,
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(14, 12),
    Size = UDim2.new(1, -24, 0, 18),
})
local navList = make("Frame", sidebar, {
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(7, 38),
    Size = UDim2.new(1, -14, 1, -46),
})
make("UIListLayout", navList, {
    FillDirection = Enum.FillDirection.Vertical,
    HorizontalAlignment = Enum.HorizontalAlignment.Center,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Padding = UDim.new(0, 6),
})

make("Frame", main, {
    Name = "SidebarDivider",
    BackgroundColor3 = colors.outline,
    BackgroundTransparency = 0.48,
    BorderSizePixel = 0,
    Position = UDim2.new(0, sidebarWidth, 0, headerHeight),
    Size = UDim2.new(0, 1, 1, -headerHeight - footerHeight),
})
local content = make("Frame", main, {
    Name = "Content",
    BackgroundTransparency = 1,
    Position = UDim2.fromOffset(sidebarWidth + 12, headerHeight + 10),
    Size = UDim2.new(1, -sidebarWidth - 22, 1, -headerHeight - footerHeight - 18),
})
local footer = make("Frame", main, {
    BackgroundColor3 = colors.panel,
    Position = UDim2.new(0, 0, 1, -footerHeight),
    Size = UDim2.new(1, 0, 0, footerHeight),
    BorderSizePixel = 0,
})
local statusTop = make("TextLabel", footer, {
    BackgroundTransparency = 1,
    Font = Enum.Font.GothamMedium,
    Text = "Level --  /  Bag --  /  Weather --",
    TextColor3 = colors.accent,
    TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(14, 3),
    Size = UDim2.new(1, -28, 0, 15),
    TextTruncate = Enum.TextTruncate.AtEnd,
})
local statusBottom = make("TextLabel", footer, {
    BackgroundTransparency = 1,
    Font = Enum.Font.Gotham,
    Text = "Ready",
    TextColor3 = colors.muted,
    TextWrapped = false,
    TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
    Position = UDim2.fromOffset(14, 19),
    Size = UDim2.new(1, -28, 0, 15),
    TextTruncate = Enum.TextTruncate.AtEnd,
})

local bubble = make("TextButton", GUI, {
    Name = "KLauncher",
    Text = "K",
    Font = Enum.Font.GothamBold,
    TextSize = 17,
    BackgroundColor3 = colors.panel,
    TextColor3 = colors.accent,
    AutoButtonColor = false,
    Size = UDim2.fromOffset(36, 36),
    Position = UDim2.fromOffset(18, 88),
    Visible = true,
    BorderSizePixel = 0,
})
round(bubble, 11)
edge(bubble, colors.accent, 0.3)
hub.bubbleDot = make("Frame", bubble, {
    BorderSizePixel = 0,
    BackgroundColor3 = colors.muted,
    Size = UDim2.fromOffset(6, 6),
    Position = UDim2.new(1, -9, 0, 5),
})
round(hub.bubbleDot, 5)

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
local activeTab = "Level"
local navGlyphs = {
    Level = "LV", Fish = "FI", Quests = "QU", Craft = "CR",
    World = "WO", Boss = "BO", Other = "ST",
}
local function activate(name)
    activeTab = name
    for tabName, page in pairs(pages) do
        page.Visible = tabName == name
    end
    for tabName, item in pairs(tabs) do
        local selected = tabName == name
        item.button.BackgroundColor3 = selected and colors.row or colors.panel
        item.label.TextColor3 = selected and colors.white or colors.muted
        item.glyph.BackgroundColor3 = selected and colors.accentSoft or colors.row
        item.glyph.TextColor3 = selected and colors.accent or colors.muted
        item.mark.Visible = selected
    end
end
local function createTab(name)
    local btn = make("TextButton", navList, {
        BackgroundColor3 = colors.panel,
        Text = "",
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, compact and 42 or 46),
        BorderSizePixel = 0,
    })
    round(btn, 9)
    local mark = make("Frame", btn, {
        BackgroundColor3 = colors.accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 3, 1, -14),
        Position = UDim2.fromOffset(0, 7),
        Visible = false,
    })
    round(mark, 3)
    local glyph = make("TextLabel", btn, {
        BackgroundColor3 = colors.row,
        Text = navGlyphs[name] or "--",
        TextColor3 = colors.muted,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        Position = UDim2.fromOffset(7, 7),
        Size = UDim2.fromOffset(compact and 28 or 32, compact and 28 or 32),
    })
    round(glyph, 8)
    local label = make("TextLabel", btn, {
        BackgroundTransparency = 1,
        Text = name,
        TextColor3 = colors.muted,
        Font = Enum.Font.GothamMedium,
        TextSize = compact and 11 or 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(compact and 42 or 47, 0),
        Size = UDim2.new(1, compact and -47 or -52, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    tabs[name] = {button=btn, glyph=glyph, label=label, mark=mark}
    track(btn.MouseEnter:Connect(function()
        if activeTab ~= name then btn.BackgroundColor3 = colors.rowHover end
    end))
    track(btn.MouseLeave:Connect(function()
        if activeTab ~= name then btn.BackgroundColor3 = colors.panel end
    end))
    track(btn.MouseButton1Click:Connect(function()
        activate(name)
    end))
    local scroll = make("ScrollingFrame", content, {
        BackgroundTransparency = 1,
        Visible = false,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = colors.accent,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.None,
    })
    local layout = make("UIListLayout", scroll, {
        Padding = UDim.new(0, 9),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    make("UIPadding", scroll, {
        PaddingLeft = UDim.new(0, 3),
        PaddingRight = UDim.new(0, 8),
        PaddingTop = UDim.new(0, 4),
        PaddingBottom = UDim.new(0, 8),
    })
    track(layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        scroll.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 16)
    end))
    pages[name] = scroll
    return scroll
end
local levelPage = createTab("Level")
local fishPage = createTab("Fish")
local questPage = createTab("Quests")
local craftPage = createTab("Craft")
local worldPage = createTab("World")
local bossPage = createTab("Boss")
local extraPage = createTab("Other")

local function section(parent, name)
    local holder = make("Frame", parent, {
        BackgroundTransparency = 1,
        Size = UDim2.new(1, -4, 0, 29),
    })
    make("TextLabel", holder, {
        BackgroundTransparency = 1,
        Text = name,
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Enum.Font.GothamBold,
        TextSize = compact and 13 or 14,
        TextColor3 = colors.white,
        Size = UDim2.new(1, 0, 1, -5),
    })
    make("Frame", holder, {
        BackgroundColor3 = colors.outline,
        BackgroundTransparency = 0.48,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 1, -2),
        Size = UDim2.new(1, 0, 0, 1),
    })
    return holder
end
local function rowBase(parent, h)
    local row = make("Frame", parent, {
        BackgroundColor3 = colors.panel,
        BorderSizePixel = 0,
        Size = UDim2.new(1, -4, 0, h or 44),
    })
    round(row, 9)
    edge(row, colors.outline, 0.72)
    return row
end
local function action(parent, label, fn, important)
    local btn = make("TextButton", parent, {
        Text = label,
        TextColor3 = important and colors.bg or colors.white,
        BackgroundColor3 = important and colors.accent or colors.row,
        Font = Enum.Font.GothamSemibold,
        TextSize = compact and 11 or 12,
        Size = UDim2.new(1, -4, 0, 42),
        TextWrapped = true,
        BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(btn, 9)
    if important then
        edge(btn, colors.accent, 0.48)
    else
        edge(btn, colors.outline, 0.78)
    end
    track(btn.MouseEnter:Connect(function()
        if not important then btn.BackgroundColor3 = colors.rowHover end
    end))
    track(btn.MouseLeave:Connect(function()
        if not important then btn.BackgroundColor3 = colors.row end
    end))
    track(btn.MouseButton1Click:Connect(function()
        if not hub.running then return end
        local ok, err = pcall(fn, btn)
        if not ok then report("Button error: " .. tostring(err)) end
    end))
    return btn
end
local function toggle(parent, label, key, onChange)
    local row = rowBase(parent, 46)
    make("TextLabel", row, {
        Text = label,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = colors.white,
        Font = Enum.Font.GothamMedium,
        TextSize = compact and 11 or 12,
        TextTruncate = Enum.TextTruncate.AtEnd,
        Size = UDim2.new(1, -88, 1, 0),
        Position = UDim2.fromOffset(13, 0),
    })
    local btn = make("TextButton", row, {
        Size = UDim2.fromOffset(58, 27),
        Position = UDim2.new(1, -72, 0.5, -13),
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        BorderSizePixel = 0,
        AutoButtonColor = false,
    })
    round(btn, 8)
    local function refresh()
        btn.Text = state[key] and "ON" or "OFF"
        btn.TextColor3 = state[key] and colors.bg or colors.muted
        btn.BackgroundColor3 = state[key] and colors.accent or colors.row
    end
    callbacks[key] = refresh
    refresh()
    track(btn.MouseButton1Click:Connect(function()
        setState(key, not state[key])
        if onChange then onChange(state[key]) end
    end))
end
local function stepper(parent, label, key, minVal, maxVal, jump, suffix)
    local row = rowBase(parent, 46)
    make("TextLabel", row, {
        Text = label, BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
        TextColor3 = colors.white, Font = Enum.Font.GothamMedium, TextSize = compact and 11 or 12,
        Size = UDim2.new(1, -150, 1, 0), Position = UDim2.fromOffset(13, 0),
    })
    local minus = make("TextButton", row, {
        Text = "-", Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -138, 0.5, -15),
        TextColor3 = colors.white, BackgroundColor3 = colors.row, Font = Enum.Font.GothamBold, TextSize = 17,
    })
    round(minus, 6)
    local number = make("TextLabel", row, {
        BackgroundTransparency = 1, TextColor3 = colors.accent,
        Font = Enum.Font.GothamBold, TextSize = 13, Position = UDim2.new(1, -106, 0, 0),
        Size = UDim2.fromOffset(62, 46),
    })
    local plus = make("TextButton", row, {
        Text = "+", Size = UDim2.fromOffset(30, 30), Position = UDim2.new(1, -34, 0.5, -15),
        TextColor3 = colors.white, BackgroundColor3 = colors.row, Font = Enum.Font.GothamBold, TextSize = 17,
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
    Font=Enum.Font.GothamBold,TextSize=compact and 12 or 14,
    Text="Level --  /  Rod --",TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,
    Size=UDim2.new(1,-4,0,56),
})
round(levelingHUD,9);edge(levelingHUD,colors.outline,0.72)
local routeHUD=make("TextLabel",levelPage,{
    BackgroundTransparency=1,TextColor3=colors.muted,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    Font=Enum.Font.Gotham,TextSize=compact and 11 or 12,TextWrapped=true,
    Text="Route: idle\nNext upgrade: --",Size=UDim2.new(1,-4,0,105),
})
section(levelPage,"Fresh account: XP / cash farming")
local levelBtn=action(levelPage,"START AUTO LEVEL TO 500",function(btn)
    local active=not state.autoLevel
    setState("autoLevel",active)
    if active then
        setState("autoRoute",true)
        hub.armAutoRoute()
        for _,k in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam","charge","rhythm","phase2"}) do
            setState(k,true)
        end
        setState("sellNearFull",false)
        -- Auto Sell/Quests are independent. Use the QUICK START preset to
        -- enable both intentionally; toggles remain available individually.
        setState("autoFavorite",true)
        setState("autoEnzo",false)
        setState("autoLong",false)
        setState("stayIsland",false)
        lastCatchAt=os.clock()
        firstProfileAt=os.clock()
        lastProfileLevel=nil
        lastProfileXP=nil
        levelGained=0
        progressionStatus="Farming started. Selling and quests are separate switches."
        report("Auto Level ON. Use Auto Sell and Auto Quests separately or the QUICK START preset.")
    else
        hub.routeGate.ready=false
        hub.routeGate.status="Leveling stopped"
        for _,k in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam","charge","rhythm","phase2"}) do
            setState(k,false)
        end
        if isShopping() then finishRodShop("Stopped by user",0) end
        if buyerTripActive() then
            local returnCF=sellTracker.returnCF
            sellTracker.buyerPhase="idle"
            sellTracker.returnCF=nil
            if returnCF then teleportTo(returnCF,"cancel buyer trip") end
        end
        report("Auto level stopped. Auto Sell / Auto Quests retain their independent settings.")
    end
    btn.Text=active and "STOP AUTO LEVEL" or "START AUTO LEVEL TO 500"
end,true)
action(levelPage,"QUICK START: LEVEL + SELL + QUESTS",function()
    -- Convenience preset; all three remain individually toggleable.
    if not state.autoLevel then
        setState("autoRoute",true)
        hub.armAutoRoute()
        setState("autoLevel",true)
        for _,k in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam","charge","rhythm","phase2"}) do setState(k,true) end
        levelBtn.Text="STOP AUTO LEVEL"
    end
    setState("autoSell",true)
    setState("autoQuests",true)
    setState("autoFavorite",true)
    setState("fastSell",true)
    setState("sellNearFull",false)
    setState("autoEnzo",false)
    setState("autoLong",false)
    lastCatchAt=os.clock()
    notify("Quick Start ON. Auto Sell & Auto Quests can be disabled separately in their tabs.")
end,true)
toggle(levelPage,"Auto route based on equipped rod Power","autoRoute")
toggle(levelPage,"Auto face sea before casting","autoSeaFacing")
toggle(levelPage,"Auto shop one best rod per island (UI)","autoBuyRod")
toggle(levelPage,"Auto claim eligible free codes","autoCodes")
toggle(levelPage,"Favorite rare fish before selling","autoFavorite")
toggle(levelPage,"FAST SELL (will sell non-favorites)","fastSell",function(v)
    if v then notify("FAST SELL ON: rare catches can be sold! Turn OFF to protect them.") end
end)
stepper(levelPage,"Goal level","targetLevel",50,2000,50,"")
stepper(levelPage,"Sell interval","sellDelay",15,300,15,"s")
stepper(levelPage,"Cast recovery delay","castDelay",0.4,3,0.1,"s")
section(levelPage,"Rod shop: one target per island")
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
        notify("Saving for island target: "..suggestion.name.." ("..suggestion.cost.." Cash) on "..suggestion.island)
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

-- Quest selection board: a searchable multi-select modal, separate from Auto Level.
-- Only catalog entries with a verified handler can be enabled; all others remain INFO.
local function buildQuestUI()
    section(questPage, "Quest automation")
    hub.questHUD = make("TextLabel", questPage, {
        BackgroundColor3 = colors.panel,
        TextColor3 = colors.accent,
        Font = Enum.Font.GothamMedium,
        TextSize = compact and 11 or 12,
        Text = "Quest engine OFF",
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        Size = UDim2.new(1, -4, 0, 82),
        Position = UDim2.new(),
    })
    round(hub.questHUD, 9)
    edge(hub.questHUD, colors.outline, 0.72)
    toggle(questPage, "Auto quest engine", "autoQuests", function(v)
        notify(v and "Quest engine ON. Only selected supported handlers will run." or "Quest engine OFF")
    end)

    local QUEST_FILTERS = {"All rewards", "Rods", "Skills", "Orbs", "Tickets", "Seasonal", "Other"}
    local questFilter = "All rewards"
    local questSearchText = ""
    local liveQuestEntries = {}

    hub.questSelectedCount = function()
        local count = 0
        for _, entry in ipairs(ext.QUESTRUN_CATALOG) do
            if entry.autoKey and state[entry.autoKey] then count = count + 1 end
        end
        return count
    end

    local selectorCard = rowBase(questPage, 70)
    make("TextLabel", selectorCard, {
        BackgroundTransparency = 1,
        Text = "Selected questlines",
        TextColor3 = colors.white,
        Font = Enum.Font.GothamSemibold,
        TextSize = 13,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(14, 8),
        Size = UDim2.new(1, compact and -112 or -170, 0, 20),
    })
    local selectedSummary = make("TextLabel", selectorCard, {
        BackgroundTransparency = 1,
        Text = "0 supported handlers selected",
        TextColor3 = colors.muted,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(14, 32),
        Size = UDim2.new(1, compact and -112 or -170, 0, 20),
    })
    local pickerButton = make("TextButton", selectorCard, {
        BackgroundColor3 = colors.accent,
        TextColor3 = colors.bg,
        Text = compact and "SELECT" or "SELECT QUESTS",
        Font = Enum.Font.GothamBold,
        TextSize = compact and 10 or 11,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(compact and 84 or 112, 34),
        Position = UDim2.new(1, compact and -98 or -126, 0.5, -17),
    })
    round(pickerButton, 8)

    -- Modal is parented to ScreenGui (not the scrolling page), so it cannot be clipped.
    local pickerOverlay = make("Frame", GUI, {
        Name = "QuestPickerOverlay",
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Visible = false,
        ZIndex = 80,
    })
    hub.questPickerOverlay = pickerOverlay
    local backdrop = make("TextButton", pickerOverlay, {
        Name = "Backdrop",
        Text = "",
        BackgroundColor3 = Color3.fromRGB(3, 9, 16),
        BackgroundTransparency = 0.32,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 80,
        AutoButtonColor = false,
    })
    local modalWidth = math.max(280, math.min(560, viewport.X - 24))
    local modalHeight = math.max(300, math.min(560, viewport.Y - 36))
    local modal = make("Frame", pickerOverlay, {
        Name = "QuestPicker",
        BackgroundColor3 = colors.bg,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(modalWidth, modalHeight),
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        ZIndex = 81,
        ClipsDescendants = true,
    })
    round(modal, 14)
    edge(modal, colors.outline, 0.12)
    local modalHeader = make("Frame", modal, {
        BackgroundColor3 = colors.panel,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 58),
        ZIndex = 82,
    })
    make("TextLabel", modalHeader, {
        BackgroundTransparency = 1,
        Text = "Choose questlines",
        TextColor3 = colors.white,
        Font = Enum.Font.GothamBold,
        TextSize = 17,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(18, 7),
        Size = UDim2.new(1, -74, 0, 24),
        ZIndex = 83,
    })
    make("TextLabel", modalHeader, {
        BackgroundTransparency = 1,
        Text = "Select supported quests. INFO entries are reference-only.",
        TextColor3 = colors.muted,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.fromOffset(19, 32),
        Size = UDim2.new(1, -78, 0, 17),
        ZIndex = 83,
        TextTruncate = Enum.TextTruncate.AtEnd,
    })
    local modalClose = make("TextButton", modalHeader, {
        Text = "X",
        TextColor3 = colors.white,
        BackgroundColor3 = colors.row,
        Font = Enum.Font.GothamBold,
        TextSize = 12,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(32, 32),
        Position = UDim2.new(1, -44, 0, 13),
        ZIndex = 84,
        AutoButtonColor = false,
    })
    round(modalClose, 8)

    local searchBox = make("TextBox", modal, {
        Name = "QuestSearch",
        BackgroundColor3 = colors.panel,
        TextColor3 = colors.white,
        PlaceholderColor3 = colors.muted,
        PlaceholderText = "Search NPC, quest, island or reward...",
        Text = "",
        ClearTextOnFocus = false,
        Font = Enum.Font.Gotham,
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 70),
        Size = UDim2.new(1, -28, 0, 38),
        ZIndex = 82,
    })
    round(searchBox, 8)
    edge(searchBox, colors.outline, 0.52)
    make("UIPadding", searchBox, {
        PaddingLeft = UDim.new(0, 12),
        PaddingRight = UDim.new(0, 10),
    })

    local filterStrip = make("ScrollingFrame", modal, {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 116),
        Size = UDim2.new(1, -28, 0, 34),
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        ZIndex = 82,
    })
    local filterStripLayout = make("UIListLayout", filterStrip, {
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local pickerScroll = make("ScrollingFrame", modal, {
        Name = "QuestEntries",
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(14, 158),
        Size = UDim2.new(1, -28, 1, -224),
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = colors.accent,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.None,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ZIndex = 82,
    })
    local pickerLayout = make("UIListLayout", pickerScroll, {
        Padding = UDim.new(0, 7),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    make("UIPadding", pickerScroll, {
        PaddingTop = UDim.new(0, 3),
        PaddingBottom = UDim.new(0, 6),
        PaddingLeft = UDim.new(0, 2),
        PaddingRight = UDim.new(0, 5),
    })

    local footerLine = make("Frame", modal, {
        BackgroundColor3 = colors.outline,
        BackgroundTransparency = 0.45,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 14, 1, -57),
        Size = UDim2.new(1, -28, 0, 1),
        ZIndex = 82,
    })
    local clearButton = make("TextButton", modal, {
        Text = "CLEAR SELECTIONS",
        TextColor3 = colors.muted,
        BackgroundColor3 = colors.row,
        Font = Enum.Font.GothamBold,
        TextSize = 10,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(142, 34),
        Position = UDim2.new(0, 14, 1, -47),
        ZIndex = 82,
        AutoButtonColor = false,
    })
    round(clearButton, 8)
    local doneButton = make("TextButton", modal, {
        Text = "DONE",
        TextColor3 = colors.bg,
        BackgroundColor3 = colors.accent,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(100, 34),
        Position = UDim2.new(1, -114, 1, -47),
        ZIndex = 82,
        AutoButtonColor = false,
    })
    round(doneButton, 8)

    local function closeQuestPicker()
        pickerOverlay.Visible = false
    end
    track(backdrop.MouseButton1Click:Connect(closeQuestPicker))
    track(modalClose.MouseButton1Click:Connect(closeQuestPicker))
    track(doneButton.MouseButton1Click:Connect(closeQuestPicker))

    local function questFilterMatches(entry)
        if questFilter == "All rewards" then return true end
        local kind = tostring(entry.rewardType or "Unknown")
        if questFilter == "Rods" then return kind == "Rod" or kind == "Rod Skin" end
        if questFilter == "Skills" then return kind == "Skill" end
        if questFilter == "Orbs" then return kind == "Orb" end
        if questFilter == "Tickets" then return kind == "Ticket" end
        if questFilter == "Seasonal" then return kind == "Seasonal" or kind == "Rod Skin" end
        return kind == "Daily" or kind == "Other" or kind == "Unknown"
    end
    local function questSearchMatches(entry)
        local q = string.lower(questSearchText or "")
        if q == "" then return true end
        local haystack = table.concat({
            tostring(entry.npc or ""), tostring(entry.type or ""),
            tostring(entry.reward or ""), tostring(entry.rewardType or ""),
            tostring(entry.island or ""), tostring(entry.objective or ""),
        }, " "):lower()
        return string.find(haystack, q, 1, true) ~= nil
    end
    local function updateQuestSummary()
        local count = hub.questSelectedCount()
        selectedSummary.Text = tostring(count) .. " supported handler(s) selected"
        pickerButton.Text = compact and "SELECT" or "SELECT QUESTS"
    end
    local function makeQuestEntryRow(entry)
        local row = make("Frame", pickerScroll, {
            BackgroundColor3 = colors.row,
            BorderSizePixel = 0,
            Size = UDim2.new(1, -5, 0, 76),
            ZIndex = 83,
        })
        round(row, 9)
        local titleText = make("TextLabel", row, {
            BackgroundTransparency = 1,
            Text = tostring(entry.npc or "Unknown NPC") .. "  /  " .. tostring(entry.type or "Quest"),
            TextColor3 = colors.white,
            Font = Enum.Font.GothamSemibold,
            TextSize = 12,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(12, 7),
            Size = UDim2.new(1, -118, 0, 18),
            ZIndex = 84,
        })
        local rewardText = make("TextLabel", row, {
            BackgroundTransparency = 1,
            Text = string.upper(tostring(entry.rewardType or "Reward")) .. "  /  " .. tostring(entry.reward or "Reward not listed"),
            TextColor3 = colors.accent,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(12, 28),
            Size = UDim2.new(1, -118, 0, 17),
            ZIndex = 84,
        })
        local detailText = make("TextLabel", row, {
            BackgroundTransparency = 1,
            Text = tostring(entry.island or "Location unknown") .. "  /  " .. tostring(entry.objective or entry.automation or "Details unavailable"),
            TextColor3 = colors.muted,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Position = UDim2.fromOffset(12, 49),
            Size = UDim2.new(1, -118, 0, 16),
            ZIndex = 84,
        })
        local supported = entry.autoKey ~= nil
        local selected = supported and state[entry.autoKey] == true
        local status = make("TextButton", row, {
            BackgroundColor3 = supported and (selected and colors.accent or colors.panel) or colors.panel,
            TextColor3 = supported and (selected and colors.bg or colors.white) or colors.gold,
            Text = supported and (selected and "SELECTED" or "ADD") or "INFO",
            Font = Enum.Font.GothamBold,
            TextSize = 12,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(88, 28),
            Position = UDim2.new(1, -100, 0.5, -14),
            ZIndex = 84,
            AutoButtonColor = false,
        })
        round(status, 8)
        track(status.MouseButton1Click:Connect(function()
            if not supported then
                print("[KITKIT QUEST INFO] " .. tostring(entry.npc)
                    .. " | Reward: " .. tostring(entry.reward)
                    .. " | Objective: " .. tostring(entry.objective)
                    .. " | " .. tostring(entry.automation))
                notify(tostring(entry.reward or entry.npc) .. " is reference-only; no verified auto handler yet.")
                return
            end
            setState(entry.autoKey, not state[entry.autoKey])
            updateQuestSummary()
            if hub.refreshQuestPicker then hub.refreshQuestPicker() end
        end))
    end

    local function rebuildQuestPicker()
        for _, child in ipairs(pickerScroll:GetChildren()) do
            if child:IsA("Frame") then child:Destroy() end
        end
        local entries = {}
        for _, entry in ipairs(ext.QUESTRUN_CATALOG) do
            if questFilterMatches(entry) and questSearchMatches(entry) then
                table.insert(entries, entry)
            end
        end
        for _, entry in ipairs(liveQuestEntries) do
            if questFilterMatches(entry) and questSearchMatches(entry) then
                table.insert(entries, entry)
            end
        end
        table.sort(entries, function(a, b)
            local at = tostring(a.rewardType or "Unknown") .. tostring(a.npc or "")
            local bt = tostring(b.rewardType or "Unknown") .. tostring(b.npc or "")
            return at < bt
        end)
        for _, entry in ipairs(entries) do makeQuestEntryRow(entry) end
        task.defer(function()
            pickerScroll.CanvasSize = UDim2.fromOffset(0, pickerLayout.AbsoluteContentSize.Y + 10)
        end)
        updateQuestSummary()
    end
    hub.refreshQuestPicker = rebuildQuestPicker
    track(pickerLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        pickerScroll.CanvasSize = UDim2.fromOffset(0, pickerLayout.AbsoluteContentSize.Y + 10)
    end))

    local filterButtons = {}
    local function setQuestFilter(name)
        questFilter = name
        for filterName, button in pairs(filterButtons) do
            local selected = filterName == name
            button.BackgroundColor3 = selected and colors.accentSoft or colors.panel
            button.TextColor3 = selected and colors.accent or colors.muted
        end
        rebuildQuestPicker()
    end
    for _, filterName in ipairs(QUEST_FILTERS) do
        local chip = make("TextButton", filterStrip, {
            BackgroundColor3 = filterName == questFilter and colors.accentSoft or colors.panel,
            TextColor3 = filterName == questFilter and colors.accent or colors.muted,
            Text = filterName,
            Font = Enum.Font.GothamMedium,
            TextSize = 12,
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(filterName == "All rewards" and 94 or 76, 30),
            ZIndex = 83,
            AutoButtonColor = false,
        })
        round(chip, 8)
        filterButtons[filterName] = chip
        track(chip.MouseButton1Click:Connect(function()
            setQuestFilter(filterName)
        end))
    end
    track(searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        questSearchText = searchBox.Text
        rebuildQuestPicker()
    end))
    track(clearButton.MouseButton1Click:Connect(function()
        for _, entry in ipairs(ext.QUESTRUN_CATALOG) do
            if entry.autoKey then setState(entry.autoKey, false) end
        end
        updateQuestSummary()
        rebuildQuestPicker()
        notify("Supported quest selections cleared. Master switch remains unchanged.")
    end))
    track(pickerButton.MouseButton1Click:Connect(function()
        rebuildQuestPicker()
        pickerOverlay.Visible = true
    end))

    updateQuestSummary()
    rebuildQuestPicker()

    -- The category filter lives in the searchable picker; this ticket selector is independent.
    section(questPage, "Quest settings")
    local function makeSingleChoiceDropdown(parent, label, options, getCurrent, onSelect)
        local row = rowBase(parent, 46)
        make("TextLabel", row, {
            BackgroundTransparency = 1,
            Text = label,
            TextColor3 = colors.muted,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
            Position = UDim2.fromOffset(13, 0),
            Size = UDim2.new(1, -(compact and 142 or 184), 1, 0),
        })
        local dropdownWidth = compact and 118 or 158
        local button = make("TextButton", row, {
            BackgroundColor3 = colors.row,
            TextColor3 = colors.white,
            Font = Enum.Font.GothamMedium,
            TextSize = 11,
            Text = "",
            BorderSizePixel = 0,
            Size = UDim2.fromOffset(dropdownWidth, 30),
            Position = UDim2.new(1, -dropdownWidth - 13, 0.5, -15),
            AutoButtonColor = false,
        })
        round(button, 8)
        local menu = make("Frame", parent, {
            BackgroundColor3 = colors.panel,
            BorderSizePixel = 0,
            Visible = false,
            Size = UDim2.new(1, -4, 0, 0),
            ClipsDescendants = true,
        })
        round(menu, 9)
        edge(menu, colors.outline, 0.35)
        local function refresh()
            button.Text = tostring(getCurrent()) .. "  v"
        end
        local function close()
            menu.Size = UDim2.new(1, -4, 0, 0)
            menu.Visible = false
        end
        for _, optionName in ipairs(options) do
            local option = make("TextButton", menu, {
                BackgroundColor3 = colors.row,
                TextColor3 = colors.white,
                Font = Enum.Font.GothamMedium,
                TextSize = 12,
                Text = optionName,
                BorderSizePixel = 0,
                Size = UDim2.new(1, -8, 0, 30),
                AutoButtonColor = false,
            })
            round(option, 7)
            track(option.MouseButton1Click:Connect(function()
                onSelect(optionName)
                refresh()
                close()
            end))
        end
        make("UIListLayout", menu, {Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder})
        make("UIPadding", menu, {
            PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
            PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5),
        })
        track(button.MouseButton1Click:Connect(function()
            if menu.Visible then
                close()
            else
                menu.Visible = true
                menu.Size = UDim2.new(1, -4, 0, #options * 33 + 12)
            end
        end))
        refresh()
        return refresh
    end
    makeSingleChoiceDropdown(questPage, "Ticket difficulty", {"Easy", "Hard"}, function()
        return state.ticketQuestMode
    end, function(value)
        state.ticketQuestMode = value
        notify("Ticket quest difficulty: " .. value)
    end)

    action(questPage, "SCAN LIVE QUEST MODULES + REWARDS", function()
        local modules, err = ext.discoverLiveQuestModules()
        if not modules then notify(err or "Live quest modules unavailable"); return end
        liveQuestEntries = {}
        local known = {}
        for _, entry in ipairs(ext.QUESTRUN_CATALOG) do
            known[tostring(entry.id or ""):lower()] = true
            known[tostring(entry.npc or ""):lower()] = true
        end
        for _, module in ipairs(modules) do
            if not known[module.name:lower()] then
                table.insert(liveQuestEntries, {
                    id = "Live_" .. module.name,
                    npc = "Live quest: " .. module.name,
                    island = "Live data",
                    reward = module.reward,
                    rewardType = "Unknown",
                    type = "Live module",
                    objective = tostring(module.objectiveCount) .. " objective rows",
                    automation = "Track only: module discovered, but NPC dialogue / reward handler is not verified",
                })
            end
        end
        rebuildQuestPicker()
        notify("Scanned " .. #modules .. " live quest modules; " .. #liveQuestEntries .. " additional entries added.")
    end)
    action(questPage, "TELEPORT TO BATTLEFIELD SAGE", function()
        local npc = ext.findQuestNPC("sage", "Battlefield Isle")
        hub.manualTravelUntil = os.clock() + 65
        teleportTo(npc and npc.CFrame * CFrame.new(0, 0, -7) or cframeIsland("Battlefield Isle"), "Sage Yijiu")
    end)
    action(questPage, "READ SELECTED QUEST STATUS", function()
        local out = {
            "Master: " .. tostring(state.autoQuests),
            "Sage: " .. ext.questTracker.sage,
            "Ticket: " .. ext.questTracker.ticketStatus,
            "Zeng: " .. ext.questTracker.zengStatus,
            ext.sideQuestStatus(),
        }
        for _, line in ipairs(out) do print("[KITKIT QUEST] " .. line) end
        notify("Quest status printed to executor console")
    end)
    action(questPage, "PRINT QUEST CATALOG + REWARDS", function()
        for i, q in ipairs(ext.QUESTRUN_CATALOG) do
            print(("[KITKIT QUEST %02d] %s @ %s | %s: %s | %s"):format(i, q.npc, q.island, q.rewardType, q.reward, q.automation))
        end
        notify("Quest catalog printed to executor console")
    end)
    make("TextLabel", questPage, {
        Text = "Supported entries can be selected for automation. INFO entries show known rewards/objectives but remain reference-only until their live dialogue and completion handlers are verified.",
        TextWrapped = true,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextXAlignment = Enum.TextXAlignment.Left,
        BackgroundTransparency = 1,
        TextColor3 = colors.muted,
        Font = Enum.Font.Gotham,
        TextSize = 11,
        Size = UDim2.new(1, -4, 0, 58),
    })
end
buildQuestUI()

section(craftPage,"Auto gather + craft (separate)")
local craftHUD=make("TextLabel",craftPage,{
    BackgroundColor3=colors.panel,TextColor3=colors.accent,
    Font=Enum.Font.Gotham,TextSize=compact and 11 or 12,
    Text="Crafting OFF",TextWrapped=true,
    TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,
    Size=UDim2.new(1,-4,0,99),
})
round(craftHUD,9);edge(craftHUD,colors.outline,0.72)
action(craftPage,"TARGET ROD: Heavenpiercer Rod",function(btn)
    state.craftTarget=state.craftTarget=="Heavenpiercer Rod" and "Pure Diamond Rod" or "Heavenpiercer Rod"
    ext.craftTracker.status="Target changed; protecting ingredients for "..state.craftTarget
    ext.craftTracker.lastBefore=nil
    ext.craftTracker.pendingAt=0
    btn.Text="TARGET ROD: "..state.craftTarget
    notify("Craft target: "..state.craftTarget)
end)
toggle(craftPage,"AUTO FARM MATERIAL FISH","autoFarmMaterials",function(v)
    if v and not state.protectMaterials then
        setState("autoFarmMaterials",false)
        notify("Turn on Protect Craft Materials before gathering.")
    elseif v then
        for _,k in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam","charge","rhythm","phase2"}) do
            setState(k,true)
        end
        setState("autoEnzo",false);setState("autoLong",false)
        notify("Ingredient farming ON with fishing engine; wait for matching weather.")
    end
end)
toggle(craftPage,"AUTO CRAFT ROD (spends Gems!)","autoCraftRod",function(v)
    if v then notify("Auto Craft ON: verified materials + Gems will be spent when ready. Failure is possible!") end
end)
toggle(craftPage,"Auto craft special bait if recipe known","autoCraftBait")
toggle(craftPage,"Protect target fish from Auto Sell","protectMaterials",function(v)
    if not v and state.autoFarmMaterials then
        setState("autoFarmMaterials",false)
        notify("Material farming stopped: protection must remain ON.")
    end
end)
toggle(craftPage,"Auto favorite protected fish","autoFavorite")
action(craftPage,"CHECK CRAFT REQUIREMENTS NOW",function()
    local recipe,name=ext.recipeForTarget()
    local missing={}
    for _,entry in ipairs(recipe and recipe.fish or {}) do
        local owned=ext.ownedFishCount(entry.name)
        local detail=entry.weather and (entry.island.." / "..entry.weather)
            or ("Summon with "..tostring(entry.bait))
        local line=entry.name.." = "..tostring(owned or "?").." | "..detail
        table.insert(missing,line)
        print("[KITKIT CRAFT] "..line)
    end
    local root=playerData()
    print("[KITKIT CRAFT] Crystals/Gems="..tostring(candidateValue(root,{"Crystals","Crystal","Gems","Gem"})))
    print("[KITKIT CRAFT] Game crafting module="..tostring(ext.liveCraftModule(name)))
    notify("Craft requirements printed to console; status: "..ext.craftTracker.status)
end)
action(craftPage,"CRAFT ONE IF VERIFIED (AUTO CRAFT ON)",function()
    if not state.autoCraftRod then notify("Enable Auto Craft first so Gem spending is intentional") return end
    ext.beginCraftAttempt()
    notify(ext.craftTracker.status)
end)
make("TextLabel",craftPage,{
    Text="Weather must match to farm each weather fish. Rainbow/Frost bait fish require bait. Missing live recipe, Gem balance, or fish blocks crafting; server decides success. We never claim a craft succeeded without the rod in your inventory.",
    TextWrapped=true,TextYAlignment=Enum.TextYAlignment.Top,TextXAlignment=Enum.TextXAlignment.Left,
    BackgroundTransparency=1,TextColor3=colors.muted,Font=Enum.Font.Gotham,TextSize=12,
    Size=UDim2.new(1,-4,0,87),
})

section(fishPage, "Fishing automation")
local reelStatusHUD = make("TextLabel", fishPage, {
    BackgroundColor3 = colors.panel, TextColor3 = colors.accent,
    Font = Enum.Font.GothamMedium, TextSize = compact and 11 or 12,
    Text = "BAR GUARD: OFF | Corrections 0 | Reel requests 0",
    TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
    Size = UDim2.new(1, -4, 0, 38),
})
round(reelStatusHUD, 9);edge(reelStatusHUD,colors.outline,0.72)
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
toggle(fishPage, "Keep fishing bar centered (triple guard)", "lockBar")
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
section(fishPage, "Selling - independently ON/OFF")
toggle(fishPage, "AUTO SELL ALL (caution)", "autoSell", function(v)
    if v then notify("Auto Sell ON. Rare protection is best-effort, not guaranteed!") end
end)
toggle(fishPage, "Only sell when bag >= 88%", "sellNearFull")
toggle(fishPage, "Protect rares (may pause all selling)", "protectRare")
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
    TextWrapped = true, TextSize = 12, Font = Enum.Font.Gotham,
    TextColor3 = colors.muted, BackgroundTransparency = 1,
    Size = UDim2.new(1, -6, 0, 43), TextXAlignment = Enum.TextXAlignment.Left,
})
toggle(bossPage, "Auto Enzo boss (retries)", "autoEnzo", function(v)
    if v then
        setState("autoLong", false); setState("autoLevel",false)
        for _,k in ipairs({"autoCast","autoReel","autoSkill"}) do setState(k,false) end
        levelBtn.Text="START AUTO LEVEL TO 500"
    end
end)
toggle(bossPage, "Auto Long Diaohai (secret)", "autoLong", function(v)
    if v then
        setState("autoEnzo", false); setState("autoLevel",false)
        for _,k in ipairs({"autoCast","autoReel","autoSkill"}) do setState(k,false) end
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

section(worldPage,"Roaming NPCs: click to teleport")
toggle(worldPage,"Popup when Maoshan/Taoist is loaded","merchantAlerts")
action(worldPage,"REFRESH MAOSHAN / TAOIST SCAN",function()
    ext.scanMerchants()
    local parts={}
    for _,name in ipairs({"Maoshan","Taoist"}) do
        parts[#parts+1]=name.."="..(ext.merchantTracker[name] and "HERE" or "not loaded")
    end
    notify(table.concat(parts," | "))
end)
action(worldPage,"TP TO MAOSHAN (if spawned)",function() ext.tpMerchant("Maoshan") end)
action(worldPage,"TP TO TAOIST (if spawned)",function() ext.tpMerchant("Taoist") end)
-- Clickable toast stays visible even when the main window is minimized.
local roamingPopup=make("Frame",GUI,{
    Name="MerchantAlerts", BackgroundColor3=colors.panel,BorderSizePixel=0,
    Position=UDim2.new(1,-260,0,92), Size=UDim2.fromOffset(244,106),
    Visible=false, ZIndex=20,
})
round(roamingPopup,9);edge(roamingPopup,colors.gold)
make("TextLabel",roamingPopup,{
    Text="MERCHANT NEARBY",TextColor3=colors.accent,
    BackgroundTransparency=1,TextSize=12,Font=Enum.Font.GothamBold,
    Size=UDim2.new(1,-16,0,22),Position=UDim2.fromOffset(8,2),ZIndex=21,
})
local merchantButtons={}
for i,name in ipairs({"Maoshan","Taoist"}) do
    local btn=make("TextButton",roamingPopup,{
        Text=name.."   /   teleport",BackgroundColor3=colors.row,
        TextColor3=colors.white,Font=Enum.Font.GothamMedium,TextSize=12,
        Position=UDim2.fromOffset(8,28+(i-1)*34),
        Size=UDim2.new(1,-16,0,30),Visible=false,ZIndex=21,
    })
    round(btn,5)
    merchantButtons[name]=btn
    track(btn.MouseButton1Click:Connect(function() ext.tpMerchant(name) end))
end

section(worldPage, "Server weather")
local weatherLabel = make("TextLabel", worldPage, {
    BackgroundColor3 = colors.panel, TextColor3 = colors.accent,
    Font = Enum.Font.GothamBold, TextSize = 14, Text = "Current weather: ...",
    Size = UDim2.new(1, -4, 0, 44),
})
round(weatherLabel, 9);edge(weatherLabel,colors.outline,0.72)
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
    Font = Enum.Font.Gotham, TextSize = 12,
    Text = "Auto Sell, Auto Quests and Auto Craft are independent. Level route saves Cash for one target rod per island. "
        .. "Crafting uses server-replicated recipes and can spend Gems with a chance of failure. "
        .. "Material fish must be favorited before Sell All. Quest/shop/craft features are best-effort and LIVE UNTESTED.",
    Size = UDim2.new(1, -4, 0, 91),
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
        "KITKIT HUB v2.7 REDACTED DIAGNOSTICS",
        "Level="..tostring(p.level).." XP="..tostring(p.xp).." Cash="..tostring(p.cash),
        "Rod="..tostring(p.rod).." Power="..tostring(rodPower(p.rod)),
        "Bag="..tostring(count).."/"..tostring(maxCount),
        "FishingGUI="..tostring(select(2,minigame())),
        reelDiagnostics(),
        "Known code attempts="..tostring((function() local n=0 for _ in pairs(codesAttempted) do n=n+1 end return n end)()),
        "Mode="..tostring(state.autoLevel).." State="..progressionStatus,
        "RouteGate="..hub.routeGate.status.." Island="..tostring(hub.routeGate.island)
            .." Ready="..tostring(hub.routeGate.ready).." TPAttempts="..hub.routeGate.attempts
            .." ReadyChecks="..hub.routeGate.confirms.." BlockedCasts="..hub.routeGate.blockedCasts,
        "NextIslandGoal="..tostring(select(2,hub.nextIslandGoal(p))),
        "Sea="..facingTracker.status.." Checks="..facingTracker.checks
            .." Verified="..facingTracker.verified.." Adjusted="..facingTracker.corrected
            .." FailedCasts="..facingTracker.failedCasts,
        "Sales="..sellTracker.status.." Tries="..sellTracker.attempts
            .." Verified="..sellTracker.confirmed.." Unconfirmed="..sellTracker.failed
            .." BuyerTrip="..sellTracker.buyerPhase,
        "Shop="..rodShop.status.." Phase="..rodShop.phase.." LastTarget="..rodShop.lastShopTarget,
        "Quest="..ext.questTracker.status.." Sage="..ext.questTracker.sage.." Ticket="..ext.questTracker.ticketStatus..
            " Zeng="..ext.questTracker.zengStatus,
        "Craft="..ext.craftTracker.status.." Target="..state.craftTarget..
            " Attempts="..ext.craftTracker.attempts,
        "Merchant Maoshan="..tostring(ext.merchantTracker.Maoshan~=nil)..
            " Taoist="..tostring(ext.merchantTracker.Taoist~=nil),
        "AutoBuy="..tostring(state.autoBuyRod).." SeaFacing="..tostring(state.autoSeaFacing),
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

hub.uiToggleKey = Enum.KeyCode.K
hub.waitingForBind = false
-- Keybind control stored on hub
hub.keybindButton=action(extraPage,"MENU KEYBIND  /  K",function(btn)
    hub.waitingForBind=true
    btn.Text="Press any keyboard key..."
end)
function hub.toggleMenu()
    main.Visible = not main.Visible
    if not main.Visible and hub.questPickerOverlay then
        hub.questPickerOverlay.Visible = false
    end
end
track(closeButton.MouseButton1Click:Connect(function()
    main.Visible = false
    if hub.questPickerOverlay then hub.questPickerOverlay.Visible = false end
end))
track(bubble.MouseButton1Click:Connect(hub.toggleMenu))
track(UIS.InputBegan:Connect(function(input, processed)
    if not hub.running then return end
    if input.UserInputType~=Enum.UserInputType.Keyboard then return end
    if input.KeyCode == Enum.KeyCode.Escape and hub.questPickerOverlay and hub.questPickerOverlay.Visible then
        hub.questPickerOverlay.Visible = false
        return
    end
    if UIS:GetFocusedTextBox() then return end
    if hub.waitingForBind then
        hub.waitingForBind=false
        if input.KeyCode~=Enum.KeyCode.Unknown then
            hub.uiToggleKey=input.KeyCode
        end
        hub.keybindButton.Text="MENU KEYBIND  /  "..hub.uiToggleKey.Name:upper()
        return
    end
    if not processed and input.KeyCode==hub.uiToggleKey then hub.toggleMenu() end
end))
activate("Level")

function hub:Unload()
    if not self.running then return end
    self.running = false
    for _, c in ipairs(self.connections) do
        pcall(function() c:Disconnect() end)
    end
    disconnectBarListener()
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

return {
    colors = colors,
    main = main,
    headerSubtitle = headerSubtitle,
    statusTop = statusTop,
    statusBottom = statusBottom,
    weatherLabel = weatherLabel,
    reelStatusHUD = reelStatusHUD,
    levelingHUD = levelingHUD,
    craftHUD = craftHUD,
    merchantButtons = merchantButtons,
    roamingPopup = roamingPopup,
    routeHUD = routeHUD,
    levelBtn = levelBtn,
}
end
hub.ui = buildInterface()

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
            if (state.protectMaterials and isCraftIngredient and isCraftIngredient(child))
                or (flaggedRare(child) and state.autoLevel and state.protectRare) then
                task.defer(function()
                    if hub.running and child.Parent then tryFavorite(child) end
                end)
            end
        end))
    end
end
local function stopAutoLevel(reason)
    state.autoLevel=false
    hub.routeGate.ready=false
    hub.routeGate.status="Leveling stopped"
    for _,k in ipairs({"autoCast","autoReel","lockBar","autoSkill","slam","charge","rhythm","phase2"}) do
        setState(k,false)
    end
    progressionStatus=reason
    if hub.ui and hub.ui.levelBtn then hub.ui.levelBtn.Text="START AUTO LEVEL TO 500" end
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
    if p.level and p.level>=state.targetLevel
        and not (state.autoQuests and state.autoSageAfterAmber
            and (not ext.diamondOwned()) and ext.questTracker.sageRoute) then
        stopAutoLevel("GOAL HIT: Level "..p.level.."! Fishing stopped; Sell/Quests stay independent.")
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
    local override,overrideReason=ext.activeFarmOverride()
    if override then desired=override end
    if overrideReason=="sage" then
        progressionStatus="Sage Diamond quest: "..ext.questTracker.sage
    elseif overrideReason=="craft" then
        progressionStatus="Gathering "..tostring(ext.craftTracker.fish).." in "..desired
    elseif not power then
        progressionStatus="Rod Power unknown: staying on Beginning Isle"
    else
        local _,nextIsland,required,nextTarget=hub.nextIslandGoal(p)
        if nextIsland and power<required then
            progressionStatus=desired.." (Power "..power..") | Next "..nextIsland
                .." needs "..required.." | "..(nextTarget and ("Save for "..nextTarget.name) or "Upgrade rod")
        else
            progressionStatus="Farming "..desired.." (Power "..power..")"
        end
    end
    hub.routeTravelTick(now,desired)
    -- If we've made no XP and caught nothing on a higher island, back off one
    -- island temporarily. This avoids repeatedly failing catches on over-tier rods.
    if not override and index>1 and now-lastCatchAt>155 then
        routeCooldownUntil[desired]=now+360
        local prev=LEVEL_ROUTE[index-1].name
        notify("No catch/XP progress for 155s. Trying "..prev.." for 6 minutes.")
        lastCatchAt=now
        lastAutoRoute=0
    elseif not override and index==1 and now-lastCatchAt>180 then
        progressionStatus="Stalled: check tutorial / rod / reel / inventory"
        if now-lastAutoHealthCheck>120 then
            lastAutoHealthCheck=now
            notify("No XP/catches after 3 min. Check tutorial, rod purchase, and fishing GUI.")
        end
        -- do not force server remote spam or fabricate XP.
        lastCatchAt=now
    end
    local suggestion=nextRodSuggestion(p)
    if suggestion and p.cash and p.cash>=suggestion.cost and not state.autoBuyRod then
        if lastRodPrompt~=("buy:"..suggestion.name) then
            lastRodPrompt="buy:"..suggestion.name
            notify("Island target affordable: "..suggestion.name.." at "..suggestion.island)
        end
    end
end

-- Late render + simulation phases reduce the time a competing game tween
-- can move the indicator. A property-change listener handles mid-frame edits.
-- No server remotes are sent from these render callbacks.
track(RunService.RenderStepped:Connect(function()
    if hub.running then monitorFishingBar() end
end))
track(RunService.Stepped:Connect(function()
    if hub.running then monitorFishingBar() end
end))
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
        if state.lockBar or workingBoss then monitorFishingBar() end
        if (state.autoReel or workingBoss) and now - lastReel >= 0.085 then
            lastReel = now
            if fire("UpdateFishProgression") then reelRequests = reelRequests + 1 end
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
    elseif state.autoCast and now>=(hub.manualTravelUntil or 0)
        and not (state.autoQuests and ext.questTracker.sageRoute=="Battlefield Isle")
        and not isShopping() and not buyerTripActive()
        and not sellTracker.pending and char and now - lastCast > math.max(0.4, state.castDelay)
        and now - lastFishingEnd > math.max(0.4, state.castDelay) then
        local p=profile()
        local island=ext.activeFarmOverride() or routeChoice(p)
        local root=char:FindFirstChild("HumanoidRootPart")
        local shopPause,shopReason=hub.shopNeedsPause(p)
        if not root then
            lastCast=now
        elseif shopPause then
            hub.routeGate.status=shopReason or "Rod upgrade queued"
            lastCast=now
        elseif not hub.routeReadyForCast(island) then
            hub.routeGate.blockedCasts=hub.routeGate.blockedCasts+1
            lastCast=now
        elseif state.autoSeaFacing and not faceSea(island,false) then
            lastCast=now
        elseif char:GetAttribute("Type")~="Fishing Rod" then
            lastCast=now
            task.spawn(equipRod)
        elseif not char:GetAttribute("Fishing") then
            lastCast=now
            if fire("Fishing",root.CFrame) then
                task.delay(2.1,function()
                    if not hub.running or not state.autoCast or isShopping() then return end
                    local c=LocalPlayer.Character
                    local _,activeNow=minigame()
                    if c==char and not activeNow and not c:GetAttribute("Fishing")
                        and os.clock()-lastCast<=4 then
                        facingTracker.failedCasts=facingTracker.failedCasts+1
                        facingTracker.lastAt=0
                        -- Rotate/revalidate again before the NEXT cast.
                        facingTracker.status="Cast not confirmed; rechecking direction"
                    end
                end)
            end
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
                if hub.touched[part] == nil then hub.touched[part] = part.CanCollide end
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
        checkSellResult()
        if state.autoSell and now>=(hub.manualTravelUntil or 0) and not isShopping() then buyerTick() end
        local _, bagCount, bagMax = getInventory()
        local emergencySell = state.autoLevel and bagMax and bagMax>0
            and bagCount and bagCount>=bagMax-2 and now-lastSell>=12
        if state.autoSell and now>=(hub.manualTravelUntil or 0) and not isShopping() and not buyerTripActive()
            and not sellTracker.pending
            and (now-lastSell>=state.sellDelay or emergencySell) then
            local _,active=minigame()
            if not active then
                lastSell=now
                local success=sellNow(false)
                if not success and sellTracker.status:find("Rare",1,true)
                    and now-lastAutoHealthCheck>45 then
                    lastAutoHealthCheck=now
                    report("Auto-sell: "..sellTracker.status)
                end
            end
        end
        if state.stayIsland and now>=(hub.manualTravelUntil or 0) and not isShopping() and not buyerTripActive() and not state.autoEnzo and not state.autoLong and now - lastTP >= 5 then
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
        if state.autoBuyRod and state.autoLevel then
            local ok,err=pcall(shopTick)
            if not ok then
                finishRodShop("Shop automation error: "..tostring(err),120)
            end
        end
        task.wait(1.1)
    end
end)

task.spawn(function()
    while hub.running do
        local craftOK,craftError=pcall(ext.craftTick)
        if not craftOK then ext.craftTracker.status="Craft error: "..tostring(craftError) end
        local ok,err=pcall(ext.questTick)
        if not ok then ext.questTracker.status="Quest error: "..tostring(err) end
        local auxOK,auxError=pcall(ext.auxiliaryFarmTick)
        if not auxOK then report("Quest/craft route issue: "..tostring(auxError)) end
        local now=os.clock()
        if now-ext.merchantTracker.lastScan>=5 then
            ext.merchantTracker.lastScan=now
            local scanned,scanError=pcall(ext.scanMerchants)
            if not scanned then report("Merchant scan issue: "..tostring(scanError)) end
        end
        task.wait(3)
    end
end)

task.spawn(function()
    while hub.running do
        local b = scanBosses()
        local _, count, cap = getInventory()
        local weather = tostring(workspace:GetAttribute("Weather") or "Unknown")
        local p=profile()
        local route,power=routeChoice(p)
        local override=ext.activeFarmOverride()
        if override then route=override end
        local activeTime=math.max(1,(os.clock()-firstProfileAt)/3600)
        local gainRate=levelGained/activeTime
        hub.ui.statusTop.Text="Lv "..tostring(p.level or "?").."  /  Bag "..tostring(count or "?").."/"..tostring(cap or "?")
            .."  /  "..weather
        hub.ui.weatherLabel.Text="Current weather: "..weather
        hub.ui.statusBottom.Text=lastAction
        hub.bubbleDot.BackgroundColor3=(state.autoLevel or state.autoCast) and hub.ui.colors.accent or hub.ui.colors.muted
        hub.ui.reelStatusHUD.Text="BAR GUARD: "..barGuard.status
            .." | Snaps "..barGuard.corrections
            .." | Reel requests "..reelRequests
        if state.autoLevel then
            hub.ui.headerSubtitle.Text="LEVELING  /  "..barGuard.status
            hub.ui.headerSubtitle.TextColor3=hub.ui.colors.accent
        elseif state.autoCast or state.autoReel or state.lockBar then
            hub.ui.headerSubtitle.Text="FISHING  /  "..barGuard.status
            hub.ui.headerSubtitle.TextColor3=hub.ui.colors.gold
        else
            hub.ui.headerSubtitle.Text="HEAVYWEIGHT  /  2.7"
            hub.ui.headerSubtitle.TextColor3=hub.ui.colors.muted
        end
        hub.ui.levelingHUD.Text="Lv "..tostring(p.level or "?").." / "..state.targetLevel
            .." | "..tostring(p.rod~="" and p.rod or "Rod unknown")
            .."\nPower "..tostring(power or "?").." | "..tostring(p.cash or "?").." Cash"
            .." | "..string.format("%.1f",gainRate).." Lv/h"
        local suggested=nextRodSuggestion(p)
        hub.questHUD.Text="Master "..(state.autoQuests and "ON" or "OFF")
            .." | Selected: "..hub.questSelectedCount()
            .."\nSage: "..ext.questTracker.sage
            .."\nTicket: "..ext.questTracker.ticketStatus
            .."\nZeng: "..ext.questTracker.zengStatus
            .."\nLive: "..ext.questTracker.side
        local recipe=ext.CRAFT_PLAN[state.craftTarget]
        local gathered,needed=0,#(recipe and recipe.fish or {})
        for _,entry in ipairs(recipe and recipe.fish or {}) do
            if (ext.ownedFishCount(entry.name) or 0)>=1 then gathered=gathered+1 end
        end
        hub.ui.craftHUD.Text=state.craftTarget.." ["..gathered.."/"..needed.."] "
            ..(state.autoFarmMaterials and "FARM ON" or "FARM OFF")
            .." | Weather "..weather.."\n"..ext.craftTracker.status
            .."\nNext fish: "..tostring(ext.craftTracker.fish or "--")
            .." | Craft attempts: "..ext.craftTracker.attempts
        local merchantActive=false
        for _,name in ipairs({"Maoshan","Taoist"}) do
            local available=ext.merchantTracker[name]~=nil
            hub.ui.merchantButtons[name].Visible=available and state.merchantAlerts
            merchantActive=merchantActive or available
        end
        hub.ui.roamingPopup.Visible=merchantActive and state.merchantAlerts
        hub.ui.routeHUD.Text="ROUTE  /  "..hub.routeGate.status
            .."\n"..progressionStatus
            .."\nSHOP  /  "..rodShop.status
            .."\nNEXT  /  "..(suggested and (suggested.name.." ("..suggested.cost.." Cash)") or "Complete")
        task.wait(3)
    end
end)

report("KITKIT v2.7 ready. Click the small K icon or press K to open the menu.")
if state.fogAlert and (lastWeather:lower():find("fog", 1, true)
    or lastWeather:lower():find("mist", 1, true)) then
    task.delay(0.7, function()
        if hub.running then notify("This server is already foggy: " .. lastWeather) end
    end)
end
