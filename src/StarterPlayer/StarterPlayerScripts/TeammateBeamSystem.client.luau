-- TeammateBeamSystem.client.luau
-- แสดง Beam จาก Rescue ของผู้เล่นไปยัง Rescue ของเพื่อนที่ HP/Battery หมด

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local rescueRemotes = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local teammateDownRemote = rescueRemotes:WaitForChild("TeammateDown")

-- เก็บ Beam ที่สร้างไว้
local activeBeams = {} -- { [downedPlayer] = {beam, attachment0, attachment1, updateConnection} }

-- ฟังก์ชันสร้าง Beam
local function createBeam(myRescue, downedRescue, downedPlayer)
	-- ตรวจสอบว่า Rescue models ยังอยู่
	if not myRescue or not myRescue.PrimaryPart or not downedRescue or not downedRescue.PrimaryPart then
		warn("[TeammateBeam] Invalid Rescue models")
		return
	end

	-- ลบ Beam เก่าถ้ามี
	if activeBeams[downedPlayer] then
		local oldData = activeBeams[downedPlayer]
		if oldData.updateConnection then
			oldData.updateConnection:Disconnect()
		end
		if oldData.beam then
			oldData.beam:Destroy()
		end
		if oldData.attachment0 then
			oldData.attachment0:Destroy()
		end
		if oldData.attachment1 then
			oldData.attachment1:Destroy()
		end
		activeBeams[downedPlayer] = nil
	end

	-- สร้าง Attachments
	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "BeamAttachment0"
	attachment0.Parent = myRescue.PrimaryPart

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "BeamAttachment1"
	attachment1.Parent = downedRescue.PrimaryPart

	local beam = ReplicatedStorage.Effects.ArrowBeam:Clone()
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1

	-- ปรับให้ Beam สว่างแบบ glowing
	beam.LightEmission = 1 -- เรื่องแสงเต็มที่
	beam.LightInfluence = 0 -- ไม่รับอิทธิพลจากแสงโดยรอบ
	beam.Brightness = 3 -- เพิ่มความสว่าง
	beam.Width0 = 2.5 -- เพิ่มความกว้าง
	beam.Width1 = 2.5

	-- ใช้สีแดง-ส้ม-เหลือง สว่างมาก
	local glowColor = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 150, 150)),   -- แดงสว่าง
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 100)), -- ส้ม-เหลืองสว่าง
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 200))    -- เหลืองสว่างมาก
	})
	beam.Color = glowColor

	-- ทำให้ทึบเต็มที่เพื่อให้เห็นชัด
	beam.Transparency = NumberSequence.new(0)

	-- ถ้ามี Texture ให้เคลื่อนไหว
	if beam.Texture and beam.Texture ~= "" then
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureSpeed = 3 -- เร็วขึ้น
		beam.TextureLength = 2
	end

	beam.Parent = myRescue.PrimaryPart

	print(string.format("[TeammateBeam] Created glowing beam from %s to %s (downed)", player.Name, downedPlayer.Name))

	-- เพิ่ม animation กระพริบ (Pulse effect)
	local pulseTime = 0
	local pulseSpeed = 3 -- เพิ่มความเร็วของการกระพริบ

	-- สร้าง connection เพื่ออัพเดตตำแหน่ง Beam (ถ้า Rescue เคลื่อนที่)
	local updateConnection = RunService.Heartbeat:Connect(function(deltaTime)
		-- อัพเดต animation กระพริบแบบ glowing
		pulseTime = pulseTime + deltaTime * pulseSpeed
		local pulseValue = (math.sin(pulseTime * math.pi * 2) + 1) / 2 -- 0 ถึง 1

		-- ปรับ Brightness ตาม pulse (2 ถึง 4) - glow มากขึ้น
		beam.Brightness = 2 + (pulseValue * 2)

		-- ปรับ Width ตาม pulse (2 ถึง 3)
		local widthScale = 1 + pulseValue
		beam.Width0 = widthScale
		beam.Width1 = widthScale

		-- ปรับสีให้สว่างขึ้นตาม pulse
		local glowIntensity = 150 + (pulseValue * 105) -- 150 ถึง 255
		local glowColor = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, glowIntensity, glowIntensity)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 220, 100 + (pulseValue * 155))),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 200 + (pulseValue * 55)))
		})
		beam.Color = glowColor

		-- เช็คว่า models ยังอยู่หรือไม่
		if not myRescue or not myRescue.Parent or not myRescue.PrimaryPart or
		   not downedRescue or not downedRescue.Parent or not downedRescue.PrimaryPart then
			-- ลบ Beam
			if activeBeams[downedPlayer] then
				local data = activeBeams[downedPlayer]
				if data.updateConnection then
					data.updateConnection:Disconnect()
				end
				if data.beam then
					data.beam:Destroy()
				end
				if data.attachment0 then
					data.attachment0:Destroy()
				end
				if data.attachment1 then
					data.attachment1:Destroy()
				end
				activeBeams[downedPlayer] = nil
				print(string.format("[TeammateBeam] Removed beam to %s (model destroyed)", downedPlayer.Name))
			end
			return
		end

		-- เช็คว่า downed rescue ฟื้นแล้วหรือยัง (IsDown = false)
		local isDown = downedRescue:GetAttribute("IsDown")
		if isDown == false then
			-- ฟื้นแล้ว ลบ Beam
			if activeBeams[downedPlayer] then
				local data = activeBeams[downedPlayer]
				if data.updateConnection then
					data.updateConnection:Disconnect()
				end
				if data.beam then
					data.beam:Destroy()
				end
				if data.attachment0 then
					data.attachment0:Destroy()
				end
				if data.attachment1 then
					data.attachment1:Destroy()
				end
				activeBeams[downedPlayer] = nil
				print(string.format("[TeammateBeam] Removed beam to %s (revived)", downedPlayer.Name))
			end
			return
		end
	end)

	-- เก็บข้อมูล
	activeBeams[downedPlayer] = {
		beam = beam,
		attachment0 = attachment0,
		attachment1 = attachment1,
		updateConnection = updateConnection,
	}
