--!strict
-- ProfileManager.server.luau
-- จัดการ PlayerProfile เมื่อผู้เล่นเข้า-ออกเกม และบันทึกอัตโนมัติ

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

-- ใช้ Shared ProfileService instance
local profileService = require(ServerScriptService.SharedProfileService)

-- เริ่ม Auto-Save
profileService:_startAutoSave()

-- จัดการเมื่อผู้เล่นเข้าเกม
local function onPlayerAdded(player: Player)
	print(`[ProfileManager] Player joined: {player.Name}`)

	-- โหลด Profile
	local profile = profileService:LoadProfile(player)

	if profile then
		print(`[ProfileManager] Profile loaded for {player.Name}`)
		print(`  Stats:`)
		print(`     - Level: {profile.progression.level} | XP: {profile.progression.xp}`)
		print(`     - Coins: {profile.stats.coins}`)
		print(`     - Total Rescued: {profile.stats.totalRescued}`)
		print(`     - Deaths: {profile.stats.deaths}`)
		print(`  Bot:`)
		print(`     - Slots Unlocked: {profile.bot.slotsUnlocked}`)

		local ownedCount = 0
		for _ in pairs(profile.bot.inventory.owned) do
			ownedCount += 1
		end
		print(`     - Items Owned: {ownedCount}`)
		print(`     - Items Equipped: {#profile.bot.inventory.equipped}`)
		if profile.bot.colors and next(profile.bot.colors) then
			local colorEntries = {}
			for path, color in pairs(profile.bot.colors) do
				local c3
				if typeof(color) == "Color3" then
					c3 = color
				elseif typeof(color) == "table" then
					local r = color.r or color.R or color[1]
					local g = color.g or color.G or color[2]
					local b = color.b or color.B or color[3]
					if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
						c3 = Color3.new(r, g, b)
					end
				end
				if c3 then
					colorEntries[#colorEntries + 1] = string.format("%s=(%.2f,%.2f,%.2f)", path, c3.R, c3.G, c3.B)
				end
			end
			print("     - Colors: { " .. table.concat(colorEntries, ", ") .. " }")
		else
			print("     - Colors: default")
		end
		print(`  Best Building: {profile.stats.bestBuilding or "None"}`)

		-- สามารถทำอะไรต่อได้ที่นี่ เช่น
		-- - สร้าง leaderstats
		-- - ตั้งค่าตัวละคร
		-- - ส่งข้อมูลไปยัง client
	else
		warn(`[ProfileManager] Failed to load profile for {player.Name}`)
		-- อาจจะ kick ผู้เล่นออกหากโหลด profile ไม่สำเร็จ
		-- player:Kick("Failed to load your profile. Please rejoin.")
	end
end

-- จัดการเมื่อผู้เล่นออกจากเกม
local function onPlayerRemoving(player: Player)
	print(`[ProfileManager] Player leaving: {player.Name}`)

	-- ดึง profile ก่อน save
	local profile = profileService:GetProfile(player)

	if profile then
		print(`[ProfileManager] Saving profile data:`)
		print(`  Final Stats:`)
		print(`     - Level: {profile.progression.level} | XP: {profile.progression.xp}`)
		print(`     - Coins: {profile.stats.coins}`)
		print(`     - Total Rescued: {profile.stats.totalRescued}`)
		print(`     - Deaths: {profile.stats.deaths}`)
		print(`  Session Time: {os.time() - profile.meta.lastSeenAt} seconds`)
	end

	-- บันทึก Profile ก่อนออก
	local success = profileService:SaveProfile(player)

	if success then
		print(`[ProfileManager] Profile saved successfully for {player.Name}`)
	else
		warn(`[ProfileManager] Failed to save profile for {player.Name}`)
	end

	-- ลบ Profile จาก cache
	profileService:RemoveProfile(player)
end

-- จัดการเมื่อเซิร์ฟเวอร์ปิด
local function onShutdown()
	print("[ProfileManager] Server shutting down, saving all profiles...")

	-- บันทึกทุก profile ก่อนปิดเซิร์ฟเวอร์
	for _, player in ipairs(Players:GetPlayers()) do
		profileService:SaveProfile(player)
		print(`[ProfileManager] Saved profile for {player.Name} on shutdown`)
	end

	-- หยุด Auto-Save
	profileService:_stopAutoSave()
end

-- เชื่อมต่อ Events
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- จัดการผู้เล่นที่อยู่ก่อนหน้า script รัน
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Bind shutdown
game:BindToClose(onShutdown)

print("[ProfileManager] Initialized successfully")
