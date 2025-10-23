-- AftershockSystem.luau
-- จัดการระบบ Aftershock ในช่วงเริ่มเกม พร้อมปล่อยหินตกแบบสุ่มใส่ RescueBots

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Debris = game:GetService("Debris")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local aftershockWarningRemote = nil

local rng = Random.new()

local function resolveRange(range, fallbackMin, fallbackMax)
	if typeof(range) ~= "table" then
		return fallbackMin, fallbackMax
	end

	local minValue = range.min or range[1] or fallbackMin
	local maxValue = range.max or range[2] or fallbackMax
	if maxValue < minValue then
		minValue, maxValue = maxValue, minValue
	end

	return minValue, maxValue
end

local function randomInRange(range, fallbackMin, fallbackMax)
	local minValue, maxValue = resolveRange(range, fallbackMin, fallbackMax)
	if minValue == maxValue then
		return minValue
	end
	return rng:NextNumber(minValue, maxValue)
end

local AFTERSHOCK_CONFIG = {
	initialDelayRange = {min = 30, max = 45},
	minInterval = 60,
	maxInterval = 60,
	warningTime = 3,
	rockFallCount = 15, -- เพิ่มเป็น 15 เศษต่อผู้เล่น (ตกเยอะขึ้น)
	rockDamage = 5,
	spawnHeightAboveFloor = 30, -- สูงเหนือพื้น BaseFloor2 เท่าไหร่ (studs)
	raycastDistance = 200, -- ระยะ Raycast ลงมา (studs)
	floor2Path = {"Building_LV1", "Buidling", "BaseFloor2"}, -- ชั้น 2 (spawn point)
	floor1Path = {"Building_LV1", "Buidling", "BaseFloor1"}, -- ชั้น 1 (target floor)
}

local AftershockSystem = {}
AftershockSystem._isRunning = false
AftershockSystem._gameEndTime = nil
AftershockSystem._damageHandler = nil
AftershockSystem._activePlayersProvider = nil
AftershockSystem._rescueModelProvider = nil

-- ตั้งค่า CollisionGroup สำหรับหิน
local PhysicsService = game:GetService("PhysicsService")

-- สร้าง Folder สำหรับเก็บ AftershockDebris
local debrisFolder = workspace:FindFirstChild("AftershockDebris")
if not debrisFolder then
	debrisFolder = Instance.new("Folder")
	debrisFolder.Name = "AftershockDebris"
	debrisFolder.Parent = workspace
	print("[Aftershock] Created AftershockDebris folder in workspace")
end

local function setupCollisionGroups()
	-- สร้าง CollisionGroup สำหรับหิน Aftershock
	pcall(function()
		PhysicsService:CreateCollisionGroup("AftershockRocks")
	end)

	-- สร้าง CollisionGroup สำหรับพื้นที่หินต้องชน (BaseFloor ชั้น 1)
	pcall(function()
		PhysicsService:CreateCollisionGroup("AftershockTargetFloor")
	end)

	-- ตั้งค่าให้หินไม่ชนกับ Default group (ชั้นอาคาร, Meshes, ฯลฯ)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("AftershockRocks", "Default", false)
	end)

	-- ตั้งค่าให้หินชนกับ AftershockTargetFloor (BaseFloor ชั้น 1)
	pcall(function()
		PhysicsService:CollisionGroupSetCollidable("AftershockRocks", "AftershockTargetFloor", true)
	end)

	-- ตั้ง BaseFloor (ชั้น 1) ให้อยู่ใน AftershockTargetFloor group
	local floor1 = workspace:FindFirstChild("Building_LV1")
	if floor1 then
		floor1 = floor1:FindFirstChild("Buidling")
		if floor1 then
			floor1 = floor1:FindFirstChild("BaseFloor1")
			if floor1 and floor1:IsA("BasePart") then
				pcall(function()
					PhysicsService:SetPartCollisionGroup(floor1, "AftershockTargetFloor")
					print("[Aftershock] BaseFloor (ชั้น 1) set to AftershockTargetFloor group")
				end)
			end
		end
	end

	print("[Aftershock] CollisionGroups configured - rocks will pass through obstacles but stop at BaseFloor")
end

setupCollisionGroups()

local function ensureRemote()
	if not aftershockWarningRemote then
		local rescueRemotes = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
		if rescueRemotes then
			aftershockWarningRemote = rescueRemotes:FindFirstChild("AftershockWarning")
		end
	end
	return aftershockWarningRemote
