-- VictimRescueSystem Server Script
-- Handles victim rescue interactions and coin rewards

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

-- Import GameConfig and GameSummary
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local GameSummary = require(ReplicatedStorage.Modules.GameSummary)
local rescueSettings = GameConfig.getRescueSettings()

-- Note: GameTimer is client-side, so we'll communicate via RemoteEvents

-- RemoteEvents
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")

-- Create or get rescue remote
local rescueRemote = remoteEvents:FindFirstChild("VictimRescue")
if not rescueRemote then
	rescueRemote = Instance.new("RemoteEvent")
	rescueRemote.Name = "VictimRescue"
	rescueRemote.Parent = remoteEvents
end

-- Track rescued victims per player
local playerRescueCount = {}


-- Function to handle victim rescue
local function handleVictimRescue(player, victim)
	if not player or not victim then return end

	-- Check if victim is valid (removed RescuePrompt check since we use CustomRescueSystem)
	local rootPart = victim:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		warn("Victim has no HumanoidRootPart:", victim.Name)
		return
	end

	print(player.Name, "rescued victim:", victim.Name)

	-- Update player rescue count
	if not playerRescueCount[player] then
		playerRescueCount[player] = 0
	end
	playerRescueCount[player] = playerRescueCount[player] + 1

	-- Update GameSummary stats
	GameSummary.addVictimRescue(player)
	GameSummary.addCoins(player, 10)

	-- Fire client to show coin animation effect (Candy Crush style)
	local coinAmount = 10 -- 10 coins per rescue
	rescueRemote:FireClient(player, "coinCollected", coinAmount, rootPart.Position)

	-- Add victim fade out effect
	local humanoid = victim:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Make victim wave or celebrate before disappearing
		local animationTrack = nil
		-- You can add celebration animation here if available
	end

	-- Fade out and destroy victim
	local fadeInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local fadeTweens = {}

	for _, part in ipairs(victim:GetDescendants()) do
		if part:IsA("BasePart") then
			local fadeTween = TweenService:Create(part, fadeInfo, {
				Transparency = 1
			})
			table.insert(fadeTweens, fadeTween)
			fadeTween:Play()
		end
	end

	-- Destroy victim after fade
	task.wait(1)
	victim:Destroy()

	-- Fire event to clients for sound effects or additional feedback
	rescueRemote:FireClient(player, "victimRescued", playerRescueCount[player])

	print("Player", player.Name, "total rescues:", playerRescueCount[player])
end

-- Handle custom rescue events from client
rescueRemote.OnServerEvent:Connect(function(player, action, victim)
	print("[VictimRescueSystem] Received rescue request from", player.Name, "action:", action, "victim:", victim and victim.Name or "nil")

	if action == "rescue" then
		-- Validate victim exists and player is close enough
		if not victim or not victim.Parent then
			warn("[VictimRescueSystem] Invalid victim provided by", player.Name)
			return
		end

		-- Check if victim is actually a victim
		if not victim.Name:match("^Victim_") then
			warn("[VictimRescueSystem] Invalid victim name:", victim.Name)
			return
		end

		-- Check distance (server-side validation)
		local playerPosition = nil

		-- Try to find player's vehicle first (same logic as client)
		for _, model in ipairs(workspace:GetChildren()) do
			if model:IsA("Model") and (model.Name == player.Name .. "_RescueCompanion" or model.Name == player.Name .. "_Rescue") then
				if model.PrimaryPart then
					playerPosition = model.PrimaryPart.Position
					print("[VictimRescueSystem] Using vehicle position for", player.Name, ":", model.Name)
					break
				end
			end
		end

		-- Fallback to character position
		if not playerPosition then
			local character = player.Character
			if character and character:FindFirstChild("HumanoidRootPart") then
				playerPosition = character.HumanoidRootPart.Position
				print("[VictimRescueSystem] Using character position for", player.Name)
			else
				warn("[VictimRescueSystem] Player has no character or vehicle:", player.Name)
				return
			end
		end

		local victimRoot = victim:FindFirstChild("HumanoidRootPart")
		if not victimRoot then
			warn("[VictimRescueSystem] Victim has no HumanoidRootPart:", victim.Name)
			return
		end

		local distance = (victimRoot.Position - playerPosition).Magnitude
		print("[VictimRescueSystem] Distance check:", player.Name, "to", victim.Name, "=", math.floor(distance), "studs")
		if distance > rescueSettings.serverValidationDistance then
			warn("[VictimRescueSystem] Player too far from victim:", player.Name, "Distance:", distance, "Max:", rescueSettings.serverValidationDistance)
			return
		end

		-- All checks passed, handle rescue
		handleVictimRescue(player, victim)
	end
end)

-- ProximityPromptService removed - using CustomRescueSystem only

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
	playerRescueCount[player] = nil
end)

-- Function to get player rescue count (for external access)
local function getPlayerRescueCount(player)
	return playerRescueCount[player] or 0
end

-- Export functions via RemoteFunction if needed
local rescueStatsRemote = remoteEvents:FindFirstChild("RescueStats")
if not rescueStatsRemote then
	rescueStatsRemote = Instance.new("RemoteFunction")
	rescueStatsRemote.Name = "RescueStats"
	rescueStatsRemote.Parent = remoteEvents
end

rescueStatsRemote.OnServerInvoke = function(player, action)
	if action == "getRescueCount" then
		return getPlayerRescueCount(player)
	end
end

print("VictimRescueSystem loaded and ready")
print("VictimRescue RemoteEvent:", rescueRemote)
print("Listening for rescue events...")