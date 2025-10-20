-- DrillSystem ModuleScript
-- จัดการระบบการเจาะและทำลาย Motor6D

local DrillConfig = require(script.Parent.DrillConfig)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local CoinEffect = require(script.Parent.CoinEffect)

local DrillSystem = {}

-- ตรวจสอบว่าเป็น Mobile หรือไม่
local function isMobileDevice(): boolean
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local isMobile = isMobileDevice()
local PARTICLE_RATE_MULTIPLIER = if isMobile then 0.3 else 1 -- ลด particles 70% บน Mobile

-- Private variables
local drillingTargets = {} -- เก็บข้อมูลการเจาะแต่ละ part
local recentlyCompleted = {} -- เก็บ part ที่เพิ่งเจาะเสร็จเพื่อหลีกเลี่ยง
local currentDrillingPart = nil -- Part ที่กำลังเจาะอยู่
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()
local drillEffectStopTimer = nil -- Timer สำหรับหยุด effect
local playerGui = player:WaitForChild("PlayerGui")
local isSummaryOpen = false
local canDrill = true
local currentDrillSound = nil -- เก็บ Sound instance ปัจจุบัน
local drillSoundStopTimer = nil -- Timer สำหรับหยุดเสียงแบบ fade
local isFadingOut = false -- สถานะการ fade out

local rescueRemotes = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local botDeathRemote = rescueRemotes:WaitForChild("BotDeath")

-- Create or get drill effect remote
local drillEffectRemote = rescueRemotes:FindFirstChild("DrillEffect")
if not drillEffectRemote then
	drillEffectRemote = Instance.new("RemoteEvent")
	drillEffectRemote.Name = "DrillEffect"
	drillEffectRemote.Parent = rescueRemotes
end

-- Create or get drill sound remote
local drillSoundRemote = rescueRemotes:FindFirstChild("DrillSound")
if not drillSoundRemote then
	drillSoundRemote = Instance.new("RemoteEvent")
	drillSoundRemote.Name = "DrillSound"
	drillSoundRemote.Parent = rescueRemotes
end

-- Notify server about device type for physics optimization
local deviceTypeRemote = rescueRemotes:WaitForChild("DeviceType")
task.spawn(function()
	task.wait(1) -- Wait a bit for server to be ready
	deviceTypeRemote:FireServer(isMobile)
	print(string.format("[DeviceType] Notified server: %s", isMobile and "Mobile" or "Desktop"))
end)

-- UI Variables
local drillGui = nil
local drillContainer = nil
local drillPartLabel = nil
local drillStatusLabel = nil
local drillProgressBar = nil
local drillProgressFill = nil
local drillHideThread = nil

-- ===== UI FUNCTIONS =====

local function cancelDrillHideThread()
	if drillHideThread then
		task.cancel(drillHideThread)
		drillHideThread = nil
	end
end

local function destroyDrillGui()
	cancelDrillHideThread()
	if drillGui then
		drillGui:Destroy()
	end

	drillGui = nil
	drillContainer = nil
	drillPartLabel = nil
	drillStatusLabel = nil
	drillProgressBar = nil
	drillProgressFill = nil
end

local function ensureDrillProgressGui()
	-- ตรวจสอบว่ามี GUI อยู่แล้วและยังอยู่ใน PlayerGui หรือไม่
	if isSummaryOpen or not canDrill then
		return
	end
	if drillGui and drillGui.Parent == playerGui then
		return
	end

	print("[DrillSystem] Creating DrillProgressGui")
	drillGui = Instance.new("ScreenGui")
	drillGui.Name = "DrillProgressGui"
	drillGui.ResetOnSpawn = false
	drillGui.DisplayOrder = 500
	drillGui.Parent = playerGui

	drillContainer = Instance.new("Frame")
	drillContainer.Name = "Container"
	drillContainer.Size = UDim2.new(0, 260, 0, 90)
	drillContainer.Position = UDim2.new(0.5, -130, 0.78, 0)
	drillContainer.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	drillContainer.BackgroundTransparency = 0.2
	drillContainer.BorderSizePixel = 0
	drillContainer.Visible = false
	drillContainer.Parent = drillGui

	local containerCorner = Instance.new("UICorner")
	containerCorner.CornerRadius = UDim.new(0, 12)
	containerCorner.Parent = drillContainer

	drillPartLabel = Instance.new("TextLabel")
	drillPartLabel.Name = "PartLabel"
	drillPartLabel.Size = UDim2.new(1, -20, 0, 24)
	drillPartLabel.Position = UDim2.new(0, 10, 0, 10)
	drillPartLabel.BackgroundTransparency = 1
	drillPartLabel.Font = Enum.Font.GothamMedium
	drillPartLabel.Text = ""
	drillPartLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
	drillPartLabel.TextSize = 20
	drillPartLabel.TextWrapped = true
	drillPartLabel.Parent = drillContainer

	drillStatusLabel = Instance.new("TextLabel")
	drillStatusLabel.Name = "StatusLabel"
	drillStatusLabel.Size = UDim2.new(1, -20, 0, 20)
	drillStatusLabel.Position = UDim2.new(0, 10, 0, 40)
	drillStatusLabel.BackgroundTransparency = 1
	drillStatusLabel.Font = Enum.Font.Gotham
	drillStatusLabel.Text = ""
	drillStatusLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	drillStatusLabel.TextSize = 16
	drillStatusLabel.TextWrapped = true
	drillStatusLabel.Parent = drillContainer

	drillProgressBar = Instance.new("Frame")
	drillProgressBar.Name = "ProgressBar"
	drillProgressBar.Size = UDim2.new(1, -40, 0, 16)
	drillProgressBar.Position = UDim2.new(0, 20, 0, 62)
	drillProgressBar.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	drillProgressBar.BorderSizePixel = 0
	drillProgressBar.Parent = drillContainer

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 8)
	barCorner.Parent = drillProgressBar

	drillProgressFill = Instance.new("Frame")
	drillProgressFill.Name = "Fill"
	drillProgressFill.Size = UDim2.new(0, 0, 1, 0)
	drillProgressFill.Position = UDim2.new(0, 0, 0, 0)
	drillProgressFill.BackgroundColor3 = Color3.fromRGB(0, 170, 255)
	drillProgressFill.BorderSizePixel = 0
	drillProgressFill.Parent = drillProgressBar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 8)
	fillCorner.Parent = drillProgressFill
