local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ProximityPromptService = game:GetService("ProximityPromptService")

-- Import shared modules
local DrillConfig = require(ReplicatedStorage.Modules.DrillConfig)
local DrillSystem = require(ReplicatedStorage.Modules.DrillSystem)
local WaitingSystem = require(ReplicatedStorage.Modules.WaitingSystem)
local MapSelectionSystem = require(ReplicatedStorage.Modules.MapSelectionSystem)

-- รอ RemoteEvents
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local spawnCompanionEvent = remoteEvents:WaitForChild("SpawnCompanion")
local controlEvent = remoteEvents:WaitForChild("ControlVehicle")
local stopControlEvent = remoteEvents:WaitForChild("StopControl")
local hydraulicRemote = remoteEvents:WaitForChild("ActivateHydraulic")
local spawnOriginalRescueEvent = remoteEvents:WaitForChild("SpawnOriginalRescue")
local controlOriginalRescueEvent = remoteEvents:WaitForChild("ControlOriginalRescue")
local stopOriginalRescueEvent = remoteEvents:WaitForChild("StopOriginalRescue")
local drillProgressRemote = remoteEvents:WaitForChild("HydraulicDrillProgress")
local waitingSystemRemote = remoteEvents:WaitForChild("WaitingSystem")
local mapVotingRemote = remoteEvents:WaitForChild("MapVoting")

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local camera = Workspace.CurrentCamera

local ScreenGuis = ReplicatedStorage.ScreenGuis
local FlipGui = ScreenGuis:WaitForChild("FlipBillboardGui")

local connectionSteer = nil
local connectionThrottle = nil

-- ตัวแปรสำหรับ Rescue Mode
local isRescueMode = false
local rescueModel = nil
local connections = {}

-- Manual control variables
local throttleInput = 0
local steerInput = 0
local vehicleParts = {}
local manualVehicle = nil

-- Wheel smoothing variables
local wheelControlState = {}
local wheelSmoothingConnection = nil
local MAX_WHEEL_TORQUE = 120000
local FRONT_TORQUE_FACTOR = 0.7
local BRAKE_TORQUE = 12000
local WHEEL_SMOOTH_SPEED = 10

-- Flip system variables
local flipSurfaceGui = nil

-- Game timer variables
local gameTimerGui = nil
local timerConnection = nil

-- Client-side waiting system variables
local currentWaitingCount = 0
local maxPlayersCount = 2

-- ระบบ Rescue Mode แบบเดิม (สำหรับ Simu touch)
local originalRescueModel = nil

-- Camera zoom system variables
local isZoomMode = false
local originalCameraSubject = nil
local originalCameraType = nil
local cameraTrackConnection = nil
local originalFieldOfView = nil
local cameraZoomLevels = {1, 2, 5}
local zoomIndex = 1

-- Thermal vision variables
local isThermalMode = false
local thermalEffect = nil
local colorCorrection = nil
local originalFogEnd = nil
local humanoidHighlights = {}
local humanoidScanConnection = nil


-- ฟังก์ชันให้ companion ตามผู้เล่นเมื่อไม่ได้ควบคุม
local function startCompanionFollow()
	print("DEBUG: startCompanionFollow called")
	if isRescueMode then
		print("DEBUG: In rescue mode, not starting follow")
		return
	end
	if not rescueModel then
		print("DEBUG: No rescueModel found")
		return
	end
	if not rescueModel.PrimaryPart then
		print("DEBUG: rescueModel has no PrimaryPart")
		return
	end
	if not character then
		print("DEBUG: No character found")
		return
	end

	local function getPlayerRoot()
		if character and character.Parent and character.PrimaryPart then
			return character.PrimaryPart
		end
		return nil
	end

	local function sendControls(throttle, steer)
		throttleInput = throttle
		steerInput = steer
		controlEvent:FireServer(throttle, steer)
	end

	local function stopControls()
		throttleInput = 0
		steerInput = 0
		stopControlEvent:FireServer()
	end
end

local function stopCompanionFollow()
	throttleInput = 0
	steerInput = 0
	stopControlEvent:FireServer()
end

local function disconnectAll()
	if connectionSteer then connectionSteer:Disconnect(); connectionSteer = nil end
	if connectionThrottle then connectionThrottle:Disconnect(); connectionThrottle = nil end
	for _, connection in pairs(connections) do
		if connection then
			connection:Disconnect()
		end
	end
	connections = {}

	if wheelSmoothingConnection then
		wheelSmoothingConnection:Disconnect()
		wheelSmoothingConnection = nil
	end
	wheelControlState = {}
end

local function sign(x)
	if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end
end

local function initializeWheelConstraint(constraint, torqueLimit)
	if not constraint then return end
	wheelControlState[constraint] = {
		currentAV = constraint.AngularVelocity or 0,
		targetAV = constraint.AngularVelocity or 0,
		currentTorque = math.clamp(constraint.MotorMaxTorque or 0, 0, torqueLimit or MAX_WHEEL_TORQUE),
		targetTorque = math.clamp(constraint.MotorMaxTorque or 0, 0, torqueLimit or MAX_WHEEL_TORQUE),
		torqueLimit = torqueLimit or MAX_WHEEL_TORQUE,
	}
end

local function ensureWheelSmoothing()
	if wheelSmoothingConnection then return end
	wheelSmoothingConnection = RunService.Heartbeat:Connect(function(dt)
		local alpha = math.clamp(dt * WHEEL_SMOOTH_SPEED, 0, 1)
		local hasData = false
		for constraint, data in pairs(wheelControlState) do
			if constraint and constraint.Parent then
				hasData = true
				data.currentAV = data.currentAV + (data.targetAV - data.currentAV) * alpha
				data.currentTorque = data.currentTorque + (data.targetTorque - data.currentTorque) * alpha
				constraint.AngularVelocity = data.currentAV
				constraint.MotorMaxTorque = math.clamp(data.currentTorque, 0, data.torqueLimit or MAX_WHEEL_TORQUE)
			else
				wheelControlState[constraint] = nil
			end
		end
		if not hasData then
			wheelSmoothingConnection:Disconnect()
			wheelSmoothingConnection = nil
		end
	end)
end

local function setWheelTargets(constraint, targetAV, targetTorque)
	if not constraint then return end
	if not wheelControlState[constraint] then
		initializeWheelConstraint(constraint)
	end
	local info = wheelControlState[constraint]
	if not info then return end
	info.targetAV = targetAV
	local limit = info.torqueLimit or MAX_WHEEL_TORQUE
	info.targetTorque = math.clamp(targetTorque, 0, limit)
	ensureWheelSmoothing()
end

