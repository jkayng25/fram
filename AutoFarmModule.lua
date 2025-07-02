-- 📦 AutoFarmModule.lua (FIXED VERSION): Tự động farm 5 tầng dungeon trong King Legacy
-- ✅ Đã fix các lỗi nghiêm trọng và cải tiến hiệu suất

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- 🎯 Cấu hình chính
local CONFIG = {
    dungeonCircleCFrame = CFrame.new(10959.5859, 133.835114, 1250.04089),
    dungeonPos = Vector3.new(20072.91, 15584.16, 20049.55),
    dungeonRadius = 600,
    maxFloors = 5,
    floorTimeout = 120, -- 2 phút timeout mỗi tầng
    respawnWaitTime = 10,
    dungeonCooldown = 25, -- Thời gian chờ giữa các lần chạy dungeon
    
    -- 🆘 Custom dungeon circle position (set này nếu auto-detect fail)
    -- Ví dụ: customDungeonCircle = CFrame.new(x, y, z)
    customDungeonCircle = nil,
}

-- 🎮 Trạng thái game
local GameState = {
    isRunning = false,
    currentFloor = 0,
    enemiesKilled = 0,
    lastFruitUse = 0,
    lastStatus = "Standby"
}

-- 🛡️ Utility Functions
local function safeCall(func, ...)
    local success, result = pcall(func, ...)
    if not success then
        warn("⚠️ SafeCall Error: " .. tostring(result))
        return false, result
    end
    return true, result
end

local function randomWait(min, max)
    local waitTime = math.random(min * 100, max * 100) / 100
    task.wait(waitTime)
end

local function log(message)
    print("🤖 [AutoFarm] " .. message)
end

-- 🧍 Character Management
local function waitForCharacter()
    local timeout = 30
    local startTime = tick()
    
    while (tick() - startTime) < timeout do
        if LocalPlayer.Character and 
           LocalPlayer.Character:FindFirstChild("HumanoidRootPart") and 
           LocalPlayer.Character:FindFirstChild("Humanoid") then
            
            local humanoid = LocalPlayer.Character.Humanoid
            if humanoid.Health > 0 then
                return LocalPlayer.Character.HumanoidRootPart
            end
        end
        
        if LocalPlayer.CharacterAdded then
            LocalPlayer.CharacterAdded:Wait()
        else
            task.wait(0.5)
        end
    end
    
    warn("❌ Character timeout after " .. timeout .. " seconds")
    return nil
end

local function isAlive()
    local character = LocalPlayer.Character
    return character and 
           character:FindFirstChild("Humanoid") and 
           character.Humanoid.Health > 0
end

local function isInDungeon()
    local HRP = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not HRP then return false end
    return (HRP.Position - CONFIG.dungeonPos).Magnitude < CONFIG.dungeonRadius
end

-- 🌀 Movement System
local activeTween
local teleportFailCount = 0

local function directTeleport(targetCFrame)
    local HRP = waitForCharacter()
    if not HRP then return false end
    
    local success = safeCall(function()
        HRP.CFrame = targetCFrame
    end)
    
    if success then
        task.wait(0.5) -- Wait for position to stabilize
        local distance = (HRP.Position - targetCFrame.Position).Magnitude
        if distance < 10 then
            log("🚀 Direct teleport successful")
            return true
        end
    end
    
    warn("❌ Direct teleport failed")
    return false
end

