--!strict
-- RescueBotHealth.luau
-- จัดการ HP และ Battery ของ RescueBot

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GameConfig = require(script.Parent.GameConfig)
local GameSummary = require(script.Parent.GameSummary)

local rescueRemotes = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local victimRescueRemote = rescueRemotes:WaitForChild("VictimRescue")

local RescueBotHealth = {}
RescueBotHealth.__index = RescueBotHealth

type TimeoutCallback = (player: Player) -> ()

local function getReviveSettings()
	local settings = GameConfig.getRescueBotSettings()
	local reviveSettings = settings.revive or {}
	reviveSettings.sharePercent = math.clamp(reviveSettings.sharePercent or 0, 0, 1)
	reviveSettings.maxDistance = reviveSettings.maxDistance or 15
	reviveSettings.holdDuration = reviveSettings.holdDuration or 2
	return reviveSettings
end

export type RescueBotHealthType = {
	rescueModel: Model,
	currentHP: number,
	maxHP: number,
	currentBattery: number,
	maxBattery: number,
	_connections: { RBXScriptConnection },
	_batteryDrainConnection: RBXScriptConnection?,
	_lastBatteryUpdate: number?,
	_isDead: boolean,
	_crashEffect: Instance?,
	_revivePrompt: ProximityPrompt?,
	_revivePromptConnection: RBXScriptConnection?,
	_reviveInProgress: boolean,
	_callbacks: {
		onTimeout: TimeoutCallback?,
	}?,

	TakeDamage: (self: RescueBotHealthType, damage: number, damageType: string?) -> (),
	Heal: (self: RescueBotHealthType, amount: number) -> (),
	DrainBattery: (self: RescueBotHealthType, amount: number) -> (),
	ChargeBattery: (self: RescueBotHealthType, amount: number) -> (),
	GetHP: (self: RescueBotHealthType) -> (number, number),
	GetBattery: (self: RescueBotHealthType) -> (number, number),
	Reset: (self: RescueBotHealthType) -> (),
	Destroy: (self: RescueBotHealthType) -> (),
	StartBatteryDrain: (self: RescueBotHealthType, gameDuration: number) -> (),
	_setupCollisionDetection: (self: RescueBotHealthType) -> (),
	_setupRockDetection: (self: RescueBotHealthType) -> (),
	_startBatteryDrain: (self: RescueBotHealthType) -> (),
	_onDeath: (self: RescueBotHealthType) -> (),
	_explodeRescueBot: (self: RescueBotHealthType) -> ()
}

local function getOwnerPlayer(typedSelf: RescueBotHealthType): Player?
	local playerName = typedSelf.rescueModel.Name:gsub("_Rescue", "")
	return Players:FindFirstChild(playerName)
end

local function clearRevivePrompt(typedSelf: RescueBotHealthType)
	if typedSelf._revivePromptConnection then
		typedSelf._revivePromptConnection:Disconnect()
		typedSelf._revivePromptConnection = nil
	end

	if typedSelf._revivePrompt then
		typedSelf._revivePrompt:Destroy()
		typedSelf._revivePrompt = nil
	end

	typedSelf._reviveInProgress = false
end