-- Humanoid scanning functions (moved up for proper scoping)
local function stopHumanoidScanning()
	print("DEBUG: stopHumanoidScanning() called")

	-- หยุด scanning
	if humanoidScanConnection then
		print("DEBUG: Disconnecting humanoid scan connection...")
		humanoidScanConnection:Disconnect()
		humanoidScanConnection = nil
		print("DEBUG: Humanoid scan connection stopped and cleared")
	else
		print("DEBUG: No humanoid scan connection to stop")
	end

	-- ล้าง highlights ทั้งหมด
	local highlightCount = 0
	print("DEBUG: humanoidHighlights table has", #humanoidHighlights, "entries")
	for character, highlight in pairs(humanoidHighlights) do
		print("DEBUG: Found highlight for character:", character.Name)
		if highlight and highlight.Parent then
			highlight:Destroy()
			highlightCount = highlightCount + 1
			print("DEBUG: Destroyed highlight for:", character.Name)
		else
			print("DEBUG: Highlight already destroyed or no parent for:", character.Name)
		end
	end
	humanoidHighlights = {}
	print("DEBUG: Cleared humanoidHighlights table")

	-- เพิ่มการลบ highlight ที่อาจค้างอยู่ในระบบ
	local orphanCount = 0
	print("DEBUG: Scanning workspace for orphan highlights...")
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Highlight") and obj.FillColor == Color3.new(1, 0.5, 0) then
			print("DEBUG: Found orphan highlight, destroying:", obj.Name, "in", obj.Parent.Name)
			obj:Destroy()
			orphanCount = orphanCount + 1
		end
	end

	print("DEBUG: Removed", highlightCount, "tracked highlights and", orphanCount, "orphan highlights")
	print("DEBUG: Humanoid scanning stopped - All highlights removed")
end

-- เชื่อมต่อ DrillSystem กับ server remote
connections.drillProgress = drillProgressRemote.OnClientEvent:Connect(function(payload)
	-- ใช้ DrillSystem จัดการ UI แทน (ถ้าต้องการ)
	-- DrillSystem จัดการ UI เอง แล้ว
end)

-- Camera tracking functions
local function applyCameraZoom()
	if not isZoomMode or not originalFieldOfView then return end
	local zoomFactor = cameraZoomLevels[zoomIndex] or 1
	if zoomFactor <= 0 then
		zoomFactor = 1
	end
	camera.FieldOfView = originalFieldOfView / zoomFactor
	print(string.format("Camera zoom set to %.1fx", zoomFactor))
end

local function setCameraZoomIndex(newIndex)
	local clamped = math.clamp(newIndex, 1, #cameraZoomLevels)
	if clamped == zoomIndex then return end
	zoomIndex = clamped
	applyCameraZoom()
end

local function setCameraZoomFactor(factor)
	for index, value in ipairs(cameraZoomLevels) do
		if value == factor then
			setCameraZoomIndex(index)
			return
		end
	end
	print("Requested zoom factor not available:", factor)
end

local function adjustCameraZoom(step)
	if #cameraZoomLevels == 0 then return end
	local newIndex = math.clamp(zoomIndex + step, 1, #cameraZoomLevels)
	if newIndex ~= zoomIndex then
		zoomIndex = newIndex
		applyCameraZoom()
	end
end

local function startCameraTracking()
	-- หยุด connection เก่า
	if cameraTrackConnection then
		cameraTrackConnection:Disconnect()
		cameraTrackConnection = nil
	end

	-- หา Camera part ใน rescue vehicle
	local rescueVehicle = workspace:FindFirstChild(player.Name .. "_Rescue")
	if not rescueVehicle then
		print("No rescue vehicle found for camera tracking")
		return false
	end

	local cameraPart = rescueVehicle:FindFirstChild("Camera")
	if not cameraPart or not cameraPart:IsA("BasePart") then
		print("No Camera part found in rescue vehicle")
		return false
	end

	-- บันทึกค่าเดิม
	if not isZoomMode then
		originalCameraSubject = camera.CameraSubject
		originalCameraType = camera.CameraType
		isZoomMode = true
		originalFieldOfView = camera.FieldOfView
		zoomIndex = 1
	end

	-- ตั้งกล้องเป็น Scriptable
	camera.CameraType = Enum.CameraType.Scriptable
	applyCameraZoom()

	-- เริ่มติดตาม Camera part โดยยื่นกล้องไปข้างหน้าในทิศทางแกน X
	cameraTrackConnection = RunService.Heartbeat:Connect(function()
		if cameraPart.Parent then -- ตรวจสอบว่า part ยังอยู่
			-- ยื่นกล้องไปข้างหน้า 5 studs ในทิศทางแกน X ของ BasePart
			local basePosition = cameraPart.Position
			local rightVector = cameraPart.CFrame.RightVector -- แกน X ของ BasePart
			local cameraPosition = basePosition + (rightVector * 5) -- ยื่นไป 5 studs
			camera.CFrame = CFrame.lookAt(cameraPosition, cameraPosition + rightVector)
		else
			-- ถ้า Camera part หายไป ให้หยุดติดตาม
			stopCameraTracking()
		end
	end)

	print("Camera now tracking Camera part in rescue vehicle")
	return true
end

function stopCameraTracking()
	print("DEBUG: stopCameraTracking() called")
	-- หยุด tracking connection
	if cameraTrackConnection then
		cameraTrackConnection:Disconnect()
		cameraTrackConnection = nil
	end

	-- ปิด thermal vision ถ้าเปิดอยู่
	if isThermalMode then
		isThermalMode = false
		if thermalEffect then
			thermalEffect:Destroy()
			thermalEffect = nil
		end

		-- ลบ ColorCorrection effect
		if colorCorrection then
			colorCorrection:Destroy()
			colorCorrection = nil
		end

		-- คืนค่า Fog ปกติ
		if originalFogEnd then
			game.Lighting.FogEnd = originalFogEnd
			game.Lighting.FogColor = Color3.new(0.75, 0.75, 0.75)
		end

		print("Thermal vision auto-disabled when closing camera tracking")
	end

	-- หยุดสแกน Humanoid ไม่ว่าจะเปิด thermal หรือไม่ (เผื่อมี highlight ค้างอยู่)
	stopHumanoidScanning()

	-- กลับไปใช้กล้องปกติ
	if originalCameraSubject then
		camera.CameraSubject = originalCameraSubject
		camera.CameraType = originalCameraType or Enum.CameraType.Custom
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = character.Humanoid
	end

	if originalFieldOfView then
		camera.FieldOfView = originalFieldOfView
	end
	originalFieldOfView = nil
	zoomIndex = 1

	isZoomMode = false
	print("Camera tracking stopped - back to normal view")
end

local function toggleCameraTracking()
	if isZoomMode then
		stopCameraTracking()
	else
		startCameraTracking()
	end
end

-- Thermal vision functions
local function createThermalEffect()
	-- สร้าง ScreenGui สำหรับ thermal effect
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ThermalVisionGui"
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	-- สร้าง Frame ปิดทั้งหน้าจอ
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0) -- สีดำ
	frame.BackgroundTransparency = 0.3 -- เล็กน้อยใส
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	-- สร้าง thermal overlay effect
	local thermalFrame = Instance.new("Frame")
	thermalFrame.Size = UDim2.new(1, 0, 1, 0)
	thermalFrame.Position = UDim2.new(0, 0, 0, 0)
	thermalFrame.BackgroundColor3 = Color3.new(0.2, 0.8, 1) -- สีฟ้าน้ำเงิน
	thermalFrame.BackgroundTransparency = 0.7
	thermalFrame.BorderSizePixel = 0
	thermalFrame.Parent = frame

	-- เพิ่ม thermal text indicator
	local thermalLabel = Instance.new("TextLabel")
	thermalLabel.Size = UDim2.new(0, 200, 0, 50)
	thermalLabel.Position = UDim2.new(0, 10, 0, 50)
	thermalLabel.BackgroundTransparency = 1
	thermalLabel.Text = "THERMAL VISION"
	thermalLabel.TextColor3 = Color3.new(0, 1, 1) -- สีฟ้าอ่อน
	thermalLabel.TextScaled = true
	thermalLabel.Font = Enum.Font.Code
	thermalLabel.Parent = frame

	-- เพิ่มเอฟเฟกต์กระพริบ
	spawn(function()
		while thermalEffect and thermalEffect.Parent do
			thermalFrame.BackgroundTransparency = 0.7
			wait(0.5)
			if thermalEffect and thermalEffect.Parent then
				thermalFrame.BackgroundTransparency = 0.8
				wait(0.5)
			end
		end
	end)

	return screenGui
end

-- Humanoid detection functions
local function createHumanoidHighlight(humanoidCharacter)
	-- สร้าง Highlight effect สำหรับ Humanoid
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 0.5, 0) -- สีส้ม
	highlight.OutlineColor = Color3.new(1, 0.3, 0) -- สีส้มเข้ม
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop -- มองเห็นผ่านกำแพง
	highlight.Parent = humanoidCharacter

	return highlight
end

local function scanForHumanoids()
	print("DEBUG: scanForHumanoids() called at", tick())
	-- ล้าง highlight เก่า
	for character, highlight in pairs(humanoidHighlights) do
		if highlight then
			highlight:Destroy()
		end
	end
	humanoidHighlights = {}

	-- สแกนหา Humanoid ทั้งหมดใน workspace
	for _, obj in pairs(workspace:GetChildren()) do
		if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
			local humanoid = obj:FindFirstChildOfClass("Humanoid")
			-- ตรวจสอบว่าเป็น character จริง (มี body parts)
			if humanoid and obj:FindFirstChild("Head") and obj:FindFirstChild("Torso") or obj:FindFirstChild("UpperTorso") then
				local highlight = createHumanoidHighlight(obj)
				humanoidHighlights[obj] = highlight
				print("Detected humanoid:", obj.Name)
			end
		end
	end
end

local function startHumanoidScanning()
	-- หยุด connection เก่า
	if humanoidScanConnection then
		humanoidScanConnection:Disconnect()
		humanoidScanConnection = nil
	end

	-- ใช้ timer-based approach แทน wait() ใน Heartbeat
	local lastScanTime = 0
	local scanInterval = 2 -- สแกนทุก 2 วินาที

	humanoidScanConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - lastScanTime >= scanInterval then
			scanForHumanoids()
			lastScanTime = currentTime
		end
	end)

	-- สแกนครั้งแรกทันที
	scanForHumanoids()
	print("DEBUG: Humanoid scanning started with proper timer")
