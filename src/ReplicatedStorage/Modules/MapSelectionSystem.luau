local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local MapSelectionSystem = {}

-- ตัวแปรสำหรับระบบ
local isVoting = false
local votingTimer = 15
local currentVotes = {}
local votingPlayers = {}
local mapSelectionGui = nil

-- ข้อมูล Map ทั้งหมด
local maps = {
	{
		name = "City Rescue",
		image = "rbxassetid://0", -- ใส่ Asset ID ของรูป Map
		description = "Urban rescue mission in the city"
	},
	{
		name = "Mountain Rescue",
		image = "rbxassetid://0", -- ใส่ Asset ID ของรูป Map
		description = "Challenging mountain terrain rescue"
	}
}

-- ฟังก์ชันสร้าง ScreenGui สำหรับ Map Selection
local function createMapSelectionUI()
	-- สร้าง ScreenGui ใหม่
	mapSelectionGui = Instance.new("ScreenGui")
	mapSelectionGui.Name = "MapSelectionGui"
	mapSelectionGui.ResetOnSpawn = false
	mapSelectionGui.IgnoreGuiInset = true

	-- สร้าง Main Frame
	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MapSelectionFrame"
	mainFrame.Size = UDim2.new(1, 0, 1, 0)
	mainFrame.Position = UDim2.new(0, 0, 0, 0)
	mainFrame.BackgroundColor3 = Color3.new(0.05, 0.05, 0.15)
	mainFrame.BackgroundTransparency = 0.5
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = mapSelectionGui

	-- Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0.15, 0)
	titleLabel.Position = UDim2.new(0, 0, 0.05, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "MAP SELECTION"
	titleLabel.TextColor3 = Color3.new(1, 1, 1)
	titleLabel.TextScaled = true
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextStrokeTransparency = 0
	titleLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	titleLabel.Parent = mainFrame

	-- Timer Label
	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "TimerLabel"
	timerLabel.Size = UDim2.new(1, 0, 0.1, 0)
	timerLabel.Position = UDim2.new(0, 0, 0.2, 0)
	timerLabel.BackgroundTransparency = 1
	timerLabel.Text = "Time remaining: " .. votingTimer .. " seconds"
	timerLabel.TextColor3 = Color3.new(1, 0.8, 0)
	timerLabel.TextScaled = true
	timerLabel.Font = Enum.Font.Gotham
	timerLabel.TextStrokeTransparency = 0
	timerLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	timerLabel.Parent = mainFrame

	-- Instruction Label
	local instructionLabel = Instance.new("TextLabel")
	instructionLabel.Name = "InstructionLabel"
	instructionLabel.Size = UDim2.new(1, 0, 0.08, 0)
	instructionLabel.Position = UDim2.new(0, 0, 0.3, 0)
	instructionLabel.BackgroundTransparency = 1
	instructionLabel.Text = "Click on a map to vote!"
	instructionLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
	instructionLabel.TextScaled = true
	instructionLabel.Font = Enum.Font.Gotham
	instructionLabel.Parent = mainFrame

	-- Maps Container
	local mapsFrame = Instance.new("Frame")
	mapsFrame.Name = "MapsFrame"
	mapsFrame.Size = UDim2.new(0.9, 0, 0.55, 0)
	mapsFrame.Position = UDim2.new(0.05, 0, 0.4, 0)
	mapsFrame.BackgroundTransparency = 1
	mapsFrame.Parent = mainFrame

	-- สร้าง UI สำหรับแต่ละ Map
	for i, map in ipairs(maps) do
		local mapFrame = Instance.new("Frame")
		mapFrame.Name = "Map" .. i
		mapFrame.Size = UDim2.new(0.45, 0, 1, 0)
		mapFrame.Position = UDim2.new((i-1) * 0.5 + 0.025, 0, 0, 0)
		mapFrame.BackgroundColor3 = Color3.new(0.15, 0.15, 0.25)
		mapFrame.BorderSizePixel = 3
		mapFrame.BorderColor3 = Color3.new(0.4, 0.4, 0.6)
		mapFrame.Parent = mapsFrame

		local uiStroke = Instance.new("UIStroke")
		uiStroke.Name = "Stroke" .. i
		uiStroke.Color = Color3.fromRGB(40, 127, 71) -- สีของเส้น
		uiStroke.Thickness = 0                       -- ความหนาของเส้น (ค่าเริ่มต้น 1)
		uiStroke.Parent = mapFrame

		-- เพิ่ม Corner Radius
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = mapFrame

		-- Map Image
		local mapImage = Instance.new("ImageLabel")
		mapImage.Name = "MapImage"
		mapImage.Size = UDim2.new(1, -20, 0.65, 0)
		mapImage.Position = UDim2.new(0, 10, 0, 10)
		mapImage.BackgroundColor3 = Color3.new(0.4, 0.4, 0.4)
		mapImage.Image = map.image
		mapImage.ScaleType = Enum.ScaleType.Crop
		mapImage.Parent = mapFrame

		-- Corner สำหรับ Image
		local imageCorner = Instance.new("UICorner")
		imageCorner.CornerRadius = UDim.new(0, 8)
		imageCorner.Parent = mapImage

		-- Map Name
		local mapName = Instance.new("TextLabel")
		mapName.Name = "MapName"
		mapName.Size = UDim2.new(1, -10, 0.15, 0)
		mapName.Position = UDim2.new(0, 5, 0.68, 0)
		mapName.BackgroundTransparency = 1
		mapName.Text = map.name
		mapName.TextColor3 = Color3.new(1, 1, 1)
		mapName.TextScaled = true
		mapName.Font = Enum.Font.GothamBold
		mapName.TextStrokeTransparency = 0
		mapName.TextStrokeColor3 = Color3.new(0, 0, 0)
		mapName.Parent = mapFrame

		-- Vote Count
		local voteCount = Instance.new("TextLabel")
		voteCount.Name = "VoteCount"
		voteCount.Size = UDim2.new(1, -10, 0.15, 0)
		voteCount.Position = UDim2.new(0, 5, 0.83, 0)
		voteCount.BackgroundTransparency = 1
		voteCount.Text = "Votes: 0"
		voteCount.TextColor3 = Color3.new(0.7, 0.7, 0.7)
		voteCount.TextScaled = true
		voteCount.Font = Enum.Font.Gotham
		voteCount.TextStrokeTransparency = 0
		voteCount.TextStrokeColor3 = Color3.new(0, 0, 0)
		voteCount.Parent = mapFrame

		-- Click Button ที่ใหญ่และเห็นชัดขึ้น
		local clickButton = Instance.new("TextButton")
		clickButton.Name = "ClickButton"
		clickButton.Size = UDim2.new(1, 0, 1, 0)
		clickButton.Position = UDim2.new(0, 0, 0, 0)
		clickButton.BackgroundTransparency = 0.95
		clickButton.BackgroundColor3 = Color3.new(1, 1, 1)
		clickButton.Text = ""
		clickButton.Parent = mapFrame

		-- เก็บ original hover effects ไว้ใช้ใน updateVoteDisplayForAllPlayers แทน
		-- เพื่อให้สีเปลี่ยนตามสถานะโหวดได้ถูกต้อง

		-- เก็บ reference สำหรับการอัปเดต
		currentVotes[i] = 0
	end

	return mapSelectionGui
end

-- ฟังก์ชันอัปเดตการแสดงผลสำหรับผู้เล่นคนหนึ่ง
local function updatePlayerVoteDisplay(player)
	if not player or not player.PlayerGui then return end

	local playerGui = player.PlayerGui:FindFirstChild("MapSelectionGui")
	if not playerGui then return end

	local mainFrame = playerGui:FindFirstChild("MapSelectionFrame")
	if not mainFrame then return end

	local mapsFrame = mainFrame:FindFirstChild("MapsFrame")
	if not mapsFrame then return end

	local playerVotedMap = votingPlayers[player] or 0

	for i = 1, #maps do
		local mapFrame = mapsFrame:FindFirstChild("Map" .. i)
		local stroke = mapFrame:FindFirstChild("Stroke" .. i)
		if stroke then
			local voteCount = mapFrame:FindFirstChild("VoteCount")
			if voteCount then
				local votes = currentVotes[i] or 0
				voteCount.Text = "Votes: " .. votes

				-- เปลี่ยนสีและเอฟเฟกต์ตามสถานะ
				if playerVotedMap == i then
					-- ผู้เล่นคนนี้โหวดให้ map นี้
					voteCount.TextColor3 = Color3.new(1, 1, 0) -- เหลืองสำหรับที่เลือก
					stroke.Thickness = 5  
				elseif votes > 0 then
					-- มีคนโหวดแต่ไม่ใช่ผู้เล่นคนนี้
					voteCount.TextColor3 = Color3.new(0, 1, 0) -- เขียว
					stroke.Thickness = 0  
				else
					-- ไม่มีใครโหวด
					stroke.Thickness = 0
				end
			end
		end
	end
end

-- ฟังก์ชันอัปเดตการแสดงผลให้ทุกผู้เล่น
local function updateVoteDisplayForAllPlayers()
	for _, player in pairs(Players:GetPlayers()) do
		updatePlayerVoteDisplay(player)
	end
end

-- ฟังก์ชันอัปเดต Timer
local function updateTimer(timeLeft)
	if not mapSelectionGui then return end

	local mainFrame = mapSelectionGui:FindFirstChild("MapSelectionFrame")
	if not mainFrame then return end

	local timerLabel = mainFrame:FindFirstChild("TimerLabel")
	if timerLabel then
		timerLabel.Text = "Time remaining: " .. timeLeft .. " seconds"

		-- เปลี่ยนสีเมื่อเวลาใกล้หมด
		if timeLeft <= 5 then
			timerLabel.TextColor3 = Color3.new(1, 0, 0) -- แดง
		elseif timeLeft <= 10 then
			timerLabel.TextColor3 = Color3.new(1, 0.5, 0) -- ส้ม
		else
			timerLabel.TextColor3 = Color3.new(1, 0.8, 0) -- เหลือง
		end
	end
end

-- ฟังก์ชันโหวด
function MapSelectionSystem.voteForMap(player, mapIndex)
	if not isVoting then return false end
	if mapIndex < 1 or mapIndex > #maps then return false end

	-- ลบโหวดเก่าของผู้เล่น
	for i = 1, #maps do
		if votingPlayers[player] == i then
			currentVotes[i] = math.max(0, currentVotes[i] - 1)
		end
	end

	-- เพิ่มโหวดใหม่
	votingPlayers[player] = mapIndex
	currentVotes[mapIndex] = (currentVotes[mapIndex] or 0) + 1

	print(player.Name .. " voted for " .. maps[mapIndex].name)

	-- อัปเดตการแสดงผลให้ทุกผู้เล่น
	updateVoteDisplayForAllPlayers()
	return true
end

-- ฟังก์ชันหาผู้ชนะ
local function getWinningMap()
	local maxVotes = 0
	local winners = {}

	-- หาจำนวนโหวดสูงสุด
	for i, votes in pairs(currentVotes) do
		if votes > maxVotes then
			maxVotes = votes
			winners = {i}
		elseif votes == maxVotes and votes > 0 then
			table.insert(winners, i)
		end
	end

	-- ถ้าไม่มีใครโหวดหรือเสมอกัน ให้สุ่ม
	if #winners == 0 or maxVotes == 0 then
		return math.random(1, #maps)
	elseif #winners > 1 then
		-- เสมอกัน สุ่มเลือก
		return winners[math.random(1, #winners)]
	else
		return winners[1]
	end
end

-- ฟังก์ชันสุ่ม spawn points
local function assignRandomSpawns(players)
	local spawnRescues = workspace:FindFirstChild("SpawnRescues")
	if not spawnRescues then
		warn("SpawnRescues not found in workspace")
		return {}
	end

	-- หา spawn points ทั้งหมด
	local spawnPoints = {}
	for _, child in ipairs(spawnRescues:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(spawnPoints, child)
		end
	end

	if #spawnPoints == 0 then
		warn("No spawn points found in SpawnRescues")
		return {}
	end

	-- สุ่มมอบหมาย spawn points ให้ผู้เล่น
	local assignments = {}
	for i, player in ipairs(players) do
		if i <= #spawnPoints then
			local randomIndex = math.random(1, #spawnPoints)
			assignments[player] = spawnPoints[randomIndex]
			table.remove(spawnPoints, randomIndex) -- ไม่ให้ซ้ำ
		else
			-- ถ้าผู้เล่นเยอะกว่า spawn points ให้ใช้แบบสุ่ม
			assignments[player] = spawnPoints[math.random(1, #spawnPoints)]
		end
	end

	return assignments
end

-- ฟังก์ชันเริ่มการโหวด
function MapSelectionSystem.startVoting(players)
	if isVoting then return false end

	isVoting = true
	votingPlayers = {}
	currentVotes = {}

	-- รีเซ็ตโหวด
	for i = 1, #maps do
		currentVotes[i] = 0
	end

	print("Starting map voting with " .. #players .. " players")

	-- สร้าง UI
	local mapUI = createMapSelectionUI()
	if not mapUI then
		isVoting = false
		return false
	end

	-- แสดง GUI ให้ทุกผู้เล่น
	for _, player in ipairs(players) do
		if player and player.PlayerGui then
			local playerGui = mapUI:Clone()
			playerGui.Parent = player.PlayerGui

			-- เชื่อมต่อ click events สำหรับผู้เล่นนี้
			local mainFrame = playerGui:FindFirstChild("MapSelectionFrame")
			if mainFrame then
				local mapsFrame = mainFrame:FindFirstChild("MapsFrame")
				if mapsFrame then
					for mapIndex = 1, #maps do
						local mapFrame = mapsFrame:FindFirstChild("Map" .. mapIndex)
						if mapFrame then
							local clickButton = mapFrame:FindFirstChild("ClickButton")
							if clickButton then
								clickButton.MouseButton1Click:Connect(function()
									MapSelectionSystem.voteForMap(player, mapIndex)
								end)

								-- เพิ่ม hover effects ที่ไม่รบกวนการแสดงผลโหวด
								clickButton.MouseEnter:Connect(function()
									if not votingPlayers[player] or votingPlayers[player] ~= mapIndex then
										mapFrame.BackgroundColor3 = Color3.new(0.2, 0.2, 0.35)
									end
								end)

								clickButton.MouseLeave:Connect(function()
									-- ให้ updatePlayerVoteDisplay จัดการสีให้
									updatePlayerVoteDisplay(player)
								end)
							end
						end
					end
				end
			end

			-- อัปเดตการแสดงผลเริ่มต้นสำหรับผู้เล่นนี้
			updatePlayerVoteDisplay(player)
		end
	end

	-- เริ่ม timer
	spawn(function()
		for timeLeft = votingTimer, 1, -1 do
			-- อัปเดต timer ในทุก player GUI
			for _, player in ipairs(players) do
				if player and player.PlayerGui then
					local playerGui = player.PlayerGui:FindFirstChild("MapSelectionGui")
					if playerGui then
						local mainFrame = playerGui:FindFirstChild("MapSelectionFrame")
						if mainFrame then
							local timerLabel = mainFrame:FindFirstChild("TimerLabel")
							if timerLabel then
								timerLabel.Text = "Time remaining: " .. timeLeft .. " seconds"

								if timeLeft <= 5 then
									timerLabel.TextColor3 = Color3.new(1, 0, 0)
								elseif timeLeft <= 10 then
									timerLabel.TextColor3 = Color3.new(1, 0.5, 0)
								else
									timerLabel.TextColor3 = Color3.new(1, 0.8, 0)
								end
							end
						end
					end
				end
			end
			wait(1)
		end

		-- หมดเวลา
		local winningMapIndex = getWinningMap()
		local winningMap = maps[winningMapIndex]

		print("Voting ended! Winning map: " .. winningMap.name)

		-- แสดงผลลัพธ์ในทุก player GUI
		for _, player in ipairs(players) do
			if player and player.PlayerGui then
				local playerGui = player.PlayerGui:FindFirstChild("MapSelectionGui")
				if playerGui then
					local mainFrame = playerGui:FindFirstChild("MapSelectionFrame")
					if mainFrame then
						local titleLabel = mainFrame:FindFirstChild("TitleLabel")
						if titleLabel then
							titleLabel.Text = "SELECTED: " .. winningMap.name
							titleLabel.TextColor3 = Color3.new(0, 1, 0)
						end
					end
				end
			end
		end

		wait(3) -- แสดงผลลัพธ์ 3 วินาที

		-- มอบหมาย spawn points
		local spawnAssignments = assignRandomSpawns(players)

		-- ส่งผลลัพธ์
		MapSelectionSystem.onVotingComplete(winningMapIndex, winningMap, spawnAssignments)

		-- ล้าง UI จากทุก player
		for _, player in ipairs(players) do
			if player and player.PlayerGui then
				local playerGui = player.PlayerGui:FindFirstChild("MapSelectionGui")
				if playerGui then
					playerGui:Destroy()
				end
			end
		end

		isVoting = false
	end)

	return true
end

-- ฟังก์ชัน callback สำหรับเมื่อโหวดเสร็จ (ให้ระบบอื่นเรียกใช้)
function MapSelectionSystem.onVotingComplete(mapIndex, mapData, spawnAssignments)
	-- ฟังก์ชันนี้จะถูกเรียกเมื่อการโหวดเสร็จสิ้น
	print("Map voting completed:")
	print("- Selected map:", mapData.name)
	print("- Spawn assignments:")
	for player, spawnPoint in pairs(spawnAssignments) do
		print("  " .. player.Name .. " -> " .. spawnPoint.Name)
	end

	-- ที่นี่สามารถเพิ่มโค้ดสำหรับเริ่มเกมได้
	-- เช่น teleport ผู้เล่น, เปิด UI เกม, ฯลฯ
end

-- ฟังก์ชันตรวจสอบสถานะ
function MapSelectionSystem.isVotingActive()
	return isVoting
end

-- ฟังก์ชันรีเซ็ตระบบ
function MapSelectionSystem.reset()
	isVoting = false
	votingPlayers = {}
	currentVotes = {}

	-- ล้าง GUI จากทุกผู้เล่น
	for _, player in pairs(Players:GetPlayers()) do
		if player and player.PlayerGui then
			local playerGui = player.PlayerGui:FindFirstChild("MapSelectionGui")
			if playerGui then
				playerGui:Destroy()
			end
		end
	end

	mapSelectionGui = nil
	print("MapSelectionSystem reset")
end

-- ฟังก์ชันเพิ่ม Map ใหม่
function MapSelectionSystem.addMap(name, imageId, description)
	table.insert(maps, {
		name = name,
		image = "rbxassetid://" .. imageId,
		description = description or ""
	})
	print("Added new map: " .. name)
end

-- ฟังก์ชันดูข้อมูล Maps
function MapSelectionSystem.getMaps()
	return maps
end

return MapSelectionSystem