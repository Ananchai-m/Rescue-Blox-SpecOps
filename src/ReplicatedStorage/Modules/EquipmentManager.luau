-- EquipmentManager Module
-- จัดการการ equip/unequip items บน Rescue bot

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentManager = {}

-- ตัวแปรเก็บ equipped items
local equippedItems: { [string]: Model } = {}
local targetBot: Model? = nil
local function toColor3(colorData: any): Color3?
	if typeof(colorData) == "Color3" then
		return colorData
	elseif typeof(colorData) == "table" then
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
	end
	return nil
end

-- ตั้งค่า bot ที่จะ equip items
function EquipmentManager.setTargetBot(bot: Model)
	targetBot = bot
end

-- Equip item บน bot
function EquipmentManager.equipItem(itemId: string, colorOverride: any?): boolean
	-- ตรวจสอบว่ามี item นี้ equip อยู่แล้วหรือไม่
	if equippedItems[itemId] then
		warn("[EquipmentManager] Item already equipped:", itemId)
		return false
	end

	-- ตรวจสอบว่ามี target bot หรือไม่
	if not targetBot or not targetBot.PrimaryPart then
		warn("[EquipmentManager] Target bot not set or missing PrimaryPart")
		return false
	end

	-- หา Assets ใน ReplicatedStorage
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[EquipmentManager] ReplicatedStorage.Assets not found")
		return false
	end

	local assetTemplate = assets:FindFirstChild(itemId)
	if not assetTemplate then
		warn("[EquipmentManager] Asset not found:", itemId)
		return false
	end

	-- Clone asset
	local clonedItem = assetTemplate:Clone()

	-- หา Mount attachments
	local itemMount = clonedItem.PrimaryPart and clonedItem.PrimaryPart:FindFirstChild("Mount")
	local botMount = targetBot.PrimaryPart:FindFirstChild("Mount")

	if not itemMount or not botMount then
		warn("[EquipmentManager] Mount attachment not found")
		clonedItem:Destroy()
		return false
	end

	-- Parent item ไปที่ targetBot
	clonedItem.Parent = targetBot

	-- Apply color override ถ้ามี
	local overrideColor = toColor3(colorOverride)
	if overrideColor then
		for _, descendant in ipairs(clonedItem:GetDescendants()) do
			if descendant:IsA("BasePart") then
				descendant.Color = overrideColor
				descendant.Material = Enum.Material.SmoothPlastic
			end
		end
		if clonedItem:IsA("Model") and clonedItem.PrimaryPart and clonedItem.PrimaryPart:IsA("BasePart") then
			clonedItem.PrimaryPart.Color = overrideColor
		end
	end

	-- Snap item ไปที่ Mount attachment
	local botMountWorldCFrame = botMount.WorldCFrame
	local itemMountLocalCFrame = itemMount.CFrame

	-- คำนวณ offset จาก item's pivot ไปยัง item's mount
	local itemPivot = clonedItem:GetPivot()
	local pivotToMount = itemPivot:Inverse() * clonedItem.PrimaryPart.CFrame * itemMountLocalCFrame

	-- คำนวณตำแหน่งสุดท้ายของ item
	local finalCFrame = botMountWorldCFrame * pivotToMount:Inverse()
	clonedItem:PivotTo(finalCFrame)

	-- Weld item เข้ากับ bot
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = targetBot.PrimaryPart
	weld.Part1 = clonedItem.PrimaryPart
	weld.Parent = clonedItem.PrimaryPart

	-- เก็บ reference
	equippedItems[itemId] = clonedItem

	print("[EquipmentManager] Equipped item:", itemId)
	return true
end

-- Unequip item จาก bot
function EquipmentManager.unequipItem(itemId: string): boolean
	local equippedItem = equippedItems[itemId]
	if not equippedItem then
		warn("[EquipmentManager] Item not equipped:", itemId)
		return false
	end

	-- Destroy item
	equippedItem:Destroy()
	equippedItems[itemId] = nil

	print("[EquipmentManager] Unequipped item:", itemId)
	return true
end

-- ลบ equipped items ทั้งหมด
function EquipmentManager.clearAll()
	for itemId, item in pairs(equippedItems) do
		if item then
			item:Destroy()
		end
	end
	table.clear(equippedItems)
	print("[EquipmentManager] Cleared all equipped items")
end

-- ดึงรายการ equipped items
function EquipmentManager.getEquippedItems(): { [string]: Model }
	return equippedItems
end

-- ตรวจสอบว่า item นี้ equip อยู่หรือไม่
function EquipmentManager.isEquipped(itemId: string): boolean
	return equippedItems[itemId] ~= nil
end

return EquipmentManager