local function handleReviveAttempt(typedSelf: RescueBotHealthType, rescuer: Player)
	if not rescuer then return end
	if not typedSelf._isDead then return end
	if typedSelf._reviveInProgress then return end

	local ownerPlayer = getOwnerPlayer(typedSelf)
	if not ownerPlayer or ownerPlayer == rescuer then
		return
	end

	local reviveSettings = getReviveSettings()
	local primaryPart = typedSelf.rescueModel.PrimaryPart
	local rescuerCharacter = rescuer.Character
	local rescuerRoot = rescuerCharacter and rescuerCharacter:FindFirstChild("HumanoidRootPart")
	if not (primaryPart and rescuerRoot and primaryPart:IsA("BasePart") and rescuerRoot:IsA("BasePart")) then
		return
	end
	local typedPrimaryPart = primaryPart :: BasePart
	local typedRescuerRoot = rescuerRoot :: BasePart

	local rescuerRescue = workspace:FindFirstChild(rescuer.Name .. "_Rescue")
	if rescuerRescue and rescuerRescue:GetAttribute("IsDown") then
		return
	end

	local distance = (typedRescuerRoot.Position - typedPrimaryPart.Position).Magnitude
	if distance > (reviveSettings.maxDistance or 15) then
		return
	end

	typedSelf._reviveInProgress = true
	if typedSelf._revivePrompt then
		typedSelf._revivePrompt.Enabled = false
	end

	local sharePercent = reviveSettings.sharePercent or 0
	local shareAmount = 0
	if sharePercent > 0 then
		local ownerCoins = GameSummary.getCoins(ownerPlayer)
		if ownerCoins > 0 then
			shareAmount = math.floor(ownerCoins * sharePercent)
			if shareAmount < 1 and ownerCoins > 0 then
				shareAmount = 1
			end
			if shareAmount > ownerCoins then
				shareAmount = ownerCoins
			end
		end
	end

	if shareAmount > 0 then
		GameSummary.addCoins(ownerPlayer, -shareAmount)
		GameSummary.addCoins(rescuer, shareAmount)

		if victimRescueRemote then
			victimRescueRemote:FireClient(rescuer, "reviveReward", shareAmount)
			victimRescueRemote:FireClient(ownerPlayer, "revivePenalty", shareAmount)
		end
	end

	print(string.format("[RescueBotHealth] %s revived %s (+%d coins)", rescuer.Name, ownerPlayer.Name, shareAmount))

	local success, err = pcall(function()
		typedSelf:Heal(typedSelf.maxHP)
	end)

	if not success then
		warn("[RescueBotHealth] Failed to heal after revive:", err)
		if typedSelf._revivePrompt then
			typedSelf._revivePrompt.Enabled = true
		end
	end

	typedSelf._reviveInProgress = false
end

local function createRevivePrompt(typedSelf: RescueBotHealthType)
	clearRevivePrompt(typedSelf)

	local primaryPart = typedSelf.rescueModel.PrimaryPart
	if not (primaryPart and primaryPart:IsA("BasePart")) then
		return
	end
	local typedPrimaryPart = primaryPart :: BasePart

	local reviveSettings = getReviveSettings()
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Revive Teammate"
	prompt.ObjectText = "Downed Teammate"
	prompt.KeyboardKeyCode = Enum.KeyCode.R
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
	prompt.HoldDuration = reviveSettings.holdDuration or 5
	prompt.MaxActivationDistance = reviveSettings.maxDistance or 15
	prompt.RequiresLineOfSight = false
	prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
	prompt.Enabled = true
	prompt.Parent = typedPrimaryPart

	print(`[RescueBotHealth] Created RevivePrompt on {typedSelf.rescueModel.Name} (HoldDuration: {prompt.HoldDuration}s, MaxDistance: {prompt.MaxActivationDistance})`)

	typedSelf._revivePrompt = prompt
	typedSelf._revivePromptConnection = prompt.Triggered:Connect(function(rescuer)
		handleReviveAttempt(typedSelf, rescuer)
	end)
end

-- สร้าง RescueBotHealth instance
type ConstructorOptions = {
	onTimeout: TimeoutCallback?,
}

