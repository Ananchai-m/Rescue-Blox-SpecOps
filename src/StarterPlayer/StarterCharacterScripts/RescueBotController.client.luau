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
local GameTimer = require(ReplicatedStorage.Modules.GameTimer)
local SpawnPointManager = require(ReplicatedStorage.Modules.SpawnPointManager)
local CameraSystem = require(ReplicatedStorage.Modules.CameraSystem)
local VehicleController = require(ReplicatedStorage.Modules.VehicleController)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local ShopUI = require(ReplicatedStorage.Modules.ShopUI)
local CustomizeUI = require(ReplicatedStorage.Modules.CustomizeUI)
local CustomizeService = require(ReplicatedStorage.Modules.CustomizeService)

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
local toggleDrillModeRemote = remoteEvents:WaitForChild("ToggleDrillMode")

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

-- ตัวแปรสำหรับ Drill Mode
local isDrillModeActive = false

-- Vehicle control จัดการโดย VehicleController module แล้ว

-- Flip system variables
local flipSurfaceGui = nil


-- Client-side waiting system variables
local currentWaitingCount = 0
local unregisterVotingComplete = nil

-- ระบบ Rescue Mode แบบเดิม (จัดการโดย VehicleController แล้ว)

-- Camera system จัดการโดย CameraSystem module แล้ว


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
		VehicleController.setThrottleInput(throttle)
		VehicleController.setSteerInput(steer)
		controlEvent:FireServer(throttle, steer)
	end

	local function stopControls()
		VehicleController.setThrottleInput(0)
		VehicleController.setSteerInput(0)
		stopControlEvent:FireServer()
	end
end

local function stopCompanionFollow()
	VehicleController.setThrottleInput(0)
	VehicleController.setSteerInput(0)
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

	-- ล้าง wheel state ใน VehicleController
	VehicleController.clearWheelState()
end

local function freezePlayerForRescue()
	local currentCharacter = player.Character or character
	if not currentCharacter then
		return
	end

	local currentHumanoid = currentCharacter:FindFirstChildOfClass("Humanoid")
	if not currentHumanoid then
		return
	end

	currentHumanoid.PlatformStand = true
	currentHumanoid.Sit = false

	local primaryPart = currentCharacter.PrimaryPart
	if primaryPart then
		primaryPart.Anchored = true
	end

	print("Player frozen after Map Selection - preparing to spawn rescue vehicle")
end

-- Vehicle functions ถูกย้ายไป VehicleController module แล้ว

local function sign(x)
	if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end
end

-- Camera functions ถูกย้ายไป CameraSystem module แล้ว

-- เชื่อมต่อ DrillSystem กับ server remote
connections.drillProgress = drillProgressRemote.OnClientEvent:Connect(function(payload)
	-- ส่ง payload จาก server ให้ DrillSystem แสดง UI
	if payload then
		print("Client received drill progress:", payload.status, payload.partName, payload.clicks, "/", payload.requiredClicks)
		DrillSystem.showDrillProgress(payload)
	else
		warn("Client received nil payload from server")
	end
end)




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
		local shouldEnable = VehicleController.isVehicleFlipped()
		local wasEnabled = flipSurfaceGui.Enabled
		flipSurfaceGui.Enabled = shouldEnable

		-- แสดง debug เฉพาะเมื่อสถานะเปลี่ยน
		if shouldEnable and not wasEnabled then
			print("Flip GUI ENABLED - Vehicle needs flipping - Press SPACEBAR")
		elseif not shouldEnable and wasEnabled then
			print("Flip GUI DISABLED - Vehicle OK")
		end
	else
		-- FlipSurfaceGui ถูกล้างแล้ว ไม่ต้องแสดง warning
		return
	end
end

-- ส่งข้อมูลการควบคุมไปยัง server (สำหรับ companion)
local function updateManualControls()
	if not isRescueMode then return end
	-- ส่งข้อมูลไปยัง server แทนการควบคุมเอง (เฉพาะ companion mode)
	if rescueModel and not VehicleController.getOriginalRescueModel() then
		controlEvent:FireServer(VehicleController.getThrottleInput(), VehicleController.getSteerInput())
	end
