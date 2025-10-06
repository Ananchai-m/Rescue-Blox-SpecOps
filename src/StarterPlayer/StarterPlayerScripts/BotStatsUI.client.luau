--!strict
-- BotStatsUI.client.luau
-- แสดง HP และ Battery ของ RescueBot มุมซ้ายล่าง (เฉพาะตอนเป็น RescueBot)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- สร้าง ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BotStatsUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- สร้าง Container (มุมซ้ายล่าง)
local container = Instance.new("Frame")
container.Name = "StatsContainer"
container.Size = UDim2.new(0, 250, 0, 85)
container.Position = UDim2.new(0, 20, 1, -105)
container.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
container.BackgroundTransparency = 0.3
container.BorderSizePixel = 0
container.Visible = false -- ซ่อนตอนเริ่มต้น
container.Parent = screenGui

-- Corner radius
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = container

-- Padding
local padding = Instance.new("UIPadding")
padding.PaddingTop = UDim.new(0, 10)
padding.PaddingBottom = UDim.new(0, 10)
padding.PaddingLeft = UDim.new(0, 15)
padding.PaddingRight = UDim.new(0, 15)
padding.Parent = container

-- HP Bar Container
local hpContainer = Instance.new("Frame")
hpContainer.Name = "HPContainer"
hpContainer.Size = UDim2.new(1, 0, 0, 25)
hpContainer.Position = UDim2.new(0, 0, 0, 0)
hpContainer.BackgroundTransparency = 1
hpContainer.Parent = container

local hpLabel = Instance.new("TextLabel")
hpLabel.Name = "HPLabel"
hpLabel.Size = UDim2.new(0, 40, 1, 0)
hpLabel.BackgroundTransparency = 1
hpLabel.Text = "HP"
hpLabel.TextColor3 = Color3.fromRGB(255, 100, 100)
hpLabel.TextSize = 14
hpLabel.Font = Enum.Font.GothamBold
hpLabel.TextXAlignment = Enum.TextXAlignment.Left
hpLabel.Parent = hpContainer

local hpBarBg = Instance.new("Frame")
hpBarBg.Name = "HPBarBg"
hpBarBg.Size = UDim2.new(1, -50, 1, 0)
hpBarBg.Position = UDim2.new(0, 50, 0, 0)
hpBarBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
hpBarBg.BorderSizePixel = 0
hpBarBg.Parent = hpContainer

local hpBarCorner = Instance.new("UICorner")
hpBarCorner.CornerRadius = UDim.new(0, 5)
hpBarCorner.Parent = hpBarBg

local hpBar = Instance.new("Frame")
hpBar.Name = "HPBar"
hpBar.Size = UDim2.new(1, 0, 1, 0)
hpBar.BackgroundColor3 = Color3.fromRGB(255, 100, 100)
hpBar.BorderSizePixel = 0
hpBar.Parent = hpBarBg

local hpBarCorner2 = Instance.new("UICorner")
hpBarCorner2.CornerRadius = UDim.new(0, 5)
hpBarCorner2.Parent = hpBar

local hpText = Instance.new("TextLabel")
hpText.Name = "HPText"
hpText.Size = UDim2.new(1, 0, 1, 0)
hpText.BackgroundTransparency = 1
hpText.Text = "100/100"
hpText.TextColor3 = Color3.fromRGB(255, 255, 255)
hpText.TextSize = 12
hpText.Font = Enum.Font.Gotham
hpText.ZIndex = 2
hpText.Parent = hpBarBg

-- Battery Bar Container
local batteryContainer = Instance.new("Frame")
batteryContainer.Name = "BatteryContainer"
batteryContainer.Size = UDim2.new(1, 0, 0, 25)
batteryContainer.Position = UDim2.new(0, 0, 0, 35)
batteryContainer.BackgroundTransparency = 1
batteryContainer.Parent = container

local batteryLabel = Instance.new("TextLabel")
batteryLabel.Name = "BatteryLabel"
batteryLabel.Size = UDim2.new(0, 40, 1, 0)
batteryLabel.BackgroundTransparency = 1
batteryLabel.Text = "BAT"
batteryLabel.TextColor3 = Color3.fromRGB(100, 200, 255)
batteryLabel.TextSize = 14
batteryLabel.Font = Enum.Font.GothamBold
batteryLabel.TextXAlignment = Enum.TextXAlignment.Left
batteryLabel.Parent = batteryContainer

