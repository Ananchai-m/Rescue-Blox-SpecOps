-- CustomizeUI Module
-- จัดการ UI สำหรับปรับแต่งตัวละคร/หุ่นยนต์

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")

-- Import modules
local TopbarPlus = require(ReplicatedStorage.Packages.TopbarPlus)
local EquipmentManager = require(ReplicatedStorage.Modules.EquipmentManager)
local CustomizeService = require(ReplicatedStorage.Modules.CustomizeService)

local CustomizeUI = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local camera = Workspace.CurrentCamera

-- ตัวแปร UI
local customizeScreenGui = nil
local customizeIcon = nil
local isCustomizeOpen = false
local isAnimating = false

-- ตัวแปรสำหรับ Preview
local previewBot = nil
local originalCameraCFrame = nil
local originalCameraType = nil

local selectedPreviewPart: BasePart? = nil
local previewSelectionBox: SelectionBox? = nil
local colorPickerFrame: Frame? = nil
local colorPickerButtons: {TextButton} = {}
local activeColorButton: TextButton? = nil
local colorPickerPartLabel: TextLabel? = nil
local previewOriginalColors: {[BasePart]: Color3} = {}
local previewDescendantConn: RBXScriptConnection? = nil
local currentColorScheme: {[string]: {r: number, g: number, b: number}}? = nil

local function getItemColorFromScheme(itemId: string, scheme: {[string]: {r: number, g: number, b: number}}?): {r: number, g: number, b: number}?
	if not scheme then
		return nil
	end
	for path, color in pairs(scheme) do
		local firstSegment = path:match("^[^/]+")
		if firstSegment == itemId or path:find(itemId, 1, true) then
			return color
		end
	end
	return nil
end

local function isSelectablePart(part: BasePart): boolean
	if part.Name == "VehicleSeat" or part:IsA("Seat") or part:IsA("VehicleSeat") then
		return false
	end

	return part:IsA("BasePart") or part:IsA("MeshPart")
end

