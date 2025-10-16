-- EnergyUI Module
-- จัดการ UI แสดงพลังงานของหุ่นยนต์

local Players = game:GetService("Players")

local EnergyUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ตัวแปร UI
local energyScreenGui = nil
local energyBar = nil
local energyLabel = nil

-- ค่าพลังงาน
local currentEnergy = 100
local maxEnergy = 100

-- ฟังก์ชันสร้าง Energy UI
local function createEnergyUI()
	if energyScreenGui then return energyScreenGui end

	-- สร้าง ScreenGui
	energyScreenGui = Instance.new("ScreenGui")
	energyScreenGui.Name = "EnergyGui"
	energyScreenGui.ResetOnSpawn = false
	energyScreenGui.DisplayOrder = 100
	energyScreenGui.IgnoreGuiInset = true
	energyScreenGui.Parent = playerGui

	-- สร้าง Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "EnergyFrame"
	mainFrame.Size = UDim2.new(0.2, 0, 0.08, 0)
	mainFrame.Position = UDim2.new(0.5, 0, 0.05, 0) -- กลางบน
	mainFrame.AnchorPoint = Vector2.new(0.5, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(40, 44, 52)
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = energyScreenGui

	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = UDim.new(0.15, 0)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(70, 75, 85)
	mainStroke.Thickness = 2
	mainStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	mainStroke.Parent = mainFrame

	-- เพิ่ม Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.15, 0)
	padding.PaddingBottom = UDim.new(0.15, 0)
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = mainFrame

	-- สร้างไอคอนแบตเตอรี่
	local batteryIcon = Instance.new("TextLabel")
	batteryIcon.Name = "BatteryIcon"
	batteryIcon.Size = UDim2.fromScale(0.15, 0.6)
	batteryIcon.Position = UDim2.fromScale(0, 0.2)
	batteryIcon.BackgroundTransparency = 1
	batteryIcon.Font = Enum.Font.GothamBold
	batteryIcon.Text = "BAT"
	batteryIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	batteryIcon.TextScaled = true
	batteryIcon.TextXAlignment = Enum.TextXAlignment.Center
	batteryIcon.TextYAlignment = Enum.TextYAlignment.Center
	batteryIcon.Parent = mainFrame

	local textSizeConstraint = Instance.new("UITextSizeConstraint")
	textSizeConstraint.MaxTextSize = 28
	textSizeConstraint.MinTextSize = 10
	textSizeConstraint.Parent = batteryIcon

	-- สร้าง Label "Energy"
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.fromScale(0.7, 0.3)
	titleLabel.Position = UDim2.fromScale(0.2, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamMedium
	titleLabel.Text = "Energy"
	titleLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = mainFrame

	local titleSizeConstraint = Instance.new("UITextSizeConstraint")
	titleSizeConstraint.MaxTextSize = 14
	titleSizeConstraint.MinTextSize = 8
	titleSizeConstraint.Parent = titleLabel

	-- สร้าง Background ของ Energy Bar
	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.fromScale(0.7, 0.4)
	barBackground.Position = UDim2.fromScale(0.2, 0.5)
	barBackground.BackgroundColor3 = Color3.fromRGB(25, 28, 33)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = mainFrame

	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0.2, 0)
	barBgCorner.Parent = barBackground

	local barBgStroke = Instance.new("UIStroke")
	barBgStroke.Color = Color3.fromRGB(60, 65, 75)
	barBgStroke.Thickness = 1
	barBgStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	barBgStroke.Parent = barBackground

	-- สร้าง Energy Bar (แถบสีเขียว)
	energyBar = Instance.new("Frame")
	energyBar.Name = "EnergyBar"
	energyBar.Size = UDim2.fromScale(0.98, 0.85)
	energyBar.Position = UDim2.fromScale(0.01, 0.075)
	energyBar.BackgroundColor3 = Color3.fromRGB(76, 209, 55)
	energyBar.BorderSizePixel = 0
	energyBar.Parent = barBackground

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0.15, 0)
	barCorner.Parent = energyBar

	-- เพิ่ม Gradient ให้สวยงาม
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 230, 70)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 190, 40))
	})
	gradient.Rotation = 90
	gradient.Parent = energyBar

	-- สร้าง Label แสดงเปอร์เซ็นต์
	energyLabel = Instance.new("TextLabel")
	energyLabel.Name = "EnergyLabel"
	energyLabel.Size = UDim2.fromScale(1, 1)
	energyLabel.BackgroundTransparency = 1
	energyLabel.Font = Enum.Font.GothamBold
	energyLabel.Text = "100%"
	energyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	energyLabel.TextScaled = true
	energyLabel.TextStrokeTransparency = 0.5
	energyLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	energyLabel.ZIndex = 2
	energyLabel.Parent = barBackground

	local labelSizeConstraint = Instance.new("UITextSizeConstraint")
	labelSizeConstraint.MaxTextSize = 14
	labelSizeConstraint.MinTextSize = 8
	labelSizeConstraint.Parent = energyLabel

	print("Energy UI created successfully")
	return energyScreenGui
end

-- ฟังก์ชันอัพเดทพลังงาน
function EnergyUI.setEnergy(energy, max)
	if not energyScreenGui then
		createEnergyUI()
	end

	max = max or maxEnergy
	energy = math.clamp(energy, 0, max)

	currentEnergy = energy
	maxEnergy = max

	-- คำนวณเปอร์เซ็นต์
	local percentage = (currentEnergy / maxEnergy) * 100
	local scale = currentEnergy / maxEnergy

	-- อัพเดท Bar
	if energyBar then
		energyBar.Size = UDim2.fromScale(scale * 0.98, 0.85)

		-- เปลี่ยนสีตามระดับพลังงาน
		if percentage > 60 then
			-- สีเขียว
			energyBar.BackgroundColor3 = Color3.fromRGB(76, 209, 55)
			local gradient = energyBar:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(100, 230, 70)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 190, 40))
				})
			end
		elseif percentage > 30 then
			-- สีเหลือง
			energyBar.BackgroundColor3 = Color3.fromRGB(241, 196, 15)
			local gradient = energyBar:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 210, 50)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(220, 170, 20))
				})
			end
		else
			-- สีแดง
			energyBar.BackgroundColor3 = Color3.fromRGB(231, 76, 60)
			local gradient = energyBar:FindFirstChildOfClass("UIGradient")
			if gradient then
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 80)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 50, 40))
				})
			end
		end
	end

	-- อัพเดท Label
	if energyLabel then
		energyLabel.Text = string.format("%d%%", math.floor(percentage))
	end
end

-- ฟังก์ชันเพิ่มพลังงาน
function EnergyUI.addEnergy(amount)
	EnergyUI.setEnergy(currentEnergy + amount, maxEnergy)
end

-- ฟังก์ชันลดพลังงาน
function EnergyUI.reduceEnergy(amount)
	EnergyUI.setEnergy(currentEnergy - amount, maxEnergy)
end

-- ฟังก์ชันดึงค่าพลังงานปัจจุบัน
function EnergyUI.getEnergy()
	return currentEnergy, maxEnergy
end

-- ฟังก์ชัน Initialize
function EnergyUI.init()
	createEnergyUI()
	EnergyUI.setEnergy(100, 100)
	print("EnergyUI initialized")
end

return EnergyUI