end


local function toggleThermalVision()
	if not isZoomMode then
		print("Thermal vision only works in camera tracking mode. Press Z first!")
		return
	end

	isThermalMode = not isThermalMode

	if isThermalMode then
		-- เปิด thermal vision
		thermalEffect = createThermalEffect()

		-- สร้าง ColorCorrection effect
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Brightness = 0.3
		colorCorrection.Contrast = 0.5
		colorCorrection.Saturation = -1 -- ลดสีให้เหมือน thermal
		colorCorrection.TintColor = Color3.new(0.7, 0.9, 1) -- สีฟ้าเล็กน้อย
		colorCorrection.Parent = game.Lighting

		-- ปรับ Fog เพื่อให้มีบรรยากาศ thermal
		originalFogEnd = game.Lighting.FogEnd
		game.Lighting.FogColor = Color3.new(0.1, 0.3, 0.8)
		game.Lighting.FogEnd = originalFogEnd * 0.7

		-- เริ่มสแกน Humanoid
		startHumanoidScanning()

		print("Thermal vision ENABLED with Humanoid detection")
	else
		-- ปิด thermal vision
		if thermalEffect then
			thermalEffect:Destroy()
			thermalEffect = nil
		end

		-- ลบ ColorCorrection effect
		if colorCorrection then
			colorCorrection:Destroy()
			colorCorrection = nil
		end

		-- คืนค่า Fog ปกติ
		if originalFogEnd then
			game.Lighting.FogEnd = originalFogEnd
			game.Lighting.FogColor = Color3.new(0.75, 0.75, 0.75) -- สีปกติ
		end

		-- หยุดสแกน Humanoid
		stopHumanoidScanning()

		print("Thermal vision DISABLED")
	end
end

-- ตรวจสอบว่าล้อกำลังฟรีหรือไม่
local function isWheelSlipping()
	-- ตรวจสอบจาก vehicleParts.primary
	if vehicleParts.primary then
		local velocity = vehicleParts.primary.Velocity
		local speed = velocity.Magnitude
		if speed < 2 and math.abs(throttleInput) > 0.5 then
			print("Wheel slipping detected from vehicleParts.primary - Speed:", speed, "ThrottleInput:", throttleInput)
			return true -- รถไม่เคลื่อนที่แต่เหยียบคันเร่ง
		end
	end

	-- ตรวจสอบจาก VehicleSeat (ทั้ง manual และ normal VehicleSeat)
	local vehicleSeat = nil
	if manualVehicle then
		vehicleSeat = manualVehicle:FindFirstChild("VehicleSeat") or manualVehicle:FindFirstChildOfClass("VehicleSeat")
	elseif originalRescueModel then
		vehicleSeat = originalRescueModel:FindFirstChild("VehicleSeat") or originalRescueModel:FindFirstChildOfClass("VehicleSeat")
	end

	if vehicleSeat then
		local velocity = vehicleSeat.Velocity
		local speed = velocity.Magnitude
		local throttleFloat = vehicleSeat.ThrottleFloat or 0 -- ใช้ ThrottleFloat ของ VehicleSeat แทน

		if speed < 2 and math.abs(throttleFloat) > 0.5 then
			print("Wheel slipping detected from VehicleSeat - Speed:", speed, "ThrottleFloat:", throttleFloat)
			return true -- รถไม่เคลื่อนที่แต่เหยียบคันเร่ง
		end
	end

	return false
end

-- ตรวจสอบว่ารถคว่ำ
local function isVehicleFlipped()
	-- หา VehicleSeat ปัจจุบัน
	local vehicleSeat = nil
	if manualVehicle then
		vehicleSeat = manualVehicle:FindFirstChild("VehicleSeat") or manualVehicle:FindFirstChildOfClass("VehicleSeat")
	elseif originalRescueModel then
		vehicleSeat = originalRescueModel:FindFirstChild("VehicleSeat") or originalRescueModel:FindFirstChildOfClass("VehicleSeat")
	end

	if not vehicleSeat then
		print("No VehicleSeat found for flip check")
		return false
	end

	-- ตรวจสอบว่ารถคว่ำ (UpVector หันลง)
	local upVector = vehicleSeat.CFrame.UpVector
	local isFlipped = upVector.Y < 0.5 -- ถ้า Y น้อยกว่า 0.5 แปลว่าคว่ำ


	return isFlipped
end

-- ตรวจสอบว่ารถติดแม้ไม่คว่ำ (เช่น ล้อฟรีหรืออยู่บนเนิน)
local function isVehicleStuck()
	if isVehicleFlipped() then
		return false
	end

	if isWheelSlipping() then
		return true
	end

	local primaryPart = nil
	if manualVehicle and manualVehicle.PrimaryPart then
		primaryPart = manualVehicle.PrimaryPart
	elseif originalRescueModel and originalRescueModel.PrimaryPart then
		primaryPart = originalRescueModel.PrimaryPart
	end

	if not primaryPart then
		return false
	end

	local speed = primaryPart.AssemblyLinearVelocity.Magnitude
	if speed < 1 then
		local upY = primaryPart.CFrame.UpVector.Y
		if upY > 0.2 then
			return true
		end
	end

	return false
end

-- ระบบ flip รถกลับคืน orientation เดิม
local function flipVehicle()
	-- หา VehicleSeat ในโมเดล
	local vehicleSeat = nil
	if manualVehicle then
		vehicleSeat = manualVehicle:FindFirstChild("VehicleSeat") or manualVehicle:FindFirstChildOfClass("VehicleSeat")
	elseif originalRescueModel then
		vehicleSeat = originalRescueModel:FindFirstChild("VehicleSeat") or originalRescueModel:FindFirstChildOfClass("VehicleSeat")
	end

	if not vehicleSeat then return end

	-- หาทิศทางที่รถควรจะหันหน้า (forward vector)
	local currentCFrame = vehicleSeat.CFrame
	local currentPos = currentCFrame.Position
	local upVector = Vector3.new(0, 1, 0)

	-- ใช้ LookVector ปัจจุบันแต่ปรับให้อยู่บนพื้นราบ
	local forwardVector = currentCFrame.LookVector
	forwardVector = Vector3.new(forwardVector.X, 0, forwardVector.Z).Unit

	-- สร้าง CFrame ใหม่ที่หันหน้าไปทิศเดิมแต่ตั้งตรง
	local newCFrame = CFrame.lookAt(currentPos, currentPos + forwardVector, upVector)

	-- ยกรถขึ้นเล็กน้อยเพื่อไม่ให้ติดกับพื้น
	newCFrame = newCFrame + Vector3.new(0, 2, 0)

	-- Set ตำแหน่งใหม่ให้ทั้งโมเดล
	if manualVehicle then
		manualVehicle:SetPrimaryPartCFrame(newCFrame)
	elseif originalRescueModel then
		originalRescueModel:SetPrimaryPartCFrame(newCFrame)
	end

	-- รีเซ็ตความเร็ว VehicleSeat (VehicleSeat ไม่มี AngularVelocity)
	vehicleSeat.Velocity = Vector3.new(0, 0, 0)

	-- รีเซ็ตความเร็วของ primary part (ถ้ามี)
	if manualVehicle and manualVehicle.PrimaryPart then
		manualVehicle.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		manualVehicle.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	elseif originalRescueModel and originalRescueModel.PrimaryPart then
		originalRescueModel.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		originalRescueModel.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end

	print("Vehicle flipped back to upright position!")