local function teleportTo(targetCFrame)
    if not isAlive() then return false end
    
    local HRP = waitForCharacter()
    if not HRP then return false end
    
    -- 🆘 Fallback to direct teleport if too many tween failures
    if teleportFailCount >= 3 then
        log("⚠️ Too many tween failures, using direct teleport")
        local success = directTeleport(targetCFrame)
        if success then
            teleportFailCount = 0 -- Reset counter on success
        end
        return success
    end
    
    -- Cancel existing tween
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    
    local distance = (HRP.Position - targetCFrame.Position).Magnitude
    local tweenTime = math.min(distance / 250, 8) -- Max 8 seconds
    
    local success, tween = safeCall(function()
        return TweenService:Create(
            HRP,
            TweenInfo.new(tweenTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
            {CFrame = targetCFrame}
        )
    end)
    
    if not success then 
        teleportFailCount = teleportFailCount + 1
        return directTeleport(targetCFrame)
    end
    
    activeTween = tween
    tween:Play()
    
    -- Wait for completion with timeout
    local completed = false
    local connection
    connection = tween.Completed:Connect(function()
        completed = true
        if connection then connection:Disconnect() end
    end)
    
    local waitStart = tick()
    while not completed and (tick() - waitStart) < tweenTime + 2 do
        task.wait(0.1)
        if not isAlive() then break end
    end
    
    if connection then connection:Disconnect() end
    activeTween = nil
    
    -- Verify teleport success
    if isAlive() and HRP.Parent then
        local finalDistance = (HRP.Position - targetCFrame.Position).Magnitude
        if finalDistance < 10 then
            log("✅ Teleport successful (distance: " .. math.floor(finalDistance) .. ")")
            teleportFailCount = 0 -- Reset counter on success
            return true
        end
    end
    
    warn("⚠️ Teleport failed, attempting direct teleport")
    teleportFailCount = teleportFailCount + 1
    return directTeleport(targetCFrame)
end

-- 🔍 Dungeon Circle Detection
local function findDungeonCircle()
    -- Try multiple detection methods
    local detectionMethods = {
        -- Method 1: Find by name patterns
        function()
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj.Name:lower():find("dungeon") and obj.Name:lower():find("circle") then
                    if obj:IsA("Part") or obj:IsA("Model") then
                        local pos = obj:IsA("Model") and obj.PrimaryPart and obj.PrimaryPart.Position or obj.Position
                        if pos then
                            return CFrame.new(pos) + Vector3.new(0, 5, 0)
                        end
                    end
                end
            end
        end,
        
        -- Method 2: Find by ClickDetector or ProximityPrompt
        function()
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj:IsA("ClickDetector") or obj:IsA("ProximityPrompt") then
                    local parent = obj.Parent
                    if parent and parent.Name:lower():find("dungeon") then
                        local pos = parent:IsA("Model") and parent.PrimaryPart and parent.PrimaryPart.Position or parent.Position
                        if pos then
                            return CFrame.new(pos) + Vector3.new(0, 5, 0)
                        end
                    end
                end
            end
        end,
        
        -- Method 3: Find by TeleportPart or similar
        function()
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj:IsA("Part") and (obj.Name:lower():find("teleport") or obj.Name:lower():find("portal")) then
                    local pos = obj.Position
                    -- Check if near our expected dungeon area
                    if (pos - CONFIG.dungeonCircleCFrame.Position).Magnitude < 100 then
                        return CFrame.new(pos) + Vector3.new(0, 5, 0)
                    end
                end
            end
        end
    }
    
    -- Try each detection method
    for i, method in ipairs(detectionMethods) do
        local success, result = pcall(method)
        if success and result then
            log("📍 Found dungeon circle using method " .. i .. " at: " .. tostring(result.Position))
            return result
        end
    end
    
    -- 🆘 Fallback: Allow user to specify custom position
    if CONFIG.customDungeonCircle then
        log("📍 Using custom dungeon circle position")
        return CONFIG.customDungeonCircle
    end
    
    -- Final fallback to default position
    warn("⚠️ All detection methods failed, using default position")
    log("💡 TIP: Set CONFIG.customDungeonCircle if default position doesn't work")
    return CONFIG.dungeonCircleCFrame
end

-- ⚔️ Combat System
local function sendInput(inputType, key, state)
    local success = safeCall(function()
        if inputType == "key" then
            VirtualInputManager:SendKeyEvent(state, key, false, game)
        elseif inputType == "mouse" then
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, state, game, 0)
        end
    end)
    return success
end

local function performClick()
    sendInput("mouse", nil, true)
    randomWait(0.02, 0.05)
    sendInput("mouse", nil, false)
end

local function performSpamClick(count)
    count = count or 5
    for i = 1, count do
        performClick()
        -- 🛡️ Increased random delay to avoid anti-cheat
        randomWait(0.2, 0.4)
    end
    randomWait(1.8, 3.0) -- Longer pause after spam
end

local function pressKey(key)
    sendInput("key", key, true)
    randomWait(0.05, 0.12)
    sendInput("key", key, false)
    -- 🛡️ Increased delay after key press
    randomWait(0.3, 0.6)
end

-- 🎒 Tool Management
local function getToolsInBackpack()
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return {} end
    
    local tools = {}
    for _, item in pairs(backpack:GetChildren()) do
        if item:IsA("Tool") then
            table.insert(tools, item)
        end
    end
    return tools