local function buildRobloxColorPalette(): {Color3}
	local palette = {}
	local seen: {[string]: boolean} = {}
	local maxIndex = 127
	for index = 0, maxIndex do
		local ok, brick = pcall(BrickColor.palette, index)
		if ok and brick then
			local color = brick.Color
			local key = string.format("%.3f_%.3f_%.3f", color.R, color.G, color.B)
			if not seen[key] then
				seen[key] = true
				palette[#palette + 1] = color
			end
		end
	end

	-- fallback palette if BrickColor.palette not available
	if #palette == 0 then
		palette = {
			Color3.fromRGB(255, 255, 255),
			Color3.fromRGB(226, 155, 64),
			Color3.fromRGB(196, 40, 28),
			Color3.fromRGB(13, 105, 172),
			Color3.fromRGB(27, 197, 141),
			Color3.fromRGB(105, 64, 157),
			Color3.fromRGB(99, 95, 98),
			Color3.fromRGB(46, 52, 64),
		}
	end

	return palette
end

local COLOR_PALETTE: {Color3} = buildRobloxColorPalette()

-- ตัวแปรสำหรับ Camera Rotation
local isDragging = false
local lastMousePosition = nil
local currentRotationAngle = 0
local baseCameraPosition = nil
local focusPoint = nil
local cameraDistance = 15
local originalFOV = nil
local inputBeganConnection = nil
local inputEndedConnection = nil
local inputChangedConnection = nil

-- ตัวแปรสำหรับพับแขน
local armsExtended = true -- true = พับ (0), false = เก็บ (180)

-- ค่าคงที่และตัวแปรสำหรับ Inventory UI
local SLOT_COLUMNS = 6
local SLOT_ROWS = 7
local SLOT_CELL_SIZE = Vector2.new(70, 70)
local SLOT_CELL_PADDING = Vector2.new(10, 10)

type SlotData = {
	frame: Frame,
	row: number,
	column: number,
	defaultColor: Color3,
	defaultTransparency: number,
	stroke: UIStroke?,
	defaultStrokeColor: Color3?,
}

local inventorySlots: { SlotData } = {}
local slotMap: { [number]: { [number]: SlotData? } } = {}
local slotOccupancy: { [number]: { [number]: GuiObject? } } = {}
local slotsOverlayFrame: Frame? = nil
local placedItems: { GuiObject } = {}

type LoadoutConfig = {
	id: string,
	displayName: string,
	size: Vector2,
}

local loadoutConfigs: { LoadoutConfig } = {
	{ id = "Camera", displayName = "Camera", size = Vector2.new(1, 1) },
	{ id = "DrillArm", displayName = "Drill Arm", size = Vector2.new(2, 1) },
	{ id = "SolarCell", displayName = "SolarCell", size = Vector2.new(2, 1) },
	{ id = "ThermometerCamera", displayName = "Thermometer\nCamera", size = Vector2.new(1, 1) },
	{ id = "Zoom3x5xCamera", displayName = "Zoom3x-5x\nCamera", size = Vector2.new(1, 1) },
}

type DragContext = {
	active: boolean,
	config: LoadoutConfig?,
	ghost: Frame?,
	connections: { RBXScriptConnection }?,
	currentPlacement: any,
	highlight: { SlotData }?,
	originalParent: GuiObject?,
	placeholder: Frame?,
	originalLayoutOrder: number?,
	isFromSlot: boolean?,
	occupiedCells: { SlotData }?,
	targetLoadoutSlot: Frame?,
}

local dragContext: DragContext = {
	active = false,
	config = nil,
	ghost = nil,
	connections = nil,
	currentPlacement = nil,
	highlight = nil,
	originalParent = nil,
	placeholder = nil,
	originalLayoutOrder = nil,
	isFromSlot = false,
	occupiedCells = nil,
	targetLoadoutSlot = nil,
}

local loadoutBarFrame: Frame? = nil

local createLoadoutSlot: ((LoadoutConfig, number) -> Frame)?
local rebuildLoadoutItems: (() -> ())?
local beginSlotItemDrag: ((Frame) -> ())?
local setGuiTreeZIndex: ((GuiObject, number) -> ())? = nil
local updateSlotLabels: (() -> ())? = nil
local updateColorPickerForPart: ((BasePart) -> ())?

local function ensureSelectionBox()
	if previewSelectionBox then
		return previewSelectionBox
	end

	previewSelectionBox = Instance.new("SelectionBox")
	previewSelectionBox.LineThickness = 0.03
	previewSelectionBox.SurfaceTransparency = 0.7
	previewSelectionBox.Color3 = Color3.fromRGB(255, 255, 255)
	previewSelectionBox.SurfaceColor3 = Color3.fromRGB(255, 255, 255)
	previewSelectionBox.Visible = true
	previewSelectionBox.Name = "CustomizePreviewSelection"

	return previewSelectionBox
end

local function clearActiveColorButton()
	if activeColorButton then
		local stroke = activeColorButton:FindFirstChild("SelectionStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Enabled = false
		end
		activeColorButton = nil
	end
end

local function clearPreviewSelection()
	selectedPreviewPart = nil
	if previewSelectionBox then
		previewSelectionBox.Adornee = nil
		previewSelectionBox.Parent = nil
	end
	clearActiveColorButton()
	if colorPickerFrame then
		colorPickerFrame.Visible = false
	end
	if colorPickerPartLabel then
		colorPickerPartLabel.Text = ""
	end
end

local function setActiveColorButton(button: TextButton?)
	if button == activeColorButton then
		return
	end

	clearActiveColorButton()

	if button then
		local stroke = button:FindFirstChild("SelectionStroke")
		if stroke and stroke:IsA("UIStroke") then
			stroke.Enabled = true
		end
		activeColorButton = button
	end
end

local function resetPreviewColors()
	for part, originalColor in pairs(previewOriginalColors) do
		if part and part.Parent then
			part.Color = originalColor
		end
	end

	if selectedPreviewPart and selectedPreviewPart.Parent then
		if updateColorPickerForPart then
			updateColorPickerForPart(selectedPreviewPart)
		end
	else
		clearPreviewSelection()
	end
end

local function placeColorPickerAtMouse()
	if not colorPickerFrame then
		return
	end

	local mousePosition = UserInputService:GetMouseLocation()
	local currentCamera = Workspace.CurrentCamera or camera
	local viewportSize = currentCamera and currentCamera.ViewportSize or Vector2.new(1920, 1080)
	local frameSize = colorPickerFrame.AbsoluteSize
	local margin = Vector2.new(16, 16)

	local targetX = math.min(mousePosition.X - margin.X, viewportSize.X - margin.X)
	local targetY = math.min(mousePosition.Y - margin.Y, viewportSize.Y - margin.Y)

	if targetX - frameSize.X < margin.X then
		targetX = frameSize.X + margin.X
	end

	if targetY - frameSize.Y < margin.Y then
		targetY = frameSize.Y + margin.Y
	end

	colorPickerFrame.Position = UDim2.fromOffset(targetX, targetY)
end

local function ensureColorPicker(parent: GuiObject)
	if colorPickerFrame then
		colorPickerFrame.Parent = parent
		return
	end

	colorPickerFrame = Instance.new("Frame")
	colorPickerFrame.Name = "ColorPicker"
	colorPickerFrame.Size = UDim2.fromScale(0.2, 0.4)
	colorPickerFrame.Position = UDim2.fromScale(0.03, 0.95)
	colorPickerFrame.BackgroundColor3 = Color3.fromRGB(35, 39, 52)
	colorPickerFrame.BackgroundTransparency = 0.1
	colorPickerFrame.BorderSizePixel = 0
	colorPickerFrame.Visible = false
	colorPickerFrame.Parent = parent
	colorPickerFrame.ZIndex = 20
	colorPickerFrame.AnchorPoint = Vector2.new(0, 1)

	local colorPickerCorner = Instance.new("UICorner")
	colorPickerCorner.CornerRadius = UDim.new(0.04, 0)
	colorPickerCorner.Parent = colorPickerFrame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0.04, 0)
	padding.PaddingBottom = UDim.new(0.04, 0)
	padding.PaddingLeft = UDim.new(0.05, 0)
	padding.PaddingRight = UDim.new(0.05, 0)
	padding.Parent = colorPickerFrame

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.fromScale(1, 0.07)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.Text = "Base Color"
	title.TextColor3 = Color3.fromRGB(235, 237, 245)
	title.TextScaled = true
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.ZIndex = colorPickerFrame.ZIndex + 1
	title.Parent = colorPickerFrame

	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MaxTextSize = 20
	titleConstraint.MinTextSize = 12
	titleConstraint.Parent = title

	local partLabel = Instance.new("TextLabel")
	partLabel.Name = "PartName"
	partLabel.Size = UDim2.fromScale(1, 0.05)
	partLabel.Position = UDim2.fromScale(0, 0.08)
	partLabel.BackgroundTransparency = 1
	partLabel.Font = Enum.Font.Gotham
	partLabel.Text = ""
	partLabel.TextColor3 = Color3.fromRGB(180, 186, 199)
	partLabel.TextScaled = true
	partLabel.TextXAlignment = Enum.TextXAlignment.Left
	partLabel.ZIndex = colorPickerFrame.ZIndex + 1
	partLabel.Parent = colorPickerFrame
	colorPickerPartLabel = partLabel

	local partConstraint = Instance.new("UITextSizeConstraint")
	partConstraint.MaxTextSize = 14
	partConstraint.MinTextSize = 10
	partConstraint.Parent = partLabel

	local paletteContainer = Instance.new("ScrollingFrame")
	paletteContainer.Name = "Palette"
	paletteContainer.Size = UDim2.fromScale(1, 0.66)
	paletteContainer.Position = UDim2.fromScale(0, 0.17)
	paletteContainer.BackgroundTransparency = 1
	paletteContainer.ZIndex = colorPickerFrame.ZIndex + 1
	paletteContainer.Parent = colorPickerFrame
	paletteContainer.ClipsDescendants = true
	paletteContainer.CanvasSize = UDim2.fromScale(0, 0)
	paletteContainer.AutomaticCanvasSize = Enum.AutomaticSize.Y
	paletteContainer.ScrollBarThickness = 6
	paletteContainer.ScrollingDirection = Enum.ScrollingDirection.Y
	paletteContainer.ScrollBarImageTransparency = 0.3

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromScale(0.16, 0.13)
	grid.CellPadding = UDim2.fromScale(0.027, 0.027)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.VerticalAlignment = Enum.VerticalAlignment.Top
	grid.FillDirection = Enum.FillDirection.Horizontal
	grid.FillDirectionMaxCells = 5
	grid.Parent = paletteContainer

	table.clear(colorPickerButtons)

	for index, color in ipairs(COLOR_PALETTE) do
		local button = Instance.new("TextButton")
		button.Name = "Color" .. index
		button.Size = UDim2.new(0, 48, 0, 48)
		button.BackgroundColor3 = color
		button.BorderSizePixel = 0
		button.AutoButtonColor = false
		button.Text = ""
		button.ZIndex = paletteContainer.ZIndex + 1
		button.Parent = paletteContainer

		local stroke = Instance.new("UIStroke")
		stroke.Name = "SelectionStroke"
		stroke.Color = Color3.fromRGB(255, 255, 255)
		stroke.Thickness = 2
		stroke.Transparency = 0
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Enabled = false
		stroke.Parent = button

		button.MouseButton1Click:Connect(function()
			if not selectedPreviewPart then
				return
			end

			selectedPreviewPart.Color = color
			setActiveColorButton(button)
		end)

		colorPickerButtons[#colorPickerButtons + 1] = button
	end

	local resetButton = Instance.new("TextButton")
	resetButton.Name = "ResetButton"
	resetButton.Size = UDim2.fromScale(1, 0.11)
	resetButton.Position = UDim2.fromScale(0, 0.88)
	resetButton.BackgroundColor3 = Color3.fromRGB(60, 64, 82)
	resetButton.BackgroundTransparency = 0.15
	resetButton.BorderSizePixel = 0
	resetButton.Font = Enum.Font.GothamMedium
	resetButton.Text = "Reset Colors"
	resetButton.TextColor3 = Color3.fromRGB(235, 237, 245)
	resetButton.TextScaled = true
	resetButton.ZIndex = colorPickerFrame.ZIndex + 1
	resetButton.Parent = colorPickerFrame

	local resetConstraint = Instance.new("UITextSizeConstraint")
	resetConstraint.MaxTextSize = 16
	resetConstraint.MinTextSize = 10
	resetConstraint.Parent = resetButton

	resetButton.MouseButton1Click:Connect(function()
		resetPreviewColors()
	end)
end

local function getRelativePath(part: Instance, root: Instance): string?
	local segments = {}
	local current: Instance? = part
	while current and current ~= root do
		table.insert(segments, 1, current.Name)
		current = current.Parent
	end
	if current ~= root then
		return nil
	end
	return table.concat(segments, "/")
end

local function findPartByPath(root: Instance?, path: string): BasePart?
	if not root or not path or path == "" then
		return nil
	end

	local current: Instance? = root
	for _, segment in ipairs(string.split(path, "/")) do
		if not current or not current:IsA("Instance") then
			return nil
		end
		current = current:FindFirstChild(segment)
		if not current then
			return nil
		end
	end

	if current and current:IsA("BasePart") then
		return current
	end

	return nil
end

local function findPartByPathOrName(root: Instance?, path: string): BasePart?
	local part = findPartByPath(root, path)
	if part then
		return part
	end
	local partName = path:match("([^/]+)$")
	if not partName or not root then
		return nil
	end
	local descendant = root:FindFirstChild(partName, true)
	if descendant and descendant:IsA("BasePart") then
		return descendant
	end
	return nil
end

local function collectColorScheme(model: Model?): {[string]: {r: number, g: number, b: number}}
	local scheme = {}
	if not model then
		return scheme
	end

	local function addPart(part: BasePart)
		if not isSelectablePart(part) then
			return
		end
		local path = getRelativePath(part, model)
		if not path then
			return
		end
		scheme[path] = {
			r = part.Color.R,
			g = part.Color.G,
			b = part.Color.B,
		}
	end

	if model:IsA("BasePart") then
		addPart(model)
	end

	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			addPart(descendant)
		end
	end

	return scheme
end

local function toColor3(colorData: any): Color3?
	if typeof(colorData) == "Color3" then
		return colorData
	elseif typeof(colorData) == "string" then
		if colorData:sub(1, 1) == "#" and (#colorData == 7 or #colorData == 9) then
			local hex = colorData:sub(2)
			local value = tonumber(hex, 16)
			if value then
				local r = math.floor(value / 0x10000) % 0x100
				local g = math.floor(value / 0x100) % 0x100
				local b = value % 0x100
				r = r / 255
				g = g / 255
				b = b / 255
				return Color3.new(r, g, b)
			end
		end
	elseif typeof(colorData) == "table" then
		local r = colorData.r or colorData.R or colorData[1]
		local g = colorData.g or colorData.G or colorData[2]
		local b = colorData.b or colorData.B or colorData[3]
		if typeof(r) == "number" and typeof(g) == "number" and typeof(b) == "number" then
			return Color3.new(r, g, b)
		end
	end

	return nil
end

local function applyColorSchemeToModel(model: Model?, colorScheme: any)
	if not model or not colorScheme then
		return
	end

	if typeof(colorScheme) ~= "table" then
		return
	end

	if colorScheme[1] and typeof(colorScheme[1]) == "table" and colorScheme[1].path then
		for _, entry in ipairs(colorScheme) do
			local path = entry.path
			local color = toColor3(entry.color)
			if path and color then
				local target = findPartByPathOrName(model, path)
				if target and isSelectablePart(target) then
					target.Color = color
				end
			end
		end
	else
		for path, colorData in pairs(colorScheme) do
			if typeof(path) == "string" then
				local color = toColor3(colorData)
				if color then
					local target = findPartByPathOrName(model, path)
					if target and isSelectablePart(target) then
						target.Color = color
					end
				end
			end
		end
	end
end

local function applyColorSchemeToWorkspaceModels(colorScheme: any)
	if not colorScheme then
		return
	end

	if typeof(colorScheme) == "table" then
		local isArray = colorScheme[1] ~= nil
		if not isArray and next(colorScheme) == nil then
			return
		elseif isArray and #colorScheme == 0 then
			return
		end
	else
		return
	end

	local rescueModel = Workspace:FindFirstChild(player.Name .. "_Rescue")
	if rescueModel and rescueModel:IsA("Model") then
		applyColorSchemeToModel(rescueModel, colorScheme)
	end

	local companionModel = Workspace:FindFirstChild(player.Name .. "_RescueCompanion")
	if companionModel and companionModel:IsA("Model") then
		applyColorSchemeToModel(companionModel, colorScheme)
	end
end

local function applyEquippedItemsToWorkspaceModels(equippedItems: {{id: string, row: number, column: number, color: any?}})
	local rescueModel = Workspace:FindFirstChild(player.Name .. "_Rescue")
	local companionModel = Workspace:FindFirstChild(player.Name .. "_RescueCompanion")

	-- Clear equipped items เก่าก่อน
	if rescueModel then
		EquipmentManager.setTargetBot(rescueModel)
		EquipmentManager.clearAll()
	end
	if companionModel then
		EquipmentManager.setTargetBot(companionModel)
		EquipmentManager.clearAll()
	end

	-- Apply equipped items ใหม่
	if equippedItems and #equippedItems > 0 then
		for _, equippedItem in ipairs(equippedItems) do
			local itemId = equippedItem.id

			-- Apply to Rescue model
			if rescueModel and rescueModel:IsA("Model") then
				EquipmentManager.setTargetBot(rescueModel)
				local success = EquipmentManager.equipItem(itemId, equippedItem.color)
				if success then
					print("[CustomizeUI] Equipped", itemId, "on Rescue")
				end
			end

			-- Apply to Companion model
			if companionModel and companionModel:IsA("Model") then
				EquipmentManager.setTargetBot(companionModel)
				local success = EquipmentManager.equipItem(itemId, equippedItem.color)
				if success then
					print("[CustomizeUI] Equipped", itemId, "on Companion")
				end
			end
		end
	end

	print("[CustomizeUI] Applied equipped items to workspace models")
end

local function loadColorSchemeIntoPreview()
	local colorScheme = CustomizeService.getColorScheme()
	if colorScheme then
		currentColorScheme = colorScheme
		if previewBot then
			applyColorSchemeToModel(previewBot, colorScheme)
		end
		applyColorSchemeToWorkspaceModels(colorScheme)
	else
		currentColorScheme = nil
	end
end

function updateColorPickerForPart(part: BasePart)
	if not colorPickerFrame then
		return
	end

	colorPickerFrame.Visible = true
	if colorPickerPartLabel then
		colorPickerPartLabel.Text = part.Name
	end
	placeColorPickerAtMouse()
	task.defer(placeColorPickerAtMouse)

	local currentColor = part.Color
	local bestMatch: TextButton? = nil
	local bestDistance = math.huge

	for _, button in ipairs(colorPickerButtons) do
		local buttonColor = button.BackgroundColor3
		local distance = (Vector3.new(buttonColor.R, buttonColor.G, buttonColor.B) - Vector3.new(currentColor.R, currentColor.G, currentColor.B)).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			bestMatch = button
		end
	end

	if bestMatch then
		setActiveColorButton(bestMatch)
	else
		clearActiveColorButton()
	end
end

local function selectPreviewPart(part: BasePart)
	if not part then
		clearPreviewSelection()
		return
	end

	if not isSelectablePart(part) then
		clearPreviewSelection()
		return
	end

	selectedPreviewPart = part
	if previewOriginalColors[part] == nil then
		previewOriginalColors[part] = part.Color
	end

	local selection = ensureSelectionBox()
	selection.Adornee = part
	if previewBot then
		selection.Parent = previewBot
	else
		selection.Parent = part
	end

	if updateColorPickerForPart then
		updateColorPickerForPart(part)
	end
end

local function pickPreviewPartFromMouse(): BasePart?
	if not previewBot or not previewBot.Parent then
		return nil
	end

	local mouseLocation = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = {previewBot}
	raycastParams.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 500, raycastParams)
	if result and result.Instance and result.Instance:IsDescendantOf(previewBot) and result.Instance:IsA("BasePart") then
		if not isSelectablePart(result.Instance) then
			return nil
		end
		return result.Instance
	end

	return nil
end

local function isCellWithinAllowedArea(row: number, column: number): boolean
	return row >= 1 and row <= 2 and column >= 1 and column <= 4
end

local function isPlacementWithinAllowedArea(startRow: number, startColumn: number, config: LoadoutConfig): boolean
	local endRow = startRow + config.size.Y - 1
	local endColumn = startColumn + config.size.X - 1

	for row = startRow, endRow do
		for column = startColumn, endColumn do
			if not isCellWithinAllowedArea(row, column) then
				return false
			end
		end
	end

	return true
end

-- ฟังก์ชันสร้าง Customize Icon ด้วย TopbarPlus
local function createCustomizeIcon()
	if customizeIcon then return customizeIcon end

	-- สร้าง Icon ด้วย TopbarPlus
	customizeIcon = TopbarPlus.new()
		:setName("CustomizeIcon")
		:setImage("77453564007772") -- Customize icon
		:setLabel("Customize")
		:setOrder(2) -- วางถัดจาก Shop (order 1)

	-- Bind events
	customizeIcon.selected:Connect(function()
		CustomizeUI.openCustomize()
	end)

	customizeIcon.deselected:Connect(function()
		CustomizeUI.closeCustomize()
	end)

	print("[CustomizeUI] Created Customize icon with TopbarPlus")
	return customizeIcon
end

local function ensureCustomizeIcon()
	if customizeIcon then
		return customizeIcon
	end

	return createCustomizeIcon()
end

local function initializeSlotState()
	table.clear(inventorySlots)
	for row = 1, SLOT_ROWS do
		slotMap[row] = slotMap[row] or {}
		slotOccupancy[row] = slotOccupancy[row] or {}
		table.clear(slotMap[row])
		table.clear(slotOccupancy[row])
	end

	table.clear(placedItems)
end

local function disconnectDragConnections()
	if dragContext.connections then
		for _, connection in ipairs(dragContext.connections) do
			connection:Disconnect()
		end
	end

	dragContext.connections = nil
end

local function clearSlotHighlights()
	if dragContext.highlight then
		for _, cell in ipairs(dragContext.highlight) do
			local frame = cell.frame
			frame.BackgroundColor3 = cell.defaultColor
			frame.BackgroundTransparency = cell.defaultTransparency
			if cell.stroke and cell.defaultStrokeColor then
				cell.stroke.Color = cell.defaultStrokeColor
			end
		end
	end

	dragContext.highlight = nil
end

local function applySlotHighlight(cells: { SlotData }, isValid: boolean)
	clearSlotHighlights()
	if not cells or #cells == 0 then
		return
	end

	dragContext.highlight = cells

	local highlightColor = if isValid then Color3.fromRGB(120, 190, 140) else Color3.fromRGB(205, 120, 120)
	local highlightTransparency = if isValid then 0.08 else 0.25

	for _, cell in ipairs(cells) do
		local frame = cell.frame
		frame.BackgroundColor3 = highlightColor
		frame.BackgroundTransparency = highlightTransparency
		if cell.stroke then
			cell.stroke.Color = highlightColor
		end
	end
end

local function clearInventoryPlacements()
	for _, guiObject in ipairs(placedItems) do
		if guiObject and guiObject.Parent then
			guiObject:Destroy()
		end
	end

	table.clear(placedItems)

	if slotsOverlayFrame then
		for _, child in ipairs(slotsOverlayFrame:GetChildren()) do
			child:Destroy()
		end
	end

	for row = 1, SLOT_ROWS do
		if slotOccupancy[row] then
			for column = 1, SLOT_COLUMNS do
				slotOccupancy[row][column] = nil
			end
		end
	end

	clearSlotHighlights()
	dragContext.currentPlacement = nil
	dragContext.placeholder = nil
	dragContext.originalParent = nil
	dragContext.originalLayoutOrder = nil
	dragContext.ghost = nil
	dragContext.active = false
	dragContext.config = nil
	dragContext.isFromSlot = false
	dragContext.occupiedCells = nil

	if loadoutBarFrame and rebuildLoadoutItems then
		rebuildLoadoutItems()
	end
end

-- โหลด equipped items จาก profile และวางลง Slots
local function loadEquippedItems()
	-- ดึง equipped items จาก server
	local equippedItems = CustomizeService.getEquippedItems()
	if not equippedItems or #equippedItems == 0 then
		print("[CustomizeUI] No equipped items to load")
		return
	end

	print("[CustomizeUI] Loading equipped items:")
	local entries = {}
	for index, equippedItem in ipairs(equippedItems) do
		local id
		local row, column
		if typeof(equippedItem) == "string" then
			id = equippedItem
			row, column = -1, -1
		elseif typeof(equippedItem) == "table" then
			id = tostring(equippedItem.id)
			row = equippedItem.row or -1
			column = equippedItem.column or -1
		end
		if not id then
			continue
		end
		local colorEntry = getItemColorFromScheme(id, currentColorScheme)
		if (not colorEntry) and typeof(equippedItem) == "table" and equippedItem.color then
			colorEntry = equippedItem.color
		end
		local line = string.format("#%d=%s(r=%d,c=%d)", index, id, row, column)
		if colorEntry then
			line ..= string.format(" color=(%.2f,%.2f,%.2f)", colorEntry.r or colorEntry.R or 0, colorEntry.g or colorEntry.G or 0, colorEntry.b or colorEntry.B or 0)
		end
		entries[#entries + 1] = line
	end
	if #entries > 0 then
		print("  { " .. table.concat(entries, ", ") .. " }")
	else
		print("  { } (none)")
	end

	for _, equippedItem in ipairs(equippedItems) do
		local itemId = equippedItem.id
		local row = equippedItem.row
		local column = equippedItem.column
		-- หา config สำหรับ item นี้
		local config: LoadoutConfig? = nil
		for _, c in ipairs(loadoutConfigs) do
			if c.id == itemId then
				config = c
				break
			end
		end

		if not config then
			warn("[CustomizeUI] Config not found for item:", itemId)
			continue
		end

		-- ตรวจสอบว่าตำแหน่งที่บันทึกไว้ว่างและพอดีกับ item หรือไม่
		local canPlace = true
		for r = row, row + config.size.Y - 1 do
			for c = column, column + config.size.X - 1 do
				if slotOccupancy[r] and slotOccupancy[r][c] then
					canPlace = false
					break
				end
				if not isCellWithinAllowedArea(r, c) then
					canPlace = false
					break
				end
			end
			if not canPlace then break end
		end

		if canPlace then
				-- สร้าง item frame และวางลง slot (เหมือนกับตอนลากวาง)
				local itemFrame = Instance.new("Frame")
				itemFrame.Name = "PlacedItem_" .. itemId
				itemFrame.BackgroundColor3 = Color3.fromRGB(58, 62, 77)
				itemFrame.BackgroundTransparency = 0.08
				itemFrame.BorderSizePixel = 0
				itemFrame.Active = false
				itemFrame.Selectable = false

				-- เพิ่ม label
				local label = Instance.new("TextLabel")
				label.Name = "Label"
				label.Size = UDim2.new(1, -8, 1, -8)
				label.Position = UDim2.new(0.5, 0, 0.5, 0)
				label.AnchorPoint = Vector2.new(0.5, 0.5)
				label.BackgroundTransparency = 1
				label.Font = Enum.Font.GothamMedium
				label.Text = config.displayName
				label.TextColor3 = Color3.fromRGB(220, 224, 233)
				label.TextScaled = true
				label.TextWrapped = true
				label.Parent = itemFrame

				-- คำนวณตำแหน่งและขนาด
				local topSlot = slotMap[row] and slotMap[row][column]
				if not topSlot then
					warn("[CustomizeUI] Slot not found for position:", row, column)
					itemFrame:Destroy()
					break
				end

				local endRow = row + config.size.Y - 1
				local endColumn = column + config.size.X - 1
				local bottomSlot = slotMap[endRow] and slotMap[endRow][endColumn]
				if not bottomSlot then
					warn("[CustomizeUI] Bottom slot not found for position:", endRow, endColumn)
					itemFrame:Destroy()
					break
				end

				local topSlotFrame = topSlot.frame
				local bottomSlotFrame = bottomSlot.frame

				if not slotsOverlayFrame then
					warn("[CustomizeUI] SlotsOverlay not found")
					itemFrame:Destroy()
					break
				end

				local topPosition = Vector2.new(topSlotFrame.AbsolutePosition.X, topSlotFrame.AbsolutePosition.Y)
				local bottomRight = Vector2.new(
					bottomSlotFrame.AbsolutePosition.X + bottomSlotFrame.AbsoluteSize.X,
					bottomSlotFrame.AbsolutePosition.Y + bottomSlotFrame.AbsoluteSize.Y
				)
				local overlayPosition = Vector2.new(slotsOverlayFrame.AbsolutePosition.X, slotsOverlayFrame.AbsolutePosition.Y)

				itemFrame.Parent = slotsOverlayFrame
				itemFrame.AnchorPoint = Vector2.new(0, 0)
				itemFrame.Position = UDim2.fromOffset(topPosition.X - overlayPosition.X, topPosition.Y - overlayPosition.Y)
				itemFrame.Size = UDim2.fromOffset(bottomRight.X - topPosition.X, bottomRight.Y - topPosition.Y)
				setGuiTreeZIndex(itemFrame, (slotsOverlayFrame.ZIndex or 1) + 1)

				-- อัปเดต occupancy
				for r = row, endRow do
					for c = column, endColumn do
						if slotOccupancy[r] then
							slotOccupancy[r][c] = itemFrame
						end
					end
				end

				itemFrame:SetAttribute("ItemId", itemId)
				itemFrame:SetAttribute("TopRow", row)
				itemFrame:SetAttribute("TopColumn", column)

				placedItems[#placedItems + 1] = itemFrame

				-- Equip item บน preview bot
				EquipmentManager.equipItem(itemId, getItemColorFromScheme(itemId, currentColorScheme))

				-- เพิ่ม InputBegan event สำหรับการลากกลับ
				itemFrame.InputBegan:Connect(function(input)
					if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
						beginSlotItemDrag(itemFrame)
					end
				end)

			print("[CustomizeUI] Placed item", itemId, "at position", row, column)
		else
			warn("[CustomizeUI] Cannot place item", itemId, "at saved position", row, column, "- position occupied or invalid")
		end
	end

	-- อัปเดต slot labels
	updateSlotLabels()

	-- Rebuild loadout items เพื่อลบ items ที่ถูกวางไปแล้ว
	rebuildLoadoutItems()
end

setGuiTreeZIndex = function(guiObject: GuiObject, baseZIndex: number)
	guiObject.ZIndex = baseZIndex
	for _, descendant in ipairs(guiObject:GetDescendants()) do
		if descendant:IsA("GuiObject") then
			descendant.ZIndex = baseZIndex + 1
		end
	end
end

local function cancelActiveDrag()
	if not dragContext.active then
		return
	end

	local ghost = dragContext.ghost
	local placeholder = dragContext.placeholder
	local originalParent = dragContext.originalParent

	if placeholder then
		placeholder:Destroy()
	end

	if ghost then
		ghost.AnchorPoint = Vector2.new(0, 0)
		ghost.Position = UDim2.fromScale(0, 0)
		ghost.Size = UDim2.fromScale(0.16, 0.95)
		ghost.Active = true
		ghost.Selectable = false

		-- เพิ่ม UIAspectRatioConstraint กลับมา
		local existingAspect = ghost:FindFirstChildOfClass("UIAspectRatioConstraint")
		if not existingAspect then
			local aspectRatio = Instance.new("UIAspectRatioConstraint")
			aspectRatio.AspectRatio = 1
			aspectRatio.Parent = ghost
		end

		local targetParent = originalParent or loadoutBarFrame
		if targetParent then
			ghost.Parent = targetParent
			setGuiTreeZIndex(ghost, (targetParent.ZIndex or 1) + 1)
			if dragContext.originalLayoutOrder then
				ghost.LayoutOrder = dragContext.originalLayoutOrder
			end
		else
			ghost:Destroy()
		end
	end

	dragContext.active = false
	dragContext.config = nil
	dragContext.ghost = nil
	dragContext.currentPlacement = nil
	dragContext.originalParent = nil
	dragContext.placeholder = nil
	dragContext.originalLayoutOrder = nil
	dragContext.isFromSlot = false
	dragContext.occupiedCells = nil

	clearSlotHighlights()
	disconnectDragConnections()

	if loadoutBarFrame and rebuildLoadoutItems then
		rebuildLoadoutItems()
	end
end

local function findSlotUnderPoint(position: Vector2): SlotData?
	for _, slot in ipairs(inventorySlots) do
		local frame = slot.frame
		local absPos = frame.AbsolutePosition
		local size = frame.AbsoluteSize
		if position.X >= absPos.X and position.X <= absPos.X + size.X and position.Y >= absPos.Y and position.Y <= absPos.Y + size.Y then
			return slot
		end
	end

	return nil
end

local function isPointOverLoadoutBar(position: Vector2): boolean
	if not loadoutBarFrame then
		return false
	end

	local absPos = loadoutBarFrame.AbsolutePosition
	local size = loadoutBarFrame.AbsoluteSize
	return position.X >= absPos.X and position.X <= absPos.X + size.X and position.Y >= absPos.Y and position.Y <= absPos.Y + size.Y
end

local function findLoadoutSlotUnderPoint(position: Vector2): Frame?
	if not loadoutBarFrame then
		return nil
	end

	for _, child in ipairs(loadoutBarFrame:GetChildren()) do
		if child:IsA("Frame") and string.find(child.Name, "LoadoutSlot") then
			local absPos = child.AbsolutePosition
			local size = child.AbsoluteSize
			if position.X >= absPos.X and position.X <= absPos.X + size.X and position.Y >= absPos.Y and position.Y <= absPos.Y + size.Y then
				return child
			end
		end
	end

	return nil
end

local function evaluatePlacement(position: Vector2, config: LoadoutConfig)
	if not config then
		return nil
	end

	-- ตรวจสอบว่าเมาส์อยู่เหนือ LoadoutBar หรือไม่
	if isPointOverLoadoutBar(position) then
		return {
			valid = true,
			isOverLoadoutBar = true,
		}
	end

	local topSlot = findSlotUnderPoint(position)
	if not topSlot then
		return nil
	end

	local endColumn = topSlot.column + config.size.X - 1
	local endRow = topSlot.row + config.size.Y - 1

	local cells: { SlotData } = {}
	local blocked = false

	if not isPlacementWithinAllowedArea(topSlot.row, topSlot.column, config) then
		for row = topSlot.row, math.min(endRow, SLOT_ROWS) do
			for column = topSlot.column, math.min(endColumn, SLOT_COLUMNS) do
				local cell = slotMap[row][column]
				if cell then
					table.insert(cells, cell)
				end
			end
		end

		return {
			valid = false,
			cells = cells,
			blocked = true,
		}
	end

	if endColumn > SLOT_COLUMNS or endRow > SLOT_ROWS then
		for row = topSlot.row, math.min(endRow, SLOT_ROWS) do
			for column = topSlot.column, math.min(endColumn, SLOT_COLUMNS) do
				local cell = slotMap[row][column]
				if cell then
					table.insert(cells, cell)
				end
			end
		end

		return {
			valid = false,
			cells = cells,
			blocked = true,
		}
	end

	for row = topSlot.row, endRow do
		for column = topSlot.column, endColumn do
			local cell = slotMap[row][column]
			if cell then
				table.insert(cells, cell)
				if slotOccupancy[row][column] then
					blocked = true
				end
			end
		end
	end

	local bottomSlot = slotMap[endRow] and slotMap[endRow][endColumn] or nil

	return {
		valid = not blocked,
		cells = cells,
		topSlot = topSlot,
		bottomSlot = bottomSlot,
		topRow = topSlot.row,
		topColumn = topSlot.column,
		endRow = endRow,
		endColumn = endColumn,
	}
end

local function positionGhost(mousePosition: Vector2)
	if dragContext.ghost then
		dragContext.ghost.Position = UDim2.fromOffset(mousePosition.X, mousePosition.Y)
	end
end

local function updateDragState(mousePosition: Vector2)
	positionGhost(mousePosition)

	-- ตรวจสอบว่ากำลังลากอยู่เหนือ LoadoutBar หรือไม่
	local isOverLoadoutBar = isPointOverLoadoutBar(mousePosition)

	-- ปรับขนาด ghost frame ตามตำแหน่งที่ลากอยู่
	if dragContext.ghost and dragContext.config then
		local camera = workspace.CurrentCamera
		local viewportSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)

		if isOverLoadoutBar then
			-- ถ้าลากอยู่เหนือ LoadoutBar ใช้ขนาดของ LoadoutBar
			local loadoutHeight = viewportSize.Y * 0.09
			local slotHeight = loadoutHeight * 0.95
			dragContext.ghost.Size = UDim2.fromOffset(slotHeight, slotHeight)
		else
			-- ถ้าลากอยู่เหนือ Inventory ใช้ขนาดของ Inventory slots
			local panelWidth = viewportSize.X * 0.35
			local slotSizePixels = Vector2.new(panelWidth * 0.148, panelWidth * 0.148)
			local paddingPixels = Vector2.new(panelWidth * 0.01, panelWidth * 0.01)

			local baseWidth = (slotSizePixels.X + paddingPixels.X) * dragContext.config.size.X - paddingPixels.X
			local baseHeight = (slotSizePixels.Y + paddingPixels.Y) * dragContext.config.size.Y - paddingPixels.Y
			dragContext.ghost.Size = UDim2.fromOffset(baseWidth, baseHeight)
		end
	end

	local placement = evaluatePlacement(mousePosition, dragContext.config)
	dragContext.currentPlacement = placement

	-- ตรวจสอบว่าเมาส์อยู่เหนือ LoadoutSlot หรือไม่ (สำหรับการสลับตำแหน่ง)
	if not dragContext.isFromSlot then
		local targetSlot = findLoadoutSlotUnderPoint(mousePosition)
		dragContext.targetLoadoutSlot = targetSlot

		-- แสดง highlight บน LoadoutSlot ถ้ามี
		if targetSlot and targetSlot ~= dragContext.ghost then
			targetSlot.BackgroundColor3 = Color3.fromRGB(120, 190, 140)
			targetSlot.BackgroundTransparency = 0.3
		end

		-- ลบ highlight จาก LoadoutSlot เก่า
		if loadoutBarFrame then
			for _, child in ipairs(loadoutBarFrame:GetChildren()) do
				if child:IsA("Frame") and string.find(child.Name, "LoadoutSlot") and child ~= targetSlot and child ~= dragContext.ghost then
					child.BackgroundColor3 = Color3.fromRGB(58, 62, 77)
					child.BackgroundTransparency = 0.08
				end
			end
		end
	end

	if placement then
		applySlotHighlight(placement.cells or {}, placement.valid)
	else
		clearSlotHighlights()
	end
end

updateSlotLabels = function()
	-- อัปเดต visibility ของ LV1 labels ตาม slot occupancy
	for row = 1, 2 do
		for column = 1, 4 do
			local cell = slotMap[row] and slotMap[row][column]
			if cell then
				local levelLabel = cell.frame:FindFirstChild("LevelTag")
				if levelLabel then
					-- แสดง label เฉพาะเมื่อ slot ว่าง
					levelLabel.Visible = not slotOccupancy[row][column]
				end
			end
		end
	end
end

local function finalizePlacement(placement)
	local ghost = dragContext.ghost
	if not ghost or not placement or not placement.valid or not slotsOverlayFrame then
		return
	end

	local topSlotFrame = placement.topSlot.frame

	-- คำนวณ bottomSlot อย่างถูกต้องตาม config size
	local bottomSlotFrame: Frame
	if placement.bottomSlot then
		bottomSlotFrame = placement.bottomSlot.frame
	else
		-- ถ้าไม่มี bottomSlot ใน placement ให้คำนวณเอง
		local endRow = placement.endRow or placement.topRow
		local endColumn = placement.endColumn or placement.topColumn
		local bottomSlot = slotMap[endRow] and slotMap[endRow][endColumn]
		bottomSlotFrame = bottomSlot and bottomSlot.frame or topSlotFrame
	end

	local topPosition = Vector2.new(topSlotFrame.AbsolutePosition.X, topSlotFrame.AbsolutePosition.Y)
	local bottomRight = Vector2.new(
		bottomSlotFrame.AbsolutePosition.X + bottomSlotFrame.AbsoluteSize.X,
		bottomSlotFrame.AbsolutePosition.Y + bottomSlotFrame.AbsoluteSize.Y
	)
	local overlayPosition = Vector2.new(slotsOverlayFrame.AbsolutePosition.X, slotsOverlayFrame.AbsolutePosition.Y)

	ghost.Parent = slotsOverlayFrame
	ghost.AnchorPoint = Vector2.new(0, 0)
	ghost.Position = UDim2.fromOffset(topPosition.X - overlayPosition.X, topPosition.Y - overlayPosition.Y)
	ghost.Size = UDim2.fromOffset(bottomRight.X - topPosition.X, bottomRight.Y - topPosition.Y)
	ghost.Active = false
	ghost.Selectable = false
	setGuiTreeZIndex(ghost, (slotsOverlayFrame.ZIndex or 1) + 1)

	if dragContext.placeholder then
		dragContext.placeholder:Destroy()
		dragContext.placeholder = nil
	end

	dragContext.originalParent = nil
	dragContext.originalLayoutOrder = nil

	for _, cell in ipairs(placement.cells or {}) do
		if slotOccupancy[cell.row] then
			slotOccupancy[cell.row][cell.column] = ghost
		end
	end

	ghost:SetAttribute("ItemId", dragContext.config and dragContext.config.id or "")
	ghost:SetAttribute("TopRow", placement.topRow)
	ghost:SetAttribute("TopColumn", placement.topColumn)

	placedItems[#placedItems + 1] = ghost

	-- อัปเดต slot labels
	updateSlotLabels()

	-- Equip item บน preview bot
	local itemId = dragContext.config and dragContext.config.id
	if itemId then
		EquipmentManager.equipItem(itemId, getItemColorFromScheme(itemId, currentColorScheme))
	end

	-- เพิ่ม InputBegan event สำหรับการลากกลับ
	ghost.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginSlotItemDrag(ghost)
		end
	end)
end

local function finishDrag(success: boolean)
	local ghost = dragContext.ghost
	local placement = dragContext.currentPlacement
	local targetSlot = dragContext.targetLoadoutSlot

	print("[CustomizeUI] finishDrag - success:", success, "placement:", placement, "valid:", placement and placement.valid, "isOverLoadoutBar:", placement and placement.isOverLoadoutBar, "isFromSlot:", dragContext.isFromSlot, "targetSlot:", targetSlot)

	-- ลบ highlight จาก LoadoutSlots ทั้งหมด
	if loadoutBarFrame then
		for _, child in ipairs(loadoutBarFrame:GetChildren()) do
			if child:IsA("Frame") and string.find(child.Name, "LoadoutSlot") then
				child.BackgroundColor3 = Color3.fromRGB(58, 62, 77)
				child.BackgroundTransparency = 0.08
			end
		end
	end

	if success and placement and placement.valid and not placement.isOverLoadoutBar then
		-- วางสำเร็จใน Slots
		print("[CustomizeUI] Placing item in slot")
		finalizePlacement(placement)
	elseif not dragContext.isFromSlot and targetSlot and targetSlot ~= ghost then
		-- สลับตำแหน่งกับ LoadoutSlot อื่น
		print("[CustomizeUI] Swapping positions with target slot")

		if dragContext.placeholder then
			dragContext.placeholder:Destroy()
			dragContext.placeholder = nil
		end

		if ghost then
			local ghostLayoutOrder = dragContext.originalLayoutOrder or ghost.LayoutOrder
			local targetLayoutOrder = targetSlot.LayoutOrder

			-- สลับ LayoutOrder
			ghost.LayoutOrder = targetLayoutOrder
			targetSlot.LayoutOrder = ghostLayoutOrder

			-- รีเซ็ต ghost ให้เป็นขนาดของ LoadoutBar
			ghost.AnchorPoint = Vector2.new(0, 0)
			ghost.Position = UDim2.fromScale(0, 0)
			ghost.Size = UDim2.fromScale(0.16, 0.95)
			ghost.Active = true
			ghost.Selectable = false
			ghost.Parent = loadoutBarFrame
			setGuiTreeZIndex(ghost, (loadoutBarFrame.ZIndex or 1) + 1)

			-- เพิ่ม UIAspectRatioConstraint กลับมา
			local existingAspect = ghost:FindFirstChildOfClass("UIAspectRatioConstraint")
			if not existingAspect then
				local aspectRatio = Instance.new("UIAspectRatioConstraint")
				aspectRatio.AspectRatio = 1
				aspectRatio.Parent = ghost
			end

			print("[CustomizeUI] Swapped successfully")
		end
	else
		-- ยกเลิกการลาก หรือวางไม่ถูกต้อง - คืนกลับไปที่ LoadoutBar
		print("[CustomizeUI] Returning item to LoadoutBar")

		if dragContext.placeholder then
			dragContext.placeholder:Destroy()
			dragContext.placeholder = nil
		end

		if ghost then
			-- ถ้าลากมาจาก Slot ให้ลบออกแล้วสร้างใหม่ที่ LoadoutBar
			if dragContext.isFromSlot and dragContext.occupiedCells then
				print("[CustomizeUI] Item was from slot, removing and rebuilding")

				-- Unequip item จาก preview bot
				local itemId = ghost:GetAttribute("ItemId")
				if itemId then
					EquipmentManager.unequipItem(itemId)
				end

				-- ลบ item ออกจาก Slots
				for _, cell in ipairs(dragContext.occupiedCells) do
					if slotOccupancy[cell.row] then
						slotOccupancy[cell.row][cell.column] = nil
					end
				end

				-- ลบ ghost จาก placedItems
				for i, item in ipairs(placedItems) do
					if item == ghost then
						table.remove(placedItems, i)
						break
					end
				end

				-- ลบ ghost
				ghost:Destroy()

				-- อัปเดต slot labels
				updateSlotLabels()

				-- สร้าง loadout slot ใหม่
				if loadoutBarFrame and rebuildLoadoutItems then
					rebuildLoadoutItems()
					print("[CustomizeUI] LoadoutBar rebuilt")
				else
					warn("[CustomizeUI] Cannot rebuild - loadoutBarFrame or rebuildLoadoutItems is nil")
				end
			else
				-- ลากมาจาก LoadoutBar - คืนกลับไปที่ LoadoutBar
				print("[CustomizeUI] Item was from LoadoutBar, returning to original position")

				ghost.AnchorPoint = Vector2.new(0, 0)
				ghost.Position = UDim2.fromScale(0, 0)
				ghost.Size = UDim2.fromScale(0.16, 0.95)
				ghost.Active = true
				ghost.Selectable = false

				-- เพิ่ม UIAspectRatioConstraint กลับมา
				local existingAspect = ghost:FindFirstChildOfClass("UIAspectRatioConstraint")
				if not existingAspect then
					local aspectRatio = Instance.new("UIAspectRatioConstraint")
					aspectRatio.AspectRatio = 1
					aspectRatio.Parent = ghost
				end

				if loadoutBarFrame then
					ghost.Parent = loadoutBarFrame
					setGuiTreeZIndex(ghost, (loadoutBarFrame.ZIndex or 1) + 1)
					if dragContext.originalLayoutOrder then
						ghost.LayoutOrder = dragContext.originalLayoutOrder
					end
					print("[CustomizeUI] Item returned to LoadoutBar successfully")
				else
					warn("[CustomizeUI] loadoutBarFrame is nil, destroying ghost")
					ghost:Destroy()
				end
			end
		else
			warn("[CustomizeUI] ghost is nil in finishDrag")
		end
	end

	dragContext.active = false
	dragContext.config = nil
	dragContext.ghost = nil
	dragContext.currentPlacement = nil
	dragContext.originalParent = nil
	dragContext.originalLayoutOrder = nil
	dragContext.isFromSlot = false
	dragContext.occupiedCells = nil
	dragContext.targetLoadoutSlot = nil

	clearSlotHighlights()
	disconnectDragConnections()
end

local function handleDragInputChanged(input)
	if not dragContext.active then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement then
		updateDragState(UserInputService:GetMouseLocation())
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local touchPos = input.Position
		updateDragState(Vector2.new(touchPos.X, touchPos.Y))
	end
end

local function handleDragInputEnded(input)
	if not dragContext.active then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local mousePosition = UserInputService:GetMouseLocation()

		-- อัปเดต placement ล่าสุดก่อนตัดสินใจ
		local placement = evaluatePlacement(mousePosition, dragContext.config)
		dragContext.currentPlacement = placement

		-- อัปเดต targetLoadoutSlot ล่าสุด
		if not dragContext.isFromSlot then
			dragContext.targetLoadoutSlot = findLoadoutSlotUnderPoint(mousePosition)
		end

		-- ถ้า placement valid และไม่ใช่เหนือ LoadoutBar = วางใน Slot สำเร็จ
		-- ถ้ามี targetLoadoutSlot = สลับตำแหน่ง
		-- ถ้าไม่ = คืนกลับไปที่ LoadoutBar
		if placement and placement.valid and not placement.isOverLoadoutBar then
			finishDrag(true)
		elseif not dragContext.isFromSlot and dragContext.targetLoadoutSlot and dragContext.targetLoadoutSlot ~= dragContext.ghost then
			finishDrag(true) -- จะเข้า swap case ใน finishDrag
		else
			finishDrag(false)
		end
	elseif input.UserInputType == Enum.UserInputType.Touch then
		local touchPos = input.Position
		local mousePosition = Vector2.new(touchPos.X, touchPos.Y)

		-- อัปเดต placement ล่าสุดก่อนตัดสินใจ
		local placement = evaluatePlacement(mousePosition, dragContext.config)
		dragContext.currentPlacement = placement

		-- อัปเดต targetLoadoutSlot ล่าสุด
		if not dragContext.isFromSlot then
			dragContext.targetLoadoutSlot = findLoadoutSlotUnderPoint(mousePosition)
		end

		if placement and placement.valid and not placement.isOverLoadoutBar then
			finishDrag(true)
		elseif not dragContext.isFromSlot and dragContext.targetLoadoutSlot and dragContext.targetLoadoutSlot ~= dragContext.ghost then
			finishDrag(true)
		else
			finishDrag(false)
		end
	end
end

local function beginLoadoutDrag(sourceFrame: Frame, config: LoadoutConfig)
	if not customizeScreenGui or dragContext.active then
		return
	end

	cancelActiveDrag()

	dragContext.active = true
	dragContext.config = config
	dragContext.ghost = sourceFrame
	dragContext.originalParent = sourceFrame.Parent
	dragContext.originalLayoutOrder = sourceFrame.LayoutOrder
	dragContext.isFromSlot = false
	dragContext.occupiedCells = nil
	if not dragContext.originalParent then
		dragContext.originalParent = loadoutBarFrame
	end

	local placeholder = Instance.new("Frame")
	placeholder.Name = sourceFrame.Name .. "_Placeholder"
	placeholder.Size = sourceFrame.Size
	placeholder.BackgroundTransparency = 1
	placeholder.BorderSizePixel = 0
	placeholder.LayoutOrder = sourceFrame.LayoutOrder
	if dragContext.originalParent then
		placeholder.Parent = dragContext.originalParent
		dragContext.placeholder = placeholder
	else
		placeholder:Destroy()
		dragContext.placeholder = nil
	end

	-- ลบ UIAspectRatioConstraint ถ้ามี (เพราะจะบังคับให้เป็นสี่เหลี่ยมจัตุรัส)
	local aspectConstraint = sourceFrame:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspectConstraint then
		aspectConstraint:Destroy()
	end

	sourceFrame.Parent = customizeScreenGui
	sourceFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	sourceFrame.Active = false
	sourceFrame.Selectable = false

	-- คำนวณขนาดแบบ dynamic จาก viewport
	local camera = workspace.CurrentCamera
	local viewportSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)

	-- คำนวณจาก Inventory Panel size (35% ของหน้าจอ)
	local panelWidth = viewportSize.X * 0.35
	local slotSizePixels = Vector2.new(panelWidth * 0.148, panelWidth * 0.148) -- ใช้ aspect ratio 1:1
	local paddingPixels = Vector2.new(panelWidth * 0.01, panelWidth * 0.01)

	local baseWidth = (slotSizePixels.X + paddingPixels.X) * config.size.X - paddingPixels.X
	local baseHeight = (slotSizePixels.Y + paddingPixels.Y) * config.size.Y - paddingPixels.Y
	sourceFrame.Size = UDim2.fromOffset(baseWidth, baseHeight)

	print(string.format("[CustomizeUI] Dragging %s from LoadoutBar - Size: %dx%d slots, Pixels: %.1fx%.1f",
		config.id, config.size.X, config.size.Y, baseWidth, baseHeight))

	setGuiTreeZIndex(sourceFrame, 200)

	local mouseLocation = UserInputService:GetMouseLocation()
	updateDragState(mouseLocation)

	dragContext.connections = {
		UserInputService.InputChanged:Connect(handleDragInputChanged),
		UserInputService.InputEnded:Connect(handleDragInputEnded),
	}
end

beginSlotItemDrag = function(sourceFrame: Frame)
	if not customizeScreenGui or dragContext.active then
		return
	end

	-- ดึงข้อมูล config จาก attribute
	local itemId = sourceFrame:GetAttribute("ItemId")
	local topRow = sourceFrame:GetAttribute("TopRow")
	local topColumn = sourceFrame:GetAttribute("TopColumn")

	if not itemId or not topRow or not topColumn then
		warn("[CustomizeUI] Cannot drag: missing item attributes")
		return
	end

	-- หา config ที่ตรงกับ itemId
	local config: LoadoutConfig? = nil
	for _, cfg in ipairs(loadoutConfigs) do
		if cfg.id == itemId then
			config = cfg
			break
		end
	end

	if not config then
		warn("[CustomizeUI] Cannot drag: config not found for", itemId)
		return
	end

	cancelActiveDrag()

	-- เก็บข้อมูล cells ที่ item นี้ครอบครอง
	local occupiedCells: { SlotData } = {}
	local endRow = topRow + config.size.Y - 1
	local endColumn = topColumn + config.size.X - 1

	for row = topRow, endRow do
		for column = topColumn, endColumn do
			local cell = slotMap[row][column]
			if cell then
				table.insert(occupiedCells, cell)
			end
		end
	end

	dragContext.active = true
	dragContext.config = config
	dragContext.ghost = sourceFrame
	dragContext.originalParent = sourceFrame.Parent
	dragContext.isFromSlot = true
	dragContext.occupiedCells = occupiedCells

	-- ลบ item ออกจาก slot occupancy ชั่วคราว
	for _, cell in ipairs(occupiedCells) do
		if slotOccupancy[cell.row] then
			slotOccupancy[cell.row][cell.column] = nil
		end
	end

	-- ลบ UIAspectRatioConstraint ถ้ามี (เพราะจะบังคับให้เป็นสี่เหลี่ยมจัตุรัส)
	local aspectConstraint = sourceFrame:FindFirstChildOfClass("UIAspectRatioConstraint")
	if aspectConstraint then
		aspectConstraint:Destroy()
	end

	sourceFrame.Parent = customizeScreenGui
	sourceFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	sourceFrame.Active = false
	sourceFrame.Selectable = false

	-- คำนวณขนาดแบบ dynamic จาก viewport สำหรับ multi-slot items
	local camera = workspace.CurrentCamera
	local viewportSize = camera and camera.ViewportSize or Vector2.new(1920, 1080)

	-- คำนวณจาก Inventory Panel size (35% ของหน้าจอ)
	local panelWidth = viewportSize.X * 0.35
	local slotSizePixels = Vector2.new(panelWidth * 0.148, panelWidth * 0.148) -- ใช้ aspect ratio 1:1
	local paddingPixels = Vector2.new(panelWidth * 0.01, panelWidth * 0.01)

	local baseWidth = (slotSizePixels.X + paddingPixels.X) * config.size.X - paddingPixels.X
	local baseHeight = (slotSizePixels.Y + paddingPixels.Y) * config.size.Y - paddingPixels.Y
	sourceFrame.Size = UDim2.fromOffset(baseWidth, baseHeight)

	print(string.format("[CustomizeUI] Dragging %s - Size: %dx%d slots, Pixels: %.1fx%.1f",
		config.id, config.size.X, config.size.Y, baseWidth, baseHeight))

	setGuiTreeZIndex(sourceFrame, 200)

	local mouseLocation = UserInputService:GetMouseLocation()
	updateDragState(mouseLocation)

	dragContext.connections = {
		UserInputService.InputChanged:Connect(handleDragInputChanged),
		UserInputService.InputEnded:Connect(handleDragInputEnded),
	}
end

createLoadoutSlot = function(config: LoadoutConfig, index: number): Frame
	if not loadoutBarFrame then
		error("[CustomizeUI] loadoutBarFrame is not initialized")
	end

	local itemFrame = Instance.new("Frame")
	itemFrame.Name = string.format("LoadoutSlot%d", index)
	itemFrame.Size = UDim2.fromScale(0.16, 0.95)
	itemFrame.BackgroundColor3 = Color3.fromRGB(58, 62, 77)
	itemFrame.BackgroundTransparency = 0.08
	itemFrame.BorderSizePixel = 0
	itemFrame.ZIndex = (loadoutBarFrame.ZIndex or 1) + 1
	itemFrame.Active = true
	itemFrame.LayoutOrder = index
	itemFrame.Parent = loadoutBarFrame
	itemFrame:SetAttribute("ItemId", config.id)

	local aspectRatio = Instance.new("UIAspectRatioConstraint")
	aspectRatio.AspectRatio = 1
	aspectRatio.Parent = itemFrame

	local itemCorner = Instance.new("UICorner")
	itemCorner.CornerRadius = UDim.new(0.1, 0)
	itemCorner.Parent = itemFrame


	local itemLabel = Instance.new("TextLabel")
	itemLabel.Name = "Label"
	itemLabel.Size = UDim2.fromScale(0.9, 0.9)
	itemLabel.Position = UDim2.fromScale(0.5, 0.5)
	itemLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	itemLabel.BackgroundTransparency = 1
	itemLabel.Font = Enum.Font.GothamMedium
	itemLabel.Text = config.displayName
	itemLabel.TextColor3 = Color3.fromRGB(220, 224, 233)
	itemLabel.TextScaled = true
	itemLabel.TextWrapped = true
	itemLabel.ZIndex = itemFrame.ZIndex + 1
	itemLabel.Parent = itemFrame

	local labelConstraint = Instance.new("UITextSizeConstraint")
	labelConstraint.MaxTextSize = 14
	labelConstraint.MinTextSize = 8
	labelConstraint.Parent = itemLabel

	local slotConfig = config
	itemFrame.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			beginLoadoutDrag(itemFrame, slotConfig)
		end
	end)

	return itemFrame
end

rebuildLoadoutItems = function()
	if not loadoutBarFrame then
		return
	end

	print("[CustomizeUI] rebuildLoadoutItems called")

	for _, child in ipairs(loadoutBarFrame:GetChildren()) do
		if child:IsA("Frame") then
			local name = child.Name
			if string.find(name, "LoadoutSlot") or string.find(name, "_Placeholder") then
				child:Destroy()
			end
		end
	end

	-- ทำความสะอาด placedItems - ลบ items ที่ถูก destroy หรือไม่มี parent แล้ว
	local validPlacedItems: { GuiObject } = {}
	for _, placedItem in ipairs(placedItems) do
		if placedItem and placedItem.Parent then
			table.insert(validPlacedItems, placedItem)
		else
			print("[CustomizeUI] - Removing invalid item from placedItems")
		end
	end
	placedItems = validPlacedItems

	-- สร้าง set ของ ItemId ที่ถูกวางใน Slots แล้ว
	local placedItemIds: { [string]: boolean } = {}
	for _, placedItem in ipairs(placedItems) do
		local itemId = placedItem:GetAttribute("ItemId")
		if itemId then
			placedItemIds[itemId] = true
			print("[CustomizeUI] - Item in slot:", itemId)
		end
	end

	print("[CustomizeUI] Total items in slots:", #placedItems)

	-- สร้างเฉพาะ items ที่ยังไม่ถูกวางใน Slots
	local slotIndex = 1
	for _, config in ipairs(loadoutConfigs) do
		if not placedItemIds[config.id] then
			print("[CustomizeUI] - Creating slot for:", config.id)
			createLoadoutSlot(config, slotIndex)
			slotIndex = slotIndex + 1
		else
			print("[CustomizeUI] - Skipping (already in slot):", config.id)
		end
	end

	print("[CustomizeUI] rebuildLoadoutItems complete, created", slotIndex - 1, "items")
end

-- ฟังก์ชันสร้าง Customize UI
local function createCustomizeUI()
	if customizeScreenGui then return customizeScreenGui end

	-- สร้าง ScreenGui
	customizeScreenGui = Instance.new("ScreenGui")
	customizeScreenGui.Name = "CustomizeGui"
	customizeScreenGui.IgnoreGuiInset = true
	customizeScreenGui.ResetOnSpawn = false
	customizeScreenGui.DisplayOrder = 200
	customizeScreenGui.Enabled = false
	customizeScreenGui.Parent = playerGui

	initializeSlotState()

	-- Content root (ใช้จัดตำแหน่ง UI)
	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "Content"
	contentFrame.Size = UDim2.new(1, 0, 1, 0)
	contentFrame.BackgroundTransparency = 1
	contentFrame.BorderSizePixel = 0
	contentFrame.Parent = customizeScreenGui

	-- Inventory panel (right side)
	local inventoryPanel = Instance.new("Frame")
	inventoryPanel.Name = "InventoryPanel"
	inventoryPanel.Size = UDim2.fromScale(0.35, 0.75)
	inventoryPanel.Position = UDim2.fromScale(0.98, 0.08)
	inventoryPanel.AnchorPoint = Vector2.new(1, 0)
	inventoryPanel.BackgroundColor3 = Color3.fromRGB(47, 51, 64)
	inventoryPanel.BackgroundTransparency = 0.8
	inventoryPanel.BorderSizePixel = 0
	inventoryPanel.ZIndex = 5
	inventoryPanel.Parent = contentFrame

	-- เพิ่ม UICorner สำหรับ rounded corners
	local inventoryCorner = Instance.new("UICorner")
	inventoryCorner.CornerRadius = UDim.new(0.02, 0)
	inventoryCorner.Parent = inventoryPanel

	local inventoryHeader = Instance.new("Frame")
	inventoryHeader.Name = "InventoryHeader"
	inventoryHeader.Size = UDim2.fromScale(1, 0.075)
	inventoryHeader.BackgroundColor3 = Color3.fromRGB(30, 32, 42)
	inventoryHeader.BackgroundTransparency = 0.2
	inventoryHeader.BorderSizePixel = 0
	inventoryHeader.ZIndex = inventoryPanel.ZIndex + 1
	inventoryHeader.Parent = inventoryPanel

	local headerPadding = Instance.new("UIPadding")
	headerPadding.PaddingLeft = UDim.new(0.03, 0)
	headerPadding.PaddingRight = UDim.new(0.03, 0)
	headerPadding.Parent = inventoryHeader

	local inventoryLabel = Instance.new("TextLabel")
	inventoryLabel.Name = "Title"
	inventoryLabel.Size = UDim2.fromScale(0.95, 1)
	inventoryLabel.BackgroundTransparency = 1
	inventoryLabel.Font = Enum.Font.GothamBold
	inventoryLabel.Text = "Inventory"
	inventoryLabel.TextColor3 = Color3.fromRGB(235, 237, 245)
	inventoryLabel.TextScaled = true
	inventoryLabel.TextXAlignment = Enum.TextXAlignment.Left
	inventoryLabel.ZIndex = inventoryHeader.ZIndex + 1
	inventoryLabel.Parent = inventoryHeader

	local inventoryConstraint = Instance.new("UITextSizeConstraint")
	inventoryConstraint.MaxTextSize = 28
	inventoryConstraint.MinTextSize = 16
	inventoryConstraint.Parent = inventoryLabel

	local slotsContainer = Instance.new("Frame")
	slotsContainer.Name = "Slots"
	slotsContainer.Size = UDim2.fromScale(0.95, 0.9)
	slotsContainer.Position = UDim2.fromScale(0.5, 0.095)
	slotsContainer.AnchorPoint = Vector2.new(0.5, 0)
	slotsContainer.BackgroundTransparency = 1
	slotsContainer.ZIndex = inventoryPanel.ZIndex + 1
	slotsContainer.Parent = inventoryPanel

	local slotsLayout = Instance.new("UIGridLayout")
	slotsLayout.CellSize = UDim2.fromScale(0.148, 0.125)
	slotsLayout.CellPadding = UDim2.fromScale(0.01, 0.01)
	slotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	slotsLayout.VerticalAlignment = Enum.VerticalAlignment.Top
	slotsLayout.StartCorner = Enum.StartCorner.TopLeft
	slotsLayout.FillDirectionMaxCells = SLOT_COLUMNS
	slotsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotsLayout.Parent = slotsContainer

	-- เพิ่ม UIAspectRatioConstraint สำหรับ slots
	local slotsAspect = Instance.new("UIAspectRatioConstraint")
	slotsAspect.AspectRatio = 1.05
	slotsAspect.Parent = slotsContainer

	for index = 1, SLOT_COLUMNS * SLOT_ROWS do
		local gridColumn = (index - 1) % SLOT_COLUMNS
		local gridRow = math.floor((index - 1) / SLOT_COLUMNS)
		local row = gridRow + 1
		local column = gridColumn + 1
		local isStarterSlot = gridRow < 2 and gridColumn < 4

		local slot = Instance.new("Frame")
		slot.Name = string.format("Slot%d", index)
		slot.BackgroundColor3 = Color3.fromRGB(58, 62, 77)
		slot.BackgroundTransparency = isStarterSlot and 0.05 or 0.35
		slot.BorderSizePixel = 0
		slot.ZIndex = slotsContainer.ZIndex + 1
		slot.Active = true
		slot.Parent = slotsContainer

		local slotStroke = Instance.new("UIStroke")
		slotStroke.Color = isStarterSlot and Color3.fromRGB(94, 99, 115) or Color3.fromRGB(64, 68, 82)
		slotStroke.Thickness = 1
		slotStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		slotStroke.Parent = slot

		if isStarterSlot then
			local levelLabel = Instance.new("TextLabel")
			levelLabel.Name = "LevelTag"
			levelLabel.Size = UDim2.new(1, 0, 1, 0)
			levelLabel.BackgroundTransparency = 1
			levelLabel.Font = Enum.Font.GothamBold
			levelLabel.Text = "LV1"
			levelLabel.TextSize = 10
			levelLabel.TextColor3 = Color3.fromRGB(215, 218, 228)
			levelLabel.ZIndex = slot.ZIndex + 1
			levelLabel.Visible = true
			levelLabel.Parent = slot
		end

		local slotData: SlotData = {
			frame = slot,
			row = row,
			column = column,
			defaultColor = slot.BackgroundColor3,
			defaultTransparency = slot.BackgroundTransparency,
			stroke = slotStroke,
			defaultStrokeColor = slotStroke.Color,
		}

		inventorySlots[#inventorySlots + 1] = slotData
		slotMap[row][column] = slotData
	end

	local slotsOverlay = Instance.new("Frame")
	slotsOverlay.Name = "SlotsOverlay"
	slotsOverlay.Size = slotsContainer.Size
	slotsOverlay.Position = slotsContainer.Position
	slotsOverlay.AnchorPoint = slotsContainer.AnchorPoint
	slotsOverlay.BackgroundTransparency = 1
	slotsOverlay.BorderSizePixel = 0
	slotsOverlay.ZIndex = slotsContainer.ZIndex + 5
	slotsOverlay.ClipsDescendants = false
	slotsOverlay.Parent = inventoryPanel
	slotsOverlayFrame = slotsOverlay

	-- Loadout bar at bottom
	local loadoutBar = Instance.new("Frame")
	loadoutBar.Name = "LoadoutBar"
	loadoutBar.Size = UDim2.fromScale(0.35, 0.09)
	loadoutBar.Position = UDim2.fromScale(0.5, 0.96)
	loadoutBar.AnchorPoint = Vector2.new(0.5, 1)
	loadoutBar.BackgroundColor3 = Color3.fromRGB(46, 50, 64)
	loadoutBar.BackgroundTransparency = 1
	loadoutBar.BorderSizePixel = 0
	loadoutBar.ZIndex = inventoryPanel.ZIndex + 1
	loadoutBar.Parent = contentFrame
	loadoutBarFrame = loadoutBar

	local loadoutPadding = Instance.new("UIPadding")
	loadoutPadding.PaddingLeft = UDim.new(0.04, 0)
	loadoutPadding.PaddingRight = UDim.new(0.04, 0)
	loadoutPadding.PaddingTop = UDim.new(0.12, 0)
	loadoutPadding.PaddingBottom = UDim.new(0.12, 0)
	loadoutPadding.Parent = loadoutBar

	local loadoutLayout = Instance.new("UIListLayout")
	loadoutLayout.FillDirection = Enum.FillDirection.Horizontal
	loadoutLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	loadoutLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	loadoutLayout.Padding = UDim.new(0.03, 0)
	loadoutLayout.SortOrder = Enum.SortOrder.LayoutOrder
	loadoutLayout.Parent = loadoutBar

	ensureColorPicker(contentFrame)

	rebuildLoadoutItems()

	print("Customize UI created successfully")
	return customizeScreenGui
end

local function showCustomizeUI()
	local screenGui = createCustomizeUI()
	if screenGui then
		screenGui.Enabled = true
	end
end

local function hideCustomizeUI()
	if customizeScreenGui then
		customizeScreenGui.Enabled = false
	end

	cancelActiveDrag()
end

-- ฟังก์ชัน Clone Rescue Bot และวางบน Garage.Base
local function setupPreviewBot()
	-- หา Rescue Model ใน ReplicatedStorage
	local rescueModel = ReplicatedStorage:FindFirstChild("Rescue")

	if not rescueModel then
		warn("[CustomizeUI] ไม่พบ Rescue ใน ReplicatedStorage")
		return
	end

	-- Clone bot
	previewBot = rescueModel:Clone()
	clearPreviewSelection()

	-- ซ่อน DrillArm parts ตั้งแต่แรก
	local tube1 = previewBot:FindFirstChild("Tube1")
	local drillArmModel = previewBot:FindFirstChild("DrillArm")
	for _, part in ipairs({tube1, drillArmModel}) do
		if part and part:IsA("BasePart") then
			part.Transparency = 1
		elseif part and part:IsA("Model") then
			for _, descendant in ipairs(part:GetDescendants()) do
				if descendant:IsA("BasePart") then
					descendant.Transparency = 1
				end
			end
		end
	end

	-- ซ่อน Camera part ตั้งแต่แรก (เหมือน DrillArm)
	local cameraPart = previewBot:FindFirstChild("Camera")
	if cameraPart and cameraPart:IsA("BasePart") then
		cameraPart.Transparency = 1
		print("[CustomizeUI] Hidden Camera part in preview bot")
	end

	if previewDescendantConn then
		previewDescendantConn:Disconnect()
		previewDescendantConn = nil
	end

	table.clear(previewOriginalColors)

	local function registerOriginalColor(instance: Instance)
		if instance:IsA("BasePart") then
			previewOriginalColors[instance] = instance.Color
		end
	end

	if previewBot:IsA("BasePart") then
		registerOriginalColor(previewBot)
	end

	for _, descendant in ipairs(previewBot:GetDescendants()) do
		registerOriginalColor(descendant)
	end

	previewDescendantConn = previewBot.DescendantAdded:Connect(function(descendant)
		registerOriginalColor(descendant)
	end)

	-- ตั้งค่า target bot สำหรับ EquipmentManager
	EquipmentManager.setTargetBot(previewBot)

	-- หา Garage.Base
	local garage = Workspace:FindFirstChild("Garage")
	if not garage then
		warn("[CustomizeUI] ไม่พบ Garage ใน Workspace")
		previewBot:Destroy()
		previewBot = nil
		return
	end

	local garageBase = garage:FindFirstChild("Base")
	if not garageBase then
		warn("[CustomizeUI] ไม่พบ Garage.Base")
		previewBot:Destroy()
		previewBot = nil
		return
	end

	-- วาง preview bot บน Garage.Base
	if previewBot.PrimaryPart then
		local basePosition = garageBase.Position
		local baseSizeY = garageBase.Size.Y
		local botSizeY = previewBot.PrimaryPart.Size.Y

		-- วางบนฐาน
		previewBot:PivotTo(CFrame.new(
			basePosition.X,
			basePosition.Y + (baseSizeY / 2) + (botSizeY / 2),
			basePosition.Z
		))
	end

	previewBot.Parent = Workspace
	print("[CustomizeUI] Preview bot spawned at Garage.Base")
end

-- ฟังก์ชัน Update Rescue Bot Rotation
local function updateBotRotation()
	if not previewBot or not previewBot.PrimaryPart then return end

	-- บันทึกตำแหน่งเดิม
	local originalPosition = previewBot.PrimaryPart.Position

	-- สร้าง CFrame ใหม่ด้วยมุม rotation รอบแกน Y
	local rotationCFrame = CFrame.new(originalPosition) * CFrame.Angles(0, math.rad(currentRotationAngle), 0)

	-- ใช้ PivotTo แทนเพื่อหมุนทั้ง Model รอบจุดเดียวกัน
	if previewBot.PrimaryPart then
		previewBot:PivotTo(rotationCFrame)
	end
end

-- ฟังก์ชันพับ/เก็บแขน
local function toggleArms()
	if not previewBot then return end

	-- สลับสถานะ
	armsExtended = not armsExtended

	-- กำหนด target angle
	local targetAngle = armsExtended and 0 or 180

	-- หา HingeConstraints ทั้งหมดในแขน
	for _, descendant in ipairs(previewBot:GetDescendants()) do
		if descendant:IsA("HingeConstraint") then
			-- ตั้งค่า TargetAngle
			descendant.TargetAngle = targetAngle
		end
	end

	print(string.format("[CustomizeUI] Arms %s (TargetAngle = %d)", armsExtended and "extended" or "folded", targetAngle))
end

-- ฟังก์ชัน Setup Camera Rotation Controls
local function setupCameraRotation()
	-- Disconnect existing connections
	if inputBeganConnection then inputBeganConnection:Disconnect() end
	if inputEndedConnection then inputEndedConnection:Disconnect() end
	if inputChangedConnection then inputChangedConnection:Disconnect() end

	-- Input Began - เริ่ม drag และ toggle arms
	inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end

		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			local hitPart = pickPreviewPartFromMouse()
			if hitPart then
				selectPreviewPart(hitPart)
			else
				clearPreviewSelection()
			end
			isDragging = true
			if input.UserInputType == Enum.UserInputType.MouseButton1 then
				lastMousePosition = UserInputService:GetMouseLocation()
			else
				local touchPos = input.Position
				lastMousePosition = Vector2.new(touchPos.X, touchPos.Y)
			end
		elseif input.KeyCode == Enum.KeyCode.Q then
			toggleArms()
		end
	end)

	-- Input Ended - หยุด drag
	inputEndedConnection = UserInputService.InputEnded:Connect(function(input, gameProcessed)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			isDragging = false
			lastMousePosition = nil
		end
	end)

	-- Input Changed - หมุน bot
	inputChangedConnection = UserInputService.InputChanged:Connect(function(input, gameProcessed)
		-- จัดการหมุน bot
		if isDragging then
			local currentMousePosition = nil

			if input.UserInputType == Enum.UserInputType.MouseMovement then
				currentMousePosition = UserInputService:GetMouseLocation()
			elseif input.UserInputType == Enum.UserInputType.Touch then
				local touchPos = input.Position
				currentMousePosition = Vector2.new(touchPos.X, touchPos.Y)
			end

			if currentMousePosition and lastMousePosition then
				local delta = currentMousePosition - lastMousePosition
				local rotationSpeed = 0.3

				-- หมุนรอบแกน Y (เฉพาะ X delta)
				currentRotationAngle = currentRotationAngle + (delta.X * rotationSpeed)

				updateBotRotation()
				lastMousePosition = currentMousePosition
			end
		end
	end)

	print("[CustomizeUI] Bot rotation controls enabled")
end

-- ฟังก์ชัน Cleanup Camera Rotation Controls
local function cleanupCameraRotation()
	if inputBeganConnection then
		inputBeganConnection:Disconnect()
		inputBeganConnection = nil
	end
	if inputEndedConnection then
		inputEndedConnection:Disconnect()
		inputEndedConnection = nil
	end
	if inputChangedConnection then
		inputChangedConnection:Disconnect()
		inputChangedConnection = nil
	end

	isDragging = false
	lastMousePosition = nil
	currentRotationAngle = 0
	armsExtended = true

	print("[CustomizeUI] Bot rotation controls disabled")
end

-- ฟังก์ชัน Pan กล้องไปที่ Garage.Camera
local function panCameraToGarage()
	-- บันทึกตำแหน่งกล้องเดิม
	originalCameraCFrame = camera.CFrame
	originalCameraType = camera.CameraType
	originalFOV = camera.FieldOfView

	-- หา Garage.Camera
	local garage = Workspace:FindFirstChild("Garage")
	if not garage then
		warn("[CustomizeUI] ไม่พบ Garage")
		showCustomizeUI()
		return
	end

	local garageCamera = garage:FindFirstChild("Camera")
	if not garageCamera then
		warn("[CustomizeUI] ไม่พบ Garage.Camera")
		showCustomizeUI()
		return
	end

	-- ตั้งค่ากล้องเป็น Scriptable
	camera.CameraType = Enum.CameraType.Scriptable

	-- ตั้งค่า Field of View สำหรับ Customize mode
	camera.FieldOfView = 70

	-- Pan กล้องไปที่ Garage.Camera CFrame
	local targetCFrame = garageCamera.CFrame
	currentRotationAngle = 0

	-- Tween camera
	local cameraTweenInfo = TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local cameraTween = TweenService:Create(camera, cameraTweenInfo, {
		CFrame = targetCFrame
	})

	cameraTween:Play()

	-- Setup rotation controls หลัง tween เสร็จ
	cameraTween.Completed:Connect(function()
		if not isCustomizeOpen then
			return
		end

		showCustomizeUI()
		setupCameraRotation()
	end)

	print("[CustomizeUI] Camera panned to Garage.Camera")
end

-- ฟังก์ชันคืนกล้องและลบ preview bot
local function cleanupPreview()
	-- Cleanup camera rotation controls
	cleanupCameraRotation()
	clearPreviewSelection()
	if previewDescendantConn then
		previewDescendantConn:Disconnect()
		previewDescendantConn = nil
	end
	table.clear(previewOriginalColors)

	-- Cleanup equipped items
	EquipmentManager.clearAll()

	-- ลบ preview bot
	if previewBot then
		previewBot:Destroy()
		previewBot = nil
		print("[CustomizeUI] Preview bot removed")
	end

	-- คืนกล้องกลับ
	if originalCameraCFrame and originalCameraType then
		camera.CameraType = originalCameraType

		-- คืน FOV เดิม
		if originalFOV then
			camera.FieldOfView = originalFOV
		end

		local cameraTweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local cameraTween = TweenService:Create(camera, cameraTweenInfo, {
			CFrame = originalCameraCFrame
		})

		cameraTween:Play()
		print("[CustomizeUI] Camera restored")
	end
end

-- ฟังก์ชันเปิด Customize
function CustomizeUI.openCustomize()
	if isCustomizeOpen then return end

	isCustomizeOpen = true

	hideCustomizeUI()
	createCustomizeUI()
	clearInventoryPlacements()

	-- ซ่อน Player List (GUI มุมขวาบน)
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)

	-- Setup preview bot และ pan กล้อง
	setupPreviewBot()
	loadColorSchemeIntoPreview()
	panCameraToGarage()

	-- โหลด equipped items จาก profile และวางลง Slots
	task.delay(0.1, function()
		loadEquippedItems()
	end)

	print("Customize opened")
end

-- ฟังก์ชันปิด Customize
function CustomizeUI.closeCustomize()
	if not isCustomizeOpen then return end

	isCustomizeOpen = false

	-- รวบรวมข้อมูลสีจาก preview (ใช้ทั้งกับ items และโมเดลจริง)
	local colorScheme = collectColorScheme(previewBot)
	local itemColorMap: {[string]: {r: number, g: number, b: number}} = {}
	if colorScheme then
		for path, color in pairs(colorScheme) do
			itemColorMap[path] = color
			local firstSegment = path:match("^[^/]+")
			if firstSegment and not itemColorMap[firstSegment] then
				itemColorMap[firstSegment] = color
			end
		end
	end

	-- บันทึก equipped items พร้อมตำแหน่งไปยัง server
	local equippedItemsWithPosition = {}

	for _, placedItem in ipairs(placedItems) do
		local itemId = placedItem:GetAttribute("ItemId")
		local row = placedItem:GetAttribute("TopRow")
		local column = placedItem:GetAttribute("TopColumn")

		if itemId and row and column then
			local entry = {
				id = itemId,
				row = row,
				column = column,
			}
			local colorForItem = itemColorMap[itemId] or itemColorMap[itemId .. "Model"]
			if not colorForItem then
				for key, color in pairs(itemColorMap) do
					if key:find(itemId, 1, true) then
						colorForItem = color
						break
					end
				end
			end
			if colorForItem then
				entry.color = colorForItem
			end
			table.insert(equippedItemsWithPosition, entry)
		end
	end

	-- บันทึกเสมอ แม้ว่าจะเป็น array ว่าง (unequip ทุกอย่าง)
	CustomizeService.saveEquippedItems(equippedItemsWithPosition)
	if #equippedItemsWithPosition > 0 then
		local entries = {}
		for _, entry in ipairs(equippedItemsWithPosition) do
			local line = string.format("%s(r=%d,c=%d)", entry.id, entry.row, entry.column)
			if entry.color then
				line ..= string.format(" color=(%.2f,%.2f,%.2f)", entry.color.r, entry.color.g, entry.color.b)
			end
			entries[#entries + 1] = line
		end
		print("[CustomizeUI] Saved equipped items with positions:", entries)
	else
		print("[CustomizeUI] Saved equipped items with positions: { } (none)")
	end

	currentColorScheme = colorScheme
	CustomizeService.saveColorScheme(colorScheme)
	applyColorSchemeToWorkspaceModels(colorScheme)

	if colorScheme and next(colorScheme) then
		local entries = {}
		for path, color in pairs(colorScheme) do
			entries[#entries + 1] = string.format("%s=(%.2f,%.2f,%.2f)", path, color.r, color.g, color.b)
		end
		print("[CustomizeUI] Saved color scheme (table):", entries)
	else
		print("[CustomizeUI] Color scheme empty (default colors in use)")
	end

	-- Apply equipped items to workspace models
	applyEquippedItemsToWorkspaceModels(equippedItemsWithPosition)

	-- แสดง Player List กลับ
	game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, true)

	-- Cleanup preview bot และคืนกล้อง
	cleanupPreview()

	hideCustomizeUI()

	-- Deselect TopbarPlus icon
	if customizeIcon then
		customizeIcon:deselect()
	end

	print("Customize closed")
end

-- ฟังก์ชัน Toggle Customize
function CustomizeUI.toggleCustomize()
	if isCustomizeOpen then
		CustomizeUI.closeCustomize()
	else
		CustomizeUI.openCustomize()
	end
end

-- ฟังก์ชัน Initialize Customize
function CustomizeUI.init()
	-- สร้าง Customize Icon ด้วย TopbarPlus (events ถูก bind แล้วใน createCustomizeIcon)
	ensureCustomizeIcon()

	print("CustomizeUI initialized")
end

function CustomizeUI.setButtonVisible(isVisible: boolean)
	local icon = ensureCustomizeIcon()
	if icon then
		-- TopbarPlus icons ใช้ :setEnabled() แทน Visible
		icon:setEnabled(isVisible)
	end

	if not isVisible then
		isCustomizeOpen = false
	end
end

return CustomizeUI
