local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- Import shared config
local DrillConfig = require(ReplicatedStorage.Modules.DrillConfig)

-- สร้าง RemoteEvents สำหรับสื่อสารกับ client
local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
if not remoteEventsFolder then
	remoteEventsFolder = Instance.new("Folder")
	remoteEventsFolder.Name = "RescueBotRemotes"
	remoteEventsFolder.Parent = ReplicatedStorage
end

local function getOrCreateRemote(name)
	local remote = remoteEventsFolder:FindFirstChild(name)
	if remote then
		if remote:IsA("RemoteEvent") then
			return remote
		end
		remote:Destroy()
	end

	remote = Instance.new("RemoteEvent")
	remote.Name = name
	remote.Parent = remoteEventsFolder
	return remote
end

local spawnCompanionEvent = getOrCreateRemote("SpawnCompanion")
local controlEvent = getOrCreateRemote("ControlVehicle")
local stopControlEvent = getOrCreateRemote("StopControl")
local hydraulicRemote = getOrCreateRemote("ActivateHydraulic")
local spawnOriginalRescueEvent = getOrCreateRemote("SpawnOriginalRescue")
local controlOriginalRescueEvent = getOrCreateRemote("ControlOriginalRescue")
local stopOriginalRescueEvent = getOrCreateRemote("StopOriginalRescue")
local drillProgressRemote = getOrCreateRemote("HydraulicDrillProgress")
local CompanionFollower = require(script.Parent:WaitForChild("CompanionFollower"))

-- เก็บข้อมูลรถของแต่ละผู้เล่น
local playerVehicles = {}
local vehicleConnections = {}
local playerDrillStates = {}
local playerOriginalRescue = {}
local playerDrillTargets = {}
local originalRescueConnections = {}
local drillDebounce = {} -- ป้องกันการคลิกเร็วเกินไป

local function sign(x)
	if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end
end

