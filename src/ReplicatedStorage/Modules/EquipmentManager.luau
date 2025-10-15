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

	-- สำหรับ DrillArm: ใช้เทคนิคซ่อน/แสดง (ไม่ clone)
	if itemId == "DrillArm" then
		-- หา DrillArm items ที่ซ่อนอยู่ใน bot
		local tube1 = targetBot:FindFirstChild("Tube1")
		local drillArmModel = targetBot:FindFirstChild("DrillArm")

		if not tube1 or not drillArmModel then
			warn("[EquipmentManager] DrillArm parts not found in bot. Tube1:", tube1, "DrillArm:", drillArmModel)
			return false
		end

		-- แสดง DrillArm parts
		for _, part in ipairs({tube1, drillArmModel}) do
			if part:IsA("BasePart") then
				part.Transparency = 0
			elseif part:IsA("Model") then
				for _, descendant in ipairs(part:GetDescendants()) do
					if descendant:IsA("BasePart") then
						descendant.Transparency = 0
					end
				end
			end
		end

		-- ตั้ง Attribute ว่า DrillArm equipped
		targetBot:SetAttribute("DrillArmEquipped", true)

		print("[EquipmentManager] Showed DrillArm parts")
		equippedItems[itemId] = drillArmModel
		return true
	end

	-- สำหรับ items อื่นๆ: ใช้วิธีเดิม (clone จาก Assets)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[EquipmentManager] ReplicatedStorage.Assets not found")
		return false
	end

	local assetTemplate = assets:FindFirstChild(itemId) :: Model
	if not assetTemplate then
		warn("[EquipmentManager] Asset not found:", itemId)
		return false
	end

	-- Clone asset
	local clonedItem = assetTemplate:Clone()

	-- กำหนด mount name ตามประเภท item
	local mountName = "Mount"

	-- หา Mount attachments
	local itemMount: Attachment? = nil
	itemMount = clonedItem.PrimaryPart and clonedItem.PrimaryPart:FindFirstChild("Mount") :: Attachment

	local botMount = targetBot.PrimaryPart:FindFirstChild(mountName) :: Attachment

	-- ตรวจสอบว่ามี mount attachments ครบ
	if not itemMount or not botMount then
		warn("[EquipmentManager] Mount attachment not found - itemMount:", itemMount, "botMount:", botMount, "mountName:", mountName)
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
	local itemMountWorldCFrame = itemMount.WorldCFrame

	-- คำนวณ offset จาก item mount ไปยัง item pivot
	local itemPivot = clonedItem:GetPivot()
	local mountToItemPivot = itemMountWorldCFrame:Inverse() * itemPivot

	-- ตำแหน่งสุดท้ายของ item = botMount * offset
	local finalCFrame = botMountWorldCFrame * mountToItemPivot
	clonedItem:PivotTo(finalCFrame)

	-- Weld item เข้ากับ bot (สำหรับ items อื่นๆ ที่ไม่ใช่ DrillArm)
	local motor = Instance.new("Motor6D")
	motor.Name = itemId .. "Motor"
	motor.Part0 = targetBot.PrimaryPart
	motor.Part1 = clonedItem.PrimaryPart

	-- ตั้งค่า C0 และ C1 สำหรับ Motor6D
	motor.C0 = targetBot.PrimaryPart.CFrame:Inverse() * clonedItem.PrimaryPart.CFrame
	motor.C1 = CFrame.new()

	motor.Parent = clonedItem.PrimaryPart
	print("[EquipmentManager] Created Motor6D for", itemId)

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

	-- สำหรับ DrillArm: ซ่อนแทนการลบ
	if itemId == "DrillArm" and targetBot then
		local tube1 = targetBot:FindFirstChild("Tube1")
		local drillArmModel = targetBot:FindFirstChild("DrillArm")

		-- ซ่อน DrillArm parts
		for _, part in ipairs({tube1, drillArmModel}) do
			if part and part:IsA("BasePart") then
				part.Transparency = 1
			elseif part and part:IsA("Model") then
				for _, descendant in ipairs(part:GetDescendants()) do
					if descendant:IsA("BasePart") then
						descendant.Transparency = 1
					end
				end
			end
		end

		-- ลบ Attribute
		targetBot:SetAttribute("DrillArmEquipped", false)

		print("[EquipmentManager] Hid DrillArm parts")
		equippedItems[itemId] = nil
		return true
	end

	-- สำหรับ items อื่นๆ: ลบออก
	equippedItem:Destroy()
	equippedItems[itemId] = nil

	print("[EquipmentManager] Unequipped item:", itemId)
	return true
end

-- ลบ equipped items ทั้งหมด
function EquipmentManager.clearAll()
	-- สำหรับ DrillArm: ซ่อนแทนการลบ
	if targetBot then
		local tube1 = targetBot:FindFirstChild("Tube1")
		local drillArmModel = targetBot:FindFirstChild("DrillArm")

		-- ซ่อน DrillArm parts
		for _, part in ipairs({tube1, drillArmModel}) do
			if part and part:IsA("BasePart") then
				part.Transparency = 1
			elseif part and part:IsA("Model") then
				for _, descendant in ipairs(part:GetDescendants()) do
					if descendant:IsA("BasePart") then
						descendant.Transparency = 1
					end
				end
			end
		end

		-- ลบ Attribute
		targetBot:SetAttribute("DrillArmEquipped", false)
	end

	-- ลบ items อื่นๆ
	for itemId, item in pairs(equippedItems) do
		if item and itemId ~= "DrillArm" then
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
