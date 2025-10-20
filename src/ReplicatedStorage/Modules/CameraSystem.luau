-- CameraSystem ModuleScript
-- จัดการระบบกล้อง, zoom, thermal vision และ humanoid detection

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CameraSystem = {}

-- Import CustomizeService
local CustomizeService = require(ReplicatedStorage.Modules.CustomizeService)

-- ตัวแปรสำหรับระบบ
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Camera tracking variables
local isZoomMode = false
local originalCameraSubject = nil
local originalCameraType = nil
local cameraTrackConnection = nil
local originalFieldOfView = nil
local cameraZoomLevels = {1} -- Default: zoom ได้แค่ 1x
local zoomIndex = 1

-- Thermal vision variables
local isThermalMode = false
local thermalEffect = nil
local colorCorrection = nil
local originalFogEnd = nil
local humanoidHighlights = {}
local humanoidScanConnection = nil
local THERMAL_DETECTION_RANGE = 20 -- studs
local cameraYaw = 0
local cameraPitch = 0
local MAX_YAW = math.rad(180)
local MAX_PITCH = math.rad(180)
local MOUSE_SENSITIVITY = math.rad(0.3)
local originalMouseBehavior = nil
local originalMouseIconEnabled = nil
local zoomGui = nil
local zoomLabel = nil

-- ===== CAMERA ZOOM FUNCTIONS =====

-- ฟังก์ชันตรวจสอบและตั้งค่า zoom levels ตาม equipped items
local function updateZoomLevels()
	-- ดึง equipped items จาก server
	local equippedItems = CustomizeService.getEquippedItems()

	if not equippedItems or #equippedItems == 0 then
		-- ไม่มี equipment: zoom ได้แค่ 1x
		cameraZoomLevels = {1}
		print("[CameraSystem] No equipment: Zoom limited to 1x")
		return
	end

	-- เช็คว่ามี camera equipment ไหน
	local hasThermometerCamera = false
	local hasZoom3x5xCamera = false

	for _, equippedItem in ipairs(equippedItems) do
		if equippedItem.id == "ThermometerCamera" then
			hasThermometerCamera = true
		elseif equippedItem.id == "Zoom3x5xCamera" then
			hasZoom3x5xCamera = true
		end
	end

	-- ตั้งค่า zoom levels
	if hasZoom3x5xCamera then
		cameraZoomLevels = {1, 3, 5}
		print("[CameraSystem] Zoom 3x-5x Camera detected: Zoom levels {1x, 3x, 5x}")
	elseif hasThermometerCamera then
		cameraZoomLevels = {1, 2}
		print("[CameraSystem] Thermometer Camera detected: Zoom levels {1x, 2x}")
	else
		cameraZoomLevels = {1}
		print("[CameraSystem] No camera equipment: Zoom limited to 1x")
	end

	-- Reset zoom index ถ้าเกินขอบเขต
	if zoomIndex > #cameraZoomLevels then
		zoomIndex = #cameraZoomLevels
	end
end

local function ensureZoomGui()
	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then return end

	if zoomGui and zoomGui.Parent ~= playerGui then
		zoomGui:Destroy()
		zoomGui = nil
		zoomLabel = nil
	end

	if zoomGui and zoomGui.Parent then
		return
	end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "CameraStatusGui"
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui
	zoomGui = screenGui

	local label = Instance.new("TextLabel")
	label.Name = "ZoomLabel"
	label.Size = UDim2.new(0.085, 0, 0.039, 0)
	label.Position = UDim2.new(0.903, 0, 0.937, 0)
	label.BackgroundColor3 = Color3.fromRGB(10, 10, 10)
	label.BackgroundTransparency = 0.2
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.Text = "ZOOM 1.0X"
	label.Parent = screenGui
	zoomLabel = label
end