-- ฟังก์ชันควบคุมรถ
local function updateVehicleControl(player, vehicle, throttleInput, steerInput)
	if not vehicle or not vehicle.PrimaryPart then return end

	-- หา vehicle parts
	local primary = vehicle.PrimaryPart
	local attachmentFL = primary:FindFirstChild("AttachmentFL")
	local attachmentFR = primary:FindFirstChild("AttachmentFR")

	local wheelBL = vehicle:FindFirstChild("Wheel_BL")
	local wheelBR = vehicle:FindFirstChild("Wheel_BR")
	local wheelFL = vehicle:FindFirstChild("Wheel_FL")
	local wheelFR = vehicle:FindFirstChild("Wheel_FR")

	if not (wheelBL and wheelBR) then return end

	local cylindricalBL = wheelBL:FindFirstChildOfClass("CylindricalConstraint")
	local cylindricalBR = wheelBR:FindFirstChildOfClass("CylindricalConstraint")
	local cylindricalFL = wheelFL and wheelFL:FindFirstChildOfClass("CylindricalConstraint")
	local cylindricalFR = wheelFR and wheelFR:FindFirstChildOfClass("CylindricalConstraint")

	if not (cylindricalBL and cylindricalBR) then return end

	-- Set network ownership (skip while anchored to avoid errors)
	if primary.Anchored then
		pcall(function()
			primary:SetNetworkOwner(nil)
		end)
		if wheelBL then pcall(function() wheelBL:SetNetworkOwner(nil) end) end
		if wheelBR then pcall(function() wheelBR:SetNetworkOwner(nil) end) end
		if wheelFL then pcall(function() wheelFL:SetNetworkOwner(nil) end) end
		if wheelFR then pcall(function() wheelFR:SetNetworkOwner(nil) end) end

		local function brakeConstraint(constraint)
			if not constraint then return end
			constraint.AngularVelocity = 0
			constraint.MotorMaxTorque = 0
		end
		brakeConstraint(cylindricalBL)
		brakeConstraint(cylindricalBR)
		brakeConstraint(cylindricalFL)
		brakeConstraint(cylindricalFR)
		return
	else
		primary:SetNetworkOwner(player)
		if wheelBL then wheelBL:SetNetworkOwner(player) end
		if wheelBR then wheelBR:SetNetworkOwner(player) end
		if wheelFL then wheelFL:SetNetworkOwner(player) end
		if wheelFR then wheelFR:SetNetworkOwner(player) end
	end

	-- Steering
	if attachmentFL and attachmentFR then
		local baseFL = attachmentFL:GetAttribute("BaseOrientation") or attachmentFL.Orientation
		local baseFR = attachmentFR:GetAttribute("BaseOrientation") or attachmentFR.Orientation

		-- เก็บค่าตั้งต้น
		if not attachmentFL:GetAttribute("BaseOrientation") then
			attachmentFL:SetAttribute("BaseOrientation", baseFL)
		end
		if not attachmentFR:GetAttribute("BaseOrientation") then
			attachmentFR:SetAttribute("BaseOrientation", baseFR)
		end

		local yaw = steerInput * 35
		attachmentFL.Orientation = Vector3.new(baseFL.X, baseFL.Y + yaw, baseFL.Z)
		attachmentFR.Orientation = Vector3.new(baseFR.X, baseFR.Y + yaw, baseFR.Z)
	end

	-- Throttle
	local dir = sign(throttleInput)
	if dir == 0 then
		-- หยุดรถทันทีด้วยแรงเบรก
		local brakeTorque = 20000 -- แรงเบรกสูงเพื่อหยุดทันที
		cylindricalBL.AngularVelocity = 0
		cylindricalBR.AngularVelocity = 0
		cylindricalBL.MotorMaxTorque = brakeTorque
		cylindricalBR.MotorMaxTorque = brakeTorque
		if cylindricalFL then
			cylindricalFL.AngularVelocity = 0
			cylindricalFL.MotorMaxTorque = brakeTorque
		end
		if cylindricalFR then
			cylindricalFR.AngularVelocity = 0
			cylindricalFR.MotorMaxTorque = brakeTorque
		end
		return
	end

	-- คำนวณแรงบิด
	local baseTorque = 8000
	local minTorque = 3000
	local vehicleOrientation = primary.CFrame.LookVector
	local slopeBonus = 1
	if vehicleOrientation.Y > 0.1 then
		slopeBonus = 1.2 + (vehicleOrientation.Y * 1)
	end

	local torque = math.max(math.abs(throttleInput) * baseTorque * slopeBonus, minTorque)
	local radius = wheelBR.Size.Y * 0.5
	local maxAngularVelocity = 15 / radius
	local targetAV = dir * maxAngularVelocity

	-- ขับล้อ
	cylindricalBL.MotorMaxTorque = torque
	cylindricalBR.MotorMaxTorque = torque
	cylindricalBL.AngularVelocity = targetAV
	cylindricalBR.AngularVelocity = targetAV

	if cylindricalFL then
		cylindricalFL.MotorMaxTorque = torque * 0.7
		cylindricalFL.AngularVelocity = targetAV
	end
	if cylindricalFR then
		cylindricalFR.MotorMaxTorque = torque * 0.7
		cylindricalFR.AngularVelocity = targetAV
	end
end

-- Spawn companion
spawnCompanionEvent.OnServerEvent:Connect(function(player, position, orientation)
	if playerVehicles[player] then
		playerVehicles[player]:Destroy()
	end

	local rescueTemplate = ReplicatedStorage:FindFirstChild("RescueCompanion")
	if not rescueTemplate then return end

	local companion = rescueTemplate:Clone()
	companion.Name = player.Name .. "_RescueCompanion"
	companion:SetAttribute("OwnerUserId", player.UserId)
	companion:SetAttribute("OwnerName", player.Name)

	-- ใส่ใน workspace ก่อน
	companion.Parent = workspace

	-- คำนวณตำแหน่ง spawn
	local spawnPosition = position
	local spawnLook = orientation

	local character = player.Character
	if character and character.PrimaryPart then
		local charPrimary = character.PrimaryPart
		local rightVector = charPrimary.CFrame.RightVector
		spawnPosition = (charPrimary.Position + rightVector * 2)
		spawnLook = charPrimary.CFrame.LookVector
	elseif not spawnPosition then
		spawnPosition = Vector3.new(0, 10, 0)
		spawnLook = Vector3.new(0, 0, -1)
	elseif not spawnLook then
		spawnLook = Vector3.new(0, 0, -1)
	end

	-- ใช้ PivotTo เพื่อตั้งตำแหน่งหลังจากใส่ใน workspace แล้ว
	companion:PivotTo(CFrame.new(spawnPosition, spawnPosition + spawnLook))

	CompanionFollower.start(companion)

	local vehicleSeat = companion:FindFirstChildWhichIsA("VehicleSeat", true)
	if vehicleSeat then
		vehicleSeat:GetPropertyChangedSignal("Occupant"):Connect(function()
			local occupant = vehicleSeat.Occupant
			if occupant then
				task.defer(function()
					if vehicleSeat.Occupant == occupant then
						occupant.Sit = false
					end
				end)
			end
		end)
	end

	playerVehicles[player] = companion
	print("Spawned companion for", player.Name)
end)

