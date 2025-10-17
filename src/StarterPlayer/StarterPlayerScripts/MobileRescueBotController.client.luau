--!strict
-- MobileRescueBotController.client.luau
-- บังคับให้ mobile ควบคุม Player.Name_Rescue แทน character และใช้ on-screen controls

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

	-- ถ้ามี touch แต่ไม่มี keyboard = mobile
	return touchEnabled and not keyboardEnabled
end

-- ตรวจสอบอุปกรณ์จริง
local isMobile = isMobileDevice()

if not isMobile then
	print("[MobileRescueBot] Not a mobile device - skipping mobile controller")
	return
end

print("[MobileRescueBot] Mobile device detected - Enabling on-screen controls")

-- เปิด on-screen controls สำหรับ mobile
UserInputService.ModalEnabled = false
-- ไม่ซ่อน mouse cursor (สำหรับทดสอบใน Studio)
-- UserInputService.MouseIconEnabled = false

-- รอให้ PlayerGui พร้อม
local playerGui = player:WaitForChild("PlayerGui")

-- ซ่อนปุ่มกระโดดของ TouchGui เพื่อไม่ให้ทับ UI
local function hideDefaultJumpButton()
	local touchGui = playerGui:FindFirstChild("TouchGui")
	if not touchGui then
		return
	end

	local jumpButton = touchGui:FindFirstChild("JumpButton", true)
	if jumpButton and jumpButton:IsA("GuiButton") then
		jumpButton.Visible = false
		jumpButton.Active = false
	end

	touchGui.DescendantAdded:Connect(function(desc)
		if desc.Name == "JumpButton" and desc:IsA("GuiButton") then
			task.defer(function()
				desc.Visible = false
				desc.Active = false
			end)
		end
	end)
end

playerGui.ChildAdded:Connect(function(child)
	if child.Name == "TouchGui" then
		task.defer(hideDefaultJumpButton)
	end
end)

hideDefaultJumpButton()

-- สร้าง ScreenGui สำหรับ controls
local controlsGui = Instance.new("ScreenGui")
controlsGui.Name = "MobileControlsGui"
controlsGui.ResetOnSpawn = false
controlsGui.IgnoreGuiInset = true
controlsGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
controlsGui.Parent = playerGui

-- Import VehicleController module
local VehicleController = require(ReplicatedStorage.Modules.VehicleController)

-- Remote events
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes") :: Folder
local controlOriginalRescueEvent = remoteEvents:WaitForChild("ControlOriginalRescue") :: RemoteEvent
local stopOriginalRescueEvent = remoteEvents:WaitForChild("StopOriginalRescue") :: RemoteEvent

-- ตัวแปรสำหรับ touch controls
type MouseKey = { kind: "Mouse" }
type InputKey = InputObject | MouseKey

type JoystickState = {
	active: boolean,
	inputObject: InputObject?,
	inputKey: InputKey?,
	startPos: Vector2,
	currentPos: Vector2,
	frame: Frame?,
	knob: Frame?,
}

local leftJoystick: JoystickState = {
	active = false,
	inputObject = nil,
	inputKey = nil,
	startPos = Vector2.new(0, 0),
	currentPos = Vector2.new(0, 0),
	frame = nil,
	knob = nil,
}

local rightJoystick: JoystickState = {
	active = false,
	inputObject = nil,
	inputKey = nil,
	startPos = Vector2.new(0, 0),
	currentPos = Vector2.new(0, 0),
	frame = nil,
	knob = nil,
}

local MAX_JOYSTICK_DISTANCE = 50
local MOUSE_INPUT_KEY: MouseKey = { kind = "Mouse" }

local function toVector2(position: Vector2 | Vector3): Vector2
	if typeof(position) == "Vector3" then
		local v3 = position :: Vector3
		return Vector2.new(v3.X, v3.Y)
	end

	return position :: Vector2
end

local function getInputPosition(input: InputObject): Vector2
	return toVector2(input.Position)
end

local function getInputKey(input: InputObject): InputKey
	if input.UserInputType == Enum.UserInputType.Touch then
		return input
	end

	return MOUSE_INPUT_KEY
