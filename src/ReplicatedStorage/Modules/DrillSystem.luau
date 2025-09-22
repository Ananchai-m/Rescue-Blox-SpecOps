-- DrillSystem ModuleScript
-- จัดการระบบการเจาะและทำลาย Motor6D

local DrillConfig = require(script.Parent.DrillConfig)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local DrillSystem = {}

-- Private variables
local drillingTargets = {} -- เก็บข้อมูลการเจาะแต่ละ part
local player = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

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

local function ensureDrillProgressGui()
	if drillGui then
		return
	end

	local playerGui = player:WaitForChild("PlayerGui")
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

local function findDrillablePartsNearPosition(position, range)
	local foundParts = {}
	local drillArmParts = {} -- เก็บ part ที่อยู่ใน DrillArm แยกต่างหาก

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

	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("BasePart") then
			-- ตรวจสอบว่า BasePart อยู่ใน Model ที่ต้องข้ามหรือไม่
			local shouldIgnore = false
			local isDrillArm = false
			local ancestor = obj.Parent
			while ancestor and ancestor ~= workspace do
				if ignoredModels[ancestor] then
					shouldIgnore = true
					break
				end
				-- ตรวจสอบชื่อ Model ที่มี "DrillArm" หรือชื่อผู้เล่น
				if ancestor:IsA("Model") then
					local modelName = ancestor.Name
					if string.find(modelName, "DrillArm") then
						isDrillArm = true
						break
					elseif string.find(modelName, player.Name .. "_Rescue") or
					       string.find(modelName, player.Name .. "_RescueCompanion") then
						shouldIgnore = true
						break
					end
				end
				ancestor = ancestor.Parent
			end

			-- ตรวจสอบระยะห่าง
			local distance = (obj.Position - position).Magnitude
			if distance <= range then
				-- ตรวจสอบว่ามี Motor6D อยู่ข้างใน
				local motor6d = obj:FindFirstChildOfClass("Motor6D")
				if motor6d then
					if isDrillArm then
						-- เก็บ DrillArm parts แยก
						table.insert(drillArmParts, {
							part = obj,
							motor6d = motor6d,
							distance = distance
						})
					elseif not shouldIgnore then
						-- เก็บ parts ปกติที่เจาะได้
						table.insert(foundParts, {
							part = obj,
							motor6d = motor6d,
							distance = distance
						})
					end
				end
			end
		end
	end

	-- เรียงตามระยะใกล้ที่สุด
	table.sort(foundParts, function(a, b)
		return a.distance < b.distance
	end)

	table.sort(drillArmParts, function(a, b)
		return a.distance < b.distance
	end)

	return foundParts, drillArmParts
end

local function checkDrillArmCollision()
	-- หา DrillArm Model ทั้งหมดใน workspace
	for _, obj in pairs(workspace:GetChildren()) do
		if obj:IsA("Model") and string.find(obj.Name, "DrillArm") then
			local drillArmPrimaryPart = obj.PrimaryPart
			if drillArmPrimaryPart then
				-- ตรวจสอบ BasePart ที่อยู่ใกล้ DrillArm.PrimaryPart
				local drillableParts = {}

				for _, part in pairs(workspace:GetDescendants()) do
					if part:IsA("BasePart") and part ~= drillArmPrimaryPart then
						-- ตรวจสอบว่าไม่ใช่ส่วนของ DrillArm เอง
						local isPartOfDrillArm = false
						local ancestor = part.Parent
						while ancestor and ancestor ~= workspace do
							if ancestor == obj then -- obj คือ DrillArm Model
								isPartOfDrillArm = true
								break
							end
							ancestor = ancestor.Parent
						end

						if not isPartOfDrillArm then
							-- ตรวจสอบการชนกัน (ใช้ Region3 หรือ distance)
							local distance = (part.Position - drillArmPrimaryPart.Position).Magnitude
							local combinedSize = (part.Size.Magnitude + drillArmPrimaryPart.Size.Magnitude) / 2

							if distance <= combinedSize then
								-- ตรวจสอบว่ามี Motor6D
								local motor6d = part:FindFirstChildOfClass("Motor6D")
								if motor6d then
									table.insert(drillableParts, {
										part = part,
										motor6d = motor6d,
										distance = distance,
										drillArmModel = obj
									})
								end
							end
						end
					end
				end

				-- ถ้าพบการชน
				if #drillableParts > 0 then
					-- เลือก part ที่ใกล้ที่สุด
					table.sort(drillableParts, function(a, b)
						return a.distance < b.distance
					end)

					local hitPart = drillableParts[1]
					return hitPart
				end
			end
		end
	end

	return nil
end

-- ===== DRILL LOGIC FUNCTIONS =====

local function startDrilling(partData)
	local part = partData.part
	local motor6d = partData.motor6d
	local partName = part.Name

	-- เริ่ม tracking การเจาะ
	if not drillingTargets[part] then
		drillingTargets[part] = {
			clicks = 0,
			motor6d = motor6d,
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

	-- ถ้าเจาะครบแล้ว
	if target.clicks >= target.requiredClicks then
		-- ทำลาย Motor6D
		if motor6d and motor6d.Parent then
			motor6d:Destroy()
			print("Motor6D destroyed for part:", partName)
		end

		-- อัพเดท payload
		payload.status = "complete"
		payload.progress = 1

		-- ล้างข้อมูลการเจาะ
		drillingTargets[part] = nil
	end

	-- แสดง UI
	showDrillProgress(payload)

	return target.clicks >= target.requiredClicks
end

-- ===== PUBLIC API =====

function DrillSystem.clearOldDrillingData()
	drillingTargets = {}
	print("Cleared old drilling data")
end

function DrillSystem.handleDrillingClick(clickPosition)
	-- ตรวจสอบการชนของ DrillArm.PrimaryPart ก่อน
	local drillArmHit = checkDrillArmCollision()
	if drillArmHit then
		print("DrillArm.PrimaryPart hit part:", drillArmHit.part.Name, "with Motor6D:", drillArmHit.motor6d.Name)

		-- แสดง UI แบบข้อมูลเท่านั้น (ไม่เจาะ)
		local payload = {
			partName = drillArmHit.part.Name,
			clicks = 0,
			requiredClicks = DrillConfig.CLICKS_REQUIRED,
			progress = 0,
			status = "info"
		}
		showDrillProgress(payload)

		-- ซ่อน UI หลัง 1 วินาที
		spawn(function()
			task.wait(1)
			hideDrillProgress()
		end)

		return true -- มี DrillArm ชน
	end

	-- หา BasePart ที่มี Motor6D ในระยะใกล้ (ปกติ)
	local drillableParts, drillArmParts = findDrillablePartsNearPosition(clickPosition, DrillConfig.DETECTION_RANGE)

	if #drillableParts > 0 then
		-- เลือก part ที่ใกล้ที่สุด
		local targetPart = drillableParts[1]
		local completed = startDrilling(targetPart)

		if completed then
			print("Drilling completed for:", targetPart.part.Name)
		else
			local target = drillingTargets[targetPart.part]
			print(string.format("Drilling %s... (%d/%d clicks)",
				target.partName, target.clicks, target.requiredClicks))
		end

		return true -- มี target ให้เจาะ
	end

	return false -- ไม่มี target ให้เจาะ
end

function DrillSystem.hideDrillProgress()
	hideDrillProgress()
end

-- Character update handler
player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
end)

return DrillSystem