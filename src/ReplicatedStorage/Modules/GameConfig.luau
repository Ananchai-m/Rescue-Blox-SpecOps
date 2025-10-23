local RunService = game:GetService("RunService")

local GameConfig = {}

-- Game Settings
GameConfig.MAX_PLAYERS = 5 -- รองรับ 1-5 ผู้เล่น (ตาม PLAYER_MODES)
GameConfig.GAME_DURATION = 300 -- 5 minutes in seconds

-- Player Modes Settings (auto-scaling based on player count)
GameConfig.PLAYER_MODES = {
	{
		playerCount = 5,
		gameDuration = 900,  -- 15 minutes
		victimCount = 30
	},
	{
		playerCount = 4,
		gameDuration = 720,  -- 12 minutes
		victimCount = 27
	},
	{
		playerCount = 3,
		gameDuration = 540,  -- 9 minutes
		victimCount = 15
	},
	{
		playerCount = 2,
		gameDuration = 300,  -- 5 minutes
		victimCount = 10
	},
	{
		playerCount = 1,
		gameDuration = 300,  -- 5 minutes
		victimCount = 5
	}
}

-- Waiting System Settings
GameConfig.WAITING_SYSTEM = {
	maxPlayers = 5, -- รองรับ 1-5 ผู้เล่น (ตาม PLAYER_MODES)
	lobbyTimeout = 5 -- seconds to wait before auto-starting with minimum players
}

-- Coin System Settings
GameConfig.COINS = {
	iconId = "117913155324009",
	collectionDistance = 10, -- studs
	spawnCount = 20, -- random coins per game
	spawnRadius = 15, -- radius around spawn points
	coinsPerSpawnPoint = 5,
	defaultValue = 1,
	maxValue = 3
}

-- Drill System Settings
GameConfig.DRILL = {
	maxCombo = 5,
	baseSpeed = 18,
	speedStep = 12,
	baseTorque = 12000,
	torqueStep = 18000,
	comboTimeout = 1.5,
	targetRadius = 5,
	clicksRequired = 5,
	debounceTime = 0.15
}

-- Vehicle Settings
GameConfig.VEHICLE = {
	baseTorque = 8000,
	minTorque = 3000,
	maxAngularVelocity = 15,
	brakeTorque = 20000,
	steerAngle = 35,
	frontWheelTorqueMultiplier = 0.7
}

-- Map Selection Settings
GameConfig.MAP_SELECTION = {
	votingTime = 5, -- seconds
	maps = {
		{
			name = "City Rescue",
			image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
			description = "Urban rescue mission in the city"
		},
		{
			name = "Mountain Rescue",
			image = "rbxasset://textures/ui/GuiImagePlaceholder.png",
			description = "Challenging mountain terrain rescue"
		}
	}
}

-- Victim Spawner Settings
GameConfig.VICTIMS = {
	spawnDelay = 1, -- seconds between spawns
	maxVictims = 50
}

-- Rescue System Settings
GameConfig.RESCUE = {
	distance = 5, -- studs - how close to victim to show UI
	holdDuration = 5, -- seconds - how long to hold E
	keyCode = Enum.KeyCode.E, -- rescue key
	serverValidationDistance = 50 -- studs - server allows more distance for lag
}

-- RescueBot Settings
GameConfig.RESCUE_BOT = {
	maxHP = 100,
	maxBattery = 100,
	damage = {
		rockFalling = 100,      -- หินหล่นทับ (ตายใน 5 ครั้ง) -20
		rockBounce = 10,       -- หินกระเด็นใส่ (ตายใน 10 ครั้ง)
		collision = 5,         -- ชนสิ่งของทั่วไป (ตายใน 20 ครั้ง)
		heavyCollision = 15    -- ชนแรงๆ ความเร็วสูง (ตายใน 6-7 ครั้ง)
	},
	batteryDrain = {
		-- Base rates (will be scaled by calculateBatteryDrain function)
		-- เหล่านี้คือค่าพื้นฐานที่จะถูกคูณด้วย multiplier จาก game duration
		idleMultiplier = 0.3,       -- Multiplier สำหรับ idle (ต่ำที่สุด)
		movingMultiplier = 1.0,     -- Multiplier สำหรับ moving (ปานกลาง)
		drillingMultiplier = 2.5,   -- Multiplier สำหรับ drilling (สูงสุด)
		-- Target: ใช้ Battery ประมาณ 70-80% ของเวลาเกมถ้าเล่นแบบ active
		baseRatePerSecond = 1.0     -- อัตราพื้นฐานที่จะคำนวณจากเวลาเกม
	},
	regeneration = {
		hpPerSecond = 0,      -- ไม่ฟื้นเลือด
		batteryPerSecond = 0  -- ไม่ชาร์จเอง
	},
	revive = {
		sharePercent = 0.3,   -- เปอร์เซ็นต์ coins ที่แบ่งให้ผู้ช่วย
		maxDistance = 15,     -- ระยะสูงสุดในการ revive เพื่อน (studs)
		holdDuration = 5      -- เวลากดค้างเพื่อ revive (วินาที)
	}
}