end

-- สร้าง Joystick UI (ซ้าย = throttle, ขวา = steer)
type JoystickUI = {
	frame: Frame,
	knob: Frame,
	blocker: TextButton,
}

local function createJoystick(name: string, position: UDim2): JoystickUI
	local joystickFrame = Instance.new("Frame")
	joystickFrame.Name = name
	joystickFrame.Size = UDim2.fromScale(0.15, 0.25)
	joystickFrame.Position = position
	joystickFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	joystickFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	joystickFrame.BackgroundTransparency = 0.5
	joystickFrame.BorderSizePixel = 0
	joystickFrame.Parent = controlsGui

	-- สร้าง TextButton แทน Frame เพราะสามารถบล็อค input ได้ดีกว่า
	local blocker = Instance.new("TextButton")
	blocker.Name = "Blocker"
	blocker.Text = "" -- ไม่แสดงข้อความ
	blocker.Size = UDim2.fromScale(2, 2) -- ขยายเป็น 2 เท่า เพื่อครอบคลุมพื้นที่ลาก
	blocker.Position = UDim2.fromScale(-0.5, -0.5) -- จัดกลาง
	blocker.AnchorPoint = Vector2.new(0, 0)
	blocker.BackgroundTransparency = 1 -- โปร่งใสสนิท
	blocker.Modal = false -- ปิดตอนเริ่มต้น
	blocker.Active = false
	blocker.ZIndex = 100
	blocker.Parent = joystickFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = joystickFrame

	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromScale(0.4, 0.4)
	knob.Position = UDim2.fromScale(0.5, 0.5)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.BackgroundTransparency = 0.3
	knob.BorderSizePixel = 0
	knob.Parent = joystickFrame

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	return {frame = joystickFrame, knob = knob, blocker = blocker}
end

-- สร้าง joysticks
local leftJoyUI = createJoystick("LeftJoystick", UDim2.fromScale(0.15, 0.75))
leftJoystick.frame = leftJoyUI.frame
leftJoystick.knob = leftJoyUI.knob
local leftBlocker = leftJoyUI.blocker

local rightJoyUI = createJoystick("RightJoystick", UDim2.fromScale(0.85, 0.75))
rightJoystick.frame = rightJoyUI.frame
rightJoystick.knob = rightJoyUI.knob
local rightBlocker = rightJoyUI.blocker

-- ฟังก์ชันคำนวณ input จาก joystick
local function getJoystickInput(joystick: JoystickState): number
	if not joystick.active then
		return 0
	end

	local delta = joystick.currentPos - joystick.startPos

	if joystick == leftJoystick then
		-- Throttle: ใช้แกน Y (up = positive, down = negative)
		local clampedY = math.clamp(-delta.Y, -MAX_JOYSTICK_DISTANCE, MAX_JOYSTICK_DISTANCE)
		return clampedY / MAX_JOYSTICK_DISTANCE
	else
		-- Steering: ใช้แกน X (right = positive, left = negative)
		local clampedX = math.clamp(delta.X, -MAX_JOYSTICK_DISTANCE, MAX_JOYSTICK_DISTANCE)
		return clampedX / MAX_JOYSTICK_DISTANCE
	end
end

-- อัปเดต knob position
local function updateKnobPosition(joystick: JoystickState)
	if not joystick.active or not joystick.frame or not joystick.knob then
		if joystick.knob then
			joystick.knob.Position = UDim2.fromScale(0.5, 0.5)
		end
		return
	end

	-- Type assertion หลังจากเช็คแล้ว
	local frame = joystick.frame :: Frame
	local knob = joystick.knob :: Frame

	local delta = joystick.currentPos - joystick.startPos
	local clampedDelta

	if joystick == leftJoystick then
		local clampedY = math.clamp(delta.Y, -MAX_JOYSTICK_DISTANCE, MAX_JOYSTICK_DISTANCE)
		clampedDelta = Vector2.new(0, clampedY)
	else
		local clampedX = math.clamp(delta.X, -MAX_JOYSTICK_DISTANCE, MAX_JOYSTICK_DISTANCE)
		clampedDelta = Vector2.new(clampedX, 0)
	end

	-- Convert to scale (guard against zero size)
	local frameSize = frame.AbsoluteSize
	if frameSize.X == 0 or frameSize.Y == 0 then
		knob.Position = UDim2.fromScale(0.5, 0.5)
		return
	end

	local offsetX = clampedDelta.X / frameSize.X
	local offsetY = clampedDelta.Y / frameSize.Y

	knob.Position = UDim2.fromScale(0.5 + offsetX, 0.5 + offsetY)