function RescueBotHealth.new(rescueModel: Model, options: ConstructorOptions?): RescueBotHealthType
	local self = setmetatable({}, RescueBotHealth) :: any

	local botSettings = GameConfig.getRescueBotSettings()

	self.rescueModel = rescueModel
	self.currentHP = botSettings.maxHP
	self.maxHP = botSettings.maxHP

	-- เช็คว่ามี SolarCell ติดตั้งหรือไม่
	local hasSolarCell = false
	local solarCell = rescueModel:FindFirstChild("SolarCell", true)
	if solarCell then
		hasSolarCell = true
		print("[RescueBotHealth] SolarCell detected - Battery x2")
	end

	-- ถ้ามี SolarCell ให้ Battery เป็น 2 เท่า
	local batteryMultiplier = hasSolarCell and 2 or 1
	self.maxBattery = botSettings.maxBattery * batteryMultiplier
	self.currentBattery = self.maxBattery

	self._connections = {}
	self._isDead = false
	self._crashEffect = nil
	self._revivePrompt = nil
	self._revivePromptConnection = nil
	self._reviveInProgress = false

	rescueModel:SetAttribute("IsDown", false)
	self._callbacks = options and {
		onTimeout = options.onTimeout,
	} or nil

	-- เก็บ HP/Battery ใน Attributes
	rescueModel:SetAttribute("HP", self.currentHP)
	rescueModel:SetAttribute("MaxHP", self.maxHP)
	rescueModel:SetAttribute("Battery", self.currentBattery)
	rescueModel:SetAttribute("MaxBattery", self.maxBattery)

	-- ตรวจจับการชน (Collision Damage)
	self:_setupCollisionDetection()

	-- ตรวจจับหินที่ตกหรือกระเด็นใส่
	self:_setupRockDetection()

	-- Battery Drain (Idle) - แต่ยังไม่เริ่มทันที จะเริ่มเมื่อเกมเริ่ม
	-- self:_startBatteryDrain() -- ปิดไว้ก่อน จะเปิดเมื่อเกมเริ่มจริงๆ

	-- ตรวจสอบการ Revive ผ่าน Attribute
	local attributeConnection = rescueModel:GetAttributeChangedSignal("IsDown"):Connect(function()
		local isDown = rescueModel:GetAttribute("IsDown")
		if isDown == false and self._isDead then
			-- ถูก revive แล้ว
			self:_onRevived()
		end
	end)
	table.insert(self._connections, attributeConnection)

	-- Sync HP จาก Attribute (สำหรับ server-side revive)
	local hpConnection = rescueModel:GetAttributeChangedSignal("HP"):Connect(function()
		local newHP = rescueModel:GetAttribute("HP")
		if newHP and newHP > 0 and self._isDead then
			self.currentHP = newHP
			self._isDead = false
		end
	end)
	table.insert(self._connections, hpConnection)

	return self
end

-- ตั้งค่าตรวจจับการชนและหิน (รวมกันเพื่อลด lag)
function RescueBotHealth:_setupCollisionDetection()
	local typedSelf = self :: RescueBotHealthType
	local primaryPart = typedSelf.rescueModel.PrimaryPart
	if not primaryPart then return end

	local lastCollisionTime = 0
	local hitParts = {} -- เก็บ parts ที่โดนแล้ว
	local COLLISION_COOLDOWN = 1.0 -- วินาที

	local connection = primaryPart.Touched:Connect(function(hit: BasePart)
		if not hit.Parent then return end
		if hit:IsDescendantOf(typedSelf.rescueModel) then return end -- ข้าม part ของตัวเอง

		local currentTime = tick()

		-- ป้องกันโดนซ้ำจาก part เดิม
		local lastHitTime = hitParts[hit]
		if lastHitTime and currentTime - lastHitTime < 2 then
			return
		end

		local hitVelocity = hit.AssemblyLinearVelocity.Magnitude
		local selfVelocity = primaryPart.AssemblyLinearVelocity.Magnitude
		local hitMass = hit.AssemblyMass

		-- ตรวจจับหินกระเด็น/หล่น (part อื่นมี velocity สูง)
		if hitVelocity > 10 then
			local impactForce = hitMass * hitVelocity
			local damage = math.clamp(impactForce / 100, 1, 50) -- หาร 100 เพื่อให้ damage พอดี, สูงสุด 50 HP
			local damageType = hitVelocity > 80 and "Rock Falling (Heavy)" or "Rock Impact"
			typedSelf:TakeDamage(damage, damageType)
			hitParts[hit] = currentTime
		-- ตรวจจับการชนปกติ (ตัวเองมี velocity สูง)
		elseif selfVelocity > 50 and currentTime - lastCollisionTime >= COLLISION_COOLDOWN then
			typedSelf:TakeDamage(GameConfig.getRescueBotSettings().damage.heavyCollision, "Heavy Collision")
			lastCollisionTime = currentTime
		elseif selfVelocity > 20 and currentTime - lastCollisionTime >= COLLISION_COOLDOWN then
			typedSelf:TakeDamage(GameConfig.getRescueBotSettings().damage.collision, "Collision")
			lastCollisionTime = currentTime
		end
	end)

	table.insert(typedSelf._connections, connection)
end

