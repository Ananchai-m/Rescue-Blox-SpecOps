local GameConfig = {}

-- Game Settings
GameConfig.MAX_PLAYERS = 1
GameConfig.GAME_DURATION = 300 -- 5 minutes in seconds
GameConfig.VOTING_TIMER = 15 -- seconds for map voting

-- Waiting System Settings
GameConfig.WAITING_SYSTEM = {
	maxPlayers = 1,
	lobbyTimeout = 60 -- seconds to wait before auto-starting with minimum players
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
	votingTime = 15, -- seconds
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

-- UI Settings
GameConfig.UI = {
	coinUIPosition = UDim2.new(0.02, 0, 0.05, 0), -- Scale-based positioning
	coinUISize = UDim2.new(0.15, 0, 0.08, 0), -- Scale-based sizing
	notificationDuration = 0.5,
	cornerRadius = UDim.new(0.01, 0), -- Scale-based corner radius
	smallCornerRadius = UDim.new(0.1, 0) -- Scale-based small corner radius
}

-- Debug Settings
GameConfig.DEBUG = {
	enableLogging = true,
	showSpawnPoints = false,
	godMode = false
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