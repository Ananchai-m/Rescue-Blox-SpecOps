-- CustomizeClient Script
-- เรียกใช้ CustomizeUI Module

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- รอให้ player พร้อม
if not player.Character then
	player.CharacterAdded:Wait()
end

-- รอ CustomizeUI Module
local CustomizeUI = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("CustomizeUI"))

-- Initialize Customize UI
CustomizeUI.init()

print("CustomizeClient loaded - Customize UI is ready!")
