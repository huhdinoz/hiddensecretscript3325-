wait()
-- Configuration Section
local host = Config["host"] or getgenv().Config["host"]
local tar = Config["tar"] or getgenv().Config["tar"]
local accounts = Config["accounts"] or getgenv().Config["accounts"]
local ROBLOSECURITY = Config["ROBLOSECURITY"] or getgenv().Config["ROBLOSECURITY"]
local maxFollowDistance = Config["maxFollowDistance"] or getgenv().Config["maxFollowDistance"]
local enableWebhookLogs = Config["enableWebhookLogs"] or getgenv().Config["enableWebhookLogs"]
local webhookURL = Config["webhookURL"] or getgenv().Config["webhookURL"]
local webhookUsername = Config["webhookUsername"] or getgenv().Config["webhookUsername"]
local enableCommandCorrection = Config["enableCommandCorrection"] or getgenv().Config["enableCommandCorrection"]
local correctionThreshold = Config["correctionThreshold"] or getgenv().Config["correctionThreshold"]
local enableOffset = Config["enableOffset"] or getgenv().Config["enableOffset"]

-- Services
local distance = 5
local angle = math.pi  2
local orbitSpeed = 1 -- Default orbit speed
getgenv().isOrbiting = false
local floatHeight = 5 -- Height at which bots will float while orbiting
local TextChatService = game:GetService("TextChatService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local TeleportService = game:GetService("TeleportService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local currentMoveDirection = nil

RunService:Set3dRenderingEnabled(false)

local startTime = tick()
local commands, aliases = {}, {}
local disallowed = false
local model = Players:GetPlayerByUserId(host)
local localPlayer = Players.LocalPlayer

local permissions = {}
permissions[host] = true

local states = {
    ["track"] = false,
    ["shuffle"] = false,
    ["move"] = false,
    ["hostile"] = false,
    ["spin"] = false,
    ["stack"] = false,
}


local bodyPositions = {}
local bodyPosConnection
local hostileRadius = 10 -- Default hostile radius

local function Chat(str)
    str = tostring(str)
    if game:GetService("TextChatService").ChatVersion == Enum.ChatVersion.TextChatService then
        game:GetService("TextChatService").TextChannels.RBXGeneral:SendAsync(str)
    else
        game.ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest:FireServer(str, "All")
    end
end

local function index()
    local found, indexes = {}, 1
    for i, uID in ipairs(accounts) do
        if Players:GetPlayerByUserId(uID) then
            found[indexes] = i
            indexes = indexes + 1
        end
    end
    return found
end

local function stopAllMovements()
    states.track = false
    states.spin = false
    states.stack = false
    states.move = false
    states.circle = false

    currentMoveDirection = nil
    for _, bodyPos in ipairs(bodyPositions) do
        bodyPos:Destroy()
    end
    bodyPositions = {}
    if bodyPosConnection then
        bodyPosConnection:Disconnect()
        bodyPosConnection = nil
    end
end


local function find(name)
    for _, Target in pairs(Players:GetPlayers()) do
        if name:lower() == (Target.Name:lower()):sub(1, #name) or name:lower() == (Target.DisplayName:lower()):sub(1, #name) then
            return Target
        end
    end
    return nil
end

local function getPlayer(name, executor)
    if name == "" then
        return executor
    end

    local player = find(name)
    return player or executor
end

local function getPlayerGroup(name)
    if name == "all" then
        local allPlayers = {}
        for _, player in pairs(Players:GetPlayers()) do
            table.insert(allPlayers, player)
        end
        return allPlayers
    elseif name == "random" then
        local allPlayers = Players:GetPlayers()
        return {allPlayers[math.random(#allPlayers)]}
    else
        local player = find(name)
        if player then
            return {player}
        else
            return nil
        end
    end
end

local function sendWebhookLog(message)
    if enableWebhookLogs and webhookURL ~= "" then
        local payload = HttpService:JSONEncode({
            content = message
        })
        
        local success, response = pcall(function()
            return syn.request({
                Url = webhookURL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = payload
            })
        end)
        
        if not success then
            warn("Failed to send webhook log: " .. tostring(response))
        end
    end
end

local function disable3DRendering()
    RunService:Set3dRenderingEnabled(false)
end

local function returnCommand()
    -- Measure round-trip time in seconds
    local startTime = tick()
    wait() -- Simulate some processing delay
    local roundTripTime = tick() - startTime -- Calculate round-trip time
    
    -- Format the message based on the round-trip time
    local message
    if roundTripTime < 0.01 then
        message = "Return time: Instant!"
    else
        message = string.format("Return time: %.2f seconds", roundTripTime)
    end

    -- Chat the message
    Chat(message)
end

local function rejoinCommand()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
end

local function bringCommand(executor, direction)
    disable3DRendering()
    local found = index()
    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot then
            local offset
            if direction == "left" or direction == "l" then
                offset = CFrame.new(-(i - (#found / 2)) * 2 - 2, 0, 0)
            elseif direction == "right" or direction == "r" then
                offset = CFrame.new((i - (#found / 2)) * 2 + 2, 0, 0)
            elseif direction == "back" or direction == "b" then
                offset = CFrame.new(0, 0, (i - (#found / 2)) * 2 + 2)
            elseif direction == "front" or direction == "f" then
                offset = CFrame.new(0, 0, -(i - (#found / 2)) * 2 - 2)
            else
                offset = CFrame.new(0, 0, -(i - (#found / 2)) * 2 - 2) -- Default to "front" if no direction is specified
            end
            
            bot.Character.HumanoidRootPart.CFrame = executor.Character.HumanoidRootPart.CFrame * offset

            -- Make the bot face the executor for 0.05 seconds
            bot.Character.HumanoidRootPart.CFrame = CFrame.lookAt(bot.Character.HumanoidRootPart.Position, executor.Character.HumanoidRootPart.Position)
            wait(0.05)
        end
    end
end




local function tpCommand(executor, targetName)
    local targetPlayer = getPlayer(targetName, executor)
    if not targetPlayer then
        Chat("Player not found: " .. targetName)
        return
    end

    disable3DRendering()
    local found = index()
    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot then
            TweenService:Create(bot.Character.HumanoidRootPart, TweenInfo.new(0.25, Enum.EasingStyle.Sine), {CFrame = targetPlayer.Character.HumanoidRootPart.CFrame * CFrame.new((i - (#found / 2) - 0.5) * 2, 0, 3)}):Play()
        end
    end
end

local function lineCommand(direction, executor)
    disable3DRendering()

    local found = index()
    if states.shuffle then
        return
    end

    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot then
            local offset
            if direction == "left" or direction == "l" then
                offset = CFrame.new(-(i - (#found / 2)) * 3 - 3, 0, 0)
            elseif direction == "right" or direction == "r" then
                offset = CFrame.new((i - (#found / 2)) * 3 + 3, 0, 0)
            elseif direction == "back" or direction == "b" then
                offset = CFrame.new(0, 0, (i - (#found / 2)) * 3 + 3)
            elseif direction == "front" or direction == "f" then
                offset = CFrame.new(0, 0, -(i - (#found / 2)) * 3 - 3)
            else
                offset = CFrame.new(0, 0, (i - (#found / 2)) * 3 + 3) -- Default to "back" if no direction is specified
            end
            TweenService:Create(bot.Character.HumanoidRootPart, TweenInfo.new(0.25, Enum.EasingStyle.Sine), {CFrame = executor.Character.HumanoidRootPart.CFrame * offset}):Play()
        end
    end
end

local function indexCommand()
    local count = 0
    for _, uID in ipairs(accounts) do
        if Players:GetPlayerByUserId(uID) then
            count = count + 1
        end
    end
    Chat("Managing " .. count .. " accounts.")
end

local function endCommand()
    stopAllMovements() -- Stop all ongoing movements and states
    disallowed = true
    Chat("Account Manager successfully closed.")
end


local function resetCommand()
    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot then
            bot.Character.Humanoid.Health = 0
        end
    end
end

local function sayCommand(...)
    local args = {...}
    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot then
            Chat(table.concat(args, " "))
            break
        end
    end
end

local function followCommand(targetName, executor)
    states.track = true
    local targetPlayer = getPlayer(targetName, executor)
    local found = index()
    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character.HumanoidRootPart then
            coroutine.wrap(function()
                while states.track do
                    local closestPlayer
                    if states.hostile then
                        for _, player in pairs(Players:GetPlayers()) do
                            if player ~= executor and player ~= bot and not table.find(accounts, player.UserId) and (player.Character.HumanoidRootPart.Position - executor.Character.HumanoidRootPart.Position).Magnitude < hostileRadius then
                                closestPlayer = player
                                break
                            end
                        end
                    end
                    local target = closestPlayer or targetPlayer
                    local targetPosition = target.Character.HumanoidRootPart.Position
                    local botPosition = bot.Character.HumanoidRootPart.Position

                    if (botPosition - targetPosition).Magnitude > maxFollowDistance then
                        bot.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -3)
                    else
                        local offset = (target == targetPlayer) and (CFrame.new((i % 3 - 1) * 3, 0, math.floor(i / 3) * 5 + 5)) or CFrame.new(0, 0, 0)
                        local targetCF = target.Character.HumanoidRootPart.CFrame * offset
                        bot.Character.Humanoid:MoveTo(targetCF.Position)

                        if not states.spin then
                            bot.Character.HumanoidRootPart.CFrame = CFrame.lookAt(botPosition, Vector3.new(targetPosition.X, botPosition.Y, targetPosition.Z))
                        end
                    end

                    if states.spin then
                        local bambam = bot.Character.HumanoidRootPart:FindFirstChild("BodyThrust")
                        if not bambam then
                            bambam = Instance.new("BodyThrust")
                            bambam.Parent = bot.Character.HumanoidRootPart
                        end
                        bambam.Force = Vector3.new(500, 0, 500)
                        bambam.Location = bot.Character.HumanoidRootPart.Position
                    end

                    wait(0.1)
                end
            end)()
        end
    end
end



local function unfollowCommand()
    states.track = false
end

local function circleCommand(executor)
    disable3DRendering()
    local radius = 5
    local found = index()
    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character.HumanoidRootPart then
            local angle = (2 * math.pi / #found) * i
            local offset = Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
            TweenService:Create(bot.Character.HumanoidRootPart, TweenInfo.new(0.5, Enum.EasingStyle.Sine), {CFrame = executor.Character.HumanoidRootPart.CFrame * CFrame.new(offset)}):Play()
        end
    end
end


local function followCircleCommand(targetName, executor)
    states.track = true
    local radius = 5
    local targetPlayer = getPlayer(targetName, executor)
    local found = index()
    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character.HumanoidRootPart then
            coroutine.wrap(function()
                while states.track do
                    local closestPlayer
                    if states.hostile then
                        for _, player in pairs(Players:GetPlayers()) do
                            if player ~= executor and player ~= bot and not table.find(accounts, player.UserId) and (player.Character.HumanoidRootPart.Position - executor.Character.HumanoidRootPart.Position).Magnitude < hostileRadius then
                                closestPlayer = player
                                break
                            end
                        end
                    end
                    local target = closestPlayer or targetPlayer
                    local targetPosition = target.Character.HumanoidRootPart.Position
                    local botPosition = bot.Character.HumanoidRootPart.Position

                    -- Check distance and teleport if necessary
                    if (botPosition - targetPosition).Magnitude > maxFollowDistance then
                        bot.Character.HumanoidRootPart.CFrame = target.Character.HumanoidRootPart.CFrame * CFrame.new(0, 0, -3)
                    else
                        local angle = (2 * math.pi / #found) * i
                        local offset = (target == targetPlayer) and Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius) or Vector3.new(0, 0, 0)
                        local targetCF = target.Character.HumanoidRootPart.CFrame * CFrame.new(offset)
                        bot.Character.Humanoid:MoveTo(targetCF.Position)

                        if not states.spin then
                            bot.Character.HumanoidRootPart.CFrame = CFrame.lookAt(botPosition, Vector3.new(targetPosition.X, botPosition.Y, targetPosition.Z))
                        end
                    end

                    if states.spin then
                        local bambam = bot.Character.HumanoidRootPart:FindFirstChild("BodyThrust")
                        if not bambam then
                            bambam = Instance.new("BodyThrust")
                            bambam.Parent = bot.Character.HumanoidRootPart
                        end
                        bambam.Force = Vector3.new(500, 0, 500)
                        bambam.Location = bot.Character.HumanoidRootPart.Position
                    end

                    wait(0.1)
                end
            end)()
        end
    end
end

local function lookAtMeCommand(executor)
    states.track = true
    local found = index()
    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character.HumanoidRootPart then
            coroutine.wrap(function()
                while states.track do
                    local botPosition = bot.Character.HumanoidRootPart.Position
                    local offset = CFrame.new(0, 0, -(i - (#found / 2)) * 3 - 3) -- Position in front of the executor
                    local targetCF = executor.Character.HumanoidRootPart.CFrame * offset
                    bot.Character.Humanoid:MoveTo(targetCF.Position)

                    if not states.spin then
                        bot.Character.HumanoidRootPart.CFrame = CFrame.lookAt(botPosition, executor.Character.HumanoidRootPart.Position)
                    end

                    if states.spin then
                        local bambam = bot.Character.HumanoidRootPart:FindFirstChild("BodyThrust")
                        if not bambam then
                            bambam = Instance.new("BodyThrust")
                            bambam.Parent = bot.Character.HumanoidRootPart
                        end
                        bambam.Force = Vector3.new(500, 0, 500)
                        bambam.Location = bot.Character.HumanoidRootPart.Position
                    end

                    wait(0.1)
                end
            end)()
        end
    end
end


local function jumpCommand()
    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character:FindFirstChildOfClass("Humanoid") then
            bot.Character:FindFirstChildOfClass("Humanoid"):ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end

local function grantPermission(targetName)
    local targetPlayer = find(targetName)
    if targetPlayer then
        if permissions[targetPlayer.UserId] then
            Chat(targetPlayer.Name .. " already has permissions.")
        else
            permissions[targetPlayer.UserId] = true
            Chat("Granted access to " .. targetPlayer.Name)
            sendWebhookLog("Granted access to " .. targetPlayer.Name)
        end
    else
        Chat("Player not found: " .. targetName)
    end
end

local function revokePermission(targetName)
    local targetPlayer = find(targetName)
    if targetPlayer then
        if not permissions[targetPlayer.UserId] then
            Chat(targetPlayer.Name .. " already does not have permissions.")
        else
            permissions[targetPlayer.UserId] = nil
            Chat("Revoked access from " .. targetPlayer.Name)
            sendWebhookLog("Revoked access from " .. targetPlayer.Name)
        end
    else
        Chat("Player not found: " .. targetName)
    end
end

local function spinCommand(speed)
    states.spin = true
    local power = tonumber(speed) or 500

    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character.HumanoidRootPart then
            local bambam = bot.Character.HumanoidRootPart:FindFirstChild("BodyThrust")
            if not bambam then
                bambam = Instance.new("BodyThrust")
                bambam.Parent = bot.Character.HumanoidRootPart
            end
            bambam.Force = Vector3.new(power, 0, power)
            bambam.Location = bot.Character.HumanoidRootPart.Position
            coroutine.wrap(function()
                while states.spin do
                    bot.Character.Head.CanCollide = false
                    bot.Character.UpperTorso.CanCollide = false
                    bot.Character.LowerTorso.CanCollide = false
                    bot.Character.HumanoidRootPart.CanCollide = false
                    bambam.Force = Vector3.new(power, 0, power)
                    wait(0.1)
                end
                bambam:Destroy()
            end)()
        end
    end
end

local function stopSpinCommand()
    states.spin = false
    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character.HumanoidRootPart then
            local bambam = bot.Character.HumanoidRootPart:FindFirstChild("BodyThrust")
            if bambam then
                bambam:Destroy()
            end
        end
    end
end


local function stackCommand(executor)
    disable3DRendering()
    states.stack = true
    coroutine.wrap(function()
        while states.stack do
            local found = index()
            for i, index in ipairs(found) do
                local bot = Players:GetPlayerByUserId(accounts[index])
                if bot and bot.Character and bot.Character.HumanoidRootPart then
                    local offset = CFrame.new(0, i * 5, 0)
                    bot.Character.HumanoidRootPart.CFrame = executor.Character.HumanoidRootPart.CFrame * offset
                    bot.Character.Humanoid.PlatformStand = true  -- Disable physics to handle player collision being off
                end
            end
            wait(0.1)  -- Adjust the frequency of position updates as needed
        end
    end)()
end

local function stopStackCommand()
    states.stack = false
    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character.HumanoidRootPart then
            bot.Character.Humanoid.PlatformStand = false  -- Re-enable physics
        end
    end
end

local function stopMoveCommand()
    states.move = false
    states.orbit = false -- Stop the orbit command
    getgenv().isOrbiting = false -- Ensure the orbit command is stopped
    currentMoveDirection = nil -- Reset the current move direction
    for _, bodyPos in ipairs(bodyPositions) do
        bodyPos:Destroy()
    end
    bodyPositions = {}
    if bodyPosConnection then
        bodyPosConnection:Disconnect()
        bodyPosConnection = nil
    end
    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot then
            bot.Character.Humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) -- Return to normal animation state
        end
    end
end


local function moveCommand(direction, executor)
    if direction ~= currentMoveDirection then
        stopMoveCommand()
        currentMoveDirection = direction
    end
    disable3DRendering()
    local found = index()
    if states.move then
        return
    end
    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot then
            local bodyPos = Instance.new("BodyPosition", bot.Character.HumanoidRootPart)
            bodyPos.D = 9e9
            bodyPos.P = 0
            bodyPos.MaxForce = Vector3.new(0, 9e9, 9e9)
            bodyPos.Position = bot.Character.HumanoidRootPart.Position + Vector3.new(0, 10, 0)
            table.insert(bodyPositions, bodyPos)
            local offset
            if direction == "left" or direction == "l" then
                offset = CFrame.new(-(i - (#found / 2)) * 3 - 3, 0, 0)
            elseif direction == "right" or direction == "r" then
                offset = CFrame.new((i - (#found / 2)) * 3 + 3, 0, 0)
            elseif direction == "back" or direction == "b" then
                offset = CFrame.new(0, 0, (i - (#found / 2)) * 3 + 3)
            elseif direction == "front" or direction == "f" then
                offset = CFrame.new(0, 0, -(i - (#found / 2)) * 3 - 3)
            else
                offset = CFrame.new(0, 0, (i - (#found / 2)) * 3 + 3)
            end
            bot.Character.HumanoidRootPart.CFrame = executor.Character.HumanoidRootPart.CFrame * offset
            bot.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

            if states.spin then
                local bambam = bot.Character.HumanoidRootPart:FindFirstChild("BodyThrust")
                if not bambam then
                    bambam = Instance.new("BodyThrust")
                    bambam.Parent = bot.Character.HumanoidRootPart
                end
                bambam.Force = Vector3.new(500, 0, 500)
                bambam.Location = bot.Character.HumanoidRootPart.Position
            end
        end
    end
    states.move = true
    bodyPosConnection = RunService.RenderStepped:Connect(function()
        for i, index in ipairs(found) do
            local bot = Players:GetPlayerByUserId(accounts[index])
            if bot and bot.Character and bot.Character.HumanoidRootPart then
                local offset
                if direction == "left" or direction == "l" then
                    offset = CFrame.new(-(i - (#found / 2)) * 3 - 3, 0, 0)
                elseif direction == "right" or direction == "r" then
                    offset = CFrame.new((i - (#found / 2)) * 3 + 3, 0, 0)
                elseif direction == "back" or direction == "b" then
                    offset = CFrame.new(0, 0, (i - (#found / 2)) * 3 + 3)
                elseif direction == "front" or direction == "f" then
                    offset = CFrame.new(0, 0, -(i - (#found / 2)) * 3 - 3)
                else
                    offset = CFrame.new(0, 0, (i - (#found / 2)) * 3 + 3)
                end
                bot.Character.HumanoidRootPart.CFrame = executor.Character.HumanoidRootPart.CFrame * offset
                bot.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Freefall)

                if states.spin then
                    local bambam = bot.Character.HumanoidRootPart:FindFirstChild("BodyThrust")
                    if not bambam then
                        bambam = Instance.new("BodyThrust")
                        bambam.Parent = bot.Character.HumanoidRootPart
                    end
                    bambam.Force = Vector3.new(500, 0, 500)
                    bambam.Location = bot.Character.HumanoidRootPart.Position
                end
            end
        end
    end)
end

local function parseCoordinates(args)
    local coordinates = {}
    for coordinate in args:gmatch("%S+") do
        table.insert(coordinates, tonumber(coordinate))
    end
    return coordinates
end

local function calculateOffset(index, total)
    if total == 1 then
        return Vector3.new(0, 0, 0)
    else
        local angle = (2 * math.pi / total) * index
        local radius = 5
        return Vector3.new(math.cos(angle) * radius, 0, math.sin(angle) * radius)
    end
end

local function tptoCommand(args)
    local coordinates = parseCoordinates(args)
    if #coordinates < 3 then
        Chat("Invalid coordinates. Usage: .tpto x y z")
        return
    end

    local targetPosition = Vector3.new(coordinates[1], coordinates[2], coordinates[3])
    local found = index()
    local totalBots = #found

    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character:FindFirstChild("HumanoidRootPart") then
            local offset = enableOffset and calculateOffset(i, totalBots) or Vector3.new(0, 0, 0)
            bot.Character.HumanoidRootPart.CFrame = CFrame.new(targetPosition + offset)
        end
    end
end

local function walktoCommand(args)
    local coordinates = parseCoordinates(args)
    if #coordinates < 3 then
        Chat("Invalid coordinates. Usage: .walkto x y z")
        return
    end

    local targetPosition = Vector3.new(coordinates[1], coordinates[2], coordinates[3])
    local found = index()
    local totalBots = #found

    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character:FindFirstChildOfClass("Humanoid") then
            local offset = enableOffset and calculateOffset(i, totalBots) or Vector3.new(0, 0, 0)
            bot.Character:FindFirstChildOfClass("Humanoid"):MoveTo(targetPosition + offset)
        end
    end
end

local function hostileCommand(args, executor)
    if args == "on" then
        states.hostile = true
        Chat("Hostile mode activated around " .. executor.Name .. ".")
    elseif args == "off" then
        states.hostile = false
        Chat("Hostile mode deactivated.")
    else
        Chat("Invalid argument for .hostile command. Use 'on' or 'off'.")
    end
end


local function hostileRadiusCommand(args)
    local radius = tonumber(args)
    if radius and radius > 0 then
        hostileRadius = radius
        Chat("Hostile radius set to " .. radius .. " studs.")
    else
        Chat("Invalid radius value. Please provide a positive number.")
    end
end

local function fetchFriendGameData(friendUserId)
    print("Fetching online friends...")
    local userId = localPlayer.UserId
    local response = syn.request({
        Url = "https://friends.roblox.com/v1/users/" .. userId .. "/friends/online",
        Method = "GET",
        Headers = {
            ["Content-Type"] = "application/json",
            ["Cookie"] = ".ROBLOSECURITY=" .. ROBLOSECURITY
        }
    })

    print("Response Status:", response.StatusCode)
    print("Response Body:", response.Body)

    if response.StatusCode == 200 then
        local friendsData = HttpService:JSONDecode(response.Body)
        for _, friend in ipairs(friendsData.data) do
            if friend.id == friendUserId then
                print("Friend found online: ", friend.id)
                print("Fetching presence for friend:", friendUserId)
                local presenceResponse = syn.request({
                    Url = "https://presence.roblox.com/v1/presence/users",
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json",
                        ["Cookie"] = ".ROBLOSECURITY=" .. ROBLOSECURITY
                    },
                    Body = HttpService:JSONEncode({ userIds = { friendUserId } })
                })

                print("Presence Response Status:", presenceResponse.StatusCode)
                print("Presence Response Body:", presenceResponse.Body)

                if presenceResponse.StatusCode == 200 then
                    -- Print the entire presence JSON to see its structure
                    print("Presence JSON Body:", presenceResponse.Body)
                    return presenceResponse.Body
                else
                    print("Failed to fetch presence information. Status code:", presenceResponse.StatusCode)
                end
            end
        end
    else
        print("Failed to fetch online friends. Status code:", response.StatusCode)
    end
    return nil
end

local function sitCommand()
    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character:FindFirstChildOfClass("Humanoid") then
            bot.Character:FindFirstChildOfClass("Humanoid").Sit = true
        end
    end
end


local function extractIdsFromString(jsonString)
    if not jsonString then
        print("Error: JSON string is nil")
        return nil, nil
    end

    -- Print the JSON string to ensure it is not nil
    print("JSON String:", jsonString)

    local success, data = pcall(function() return HttpService:JSONDecode(jsonString) end)
    if success then
        local userPresences = data.userPresences or {}
        if #userPresences > 0 then
            local placeId = userPresences[1].placeId
            local gameInstanceId = userPresences[1].gameId  -- corrected key from gameInstanceId to gameId
            print("Extracted placeId:", placeId)
            print("Extracted gameInstanceId:", gameInstanceId)
            return placeId, gameInstanceId
        else
            print("No user presences found.")
            return nil, nil
        end
    else
        print("Error decoding JSON:", data)
        return nil, nil
    end
end

local function teleportToPlaceInstance(placeId, gameInstanceId)
    if placeId and gameInstanceId then
        print("Teleporting to placeId:", placeId, "gameInstanceId:", gameInstanceId)
        TeleportService:TeleportToPlaceInstance(tonumber(placeId), gameInstanceId, Players.LocalPlayer)
    else
        print("Invalid placeId or gameInstanceId.")
    end
end

local function napCommand()
    local found = index()
    for _, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character:FindFirstChild("HumanoidRootPart") then
            bot.Character.HumanoidRootPart.CFrame = bot.Character.HumanoidRootPart.CFrame * CFrame.Angles(math.rad(90), 0, 0)
            bot.Character.Humanoid.PlatformStand = true
        end
    end
end


local function scanForHost()
    local scanDuration = 600 -- 10 minutes
    local scanInterval = 5 -- Every 5 seconds
    local startTime = tick()

    while tick() - startTime < scanDuration do
        wait(scanInterval)
        local presenceJson = fetchFriendGameData(host)
        if presenceJson then
            local placeId, gameInstanceId = extractIdsFromString(presenceJson)
            if placeId and gameInstanceId then
                sendWebhookLog("Following host to a new game with placeId: " .. placeId .. " and gameInstanceId: " .. gameInstanceId)
                teleportToPlaceInstance(placeId, gameInstanceId)
                return
            end
        end
    end

    Chat("Failed to join the host after 10 minutes.")
    sendWebhookLog("Failed to join the host after 10 minutes.")
    TeleportService:Teleport(game.PlaceId) -- Optionally teleport to a different place or end script
end


local function monitorHost()
    local hostPlayer = Players:GetPlayerByUserId(host)
    if hostPlayer then
        hostPlayer.AncestryChanged:Connect(function(_, parent)
            if not parent then
                Chat("Host has left. Scanning for new game location...")
                sendWebhookLog("Host has left. Scanning for new game location...")
                scanForHost()
            end
        end)
    end
end


-- Add monitorHost call to initialization
monitorHost()

local function extractQuotedArgument(args)
    local quoteTypes = {['"'] = '"', ["'"] = "'", ["‘"] = "’", ["“"] = "”"}
    local firstChar = args:sub(1, 1)
    local lastChar = quoteTypes[firstChar]

    if lastChar then
        local endIdx = args:find(lastChar, 2)
        if endIdx then
            return args:sub(2, endIdx - 1), args:sub(endIdx + 1):match("^%s*(.-)%s*$")
        end
    end
    return args, ""
end

local function levenshteinDistance(s, t)
    local m, n = #s, #t
    local d = {}

    for i = 0, m do
        d[i] = {}
        d[i][0] = i
    end
    for j = 0, n do
        d[0][j] = j
    end

    for i = 1, m do
        for j = 1, n do
            local cost = (s:sub(i, i) == t:sub(j, j)) and 0 or 1
            d[i][j] = math.min(d[i-1][j] + 1, d[i][j-1] + 1, d[i-1][j-1] + cost)
        end
    end

    return d[m][n]
end

local function orbit(user, speed)
    getgenv().isOrbiting = true
    orbitSpeed = speed or 1 -- Use the provided speed or default to 1

    if not user then
        return
    else
        coroutine.wrap(function()
            while getgenv().isOrbiting do
                local angular = tick() * angle * orbitSpeed
                local center = user.Character.HumanoidRootPart.Position

                for i, accountID in ipairs(accounts) do
                    local bot = Players:GetPlayerByUserId(accountID)
                    if bot and bot.Character and bot.Character:FindFirstChild("HumanoidRootPart") then
                        local botRootPart = bot.Character.HumanoidRootPart

                        local botAngle = angular + (2 * math.pi / #accounts) * i
                        local x = center.X + distance * math.cos(botAngle)
                        local y = center.Y + floatHeight -- Float 5 studs higher
                        local z = center.Z + distance * math.sin(botAngle)

                        botRootPart.CFrame = CFrame.new(Vector3.new(x, y, z))
                    end
                end
                wait(0.03) -- Smaller wait time for smoother movement
            end
        end)()
    end
end

local function stopOrbit()
    getgenv().isOrbiting = false
end


local function stopOrbit()
    getgenv().isOrbiting = false
end


local function stopOrbit()
    getgenv().isOrbiting = false
end


local function findClosestCommand(inputCommand, commandList)
    local closestCommand = nil
    local minDistance = math.huge

    for _, command in ipairs(commandList) do
        local distance = levenshteinDistance(inputCommand, command)
        if distance < minDistance then
            minDistance = distance
            closestCommand = command
        end
    end

    if minDistance <= correctionThreshold then
        return closestCommand
    else
        return nil
    end
end

local commandsList = {
    ".test", ".rejoin", ".bring", ".tp", ".line", ".index", ".end", ".reset",
    ".say", ".follow", ".unfollow", ".circle", ".followc", ".lookatme",
    ".hostile", ".hradius", ".jump", ".grant", ".revoke", ".move", ".drop",
    ".spin", ".stopspin", ".stack", ".stopstack", ".sit", ".tpto", ".walkto",
    ".nap", ".orbit"
}

local function handleCommand(text, senderUserId)
    if not text:match("^%.") then
        return
    end

    local commandWords = text:split(" ")
    local command = commandWords[1]:lower()
    local args = table.concat(commandWords, " ", 2)

    local executor = Players:GetPlayerByUserId(senderUserId)
    if not executor then
        warn("Executor not found for UserId: " .. tostring(senderUserId))
        return
    end

    if senderUserId ~= host and not permissions[senderUserId] then
        if command == ".grant" or command == ".revoke" then
            Chat("Only the owner can grant or revoke permissions.")
        end
        return
    end

    if not table.find(commandsList, command) then
        if enableCommandCorrection then
            local closestCommand = findClosestCommand(command, commandsList)
            if closestCommand then
                Chat("Did you mean: " .. closestCommand .. "? Executing the closest command.")
                command = closestCommand
            else
                Chat("Unknown command: " .. command)
                sendWebhookLog("Unknown command: " .. command .. " by User: " .. executor.Name)
                return
            end
        else
            Chat("Unknown command: " .. command)
            sendWebhookLog("Unknown command: " .. command .. " by User: " .. executor.Name)
            return
        end
    end

    print("Executing command:", command, "with args:", args)
    sendWebhookLog("Executing command: " .. command .. " with args: " .. args .. " by User: " .. executor.Name)

    local success, errorMessage = pcall(function()
        if command == ".test" then 
            returnCommand()
        elseif command == ".rejoin" then 
            rejoinCommand()
        elseif command == ".bring" then 
            stopAllMovements()
            bringCommand(executor, args)
        elseif command == ".tp" then
            stopAllMovements()
            tpCommand(executor, args)
        elseif command == ".line" then 
            stopAllMovements()
            lineCommand(args, executor)
        elseif command == ".index" then 
            indexCommand()
        elseif command == ".end" then 
            endCommand()
        elseif command == ".reset" then 
            resetCommand()
        elseif command == ".say" then 
            sayCommand(args)
        elseif command == ".follow" then 
            stopAllMovements()
            followCommand(args, executor)
            sendWebhookLog("Started following user: " .. args .. " by User: " .. executor.Name)
        elseif command == ".unfollow" then 
            stopAllMovements()
            unfollowCommand()
            sendWebhookLog("Stopped following by User: " .. executor.Name)
        elseif command == ".circle" then 
            stopAllMovements()
            circleCommand(executor)
        elseif command == ".followc" then 
            stopAllMovements()
            followCircleCommand(args, executor)
            sendWebhookLog("Started following in a circle around user: " .. args .. " by User: " .. executor.Name)
        elseif command == ".lookatme" then
            stopAllMovements()
            lookAtMeCommand(executor)
        elseif command == ".hostile" then 
            hostileCommand(args, executor)
            sendWebhookLog("Hostile mode set to: " .. args .. " by User: " .. executor.Name)
        elseif command == ".hradius" then 
            hostileRadiusCommand(args)
            sendWebhookLog("Hostile radius set to: " .. args .. " by User: " .. executor.Name)
        elseif command == ".jump" then 
            jumpCommand()
        elseif command == ".grant" then 
            if senderUserId == host then
                grantPermission(args)
                sendWebhookLog("Granted access to: " .. args .. " by User: " .. executor.Name)
            else
                Chat("Only the owner can grant permissions.")
            end
        elseif command == ".revoke" then 
            if senderUserId == host then
                revokePermission(args)
                sendWebhookLog("Revoked access from: " .. args .. " by User: " .. executor.Name)
            else
                Chat("Only the owner can revoke permissions.")
            end
        elseif command == ".move" then
            stopAllMovements()
            moveCommand(args, executor)
            sendWebhookLog("Moving in direction: " .. args .. " by User: " .. executor.Name)
        elseif command == ".drop" then
            stopAllMovements()
            stopMoveCommand()
            sendWebhookLog("Stopped moving by User: " .. executor.Name)
        elseif command == ".spin" then
            stopAllMovements()
            states.spin = true
            spinCommand(args, executor)
            sendWebhookLog("Started spinning with speed: " .. args .. " by User: " .. executor.Name)
        elseif command == ".stopspin" then
            stopSpinCommand()
            sendWebhookLog("Stopped spinning by User: " .. executor.Name)
        elseif command == ".stack" then
            stackCommand(executor)
            sendWebhookLog("Started stacking by User: " .. executor.Name)
        elseif command == ".stopstack" then
            stopStackCommand()
            sendWebhookLog("Stopped stacking by User: " .. executor.Name)
        elseif command == ".sit" then
            sitCommand()
            sendWebhookLog("Sit command executed by User: " .. executor.Name)
        elseif command == ".tpto" then
            tptoCommand(args)
            sendWebhookLog("Teleporting to coordinates: " .. args .. " by User: " .. executor.Name)
        elseif command == ".walkto" then
            walktoCommand(args)
            sendWebhookLog("Walking to coordinates: " .. args .. " by User: " .. executor.Name)
        elseif command == ".nap" then
            napCommand()
            sendWebhookLog("Nap command executed by User: " .. executor.Name)
        elseif command == ".orbit" then
            stopAllMovements()
            local targetName, speed = args:match("^(%S+)%s*(%d*)$")
            local target = getPlayer(targetName, executor)
            orbit(target, tonumber(speed) or 1)
            sendWebhookLog("Orbit command executed by User: " .. executor.Name .. " with speed: " .. (tonumber(speed) or 1))
        else
            Chat("Unknown command: " .. command)
            sendWebhookLog("Unknown command: " .. command .. " by User: " .. executor.Name)
        end
    end)

    if not success then
        warn("Error executing command: " .. tostring(errorMessage))
        sendWebhookLog("Error executing command: " .. command .. " with args: " .. args .. " by User: " .. executor.Name .. " - Error: " .. tostring(errorMessage))
    end
end


-- Store connections for cleanup
local connections = {}

local function connectPlayerChat(player)
    if player and not connections[player] then
        local conn = player.Chatted:Connect(function(txt)
            handleCommand(txt:lower(), player.UserId)
        end)
        connections[player] = conn

        player.AncestryChanged:Connect(function(_, parent)
            if not parent then
                if connections[player] then
                    connections[player]:Disconnect()
                    connections[player] = nil
                end
            end
        end)
    end
end

-- Connect to existing players
for _, player in ipairs(Players:GetPlayers()) do
    connectPlayerChat(player)
end

-- Connect to new players
local playerAddedConn = Players.PlayerAdded:Connect(function(player)
    connectPlayerChat(player)
end)
table.insert(connections, playerAddedConn)

local function initializeBot(executor)
    local found = index()
    for i, index in ipairs(found) do
        local bot = Players:GetPlayerByUserId(accounts[index])
        if bot and bot.Character and bot.Character.HumanoidRootPart then
            local offset = CFrame.new((i - (#found / 2) - 0.5) * 2, 0, -5) -- Teleport in front of the executor
            bot.Character.HumanoidRootPart.CFrame = executor.Character.HumanoidRootPart.CFrame * offset

            -- Make the bot look at the executor
            bot.Character.HumanoidRootPart.CFrame = CFrame.lookAt(bot.Character.HumanoidRootPart.Position, executor.Character.HumanoidRootPart.Position)
            wait(0.1)

            Chat("/e wave")
            wait(0.5) -- Wait a bit to ensure the chat message goes through
        end
    end
end

local function initialize()
    local initStartTime = tick()
    local targetPlayer = Players:FindFirstChild(tar)

    local initEndTime = tick()
    Chat("Account Manager loaded in " .. string.format("%.2f", initEndTime - initStartTime) .. " seconds.")

    if model then
        connectPlayerChat(model)  -- Ensure the model player is connected
        initializeBot(model)  -- Initialize the bot when the model is connected
    else
        Chat("Host not found initially. Scanning for host's new game location...")
        scanForHost()
    end
end

initialize()

game.Players.LocalPlayer.Idled:Connect(function()
    game:GetService("VirtualUser"):CaptureController()
    game:GetService("VirtualUser"):ClickButton2(Vector2.new())
end)