end

local function hideDrillProgress()
	cancelDrillHideThread()
	if drillContainer then
		drillContainer.Visible = false
	end
end

local function showDrillProgress(payload)
	ensureDrillProgressGui()

	if not drillContainer then
		warn("[DrillSystem] ERROR: drillContainer is nil!")
		return
	end

	if payload.status == "cancel" then
		hideDrillProgress()
		return
	end

	cancelDrillHideThread()
	drillContainer.Visible = true

	local partName = payload.partName or ""
	local clicks = payload.clicks or 0
	local required = payload.requiredClicks or 1
	local progress = math.clamp(payload.progress or 0, 0, 1)

	drillPartLabel.Text = partName ~= "" and partName or "Unknown Part"
	if payload.status == "complete" then
		drillStatusLabel.Text = string.format("เจาะสำเร็จ (%d/%d)", clicks, required)
	elseif payload.status == "info" then
		drillStatusLabel.Text = "DrillArm ตรวจพบ Part"
	else
		drillStatusLabel.Text = string.format("กำลังเจาะ... (%d/%d)", clicks, required)
	end
	drillProgressFill.Size = UDim2.new(progress, 0, 1, 0)

	if payload.status == "complete" then
		drillHideThread = task.delay(DrillConfig.HIDE_DELAY, function()
			drillHideThread = nil
			hideDrillProgress()
		end)
	end
end

-- ===== DRILL DETECTION FUNCTIONS =====

-- ฟังก์ชันเช็คว่า Part เป็น body part หรือไม่
local function isBodyPart(part)
	local bodyParts = {
		"LeftFoot", "LeftHand", "LeftLowerArm", "LeftLowerLeg", "LeftUpperArm", "LeftUpperLeg",
		"LowerTorso", "RightFoot", "RightHand", "RightLowerArm", "RightLowerLeg",
		"RightUpperArm", "RightUpperLeg", "UpperTorso", "Head", "HumanoidRootPart"
	}
	for _, bodyPartName in ipairs(bodyParts) do
		if part.Name == bodyPartName then
			return true
		end
	end
	return false
end