-- UI Settings
GameConfig.UI = {
	coinUIPosition = UDim2.new(0.02, 0, 0.05, 0), -- Scale-based positioning
	coinUISize = UDim2.new(0.15, 0, 0.08, 0), -- Scale-based sizing
	notificationDuration = 0.5,
	cornerRadius = UDim.new(0.01, 0), -- Scale-based corner radius
	smallCornerRadius = UDim.new(0.1, 0), -- Scale-based small corner radius
	mapSelectioCornerRadius = UDim.new(0.05, 0)
}

-- Mobile/Tablet Performance Settings
GameConfig.MOBILE_PERFORMANCE = {
	REDUCE_DEBRIS_COUNT = 0.5,        -- ลดจำนวนเศษหินเหลือ 50%
	DEBRIS_LIFETIME = 1.5,             -- เศษหินหายใน 1.5 วินาที (ลดจาก 3)
	PARTICLE_RATE_MULTIPLIER = 0.3,    -- ลด particle emission 70%
	MAX_ACTIVE_DEBRIS = 10,            -- จำกัดเศษหินสูงสุด 10 ชิ้นพร้อมกัน (ลดจาก 15)
	DEBRIS_PHYSICS_TIMEOUT = 0.8,      -- หยุด physics หลัง 0.8 วินาที (ลดจาก 2)
	DISABLE_OTHER_PLAYER_EFFECTS = true, -- ปิด particle effects ของผู้เล่นอื่น
	DEBRIS_VELOCITY_MULTIPLIER = 0.4,  -- ลดความเร็วกระเด็นเหลือ 40%
	DEBRIS_GRAVITY_MULTIPLIER = 2.5    -- เพิ่มแรงโน้มถ่วงให้ตกเร็วขึ้น 2.5 เท่า
}

-- Debug Settings
GameConfig.DEBUG = {
	enableLogging = true,
	showSpawnPoints = false,
	godMode = false,
	developerUserIds = {
		1570994142, -- RatchadaSoi2
		7347653268, -- Developer 2
	},
	enableDeveloperShortcuts = true
}

-- Utility functions
function GameConfig.getMaxPlayers()
	return GameConfig.MAX_PLAYERS
end

function GameConfig.setMaxPlayers(count)
	if type(count) == "number" and count > 0 then
		GameConfig.MAX_PLAYERS = count
		GameConfig.WAITING_SYSTEM.maxPlayers = count
		return true
	end
	return false
end

function GameConfig.getGameDuration()
	return GameConfig.GAME_DURATION
end

function GameConfig.setGameDuration(seconds)
	if type(seconds) == "number" and seconds > 0 then
		GameConfig.GAME_DURATION = seconds
		return true
	end
	return false
end

function GameConfig.getCoinSettings()
	return GameConfig.COINS
end

function GameConfig.getDrillSettings()
	return GameConfig.DRILL
end

function GameConfig.getVehicleSettings()
	return GameConfig.VEHICLE
end

function GameConfig.getMapSettings()
	return GameConfig.MAP_SELECTION
end

function GameConfig.addMap(mapData)
	if mapData and mapData.name and mapData.image then
		table.insert(GameConfig.MAP_SELECTION.maps, mapData)
		return true
	end
	return false
end

function GameConfig.removeMap(mapName)
	for i, map in ipairs(GameConfig.MAP_SELECTION.maps) do
		if map.name == mapName then
			table.remove(GameConfig.MAP_SELECTION.maps, i)
			return true
		end
	end
	return false