-- ตั้งค่าตรวจจับหินที่ตก/กระเด็น (ใช้ connection เดียวกับ collision เพื่อลด lag)
function RescueBotHealth:_setupRockDetection()
	-- ไม่สร้าง Touched connection แยก จะรวมกับ _setupCollisionDetection แทน
	-- เพื่อลดจำนวน event listeners
end

-- เริ่ม Battery Drain (เรียกจาก server เมื่อเกมเริ่ม)
function RescueBotHealth:StartBatteryDrain(gameDuration)
	local typedSelf = self :: RescueBotHealthType

	-- ถ้า drain อยู่แล้วให้หยุดก่อน
	if typedSelf._batteryDrainConnection then
		typedSelf._batteryDrainConnection:Disconnect()
		typedSelf._batteryDrainConnection = nil
	end

	-- เช็คว่ามี SolarCell ติดตั้งหรือไม่
	local hasSolarCell = typedSelf.rescueModel:FindFirstChild("SolarCell", true) ~= nil
	local maxBattery = hasSolarCell and (GameConfig.RESCUE_BOT.maxBattery * 2) or GameConfig.RESCUE_BOT.maxBattery

	-- คำนวณ battery drain rates จากเวลาเกมจริง
	local drainRates = GameConfig.calculateBatteryDrain(gameDuration, maxBattery)

	print(string.format("[RescueBotHealth] Starting battery drain for %s - Duration: %ds, SolarCell: %s, MaxBattery: %d, Idle: %.3f/s",
		typedSelf.rescueModel.Name, gameDuration or 0, tostring(hasSolarCell), maxBattery, drainRates.idle))

	typedSelf._batteryDrainConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- Idle drain (ใช้ตลอดเวลา)
		typedSelf:DrainBattery(drainRates.idle * deltaTime)

		-- TODO: เพิ่มการตรวจสอบสถานะ moving และ drilling
		-- if isMoving then
		--     self:DrainBattery(drainRates.moving * deltaTime)
		-- end
		-- if isDrilling then
		--     self:DrainBattery(drainRates.drilling * deltaTime)
		-- end
	end)
end

-- เริ่ม Battery Drain (deprecated - ใช้ StartBatteryDrain แทน)
function RescueBotHealth:_startBatteryDrain()
	local typedSelf = self :: RescueBotHealthType

	-- ดึงข้อมูล player count และคำนวณ battery drain rate
	local playerCount = #Players:GetPlayers()

	-- เช็คว่ามี SolarCell ติดตั้งหรือไม่
	local hasSolarCell = typedSelf.rescueModel:FindFirstChild("SolarCell", true) ~= nil

	-- คำนวณ battery drain rates สำหรับโหมดปัจจุบัน
	local drainRates = GameConfig.getBatteryDrainForMode(playerCount, hasSolarCell)

	print(string.format("[RescueBotHealth] Battery drain rates for %d players (SolarCell: %s): Idle=%.3f/s, Moving=%.3f/s, Drilling=%.3f/s",
		playerCount, tostring(hasSolarCell), drainRates.idle, drainRates.moving, drainRates.drilling))

	typedSelf._batteryDrainConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- Idle drain (ใช้ตลอดเวลา)
		typedSelf:DrainBattery(drainRates.idle * deltaTime)

		-- TODO: เพิ่มการตรวจสอบสถานะ moving และ drilling
		-- if isMoving then
		--     self:DrainBattery(drainRates.moving * deltaTime)
		-- end
		-- if isDrilling then
		--     self:DrainBattery(drainRates.drilling * deltaTime)
		-- end
	end)
end

