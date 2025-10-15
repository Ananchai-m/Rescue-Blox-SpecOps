-- CustomizeServer
-- จัดการ Customize ฝั่ง Server

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local CustomizeService = require(ReplicatedStorage.Modules.CustomizeService)
local CompanionEquipment = require(ReplicatedStorage.Modules.CompanionEquipment)
local EquipmentManager = require(ReplicatedStorage.Modules.EquipmentManager)

-- ใช้ Shared ProfileService instance
local profileService = require(ServerScriptService.SharedProfileService)

local function toColor3(colorData)
	if typeof(colorData) == "table" then
		local r = colorData.r or colorData.R or colorData[1]
		local g = colorData.g or colorData.G or colorData[2]
		local b = colorData.b or colorData.B or colorData[3]
		if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
			r = math.clamp(r, 0, 1)
			g = math.clamp(g, 0, 1)
			b = math.clamp(b, 0, 1)
			return Color3.new(r, g, b)
		end
	elseif typeof(colorData) == "string" then
		if colorData:sub(1, 1) == "#" and (#colorData == 7 or #colorData == 9) then
			local hex = colorData:sub(2)
			local value = tonumber(hex, 16)
			if value then
				local r = math.floor(value / 0x10000) % 0x100
				local g = math.floor(value / 0x100) % 0x100
				local b = value % 0x100
				r = r / 255
				g = g / 255
				b = b / 255
				return Color3.new(r, g, b)
			end
		end
	elseif typeof(colorData) == "Color3" then
		return colorData
	end

	return nil
end

local function findPartByPath(model: Instance?, path: string): BasePart?
	if not model or not path or path == "" then
		return nil
	end

	local current: Instance? = model
	for _, segment in ipairs(string.split(path, "/")) do
		if not current then
			return nil
		end
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	if current and current:IsA("BasePart") and not current:IsA("Seat") and current.Name ~= "VehicleSeat" then
		return current
	end

	return nil
end

local function findPartByPathOrName(model: Instance?, path: string): BasePart?
	local part = findPartByPath(model, path)
	if part then
		return part
	end
	if not model then
		return nil
	end
	local partName = path:match("([^/]+)$")
	if not partName then
		return nil
	end
	local descendant = model:FindFirstChild(partName, true)
	if descendant and descendant:IsA("BasePart") and not descendant:IsA("Seat") and descendant.Name ~= "VehicleSeat" then
		return descendant
	end
	return nil
end

local function applyColorSchemeToModel(model: Model?, colorScheme: any)
	if not model or not colorScheme then
		return
	end

	if typeof(colorScheme) ~= "table" then
		return
	end

	if colorScheme[1] and typeof(colorScheme[1]) == "table" and colorScheme[1].path then
		for _, entry in ipairs(colorScheme) do
			local path = entry.path
			local color = toColor3(entry.color)
			if typeof(path) == "string" and color then
				local part = findPartByPathOrName(model, path)
				if part then
					part.Color = color
				else
					print("[CustomizeServer] Missing path", path, "on", model.Name)
				end
			end
		end
	else
		for path, colorData in pairs(colorScheme) do
			if typeof(path) == "string" then
				local color = toColor3(colorData)
				if color then
					local part = findPartByPathOrName(model, path)
					if part then
						part.Color = color
					else
						print("[CustomizeServer] Missing path", path, "on", model.Name)
					end
				end
			end
		end
	end
end

local function sanitizeColorScheme(colorScheme: any): {[string]: {r: number, g: number, b: number}}
	local sanitized: {[string]: {r: number, g: number, b: number}} = {}
	if typeof(colorScheme) ~= "table" then
		return sanitized
	end

	if colorScheme[1] and typeof(colorScheme[1]) == "table" and colorScheme[1].path then
		for _, entry in ipairs(colorScheme) do
			if typeof(entry.path) == "string" and entry.path ~= "" then
				local c3 = toColor3(entry.color)
				if c3 then
					sanitized[entry.path] = { r = c3.R, g = c3.G, b = c3.B }
				end
			end
		end
	else
		for path, color in pairs(colorScheme) do
			if typeof(path) == "string" and path ~= "" then
				local c3 = toColor3(color)
				if c3 then
					sanitized[path] = { r = c3.R, g = c3.G, b = c3.B }
				end
			end
		end
	end

	return sanitized
end

local function applyColorSchemeForPlayer(player: Player, colorScheme: any)
	if not colorScheme then
		return
	end

	if typeof(colorScheme) == "table" then
		if colorScheme[1] and #colorScheme == 0 then
			return
		elseif not colorScheme[1] and next(colorScheme) == nil then
			return
		end
	else
		return
	end

	local rescueModel = workspace:FindFirstChild(player.Name .. "_Rescue")
	if rescueModel and rescueModel:IsA("Model") then
		applyColorSchemeToModel(rescueModel, colorScheme)
	end

	local companionModel = workspace:FindFirstChild(player.Name .. "_RescueCompanion")
	if companionModel and companionModel:IsA("Model") then
		applyColorSchemeToModel(companionModel, colorScheme)
	end
end

local shouldSaveProfile: {[Player]: boolean} = {}

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
	profile.bot = profile.bot or {}
	profile.bot.inventory = profile.bot.inventory or {}
	local sanitizedEquipped: {{id: string, row: number, column: number, color: {r: number, g: number, b: number}?}} = {}

	for _, entry in ipairs(equippedItems) do
		if typeof(entry) == "table" and typeof(entry.id) == "string" then
			local sanitizedEntry = {
				id = entry.id,
				row = entry.row or 1,
				column = entry.column or 1,
			}
			if entry.color then
				local c3 = toColor3(entry.color)
				if c3 then
					sanitizedEntry.color = { r = c3.R, g = c3.G, b = c3.B }
				end
			end
			table.insert(sanitizedEquipped, sanitizedEntry)
		end
	end
	profile.bot.inventory.equipped = sanitizedEquipped

	-- Apply equipment สำหรับ RescueCompanion
	CompanionEquipment.applyForPlayer(player, sanitizedEquipped)

	-- Apply equipment สำหรับ Original Rescue
	local rescueModel = workspace:FindFirstChild(player.Name .. "_Rescue")
	if rescueModel and rescueModel:IsA("Model") then
		EquipmentManager.setTargetBot(rescueModel)
		-- Clear equipment เก่าก่อน (ซ่อน DrillArm และ Camera)
		EquipmentManager.clearAll()
		-- Equip items ใหม่ทั้งหมด
		for _, equippedItem in ipairs(sanitizedEquipped) do
			local itemId = equippedItem.id
			if itemId then
				local colorOverride = equippedItem.color or nil
				local success = EquipmentManager.equipItem(itemId, colorOverride)
				if success then
					print("[CustomizeServer] Equipped", itemId, "on Original Rescue for", player.Name)
				else
					warn("[CustomizeServer] Failed to equip", itemId, "on Original Rescue for", player.Name)
				end
			end
		end
		print("[CustomizeServer] Applied equipment to Original Rescue for", player.Name)
	end

	shouldSaveProfile[player] = true
end)