-- Control vehicle
controlEvent.OnServerEvent:Connect(function(player, throttleInput, steerInput)
	local vehicle = playerVehicles[player]
	if not vehicle then return end

	-- เก็บ input ล่าสุด
	vehicle:SetAttribute("ThrottleInput", throttleInput)
	vehicle:SetAttribute("SteerInput", steerInput)

	-- เริ่ม/อัพเดท connection
	local connectionKey = tostring(player.UserId)
	if vehicleConnections[connectionKey] then
		return -- connection มีอยู่แล้ว
	end

	vehicleConnections[connectionKey] = RunService.Heartbeat:Connect(function()
		local currentThrottle = vehicle:GetAttribute("ThrottleInput") or 0
		local currentSteer = vehicle:GetAttribute("SteerInput") or 0
		updateVehicleControl(player, vehicle, currentThrottle, currentSteer)
	end)
end)

-- Stop control
stopControlEvent.OnServerEvent:Connect(function(player)
	local vehicle = playerVehicles[player]
	if vehicle then
		-- หยุดรถ
		vehicle:SetAttribute("ThrottleInput", 0)
		vehicle:SetAttribute("SteerInput", 0)
		updateVehicleControl(player, vehicle, 0, 0)

		-- หยุด connection
		local connectionKey = tostring(player.UserId)
		if vehicleConnections[connectionKey] then
			vehicleConnections[connectionKey]:Disconnect()
			vehicleConnections[connectionKey] = nil
		end
	end
end)

-- ฟังก์ชันหา DrillArm ของผู้เล่น
local function findPlayerDrillHinge(player)
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and model.Name == player.Name .. "_Rescue" then
			local drillArm = model:FindFirstChild("DrillArm")
			if drillArm then
				local head = drillArm:FindFirstChild("Head")
				if head and head:IsA("BasePart") then
					local hinge = head:FindFirstChildOfClass("HingeConstraint")
					if hinge then
						return hinge, model
					end
				end
			end
		end
	end
	return nil, nil
end

local MAX_COMBO = 5
local BASE_SPEED = 18
local SPEED_STEP = 12
local BASE_TORQUE = 12000
local TORQUE_STEP = 18000
local COMBO_TIMEOUT = 1.5

local function findMotorInside(part)
	if not part then
		return nil
	end

	local motor = part:FindFirstChildWhichIsA("Motor6D")
	if motor then
		return motor
	end

	for _, descendant in ipairs(part:GetDescendants()) do
		if descendant:IsA("Motor6D") then
			return descendant
		end
	end

	return nil
end

local function locateDrillTarget(state)
	if not state then
		return nil
	end

	local hinge = state.hinge
	local head = hinge and hinge.Parent
	if not (head and head:IsA("BasePart")) then
		return nil
	end

	local nearbyParts = workspace:GetPartBoundsInRadius(head.Position, DrillConfig.TARGET_RADIUS)
	local best
	local bestDistance = math.huge
	for _, candidate in ipairs(nearbyParts) do
		local isOwn = state.model and state.model:IsAncestorOf(candidate)
		if candidate ~= head and not isOwn and candidate:IsA("BasePart") then
			local motor = findMotorInside(candidate)
			if motor then
				local distance = (candidate.Position - head.Position).Magnitude
				if distance < bestDistance then
					bestDistance = distance
					best = {
						part = candidate,
						motor = motor,
					}
				end
			end
		end
	end

	return best
end

local function resetDrillTarget(player)
	local targetInfo = playerDrillTargets[player]
	if not targetInfo then
		return
	end
	playerDrillTargets[player] = nil
	pcall(function()
		drillProgressRemote:FireClient(player, {
			status = "cancel",
		})
	end)
end

