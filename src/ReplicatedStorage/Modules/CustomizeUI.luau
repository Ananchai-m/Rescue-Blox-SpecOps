-- CustomizeUI Module
-- จัดการ UI สำหรับปรับแต่งตัวละคร/หุ่นยนต์

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

-- Import TopbarPlus
local TopbarPlus = require(ReplicatedStorage.Packages.TopbarPlus)

local CustomizeUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

-- ตัวแปร UI
local customizeScreenGui = nil
local customizeFrame = nil
local customizeIcon = nil
local isCustomizeOpen = false
local isAnimating = false

-- ตัวแปรสำหรับ Preview
local previewBot = nil
local originalCameraCFrame = nil
local originalCameraType = nil

-- ตัวแปรสำหรับ Camera Rotation
local isDragging = false
local lastMousePosition = nil
local currentRotationAngle = 0
local baseCameraPosition = nil
local focusPoint = nil
local cameraDistance = 15
local originalFOV = nil
local inputBeganConnection = nil
local inputEndedConnection = nil
local inputChangedConnection = nil

-- ตัวแปรสำหรับพับแขน
local armsExtended = true -- true = พับ (0), false = เก็บ (180)

-- ฟังก์ชันสร้าง Customize Icon ด้วย TopbarPlus
local function createCustomizeIcon()
	if customizeIcon then return customizeIcon end

	-- สร้าง Icon ด้วย TopbarPlus
	customizeIcon = TopbarPlus.new()
		:setName("CustomizeIcon")
		:setImage("77453564007772") -- Customize icon
		:setLabel("Customize")
		:setOrder(2) -- วางถัดจาก Shop (order 1)

	-- Bind events
	customizeIcon.selected:Connect(function()
		CustomizeUI.openCustomize()
	end)

	customizeIcon.deselected:Connect(function()
		CustomizeUI.closeCustomize()
	end)

	print("[CustomizeUI] Created Customize icon with TopbarPlus")
	return customizeIcon
end

local function ensureCustomizeIcon()
	if customizeIcon then
		return customizeIcon
	end

	return createCustomizeIcon()
end

-- ฟังก์ชันสร้าง Customize UI
local function createCustomizeUI()
	if customizeScreenGui then return customizeScreenGui end

	-- สร้าง ScreenGui
	customizeScreenGui = Instance.new("ScreenGui")
	customizeScreenGui.Name = "CustomizeGui"
	customizeScreenGui.IgnoreGuiInset = true
	customizeScreenGui.ResetOnSpawn = false
	customizeScreenGui.DisplayOrder = 200
	customizeScreenGui.Enabled = false
	customizeScreenGui.Parent = playerGui

	-- สร้าง Background (มืดๆ ด้านหลัง)
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	background.BackgroundTransparency = 0.5
	background.BorderSizePixel = 0
	background.Parent = customizeScreenGui

	-- สร้าง Main Frame
	customizeFrame = Instance.new("Frame")
	customizeFrame.Name = "CustomizeFrame"
	customizeFrame.Size = UDim2.new(0.7, 0, 0.85, 0)
	customizeFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	customizeFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	customizeFrame.BackgroundColor3 = Color3.fromRGB(238, 240, 245)
	customizeFrame.BorderSizePixel = 0
	customizeFrame.Parent = customizeScreenGui

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(205, 208, 220)
	frameStroke.Thickness = 1
	frameStroke.Parent = customizeFrame

	-- สร้าง Top Bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0.12, 0)
	topBar.BackgroundColor3 = Color3.fromRGB(101, 105, 115)
	topBar.BorderSizePixel = 0
	topBar.Parent = customizeFrame

	local topPadding = Instance.new("UIPadding")
	topPadding.PaddingLeft = UDim.new(0.025, 0)
	topPadding.PaddingRight = UDim.new(0.025, 0)
	topPadding.Parent = topBar

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "SectionTitle"
	titleLabel.Size = UDim2.new(0.2, 0, 1, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.Text = "Customize"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextSize = 28
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = topBar

	local brandLabel = Instance.new("TextLabel")
	brandLabel.Name = "Brand"
	brandLabel.Size = UDim2.new(0.3, 0, 1, 0)
	brandLabel.Position = UDim2.new(0.5, 0, 0, 0)
	brandLabel.AnchorPoint = Vector2.new(0.5, 0)
	brandLabel.BackgroundTransparency = 1
	brandLabel.Font = Enum.Font.GothamBold
	brandLabel.Text = "Rescue Blox"
	brandLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	brandLabel.TextSize = 30
	brandLabel.TextScaled = true
	brandLabel.TextXAlignment = Enum.TextXAlignment.Center
	brandLabel.Parent = topBar

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0.045, 0, 0.45, 0)
	closeButton.Position = UDim2.new(1, 0, 0.5, 0)
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.BackgroundColor3 = Color3.fromRGB(236, 241, 246)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(80, 88, 103)
	closeButton.TextSize = 18
	closeButton.TextScaled = true
	closeButton.Parent = topBar

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0.2, 0)
	closeCorner.Parent = closeButton

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(198, 203, 215)
	closeStroke.Thickness = 1
	closeStroke.Parent = closeButton

	-- เชื่อมปุ่มปิด
	closeButton.MouseButton1Click:Connect(function()
		CustomizeUI.closeCustomize()
	end)

	-- สร้าง Content Area
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(0.96, 0, 0.82, 0)
	contentFrame.Position = UDim2.new(0.02, 0, 0.16, 0)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.Parent = customizeFrame

	-- Placeholder text
	local placeholderLabel = Instance.new("TextLabel")
	placeholderLabel.Size = UDim2.new(1, 0, 1, 0)
	placeholderLabel.BackgroundTransparency = 1
	placeholderLabel.Font = Enum.Font.GothamMedium
	placeholderLabel.Text = "Customize options coming soon..."
	placeholderLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
	placeholderLabel.TextSize = 24
	placeholderLabel.Parent = contentFrame

	print("Customize UI created successfully")
	return customizeScreenGui
