-- CompanionEquipment Module
-- จัดการการติดตั้งอุปกรณ์บน Rescue Companion ตามของที่ผู้เล่น equip

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local EquipmentManager = require(ReplicatedStorage.Modules.EquipmentManager)

local CompanionEquipment = {}

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
	end
	return nil
end

local function isSolarCellEquipped(equippedItems: any): boolean
	if not equippedItems then
		return false
	end

	for _, item in ipairs(equippedItems) do
		if item and item.id == "SolarCell" then
			return true
		end
	end

	return false
end

local function removeExistingSolarCell(companion: Model)
	for _, child in ipairs(companion:GetChildren()) do
		if child:IsA("Model") then
			local equippedId = child:GetAttribute("EquippedItemId")
			if child.Name == "SolarCell_Companion" or equippedId == "SolarCell" then
				child:Destroy()
			end
		end
	end
end

local function getColorForItem(equippedItems: any, itemId: string): Color3?
	if typeof(equippedItems) ~= "table" then
		return nil
	end
	for _, entry in ipairs(equippedItems) do
		if entry and entry.id == itemId and entry.color then
			return toColor3(entry.color)
		end
	end
	return nil
end

local function applyColorToModel(model: Model, color: Color3)
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Color = color
			descendant.Material = Enum.Material.SmoothPlastic
		end
	end
	if model.PrimaryPart and model.PrimaryPart:IsA("BasePart") then
		model.PrimaryPart.Color = color
	end
end

local function attachSolarCell(companion: Model, equippedItems: any)
	if not isSolarCellEquipped(equippedItems) then
		removeExistingSolarCell(companion)
		return
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		warn("[CompanionEquipment] ReplicatedStorage.Assets not found")
		return
	end

	local template = assets:FindFirstChild("SolarCell_Companion")
	if not template or not template:IsA("Model") then
		warn("[CompanionEquipment] SolarCell_Companion asset not found or invalid")
		return
	end

	local companionPrimary = companion.PrimaryPart or companion:FindFirstChildWhichIsA("BasePart", true)
	if not companionPrimary then
		warn("[CompanionEquipment] Companion has no PrimaryPart or base part")
		return
	end

	companion.PrimaryPart = companionPrimary

	removeExistingSolarCell(companion)

	local clone = template:Clone()
	clone.Name = "SolarCell_Companion"
	clone:SetAttribute("EquippedItemId", "SolarCell")

	local itemPrimary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart", true)
	if not itemPrimary then
		warn("[CompanionEquipment] SolarCell_Companion has no PrimaryPart")
		clone:Destroy()
		return
	end

	clone.PrimaryPart = itemPrimary
	clone.Parent = companion

	local overrideColor = getColorForItem(equippedItems, "SolarCell")
	if overrideColor then
		print("[CompanionEquipment] Applying SolarCell color", overrideColor)
		applyColorToModel(clone, overrideColor)
	end

	local itemMount = itemPrimary:FindFirstChild("Mount")
	local companionMount = companionPrimary:FindFirstChild("Mount")

	if itemMount and companionMount then
		local botMountWorldCFrame = companionMount.WorldCFrame
		local itemMountLocalCFrame = itemMount.CFrame
		local itemPivot = clone:GetPivot()
		local pivotToMount = itemPivot:Inverse() * itemPrimary.CFrame * itemMountLocalCFrame
		local finalCFrame = botMountWorldCFrame * pivotToMount:Inverse()
		clone:PivotTo(finalCFrame)
	else
		clone:PivotTo(companionPrimary.CFrame)
	end

	for _, descendant in ipairs(clone:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = false
			descendant.CanCollide = false
		end
	end

	local weld = Instance.new("WeldConstraint")
	weld.Name = "SolarCell_Companion_Weld"
	weld.Part0 = companionPrimary
	weld.Part1 = clone.PrimaryPart
	weld.Parent = clone.PrimaryPart
end

function CompanionEquipment.apply(companion: Model?, equippedItems: any)
	if not companion or not companion:IsA("Model") then
		return
	end

	-- ใช้ EquipmentManager สำหรับ equip items ทั้งหมด ยกเว้น SolarCell
	EquipmentManager.setTargetBot(companion)

	-- Clear equipment เก่าก่อน (ซ่อน DrillArm และ Camera)
	EquipmentManager.clearAll()

	if typeof(equippedItems) == "table" then
		for _, item in ipairs(equippedItems) do
			if item and item.id then
				-- Skip SolarCell - จะใช้ attachSolarCell() แทน
				if item.id ~= "SolarCell" then
					local colorOverride = item.color or nil
					local success = EquipmentManager.equipItem(item.id, colorOverride)
					if success then
						print("[CompanionEquipment] Equipped", item.id, "on companion")
					else
						warn("[CompanionEquipment] Failed to equip", item.id, "on companion")
					end
				end
			end
		end
	end

	-- Attach SolarCell_Companion (companion-specific asset)
	attachSolarCell(companion, equippedItems)
end

function CompanionEquipment.applyForPlayer(player: Player, equippedItems: any)
	local companionName = player.Name .. "_RescueCompanion"
	local companion = workspace:FindFirstChild(companionName)
	if not companion or not companion:IsA("Model") then
		return
	end

	CompanionEquipment.apply(companion, equippedItems)
end

return CompanionEquipment