-- รับความเสียหาย
function RescueBotHealth:TakeDamage(damage: number, damageType: string?)
	local typedSelf = self :: RescueBotHealthType
	typedSelf.currentHP = math.max(0, typedSelf.currentHP - damage)
	typedSelf.rescueModel:SetAttribute("HP", typedSelf.currentHP)

	-- ลด logs เพื่อลด lag (แสดงเฉพาะเมื่อ HP ต่ำ)
	if typedSelf.currentHP <= 30 then
		warn(`[RescueBotHealth] LOW HP! {typedSelf.currentHP}/{typedSelf.maxHP} (-{damage} from {damageType or "Unknown"})`)
	end

	-- ส่ง event ไปยัง client เพื่ออัปเดต UI
	local remoteEvents = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
	if remoteEvents then
		local UpdateHP = remoteEvents:FindFirstChild("UpdateHP")
		if UpdateHP and UpdateHP:IsA("RemoteEvent") then
			-- หา player owner
			local playerName = typedSelf.rescueModel.Name:gsub("_Rescue", "")
			local Players = game:GetService("Players")
			local player = Players:FindFirstChild(playerName)

			if player then
				UpdateHP:FireClient(player, typedSelf.currentHP, typedSelf.maxHP)
			end
		end
	end

	-- ถ้า HP หมด
	if typedSelf.currentHP <= 0 and not typedSelf._isDead then
		typedSelf._isDead = true
		warn(`[RescueBotHealth] RescueBot DESTROYED!`)
		typedSelf:_onDeath()
	end
end

-- จัดการเมื่อ RescueBot ตาย
function RescueBotHealth:_onDeath()
	local typedSelf = self :: RescueBotHealthType

	-- หยุด Battery Drain
	if typedSelf._batteryDrainConnection then
		typedSelf._batteryDrainConnection:Disconnect()
		typedSelf._batteryDrainConnection = nil
	end

	-- ล็อคการเคลื่อนที่ (anchored)
	if typedSelf.rescueModel.PrimaryPart then
		typedSelf.rescueModel.PrimaryPart.Anchored = true
	end

	typedSelf.rescueModel:SetAttribute("IsDown", true)

	-- เพิ่ม CrashEffect
	local effectsFolder = ReplicatedStorage:FindFirstChild("Effects")
	if effectsFolder then
		local crashEffectTemplate = effectsFolder:FindFirstChild("CrashEffect")
		if crashEffectTemplate and typedSelf.rescueModel.PrimaryPart then
			local crashEffect = crashEffectTemplate:Clone()
			crashEffect.Parent = typedSelf.rescueModel.PrimaryPart
			typedSelf._crashEffect = crashEffect
		end
	end

	-- ปิดใช้งาน ClickDetector/ProximityPrompt ทั้งหมดใน RescueBot
	for _, descendant in ipairs(typedSelf.rescueModel:GetDescendants()) do
		if descendant:IsA("ClickDetector") then
			descendant.MaxActivationDistance = 0
		elseif descendant:IsA("ProximityPrompt") then
			descendant.Enabled = false
		end
	end

	-- ไม่ใช้ ProximityPrompt แล้ว ใช้ ReviveSystem.client.luau แทน

	-- ส่ง event ไป client เพื่อแสดง popup รอช่วยเหลือ
	local remoteEvents = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
	if remoteEvents then
		local botDeathEvent = remoteEvents:FindFirstChild("BotDeath")
		if not botDeathEvent then
			botDeathEvent = Instance.new("RemoteEvent")
			botDeathEvent.Name = "BotDeath"
			botDeathEvent.Parent = remoteEvents
		end

		-- หา player owner
		local playerName = typedSelf.rescueModel.Name:gsub("_Rescue", "")
		local Players = game:GetService("Players")
		local player = Players:FindFirstChild(playerName)

		if player then
			-- ส่งสัญญาณตายและซ่อน DrillProgressGui
			botDeathEvent:FireClient(player, "died")

			-- แจ้งเตือนผู้เล่นคนอื่นว่าเพื่อนล้ม (สำหรับแสดง Beam)
			local teammateDownRemote = remoteEvents:FindFirstChild("TeammateDown")
			if teammateDownRemote then
				-- ส่งให้ทุกคนยกเว้นผู้เล่นที่ล้ม
				for _, otherPlayer in pairs(Players:GetPlayers()) do
					if otherPlayer ~= player then
						teammateDownRemote:FireClient(otherPlayer, player, typedSelf.rescueModel)
						print(string.format("[RescueBotHealth] Notified %s that %s is down", otherPlayer.Name, player.Name))
					end
				end
			end

			-- เริ่มนับถอยหลัง 30 วินาที
			task.delay(30, function()
				-- ถ้ายังไม่ฟื้น (HP ยังเป็น 0) ให้สรุปคะแนนและระเบิด
				if typedSelf.currentHP <= 0 and typedSelf._isDead then
					-- ระเบิด RescueBot (ทำให้ชิ้นส่วนกระเด็นออกมา)
					typedSelf:_explodeRescueBot()

					botDeathEvent:FireClient(player, "timeout")

					warn(`[RescueBotHealth] Player {player.Name} timeout - RescueBot EXPLODED!`)

					-- รอ 3 วินาทีให้เห็นหุ่นกระจายก่อนแสดงสกอร์บอร์ด
					task.delay(3, function()
						-- Fire BotTimeout event เพื่อให้ server handler แสดงสกอร์บอร์ด
						local botTimeoutEvent = remoteEvents:FindFirstChild("BotTimeout")
						if botTimeoutEvent and botTimeoutEvent:IsA("BindableEvent") then
							botTimeoutEvent:Fire(player)
							print(`[RescueBotHealth] Showing scoreboard after explosion for {player.Name}`)
						end
					end)
				end
			end)
		end
	end
