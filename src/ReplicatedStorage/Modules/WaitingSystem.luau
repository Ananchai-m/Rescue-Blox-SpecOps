local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MapSelectionSystem = require(ReplicatedStorage.Modules.MapSelectionSystem)
local WaitingSystem = {}

-- ตัวแปรสำหรับติดตาม
local waitingPlayers = {}
local maxPlayers = 1
local simuBillboard = nil
local isCountingDown = false
local isGamePlaying = false

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

-- ฟังก์ชันอัปเดตข้อความรอ
local function updateWaitingMessage()
	if not simuBillboard then
		simuBillboard = findSimuBillboard()
		if not simuBillboard then
			return
		end
	end

	local waitingCount = #waitingPlayers
	local remaining = maxPlayers - waitingCount

	if isGamePlaying then
		simuBillboard.Text = "Game Playing!"
		simuBillboard.Visible = true
	elseif waitingCount > 0 and remaining > 0 then
		simuBillboard.Text = string.format("Waiting for other players %d/%d คน", remaining, maxPlayers)
		simuBillboard.Visible = true
	elseif waitingCount == 0 then 
		simuBillboard.Text = "Please join the mission!"
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
	if #waitingPlayers >= maxPlayers then
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
	updateWaitingMessage()
	print("Game stopped")
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
		maxPlayers = count
		updateWaitingMessage()
		print("Max players set to: " .. maxPlayers)
	end
end

-- ฟังก์ชันดูจำนวนผู้เล่นที่รออยู่
function WaitingSystem.getWaitingCount()
	return #waitingPlayers
end

-- ฟังก์ชันดูจำนวนผู้เล่นสูงสุด
function WaitingSystem.getMaxPlayers()
	return maxPlayers
end

-- ฟังก์ชันดูรายการผู้เล่นที่รออยู่
function WaitingSystem.getWaitingPlayers()
	return waitingPlayers
end

-- เริ่มต้นระบบ
spawn(function()
	wait(1) -- รอให้ workspace โหลดเสร็จ
	simuBillboard = findSimuBillboard()
	updateWaitingMessage()
end)

return WaitingSystem