end

function AftershockSystem.setDamageHandler(callback)
	AftershockSystem._damageHandler = callback
end

function AftershockSystem.setActivePlayersProvider(callback)
	AftershockSystem._activePlayersProvider = callback
end

function AftershockSystem.setRescueModelProvider(callback)
	AftershockSystem._rescueModelProvider = callback
end

local function getActivePlayers()
	if AftershockSystem._activePlayersProvider then
		local ok, players = pcall(AftershockSystem._activePlayersProvider)
		if ok and typeof(players) == "table" then
			return players
		end
	end

	return Players:GetPlayers()
end

local function getRescueModelForPlayer(player)
	if not player then
		warn("[Aftershock] getRescueModelForPlayer - player is nil")
		return nil
	end

	print(string.format("[Aftershock] getRescueModelForPlayer - looking for rescue for %s", player.Name))

	if AftershockSystem._rescueModelProvider then
		local ok, model = pcall(AftershockSystem._rescueModelProvider, player)
		if ok and typeof(model) == "Instance" then
			print(string.format("[Aftershock] Found rescue via provider for %s: %s", player.Name, model.Name))
			return model
		else
			warn(string.format("[Aftershock] Provider failed for %s: %s", player.Name, tostring(model)))
		end
	end

	local expectedName = player.Name .. "_Rescue"
	print(string.format("[Aftershock] Looking for rescue in workspace: %s", expectedName))

	local fallback = workspace:FindFirstChild(expectedName)
	if fallback then
		print(string.format("[Aftershock] Found instance: %s, ClassName: %s, IsA Model: %s", fallback.Name, fallback.ClassName, tostring(fallback:IsA("Model"))))
		if fallback:IsA("Model") then
			if fallback.PrimaryPart then
				print(string.format("[Aftershock] Rescue has PrimaryPart: %s at position %s", fallback.PrimaryPart.Name, tostring(fallback.PrimaryPart.Position)))
			else
				warn(string.format("[Aftershock] Rescue %s has NO PrimaryPart!", fallback.Name))
			end
			return fallback
		end
	else
		warn(string.format("[Aftershock] FindFirstChild returned nil for %s", expectedName))
		-- List all _Rescue models in workspace for debugging
		print("[Aftershock] All _Rescue models in workspace:")
		for _, child in ipairs(workspace:GetChildren()) do
			if child.Name:match("_Rescue$") then
				print(string.format("  - %s (ClassName: %s)", child.Name, child.ClassName))
			end
		end
	end

	warn(string.format("[Aftershock] No rescue model found for %s", player.Name))
	return nil
end

-- ฟังก์ชันง่ายๆ สำหรับคำนวณตำแหน่ง spawn หิน (ข้างบน Rescue)
local function computeRockSpawnPosition(rescueModel: Model?)
	if not rescueModel or not rescueModel.PrimaryPart then
		warn("[Aftershock] computeRockSpawnPosition - no rescue or PrimaryPart")
		return nil
	end

	-- หา BaseFloor2 (ชั้น 2)
	local current: Instance? = workspace
	for _, segment in ipairs(AFTERSHOCK_CONFIG.floor2Path) do
		if not current then
			break
		end
		current = current:FindFirstChild(segment)
	end

	local floor2 = current
	if not floor2 or not floor2:IsA("BasePart") then
		warn("[Aftershock] BaseFloor2 not found at path:", table.concat(AFTERSHOCK_CONFIG.floor2Path, " > "))
		return nil
	end

	-- หา BaseFloor1 (ชั้น 1 - เป้าหมาย)
	local current1: Instance? = workspace
	for _, segment in ipairs(AFTERSHOCK_CONFIG.floor1Path) do
		if not current1 then
			break
		end
		current1 = current1:FindFirstChild(segment)
	end

	local floor1 = current1
	if not floor1 or not floor1:IsA("BasePart") then
		warn("[Aftershock] BaseFloor1 not found at path:", table.concat(AFTERSHOCK_CONFIG.floor1Path, " > "))
		-- ไม่ return nil, ใช้ floor2 ต่อไปก็ได้
	end

	local floor2CFrame = floor2.CFrame
	local floor2Size = floor2.Size

	-- สุ่มตำแหน่งบนพื้น BaseFloor2
	local randomX = rng:NextNumber(-floor2Size.X * 0.4, floor2Size.X * 0.4)
	local randomZ = rng:NextNumber(-floor2Size.Z * 0.4, floor2Size.Z * 0.4)

	-- คำนวณตำแหน่ง spawn (เหนือ Floor2)
	local localPosition = Vector3.new(
		randomX,
		floor2Size.Y / 2 + AFTERSHOCK_CONFIG.spawnHeightAboveFloor,
		randomZ
	)

	local spawnPosition = floor2CFrame:PointToWorldSpace(localPosition)

	-- ถ้ามี Floor1 ให้ Raycast ลงไปตรวจสอบ
	if floor1 then
		local rayOrigin = spawnPosition
		local rayDirection = Vector3.new(0, -AFTERSHOCK_CONFIG.raycastDistance, 0)

		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Include
		rayParams.FilterDescendantsInstances = {floor1}

		local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)

		if rayResult then
			print(string.format("[Aftershock] Rock will fall from Floor2 to Floor1 (distance: %.2f studs)", (rayResult.Position - spawnPosition).Magnitude))
		else
			warn("[Aftershock] Raycast failed to reach Floor1 from:", tostring(spawnPosition))
		end
	end

	print(string.format("[Aftershock] Rock spawn at random position on BaseFloor2: %s", tostring(spawnPosition)))

	return spawnPosition
