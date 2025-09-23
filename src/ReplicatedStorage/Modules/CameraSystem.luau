-- CameraSystem ModuleScript
-- จัดการระบบกล้อง, zoom, thermal vision และ humanoid detection

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CameraSystem = {}

-- ตัวแปรสำหรับระบบ
local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

-- Camera tracking variables
local isZoomMode = false
local originalCameraSubject = nil
local originalCameraType = nil
local cameraTrackConnection = nil
local originalFieldOfView = nil
local cameraZoomLevels = {1, 2, 5}
local zoomIndex = 1

-- Thermal vision variables
local isThermalMode = false
local thermalEffect = nil
local colorCorrection = nil
local originalFogEnd = nil
local humanoidHighlights = {}
local humanoidScanConnection = nil

-- ===== CAMERA ZOOM FUNCTIONS =====

local function applyCameraZoom()
	if not isZoomMode or not originalFieldOfView then return end
	local zoomFactor = cameraZoomLevels[zoomIndex] or 1
	if zoomFactor <= 0 then
		zoomFactor = 1
	end
	camera.FieldOfView = originalFieldOfView / zoomFactor
	print(string.format("CameraSystem: Zoom set to %.1fx", zoomFactor))
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

local function createHumanoidHighlight(humanoidCharacter)
	local highlight = Instance.new("Highlight")
	highlight.FillColor = Color3.new(1, 0.5, 0) -- สีส้ม
	highlight.OutlineColor = Color3.new(1, 0.3, 0) -- สีส้มเข้ม
	highlight.FillTransparency = 0.3
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = humanoidCharacter
	return highlight
end

local function scanForHumanoids()
	print("CameraSystem: Scanning for humanoids...")

	-- ล้าง highlight เก่า
	for character, highlight in pairs(humanoidHighlights) do
		if highlight then
			highlight:Destroy()
		end
	end
	humanoidHighlights = {}

	-- สแกนหา Humanoid ทั้งหมดใน workspace (รวม VictimFolders)
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("Model") and obj:FindFirstChildOfClass("Humanoid") then
			local humanoid = obj:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local highlight = createHumanoidHighlight(obj)
				humanoidHighlights[obj] = highlight
				print("CameraSystem: Detected humanoid:", obj.Name)
			end
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

	-- บันทึกค่าเดิม
	if not isZoomMode then
		originalCameraSubject = camera.CameraSubject
		originalCameraType = camera.CameraType
		isZoomMode = true
		originalFieldOfView = camera.FieldOfView
		zoomIndex = 1
	end

	-- ตั้งกล้องเป็น Scriptable
	camera.CameraType = Enum.CameraType.Scriptable
	applyCameraZoom()

	-- เริ่มติดตาม Camera part
	cameraTrackConnection = RunService.Heartbeat:Connect(function()
		if cameraPart.Parent then
			-- ยื่นกล้องไปข้างหน้า 5 studs ในทิศทางแกน X ของ BasePart
			local basePosition = cameraPart.Position
			local rightVector = cameraPart.CFrame.RightVector
			local cameraPosition = basePosition + (rightVector * 5)
			camera.CFrame = CFrame.lookAt(cameraPosition, cameraPosition + rightVector)
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