end

function GameConfig.getRescueSettings()
	return GameConfig.RESCUE
end

function GameConfig.getRescueBotSettings()
	return GameConfig.RESCUE_BOT
end

function GameConfig.isDebugUser(userId)
	if RunService:IsStudio() then
		return true
	end

	if type(userId) ~= "number" then
		return false
	end

	local ids = GameConfig.DEBUG and GameConfig.DEBUG.developerUserIds
	if type(ids) ~= "table" then
		return false
	end

	return table.find(ids, userId) ~= nil
end

function GameConfig.canUseDeveloperShortcuts(userId)
	if RunService:IsStudio() then
		return true
	end

	local debugConfig = GameConfig.DEBUG
	if not (debugConfig and debugConfig.enableDeveloperShortcuts) then
		return false
	end

	if userId == nil then
		return false
	end

	return GameConfig.isDebugUser(userId)
end

-- Validation function
function GameConfig.validate()
	local errors = {}

	if GameConfig.MAX_PLAYERS <= 0 then
		table.insert(errors, "MAX_PLAYERS must be greater than 0")
	end

	if GameConfig.GAME_DURATION <= 0 then
		table.insert(errors, "GAME_DURATION must be greater than 0")
	end

	if #GameConfig.MAP_SELECTION.maps == 0 then
		table.insert(errors, "At least one map must be configured")
	end

	if GameConfig.COINS.collectionDistance <= 0 then
		table.insert(errors, "Coin collection distance must be greater than 0")
	end

	return #errors == 0, errors
end

-- Get game mode settings based on player count
function GameConfig.getGameModeForPlayerCount(playerCount)
	if type(playerCount) ~= "number" or playerCount < 1 then
		playerCount = 1
	end

	-- หาโหมดที่ตรงกับจำนวนผู้เล่น หรือใกล้เคียงที่สุด
	local bestMode = GameConfig.PLAYER_MODES[#GameConfig.PLAYER_MODES] -- default to 1 player mode
	for _, mode in ipairs(GameConfig.PLAYER_MODES) do
		if playerCount >= mode.playerCount then
			bestMode = mode
			break
		end
	end

	return bestMode
end

-- Calculate battery drain rates based on game duration
-- Returns: { idle, moving, drilling }
function GameConfig.calculateBatteryDrain(gameDuration, maxBattery)
	local duration = gameDuration or GameConfig.GAME_DURATION
	local battery = maxBattery or GameConfig.RESCUE_BOT.maxBattery
	local drainSettings = GameConfig.RESCUE_BOT.batteryDrain

	-- คำนวณ base rate เพื่อให้ Battery หมดใน 70% ของเวลาเกมถ้าเล่นแบบ active
	-- สูตร: (maxBattery / (gameDuration * 0.7)) = base rate per second
	local baseRate = battery / (duration * 0.7)

	-- คำนวณอัตราการใช้แต่ละแบบ
	local idleRate = baseRate * drainSettings.idleMultiplier
	local movingRate = baseRate * drainSettings.movingMultiplier
	local drillingRate = baseRate * drainSettings.drillingMultiplier

	return {
		idle = idleRate,
		moving = movingRate,
		drilling = drillingRate
	}
end

-- Get battery drain for current game mode
function GameConfig.getBatteryDrainForMode(playerCount, hasSolarCell)
	local mode = GameConfig.getGameModeForPlayerCount(playerCount)
	local maxBattery = GameConfig.RESCUE_BOT.maxBattery

	-- ถ้ามี SolarCell Battery จะเป็น 2 เท่า
	if hasSolarCell then
		maxBattery = maxBattery * 2
	end

	return GameConfig.calculateBatteryDrain(mode.gameDuration, maxBattery)
end

-- Print current configuration
function GameConfig.printConfig()
	print("=== Game Configuration ===")
	print("Max Players:", GameConfig.MAX_PLAYERS)
	print("Game Duration:", GameConfig.GAME_DURATION, "seconds")
	print("Voting Timer:", GameConfig.VOTING_TIMER, "seconds")
	print("Available Maps:", #GameConfig.MAP_SELECTION.maps)
	print("Coin Collection Distance:", GameConfig.COINS.collectionDistance, "studs")
	print("=========================")
end

return GameConfig
