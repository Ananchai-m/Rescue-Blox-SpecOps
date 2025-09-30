-- ShopClient Script
-- เรียกใช้ ShopUI Module

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local player = Players.LocalPlayer

-- รอให้ player พร้อม
if not player.Character then
	player.CharacterAdded:Wait()
end

-- รอ ShopUI Module
local ShopUI = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("ShopUI"))

-- Initialize Shop UI
ShopUI.init()

print("ShopClient loaded - Shop UI is ready!")