-- VehicleController ModuleScript
-- จัดการระบบควบคุมรถ, flip detection, wheel management

local RunService = game:GetService("RunService")

local VehicleController = {}

-- ตัวแปรสำหรับระบบ
local vehicleParts = {}
local manualVehicle = nil
local originalRescueModel = nil

-- Wheel smoothing variables
local wheelControlState = {}
local wheelSmoothingConnection = nil
local MAX_WHEEL_TORQUE = 120000
local FRONT_TORQUE_FACTOR = 0.7
local BRAKE_TORQUE = 12000
local WHEEL_SMOOTH_SPEED = 10

-- Input variables
local throttleInput = 0
local steerInput = 0

-- ===== UTILITY FUNCTIONS =====

local function sign(x)
	if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end
end

-- ===== WHEEL MANAGEMENT FUNCTIONS =====

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

-- ===== VEHICLE DETECTION FUNCTIONS =====

local function isWheelSlipping()
	-- ตรวจสอบจาก vehicleParts.primary
	if vehicleParts.primary then
		local velocity = vehicleParts.primary.Velocity
		local speed = velocity.Magnitude
		if speed < 2 and math.abs(throttleInput) > 0.5 then
			print("VehicleController: Wheel slipping detected from vehicleParts.primary - Speed:", speed, "ThrottleInput:", throttleInput)
			return true
		end
	end

	-- ตรวจสอบจาก VehicleSeat
	local vehicleSeat = nil
	if manualVehicle then
		vehicleSeat = manualVehicle:FindFirstChild("VehicleSeat") or manualVehicle:FindFirstChildOfClass("VehicleSeat")
	elseif originalRescueModel then
		vehicleSeat = originalRescueModel:FindFirstChild("VehicleSeat") or originalRescueModel:FindFirstChildOfClass("VehicleSeat")
	end

	if vehicleSeat then
		local velocity = vehicleSeat.Velocity
		local speed = velocity.Magnitude
		local throttleFloat = vehicleSeat.ThrottleFloat or 0

		if speed < 2 and math.abs(throttleFloat) > 0.5 then
			print("VehicleController: Wheel slipping detected from VehicleSeat - Speed:", speed, "ThrottleFloat:", throttleFloat)
			return true
		end
	end

	return false
end

local function isVehicleFlipped()
	-- หา VehicleSeat ปัจจุบัน
	local vehicleSeat = nil
	if manualVehicle then
		vehicleSeat = manualVehicle:FindFirstChild("VehicleSeat") or manualVehicle:FindFirstChildOfClass("VehicleSeat")
	elseif originalRescueModel then
		vehicleSeat = originalRescueModel:FindFirstChild("VehicleSeat") or originalRescueModel:FindFirstChildOfClass("VehicleSeat")
	end

	if not vehicleSeat then
		print("VehicleController: No VehicleSeat found for flip check")
		return false
	end

	-- ตรวจสอบว่ารถคว่ำ (UpVector หันลง)
	local upVector = vehicleSeat.CFrame.UpVector
	local isFlipped = upVector.Y < 0.5

	return isFlipped
end

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

-- ===== VEHICLE ACTIONS =====

local function flipVehicle()
	-- หา VehicleSeat ในโมเดล
	local vehicleSeat = nil
	if manualVehicle then
		vehicleSeat = manualVehicle:FindFirstChild("VehicleSeat") or manualVehicle:FindFirstChildOfClass("VehicleSeat")
	elseif originalRescueModel then
		vehicleSeat = originalRescueModel:FindFirstChild("VehicleSeat") or originalRescueModel:FindFirstChildOfClass("VehicleSeat")
	end

	if not vehicleSeat then return end

	-- หาทิศทางที่รถควรจะหันหน้า
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

	-- รีเซ็ตความเร็ว
	vehicleSeat.Velocity = Vector3.new(0, 0, 0)

	-- รีเซ็ตความเร็วของ primary part
	if manualVehicle and manualVehicle.PrimaryPart then
		manualVehicle.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		manualVehicle.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	elseif originalRescueModel and originalRescueModel.PrimaryPart then
		originalRescueModel.PrimaryPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		originalRescueModel.PrimaryPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end

	print("VehicleController: Vehicle flipped back to upright position!")
