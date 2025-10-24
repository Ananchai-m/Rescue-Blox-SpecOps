--[[
	VideoIntro Module
	แสดงวิดีโอเมื่อเข้าเกม
	- ครั้งแรก: ดูจนจบ (ไม่มีปุ่ม Skip)
	- ครั้งที่ 2+: มีปุ่ม Skip
]]

local VideoIntro = {}

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local tweenService = game:GetService("TweenService")

-- รอ RemoteFunction และ RemoteEvent
local remoteFolder = ReplicatedStorage:WaitForChild("RescueBotRemotes")
local checkWatchedFunction = remoteFolder:WaitForChild("CheckWatchedIntro") :: RemoteFunction
local markWatchedEvent = remoteFolder:WaitForChild("MarkWatchedIntro") :: RemoteEvent

-- ฟังก์ชันเช็คว่าผู้เล่นเคยดูวิดีโอแล้วหรือยัง (เรียก Server)
local function hasWatchedBefore(player): boolean
	local success, result = pcall(function()
		return checkWatchedFunction:InvokeServer()
	end)

	if success and result == true then
		return true
	end

	return false
end

-- ฟังก์ชันบันทึกว่าผู้เล่นดูวิดีโอแล้ว (ส่งไป Server)
local function markAsWatched(player)
	pcall(function()
		markWatchedEvent:FireServer()
	end)
	print("[VideoIntro] Marked as watched for", player.Name)
end

function VideoIntro.Show(videoId: number)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- เช็คว่าผู้เล่นเคยดูวิดีโอแล้วหรือยัง
	local hasWatched = hasWatchedBefore(player)

	-- สร้าง ScreenGui
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "VideoIntroGui"
	screenGui.DisplayOrder = 100
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	-- สร้าง Background Frame
	local backgroundFrame = Instance.new("Frame")
	backgroundFrame.Name = "Background"
	backgroundFrame.Size = UDim2.fromScale(1, 1)
	backgroundFrame.Position = UDim2.fromScale(0, 0)
	backgroundFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	backgroundFrame.BorderSizePixel = 0
	backgroundFrame.BackgroundTransparency = 0
	backgroundFrame.Parent = screenGui

	-- สร้าง VideoFrame
	local videoFrame = Instance.new("VideoFrame")
	videoFrame.Name = "IntroVideo"
	videoFrame.Size = UDim2.fromScale(1, 1)
	videoFrame.Position = UDim2.fromScale(0, 0)
	videoFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	videoFrame.BorderSizePixel = 0
	videoFrame.Video = "rbxassetid://" .. tostring(videoId)
	videoFrame.Looped = false
	videoFrame.Volume = 0.5
	videoFrame.Visible = true
	videoFrame.ZIndex = 1
	videoFrame.Parent = backgroundFrame

	-- สร้างปุ่ม Skip (แสดงเฉพาะถ้าดูวิดีโอไปแล้ว)
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipButton"
	skipButton.Size = UDim2.fromScale(0.15, 0.08)
	skipButton.Position = UDim2.fromScale(0.83, 0.88)
	skipButton.AnchorPoint = Vector2.new(0.5, 0.5)
	skipButton.BackgroundTransparency = 1
	skipButton.TextTransparency = 1
	skipButton.BorderSizePixel = 0
	skipButton.Text = "SKIP"
	skipButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	skipButton.TextScaled = true
	skipButton.Font = Enum.Font.GothamBold
	skipButton.Visible = false -- ซ่อนไว้ก่อน
	skipButton.Parent = backgroundFrame

	-- เพิ่ม UITextSizeConstraint
	local textSizeConstraint = Instance.new("UITextSizeConstraint")
	textSizeConstraint.MinTextSize = 14
	textSizeConstraint.MaxTextSize = 28
	textSizeConstraint.Parent = skipButton

	-- ตัวแปรเช็คว่าปิดไปแล้วหรือยัง
	local hasEnded = false

	-- ฟังก์ชันปิดวิดีโอ
	local function closeVideo()
		if hasEnded then
			return
		end
		hasEnded = true

		print("[VideoIntro] Closing video intro")

		-- หยุดวิดีโอ
		videoFrame:Pause()

		-- Fade out
		local fadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local fadeTween = tweenService:Create(backgroundFrame, fadeInfo, {
			BackgroundTransparency = 1
		})

		local buttonTween = tweenService:Create(skipButton, fadeInfo, {
			TextTransparency = 1
		})

		fadeTween:Play()
		buttonTween:Play()

		-- รอ fade out เสร็จแล้วลบ GUI
		fadeTween.Completed:Wait()
		screenGui:Destroy()

		-- ลบ Loading Screen ของ Roblox
		ReplicatedFirst:RemoveDefaultLoadingScreen()
	end

	-- เมื่อกดปุ่ม Skip
	skipButton.Activated:Connect(function()
		print("[VideoIntro] Skip button pressed")
		closeVideo()
	end)

	-- เมื่อวิดีโอเล่นจบ
	videoFrame.Ended:Connect(function()
		-- บันทึกว่าผู้เล่นดูวิดีโอแล้ว
		if not hasWatched then
			markAsWatched(player)
		end
		closeVideo()
	end)

	-- Hover effect ปุ่ม Skip
	skipButton.MouseEnter:Connect(function()
		if hasEnded then
			return
		end
		local hoverTween = tweenService:Create(skipButton, TweenInfo.new(0.2), {
			TextColor3 = Color3.fromRGB(220, 220, 220)
		})
		hoverTween:Play()
	end)

	skipButton.MouseLeave:Connect(function()
		if hasEnded then
			return
		end
		local leaveTween = tweenService:Create(skipButton, TweenInfo.new(0.2), {
			TextColor3 = Color3.fromRGB(255, 255, 255)
		})
		leaveTween:Play()
	end)

	-- เล่นวิดีโอทันที
	print("[VideoIntro] Playing video:", videoId)
	videoFrame:Play()

	-- แสดงปุ่ม Skip (เฉพาะถ้าดูวิดีโอไปแล้ว)
	if hasWatched then
		print("[VideoIntro] Showing Skip button (watched before)")
		skipButton.Visible = true
		local skipFadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local skipFadeTween = tweenService:Create(skipButton, skipFadeInfo, {
			TextTransparency = 0
		})
		skipFadeTween:Play()
	else
		print("[VideoIntro] No Skip button (first time)")
	end

	return screenGui
end

return VideoIntro
