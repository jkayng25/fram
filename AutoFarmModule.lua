-- 📦 AutoFarmModule.lua (ENHANCED VERSION): Tự động farm 5 tầng dungeon trong King Legacy
-- ✅ FIXED: Smooth teleport, High attack position, Direct targeting

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
    floorTimeout = 120,
    respawnWaitTime = 10,
    dungeonCooldown = 25,
    
    -- 🎯 Combat settings - BAY CAO HỠN
    attackDistance = 12, -- Khoảng cách tấn công
    attackHeight = 25, -- Bay cao hơn (tăng từ 2 lên 25)
    targetSwitchDelay = 3,
    directAttack = true, -- Tấn công trực tiếp
    
    -- 🌀 Smooth movement settings
    smoothTeleport = true, -- Bật teleport mượt
    tweenSpeed = 300, -- Tốc độ tween (cao hơn = nhanh hơn)
    maxTweenTime = 6, -- Thời gian tween tối đa
    
    -- 🆘 Custom dungeon circle position
    customDungeonCircle = nil,
}

-- 🎮 Trạng thái game
local GameState = {
    isRunning = false,
    currentFloor = 0,
    enemiesKilled = 0,
    lastFruitUse = 0,
    lastStatus = "Standby",
    currentTarget = nil,
    targetLockTime = 0,
    lastTargetHealth = 0,
    isMoving = false, -- Trạng thái di chuyển
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

-- 🌀 IMPROVED Movement System - SMOOTH TELEPORT
local activeTween
local bodyVelocity
local bodyPosition

local function stopMovement()
    if activeTween then
        activeTween:Cancel()
        activeTween = nil
    end
    
    if bodyVelocity then
        bodyVelocity:Destroy()
        bodyVelocity = nil
    end
    
    if bodyPosition then
        bodyPosition:Destroy()
        bodyPosition = nil
    end
    
    GameState.isMoving = false
end

local function smoothTeleportTo(targetCFrame)
    if not isAlive() then return false end
    
    local HRP = waitForCharacter()
    if not HRP then return false end
    
    -- Stop any existing movement
    stopMovement()
    
    local distance = (HRP.Position - targetCFrame.Position).Magnitude
    
    -- 🚀 Instant teleport for very long distances
    if distance > 2000 then
        log("🚀 Long distance teleport")
        GameState.isMoving = true
        safeCall(function()
            HRP.CFrame = targetCFrame
        end)
        task.wait(0.5)
        GameState.isMoving = false
        return true
    end
    
    -- 🌀 Smooth tween for shorter distances
    if CONFIG.smoothTeleport then
        local tweenTime = math.min(distance / CONFIG.tweenSpeed, CONFIG.maxTweenTime)
        
        local success, tween = safeCall(function()
            return TweenService:Create(
                HRP,
                TweenInfo.new(
                    tweenTime, 
                    Enum.EasingStyle.Quad, -- Smooth easing
                    Enum.EasingDirection.Out
                ),
                {CFrame = targetCFrame}
            )
        end)
        
        if success then
            activeTween = tween
            GameState.isMoving = true
            
            tween:Play()
            
            -- Wait for completion
            local completed = false
            local connection
            connection = tween.Completed:Connect(function()
                completed = true
                GameState.isMoving = false
                if connection then connection:Disconnect() end
            end)
            
            -- Wait with timeout
            local waitStart = tick()
            while not completed and (tick() - waitStart) < tweenTime + 1 do
                if not isAlive() then break end
                task.wait(0.05) -- Smaller wait for smoother experience
            end
            
            if connection then connection:Disconnect() end
            stopMovement()
            
            return true
        end
    end
    
    -- 🆘 Fallback to direct teleport
    log("🆘 Using direct teleport")
    GameState.isMoving = true
    safeCall(function()
        HRP.CFrame = targetCFrame
    end)
    task.wait(0.2)
    GameState.isMoving = false
    return true
end

-- 🔍 Dungeon Circle Detection
local function findDungeonCircle()
    local detectionMethods = {
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
        
        function()
            for _, obj in pairs(workspace:GetDescendants()) do
                if obj:IsA("Part") and (obj.Name:lower():find("teleport") or obj.Name:lower():find("portal")) then
                    local pos = obj.Position
                    if (pos - CONFIG.dungeonCircleCFrame.Position).Magnitude < 100 then
                        return CFrame.new(pos) + Vector3.new(0, 5, 0)
                    end
                end
            end
        end
    }
    
    for i, method in ipairs(detectionMethods) do
        local success, result = pcall(method)
        if success and result then
            log("📍 Found dungeon circle using method " .. i)
            return result
        end
    end
    
    if CONFIG.customDungeonCircle then
        return CONFIG.customDungeonCircle
    end
    
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
        randomWait(0.15, 0.3)
    end
    randomWait(1.5, 2.5)
end

local function pressKey(key)
    sendInput("key", key, true)
    randomWait(0.05, 0.1)
    sendInput("key", key, false)
    randomWait(0.2, 0.4)
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
    if not tools[slot] then return false end
    
    local tool = tools[slot]
    local backpack = LocalPlayer:FindFirstChild("Backpack")
    
    if not tool.Parent or tool.Parent ~= backpack then
        return false
    end
    
    local success = safeCall(function()
        LocalPlayer.Character.Humanoid:EquipTool(tool)
    end)
    
    if success then
        task.wait(0.1)
        local equippedTool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if equippedTool and equippedTool.Name == tool.Name then
            randomWait(0.1, 0.2)
            return true
        end
    end
    return false
end

-- 👹 Enemy Detection & Management
local function isValidEnemy(obj)
    if not obj or not obj:IsA("Model") then return false end
    if not obj:FindFirstChild("Humanoid") or not obj:FindFirstChild("HumanoidRootPart") then return false end
    
    if Players:GetPlayerFromCharacter(obj) then return false end
    if obj.Name:lower():find("pet") or obj.Name:lower():find("npc") then return false end
    
    local humanoid = obj.Humanoid
    if humanoid.Health <= 0 then return false end
    
    local validEnemyNames = {"Boss", "Monster", "Enemy", "Bandit", "Marine", "Pirate", "Mob"}
    for _, enemyType in pairs(validEnemyNames) do
        if obj.Name:find(enemyType) then
            return true
        end
    end
    
    local parent = obj.Parent
    if parent and (parent.Name:find("Enemy") or parent.Name:find("Monster") or parent.Name:find("Boss")) then
        return true
    end
    
    return false
end

local function isValidTarget(enemy)
    if not enemy or not enemy.Parent then return false end
    if not enemy:FindFirstChild("Humanoid") or not enemy:FindFirstChild("HumanoidRootPart") then return false end
    if enemy.Humanoid.Health <= 0 then return false end
    
    local enemyPos = enemy.HumanoidRootPart.Position
    local distanceFromDungeon = (enemyPos - CONFIG.dungeonPos).Magnitude
    return distanceFromDungeon < CONFIG.dungeonRadius
end

local function getEnemiesInDungeon()
    if not isInDungeon() then return {} end
    
    local enemies = {}
    for _, obj in pairs(workspace:GetDescendants()) do
        if isValidEnemy(obj) then
            local enemyPos = obj.HumanoidRootPart.Position
            local distanceFromDungeon = (enemyPos - CONFIG.dungeonPos).Magnitude
            
            if distanceFromDungeon < CONFIG.dungeonRadius then
                table.insert(enemies, obj)
            end
        end
    end
    
    return enemies
end

local function selectBestTarget(enemies)
    if not enemies or #enemies == 0 then return nil end
    
    local HRP = waitForCharacter()
    if not HRP then return nil end
    
    local bestTarget = nil
    local closestDistance = math.huge
    
    for _, enemy in pairs(enemies) do
        if isValidTarget(enemy) then
            local distance = (HRP.Position - enemy.HumanoidRootPart.Position).Magnitude
            if distance < closestDistance then
                closestDistance = distance
                bestTarget = enemy
            end
        end
    end
    
    return bestTarget
end

-- 🗡️ ENHANCED Combat Actions - BAY CAO & DIRECT ATTACK
local function getOptimalAttackPosition(enemy)
    if not enemy or not enemy:FindFirstChild("HumanoidRootPart") then return nil end
    
    local enemyRoot = enemy.HumanoidRootPart
    local enemyPos = enemyRoot.Position
    
    -- 🎯 DIRECT ATTACK - Bay thẳng lên trên đầu quái
    if CONFIG.directAttack then
        local attackPosition = enemyPos + Vector3.new(0, CONFIG.attackHeight, 0)
        return CFrame.new(attackPosition, enemyPos)
    end
    
    -- 🎯 Alternative: Attack from random position around enemy
    local attackOffset = Vector3.new(
        math.random(-CONFIG.attackDistance, CONFIG.attackDistance),
        CONFIG.attackHeight,
        math.random(-CONFIG.attackDistance, CONFIG.attackDistance)
    )
    
    local attackPosition = enemyPos + attackOffset
    return CFrame.new(attackPosition, enemyPos)
end

local function attackEnemy(enemy)
    if not enemy or not enemy.Parent then return false end
    if not isAlive() then return false end
    
    local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
    if not enemyRoot then return false end
    
    local HRP = waitForCharacter()
    if not HRP then return false end
    
    -- 🎯 Get optimal attack position (BAY CAO TRÊN ĐẦU)
    local attackCFrame = getOptimalAttackPosition(enemy)
    if not attackCFrame then return false end
    
    -- 🚀 Smooth move to attack position
    local moveSuccess = smoothTeleportTo(attackCFrame)
    if not moveSuccess then return false end
    
    -- Wait for movement to complete
    while GameState.isMoving do
        task.wait(0.1)
    end
    
    randomWait(0.1, 0.2)
    
    -- 🗡️ Combat sequence
    if equipToolBySlot(1) then -- Devil Fruit
        pressKey(Enum.KeyCode.Z)
        randomWait(0.2, 0.3)
    end
    
    if equipToolBySlot(2) then -- Sword
        pressKey(Enum.KeyCode.Z)
        randomWait(0.1, 0.2)
        performSpamClick(math.random(4, 8))
    end
    
    -- 🍎 Use fruit ability periodically
    if tick() - GameState.lastFruitUse > 15 then
        if equipToolBySlot(1) then
            pressKey(Enum.KeyCode.Z)
            GameState.lastFruitUse = tick()
        end
    end
    
    return true
end

-- 🏰 Enhanced Floor Clearing
local function clearFloor(floorNumber)
    log("⚔️ Starting floor " .. floorNumber)
    GameState.currentFloor = floorNumber
    GameState.currentTarget = nil
    
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
        
        -- 🎯 Target management
        if not GameState.currentTarget or not isValidTarget(GameState.currentTarget) then
            local enemies = getEnemiesInDungeon()
            
            if #enemies == 0 then
                log("✅ Floor " .. floorNumber .. " cleared! Enemies killed: " .. enemiesKilledThisFloor)
                randomWait(2, 3)
                return true
            end
            
            GameState.currentTarget = selectBestTarget(enemies)
            if GameState.currentTarget then
                GameState.targetLockTime = tick()
                GameState.lastTargetHealth = GameState.currentTarget.Humanoid.Health
                log("🎯 New target: " .. GameState.currentTarget.Name .. " (HP: " .. GameState.lastTargetHealth .. ")")
            end
        end
        
        -- 🗡️ Attack current target
        if GameState.currentTarget and isValidTarget(GameState.currentTarget) then
            local success = attackEnemy(GameState.currentTarget)
            if success then
                local currentHealth = GameState.currentTarget.Humanoid.Health
                
                if currentHealth < GameState.lastTargetHealth then
                    GameState.lastTargetHealth = currentHealth
                    GameState.targetLockTime = tick()
                end
                
                if currentHealth <= 0 then
                    enemiesKilledThisFloor = enemiesKilledThisFloor + 1
                    GameState.enemiesKilled = GameState.enemiesKilled + 1
                    log("💀 Target killed! Total: " .. GameState.enemiesKilled)
                    GameState.currentTarget = nil
                end
            end
            
            -- 🔄 Switch target if stuck
            if tick() - GameState.targetLockTime > CONFIG.targetSwitchDelay then
                log("🔄 Switching target")
                GameState.currentTarget = nil
            end
        end
        
        randomWait(0.3, 0.7)
    end
    
    warn("⏰ Floor " .. floorNumber .. " timeout")
    return false
end

local function farmDungeon()
    if not isInDungeon() then
        warn("❌ Not in dungeon")
        return false
    end
    
    log("🏰 Starting dungeon farm")
    GameState.currentFloor = 0
    GameState.enemiesKilled = 0
    GameState.currentTarget = nil
    
    for floor = 1, CONFIG.maxFloors do
        if not GameState.isRunning then
            log("⏹️ Farming stopped")
            return false
        end
        
        local success = clearFloor(floor)
        if not success then
            warn("❌ Failed to clear floor " .. floor)
            return false
        end
        
        if floor < CONFIG.maxFloors then
            randomWait(2, 4)
        end
    end
    
    log("🏆 Dungeon completed! Total enemies: " .. GameState.enemiesKilled)
    return true
end

-- 🎨 UI System
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AutoFarmUI_Enhanced"
ScreenGui.Parent = CoreGui

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

local Corner1 = Instance.new("UICorner")
Corner1.CornerRadius = UDim.new(0, 8)
Corner1.Parent = ToggleButton

local StatusFrame = Instance.new("Frame")
StatusFrame.Name = "StatusFrame"
StatusFrame.Size = UDim2.new(0, 350, 0, 130)
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
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.TextYAlignment = Enum.TextYAlignment.Top
StatusLabel.Text = "Status: Standby"
StatusLabel.Parent = StatusFrame

-- 🎮 UI Update
local function updateUI()
    local locationText = isInDungeon() and "Inside Dungeon" or "Outside Dungeon"
    local statusText = GameState.isRunning and "FARMING" or "STANDBY"
    local targetText = GameState.currentTarget and GameState.currentTarget.Name or "None"
    local targetHealth = GameState.currentTarget and math.floor(GameState.currentTarget.Humanoid.Health) or 0
    local movingText = GameState.isMoving and "Moving" or "Idle"
    
    if GameState.currentTarget and targetHealth > 0 then
        targetText = targetText .. " (HP: " .. targetHealth .. ")"
    end
    
    StatusLabel.Text = string.format(
        "Status: %s\nFloor: %d/%d\nEnemies Killed: %d\nCurrent Target: %s\nLocation: %s\nMovement: %s",
        statusText,
        GameState.currentFloor,
        CONFIG.maxFloors,
        GameState.enemiesKilled,
        targetText,
        locationText,
        movingText
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
                    stopMovement()
                    GameState.currentTarget = nil
                    repeat 
                        task.wait(1) 
                        updateUI()
                    until isAlive()
                    
                    log("✨ Respawned")
                    task.wait(CONFIG.respawnWaitTime)
                end
                
                if not isInDungeon() then
                    log("🌀 Teleporting to dungeon...")
                    GameState.currentTarget = nil
                    local dungeonCFrame = findDungeonCircle()
                    
                    if smoothTeleportTo(dungeonCFrame) then
                        log("⏳ Waiting for dungeon entry...")
                        
                        local waitTime = 0
                        while not isInDungeon() and waitTime < 30 do
                            task.wait(1)
                            waitTime = waitTime + 1
                            updateUI()
                        end
                        
                        if not isInDungeon() then
                            warn("❌ Failed to enter dungeon")
                            randomWait(5, 10)
                            continue
                        end
                    else
                        warn("❌ Failed to teleport to dungeon")
                        randomWait(5, 10)
                        continue
                    end
                end
                
                local farmSuccess = farmDungeon()
                
                if farmSuccess then
                    log("🎉 Dungeon completed!")
                else
                    warn("⚠️ Dungeon farm failed")
                end
                
                log("🏠 Returning to entrance...")
                GameState.currentTarget = nil
                smoothTeleportTo(findDungeonCircle())
                
                log("💤 Cooldown: " .. CONFIG.dungeonCooldown .. "s")
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
log("🎮 AutoFarm Enhanced - SMOOTH & HIGH ATTACK!")
log("✨ NEW FEATURES:")
log("   🚀 Smooth teleport movement")
log("   🎯 High attack position (25 units above enemy)")
log("   🔄 Direct targeting system")
log("   ⚡ Improved combat flow")
log("📋 Click toggle to start!")

mainLoop()

-- 📤 Module Export
return {
    Start = function()
        GameState.isRunning = true
        updateUI()
    end,
    
    Stop = function()
        GameState.isRunning = false
        stopMovement()
        GameState.currentTarget = nil
        updateUI()
    end,
    
    GetStatus = function()
        return GameState
    end,
    
    Config = CONFIG,
    
    -- 🔧 Advanced controls
    SetAttackHeight = function(height)
        CONFIG.attackHeight = height
        log("🎯 Attack height set to: " .. height)
    end,
    
    SetTweenSpeed = function(speed)
        CONFIG.tweenSpeed = speed
        log("🚀 Tween speed set to: " .. speed)
    end,
    
    ToggleSmoothTeleport = function()
        CONFIG.smoothTeleport = not CONFIG.smoothTeleport
        log("🌀 Smooth teleport: " .. (CONFIG.smoothTeleport and "ON" or "OFF"))
    end,
    
    ToggleDirectAttack = function()
        CONFIG.directAttack = not CONFIG.directAttack
        log("🎯 Direct attack: " .. (CONFIG.directAttack and "ON" or "OFF"))
    end
}