local function findDrillablePartsNearPosition(position, range)
	local foundParts = {}

	-- หา Obstacles folder (รองรับหลายตำแหน่ง)
	local obstaclesFolder = nil

	-- ลองหาใน Building_LV1 ก่อน
	local buildingLV1 = workspace:FindFirstChild("Building_LV1")
	if buildingLV1 then
		obstaclesFolder = buildingLV1:FindFirstChild("Obstacles")
	end

	-- ถ้าไม่เจอ ลองหาตรงๆ ใน workspace
	if not obstaclesFolder then
		obstaclesFolder = workspace:FindFirstChild("Obstacles")
	end

	-- ถ้ายังไม่เจอ ให้ใช้ทั้ง workspace
	local searchContainer = obstaclesFolder or workspace

	if not obstaclesFolder then
		print("DrillSystem: Obstacles folder not found, searching entire workspace")
	else
		print("DrillSystem: Found Obstacles at", obstaclesFolder:GetFullName())
	end

	-- รายชื่อ Model ที่ต้องข้าม
	local ignoredModels = {}

	-- เพิ่ม character ของผู้เล่นทุกคน
	for _, otherPlayer in pairs(Players:GetPlayers()) do
		if otherPlayer.Character then
			ignoredModels[otherPlayer.Character] = true
		end
	end

	-- เพิ่ม Rescue models ของผู้เล่นทุกคน
	for _, otherPlayer in pairs(Players:GetPlayers()) do
		local rescueCompanion = workspace:FindFirstChild(otherPlayer.Name .. "_RescueCompanion")
		local rescueModel = workspace:FindFirstChild(otherPlayer.Name .. "_Rescue")
		if rescueCompanion then
			ignoredModels[rescueCompanion] = true
		end
		if rescueModel then
			ignoredModels[rescueModel] = true
		end
	end

	-- เพิ่ม Victims ทั้งหมด
	for _, obj in pairs(workspace:GetChildren()) do
		if obj:IsA("Model") and string.find(obj.Name, "Victim_") then
			ignoredModels[obj] = true
		end
	end

	-- หา Part/MeshPart
	for _, obj in pairs(searchContainer:GetDescendants()) do
		if (obj:IsA("BasePart") or obj:IsA("MeshPart")) and obj.Anchored then
			-- ตรวจสอบว่าไม่อยู่ใน ignored models
			local shouldIgnore = false
			local ancestor = obj.Parent
			while ancestor and ancestor ~= workspace do
				if ignoredModels[ancestor] then
					shouldIgnore = true
					break
				end
				ancestor = ancestor.Parent
			end

			-- ตรวจสอบว่าไม่ใช่ body part
			if not shouldIgnore and not isBodyPart(obj) then
				-- ตรวจสอบระยะห่าง
				local distance = (obj.Position - position).Magnitude
				if distance <= range and not recentlyCompleted[obj] then
					-- เก็บ parts ที่เจาะได้
					table.insert(foundParts, {
						part = obj,
						distance = distance
					})
				end
			end
		end
	end

	-- เรียงตามระยะใกล้ที่สุด
	table.sort(foundParts, function(a, b)
		return a.distance < b.distance
	end)

	return foundParts
end


-- ===== DRILL LOGIC FUNCTIONS =====

-- ฟังก์ชันหาชิ้นที่ติดกันโดยใช้ Raycast ใน 6 ทิศทาง (เฉพาะใน Obstacles)
local function findConnectedParts(startPart, visitedParts, maxDepth)
	visitedParts = visitedParts or {}
	maxDepth = maxDepth or 3 -- จำกัดความลึกในการค้นหา (ป้องกันหาทั้งกอง)

	if maxDepth <= 0 or visitedParts[startPart] then
		return visitedParts
	end

	visitedParts[startPart] = true

	-- หา Obstacles folder (รองรับหลายตำแหน่ง)
	local obstaclesFolder = nil
	local buildingLV1 = workspace:FindFirstChild("Building_LV1")
	if buildingLV1 then
		obstaclesFolder = buildingLV1:FindFirstChild("Obstacles")
	end
	if not obstaclesFolder then
		obstaclesFolder = workspace:FindFirstChild("Obstacles")
	end

	-- เช็คว่า part อยู่ใน Obstacles folder หรือไม่ (เช็คจากชื่อ)
	local isInObstacles = false
	local ancestor = startPart.Parent
	while ancestor and ancestor ~= workspace do
		if ancestor.Name == "Obstacles" then
			isInObstacles = true
			break
		end
		ancestor = ancestor.Parent
	end

	if not isInObstacles then
		return visitedParts
	end

	-- ทิศทาง 6 ด้าน: บน, ล่าง, หน้า, หลัง, ซ้าย, ขวา
	local directions = {
		Vector3.new(0, 1, 0),   -- บน
		Vector3.new(0, -1, 0),  -- ล่าง
		Vector3.new(0, 0, 1),   -- หน้า
		Vector3.new(0, 0, -1),  -- หลัง
		Vector3.new(1, 0, 0),   -- ขวา
		Vector3.new(-1, 0, 0)   -- ซ้าย
	}

	-- คำนวณระยะ Raycast จาก Size ของ Part
	local partSize = startPart.Size
	local rayDistance = math.max(partSize.X, partSize.Y, partSize.Z) * 0.6 -- เช็คระยะใกล้ๆ

	-- สร้าง RaycastParams
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {character} -- ไม่เช็คตัวละคร

	for _, direction in ipairs(directions) do
		-- ยิง Ray จากจุดศูนย์กลางของ Part
		local origin = startPart.Position
		local rayDirection = direction * rayDistance

		local rayResult = workspace:Raycast(origin, rayDirection, rayParams)

		if rayResult and rayResult.Instance then
			local hitPart = rayResult.Instance

			-- ตรวจสอบว่า hitPart อยู่ใน Obstacles folder (เช็คจากชื่อ)
			local hitIsInObstacles = false
			local hitAncestor = hitPart.Parent
			while hitAncestor and hitAncestor ~= workspace do
				if hitAncestor.Name == "Obstacles" then
					hitIsInObstacles = true
					break
				end
				hitAncestor = hitAncestor.Parent
			end

			-- ตรวจสอบว่าเป็น BasePart/MeshPart, Anchored, อยู่ใน Obstacles, และยังไม่เคยเจอ
			if hitIsInObstacles and
			   (hitPart:IsA("BasePart") or hitPart:IsA("MeshPart")) and
			   hitPart.Anchored and
			   not visitedParts[hitPart] then
				-- เรียกตัวเองซ้ำเพื่อหา connected parts ต่อไป
				findConnectedParts(hitPart, visitedParts, maxDepth - 1)
			end
		end
	end

	return visitedParts
