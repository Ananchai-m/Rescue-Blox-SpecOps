local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapSelectionSystem = require(ReplicatedStorage.Modules.MapSelectionSystem)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local WaitingSystem = {}

-- ตัวแปรสำหรับติดตาม
local waitingPlayers = {}
local currentWaitingCount = 0 -- จำนวนผู้เล่นที่รออยู่จริง (จาก server)
local simuBillboard = nil
local isCountingDown = false
local isGamePlaying = false
local gameTimeLeft = 0
local gameTimerThread = nil
local lobbyCountdownTime = 0
local isLobbyCountingDown = false
local lobbyCountdownThread = nil

-- ฟังก์ชันหา Simu BillboardGui
local function findSimuBillboard()
	local simu = workspace:FindFirstChild("Simu")
	if not simu then
		warn("Simu object not found in workspace")
		return nil
	end

	local attachment = simu:FindFirstChild("Attachment")
	if not attachment then
		warn("Attachment not found in Simu object")
		return nil
	end

	local billboardGui = attachment:FindFirstChild("BillboardGui")
	if not billboardGui then
		warn("BillboardGui not found in Simu.Attachment")
		return nil
	end

	local frame = billboardGui:FindFirstChild("Frame")
	if not frame then
		warn("Frame not found in BillboardGui")
		return nil
	end

	local textLabel = frame:FindFirstChild("TextLabel")
	if not textLabel then
		warn("TextLabel not found in Frame")
		return nil
	end

	return textLabel
end

-- ฟังก์ชันแปลงวินาทีเป็นรูปแบบเวลา
local function formatTime(seconds)
	local minutes = math.floor(seconds / 60)
	local secs = seconds % 60
	return string.format("%02d:%02d", minutes, secs)
end

-- ฟังก์ชันอัปเดตข้อความรอ
local function updateWaitingMessage()
	if not simuBillboard then
		simuBillboard = findSimuBillboard()
		if not simuBillboard then
			return
		end
	end

	local waitingCount = currentWaitingCount -- ใช้ค่าจาก server แทน
	local maxPlayers = GameConfig.getMaxPlayers()
	local remaining = maxPlayers - waitingCount

	if isGamePlaying and gameTimeLeft > 0 then
		-- แสดงเวลาที่เหลือของเกม พร้อมจำนวนผู้เล่น
		local playerCount = #Players:GetPlayers()
		simuBillboard.Text = string.format("Game in Progress (%d/%d players)\nTime: %s", playerCount, maxPlayers, formatTime(gameTimeLeft))
		simuBillboard.Visible = true
	elseif isGamePlaying then
		-- เกมกำลังเล่นแต่ไม่มีข้อมูลเวลา
		local playerCount = #Players:GetPlayers()
		simuBillboard.Text = string.format("Game Playing! (%d/%d players)", playerCount, maxPlayers)
		simuBillboard.Visible = true
	elseif isLobbyCountingDown and lobbyCountdownTime > 0 then
		-- แสดงการนับถอยหลังใน lobby พร้อมจำนวนผู้เล่นที่รออยู่
		simuBillboard.Text = string.format("Starting soon!\n%d/%d players ready\nGame starts in %s", waitingCount, maxPlayers, formatTime(lobbyCountdownTime))
		simuBillboard.Visible = true
	elseif waitingCount > 0 and remaining > 0 then
		-- แสดงจำนวนผู้เล่นที่รออยู่และที่ยังขาด
		simuBillboard.Text = string.format("Waiting for players\n%d/%d players joined\nStay in zone!", waitingCount, maxPlayers)
		simuBillboard.Visible = true
	elseif waitingCount == 0 then
		-- แสดงจำนวนผู้เล่นที่ต้องการ
		simuBillboard.Text = string.format("Join the mission!\nStay in Simu to join (1-%d players)", maxPlayers)
		simuBillboard.Visible = true
	else
		simuBillboard.Text = ""
		simuBillboard.Visible = false
	end
end

