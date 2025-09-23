-- CustomRescueSystem - Custom proximity system for victim rescue

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Import GameConfig
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local rescueSettings = GameConfig.getRescueSettings()

-- Configuration from GameConfig
local RESCUE_DISTANCE = rescueSettings.distance
local HOLD_DURATION = rescueSettings.holdDuration
local RESCUE_KEY = rescueSettings.keyCode

-- Variables
local nearestVictim = nil
local victimBillboard = nil
local isRescuing = false
local rescueConnection = nil
local distanceConnection = nil
local holdStartTime = 0
local progressBar = nil
local lastDebugTime = 0
local lastCharacterWarning = 0
local systemInitialized = false

-- RemoteEvents
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local rescueRemote = remoteEvents:WaitForChild("VictimRescue")
local victimsReadyRemote = remoteEvents:WaitForChild("VictimsReady")

-- Function to create billboard UI on victim
local function createVictimBillboard(victim)
	if not victim or not victim:FindFirstChild("HumanoidRootPart") then
		return nil
	end

	-- Remove existing billboard
	if victimBillboard then
		victimBillboard:Destroy()
		victimBillboard = nil
	end

	local rootPart = victim:FindFirstChild("HumanoidRootPart")

	-- Create BillboardGui
	victimBillboard = Instance.new("BillboardGui")
	victimBillboard.Name = "RescueBillboard"
	victimBillboard.Size = UDim2.new(4, 0, 2, 0)
	victimBillboard.StudsOffset = Vector3.new(0, 3, 0) -- แสดงเหนือหัว victim
	victimBillboard.Adornee = rootPart
	victimBillboard.Parent = victim

	-- Main frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.Position = UDim2.new(0, 0, 0, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.2
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = victimBillboard

	-- Corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = mainFrame

	-- Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 3
	stroke.Parent = mainFrame

	-- Action text
	local actionText = Instance.new("TextLabel")
	actionText.Name = "ActionText"
	actionText.Size = UDim2.new(1, 0, 0.6, 0)
	actionText.Position = UDim2.new(0, 0, 0, 0)
	actionText.BackgroundTransparency = 1
	actionText.Text = "[E] ช่วยเหลือ"
	actionText.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionText.TextScaled = true
	actionText.Font = Enum.Font.GothamBold
	actionText.TextStrokeTransparency = 0
	actionText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	actionText.Parent = mainFrame

	-- Progress bar background
	local progressBg = Instance.new("Frame")
	progressBg.Name = "ProgressBg"
	progressBg.Size = UDim2.new(0.9, 0, 0.25, 0)
	progressBg.Position = UDim2.new(0.05, 0, 0.7, 0)
	progressBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	progressBg.BorderSizePixel = 0
	progressBg.Visible = false
	progressBg.Parent = mainFrame

	local progressBgCorner = Instance.new("UICorner")
	progressBgCorner.CornerRadius = UDim.new(0.5, 0)
	progressBgCorner.Parent = progressBg

	-- Progress bar fill
	progressBar = Instance.new("Frame")
	progressBar.Name = "ProgressFill"
	progressBar.Size = UDim2.new(0, 0, 1, 0)
	progressBar.Position = UDim2.new(0, 0, 0, 0)
	progressBar.BackgroundColor3 = Color3.fromRGB(40, 127, 71)
	progressBar.BorderSizePixel = 0
	progressBar.Parent = progressBg

	local progressFillCorner = Instance.new("UICorner")
	progressFillCorner.CornerRadius = UDim.new(0.5, 0)
	progressFillCorner.Parent = progressBar

	return victimBillboard, progressBg
end

-- Function to find nearest victim
local function findNearestVictim()
	local character = player.Character
	local searchPosition = nil

	-- Try to find player's vehicle first
	local playerVehicle = nil
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and (model.Name == player.Name .. "_RescueCompanion" or model.Name == player.Name .. "_Rescue") then
			if model.PrimaryPart then
				playerVehicle = model
				searchPosition = model.PrimaryPart.Position
				break
			end
		end
	end

	-- Fallback to character position if no vehicle found
	if not searchPosition and character and character:FindFirstChild("HumanoidRootPart") then
		searchPosition = character.HumanoidRootPart.Position
	end

	if not searchPosition then
		-- Debug: Check why no position found
		if tick() - lastCharacterWarning > 10 then
			lastCharacterWarning = tick()
			print("[CustomRescueSystem] No character or vehicle position found")
		end
		return nil
	end

	local nearest = nil
	local nearestDistance = math.huge

	-- Check VictimFolders
	local victimFolder = workspace:FindFirstChild("VictimFolders")
	if not victimFolder then
		print("[CustomRescueSystem] VictimFolders not found in workspace")
		return nil
	end

	local victimCount = 0
	for _, victim in ipairs(victimFolder:GetChildren()) do
		if victim.Name:match("^Victim_") then
			victimCount = victimCount + 1
			local rootPart = victim:FindFirstChild("HumanoidRootPart")
			if rootPart then
				local distance = (rootPart.Position - searchPosition).Magnitude
				if distance <= RESCUE_DISTANCE and distance < nearestDistance then
					nearest = victim
					nearestDistance = distance
				end
			end
		end
	end

	if victimCount == 0 then
		print("[CustomRescueSystem] No victims found in VictimFolders")
	end

	return nearest, nearestDistance
end

-- Function to stop rescue
local function stopRescue()
	isRescuing = false

	if rescueConnection then
		rescueConnection:Disconnect()
		rescueConnection = nil
	end

	-- Hide progress bar in BillboardGui
	if victimBillboard then
		local mainFrame = victimBillboard:FindFirstChild("MainFrame")
		local progressBg = mainFrame and mainFrame:FindFirstChild("ProgressBg")
		if progressBg then
			progressBg.Visible = false
		end
	end

	print("[CustomRescueSystem] Stopped rescue")
end

-- Function to complete rescue
local function completeRescue()
	if not nearestVictim then
		print("[CustomRescueSystem] ERROR: No nearestVictim to rescue")
		return
	end

	local victimToRescue = nearestVictim
	print("[CustomRescueSystem] Completed rescue of", victimToRescue.Name, "- Sending to server...")

	-- Fade out BillboardGui before server processing
	if victimBillboard then
		local mainFrame = victimBillboard:FindFirstChild("MainFrame")
		if mainFrame then
			local fadeInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local fadeTween = TweenService:Create(mainFrame, fadeInfo, {
				BackgroundTransparency = 1
			})

			-- Fade all text and UI elements
			for _, child in ipairs(mainFrame:GetDescendants()) do
				if child:IsA("TextLabel") then
					local textTween = TweenService:Create(child, fadeInfo, {
						TextTransparency = 1,
						TextStrokeTransparency = 1
					})
					textTween:Play()
				elseif child:IsA("Frame") and child.Name ~= "MainFrame" then
					local frameTween = TweenService:Create(child, fadeInfo, {
						BackgroundTransparency = 1
					})
					frameTween:Play()
				elseif child:IsA("UIStroke") then
					local strokeTween = TweenService:Create(child, fadeInfo, {
						Transparency = 1
					})
					strokeTween:Play()
				end
			end

			fadeTween:Play()
			fadeTween.Completed:Connect(function()
				victimBillboard:Destroy()
				victimBillboard = nil
			end)
		else
			-- Fallback: destroy immediately if no mainFrame
			victimBillboard:Destroy()
			victimBillboard = nil
		end
	end

	-- Fire server event
	local success = pcall(function()
		rescueRemote:FireServer("rescue", victimToRescue)
	end)

	if success then
		print("[CustomRescueSystem] Successfully sent rescue request to server")
	else
		print("[CustomRescueSystem] ERROR: Failed to send rescue request to server")
	end

	-- Reset state
	stopRescue()
	nearestVictim = nil
end

-- Function to update rescue UI
local function updateRescueUI()
	local victim, distance = findNearestVictim()

	-- Debug: Show nearest distance every 3 seconds
	if tick() - lastDebugTime > 3 then
		lastDebugTime = tick()

		-- Check what position source we're using
		local positionSource = "unknown"
		local playerVehicle = nil
		for _, model in ipairs(workspace:GetChildren()) do
			if model:IsA("Model") and (model.Name == player.Name .. "_RescueCompanion" or model.Name == player.Name .. "_Rescue") then
				if model.PrimaryPart then
					playerVehicle = model
					positionSource = "vehicle (" .. model.Name .. ")"
					break
				end
			end
		end

		if not playerVehicle and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			positionSource = "character"
		end

		if distance and distance < 50 then -- Show if within 50 studs
			print("[CustomRescueSystem] Nearest victim distance:", math.floor(distance), "studs (need ≤", RESCUE_DISTANCE, ") from", positionSource)
		elseif distance then
			print("[CustomRescueSystem] Nearest victim too far:", math.floor(distance), "studs (need ≤", RESCUE_DISTANCE, ") from", positionSource)
		else
			print("[CustomRescueSystem] No distance returned from", positionSource)
		end
	end

	if victim ~= nearestVictim then
		nearestVictim = victim

		if nearestVictim then
			-- Create billboard on victim
			createVictimBillboard(nearestVictim)
			print("[CustomRescueSystem] Showing rescue UI for", nearestVictim.Name, "at distance", math.floor(distance), "studs")
		else
			-- Remove billboard immediately
			if victimBillboard then
				victimBillboard:Destroy()
				victimBillboard = nil
			end

			-- Stop any ongoing rescue
			if isRescuing then
				stopRescue()
			end
		end
	end

	-- Safety check: if victim was destroyed but billboard still exists
	if victimBillboard and nearestVictim and not nearestVictim.Parent then
		print("[CustomRescueSystem] Victim destroyed, cleaning up billboard")
		victimBillboard:Destroy()
		victimBillboard = nil
		nearestVictim = nil
		if isRescuing then
			stopRescue()
		end
	end
end

-- Function to start rescue
local function startRescue()
	if not nearestVictim or isRescuing then return end

	isRescuing = true
	holdStartTime = tick()

	print("[CustomRescueSystem] Started rescuing", nearestVictim.Name)

	-- Show progress bar in BillboardGui
	if victimBillboard then
		local mainFrame = victimBillboard:FindFirstChild("MainFrame")
		local progressBg = mainFrame and mainFrame:FindFirstChild("ProgressBg")
		if progressBg then
			progressBg.Visible = true
			progressBar.Size = UDim2.new(0, 0, 1, 0)
		end
	end

	-- Update progress
	rescueConnection = RunService.Heartbeat:Connect(function()
		if not nearestVictim or not isRescuing then
			stopRescue()
			return
		end

		local elapsed = tick() - holdStartTime
		local progress = math.min(elapsed / HOLD_DURATION, 1)

		-- Update progress bar
		if progressBar then
			local tween = TweenService:Create(progressBar,
				TweenInfo.new(0.1, Enum.EasingStyle.Linear),
				{Size = UDim2.new(progress, 0, 1, 0)}
			)
			tween:Play()
		end

		-- Check if completed
		if progress >= 1 then
			completeRescue()
		end
	end)
end

-- Handle input
local function onKeyPressed(key, gameProcessed)
	if gameProcessed then return end

	if key.KeyCode == RESCUE_KEY then
		if nearestVictim and not isRescuing then
			startRescue()
		end
	end
end

local function onKeyReleased(key, gameProcessed)
	if gameProcessed then return end

	if key.KeyCode == RESCUE_KEY then
		if isRescuing then
			stopRescue()
		end
	end
end

-- Initialize system
local function initializeSystem()
	if systemInitialized then
		print("[CustomRescueSystem] Already initialized, skipping...")
		return
	end

	print("[CustomRescueSystem] Starting initialization...")

	-- Check if VictimFolders exists
	local victimFolder = workspace:FindFirstChild("VictimFolders")
	if victimFolder then
		local victimCount = 0
		for _, child in ipairs(victimFolder:GetChildren()) do
			if child.Name:match("^Victim_") then
				victimCount = victimCount + 1
			end
		end
		print("[CustomRescueSystem] Found", victimCount, "victims in VictimFolders")
	else
		print("[CustomRescueSystem] VictimFolders not found during initialization")
	end

	-- Stop existing connections
	if distanceConnection then
		distanceConnection:Disconnect()
	end

	-- Start distance checking
	distanceConnection = RunService.Heartbeat:Connect(updateRescueUI)
	print("[CustomRescueSystem] Distance checking connection established")

	-- Connect input (only once)
	if not systemInitialized then
		UserInputService.InputBegan:Connect(onKeyPressed)
		UserInputService.InputEnded:Connect(onKeyReleased)
		print("[CustomRescueSystem] Input connections established")
	end

	systemInitialized = true
	print("[CustomRescueSystem] Initialized for", player.Name)
end

-- Wait for victims to be ready before initializing
local function waitForVictimsAndInitialize()
	if player.Character then
		print("[CustomRescueSystem] Waiting for victims to be spawned...")
		victimsReadyRemote.OnClientEvent:Wait()
		print("[CustomRescueSystem] Victims ready signal received")
		task.wait(1) -- Additional wait for character to be ready
		initializeSystem()
	end
end

-- Cleanup and re-initialize when character spawns
player.CharacterAdded:Connect(function()
	-- Stop existing connections if any
	if distanceConnection then
		distanceConnection:Disconnect()
		distanceConnection = nil
	end

	-- Clean up existing UI
	if victimBillboard then
		victimBillboard:Destroy()
		victimBillboard = nil
	end

	-- Reset state
	isRescuing = false
	nearestVictim = nil
	systemInitialized = false -- Allow re-initialization

	waitForVictimsAndInitialize()
end)

-- Listen for victims ready signal to initialize system
victimsReadyRemote.OnClientEvent:Connect(function()
	print("[CustomRescueSystem] Victims ready signal received")
	if player.Character then
		task.wait(1) -- Wait for character to be ready
		initializeSystem()
	end
end)

print("[CustomRescueSystem] Loaded for", player.Name)