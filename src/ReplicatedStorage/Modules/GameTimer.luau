-- GameTimer ModuleScript
-- จัดการระบบ timer สำหรับเกม

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local GameTimer = {}

-- ตัวแปรสำหรับ timer
local timerGui = nil
local timerConnection = nil
local timerThread = nil
local player = Players.LocalPlayer
local emitterAttributeName = "CoinEffectOriginalEnabled"
local countdownSound = nil -- เก็บ Sound instance ของเสียงนับถอยหลัง

-- RemoteEvent สำหรับ sync เสียงนับถอยหลัง (จะถูก setup จาก client script)
local rescueRemotes = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local countdownSoundRemote = nil

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

	emitterClone:SetAttribute(emitterAttributeName, 0)

	for _, descendant in emitterClone:GetDescendants() do
		local success, currentEnabled = pcall(function()
			return descendant.Enabled
		end)
		if success then
			descendant:SetAttribute(emitterAttributeName, 0)
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
	timerLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
	timerLabel.AnchorPoint = Vector2.new(0.5, 0.5) -- Scale จากจุดกลาง
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

	-- สร้าง UIScale สำหรับแอนิเมชัน
	local timerScale = Instance.new("UIScale")
	timerScale.Name = "TimerScale"
	timerScale.Scale = 1
	timerScale.Parent = timerLabel

	-- เริ่ม timer
	timerThread = task.spawn(function()
		local lastSyncTime = 0 -- เวลาที่ sync ครั้งล่าสุด
		local isFirstSync = true -- ตัวแปรเช็คว่าเป็น sync ครั้งแรกหรือไม่

		while timeLeft > 0 and timerGui and timerGui.Parent do
			-- อัปเดตการแสดงผล
			local minutes = math.floor(timeLeft / 60)
			local seconds = timeLeft % 60
			local timeText = string.format("%02d:%02d", minutes, seconds)
			timerLabel.Text = timeText

			-- Sync เวลาไปยัง server (ครั้งแรกทันที แล้วทุก 5 วินาที)
			if isFirstSync or tick() - lastSyncTime >= 5 then
				local gameTimerRemote = ReplicatedStorage:FindFirstChild("RescueBotRemotes"):FindFirstChild("GameTimer")
				if gameTimerRemote then
					-- ส่งทั้ง timeLeft และ timeText (MM:SS) ไปด้วย
					gameTimerRemote:FireServer("syncTime", timeLeft, timeText)
					print("[GameTimer] Synced time to server:", timeText)
				end
				lastSyncTime = tick()
				isFirstSync = false
			end

			-- เปลี่ยนสีและเพิ่มเอฟเฟกต์เมื่อเวลาเหลือน้อย
			if timeLeft <= 60 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 100, 100) -- แดง

				-- เล่นเสียงนับถอยหลังเมื่อเหลือ 60 วินาทีลงไป
				if timeLeft == 60 then
					-- สร้างเสียงนับถอยหลัง
					if countdownSound then
						countdownSound:Stop()
						countdownSound:Destroy()
					end

					countdownSound = Instance.new("Sound")
					countdownSound.SoundId = "rbxassetid://74033679363032"
					countdownSound.Volume = 0.1 -- เริ่มจากเสียงเบาๆ
					countdownSound.Looped = true
					countdownSound.Parent = timerLabel
					countdownSound:Play()

					print("[GameTimer] Started countdown sound")
				end

				-- ค่อยๆ เพิ่มความดังของเสียงตามเวลาที่เหลือ
				if countdownSound and countdownSound.IsPlaying then
					-- คำนวณ volume ตามเวลา: 60s = 0.1, 30s = 0.35, 10s = 0.6, 1s = 0.8
					local progress = (60 - timeLeft) / 60 -- 0 ถึง 1
					local targetVolume = 0.1 + (progress * 0.7) -- 0.1 ถึง 0.8

					-- ตั้งค่า volume โดยตรงให้ดังขึ้นเรื่อยๆ
					countdownSound.Volume = targetVolume
				end

				-- แอนิเมชัน scale แบบตื่นเต้นเมื่อเหลือ 10 วินาทีสุดท้าย
				if timeLeft <= 10 then
					-- Scale ขึ้น-ลงแบบรวดเร็ว
					local scaleUp = TweenService:Create(timerScale,
						TweenInfo.new(0.3, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
						{Scale = 1.4}
					)
					local scaleDown = TweenService:Create(timerScale,
						TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{Scale = 1}
					)

					scaleUp:Play()
					scaleUp.Completed:Connect(function()
						scaleDown:Play()
					end)

					-- สั่นกรอบเล็กน้อย
					local mainFrame = timerLabel.Parent
					if mainFrame then
						local originalPos = mainFrame.Position

						-- สั่น 3 ครั้ง
						for i = 1, 3 do
							task.spawn(function()
								local offset = i * 0.1
								local shakeRight = TweenService:Create(mainFrame,
									TweenInfo.new(0.05, Enum.EasingStyle.Linear),
									{Position = UDim2.new(originalPos.X.Scale + 0.005, 0, originalPos.Y.Scale, 0)}
								)
								local shakeLeft = TweenService:Create(mainFrame,
									TweenInfo.new(0.05, Enum.EasingStyle.Linear),
									{Position = UDim2.new(originalPos.X.Scale - 0.005, 0, originalPos.Y.Scale, 0)}
								)
								local shakeBack = TweenService:Create(mainFrame,
									TweenInfo.new(0.05, Enum.EasingStyle.Linear),
									{Position = originalPos}
								)

								task.wait(offset)
								shakeRight:Play()
								shakeRight.Completed:Wait()
								shakeLeft:Play()
								shakeLeft.Completed:Wait()
								shakeBack:Play()
							end)
						end
					end
				elseif timeLeft <= 30 then
					-- Scale แบบปกติเมื่อเหลือ 30 วินาทีลงไป
					local scaleUp = TweenService:Create(timerScale,
						TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
						{Scale = 1.2}
					)
					local scaleDown = TweenService:Create(timerScale,
						TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
						{Scale = 1}
					)

					scaleUp:Play()
					scaleUp.Completed:Connect(function()
						scaleDown:Play()
					end)
				end
			elseif timeLeft <= 120 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 255, 100) -- เหลือง

				-- Scale เล็กน้อยเมื่อเหลือ 2 นาที
				local scaleUp = TweenService:Create(timerScale,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Scale = 1.1}
				)
				local scaleDown = TweenService:Create(timerScale,
					TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{Scale = 1}
				)

				scaleUp:Play()
				scaleUp.Completed:Connect(function()
					scaleDown:Play()
				end)
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

			-- หยุดเสียงนับถอยหลัง
			if countdownSound then
				countdownSound:Stop()
				countdownSound:Destroy()
				countdownSound = nil
				print("[GameTimer] Countdown sound stopped")
			end

			print("Game timer finished!")

			-- ลบ DrillProgressGui ก่อนเรียก callback
			local playerGui = player:WaitForChild("PlayerGui")
			local drillProgressGui = playerGui:FindFirstChild("DrillProgressGui")
			if drillProgressGui then
				drillProgressGui:Destroy()
				print("[GameTimer] Cleared DrillProgressGui before showing summary")
			end

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

	-- หยุดและลบเสียงนับถอยหลัง
	if countdownSound then
		countdownSound:Stop()
		countdownSound:Destroy()
		countdownSound = nil
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
	if not timerGui then return end
	if not amount or amount == 0 then return end

	local coinFrame = timerGui:FindFirstChild("CoinFrame")
	if not coinFrame then return end

	local coinLabel = coinFrame:FindFirstChild("CoinLabel")
	local coinIcon = coinFrame:FindFirstChild("CoinIcon")
	if not (coinLabel and coinIcon) then return end

	local currentCount = tonumber(coinLabel.Text) or 0
	local newCount = currentCount + amount
	if newCount < 0 then
		newCount = 0
	end

	local delta = newCount - currentCount
	if delta == 0 then
		return
	end

	coinLabel.Text = tostring(newCount)

	if delta > 0 then
		local TweenService = game:GetService("TweenService")

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
	else
		local originalColor = Color3.fromRGB(255, 215, 0)
		coinLabel.TextColor3 = Color3.fromRGB(255, 85, 85)
		task.delay(0.35, function()
			if coinLabel and coinLabel.Parent then
				coinLabel.TextColor3 = originalColor
			end
		end)
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

