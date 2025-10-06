local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local MapSelectionSystem = {}

-- รอ RemoteEvents
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local mapVotingRemote = remoteEvents:WaitForChild("MapVoting")

-- ตัวแปรสำหรับระบบ
local isVoting = false
local votingTimer = GameConfig.MAP_SELECTION.votingTime
local currentVotes = {}
local votingPlayers = {}
local mapSelectionGui = nil
local votingCompleteCallbacks = {}

local function dispatchVotingComplete(mapIndex, mapData)
	print("Map voting completed:")
	if mapData then
		print("- Selected map:", mapData.name)
	end

	local callbacksCopy = {}
	for index, callback in ipairs(votingCompleteCallbacks) do
		callbacksCopy[index] = callback
	end

	for _, callback in ipairs(callbacksCopy) do
		local success, err = pcall(callback, mapIndex, mapData)
		if not success then
			warn("[MapSelectionSystem] onVotingComplete callback error:", err)
		end
	end
end

-- ข้อมูล Map ทั้งหมด
local maps = {
	{
		name = "City Rescue",
		image = "rbxasset://textures/ui/GuiImagePlaceholder.png", -- ใส่ Asset ID ของรูป Map
		description = "Urban rescue mission in the city"
	},
	{
		name = "Mountain Rescue",
		image = "rbxasset://textures/ui/GuiImagePlaceholder.png", -- ใส่ Asset ID ของรูป Map
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
	mainFrame.BackgroundTransparency = 1
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
	timerLabel.Text = "Time remaining: " .. tostring(votingTimer) .. " seconds"
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
		corner.CornerRadius = GameConfig.UI.mapSelectioCornerRadius
		corner.Parent = mapFrame

		-- Map Image
		local mapImage = Instance.new("ImageLabel")
		mapImage.Name = "MapImage"
		mapImage.Size = UDim2.new(0.95, 0, 0.65, 0)
		mapImage.Position = UDim2.new(0.025, 0, 0.05, 0)
		mapImage.BackgroundColor3 = Color3.new(0.4, 0.4, 0.4)
		mapImage.Image = map.image
		mapImage.ScaleType = Enum.ScaleType.Crop
		mapImage.Parent = mapFrame
		
		-- Corner สำหรับ Image
		local imageCorner = Instance.new("UICorner")
		imageCorner.CornerRadius = GameConfig.UI.mapSelectioCornerRadius
		imageCorner.Parent = mapImage

		-- Map Name
		local mapName = Instance.new("TextLabel")
		mapName.Name = "MapName"
		mapName.Size = UDim2.new(0.95, 0, 0.15, 0)
		mapName.Position = UDim2.new(0.025, 0, 0.68, 0)
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
		voteCount.Size = UDim2.new(0.95, 0, 0.15, 0)
		voteCount.Position = UDim2.new(0.025, 0, 0.83, 0)
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
	if not player then return end

	-- ตรวจสอบว่าเป็น local player หรือไม่ (เพื่อป้องกัน PlayerGui access error)
	local localPlayer = Players.LocalPlayer
	if player ~= localPlayer then
		-- ไม่สามารถเข้าถึง PlayerGui ของผู้เล่นอื่นได้ใน client script
		return
	end

	if not player.PlayerGui then return end

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
				-- หา votes จาก mapName แทน index
				local mapData = maps[i]
				local votes = 0
				if mapData then
					votes = currentVotes[mapData.name] or 0
				end
				voteCount.Text = "Votes: " .. votes

				-- เปลี่ยนสีและเอฟเฟกต์ตามสถานะ (เฉพาะ local player)
				local localPlayer = Players.LocalPlayer
				local localPlayerVotedMap = votingPlayers[localPlayer] or 0


				if localPlayerVotedMap == i then
					-- Local player โหวดให้ map นี้ - แสดง stroke สีเขียว
					voteCount.TextColor3 = Color3.fromRGB(40, 127, 71)
					stroke.Thickness = 5
					stroke.Color = Color3.fromRGB(40, 127, 71)
				else
					-- Local player ไม่ได้โหวดให้ map นี้ - ไม่แสดง stroke
					voteCount.TextColor3 = Color3.new(1, 1, 1) -- ขาวปกติ
					stroke.Thickness = 0
				end
			end
		end
	end
end

-- ฟังก์ชันอัปเดตการแสดงผลให้ทุกผู้เล่น (เฉพาะ local player ใน client)
local function updateVoteDisplayForAllPlayers()
	-- ใน client script จะ update ได้เฉพาะ local player เท่านั้น
	local localPlayer = Players.LocalPlayer
	if localPlayer then
		updatePlayerVoteDisplay(localPlayer)
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




-- ฟังก์ชันเริ่มการโหวด
function MapSelectionSystem.startVoting(players)
	if isVoting then return false end

	isVoting = true
	votingPlayers = {}
	currentVotes = {}

	-- รีเซ็ต votes บน server
	mapVotingRemote:FireServer("resetVotes")

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

		-- หมดเวลา - หา map ที่ได้ votes มากที่สุด
		local maxVotes = 0
		local winningMapName = nil
		local winningMapData = nil

		-- หา map ที่มี votes มากที่สุดจาก currentVotes (mapName -> count)
		for mapName, votes in pairs(currentVotes) do
			if votes > maxVotes then
				maxVotes = votes
				winningMapName = mapName
			end
		end

		-- หา mapData จาก mapName
		if winningMapName then
			for _, mapData in ipairs(maps) do
				if mapData.name == winningMapName then
					winningMapData = mapData
					break
				end
			end
		end

		-- ถ้าไม่มีใครโหวด ให้เลือกแบบสุ่ม
		if not winningMapData then
			local randomIndex = math.random(1, #maps)
			winningMapData = maps[randomIndex]
			winningMapName = winningMapData.name
		end

		print("Voting ended! Winning map: " .. winningMapName)

		-- แสดงผลลัพธ์ในทุก player GUI
		for _, player in ipairs(players) do
			if player and player.PlayerGui then
				local playerGui = player.PlayerGui:FindFirstChild("MapSelectionGui")
				if playerGui then
					local mainFrame = playerGui:FindFirstChild("MapSelectionFrame")
					if mainFrame then
						local titleLabel = mainFrame:FindFirstChild("TitleLabel")
						if titleLabel then
							titleLabel.Text = "SELECTED: " .. winningMapName
							titleLabel.TextColor3 = Color3.new(0, 1, 0)
						end
					end
				end
			end
		end

		wait(3) -- แสดงผลลัพธ์ 3 วินาที

		-- หา winning map index สำหรับ backward compatibility
		local winningMapIndex = 1
		for i, mapData in ipairs(maps) do
			if mapData.name == winningMapName then
				winningMapIndex = i
				break
			end
		end

		-- ส่งผลลัพธ์ (ไม่ต้องส่ง spawn assignments เพราะ server จัดการแล้ว)
		dispatchVotingComplete(winningMapIndex, winningMapData)

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
function MapSelectionSystem.onVotingComplete(callback)
	if typeof(callback) ~= "function" then
		error("MapSelectionSystem.onVotingComplete expects a function callback")
	end

	table.insert(votingCompleteCallbacks, callback)

	return function()
		for index = #votingCompleteCallbacks, 1, -1 do
			if votingCompleteCallbacks[index] == callback then
				table.remove(votingCompleteCallbacks, index)
				break
			end
		end
	end
end

-- ฟังก์ชันโหวดสำหรับ Map
function MapSelectionSystem.voteForMap(player, mapIndex)
	if not isVoting then
		print("Voting is not active")
		return
	end

	if mapIndex < 1 or mapIndex > #maps then
		print("Invalid map index:", mapIndex)
		return
	end

	local mapData = maps[mapIndex]
	local mapName = mapData.name

	print(player.Name .. " voted for " .. mapName)

	-- ส่ง vote ไป server
	mapVotingRemote:FireServer("vote", mapName)

	-- อัปเดต local vote (จะถูก override เมื่อ server ส่งกลับมา)
	votingPlayers[player] = mapIndex
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


-- Handle MapVoting RemoteEvent updates from server
mapVotingRemote.OnClientEvent:Connect(function(action, ...)
	if action == "updateVotes" then
		local serverVotes, serverPlayerVotes = ...

		-- อัปเดต currentVotes จาก server
		currentVotes = {}
		for mapName, count in pairs(serverVotes) do
			currentVotes[mapName] = count
		end

		-- อัปเดต votingPlayers จาก server (playerName -> mapIndex)
		votingPlayers = {}
		for playerName, mapName in pairs(serverPlayerVotes) do
			-- หา player object จาก playerName
			local player = Players:FindFirstChild(playerName)
			if player then
				-- หา mapIndex จาก mapName
				for i, mapData in ipairs(maps) do
					if mapData.name == mapName then
						votingPlayers[player] = i
						break
					end
				end
			end
		end

		-- อัปเดต UI
		updateVoteDisplayForAllPlayers()

		print("Votes updated from server:", currentVotes)
	end
end)

return MapSelectionSystem
