-- VictimSpawner ModuleScript
-- จัดการการ spawn victims ตามตำแหน่งใน workspace.SpawnVictims

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local VictimSpawner = {}

-- ตัวแปรเก็บ spawned victims
local spawnedVictims = {}

-- ฟังก์ชันสุ่มตำแหน่งบน BasePart (เท้าอยู่บนพื้นผิว)
local function getRandomPositionOnPart(part)
	if not part or not part:IsA("BasePart") then
		return nil
	end

	local size = part.Size
	local cframe = part.CFrame

	-- สุ่มตำแหน่งบนพื้นผิวของ part
	local randomX = math.random(-size.X/2, size.X/2)
	local randomZ = math.random(-size.Z/2, size.Z/2)
	local surfaceY = size.Y/2 -- พื้นผิวด้านบนของ part

	local worldPosition = cframe:PointToWorldSpace(Vector3.new(randomX, surfaceY, randomZ))
	return worldPosition
end


-- ฟังก์ชันโคลน victim template
local function cloneVictimTemplate()
	local victimNPC = ServerStorage:FindFirstChild("VictimNPC")
	if not victimNPC then
		warn("VictimNPC folder not found in ServerStorage")
		return nil
	end

	local template = victimNPC:FindFirstChild("TemplateOldR15")
	if not template then
		warn("TemplateOldR15 not found in ServerStorage.VictimNPC")
		return nil
	end

	local clonedVictim = template:Clone()
	return clonedVictim
end

-- ฟังก์ชัน spawn victim ที่ตำแหน่งที่กำหนด
local function spawnVictimAtPosition(position, spawnPointName)
	local victim = cloneVictimTemplate()
	if not victim then
		return nil
	end

	-- ตั้งชื่อ victim
	victim.Name = "Victim_" .. spawnPointName

	-- หาหรือสร้าง VictimFolders folder เดียว
	local victimFolder = workspace:FindFirstChild("VictimFolders")
	if not victimFolder then
		victimFolder = Instance.new("Folder")
		victimFolder.Name = "VictimFolders"
		victimFolder.Parent = workspace
	end
	victim.Parent = victimFolder

	-- คำนวณความสูงของ victim เพื่อวางเท้าให้อยู่บนพื้นผิว
	local victimHeight = 0

	-- หาความสูงจาก HumanoidRootPart หรือ PrimaryPart
	local rootPart = victim:FindFirstChild("HumanoidRootPart") or victim.PrimaryPart
	if rootPart then
		-- หาขาล่าง (Lower Leg หรือ Left/Right Leg) เพื่อคำนวณระยะจากกลางตัวถึงเท้า
		local leftLeg = victim:FindFirstChild("Left Leg") or victim:FindFirstChild("LeftLowerLeg") or victim:FindFirstChild("LeftFoot")
		local rightLeg = victim:FindFirstChild("Right Leg") or victim:FindFirstChild("RightLowerLeg") or victim:FindFirstChild("RightFoot")

		if leftLeg and leftLeg:IsA("BasePart") then
			-- ใช้ระยะจาก HumanoidRootPart ถึงขา + ขนาดขา
			local legDistance = math.abs(rootPart.Position.Y - leftLeg.Position.Y)
			victimHeight = legDistance + leftLeg.Size.Y/2
		else
			-- fallback: ใช้ครึ่งหนึ่งของความสูง HumanoidRootPart
			victimHeight = rootPart.Size.Y/2 + 2.5 -- ประมาณความสูงจากกลางตัวถึงเท้า
		end
	else
		-- fallback: ใช้ความสูงเริ่มต้น
		victimHeight = 3
	end

	-- ปรับตำแหน่งให้เท้าอยู่บนพื้นผิว
	local adjustedPosition = position + Vector3.new(0, victimHeight, 0)
	victim:PivotTo(CFrame.new(adjustedPosition))

	-- ระบบ rescue ใช้ CustomRescueSystem แทน ProximityPrompt แล้ว

	print("Spawned victim:", victim.Name, "at position:", adjustedPosition, "(height offset:", victimHeight, ")")
	return victim
end

