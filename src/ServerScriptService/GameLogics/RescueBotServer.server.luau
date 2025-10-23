local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

-- Import shared config
local DrillConfig = require(ReplicatedStorage.Modules.DrillConfig)
local EquipmentManager = require(ReplicatedStorage.Modules.EquipmentManager)
local CompanionEquipment = require(ReplicatedStorage.Modules.CompanionEquipment)
local profileService = require(ServerScriptService.SharedProfileService)

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
local drillCompleteRemote = getOrCreateRemote("DrillComplete")
local waitingSystemRemote = getOrCreateRemote("WaitingSystem")
local mapVotingRemote = getOrCreateRemote("MapVoting")
local spawnAssignmentRemote = getOrCreateRemote("SpawnAssignment")
local victimsReadyRemote = getOrCreateRemote("VictimsReady")
local gameTimerRemote = getOrCreateRemote("GameTimer")
local toggleDrillModeRemote = getOrCreateRemote("ToggleDrillMode")
local updateHPRemote = getOrCreateRemote("UpdateHP")
local updateBatteryRemote = getOrCreateRemote("UpdateBattery")
local debugModifyHPRemote = getOrCreateRemote("DebugModifyHP")
local drillEffectRemote = getOrCreateRemote("DrillEffect")
local deviceTypeRemote = getOrCreateRemote("DeviceType")
local teammateDownRemote = getOrCreateRemote("TeammateDown")
local _aftershockWarningRemote = getOrCreateRemote("AftershockWarning")

-- Track mobile players for physics optimization
local mobilePlayersList = {}

-- Import CompanionFollower and AftershockSystem after RemoteEvents are created
local CompanionFollower = require(script.Parent:WaitForChild("CompanionFollower"))
local AftershockSystem = require(script.Parent:WaitForChild("AftershockSystem"))

-- Initialize AftershockSystem to connect RemoteEvents
AftershockSystem.init()

-- Import VictimSpawner, GameConfig, GameSummary, and RescueBotHealth
local VictimSpawner = require(ReplicatedStorage.Modules.VictimSpawner)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local GameSummary = require(ReplicatedStorage.Modules.GameSummary)
local RescueBotHealth = require(ReplicatedStorage.Modules.RescueBotHealth)

-- Mission Result Handler (inline)
local missionResultRemote = getOrCreateRemote("MissionResult")

local function broadcastMissionResult(isSuccess)
	local soundId = isSuccess and "1844584719" or "1846942471"
	local message = isSuccess and "Mission Success" or "Mission Failed"

	print(string.format("[MissionResultHandler] Broadcasting %s - Sound: %s - isSuccess: %s", message, soundId, tostring(isSuccess)))

	-- Broadcast ให้ทุกคนในเกม
	missionResultRemote:FireAllClients(isSuccess, soundId, message)

	print("[MissionResultHandler] FireAllClients sent successfully")
end


local function toColor3(colorData)
	if typeof(colorData) == "Color3" then
		return colorData
	elseif typeof(colorData) == "table" then
		local r = colorData.r or colorData.R or colorData[1]
		local g = colorData.g or colorData.G or colorData[2]
		local b = colorData.b or colorData.B or colorData[3]
		if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
			r = math.clamp(r, 0, 1)
			g = math.clamp(g, 0, 1)
			b = math.clamp(b, 0, 1)
			return Color3.new(r, g, b)
		end
	end

	return nil
end

local function findPartByPath(model: Instance?, path: string): BasePart?
	if not model or not path or path == "" then
		return nil
	end

	local current: Instance? = model
	for _, segment in ipairs(string.split(path, "/")) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	if current and current:IsA("BasePart") and not current:IsA("Seat") and current.Name ~= "VehicleSeat" then
		return current
	end

	return nil
end

local function applyColorSchemeToModel(model: Model?, colorScheme: {{path: string, color: any}}?)
	if not model or not colorScheme then
		return
	end

	for _, entry in ipairs(colorScheme) do
		if typeof(entry) == "table" then
			local path = entry.path
			local color = toColor3(entry.color)
			if typeof(path) == "string" and color then
				local part = findPartByPath(model, path)
				if part then
					part.Color = color
				end
			end
		end
	end
end

local function getPlayerColorScheme(player: Player)
	local profile = profileService:GetProfile(player)
	return profile and profile.bot and profile.bot.colors or nil
end

local function getEquippedItemId(entry): string?
	if typeof(entry) == "string" then
		return entry
	elseif typeof(entry) == "table" then
		return entry.id :: string?
	end
	return nil
end

-- ปิดการนั่งใน VehicleSeat ทั้งหมด
local function disableVehicleSeats()
	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("VehicleSeat") then
			descendant.Disabled = true
			print("Disabled VehicleSeat:", descendant:GetFullName())
		end
	end
end

-- เรียกใช้ตอนเริ่มเกม
disableVehicleSeats()

-- ตรวจสอบ VehicleSeat ใหม่ที่ถูกสร้างขึ้นมา
workspace.DescendantAdded:Connect(function(descendant)
	if descendant:IsA("VehicleSeat") then
		descendant.Disabled = true
		print("Auto-disabled new VehicleSeat:", descendant:GetFullName())
	end
end)

-- เก็บข้อมูลรถของแต่ละผู้เล่น
local playerVehicles = {}
local vehicleConnections = {}
local playerDrillStates = {}
local playerOriginalRescue = {}
local playerDrillTargets = {}
local originalRescueConnections = {}
local drillDebounce = {}
local companionFollowers = {}
local rescueBotHealthInstances = {} -- เก็บ RescueBotHealth instances
local activeGamePlayers = {}

AftershockSystem.setActivePlayersProvider(function()
	local playersInGame = {}
	for player in pairs(activeGamePlayers) do
		if player and player.Parent == Players then
			table.insert(playersInGame, player)
		end
	end
	return playersInGame
end)

AftershockSystem.setRescueModelProvider(function(player)
	return playerOriginalRescue[player]
end)

AftershockSystem.setDamageHandler(function(player, damage, damageType)
	local healthInstance = rescueBotHealthInstances[player]
	if healthInstance then
		healthInstance:TakeDamage(damage, damageType or "Aftershock Rockfall")
	end
end)

-- Server-side Waiting System variables
local waitingPlayers = {}
local isGamePlaying = false
local lobbyCountdownThread = nil
local lobbyCountdownTime = 0
local isCountingDown = false

local function foldDrillArm(model: Model?, playerName: string, context: string)
	if not model then
		return
	end

	task.spawn(function()
		task.wait(0.5)

		local drillArm = model:FindFirstChild("DrillArm")
		if not drillArm then
			warn(string.format("[RescueBotServer][%s] DrillArm not found for %s", context, playerName))
			return
		end

		local hingeConstraint: HingeConstraint? = nil
		local tube2 = drillArm:FindFirstChild("Tube2")
		if tube2 then
			hingeConstraint = tube2:FindFirstChildWhichIsA("HingeConstraint")
		end

		if not hingeConstraint then
			hingeConstraint = drillArm:FindFirstChildWhichIsA("HingeConstraint", true)
		end

		if not hingeConstraint then
			warn(string.format("[RescueBotServer][%s] HingeConstraint not found in DrillArm for %s", context, playerName))
			return
		end

		hingeConstraint.LimitsEnabled = true
		hingeConstraint.ActuatorType = Enum.ActuatorType.Servo
		hingeConstraint.ServoMaxTorque = 1000000
		hingeConstraint.AngularResponsiveness = 50
		hingeConstraint.AngularSpeed = 1
		hingeConstraint.TargetAngle = 180
	end)
end

local function getBasePart(instance: Instance?): BasePart?
	if not instance then
		return nil
	end

	if instance:IsA("BasePart") then
		return instance
	end

	if instance:IsA("Model") then
		local model = instance :: Model
		if model.PrimaryPart then
			return model.PrimaryPart
		end
		return model:FindFirstChildWhichIsA("BasePart", true)
	end

	return instance:FindFirstChildWhichIsA("BasePart", true)
end

local function handleRescueBotTimeout(player)
	if not player then
		return
	end

	if isGamePlaying then
		isGamePlaying = false
		waitingSystemRemote:FireAllClients("gameEnded")
	end

	local originalCallback = GameSummary.onSummaryClosed

	GameSummary.onSummaryClosed = function(closedPlayer)
		if closedPlayer == player then
			GameSummary.resetToLobby(player)
			GameSummary.onSummaryClosed = originalCallback
		elseif originalCallback then
			originalCallback(closedPlayer)
		end
	end

	GameSummary.showSummary(player)
end

local function isAuthorizedDebugPlayer(player)
	if not player then
		return false
	end

	local success, result = pcall(GameConfig.isDebugUser, player.UserId)
	if success then
		return result == true
	end

	return false
end

