-- GameSummary ModuleScript
-- จัดการการแสดงผลสรุปเกมเมื่อจบ

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(script.Parent.GameConfig)

local GameSummary = {}

-- ข้อมูลผู้เล่น
local playerStats = {}

-- ฟังก์ชันเพิ่มคะแนนผู้เล่น
function GameSummary.addPlayerScore(player, victims, coins)
	if not playerStats[player.UserId] then
		playerStats[player.UserId] = {
			player = player,
			displayName = player.DisplayName,
			username = player.Name,
			victims = 0,
			coins = 0,
			joinTime = tick()
		}
	end

	playerStats[player.UserId].victims = victims or playerStats[player.UserId].victims
	playerStats[player.UserId].coins = coins or playerStats[player.UserId].coins
end

-- ฟังก์ชันเพิ่ม victim ที่ช่วยเหลือ
function GameSummary.addVictimRescue(player)
	if not playerStats[player.UserId] then
		GameSummary.addPlayerScore(player, 0, 0)
	end
	playerStats[player.UserId].victims = playerStats[player.UserId].victims + 1
end

-- ฟังก์ชันเพิ่ม coins
function GameSummary.addCoins(player, amount)
	if not playerStats[player.UserId] then
		GameSummary.addPlayerScore(player, 0, 0)
	end
	playerStats[player.UserId].coins = playerStats[player.UserId].coins + (amount or 1)
end

-- ฟังก์ชันเพิ่มผู้เล่นทุกคนเข้าสู่ summary (เรียกเมื่อเกมเริ่ม)
function GameSummary.initializeAllPlayers()
	for _, player in ipairs(Players:GetPlayers()) do
		if not playerStats[player.UserId] then
			GameSummary.addPlayerScore(player, 0, 0)
			print("[GameSummary] Initialized player", player.Name, "with 0 score")
		end
	end
end

-- ฟังก์ชันเรียงลำดับผู้เล่น
function GameSummary.getSortedPlayers()
	local sortedPlayers = {}

	-- แปลง dictionary เป็น array
	for userId, stats in pairs(playerStats) do
		table.insert(sortedPlayers, stats)
	end

	-- เรียงลำดับตาม victims แล้วตาม coins
	table.sort(sortedPlayers, function(a, b)
		if a.victims == b.victims then
			return a.coins > b.coins -- ถ้า victims เท่ากันให้เรียงตาม coins
		end
		return a.victims > b.victims -- เรียงตาม victims มากไปน้อย
	end)

	return sortedPlayers
end

