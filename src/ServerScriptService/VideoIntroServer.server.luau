--!strict
-- VideoIntroServer.server.luau
-- จัดการ VideoIntro ผ่าน ProfileService

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

-- ใช้ Shared ProfileService instance (ต้องใช้ตัวเดียวกับ ProfileManager)
local profileService = require(ServerScriptService.SharedProfileService)

-- สร้าง RemoteFunction และ RemoteEvent
local remoteFolder = ReplicatedStorage:WaitForChild("RescueBotRemotes")

local checkWatchedFunction = Instance.new("RemoteFunction")
checkWatchedFunction.Name = "CheckWatchedIntro"
checkWatchedFunction.Parent = remoteFolder

local markWatchedEvent = Instance.new("RemoteEvent")
markWatchedEvent.Name = "MarkWatchedIntro"
markWatchedEvent.Parent = remoteFolder

-- ฟังก์ชันเช็คว่าผู้เล่นดูวิดีโอแล้วหรือยัง
checkWatchedFunction.OnServerInvoke = function(player: Player): boolean
	-- รอ Profile โหลดเสร็จก่อน (สูงสุด 10 วินาที)
	local profile = profileService:GetProfile(player)
	local attempts = 0
	local maxAttempts = 100 -- 100 * 0.1 = 10 วินาที

	while not profile and attempts < maxAttempts do
		task.wait(0.1)
		profile = profileService:GetProfile(player)
		attempts += 1
	end

	if not profile then
		warn("[VideoIntroServer] Profile not found for", player.Name, "after", maxAttempts * 0.1, "seconds")
		return false
	end

	-- ถ้ายังไม่เคยตั้งค่า ให้ return false (ครั้งแรก)
	local hasWatched = profile.meta.hasWatchedIntro
	if hasWatched == nil then
		print("[VideoIntroServer] First time for", player.Name, "- hasWatchedIntro is nil")
		return false
	end

	print("[VideoIntroServer] Check watched for", player.Name, "=", hasWatched)
	return hasWatched
end

-- ฟังก์ชันบันทึกว่าผู้เล่นดูวิดีโอแล้ว
markWatchedEvent.OnServerEvent:Connect(function(player: Player)
	-- รอ Profile โหลดเสร็จก่อน (สูงสุด 10 วินาที)
	local profile = profileService:GetProfile(player)
	local attempts = 0
	local maxAttempts = 100

	while not profile and attempts < maxAttempts do
		task.wait(0.1)
		profile = profileService:GetProfile(player)
		attempts += 1
	end

	if not profile then
		warn("[VideoIntroServer] Profile not found for", player.Name, "after", maxAttempts * 0.1, "seconds")
		return
	end

	-- บันทึกว่าดูแล้ว
	profile.meta.hasWatchedIntro = true
	print("[VideoIntroServer] Marked as watched for", player.Name)

	-- Save profile
	local success = profileService:SaveProfile(player)
	if success then
		print("[VideoIntroServer] Saved hasWatchedIntro for", player.Name)
	else
		warn("[VideoIntroServer] Failed to save hasWatchedIntro for", player.Name)
	end
end)

print("[VideoIntroServer] Initialized")
