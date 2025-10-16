--!strict
-- BotDeathUI.client.luau
-- แสดง Popup รอช่วยเหลือเมื่อ RescueBot พัง

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- สร้าง ScreenGui
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BotDeathUI"
screenGui.IgnoreGuiInset = true 
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder = 1000
screenGui.Parent = playerGui

-- สร้าง Background (มืด)
local background = Instance.new("Frame")
background.Name = "Background"
background.Size = UDim2.new(1, 0, 1, 0)
background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
background.BackgroundTransparency = 0.5
background.BorderSizePixel = 0
background.Visible = false
background.Parent = screenGui

-- สร้าง Popup Container
local popup = Instance.new("Frame")
popup.Name = "Popup"
popup.Size = UDim2.fromScale(0.21, 0.23)
popup.Position = UDim2.fromScale(0.5, 0.5)
popup.AnchorPoint = Vector2.new(0.5, 0.5)
popup.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
popup.BackgroundTransparency = 0.5
popup.BorderSizePixel = 0
popup.Parent = background

local popupCorner = Instance.new("UICorner")
popupCorner.CornerRadius = UDim.new(0.06, 0)
popupCorner.Parent = popup

local popupPadding = Instance.new("UIPadding")
popupPadding.PaddingTop = UDim.new(0.08, 0)
popupPadding.PaddingBottom = UDim.new(0.08, 0)
popupPadding.PaddingLeft = UDim.new(0.05, 0)
popupPadding.PaddingRight = UDim.new(0.05, 0)
popupPadding.Parent = popup

-- Title
local title = Instance.new("TextLabel")
title.Name = "Title"
title.Size = UDim2.fromScale(1, 0.2)
title.BackgroundTransparency = 1
title.Text = "RESCUE BOT พัง!"
title.TextColor3 = Color3.fromRGB(255, 100, 100)
title.TextScaled = true
title.Font = Enum.Font.GothamBold
title.TextWrapped = true
title.Parent = popup

local titleConstraint = Instance.new("UITextSizeConstraint")
titleConstraint.MaxTextSize = 28
titleConstraint.MinTextSize = 16
titleConstraint.Parent = title

-- Message
local message = Instance.new("TextLabel")
message.Name = "Message"
message.Size = UDim2.fromScale(1, 0.24)
message.Position = UDim2.fromScale(0, 0.24)
message.BackgroundTransparency = 1
message.Text = "รอเพื่อนมาช่วยเหลือ\nหรือรอจนหมดเวลา"
message.TextColor3 = Color3.fromRGB(255, 255, 255)
message.TextScaled = true
message.Font = Enum.Font.Gotham
message.TextWrapped = true
message.Parent = popup

local messageConstraint = Instance.new("UITextSizeConstraint")
messageConstraint.MaxTextSize = 18
messageConstraint.MinTextSize = 12
messageConstraint.Parent = message

-- Timer Label
local timerLabel = Instance.new("TextLabel")
timerLabel.Name = "Timer"
timerLabel.Size = UDim2.fromScale(1, 0.32)
timerLabel.Position = UDim2.fromScale(0, 0.6)
timerLabel.BackgroundTransparency = 1
timerLabel.Text = "30"
timerLabel.TextColor3 = Color3.fromRGB(255, 200, 100)
timerLabel.TextScaled = true
timerLabel.Font = Enum.Font.GothamBold
timerLabel.Parent = popup

local timerConstraint = Instance.new("UITextSizeConstraint")
timerConstraint.MaxTextSize = 60
timerConstraint.MinTextSize = 24
timerConstraint.Parent = timerLabel

local currentTimer: thread? = nil

-- ฟังก์ชันแสดง popup
local function showDeathPopup()
	background.Visible = true

	-- เริ่มนับถอยหลัง 30 วินาที
	if currentTimer then
		task.cancel(currentTimer)
	end

	local timeLeft = 30
	timerLabel.Text = tostring(timeLeft)

	currentTimer = task.spawn(function()
		while timeLeft > 0 do
			task.wait(1)
			timeLeft -= 1
			timerLabel.Text = tostring(timeLeft)

			-- เปลี่ยนสีเมื่อเวลาน้อย
			if timeLeft <= 10 then
				timerLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
			end
		end

		-- หมดเวลา
		timerLabel.Text = "หมดเวลา!"
	end)

	print("[BotDeathUI] Showing death popup")
end

-- ฟังก์ชันซ่อน popup
local function hideDeathPopup()
	background.Visible = false

	if currentTimer then
		task.cancel(currentTimer)
		currentTimer = nil
	end

	print("[BotDeathUI] Hiding death popup")
end

-- รับ event จาก server
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local botDeathEvent = remoteEvents:WaitForChild("BotDeath")

botDeathEvent.OnClientEvent:Connect(function(action)
	if action == "died" then
		-- ซ่อน DrillProgressGui
		local playerGui = player:WaitForChild("PlayerGui")
		local drillGui = playerGui:FindFirstChild("DrillProgressGui")
		if drillGui then
			drillGui:Destroy()
		end

		showDeathPopup()
	elseif action == "timeout" then
		-- หมดเวลา ซ่อน popup (GameSummary จะแสดงจาก server)
		hideDeathPopup()
		print("[BotDeathUI] Timeout - Summary will be shown by server")
	elseif action == "revived" then
		-- ถูกช่วยเหลือแล้ว
		hideDeathPopup()
		print("[BotDeathUI] Revived!")
	end
end)

print("[BotDeathUI] Initialized")