local function handleDebugModifyHP(player, action, value)
	if not isAuthorizedDebugPlayer(player) then
		warn("[DebugModifyHP] Unauthorized attempt", player and player.Name or "Unknown")
		return
	end

	local healthInstance = rescueBotHealthInstances[player]
	if not healthInstance then
		warn("[DebugModifyHP] No RescueBotHealth for player", player.Name)
		return
	end

	local currentHP, maxHP = healthInstance:GetHP()
	local actionKind = typeof(action) == "string" and string.lower(action) or ""

	if actionKind == "kill" then
		if currentHP > 0 then
			healthInstance:TakeDamage(currentHP, "DebugKill")
		end
	elseif actionKind == "damage" then
		local damageAmount = tonumber(value)
		if damageAmount and damageAmount > 0 then
			healthInstance:TakeDamage(damageAmount, "DebugDamage")
		end
	elseif actionKind == "set" then
		local targetHP = tonumber(value)
		if targetHP then
			targetHP = math.clamp(targetHP, 0, maxHP)
			if targetHP < currentHP then
				healthInstance:TakeDamage(currentHP - targetHP, "DebugSetHP")
			elseif targetHP > currentHP then
				healthInstance:Heal(targetHP - currentHP)
			end
		end
	end
end

debugModifyHPRemote.OnServerEvent:Connect(handleDebugModifyHP)

-- Server-side Map Voting variables
local currentVotes = {} -- {mapName = count}
local playerVotes = {} -- {player = mapName}
local playerSpawnAssignments = {} -- {playerName = spawnPoint} - spawn points ที่ไม่ซ้ำกัน

local function sign(x)
	if x > 0 then return 1 elseif x < 0 then return -1 else return 0 end
end