local function updateDrillProgress(player, state)
	local detected = locateDrillTarget(state)
	if not detected then
		resetDrillTarget(player)
		return
	end

	local current = playerDrillTargets[player]
	if not current or current.part ~= detected.part then
		current = {
			part = detected.part,
			motor = detected.motor,
			clicks = 0,
			required = DrillConfig.CLICKS_REQUIRED,
		}
		playerDrillTargets[player] = current
		drillProgressRemote:FireClient(player, {
			status = "start",
			partName = current.part.Name,
			progress = 0,
			requiredClicks = current.required,
			clicks = 0,
		})
	else
		current.motor = current.motor or detected.motor
	end

	current.clicks += 1
	local progress = math.clamp(current.clicks / current.required, 0, 1)

	if progress >= 1 then
		local motor = current.motor
		if motor and motor.Parent then
			pcall(function()
				motor:Destroy()
			end)
		else
			-- หากหา motor ไม่เจอแล้ว ให้ลองค้นหาอีกครั้งก่อนจบ
			local freshMotor = findMotorInside(current.part)
			if freshMotor then
				pcall(function()
					freshMotor:Destroy()
				end)
			end
		end
		drillProgressRemote:FireClient(player, {
			status = "complete",
			partName = current.part.Name,
			progress = 1,
			requiredClicks = current.required,
			clicks = current.required,
		})
		playerDrillTargets[player] = nil
	else
		drillProgressRemote:FireClient(player, {
			status = "inprogress",
			partName = current.part.Name,
			progress = progress,
			requiredClicks = current.required,
			clicks = current.clicks,
		})
	end
end

local function applyDrillSpin(player, state)
	local hinge = state.hinge
	if not hinge then
		return
	end
	state.isActive = true
	state.combo = math.clamp(state.combo, 1, MAX_COMBO)

	if hinge.ActuatorType ~= Enum.ActuatorType.Motor then
		hinge.ActuatorType = Enum.ActuatorType.Motor
	end

	local head = hinge.Parent
	if head and head:IsA("BasePart") then
		if state.head ~= head then
			state.head = head
			state.originalMassless = head.Massless
			state.originalPhysicalProperties = head.CustomPhysicalProperties
		end
		head.Massless = true
		pcall(function()
			head.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.3)
		end)
	end

	local model = state.model
	if model and model.PrimaryPart then
		if not state.anchorInfo then
			state.anchorInfo = {
				part = model.PrimaryPart,
				wasAnchored = model.PrimaryPart.Anchored,
			}
			state.wheelConstraints = {}
			state.anchoredParts = {}
			local drillArm = model:FindFirstChild("DrillArm")
			for _, descendant in ipairs(model:GetDescendants()) do
				if descendant:IsA("BasePart") then
					if drillArm and drillArm:IsAncestorOf(descendant) then
						continue
					end
					table.insert(state.anchoredParts, {
						part = descendant,
						wasAnchored = descendant.Anchored,
					})
					descendant.Anchored = true
					descendant.AssemblyLinearVelocity = Vector3.zero
					descendant.AssemblyAngularVelocity = Vector3.zero
				end
			end
			local function disableConstraint(wheel)
				if not wheel then return end
				local constraint = wheel:FindFirstChildOfClass("CylindricalConstraint")
				if constraint then
					state.wheelConstraints[constraint] = {
						enabled = constraint.Enabled,
						angularVelocity = constraint.AngularVelocity,
						motorTorque = constraint.MotorMaxTorque,
					}
					constraint.AngularVelocity = 0
					constraint.MotorMaxTorque = 0
					constraint.Enabled = false
				end
			end
			disableConstraint(model:FindFirstChild("Wheel_BL"))
			disableConstraint(model:FindFirstChild("Wheel_BR"))
			disableConstraint(model:FindFirstChild("Wheel_FL"))
			disableConstraint(model:FindFirstChild("Wheel_FR"))
		end
	end

	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if state.humanoid ~= humanoid then
			state.humanoid = humanoid
			state.originalWalkSpeed = humanoid.WalkSpeed
			state.originalAutoRotate = humanoid.AutoRotate
		end
		if not state.walkSuppressed then
			state.originalWalkSpeed = humanoid.WalkSpeed
			state.originalAutoRotate = humanoid.AutoRotate
			humanoid.WalkSpeed = 0
			humanoid.AutoRotate = false
			state.walkSuppressed = true
		end
	end

	local speed = BASE_SPEED + (state.combo - 1) * SPEED_STEP
	local torque = BASE_TORQUE + (state.combo - 1) * TORQUE_STEP
	pcall(function()
		hinge.AngularSpeed = speed
		hinge.MotorMaxTorque = torque
		hinge.AngularResponsiveness = 80
	end)
