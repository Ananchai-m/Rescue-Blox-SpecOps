--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
if not localPlayer then
	return
end

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(modulesFolder:WaitForChild("GameConfig"))

if not GameConfig.canUseDeveloperShortcuts(localPlayer.UserId) then
	return
end

local remotesFolder = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local debugModifyHPRemote = remotesFolder:WaitForChild("DebugModifyHP")

local killKey = Enum.KeyCode.K
local damageKey = Enum.KeyCode.J
local debugDamageAmount = 20

local function isModifierPressed()
	return UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
		or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end

	if input.KeyCode == killKey and isModifierPressed() then
		debugModifyHPRemote:FireServer("kill")
	elseif input.KeyCode == damageKey and isModifierPressed() then
		debugModifyHPRemote:FireServer("damage", debugDamageAmount)
	end
end)