-- ฟังก์ชันสร้าง Summary UI
function GameSummary.createSummaryUI(player)
	local playerGui = player:WaitForChild("PlayerGui")

	-- ลบ GUI เก่าถ้ามี
	local existingGui = playerGui:FindFirstChild("GameSummaryGui")
	if existingGui then
		existingGui:Destroy()
	end

	-- ลบ DrillProgressGui ก่อนแสดง Summary
	local drillProgressGui = playerGui:FindFirstChild("DrillProgressGui")
	if drillProgressGui then
		drillProgressGui:Destroy()
		print("[GameSummary] Cleared DrillProgressGui")
	end

	-- สร้าง ScreenGui
	local summaryGui = Instance.new("ScreenGui")
	summaryGui.Name = "GameSummaryGui"
	summaryGui.ResetOnSpawn = false
	summaryGui.IgnoreGuiInset = true
	summaryGui.Parent = playerGui

	-- Background overlay
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.Position = UDim2.new(0, 0, 0, 0)
	background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	background.BackgroundTransparency = 0.3
	background.BorderSizePixel = 0
	background.Parent = summaryGui

	-- Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.new(0.8, 0, 0.7, 0)
	mainFrame.Position = UDim2.new(0.1, 0, 0.15, 0)
	mainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	mainFrame.BackgroundTransparency = 0.1
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = summaryGui

	-- Main Frame Corner
	local mainCorner = Instance.new("UICorner")
	mainCorner.CornerRadius = GameConfig.UI.cornerRadius
	mainCorner.Parent = mainFrame

	-- Main Frame Stroke
	local mainStroke = Instance.new("UIStroke")
	mainStroke.Color = Color3.fromRGB(255, 255, 255)
	mainStroke.Thickness = 3
	mainStroke.Parent = mainFrame

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0.15, 0)
	titleLabel.Position = UDim2.new(0, 0, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "Mission Summary"
	titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextStrokeTransparency = 0
	titleLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	titleLabel.Parent = mainFrame

	-- Scrolling Frame for players
	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "PlayerList"
	scrollFrame.Size = UDim2.new(0.95, 0, 0.75, 0)
	scrollFrame.Position = UDim2.new(0.025, 0, 0.18, 0)
	scrollFrame.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
	scrollFrame.BackgroundTransparency = 0.2
	scrollFrame.BorderSizePixel = 0
	scrollFrame.ScrollBarThickness = 8
	scrollFrame.ScrollBarImageColor3 = Color3.fromRGB(100, 100, 100)
	scrollFrame.Parent = mainFrame

	-- Scroll Frame Corner
	local scrollCorner = Instance.new("UICorner")
	scrollCorner.CornerRadius = GameConfig.UI.smallCornerRadius
	scrollCorner.Parent = scrollFrame

	-- UIListLayout for player entries
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 10)
	listLayout.Parent = scrollFrame

	-- UIPadding for scroll frame
	local scrollPadding = Instance.new("UIPadding")
	scrollPadding.PaddingTop = UDim.new(0, 10)
	scrollPadding.PaddingBottom = UDim.new(0, 10)
	scrollPadding.PaddingLeft = UDim.new(0, 10)
	scrollPadding.PaddingRight = UDim.new(0, 10)
	scrollPadding.Parent = scrollFrame

	-- Close Button
	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0.2, 0, 0.08, 0)
	closeButton.Position = UDim2.new(0.4, 0, 0.94, 0)
	closeButton.BackgroundColor3 = Color3.fromRGB(0, 150, 255)
	closeButton.Text = "OK"
	closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeButton.TextScaled = true
	closeButton.Font = Enum.Font.GothamBold
	closeButton.BorderSizePixel = 0
	closeButton.Parent = mainFrame

	-- Close Button Corner
	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = GameConfig.UI.smallCornerRadius
	closeCorner.Parent = closeButton

	-- ฟังก์ชันปิด Summary (ใช้ร่วมกันระหว่าง manual click และ auto-close)
	local function closeSummary()
		-- เคลียร์ coins ก่อนปิด summary (client-side)
		local GameTimer = require(ReplicatedStorage.Modules.GameTimer)
		GameTimer.clearCoins()

		local backgroundCloseTween = TweenService:Create(background,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}
		)

		local mainFrameCloseTween = TweenService:Create(mainFrame,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 1}
		)

		backgroundCloseTween:Play()
		mainFrameCloseTween:Play()

		backgroundCloseTween.Completed:Connect(function()
			summaryGui:Destroy()

			-- เรียก callback เมื่อปิด summary (server จะจัดการ clear victims/obstacles)
			if GameSummary.onSummaryClosed then
				GameSummary.onSummaryClosed(player)
			end
		end)
	end

	-- Auto-close timer (10 วินาที) พร้อม countdown
	local autoCloseTimer = nil
	local countdownTimer = nil
	local timeLeft = 10

	local function startAutoCloseTimer()
		-- Countdown display
		countdownTimer = task.spawn(function()
			while timeLeft > 0 and summaryGui and summaryGui.Parent do
				closeButton.Text = "OK (" .. timeLeft .. ")"
				task.wait(1)
				timeLeft = timeLeft - 1
			end
		end)

		-- Auto-close after 10 seconds
		autoCloseTimer = task.spawn(function()
			task.wait(10)
			if summaryGui and summaryGui.Parent then -- ตรวจสอบว่ายังไม่ถูกปิด
				print("[GameSummary] Auto-closing summary for", player.Name, "after 10 seconds")
				closeSummary()
			end
		end)
	end

	-- เริ่ม auto-close timer
	startAutoCloseTimer()

	-- Close Button Click
	closeButton.MouseButton1Click:Connect(function()
		-- ยกเลิก auto-close timer เมื่อผู้เล่นกด OK เอง
		if autoCloseTimer then
			task.cancel(autoCloseTimer)
			autoCloseTimer = nil
		end
		if countdownTimer then
			task.cancel(countdownTimer)
			countdownTimer = nil
		end
		print("[GameSummary] Manual close by", player.Name)
		closeSummary()
	end)

	return summaryGui, scrollFrame