end

-- ส่งข้อมูลการควบคุม Original Rescue ไปยัง server
local function updateOriginalRescueControls()
	local originalRescueModel = VehicleController.getOriginalRescueModel()
	if not originalRescueModel then return end

	local throttle = VehicleController.getThrottleInput()
	local steer = VehicleController.getSteerInput()

	-- ส่งข้อมูลไปยัง server สำหรับ original rescue control
	controlOriginalRescueEvent:FireServer(throttle, steer)
end

local function stopRescueMode()
	if not isRescueMode then return end

	isRescueMode = false

	-- รีเซ็ต inputs ใน VehicleController
	VehicleController.setThrottleInput(0)
	VehicleController.setSteerInput(0)

	-- ส่งคำสั่งหยุดไปยัง server
	stopControlEvent:FireServer()
	
	-- คืน camera กลับเป็นปกติ (เฉพาะเมื่อมีการปรับ)
	if character and character:FindFirstChild("Humanoid") then
		camera.CameraType = Enum.CameraType.Custom
		camera.CameraSubject = character.Humanoid
	end
	
	-- ล้างตัวแปรใน VehicleController
	VehicleController.clearVehicleParts()

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

-- ฟังก์ชันล้าง GUI ต่างๆ ของเกม
local function cleanupGameGUIs()
	-- ลบ flip GUI
	if flipSurfaceGui then
		flipSurfaceGui:Destroy()
		flipSurfaceGui = nil
	end

	-- ลบ Timer GUI (จะถูกทำการล้างใน GameSummary.resetToLobby แล้ว แต่เผื่อไว้)
	local playerGui = player:WaitForChild("PlayerGui")
	local timerGui = playerGui:FindFirstChild("GameTimerGui")
	if timerGui then
		timerGui:Destroy()
	end

	print("Game GUIs cleaned up")
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

	local constants = VehicleController.getConstants()

	VehicleController.initializeWheelConstraint(cylindricalBL)
	VehicleController.initializeWheelConstraint(cylindricalBR)
	if cylindricalFL then
		VehicleController.initializeWheelConstraint(cylindricalFL, constants.MAX_WHEEL_TORQUE * constants.FRONT_TORQUE_FACTOR)
	end
	if cylindricalFR then
		VehicleController.initializeWheelConstraint(cylindricalFR, constants.MAX_WHEEL_TORQUE * constants.FRONT_TORQUE_FACTOR)
	end

	local initialFrontBrake = constants.BRAKE_TORQUE * constants.FRONT_TORQUE_FACTOR
	VehicleController.setWheelTargets(cylindricalBL, 0, constants.BRAKE_TORQUE)
	VehicleController.setWheelTargets(cylindricalBR, 0, constants.BRAKE_TORQUE)
	if cylindricalFL then
		VehicleController.setWheelTargets(cylindricalFL, 0, initialFrontBrake)
	end
	if cylindricalFR then
		VehicleController.setWheelTargets(cylindricalFR, 0, initialFrontBrake)
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
		local frontBrakeTorque = constants.BRAKE_TORQUE * constants.FRONT_TORQUE_FACTOR

		-- ไม่มีคันเร่ง -> หยุดรถทันทีด้วยแรงเบรก (กันรถไหล/creep)
		if dir == 0 or maxAngularVelocity == 0 then
			VehicleController.setWheelTargets(cylindricalBL, 0, constants.BRAKE_TORQUE)
			VehicleController.setWheelTargets(cylindricalBR, 0, constants.BRAKE_TORQUE)
			if cylindricalFL then
				VehicleController.setWheelTargets(cylindricalFL, 0, frontBrakeTorque)
			end
			if cylindricalFR then
				VehicleController.setWheelTargets(cylindricalFR, 0, frontBrakeTorque)
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

		torque = math.clamp(torque, minTorque, constants.MAX_WHEEL_TORQUE)
		targetAV = math.clamp(targetAV, -maxAngularVelocity * 3, maxAngularVelocity * 3)
		local frontTorque = math.clamp(torque * constants.FRONT_TORQUE_FACTOR, minTorque * constants.FRONT_TORQUE_FACTOR, constants.MAX_WHEEL_TORQUE * constants.FRONT_TORQUE_FACTOR)
		frontTorque = math.max(frontTorque, frontBrakeTorque)

		VehicleController.setWheelTargets(cylindricalBL, targetAV, torque)
		VehicleController.setWheelTargets(cylindricalBR, targetAV, torque)
		if cylindricalFL then
			VehicleController.setWheelTargets(cylindricalFL, targetAV, frontTorque)
		end
		if cylindricalFR then
			VehicleController.setWheelTargets(cylindricalFR, targetAV, frontTorque)
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
		local success = VehicleController.setupVehicle(rescueModel)
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
local isInOriginalRescueMode = false -- ตัวแปรควบคุมว่าผู้เล่นอยู่ใน Original Rescue Mode หรือไม่
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
	local originalRescueModel = VehicleController.getOriginalRescueModel()
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
	isInOriginalRescueMode = true

	-- ใช้ SpawnPointManager เพื่อขอ spawn point จาก server
	local finalSpawnPosition = SpawnPointManager.getSpawnPoint(5) -- timeout 5 วินาที

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
	local originalRescueModel = workspace:FindFirstChild(player.Name .. "_Rescue")
	if not originalRescueModel then
		warn("Original Rescue Model not found after server spawn")
		isInOriginalRescueMode = false
		return
	end

	DrillSystem.setDrillEnabled(true)

	-- เก็บใน VehicleController
	VehicleController.setOriginalRescueModel(originalRescueModel)

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

		-- เริ่ม Game Timer (ใช้ GameConfig)
		GameTimer.startCountdown(GameConfig.getGameDuration())

		-- Set callback เมื่อ timer หมด
		GameTimer.onTimerFinished = function()
			print("Timer finished - notifying server...")
			-- ส่งสัญญาณไปยัง server เมื่อ timer หมดจริงๆ
			local gameTimerRemote = remoteEvents:FindFirstChild("GameTimer")
			if gameTimerRemote then
				gameTimerRemote:FireServer("timerFinished")
			end
		end

		-- ล้าง connection เก่าก่อนสร้างใหม่
		if connections.originalRescueControl then
			connections.originalRescueControl:Disconnect()
			connections.originalRescueControl = nil
		end

		connections.originalRescueControl = RunService.Heartbeat:Connect(function()
			updateOriginalRescueControls() -- ส่ง input ไป server
			-- อัปเดต flip GUI
			updateFlipGui()
			-- กล้องจะตามรถอัตโนมัติผ่าน CameraSubject แล้ว ไม่ต้องปรับ manual
		end)

		isInOriginalRescueMode = true
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

	-- รีเซ็ต inputs ใน VehicleController
	VehicleController.setThrottleInput(0)
	VehicleController.setSteerInput(0)

	-- ส่งคำสั่งหยุดไป server
	stopOriginalRescueEvent:FireServer()

	-- หยุด camera tracking
	CameraSystem.stopCameraTracking()

	-- ปลดล็อค character และคืน camera
	if character and character:FindFirstChild("Humanoid") then
		character.Humanoid.PlatformStand = false
		if character.PrimaryPart then
			character.PrimaryPart.Anchored = false
		end

		-- กล้องจะถูก reset ใน CameraSystem.stopCameraTracking() แล้ว แต่เผื่อไว้
		if not CameraSystem.isInZoomMode() then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = character.Humanoid
		end

		-- เทเลพอร์ตออกจากรถ
		local originalRescueModel = VehicleController.getOriginalRescueModel()
		if character.PrimaryPart and originalRescueModel and originalRescueModel.PrimaryPart then
			local exitPos = originalRescueModel.PrimaryPart.Position + Vector3.new(5, 3, 0)
			character:SetPrimaryPartCFrame(CFrame.new(exitPos))
		end
	end

	-- ล้างตัวแปรใน VehicleController
	VehicleController.clearVehicleParts()
	VehicleController.setOriginalRescueModel(nil)

	-- ลบ flip GUI
	if flipSurfaceGui then
		flipSurfaceGui:Destroy()
		flipSurfaceGui = nil
	end

	-- หยุด Game Timer
	GameTimer.stopTimer()

	-- originalRescueModel ถูกล้างใน VehicleController แล้ว
	isRescueMode = false
	isInOriginalRescueMode = false
	print("Reset isInOriginalRescueMode = false")

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
		if VehicleController.getOriginalRescueModel() then
			stopOriginalRescueMode()
		elseif isRescueMode then
			stopRescueMode()
		end
	end

	-- Toggle Drill Mode with Q key
	if input.KeyCode == Enum.KeyCode.Q then
		if isRescueMode or VehicleController.getOriginalRescueModel() then
			isDrillModeActive = not isDrillModeActive

			-- ส่งคำสั่งไป Server ให้ปรับ Tube2 และ Head HingeConstraint
			toggleDrillModeRemote:FireServer(isDrillModeActive)

			if isDrillModeActive then
				print("[Drill Mode] Activated - Ready to drill!")
			else
				print("[Drill Mode] Deactivated")
			end
		end
	end

	-- Camera tracking controls
	if input.KeyCode == Enum.KeyCode.Z then
		-- กด Z เพื่อ toggle camera tracking (ติดตาม Camera part ของ rescue vehicle)
		print("DEBUG: Z key pressed, calling CameraSystem.toggleCameraTracking()")
		CameraSystem.toggleCameraTracking()
	elseif input.KeyCode == Enum.KeyCode.X then
		-- กด X เพื่อ toggle thermal vision (ต้องมี Thermometer Camera)
		-- เช็คว่ามี Thermometer Camera equip อยู่หรือไม่
		local equippedItems = CustomizeService.getEquippedItems()
		local hasThermometerCamera = false

		if equippedItems then
			for _, equippedItem in ipairs(equippedItems) do
				if equippedItem.id == "ThermometerCamera" then
					hasThermometerCamera = true
					break
				end
			end
		end

		if hasThermometerCamera then
			CameraSystem.toggleThermalVision()
		else
			print("[CameraSystem] Thermometer Camera required to use thermal vision!")
		end
	end

	if CameraSystem.isInZoomMode() then
		if input.KeyCode == Enum.KeyCode.One then
			CameraSystem.setCameraZoomFactor(1)
		elseif input.KeyCode == Enum.KeyCode.Two then
			CameraSystem.setCameraZoomFactor(2)
		elseif input.KeyCode == Enum.KeyCode.Five then
			CameraSystem.setCameraZoomFactor(5)
		end
	end

	-- คลิกที่ไหนบนหน้าจอก็ได้เพื่อเจาะหรือเปิดใช้ hydraulic arm (เฉพาะใน rescue mode)
	if input.UserInputType == Enum.UserInputType.MouseButton1 and (isRescueMode or VehicleController.getOriginalRescueModel()) then
		-- ได้ตำแหน่งของเมาส์
		local mouse = player:GetMouse()
		local clickPosition = mouse.Hit.Position

		-- เช็คว่า DrillArm อยู่ที่ TargetAngle = 0 หรือไม่ และ Head.HingeConstraint.Enabled
		local canDrill = false
		local currentTargetAngle = nil
		local currentRescueModel = VehicleController.getOriginalRescueModel() or rescueModel
		if currentRescueModel then
			local drillArm = currentRescueModel:FindFirstChild("DrillArm")
			if drillArm then
				-- เช็ค Tube2.HingeConstraint TargetAngle
				local tube2 = drillArm:FindFirstChild("Tube2")
				if tube2 then
					local hingeConstraint = tube2:FindFirstChild("HingeConstraint")
					if hingeConstraint then
						currentTargetAngle = hingeConstraint.TargetAngle
						print("[Click Debug] TargetAngle:", currentTargetAngle, "isDrillModeActive:", isDrillModeActive)
						if hingeConstraint.TargetAngle == 0 then
							canDrill = true
						end
					end
				end

				-- เช็ค Head.HingeConstraint.Enabled (ต้อง Enabled ด้วย)
				local head = drillArm:FindFirstChild("Head")
				if head then
					local headHingeConstraint = head:FindFirstChild("HingeConstraint")
					if headHingeConstraint and not headHingeConstraint.Enabled then
						canDrill = false
						print("[Click Debug] Head.HingeConstraint is disabled")
					end
				end
			end
		end

		-- ลองเจาะได้ก็ต่อเมื่อ TargetAngle = 0 และเปิด Drill Mode
		if canDrill and isDrillModeActive then
			print("[Drill Mode] Drilling allowed - TargetAngle = 0")
			local didDrill = DrillSystem.handleDrillingClick(clickPosition)

			if not didDrill then
				-- ถ้าไม่มี part ให้เจาะ ก็เปิด hydraulic arm ธรรมดา
				hydraulicRemote:FireServer()
				print("Screen clicked - Hydraulic arm activated!")
			end
		elseif isDrillModeActive and not canDrill then
			-- ถ้าเปิด Drill Mode แต่ TargetAngle ไม่ใช่ 0 ให้แสดงข้อความเตือนและไม่ให้เจาะ
			warn("[Drill Mode] Cannot drill! DrillArm must be at TargetAngle = 0. Current:", currentTargetAngle)
			print("Press Q to move DrillArm to position 0")
		else
			-- ถ้าปิด Drill Mode (isDrillModeActive = false) ไม่ต้องทำอะไร
			-- ไม่เรียก hydraulicRemote เพราะ Head.HingeConstraint ถูก Disable แล้ว
			print("[Drill Mode] Drill mode is off - press Q to activate")
		end
	end

	-- Manual control inputs (เฉพาะเมื่ออยู่ใน Rescue Mode หรือ Original Rescue Mode)
	if isRescueMode or isInOriginalRescueMode then
		if input.KeyCode == Enum.KeyCode.W then
			VehicleController.setThrottleInput(1)
		elseif input.KeyCode == Enum.KeyCode.S then
			VehicleController.setThrottleInput(-0.8)
		elseif input.KeyCode == Enum.KeyCode.A then
			VehicleController.setSteerInput(1)
		elseif input.KeyCode == Enum.KeyCode.D then
			VehicleController.setSteerInput(-1)
		elseif input.KeyCode == Enum.KeyCode.Space then
			-- กด SPACE เพื่อ flip รถเมื่อคว่ำ หรือดันรถถ้าแค่ติดอยู่
			VehicleController.handleSpaceKey()
		end
	-- else
		-- WASD input ignored when not in control mode
	end
