-- ShopUI Module
-- จัดการ UI ของร้านค้า

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

-- Import TopbarPlus
local TopbarPlus = require(ReplicatedStorage.Packages.TopbarPlus)

local ShopUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ตัวแปร UI
local shopScreenGui = nil
local shopFrame = nil
local shopIcon = nil -- เปลี่ยนจาก shopButton เป็น shopIcon
local isShopOpen = false
local isAnimating = false

-- ตัวแปรสำหรับระบบเลื่อน
local currentPage = 1
local itemsPerPage = 4
local itemCards = {}
local scrollingFrame = nil
local leftArrow = nil
local rightArrow = nil

local function formatItemName(text, breakName)
	local value = text and text ~= "" and text or "Item"
	local shouldBreak = breakName
	if shouldBreak == nil then
		shouldBreak = true
	end

	if shouldBreak then
		local firstSpace = value:find("%s")
		if firstSpace then
			local before = value:sub(1, firstSpace - 1)
			local after = value:sub(firstSpace + 1)
			value = before .. "\n" .. after
		end
	end

	return value
end

-- ฟังก์ชันสร้าง Shop Button
-- ฟังก์ชันสร้าง Shop Icon ด้วย TopbarPlus
local function createShopIcon()
	if shopIcon then return shopIcon end

	-- สร้าง Icon ด้วย TopbarPlus
	shopIcon = TopbarPlus.new()
	    :setImage("4882429582") -- Shopping cart icon
		:setLabel("Shop")
		:setOrder(1) -- วางถัดจาก Chat

	-- Bind events
	shopIcon.selected:Connect(function()
		ShopUI.openShop()
	end)

	shopIcon.deselected:Connect(function()
		ShopUI.closeShop()
	end)

	print("[ShopUI] Created Shop icon with TopbarPlus")
	return shopIcon
end

local function ensureShopIcon()
	if shopIcon then
		return shopIcon
	end

	return createShopIcon()
end

-- ฟังก์ชันอัปเดตสถานะปุ่มลูกศร (ประกาศก่อนเพื่อให้ createShopUI ใช้ได้)
local function updateArrowStates()
	if not leftArrow or not rightArrow then return end

	local totalItems = #itemCards
	local totalPages = math.ceil(totalItems / itemsPerPage)

	if totalPages <= 1 then
		leftArrow.Visible = false
		rightArrow.Visible = false
		return
	end

	leftArrow.Visible = true
	rightArrow.Visible = true

	if currentPage <= 1 then
		leftArrow.BackgroundTransparency = 0.7
	else
		leftArrow.BackgroundTransparency = 0.3
	end

	if currentPage >= totalPages then
		rightArrow.BackgroundTransparency = 0.7
	else
		rightArrow.BackgroundTransparency = 0.3
	end
end

