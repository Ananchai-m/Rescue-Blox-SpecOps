-- VictimSpawner ModuleScript
-- จัดการการ spawn victims ตามตำแหน่งใน workspace.SpawnVictims

local ServerStorage = game:GetService("ServerStorage")
local Workspace = game:GetService("Workspace")

local VictimSpawner = {}

-- ตัวแปรเก็บ spawned victims และ obstacles
local spawnedVictims = {}
local spawnedObstacles = {}

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

-- ฟังก์ชันตรวจสอบว่า part สามารถ SetNetworkOwner ได้หรือไม่
local function canSetNetworkOwner(part)
	if not part:IsA("BasePart") or part.Anchored then
		return false
	end

	-- ตรวจสอบว่ามี weld/motor ไปยัง Anchored part หรือไม่
	for _, joint in ipairs(part:GetJoints()) do
		if joint:IsA("Motor6D") or joint:IsA("Weld") or joint:IsA("WeldConstraint") then
			local part0 = joint:FindFirstChild("Part0") and joint.Part0
			local part1 = joint:FindFirstChild("Part1") and joint.Part1

			if (part0 and part0.Anchored) or (part1 and part1.Anchored) then
				return false
			end
		end
	end

	return true
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

	-- Set Network Owner เป็น server เพื่อลดการกระตุกของฟิสิกส์
	-- เฉพาะ HumanoidRootPart เท่านั้น เพราะเป็น primary part ที่ควบคุมฟิสิกส์ทั้งหมด
	if rootPart and canSetNetworkOwner(rootPart) then
		local success = pcall(function()
			rootPart:SetNetworkOwner(nil)
		end)
		if success then
			print("Set NetworkOwner for", victim.Name, "HumanoidRootPart")
		end
	end

	-- ระบบ rescue ใช้ CustomRescueSystem แทน ProximityPrompt แล้ว

	print("Spawned victim:", victim.Name, "at position:", adjustedPosition, "(height offset:", victimHeight, ")")
	return victim
end

-- ฟังก์ชัน spawn obstacles จาก ServerStorage ไป workspace
function VictimSpawner.spawnAllObstacles()
	print("Starting obstacles spawning process...")

	-- หา ServerStorage.Models.Obstacles
	local models = ServerStorage:FindFirstChild("Models")
	if not models then
		warn("Models folder not found in ServerStorage")
		return false
	end

	local obstaclesFolder = models:FindFirstChild("Obstacles")
	if not obstaclesFolder then
		warn("Obstacles folder not found in ServerStorage.Models")
		return false
	end

	-- หา workspace.Building_LV1.Obstacles
	local buildingLV1 = Workspace:FindFirstChild("Building_LV1")
	if not buildingLV1 then
		warn("Building_LV1 not found in workspace")
		return false
	end

	local targetObstaclesFolder = buildingLV1:FindFirstChild("Obstacles")
	if targetObstaclesFolder then
		-- ถ้ามี Obstacles folder อยู่แล้ว ให้ลบของเก่าทั้งหมดก่อน
		print("Found existing Obstacles folder, clearing old obstacles...")
		local clearedCount = 0
		for _, child in ipairs(targetObstaclesFolder:GetChildren()) do
			child:Destroy()
			clearedCount = clearedCount + 1
		end
		print("Cleared", clearedCount, "old obstacles")
	else
		-- สร้าง Obstacles folder ถ้าไม่มี
		targetObstaclesFolder = Instance.new("Folder")
		targetObstaclesFolder.Name = "Obstacles"
		targetObstaclesFolder.Parent = buildingLV1
		print("Created Obstacles folder in Building_LV1")
	end

	-- เคลียร์ spawnedObstacles array ก่อน spawn ใหม่
	spawnedObstacles = {}

	-- Clone obstacles ทั้งหมดจาก ServerStorage
	local successCount = 0
	for _, obstacleModel in ipairs(obstaclesFolder:GetChildren()) do
		if obstacleModel:IsA("Model") or obstacleModel:IsA("Folder") then
			local clonedObstacle = obstacleModel:Clone()
			clonedObstacle.Parent = targetObstaclesFolder
			table.insert(spawnedObstacles, clonedObstacle)
			successCount = successCount + 1
			print("Spawned obstacle:", clonedObstacle.Name)
		end
	end

	print("Successfully spawned", successCount, "obstacles")
	return successCount > 0
end

-- ฟังก์ชันลบ obstacles ทั้งหมด
function VictimSpawner.clearAllObstacles()
	print("Clearing all spawned obstacles...")

	local clearedCount = 0

	-- ลบ obstacles จาก tracked array
	for _, obstacle in ipairs(spawnedObstacles) do
		if obstacle and obstacle.Parent then
			obstacle:Destroy()
			clearedCount = clearedCount + 1
		end
	end

	spawnedObstacles = {}
	print("Cleared", clearedCount, "obstacles total")
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

	-- เคลียร์ spawnedVictims array ก่อน spawn ใหม่
	spawnedVictims = {}

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


-- ฟังก์ชันนับจำนวน victims ทั้งหมดที่ spawn
function VictimSpawner.getTotalVictimCount()
	-- หา SpawnVictims folder เพื่อนับจำนวน spawn points
	local spawnVictims = Workspace:FindFirstChild("SpawnVictims")
	if not spawnVictims then
		return 0
	end
	
	local count = 0
	for _, child in ipairs(spawnVictims:GetChildren()) do
		if child:IsA("BasePart") then
			count = count + 1
		end
	end
	
	return count
end

-- ฟังก์ชันนับจำนวน victims ที่ถูกช่วยแล้ว (ถูกลบไปแล้ว)
function VictimSpawner.getRescuedVictimCount()
	local totalVictims = VictimSpawner.getTotalVictimCount()
	local currentVictims = 0
	
	-- นับ victims ที่ยังอยู่ใน workspace
	local victimFolder = Workspace:FindFirstChild("VictimFolders")
	if victimFolder then
		for _, victim in ipairs(victimFolder:GetChildren()) do
			if victim:IsA("Model") and victim.Name:match("^Victim_") then
				currentVictims = currentVictims + 1
			end
		end
	end
	
	-- จำนวนที่ช่วยแล้ว = ทั้งหมด - ที่เหลืออยู่
	return totalVictims - currentVictims
end

return VictimSpawner
