local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")

local CompanionFollower = {}
CompanionFollower.__index = CompanionFollower

local SMALL_NUMBER = 1e-4

local KEEP_SURFACE = 5
local SLOW_BAND = 8
local RETARGET_EPS = 0.3
local MIN_WS, MAX_WS = 8, 16
local TICK = 0.03

local AGENT_RADIUS = 3
local AGENT_HEIGHT = 4
local WAYPOINT_REACH = 3.5
local REPATH_DIST = 6
local REPATH_COOLDOWN = 0.2

local SLOPE_ENTER_DEG = 20
local SLOPE_EXIT_DEG = 10
local STUCK_TIME_TO_CLIMB = 0.1
local LEDGE_AHEAD, LEDGE_MIN_H = 2.5, 1

local flat = Vector3.new(1, 0, 1)
local clock = os.clock

local function safeGet(humanoid: Humanoid, prop, fallback)
	local ok, value = pcall(function()
		return humanoid[prop]
	end)
	return (ok and value ~= nil) and value or fallback
end

local function horizontalUnit(vec: Vector3)
	local flatVec = Vector3.new(vec.X, 0, vec.Z)
	local magnitude = flatVec.Magnitude
	if magnitude < SMALL_NUMBER then
		return nil
	end
	return flatVec / magnitude
end

local function getRoot(model: Instance): BasePart?
	return (model and (model:FindFirstChild("HumanoidRootPart") or model:FindFirstChild("Torso"))) :: BasePart?
end

local function getRadius(model: Model): number
	local root = getRoot(model)
	if root then
		return math.max(root.Size.X, root.Size.Z) * 0.5
	end
	local s = model:GetExtentsSize()
	return math.max(s.X, s.Z) * 0.25
end

local function groundPointAt(humanoid: Humanoid, baseHipHeight: number, xz: Vector3, ignore: {Instance})
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local origin = xz + Vector3.new(0, 150, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -2000, 0), params)
	if hit then
		local hh = safeGet(humanoid, "HipHeight", baseHipHeight)
		return Vector3.new(xz.X, hit.Position.Y + math.max(1, hh * 0.5), xz.Z)
	end
	return xz
end

local function waitForOwnerUserId(character: Instance)
	local ownerId = character:GetAttribute("OwnerUserId")
	if ownerId then
		return ownerId
	end
	local signal = character:GetAttributeChangedSignal("OwnerUserId")
	repeat
		signal:Wait()
		ownerId = character:GetAttribute("OwnerUserId")
	until ownerId
	return ownerId
end

function CompanionFollower.new(character: Model)
	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = character:WaitForChild("Humanoid")
	end

	if not humanoid then
		return nil
	end

	humanoid.AutoRotate = true
	pcall(function()
		humanoid.UseJumpPower = true
	end)

	local base = {
		JumpPower = safeGet(humanoid, "JumpPower", 50),
		MaxSlopeAngle = safeGet(humanoid, "MaxSlopeAngle", 60),
		HipHeight = safeGet(humanoid, "HipHeight", 0.5),
	}

	local climb = {
		active = false,
		lastActiveT = 0,
		JumpPower = math.max(base.JumpPower, 20),
		MaxSlopeAngle = 85,
		HipHeightInc = 0.5,
		STABLE_TIME = 0.6,
	}

	local self = setmetatable({
		character = character,
		humanoid = humanoid,
		base = base,
		climb = climb,
		currentPath = nil,
		waypoints = {},
		wpi = 0,
		lastGoal = nil,
		repathCooldown = 0,
		stuckTimer = 0,
		lastPos = nil,
		running = true,
		ownerUserId = waitForOwnerUserId(character),
	}, CompanionFollower)

	character.AncestryChanged:Connect(function(_, parent)
		if not parent then
			self.running = false
		end
	end)

	humanoid.Died:Connect(function()
		self.running = false
	end)

	task.spawn(function()
		self:run()
	end)

	return self
end

function CompanionFollower:enterClimb()
	local climb = self.climb
	if climb.active then
		climb.lastActiveT = clock()
		return
	end
	climb.active = true
	climb.lastActiveT = clock()
	local humanoid = self.humanoid
	pcall(function()
		humanoid.JumpPower = climb.JumpPower
	end)
	pcall(function()
		humanoid.MaxSlopeAngle = climb.MaxSlopeAngle
	end)
	pcall(function()
		humanoid.HipHeight = self.base.HipHeight + climb.HipHeightInc
	end)
end

function CompanionFollower:exitClimb()
	local climb = self.climb
	if not climb.active then
		return
	end
	climb.active = false
	local humanoid = self.humanoid
	pcall(function()
		humanoid.JumpPower = self.base.JumpPower
	end)
	pcall(function()
		humanoid.MaxSlopeAngle = self.base.MaxSlopeAngle
	end)
	pcall(function()
		humanoid.HipHeight = self.base.HipHeight
	end)
end

function CompanionFollower:getOwnerCharacter()
	local player = Players:GetPlayerByUserId(self.ownerUserId)
	if not player then
		return nil, nil
	end
	local char = player.Character
	if not char then
		return nil, nil
	end
	return char, getRoot(char)
end