-- ฟังก์ชันเคลียร์ coins (รีเซ็ตเป็น 0)
function GameTimer.clearCoins()
	if timerGui then
		local coinFrame = timerGui:FindFirstChild("CoinFrame")
		if coinFrame then
			local coinLabel = coinFrame:FindFirstChild("CoinLabel")
			if coinLabel then
				coinLabel.Text = "0"
				print("[GameTimer] Coins cleared")
			end
		end
	end
end


-- ฟังก์ชันเริ่มเสียงนับถอยหลัง (เรียกจาก client script)
function GameTimer.startCountdownSound()
	if timerGui and timerGui:FindFirstChild("TimerFrame") then
		local timerFrame = timerGui.TimerFrame
		local timerLabel = timerFrame:FindFirstChild("TimerLabel")

		if timerLabel then
			-- หยุดเสียงเก่าถ้ามี
			if countdownSound then
				countdownSound:Stop()
				countdownSound:Destroy()
			end

			-- สร้างเสียงใหม่
			countdownSound = Instance.new("Sound")
			countdownSound.SoundId = "rbxassetid://74033679363032"
			countdownSound.Volume = 0.1 -- เริ่มจากเสียงเบาๆ
			countdownSound.Looped = true
			countdownSound.Parent = timerLabel
			countdownSound:Play()

			print("[GameTimer] Started countdown sound (synced)")
		end
	end
end

-- ฟังก์ชันหยุดเสียงนับถอยหลัง (เรียกจาก client script)
function GameTimer.stopCountdownSound()
	if countdownSound then
		countdownSound:Stop()
		countdownSound:Destroy()
		countdownSound = nil
		print("[GameTimer] Stopped countdown sound (synced)")
	end
end

return GameTimer