end

-- ฟังก์ชันสร้าง Player Entry
function GameSummary.createPlayerEntry(playerData, rank, parent)
	local playerFrame = Instance.new("Frame")
	playerFrame.Name = "Player_" .. playerData.username
	playerFrame.Size = UDim2.new(1, -20, 0, 80)
	playerFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	playerFrame.BackgroundTransparency = 0.1
	playerFrame.BorderSizePixel = 0
	playerFrame.LayoutOrder = rank
	playerFrame.Parent = parent

	-- Player Frame Corner
	local playerCorner = Instance.new("UICorner")
	playerCorner.CornerRadius = GameConfig.UI.smallCornerRadius
	playerCorner.Parent = playerFrame

	-- Rank Colors
	local rankColors = {
		Color3.fromRGB(255, 215, 0), -- Gold
		Color3.fromRGB(192, 192, 192), -- Silver
		Color3.fromRGB(205, 127, 50), -- Bronze
		Color3.fromRGB(100, 100, 100) -- Default
	}

	local frameColor = rankColors[math.min(rank, 4)]

	-- Player Frame Stroke (rank color)
	local playerStroke = Instance.new("UIStroke")
	playerStroke.Color = frameColor
	playerStroke.Thickness = 2
	playerStroke.Parent = playerFrame

	-- Rank Label
	local rankLabel = Instance.new("TextLabel")
	rankLabel.Name = "RankLabel"
	rankLabel.Size = UDim2.new(0.1, 0, 1, 0)
	rankLabel.Position = UDim2.new(0, 0, 0, 0)
	rankLabel.BackgroundTransparency = 1
	rankLabel.Text = "#" .. rank
	rankLabel.TextColor3 = frameColor
	rankLabel.TextScaled = true
	rankLabel.Font = Enum.Font.GothamBold
	rankLabel.TextStrokeTransparency = 0
	rankLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	rankLabel.Parent = playerFrame

	-- Player Avatar (ใช้ placeholder)
	local avatarFrame = Instance.new("Frame")
	avatarFrame.Name = "AvatarFrame"
	avatarFrame.Size = UDim2.new(0, 60, 0, 60)
	avatarFrame.Position = UDim2.new(0.12, 0, 0.5, -30)
	avatarFrame.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
	avatarFrame.BorderSizePixel = 0
	avatarFrame.Parent = playerFrame

	-- Avatar Corner
	local avatarCorner = Instance.new("UICorner")
	avatarCorner.CornerRadius = UDim.new(0.5, 0) -- Circular
	avatarCorner.Parent = avatarFrame

	-- Avatar Image (Roblox Headshot)
	local avatarImage = Instance.new("ImageLabel")
	avatarImage.Size = UDim2.new(1, 0, 1, 0)
	avatarImage.Position = UDim2.new(0, 0, 0, 0)
	avatarImage.BackgroundTransparency = 1
	avatarImage.Image = "https://www.roblox.com/headshot-thumbnail/image?userId=" .. playerData.player.UserId .. "&width=60&height=60&format=png"
	avatarImage.ScaleType = Enum.ScaleType.Crop
	avatarImage.Parent = avatarFrame

	-- Avatar Image Corner
	local avatarImageCorner = Instance.new("UICorner")
	avatarImageCorner.CornerRadius = UDim.new(0.5, 0)
	avatarImageCorner.Parent = avatarImage

	-- Player Name (centered)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(0.4, 0, 1, 0)
	nameLabel.Position = UDim2.new(0.25, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = playerData.displayName
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextStrokeTransparency = 0
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Center
	nameLabel.Parent = playerFrame

	-- Victims Count
	local victimsFrame = Instance.new("Frame")
	victimsFrame.Name = "VictimsFrame"
	victimsFrame.Size = UDim2.new(0.15, 0, 0.6, 0)
	victimsFrame.Position = UDim2.new(0.68, 0, 0.2, 0)
	victimsFrame.BackgroundColor3 = Color3.fromRGB(40, 127, 71)
	victimsFrame.BackgroundTransparency = 0.2
	victimsFrame.BorderSizePixel = 0
	victimsFrame.Parent = playerFrame

	local victimsCorner = Instance.new("UICorner")
	victimsCorner.CornerRadius = GameConfig.UI.smallCornerRadius
	victimsCorner.Parent = victimsFrame

	local victimsLabel = Instance.new("TextLabel")
	victimsLabel.Size = UDim2.new(1, 0, 1, 0)
	victimsLabel.BackgroundTransparency = 1
	victimsLabel.Text = "Help " .. playerData.victims
	victimsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	victimsLabel.TextScaled = true
	victimsLabel.Font = Enum.Font.GothamBold
	victimsLabel.TextStrokeTransparency = 0
	victimsLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	victimsLabel.Parent = victimsFrame

	-- Coins Count
	local coinsFrame = Instance.new("Frame")
	coinsFrame.Name = "CoinsFrame"
	coinsFrame.Size = UDim2.new(0.15, 0, 0.6, 0)
	coinsFrame.Position = UDim2.new(0.84, 0, 0.2, 0)
	coinsFrame.BackgroundColor3 = Color3.fromRGB(255, 215, 0)
	coinsFrame.BackgroundTransparency = 0.2
	coinsFrame.BorderSizePixel = 0
	coinsFrame.Parent = playerFrame

	local coinsCorner = Instance.new("UICorner")
	coinsCorner.CornerRadius = GameConfig.UI.smallCornerRadius
	coinsCorner.Parent = coinsFrame

	-- Coin Icon
	local coinIcon = Instance.new("ImageLabel")
	coinIcon.Name = "CoinIcon"
	coinIcon.Size = UDim2.new(0.4, 0, 0.8, 0)
	coinIcon.Position = UDim2.new(0.05, 0, 0.1, 0)
	coinIcon.BackgroundTransparency = 1
	coinIcon.Image = "rbxassetid://124358779164505"
	coinIcon.ScaleType = Enum.ScaleType.Fit
	coinIcon.Parent = coinsFrame

	-- Coin Count Text
	local coinsLabel = Instance.new("TextLabel")
	coinsLabel.Name = "CoinsLabel"
	coinsLabel.Size = UDim2.new(0.5, 0, 1, 0)
	coinsLabel.Position = UDim2.new(0.5, 0, 0, 0)
	coinsLabel.BackgroundTransparency = 1
	coinsLabel.Text = tostring(playerData.coins)
	coinsLabel.TextColor3 = Color3.fromRGB(0, 0, 0)
	coinsLabel.TextScaled = true
	coinsLabel.Font = Enum.Font.GothamBold
	coinsLabel.TextStrokeTransparency = 0
	coinsLabel.TextStrokeColor3 = Color3.fromRGB(255, 255, 255)
	coinsLabel.TextXAlignment = Enum.TextXAlignment.Left
	coinsLabel.Parent = coinsFrame

	return playerFrame
end

-- ฟังก์ชันแสดง Summary ให้ผู้เล่น
function GameSummary.showSummary(player)
	local summaryGui, scrollFrame = GameSummary.createSummaryUI(player)
	local sortedPlayers = GameSummary.getSortedPlayers()

	-- สร้าง player entries
	for rank, playerData in ipairs(sortedPlayers) do
		GameSummary.createPlayerEntry(playerData, rank, scrollFrame)
	end

	-- คำนวณ canvas size
	local totalHeight = #sortedPlayers * 90 + 20 -- 80px per entry + 10px spacing + padding
	scrollFrame.CanvasSize = UDim2.new(0, 0, 0, totalHeight)

	-- Animation entrance
	local background = summaryGui:FindFirstChild("Background")
	local mainFrame = summaryGui:FindFirstChild("MainFrame")

	if background then background.BackgroundTransparency = 1 end
	if mainFrame then mainFrame.BackgroundTransparency = 1 end

	if background then
		local backgroundTween = TweenService:Create(background,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0.3}
		)
		backgroundTween:Play()
	end

	if mainFrame then
		local mainFrameTween = TweenService:Create(mainFrame,
			TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{BackgroundTransparency = 0.1}
		)
		mainFrameTween:Play()
	end

	print("[GameSummary] Showing summary for", player.Name)