end

-- จัดการเมื่อถูก Revive
function RescueBotHealth:_onRevived()
	local typedSelf = self :: RescueBotHealthType

	print(`[RescueBotHealth] {typedSelf.rescueModel.Name} has been revived!`)

	-- Reset ค่า
	typedSelf._isDead = false
	typedSelf.rescueModel:SetAttribute("IsDown", false)

	-- ยกเลิก Anchor
	if typedSelf.rescueModel.PrimaryPart then
		typedSelf.rescueModel.PrimaryPart.Anchored = false
	end

	-- ลบ CrashEffect
	if typedSelf._crashEffect then
		typedSelf._crashEffect:Destroy()
		typedSelf._crashEffect = nil
	end

	-- เปิดใช้งาน ProximityPrompt กลับ
	for _, descendant in ipairs(typedSelf.rescueModel:GetDescendants()) do
		if descendant:IsA("ProximityPrompt") then
			descendant.Enabled = true
		elseif descendant:IsA("ClickDetector") then
			descendant.MaxActivationDistance = 32
		end
	end

	-- เริ่ม Battery Drain ใหม่ (ถ้าถูกหยุดไว้)
	-- ปิดไว้เพราะ battery drain จะถูกจัดการจาก server ผ่าน StartBatteryDrain
	-- if not typedSelf._batteryDrainConnection then
	-- 	typedSelf:_startBatteryDrain()
	-- end
end

-- ฟื้น HP
function RescueBotHealth:Heal(amount: number)
	local typedSelf = self :: RescueBotHealthType
	typedSelf.currentHP = math.min(typedSelf.maxHP, typedSelf.currentHP + amount)
	typedSelf.rescueModel:SetAttribute("HP", typedSelf.currentHP)

	-- ถ้าฟื้นจากตาย
	if typedSelf._isDead and typedSelf.currentHP > 0 then
		typedSelf._isDead = false
		typedSelf.rescueModel:SetAttribute("IsDown", false)
		clearRevivePrompt(typedSelf)
		typedSelf._reviveInProgress = false

		-- ปลดล็อคการเคลื่อนที่
		if typedSelf.rescueModel.PrimaryPart then
			typedSelf.rescueModel.PrimaryPart.Anchored = false
		end

		-- ลบ CrashEffect
		if typedSelf._crashEffect then
			typedSelf._crashEffect:Destroy()
			typedSelf._crashEffect = nil
		end

		-- เริ่ม Battery Drain ใหม่
		-- ปิดไว้เพราะ battery drain จะถูกจัดการจาก server ผ่าน StartBatteryDrain
		-- typedSelf:_startBatteryDrain()

		-- ส่ง event บอก client ว่าฟื้นแล้ว
		local remoteEvents = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
		if remoteEvents then
			local botDeathEvent = remoteEvents:FindFirstChild("BotDeath")
			if botDeathEvent then
				local playerName = typedSelf.rescueModel.Name:gsub("_Rescue", "")
				local Players = game:GetService("Players")
				local player = Players:FindFirstChild(playerName)

				if player then
					botDeathEvent:FireClient(player, "revived")
				end
			end
		end

		warn(`[RescueBotHealth] RescueBot REVIVED!`)
	end
end