end

local function equipToolBySlot(slot)
    if not isAlive() then return false end
    
    local tools = getToolsInBackpack()
    if not tools[slot] then
        warn("⚠️ No tool found at slot " .. slot)
        return false
    end
    
    local tool = tools[slot]
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    
    -- 🔍 Kiểm tra tool còn valid không
    if not tool.Parent or tool.Parent ~= backpack or not tool:IsDescendantOf(backpack) then
        warn("⚠️ Tool is invalid or not in backpack: " .. tool.Name)
        return false
    end
    
    local success = safeCall(function()
        LocalPlayer.Character.Humanoid:EquipTool(tool)
    end)
    
    if success then
        -- Verify tool was actually equipped
        task.wait(0.1)
        local equippedTool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if equippedTool and equippedTool.Name == tool.Name then
            randomWait(0.2, 0.4)
            log("🔧 Equipped tool: " .. tool.Name)
            return true
        else
            warn("⚠️ Tool equip verification failed")
            return false
        end
    end
    return false
end

local function equipToolByName(toolName)
    if not isAlive() then return false end
    
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return false end
    
    local tool = backpack:FindFirstChild(toolName)
    if not tool then
        warn("⚠️ Tool not found: " .. toolName)
        return false
    end
    
    -- 🔍 Kiểm tra tool còn valid không
    if not tool.Parent or tool.Parent ~= backpack or not tool:IsDescendantOf(backpack) then
        warn("⚠️ Tool is invalid or not in backpack: " .. toolName)
        return false
    end
    
    local success = safeCall(function()
        LocalPlayer.Character.Humanoid:EquipTool(tool)
    end)
    
    if success then
        -- Verify tool was actually equipped
        task.wait(0.1)
        local equippedTool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if equippedTool and equippedTool.Name == toolName then
            randomWait(0.2, 0.4)
            log("🔧 Equipped tool: " .. toolName)
            return true
        else
            warn("⚠️ Tool equip verification failed")
            return false
        end
    end
    return false
end

-- 👹 Enemy Detection (FIXED)
local function isValidEnemy(obj)
    if not obj or not obj:IsA("Model") then return false end
    if not obj:FindFirstChild("Humanoid") or not obj:FindFirstChild("HumanoidRootPart") then return false end
    
    -- Exclude players
    if Players:GetPlayerFromCharacter(obj) then return false end
    
    -- Exclude pets and NPCs
    if obj.Name:lower():find("pet") or obj.Name:lower():find("npc") then return false end
    
    -- Check if it's actually an enemy/monster
    local humanoid = obj.Humanoid
    if humanoid.Health <= 0 then return false end
    
    -- Additional checks for enemy identification
    local validEnemyNames = {"Boss", "Monster", "Enemy", "Bandit", "Marine", "Pirate"}
    local isEnemy = false
    
    for _, enemyType in pairs(validEnemyNames) do
        if obj.Name:find(enemyType) then
            isEnemy = true
            break
        end
    end
    
    -- If name doesn't match, check if it has enemy-like properties
    if not isEnemy then
        -- Check if it's in a specific folder or has enemy tags
        local parent = obj.Parent
        if parent and (parent.Name:find("Enemy") or parent.Name:find("Monster") or parent.Name:find("Boss")) then
            isEnemy = true
        end
    end
    
    return isEnemy
end

local function getEnemiesInDungeon()
    if not isInDungeon() then return {} end
    
    local enemies = {}
    local searchStart = tick()
    
    for _, obj in pairs(workspace:GetDescendants()) do
        if tick() - searchStart > 5 then break end -- Timeout enemy search
        
        if isValidEnemy(obj) then
            local enemyPos = obj.HumanoidRootPart.Position
            local distanceFromDungeon = (enemyPos - CONFIG.dungeonPos).Magnitude
            
            -- Only include enemies within dungeon area
            if distanceFromDungeon < CONFIG.dungeonRadius then
                table.insert(enemies, obj)
            end
        end
    end
    
    return enemies
end