-- ฟังก์ชันสร้าง Shop UI
local function createShopUI()
	if shopScreenGui then return shopScreenGui end

	-- สร้าง ScreenGui
	shopScreenGui = Instance.new("ScreenGui")
	shopScreenGui.Name = "ShopGui"
	shopScreenGui.IgnoreGuiInset = true
	shopScreenGui.ResetOnSpawn = false
	shopScreenGui.DisplayOrder = 200
	shopScreenGui.Enabled = false
	shopScreenGui.Parent = playerGui

	-- สร้าง Background (มืดๆ ด้านหลัง)
	local background = Instance.new("Frame")
	background.Name = "Background"
	background.Size = UDim2.new(1, 0, 1, 0)
	background.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	background.BackgroundTransparency = 0.5
	background.BorderSizePixel = 0
	background.Parent = shopScreenGui

	-- สร้าง Main Frame
	shopFrame = Instance.new("Frame")
	shopFrame.Name = "ShopFrame"
	shopFrame.Size = UDim2.new(0.7, 0, 0.85, 0)
	shopFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	shopFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	shopFrame.BackgroundColor3 = Color3.fromRGB(238, 240, 245)
	shopFrame.BorderSizePixel = 0
	shopFrame.Parent = shopScreenGui

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(205, 208, 220)
	frameStroke.Thickness = 1
	frameStroke.Parent = shopFrame

	-- สร้าง Top Bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0.12, 0)
	topBar.BackgroundColor3 = Color3.fromRGB(101, 105, 115)
	topBar.BorderSizePixel = 0
	topBar.Parent = shopFrame

	local topPadding = Instance.new("UIPadding")
	topPadding.PaddingLeft = UDim.new(0.025, 0)
	topPadding.PaddingRight = UDim.new(0.025, 0)
	topPadding.Parent = topBar

	local shopLabel = Instance.new("TextLabel")
	shopLabel.Name = "SectionTitle"
	shopLabel.Size = UDim2.fromScale(0.15, 1)
	shopLabel.BackgroundTransparency = 1
	shopLabel.Font = Enum.Font.GothamBold
	shopLabel.Text = "Shop"
	shopLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopLabel.TextScaled = true
	shopLabel.TextXAlignment = Enum.TextXAlignment.Left
	shopLabel.Parent = topBar

	local shopConstraint = Instance.new("UITextSizeConstraint")
	shopConstraint.MaxTextSize = 28
	shopConstraint.MinTextSize = 16
	shopConstraint.Parent = shopLabel

	local brandLabel = Instance.new("TextLabel")
	brandLabel.Name = "Brand"
	brandLabel.Size = UDim2.fromScale(0.3, 1)
	brandLabel.Position = UDim2.fromScale(0.5, 0)
	brandLabel.AnchorPoint = Vector2.new(0.5, 0)
	brandLabel.BackgroundTransparency = 1
	brandLabel.Font = Enum.Font.GothamBold
	brandLabel.Text = "Rescue Blox"
	brandLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	brandLabel.TextScaled = true
	brandLabel.TextXAlignment = Enum.TextXAlignment.Center
	brandLabel.Parent = topBar

	local brandConstraint = Instance.new("UITextSizeConstraint")
	brandConstraint.MaxTextSize = 30
	brandConstraint.MinTextSize = 18
	brandConstraint.Parent = brandLabel

	local currencyFrame = Instance.new("Frame")
	currencyFrame.Name = "Currency"
	currencyFrame.Size = UDim2.fromScale(0.2, 0.45)
	currencyFrame.Position = UDim2.fromScale(0.95, 0.5)
	currencyFrame.AnchorPoint = Vector2.new(1, 0.5)
	currencyFrame.BackgroundColor3 = Color3.fromRGB(85, 89, 99)
	currencyFrame.BorderSizePixel = 0
	currencyFrame.Parent = topBar

	local currencyCorner = Instance.new("UICorner")
	currencyCorner.CornerRadius = UDim.new(0.3, 0)
	currencyCorner.Parent = currencyFrame

	local currencyIcon = Instance.new("TextLabel")
	currencyIcon.Name = "Icon"
	currencyIcon.Size = UDim2.fromScale(0.2, 1)
	currencyIcon.BackgroundTransparency = 1
	currencyIcon.Font = Enum.Font.GothamBold
	currencyIcon.Text = "R$"
	currencyIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	currencyIcon.TextScaled = true
	currencyIcon.TextXAlignment = Enum.TextXAlignment.Center
	currencyIcon.Parent = currencyFrame

	local currencyConstraint = Instance.new("UITextSizeConstraint")
	currencyConstraint.MaxTextSize = 20
	currencyConstraint.MinTextSize = 12
	currencyConstraint.Parent = currencyIcon

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.Name = "Balance"
	balanceLabel.Size = UDim2.fromScale(0.75, 1)
	balanceLabel.Position = UDim2.fromScale(0.25, 0)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Font = Enum.Font.GothamMedium
	balanceLabel.Text = "0"
	balanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	balanceLabel.TextScaled = true
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.Parent = currencyFrame

	local balanceConstraint = Instance.new("UITextSizeConstraint")
	balanceConstraint.MaxTextSize = 20
	balanceConstraint.MinTextSize = 12
	balanceConstraint.Parent = balanceLabel

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.fromScale(0.045, 0.45)
	closeButton.Position = UDim2.fromScale(1, 0.5)
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.BackgroundColor3 = Color3.fromRGB(236, 241, 246)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(80, 88, 103)
	closeButton.TextScaled = true
	closeButton.Parent = topBar

	local closeConstraint = Instance.new("UITextSizeConstraint")
	closeConstraint.MaxTextSize = 18
	closeConstraint.MinTextSize = 12
	closeConstraint.Parent = closeButton

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0.2, 0)
	closeCorner.Parent = closeButton

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Color3.fromRGB(198, 203, 215)
	closeStroke.Thickness = 1
	closeStroke.Parent = closeButton

	-- เชื่อมปุ่มปิด
	closeButton.MouseButton1Click:Connect(function()
		ShopUI.closeShop()
	end)

	-- สร้าง Content Container
	local contentContainer = Instance.new("Frame")
	contentContainer.Name = "ContentContainer"
	contentContainer.Size = UDim2.fromScale(0.96, 0.82)
	contentContainer.Position = UDim2.fromScale(0.02, 0.16)
	contentContainer.BackgroundTransparency = 1
	contentContainer.BorderSizePixel = 0
	contentContainer.Parent = shopFrame

	-- สร้าง ScrollingFrame แนวนอน
	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.fromScale(0.9, 1)
	contentFrame.Position = UDim2.fromScale(0.05, 0)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 0
	contentFrame.CanvasSize = UDim2.fromScale(0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.X
	contentFrame.ScrollingDirection = Enum.ScrollingDirection.X
	contentFrame.ScrollBarImageColor3 = Color3.fromRGB(190, 195, 205)
	contentFrame.Parent = contentContainer

	scrollingFrame = contentFrame

	-- ตรวจจับการ scroll ด้วยนิ้วเพื่ออัปเดต currentPage
	contentFrame:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		if #itemCards == 0 then return end

		-- คำนวณว่าอยู่หน้าไหนจาก CanvasPosition
		local scrollPosition = contentFrame.CanvasPosition.X
		local itemWidth = 0

		if itemCards[1] then
			itemWidth = itemCards[1].AbsoluteSize.X
		end

		if itemWidth > 0 then
			local listLayout = contentFrame:FindFirstChildOfClass("UIListLayout")
			local spacing = 0
			if listLayout and listLayout.Padding then
				spacing = listLayout.Padding.Scale * contentFrame.AbsoluteCanvasSize.X
			end

			local itemTotalWidth = itemWidth + spacing
			local estimatedPage = math.floor(scrollPosition / itemTotalWidth) + 1
			local totalPages = math.ceil(#itemCards / itemsPerPage)

			currentPage = math.clamp(estimatedPage, 1, totalPages)
			updateArrowStates()
		end
	end)

	-- สร้าง List Layout แนวนอน
	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Horizontal
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	listLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0.02, 0)
	listLayout.Parent = contentFrame

	-- เพิ่ม Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.01, 0)
	padding.PaddingBottom = UDim.new(0.01, 0)
	padding.PaddingLeft = UDim.new(0.01, 0)
	padding.PaddingRight = UDim.new(0.01, 0)
	padding.Parent = contentFrame

	-- เพิ่ม spacer ท้าย canvas เพื่อให้ item สุดท้ายเลื่อนมาชิดซ้ายได้
	local spacer = Instance.new("Frame")
	spacer.Name = "Spacer"
	spacer.Size = UDim2.fromScale(0.22, 1)
	spacer.BackgroundTransparency = 1
	spacer.LayoutOrder = 9999
	spacer.Parent = contentFrame

	-- สร้างปุ่มลูกศรซ้าย
	leftArrow = Instance.new("TextButton")
	leftArrow.Name = "LeftArrow"
	leftArrow.Size = UDim2.fromScale(0.04, 0.08)
	leftArrow.Position = UDim2.fromScale(0.005, 0.5)
	leftArrow.AnchorPoint = Vector2.new(0, 0.5)
	leftArrow.BackgroundColor3 = Color3.fromRGB(101, 105, 115)
	leftArrow.BackgroundTransparency = 0.3
	leftArrow.BorderSizePixel = 0
	leftArrow.Font = Enum.Font.GothamBold
	leftArrow.Text = "<"
	leftArrow.TextColor3 = Color3.fromRGB(255, 255, 255)
	leftArrow.TextScaled = true
	leftArrow.Parent = contentContainer

	local leftCorner = Instance.new("UICorner")
	leftCorner.CornerRadius = UDim.new(0.3, 0)
	leftCorner.Parent = leftArrow

	local leftConstraint = Instance.new("UITextSizeConstraint")
	leftConstraint.MaxTextSize = 24
	leftConstraint.MinTextSize = 16
	leftConstraint.Parent = leftArrow

	-- สร้างปุ่มลูกศรขวา
	rightArrow = Instance.new("TextButton")
	rightArrow.Name = "RightArrow"
	rightArrow.Size = UDim2.fromScale(0.04, 0.08)
	rightArrow.Position = UDim2.fromScale(0.995, 0.5)
	rightArrow.AnchorPoint = Vector2.new(1, 0.5)
	rightArrow.BackgroundColor3 = Color3.fromRGB(101, 105, 115)
	rightArrow.BackgroundTransparency = 0.3
	rightArrow.BorderSizePixel = 0
	rightArrow.Font = Enum.Font.GothamBold
	rightArrow.Text = ">"
	rightArrow.TextColor3 = Color3.fromRGB(255, 255, 255)
	rightArrow.TextScaled = true
	rightArrow.Parent = contentContainer

	local rightCorner = Instance.new("UICorner")
	rightCorner.CornerRadius = UDim.new(0.3, 0)
	rightCorner.Parent = rightArrow

	local rightConstraint = Instance.new("UITextSizeConstraint")
	rightConstraint.MaxTextSize = 24
	rightConstraint.MinTextSize = 16
	rightConstraint.Parent = rightArrow

	-- เพิ่มระบบ drag ใน ContentContainer
	local isDragging = false
	local dragStartPos = nil
	local dragStartCanvasPos = nil

	contentContainer.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = true
			dragStartPos = input.Position
			dragStartCanvasPos = contentFrame.CanvasPosition
		end
	end)

	contentContainer.InputChanged:Connect(function(input)
		if not isDragging then return end

		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local delta = dragStartPos.X - input.Position.X
			local newCanvasPos = dragStartCanvasPos.X + delta

			-- จำกัดไม่ให้เลื่อนเกินขอบ
			local maxScroll = math.max(0, contentFrame.AbsoluteCanvasSize.X - contentFrame.AbsoluteSize.X)
			newCanvasPos = math.clamp(newCanvasPos, 0, maxScroll)

			contentFrame.CanvasPosition = Vector2.new(newCanvasPos, 0)
		end
	end)

	contentContainer.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
			dragStartPos = nil
			dragStartCanvasPos = nil
		end
	end)

	print("Shop UI created successfully")
	return shopScreenGui