-- ใช้แบตเตอรี่
function RescueBotHealth:DrainBattery(amount: number)
	local typedSelf = self :: RescueBotHealthType
	typedSelf.currentBattery = math.max(0, typedSelf.currentBattery - amount)
	typedSelf.rescueModel:SetAttribute("Battery", typedSelf.currentBattery)

	-- ส่ง event ไปยัง client (ทุก 0.5 วินาที)
	if not typedSelf._lastBatteryUpdate or tick() - typedSelf._lastBatteryUpdate >= 0.5 then
		typedSelf._lastBatteryUpdate = tick()

		local remoteEvents = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
		if remoteEvents then
			local UpdateBattery = remoteEvents:FindFirstChild("UpdateBattery")
			if UpdateBattery and UpdateBattery:IsA("RemoteEvent") then
				local playerName = typedSelf.rescueModel.Name:gsub("_Rescue", "")
				local Players = game:GetService("Players")
				local player = Players:FindFirstChild(playerName)

				if player then
					UpdateBattery:FireClient(player, typedSelf.currentBattery, typedSelf.maxBattery)
				end
			end
		end
	end

	-- ถ้า Battery หมด ให้ตายเหมือน HP หมด
	if typedSelf.currentBattery <= 0 and not typedSelf._isDead then
		typedSelf._isDead = true
		warn("[RescueBotHealth] Battery depleted - RescueBot SHUTDOWN!")
		typedSelf:_onDeath()
	end
end

-- ชาร์จแบตเตอรี่
function RescueBotHealth:ChargeBattery(amount: number)
	local typedSelf = self :: RescueBotHealthType
	typedSelf.currentBattery = math.min(typedSelf.maxBattery, typedSelf.currentBattery + amount)
	typedSelf.rescueModel:SetAttribute("Battery", typedSelf.currentBattery)
end

-- ดึงค่า HP
function RescueBotHealth:GetHP(): (number, number)
	local typedSelf = self :: RescueBotHealthType
	return typedSelf.currentHP, typedSelf.maxHP
end

-- ดึงค่า Battery
function RescueBotHealth:GetBattery(): (number, number)
	local typedSelf = self :: RescueBotHealthType
	return typedSelf.currentBattery, typedSelf.maxBattery
end

-- Reset HP และ Battery เป็นค่าเต็ม
function RescueBotHealth:Reset()
	local typedSelf = self :: RescueBotHealthType
	typedSelf.currentHP = typedSelf.maxHP
	typedSelf.currentBattery = typedSelf.maxBattery
	typedSelf._isDead = false
	typedSelf.rescueModel:SetAttribute("IsDown", false)
	clearRevivePrompt(typedSelf)
	typedSelf._reviveInProgress = false

	-- ลบ CrashEffect ถ้ามี
	if typedSelf._crashEffect then
		typedSelf._crashEffect:Destroy()
		typedSelf._crashEffect = nil
	end

	-- ปลดล็อคการเคลื่อนที่
	if typedSelf.rescueModel.PrimaryPart then
		typedSelf.rescueModel.PrimaryPart.Anchored = false
	end

	typedSelf.rescueModel:SetAttribute("HP", typedSelf.currentHP)
	typedSelf.rescueModel:SetAttribute("Battery", typedSelf.currentBattery)

	-- ส่ง update ไปยัง client
	local remoteEvents = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
	if remoteEvents then
		local UpdateHP = remoteEvents:FindFirstChild("UpdateHP")
		local UpdateBattery = remoteEvents:FindFirstChild("UpdateBattery")

		local playerName = typedSelf.rescueModel.Name:gsub("_Rescue", "")
		local player = Players:FindFirstChild(playerName)

		if player then
			if UpdateHP and UpdateHP:IsA("RemoteEvent") then
				UpdateHP:FireClient(player, typedSelf.currentHP, typedSelf.maxHP)
			end
			if UpdateBattery and UpdateBattery:IsA("RemoteEvent") then
				UpdateBattery:FireClient(player, typedSelf.currentBattery, typedSelf.maxBattery)
			end
		end
	end

	-- ลด log
end

