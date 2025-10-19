-- MissionResultHandler Client Script
-- จัดการรับสัญญาณผลการช่วยเหลือจาก Server และเล่นเสียง

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GameSummary = require(ReplicatedStorage.Modules.GameSummary)

-- รับ RemoteEvent
local rescueRemotes = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local missionResultRemote = rescueRemotes:WaitForChild("MissionResult")

local missionSound = nil

-- รับสัญญาณผลการช่วยเหลือจาก Server
missionResultRemote.OnClientEvent:Connect(function(isSuccess, soundId, message)
	-- ตั้งค่าผลการช่วยเหลือใน GameSummary
	GameSummary.setMissionResult(isSuccess, message)

	-- เล่นเสียงผลการช่วยเหลือ
	if missionSound then
		missionSound:Stop()
		missionSound:Destroy()
	end

	missionSound = Instance.new("Sound")
	missionSound.SoundId = "rbxassetid://" .. soundId
	missionSound.Volume = 0.7
	missionSound.Parent = SoundService
	missionSound:Play()

	print(string.format("[MissionResultHandler] Received mission result: %s (Sound: %s)", message, soundId))
end)

print("[MissionResultHandler] Client script loaded")
