local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

-- สร้าง RemoteEvents สำหรับสื่อสารกับ client
local remoteEvents = Instance.new("Folder")
remoteEvents.Name = "RescueBotRemotes"
remoteEvents.Parent = ReplicatedStorage

local spawnCompanionEvent = Instance.new("RemoteEvent")
spawnCompanionEvent.Name = "SpawnCompanion"
spawnCompanionEvent.Parent = remoteEvents

local controlEvent = Instance.new("RemoteEvent")
controlEvent.Name = "ControlVehicle"
controlEvent.Parent = remoteEvents

local stopControlEvent = Instance.new("RemoteEvent")
stopControlEvent.Name = "StopControl"
stopControlEvent.Parent = remoteEvents

local hydraulicRemote = Instance.new("RemoteEvent")
hydraulicRemote.Name = "ActivateHydraulic"
hydraulicRemote.Parent = remoteEvents

local spawnOriginalRescueEvent = Instance.new("RemoteEvent")
spawnOriginalRescueEvent.Name = "SpawnOriginalRescue"
spawnOriginalRescueEvent.Parent = remoteEvents

local controlOriginalRescueEvent = Instance.new("RemoteEvent")
controlOriginalRescueEvent.Name = "ControlOriginalRescue"
controlOriginalRescueEvent.Parent = remoteEvents

local stopOriginalRescueEvent = Instance.new("RemoteEvent")
stopOriginalRescueEvent.Name = "StopOriginalRescue"
stopOriginalRescueEvent.Parent = remoteEvents

-- เก็บข้อมูลรถของแต่ละผู้เล่น
local playerVehicles = {}
local vehicleConnections = {}
local playerHydraulicArms = {}
local playerOriginalRescue = {}
local originalRescueConnections = {}
local hydraulicDebounce = {} -- ป้องกันการคลิกเร็วเกินไป

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

	-- Set network ownership
	primary:SetNetworkOwner(player)
	if wheelBL then wheelBL:SetNetworkOwner(player) end
	if wheelBR then wheelBR:SetNetworkOwner(player) end
	if wheelFL then wheelFL:SetNetworkOwner(player) end
	if wheelFR then wheelFR:SetNetworkOwner(player) end

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
	companion.Parent = workspace

	if companion.PrimaryPart and position then
		companion:SetPrimaryPartCFrame(CFrame.new(position, position + orientation))
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

-- ฟังก์ชันหา hydraulic arm ของผู้เล่น
local function findPlayerHydraulicArm(player)
	-- หาจาก Rescue model ที่ผู้เล่นกำลังใช้
	print("Searching in workspace for Rescue models...")
	for _, model in pairs(workspace:GetChildren()) do
		if model:IsA("Model") and model.Name == player.Name .. "_Rescue" then
			print("Found potential model:", model.Name)
			local hydroArm = model:FindFirstChild("hydoclicArm")
			if hydroArm then
				print("Found hydoclicArm in", model.Name)
				local shalf = hydroArm:FindFirstChild("Shalf") or hydroArm:FindFirstChild("Shelf")
				if shalf then
					print("Found Shalf/Shelf:", shalf.Name, "in", model.Name)
					local pc = shalf:FindFirstChild("PrismaticConstraint")
					if pc then
						print("SUCCESS: Found PrismaticConstraint in", model.Name)
						return pc
					else
						print("ERROR: No PrismaticConstraint in", shalf.Name)
					end
				else
					print("ERROR: No Shalf/Shelf in hydoclicArm of", model.Name)
				end
			else
				print("No hydoclicArm in", model.Name)
			end
		end
	end

	print("=== END DEBUG: No hydraulic arm found anywhere")
	return nil
end

-- Hydraulic arm control
hydraulicRemote.OnServerEvent:Connect(function(player)
	-- Debounce - ป้องกันการคลิกเร็วเกินไป
	local currentTime = tick()
	if hydraulicDebounce[player] and (currentTime - hydraulicDebounce[player]) < 0.5 then
		print("Hydraulic arm debounced for", player.Name)
		return
	end
	hydraulicDebounce[player] = currentTime

	local pc = findPlayerHydraulicArm(player)
	if not pc then
		print("No hydraulic arm found for", player.Name)
		return
	end

	pc.LowerLimit = -1
	pc.UpperLimit = 5

	-- สลับสถานะ - เริ่มต้นเป็นหุบ (up = true)
	if not playerHydraulicArms[player] then
		playerHydraulicArms[player] = {up = true} -- เริ่มต้นเป็นหุบ
	end

	playerHydraulicArms[player].up = not playerHydraulicArms[player].up
	local up = playerHydraulicArms[player].up

	-- กดครั้งแรก = หุบ (0), กดครั้งสอง = เลื่อนออก (-1)
	if up then
		-- หุบ - เลื่อนเข้าสุด
		pc.Speed = 100
		pc.TargetPosition = 0
		print(player.Name .. " hydraulic arm: RETRACTING to position 0")
	else
		-- เลื่อนออก
		pc.Speed = 100
		pc.TargetPosition = -10
		print(player.Name .. " hydraulic arm: EXTENDING to position -1")
	end

	print(player.Name .. " activated hydraulic arm - Position:", pc.TargetPosition, "Speed:", pc.Speed)
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

	-- ตั้งตำแหน่งที่ SpawnRescue หรือใกล้ผู้เล่น
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

	local originalConnectionKey = "original_" .. tostring(player.UserId)
	if originalRescueConnections[originalConnectionKey] then
		originalRescueConnections[originalConnectionKey]:Disconnect()
		originalRescueConnections[originalConnectionKey] = nil
	end

	-- ลบข้อมูล hydraulic arm และ debounce
	playerHydraulicArms[player] = nil
	hydraulicDebounce[player] = nil
end)

print("RescueBotServer loaded")