-- ระเบิด RescueBot (ทำให้ชิ้นส่วนกระเด็นออกมา)
function RescueBotHealth:_explodeRescueBot()
	local typedSelf = self :: RescueBotHealthType
	local rescueModel = typedSelf.rescueModel

	if not rescueModel then
		return
	end

	print("[RescueBotHealth] Exploding RescueBot:", rescueModel.Name)

	-- ลบ weld/motor6D/attachment ทั้งหมดเพื่อให้ชิ้นส่วนแยกออก
	for _, descendant in ipairs(rescueModel:GetDescendants()) do
		if descendant:IsA("Weld") or descendant:IsA("Motor6D") or descendant:IsA("WeldConstraint") or descendant:IsA("Attachment") then
			descendant:Destroy()
		end
	end

	-- ทำให้ทุก part กระเด็นออกมา (ปรับให้ตกเร็วขึ้น ไม่ลอย)
	local centerPosition = rescueModel.PrimaryPart and rescueModel.PrimaryPart.Position or rescueModel:GetPivot().Position
	local explosionForce = 35 -- แรงระเบิด (ลดจาก 100 เป็น 35 เพื่อให้ตกเร็วขึ้น)
	local groundY = centerPosition.Y -- เก็บ Y ของพื้น

	for _, descendant in ipairs(rescueModel:GetDescendants()) do
		if descendant:IsA("BasePart") and not descendant:IsA("Seat") then
			-- Unanchor
			descendant.Anchored = false
			descendant.CanCollide = true

			-- ตั้งค่า physics properties (เพิ่มมวลและ friction เพื่อให้ตกเร็วขึ้น)
			pcall(function()
				descendant.CustomPhysicalProperties = PhysicalProperties.new(
					0.7,  -- Density (เพิ่มจาก 0.5 เป็น 0.7 เพื่อให้หนักขึ้น)
					0.3,  -- Friction (ลดจาก 0.5 เป็น 0.3)
					0.1,  -- Elasticity (ลดจาก 0.3 เป็น 0.1 เพื่อลดการเด้ง)
					1,    -- FrictionWeight
					1     -- ElasticityWeight
				)
			end)

			-- คำนวณทิศทางกระเด็นออกจากศูนย์กลาง (ลดแรงขึ้น)
			local direction = (descendant.Position - centerPosition).Unit
			local randomOffset = Vector3.new(
				math.random(-30, 30) / 100, -- ลดจาก -50,50
				math.random(5, 20) / 100,   -- ลดจาก 10-50 เป็น 5-20 (กระเด็นขึ้นน้อยลง)
				math.random(-30, 30) / 100  -- ลดจาก -50,50
			)
			local finalDirection = (direction + randomOffset).Unit

			-- ใช้ AssemblyLinearVelocity (ลดแรงกระเด็น)
			local horizontalForce = Vector3.new(finalDirection.X, 0, finalDirection.Z).Unit * explosionForce
			local verticalForce = Vector3.new(0, math.random(10, 25), 0) -- ลดจาก 30-60 เป็น 10-25
			descendant.AssemblyLinearVelocity = horizontalForce + verticalForce

			-- ให้หมุนสุ่ม (ลดลง)
			descendant.AssemblyAngularVelocity = Vector3.new(
				math.random(-8, 8),  -- ลดจาก -15,15
				math.random(-8, 8),
				math.random(-8, 8)
			)

			-- SetNetworkOwnershipAuto เพื่อลด lag
			pcall(function()
				descendant:SetNetworkOwnershipAuto()
			end)

			-- ลบการใช้ task.delay เพื่อหยุด velocity (ให้ตกตามธรรมชาติ)
		end
	end

	-- ใช้ Debris Service เพื่อลบชิ้นส่วนหลังจาก 10 วินาที
	local Debris = game:GetService("Debris")
	for _, descendant in ipairs(rescueModel:GetDescendants()) do
		if descendant:IsA("BasePart") then
			Debris:AddItem(descendant, 10)
		end
	end

	-- ลบ model หลังจาก 10 วินาที
	Debris:AddItem(rescueModel, 10)
	print("[RescueBotHealth] RescueBot explosion complete - will be removed in 10 seconds")
end

-- ทำลาย instance
function RescueBotHealth:Destroy()
	-- ตัด connections
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end

	if self._batteryDrainConnection then
		self._batteryDrainConnection:Disconnect()
	end

	clearRevivePrompt(self :: RescueBotHealthType)

	table.clear(self)
end

return RescueBotHealth