-- ฟังก์ชันหลักสำหรับ spawn victims ทั้งหมด
function VictimSpawner.spawnAllVictims()
	print("Starting victim spawning process...")

	-- หา SpawnVictims folder
	local spawnVictims = Workspace:FindFirstChild("SpawnVictims")
	if not spawnVictims then
		warn("SpawnVictims folder not found in workspace")
		return false
	end

	-- เก็บ spawn points ทั้งหมด
	local spawnPoints = {}
	for _, child in ipairs(spawnVictims:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(spawnPoints, child)
		end
	end

	if #spawnPoints == 0 then
		warn("No spawn points found in SpawnVictims folder")
		return false
	end

	print("Found", #spawnPoints, "spawn points for victims")

	-- Spawn victim ที่แต่ละ spawn point
	local successCount = 0
	for _, spawnPoint in ipairs(spawnPoints) do
		local spawnPosition = getRandomPositionOnPart(spawnPoint)
		if spawnPosition then
			local victim = spawnVictimAtPosition(spawnPosition, spawnPoint.Name)
			if victim then
				table.insert(spawnedVictims, victim)
				successCount = successCount + 1
			end
		else
			warn("Failed to get spawn position for:", spawnPoint.Name)
		end
	end

	print("Successfully spawned", successCount, "victims out of", #spawnPoints, "spawn points")
	return successCount > 0
end

-- ฟังก์ชันลบ victims ทั้งหมด
function VictimSpawner.clearAllVictims()
	print("Clearing all spawned victims...")

	local clearedCount = 0

	-- ลบ victims จาก tracked array
	for _, victim in ipairs(spawnedVictims) do
		if victim and victim.Parent then
			victim:Destroy()
			clearedCount = clearedCount + 1
		end
	end

	-- ลบ VictimFolders folder ทั้งหมด
	local victimFolder = workspace:FindFirstChild("VictimFolders")
	if victimFolder then
		-- นับ victims ที่เหลืออยู่ในfolder (กรณีมี orphan victims)
		local folderVictimCount = 0
		for _, child in ipairs(victimFolder:GetChildren()) do
			if child.Name:match("^Victim_") then
				folderVictimCount = folderVictimCount + 1
			end
		end

		if folderVictimCount > 0 then
			print("Found", folderVictimCount, "additional victims in folder")
			clearedCount = clearedCount + folderVictimCount
		end

		victimFolder:Destroy()
		print("VictimFolders folder removed")
	end

	spawnedVictims = {}
	print("Cleared", clearedCount, "victims total")
end

-- ฟังก์ชันดูจำนวน victims ที่ spawn แล้ว
function VictimSpawner.getSpawnedVictimCount()
	local activeCount = 0
	for _, victim in ipairs(spawnedVictims) do
		if victim and victim.Parent then
			activeCount = activeCount + 1
		end
	end
	return activeCount
end

-- ฟังก์ชันดู victims ทั้งหมดที่ spawn แล้ว
function VictimSpawner.getAllSpawnedVictims()
	local activeVictims = {}
	for _, victim in ipairs(spawnedVictims) do
		if victim and victim.Parent then
			table.insert(activeVictims, victim)
		end
	end
	return activeVictims
end

-- ฟังก์ชันตรวจสอบว่า template พร้อมใช้งานหรือไม่
function VictimSpawner.checkTemplate()
	local victimNPC = ServerStorage:FindFirstChild("VictimNPC")
	if not victimNPC then
		return false, "VictimNPC folder not found in ServerStorage"
	end

	local template = victimNPC:FindFirstChild("TemplateOldR15")
	if not template then
		return false, "TemplateOldR15 not found in ServerStorage.VictimNPC"
	end

	return true, "Template found and ready"
end

-- ฟังก์ชันตรวจสอบ spawn points
function VictimSpawner.checkSpawnPoints()
	local spawnVictims = Workspace:FindFirstChild("SpawnVictims")
	if not spawnVictims then
		return false, "SpawnVictims folder not found in workspace"
	end

	local spawnPointCount = 0
	for _, child in ipairs(spawnVictims:GetChildren()) do
		if child:IsA("BasePart") then
			spawnPointCount = spawnPointCount + 1
		end
	end

	if spawnPointCount == 0 then
		return false, "No spawn points found in SpawnVictims folder"
	end

	return true, "Found " .. spawnPointCount .. " spawn points"
end

return VictimSpawner