end)

connections.inputChanged = UserInputService.InputChanged:Connect(function(input)
	if not CameraSystem.isInZoomMode() then return end

	if input.UserInputType == Enum.UserInputType.MouseWheel then
		local direction = 0
		if input.Position.Z > 0 then
			direction = 1
		elseif input.Position.Z < 0 then
			direction = -1
		end

		if direction ~= 0 then
			CameraSystem.adjustCameraZoom(direction)
		end
	end
end)

connections.inputEnded = UserInputService.InputEnded:Connect(function(input, gameProcessed)
	if not (isRescueMode or isInOriginalRescueMode) then return end

	if input.KeyCode == Enum.KeyCode.W or input.KeyCode == Enum.KeyCode.S then
		VehicleController.setThrottleInput(0)
	elseif input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.D then
		VehicleController.setSteerInput(0)
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
							local maxPlayersFromConfig = GameConfig.getMaxPlayers()
							local remaining = maxPlayersFromConfig - waitingCount
							if waitingCount > 0 and remaining > 0 then
								textLabel.Text = string.format("Waiting for other players %d/%d คน", remaining, maxPlayersFromConfig)
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

		print("Waiting count updated:", waitingCount, "/", GameConfig.getMaxPlayers())
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
			ShopUI.closeShop()
			ShopUI.setButtonVisible(false)
			CustomizeUI.closeCustomize()
			CustomizeUI.setButtonVisible(false)

			local function cleanupVotingCallback()
				if unregisterVotingComplete then
					unregisterVotingComplete()
					unregisterVotingComplete = nil
				end
			end

			local function handleVotingFinished()
				cleanupVotingCallback()
				freezePlayerForRescue()
				task.delay(2, startOriginalRescueMode)
			end

			cleanupVotingCallback()
			unregisterVotingComplete = MapSelectionSystem.onVotingComplete(function()
				handleVotingFinished()
			end)

			-- เริ่ม Map Selection สำหรับ player คนนี้เท่านั้น (client-side)
			-- ส่งเฉพาะ local player เพราะแต่ละ client ทำ map selection แยกกัน
			local startedVoting = MapSelectionSystem.startVoting({player})
			if not startedVoting then
				warn("[RescueBotController] Failed to start map voting - freezing immediately")
				handleVotingFinished()
			end
		end)
	elseif action == "returnToLobby" then
		print("Returning to lobby after game summary")

		if unregisterVotingComplete then
			unregisterVotingComplete()
			unregisterVotingComplete = nil
		end
		ShopUI.setButtonVisible(true)
		CustomizeUI.setButtonVisible(true)

		-- ล้างสถานะเกมทั้งหมด
		playerInGame = false
		isRescueMode = false
		isInOriginalRescueMode = false

		-- ลบ GUI ต่างๆ
		cleanupGameGUIs()

		-- ลบ Original Rescue Model
		local originalRescueModel = VehicleController.getOriginalRescueModel()
		if originalRescueModel then
			originalRescueModel:Destroy()
			VehicleController.setOriginalRescueModel(nil)
		end

		-- รีเซ็ตกล้องกลับมาหาผู้เล่น
		if character and character:FindFirstChild("Humanoid") then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = character.Humanoid

			-- ปลดการ anchor character (กรณีที่ถูก anchor ไว้จากเกม)
			if character.PrimaryPart then
				character.PrimaryPart.Anchored = false
			end

			-- รีเซ็ต humanoid state
			local humanoid = character.Humanoid
			humanoid.PlatformStand = false
			humanoid.Sit = false

			print("Camera and character reset to normal state")
		end

		-- Spawn companion หลังจาก reset เสร็จ
		wait(0.5) -- รอให้ reset เสร็จก่อน
		spawnRescueCompanion()

		-- เข้าโหมดควบคุม companion ทันที
		wait(0.5) -- รอให้ companion spawn เสร็จ
		if rescueModel then
			startRescueMode(false) -- ไม่ใช้ camera tracking
		end

		print("Successfully returned to lobby with new companion - ready for next game")

		local simu = workspace:FindFirstChild("Simu")
		if simu and simu:FindFirstChild("Attachment") then
			local billboardGui = simu.Attachment:FindFirstChild("BillboardGui")
			if billboardGui and billboardGui:FindFirstChild("Frame") then
				local textLabel = billboardGui.Frame:FindFirstChild("TextLabel")
				if textLabel then
					textLabel.Text = "Please join the mission!"
					textLabel.Visible = true
				end
			end
		end

	elseif action == "gameEnded" then
		print("Game ended - can join new game")
		-- รีเซ็ตสถานะ
		playerInGame = false
		if unregisterVotingComplete then
			unregisterVotingComplete()
			unregisterVotingComplete = nil
		end
		ShopUI.setButtonVisible(true)
		CustomizeUI.setButtonVisible(true)
	end
end)

print("RescueBotController loaded - Companion auto-spawned and ready to control with WASD, Press SPACEBAR to flip when stuck/flipped, Press F to stop")
print("Camera controls: Z = Toggle Camera Tracking, X = Toggle Thermal Vision")
print("Drill System: Click anywhere during rescue mode to drill or activate hydraulic arm")
