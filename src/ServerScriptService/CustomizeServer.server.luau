-- CustomizeServer
-- จัดการ Customize ฝั่ง Server

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CustomizeService = require(ReplicatedStorage.Modules.CustomizeService)

-- ใช้ Shared ProfileService instance
local profileService = require(ServerScriptService.SharedProfileService)

-- รับและบันทึก equipped items
CustomizeService.onSaveEquipment(function(player: Player, equippedItems: {{id: string, row: number, column: number}})
	print("[CustomizeServer] Received save request from", player.Name, "items:", equippedItems)

	-- ดึง profile ของผู้เล่น
	local profile = profileService:GetProfile(player)
	if not profile then
		warn("[CustomizeServer] Profile not found for", player.Name)
		return
	end

	-- บันทึก equipped items พร้อมตำแหน่ง
	profile.bot.inventory.equipped = equippedItems

	-- Save profile
	local saveSuccess = profileService:SaveProfile(player)
	if saveSuccess then
		print("[CustomizeServer] Saved profile for", player.Name)
	else
		warn("[CustomizeServer] Failed to save profile for", player.Name)
	end
end)

-- ส่งรายการ equipped items กลับไปยัง client
CustomizeService.onGetEquipment(function(player: Player): {{id: string, row: number, column: number}}?
	print("[CustomizeServer] Get equipment request from", player.Name)

	local profile = profileService:GetProfile(player)
	if not profile then
		warn("[CustomizeServer] Profile not found for", player.Name)
		return nil
	end

	return profile.bot.inventory.equipped
end)

print("[CustomizeServer] Initialized")
