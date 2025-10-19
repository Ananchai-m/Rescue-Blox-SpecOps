-- CountdownSoundHandler Client Script
-- จัดการรับสัญญาณเสียงนับถอยหลังจาก Server

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameTimer = require(ReplicatedStorage.Modules.GameTimer)

-- รับ RemoteEvent
local rescueRemotes = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local countdownSoundRemote = rescueRemotes:WaitForChild("CountdownSound")

-- รับสัญญาณจาก Server เพื่อเล่นเสียงนับถอยหลังพร้อมกัน
countdownSoundRemote.OnClientEvent:Connect(function(action)
	if action == "start" then
		GameTimer.startCountdownSound()
	elseif action == "stop" then
		GameTimer.stopCountdownSound()
	end
end)

print("[CountdownSoundHandler] Client script loaded")
