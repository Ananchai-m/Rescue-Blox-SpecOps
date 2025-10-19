--!strict
-- MobileRescueBotController.client.luau
-- Touch-to-Move system for mobile devices

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- ตรวจสอบว่าเป็น mobile หรือไม่
local function isMobileDevice(): boolean
	local touchEnabled = UserInputService.TouchEnabled
	local keyboardEnabled = UserInputService.KeyboardEnabled
	return touchEnabled and not keyboardEnabled
end

local isMobile = isMobileDevice()

if not isMobile then
	print("[MobileTouchControl] Not a mobile device - skipping mobile controller")
	return
end

print("[MobileTouchControl] Mobile device detected - Enabling touch-to-move controls")

-- รอให้ PlayerGui พร้อม
local playerGui = player:WaitForChild("PlayerGui")

-- Import VehicleController module
local VehicleController = require(ReplicatedStorage.Modules.VehicleController)

-- Remote events
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes") :: Folder
local controlOriginalRescueEvent = remoteEvents:WaitForChild("ControlOriginalRescue") :: RemoteEvent

-- ตัวแปรสำหรับ Drag-to-Move
local touchStartPosition: Vector2? = nil
local touchCurrentPosition: Vector2? = nil
local touchActive = false
local touchInputObject: InputObject? = nil

-- ตัวแปรสำหรับ RescueBot
local rescueBotModel: Model? = nil
local isBotControlActive = false
local updateConnection: RBXScriptConnection? = nil

-- Constants
local DRAG_SENSITIVITY_STEER = 1.2 -- ความไวในการเลี้ยว (ยิ่งมากยิ่งไว)
local DRAG_SENSITIVITY_THROTTLE = 1.0 -- ความไวในการเร่ง/ถอย
local DRAG_DEADZONE = 20 -- พื้นที่ตายกลาง (pixels)
local MAX_DRAG_DISTANCE = 150 -- ระยะลากสูงสุด (pixels)

-- Forward declaration
local stopRescueBotControl: () -> ()

-- ฟังก์ชันคำนวณ throttle และ steer จากการลาก (Drag)
local function calculateControlsFromDrag(): (number, number)
	if not touchActive or not touchStartPosition or not touchCurrentPosition then
		return 0, 0
	end

	-- คำนวณระยะห่างจากจุดเริ่มต้น (Delta)
	local deltaX = touchCurrentPosition.X - touchStartPosition.X
	local deltaY = touchCurrentPosition.Y - touchStartPosition.Y

	-- คำนวณ throttle (Y axis)
	-- ลากขึ้น (deltaY < 0) = ไปข้างหน้า (positive)
	-- ลากลง (deltaY > 0) = ถอยหลัง (negative)
	local throttle = 0
	if math.abs(deltaY) > DRAG_DEADZONE then
		local normalizedY = -deltaY / MAX_DRAG_DISTANCE -- กลับเครื่องหมายเพราะ Y axis กลับกัน
		throttle = math.clamp(normalizedY * DRAG_SENSITIVITY_THROTTLE, -1, 1)
	end

	-- คำนวณ steer (X axis)
	-- ลากซ้าย (deltaX < 0) = เลี้ยวซ้าย (positive)
	-- ลากขวา (deltaX > 0) = เลี้ยวขวา (negative)
	local steer = 0
	if math.abs(deltaX) > DRAG_DEADZONE then
		local normalizedX = deltaX / MAX_DRAG_DISTANCE
		steer = math.clamp(normalizedX * DRAG_SENSITIVITY_STEER, -1, 1)
	end

	return throttle, steer
end

-- ฟังก์ชันหา RescueBot ของผู้เล่น
local function findPlayerRescueBot(): Model?
	local botName = player.Name .. "_Rescue"
	return Workspace:FindFirstChild(botName) :: Model?
end