-- 🗡️ Combat Actions
local function attackEnemy(enemy)
    if not enemy or not enemy.Parent then return false end
    if not isAlive() then return false end
    
    local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
    if not enemyRoot then return false end
    
    local HRP = waitForCharacter()
    if not HRP then return false end
    
    -- Position near enemy
    local attackPosition = enemyRoot.CFrame + Vector3.new(
        math.random(-5, 5),
        math.random(2, 8),
        math.random(-5, 5)
    )
    
    HRP.CFrame = attackPosition
    randomWait(0.1, 0.2)
    
    -- Combat sequence
    if equipToolBySlot(1) then -- Devil Fruit
        pressKey(Enum.KeyCode.Z)
        randomWait(0.3, 0.5)
    end
    
    if equipToolBySlot(2) then -- Sword
        pressKey(Enum.KeyCode.Z)
        randomWait(0.2, 0.3)
        performSpamClick(math.random(3, 7))
    end
    
    -- Use fruit ability periodically
    if tick() - GameState.lastFruitUse > 20 then
        if equipToolBySlot(1) then
            pressKey(Enum.KeyCode.Z)
            GameState.lastFruitUse = tick()
        end
    end
    
    return true
end

-- 🏰 Dungeon Farming Logic
local function clearFloor(floorNumber)
    log("⚔️ Starting floor " .. floorNumber)
    GameState.currentFloor = floorNumber
    
    local floorStartTime = tick()
    local enemiesKilledThisFloor = 0
    
    while (tick() - floorStartTime) < CONFIG.floorTimeout do
        if not isAlive() then
            warn("💀 Died during floor " .. floorNumber)
            return false
        end
        
        if not isInDungeon() then
            warn("⚠️ Not in dungeon anymore")
            return false
        end
        
        local enemies = getEnemiesInDungeon()
        
        if #enemies == 0 then
            log("✅ Floor " .. floorNumber .. " cleared! Enemies killed: " .. enemiesKilledThisFloor)
            randomWait(2, 4)
            return true
        end
        
        -- Attack enemies
        for i, enemy in pairs(enemies) do
            if not enemy.Parent then continue end
            
            local success = attackEnemy(enemy)
            if success then
                enemiesKilledThisFloor = enemiesKilledThisFloor + 1
                GameState.enemiesKilled = GameState.enemiesKilled + 1
            end
            
            randomWait(0.2, 0.5)
            
            -- Break if too many enemies (performance)
            if i >= 5 then break end
        end
        
        randomWait(1, 2)
    end
    
    warn("⏰ Floor " .. floorNumber .. " timeout after " .. CONFIG.floorTimeout .. " seconds")
    return false
end

local function farmDungeon()
    if not isInDungeon() then
        warn("❌ Not in dungeon, cannot farm")
        return false
    end
    
    log("🏰 Starting dungeon farm (5 floors)")
    GameState.currentFloor = 0
    GameState.enemiesKilled = 0
    
    for floor = 1, CONFIG.maxFloors do
        if not GameState.isRunning then
            log("⏹️ Farming stopped by user")
            return false
        end
        
        local success = clearFloor(floor)
        if not success then
            warn("❌ Failed to clear floor " .. floor)
            return false
        end
        
        -- Wait between floors
        if floor < CONFIG.maxFloors then
            randomWait(3, 5)
        end
    end
    
    log("🏆 Dungeon completed! Total enemies killed: " .. GameState.enemiesKilled)
    return true
end

-- 🎨 UI System
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFarmUI_Fixed"
ScreenGui.Parent = CoreGui

-- Main toggle button
local ToggleButton = Instance.new("TextButton")
ToggleButton.Name = "ToggleButton"
ToggleButton.Size = UDim2.new(0, 140, 0, 45)
ToggleButton.Position = UDim2.new(0, 10, 0, 10)
ToggleButton.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
ToggleButton.BorderSizePixel = 0
ToggleButton.TextColor3 = Color3.new(1, 1, 1)
ToggleButton.Font = Enum.Font.GothamBold
ToggleButton.TextSize = 14
ToggleButton.Text = "🤖 AutoFarm: OFF"
ToggleButton.Parent = ScreenGui

-- Add rounded corners
local Corner1 = Instance.new("UICorner")
Corner1.CornerRadius = UDim.new(0, 8)
Corner1.Parent = ToggleButton

-- Status display
local StatusFrame = Instance.new("Frame")
StatusFrame.Name = "StatusFrame"
StatusFrame.Size = UDim2.new(0, 280, 0, 100)
StatusFrame.Position = UDim2.new(0, 160, 0, 10)
StatusFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
StatusFrame.BorderSizePixel = 0
StatusFrame.BackgroundTransparency = 0.1
StatusFrame.Parent = ScreenGui