-- ฟังก์ชันเพิ่มผู้เล่นที่รอ
function WaitingSystem.addWaitingPlayer(player)
	-- ตรวจสอบว่าผู้เล่นอยู่ในรายการแล้วหรือไม่
	for _, waitingPlayer in ipairs(waitingPlayers) do
		if waitingPlayer == player then
			return false -- ผู้เล่นอยู่ในรายการแล้ว
		end
	end

	-- เพิ่มผู้เล่นใหม่
	table.insert(waitingPlayers, player)
	print(player.Name .. " added to waiting list. Total waiting: " .. #waitingPlayers)

	-- อัปเดตข้อความ
	updateWaitingMessage()

	-- ตรวจสอบว่าครบจำนวนแล้วหรือไม่
	if #waitingPlayers >= GameConfig.getMaxPlayers() then
		WaitingSystem.startGame()
		return true
	end

	return false
end

-- ฟังก์ชันลบผู้เล่นที่รอ
function WaitingSystem.removeWaitingPlayer(player)
	for i = #waitingPlayers, 1, -1 do
		if waitingPlayers[i] == player then
			table.remove(waitingPlayers, i)
			print(player.Name .. " removed from waiting list. Total waiting: " .. #waitingPlayers)
			updateWaitingMessage()
			return true
		end
	end
	return false
end

-- ฟังก์ชันนับถอยหลัง
local function startCountdown()
	if isCountingDown then return end
	isCountingDown = true

	-- แสดงข้อความเริ่มนับถอยหลัง
	if simuBillboard then
		for countdown = 5, 1, -1 do
			simuBillboard.Text = "The mission will start in " .. countdown .. " seconds!"
			simuBillboard.Visible = true
			wait(1)
		end

		-- ซ่อนข้อความ
		simuBillboard.Text = ""
		simuBillboard.Visible = false
	else
		-- ถ้าไม่มี billboard ให้รอ 5 วินาทีเฉยๆ
		wait(5)
	end

	isCountingDown = false
end

-- ฟังก์ชันเริ่มเกม
function WaitingSystem.startGame()
	print("Starting countdown with " .. #waitingPlayers .. " players!")

	-- เริ่มนับถอยหลัง
	spawn(function()
		startCountdown()

		print("Starting map selection...")
		-- เริ่มระบบเลือก Map
		local playersArray = {}
		for _, player in ipairs(waitingPlayers) do
			table.insert(playersArray, player)
		end

		-- ล้างรายการผู้เล่นที่รอ
		waitingPlayers = {}

		-- เริ่ม Map Selection (จะใช้เวลา ~18 วินาที: 15s voting + 3s result)
		MapSelectionSystem.startVoting(playersArray)

		-- รอให้ Map Selection เสร็จ
		wait(19) -- buffer เพิ่มอีกนิด

		-- ตั้งสถานะเกมเป็นกำลังเล่น
		isGamePlaying = true
		updateWaitingMessage()

		print("Map selection completed - Game starting now!")
	end)
end

function WaitingSystem.stopGame()
	isGamePlaying = false
	gameTimeLeft = 0

	-- หยุด game timer thread
	if gameTimerThread then
		task.cancel(gameTimerThread)
		gameTimerThread = nil
	end

	updateWaitingMessage()
	print("Game stopped")
end

-- ฟังก์ชันเริ่มนับถอยหลังเวลาบน Billboard
function WaitingSystem.startGameTimer(duration)
	gameTimeLeft = duration or 300
	isGamePlaying = true

	-- หยุด thread เก่าถ้ามี
	if gameTimerThread then
		task.cancel(gameTimerThread)
		gameTimerThread = nil
	end

	-- เริ่ม countdown
	gameTimerThread = task.spawn(function()
		while gameTimeLeft > 0 do
			updateWaitingMessage()
			task.wait(1)
			gameTimeLeft = gameTimeLeft - 1
		end

		-- เมื่อหมดเวลา
		gameTimeLeft = 0
		updateWaitingMessage()
		print("[WaitingSystem] Game timer finished")
	end)

	print("[WaitingSystem] Started game timer:", duration, "seconds")
end

-- ฟังก์ชันอัปเดตเวลาจาก server (ใช้เมื่อ sync เวลา)
function WaitingSystem.updateGameTime(timeLeft, timeText)
	gameTimeLeft = timeLeft

	-- ถ้ามี timeText (MM:SS) ให้ใช้แสดงบน Billboard โดยตรง
	if timeText and simuBillboard then
		local playerCount = #Players:GetPlayers()
		local maxPlayers = GameConfig.getMaxPlayers()
		simuBillboard.Text = string.format("Game in Progress (%d/%d players)\nTime: %s", playerCount, maxPlayers, timeText)
		simuBillboard.Visible = true
	else
		-- ถ้าไม่มี timeText ให้ใช้ formatTime แบบเดิม
		updateWaitingMessage()
	end
end

-- ฟังก์ชันรีเซ็ตระบบ
function WaitingSystem.reset()
	waitingPlayers = {}
	isGamePlaying = false
	updateWaitingMessage()
	print("WaitingSystem reset")
end

-- ฟังก์ชันตั้งค่าจำนวนผู้เล่นสูงสุด
function WaitingSystem.setMaxPlayers(count)
	if count and count > 0 then
		GameConfig.setMaxPlayers(count)
		updateWaitingMessage()
		print("Max players set to: " .. GameConfig.getMaxPlayers())
	end
end

-- ฟังก์ชันดูจำนวนผู้เล่นที่รออยู่
function WaitingSystem.getWaitingCount()
	return #waitingPlayers
end

-- ฟังก์ชันดูจำนวนผู้เล่นสูงสุด
function WaitingSystem.getMaxPlayers()
	return GameConfig.getMaxPlayers()
end

-- ฟังก์ชันดูรายการผู้เล่นที่รออยู่
function WaitingSystem.getWaitingPlayers()
	return waitingPlayers
end

-- ฟังก์ชันเริ่มนับถอยหลัง lobby
function WaitingSystem.startLobbyCountdown(duration)
	isLobbyCountingDown = true
	lobbyCountdownTime = duration or 60

	-- หยุด thread เก่าถ้ามี
	if lobbyCountdownThread then
		task.cancel(lobbyCountdownThread)
		lobbyCountdownThread = nil
	end

	-- เริ่ม countdown แบบต่อเนื่องทุกวินาที
	lobbyCountdownThread = task.spawn(function()
		while lobbyCountdownTime > 0 and isLobbyCountingDown do
			updateWaitingMessage()
			task.wait(1)
			lobbyCountdownTime = lobbyCountdownTime - 1
		end

		-- อัปเดตครั้งสุดท้าย
		if isLobbyCountingDown then
			updateWaitingMessage()
		end
	end)

	print("[WaitingSystem] Lobby countdown started:", lobbyCountdownTime, "seconds")
end

-- ฟังก์ชันอัปเดตเวลานับถอยหลัง lobby (sync จาก server)
function WaitingSystem.updateLobbyCountdown(timeLeft)
	-- sync เวลาจาก server เพื่อแก้ไข drift
	lobbyCountdownTime = timeLeft
	print("[WaitingSystem] Lobby countdown synced:", timeLeft, "seconds")
end

-- ฟังก์ชันหยุดนับถอยหลัง lobby
function WaitingSystem.stopLobbyCountdown()
	isLobbyCountingDown = false
	lobbyCountdownTime = 0

	-- หยุด thread
	if lobbyCountdownThread then
		task.cancel(lobbyCountdownThread)
		lobbyCountdownThread = nil
	end

	updateWaitingMessage()
	print("[WaitingSystem] Lobby countdown stopped")
end

-- ฟังก์ชันอัปเดตจำนวนผู้เล่นที่รอ (จาก server)
function WaitingSystem.updateWaitingCount(count)
	currentWaitingCount = count
	updateWaitingMessage()
	print("[WaitingSystem] Waiting count updated:", count)
end

-- เริ่มต้นระบบ
spawn(function()
	wait(1) -- รอให้ workspace โหลดเสร็จ
	simuBillboard = findSimuBillboard()
	updateWaitingMessage()
end)

return WaitingSystem
