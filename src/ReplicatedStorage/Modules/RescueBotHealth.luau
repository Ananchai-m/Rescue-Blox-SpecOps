--!strict
-- RescueBotHealth.luau
-- จัดการ HP และ Battery ของ RescueBot

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.GameConfig)

local RescueBotHealth = {}
RescueBotHealth.__index = RescueBotHealth

type TimeoutCallback = (player: Player) -> ()

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
	_setupCollisionDetection: (self: RescueBotHealthType) -> (),
	_setupRockDetection: (self: RescueBotHealthType) -> (),
	_startBatteryDrain: (self: RescueBotHealthType) -> (),
	_onDeath: (self: RescueBotHealthType) -> ()
}

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
	self.currentBattery = botSettings.maxBattery
	self.maxBattery = botSettings.maxBattery
	self._connections = {}
	self._isDead = false
	self._crashEffect = nil
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

	-- Battery Drain (Idle)
	self:_startBatteryDrain()

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

-- เริ่ม Battery Drain
function RescueBotHealth:_startBatteryDrain()
	local botSettings = GameConfig.getRescueBotSettings()

	self._batteryDrainConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- Idle drain
		self:DrainBattery(botSettings.batteryDrain.idle * deltaTime)

		-- TODO: เพิ่มการตรวจสอบสถานะ moving และ drilling
		-- if isMoving then
		--     self:DrainBattery(botSettings.batteryDrain.moving * deltaTime)
		-- end
		-- if isDrilling then
		--     self:DrainBattery(botSettings.batteryDrain.drilling * deltaTime)
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

			-- เริ่มนับถอยหลัง 30 วินาที
			task.delay(30, function()
				-- ถ้ายังไม่ฟื้น (HP ยังเป็น 0) ให้สรุปคะแนน
				if typedSelf.currentHP <= 0 and typedSelf._isDead then
					botDeathEvent:FireClient(player, "timeout")

					-- แจ้ง callback เพื่อให้ server จัดการ timeout flow
					if typedSelf._callbacks and typedSelf._callbacks.onTimeout then
						typedSelf._callbacks.onTimeout(player)
					end

					warn(`[RescueBotHealth] Player {player.Name} timeout - requesting summary`)
				end
			end)
		end
	end
end

-- ฟื้น HP
function RescueBotHealth:Heal(amount: number)
	local typedSelf = self :: RescueBotHealthType
	typedSelf.currentHP = math.min(typedSelf.maxHP, typedSelf.currentHP + amount)
	typedSelf.rescueModel:SetAttribute("HP", typedSelf.currentHP)

	-- ถ้าฟื้นจากตาย
	if typedSelf._isDead and typedSelf.currentHP > 0 then
		typedSelf._isDead = false

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
		typedSelf:_startBatteryDrain()

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
		local Players = game:GetService("Players")
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

-- ทำลาย instance
function RescueBotHealth:Destroy()
	-- ตัด connections
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end

	if self._batteryDrainConnection then
		self._batteryDrainConnection:Disconnect()
	end

	table.clear(self)
end

return RescueBotHealth