end

-- ฟังก์ชันหา Rescue model ของผู้เล่น
local function findMyRescue()
	return workspace:FindFirstChild(player.Name .. "_Rescue")
end

-- รับสัญญาณจาก server ว่าเพื่อนล้ม
teammateDownRemote.OnClientEvent:Connect(function(downedPlayer, downedRescue)
	if not downedPlayer or not downedRescue then
		warn("[TeammateBeam] Invalid data received")
		return
	end

	print(string.format("[TeammateBeam] Received notification: %s is down", downedPlayer.Name))

	-- หา Rescue ของตัวเอง
	local myRescue = findMyRescue()
	if not myRescue then
		warn("[TeammateBeam] My Rescue not found - will retry when it spawns")

		-- รอให้ Rescue spawn แล้วค่อยสร้าง Beam
		local retryCount = 0
		local maxRetries = 20
		task.spawn(function()
			while retryCount < maxRetries do
				task.wait(0.5)
				myRescue = findMyRescue()
				if myRescue then
					print("[TeammateBeam] My Rescue found - creating beam")
					createBeam(myRescue, downedRescue, downedPlayer)
					break
				end
				retryCount = retryCount + 1
			end

			if retryCount >= maxRetries then
				warn("[TeammateBeam] Failed to find my Rescue after retries")
			end
		end)
		return
	end

	-- สร้าง Beam
	createBeam(myRescue, downedRescue, downedPlayer)
end)

-- Cleanup เมื่อผู้เล่นออก
Players.PlayerRemoving:Connect(function(leavingPlayer)
	-- ลบ Beam ที่เกี่ยวข้องกับผู้เล่นที่ออก
	if activeBeams[leavingPlayer] then
		local data = activeBeams[leavingPlayer]
		if data.updateConnection then
			data.updateConnection:Disconnect()
		end
		if data.beam then
			data.beam:Destroy()
		end
		if data.attachment0 then
			data.attachment0:Destroy()
		end
		if data.attachment1 then
			data.attachment1:Destroy()
		end
		activeBeams[leavingPlayer] = nil
		print(string.format("[TeammateBeam] Removed beam to %s (player left)", leavingPlayer.Name))
	end
end)

print("[TeammateBeam] System initialized")
