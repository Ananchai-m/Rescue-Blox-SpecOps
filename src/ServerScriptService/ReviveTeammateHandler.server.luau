--!strict
-- ReviveTeammateHandler.server.luau
-- จัดการ Revive เพื่อน RescueBot ที่พัง

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local GameSummary = require(ReplicatedStorage.Modules.GameSummary)

local reviveSettings = GameConfig.getRescueBotSettings().revive
local MAX_DISTANCE = reviveSettings.maxDistance or 15
local SHARE_PERCENT = reviveSettings.sharePercent or 0.3

-- RemoteEvent
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local reviveRemote = remoteEvents:WaitForChild("ReviveTeammate")

reviveRemote.OnServerEvent:Connect(function(rescuer: Player, downedBotModel: Model)
	if not rescuer or not downedBotModel then
		return
	end

	-- ตรวจสอบว่า downedBot เป็น RescueBot จริง
	if not downedBotModel:IsA("Model") or not downedBotModel.Name:match("_Rescue$") then
		warn("[ReviveTeammate] Invalid model:", downedBotModel.Name)
		return
	end

	-- ตรวจสอบว่าพังจริง
	local isDown = downedBotModel:GetAttribute("IsDown")
	if not isDown then
		warn("[ReviveTeammate] Bot is not downed:", downedBotModel.Name)
		return
	end

	-- หา owner ของ downedBot
	local ownerName = downedBotModel.Name:gsub("_Rescue", "")
	local owner = game.Players:FindFirstChild(ownerName)
	if not owner then
		warn("[ReviveTeammate] Owner not found:", ownerName)
		return
	end

	-- ไม่ให้ revive ตัวเอง
	if rescuer == owner then
		warn("[ReviveTeammate] Cannot revive yourself")
		return
	end

	-- ตรวจสอบระยะทาง
	local rescuerBot = workspace:FindFirstChild(rescuer.Name .. "_Rescue")
	if not rescuerBot or not rescuerBot.PrimaryPart or not downedBotModel.PrimaryPart then
		warn("[ReviveTeammate] Missing PrimaryPart")
		return
	end

	local distance = (rescuerBot.PrimaryPart.Position - downedBotModel.PrimaryPart.Position).Magnitude
	if distance > MAX_DISTANCE then
		warn("[ReviveTeammate] Too far:", distance, "studs")
		return
	end

	print(`[ReviveTeammate] {rescuer.Name} is reviving {owner.Name}`)

	-- คำนวณ HP ที่จะโอน (30% จากผู้ช่วย)
	local maxHP = GameConfig.getRescueBotSettings().maxHP
	local rescuerCurrentHP = rescuerBot:GetAttribute("HP") or maxHP
	local transferHP = math.floor(rescuerCurrentHP * SHARE_PERCENT)

	-- ตรวจสอบว่าผู้ช่วยมี HP เพียงพอหรือไม่
	if transferHP <= 0 or rescuerCurrentHP <= 0 then
		warn(`[ReviveTeammate] {rescuer.Name} doesn't have enough HP to revive`)
		return
	end

	-- หัก HP จากผู้ช่วย (เหลืออย่างน้อย 1 HP)
	local newRescuerHP = math.max(1, rescuerCurrentHP - transferHP)
	rescuerBot:SetAttribute("HP", newRescuerHP)

	-- ส่ง update HP ไป client ของผู้ช่วย
	local updateHPEvent = remoteEvents:FindFirstChild("UpdateHP")
	if updateHPEvent then
		updateHPEvent:FireClient(rescuer, newRescuerHP, maxHP)
	end

	-- ฟื้นคนพังด้วย HP ที่ได้จากผู้ช่วย
	downedBotModel:SetAttribute("HP", transferHP)
	downedBotModel:SetAttribute("IsDown", false)

	-- ส่ง update HP ไป client ของคนที่ถูกช่วย
	if updateHPEvent and owner then
		updateHPEvent:FireClient(owner, transferHP, maxHP)
	end

	-- ผู้ช่วยได้ 5 coins
	local REVIVE_REWARD = 5
	GameSummary.addCoins(rescuer, REVIVE_REWARD)

	-- ส่ง event ไปแสดง coin animation
	local victimRescueRemote = remoteEvents:FindFirstChild("VictimRescue")
	if victimRescueRemote and downedBotModel.PrimaryPart then
		victimRescueRemote:FireClient(rescuer, "coinCollected", REVIVE_REWARD, downedBotModel.PrimaryPart.Position)
	end

	print(`[ReviveTeammate] {rescuer.Name} transferred {transferHP} HP to {owner.Name} (Rescuer: {newRescuerHP}/{maxHP}, Revived: {transferHP}/{maxHP}) + {REVIVE_REWARD} coins`)

	-- ยกเลิก Anchor
	if downedBotModel.PrimaryPart then
		downedBotModel.PrimaryPart.Anchored = false
	end

	-- ลบ CrashEffect
	local crashEffect = downedBotModel.PrimaryPart:FindFirstChild("CrashEffect")
	if crashEffect then
		crashEffect:Destroy()
	end

	-- ส่งสัญญาณ revived ไปยัง client
	local botDeathEvent = remoteEvents:FindFirstChild("BotDeath")
	if botDeathEvent then
		botDeathEvent:FireClient(owner, "revived")
	end

	print(`[ReviveTeammate] {owner.Name} has been revived by {rescuer.Name}`)
end)

print("[ReviveTeammateHandler] Initialized")