end

-- ฟังก์ชันเลื่อนไปยังหน้า
local function scrollToPage(page)
	if not scrollingFrame or #itemCards == 0 then return end

	local totalPages = math.ceil(#itemCards / itemsPerPage)
	local targetPage = math.clamp(page, 1, totalPages)
	currentPage = targetPage

	-- คำนวณ item แรกของหน้านั้น
	local firstItemIndex = (targetPage - 1) * itemsPerPage + 1
	local targetCard = itemCards[firstItemIndex]

	if targetCard then
		-- คำนวณตำแหน่งให้ item แรกของหน้าแสดงชิดซ้าย
		local cardPositionInCanvas = targetCard.AbsolutePosition.X - scrollingFrame.AbsolutePosition.X + scrollingFrame.CanvasPosition.X

		-- เอา padding ซ้ายออกเพื่อให้ชิดซ้ายพอดี
		local padding = scrollingFrame:FindFirstChildOfClass("UIPadding")
		local leftPadding = 0

		if padding and padding.PaddingLeft then
			leftPadding = padding.PaddingLeft.Scale * scrollingFrame.AbsoluteCanvasSize.X
		end

		local targetPosition = cardPositionInCanvas - leftPadding

		-- จำกัดไม่ให้เลื่อนเกินขอบ
		local maxScroll = math.max(0, scrollingFrame.AbsoluteCanvasSize.X - scrollingFrame.AbsoluteSize.X)
		targetPosition = math.clamp(targetPosition, 0, maxScroll)

		local tweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local tween = TweenService:Create(scrollingFrame, tweenInfo, {
			CanvasPosition = Vector2.new(targetPosition, 0)
		})
		tween:Play()

		print(("[ShopUI] Scrolled to page %d (item %d)"):format(targetPage, firstItemIndex))
	end

	updateArrowStates()
end

-- ฟังก์ชันสร้าง Item Card (สำหรับแต่ละสินค้า)
local function createItemCard(itemData)
	local card = Instance.new("Frame")
	card.Name = "ItemCard"
	card.Size = UDim2.fromScale(0.22, 0.95)
	card.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	card.BorderSizePixel = 0
	card.LayoutOrder = itemData.order or 0

	local cardCorner = Instance.new("UICorner")
	cardCorner.CornerRadius = UDim.new(0, 12)
	cardCorner.Parent = card

	local cardStroke = Instance.new("UIStroke")
	cardStroke.Color = Color3.fromRGB(122, 124, 137)
	cardStroke.Thickness = 2
	cardStroke.Transparency = 0.3
	cardStroke.Parent = card

	local cardPadding = Instance.new("UIPadding")
	cardPadding.PaddingTop = UDim.new(0.04, 0)
	cardPadding.PaddingLeft = UDim.new(0.08, 0)
	cardPadding.PaddingRight = UDim.new(0.08, 0)
	cardPadding.PaddingBottom = UDim.new(0.04, 0)
	cardPadding.Parent = card

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ItemName"
	nameLabel.Size = UDim2.fromScale(1, 0.11)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = formatItemName(itemData.name, itemData.breakName)
	nameLabel.TextColor3 = Color3.fromRGB(58, 66, 82)
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	nameLabel.TextWrapped = true
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MaxTextSize = 20
	nameConstraint.MinTextSize = 12
	nameConstraint.Parent = nameLabel

	local headerDivider = Instance.new("Frame")
	headerDivider.Name = "HeaderDivider"
	headerDivider.Size = UDim2.fromScale(1, 0.003)
	headerDivider.Position = UDim2.fromScale(0, 0.12)
	headerDivider.BackgroundColor3 = Color3.fromRGB(215, 219, 230)
	headerDivider.BorderSizePixel = 0
	headerDivider.Parent = card

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "Preview"
	imageLabel.Size = UDim2.fromScale(1, 0.3)
	imageLabel.Position = UDim2.fromScale(0, 0.15)
	imageLabel.BackgroundColor3 = itemData.imageBackgroundColor or Color3.fromRGB(240, 242, 247)
	imageLabel.BorderSizePixel = 0
	imageLabel.ScaleType = Enum.ScaleType.Fit
	imageLabel.Parent = card

	local imageCorner = Instance.new("UICorner")
	imageCorner.CornerRadius = UDim.new(0, 10)
	imageCorner.Parent = imageLabel

	if itemData.image and itemData.image ~= "" then
		imageLabel.Image = itemData.image
		imageLabel.ImageTransparency = 0
	else
		imageLabel.Image = ""
		imageLabel.ImageTransparency = 1
	end

	local detailsLabel = Instance.new("TextLabel")
	detailsLabel.Name = "Details"
	detailsLabel.Size = UDim2.fromScale(1, 0.14)
	detailsLabel.Position = UDim2.fromScale(0, 0.49)
	detailsLabel.BackgroundTransparency = 1
	detailsLabel.Font = Enum.Font.GothamMedium
	detailsLabel.TextColor3 = Color3.fromRGB(94, 94, 94)
	detailsLabel.TextScaled = true
	detailsLabel.TextWrapped = true
	detailsLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailsLabel.TextYAlignment = Enum.TextYAlignment.Top
	detailsLabel.Parent = card

	local detailsConstraint = Instance.new("UITextSizeConstraint")
	detailsConstraint.MaxTextSize = 14
	detailsConstraint.MinTextSize = 8
	detailsConstraint.Parent = detailsLabel

	if itemData.features and #itemData.features > 0 then
		local lines = {}
		for _, detail in ipairs(itemData.features) do
			table.insert(lines, "• " .. detail)
		end
		detailsLabel.Text = table.concat(lines, "\n")
	else
		detailsLabel.Text = itemData.description or ""
	end

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Name = "Price"
	priceLabel.Size = UDim2.fromScale(1, 0.06)
	priceLabel.Position = UDim2.fromScale(0, 0.75)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.Text = itemData.priceDisplay or ("R$ " .. tostring(itemData.price or 0))
	priceLabel.TextColor3 = Color3.fromRGB(58, 66, 82)
	priceLabel.TextScaled = true
	priceLabel.TextXAlignment = Enum.TextXAlignment.Center
	priceLabel.Parent = card

	local priceConstraint = Instance.new("UITextSizeConstraint")
	priceConstraint.MaxTextSize = 18
	priceConstraint.MinTextSize = 12
	priceConstraint.Parent = priceLabel

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "BuyButton"
	buyButton.Size = UDim2.fromScale(1, 0.095)
	buyButton.Position = UDim2.fromScale(0, 0.96)
	buyButton.AnchorPoint = Vector2.new(0, 1)
	buyButton.BackgroundColor3 = Color3.fromRGB(67, 181, 129)
	buyButton.BorderSizePixel = 0
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Text = "Buy"
	buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyButton.TextScaled = true
	buyButton.Parent = card

	local buyConstraint = Instance.new("UITextSizeConstraint")
	buyConstraint.MaxTextSize = 18
	buyConstraint.MinTextSize = 12
	buyConstraint.Parent = buyButton

	local buyCorner = Instance.new("UICorner")
	buyCorner.CornerRadius = UDim.new(0.2, 0)
	buyCorner.Parent = buyButton

	buyButton.MouseButton1Click:Connect(function()
		local priceInfo = itemData.priceDisplay or itemData.price or "N/A"
		print(("Attempting to buy %s for %s"):format(itemData.name or "Item", priceInfo))
		-- TODO: เชื่อมกับระบบซื้อของ
	end)

	return card
end

-- ฟังก์ชันเปิด Shop
function ShopUI.openShop()
	if isAnimating or isShopOpen then return end

	if not shopScreenGui then
		createShopUI()
	end

	isAnimating = true
	shopScreenGui.Enabled = true

	-- ตั้งค่าเริ่มต้นสำหรับ animation
	local background = shopScreenGui:FindFirstChild("Background")
	local frame = shopScreenGui:FindFirstChild("ShopFrame")

	if background then
		background.BackgroundTransparency = 1
	end

	if frame then
		frame.Size = UDim2.new(0, 0, 0, 0)
		frame.Position = UDim2.new(0.5, 0, 0.5, 0)

		-- Tween สำหรับ background
		local bgTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local bgTween = TweenService:Create(background, bgTweenInfo, {
			BackgroundTransparency = 0.5
		})

		-- Tween สำหรับ frame (scale up)
		local frameTweenInfo = TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		local frameTween = TweenService:Create(frame, frameTweenInfo, {
			Size = UDim2.new(0.7, 0, 0.85, 0)
		})

		bgTween:Play()
		frameTween:Play()

		frameTween.Completed:Connect(function()
			isAnimating = false
			isShopOpen = true
		end)
	else
		isAnimating = false
		isShopOpen = true
	end

	print("Shop opened")
end

-- ฟังก์ชันปิด Shop
function ShopUI.closeShop()
	if isAnimating or not isShopOpen then return end

	if not shopScreenGui then return end

	isAnimating = true

	-- Deselect TopbarPlus icon
	if shopIcon then
		shopIcon:deselect()
	end

	local background = shopScreenGui:FindFirstChild("Background")
	local frame = shopScreenGui:FindFirstChild("ShopFrame")

	if background and frame then
		-- Tween สำหรับ background
		local bgTweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		local bgTween = TweenService:Create(background, bgTweenInfo, {
			BackgroundTransparency = 1
		})

		-- Tween สำหรับ frame (scale down)
		local frameTweenInfo = TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.In)
		local frameTween = TweenService:Create(frame, frameTweenInfo, {
			Size = UDim2.new(0, 0, 0, 0)
		})

		bgTween:Play()
		frameTween:Play()

		frameTween.Completed:Connect(function()
			shopScreenGui.Enabled = false
			isAnimating = false
			isShopOpen = false
		end)
	else
		shopScreenGui.Enabled = false
		isAnimating = false
		isShopOpen = false
	end

	print("Shop closed")