CustomizeService.onSaveColorScheme(function(player: Player, colorScheme)
	print("[CustomizeServer] Received color scheme from", player.Name)
	local profile = profileService:GetProfile(player)
	if not profile then
		warn("[CustomizeServer] Profile not found for", player.Name)
		return
	end

	local sanitized = sanitizeColorScheme(colorScheme)
	if sanitized and next(sanitized) then
		local entries = {}
		for path, color in pairs(sanitized) do
			entries[#entries + 1] = string.format("%s=(%.2f,%.2f,%.2f)", path, color.r, color.g, color.b)
		end
		print("[CustomizeServer] Saving color scheme:", entries)
	else
		print("[CustomizeServer] Color scheme empty (default colors)")
	end
	profile.bot = profile.bot or {}
	profile.bot.colors = sanitized

	applyColorSchemeForPlayer(player, sanitized)
	shouldSaveProfile[player] = true
end)

CustomizeService.onGetColorScheme(function(player: Player)
	local profile = profileService:GetProfile(player)
	if not profile then
		return nil
	end
	return profile.bot and profile.bot.colors
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

local function flushProfileSave(player: Player)
	if shouldSaveProfile[player] then
		shouldSaveProfile[player] = nil
		local success, err = pcall(function()
			return profileService:SaveProfile(player)
		end)
		if success then
			print("[CustomizeServer] Saved profile for", player.Name)
		else
			warn("[CustomizeServer] Failed to save profile for", player.Name, err)
		end
	end
end

Players.PlayerRemoving:Connect(function(player)
	flushProfileSave(player)
end)

game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		flushProfileSave(player)
	end
end)

print("[CustomizeServer] Initialized")