end

local function nudgeVehicle()
	local vehicle = manualVehicle or originalRescueModel
	if not vehicle then
		print("VehicleController: No vehicle available for nudge")
		return
	end

	local primaryPart = vehicle.PrimaryPart
	if not primaryPart then
		print("VehicleController: Vehicle has no PrimaryPart - cannot nudge")
		return
	end

	if primaryPart.Anchored then
		print("VehicleController: PrimaryPart anchored - cannot apply nudge")
		return
	end

	local mass = primaryPart.AssemblyMass
	if mass <= 0 then
		return
	end

	local upwardImpulse = Vector3.new(0, mass * 90, 0)
	local forwardImpulse = primaryPart.CFrame.LookVector * (mass * 35)
	primaryPart:ApplyImpulse(upwardImpulse + forwardImpulse)

	print("VehicleController: Vehicle nudged to regain traction")
end

-- ===== VEHICLE SETUP =====

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
	vehicleParts.maxAngularVelocity = 15 / radius

	return true
end

-- ===== PUBLIC API =====

function VehicleController.setThrottleInput(value)
	throttleInput = value or 0
end

function VehicleController.setSteerInput(value)
	steerInput = value or 0
end

function VehicleController.getThrottleInput()
	return throttleInput
end

function VehicleController.getSteerInput()
	return steerInput
end

function VehicleController.setupVehicle(vehicle)
	return setupVehicleParts(vehicle)
end

function VehicleController.setOriginalRescueModel(model)
	originalRescueModel = model
end

function VehicleController.getOriginalRescueModel()
	return originalRescueModel
end

function VehicleController.getManualVehicle()
	return manualVehicle
end

function VehicleController.getVehicleParts()
	return vehicleParts
end

function VehicleController.clearVehicleParts()
	vehicleParts = {}
	manualVehicle = nil
end

function VehicleController.clearWheelState()
	if wheelSmoothingConnection then
		wheelSmoothingConnection:Disconnect()
		wheelSmoothingConnection = nil
	end
	wheelControlState = {}
end

-- Vehicle state checks
function VehicleController.isVehicleFlipped()
	return isVehicleFlipped()
end

function VehicleController.isVehicleStuck()
	return isVehicleStuck()
end

function VehicleController.isWheelSlipping()
	return isWheelSlipping()
end

-- Vehicle actions
function VehicleController.flipVehicle()
	flipVehicle()
end

function VehicleController.nudgeVehicle()
	nudgeVehicle()
end

function VehicleController.handleSpaceKey()
	-- กด SPACE เพื่อ flip รถเมื่อคว่ำ หรือดันรถถ้าแค่ติดอยู่
	if isVehicleFlipped() then
		flipVehicle()
	elseif isVehicleStuck() then
		nudgeVehicle()
	end
end

-- Wheel control functions
function VehicleController.setWheelTargets(constraint, targetAV, targetTorque)
	setWheelTargets(constraint, targetAV, targetTorque)
end

function VehicleController.initializeWheelConstraint(constraint, torqueLimit)
	initializeWheelConstraint(constraint, torqueLimit)
end

-- Constants
function VehicleController.getConstants()
	return {
		MAX_WHEEL_TORQUE = MAX_WHEEL_TORQUE,
		FRONT_TORQUE_FACTOR = FRONT_TORQUE_FACTOR,
		BRAKE_TORQUE = BRAKE_TORQUE,
		WHEEL_SMOOTH_SPEED = WHEEL_SMOOTH_SPEED
	}
end

return VehicleController