end

-- ตัวแปรสำหรับ RescueBot
local rescueBotModel: Model? = nil
local isBotControlActive = false
local controlConnection: RBXScriptConnection? = nil
local updateConnection: RBXScriptConnection? = nil

-- ตัวแปรสำหรับจัดการ camera
local savedCameraDistance: number = 0

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

-- Forward declaration
local stopRescueBotControl: () -> ()

-- ฟังก์ชันบังคับควบคุม RescueBot
local function startRescueBotControl()
	if isBotControlActive then
		print("[MobileRescueBot] Already controlling bot")
		return
	end

	rescueBotModel = findPlayerRescueBot()

	if not rescueBotModel then
		warn("[MobileRescueBot] RescueBot not found:", player.Name .. "_Rescue")
		return
	end

	local rescuePrimaryPart = rescueBotModel.PrimaryPart
	if not rescuePrimaryPart then
		warn("[MobileRescueBot] RescueBot has no PrimaryPart")
		return
	end

	isBotControlActive = true

	-- ตั้งค่ากล้องแบบปกติ (เหมือน PC)
	camera.CameraType = Enum.CameraType.Custom
	camera.CameraSubject = rescuePrimaryPart

	-- ซ่อน character และทำให้หยุดเคลื่อนที่
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.PlatformStand = true
			humanoid.WalkSpeed = 0
		end

		if character.PrimaryPart then
			character.PrimaryPart.Anchored = true
			-- ย้าย character ไปใต้แผนที่
			character:SetPrimaryPartCFrame(CFrame.new(0, -500, 0))
		end

		hideCharacter(true)
	end

	-- แสดง controls
	controlsGui.Enabled = true

	print("[MobileRescueBot] Now controlling RescueBot:", rescueBotModel.Name)
	print("[MobileRescueBot] Camera following:", rescuePrimaryPart.Name)

	-- สร้าง connection เพื่อส่ง input ไปยัง server
	updateConnection = RunService.Heartbeat:Connect(function()
		if not rescueBotModel or not rescueBotModel.Parent then
			print("[MobileRescueBot] RescueBot destroyed - stopping control")
			stopRescueBotControl()
			return
		end

		-- คำนวณ throttle และ steer จาก joysticks
		local throttle = getJoystickInput(leftJoystick)
		local steer = getJoystickInput(rightJoystick)

		-- อัปเดต knob positions
		updateKnobPosition(leftJoystick)
		updateKnobPosition(rightJoystick)

		-- ตั้งค่า input ใน VehicleController (เหมือน PC)
		VehicleController.setThrottleInput(throttle)
		VehicleController.setSteerInput(-steer) -- กลับทิศให้ตรงกับ PC (left=positive, right=negative)

		-- ส่งไปยัง server (เหมือนกับ PC ที่ใช้ updateOriginalRescueControls)
		controlOriginalRescueEvent:FireServer(throttle, -steer)
	end)

	-- สร้าง connection เพื่อตรวจสอบว่า bot ยังอยู่หรือไม่
	controlConnection = RunService.Heartbeat:Connect(function()
		if not rescueBotModel or not rescueBotModel.Parent then
			print("[MobileRescueBot] RescueBot destroyed - stopping control")
			stopRescueBotControl()
		end
	end)
end

