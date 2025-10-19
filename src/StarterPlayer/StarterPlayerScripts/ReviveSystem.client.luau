--!strict
-- ReviveSystem.client.luau
-- ระบบช่วยเหลือเพื่อน RescueBot ที่พัง (แบบ Custom UI เหมือน Victim)

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Import GameConfig
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local reviveSettings = GameConfig.getRescueBotSettings().revive

-- Configuration
local REVIVE_DISTANCE = reviveSettings.maxDistance or 15
local HOLD_DURATION = reviveSettings.holdDuration or 5
local REVIVE_KEY = Enum.KeyCode.R

-- Variables
local nearestDownedBot: Model? = nil
local billboardGui: BillboardGui? = nil
local progressBg: Frame? = nil
local isReviving = false
local holdStartTime = 0
local progressFill: Frame? = nil
local heartbeatConnection: RBXScriptConnection? = nil
-- ลบ mobileReviveButton เพราะให้กดที่ billboard ได้เลย

-- RemoteEvents
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local reviveRemote = remoteEvents:WaitForChild("ReviveTeammate") :: RemoteEvent

-- Forward declarations
local startRevive: () -> ()
local stopRevive: (boolean) -> ()

-- สร้าง Billboard UI บนหุ่นยนต์ที่พัง
local function createBillboard(downedBot: Model): (BillboardGui?, Frame?)
	if not downedBot or not downedBot.PrimaryPart then
		return nil, nil
	end

	-- ลบ billboard เก่า
	if billboardGui then
		billboardGui:Destroy()
		billboardGui = nil
	end

	-- Create BillboardGui
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ReviveBillboard"
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.new(4, 0, 2, 0)
	billboard.StudsOffset = Vector3.new(0, 3, 0)
	billboard.Adornee = downedBot.PrimaryPart
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.ClipsDescendants = false
	billboard.Enabled = true
	billboard.Active = true
	billboard.Parent = downedBot

	-- Main frame (ทำเป็น TextButton เพื่อให้กดได้)
	local mainFrame = Instance.new("TextButton")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.Position = UDim2.new(0, 0, 0, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	mainFrame.BackgroundTransparency = 0.2
	mainFrame.BorderSizePixel = 0
	mainFrame.Text = ""
	mainFrame.AutoButtonColor = false
	mainFrame.Active = true
	mainFrame.Selectable = true
	mainFrame.Modal = false
	mainFrame.ZIndex = 10
	mainFrame.Parent = billboard

	-- ตัวแปรสำหรับติดตาม input state
	local isHolding = false

	-- ฟังก์ชันตรวจสอบว่า input อยู่นอก Thumbstick และมี Billboard แสดง
	local function canRevive(inputPosition: Vector2): boolean
		-- ตรวจสอบว่า input อยู่ใน Thumbstick หรือไม่
		local playerGui = player:FindFirstChild("PlayerGui")
		if playerGui then
			local touchGui = playerGui:FindFirstChild("TouchGui")
			if touchGui then
				local touchControlFrame = touchGui:FindFirstChild("TouchControlFrame")
				if touchControlFrame then
					local thumbstickFrame = touchControlFrame:FindFirstChild("DynamicThumbstickFrame")
					if thumbstickFrame then
						local framePos = thumbstickFrame.AbsolutePosition
						local frameSize = thumbstickFrame.AbsoluteSize
						local inX = inputPosition.X >= framePos.X and inputPosition.X <= (framePos.X + frameSize.X)
						local inY = inputPosition.Y >= framePos.Y and inputPosition.Y <= (framePos.Y + frameSize.Y)

						if inX and inY then
							-- อยู่ใน Thumbstick → ไม่ให้ revive
							return false
						end
					end
				end
			end
		end

		-- ไม่อยู่ใน Thumbstick → ตรวจสอบว่ามี Billboard และอยู่ในระยะหรือไม่
		if not billboard or not billboard.Enabled then return false end
		if not nearestDownedBot or nearestDownedBot ~= downedBot then return false end

		-- ตรวจสอบว่า downedBot อยู่ในระยะหรือไม่
		local myBot = Workspace:FindFirstChild(player.Name .. "_Rescue")
		if myBot and myBot.PrimaryPart and downedBot.PrimaryPart then
			local distance = (myBot.PrimaryPart.Position - downedBot.PrimaryPart.Position).Magnitude
			return distance <= REVIVE_DISTANCE
		end

		return false
	end

	-- ใช้ UserInputService เพื่อจับ input เมื่อมี Billboard แสดง
	-- (BillboardGui ไม่สามารถรับ input events ได้โดยตรง)
	local uisConnection1, uisConnection2

	uisConnection1 = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			local inputPos = Vector2.new(input.Position.X, input.Position.Y)
			if canRevive(inputPos) then
				if nearestDownedBot == downedBot and not isReviving and not isHolding then
					isHolding = true
					startRevive()
				end
			end
		end
	end)

	uisConnection2 = UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			if isHolding then
				isHolding = false
				if isReviving then
					local elapsed = tick() - holdStartTime
					local completed = elapsed >= HOLD_DURATION
					stopRevive(completed)
				end
			end
		end
	end)

	-- Corner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = mainFrame

	-- Stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Thickness = 3
	stroke.Parent = mainFrame

	-- Action text
	local actionText = Instance.new("TextLabel")
	actionText.Name = "ActionText"
	actionText.Size = UDim2.new(1, 0, 0.6, 0)
	actionText.Position = UDim2.new(0, 0, 0, 0)
	actionText.BackgroundTransparency = 1
	actionText.Text = "[R] ช่วยเหลือ"
	actionText.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionText.TextScaled = true
	actionText.Font = Enum.Font.GothamBold
	actionText.TextStrokeTransparency = 0
	actionText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	actionText.Parent = mainFrame

	-- Progress bar background
	local progressBg = Instance.new("Frame")
	progressBg.Name = "ProgressBg"
	progressBg.Size = UDim2.new(0.9, 0, 0.25, 0)
	progressBg.Position = UDim2.new(0.05, 0, 0.7, 0)
	progressBg.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
	progressBg.BorderSizePixel = 0
	progressBg.Visible = false
	progressBg.Parent = mainFrame

	local progressBgCorner = Instance.new("UICorner")
	progressBgCorner.CornerRadius = UDim.new(0.5, 0)
	progressBgCorner.Parent = progressBg

	-- Progress bar fill
	local fill = Instance.new("Frame")
	fill.Name = "ProgressFill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.Position = UDim2.new(0, 0, 0, 0)
	fill.BackgroundColor3 = Color3.fromRGB(40, 127, 71)
	fill.BorderSizePixel = 0
	fill.Parent = progressBg

	local progressFillCorner = Instance.new("UICorner")
	progressFillCorner.CornerRadius = UDim.new(0.5, 0)
	progressFillCorner.Parent = fill

	progressFill = fill
	billboardGui = billboard

	return billboard, progressBg