local function updateZoomLabel()
	if not isZoomMode then return end
	ensureZoomGui()
	if not zoomLabel then return end
	local zoomFactor = cameraZoomLevels[zoomIndex] or 1
	zoomLabel.Text = string.format("ZOOM %.1fX", zoomFactor)
	zoomLabel.Visible = true
end

local function applyCameraZoom()
	if not isZoomMode or not originalFieldOfView then return end
	local zoomFactor = cameraZoomLevels[zoomIndex] or 1
	if zoomFactor <= 0 then
		zoomFactor = 1
	end
	camera.FieldOfView = originalFieldOfView / zoomFactor
	print(string.format("CameraSystem: Zoom set to %.1fX", zoomFactor))
	updateZoomLabel()
end

function CameraSystem.setCameraZoomIndex(newIndex)
	local clamped = math.clamp(newIndex, 1, #cameraZoomLevels)
	if clamped == zoomIndex then return end
	zoomIndex = clamped
	applyCameraZoom()
end

function CameraSystem.setCameraZoomFactor(factor)
	for index, value in ipairs(cameraZoomLevels) do
		if value == factor then
			CameraSystem.setCameraZoomIndex(index)
			return
		end
	end
	print("CameraSystem: Requested zoom factor not available:", factor)
end

function CameraSystem.adjustCameraZoom(step)
	if #cameraZoomLevels == 0 then return end
	local newIndex = math.clamp(zoomIndex + step, 1, #cameraZoomLevels)
	if newIndex ~= zoomIndex then
		zoomIndex = newIndex
		applyCameraZoom()
	end
end

-- ===== HUMANOID DETECTION FUNCTIONS =====

local function createHumanoidHighlight(humanoidCharacter, canSeeThroughWalls)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 0.5, 0) -- สีส้ม
	highlight.OutlineColor = Color3.new(1, 0.3, 0) -- สีส้มเข้ม
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	-- ถ้ามี ThermometerCamera ให้เห็นทะลุกำแพง
	highlight.DepthMode = canSeeThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop or Enum.HighlightDepthMode.Occluded
	highlight.Parent = humanoidCharacter
	return highlight
end

local function applyMouseDelta(delta)
	if typeof(delta) ~= "Vector2" then return end
	if delta.Magnitude == 0 then return end
	cameraYaw = math.clamp(cameraYaw - (delta.X * MOUSE_SENSITIVITY), -MAX_YAW, MAX_YAW)
	cameraPitch = math.clamp(cameraPitch - (delta.Y * MOUSE_SENSITIVITY), -MAX_PITCH, MAX_PITCH)
end

local function scanForHumanoids()
	print("CameraSystem: Scanning for humanoids...")

	local detectionOrigin
	if camera and camera.CFrame then
		detectionOrigin = camera.CFrame.Position
	end

	if not detectionOrigin then
		return
	end

	-- เช็คว่ามี ThermometerCamera หรือไม่
	local equippedItems = CustomizeService.getEquippedItems()
	local hasThermometerCamera = false
	if equippedItems then
		for _, equippedItem in ipairs(equippedItems) do
			if equippedItem.id == "ThermometerCamera" then
				hasThermometerCamera = true
				break
			end
		end
	end

	-- เก็บรายชื่อ humanoid ที่เจอในรอบนี้
	local foundHumanoids = {}

	-- สแกนหา Humanoid ทั้งหมดใน workspace (รวม VictimFolders)
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
			local humanoid = obj:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local rootPart = obj.PrimaryPart or obj:FindFirstChild("HumanoidRootPart")
				if rootPart then
					local distance = (rootPart.Position - detectionOrigin).Magnitude
					if distance <= THERMAL_DETECTION_RANGE then
						-- ถ้ามี ThermometerCamera ให้เห็นทะลุกำแพงได้เลยตามระยะ THERMAL_DETECTION_RANGE
						if hasThermometerCamera then
							foundHumanoids[obj] = true
							-- ถ้ายังไม่มี highlight ให้สร้างใหม่
							if not humanoidHighlights[obj] then
								local highlight = createHumanoidHighlight(obj, true)
								humanoidHighlights[obj] = highlight
								print("CameraSystem: Detected humanoid (thermal through walls):", obj.Name)
							end
						end
					end
				end
			end
		end
	end

	-- ลบ highlight ที่ไม่ได้อยู่ในรายชื่อที่เจอ (ถอยออกนอกระยะแล้ว)
	for character, highlight in pairs(humanoidHighlights) do
		if not foundHumanoids[character] then
			if highlight then
				highlight:Destroy()
				print("CameraSystem: Removed highlight for:", character.Name)
			end
			humanoidHighlights[character] = nil
		end
	end
end

local function startHumanoidScanning()
	-- หยุด connection เก่า
	if humanoidScanConnection then
		humanoidScanConnection:Disconnect()
		humanoidScanConnection = nil
	end

	-- ใช้ timer-based approach
	local lastScanTime = 0
	local scanInterval = 2 -- สแกนทุก 2 วินาที

	humanoidScanConnection = RunService.Heartbeat:Connect(function()
		local currentTime = tick()
		if currentTime - lastScanTime >= scanInterval then
			scanForHumanoids()
			lastScanTime = currentTime
		end
	end)

	-- สแกนครั้งแรกทันที
	scanForHumanoids()
	print("CameraSystem: Humanoid scanning started")
end

local function stopHumanoidScanning()
	print("CameraSystem: Stopping humanoid scanning...")

	-- หยุด scanning
	if humanoidScanConnection then
		humanoidScanConnection:Disconnect()
		humanoidScanConnection = nil
	end

	-- ล้าง highlights ทั้งหมด
	local highlightCount = 0
	for character, highlight in pairs(humanoidHighlights) do
		if highlight and highlight.Parent then
			highlight:Destroy()
			highlightCount = highlightCount + 1
		end
	end
	humanoidHighlights = {}

	-- เพิ่มการลบ highlight ที่อาจค้างอยู่
	local orphanCount = 0
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Highlight") and obj.FillColor == Color3.new(1, 0.5, 0) then
			obj:Destroy()
			orphanCount = orphanCount + 1
		end
	end

	print("CameraSystem: Removed", highlightCount, "tracked highlights and", orphanCount, "orphan highlights")
end

-- ===== THERMAL VISION FUNCTIONS =====

local function createThermalEffect()
	-- สร้าง ScreenGui สำหรับ thermal effect
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ThermalVisionGui"
	screenGui.IgnoreGuiInset = true
	screenGui.Parent = player.PlayerGui

	-- สร้าง Frame ปิดทั้งหน้าจอ
	local frame = Instance.new("Frame")
	frame.Size = UDim2.new(1, 0, 1, 0)
	frame.Position = UDim2.new(0, 0, 0, 0)
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 0.3
	frame.BorderSizePixel = 0
	frame.Parent = screenGui

	-- สร้าง thermal overlay effect
	local thermalFrame = Instance.new("Frame")
	thermalFrame.Size = UDim2.new(1, 0, 1, 0)
	thermalFrame.Position = UDim2.new(0, 0, 0, 0)
	thermalFrame.BackgroundColor3 = Color3.new(0.2, 0.8, 1)
	thermalFrame.BackgroundTransparency = 0.7
	thermalFrame.BorderSizePixel = 0
	thermalFrame.Parent = frame

	-- เพิ่ม thermal text indicator
	local thermalLabel = Instance.new("TextLabel")
	thermalLabel.Size = UDim2.new(0, 200, 0, 50)
	thermalLabel.Position = UDim2.new(0, 10, 0, 50)
	thermalLabel.BackgroundTransparency = 1
	thermalLabel.Text = "THERMAL VISION"
	thermalLabel.TextColor3 = Color3.new(0, 1, 1)
	thermalLabel.TextScaled = true
	thermalLabel.Font = Enum.Font.Code
	thermalLabel.Parent = frame

	-- เพิ่มเอฟเฟกต์กระพริบ
	spawn(function()
		while thermalEffect and thermalEffect.Parent do
			thermalFrame.BackgroundTransparency = 0.7
			wait(0.5)
			if thermalEffect and thermalEffect.Parent then
				thermalFrame.BackgroundTransparency = 0.8
				wait(0.5)
			end
		end
	end)

	return screenGui
end

-- ===== CAMERA TRACKING FUNCTIONS =====

function CameraSystem.startCameraTracking()
	-- หยุด connection เก่า
	if cameraTrackConnection then
		cameraTrackConnection:Disconnect()
		cameraTrackConnection = nil
	end

	-- หา Camera part ใน rescue vehicle
	local rescueVehicle = workspace:FindFirstChild(player.Name .. "_Rescue")
	if not rescueVehicle then
		print("CameraSystem: No rescue vehicle found for camera tracking")
		return false
	end

	local cameraPart = rescueVehicle:FindFirstChild("Camera")
	if not cameraPart or not cameraPart:IsA("BasePart") then
		print("CameraSystem: No Camera part found in rescue vehicle")
		return false
	end

	-- อัปเดต zoom levels ตาม equipped items
	updateZoomLevels()

	-- บันทึกค่าเดิม
	if not isZoomMode then
		originalCameraSubject = camera.CameraSubject
		originalCameraType = camera.CameraType
		isZoomMode = true
		originalFieldOfView = camera.FieldOfView
		zoomIndex = 1
	end

	-- บันทึกค่า mouse behavior เดิม
	if not originalMouseBehavior then
		originalMouseBehavior = UserInputService.MouseBehavior
	end
	if originalMouseIconEnabled == nil then
		originalMouseIconEnabled = UserInputService.MouseIconEnabled
	end

	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	UserInputService.MouseIconEnabled = false
	cameraYaw = 0
	cameraPitch = 0
	ensureZoomGui()
	updateZoomLabel()

	-- ตั้งกล้องเป็น Scriptable
	camera.CameraType = Enum.CameraType.Scriptable
	applyCameraZoom()

	-- เริ่มติดตาม Camera part
	cameraTrackConnection = RunService.RenderStepped:Connect(function()
		if cameraPart.Parent then
			applyMouseDelta(UserInputService:GetMouseDelta())
			local baseCFrame = cameraPart.CFrame
			local rotation = CFrame.Angles(0, cameraYaw, 0) * CFrame.Angles(cameraPitch, 0, 0)
			local finalCFrame = baseCFrame * rotation
			local lookDirection = finalCFrame.RightVector
			local targetCameraPosition = finalCFrame.Position + (lookDirection * 5)

			-- กล้องเช็ค Raycast ปกติเสมอ (ไม่ทะลุกำแพง)
			local rayDirection = targetCameraPosition - finalCFrame.Position
			local rayDistance = rayDirection.Magnitude

			local raycastParams = RaycastParams.new()
			raycastParams.FilterDescendantsInstances = {rescueVehicle, player.Character}
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude

			local raycastResult = workspace:Raycast(finalCFrame.Position, rayDirection, raycastParams)

			local finalCameraPosition = targetCameraPosition
			if raycastResult then
				-- ถ้าชนสิ่งกีดขวาง ให้วางกล้องที่จุดชนแทน (ถอยห่างออกมา 0.5 studs)
				finalCameraPosition = raycastResult.Position - (rayDirection.Unit * 0.5)
			end

			camera.CFrame = CFrame.lookAt(finalCameraPosition, finalCameraPosition + lookDirection)
		else
			-- ถ้า Camera part หายไป ให้หยุดติดตาม
			CameraSystem.stopCameraTracking()
		end
	end)

	print("CameraSystem: Camera now tracking Camera part in rescue vehicle")
	return true
end

function CameraSystem.stopCameraTracking()
	print("CameraSystem: Stopping camera tracking...")

	-- หยุด tracking connection
	if cameraTrackConnection then
		cameraTrackConnection:Disconnect()
		cameraTrackConnection = nil
	end

	-- ปิด thermal vision ถ้าเปิดอยู่
	if isThermalMode then
		CameraSystem.toggleThermalVision() -- จะปิด thermal vision
	end

	-- หยุดสแกน Humanoid
	stopHumanoidScanning()

	-- กลับไปใช้กล้องปกติ
	if originalCameraSubject then
		camera.CameraSubject = originalCameraSubject
		camera.CameraType = originalCameraType or Enum.CameraType.Custom
	else
		camera.CameraType = Enum.CameraType.Custom
		local character = player.Character
		if character and character:FindFirstChild("Humanoid") then
			camera.CameraSubject = character.Humanoid
		end
	end

	if originalFieldOfView then
		camera.FieldOfView = originalFieldOfView
	end
	originalFieldOfView = nil
	zoomIndex = 1
	cameraYaw = 0
	cameraPitch = 0

	-- คืนค่า mouse behavior
	if originalMouseBehavior then
		UserInputService.MouseBehavior = originalMouseBehavior
		originalMouseBehavior = nil
	else
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end

	-- คืนค่า mouse icon
	if originalMouseIconEnabled ~= nil then
		UserInputService.MouseIconEnabled = originalMouseIconEnabled
		originalMouseIconEnabled = nil
	else
		UserInputService.MouseIconEnabled = true
	end
	if zoomGui then
		zoomGui:Destroy()
		zoomGui = nil
		zoomLabel = nil
	end

	isZoomMode = false
	print("CameraSystem: Camera tracking stopped - back to normal view")
end

function CameraSystem.toggleCameraTracking()
	if isZoomMode then
		CameraSystem.stopCameraTracking()
	else
		CameraSystem.startCameraTracking()
	end
end

function CameraSystem.toggleThermalVision()
	if not isZoomMode then
		print("CameraSystem: Thermal vision only works in camera tracking mode. Press Z first!")
		return
	end

	isThermalMode = not isThermalMode

	if isThermalMode then
		-- เปิด thermal vision
		thermalEffect = createThermalEffect()

		-- สร้าง ColorCorrection effect
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Brightness = 0.3
		colorCorrection.Contrast = 0.5
		colorCorrection.Saturation = -1
		colorCorrection.TintColor = Color3.new(0.7, 0.9, 1)
		colorCorrection.Parent = game.Lighting

		-- ปรับ Fog เพื่อให้มีบรรยากาศ thermal
		originalFogEnd = game.Lighting.FogEnd
		game.Lighting.FogColor = Color3.new(0.1, 0.3, 0.8)
		game.Lighting.FogEnd = originalFogEnd * 0.7

		-- เริ่มสแกน Humanoid
		startHumanoidScanning()

		print("CameraSystem: Thermal vision ENABLED with Humanoid detection")
	else
		-- ปิด thermal vision
		if thermalEffect then
			thermalEffect:Destroy()
			thermalEffect = nil
		end

		-- ลบ ColorCorrection effect
		if colorCorrection then
			colorCorrection:Destroy()
			colorCorrection = nil
		end

		-- คืนค่า Fog ปกติ
		if originalFogEnd then
			game.Lighting.FogEnd = originalFogEnd
			game.Lighting.FogColor = Color3.new(0.75, 0.75, 0.75)
		end

		-- หยุดสแกน Humanoid
		stopHumanoidScanning()

		print("CameraSystem: Thermal vision DISABLED")
	end
end

-- ===== GETTERS =====

function CameraSystem.isInZoomMode()
	return isZoomMode
end

function CameraSystem.isThermalActive()
	return isThermalMode
end

return CameraSystem