-- ฟังก์ชันซ่อน character
local function hideCharacter(hide: boolean)
	local character = player.Character
	if not character then return end

	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			if hide then
				part.Transparency = 1
			elseif part.Name == "Head" then
				part.Transparency = 0
			end
		elseif part:IsA("Decal") then
			part.Transparency = hide and 1 or part.Transparency
		elseif part:IsA("Accessory") then
			local handle = part:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then
				handle.Transparency = hide and 1 or 0
			end
		end
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		humanoid.WalkSpeed = hide and 0 or 16
	end
end

-- ฟังก์ชันบังคับควบคุม RescueBot
local function startRescueBotControl()
	if isBotControlActive then
		print("[MobileTouchControl] Already controlling bot")
		return
	end

	rescueBotModel = findPlayerRescueBot()

	if not rescueBotModel then
		warn("[MobileTouchControl] RescueBot not found:", player.Name .. "_Rescue")
		return
	end

	local rescuePrimaryPart = rescueBotModel.PrimaryPart
	if not rescuePrimaryPart then
		warn("[MobileTouchControl] RescueBot has no PrimaryPart")
		return
	end

	isBotControlActive = true

	-- ตั้งค่ากล้อง
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = rescuePrimaryPart

	-- ซ่อน character
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = true
			humanoid.WalkSpeed = 0
		end

		if character.PrimaryPart then
			character.PrimaryPart.Anchored = true
			character:SetPrimaryPartCFrame(CFrame.new(0, -500, 0))
		end

		hideCharacter(true)
	end

	print("[MobileTouchControl] Now controlling RescueBot:", rescueBotModel.Name)
	print("[MobileTouchControl] Drag to control: Up=Forward, Down=Backward, Left=Left, Right=Right")

	-- สร้าง connection เพื่อส่ง input ไปยัง server
	updateConnection = RunService.Heartbeat:Connect(function()
		if not rescueBotModel or not rescueBotModel.Parent then
			print("[MobileTouchControl] RescueBot destroyed - stopping control")
			stopRescueBotControl()
			return
		end

		-- คำนวณ throttle และ steer จากการลาก (Drag)
		local throttle, steer = calculateControlsFromDrag()

		-- ตั้งค่า input ใน VehicleController
		VehicleController.setThrottleInput(throttle)
		VehicleController.setSteerInput(-steer) -- กลับทิศให้ตรงกับ PC

		-- ส่งไปยัง server
		controlOriginalRescueEvent:FireServer(throttle, -steer)
	end)
end

-- ฟังก์ชันหยุดควบคุม RescueBot
function stopRescueBotControl()
	if not isBotControlActive then return end

	isBotControlActive = false

	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	-- รีเซ็ตสถานะ touch
	touchActive = false
	touchStartPosition = nil
	touchCurrentPosition = nil
	touchInputObject = nil

	-- คืน camera กลับมาที่ character
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
			humanoid.PlatformStand = false
			humanoid.WalkSpeed = 16
		end

		if character.PrimaryPart then
			character.PrimaryPart.Anchored = false
		end

		hideCharacter(false)
	end

	player.CameraMode = Enum.CameraMode.Classic

	rescueBotModel = nil
	print("[MobileTouchControl] Stopped controlling RescueBot")
end

-- Drag input handling
local function handleTouchBegan(touch: InputObject)
	if not isBotControlActive then return end

	-- ตรวจสอบว่ามี RescueBillboard active อยู่หรือไม่ (อยู่ใน Workspace)
	local victimFolder = workspace:FindFirstChild("VictimFolders")
	if victimFolder then
		for _, victim in ipairs(victimFolder:GetChildren()) do
			local billboard = victim:FindFirstChild("RescueBillboard")
			if billboard and billboard:IsA("BillboardGui") and billboard.Enabled then
				print("[MobileTouchControl] Found active RescueBillboard, ignoring touch")
				return
			end
		end
	end

	-- บันทึกจุดเริ่มต้นของการลาก
	touchActive = true
	touchStartPosition = Vector2.new(touch.Position.X, touch.Position.Y)
	touchCurrentPosition = Vector2.new(touch.Position.X, touch.Position.Y)
	touchInputObject = touch

	print("[MobileTouchControl] Drag started at:", touchStartPosition)
