-- ShopUI Module
-- จัดการ UI ของร้านค้า

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ShopUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ตัวแปร UI
local shopScreenGui = nil
local shopFrame = nil
local shopButton = nil
local isShopOpen = false
local isAnimating = false

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
local function createShopButton()
	if shopButton then return shopButton end

	-- สร้าง ScreenGui สำหรับปุ่ม
	local buttonGui = Instance.new("ScreenGui")
	buttonGui.Name = "ShopButtonGui"
	buttonGui.ResetOnSpawn = false
	buttonGui.DisplayOrder = 100
	buttonGui.IgnoreGuiInset = true
	buttonGui.Parent = playerGui

	-- สร้างปุ่ม Shop
	shopButton = Instance.new("TextButton")
	shopButton.Name = "ShopButton"
	shopButton.Size = UDim2.new(0.08, 0, 0.05, 0)
	shopButton.Position = UDim2.new(0.1, 0, 0.5, 0) -- มุมขวาบน
	shopButton.AnchorPoint = Vector2.new(1, 0)
	shopButton.BackgroundColor3 = Color3.fromRGB(52, 168, 83) -- สีเขียว
	shopButton.BorderSizePixel = 0
	shopButton.Font = Enum.Font.GothamBold
	shopButton.Text = "🛒 SHOP"
	shopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopButton.TextSize = 20
	shopButton.TextScaled = true
	shopButton.Parent = buttonGui

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.2, 0)
	corner.Parent = shopButton

	return shopButton
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
	shopLabel.Size = UDim2.new(0.15, 0, 1, 0)
	shopLabel.BackgroundTransparency = 1
	shopLabel.Font = Enum.Font.GothamBold
	shopLabel.Text = "Shop"
	shopLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	shopLabel.TextSize = 28
	shopLabel.TextScaled = true
	shopLabel.TextXAlignment = Enum.TextXAlignment.Left
	shopLabel.Parent = topBar

	local brandLabel = Instance.new("TextLabel")
	brandLabel.Name = "Brand"
	brandLabel.Size = UDim2.new(0.3, 0, 1, 0)
	brandLabel.Position = UDim2.new(0.5, 0, 0, 0)
	brandLabel.AnchorPoint = Vector2.new(0.5, 0)
	brandLabel.BackgroundTransparency = 1
	brandLabel.Font = Enum.Font.GothamBold
	brandLabel.Text = "Rescue Blox"
	brandLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	brandLabel.TextSize = 30
	brandLabel.TextScaled = true
	brandLabel.TextXAlignment = Enum.TextXAlignment.Center
	brandLabel.Parent = topBar

	local currencyFrame = Instance.new("Frame")
	currencyFrame.Name = "Currency"
	currencyFrame.Size = UDim2.new(0.2, 0, 0.45, 0)
	currencyFrame.Position = UDim2.new(0.95, 0, 0.5, 0)
	currencyFrame.AnchorPoint = Vector2.new(1, 0.5)
	currencyFrame.BackgroundColor3 = Color3.fromRGB(85, 89, 99)
	currencyFrame.BorderSizePixel = 0
	currencyFrame.Parent = topBar

	local currencyCorner = Instance.new("UICorner")
	currencyCorner.CornerRadius = UDim.new(0.3, 0)
	currencyCorner.Parent = currencyFrame

	local currencyIcon = Instance.new("TextLabel")
	currencyIcon.Name = "Icon"
	currencyIcon.Size = UDim2.new(0.2, 0, 1, 0)
	currencyIcon.BackgroundTransparency = 1
	currencyIcon.Font = Enum.Font.GothamBold
	currencyIcon.Text = "R$"
	currencyIcon.TextColor3 = Color3.fromRGB(255, 255, 255)
	currencyIcon.TextSize = 20
	currencyIcon.TextScaled = true
	currencyIcon.TextXAlignment = Enum.TextXAlignment.Center
	currencyIcon.Parent = currencyFrame

	local balanceLabel = Instance.new("TextLabel")
	balanceLabel.Name = "Balance"
	balanceLabel.Size = UDim2.new(0.75, 0, 1, 0)
	balanceLabel.Position = UDim2.new(0.25, 0, 0, 0)
	balanceLabel.BackgroundTransparency = 1
	balanceLabel.Font = Enum.Font.GothamMedium
	balanceLabel.Text = "0"
	balanceLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	balanceLabel.TextSize = 20
	balanceLabel.TextScaled = true
	balanceLabel.TextXAlignment = Enum.TextXAlignment.Left
	balanceLabel.Parent = currencyFrame

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.Size = UDim2.new(0.045, 0, 0.45, 0)
	closeButton.Position = UDim2.new(1, 0, 0.5, 0)
	closeButton.AnchorPoint = Vector2.new(1, 0.5)
	closeButton.BackgroundColor3 = Color3.fromRGB(236, 241, 246)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.Text = "X"
	closeButton.TextColor3 = Color3.fromRGB(80, 88, 103)
	closeButton.TextSize = 18
	closeButton.TextScaled = true
	closeButton.Parent = topBar

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

	-- สร้าง Content Area (สำหรับใส่ items)
	local contentFrame = Instance.new("ScrollingFrame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(0.96, 0, 0.82, 0)
	contentFrame.Position = UDim2.new(0.02, 0, 0.16, 0)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.ScrollBarThickness = 4
	contentFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	contentFrame.AutomaticCanvasSize = Enum.AutomaticSize.XY
	contentFrame.ScrollBarImageColor3 = Color3.fromRGB(190, 195, 205)
	contentFrame.Parent = shopFrame

	-- สร้าง Grid Layout
	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.23, 0, 0.9, 0)
	gridLayout.CellPadding = UDim2.new(0.02, 0, 0.02, 0)
	gridLayout.FillDirection = Enum.FillDirection.Horizontal
	gridLayout.FillDirectionMaxCells = 4
	gridLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	gridLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = contentFrame

	-- เพิ่ม Padding
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.01, 0)
	padding.PaddingBottom = UDim.new(0.01, 0)
	padding.PaddingLeft = UDim.new(0.01, 0)
	padding.PaddingRight = UDim.new(0.01, 0)
	padding.Parent = contentFrame

	print("Shop UI created successfully")
	return shopScreenGui