end

-- ดันรถเล็กน้อยเพื่อให้หลุดจากเนินหรือล้อฟรี
local function nudgeVehicle()
	local vehicle = manualVehicle or originalRescueModel
	if not vehicle then
		print("No vehicle available for nudge")
		return
	end

	local primaryPart = vehicle.PrimaryPart
	if not primaryPart then
		print("Vehicle has no PrimaryPart - cannot nudge")
		return
	end

	if primaryPart.Anchored then
		print("PrimaryPart anchored - cannot apply nudge")
		return
	end

	local mass = primaryPart.AssemblyMass
	if mass <= 0 then
		return
	end

	local upwardImpulse = Vector3.new(0, mass * 90, 0)
	local forwardImpulse = primaryPart.CFrame.LookVector * (mass * 35)
	primaryPart:ApplyImpulse(upwardImpulse + forwardImpulse)

	print("Vehicle nudged to regain traction")
end

-- Setup vehicle parts สำหรับ manual control
local function setupVehicleParts(vehicle)
	vehicleParts = {}
	manualVehicle = vehicle

	local primary = vehicle.PrimaryPart
	if not primary then return false end

	vehicleParts.primary = primary
	vehicleParts.attachmentFL = primary:FindFirstChild("AttachmentFL")
	vehicleParts.attachmentFR = primary:FindFirstChild("AttachmentFR")
	
	if vehicleParts.attachmentFL and vehicleParts.attachmentFR then
		vehicleParts.baseFL = vehicleParts.attachmentFL.Orientation
		vehicleParts.baseFR = vehicleParts.attachmentFR.Orientation
	end
	
	vehicleParts.wheelBL = vehicle:FindFirstChild("Wheel_BL")
	vehicleParts.wheelBR = vehicle:FindFirstChild("Wheel_BR")
	vehicleParts.wheelFL = vehicle:FindFirstChild("Wheel_FL")
	vehicleParts.wheelFR = vehicle:FindFirstChild("Wheel_FR")

	if not (vehicleParts.wheelBL and vehicleParts.wheelBR) then return false end
	
	vehicleParts.cylindricalBL = vehicleParts.wheelBL:FindFirstChildOfClass("CylindricalConstraint")
	vehicleParts.cylindricalBR = vehicleParts.wheelBR:FindFirstChildOfClass("CylindricalConstraint")
	
	if vehicleParts.wheelFL then
		vehicleParts.cylindricalFL = vehicleParts.wheelFL:FindFirstChildOfClass("CylindricalConstraint")
	end
	if vehicleParts.wheelFR then
		vehicleParts.cylindricalFR = vehicleParts.wheelFR:FindFirstChildOfClass("CylindricalConstraint")
	end
	
	if not (vehicleParts.cylindricalBL and vehicleParts.cylindricalBR) then return false end
	
	local radius = vehicleParts.wheelBR.Size.Y * 0.5
	vehicleParts.maxAngularVelocity = 15 / radius -- รักษาความเร็วปกติ
	
	return true
end

-- สร้าง SurfaceGui สำหรับ flip รถ
local function createFlipGui(vehicle)
	if flipSurfaceGui then
		flipSurfaceGui:Destroy()
	end

	-- หา PrimaryPart ของรถ
	local primaryPart = vehicle.PrimaryPart
	if not primaryPart then
		warn("Vehicle has no PrimaryPart - cannot create flip GUI")
		return
	end

	-- สร้าง SurfaceGui
	flipSurfaceGui = FlipGui:Clone()
	flipSurfaceGui.Parent = primaryPart
	-- ซ่อน GUI ตั้งแต่แรก
	flipSurfaceGui.Enabled = false

	print("Flip SurfaceGui created on PrimaryPart:", primaryPart.Name)
end

-- อัปเดตสถานะ Flip GUI
local function updateFlipGui()
	if flipSurfaceGui then
		local shouldEnable = isVehicleFlipped()
		local wasEnabled = flipSurfaceGui.Enabled
		flipSurfaceGui.Enabled = shouldEnable

		-- แสดง debug เฉพาะเมื่อสถานะเปลี่ยน
		if shouldEnable and not wasEnabled then
			print("Flip GUI ENABLED - Vehicle needs flipping - Press SPACEBAR")
		elseif not shouldEnable and wasEnabled then
			print("Flip GUI DISABLED - Vehicle OK")
		end
	else
		print("FlipSurfaceGui is nil!")
	end
end

-- สร้าง Game Timer GUI สำหรับนับถอยหลัง 5 นาที
local function createGameTimerGui()
	-- ลบ GUI เก่าถ้ามี
	if gameTimerGui then
		gameTimerGui:Destroy()
		gameTimerGui = nil
	end

	-- หยุด timer connection เก่าถ้ามี
	if timerConnection then
		timerConnection:Disconnect()
		timerConnection = nil
	end

	-- สร้าง ScreenGui
	gameTimerGui = Instance.new("ScreenGui")
	gameTimerGui.Name = "GameTimerGui"
	gameTimerGui.ResetOnSpawn = false
	gameTimerGui.IgnoreGuiInset = true
	gameTimerGui.Parent = player.PlayerGui

	-- สร้าง Frame หลัก
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "TimerFrame"
	mainFrame.Size = UDim2.new(0.2, 0, 0.08, 0)
	mainFrame.Position = UDim2.new(0.4, 0, 0.05, 0) -- อยู่ตรงกลางด้านบน
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.3
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = gameTimerGui

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

	-- เริ่มนับถอยหลังจาก 5 นาที (300 วินาที)
	local timeLeft = 300

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
		end
	end

	-- เริ่ม timer
	timerConnection = task.spawn(function()
		while timeLeft >= 0 and gameTimerGui and gameTimerGui.Parent do
			updateTimer()
			task.wait(1)
		end
	end)

	print("Game Timer GUI created - 5 minute countdown started")
end

-- ส่งข้อมูลการควบคุมไปยัง server (สำหรับ companion)
local function updateManualControls()
	if not isRescueMode then return end
	-- ส่งข้อมูลไปยัง server แทนการควบคุมเอง (เฉพาะ companion mode)
	if rescueModel and not originalRescueModel then
		controlEvent:FireServer(throttleInput, steerInput)
	end
end

-- ส่งข้อมูลการควบคุม Original Rescue ไปยัง server
local function updateOriginalRescueControls()
	if not originalRescueModel then return end
	-- ส่งข้อมูลไปยัง server สำหรับ original rescue control
	controlOriginalRescueEvent:FireServer(throttleInput, steerInput)
end

local function stopRescueMode()
	if not isRescueMode then return end

	isRescueMode = false

	-- รีเซ็ต inputs
	throttleInput = 0
	steerInput = 0

	-- ส่งคำสั่งหยุดไปยัง server
	stopControlEvent:FireServer()
	
	-- คืน camera กลับเป็นปกติ (เฉพาะเมื่อมีการปรับ)
	if character and character:FindFirstChild("Humanoid") then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = character.Humanoid
	end
	
	-- ล้างตัวแปร
	vehicleParts = {}
	manualVehicle = nil

	-- ลบ flip GUI
	if flipSurfaceGui then
		flipSurfaceGui:Destroy()
		flipSurfaceGui = nil
	end
	
	-- เริ่มระบบตามผู้เล่นอีกครั้ง (ไม่ลบ companion)
	if rescueModel then
		startCompanionFollow()
	end
	
	print("Stopped controlling RescueCompanion")
