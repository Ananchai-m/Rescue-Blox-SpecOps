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
	mainCorner.CornerRadius = UDim.new(0, 12)
	mainCorner.Parent = mainFrame

	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(70, 75, 85)
	mainStroke.Thickness = 2
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
	batteryIcon.Size = UDim2.new(0.15, 0, 0.6, 0)
	batteryIcon.Position = UDim2.new(0, 0, 0.2, 0)
	batteryIcon.BackgroundTransparency = 1
	batteryIcon.Font = Enum.Font.GothamBold
	batteryIcon.Text = "🔋"
	batteryIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	batteryIcon.TextSize = 28
	batteryIcon.TextScaled = true
	batteryIcon.TextXAlignment = Enum.TextXAlignment.Center
	batteryIcon.TextYAlignment = Enum.TextYAlignment.Center
	batteryIcon.Parent = mainFrame

	-- สร้าง Label "Energy"
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(0.7, 0, 0.3, 0)
	titleLabel.Position = UDim2.new(0.2, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamMedium
	titleLabel.Text = "Energy"
	titleLabel.TextColor3 = Color3.fromRGB(200, 205, 215)
	titleLabel.TextSize = 14
	titleLabel.TextScaled = true
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = mainFrame

	-- สร้าง Background ของ Energy Bar
	local barBackground = Instance.new("Frame")
	barBackground.Name = "BarBackground"
	barBackground.Size = UDim2.new(0.7, 0, 0.4, 0)
	barBackground.Position = UDim2.new(0.2, 0, 0.5, 0)
	barBackground.BackgroundColor3 = Color3.fromRGB(25, 28, 33)
	barBackground.BorderSizePixel = 0
	barBackground.Parent = mainFrame

	local barBgCorner = Instance.new("UICorner")
	barBgCorner.CornerRadius = UDim.new(0, 8)
	barBgCorner.Parent = barBackground

	local barBgStroke = Instance.new("UIStroke")
	barBgStroke.Color = Color3.fromRGB(60, 65, 75)
	barBgStroke.Thickness = 1
	barBgStroke.Parent = barBackground

	-- สร้าง Energy Bar (แถบสีเขียว)
	energyBar = Instance.new("Frame")
	energyBar.Name = "EnergyBar"
	energyBar.Size = UDim2.new(1, -4, 1, -4)
	energyBar.Position = UDim2.new(0, 2, 0, 2)
	energyBar.BackgroundColor3 = Color3.fromRGB(76, 209, 55) -- สีเขียว
	energyBar.BorderSizePixel = 0
	energyBar.Parent = barBackground

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(0, 6)
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
	energyLabel.Size = UDim2.new(1, 0, 1, 0)
	energyLabel.BackgroundTransparency = 1
	energyLabel.Font = Enum.Font.GothamBold
	energyLabel.Text = "100%"
	energyLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	energyLabel.TextSize = 14
	energyLabel.TextStrokeTransparency = 0.5
	energyLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	energyLabel.ZIndex = 2
	energyLabel.Parent = barBackground

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
		energyBar.Size = UDim2.new(scale, -4, 1, -4)

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
