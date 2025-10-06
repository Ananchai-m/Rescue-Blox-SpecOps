--!strict
-- ProfileService.luau
-- Service สำหรับจัดการ DataStore ของ PlayerProfile

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ProfileTemplate = require(script.Parent.ProfileTemplate)
type PlayerProfile = ProfileTemplate.PlayerProfile

local ProfileService = {}
ProfileService.__index = ProfileService

-- Configuration
local IS_PRODUCTION = false -- เปลี่ยนเป็น true เมื่อ publish
local DATASTORE_NAME = IS_PRODUCTION and "PlayerProfiles_Release" or "PlayerProfiles_Dev"
local AUTO_SAVE_INTERVAL = 300 -- 5 นาที

type ProfileServiceType = {
	_profiles: { [number]: PlayerProfile },
	_dataStore: DataStore,
	_autoSaveRunning: boolean,
	GetProfile: (self: ProfileServiceType, player: Player) -> PlayerProfile?,
	SaveProfile: (self: ProfileServiceType, player: Player) -> boolean,
	LoadProfile: (self: ProfileServiceType, player: Player) -> PlayerProfile?,
	RemoveProfile: (self: ProfileServiceType, player: Player) -> (),
	UpdateLastSeen: (self: ProfileServiceType, player: Player) -> (),

	-- Update helpers
	AddCoins: (self: ProfileServiceType, player: Player, amount: number) -> boolean,
	RemoveCoins: (self: ProfileServiceType, player: Player, amount: number) -> boolean,
	AddXP: (self: ProfileServiceType, player: Player, amount: number) -> (),
	SetBotColor: (self: ProfileServiceType, player: Player, part: string, color: string) -> (),
	AddRescue: (self: ProfileServiceType, player: Player) -> (),
	UpdateMission: (self: ProfileServiceType, player: Player, missionId: string, state: string, bestTime: number?) -> (),
	UpdateBestTime: (self: ProfileServiceType, player: Player, buildingId: string, time: number) -> (),
	EquipItem: (self: ProfileServiceType, player: Player, itemId: string) -> boolean,
	UnequipItem: (self: ProfileServiceType, player: Player, itemId: string) -> boolean,
	AddItem: (self: ProfileServiceType, player: Player, itemId: string, slotCost: number, tier: number, uses: number?) -> (),

	_startAutoSave: (self: ProfileServiceType) -> (),
	_stopAutoSave: (self: ProfileServiceType) -> ()
}

function ProfileService.new(): ProfileServiceType
	local self = setmetatable({}, ProfileService) :: any

	self._profiles = {}
	self._dataStore = DataStoreService:GetDataStore(DATASTORE_NAME)
	self._autoSaveRunning = false

	return self
end

-- ดึง Profile ของผู้เล่น (จาก cache)
function ProfileService:GetProfile(player: Player): PlayerProfile?
	return self._profiles[player.UserId]
end

-- โหลด Profile จาก DataStore
function ProfileService:LoadProfile(player: Player): PlayerProfile?
	local key = `player_{player.UserId}`
	local success, result = pcall(function()
		return self._dataStore:GetAsync(key)
	end)

	if not success then
		warn(`[ProfileService] Failed to load profile for {player.Name}: {result}`)
		return nil
	end

	local profile: PlayerProfile

	if result then
		-- มีข้อมูลอยู่แล้ว ใช้ข้อมูลเก่า
		profile = result :: PlayerProfile

		-- อัพเดทข้อมูล identity และ lastSeenAt
		profile.identity.name = player.Name
		profile.identity.displayName = player.DisplayName
		profile.meta.lastSeenAt = os.time()
	else
		-- ไม่มีข้อมูล สร้างใหม่
		profile = ProfileTemplate.new(player)
		print(`[ProfileService] Created new profile for {player.Name}`)
	end

	-- เก็บใน cache
	self._profiles[player.UserId] = profile

	return profile
end

-- บันทึก Profile ไปยัง DataStore
function ProfileService:SaveProfile(player: Player): boolean
	local profile = self._profiles[player.UserId]

	if not profile then
		warn(`[ProfileService] No profile found for {player.Name}`)
		return false
	end

	-- อัพเดท lastSeenAt ก่อนบันทึก
	profile.meta.lastSeenAt = os.time()

	local key = `player_{player.UserId}`
	local success, err = pcall(function()
		self._dataStore:SetAsync(key, profile)
	end)

	if not success then
		warn(`[ProfileService] Failed to save profile for {player.Name}: {err}`)
		return false
	end

	print(`[ProfileService] Saved profile for {player.Name}`)
	return true
end

-- ลบ Profile จาก cache (เรียกตอน player ออก)
function ProfileService:RemoveProfile(player: Player)
	self._profiles[player.UserId] = nil
end

-- อัพเดท lastSeenAt
function ProfileService:UpdateLastSeen(player: Player)
	local profile = self._profiles[player.UserId]
	if profile then
		profile.meta.lastSeenAt = os.time()
	end
end