-- ฟังก์ชันควบคุมรถ
local function updateVehicleControl(player, vehicle, throttleInput, steerInput)
	if not vehicle or not vehicle.PrimaryPart then
		if throttleInput ~= 0 or steerInput ~= 0 then
			-- updateVehicleControl failed - no vehicle or PrimaryPart
		end
		return
	end

	-- หา vehicle parts
	local primary = vehicle.PrimaryPart
	local attachmentFL = primary:FindFirstChild("AttachmentFL")
	local attachmentFR = primary:FindFirstChild("AttachmentFR")

	local wheelBL = vehicle:FindFirstChild("Wheel_BL")
	local wheelBR = vehicle:FindFirstChild("Wheel_BR")
	local wheelFL = vehicle:FindFirstChild("Wheel_FL")
	local wheelFR = vehicle:FindFirstChild("Wheel_FR")

	if not (wheelBL and wheelBR) then
		if throttleInput ~= 0 or steerInput ~= 0 then
			-- Missing back wheels
		end
		return
	end

	local cylindricalBL = wheelBL:FindFirstChildOfClass("CylindricalConstraint")
	local cylindricalBR = wheelBR:FindFirstChildOfClass("CylindricalConstraint")
	local cylindricalFL = wheelFL and wheelFL:FindFirstChildOfClass("CylindricalConstraint")
	local cylindricalFR = wheelFR and wheelFR:FindFirstChildOfClass("CylindricalConstraint")

	if not (cylindricalBL and cylindricalBR) then
		if throttleInput ~= 0 or steerInput ~= 0 then
			-- Missing cylindrical constraints
		end
		return
	end

	-- Set network ownership (skip while anchored to avoid errors)
	if primary.Anchored then
		-- ไม่เรียก SetNetworkOwner เพราะ part ยัง anchored อยู่
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
		-- ตั้ง network owner เฉพาะเมื่อ part ไม่ anchored
		pcall(function()
			primary:SetNetworkOwner(player)
		end)
		if wheelBL and not wheelBL.Anchored then
			pcall(function() wheelBL:SetNetworkOwner(player) end)
		end
		if wheelBR and not wheelBR.Anchored then
			pcall(function() wheelBR:SetNetworkOwner(player) end)
		end
		if wheelFL and not wheelFL.Anchored then
			pcall(function() wheelFL:SetNetworkOwner(player) end)
		end
		if wheelFR and not wheelFR.Anchored then
			pcall(function() wheelFR:SetNetworkOwner(player) end)
		end
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

	-- Debug torque application
	if throttleInput ~= 0 or steerInput ~= 0 then
		-- Applying vehicle controls
	end

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
		playerVehicles[player] = nil
	end

	-- ล้าง vehicle connections เก่า
	local connectionKey = tostring(player.UserId)
	if vehicleConnections[connectionKey] then
		vehicleConnections[connectionKey]:Disconnect()
		vehicleConnections[connectionKey] = nil
	end

	-- หยุด companion follower เก่า
	if companionFollowers[player] then
		companionFollowers[player].running = false
		companionFollowers[player] = nil
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

	local profile = profileService:GetProfile(player)
	local equippedItems = profile and profile.bot and profile.bot.inventory and profile.bot.inventory.equipped or {}
	local colorScheme = profile and profile.bot and profile.bot.colors
	if colorScheme and next(colorScheme) then
		local colorArray = {}
		for path, color in pairs(colorScheme) do
			table.insert(colorArray, {path = path, color = color})
		end
		local entries = {}
		for _, entry in ipairs(colorArray) do
			entries[#entries + 1] = string.format("%s=(%.2f,%.2f,%.2f)", entry.path, entry.color.r or 0, entry.color.g or 0, entry.color.b or 0)
		end
		print("[RescueBotServer] Applying companion color scheme: { " .. table.concat(entries, ", ") .. " }")
		applyColorSchemeToModel(companion, colorArray)
	else
		print("[RescueBotServer] No companion color scheme for", player.Name)
	end
	-- ซ่อน DrillArm parts ก่อน (จะถูกแสดงโดย CompanionEquipment.apply ถ้า equipped)
	local tube1 = companion:FindFirstChild("Tube1")
	local drillArmModel = companion:FindFirstChild("DrillArm")
	for _, part in ipairs({tube1, drillArmModel}) do
		if part and part:IsA("BasePart") then
			part.Transparency = 1
		elseif part and part:IsA("Model") then
			for _, descendant in ipairs(part:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Transparency = 1
				end
			end
		end
	end

	-- ซ่อน Camera part ตั้งแต่แรก (เหมือน DrillArm)
	local cameraPart = companion:FindFirstChild("Camera")
	if cameraPart and cameraPart:IsA("BasePart") then
		cameraPart.Transparency = 1
		print("[RescueBotServer] Hidden Camera part in companion for", player.Name)
	else
		print("[RescueBotServer] No Camera part found in companion for", player.Name)
	end

	-- Apply equipped items (จะแสดง DrillArm ถ้ามีใน equippedItems)
	CompanionEquipment.apply(companion, equippedItems)
	foldDrillArm(companion, player.Name, "Companion")

	local follower = CompanionFollower.start(companion)
	companionFollowers[player] = follower

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
	local rootParts = {} -- เก็บ RootPart ที่เจอ

	for _, candidate in ipairs(nearbyParts) do
		local isOwn = state.model and state.model:IsAncestorOf(candidate)

		-- ตรวจสอบว่าเป็นชิ้นส่วนร่างกายหรือไม่
		local bodyParts = {
			"LeftFoot", "LeftHand", "LeftLowerArm", "LeftLowerLeg", "LeftUpperArm", "LeftUpperLeg",
			"LowerTorso", "RightFoot", "RightHand", "RightLowerArm", "RightLowerLeg",
			"RightUpperArm", "RightUpperLeg", "UpperTorso", "Head", "HumanoidRootPart"
		}
		local isBodyPart = false
		for _, bodyPartName in ipairs(bodyParts) do
			if candidate.Name == bodyPartName then
				isBodyPart = true
				break
			end
		end

		-- มองหา part ทั้งหมดที่สามารถเจาะได้
		if candidate ~= head and not isOwn and not isBodyPart and candidate:IsA("BasePart") then
			-- ตรวจสอบว่า part อยู่ใน Obstacles folder หรือไม่
			local isInObstacles = false
			local ancestor = candidate.Parent
			while ancestor and ancestor ~= workspace do
				if ancestor.Name == "Obstacles" then
					isInObstacles = true
					break
				end
				ancestor = ancestor.Parent
			end

			-- ยอมรับทุก part ใน Obstacles
			if isInObstacles then
				local distance = (candidate.Position - head.Position).Magnitude
				-- Priority ตามระยะใกล้ (ใกล้กว่า = priority สูงกว่า)
				local priority = 100 - distance
				table.insert(rootParts, {
					part = candidate,
					distance = distance,
					priority = priority
				})
			end
		end
	end

	-- เรียงตาม priority แล้วถึงระยะใกล้
	if #rootParts > 0 then
		table.sort(rootParts, function(a, b)
			if a.priority ~= b.priority then
				return a.priority > b.priority
			end
			return a.distance < b.distance
		end)

		local selected = rootParts[1]

		-- ส่งกลับ part ที่เลือก
		return {
			part = selected.part,
			distance = selected.distance
		}
	end

	return nil
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
	end

	current.clicks += 1
	local progress = math.clamp(current.clicks / current.required, 0, 1)

	if progress >= 1 then
		-- เจาะเสร็จแล้ว - Unanchor part (ไม่ต้องทำลาย weld)
		local partToEject = current.part

		if partToEject and partToEject.Parent then
			print("Drilling complete - Unanchoring part:", partToEject.Name)

			-- ยกเลิก anchoring และเปิด CanCollide
			partToEject.Anchored = false
			partToEject.CanCollide = true

			-- ปรับให้มีมวลน้อย
			pcall(function()
				partToEject.CustomPhysicalProperties = PhysicalProperties.new(
					0.3,  -- Density (มวลน้อยพอที่จะตกลงมา แต่ไม่หนักเกินไป)
					0.5,  -- Friction (เพิ่มเพื่อไม่ให้ลื่นมาก)
					0.2,  -- Elasticity (ลดเพื่อไม่ให้เด้งมาก)
					1,    -- FrictionWeight
					1     -- ElasticityWeight
				)
			end)

			-- ใช้ AssemblyLinearVelocity แทน BodyVelocity เพื่อไม่ต่อต้านแรงโน้มถ่วง
			-- คำนวณทิศทางการกระเด็น (สุ่มทิศทางขึ้นและออกจากจุดศูนย์กลาง)
			local randomDirection = Vector3.new(
				math.random(-100, 100) / 100,  -- X: -1 ถึง 1
				math.random(50, 150) / 100,    -- Y: 0.5 ถึง 1.5 (ขึ้นบน)
				math.random(-100, 100) / 100   -- Z: -1 ถึง 1
			).Unit

			local ejectForce = 25 -- แรงกระเด็น
			partToEject.AssemblyLinearVelocity = randomDirection * ejectForce

			-- ให้มีการหมุนสุ่มเล็กน้อย
			partToEject.AssemblyAngularVelocity = Vector3.new(
				math.random(-5, 5),
				math.random(-5, 5),
				math.random(-5, 5)
			)

			-- เช็คว่าเป็น root part (parent Model) หรือไม่
			-- ถ้า parent เป็น Model หรือ Folder = root part ให้ debris
			-- ถ้า parent เป็น BasePart = children part ข้าม debris
			local isRootPart = false
			if partToEject.Parent then
				if partToEject.Parent:IsA("Model") or partToEject.Parent:IsA("Folder") then
					isRootPart = true
				end
			end

			if isRootPart then
				-- ใช้ Debris Service เพื่อลบ root part หลังจาก 10 วินาที
				local Debris = game:GetService("Debris")
				Debris:AddItem(partToEject, 10)
				print("Debris added to root part:", partToEject.Name)
			else
				print("Skipped debris for children part:", partToEject.Name)
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

	-- เช็คว่า HingeConstraint ถูก Enabled หรือไม่ ถ้าไม่ให้ return ทันที
	if not hinge.Enabled then
		warn("[Drill] HingeConstraint is disabled - cannot drill")
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
			state.originalAnchored = head.Anchored
			state.originalCanCollide = head.CanCollide
		end
		-- ตั้งค่า Head ให้หมุนได้แต่ไม่กระเด็น
		head.Anchored = false
		head.Massless = true
		head.CanCollide = false -- ปิด collision เพื่อไม่ให้กระเด็นตอนโดนหิน
		pcall(function()
			head.CustomPhysicalProperties = PhysicalProperties.new(0.1, 0.3, 0.3)
		end)
		-- Reset velocity เพื่อไม่ให้มีแรงเหลือค้าง
		head.AssemblyLinearVelocity = Vector3.zero
		head.AssemblyAngularVelocity = Vector3.zero
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

			-- เก็บและป้องกัน DrillArm parts ทั้งหมดจากการกระเด็น
			if drillArm then
				state.drillArmParts = {}
				-- ป้องกันทุก part ใน DrillArm (ยกเว้น Head ที่จัดการแล้ว)
				for _, part in ipairs(drillArm:GetDescendants()) do
					if part:IsA("BasePart") and part ~= state.head then
						table.insert(state.drillArmParts, {
							part = part,
							wasCanCollide = part.CanCollide,
						})
						-- ปิด collision และ reset velocity
						part.CanCollide = false
						part.AssemblyLinearVelocity = Vector3.zero
						part.AssemblyAngularVelocity = Vector3.zero
					end
				end
				print(string.format("[Drill] Protected %d DrillArm parts from collision", #state.drillArmParts))
			end

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
		hinge.AngularVelocity = 100
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
			-- หยุดการหมุนโดยตั้งความเร็วและแรงบิดเป็น 0 (ActuatorType ยังคงเป็น Motor)
			hinge.AngularVelocity = 0
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
		-- คืนค่า Anchored เดิม
		if state.originalAnchored ~= nil then
			head.Anchored = state.originalAnchored
		end
		head.Massless = state.originalMassless or false
		-- คืนค่า CanCollide เดิม
		if state.originalCanCollide ~= nil then
			head.CanCollide = state.originalCanCollide
		end
		pcall(function()
			head.CustomPhysicalProperties = state.originalPhysicalProperties
		end)
		-- Reset velocity ก่อนหยุด
		head.AssemblyLinearVelocity = Vector3.zero
		head.AssemblyAngularVelocity = Vector3.zero
	end
	state.head = nil
	state.originalMassless = nil
	state.originalPhysicalProperties = nil
	state.originalAnchored = nil
	state.originalCanCollide = nil

	-- คืนค่า DrillArm parts CanCollide เดิม
	if state.drillArmParts then
		for _, info in ipairs(state.drillArmParts) do
			local part = info.part
			if part and part.Parent then
				part.CanCollide = info.wasCanCollide or false
				part.AssemblyLinearVelocity = Vector3.zero
				part.AssemblyAngularVelocity = Vector3.zero
			end
		end
		print("[Drill] Restored DrillArm parts collision")
	end
	state.drillArmParts = nil

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

	-- Disable Motor6D และ Enable HingeConstraint เพื่อให้หมุนได้
	local drillArm = rescueModel:FindFirstChild("DrillArm")
	if drillArm then
		-- Disable Motor6D และ Enable HingeConstraint ใน Head
		local head = drillArm:FindFirstChild("Head")
		local headPart = getBasePart(head)
		if headPart then
			for _, child in ipairs(headPart:GetChildren()) do
				if child:IsA("Motor6D") then
					child.Enabled = false
					print("[Server] Disabled Head Motor6D:", child.Name, "for", player.Name)
				end
			end
		end

		-- Enable HingeConstraint เพื่อให้หมุนได้
		if head then
			local headHingeConstraint = head:FindFirstChild("HingeConstraint")
			if headHingeConstraint then
				headHingeConstraint.Enabled = true
				print("[Server] Enabled Head HingeConstraint for drilling:", player.Name)
			end
		end
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
	-- หยุดสว่านก่อน spawn รถใหม่
	local drillState = playerDrillStates[player]
	if drillState then
		drillState.isActive = false
		stopDrillSpin(drillState)
		playerDrillStates[player] = nil
		print("Stopped drill before spawning new rescue vehicle for", player.Name)
	end

	-- ลบ RescueCompanion ก่อน spawn Rescue หลัก
	local companionName = player.Name .. "_RescueCompanion"
	local companionModel = workspace:FindFirstChild(companionName)
	if companionModel then
		companionModel:Destroy()
		print("Destroyed RescueCompanion before spawning Rescue for", player.Name)
	end

	-- ลบจาก playerVehicles ด้วย (ถ้ามี companion อยู่)
	if playerVehicles[player] then
		playerVehicles[player]:Destroy()
		playerVehicles[player] = nil
		print("Cleared companion from playerVehicles for", player.Name)
	end

	-- หยุด companion follower
	if companionFollowers[player] then
		companionFollowers[player].running = false
		companionFollowers[player] = nil
		print("Stopped companion follower for", player.Name)
	end

	-- ลบ original rescue model เก่า (ถ้ามี)
	if playerOriginalRescue[player] then
		playerOriginalRescue[player]:Destroy()
		playerOriginalRescue[player] = nil
	end

	-- ทำลาย RescueBotHealth instance เก่า
	if rescueBotHealthInstances[player] then
		rescueBotHealthInstances[player]:Destroy()
		rescueBotHealthInstances[player] = nil
	end

	-- ล้าง original rescue connections เก่า
	local connectionKey = tostring(player.UserId)
	if originalRescueConnections[connectionKey] then
		originalRescueConnections[connectionKey]:Disconnect()
		originalRescueConnections[connectionKey] = nil
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

	local rescueColorScheme = getPlayerColorScheme(player)
	if rescueColorScheme and next(rescueColorScheme) then
		local colorArray = {}
		for path, color in pairs(rescueColorScheme) do
			table.insert(colorArray, {path = path, color = color})
		end
		local entries = {}
		for _, entry in ipairs(colorArray) do
			entries[#entries + 1] = string.format("%s=(%.2f,%.2f,%.2f)", entry.path, entry.color.r or 0, entry.color.g or 0, entry.color.b or 0)
		end
		print("[RescueBotServer] Applying rescue color scheme: { " .. table.concat(entries, ", ") .. " }")
		applyColorSchemeToModel(originalRescueModel, colorArray)
	else
		print("[RescueBotServer] No rescue color scheme for", player.Name)
	end

	playerOriginalRescue[player] = originalRescueModel

	-- ซ่อน DrillArm parts ตั้งแต่แรก
	local tube1 = originalRescueModel:FindFirstChild("Tube1")
	local drillArmModel = originalRescueModel:FindFirstChild("DrillArm")
	for _, part in ipairs({tube1, drillArmModel}) do
		if part and part:IsA("BasePart") then
			part.Transparency = 1
		elseif part and part:IsA("Model") then
			for _, descendant in ipairs(part:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Transparency = 1
				end
			end
		end
	end

	-- ซ่อน Camera part ตั้งแต่แรก (เหมือน DrillArm)
	local cameraPart = originalRescueModel:FindFirstChild("Camera")
	if cameraPart and cameraPart:IsA("BasePart") then
		cameraPart.Transparency = 1
		print("[RescueBotServer] Hidden Camera part in", player.Name)
	else
		print("[RescueBotServer] No Camera part found in", player.Name)
	end

	-- โหลด equipped items จาก profile ก่อน
	local profile = profileService:GetProfile(player)
	if profile then
		if profile.bot and profile.bot.inventory then
			local equippedItems = profile.bot.inventory.equipped
			if equippedItems and #equippedItems > 0 then
				EquipmentManager.setTargetBot(originalRescueModel)
				-- Clear equipment เก่าก่อน (ซ่อน DrillArm และ Camera)
				EquipmentManager.clearAll()
				-- Equip items ใหม่ทั้งหมด
				for _, equippedItem in ipairs(equippedItems) do
					local itemId = getEquippedItemId(equippedItem)
					if itemId then
						local colorOverride = typeof(equippedItem) == "table" and equippedItem.color or nil
						local success = EquipmentManager.equipItem(itemId, colorOverride)
						if success then
							print("[RescueBotServer] Equipped", itemId, "for", player.Name)
						else
							warn("[RescueBotServer] Failed to equip", itemId, "for", player.Name)
						end
					end
				end
			else
				print("[RescueBotServer] No equipped items found for", player.Name)
			end
		else
			print("[RescueBotServer] No inventory data for", player.Name)
		end
	else
		warn("[RescueBotServer] Profile not found for", player.Name)
	end

	-- สร้าง RescueBotHealth instance หลังจากติดตั้ง Equipment แล้ว
	local healthInstance = RescueBotHealth.new(originalRescueModel, {
		onTimeout = handleRescueBotTimeout,
	})
	rescueBotHealthInstances[player] = healthInstance
	print("[RescueBotServer] Created RescueBotHealth for", player.Name)

	foldDrillArm(originalRescueModel, player.Name, "OriginalRescue")

	print("Server: Spawned original rescue model for", player.Name)
end)

-- Control Original Rescue
controlOriginalRescueEvent.OnServerEvent:Connect(function(player, throttleInput, steerInput)
	local vehicle = playerOriginalRescue[player]
	if not vehicle then
		-- No original rescue vehicle found
		return
	end

	-- Controls received from client

	-- เก็บ input ล่าสุด
	vehicle:SetAttribute("ThrottleInput", throttleInput)
	vehicle:SetAttribute("SteerInput", steerInput)

	-- เริ่ม/อัพเดท connection สำหรับ original rescue
	local connectionKey = "original_" .. tostring(player.UserId)

	-- ลบ connection เก่าก่อน (กรณีที่ vehicle เปลี่ยนแปลง)
	if originalRescueConnections[connectionKey] then
		originalRescueConnections[connectionKey]:Disconnect()
		originalRescueConnections[connectionKey] = nil
	end
	originalRescueConnections[connectionKey] = RunService.Heartbeat:Connect(function()
		-- ตรวจสอบว่า vehicle ยังมีอยู่หรือไม่
		if not vehicle or not vehicle.Parent then
			-- Vehicle destroyed, disconnecting heartbeat
			if originalRescueConnections[connectionKey] then
				originalRescueConnections[connectionKey]:Disconnect()
				originalRescueConnections[connectionKey] = nil
			end
			return
		end

		local currentThrottle = vehicle:GetAttribute("ThrottleInput") or 0
		local currentSteer = vehicle:GetAttribute("SteerInput") or 0

		-- Debug heartbeat - only when there's input
		if currentThrottle ~= 0 or currentSteer ~= 0 then
			-- Heartbeat updating vehicle controls
		end

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

-- Toggle Drill Mode (Q key)
toggleDrillModeRemote.OnServerEvent:Connect(function(player, isActive)
	local rescueModelName = player.Name .. "_Rescue"
	local rescueModel = workspace:FindFirstChild(rescueModelName)

	if not rescueModel then
		rescueModelName = player.Name .. "_RescueCompanion"
		rescueModel = workspace:FindFirstChild(rescueModelName)
		if not rescueModel then
			warn("Rescue model not found for", player.Name)
			return
		end
	end

	local drillArm = rescueModel:FindFirstChild("DrillArm")
	if not drillArm then
		warn("DrillArm not found in", rescueModelName)
		return
	end

	local tube2 = drillArm:FindFirstChild("Tube2")
	local tube2Part = getBasePart(tube2)
	local head = drillArm:FindFirstChild("Head")
	local headPart = getBasePart(head)

	local weldName = "HeadTube2Weld"
	local motorName = "HeadTube2Motor6D"

	if headPart and tube2Part then
		if isActive then
			-- ควบคุม Tube2.HingeConstraint
			if tube2 then
				local hingeConstraint = tube2:FindFirstChild("HingeConstraint")
				if hingeConstraint then
					-- เปิดโหมดเจาะ: TargetAngle = 0
					hingeConstraint.TargetAngle = 0
					print("[Server] Drill mode activated for", player.Name, "- TargetAngle = 0")
				end
			end
		else
			if headPart then
				for _, child in ipairs(headPart:GetChildren()) do
					if child:IsA("Motor6D") then
						child.Enabled = true
						print("[Server] Re-enabled Head Motor6D:", child.Name, "for", player.Name)
					end
				end
			end
			-- พับเก็บ: หยุด Motor และ Disable HingeConstraint ก่อน
			if head then
				local headHingeConstraint = head:FindFirstChild("HingeConstraint")
				if headHingeConstraint then
					-- หยุดการหมุนและ Disable ทันที
					headHingeConstraint.AngularVelocity = 0
					headHingeConstraint.MotorMaxTorque = 0
					headHingeConstraint.Enabled = false
					print("[Server] Stopped and Disabled Head Motor for fold-up", player.Name)
				end
			end

			-- รอให้หยุดสนิท
			task.wait(0.1)

			-- ปิดโหมดเจาะ: TargetAngle = 180 (พับเก็บ)
			if tube2 then
				local hingeConstraint = tube2:FindFirstChild("HingeConstraint")
				if hingeConstraint then
					hingeConstraint.TargetAngle = 180
					print("[Server] Drill mode deactivated for", player.Name, "- TargetAngle = 180")
				end
			end
			print("[Server] Removed Head-Tube2 Motor6D for", player.Name)
		end
	end
end)

-- Player left cleanup
Players.PlayerRemoving:Connect(function(player)
	activeGamePlayers[player] = nil
	if next(activeGamePlayers) == nil then
		AftershockSystem.stop()
	end

	if playerVehicles[player] then
		playerVehicles[player]:Destroy()
		playerVehicles[player] = nil
	end

	if playerOriginalRescue[player] then
		playerOriginalRescue[player]:Destroy()
		playerOriginalRescue[player] = nil
	end

	-- หยุด companion follower
	if companionFollowers[player] then
		companionFollowers[player].running = false
		companionFollowers[player] = nil
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

	-- ลบผู้เล่นจาก waiting list
	for i = #waitingPlayers, 1, -1 do
		if waitingPlayers[i] == player then
			table.remove(waitingPlayers, i)
			print("Removed", player.Name, "from waiting list. Total waiting:", #waitingPlayers)
			-- แจ้ง clients ทั้งหมด
			waitingSystemRemote:FireAllClients("updateCount", #waitingPlayers, GameConfig.getMaxPlayers())
			break
		end
	end
end)

-- รับข้อมูลจาก Client เมื่อเจาะเสร็จ แล้วจัดการ physics ฝั่ง Server
local function isBreakablePart(instance)
	return instance:IsA("BasePart") or instance:IsA("MeshPart")
end

-- Physics properties สำหรับ debris (ปรับให้ตกเร็วขึ้น ไม่ลอย)
local LIGHT_DEBRIS_PROPERTIES = PhysicalProperties.new(
	0.7,   -- Density: เพิ่มจาก 0.05 เป็น 0.7 เพื่อให้หนักพอที่จะตก
	0.3,   -- Friction: เพิ่มจาก 0.05 เป็น 0.3 เพื่อหยุดเร็วขึ้น
	0.1,   -- Elasticity: ลดจาก 0.3 เป็น 0.1 เพื่อลดการเด้ง
	1.0,   -- FrictionWeight
	1.0    -- ElasticityWeight
)

-- ตัวแปรติดตามจำนวน debris ที่ active (สำหรับ mobile optimization)
local activeDebrisCount = 0
local MAX_MOBILE_DEBRIS = GameConfig.MOBILE_PERFORMANCE.MAX_ACTIVE_DEBRIS

-- ฟังก์ชัน fade debris ค่อยๆหายไป (ปรับแต่งสำหรับ mobile)
local function fadeDebris(debrisPart, delayTime, fadeDuration, isMobileOptimized)
	task.spawn(function()
		-- ถ้าเป็น mobile optimization ให้หยุด physics ก่อน fade
		if isMobileOptimized then
			task.wait(GameConfig.MOBILE_PERFORMANCE.DEBRIS_PHYSICS_TIMEOUT)

			if debrisPart and debrisPart.Parent then
				-- หยุด physics แต่ยังไม่ลบ
				debrisPart.Anchored = true
				debrisPart.CanCollide = false
				debrisPart.AssemblyLinearVelocity = Vector3.zero
				debrisPart.AssemblyAngularVelocity = Vector3.zero
			end
		end

		-- รอก่อน fade (ใช้ค่าจาก config สำหรับ mobile)
		local actualDelay = isMobileOptimized and GameConfig.MOBILE_PERFORMANCE.DEBRIS_LIFETIME or (delayTime or 3)
		task.wait(actualDelay)

		if not debrisPart or not debrisPart.Parent then
			if isMobileOptimized then
				activeDebrisCount = math.max(0, activeDebrisCount - 1)
			end
			return
		end

		-- เก็บ Transparency เดิม
		local originalTransparency = debrisPart.Transparency
		local fadeTime = fadeDuration or 2 -- fade ใช้เวลา 2 วินาที
		local steps = isMobileOptimized and 10 or 20 -- ลดขั้นตอนบน mobile
		local stepTime = fadeTime / steps
		local transparencyIncrement = (1 - originalTransparency) / steps

		-- ค่อยๆเพิ่ม Transparency
		for i = 1, steps do
			if not debrisPart or not debrisPart.Parent then
				break
			end
			debrisPart.Transparency = math.min(1, debrisPart.Transparency + transparencyIncrement)
			task.wait(stepTime)
		end

		-- ลบ part เมื่อ fade เสร็จ
		if debrisPart and debrisPart.Parent then
			debrisPart:Destroy()
		end

		-- ลดจำนวน active debris
		if isMobileOptimized then
			activeDebrisCount = math.max(0, activeDebrisCount - 1)
		end
	end)
end

drillCompleteRemote.OnServerEvent:Connect(function(player, partData, connectedPartsData, rescuePosition, ejectStrength)
	print("Server received drill complete from", player.Name, "for part:", partData.Name, "Strength:", ejectStrength or "normal")

	-- Check if any mobile players are in the game for optimization
	local hasMobilePlayers = false
	for _, isMobile in pairs(mobilePlayersList) do
		if isMobile then
			hasMobilePlayers = true
			break
		end
	end

	-- หา part จริงใน workspace (ใช้ instance จาก client ถ้ามี)
	local part = nil
	if partData.Instance and partData.Instance:IsA("BasePart") and partData.Instance:IsDescendantOf(workspace) then
		part = partData.Instance
	else
		part = workspace:FindFirstChild(partData.Name, true)
	end

	if not part or (not part:IsA("BasePart") and not part:IsA("MeshPart")) then
		warn("Part not found or invalid:", partData.Name)
		return
	end

	local directChildren = {}
	local parentContainer = part.Parent
	for _, child in ipairs(part:GetChildren()) do
		if isBreakablePart(child) and child.Name ~= "Root" then
			table.insert(directChildren, child)
		end
	end

	if #directChildren > 0 then
		print(string.format("Breakable hierarchy detected - Main: %s | Nested parts: %d", part.Name, #directChildren))

		-- Reduce debris count for mobile optimization (keep only 50% of parts)
		if hasMobilePlayers and #directChildren > 3 then
			local reduceMultiplier = GameConfig.MOBILE_PERFORMANCE.REDUCE_DEBRIS_COUNT
			local reducedCount = math.max(3, math.floor(#directChildren * reduceMultiplier))
			local tempChildren = {}
			for i = 1, reducedCount do
				table.insert(tempChildren, directChildren[i])
			end
			-- Destroy the rest immediately
			for i = reducedCount + 1, #directChildren do
				directChildren[i]:Destroy()
			end
			directChildren = tempChildren
			print(string.format("[Mobile Optimization] Reduced debris from %d to %d parts", #directChildren + (#tempChildren - reducedCount), #directChildren))
		end

		-- Check debris limit สำหรับ mobile (ถ้าเกินให้ลบของเก่าทิ้งก่อน)
		if hasMobilePlayers and activeDebrisCount >= MAX_MOBILE_DEBRIS then
			print(string.format("[Mobile Optimization] Debris limit reached (%d/%d) - skipping some debris", activeDebrisCount, MAX_MOBILE_DEBRIS))
			-- ลด nested parts ให้เหลือแค่ 1-2 ชิ้น
			local tempChildren = {}
			for i = 1, math.min(2, #directChildren) do
				table.insert(tempChildren, directChildren[i])
			end
			for i = 3, #directChildren do
				directChildren[i]:Destroy()
			end
			directChildren = tempChildren
		end

		for _, nestedPart in ipairs(directChildren) do
			if nestedPart.Parent ~= workspace then
				nestedPart.Parent = parentContainer or workspace
			end

			nestedPart.Anchored = false
			nestedPart.CanCollide = true
			nestedPart.Massless = false -- เปลี่ยนเป็น false เพื่อให้มีมวล
			nestedPart.CustomPhysicalProperties = LIGHT_DEBRIS_PROPERTIES

			-- ลดความแรงกระเด็นบน mobile เพื่อประหยัด physics และให้ตกเร็วขึ้น
			local velocityMultiplier
			if hasMobilePlayers then
				velocityMultiplier = (ejectStrength == "strong") and 35 or 25 -- ลดจาก 100/60
			else
				velocityMultiplier = (ejectStrength == "strong") and 50 or 35 -- ลดจาก 150/80
			end

			local ejectDirection
			if rescuePosition then
				local awayDirection = (nestedPart.Position - rescuePosition).Unit
				-- ลดแรงขึ้นแนวตั้ง (Y) เพื่อให้ตกเร็วขึ้น
				ejectDirection = Vector3.new(
					awayDirection.X + math.random(-3, 3) / 10,
					math.random(5, 15) / 10, -- ลดจาก 25-50 เป็น 5-15 (ตกเร็วขึ้น)
					awayDirection.Z + math.random(-3, 3) / 10
				).Unit
			else
				ejectDirection = Vector3.new(
					math.random(-10, 10) / 10,
					math.random(5, 15) / 10, -- ลดจาก 25-50 เป็น 5-15 (ตกเร็วขึ้น)
					math.random(-10, 10) / 10
				).Unit
			end

			nestedPart.AssemblyLinearVelocity = ejectDirection * velocityMultiplier

			-- ลดการหมุนบน mobile
			local rotationMultiplier
			if hasMobilePlayers then
				rotationMultiplier = (ejectStrength == "strong") and 5 or 3 -- ลดจาก 10/5
			else
				rotationMultiplier = (ejectStrength == "strong") and 8 or 5 -- ลดจาก 15/10
			end

			local randomRotation = Vector3.new(
				math.random(-rotationMultiplier, rotationMultiplier),
				math.random(-rotationMultiplier, rotationMultiplier),
				math.random(-rotationMultiplier, rotationMultiplier)
			)
			nestedPart.AssemblyAngularVelocity = randomRotation

			-- SetNetworkOwnershipAuto เพื่อลด lag
			pcall(function()
				nestedPart:SetNetworkOwnershipAuto()
			end)

			-- ใช้ fadeDebris แทน Debris:AddItem เพื่อให้ค่อยๆหายไป
			if hasMobilePlayers then
				activeDebrisCount = activeDebrisCount + 1
			end
			fadeDebris(nestedPart, 3, 2, hasMobilePlayers) -- รอ 3 วินาที แล้ว fade ใน 2 วินาที (mobile optimized)
			print("Ejected nested part:", nestedPart.Name, hasMobilePlayers and "- Mobile optimized" or "- Standard physics")
		end

		-- ลบ main part ทันที
		if part and part.Parent then
			part:Destroy()
		end
		print("Main part", part.Name, "removed immediately")

		return
	end

	-- ถ้าไม่มี nested parts ให้ใช้ระบบเดิม (connected parts) และแน่ใจว่ามีข้อมูลสำหรับ part หลัก
	print("No nested parts detected - Using old connected parts system")

	connectedPartsData = connectedPartsData or {}
	local hasMainPart = false
	for _, partInfo in ipairs(connectedPartsData) do
		if partInfo.Name == part.Name then
			hasMainPart = true
			break
		end
	end

	if not hasMainPart then
		print("Adding main part to connectedPartsData for fallback ejection:", part.Name)
		table.insert(connectedPartsData, {
			Name = part.Name,
			Position = part.Position,
			Instance = part
		})
	end

	-- Reduce connected parts for mobile optimization (keep only 30% of parts)
	if hasMobilePlayers and #connectedPartsData > 3 then
		local reducedCount = math.max(3, math.floor(#connectedPartsData * 0.3))
		local tempConnected = {}
		for i = 1, reducedCount do
			table.insert(tempConnected, connectedPartsData[i])
		end
		connectedPartsData = tempConnected
		print(string.format("[Mobile Optimization] Reduced connected parts to %d", #connectedPartsData))
	end

	-- Unanchor และเพิ่มแรงกระเด็นให้ part หลักและ connected parts
	for _, partInfo in ipairs(connectedPartsData) do
		local connectedPart = nil
		if partInfo.Instance and partInfo.Instance:IsA("BasePart") and partInfo.Instance:IsDescendantOf(workspace) then
			connectedPart = partInfo.Instance
		else
			connectedPart = workspace:FindFirstChild(partInfo.Name, true)
		end
		if connectedPart and (connectedPart:IsA("BasePart") or connectedPart:IsA("MeshPart")) then
			-- เจาะได้ทั้ง part ที่ Anchored และ Unanchored
			-- Unanchor ถ้ายัง anchored อยู่
			if connectedPart.Anchored then
				connectedPart.Anchored = false
			end
			connectedPart.CanCollide = true
			connectedPart.Massless = false -- เปลี่ยนเป็น false เพื่อให้มีมวล
			connectedPart.CustomPhysicalProperties = LIGHT_DEBRIS_PROPERTIES

			-- กระเด็นทุกครั้ง แต่ความแรงแตกต่างกัน
			local isMainPart = (connectedPart == part)

			-- กำหนดความแรงตาม ejectStrength (ลดลงเพื่อให้ตกเร็วขึ้น)
			local velocityMultiplier
			if hasMobilePlayers then
				if ejectStrength == "strong" then
					velocityMultiplier = isMainPart and 50 or 35 -- ลดจาก 300/150
				else
					velocityMultiplier = isMainPart and 35 or 25 -- ลดจาก 150/80
				end
			else
				if ejectStrength == "strong" then
					velocityMultiplier = isMainPart and 70 or 50 -- ลดจาก 300/150
				else
					velocityMultiplier = isMainPart and 50 or 35 -- ลดจาก 150/80
				end
			end

			-- คำนวณทิศทางกระเด็นออกจาก Rescue bot (ลดแรงขึ้น)
			local ejectDirection
			if rescuePosition then
				local awayDirection = (connectedPart.Position - rescuePosition).Unit
				ejectDirection = Vector3.new(
					awayDirection.X + math.random(-3, 3) / 10,
					math.random(5, 15) / 10,  -- ลดจาก 25-50 เป็น 5-15 (ตกเร็วขึ้น)
					awayDirection.Z + math.random(-3, 3) / 10
				).Unit
			else
				ejectDirection = Vector3.new(
					math.random(-10, 10) / 10,
					math.random(5, 15) / 10,  -- ลดจาก 25-50 เป็น 5-15 (ตกเร็วขึ้น)
					math.random(-10, 10) / 10
				).Unit
			end

			-- ใช้ความแรงที่กำหนดไว้
			connectedPart.AssemblyLinearVelocity = ejectDirection * velocityMultiplier

			-- แรงหมุน (ปรับตาม strength และลดลง)
			local rotationMultiplier
			if hasMobilePlayers then
				rotationMultiplier = (ejectStrength == "strong") and (isMainPart and 8 or 5) or (isMainPart and 5 or 3)
			else
				rotationMultiplier = (ejectStrength == "strong") and (isMainPart and 12 or 8) or (isMainPart and 8 or 5)
			end

			local randomRotation = Vector3.new(
				math.random(-rotationMultiplier, rotationMultiplier),
				math.random(-rotationMultiplier, rotationMultiplier),
				math.random(-rotationMultiplier, rotationMultiplier)
			)
			connectedPart.AssemblyAngularVelocity = randomRotation

			-- SetNetworkOwnershipAuto เพื่อลด lag
			pcall(function()
				connectedPart:SetNetworkOwnershipAuto()
			end)

			print("Server ejected:", connectedPart.Name, "IsMainPart:", isMainPart, "Strength:", ejectStrength or "normal", "Velocity:", velocityMultiplier)
		end
	end

	-- เช็คว่ามี part อื่นๆ ที่ Anchored แต่ไม่มี part ล้อมรอบ ให้ unanchor ตัวเอง (เฉพาะบริเวณใกล้ๆ)
	local function checkFloatingParts()
		local buildingLV1 = workspace:FindFirstChild("Building_LV1")
		local obstaclesFolder = buildingLV1 and buildingLV1:FindFirstChild("Obstacles") or workspace:FindFirstChild("Obstacles")

		if not obstaclesFolder then return end

		-- เช็คเฉพาะ parts ในรัศมี 20 studs จาก part ที่เจาะ เพื่อลดภาระ
		local searchRadius = 20
		local nearbyParts = workspace:GetPartBoundsInRadius(part.Position, searchRadius)

		for _, nearbyPart in ipairs(nearbyParts) do
			if (nearbyPart:IsA("BasePart") or nearbyPart:IsA("MeshPart")) and nearbyPart.Anchored then
				-- เช็คว่าอยู่ใน Obstacles folder
				local isInObstacles = false
				local ancestor = nearbyPart.Parent
				while ancestor and ancestor ~= workspace do
					if ancestor == obstaclesFolder then
						isInObstacles = true
						break
					end
					ancestor = ancestor.Parent
				end

				if not isInObstacles then
					continue -- ข้าม part ที่ไม่ได้อยู่ใน Obstacles
				end
				-- ยิง raycast 6 ทิศทาง เพื่อหา part ข้างๆ
				local hasNeighbor = false
				local directions = {
					Vector3.new(0, 1, 0),   -- up
					Vector3.new(0, -1, 0),  -- down
					Vector3.new(0, 0, 1),   -- front
					Vector3.new(0, 0, -1),  -- back
					Vector3.new(1, 0, 0),   -- right
					Vector3.new(-1, 0, 0)   -- left
				}

				local partSize = nearbyPart.Size
				local rayDistance = math.max(partSize.X, partSize.Y, partSize.Z) * 0.6

				local rayParams = RaycastParams.new()
				rayParams.FilterDescendantsInstances = {nearbyPart}
				rayParams.FilterType = Enum.RaycastFilterType.Exclude

				for _, direction in ipairs(directions) do
					local rayResult = workspace:Raycast(nearbyPart.Position, direction * rayDistance, rayParams)
					if rayResult and rayResult.Instance then
						local hitPart = rayResult.Instance
						-- เช็คว่า hitPart อยู่ใน Obstacles และยัง Anchored
						if hitPart:IsA("BasePart") or hitPart:IsA("MeshPart") then
							local isInObstacles = false
							local ancestor = hitPart.Parent
							while ancestor and ancestor ~= workspace do
								if ancestor == obstaclesFolder then
									isInObstacles = true
									break
								end
								ancestor = ancestor.Parent
							end

							if isInObstacles and hitPart.Anchored then
								hasNeighbor = true
								break
							end
						end
					end
				end

				-- ถ้าไม่มีเพื่อนบ้าน ให้ unanchor
				if not hasNeighbor then
					print("Found floating part:", nearbyPart.Name, "- Unanchoring")
					nearbyPart.Anchored = false
					nearbyPart.CanCollide = true

					-- ตั้งค่า physics properties
					local customProps = PhysicalProperties.new(0.3, 0.1, 0.7, 1.0, 1.0)
					nearbyPart.CustomPhysicalProperties = customProps
				end
			end
		end
	end

	-- เช็ค floating parts หลังจากกระเด็นเสร็จ
	task.wait(0.5)
	checkFloatingParts()
end)

-- Server-side Waiting System functions
-- ฟังก์ชันสุ่ม spawn points ที่ไม่ซ้ำกัน (ย้ายมาจาก client)
local function assignRandomSpawns(players)
	local spawnRescues = workspace:FindFirstChild("SpawnRescues")
	if not spawnRescues then
		warn("SpawnRescues not found in workspace")
		return {}
	end

	-- หา spawn points ทั้งหมด
	local spawnPoints = {}
	for _, child in ipairs(spawnRescues:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(spawnPoints, child)
		end
	end

	if #spawnPoints == 0 then
		warn("No spawn points found in SpawnRescues")
		return {}
	end

	-- สุ่มมอบหมาย spawn points ให้ผู้เล่น
	local assignments = {}
	for i, player in ipairs(players) do
		if i <= #spawnPoints then
			local randomIndex = math.random(1, #spawnPoints)
			assignments[player.Name] = spawnPoints[randomIndex] -- ใช้ player.Name เป็น key
			table.remove(spawnPoints, randomIndex) -- ไม่ให้ซ้ำ
			print("Assigned spawn point", assignments[player.Name].Name, "to", player.Name)
		else
			-- ถ้าผู้เล่นเยอะกว่า spawn points ให้ใช้แบบสุ่ม
			local randomPoint = spawnPoints[math.random(1, #spawnPoints)]
			assignments[player.Name] = randomPoint
			print("Assigned random spawn point", randomPoint.Name, "to", player.Name, "(overflow)")
		end
	end

	return assignments
end

local function startGame()
	print("Server: Starting game with " .. #waitingPlayers .. " players!")
	isGamePlaying = true

	if table.clear then
		table.clear(activeGamePlayers)
	else
		for player in pairs(activeGamePlayers) do
			activeGamePlayers[player] = nil
		end
	end

	for _, player in ipairs(waitingPlayers) do
		if player and player.Parent == Players then
			activeGamePlayers[player] = true
		end
	end

	-- Reset HP และ Battery ของทุก RescueBot
	for player, healthInstance in pairs(rescueBotHealthInstances) do
		if healthInstance then
			healthInstance:Reset()
		end
	end

	-- สุ่ม spawn points ให้ผู้เล่นแบบไม่ซ้ำกัน
	playerSpawnAssignments = assignRandomSpawns(waitingPlayers)

	-- ส่งรายชื่อผู้เล่นให้ clients
	local playersArray = {}
	for _, player in ipairs(waitingPlayers) do
		table.insert(playersArray, player.Name)
	end

	-- Clear obstacles และ victims เก่าก่อน (ป้องกันการ spawn ซ้ำ)
	print("Clearing old obstacles and victims before spawning new ones...")
	VictimSpawner.clearAllObstacles()
	VictimSpawner.clearAllVictims()

	-- Spawn obstacles ก่อน (จาก ServerStorage.Models.Obstacles -> workspace.Building_LV1.Obstacles)
	print("Spawning obstacles for the game...")
	local obstaclesSpawned = VictimSpawner.spawnAllObstacles()
	if obstaclesSpawned then
		print("Obstacles spawned successfully")
	else
		warn("Failed to spawn obstacles")
	end

	-- Spawn victims ทั้งหมด
	print("Spawning victims for the game...")
	local victimsSpawned = VictimSpawner.spawnAllVictims()
	if victimsSpawned then
		print("Victims spawned successfully")
		-- Signal to clients that victims are ready
		task.wait(0.5) -- Small delay to ensure victims are fully loaded
		victimsReadyRemote:FireAllClients()
		print("Sent VictimsReady signal to all clients")
	else
		warn("Failed to spawn victims")
	end


	-- คำนวณ game duration ตามจำนวนผู้เล่น
	local playerCount = #waitingPlayers
	local gameMode = GameConfig.getGameModeForPlayerCount(playerCount)
	local gameDuration = gameMode.gameDuration

	print(string.format("[Server] Starting game with %d players - Duration: %d seconds", playerCount, gameDuration))

	if next(activeGamePlayers) ~= nil then
		AftershockSystem.start({
			gameDuration = gameDuration,
		})
	else
		AftershockSystem.stop()
	end

	-- เริ่ม Battery drain สำหรับ RescueBot ทั้งหมด
	for player, healthInstance in pairs(rescueBotHealthInstances) do
		if healthInstance then
			healthInstance:StartBatteryDrain(gameDuration)
		end
	end

	-- แจ้งทุก client ว่าเกมเริ่มแล้ว และให้เริ่ม billboard timer (ส่งไปทุกคน)
	waitingSystemRemote:FireAllClients("gameStarted", gameDuration, playerCount)
	print("[Server] Broadcasted gameStarted to all clients - Duration:", gameDuration)

	-- แจ้ง clients ที่อยู่ในเกมให้เริ่มเล่น (เฉพาะผู้เล่นที่อยู่ในเกม)
	for _, player in ipairs(waitingPlayers) do
		waitingSystemRemote:FireClient(player, "startGame", playersArray)
		print("[Server] Sent startGame to", player.Name)
	end

	-- เริ่มต้น GameSummary สำหรับผู้เล่นทุกคน
	GameSummary.initializeAllPlayers()

	-- ล้างรายการผู้เล่นที่รอ
	waitingPlayers = {}

	-- Game จะจบเมื่อ client ส่งสัญญาณ timer หมด (ไม่ใช้ server timer แล้ว)
end

-- ฟังก์ชันจบเกม (เรียกเมื่อได้รับสัญญาณจาก client)
local function endGame()
	if not isGamePlaying then return end -- ป้องกันการเรียกซ้ำ

	isGamePlaying = false

	AftershockSystem.stop()
	if table.clear then
		table.clear(activeGamePlayers)
	else
		for player in pairs(activeGamePlayers) do
			activeGamePlayers[player] = nil
		end
	end

	-- ตรวจสอบจำนวน victims ที่ช่วยได้
	local totalVictims = VictimSpawner.getTotalVictimCount()
	local rescuedVictims = VictimSpawner.getRescuedVictimCount()
	local allRescued = (rescuedVictims >= totalVictims and totalVictims > 0)

	print(string.format("[EndGame] Rescued: %d/%d - Success: %s", rescuedVictims, totalVictims, tostring(allRescued)))

	-- Broadcast ผลการช่วยเหลือพร้อมเสียงให้ทุกคน
	broadcastMissionResult(allRescued)

	-- รอให้ client ได้รับข้อมูลก่อนแสดง Summary
	task.wait(0.5)

	-- แสดงสรุปผลเกม
	print("Showing game summary...")
	GameSummary.printStats() -- Debug stats
	task.wait(2) -- รอให้ effects ต่างๆ เสร็จ

	-- Set callback สำหรับเมื่อผู้เล่นปิด summary
	local playersClosed = {}
	local totalPlayers = #game:GetService("Players"):GetPlayers()
	local hasRespawned = false -- ป้องกันการ spawn ซ้ำ

	GameSummary.onSummaryClosed = function(player)
		GameSummary.resetToLobby(player)

		task.wait(5)

		-- เช็คว่าผู้เล่นคนนี้ปิดหรือยัง
		if not playersClosed[player.UserId] then
			playersClosed[player.UserId] = true

			-- นับจำนวนผู้เล่นที่ปิดแล้ว
			local closedCount = 0
			for _ in pairs(playersClosed) do
				closedCount = closedCount + 1
			end

			-- ถ้าเป็นผู้เล่นคนสุดท้ายที่ปิด summary ให้ clear และ spawn ใหม่
			if closedCount >= totalPlayers and not hasRespawned then
				hasRespawned = true
				print("All players closed summary - clearing obstacles and victims...")
				VictimSpawner.clearAllObstacles()
				VictimSpawner.clearAllVictims()

				print("Respawning obstacles and victims...")
				VictimSpawner.spawnAllObstacles()
				VictimSpawner.spawnAllVictims()
				print("Map reset complete - obstacles and victims respawned")
			end
		end
	end

	-- ส่ง mission result ไปด้วยเพื่อให้ Server สามารถสร้าง UI ที่มีข้อความถูกต้อง
	local missionResultMessage = allRescued and "Mission Success" or "Mission Failed"
	GameSummary.showSummaryToAll(allRescued, missionResultMessage)

	print("Server: Game ended - accepting new players")
	waitingSystemRemote:FireAllClients("gameEnded")

	-- รีเซ็ต GameSummary สำหรับเกมถัดไป และ clear/respawn obstacles/victims ถ้ายังไม่ได้ทำ
	task.wait(10) -- รอให้ผู้เล่นดู summary (auto-close)
	if not hasRespawned then
		print("Auto-close timer expired - clearing obstacles and victims...")
		VictimSpawner.clearAllObstacles()
		VictimSpawner.clearAllVictims()

		print("Respawning obstacles and victims...")
		VictimSpawner.spawnAllObstacles()
		VictimSpawner.spawnAllVictims()
		print("Map reset complete - obstacles and victims respawned")
	end
	GameSummary.reset()
end

-- ฟัง event จาก client เมื่อ timer หมดหรือ sync เวลา
gameTimerRemote.OnServerEvent:Connect(function(player, action, ...)
	if action == "timerFinished" then
		print("Received timer finished signal from", player.Name)
		endGame()
	elseif action == "syncTime" then
		-- รับเวลาจาก client ที่กำลังเล่น แล้ว broadcast ไปทุกคน
		local timeLeft, timeText = ...
		if timeLeft and timeText and isGamePlaying then
			-- Broadcast ทั้ง timeLeft และ timeText (MM:SS) ไปทุก client เพื่อ sync Billboard
			waitingSystemRemote:FireAllClients("updateGameTime", timeLeft, timeText)
		end
	end
end)

-- ฟังก์ชันเริ่มนับถอยหลังใน lobby (รอผู้เล่น)
local function startLobbyCountdown()
	if isCountingDown or isGamePlaying then
		return
	end

	isCountingDown = true
	lobbyCountdownTime = GameConfig.WAITING_SYSTEM.lobbyTimeout or 60

	print("[Lobby] Starting countdown:", lobbyCountdownTime, "seconds")

	-- ส่งข้อมูลการนับถอยหลังไปยัง clients
	waitingSystemRemote:FireAllClients("lobbyCountdownStarted", lobbyCountdownTime)

	-- เริ่มนับถอยหลัง
	lobbyCountdownThread = task.spawn(function()
		while lobbyCountdownTime > 0 and isCountingDown do
			task.wait(1)
			lobbyCountdownTime = lobbyCountdownTime - 1

			-- อัปเดตเวลาถอยหลังทุก 5 วินาที หรือเมื่อเหลือน้อยกว่า 10 วินาที
			if lobbyCountdownTime % 5 == 0 or lobbyCountdownTime <= 10 then
				waitingSystemRemote:FireAllClients("lobbyCountdownUpdate", lobbyCountdownTime)
				print("[Lobby] Countdown:", lobbyCountdownTime, "seconds remaining")
			end
		end

		-- หมดเวลา - เริ่มเกมกับผู้เล่นที่มี
		if isCountingDown and #waitingPlayers >= 1 then
			print("[Lobby] Countdown finished - Starting game with", #waitingPlayers, "players")
			startGame()
		end

		isCountingDown = false
		lobbyCountdownThread = nil
	end)
end

-- ฟังก์ชันหยุดนับถอยหลัง lobby
local function stopLobbyCountdown()
	if lobbyCountdownThread then
		task.cancel(lobbyCountdownThread)
		lobbyCountdownThread = nil
	end
	isCountingDown = false
	lobbyCountdownTime = 0
	waitingSystemRemote:FireAllClients("lobbyCountdownStopped")
	print("[Lobby] Countdown stopped")
end

local function addWaitingPlayer(player)
	-- ตรวจสอบว่าผู้เล่นอยู่ในรายการแล้วหรือไม่
	for _, waitingPlayer in ipairs(waitingPlayers) do
		if waitingPlayer == player then
			return false -- ผู้เล่นอยู่ในรายการแล้ว
		end
	end

	-- ตรวจสอบว่าเกมเริ่มแล้วหรือไม่
	if isGamePlaying then
		return false -- เกมกำลังเล่นอยู่
	end

	-- เพิ่มผู้เล่นใหม่
	table.insert(waitingPlayers, player)
	print(player.Name .. " added to server waiting list. Total waiting: " .. #waitingPlayers)

	-- แจ้ง clients ทั้งหมด
	waitingSystemRemote:FireAllClients("updateCount", #waitingPlayers, GameConfig.getMaxPlayers())

	-- ถ้ามีผู้เล่นคนแรก ให้เริ่มนับถอยหลัง
	if #waitingPlayers == 1 then
		startLobbyCountdown()
	end

	-- ถ้าครบจำนวนสูงสุด ให้เริ่มเกมทันที
	if #waitingPlayers >= GameConfig.getMaxPlayers() then
		stopLobbyCountdown()
		startGame()
		return true
	end

	return false
end

-- Handle WaitingSystem RemoteEvent
waitingSystemRemote.OnServerEvent:Connect(function(player, action, ...)
	if action == "addPlayer" then
		local gameReady = addWaitingPlayer(player)
		-- ส่งผลลัพธ์กลับให้ player ที่ request
		waitingSystemRemote:FireClient(player, "gameReady", gameReady)
	elseif action == "removePlayer" then
		-- ป้องกันไม่ให้ออกจากคิวได้หลังจากเกมเริ่มแล้ว
		if isGamePlaying then
			warn(player.Name, "tried to leave waiting list but game already started")
			return
		end

		for i = #waitingPlayers, 1, -1 do
			if waitingPlayers[i] == player then
				table.remove(waitingPlayers, i)
				print("Removed", player.Name, "from waiting list. Total waiting:", #waitingPlayers)
				waitingSystemRemote:FireAllClients("updateCount", #waitingPlayers, GameConfig.getMaxPlayers())

				-- แจ้ง client ที่ออกจากคิวว่าถูกลบออกแล้ว (ยกเลิกการเข้าเกม)
				waitingSystemRemote:FireClient(player, "removedFromWaiting")
				print("[Server] Notified", player.Name, "that they were removed from waiting list")

				-- ถ้าไม่มีผู้เล่นเหลือเลย ให้หยุด countdown
				if #waitingPlayers == 0 then
					stopLobbyCountdown()
					print("[Lobby] No players left - countdown stopped")
				end

				break
			end
		end
	end
end)

-- Handle MapVoting RemoteEvent
mapVotingRemote.OnServerEvent:Connect(function(player, action, ...)
	if action == "vote" then
		local mapName = ...
		if not mapName then return end

		-- ลบ vote เก่าของผู้เล่น (ถ้ามี)
		local oldVote = playerVotes[player.Name]
		if oldVote then
			currentVotes[oldVote] = (currentVotes[oldVote] or 1) - 1
			if currentVotes[oldVote] <= 0 then
				currentVotes[oldVote] = nil
			end
		end

		-- เพิ่ม vote ใหม่ (ใช้ player.Name เป็น key)
		playerVotes[player.Name] = mapName
		currentVotes[mapName] = (currentVotes[mapName] or 0) + 1

		print("Server: " .. player.Name .. " voted for " .. mapName)
		print("Current votes:", currentVotes)

		-- ส่งข้อมูล vote ใหม่ให้ clients ทั้งหมด
		mapVotingRemote:FireAllClients("updateVotes", currentVotes, playerVotes)
	elseif action == "resetVotes" then
		-- รีเซ็ต votes (เมื่อเริ่ม voting ใหม่)
		currentVotes = {}
		playerVotes = {}
		print("Server: Reset all votes")
		mapVotingRemote:FireAllClients("updateVotes", currentVotes, playerVotes)
	end
end)

-- Player cleanup for voting
Players.PlayerRemoving:Connect(function(player)
	-- ลบ vote ของผู้เล่นที่ออกจากเกม (ใช้ player.Name)
	local playerVote = playerVotes[player.Name]
	if playerVote then
		currentVotes[playerVote] = (currentVotes[playerVote] or 1) - 1
		if currentVotes[playerVote] <= 0 then
			currentVotes[playerVote] = nil
		end
		playerVotes[player.Name] = nil

		-- แจ้ง clients ที่เหลือ
		mapVotingRemote:FireAllClients("updateVotes", currentVotes, playerVotes)
	end
end)

-- Handle SpawnAssignment RemoteEvent
spawnAssignmentRemote.OnServerEvent:Connect(function(player, action)
	if action == "getSpawnPoint" then
		local assignedSpawnPoint = playerSpawnAssignments[player.Name]
		if assignedSpawnPoint then
			-- ส่ง spawn point position กลับไป (ไม่ส่ง BasePart object)
			local position = assignedSpawnPoint.Position
			spawnAssignmentRemote:FireClient(player, "spawnPoint", position)
			print("Sent spawn point to", player.Name, ":", position)
		else
			spawnAssignmentRemote:FireClient(player, "spawnPoint", nil)
			print("No spawn point assigned for", player.Name)
		end
	end
end)

-- ตรวจสอบ VictimSpawner setup
print("Checking VictimSpawner setup...")
local templateReady, templateMessage = VictimSpawner.checkTemplate()
print("Template check:", templateMessage)

local spawnPointsReady, spawnPointsMessage = VictimSpawner.checkSpawnPoints()
print("Spawn points check:", spawnPointsMessage)

if templateReady and spawnPointsReady then
	print("VictimSpawner is ready!")
else
	warn("VictimSpawner setup incomplete - victims may not spawn properly")
end

-- Handle drill effect broadcasting
drillEffectRemote.OnServerEvent:Connect(function(player, action)
	-- Broadcast to all other players
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			drillEffectRemote:FireClient(otherPlayer, player, action)
		end
	end
end)

-- Handle drill sound broadcasting
local drillSoundRemote = getOrCreateRemote("DrillSound")
drillSoundRemote.OnServerEvent:Connect(function(player, action)
	-- Broadcast to all other players
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			drillSoundRemote:FireClient(otherPlayer, player, action)
		end
	end
	print(string.format("[DrillSound] Broadcasting %s from %s to all players", action, player.Name))
end)

-- Handle device type notification from clients
deviceTypeRemote.OnServerEvent:Connect(function(player, isMobile)
	mobilePlayersList[player.UserId] = isMobile
	print(string.format("[DeviceType] Player %s is on %s", player.Name, isMobile and "Mobile" or "Desktop"))
end)

-- Clean up when player leaves
Players.PlayerRemoving:Connect(function(player)
	mobilePlayersList[player.UserId] = nil
end)

print("RescueBotServer loaded")