end

character:WaitForChild("Humanoid").Seated:Connect(function(active, seatPart)
	-- ตัดการเชื่อมต่อเก่าเสมอ
	if seatPart and rescueModel and seatPart:IsDescendantOf(rescueModel) then
		humanoid.Sit = false
		if seatPart.Occupant then
			seatPart.Occupant.Sit = false
		end
		return
	end

	disconnectAll()

	-- ถ้าไม่ได้กำลังนั่ง หรือไม่มีที่นั่ง ให้จบ
	if not active or seatPart == nil then
		return
	end
	-- เช็คชนิดเป็น VehicleSeat แทนการเช็คชื่อ
	if not seatPart:IsA("VehicleSeat") then
		return
	end

	local vehicleModel = seatPart.Parent
	if not vehicleModel then return end

	-- หา PrimaryPart (โครงรถ) เพื่อหยิบ AttachmentFL/FR
	local primary = nil
	if vehicleModel:IsA("Model") then
		primary = vehicleModel.PrimaryPart
	end
	if not primary then return end

	local attachmentFL = primary:FindFirstChild("AttachmentFL")
	local attachmentFR = primary:FindFirstChild("AttachmentFR")
	if not (attachmentFL and attachmentFR) then 
		warn("RescueBot: Missing AttachmentFL or AttachmentFR on PrimaryPart")
		return 
	end
	if not (attachmentFL:IsA("Attachment") and attachmentFR:IsA("Attachment")) then 
		warn("RescueBot: AttachmentFL or AttachmentFR are not Attachment objects")
		return 
	end

	-- เก็บค่าตั้งต้นของ Orientation ไว้ (สำคัญ!)
	local baseFL = attachmentFL.Orientation  -- ใช้ของจริงในโมเดล
	local baseFR = attachmentFR.Orientation  -- เช่น FR = (0, -90, 90) ตามที่ให้มา

	-- ล้อขับทั้งหมด (4WD สำหรับขึ้นเนิน)
	local wheelBL = vehicleModel:FindFirstChild("Wheel_BL")
	local wheelBR = vehicleModel:FindFirstChild("Wheel_BR")
	local wheelFL = vehicleModel:FindFirstChild("Wheel_FL")
	local wheelFR = vehicleModel:FindFirstChild("Wheel_FR")
	
	if not (wheelBL and wheelBR) then 
		warn("RescueBot: Missing Wheel_BL or Wheel_BR")
		return 
	end
	if not (wheelBL:IsA("BasePart") and wheelBR:IsA("BasePart")) then 
		warn("RescueBot: Wheel_BL or Wheel_BR are not BasePart objects")
		return 
	end

	local cylindricalBL = wheelBL:FindFirstChildOfClass("CylindricalConstraint")
	local cylindricalBR = wheelBR:FindFirstChildOfClass("CylindricalConstraint")
	if not (cylindricalBL and cylindricalBR) then 
		warn("RescueBot: Missing CylindricalConstraints on rear wheels")
		return 
	end
	
	-- ล้อหน้า (ถ้ามี) สำหรับ 4WD
	local cylindricalFL, cylindricalFR
	if wheelFL and wheelFL:IsA("BasePart") then
		cylindricalFL = wheelFL:FindFirstChildOfClass("CylindricalConstraint")
	end
	if wheelFR and wheelFR:IsA("BasePart") then
		cylindricalFR = wheelFR:FindFirstChildOfClass("CylindricalConstraint")
	end

	initializeWheelConstraint(cylindricalBL)
	initializeWheelConstraint(cylindricalBR)
	if cylindricalFL then
		initializeWheelConstraint(cylindricalFL, MAX_WHEEL_TORQUE * FRONT_TORQUE_FACTOR)
	end
	if cylindricalFR then
		initializeWheelConstraint(cylindricalFR, MAX_WHEEL_TORQUE * FRONT_TORQUE_FACTOR)
	end

	local initialFrontBrake = BRAKE_TORQUE * FRONT_TORQUE_FACTOR
	setWheelTargets(cylindricalBL, 0, BRAKE_TORQUE)
	setWheelTargets(cylindricalBR, 0, BRAKE_TORQUE)
	if cylindricalFL then
		setWheelTargets(cylindricalFL, 0, initialFrontBrake)
	end
	if cylindricalFR then
		setWheelTargets(cylindricalFR, 0, initialFrontBrake)
	end

	-- คำนวณความเร็วเชิงมุมสูงสุดจาก MaxSpeed และรัศมีล้อที่ขับ (BR)
	local radius = wheelBR.Size.Y * 0.5
	if radius <= 0 then 
		warn("RescueBot: Wheel radius is too small:", radius)
		return 
	end
	
	local maxSpeed = seatPart.MaxSpeed or 20 -- รักษาความเร็วปกติ
	local maxAngularVelocity = maxSpeed / radius

	if not maxAngularVelocity or maxAngularVelocity ~= maxAngularVelocity or maxAngularVelocity <= 0 then
		maxAngularVelocity = 30 -- รักษาความเร็วปกติ
	end
	
	print("RescueBot initialized - MaxSpeed:", maxSpeed, "Radius:", radius, "MaxAngularVelocity:", maxAngularVelocity)

	-- ===== Steering (เลี้ยว) =====
	-- กำหนดมุมเลี้ยวสูงสุด (องศา) ถ้าไม่ได้มีระบบ TurnSpeed แยก
	local MAX_STEER_ANGLE = 35

	-- ถ้ามี NumberValue "TurnSpeed" (หรืออยากใช้ seatPart.TurnSpeed) จะ override มุมสูงสุดได้
	local turnSpeedVal = seatPart:FindFirstChild("TurnSpeed")
	local function getMaxSteerAngle()
		if turnSpeedVal and turnSpeedVal:IsA("NumberValue") then
			return turnSpeedVal.Value
		end
		-- ถ้าอยากเอา TurnSpeed ของ VehicleSeat มาใช้เป็นมุมก็ทำได้:
		-- return seatPart.TurnSpeed or MAX_STEER_ANGLE
		return MAX_STEER_ANGLE
	end

	-- หมายเหตุ: ในเคสรถของคุณ AttachmentFR ตั้งต้น = (0, -90, 90)
	-- เราจะ "บวก yaw บนแกน Y" เข้าไปจากค่าตั้งต้นของแต่ละข้าง
	connectionSteer = seatPart:GetPropertyChangedSignal("SteerFloat"):Connect(function()
		local steer = seatPart.SteerFloat or 0
		local yaw = steer * getMaxSteerAngle() -- ช่วง ~ -MAX..+MAX องศา

		attachmentFL.Orientation = Vector3.new(baseFL.X, baseFL.Y + yaw, baseFL.Z)
		attachmentFR.Orientation = Vector3.new(baseFR.X, baseFR.Y + yaw, baseFR.Z)
	end)

	-- ===== Throttle (เร่ง/ถอย) =====
	connectionThrottle = seatPart:GetPropertyChangedSignal("ThrottleFloat"):Connect(function()
		local throttle = seatPart.ThrottleFloat or 0
		local dir = sign(throttle)
		local frontBrakeTorque = BRAKE_TORQUE * FRONT_TORQUE_FACTOR

		-- ไม่มีคันเร่ง -> หยุดรถทันทีด้วยแรงเบรก (กันรถไหล/creep)
		if dir == 0 or maxAngularVelocity == 0 then
			setWheelTargets(cylindricalBL, 0, BRAKE_TORQUE)
			setWheelTargets(cylindricalBR, 0, BRAKE_TORQUE)
			if cylindricalFL then
				setWheelTargets(cylindricalFL, 0, frontBrakeTorque)
			end
			if cylindricalFR then
				setWheelTargets(cylindricalFR, 0, frontBrakeTorque)
			end
			return
		end

		-- ปรับแรงบิดตามคันเร่ง (รักษาค่าพื้นฐาน)
		local baseTorque = seatPart.Torque or 5000 -- รักษาค่าเดิม
		local minTorque = 2000 -- รักษาค่าเดิม
		
		-- เพิ่มแรงบิดเมื่อขึ้นเนิน (ตรวจจากความชันของรถ)
		local vehicleOrientation = primary.CFrame.LookVector
		local slopeBonus = 1
		if vehicleOrientation.Y > 0.05 then -- ลดเกณฑ์การตรวจจับเนิน
			-- เพิ่มแรงแบบขั้นบันได
			if vehicleOrientation.Y > 0.8 then -- เนินชันมาก
				slopeBonus = 25 + (vehicleOrientation.Y * 30)
			elseif vehicleOrientation.Y > 0.4 then -- เนินปานกลาง
				slopeBonus = 15 + (vehicleOrientation.Y * 20)
			else -- เนินเล็กน้อย
				slopeBonus = 10 + (vehicleOrientation.Y * 16)
			end
		end
		
		local torque = math.max(math.abs(throttle) * baseTorque * slopeBonus, minTorque)
		local targetAV = dir * maxAngularVelocity

		-- ตรวจสอบว่าติดเนินไหม (สำหรับ VehicleSeat)
		if primary and vehicleOrientation.Y > 0.1 then -- อยู่บนเนิน
			local velocity = primary.Velocity
			local speed = velocity.Magnitude
			if speed < 3 and math.abs(throttle) > 0.3 then -- ติดเนิน
				torque = torque * 4 -- เพิ่มแรงเป็น 4 เท่า
				targetAV = targetAV * 1.5 -- เพิ่มความเร็วล้อ
				print("Vehicle stuck on slope - boosting torque!")
			end
		end

		-- ตรวจสอบล้อฟรีและเพิ่มแรงเมื่อติดคาน (สำหรับ VehicleSeat)
		if primary then
			local velocity = primary.Velocity
			local speed = velocity.Magnitude
			if speed < 2 and math.abs(throttle) > 0.5 then -- รถไม่เคลื่อนที่แต่เหยียบคันเร่ง
				torque = torque * 3 -- เพิ่มแรงเป็น 3 เท่า
				targetAV = targetAV * 2 -- เพิ่มความเร็วล้อ
				print("Vehicle stuck - boosting torque!")
			end
		end

		torque = math.clamp(torque, minTorque, MAX_WHEEL_TORQUE)
		targetAV = math.clamp(targetAV, -maxAngularVelocity * 3, maxAngularVelocity * 3)
		local frontTorque = math.clamp(torque * FRONT_TORQUE_FACTOR, minTorque * FRONT_TORQUE_FACTOR, MAX_WHEEL_TORQUE * FRONT_TORQUE_FACTOR)
		frontTorque = math.max(frontTorque, frontBrakeTorque)
		
		setWheelTargets(cylindricalBL, targetAV, torque)
		setWheelTargets(cylindricalBR, targetAV, torque)
		if cylindricalFL then
			setWheelTargets(cylindricalFL, targetAV, frontTorque)
		end
		if cylindricalFR then
			setWheelTargets(cylindricalFR, targetAV, frontTorque)
		end
	end)
end)

