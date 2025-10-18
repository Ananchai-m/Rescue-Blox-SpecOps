--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local localPlayer = Players.LocalPlayer
if not localPlayer then
	warn("[DebugShortcuts] LocalPlayer not found")
	return
end

local modulesFolder = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(modulesFolder:WaitForChild("GameConfig"))

local canUseShortcuts = GameConfig.canUseDeveloperShortcuts(localPlayer.UserId)
print("[DebugShortcuts] UserId:", localPlayer.UserId, "CanUse:", canUseShortcuts)

if not canUseShortcuts then
	warn("[DebugShortcuts] User", localPlayer.UserId, "cannot use developer shortcuts")
	return
end

print("[DebugShortcuts] Debug shortcuts enabled for", localPlayer.Name)

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
		print("[DebugShortcuts] Firing kill command")
		debugModifyHPRemote:FireServer("kill")
	elseif input.KeyCode == damageKey and isModifierPressed() then
		print("[DebugShortcuts] Firing damage command:", debugDamageAmount)
		debugModifyHPRemote:FireServer("damage", debugDamageAmount)
	end
end)

print("[DebugShortcuts] Shortcuts:", "Shift+K = Kill", "Shift+J = Damage", debugDamageAmount)
