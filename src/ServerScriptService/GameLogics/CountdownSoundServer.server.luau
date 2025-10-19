-- CountdownSoundServer
-- จัดการ broadcast เสียงนับถอยหลังให้ทุกคนได้ยินพร้อมกัน

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- สร้าง/หา RemoteEvent สำหรับ countdown sound
local rescueRemotes = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local countdownSoundRemote = rescueRemotes:FindFirstChild("CountdownSound")
if not countdownSoundRemote then
	countdownSoundRemote = Instance.new("RemoteEvent")
	countdownSoundRemote.Name = "CountdownSound"
	countdownSoundRemote.Parent = rescueRemotes
end

print("[CountdownSoundServer] Initialized")

-- รับสัญญาณจาก client และ broadcast ให้ทุกคน
countdownSoundRemote.OnServerEvent:Connect(function(player, action)
	if action == "start" then
		print("[CountdownSoundServer] Received start signal from", player.Name, "- Broadcasting to all clients")

		-- Broadcast ให้ทุกคนในเกม
		countdownSoundRemote:FireAllClients("start")
	elseif action == "stop" then
		print("[CountdownSoundServer] Received stop signal from", player.Name, "- Broadcasting to all clients")

		-- Broadcast ให้ทุกคนในเกม
		countdownSoundRemote:FireAllClients("stop")
	end
end)
