-- VictimRescueClient - Handles client-side rescue effects and UI updates

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Import modules
local GameTimer = require(ReplicatedStorage.Modules.GameTimer)
local CoinEffect = require(ReplicatedStorage.Modules.CoinEffect)

-- Wait for RemoteEvents
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local rescueRemote = remoteEvents:WaitForChild("VictimRescue")

-- Function to create client-side coin effect to UI
local function createCoinUIEffect()
	local timerGui = playerGui:FindFirstChild("GameTimerGui")
	if not timerGui then return end

	local coinFrame = timerGui:FindFirstChild("CoinFrame")
	if not coinFrame then return end

	-- Create a temporary coin that flies to the UI
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CoinEffect"
	screenGui.Parent = playerGui

	local coinImage = Instance.new("ImageLabel")
	coinImage.Name = "FlyingCoin"
	coinImage.Size = UDim2.new(0, 50, 0, 50)
	coinImage.Position = UDim2.new(0.5, -25, 0.5, -25) -- Start at center
	coinImage.BackgroundTransparency = 1
	coinImage.Image = "rbxassetid://124358779164505"
	coinImage.ScaleType = Enum.ScaleType.Fit
	coinImage.Parent = screenGui

	-- Get target position (coin UI frame)
	local targetPosition = UDim2.new(0.63, 0, 0.05, 0) -- Same as coin frame position

	-- Create tween to coin UI
	local tweenInfo = TweenInfo.new(
		0.8, -- Duration
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	local tween = TweenService:Create(coinImage, tweenInfo, {
		Position = targetPosition,
		Size = UDim2.new(0, 30, 0, 30)
	})

	-- Start the animation
	tween:Play()

	-- Clean up and trigger coin UI update
	tween.Completed:Connect(function()
		screenGui:Destroy()
		-- Update the actual coin counter with animation
		task.wait(0.1) -- Small delay for effect
		GameTimer.addCoins(1)
	end)
end

-- Function to play rescue sound effect
local function playRescueSound()
	-- You can add a rescue sound effect here
	-- local rescueSound = SoundService:FindFirstChild("RescueSound")
	-- if rescueSound then
	--     rescueSound:Play()
	-- end
	print("🎵 Rescue sound effect would play here")
end

-- Function to show rescue notification
local function showRescueNotification(rescueCount)
	local screenGui = playerGui:FindFirstChild("GameTimerGui")
	if not screenGui then return end

	-- Create notification
	local notification = Instance.new("Frame")
	notification.Name = "RescueNotification"
	notification.Size = UDim2.new(0.3, 0, 0.1, 0)
	notification.Position = UDim2.new(0.35, 0, 0.15, 0) -- Below timer
	notification.BackgroundColor3 = Color3.fromRGB(40, 127, 71) -- Green
	notification.BackgroundTransparency = 0.1
	notification.BorderSizePixel = 0
	notification.Parent = screenGui

	-- Add corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.01, 0)
	corner.Parent = notification

	-- Add text
	local notificationText = Instance.new("TextLabel")
	notificationText.Size = UDim2.new(1, 0, 1, 0)
	notificationText.Position = UDim2.new(0, 0, 0, 0)
	notificationText.BackgroundTransparency = 1
	notificationText.Text = "Victim Rescued! (" .. rescueCount .. ")"
	notificationText.TextColor3 = Color3.fromRGB(255, 255, 255)
	notificationText.TextScaled = true
	notificationText.Font = Enum.Font.GothamBold
	notificationText.TextStrokeTransparency = 0
	notificationText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	notificationText.Parent = notification

	-- Animate notification
	local slideIn = TweenService:Create(notification,
		TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{BackgroundTransparency = 0.1}
	)

	local slideOut = TweenService:Create(notification,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{
			Position = UDim2.new(0.35, 0, 0.05, 0),
			BackgroundTransparency = 1
		}
	)

	local textFade = TweenService:Create(notificationText,
		TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{TextTransparency = 1}
	)

	-- Play animations
	slideIn:Play()

	-- Wait then fade out
	task.wait(2)
	slideOut:Play()
	textFade:Play()

	slideOut.Completed:Connect(function()
		notification:Destroy()
	end)
end

-- Handle rescue events from server

local function showReviveNotification(text)
	local screenGui = playerGui:FindFirstChild("GameTimerGui")
	if not screenGui then return end

	local notification = Instance.new("TextLabel")
	notification.Name = "ReviveNotification"
	notification.Size = UDim2.new(0.3, 0, 0.06, 0)
	notification.Position = UDim2.new(0.35, 0, 0.22, 0)
	notification.BackgroundTransparency = 1
	notification.Text = text
	notification.TextColor3 = Color3.fromRGB(255, 255, 255)
	notification.Font = Enum.Font.GothamBold
	notification.TextScaled = true
	notification.TextStrokeTransparency = 0.25
	notification.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	notification.Parent = screenGui

	task.delay(2, function()
		if notification.Parent then
			notification:Destroy()
		end
	end)
end

rescueRemote.OnClientEvent:Connect(function(action, data, position)
	if action == "coinCollected" then
		-- Use new CoinEffect system
		local coinAmount = data or 1
		local worldPosition = position or Vector3.new(0, 10, 0)

		print("[VictimRescueClient] Received coinCollected:", coinAmount, "coins at", worldPosition)
		CoinEffect.SpawnCoins(worldPosition, coinAmount, player)
		playRescueSound()
	elseif action == "victimRescued" then
		local rescueCount = data
		showRescueNotification(rescueCount)
	elseif action == "reviveReward" then
		local rewardAmount = 0
		if typeof(data) == "number" then
			rewardAmount = data
		elseif typeof(data) == "table" then
			rewardAmount = tonumber(data.amount) or 0
		end

		rewardAmount = math.floor(rewardAmount)
		if rewardAmount > 0 then
			GameTimer.addCoins(rewardAmount)
			showReviveNotification(string.format("Revived teammate! +%d", rewardAmount))
		end
	elseif action == "revivePenalty" then
		local penalty = tonumber(data) or 0
		penalty = math.floor(penalty)
		if penalty > 0 then
			GameTimer.addCoins(-penalty)
			showReviveNotification(string.format("Revived by friend -%d", penalty))
		end
	end
end)

print("VictimRescueClient loaded for", player.Name)