end

-- ฟังก์ชันแสดง Summary ให้ทุกคน
function GameSummary.showSummaryToAll()
	for _, player in ipairs(Players:GetPlayers()) do
		GameSummary.showSummary(player)
	end
end

-- Callback สำหรับเมื่อปิด summary
GameSummary.onSummaryClosed = nil

-- ฟังก์ชันรีเซ็ตข้อมูล
function GameSummary.reset()
	playerStats = {}
	print("[GameSummary] Reset all player stats")
end

-- ฟังก์ชันล้างข้อมูลและกลับไปจุดเริ่มต้น
function GameSummary.resetToLobby(player)
	print("[GameSummary] Player", player.Name, "returning to lobby")

	-- ย้ายผู้เล่นกลับไป SpawnLocation
	local character = player.Character
	if character and character:FindFirstChild("HumanoidRootPart") then
		-- หา SpawnLocation
		local spawnLocation = workspace:FindFirstChildOfClass("SpawnLocation")
		if spawnLocation then
			character:PivotTo(spawnLocation.CFrame + Vector3.new(0, 3, 0))
			print("[GameSummary] Teleported", player.Name, "to SpawnLocation")
		else
			-- Fallback: ย้ายไปตำแหน่งเริ่มต้น
			character:PivotTo(CFrame.new(0, 10, 0))
			print("[GameSummary] Teleported", player.Name, "to default spawn")
		end
	end

	-- ลบรถของผู้เล่น (ถ้ามี)
	for _, model in ipairs(workspace:GetChildren()) do
		if model:IsA("Model") and (
			model.Name == player.Name .. "_RescueCompanion" or
			model.Name == player.Name .. "_Rescue"
		) then
			model:Destroy()
			print("[GameSummary] Destroyed vehicle", model.Name)
		end
	end

	-- ล้าง GUI ต่างๆ ของผู้เล่น
	local playerGui = player:WaitForChild("PlayerGui")

	-- ลบ Timer GUI
	local timerGui = playerGui:FindFirstChild("GameTimerGui")
	if timerGui then
		timerGui:Destroy()
	end

	-- ลบ GUIs อื่นๆ ที่เกี่ยวข้องกับเกม
	local flipGui = playerGui:FindFirstChild("FlipGui")
	if flipGui then
		flipGui:Destroy()
	end

	-- ลบ Map Selection GUI ถ้ามี
	local mapSelectionGui = playerGui:FindFirstChild("MapSelectionGui")
	if mapSelectionGui then
		mapSelectionGui:Destroy()
	end

	-- รีเซ็ต character health และ state
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.Health = humanoid.MaxHealth
			humanoid.PlatformStand = false
			humanoid.Sit = false
		end
	end

	-- Fire event กลับไป lobby
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local remoteEvents = ReplicatedStorage:FindFirstChild("RescueBotRemotes")
	if remoteEvents then
		local waitingSystemRemote = remoteEvents:FindFirstChild("WaitingSystem")
		if waitingSystemRemote then
			-- ส่งผู้เล่นกลับไป waiting room
			waitingSystemRemote:FireClient(player, "returnToLobby")
		end
	end

	print("[GameSummary] Player", player.Name, "successfully reset to lobby")
end

-- ฟังก์ชันดูข้อมูลสถิติ
function GameSummary.getPlayerStats()
	return playerStats
end

-- ฟังก์ชันดูผู้ชนะ
function GameSummary.getWinner()
	local sortedPlayers = GameSummary.getSortedPlayers()
	return sortedPlayers[1] -- ผู้เล่นอันดับ 1
end

-- Debug function
function GameSummary.printStats()
	print("=== GAME SUMMARY STATS ===")
	local sortedPlayers = GameSummary.getSortedPlayers()
	for rank, playerData in ipairs(sortedPlayers) do
		print(rank .. ". " .. playerData.displayName .. " (@" .. playerData.username .. ")")
		print("   Victims: " .. playerData.victims .. ", Coins: " .. playerData.coins)
	end
	print("========================")
end

return GameSummary