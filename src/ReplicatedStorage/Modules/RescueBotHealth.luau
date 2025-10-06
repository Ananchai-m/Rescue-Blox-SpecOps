--!strict
-- RescueBotHealth.luau
-- จัดการ HP และ Battery ของ RescueBot

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GameConfig = require(script.Parent.GameConfig)

local RescueBotHealth = {}
RescueBotHealth.__index = RescueBotHealth

export type RescueBotHealthType = {
	rescueModel: Model,
	currentHP: number,
	maxHP: number,
	currentBattery: number,
	maxBattery: number,
	_connections: { RBXScriptConnection },
	_batteryDrainConnection: RBXScriptConnection?,
	_lastBatteryUpdate: number?,

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
	_startBatteryDrain: (self: RescueBotHealthType) -> ()
}

-- สร้าง RescueBotHealth instance
function RescueBotHealth.new(rescueModel: Model): RescueBotHealthType
	local self = setmetatable({}, RescueBotHealth) :: any

	local botSettings = GameConfig.getRescueBotSettings()

	self.rescueModel = rescueModel
	self.currentHP = botSettings.maxHP
	self.maxHP = botSettings.maxHP
	self.currentBattery = botSettings.maxBattery
	self.maxBattery = botSettings.maxBattery
	self._connections = {}

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
	if not self.rescueModel.PrimaryPart then return end

	local primaryPart = self.rescueModel.PrimaryPart
	local lastCollisionTime = 0
	local hitParts = {} -- เก็บ parts ที่โดนแล้ว
	local COLLISION_COOLDOWN = 1.0 -- วินาที

	local connection = primaryPart.Touched:Connect(function(hit)
		if not hit or not hit.Parent then return end
		if hit:IsDescendantOf(self.rescueModel) then return end -- ข้าม part ของตัวเอง

		local currentTime = tick()

		-- ป้องกันโดนซ้ำจาก part เดิม
		if hitParts[hit] and currentTime - hitParts[hit] < 2 then
			return
		end

		local hitVelocity = hit.AssemblyLinearVelocity.Magnitude
		local selfVelocity = primaryPart.AssemblyLinearVelocity.Magnitude

		-- ตรวจจับหินกระเด็น/หล่น (part อื่นมี velocity สูง)
		if hitVelocity > 80 then
			-- หินหล่นทับ
			self:TakeDamage(GameConfig.getRescueBotSettings().damage.rockFalling, "Rock Falling")
			hitParts[hit] = currentTime
		elseif hitVelocity > 30 then
			-- หินกระเด็น
			self:TakeDamage(GameConfig.getRescueBotSettings().damage.rockBounce, "Rock Bounce")
			hitParts[hit] = currentTime
		-- ตรวจจับการชนปกติ (ตัวเองมี velocity สูง)
		elseif selfVelocity > 50 and currentTime - lastCollisionTime >= COLLISION_COOLDOWN then
			-- ชนแรง
			self:TakeDamage(GameConfig.getRescueBotSettings().damage.heavyCollision, "Heavy Collision")
			lastCollisionTime = currentTime
		elseif selfVelocity > 20 and currentTime - lastCollisionTime >= COLLISION_COOLDOWN then
			-- ชนเบา
			self:TakeDamage(GameConfig.getRescueBotSettings().damage.collision, "Collision")
			lastCollisionTime = currentTime
		end
	end)

	table.insert(self._connections, connection)
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
	if typedSelf.currentHP <= 0 then
		warn(`[RescueBotHealth] RescueBot DESTROYED!`)
		-- TODO: ทำลาย RescueBot หรือ respawn
	end
end

-- ฟื้น HP
function RescueBotHealth:Heal(amount: number)
	local typedSelf = self :: RescueBotHealthType
	typedSelf.currentHP = math.min(typedSelf.maxHP, typedSelf.currentHP + amount)
	typedSelf.rescueModel:SetAttribute("HP", typedSelf.currentHP)
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