function CompanionFollower:computePath(startPos: Vector3, goal: Vector3, ignore: {Instance})
	local path = PathfindingService:CreatePath({
		AgentRadius = AGENT_RADIUS,
		AgentHeight = AGENT_HEIGHT,
		AgentCanJump = true,
		WaypointSpacing = 4,
	})
	path:ComputeAsync(groundPointAt(self.humanoid, self.base.HipHeight, startPos, ignore), groundPointAt(self.humanoid, self.base.HipHeight, goal, ignore))
	if path.Status == Enum.PathStatus.Success then
		self.currentPath = path
		self.waypoints = path:GetWaypoints()
		self.wpi = 1
		return true
	end
	self.currentPath = nil
	self.waypoints = {}
	self.wpi = 0
	return false
end

function CompanionFollower:stepClimbLogic(slopeDeg: number, moved: number)
	if slopeDeg >= SLOPE_ENTER_DEG or self.stuckTimer >= STUCK_TIME_TO_CLIMB then
		self:enterClimb()
	else
		if self.climb.active then
			if slopeDeg <= SLOPE_EXIT_DEG and moved > 0.05 and (clock() - self.climb.lastActiveT) >= self.climb.STABLE_TIME then
				self:exitClimb()
			end
		end
	end
end

function CompanionFollower:run()
	while self.running and task.wait(TICK) do
		local humanoid = self.humanoid
		if humanoid.Health <= 0 then
			break
		end

		local myRoot = getRoot(self.character)
		if not myRoot then
			continue
		end

		local ownerChar, targetRoot = self:getOwnerCharacter()
		if not ownerChar or not targetRoot then
			humanoid:Move(Vector3.zero)
			self.lastGoal = nil
			self.currentPath = nil
			self.waypoints = {}
			self.wpi = 0
			self:exitClimb()
			continue
		end

		local delta = targetRoot.Position - myRoot.Position
		local centerDist = delta.Magnitude
		if centerDist < SMALL_NUMBER then
			humanoid:Move(Vector3.zero)
			continue
		end

		local rSelf = getRadius(self.character)
		local rOther = getRadius(ownerChar)
		local surfaceDist = centerDist - (rSelf + rOther)

		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { self.character }
		local groundHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 4, 0), Vector3.new(0, -12, 0), params)
		local slopeDeg = 0
		if groundHit then
			local ny = math.clamp(groundHit.Normal.Y, -1, 1)
			slopeDeg = math.deg(math.acos(ny))
		end

		local moved = 0
		if self.lastPos then
			moved = (myRoot.Position - self.lastPos).Magnitude
		end
		if moved < 0.05 then
			self.stuckTimer += TICK
		else
			self.stuckTimer = 0
		end

		self:stepClimbLogic(slopeDeg, moved)

		if surfaceDist <= KEEP_SURFACE then
			humanoid:Move(Vector3.zero)
			self.lastGoal = nil
			self.currentPath = nil
			self.waypoints = {}
			self.wpi = 0
			if slopeDeg <= SLOPE_EXIT_DEG then
				self:exitClimb()
			end
			self.lastPos = myRoot.Position
			continue
		end

		local over = math.max(0, surfaceDist - KEEP_SURFACE)
		local t = math.clamp(over / SLOW_BAND, 0, 1)
		humanoid.WalkSpeed = MIN_WS + (MAX_WS - MIN_WS) * t

		local dir = delta.Unit
		local rawGoal = targetRoot.Position - dir * (KEEP_SURFACE + rSelf + rOther)
		local groundGoal = groundPointAt(humanoid, self.base.HipHeight, rawGoal, { self.character, ownerChar })

		local needRepath = (not self.currentPath) or (self.lastGoal and (groundGoal - self.lastGoal).Magnitude > REPATH_DIST)
		if needRepath and self.repathCooldown <= 0 then
			self:computePath(myRoot.Position, groundGoal, { self.character, ownerChar })
			self.lastGoal = groundGoal
			self.repathCooldown = REPATH_COOLDOWN
		end
		self.repathCooldown = math.max(0, self.repathCooldown - TICK)

		local targetPos: Vector3
		if self.wpi > 0 and self.waypoints[self.wpi] then
			targetPos = groundPointAt(humanoid, self.base.HipHeight, self.waypoints[self.wpi].Position, { self.character })
			if (myRoot.Position - targetPos).Magnitude <= WAYPOINT_REACH then
				self.wpi += 1
				if not self.waypoints[self.wpi] then
					self.currentPath = nil
					self.wpi = 0
				end
			end
		else
			targetPos = groundGoal
		end

		local moveDir = (targetPos - myRoot.Position).Unit
		humanoid:Move(moveDir)

		if self.climb.active then
			local lookFlat = horizontalUnit((myRoot.CFrame.LookVector * flat))
			if lookFlat then
				local baseHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 2, 0), Vector3.new(0, -8, 0), params)
				local frontHit = workspace:Raycast(myRoot.Position + Vector3.new(0, 2, 0) + lookFlat * LEDGE_AHEAD, Vector3.new(0, -8, 0), params)
				if baseHit and frontHit then
					local step = frontHit.Position.Y - baseHit.Position.Y
					if step > LEDGE_MIN_H then
						humanoid.Jump = true
					end
				end
			end
		end

		self.lastPos = myRoot.Position
	end

	self:exitClimb()
end

function CompanionFollower.start(character: Model)
	return CompanionFollower.new(character)
end

return CompanionFollower