-- ระบบ Rescue Companion
local function spawnRescueCompanion()
	if rescueModel then
		-- ถ้ามี companion อยู่แล้ว ให้ลบก่อน
		stopCompanionFollow()
		rescueModel:Destroy()
		rescueModel = nil
	end
	
	-- หา RescueCompanion ใน ReplicatedStorage และ Clone มา
	local rescueTemplate = ReplicatedStorage:FindFirstChild("RescueCompanion")
	if not rescueTemplate or not rescueTemplate:IsA("Model") then
		warn("RescueCompanion not found in ReplicatedStorage")
		return
	end
	
	-- ส่งคำสั่ง spawn ไปยัง server
	if character and character.PrimaryPart then
		local playerPosition = character.PrimaryPart.Position
		local playerCFrame = character.PrimaryPart.CFrame
			-- วางด้านข้างผู้เล่น 2 studs ใกล้ขึ้น
			local sideOffset = playerCFrame.RightVector * 2
			local companionPosition = playerPosition + sideOffset
			companionPosition = Vector3.new(companionPosition.X, playerPosition.Y, companionPosition.Z)
		local lookDirection = playerCFrame.LookVector

		print("DEBUG: Sending spawn request to server")
		spawnCompanionEvent:FireServer(companionPosition, lookDirection)

		-- รอให้ server สร้าง companion และลองหาหลายครั้ง
		local attempts = 0
		local maxAttempts = 20
		while attempts < maxAttempts do
			wait(0.1)
			rescueModel = workspace:FindFirstChild(player.Name .. "_RescueCompanion")
			if rescueModel then
				print("DEBUG: Found companion model after", attempts + 1, "attempts")
				break
			end
			attempts = attempts + 1
		end

		if not rescueModel then
			warn("DEBUG: Failed to find companion model after", maxAttempts, "attempts")
			return
		end
	end

	print("DEBUG: RescueCompanion spawned near player")
	if not isRescueMode then
		print("DEBUG: Starting companion follow")
		startCompanionFollow()
	else
		print("DEBUG: In rescue mode, not starting follow")
	end
	return rescueModel
end

function startRescueMode(useCamera)
	if isRescueMode then return end
	
	-- Spawn companion ถ้าไม่มี
	if not rescueModel then
		spawnRescueCompanion()
		if not rescueModel then return end
	end
	
	-- หา VehicleSeat ใน RescueCompanion
	local vehicleSeat = rescueModel:FindFirstChild("VehicleSeat") or rescueModel:FindFirstChildOfClass("VehicleSeat")
	if not vehicleSeat then
		warn("VehicleSeat not found in RescueCompanion")
		rescueModel:Destroy()
		rescueModel = nil
		return
	end
	
	isRescueMode = true
	
	-- หยุดการตามผู้เล่น
	stopCompanionFollow()
	
	-- ผู้เล่นยังคงเคลื่อนไหวได้ปกติ แต่ควบคุม companion จากระยะไกล
	if character and character.PrimaryPart and character:FindFirstChild("Humanoid") then
		print("Controlling RescueCompanion remotely")
		
		-- ใช้กล้องแบบปกติ (ไม่ปรับ camera)
		-- if useCamera then
		--	camera.CameraType = Enum.CameraType.Scriptable
		-- end
		
		print("Player can move freely while controlling RescueCompanion")
		
		-- Setup การควบคุมแบบ manual
		local success = setupVehicleParts(rescueModel)
		if success then
			-- สร้าง flip GUI
			createFlipGui(rescueModel)
			-- Input handling สำหรับ WASD
			connections.manualControl = RunService.Heartbeat:Connect(function()
				-- ควบคุม companion ด้วย input
				updateManualControls()

				-- อัปเดต flip GUI
				updateFlipGui()

				-- ใช้กล้องแบบปกติ (ไม่เปลี่ยนตำแหน่งกล้อง)
				-- if useCamera and rescueModel and rescueModel.PrimaryPart then
				--	local vehicleCFrame = rescueModel.PrimaryPart.CFrame
				--	-- ตำแหน่งกล้องหลัง companion
				--	local cameraPosition = vehicleCFrame * CFrame.new(-20, 8, 0)
				--	-- มองไปที่ companion
				--	local lookAtPosition = rescueModel.PrimaryPart.Position + Vector3.new(0, 2, 0)
				--	camera.CFrame = CFrame.lookAt(cameraPosition.Position, lookAtPosition)
				-- end
			end)
			
			local cameraText = useCamera and "with camera following" or "(no camera change)"
			print("Now controlling RescueCompanion manually " .. cameraText)
		else
			stopRescueMode()
		end
	else
		stopRescueMode()
	end
end