-- เริ่ม Auto-Save ทุก ๆ interval
function ProfileService:_startAutoSave()
	if self._autoSaveRunning then return end

	self._autoSaveRunning = true

	task.spawn(function()
		while self._autoSaveRunning do
			task.wait(AUTO_SAVE_INTERVAL)

			-- บันทึกทุก profile ที่มีใน cache
			for userId, profile in pairs(self._profiles) do
				local player = Players:GetPlayerByUserId(userId)
				if player then
					self:SaveProfile(player)
				end
			end
		end
	end)

	print("[ProfileService] Auto-save started")
end

-- หยุด Auto-Save
function ProfileService:_stopAutoSave()
	self._autoSaveRunning = false
	print("[ProfileService] Auto-save stopped")
end

-- ========================================
-- UPDATE HELPERS
-- ========================================

-- เพิ่มเหรียญ
function ProfileService:AddCoins(player: Player, amount: number): boolean
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return false end

	profile.stats.coins += amount
	return true
end

-- ลดเหรียญ (ตรวจสอบว่ามีพอก่อน)
function ProfileService:RemoveCoins(player: Player, amount: number): boolean
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return false end

	if profile.stats.coins < amount then
		return false -- เหรียญไม่พอ
	end

	profile.stats.coins -= amount
	return true
end

-- เพิ่ม XP
function ProfileService:AddXP(player: Player, amount: number)
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return end

	profile.progression.xp += amount

	-- TODO: คำนวณการเลเวลอัพ
	-- local xpForNextLevel = 100 * profile.progression.level
	-- if profile.progression.xp >= xpForNextLevel then
	--     profile.progression.level += 1
	--     profile.progression.xp -= xpForNextLevel
	-- end
end

-- ตั้งสีของหุ่นยนต์
function ProfileService:SetBotColor(player: Player, part: string, color: string)
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return end

	profile.bot.colors[part] = color
end

-- เพิ่มจำนวนผู้ประสบภัยที่ช่วยแล้ว
function ProfileService:AddRescue(player: Player)
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return end

	profile.stats.totalRescued += 1
end

-- อัพเดทสถานะภารกิจ
function ProfileService:UpdateMission(player: Player, missionId: string, state: string, bestTime: number?)
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return end

	if not profile.progression.missions[missionId] then
		profile.progression.missions[missionId] = {
			state = state :: any,
			bestTime = bestTime
		}
	else
		profile.progression.missions[missionId].state = state :: any

		-- อัพเดท bestTime ถ้าดีกว่า
		if bestTime then
			local currentBest = profile.progression.missions[missionId].bestTime
			if not currentBest or bestTime < currentBest then
				profile.progression.missions[missionId].bestTime = bestTime
			end
		end
	end
end

-- อัพเดทเวลาที่ดีที่สุดต่ออาคาร
function ProfileService:UpdateBestTime(player: Player, buildingId: string, time: number)
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return end

	local currentBest = profile.stats.bestTimePerBuilding[buildingId]

	-- อัพเดทถ้ายังไม่มีหรือดีกว่าเดิม
	if not currentBest or time < currentBest then
		profile.stats.bestTimePerBuilding[buildingId] = time

		-- อัพเดท bestBuilding ถ้าเป็นอาคารที่ทำเวลาได้เร็วที่สุด
		if not profile.stats.bestBuilding or time < (profile.stats.bestTimePerBuilding[profile.stats.bestBuilding] or math.huge) then
			profile.stats.bestBuilding = buildingId
		end
	end
end

-- ติดตั้งไอเทม (ตรวจสอบว่ามีของและช่องพอ)
function ProfileService:EquipItem(player: Player, itemId: string): boolean
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return false end

	-- ตรวจสอบว่ามีของ
	local item = profile.bot.inventory.owned[itemId]
	if not item then return false end

	-- ตรวจสอบว่าติดตั้งอยู่แล้วหรือยัง
	if table.find(profile.bot.inventory.equipped, itemId) then
		return false -- ติดตั้งอยู่แล้ว
	end

	-- คำนวณ slot ที่ใช้อยู่
	local slotsUsed = 0
	for _, equippedId in ipairs(profile.bot.inventory.equipped) do
		local equippedItem = profile.bot.inventory.owned[equippedId]
		if equippedItem then
			slotsUsed += equippedItem.slotCost
		end
	end

	-- ตรวจสอบว่ามีช่องพอ
	if slotsUsed + item.slotCost > profile.bot.slotsUnlocked then
		return false -- ช่องไม่พอ
	end

	-- ติดตั้ง
	table.insert(profile.bot.inventory.equipped, itemId)
	return true
end

-- ถอดไอเทม
function ProfileService:UnequipItem(player: Player, itemId: string): boolean
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return false end

	local index = table.find(profile.bot.inventory.equipped, itemId)
	if not index then return false end

	table.remove(profile.bot.inventory.equipped, index)
	return true
end

-- เพิ่มไอเทมในคลัง
function ProfileService:AddItem(player: Player, itemId: string, slotCost: number, tier: number, uses: number?)
	local profile: PlayerProfile? = self._profiles[player.UserId]
	if not profile then return end

	profile.bot.inventory.owned[itemId] = {
		id = itemId,
		slotCost = slotCost,
		tier = tier,
		uses = uses
	}
end

return ProfileService