end

local function stopDrillSpin(state)
	if not state then
		return
	end
	if state.isActive then
		return
	end
	local hinge = state.hinge
	if hinge then
		pcall(function()
			hinge.AngularSpeed = 0
			hinge.MotorMaxTorque = 0
		end)
	end
	if state.anchoredParts then
		for _, info in ipairs(state.anchoredParts) do
			local part = info.part
			if part then
				pcall(function()
					part.Anchored = info.wasAnchored and true or false
				end)
			end
		end
		state.anchoredParts = nil
	end
	if state.anchorInfo and state.anchorInfo.part then
		local part = state.anchorInfo.part
		local wasAnchored = state.anchorInfo.wasAnchored
		pcall(function()
			part.Anchored = wasAnchored
		end)
	end
	state.anchorInfo = nil
	if state.head and state.head:IsA("BasePart") then
		local head = state.head
		head.Massless = state.originalMassless or false
		pcall(function()
			head.CustomPhysicalProperties = state.originalPhysicalProperties
		end)
	end
	state.head = nil
	state.originalMassless = nil
	state.originalPhysicalProperties = nil

	if state.wheelConstraints then
		for constraint, info in pairs(state.wheelConstraints) do
			if constraint then
				pcall(function()
					constraint.Enabled = info.enabled ~= nil and info.enabled or true
					constraint.AngularVelocity = 0
					constraint.MotorMaxTorque = info.motorTorque or 0
				end)
			end
		end
		state.wheelConstraints = nil
	end

	if state.model then
		local primary = state.model.PrimaryPart
		local function zeroConstraint(basePart)
			if not basePart then return end
			local constraint = basePart:FindFirstChildOfClass("CylindricalConstraint")
			if constraint then
				constraint.AngularVelocity = 0
				constraint.MotorMaxTorque = 0
			end
		end
		local wheelBL = state.model:FindFirstChild("Wheel_BL")
		local wheelBR = state.model:FindFirstChild("Wheel_BR")
		local wheelFL = state.model:FindFirstChild("Wheel_FL")
		local wheelFR = state.model:FindFirstChild("Wheel_FR")
		zeroConstraint(wheelBL)
		zeroConstraint(wheelBR)
		zeroConstraint(wheelFL)
		zeroConstraint(wheelFR)
	end

	if state.walkSuppressed and state.humanoid then
		local humanoid = state.humanoid
		pcall(function()
			humanoid.WalkSpeed = state.originalWalkSpeed or 16
			humanoid.AutoRotate = (state.originalAutoRotate == nil) and true or state.originalAutoRotate
		end)
	end
	state.walkSuppressed = nil
	state.humanoid = nil
	state.originalWalkSpeed = nil
	state.originalAutoRotate = nil
end

hydraulicRemote.OnServerEvent:Connect(function(player)
	local now = tick()
	if drillDebounce[player] and (now - drillDebounce[player]) < 0.15 then
		return
	end
	drillDebounce[player] = now

	local hinge, rescueModel = findPlayerDrillHinge(player)
	if not hinge then
		warn("Drill arm not found for", player.Name)
		return
	end

	local state = playerDrillStates[player]
	if not state then
		state = { combo = 0, lastTime = 0, token = 0, hinge = hinge, model = rescueModel }
		playerDrillStates[player] = state
	else
		state.hinge = hinge
		state.model = rescueModel
	end

	if now - state.lastTime <= COMBO_TIMEOUT then
		state.combo = math.min(state.combo + 1, MAX_COMBO)
	else
		state.combo = 1
	end
	state.lastTime = now

	applyDrillSpin(player, state)

	state.token = (state.token or 0) + 1
	local token = state.token

	updateDrillProgress(player, state)
	task.delay(COMBO_TIMEOUT, function()
		if state.token ~= token then
			return
		end
		state.combo = 0
		state.isActive = false
		stopDrillSpin(state)
		resetDrillTarget(player)
	end)
end)