-- Setup Simu Touched event สำหรับบังคับ Rescue Model แบบเดิม
local simuDebounce = false
local playerInGame = false -- ตัวแปรควบคุมว่าผู้เล่นคนนี้อยู่ในเกมหรือไม่
local function setupSimuTouched()
	-- Disconnect ถ้ามี connection เก่า
	if connections.simuTouched then
		connections.simuTouched:Disconnect()
	end

	local simu = Workspace:FindFirstChild("Simu")
	if simu and simu:IsA("BasePart") then
		connections.simuTouched = simu.Touched:Connect(function(hit)
			-- ตรวจสอบว่าผู้เล่นคนนี้อยู่ในเกมแล้วหรือยัง
			if playerInGame then
				return
			end

			if simuDebounce then return end

			local humanoidHit = hit.Parent:FindFirstChildOfClass("Humanoid")
			if humanoidHit and hit.Parent == character then
				simuDebounce = true
				print("Touched Simu - Requesting to join waiting list")
				print("DEBUG: Player", player.Name, "touching Simu. playerInGame =", playerInGame)

				-- ส่งคำขอไป server
				waitingSystemRemote:FireServer("addPlayer")

				-- Reset debounce หลัง 2 วินาที (ใช้ spawn เพื่อไม่ block)
				spawn(function()
					wait(2)
					simuDebounce = false
				end)
			end
		end)
		print("Simu part found - Touch it to control original Rescue Model")
	else
		warn("Simu part not found in workspace")
	end
end

-- ฟังก์ชันให้ผู้เล่นออกจากเกม
local function exitGame()
	playerInGame = false
	print("Player exited game - Can touch Simu again")
end

function startOriginalRescueMode()
	print("startOriginalRescueMode called, originalRescueModel exists:", originalRescueModel ~= nil)

	-- เช็คว่ามี original rescue model อยู่แล้วหรือไม่
	if originalRescueModel then
		print("Already in original rescue mode, returning early")
		return -- หยุดทำงานเลยถ้ามี original model อยู่แล้ว
	end

	-- หยุด companion mode ถ้ากำลังทำงานอยู่
	if isRescueMode and rescueModel then
		print("Stopping companion mode first")
		stopRescueMode()
		wait(0.1)
	end

	-- Set flag ทันทีเพื่อป้องกันการเรียกซ้ำ
	isRescueMode = true
	print("Set isRescueMode = true")

	-- สุ่ม spawn point จาก workspace.SpawnRescues ก่อน
	local finalSpawnPosition = nil
	local spawnRescues = workspace:FindFirstChild("SpawnRescues")
	if spawnRescues then
		local spawnPoints = {}
		for _, child in ipairs(spawnRescues:GetChildren()) do
			if child:IsA("BasePart") then
				table.insert(spawnPoints, child)
			end
		end

		if #spawnPoints > 0 then
			local randomSpawnPoint = spawnPoints[math.random(1, #spawnPoints)]
			finalSpawnPosition = randomSpawnPoint.Position + Vector3.new(0, 5, 0) -- เว้นระยะจากพื้น
			print("Selected random spawn point:", randomSpawnPoint.Name, "at position:", finalSpawnPosition)
		else
			warn("No spawn points found in SpawnRescues folder")
		end
	else
		warn("SpawnRescues folder not found in workspace")
	end

	-- ถ้าไม่มี spawn point ให้ใช้ตำแหน่งผู้เล่นแทน
	if not finalSpawnPosition and character and character.PrimaryPart then
		finalSpawnPosition = character.PrimaryPart.Position
		print("Using fallback player position:", finalSpawnPosition)
	end

	print("Requesting server to spawn original rescue model at position:", finalSpawnPosition)
	spawnOriginalRescueEvent:FireServer(finalSpawnPosition)

	-- รอให้ server สร้าง model
	wait(0.5)

	-- หา model ที่ server สร้าง
	originalRescueModel = workspace:FindFirstChild(player.Name .. "_Rescue")
	if not originalRescueModel then
		warn("Original Rescue Model not found after server spawn")
		isRescueMode = false
		return
	end

	if character and character.PrimaryPart and character:FindFirstChild("Humanoid") then
		print("Setting up original Rescue Mode...")

		-- ตรวจสอบว่าผู้เล่น freeze อยู่แล้วหรือยัง (จาก game ready)
		-- ถ้ายัง ให้ freeze และย้ายไปที่ Simu
		if not character.Humanoid.PlatformStand then
			-- Freeze player และปรับ camera
			local simu = Workspace:FindFirstChild("Simu")
			if simu and simu:IsA("BasePart") then
				local simuPos = simu.Position + Vector3.new(0, simu.Size.Y/2 + 3, 0)
				character:PivotTo(CFrame.new(simuPos))
			end

			character.Humanoid.PlatformStand = true
			if character.PrimaryPart then
				character.PrimaryPart.Anchored = true
			end
			print("Player frozen at Simu location")
		else
			print("Player already frozen - skipping teleport to Simu")
		end

		-- ใช้กล้องแบบปกติแต่เปลี่ยน CameraSubject ให้ตามรถ
		camera.CameraType = Enum.CameraType.Custom
		if originalRescueModel.PrimaryPart then
			camera.CameraSubject = originalRescueModel.PrimaryPart
		end

		-- สร้าง flip GUI สำหรับ original rescue
		createFlipGui(originalRescueModel)

		-- สร้าง Timer GUI
		createGameTimerGui()

		connections.originalRescueControl = RunService.Heartbeat:Connect(function()
			updateOriginalRescueControls() -- ส่ง input ไป server
			-- อัปเดต flip GUI
			updateFlipGui()
			-- กล้องจะตามรถอัตโนมัติผ่าน CameraSubject แล้ว ไม่ต้องปรับ manual
		end)

		print("Original Rescue Mode started successfully!")
	else
		print("Character not ready")
	end
end

function stopOriginalRescueMode()
	if connections.originalRescueControl then
		connections.originalRescueControl:Disconnect()
		connections.originalRescueControl = nil
	end

	-- รีเซ็ต inputs
	throttleInput = 0
	steerInput = 0

	-- ส่งคำสั่งหยุดไป server
	stopOriginalRescueEvent:FireServer()

	-- หยุด camera tracking
	stopCameraTracking()

	-- ปลดล็อค character และคืน camera
	if character and character:FindFirstChild("Humanoid") then
		character.Humanoid.PlatformStand = false
		if character.PrimaryPart then
			character.PrimaryPart.Anchored = false
		end

		-- กล้องจะถูก reset ใน stopCameraTracking() แล้ว แต่เผื่อไว้
		if not isZoomMode then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = character.Humanoid
		end

		-- เทเลพอร์ตออกจากรถ
		if character.PrimaryPart and originalRescueModel and originalRescueModel.PrimaryPart then
			local exitPos = originalRescueModel.PrimaryPart.Position + Vector3.new(5, 3, 0)
			character:SetPrimaryPartCFrame(CFrame.new(exitPos))
		end
	end

	vehicleParts = {}
	manualVehicle = nil

	-- ลบ flip GUI
	if flipSurfaceGui then
		flipSurfaceGui:Destroy()
		flipSurfaceGui = nil
	end

	-- ไม่ต้องลบ originalRescueModel เพราะ server จัดการแล้ว
	originalRescueModel = nil

	isRescueMode = false

	-- ให้ผู้เล่นคนนี้สามารถเข้าเกมใหม่ได้
	exitGame()

	-- รีเซ็ต WaitingSystem
	WaitingSystem.stopGame()

	print("Exited from original Rescue Model - Ready for new game")

	-- กลับไปควบคุม companion อัตโนมัติ - ลบของเก่าแล้ว spawn ใหม่
	if rescueModel then
		print("Deleting existing RescueCompanion and spawning new one...")
		rescueModel:Destroy()
		rescueModel = nil
	end
	spawnRescueCompanion() -- spawn ใหม่เสมอ
end

-- Input handling
connections.inputBegan = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end

	if input.KeyCode == Enum.KeyCode.F then
		if originalRescueModel then
			stopOriginalRescueMode()
		elseif isRescueMode then
			stopRescueMode()
		end
	end

	-- Camera tracking controls
	if input.KeyCode == Enum.KeyCode.Z then
		-- กด Z เพื่อ toggle camera tracking (ติดตาม Camera part ของ rescue vehicle)
		print("DEBUG: Z key pressed, calling toggleCameraTracking()")
		toggleCameraTracking()
	elseif input.KeyCode == Enum.KeyCode.X then
		-- กด X เพื่อ toggle thermal vision (ต้องเปิด camera tracking ก่อน)
		toggleThermalVision()
	end

	if isZoomMode then
		if input.KeyCode == Enum.KeyCode.One then
			setCameraZoomFactor(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			setCameraZoomFactor(2)
		elseif input.KeyCode == Enum.KeyCode.Five then
			setCameraZoomFactor(5)
		end
	end

	-- คลิกที่ไหนบนหน้าจอก็ได้เพื่อเจาะหรือเปิดใช้ hydraulic arm (เฉพาะใน rescue mode)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and (isRescueMode or originalRescueModel) then
		-- ได้ตำแหน่งของเมาส์
		local mouse = player:GetMouse()
		local clickPosition = mouse.Hit.Position

		-- ลองเจาะก่อน ถ้าไม่มี target ให้เจาะก็เปิด hydraulic arm
		local didDrill = DrillSystem.handleDrillingClick(clickPosition)

		if not didDrill then
			hydraulicRemote:FireServer()
			print("Screen clicked - Hydraulic arm activated!")
		end
	end

	-- Manual control inputs (เฉพาะเมื่ออยู่ใน Rescue Mode)
	if isRescueMode then
		if input.KeyCode == Enum.KeyCode.W then
			throttleInput = 1
		elseif input.KeyCode == Enum.KeyCode.S then
			throttleInput = -0.8
		elseif input.KeyCode == Enum.KeyCode.A then
			steerInput = 1
		elseif input.KeyCode == Enum.KeyCode.D then
			steerInput = -1
		elseif input.KeyCode == Enum.KeyCode.Space then
			-- กด SPACE เพื่อ flip รถเมื่อคว่ำ หรือดันรถถ้าแค่ติดอยู่
			if isVehicleFlipped() then
				flipVehicle()
			elseif isVehicleStuck() then
				nudgeVehicle()
			end
		end
	end
end)

connections.inputChanged = UserInputService.InputChanged:Connect(function(input)
	if not isZoomMode then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local direction = 0
		if input.Position.Z > 0 then
			direction = 1
		elseif input.Position.Z < 0 then
			direction = -1
		end

		if direction ~= 0 then
			adjustCameraZoom(direction)
		end
	end
end)

connections.inputEnded = UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if not isRescueMode then return end
	
	if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.S then
		throttleInput = 0
	elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.D then
		steerInput = 0
	end
end)

-- Character respawn handling
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	humanoid = character:WaitForChild("Humanoid")
	
	if isRescueMode then
		stopRescueMode()
	end
	
	-- Spawn RescueCompanion เมื่อผู้เล่นเกิด และเริ่มควบคุมทันที
	wait(1) -- รอให้ character โหลดเสร็จ
	spawnRescueCompanion() -- จะเริ่มควบคุมอัตโนมัติ
	
	-- Setup Simu again for new character (ถ้าต้องการใช้ Simu trigger)
	setupSimuTouched()
end)