end

local function startDrilling(partData)
	local part = partData.part
	local partName = part.Name

	-- ตรวจสอบว่ากำลังเจาะ Part เดิมหรือไม่
	if currentDrillingPart and currentDrillingPart ~= part then
		-- เปลี่ยน Part ที่เจาะ - ล้างข้อมูลเก่า
		drillingTargets[currentDrillingPart] = nil
		hideDrillProgress()
	end

	-- อัปเดต Part ที่กำลังเจาะปัจจุบัน
	currentDrillingPart = part

	-- เริ่ม tracking การเจาะ
	if not drillingTargets[part] then
		drillingTargets[part] = {
			clicks = 0,
			partName = partName,
			requiredClicks = DrillConfig.CLICKS_REQUIRED
		}
	else
		-- อัปเดต requiredClicks ในกรณีที่ค่าเปลี่ยน
		drillingTargets[part].requiredClicks = DrillConfig.CLICKS_REQUIRED
	end

	local target = drillingTargets[part]
	target.clicks = target.clicks + 1

	-- แสดง progress
	local progress = target.clicks / target.requiredClicks
	local payload = {
		partName = partName,
		clicks = target.clicks,
		requiredClicks = target.requiredClicks,
		progress = progress,
		status = "progress"
	}

	-- ถ้าเจาะครบ 10 ครั้ง ให้กระเด็นเสมอ (แต่สุ่มความแรง)
	if target.clicks >= target.requiredClicks then
		-- อัพเดท payload - กระเด็นออก
		payload.status = "complete"
		payload.progress = 1

		-- สุ่มความแรงการกระเด็น (50% แรงมาก, 50% แรงปานกลาง)
		local ejectStrength = math.random(1, 100) <= 50 and "strong" or "weak"

		-- หา Rescue bot position สำหรับคำนวณทิศทางกระเด็น
		local rescueModelName = player.Name .. "_Rescue"
		local rescueModel = workspace:FindFirstChild(rescueModelName)
		local rescuePosition = nil
		if rescueModel and rescueModel.PrimaryPart then
			rescuePosition = rescueModel.PrimaryPart.Position
		end

		-- หาชิ้นที่ติดกันทั้งหมด
		local connectedParts = findConnectedParts(part)

		-- เตรียมข้อมูลส่งไป Server เพื่อจัดการ physics
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local remoteEventsFolder = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
		local drillCompleteRemote = remoteEventsFolder and remoteEventsFolder:FindFirstChild("DrillComplete")

		if drillCompleteRemote then
			-- สร้าง array ของข้อมูล parts ที่จะส่งไป server
			local connectedPartsData = {}
			for connectedPart, _ in pairs(connectedParts) do
				if (connectedPart:IsA("BasePart") or connectedPart:IsA("MeshPart")) then
					table.insert(connectedPartsData, {
						Name = connectedPart.Name,
						Position = connectedPart.Position,
						Instance = connectedPart
					})
				end
			end

			-- ส่งข้อมูลไป Server พร้อมข้อมูลความแรง
			local partData = {
				Name = part.Name,
				Position = part.Position,
				Instance = part
			}
			drillCompleteRemote:FireServer(partData, connectedPartsData, rescuePosition, ejectStrength)
		end

		-- ล้างข้อมูลการเจาะและเพิ่มเข้า recently completed
		drillingTargets[part] = nil
		currentDrillingPart = nil -- ล้าง Part ปัจจุบัน
		recentlyCompleted[part] = true

		-- ลบออกจาก recently completed หลัง 0.5 วินาที
		task.delay(0.5, function()
			recentlyCompleted[part] = nil
		end)
	end

	-- แสดง UI
	showDrillProgress(payload)

	return target.clicks >= target.requiredClicks
end

-- ===== PUBLIC API =====