end

-- อัพเดต Billboard เมื่อเก็บตัวแปร progressBg ไว้
local function updateBillboardReferences(billboard: BillboardGui?, bg: Frame?)
	billboardGui = billboard
	progressBg = bg
end

-- หา RescueBot ที่พังที่ใกล้ที่สุด
local function findNearestDownedBot(): Model?
	local myBot = Workspace:FindFirstChild(player.Name .. "_Rescue")
	if not myBot or not myBot.PrimaryPart then
		return nil
	end

	local myPosition = myBot.PrimaryPart.Position
	local nearest: Model? = nil
	local nearestDistance = REVIVE_DISTANCE

	for _, child in Workspace:GetChildren() do
		if child:IsA("Model") and child.Name:match("_Rescue$") then
			-- ไม่ใช่ตัวเอง
			if child ~= myBot then
				-- ตรวจสอบว่าพังหรือไม่
				local isDown = child:GetAttribute("IsDown")
				if isDown == true and child.PrimaryPart then
					local distance = (child.PrimaryPart.Position - myPosition).Magnitude
					if distance < nearestDistance then
						nearest = child
						nearestDistance = distance
					end
				end
			end
		end
	end

	return nearest
end

-- เริ่มช่วยเหลือ
function startRevive()
	if isReviving or not nearestDownedBot then
		return
	end

	isReviving = true
	holdStartTime = tick()

	-- แสดง progress bar
	if progressBg then
		progressBg.Visible = true
	end

	print("[ReviveSystem] Started reviving", nearestDownedBot.Name)
end

-- หยุดช่วยเหลือ
function stopRevive(completed: boolean)
	if not isReviving then
		return
	end

	isReviving = false

	-- ซ่อน progress bar
	if progressBg then
		progressBg.Visible = false
	end

	if completed and nearestDownedBot then
		-- ส่ง request ไป server
		reviveRemote:FireServer(nearestDownedBot)
		print("[ReviveSystem] Revive completed for", nearestDownedBot.Name)
	else
		print("[ReviveSystem] Revive cancelled")
	end

	-- Reset progress bar
	if progressFill then
		progressFill.Size = UDim2.new(0, 0, 1, 0)
	end

	holdStartTime = 0
end

local function handleReviveAction(_: string, inputState: Enum.UserInputState, inputObject: InputObject?)
	if inputState == Enum.UserInputState.Begin then
		if nearestDownedBot and not isReviving then
			startRevive()
		end
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		if isReviving then
			local elapsed = tick() - holdStartTime
			local completed = elapsed >= HOLD_DURATION
			stopRevive(completed)
		end
	end

	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("ReviveTeammateAction", handleReviveAction, false, REVIVE_KEY)
ContextActionService:SetTitle("ReviveTeammateAction", "Revive")

-- ลบฟังก์ชัน updateReviveButton() และ listeners เพราะให้กดที่ billboard ได้เลย

-- Main loop - update UI และตรวจสอบระยะทาง
heartbeatConnection = RunService.Heartbeat:Connect(function()
	local myBot = Workspace:FindFirstChild(player.Name .. "_Rescue")
	if not myBot or not myBot.PrimaryPart then
		-- ไม่มี RescueBot ลบ UI
		if billboardGui then
			billboardGui:Destroy()
			billboardGui = nil
		end
		nearestDownedBot = nil
		return
	end

	-- หา downed bot ใกล้ที่สุด
	local foundBot = findNearestDownedBot()

	-- ถ้าเปลี่ยน target
	if foundBot ~= nearestDownedBot then
		nearestDownedBot = foundBot

		-- ลบ billboard เก่า
		if billboardGui then
			billboardGui:Destroy()
			billboardGui = nil
		end

		-- สร้าง billboard ใหม่
		if nearestDownedBot then
			local billboard, bg = createBillboard(nearestDownedBot)
			updateBillboardReferences(billboard, bg)
		end

		-- หยุด revive ถ้ากำลังทำอยู่
		if isReviving then
			stopRevive(false)
		end
	end

	-- Update progress bar
	if isReviving and progressFill then
		local elapsed = tick() - holdStartTime
		local progress = math.clamp(elapsed / HOLD_DURATION, 0, 1)
		progressFill.Size = UDim2.new(progress, 0, 1, 0)

		-- ถ้าครบเวลา
		if progress >= 1 then
			stopRevive(true)
		end
	end

	-- ซ่อน billboard ถ้าไม่มี target
	if billboardGui then
		billboardGui.Enabled = nearestDownedBot ~= nil
	end
end)

print("[ReviveSystem] Initialized")
