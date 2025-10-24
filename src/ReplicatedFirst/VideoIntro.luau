--[[
	VideoIntro Module
	แสดงวิดีโอเมื่อเข้าเกม พร้อมปุ่ม Skip
]]

local VideoIntro = {}

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local tweenService = game:GetService("TweenService")

function VideoIntro.Show(videoId: number)
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

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

	-- สร้าง Title Frame สำหรับแสดงชื่อเกม
	local titleFrame = Instance.new("Frame")
	titleFrame.Name = "TitleFrame"
	titleFrame.Size = UDim2.fromScale(1, 1)
	titleFrame.Position = UDim2.fromScale(0, 0)
	titleFrame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	titleFrame.BorderSizePixel = 0
	titleFrame.BackgroundTransparency = 1
	titleFrame.ZIndex = 2
	titleFrame.Parent = backgroundFrame

	-- สร้าง Title Text "RESCUE BLOX" (เริ่มจากโปร่งใส)
	local titleText = Instance.new("TextLabel")
	titleText.Name = "TitleText"
	titleText.Size = UDim2.fromScale(0.8, 0.15)
	titleText.Position = UDim2.fromScale(0.5, 0.42)
	titleText.AnchorPoint = Vector2.new(0.5, 0.5)
	titleText.BackgroundTransparency = 1
	titleText.Text = "RESCUE BLOX"
	titleText.TextColor3 = Color3.fromRGB(255, 255, 255)
	titleText.TextTransparency = 0
	titleText.TextScaled = true
	titleText.Font = Enum.Font.GothamBold
	titleText.Parent = titleFrame

	-- เพิ่ม UITextSizeConstraint สำหรับ Title
	local titleTextSizeConstraint = Instance.new("UITextSizeConstraint")
	titleTextSizeConstraint.MinTextSize = 40
	titleTextSizeConstraint.MaxTextSize = 120
	titleTextSizeConstraint.Parent = titleText

	-- สร้าง Subtitle "SpecOps" (เริ่มจากโปร่งใส)
	local subtitleText = Instance.new("TextLabel")
	subtitleText.Name = "SubtitleText"
	subtitleText.Size = UDim2.fromScale(0.6, 0.08)
	subtitleText.Position = UDim2.fromScale(0.5, 0.58)
	subtitleText.AnchorPoint = Vector2.new(0.5, 0.5)
	subtitleText.BackgroundTransparency = 1
	subtitleText.Text = "SpecOps"
	subtitleText.TextColor3 = Color3.fromRGB(200, 200, 200)
	subtitleText.TextTransparency = 0
	subtitleText.TextScaled = true
	subtitleText.Font = Enum.Font.Gotham
	subtitleText.Parent = titleFrame

	-- เพิ่ม UITextSizeConstraint สำหรับ Subtitle
	local subtitleTextSizeConstraint = Instance.new("UITextSizeConstraint")
	subtitleTextSizeConstraint.MinTextSize = 20
	subtitleTextSizeConstraint.MaxTextSize = 60
	subtitleTextSizeConstraint.Parent = subtitleText

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
	videoFrame.Visible = false
	videoFrame.ZIndex = 1
	videoFrame.Parent = backgroundFrame

	-- สร้างปุ่ม Skip (ซ่อนไว้ก่อน จะแสดงตอนเล่นวิดีโอ)
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
	skipButton.Visible = false
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

	-- แสดง Title ก่อน แล้วค่อย fade ไปวิดีโอ
	print("[VideoIntro] Fading in game title")
	local tweenService = game:GetService("TweenService")

	-- Fade in Title และ Subtitle
	local fadeInInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local titleFadeInTween = tweenService:Create(titleText, fadeInInfo, {
		TextTransparency = 0
	})
	local subtitleFadeInTween = tweenService:Create(subtitleText, fadeInInfo, {
		TextTransparency = 0
	})

	titleFadeInTween:Play()
	subtitleFadeInTween:Play()

	-- รอ fade in เสร็จ
	titleFadeInTween.Completed:Wait()

	print("[VideoIntro] Title displayed")
	print("[VideoIntro] Fading out title, preparing video")
	local titleFadeOutInfo = TweenInfo.new(5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local titleFadeTween = tweenService:Create(titleFrame, titleFadeOutInfo, {
		BackgroundTransparency = 1
	})
	local titleTextFadeTween = tweenService:Create(titleText, titleFadeOutInfo, {
		TextTransparency = 1
	})
	local subtitleTextFadeTween = tweenService:Create(subtitleText, titleFadeOutInfo, {
		TextTransparency = 1
	})

	titleFadeTween:Play()
	titleTextFadeTween:Play()
	subtitleTextFadeTween:Play()

	-- รอ fade out เสร็จ
	titleFadeTween.Completed:Wait()

	-- ลบ title frame
	titleFrame:Destroy()

	-- แสดงวิดีโอและเริ่มเล่น
	print("[VideoIntro] Playing video: " .. videoId)
	videoFrame.Visible = true
	videoFrame:Play()

	-- แสดงปุ่ม Skip ด้วย fade in
	skipButton.Visible = true
	local skipFadeInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local skipFadeTween = tweenService:Create(skipButton, skipFadeInfo, {
		TextTransparency = 0
	})
	skipFadeTween:Play()

	return screenGui
end

return VideoIntro