local Corner2 = Instance.new("UICorner")
Corner2.CornerRadius = UDim.new(0, 8)
Corner2.Parent = StatusFrame

local StatusLabel = Instance.new("TextLabel")
StatusLabel.Name = "StatusLabel"
StatusLabel.Size = UDim2.new(1, -10, 1, -10)
StatusLabel.Position = UDim2.new(0, 5, 0, 5)
StatusLabel.BackgroundTransparency = 1
StatusLabel.TextColor3 = Color3.new(1, 1, 1)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 12
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
StatusLabel.Text = "Status: Standby\nFloor: 0/5\nEnemies Killed: 0\nLocation: Outside Dungeon"
StatusLabel.Parent = StatusFrame

-- 🎮 UI Event Handlers
local function updateUI()
    local locationText = isInDungeon() and "Inside Dungeon" or "Outside Dungeon"
    local statusText = GameState.isRunning and "FARMING" or "STANDBY"
    
    StatusLabel.Text = string.format(
        "Status: %s\nFloor: %d/%d\nEnemies Killed: %d\nLocation: %s",
        statusText,
        GameState.currentFloor,
        CONFIG.maxFloors,
        GameState.enemiesKilled,
        locationText
    )
    
    ToggleButton.Text = GameState.isRunning and "🤖 AutoFarm: ON" or "🤖 AutoFarm: OFF"
    ToggleButton.BackgroundColor3 = GameState.isRunning and Color3.fromRGB(50, 220, 50) or Color3.fromRGB(220, 50, 50)
end

ToggleButton.MouseButton1Click:Connect(function()
    GameState.isRunning = not GameState.isRunning
    log(GameState.isRunning and "🟢 AutoFarm started" or "🔴 AutoFarm stopped")
    updateUI()
end)

-- 🚀 Main Loop
local function mainLoop()
    spawn(function()
        while true do
            updateUI()
            
            if GameState.isRunning then
                if not isAlive() then
                    log("💀 Waiting for respawn...")
                    repeat 
                        task.wait(1) 
                        updateUI()
                    until isAlive()
                    
                    log("✨ Respawned, waiting for character load...")
                    task.wait(CONFIG.respawnWaitTime)
                end
                
                if not isInDungeon() then
                    log("🌀 Teleporting to dungeon...")
                    local dungeonCFrame = findDungeonCircle()
                    
                    if teleportTo(dungeonCFrame) then
                        log("⏳ Waiting for dungeon entry...")
                        
                        local waitTime = 0
                        while not isInDungeon() and waitTime < 30 do
                            task.wait(1)
                            waitTime = waitTime + 1
                            updateUI()
                        end
                        
                        if not isInDungeon() then
                            warn("❌ Failed to enter dungeon after 30s")
                            randomWait(5, 10)
                            continue
                        end
                    else
                        warn("❌ Failed to teleport to dungeon")
                        randomWait(5, 10)
                        continue
                    end
                end
                
                -- Farm dungeon
                local farmSuccess = farmDungeon()
                
                if farmSuccess then
                    log("🎉 Dungeon farm completed successfully!")
                else
                    warn("⚠️ Dungeon farm failed or interrupted")
                end
                
                -- Return to dungeon circle
                log("🏠 Returning to dungeon entrance...")
                teleportTo(findDungeonCircle())
                
                -- Cooldown
                log("💤 Cooldown for " .. CONFIG.dungeonCooldown .. " seconds...")
                for i = CONFIG.dungeonCooldown, 1, -1 do
                    if not GameState.isRunning then break end
                    task.wait(1)
                    updateUI()
                end
                
            else
                task.wait(1)
            end
        end
    end)
end

-- 🏁 Initialize
log("🎮 AutoFarm Module Loaded Successfully!")
log("📋 Features: Anti-Detection, Safe Enemy Detection, Error Handling")
log("🎯 Click the toggle button to start/stop farming")

mainLoop()

-- 📤 Module Export
return {
    Start = function()
        GameState.isRunning = true
        updateUI()
    end,
    
    Stop = function()
        GameState.isRunning = false
        updateUI()
    end,
    
    GetStatus = function()
        return GameState
    end,
    
    Config = CONFIG
}