end

-- ฟังก์ชัน Toggle Shop
function ShopUI.toggleShop()
	if isShopOpen then
		ShopUI.closeShop()
	else
		ShopUI.openShop()
	end
end

-- ฟังก์ชันเพิ่มสินค้าใน Shop
function ShopUI.addItem(itemData)
	if not shopScreenGui then
		createShopUI()
	end

	local shopFrameInstance = shopScreenGui:FindFirstChild("ShopFrame")
	if not shopFrameInstance then return end

	local contentContainer = shopFrameInstance:FindFirstChild("ContentContainer")
	if not contentContainer then return end

	local contentFrame = contentContainer:FindFirstChild("Content")
	if contentFrame then
		local itemCard = createItemCard(itemData)
		itemCard.Parent = contentFrame
		table.insert(itemCards, itemCard)
		updateArrowStates()
	end
end

-- ฟังก์ชัน Initialize Shop
function ShopUI.init()
	-- สร้าง Shop Icon ด้วย TopbarPlus (events ถูก bind แล้วใน createShopIcon)
	ensureShopIcon()

	-- สร้าง UI (แต่ยังไม่แสดง)
	createShopUI()

	-- เชื่อมต่อปุ่มลูกศร
	if leftArrow then
		leftArrow.MouseButton1Click:Connect(function()
			scrollToPage(currentPage - 1)
		end)
	end

	if rightArrow then
		rightArrow.MouseButton1Click:Connect(function()
			scrollToPage(currentPage + 1)
		end)
	end

	-- เพิ่มสินค้าตัวอย่าง
	ShopUI.addItem({
		order = 1,
		name = "Starter Pack",
		features = {"Special hard hat"},
		priceDisplay = "R$ 99",
		image = "rbxassetid://83670893385280",
		imageBackgroundColor = Color3.fromRGB(245, 223, 140)
	})

	ShopUI.addItem({
		order = 2,
		name = "Rescue Tools Pack",
		features = {
			"Thermometer Camera",
			"Zoom 3x-5x Camera"
		},
		priceDisplay = "R$ 299",
		image = "rbxassetid://121210617940153",
		imageBackgroundColor = Color3.fromRGB(204, 208, 217)
	})

	ShopUI.addItem({
		order = 3,
		name = "Robot Upgrade Pack",
		features = {"Solar Cell"},
		priceDisplay = "R$ 799",
		image = "rbxassetid://92408622041483",
		imageBackgroundColor = Color3.fromRGB(201, 206, 210)
	})

	ShopUI.addItem({
		order = 4,
		name = "VIP Hero Pack",
		features = {"Attack Everyone"},
		priceDisplay = "R$ 1,499 - 1,999",
		image = "rbxassetid://74329715725631",
		imageBackgroundColor = Color3.fromRGB(218, 220, 230)
	})

	ShopUI.addItem({
		order = 5,
		name = "Kit Heal",
		features = {"Heal yourself", "Quick recovery"},
		priceDisplay = "R$ 199",
		image = "rbxassetid://137702011953812",
		imageBackgroundColor = Color3.fromRGB(255, 182, 193)
	})

	print("ShopUI initialized")
end

function ShopUI.setButtonVisible(isVisible: boolean)
	local icon = ensureShopIcon()
	if icon then
		-- TopbarPlus icons ใช้ :setEnabled() แทน Visible
		icon:setEnabled(isVisible)
	end

	if not isVisible then
		if shopScreenGui then
			shopScreenGui.Enabled = false
		end
		isShopOpen = false
		isAnimating = false
	end
end

return ShopUI