-- ฟังก์ชันหยุดควบคุม RescueBot
function stopRescueBotControl()
	if not isBotControlActive then return end

	isBotControlActive = false

	if controlConnection then
		controlConnection:Disconnect()
		controlConnection = nil
	end

	if updateConnection then
		updateConnection:Disconnect()
		updateConnection = nil
	end

	-- ซ่อน controls
	controlsGui.Enabled = false

	-- รีเซ็ตสถานะ joystick
	leftJoystick.active = false
	leftJoystick.inputObject = nil
	leftJoystick.inputKey = nil
	leftJoystick.currentPos = leftJoystick.startPos
	if leftJoystick.knob then
		leftJoystick.knob.Position = UDim2.fromScale(0.5, 0.5)
	end

	rightJoystick.active = false
	rightJoystick.inputObject = nil
	rightJoystick.inputKey = nil
	rightJoystick.currentPos = rightJoystick.startPos
	if rightJoystick.knob then
		rightJoystick.knob.Position = UDim2.fromScale(0.5, 0.5)
	end

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

	-- รีเซ็ตการตั้งค่ากล้อง
	player.CameraMode = Enum.CameraMode.Classic

	rescueBotModel = nil
	print("[MobileRescueBot] Stopped controlling RescueBot")
end

-- ฟังก์ชันช่วยในการจัดการ input (ใช้ได้ทั้ง touch และ mouse)
local function handleInputBegan(input: InputObject): boolean
	if not isBotControlActive then return false end

	local isJoystickInput = false
	local position2D = getInputPosition(input)
	local inputKey = getInputKey(input)

	-- เช็คว่า input อยู่ใน left joystick หรือไม่
	local leftFrame = leftJoystick.frame
	if leftFrame then
		local framePos = leftFrame.AbsolutePosition
		local frameSize = leftFrame.AbsoluteSize
		local inBoundsX = position2D.X >= framePos.X and position2D.X <= framePos.X + frameSize.X
		local inBoundsY = position2D.Y >= framePos.Y and position2D.Y <= framePos.Y + frameSize.Y

		if inBoundsX and inBoundsY and not leftJoystick.active then
			leftJoystick.active = true
			leftJoystick.inputObject = input
			leftJoystick.inputKey = inputKey
			leftJoystick.startPos = position2D
			leftJoystick.currentPos = position2D
			leftBlocker.Modal = true -- บล็อค input ทั้งหมด
			leftBlocker.Active = true

			-- บันทึกระยะกล้องเพื่อ debug
			if rescueBotModel and rescueBotModel.PrimaryPart then
				local primary = rescueBotModel.PrimaryPart
				savedCameraDistance = (camera.CFrame.Position - primary.Position).Magnitude
			end

			isJoystickInput = true
			print("[MobileRescueBot] Left joystick activated - Camera distance stored", savedCameraDistance)
		end
	end

	-- เช็คว่า input อยู่ใน right joystick หรือไม่
	local rightFrame = rightJoystick.frame
	if rightFrame then
		local framePos = rightFrame.AbsolutePosition
		local frameSize = rightFrame.AbsoluteSize
		local inBoundsX = position2D.X >= framePos.X and position2D.X <= framePos.X + frameSize.X
		local inBoundsY = position2D.Y >= framePos.Y and position2D.Y <= framePos.Y + frameSize.Y

		if inBoundsX and inBoundsY and not rightJoystick.active then
			rightJoystick.active = true
			rightJoystick.inputObject = input
			rightJoystick.inputKey = inputKey
			rightJoystick.startPos = position2D
			rightJoystick.currentPos = position2D
			rightBlocker.Modal = true -- บล็อค input ทั้งหมด
			rightBlocker.Active = true

			-- บันทึกระยะกล้องเพื่อ debug
			if rescueBotModel and rescueBotModel.PrimaryPart then
				local primary = rescueBotModel.PrimaryPart
				savedCameraDistance = (camera.CFrame.Position - primary.Position).Magnitude
			end

			isJoystickInput = true
			print("[MobileRescueBot] Right joystick activated - Camera distance stored", savedCameraDistance)
		end
	end

	return isJoystickInput
end

