--!strict
-- Coin Effect System - Candy Crush Style (2D GUI Version)
-- Creates animated GUI coin effects that fly to the coin UI

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CoinEffect = {}

-- Configuration
local CONFIG = {
	AnimationDuration = 0.8,
	BounceDelay = 0.1,
	ScatterRadius = 100, -- pixels
	CoinSize = UDim2.new(0, 60, 0, 60),
	RotationDegrees = 360,
}

local EMITTER_ATTRIBUTE = "CoinEffectOriginalEnabled"
local activeEmitterCounts: {[Instance]: number} = {}
local emitterToggleTargets: {[Instance]: {Instance}} = {}

local function getToggleTargets(emitter: Instance): {Instance}
	local cached = emitterToggleTargets[emitter]
	if cached then
		return cached
	end

	local targets: {Instance} = {}

	local function tryRegister(instance: Instance)
		-- Check if instance has Enabled property or attribute
		local success, value = pcall(function()
			local enabled = instance:GetAttribute("Enabled")
			return if type(enabled) == "boolean" then enabled else false
		end)

		if success and value ~= nil then
			targets[#targets + 1] = instance
			local attr = instance:GetAttribute(EMITTER_ATTRIBUTE)
			if type(attr) ~= "boolean" then
				instance:SetAttribute(EMITTER_ATTRIBUTE, value)
				attr = value
			end
		end
	end

	tryRegister(emitter)
	for _, descendant in emitter:GetDescendants() do
		tryRegister(descendant)
	end

	emitterToggleTargets[emitter] = targets
	return targets
end

local function restoreTarget(instance: Instance)
	local attr = instance:GetAttribute(EMITTER_ATTRIBUTE)
	local targetEnabled = if type(attr) == "boolean" then attr else false
	pcall(function()
		if instance:IsA("Configuration") then
			instance:SetAttribute("Enabled", targetEnabled)
		end
	end)
end

local function setTargetEnabled(instance: Instance, enabled: boolean)
	pcall(function()
		if instance:IsA("Configuration") then
			instance:SetAttribute("Enabled", enabled)
		end
	end)
end

local function startCoinEmitter(emitter: Instance, countIncrement: number?)
	if not emitter then
		return
	end

	local increment = math.max(countIncrement or 1, 1)
	local targets = getToggleTargets(emitter)

	if #targets == 0 then
		if emitter:IsA("ParticleEmitter") then
			emitter:Emit(increment)
		end
		return
	end

	local previous = activeEmitterCounts[emitter]
	if not previous or previous <= 0 then
		for _, target in ipairs(targets) do
			setTargetEnabled(target, true)
		end
		activeEmitterCounts[emitter] = increment
	else
		activeEmitterCounts[emitter] = previous + increment
	end
end

local function stopCoinEmitter(emitter: Instance, countDecrement: number?)
	if not emitter then
		return
	end

	local currentCount = activeEmitterCounts[emitter]
	if not currentCount then
		return
	end

	local decrement = math.max(countDecrement or 1, 1)
	local newCount = currentCount - decrement

	if newCount > 0 then
		activeEmitterCounts[emitter] = newCount
		return
	end

	activeEmitterCounts[emitter] = nil

	local targets = emitterToggleTargets[emitter]
	if targets and #targets > 0 then
		for _, target in ipairs(targets) do
			restoreTarget(target)
		end
	elseif emitter:IsA("ParticleEmitter") then
		emitter:Clear()
	end
end

-- Get or create player's coin effect GUI
local function getOrCreateCoinGui(player: Player): ScreenGui?
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end

	local coinEffectGui = playerGui:FindFirstChild("CoinEffectGui")
	if coinEffectGui then
		return coinEffectGui :: ScreenGui
	end

	-- Create new GUI
	local newGui = Instance.new("ScreenGui")
	newGui.Name = "CoinEffectGui"
	newGui.ResetOnSpawn = false
	newGui.DisplayOrder = 999
	newGui.IgnoreGuiInset = true
	newGui.Parent = playerGui

	return newGui :: ScreenGui
end

-- Find the target coin icon (CoinFrame.CoinIcon)
local function findCoinIcon(player: Player): GuiObject?
	local playerGui = player:FindFirstChild("PlayerGui")
	if not playerGui then return nil end

	-- Look for GameTimerGui.CoinFrame.CoinIcon
	local gameTimerGui = playerGui:FindFirstChild("GameTimerGui")
	if gameTimerGui then
		local coinFrame = gameTimerGui:FindFirstChild("CoinFrame")
		if coinFrame then
			local coinIcon = coinFrame:FindFirstChild("CoinIcon")
			if coinIcon and coinIcon:IsA("GuiObject") then
				return coinIcon
			end
		end
	end

	return nil
end

-- Create a coin GUI element (clone from template or create new)
local function createCoinGui(parent: ScreenGui): GuiObject
	-- Try to find template CoinFrame to clone
	local screenGuis = ReplicatedStorage:FindFirstChild("ScreenGuis")
	local templateCoin = nil

	if screenGuis then
		local coinFrame = screenGuis:FindFirstChild("CoinFrame")
		if coinFrame then
			-- Clone the entire CoinFrame as template
			templateCoin = coinFrame:Clone()
			templateCoin.Name = "FlyingCoin"

			-- Force absolute positioning for flying coins
			templateCoin.Size = UDim2.new(0, 60, 0, 60) -- Fixed pixel size
		end
	end

	-- If no template found, create a simple coin
	if not templateCoin then
		templateCoin = Instance.new("ImageLabel")
		templateCoin.Name = "FlyingCoin"
		templateCoin.Size = CONFIG.CoinSize
		templateCoin.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
		templateCoin.BorderSizePixel = 0
		templateCoin.Image = "rbxasset://textures/ui/GuiImagePlaceholder.png"

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(1, 0)
		corner.Parent = templateCoin
	end

	-- Always use center anchor and absolute positioning
	templateCoin.AnchorPoint = Vector2.new(0.5, 0.5)
	templateCoin.Position = UDim2.new(0, 0, 0, 0) -- Will be set by animation
	templateCoin.ZIndex = 1000
	templateCoin.Parent = parent

	return templateCoin
end

-- Convert world position to screen position
local function worldToScreen(position: Vector3, camera: Camera): Vector2?
	local viewportPoint, onScreen = camera:WorldToViewportPoint(position)
	if onScreen then
		return Vector2.new(viewportPoint.X, viewportPoint.Y)
	end
	return nil
end

-- Animate a single coin GUI
local function animateCoinGui(
	coinGui: GuiObject,
	startPos: UDim2,
	targetPos: UDim2,
	delay: number,
	onComplete: () -> ()
)
	task.wait(delay)

	-- Set initial position
	coinGui.Position = startPos

	-- Bounce animation
	local bounceInfo = TweenInfo.new(
		0.3,
		Enum.EasingStyle.Quad,
		Enum.EasingDirection.Out
	)

	-- Calculate bounce position (slight upward movement)
	local bounceOffset = UDim2.new(0, 0, 0, -50)
	local bouncePos = UDim2.new(
		startPos.X.Scale,
		startPos.X.Offset,
		startPos.Y.Scale,
		startPos.Y.Offset - 50
	)

	local bounceTween = TweenService:Create(coinGui, bounceInfo, {
		Position = bouncePos
	})

	-- Rotation animation
	local rotationInfo = TweenInfo.new(
		CONFIG.AnimationDuration,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.InOut
	)
	local rotationTween = TweenService:Create(coinGui, rotationInfo, {
		Rotation = CONFIG.RotationDegrees
	})

	bounceTween:Play()
	rotationTween:Play()

	bounceTween.Completed:Connect(function()
		-- Fly to target
		local flyInfo = TweenInfo.new(
			CONFIG.AnimationDuration,
			Enum.EasingStyle.Back,
			Enum.EasingDirection.In
		)

		local flyTween = TweenService:Create(coinGui, flyInfo, {
			Position = targetPos,
			Size = UDim2.new(0, 30, 0, 30) -- Shrink to match icon size
		})

		flyTween:Play()

		flyTween.Completed:Connect(function()
			rotationTween:Cancel()
			coinGui:Destroy()
			onComplete()
		end)
	end)
end

-- Scale animation for coin icon
-- Use a persistent UIScale so the icon scales without shifting its position
local function getOrCreateCoinIconScale(coinIcon: GuiObject): UIScale
	local existing = coinIcon:FindFirstChild("CoinEffectScale")
	if existing and existing:IsA("UIScale") then
		return existing
	end

	if existing then
		existing:Destroy()
	end

	local uiScale = Instance.new("UIScale")
	uiScale.Name = "CoinEffectScale"
	uiScale.Parent = coinIcon
	return uiScale
end

local function animateCoinIconScale(coinIcon: GuiObject, _originalSize: UDim2, originalAnchorPoint: Vector2)
	coinIcon.AnchorPoint = originalAnchorPoint

	local uiScale = getOrCreateCoinIconScale(coinIcon)
	local storedScale = coinIcon:GetAttribute("CoinEffectOriginalScale")
	local originalScale = if type(storedScale) == "number" then storedScale else uiScale.Scale
	if type(storedScale) ~= "number" then
		coinIcon:SetAttribute("CoinEffectOriginalScale", originalScale)
	else
		uiScale.Scale = originalScale
	end

	local scaleUp = TweenService:Create(uiScale,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Scale = originalScale + 0.15}
	)

	local scaleDown = TweenService:Create(uiScale,
		TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{Scale = originalScale}
	)

	scaleUp:Play()
	scaleUp.Completed:Connect(function()
		scaleDown:Play()
	end)

	scaleDown.Completed:Connect(function()
		uiScale.Scale = originalScale
	end)
