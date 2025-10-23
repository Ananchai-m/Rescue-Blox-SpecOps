-- AftershockClient.client.luau
-- จัดการ Camera Shake เมื่อมี Aftershock

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- รอ RemoteEvent
local rescueRemotes = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local aftershockWarningRemote = rescueRemotes:WaitForChild("AftershockWarning")

-- Camera Shake Variables
local isShaking = false
local shakeConnection = nil

-- Config
local SHAKE_CONFIG = {
	warningDuration = 3, -- เวลาสั่นเตือน (วินาที)
	warningIntensity = 0.1, -- ความแรงของการสั่นเตือน
	aftershockDuration = 2, -- เวลาสั่นหลัง aftershock เริ่ม (วินาที)
	aftershockIntensity = 0.3, -- ความแรงของการสั่นหลัง aftershock
	frequency = 20, -- ความถี่ของการสั่น (Hz)
}

-- ฟังก์ชันสั่นกล้อง
local function shakeCamera(duration, intensity)
	if isShaking then
		return
	end

	isShaking = true
	local startTime = tick()
	local originalCFrame = camera.CFrame

	-- หยุด shake connection เก่า
	if shakeConnection then
		shakeConnection:Disconnect()
		shakeConnection = nil
	end

	shakeConnection = RunService.RenderStepped:Connect(function()
		local elapsed = tick() - startTime

		if elapsed >= duration then
			-- หยุดสั่น
			if shakeConnection then
				shakeConnection:Disconnect()
				shakeConnection = nil
			end
			isShaking = false
			return
		end

		-- คำนวณความแรงของการสั่น (ลดลงเมื่อเวลาผ่านไป)
		local fadeOut = 1 - (elapsed / duration)
		local currentIntensity = intensity * fadeOut

		-- สุ่มทิศทางการสั่น
		local shakeOffset = Vector3.new(
			math.random(-100, 100) / 100 * currentIntensity,
			math.random(-100, 100) / 100 * currentIntensity,
			math.random(-100, 100) / 100 * currentIntensity
		)

		-- สุ่มมุมการหมุน
		local shakeRotation = CFrame.Angles(
			math.rad(math.random(-5, 5) * currentIntensity),
			math.rad(math.random(-5, 5) * currentIntensity),
			math.rad(math.random(-5, 5) * currentIntensity)
		)

		-- ใช้ CFrame ของกล้องปัจจุบัน + offset
		camera.CFrame = camera.CFrame * CFrame.new(shakeOffset) * shakeRotation
	end)

	print(string.format("[Aftershock Client] Camera shake started - Duration: %.1fs, Intensity: %.2f", duration, intensity))
end

-- ฟังก์ชันหยุดสั่นกล้อง
local function stopShake()
	if shakeConnection then
		shakeConnection:Disconnect()
		shakeConnection = nil
	end
	isShaking = false
	print("[Aftershock Client] Camera shake stopped")
end

-- รับสัญญาณจาก server
aftershockWarningRemote.OnClientEvent:Connect(function(action)
	if action == "warning" then
		print("[Aftershock Client] Warning received - Camera shaking!")
		-- สั่นกล้องเตือน (น้อย)
		shakeCamera(SHAKE_CONFIG.warningDuration, SHAKE_CONFIG.warningIntensity)

		-- แสดงข้อความเตือน
		local StarterGui = game:GetService("StarterGui")
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = "[AFTERSHOCK WARNING] Earthquake detected! Take cover!",
				Color = Color3.fromRGB(255, 100, 100),
				Font = Enum.Font.GothamBold,
				FontSize = Enum.FontSize.Size24,
			})
		end)

	elseif action == "start" then
		print("[Aftershock Client] Aftershock started - Intense shake!")
		-- หยุดการสั่นเตือน
		stopShake()

		-- สั่นกล้องแรง
		task.wait(0.1)
		shakeCamera(SHAKE_CONFIG.aftershockDuration, SHAKE_CONFIG.aftershockIntensity)

		-- แสดงข้อความ
		local StarterGui = game:GetService("StarterGui")
		pcall(function()
			StarterGui:SetCore("ChatMakeSystemMessage", {
				Text = "[AFTERSHOCK] Rocks falling! Watch out!",
				Color = Color3.fromRGB(255, 50, 50),
				Font = Enum.Font.GothamBold,
				FontSize = Enum.FontSize.Size24,
			})
		end)
	elseif action == "stop" then
		print("[Aftershock Client] Aftershock stop signal received - clearing shake")
		stopShake()
	end
end)

-- Cleanup เมื่อผู้เล่นออก
player.CharacterRemoving:Connect(function()
	stopShake()
end)

print("[Aftershock Client] System initialized")
