-- GameTimer ModuleScript
-- จัดการระบบ timer สำหรับเกม

local Players = game:GetService("Players")

local GameTimer = {}

-- ตัวแปรสำหรับ timer
local timerGui = nil
local timerConnection = nil
local player = Players.LocalPlayer

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

	-- สร้าง ScreenGui
	timerGui = Instance.new("ScreenGui")
	timerGui.Name = "GameTimerGui"
	timerGui.ResetOnSpawn = false
	timerGui.IgnoreGuiInset = true
	timerGui.Parent = player.PlayerGui

	-- สร้าง Frame หลัก
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "TimerFrame"
	mainFrame.Size = UDim2.new(0.2, 0, 0.08, 0)
	mainFrame.Position = UDim2.new(0.4, 0, 0.05, 0) -- อยู่ตรงกลางด้านบน
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.3
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = timerGui

	-- สร้าง UICorner สำหรับ Frame
	local frameCorner = Instance.new("UICorner")
	frameCorner.CornerRadius = UDim.new(0, 8)
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

	print("Game Timer GUI created")
	return timerLabel
end

-- ฟังก์ชันเริ่ม countdown
function GameTimer.startCountdown(duration)
	duration = duration or 300 -- default 5 minutes

	local timerLabel = GameTimer.createTimerGui()
	if not timerLabel then
		warn("Failed to create timer GUI")
		return
	end

	local timeLeft = duration

	-- ฟังก์ชันอัปเดตเวลา
	local function updateTimer()
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

		-- เมื่อหมดเวลา
		if timeLeft < 0 then
			timerLabel.Text = "00:00"
			timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
			if timerConnection then
				timerConnection:Disconnect()
				timerConnection = nil
			end
			print("Game timer finished!")

			-- เรียก callback function ถ้ามี
			if GameTimer.onTimerFinished then
				GameTimer.onTimerFinished()
			end
		end
	end

	-- เริ่ม timer
	timerConnection = task.spawn(function()
		while timeLeft >= 0 and timerGui and timerGui.Parent do
			updateTimer()
			task.wait(1)
		end
	end)

	print("Game Timer started - " .. duration .. " seconds countdown")
end

-- ฟังก์ชันหยุด timer
function GameTimer.stopTimer()
	if timerConnection then
		timerConnection:Disconnect()
		timerConnection = nil
	end

	if timerGui then
		timerGui:Destroy()
		timerGui = nil
	end

	print("Game timer stopped")
end

-- ฟังก์ชันตรวจสอบสถานะ timer
function GameTimer.isTimerActive()
	return timerConnection ~= nil
end

-- ฟังก์ชัน callback เมื่อ timer จบ (สามารถ override ได้)
GameTimer.onTimerFinished = nil

return GameTimer