end

local function applyDamage(player, amount, damageType)
	if AftershockSystem._damageHandler and player then
		local ok, err = pcall(AftershockSystem._damageHandler, player, amount, damageType)
		if not ok then
			warn("[Aftershock] Failed to apply damage:", err)
		end
	end
end

-- สุ่มเลือก MeshPart จาก ServerStorage.CrackObject
local function createFallingDebris()
	local crackObject = ServerStorage:FindFirstChild("CrackObject")
	if not crackObject then
		warn("[Aftershock] CrackObject not found in ServerStorage")
		return nil
	end

	-- หา MeshParts ทั้งหมดใน CrackObject
	local meshParts = {}
	for _, child in ipairs(crackObject:GetDescendants()) do
		if child:IsA("MeshPart") then
			table.insert(meshParts, child)
		end
	end

	if #meshParts == 0 then
		warn("[Aftershock] No MeshParts found in CrackObject")
		return nil
	end

	-- สุ่มเลือก 1 MeshPart
	local randomIndex = rng:NextInteger(1, #meshParts)
	local selectedMesh = meshParts[randomIndex]

	-- Clone MeshPart
	local debris = selectedMesh:Clone()
	debris.Name = "AftershockDebris"
	debris.Anchored = false
	debris.CanCollide = true
	debris.CanQuery = true
	debris.CanTouch = true
	debris:SetAttribute("AftershockDebris", true)

	-- Unanchor ทุก MeshPart ที่อยู่ข้างใน (Children)
	for _, child in ipairs(debris:GetDescendants()) do
		if child:IsA("BasePart") or child:IsA("MeshPart") then
			child.Anchored = false
		end
	end

	-- ตั้งค่า physics ให้หนักและตกเร็ว
	pcall(function()
		debris.CustomPhysicalProperties = PhysicalProperties.new(5.0, 0.3, 0.1, 1, 1)
	end)

	-- ใส่ CollisionGroup เพื่อให้ผ่านสิ่งกีดขวางได้
	pcall(function()
		PhysicsService:SetPartCollisionGroup(debris, "AftershockRocks")
	end)

	print(string.format("[Aftershock] Created debris from: %s", selectedMesh.Name))

	return debris
end

local function dropRock(spawnPosition, targetPlayer, targetRescue, isMobile)
	if not spawnPosition then
		warn("[Aftershock] dropRock failed - missing spawn position")
		return
	end

	print(string.format("[Aftershock] Dropping debris at %s (Player: %s, Mobile: %s)", tostring(spawnPosition), targetPlayer and targetPlayer.Name or "nil", tostring(isMobile)))

	local debris = createFallingDebris()
	if not debris then
		warn("[Aftershock] Failed to create debris")
		return
	end

	debris.CFrame = CFrame.new(spawnPosition)
	debris.Parent = debrisFolder -- ใส่ใน Folder แทน workspace โดยตรง
	debris:SetNetworkOwner(nil)

	print(string.format("[Aftershock] Debris spawned: %s at %s", debris.Name, tostring(debris.Position)))

	-- ตั้งเวลาหาย (fallback) - กรณีไม่โดนอะไรเลย
	local maxLifetime = isMobile and 5 or 10
	Debris:AddItem(debris, maxLifetime)
	print(string.format("[Aftershock] Debris fallback cleanup set to %ds", maxLifetime))

	-- ให้ debris ตกแบบอิสระตาม physics (แรงโน้มถ่วงจะทำให้ตก)
	-- เพิ่มการหมุนสุ่มเล็กน้อย
	debris.AssemblyAngularVelocity = Vector3.new(
		rng:NextNumber(-3, 3),
		rng:NextNumber(-3, 3),
		rng:NextNumber(-3, 3)
	)

	local damageApplied = false
	local connection
	connection = debris.Touched:Connect(function(hit)
		if damageApplied or not hit or not hit.Parent then
			return
		end

		if hit:IsDescendantOf(debris) then
			return
		end

		-- Debug: แสดงทุกอย่างที่ debris โดน
		print(string.format("[Aftershock] Debris touched: %s (CanCollide: %s)", hit.Name, tostring(hit.CanCollide)))

		local hitModel = hit:FindFirstAncestorOfClass("Model")
		if hitModel and (hitModel == targetRescue or hitModel.Name:match("_Rescue$")) then
			damageApplied = true

			local player = targetPlayer
			if not player and hitModel then
				player = Players:FindFirstChild(hitModel.Name:gsub("_Rescue$", ""))
			end

			applyDamage(player, AFTERSHOCK_CONFIG.rockDamage, "Aftershock Debris")

			if connection then
				connection:Disconnect()
			end
			debris:Destroy()
			print(string.format("[Aftershock] Debris hit Rescue and destroyed"))
		elseif hit.Name == "BaseFloor" then
			-- โดนพื้นชั้น 1 (BaseFloor) เท่านั้น - debris หยุด
			print(string.format("[Aftershock] Debris hit BaseFloor (target floor): %s", hit.Name))
			print(string.format("[Aftershock] Debris stopped at position: %s", tostring(debris.Position)))
			damageApplied = true
			if connection then
				connection:Disconnect()
			end

			-- ลบ debris หลังจากหยุด
			local lifetime = 3 -- PC: 3 วินาที
			if isMobile then
				lifetime = GameConfig.MOBILE_PERFORMANCE.DEBRIS_LIFETIME -- Mobile: 1.5 วินาที
			end
			print(string.format("[Aftershock] Debris will be removed in %.1fs", lifetime))
			Debris:AddItem(debris, lifetime)
		else
			-- โดนสิ่งอื่นๆ (Meshes, BaseFloor2, ฯลฯ) - ให้ผ่านไป (ไม่ทำอะไร)
			print(string.format("[Aftershock] Debris passing through: %s (ignoring)", hit.Name))
		end
	end)
end

local function triggerAftershock()
	local remote = ensureRemote()
	if not remote then
		warn("[Aftershock] AftershockWarning remote not found")
		return
	end

	local players = getActivePlayers()
	print(string.format("[Aftershock] triggerAftershock - %d active players", #players))
	if #players == 0 then
		warn("[Aftershock] No active players found")
		return
	end

	local activeEntries = {}
	local rescueMap = {}
	local includeModels = {}

	for _, player in ipairs(players) do
		print(string.format("[Aftershock] Checking player: %s", player.Name))
		local rescueModel = getRescueModelForPlayer(player)
		if rescueModel and rescueModel.PrimaryPart then
			print(string.format("[Aftershock] Added %s to active entries (Rescue: %s, PrimaryPart: %s)", player.Name, rescueModel.Name, rescueModel.PrimaryPart.Name))
			table.insert(activeEntries, {player = player, rescueModel = rescueModel})
			rescueMap[rescueModel] = player
			table.insert(includeModels, rescueModel)
		else
			warn(string.format("[Aftershock] Skipped %s - no rescue model or PrimaryPart", player.Name))
		end
	end

	print(string.format("[Aftershock] Total active entries: %d", #activeEntries))
	if #activeEntries == 0 then
		warn("[Aftershock] No active entries - aborting aftershock")
		return
	end

	local pendingDrops = {}

	for _, entry in ipairs(activeEntries) do
		-- ตรวจจับว่าผู้เล่นเป็น mobile หรือไม่ และปรับจำนวน debris
		local isMobile = false
		pcall(function()
			if entry.player and entry.player:FindFirstChild("DeviceType") then
				local deviceType = entry.player.DeviceType.Value
				isMobile = (deviceType == "Mobile" or deviceType == "Tablet")
			end
		end)

		local debrisCount = AFTERSHOCK_CONFIG.rockFallCount
		if isMobile then
			debrisCount = math.floor(debrisCount * GameConfig.MOBILE_PERFORMANCE.REDUCE_DEBRIS_COUNT)
			print(string.format("[Aftershock] Mobile player %s - reduced debris to %d", entry.player.Name, debrisCount))
		end

		for rockIndex = 1, debrisCount do
			local spawnPosition = computeRockSpawnPosition(entry.rescueModel)
			if spawnPosition then
				print(string.format("[Aftershock] Debris #%d for %s: spawn at %s", rockIndex, entry.player.Name, tostring(spawnPosition)))
				table.insert(pendingDrops, {
					spawnPosition = spawnPosition,
					player = entry.player,
					rescue = entry.rescueModel,
					delay = randomInRange({min = 0.1, max = 0.5}, 0.1, 0.5),
					isMobile = isMobile,
				})
			else
				warn(string.format("[Aftershock] No spawn position for debris #%d (player: %s)", rockIndex, entry.player.Name))
			end
		end
	end

	if #pendingDrops == 0 then
		return
	end

	remote:FireAllClients("warning")
	print(string.format("[Aftershock] Warning broadcast (%d rocks queued)", #pendingDrops))

	task.wait(AFTERSHOCK_CONFIG.warningTime)
	if not AftershockSystem._isRunning then
		remote:FireAllClients("stop")
		return
	end

	remote:FireAllClients("start")
	print(string.format("[Aftershock] Debris fall triggered - spawning %d debris pieces", #pendingDrops))

	for i, drop in ipairs(pendingDrops) do
		task.spawn(function()
			print(string.format("[Aftershock] Debris #%d queued with delay %.2fs", i, drop.delay))
			task.wait(drop.delay)
			dropRock(drop.spawnPosition, drop.player, drop.rescue, drop.isMobile)
		end)
	end
end

local function getTimeRemaining()
	if not AftershockSystem._gameEndTime then
		return math.huge
	end
	return AftershockSystem._gameEndTime - os.clock()
end

function AftershockSystem.start(options)
	AftershockSystem.stop()

	local gameDuration = options and options.gameDuration
	if typeof(gameDuration) == "number" and gameDuration > 0 then
		AftershockSystem._gameEndTime = os.clock() + gameDuration
	else
		AftershockSystem._gameEndTime = nil
	end

	AftershockSystem._isRunning = true
	print("[Aftershock] System started")

	task.spawn(function()
		local nextDelay = randomInRange(AFTERSHOCK_CONFIG.initialDelayRange, 6, 10)

		while AftershockSystem._isRunning do
			local timeRemaining = getTimeRemaining()
			if timeRemaining <= AFTERSHOCK_CONFIG.warningTime then
				break
			end

			local waitTime = math.min(nextDelay, timeRemaining - AFTERSHOCK_CONFIG.warningTime)
			task.wait(waitTime)

			if not AftershockSystem._isRunning then
				break
			end

			triggerAftershock()

			nextDelay = randomInRange({min = AFTERSHOCK_CONFIG.minInterval, max = AFTERSHOCK_CONFIG.maxInterval}, AFTERSHOCK_CONFIG.minInterval, AFTERSHOCK_CONFIG.maxInterval)
		end

		print("[Aftershock] Loop finished")
	end)
end

function AftershockSystem.stop()
	if not AftershockSystem._isRunning then
		return
	end

	AftershockSystem._isRunning = false
	AftershockSystem._gameEndTime = nil

	local remote = ensureRemote()
	if remote then
		remote:FireAllClients("stop")
	end
	print("[Aftershock] System stopped")
end

function AftershockSystem.init()
	local rescueRemotes = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
	if rescueRemotes then
		local gameTimerRemote = rescueRemotes:FindFirstChild("GameTimer")
		if gameTimerRemote then
			gameTimerRemote.OnServerEvent:Connect(function(_, action)
				if action == "timerFinished" then
					AftershockSystem.stop()
				end
			end)
		end
	end
end

return AftershockSystem
