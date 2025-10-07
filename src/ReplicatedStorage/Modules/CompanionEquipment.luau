-- CompanionEquipment Module
-- จัดการการติดตั้งอุปกรณ์บน Rescue Companion ตามของที่ผู้เล่น equip

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CompanionEquipment = {}

local function isSolarCellEquipped(equippedItems: {{id: string}}?): boolean
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

local function attachSolarCell(companion: Model, equippedItems: {{id: string}}?)
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

function CompanionEquipment.apply(companion: Model?, equippedItems: {{id: string}}?)
	if not companion or not companion:IsA("Model") then
		return
	end

	attachSolarCell(companion, equippedItems)
end

function CompanionEquipment.applyForPlayer(player: Player, equippedItems: {{id: string}}?)
	local companionName = player.Name .. "_RescueCompanion"
	local companion = workspace:FindFirstChild(companionName)
	if not companion or not companion:IsA("Model") then
		return
	end

	CompanionEquipment.apply(companion, equippedItems)
end

return CompanionEquipment