-- เรียกใช้เมื่อเริ่มต้น - เริ่มควบคุมทันที
DrillSystem.clearOldDrillingData() -- ล้างข้อมูลการเจาะเก่า
wait(1) -- รอให้ character โหลดเสร็จ
spawnRescueCompanion() -- Spawn companion และเริ่มควบคุมทันที
setupSimuTouched() -- Setup Simu touch event

-- Handle WaitingSystem RemoteEvent responses
waitingSystemRemote.OnClientEvent:Connect(function(action, ...)
	if action == "gameReady" then
		local gameReady = ...
		if gameReady then
			-- ครบจำนวนแล้ว เริ่มนับถอยหลัง แล้วเริ่ม Map Selection แล้วเริ่มเกม
			print("Game ready - Starting countdown then Map Selection then original Rescue Mode")

			-- ตั้งสถานะว่าผู้เล่นคนนี้เข้าเกมแล้ว
			playerInGame = true
			print("Player entered game - Simu disabled for this player")
		else
			print("Added to waiting list - waiting for more players...")
		end
	elseif action == "updateCount" then
		local waitingCount, maxPlayers = ...
		currentWaitingCount = waitingCount
		maxPlayersCount = maxPlayers

		-- อัปเดต billboard หรือ UI (ใช้ WaitingSystem ตรงๆ)
		spawn(function()
			pcall(function()
				-- ใช้ module WaitingSystem ที่มีอยู่
				local simu = workspace:FindFirstChild("Simu")
				if simu and simu:FindFirstChild("Attachment") then
					local billboardGui = simu.Attachment:FindFirstChild("BillboardGui")
					if billboardGui and billboardGui:FindFirstChild("Frame") then
						local textLabel = billboardGui.Frame:FindFirstChild("TextLabel")
						if textLabel then
							local remaining = maxPlayers - waitingCount
							if waitingCount > 0 and remaining > 0 then
								textLabel.Text = string.format("Waiting for other players %d/%d คน", remaining, maxPlayers)
								textLabel.Visible = true
							elseif waitingCount == 0 then
								textLabel.Text = "Please join the mission!"
								textLabel.Visible = true
							end
						end
					end
				end
			end)
		end)

		print("Waiting count updated:", waitingCount, "/", maxPlayers)
	elseif action == "startGame" then
		local playersArray = ...
		print("Server started game with players:", table.concat(playersArray, ", "))

		-- เริ่ม Map Selection แล้วเริ่มเกม
		spawn(function()
			-- เริ่มนับถอยหลัง
			local simu = workspace:FindFirstChild("Simu")
			if simu and simu:FindFirstChild("Attachment") then
				local billboardGui = simu.Attachment:FindFirstChild("BillboardGui")
				if billboardGui and billboardGui:FindFirstChild("Frame") then
					local textLabel = billboardGui.Frame:FindFirstChild("TextLabel")
					if textLabel then
						for countdown = 5, 1, -1 do
							textLabel.Text = "The mission will start in " .. countdown .. " seconds!"
							textLabel.Visible = true
							wait(1)
						end
						textLabel.Text = ""
						textLabel.Visible = false
					end
				end
			end

			print("Starting map selection...")
			-- เริ่ม Map Selection สำหรับ player คนนี้เท่านั้น (client-side)
			-- ส่งเฉพาะ local player เพราะแต่ละ client ทำ map selection แยกกัน
			MapSelectionSystem.startVoting({player})

			-- รอให้ countdown + Map Selection เสร็จ แล้วจึง freeze และเริ่มเกม
			wait(19) -- รอให้ Map Selection 15s + result 3s + buffer = 19s

			-- Freeze ผู้เล่นหลังจาก Map Selection เสร็จ
			if character and character:FindFirstChild("Humanoid") then
				character.Humanoid.PlatformStand = true
				if character.PrimaryPart then
					character.PrimaryPart.Anchored = true
				end
				print("Player frozen after Map Selection - preparing to spawn rescue vehicle")
			end

			wait(2) -- buffer เพิ่มอีกนิด
			startOriginalRescueMode() -- บังคับ Rescue Model แบบเดิม
		end)
	elseif action == "gameEnded" then
		print("Game ended - can join new game")
		-- รีเซ็ตสถานะ
		playerInGame = false
	end
end)

print("RescueBotController loaded - Companion auto-spawned and ready to control with WASD, Press SPACEBAR to flip when stuck/flipped, Press F to stop")
print("Camera controls: Z = Toggle Camera Tracking, X = Toggle Thermal Vision")
print("Drill System: Click anywhere during rescue mode to drill or activate hydraulic arm")