end

-- ฟังก์ชันสร้าง Item Card (สำหรับแต่ละสินค้า)
local function createItemCard(itemData)
	local card = Instance.new("Frame")
	card.Name = "ItemCard"
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
	nameLabel.Size = UDim2.new(1, 0, 0.11, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Text = formatItemName(itemData.name, itemData.breakName)
	nameLabel.TextColor3 = Color3.fromRGB(58, 66, 82)
	nameLabel.TextSize = 20
	nameLabel.TextScaled = true
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextYAlignment = Enum.TextYAlignment.Top
	nameLabel.TextWrapped = true
	nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
	nameLabel.Parent = card

	local headerDivider = Instance.new("Frame")
	headerDivider.Name = "HeaderDivider"
	headerDivider.Size = UDim2.new(1, 0, 0.003, 0)
	headerDivider.Position = UDim2.new(0, 0, 0.12, 0)
	headerDivider.BackgroundColor3 = Color3.fromRGB(215, 219, 230)
	headerDivider.BorderSizePixel = 0
	headerDivider.Parent = card

	local imageLabel = Instance.new("ImageLabel")
	imageLabel.Name = "Preview"
	imageLabel.Size = UDim2.new(1, 0, 0.3, 0)
	imageLabel.Position = UDim2.new(0, 0, 0.15, 0)
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
	detailsLabel.Size = UDim2.new(1, 0, 0.14, 0)
	detailsLabel.Position = UDim2.new(0, 0, 0.49, 0)
	detailsLabel.BackgroundTransparency = 1
	detailsLabel.Font = Enum.Font.GothamMedium
	detailsLabel.TextColor3 = Color3.fromRGB(94, 94, 94)
	detailsLabel.TextSize = 20
	detailsLabel.TextWrapped = true
	detailsLabel.TextXAlignment = Enum.TextXAlignment.Left
	detailsLabel.TextYAlignment = Enum.TextYAlignment.Top
	detailsLabel.Parent = card

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
	priceLabel.Size = UDim2.new(1, 0, 0.06, 0)
	priceLabel.Position = UDim2.new(0, 0, 0.75, 0)
	priceLabel.BackgroundTransparency = 1
	priceLabel.Font = Enum.Font.GothamBold
	priceLabel.Text = itemData.priceDisplay or ("R$ " .. tostring(itemData.price or 0))
	priceLabel.TextColor3 = Color3.fromRGB(58, 66, 82)
	priceLabel.TextSize = 18
	priceLabel.TextScaled = true
	priceLabel.TextXAlignment = Enum.TextXAlignment.Center
	priceLabel.Parent = card

	local buyButton = Instance.new("TextButton")
	buyButton.Name = "BuyButton"
	buyButton.Size = UDim2.new(1, 0, 0.095, 0)
	buyButton.Position = UDim2.new(0, 0, 0.96, 0)
	buyButton.AnchorPoint = Vector2.new(0, 1)
	buyButton.BackgroundColor3 = Color3.fromRGB(67, 181, 129)
	buyButton.BorderSizePixel = 0
	buyButton.Font = Enum.Font.GothamBold
	buyButton.Text = "Buy"
	buyButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	buyButton.TextSize = 18
	buyButton.TextScaled = true
	buyButton.Parent = card

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

	local contentFrame = shopScreenGui:FindFirstChild("ShopFrame"):FindFirstChild("Content")
	if contentFrame then
		local itemCard = createItemCard(itemData)
		itemCard.Parent = contentFrame
	end
end

-- ฟังก์ชัน Initialize Shop
function ShopUI.init()
	-- สร้างปุ่ม Shop
	local button = createShopButton()

	-- เชื่อมปุ่มกับการเปิด Shop
	button.MouseButton1Click:Connect(function()
		ShopUI.toggleShop()
	end)

	-- สร้าง UI (แต่ยังไม่แสดง)
	createShopUI()

	-- เพิ่มสินค้าตัวอย่าง
	ShopUI.addItem({
		order = 1,
		name = "Starter Pack",
		features = {"Special hard hat"},
		priceDisplay = "R$ 99",
		image = "",
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
		image = "",
		imageBackgroundColor = Color3.fromRGB(204, 208, 217)
	})

	ShopUI.addItem({
		order = 3,
		name = "Robot Upgrade Pack",
		features = {"Solar Cell"},
		priceDisplay = "R$ 799",
		image = "",
		imageBackgroundColor = Color3.fromRGB(201, 206, 210)
	})

	ShopUI.addItem({
		order = 4,
		name = "VIP Hero Pack",
		features = {"Attack Everyone"},
		priceDisplay = "R$ 1,499 - 1,999",
		image = "",
		imageBackgroundColor = Color3.fromRGB(218, 220, 230)
	})

	print("ShopUI initialized")
end

return ShopUI
