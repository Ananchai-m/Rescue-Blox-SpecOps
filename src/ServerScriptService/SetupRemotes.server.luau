--!strict
-- SetupRemotes.server.luau
-- สร้าง RemoteEvents ที่จำเป็นสำหรับระบบต่างๆ

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- สร้าง RescueBotRemotes folder
local rescueBotRemotes = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
if not rescueBotRemotes then
	rescueBotRemotes = Instance.new("Folder")
	rescueBotRemotes.Name = "RescueBotRemotes"
	rescueBotRemotes.Parent = ReplicatedStorage
end

-- สร้าง RemoteEvents ที่จำเป็น
local remoteEventNames = {
	"UpdateHP",
	"UpdateBattery",
	"BotDeath",
	"DebugModifyHP",
	"ReviveTeammate", -- ช่วยเหลือเพื่อนที่พัง
}

for _, eventName in ipairs(remoteEventNames) do
	if not rescueBotRemotes:FindFirstChild(eventName) then
		local remoteEvent = Instance.new("RemoteEvent")
		remoteEvent.Name = eventName
		remoteEvent.Parent = rescueBotRemotes
		print(`[SetupRemotes] Created RemoteEvent: {eventName}`)
	end
end

-- สร้าง BindableEvent สำหรับ server-to-server (BotTimeout)
if not rescueBotRemotes:FindFirstChild("BotTimeout") then
	local bindableEvent = Instance.new("BindableEvent")
	bindableEvent.Name = "BotTimeout"
	bindableEvent.Parent = rescueBotRemotes
	print(`[SetupRemotes] Created BindableEvent: BotTimeout`)
end

print("[SetupRemotes] All RescueBot RemoteEvents are ready")