-- Spawn Original Rescue Model
spawnOriginalRescueEvent.OnServerEvent:Connect(function(player, position)
	-- ลบ original rescue model เก่า (ถ้ามี)
	if playerOriginalRescue[player] then
		playerOriginalRescue[player]:Destroy()
		playerOriginalRescue[player] = nil
	end

	-- หา Rescue template
	local rescueTemplate = ReplicatedStorage:FindFirstChild("Rescue")
	if not rescueTemplate or not rescueTemplate:IsA("Model") then
		warn("Rescue Model not found in ReplicatedStorage")
		return
	end

	print("Server: Cloning new Rescue Model for", player.Name)
	local originalRescueModel = rescueTemplate:Clone()
	originalRescueModel.Name = player.Name .. "_Rescue"

	originalRescueModel.Parent = workspace

	if not originalRescueModel.PrimaryPart then
		warn("Original Rescue Model has no PrimaryPart")
		originalRescueModel:Destroy()
		return
	end

	-- ตั้งตำแหน่งตาม position parameter ที่ส่งมา หรือ fallback
	if position then
		print("Using provided spawn position:", position)
		originalRescueModel:PivotTo(CFrame.new(position))
	else
		-- Fallback: หา SpawnRescue หรือใกล้ผู้เล่น
		local spawnRescue = workspace:FindFirstChild("SpawnRescue")
		if spawnRescue then
			print("Found SpawnRescue, pivoting to:", spawnRescue.CFrame.Position)
			originalRescueModel:PivotTo(spawnRescue.CFrame)
		elseif player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			print("No SpawnRescue found, spawning near player")
			originalRescueModel:PivotTo(CFrame.new(player.Character.HumanoidRootPart.Position + Vector3.new(10, 5, 0)))
		else
			print("No spawn location found, using default position")
		end
	end

	playerOriginalRescue[player] = originalRescueModel
	print("Server: Spawned original rescue model for", player.Name)
end)

-- Control Original Rescue
controlOriginalRescueEvent.OnServerEvent:Connect(function(player, throttleInput, steerInput)
	local vehicle = playerOriginalRescue[player]
	if not vehicle then return end

	-- เก็บ input ล่าสุด
	vehicle:SetAttribute("ThrottleInput", throttleInput)
	vehicle:SetAttribute("SteerInput", steerInput)

	-- เริ่ม/อัพเดท connection สำหรับ original rescue
	local connectionKey = "original_" .. tostring(player.UserId)
	if originalRescueConnections[connectionKey] then
		return -- connection มีอยู่แล้ว
	end

	originalRescueConnections[connectionKey] = RunService.Heartbeat:Connect(function()
		local currentThrottle = vehicle:GetAttribute("ThrottleInput") or 0
		local currentSteer = vehicle:GetAttribute("SteerInput") or 0
		updateVehicleControl(player, vehicle, currentThrottle, currentSteer)
	end)
end)

-- Stop Original Rescue
stopOriginalRescueEvent.OnServerEvent:Connect(function(player)
	local vehicle = playerOriginalRescue[player]
	if vehicle then
		-- หยุดรถ
		vehicle:SetAttribute("ThrottleInput", 0)
		vehicle:SetAttribute("SteerInput", 0)
		updateVehicleControl(player, vehicle, 0, 0)

		-- หยุด connection
		local connectionKey = "original_" .. tostring(player.UserId)
		if originalRescueConnections[connectionKey] then
			originalRescueConnections[connectionKey]:Disconnect()
			originalRescueConnections[connectionKey] = nil
		end
	end
end)

-- Player left cleanup
Players.PlayerRemoving:Connect(function(player)
	if playerVehicles[player] then
		playerVehicles[player]:Destroy()
		playerVehicles[player] = nil
	end

	if playerOriginalRescue[player] then
		playerOriginalRescue[player]:Destroy()
		playerOriginalRescue[player] = nil
	end

	local connectionKey = tostring(player.UserId)
	if vehicleConnections[connectionKey] then
		vehicleConnections[connectionKey]:Disconnect()
		vehicleConnections[connectionKey] = nil
	end

	playerDrillTargets[player] = nil

	local originalConnectionKey = "original_" .. tostring(player.UserId)
	if originalRescueConnections[originalConnectionKey] then
		originalRescueConnections[originalConnectionKey]:Disconnect()
		originalRescueConnections[originalConnectionKey] = nil
	end

	local drillState = playerDrillStates[player]
	if drillState then
		drillState.isActive = false
		stopDrillSpin(drillState)
		playerDrillStates[player] = nil
	end
	drillDebounce[player] = nil
end)

print("RescueBotServer loaded")