end

local function handleTouchMoved(touch: InputObject)
	if not isBotControlActive then return end
	if not touchInputObject then return end

	-- อัปเดตตำแหน่งปัจจุบันของการลาก ถ้าเป็น touch object เดียวกัน
	if touch == touchInputObject then
		local currentPos = Vector2.new(touch.Position.X, touch.Position.Y)
		touchCurrentPosition = currentPos

		-- Debug: แสดงระยะห่างที่ลาก
		if touchStartPosition then
			local deltaX = currentPos.X - touchStartPosition.X
			local deltaY = currentPos.Y - touchStartPosition.Y
			-- print(string.format("[Drag] deltaX: %.1f, deltaY: %.1f", deltaX, deltaY))
		end
	end
end

local function handleTouchEnded(touch: InputObject)
	if not isBotControlActive then return end

	-- รีเซ็ตสถานะ touch ถ้าเป็น touch object เดียวกัน
	if touch == touchInputObject then
		touchActive = false
		touchStartPosition = nil
		touchCurrentPosition = nil
		touchInputObject = nil

		print("[MobileTouchControl] Drag ended")
	end
end

-- เชื่อมต่อ Touch events
UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
	if gameProcessed then return end
	handleTouchBegan(touch)
end)

UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
	handleTouchMoved(touch)
end)

UserInputService.TouchEnded:Connect(function(touch, gameProcessed)
	handleTouchEnded(touch)
end)

-- Mouse input handling (สำหรับทดสอบใน Studio)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		-- ตรวจสอบว่ามี RescueBillboard active อยู่หรือไม่ (อยู่ใน Workspace)
		local victimFolder = workspace:FindFirstChild("VictimFolders")
		if victimFolder then
			for _, victim in ipairs(victimFolder:GetChildren()) do
				local billboard = victim:FindFirstChild("RescueBillboard")
				if billboard and billboard:IsA("BillboardGui") and billboard.Enabled then
					print("[MobileTouchControl] Found active RescueBillboard, ignoring mouse")
					return
				end
			end
		end
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mockTouch = {
			Position = input.Position,
			UserInputType = Enum.UserInputType.Touch,
		}
		handleTouchBegan(input)
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if touchActive and touchInputObject then
			local mockInput = input
			if touchInputObject.UserInputType == Enum.UserInputType.MouseButton1 then
				handleTouchMoved(input)
			end
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		handleTouchEnded(input)
	end
end)

-- ตรวจสอบ RescueBot ทุกๆ 1 วินาที
local function monitorRescueBot()
	while true do
		task.wait(1)

		local bot = findPlayerRescueBot()

		if bot and not isBotControlActive then
			print("[MobileTouchControl] RescueBot detected - Starting auto-control")
			startRescueBotControl()
		elseif not bot and isBotControlActive then
			print("[MobileTouchControl] RescueBot not found - Stopping control")
			stopRescueBotControl()
		end
	end
end

-- เริ่มระบบ monitor
task.spawn(monitorRescueBot)

-- Handle character respawn
player.CharacterAdded:Connect(function(newCharacter)
	if isBotControlActive then
		-- ซ่อน character ใหม่ทันที
		task.wait(0.5)
		hideCharacter(true)

		local humanoid = newCharacter:WaitForChild("Humanoid") :: Humanoid
		humanoid.PlatformStand = true
		humanoid.WalkSpeed = 0

		if newCharacter.PrimaryPart then
			newCharacter.PrimaryPart.Anchored = true
			newCharacter:SetPrimaryPartCFrame(CFrame.new(0, -500, 0))
		end
	end
end)

print("[MobileTouchControl] Mobile touch-to-move controller initialized - Waiting for RescueBot...")
