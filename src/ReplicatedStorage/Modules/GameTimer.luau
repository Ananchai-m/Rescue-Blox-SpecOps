-- GameTimer ModuleScript
-- จัดการระบบ timer สำหรับเกม

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local GameTimer = {}

-- ตัวแปรสำหรับ timer
local timerGui = nil
local timerConnection = nil
local timerThread = nil
local player = Players.LocalPlayer
local emitterAttributeName = "CoinEffectOriginalEnabled"

local function attachCoinEmitter(targetCoinFrame: Frame)
	local effectsFolder = ReplicatedStorage:FindFirstChild("Effects")
	if not effectsFolder then
		warn("GameTimer: Effects folder not found in ReplicatedStorage")
		return nil
	end

	local emitterTemplate = effectsFolder:FindFirstChild("Emitter")
	if not emitterTemplate then
		warn("GameTimer: Emitter template not found under ReplicatedStorage.Effects")
		return nil
	end

	local emitterClone = emitterTemplate:Clone()
	emitterClone.Name = emitterTemplate.Name
	emitterClone.Parent = targetCoinFrame

	emitterClone:SetAttribute(emitterAttributeName, false)

	for _, descendant in emitterClone:GetDescendants() do
		local success, currentEnabled = pcall(function()
			return descendant.Enabled
		end)
		if success then
			descendant:SetAttribute(emitterAttributeName, false)
			if currentEnabled ~= false then
				pcall(function()
					descendant.Enabled = false
				end)
			end
		end
	end

	return emitterClone
end

-- ฟังก์ชันสร้าง Timer GUI
function GameTimer.createTimerGui()
	-- ลบ GUI เก่าถ้ามี
	if timerGui then
		timerGui:Destroy()
		timerGui = nil
	end

	-- หยุด timer connection เก่าถ้ามี
	if timerConnection then
		timerConnection:Disconnect()
		timerConnection = nil
	end

	-- หยุด timer thread เก่าถ้ามี
	if timerThread then
		task.cancel(timerThread)
		timerThread = nil
	end

	-- สร้าง ScreenGui
	timerGui = Instance.new("ScreenGui")
	timerGui.Name = "GameTimerGui"
	timerGui.ResetOnSpawn = false
	timerGui.IgnoreGuiInset = true
	timerGui.Parent = player.PlayerGui

	-- สร้าง Frame หลัก
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "TimerFrame"
	mainFrame.Size = UDim2.new(0.1, 0, 0.05, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0)
	mainFrame.Position = UDim2.new(0.5, 0, 0.05, 0) -- อยู่ตรงกลางด้านบน
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.5
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = timerGui

	local coinStroke = Instance.new("UIStroke")
	coinStroke.Color = Color3.fromRGB(255, 255, 255)
	coinStroke.Thickness = 2
	coinStroke.Parent = mainFrame

	-- สร้าง UICorner สำหรับ Frame
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = GameConfig.UI.smallCornerRadius
	frameCorner.Parent = mainFrame

	-- สร้าง TextLabel สำหรับแสดงเวลา
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 1, 0)
	timerLabel.Position = UDim2.new(0, 0, 0, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "05:00"
	timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timerLabel.TextScaled = true
	timerLabel.Font = Enum.Font.GothamBold
	timerLabel.Parent = mainFrame

	-- สร้าง Coin Frame ข้างๆ Timer
	local coinFrame = Instance.new("Frame")
	coinFrame.Name = "CoinFrame"
	coinFrame.AnchorPoint = Vector2.new(0.5, 0)
	coinFrame.Size = UDim2.new(0.15, 0, 0.05, 0)
	coinFrame.Position = UDim2.new(0.63, 0, 0.05, 0) -- ข้างๆ TimerFrame
	coinFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	coinFrame.BackgroundTransparency = 0.5
	coinFrame.BorderSizePixel = 0
	coinFrame.Parent = timerGui

	-- สร้าง UICorner สำหรับ CoinFrame
	local coinFrameCorner = Instance.new("UICorner")
	coinFrameCorner.CornerRadius = GameConfig.UI.smallCornerRadius
	coinFrameCorner.Parent = coinFrame

	-- สร้าง UIStroke สำหรับ CoinFrame
	local coinStroke = Instance.new("UIStroke")
	coinStroke.Color = Color3.fromRGB(255, 215, 0)
	coinStroke.Thickness = 2
	coinStroke.Parent = coinFrame

	attachCoinEmitter(coinFrame)

	-- สร้าง Coin Icon
	local coinIcon = Instance.new("ImageLabel")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.new(0.2, 0, 0.8, 0) -- Scale-based: 60% width, 80% height
	coinIcon.Position = UDim2.new(0.05, 0, 0.1, 0) -- Scale-based: 5% from left, 10% from top
	coinIcon.BackgroundTransparency = 1
	coinIcon.Image = "rbxassetid://124358779164505"
	coinIcon.ScaleType = Enum.ScaleType.Fit
	coinIcon.Parent = coinFrame

	-- สร้าง Coin Count Label
	local coinLabel = Instance.new("TextLabel")
	coinLabel.Name = "CoinLabel"
	coinLabel.Size = UDim2.new(0.7, 0, 1, 0) -- Scale-based: 35% width, full height
	coinLabel.Position = UDim2.new(0.3, 0, 0, 0) -- Scale-based: starts at 65% from left
	coinLabel.BackgroundTransparency = 1
	coinLabel.Text = "0"
	coinLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	coinLabel.TextScaled = true
	coinLabel.Font = Enum.Font.GothamBold
	coinLabel.TextStrokeTransparency = 0
	coinLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	coinLabel.TextXAlignment = Enum.TextXAlignment.Center
	coinLabel.Parent = coinFrame

	print("Game Timer GUI with Coin UI created")
	return timerLabel, coinLabel
end

-- ฟังก์ชันเริ่ม countdown
function GameTimer.startCountdown(duration)
	duration = duration or 300 -- default 5 minutes

	local timerLabel, coinLabel = GameTimer.createTimerGui()
	if not timerLabel then
		warn("Failed to create timer GUI")
		return
	end

	local timeLeft = duration

	-- เริ่ม timer
	timerThread = task.spawn(function()
		while timeLeft > 0 and timerGui and timerGui.Parent do
			-- อัปเดตการแสดงผล
			local minutes = math.floor(timeLeft / 60)
			local seconds = timeLeft % 60
			timerLabel.Text = string.format("%02d:%02d", minutes, seconds)

			-- เปลี่ยนสีเมื่อเวลาเหลือน้อย
			if timeLeft <= 60 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 100, 100) -- แดง
			elseif timeLeft <= 120 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100) -- เหลือง
			else
				timerLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- ขาว
			end

			timeLeft = timeLeft - 1
			task.wait(1)
		end

		-- เมื่อหมดเวลา
		if timerGui and timerGui.Parent then
			timerLabel.Text = "00:00"
			timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)

			print("Game timer finished!")

			-- เรียก callback function ถ้ามี
			if GameTimer.onTimerFinished then
				GameTimer.onTimerFinished()
			end
		end

		timerThread = nil -- ล้าง reference
	end)

	print("Game Timer started - " .. duration .. " seconds countdown")