-- ฟังก์ชันเปิด Particle Effects
local function enableDrillEffects()
	local rescueModelName = player.Name .. "_Rescue"
	local rescueModel = workspace:FindFirstChild(rescueModelName)

	if not rescueModel then return end

	local drillArm = rescueModel:FindFirstChild("DrillArm")
	if not drillArm then return end

	local head = drillArm:FindFirstChild("Head")
	if not head then return end

	-- Enable effects ใน AttachmentEffect1
	local attachment1 = head:FindFirstChild("AttachmentEffect1")
	if attachment1 then
		for _, effect in ipairs(attachment1:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				-- Optimize สำหรับ Mobile
				if isMobile and not effect:GetAttribute("OriginalRate") then
					effect:SetAttribute("OriginalRate", effect.Rate)
					effect.Rate = effect.Rate * PARTICLE_RATE_MULTIPLIER
				end
				effect.Enabled = true
			end
		end
	end

	-- Enable effects ใน AttachmentEffect2
	local attachment2 = head:FindFirstChild("AttachmentEffect2")
	if attachment2 then
		for _, effect in ipairs(attachment2:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				-- Optimize สำหรับ Mobile
				if isMobile and not effect:GetAttribute("OriginalRate") then
					effect:SetAttribute("OriginalRate", effect.Rate)
					effect.Rate = effect.Rate * PARTICLE_RATE_MULTIPLIER
				end
				effect.Enabled = true
			end
		end
	end
end

-- ฟังก์ชันปิด Particle Effects
local function disableDrillEffects()
	local rescueModelName = player.Name .. "_Rescue"
	local rescueModel = workspace:FindFirstChild(rescueModelName)

	if not rescueModel then return end

	local drillArm = rescueModel:FindFirstChild("DrillArm")
	if not drillArm then return end

	local head = drillArm:FindFirstChild("Head")
	if not head then return end

	-- Disable effects ใน AttachmentEffect1
	local attachment1 = head:FindFirstChild("AttachmentEffect1")
	if attachment1 then
		for _, effect in ipairs(attachment1:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				effect.Enabled = false
			end
		end
	end

	-- Disable effects ใน AttachmentEffect2
	local attachment2 = head:FindFirstChild("AttachmentEffect2")
	if attachment2 then
		for _, effect in ipairs(attachment2:GetChildren()) do
			if effect:IsA("ParticleEmitter") then
				effect.Enabled = false
			end
		end
	end
end

-- ฟังก์ชัน fade out เสียงเจาะ
local function fadeDrillSound()
	if not currentDrillSound or not currentDrillSound.IsPlaying then
		return
	end

	if isFadingOut then
		return
	end

	isFadingOut = true
	local startVolume = currentDrillSound.Volume
	local fadeTime = 0.3 -- 300ms
	local steps = 10
	local stepTime = fadeTime / steps
	local volumeDecrement = startVolume / steps

	task.spawn(function()
		for i = 1, steps do
			if not currentDrillSound or not currentDrillSound.Parent then
				break
			end
			currentDrillSound.Volume = math.max(0, currentDrillSound.Volume - volumeDecrement)
			task.wait(stepTime)
		end

		-- หยุดและลบเสียง
		if currentDrillSound then
			currentDrillSound:Stop()
			currentDrillSound:Destroy()
			currentDrillSound = nil
		end
		isFadingOut = false

		-- ส่งสัญญาณหยุดเสียงเจาะไปยัง server
		drillSoundRemote:FireServer("stop")
	end)
end

function DrillSystem.clearOldDrillingData()
	drillingTargets = {}
	recentlyCompleted = {}
	print("Cleared old drilling data and recently completed list")
end

function DrillSystem.clearProgressGui()
	destroyDrillGui()
end

if playerGui then
	playerGui.ChildAdded:Connect(function(child)
		if child.Name == "GameSummaryGui" then
			isSummaryOpen = true
			canDrill = false
			destroyDrillGui()

			-- หยุดเสียงเจาะเมื่อเกมจบ
			if currentDrillSound then
				currentDrillSound:Stop()
				currentDrillSound:Destroy()
				currentDrillSound = nil
				drillSoundRemote:FireServer("stop")
			end
			isFadingOut = false
		end
	end)

	playerGui.ChildRemoved:Connect(function(child)
		if child.Name == "GameSummaryGui" then
			isSummaryOpen = false
		end
	end)
end

botDeathRemote.OnClientEvent:Connect(function(status)
	if status == "died" or status == "timeout" then
		DrillSystem.setDrillEnabled(false)
	elseif status == "revived" then
		DrillSystem.setDrillEnabled(true)
	end
end)

-- ฟังก์ชันหา Part ที่ชนกับ DrillArm.PrimaryPart
local function findPartAtDrillArm()
	-- หา DrillArm Model ของผู้เล่น
	local rescueModelName = player.Name .. "_Rescue"
	local rescueModel = workspace:FindFirstChild(rescueModelName)

	if not rescueModel then
		return nil
	end

	-- หา DrillArm ใน RescueModel
	local drillArm = rescueModel:FindFirstChild("DrillArm")
	if not drillArm or not drillArm.PrimaryPart then
		return nil
	end

	local drillArmPrimaryPart = drillArm.PrimaryPart

	-- หา Obstacles folder
	local obstaclesFolder = nil
	local buildingLV1 = workspace:FindFirstChild("Building_LV1")
	if buildingLV1 then
		obstaclesFolder = buildingLV1:FindFirstChild("Obstacles")
	end
	if not obstaclesFolder then
		obstaclesFolder = workspace:FindFirstChild("Obstacles")
	end

	if not obstaclesFolder then
		return nil
	end

	-- ใช้ Raycast ยิงออกจาก DrillArm.PrimaryPart ตามทิศทางหน้าของ Rescue bot
	local rayOrigin = drillArmPrimaryPart.Position
	-- ถ้า LookVector ยิงไปซ้าย แสดงว่าต้องใช้ RightVector แทน (ข้างหน้าจริงๆ)
	local rayDirection = rescueModel.PrimaryPart.CFrame.RightVector * DrillConfig.DETECTION_RANGE

	-- ตั้งค่า RaycastParams
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {rescueModel, character}  -- ไม่ชน Rescue bot และ character

	-- สร้าง visual debug beam
	local function createDebugBeam(startPos, endPos, color)
		local attachment0 = Instance.new("Attachment")
		local attachment1 = Instance.new("Attachment")
		local part0 = Instance.new("Part")
		local part1 = Instance.new("Part")

		-- ตั้งค่า parts
		part0.Anchored = true
		part0.CanCollide = false
		part0.Transparency = 1
		part0.Size = Vector3.new(0.1, 0.1, 0.1)
		part0.Position = startPos
		part0.Parent = workspace

		part1.Anchored = true
		part1.CanCollide = false
		part1.Transparency = 1
		part1.Size = Vector3.new(0.1, 0.1, 0.1)
		part1.Position = endPos
		part1.Parent = workspace

		attachment0.Parent = part0
		attachment1.Parent = part1

		-- สร้าง beam
		local beam = Instance.new("Beam")
		beam.Attachment0 = attachment0
		beam.Attachment1 = attachment1
		beam.Color = ColorSequence.new(color)
		beam.Width0 = 0.3
		beam.Width1 = 0.3
		beam.FaceCamera = true
		beam.Parent = part0

		-- ลบหลัง 0.5 วินาที
		task.delay(0.5, function()
			part0:Destroy()
			part1:Destroy()
		end)
	end

	-- Raycast
	local rayResult = workspace:Raycast(rayOrigin, rayDirection, rayParams)

	if rayResult and rayResult.Instance then
		local hitPart = rayResult.Instance

		if (hitPart:IsA("BasePart") or hitPart:IsA("MeshPart")) then
			-- เช็คว่าอยู่ใน Obstacles folder
			local isInObstacles = false
			local ancestor = hitPart.Parent
			while ancestor and ancestor ~= workspace do
				if ancestor.Name == "Obstacles" then
					isInObstacles = true
					break
				end
				ancestor = ancestor.Parent
			end

			-- เช็คว่าไม่ใช่ body part และไม่ใช่ part ที่เพิ่งเจาะเสร็จ
			if isInObstacles and not isBodyPart(hitPart) and not recentlyCompleted[hitPart] then
				return {
					part = hitPart,
					distance = rayResult.Distance
				}
			end
		end
	end

	return nil
end

function DrillSystem.handleDrillingClick(clickPosition)
	if not canDrill then
		return false
	end

	-- หา DrillArm.PrimaryPart เพื่อเล่นเสียงเจาะ
	local rescueModelName = player.Name .. "_Rescue"
	local rescueModel = workspace:FindFirstChild(rescueModelName)
	local drillArmPart = nil

	if rescueModel then
		local drillArm = rescueModel:FindFirstChild("DrillArm")
		if drillArm and drillArm.PrimaryPart then
			drillArmPart = drillArm.PrimaryPart
		end
	end

	-- ยกเลิก timer fade out ถ้ามี (เพราะกำลังคลิกอีกครั้ง)
	if drillSoundStopTimer then
		task.cancel(drillSoundStopTimer)
		drillSoundStopTimer = nil
	end

	-- เล่นเสียงเจาะเฉพาะเมื่อไม่มีเสียงกำลังเล่นอยู่
	if drillArmPart then
		if not currentDrillSound or not currentDrillSound.IsPlaying or isFadingOut then
			-- ลบเสียงเก่าถ้ามี
			if currentDrillSound then
				currentDrillSound:Stop()
				currentDrillSound:Destroy()
				currentDrillSound = nil
			end

			isFadingOut = false

			-- สร้างเสียงใหม่
			currentDrillSound = Instance.new("Sound")
			currentDrillSound.SoundId = "rbxassetid://9118907884"
			currentDrillSound.Volume = 0.5 -- ลดเสียงลง 50%
			currentDrillSound.Looped = true -- ทำให้เสียงวนลูป
			currentDrillSound.Parent = drillArmPart
			currentDrillSound:Play()

			-- ส่งสัญญาณเสียงเจาะไปยัง server
			drillSoundRemote:FireServer("start")
		elseif currentDrillSound and isFadingOut then
			-- ถ้ากำลัง fade out อยู่ ให้ฟื้นฟู volume
			isFadingOut = false
			currentDrillSound.Volume = 0.5 -- ลดเสียงลง 50%
		end
	end

	-- เปิด Particle Effects เมื่อคลิก
	enableDrillEffects()

	-- ส่งสัญญาณไปยัง server เพื่อ broadcast ให้เพื่อนเห็น effect
	drillEffectRemote:FireServer("start")

	-- ยกเลิก timer เก่าถ้ามี
	if drillEffectStopTimer then
		task.cancel(drillEffectStopTimer)
	end

	-- ตั้ง timer ใหม่เพื่อปิด effects หลังหยุดคลิก 0.5 วินาที
	drillEffectStopTimer = task.delay(0.5, function()
		disableDrillEffects()
		drillEffectRemote:FireServer("stop")
		drillEffectStopTimer = nil
	end)

	-- ตั้ง timer สำหรับ fade out เสียงเจาะ
	if drillSoundStopTimer then
		task.cancel(drillSoundStopTimer)
	end

	drillSoundStopTimer = task.delay(0.5, function()
		fadeDrillSound()
		drillSoundStopTimer = nil
	end)

	-- ถ้ากำลังเจาะ part อยู่ ให้เจาะต่อไปเลยโดยไม่ต้องหา part ใหม่
	if currentDrillingPart and drillingTargets[currentDrillingPart] then
		local targetPart = {part = currentDrillingPart, distance = 0}
		startDrilling(targetPart)
		return true -- กำลังเจาะ part เดิมอยู่
	end

	-- ถ้ายังไม่มี target หรือเจาะเสร็จแล้ว ให้หา part ใหม่
	local targetPart = findPartAtDrillArm()

	if targetPart then
		startDrilling(targetPart)
		return true -- มี target ให้เจาะ
	end

	return false -- ไม่มี target ให้เจาะ
end

function DrillSystem.hideDrillProgress()
	hideDrillProgress()
end

function DrillSystem.showDrillProgress(payload)
	if not canDrill then
		destroyDrillGui()
		return
	end

	showDrillProgress(payload)
end

function DrillSystem.setDrillEnabled(isEnabled: boolean)
	canDrill = isEnabled
	if not canDrill then
		disableDrillEffects()
		destroyDrillGui()
		-- หยุดเสียงเจาะทันที
		if currentDrillSound then
			currentDrillSound:Stop()
			currentDrillSound:Destroy()
			currentDrillSound = nil
			-- ส่งสัญญาณหยุดเสียงไปยัง server
			drillSoundRemote:FireServer("stop")
		end
		isFadingOut = false
	end
end

-- ===== DISTANCE CHECK SYSTEM =====

-- ตรวจสอบระยะห่างจาก Part ที่กำลังเจาะ
local function checkDrillingDistance()
	if not currentDrillingPart then
		return
	end

	-- หา RescueOriginal Model ของผู้เล่น
	local rescueModelName = player.Name .. "_Rescue"
	local rescueModel = workspace:FindFirstChild(rescueModelName)

	if not rescueModel or not rescueModel.PrimaryPart then
		return
	end

	local rescuePrimaryPart = rescueModel.PrimaryPart
	local distance = (currentDrillingPart.Position - rescuePrimaryPart.Position).Magnitude

	-- ถ้าห่างเกิน DETECTION_RANGE + buffer ให้ reset
	local maxDistance = DrillConfig.DETECTION_RANGE + 5 -- เพิ่ม buffer 5 studs
	if distance > maxDistance then
		print("Rescue bot moved away from drilling target:", currentDrillingPart.Name, "Distance:", math.floor(distance), "Max:", maxDistance)

		-- ล้างข้อมูลการเจาะ
		if drillingTargets[currentDrillingPart] then
			print("Resetting drilling progress for:", currentDrillingPart.Name)
			drillingTargets[currentDrillingPart] = nil
		end
		currentDrillingPart = nil

		-- ซ่อน UI
		hideDrillProgress()
	end
end

-- เริ่ม loop เช็คระยะห่าง
RunService.Heartbeat:Connect(function()
	if currentDrillingPart then
		checkDrillingDistance()
	end
end)

-- Character update handler
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	-- ล้างข้อมูลเมื่อตัวละครใหม่
	drillingTargets = {}
	currentDrillingPart = nil
	hideDrillProgress()

	-- หยุดเสียงเจาะถ้ามี
	if currentDrillSound then
		currentDrillSound:Stop()
		currentDrillSound:Destroy()
		currentDrillSound = nil
		drillSoundRemote:FireServer("stop")
	end
	isFadingOut = false
end)

-- Listen for drill complete events from server (for coin effects)
local remoteEventsFolder = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local drillCompleteRemote = remoteEventsFolder:WaitForChild("DrillComplete")

drillCompleteRemote.OnClientEvent:Connect(function(position, coinAmount)
	-- Show coin effect when drilling is complete
	if position and coinAmount then
		CoinEffect.SpawnCoins(position, coinAmount, player)
	end
end)

-- Listen for drill effect events from other players
drillEffectRemote.OnClientEvent:Connect(function(otherPlayer, action)
	-- Don't apply effects to self (already handled locally)
	if otherPlayer == player then
		return
	end

	-- บน Mobile ปิด particle effects ของผู้เล่นอื่นเพื่อประหยัด performance
	if isMobile then
		print("[DrillSystem] Mobile device - skipping other players' drill effects for performance")
		return
	end

	-- Find the other player's rescue bot
	local rescueBotName = otherPlayer.Name .. "_Rescue"
	local rescueBot = workspace:FindFirstChild(rescueBotName)
	if not rescueBot then
		return
	end

	local drillArm = rescueBot:FindFirstChild("DrillArm")
	if not drillArm then
		return
	end

	local head = drillArm:FindFirstChild("Head")
	if not head then
		return
	end

	if action == "start" then
		-- Enable effects (ลด rate บน Mobile)
		local attachment1 = head:FindFirstChild("AttachmentEffect1")
		if attachment1 then
			for _, effect in ipairs(attachment1:GetChildren()) do
				if effect:IsA("ParticleEmitter") then
					-- Optimize สำหรับ Mobile
					if isMobile and not effect:GetAttribute("OriginalRate") then
						effect:SetAttribute("OriginalRate", effect.Rate)
						effect.Rate = effect.Rate * PARTICLE_RATE_MULTIPLIER
					end
					effect.Enabled = true
				end
			end
		end

		local attachment2 = head:FindFirstChild("AttachmentEffect2")
		if attachment2 then
			for _, effect in ipairs(attachment2:GetChildren()) do
				if effect:IsA("ParticleEmitter") then
					-- Optimize สำหรับ Mobile
					if isMobile and not effect:GetAttribute("OriginalRate") then
						effect:SetAttribute("OriginalRate", effect.Rate)
						effect.Rate = effect.Rate * PARTICLE_RATE_MULTIPLIER
					end
					effect.Enabled = true
				end
			end
		end
	elseif action == "stop" then
		-- Disable effects
		local attachment1 = head:FindFirstChild("AttachmentEffect1")
		if attachment1 then
			for _, effect in ipairs(attachment1:GetChildren()) do
				if effect:IsA("ParticleEmitter") then
					effect.Enabled = false
				end
			end
		end

		local attachment2 = head:FindFirstChild("AttachmentEffect2")
		if attachment2 then
			for _, effect in ipairs(attachment2:GetChildren()) do
				if effect:IsA("ParticleEmitter") then
					effect.Enabled = false
				end
			end
		end
	end
end)

-- Track other players' drill sounds
local otherPlayersDrillSounds = {}

-- Handle drill sound from other players
drillSoundRemote.OnClientEvent:Connect(function(otherPlayer, action)
	-- Don't apply sound to self (already handled locally)
	if otherPlayer == player then
		return
	end

	-- Find the other player's rescue bot
	local rescueBotName = otherPlayer.Name .. "_Rescue"
	local rescueBot = workspace:FindFirstChild(rescueBotName)
	if not rescueBot then
		return
	end

	local drillArm = rescueBot:FindFirstChild("DrillArm")
	if not drillArm or not drillArm.PrimaryPart then
		return
	end

	local drillArmPart = drillArm.PrimaryPart
	local playerKey = otherPlayer.UserId

	if action == "start" then
		-- Stop and remove old sound if exists
		if otherPlayersDrillSounds[playerKey] then
			otherPlayersDrillSounds[playerKey]:Stop()
			otherPlayersDrillSounds[playerKey]:Destroy()
			otherPlayersDrillSounds[playerKey] = nil
		end

		-- Create and play drill sound
		local drillSound = Instance.new("Sound")
		drillSound.SoundId = "rbxassetid://9118907884"
		drillSound.Volume = 0.4 -- ลดเสียงของผู้เล่นอื่นลง 50% (จาก 0.8)
		drillSound.Looped = true
		drillSound.Parent = drillArmPart
		drillSound:Play()

		otherPlayersDrillSounds[playerKey] = drillSound
		print(string.format("[DrillSound] Started drill sound for %s", otherPlayer.Name))

	elseif action == "stop" then
		-- Fade out and stop sound
		if otherPlayersDrillSounds[playerKey] then
			local sound = otherPlayersDrillSounds[playerKey]
			local startVolume = sound.Volume
			local fadeTime = 0.3
			local steps = 10
			local stepTime = fadeTime / steps
			local volumeDecrement = startVolume / steps

			task.spawn(function()
				for i = 1, steps do
					if not sound or not sound.Parent then
						break
					end
					sound.Volume = math.max(0, sound.Volume - volumeDecrement)
					task.wait(stepTime)
				end

				if sound then
					sound:Stop()
					sound:Destroy()
				end
				otherPlayersDrillSounds[playerKey] = nil
				print(string.format("[DrillSound] Stopped drill sound for %s", otherPlayer.Name))
			end)
		end
	end
end)

-- Clean up sounds when player leaves
Players.PlayerRemoving:Connect(function(leavingPlayer)
	local playerKey = leavingPlayer.UserId
	if otherPlayersDrillSounds[playerKey] then
		otherPlayersDrillSounds[playerKey]:Stop()
		otherPlayersDrillSounds[playerKey]:Destroy()
		otherPlayersDrillSounds[playerKey] = nil
	end
end)

return DrillSystem