end

-- ฟังก์ชัน Clone Rescue Bot และวางบน Garage.Base
local function setupPreviewBot()
	-- หา Rescue Model ใน ReplicatedStorage
	local rescueModel = ReplicatedStorage:FindFirstChild("Rescue")

	if not rescueModel then
		warn("[CustomizeUI] ไม่พบ Rescue ใน ReplicatedStorage")
		return
	end

	-- Clone bot
	previewBot = rescueModel:Clone()

	-- หา Garage.Base
	local garage = Workspace:FindFirstChild("Garage")
	if not garage then
		warn("[CustomizeUI] ไม่พบ Garage ใน Workspace")
		previewBot:Destroy()
		previewBot = nil
		return
	end

	local garageBase = garage:FindFirstChild("Base")
	if not garageBase then
		warn("[CustomizeUI] ไม่พบ Garage.Base")
		previewBot:Destroy()
		previewBot = nil
		return
	end

	-- วาง preview bot บน Garage.Base
	if previewBot.PrimaryPart then
		local basePosition = garageBase.Position
		local baseSizeY = garageBase.Size.Y
		local botSizeY = previewBot.PrimaryPart.Size.Y

		-- วางบนฐาน
		previewBot:PivotTo(CFrame.new(
			basePosition.X,
			basePosition.Y + (baseSizeY / 2) + (botSizeY / 2),
			basePosition.Z
		))
	end

	previewBot.Parent = Workspace
	print("[CustomizeUI] Preview bot spawned at Garage.Base")
end

-- ฟังก์ชัน Update Rescue Bot Rotation
local function updateBotRotation()
	if not previewBot or not previewBot.PrimaryPart then return end

	-- บันทึกตำแหน่งเดิม
	local originalPosition = previewBot.PrimaryPart.Position

	-- สร้าง CFrame ใหม่ด้วยมุม rotation รอบแกน Y
	local rotationCFrame = CFrame.new(originalPosition) * CFrame.Angles(0, math.rad(currentRotationAngle), 0)

	-- ใช้ PivotTo แทนเพื่อหมุนทั้ง Model รอบจุดเดียวกัน
	if previewBot.PrimaryPart then
		previewBot:PivotTo(rotationCFrame)
	end
end

-- ฟังก์ชันพับ/เก็บแขน
local function toggleArms()
	if not previewBot then return end

	-- สลับสถานะ
	armsExtended = not armsExtended

	-- กำหนด target angle
	local targetAngle = armsExtended and 0 or 180

	-- หา HingeConstraints ทั้งหมดในแขน
	for _, descendant in ipairs(previewBot:GetDescendants()) do
		if descendant:IsA("HingeConstraint") then
			-- ตั้งค่า TargetAngle
			descendant.TargetAngle = targetAngle
		end
	end

	print(string.format("[CustomizeUI] Arms %s (TargetAngle = %d)", armsExtended and "extended" or "folded", targetAngle))
end

-- ฟังก์ชัน Setup Camera Rotation Controls
local function setupCameraRotation()
	-- Disconnect existing connections
	if inputBeganConnection then inputBeganConnection:Disconnect() end
	if inputEndedConnection then inputEndedConnection:Disconnect() end
	if inputChangedConnection then inputChangedConnection:Disconnect() end

	-- Input Began - เริ่ม drag และ toggle arms
	inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = true
			lastMousePosition = UserInputService:GetMouseLocation()
		elseif input.KeyCode == Enum.KeyCode.Q then
			toggleArms()
		end
	end)

	-- Input Ended - หยุด drag
	inputEndedConnection = UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			isDragging = false
			lastMousePosition = nil
		end
	end)

	-- Input Changed - หมุน bot
	inputChangedConnection = UserInputService.InputChanged:Connect(function(input, gameProcessed)
		-- จัดการหมุน bot
		if isDragging and input.UserInputType == Enum.UserInputType.MouseMovement then
			local currentMousePosition = UserInputService:GetMouseLocation()

			if lastMousePosition then
				local delta = currentMousePosition - lastMousePosition
				local rotationSpeed = 0.3

				-- หมุนรอบแกน Y (เฉพาะ X delta) - เปลี่ยนเครื่องหมายเป็น + เพื่อให้ลากขวาหมุนขวา
				currentRotationAngle = currentRotationAngle + (delta.X * rotationSpeed)

				updateBotRotation()
			end

			lastMousePosition = currentMousePosition
		end
	end)

	print("[CustomizeUI] Bot rotation controls enabled")