end

-- ฟังก์ชันหยุด timer
function GameTimer.stopTimer()
	if timerConnection then
		timerConnection:Disconnect()
		timerConnection = nil
	end

	if timerThread then
		task.cancel(timerThread)
		timerThread = nil
	end

	if timerGui then
		timerGui:Destroy()
		timerGui = nil
	end

	print("Game timer stopped")
end

-- ฟังก์ชันตรวจสอบสถานะ timer
function GameTimer.isTimerActive()
	return timerThread ~= nil
end

-- ฟังก์ชัน callback เมื่อ timer จบ (สามารถ override ได้)
GameTimer.onTimerFinished = nil

-- ฟังก์ชันอัปเดต coin count
function GameTimer.updateCoinCount(count)
	if timerGui then
		local coinFrame = timerGui:FindFirstChild("CoinFrame")
		if coinFrame then
			local coinLabel = coinFrame:FindFirstChild("CoinLabel")
			if coinLabel then
				coinLabel.Text = tostring(count or 0)
			end
		end
	end
end

-- ฟังก์ชันเพิ่ม coins พร้อม animation
function GameTimer.addCoins(amount)
	if timerGui then
		local coinFrame = timerGui:FindFirstChild("CoinFrame")
		if coinFrame then
			local coinLabel = coinFrame:FindFirstChild("CoinLabel")
			local coinIcon = coinFrame:FindFirstChild("CoinIcon")
			if coinLabel and coinIcon then
				local currentCount = tonumber(coinLabel.Text) or 0
				local newCount = currentCount + amount
				coinLabel.Text = tostring(newCount)

				local TweenService = game:GetService("TweenService")

				-- Animation สำหรับ coin icon ด้วย UIScale
				local iconScale = coinIcon:FindFirstChild("CoinIconScale")
				if not iconScale then
					iconScale = Instance.new("UIScale")
					iconScale.Name = "CoinIconScale"
					iconScale.Scale = 1
					iconScale.Parent = coinIcon
				end

				local iconScaleUp = TweenService:Create(iconScale,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Scale = 1.2}
				)
				local iconScaleDown = TweenService:Create(iconScale,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{Scale = 1}
				)

				iconScaleUp:Play()
				iconScaleUp.Completed:Connect(function()
					iconScaleDown:Play()
				end)

				-- Animation สำหรับ coin label ด้วย UIScale
				local labelScale = coinLabel:FindFirstChild("CoinLabelScale")
				if not labelScale then
					labelScale = Instance.new("UIScale")
					labelScale.Name = "CoinLabelScale"
					labelScale.Scale = 1
					labelScale.Parent = coinLabel
				end

				local labelScaleUp = TweenService:Create(labelScale,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Scale = 1.3}
				)
				local labelScaleDown = TweenService:Create(labelScale,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{Scale = 1}
				)

				labelScaleUp:Play()
				labelScaleUp.Completed:Connect(function()
					labelScaleDown:Play()
				end)

				-- Text color flash
				local flashInfo = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				local flashTween = TweenService:Create(coinLabel, flashInfo, {
					TextColor3 = Color3.fromRGB(255, 255, 255)
				})
				flashTween:Play()

				flashTween.Completed:Connect(function()
					local returnTween = TweenService:Create(coinLabel, flashInfo, {
						TextColor3 = Color3.fromRGB(255, 215, 0)
					})
					returnTween:Play()
				end)
			end
		end
	end
end

-- ฟังก์ชันดู coin count ปัจจุบัน
function GameTimer.getCoinCount()
	if timerGui then
		local coinFrame = timerGui:FindFirstChild("CoinFrame")
		if coinFrame then
			local coinLabel = coinFrame:FindFirstChild("CoinLabel")
			if coinLabel then
				return tonumber(coinLabel.Text) or 0
			end
		end
	end
	return 0
end

return GameTimer