local batteryBarBg = Instance.new("Frame")
batteryBarBg.Name = "BatteryBarBg"
batteryBarBg.Size = UDim2.new(1, -50, 1, 0)
batteryBarBg.Position = UDim2.new(0, 50, 0, 0)
batteryBarBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
batteryBarBg.BorderSizePixel = 0
batteryBarBg.Parent = batteryContainer

local batteryBarCorner = Instance.new("UICorner")
batteryBarCorner.CornerRadius = UDim.new(0, 5)
batteryBarCorner.Parent = batteryBarBg

local batteryBar = Instance.new("Frame")
batteryBar.Name = "BatteryBar"
batteryBar.Size = UDim2.new(1, 0, 1, 0)
batteryBar.BackgroundColor3 = Color3.fromRGB(100, 200, 255)
batteryBar.BorderSizePixel = 0
batteryBar.Parent = batteryBarBg

local batteryBarCorner2 = Instance.new("UICorner")
batteryBarCorner2.CornerRadius = UDim.new(0, 5)
batteryBarCorner2.Parent = batteryBar

local batteryText = Instance.new("TextLabel")
batteryText.Name = "BatteryText"
batteryText.Size = UDim2.new(1, 0, 1, 0)
batteryText.BackgroundTransparency = 1
batteryText.Text = "100/100"
batteryText.TextColor3 = Color3.fromRGB(255, 255, 255)
batteryText.TextSize = 12
batteryText.Font = Enum.Font.Gotham
batteryText.ZIndex = 2
batteryText.Parent = batteryBarBg

-- ฟังก์ชันอัปเดต HP
local function updateHP(current: number, max: number)
	local percentage = math.clamp(current / max, 0, 1)
	hpBar:TweenSize(
		UDim2.new(percentage, 0, 1, 0),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quad,
		0.2,
		true
	)
	hpText.Text = `{math.floor(current)}/{max}`
end

-- ฟังก์ชันอัปเดต Battery
local function updateBattery(current: number, max: number)
	local percentage = math.clamp(current / max, 0, 1)
	batteryBar:TweenSize(
		UDim2.new(percentage, 0, 1, 0),
		Enum.EasingDirection.Out,
		Enum.EasingStyle.Quad,
		0.2,
		true
	)
	batteryText.Text = `{math.floor(current)}/{max}`
end

-- ค่าเริ่มต้น
local maxHP = 100
local currentHP = 100
local maxBattery = 100
local currentBattery = 100

updateHP(currentHP, maxHP)
updateBattery(currentBattery, maxBattery)

-- ฟังก์ชันตรวจสอบว่าเป็น RescueBot หรือไม่
local function checkIfRescueBot()
	-- ตรวจสอบจาก workspace ว่ามี RescueBot ของผู้เล่นหรือไม่
	local rescueModelName = player.Name .. "_Rescue"
	local rescueModel = workspace:FindFirstChild(rescueModelName)

	if rescueModel then
		container.Visible = true
		print("[BotStatsUI] RescueBot detected:", rescueModelName)
		return true
	else
		container.Visible = false
		return false
	end
end

-- ตรวจสอบเมื่อ character spawn
local function onCharacterAdded(character: Model)
	-- รอให้ RescueBot spawn
	task.wait(0.5)
	checkIfRescueBot()
end

-- ตรวจสอบทุก 1 วินาที (เพื่อตรวจจับเมื่อ spawn RescueBot)
task.spawn(function()
	while true do
		checkIfRescueBot()
		task.wait(1)
	end
end)

-- เชื่อมต่อ events
player.CharacterAdded:Connect(onCharacterAdded)

-- ตรวจสอบ character ปัจจุบัน (ถ้ามี)
if player.Character then
	onCharacterAdded(player.Character)
end

-- เชื่อมต่อกับระบบ HP/Battery จริง
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local updateHPRemote = remoteEvents:WaitForChild("UpdateHP")
local updateBatteryRemote = remoteEvents:WaitForChild("UpdateBattery")

updateHPRemote.OnClientEvent:Connect(function(hp, maxHp)
	currentHP = hp
	maxHP = maxHp
	updateHP(currentHP, maxHP)
end)

updateBatteryRemote.OnClientEvent:Connect(function(battery, maxBat)
	currentBattery = battery
	maxBattery = maxBat
	updateBattery(currentBattery, maxBattery)
end)

print("[BotStatsUI] UI initialized")