end

-- Reset coin icon to original state
local function resetCoinIcon(coinIcon: GuiObject, originalSize: UDim2, originalPosition: UDim2, originalAnchorPoint: Vector2)
	coinIcon.Size = originalSize
	coinIcon.Position = originalPosition
	coinIcon.AnchorPoint = originalAnchorPoint

	local uiScale = coinIcon:FindFirstChild("CoinEffectScale")
	if uiScale and uiScale:IsA("UIScale") then
		local targetScale = coinIcon:GetAttribute("CoinEffectOriginalScale")
		if type(targetScale) ~= "number" then
			targetScale = 1
		end
		local resetTween = TweenService:Create(uiScale,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{Scale = targetScale}
		)
		resetTween:Play()
	end
end

-- Main function to spawn coin effect
function CoinEffect.SpawnCoins(position: Vector3, amount: number, targetPlayer: Player?)
	local player = targetPlayer or Players.LocalPlayer
	if not player then return end

	-- Get camera
	local camera = workspace.CurrentCamera
	if not camera then return end

	-- Get or create GUI container
	local coinGui = getOrCreateCoinGui(player)
	if not coinGui then return end

	-- Find target coin icon
	local targetCoinIcon = findCoinIcon(player)
	local targetPosition: UDim2
	local targetCoinEmitter: Instance? = nil

	-- Store original state of coin icon
	local originalIconSize: UDim2? = nil
	local originalIconPosition: UDim2? = nil
	local originalIconAnchorPoint: Vector2? = nil

	if targetCoinIcon then
		-- Save original size, position, and anchor point
		originalIconSize = targetCoinIcon.Size
		originalIconPosition = targetCoinIcon.Position
		originalIconAnchorPoint = targetCoinIcon.AnchorPoint

			local coinFrame = targetCoinIcon.Parent
			if coinFrame then
				targetCoinEmitter = coinFrame:FindFirstChild("Emitter")
			end

		-- Calculate absolute position of CoinIcon center
		local absPos = targetCoinIcon.AbsolutePosition
		local absSize = targetCoinIcon.AbsoluteSize
		targetPosition = UDim2.new(
			0,
			absPos.X + absSize.X / 2,
			0,
			absPos.Y + absSize.Y / 2
		)
	else
		-- Fallback to top-right corner
		warn("CoinIcon not found, using default position")
		targetPosition = UDim2.new(0.9, 0, 0.1, 0)
	end

	-- Get viewport size for random positioning
	local viewportSize = camera.ViewportSize

	-- Play initial burst sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://4612377122"
	sound.Volume = 0.5
	sound.Parent = workspace
	sound:Play()
	task.delay(2, function()
		sound:Destroy()
	end)

		-- Spawn coins
		local coinsCollected = 0

		if targetCoinEmitter then
			startCoinEmitter(targetCoinEmitter, amount)
		end

	for i = 1, amount do
		local coin = createCoinGui(coinGui)

		-- Random position across the screen (not from world position)
		-- Spread coins randomly across viewport
		local randomX = math.random(100, viewportSize.X - 100)
		local randomY = math.random(100, viewportSize.Y - 100)

		local startPosition = UDim2.new(0, randomX, 0, randomY)

		-- Animate with staggered delay (sequential)
		local delay = (i - 1) * CONFIG.BounceDelay

		animateCoinGui(coin, startPosition, targetPosition, delay, function()
			coinsCollected += 1

			-- Animate coin icon scale
				if targetCoinIcon and originalIconSize and originalIconAnchorPoint then
					animateCoinIconScale(targetCoinIcon, originalIconSize, originalIconAnchorPoint)
				end

				-- Play collection sound for each coin
				local collectSound = Instance.new("Sound")
			collectSound.SoundId = "rbxassetid://4612377122"
			collectSound.Volume = 0.3
			collectSound.PlaybackSpeed = 1 + (coinsCollected * 0.1) -- Pitch up
			collectSound.Parent = workspace
			collectSound:Play()
			task.delay(1, function()
				collectSound:Destroy()
			end)

				-- Reset coin icon when all coins are collected
				if coinsCollected == amount then
					print("All coins collected!")

				-- Reset coin icon to original state
					if targetCoinIcon and originalIconSize and originalIconPosition and originalIconAnchorPoint then
						task.wait(0.3) -- Small delay before reset
						resetCoinIcon(targetCoinIcon, originalIconSize, originalIconPosition, originalIconAnchorPoint)
					end

				end

				if targetCoinEmitter then
					stopCoinEmitter(targetCoinEmitter)
				end
			end)
		end
end

-- Quick spawn for common use cases
function CoinEffect.SpawnCoinReward(part: BasePart, amount: number, targetPlayer: Player?)
	local position = part.Position + Vector3.new(0, part.Size.Y / 2 + 2, 0)
	CoinEffect.SpawnCoins(position, amount, targetPlayer)
end

return CoinEffect