local function handleInputMoved(input: InputObject)
	if not isBotControlActive then return end

	local position2D = getInputPosition(input)
	local inputKey = getInputKey(input)

	-- อัปเดต left joystick (จำกัดการเคลื่อนที่แกน Y)
	if leftJoystick.active and (leftJoystick.inputObject == input or leftJoystick.inputKey == inputKey) then
		local startPos = leftJoystick.startPos
		local minY = startPos.Y - MAX_JOYSTICK_DISTANCE
		local maxY = startPos.Y + MAX_JOYSTICK_DISTANCE
		local clampedY = math.clamp(position2D.Y, minY, maxY)
		leftJoystick.currentPos = Vector2.new(startPos.X, clampedY)
		leftJoystick.inputObject = input
		leftJoystick.inputKey = inputKey
	end

	-- อัปเดต right joystick (จำกัดการเคลื่อนที่แกน X)
	if rightJoystick.active and (rightJoystick.inputObject == input or rightJoystick.inputKey == inputKey) then
		local startPos = rightJoystick.startPos
		local minX = startPos.X - MAX_JOYSTICK_DISTANCE
		local maxX = startPos.X + MAX_JOYSTICK_DISTANCE
		local clampedX = math.clamp(position2D.X, minX, maxX)
		rightJoystick.currentPos = Vector2.new(clampedX, startPos.Y)
		rightJoystick.inputObject = input
		rightJoystick.inputKey = inputKey
	end
end

local function handleInputEnded(input: InputObject?)
	if not isBotControlActive then return end

local inputKey = input and getInputKey(input)

-- รีเซ็ต left joystick
if leftJoystick.active and (not inputKey or leftJoystick.inputKey == inputKey) then
	leftJoystick.active = false
	leftJoystick.inputObject = nil
	leftJoystick.inputKey = nil
	if leftJoystick.knob then
			leftJoystick.knob.Position = UDim2.fromScale(0.5, 0.5)
		end
		leftBlocker.Modal = false -- ปลดบล็อค
		leftBlocker.Active = false

		print("[MobileRescueBot] Left joystick deactivated")
	end

	-- รีเซ็ต right joystick
if rightJoystick.active and (not inputKey or rightJoystick.inputKey == inputKey) then
	rightJoystick.active = false
	rightJoystick.inputObject = nil
	rightJoystick.inputKey = nil
		if rightJoystick.knob then
			rightJoystick.knob.Position = UDim2.fromScale(0.5, 0.5)
		end
		rightBlocker.Modal = false -- ปลดบล็อค
		rightBlocker.Active = false

		print("[MobileRescueBot] Right joystick deactivated")
	end

	-- แจ้งเมื่อไม่มี joystick ทำงาน
	if not leftJoystick.active and not rightJoystick.active then
		print("[MobileRescueBot] Camera distance flag cleared")
	end
end

-- Touch input handling
UserInputService.TouchStarted:Connect(function(touch, gameProcessed)
	if gameProcessed then return end
	handleInputBegan(touch)
end)

UserInputService.TouchMoved:Connect(function(touch, gameProcessed)
	handleInputMoved(touch)
end)

UserInputService.TouchEnded:Connect(function(touch, gameProcessed)
	handleInputEnded(touch)
end)

-- Mouse input handling (สำหรับทดสอบใน Studio)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		handleInputBegan(input)
	end
end)

UserInputService.InputChanged:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		if leftJoystick.active or rightJoystick.active then
			handleInputMoved(input)
		end
	end
end)

UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		handleInputEnded(input)
	end
end)

-- ตรวจสอบ RescueBot ทุกๆ 1 วินาที
local function monitorRescueBot()
	while true do
		task.wait(1)

		local bot = findPlayerRescueBot()

		if bot and not isBotControlActive then
			print("[MobileRescueBot] RescueBot detected - Starting auto-control")
			startRescueBotControl()
		elseif not bot and isBotControlActive then
			print("[MobileRescueBot] RescueBot not found - Stopping control")
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

-- ซ่อน controls ตอนเริ่มต้น
controlsGui.Enabled = false

print("[MobileRescueBot] Mobile controller initialized with on-screen joysticks - Waiting for RescueBot...")
