-- SpawnPointManager ModuleScript
-- จัดการระบบ spawn points ระหว่าง server และ client

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SpawnPointManager = {}

-- รอ RemoteEvents
local remoteEvents = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local spawnAssignmentRemote = remoteEvents:WaitForChild("SpawnAssignment")

-- ฟังก์ชันขอ spawn point จาก server (สำหรับ client)
function SpawnPointManager.requestSpawnPoint()
	print("SpawnPointManager: Requesting spawn point from server...")
	spawnAssignmentRemote:FireServer("getSpawnPoint")

	-- สร้าง Promise-like pattern
	return {
		await = function(timeout)
			timeout = timeout or 5 -- default 5 วินาที
			local finalSpawnPosition = nil
			local spawnPointReceived = false

			-- รอ response จาก server
			local connection
			connection = spawnAssignmentRemote.OnClientEvent:Connect(function(action, position)
				if action == "spawnPoint" and not spawnPointReceived then
					spawnPointReceived = true
					connection:Disconnect()

					if position then
						finalSpawnPosition = position + Vector3.new(0, 5, 0)
						print("SpawnPointManager: Received assigned spawn point:", position)
					else
						warn("SpawnPointManager: No spawn point assigned by server")
					end
				end
			end)

			-- รอให้ได้ response หรือ timeout
			local timeWaited = 0
			while not spawnPointReceived and timeWaited < timeout do
				wait(0.1)
				timeWaited = timeWaited + 0.1
			end

			if not spawnPointReceived then
				connection:Disconnect()
				warn("SpawnPointManager: Timeout waiting for spawn point from server")
			end

			return finalSpawnPosition
		end
	}
end

-- ฟังก์ชัน fallback สำหรับการสุ่ม spawn point เอง
function SpawnPointManager.getFallbackSpawnPoint()
	warn("SpawnPointManager: Using fallback random selection")
	local spawnRescues = workspace:FindFirstChild("SpawnRescues")
	if not spawnRescues then
		warn("SpawnPointManager: SpawnRescues folder not found")
		return nil
	end

	local spawnPoints = {}
	for _, child in ipairs(spawnRescues:GetChildren()) do
		if child:IsA("BasePart") then
			table.insert(spawnPoints, child)
		end
	end

	if #spawnPoints == 0 then
		warn("SpawnPointManager: No spawn points found in SpawnRescues folder")
		return nil
	end

	local randomSpawnPoint = spawnPoints[math.random(1, #spawnPoints)]
	local position = randomSpawnPoint.Position + Vector3.new(0, 5, 0)
	print("SpawnPointManager: Selected fallback spawn point:", randomSpawnPoint.Name, "at:", position)
	return position
end

-- ฟังก์ชันหลักสำหรับขอ spawn point (พร้อม fallback)
function SpawnPointManager.getSpawnPoint(timeout)
	local spawnPromise = SpawnPointManager.requestSpawnPoint()
	local position = spawnPromise.await(timeout)

	-- ถ้าไม่ได้ position จาก server ให้ใช้ fallback
	if not position then
		position = SpawnPointManager.getFallbackSpawnPoint()
	end

	return position
end

-- ฟังก์ชันตรวจสอบว่ามี SpawnRescues หรือไม่
function SpawnPointManager.checkSpawnPoints()
	local spawnRescues = workspace:FindFirstChild("SpawnRescues")
	if not spawnRescues then
		return false, "SpawnRescues folder not found in workspace"
	end

	local spawnPointCount = 0
	for _, child in ipairs(spawnRescues:GetChildren()) do
		if child:IsA("BasePart") then
			spawnPointCount = spawnPointCount + 1
		end
	end

	if spawnPointCount == 0 then
		return false, "No spawn points found in SpawnRescues folder"
	end

	return true, "Found " .. spawnPointCount .. " spawn points"
end

return SpawnPointManager