end

-- ฟังก์ชัน Cleanup Camera Rotation Controls
local function cleanupCameraRotation()
	if inputBeganConnection then
		inputBeganConnection:Disconnect()
		inputBeganConnection = nil
	end
	if inputEndedConnection then
		inputEndedConnection:Disconnect()
		inputEndedConnection = nil
	end
	if inputChangedConnection then
		inputChangedConnection:Disconnect()
		inputChangedConnection = nil
	end

	isDragging = false
	lastMousePosition = nil
	currentRotationAngle = 0
	armsExtended = true

	print("[CustomizeUI] Bot rotation controls disabled")
end

-- ฟังก์ชัน Pan กล้องไปที่ Garage.Camera
local function panCameraToGarage()
	-- บันทึกตำแหน่งกล้องเดิม
	originalCameraCFrame = camera.CFrame
	originalCameraType = camera.CameraType
	originalFOV = camera.FieldOfView

	-- หา Garage.Camera
	local garage = Workspace:FindFirstChild("Garage")
	if not garage then
		warn("[CustomizeUI] ไม่พบ Garage")
		return
	end

	local garageCamera = garage:FindFirstChild("Camera")
	if not garageCamera then
		warn("[CustomizeUI] ไม่พบ Garage.Camera")
		return
	end

	-- ตั้งค่ากล้องเป็น Scriptable
	camera.CameraType = Enum.CameraType.Scriptable

	-- ตั้งค่า Field of View สำหรับ Customize mode
	camera.FieldOfView = 70

	-- Pan กล้องไปที่ Garage.Camera CFrame
	local targetCFrame = garageCamera.CFrame
	currentRotationAngle = 0

	-- Tween camera
	local cameraTweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local cameraTween = TweenService:Create(camera, cameraTweenInfo, {
		CFrame = targetCFrame
	})

	cameraTween:Play()

	-- Setup rotation controls หลัง tween เสร็จ
	cameraTween.Completed:Connect(function()
		setupCameraRotation()
	end)

	print("[CustomizeUI] Camera panned to Garage.Camera")
end

-- ฟังก์ชันคืนกล้องและลบ preview bot
local function cleanupPreview()
	-- Cleanup camera rotation controls
	cleanupCameraRotation()

	-- ลบ preview bot
	if previewBot then
		previewBot:Destroy()
		previewBot = nil
		print("[CustomizeUI] Preview bot removed")
	end

	-- คืนกล้องกลับ
	if originalCameraCFrame and originalCameraType then
		camera.CameraType = originalCameraType

		-- คืน FOV เดิม
		if originalFOV then
			camera.FieldOfView = originalFOV
		end

		local cameraTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local cameraTween = TweenService:Create(camera, cameraTweenInfo, {
			CFrame = originalCameraCFrame
		})

		cameraTween:Play()
		print("[CustomizeUI] Camera restored")
	end
end

-- ฟังก์ชันเปิด Customize
function CustomizeUI.openCustomize()
	if isCustomizeOpen then return end

	isCustomizeOpen = true

	-- ซ่อน Player List (GUI มุมขวาบน)
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

	-- Setup preview bot และ pan กล้อง
	setupPreviewBot()
	panCameraToGarage()

	print("Customize opened")
end

-- ฟังก์ชันปิด Customize
function CustomizeUI.closeCustomize()
	if not isCustomizeOpen then return end

	isCustomizeOpen = false

	-- แสดง Player List กลับ
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)

	-- Cleanup preview bot และคืนกล้อง
	cleanupPreview()

	-- Deselect TopbarPlus icon
	if customizeIcon then
		customizeIcon:deselect()
	end

	print("Customize closed")
end

-- ฟังก์ชัน Toggle Customize
function CustomizeUI.toggleCustomize()
	if isCustomizeOpen then
		CustomizeUI.closeCustomize()
	else
		CustomizeUI.openCustomize()
	end
end

-- ฟังก์ชัน Initialize Customize
function CustomizeUI.init()
	-- สร้าง Customize Icon ด้วย TopbarPlus (events ถูก bind แล้วใน createCustomizeIcon)
	ensureCustomizeIcon()

	print("CustomizeUI initialized")
end

function CustomizeUI.setButtonVisible(isVisible: boolean)
	local icon = ensureCustomizeIcon()
	if icon then
		-- TopbarPlus icons ใช้ :setEnabled() แทน Visible
		icon:setEnabled(isVisible)
	end

	if not isVisible then
		isCustomizeOpen = false
	end
end

return CustomizeUI
