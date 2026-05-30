--!nocheck
local behindOffset = 125

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("TeleportDropdownUI")
if oldGui then
	oldGui:Destroy()
end

local oldEspFolder = playerGui:FindFirstChild("TeleportESP")
if oldEspFolder then
	oldEspFolder:Destroy()
end

local oldWaypointSpotFolder = workspace:FindFirstChild("TeleportWaypointSpots")
if oldWaypointSpotFolder then
	oldWaypointSpotFolder:Destroy()
end

local selectedTargetName = nil
local selectedWaypointName = nil
local waypoints = {}
local waypointOrder = {}
local waypointSpotsEnabled = false
local waypointSpotEntries = {}

local running = false
local waypointRunning = false
local activeWaypointLoopName = nil
local noclipEnabled = false
local noclipRebinding = false
local noclipKey = Enum.KeyCode.N
local noclipOriginalCollisions = {}
local vehicleFlyEnabled = false
local vehicleFlyRebinding = false
local vehicleFlyKey = Enum.KeyCode.V
local vehicleFlySpeed = 90
local vehicleFlyRoot = nil
local vehicleFlyVelocity = nil
local vehicleFlyGyro = nil
local vehicleFlySeat = nil
local vehicleFlyLastSeat = nil
local vehicleFlyNextSeatScan = 0
local espEnabled = false
local espEntries = {}
local espToggleKey = nil
local espKeybindMode = nil
local espMaxDistance = 3100
local espNamesEnabled = true
local espDistanceEnabled = true
local espHealthEnabled = true
local espPlayersEnabled = true
local espPlayersKey = nil
local espZombiesEnabled = false
local espZombiesKey = nil
local espBossOnlyEnabled = false
local espVehiclesEnabled = true
local espVehiclesKey = nil
local espCorpsesEnabled = true
local espCorpsesKey = nil
local worldEspEntries = {}
local worldEspTargets = {}
local worldEspScanTimer = 0
local chamsEnabled = false
local chamsEntries = {}
local unloaded = false
local rebinding = false
local menuKey = Enum.KeyCode.RightControl
local connections = {}
local waypointStorageFile = "dontmindthis_waypoints_" .. tostring(game.PlaceId) .. "_" .. tostring(player.UserId) .. ".json"
local persistentWaypointsEnabled = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

local function connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(connections, connection)
	return connection
end

local function getRoot(character)
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function trim(text)
	return tostring(text or ""):match("^%s*(.-)%s*$")
end

local function cframeToArray(cframe)
	return { cframe:GetComponents() }
end

local function arrayToCFrame(values)
	if type(values) ~= "table" or #values < 12 then
		return nil
	end

	local components = {}

	for index = 1, 12 do
		local value = tonumber(values[index])

		if not value then
			return nil
		end

		components[index] = value
	end

	return CFrame.new(
		components[1],
		components[2],
		components[3],
		components[4],
		components[5],
		components[6],
		components[7],
		components[8],
		components[9],
		components[10],
		components[11],
		components[12]
	)
end

local function uniqueLoadedWaypointName(rawName, usedNames)
	local baseName = trim(rawName)

	if baseName == "" then
		baseName = "Waypoint"
	end

	local name = baseName
	local index = 2

	while usedNames[name] do
		name = baseName .. " " .. index
		index += 1
	end

	usedNames[name] = true
	return name
end

local function saveWaypointsToDisk()
	if not persistentWaypointsEnabled then
		return false, "file saving unsupported"
	end

	local payload = {
		version = 1,
		placeId = game.PlaceId,
		userId = player.UserId,
		waypoints = {},
	}

	for _, name in ipairs(waypointOrder) do
		local waypoint = waypoints[name]

		if waypoint and waypoint.cframe then
			table.insert(payload.waypoints, {
				name = name,
				cframe = cframeToArray(waypoint.cframe),
			})
		end
	end

	local encodeSuccess, encoded = pcall(function()
		return HttpService:JSONEncode(payload)
	end)

	if not encodeSuccess then
		return false, "could not encode waypoints"
	end

	local writeSuccess = pcall(function()
		writefile(waypointStorageFile, encoded)
	end)

	if not writeSuccess then
		return false, "could not write waypoint file"
	end

	return true, "saved"
end

local function loadWaypointsFromDisk()
	if not persistentWaypointsEnabled then
		return false, 0, "File saving unsupported; waypoints are session-only."
	end

	local existsSuccess, exists = pcall(function()
		return isfile(waypointStorageFile)
	end)

	if not existsSuccess or not exists then
		return true, 0, "Persistent waypoints ready. No saved waypoints yet."
	end

	local readSuccess, contents = pcall(function()
		return readfile(waypointStorageFile)
	end)

	if not readSuccess or type(contents) ~= "string" then
		return false, 0, "Saved waypoint file could not be read."
	end

	local decodeSuccess, payload = pcall(function()
		return HttpService:JSONDecode(contents)
	end)

	if not decodeSuccess or type(payload) ~= "table" or type(payload.waypoints) ~= "table" then
		return false, 0, "Saved waypoint file is invalid."
	end

	local loadedWaypoints = {}
	local loadedOrder = {}
	local usedNames = {}

	for _, savedWaypoint in ipairs(payload.waypoints) do
		if type(savedWaypoint) == "table" then
			local cframe = arrayToCFrame(savedWaypoint.cframe)

			if cframe then
				local name = uniqueLoadedWaypointName(savedWaypoint.name, usedNames)
				loadedWaypoints[name] = {
					cframe = cframe,
				}
				table.insert(loadedOrder, name)
			end
		end
	end

	waypoints = loadedWaypoints
	waypointOrder = loadedOrder

	if #waypointOrder == 1 then
		return true, 1, "Loaded 1 saved waypoint."
	end

	return true, #waypointOrder, "Loaded " .. tostring(#waypointOrder) .. " saved waypoints."
end

local colors = {
	panel = Color3.fromRGB(9, 20, 38),
	sidebar = Color3.fromRGB(13, 28, 54),
	content = Color3.fromRGB(15, 37, 74),
	card = Color3.fromRGB(12, 27, 52),
	button = Color3.fromRGB(37, 87, 165),
	buttonDark = Color3.fromRGB(23, 58, 112),
	accent = Color3.fromRGB(75, 112, 255),
	orange = Color3.fromRGB(210, 104, 76),
	text = Color3.fromRGB(245, 248, 255),
	muted = Color3.fromRGB(170, 187, 215),
	green = Color3.fromRGB(50, 160, 105),
	red = Color3.fromRGB(190, 70, 80),
	stroke = Color3.fromRGB(85, 130, 220),
}

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = instance
end

local function addStroke(instance, color, thickness, transparency)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0.35
	stroke.Parent = instance
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "TeleportDropdownUI"
screenGui.ResetOnSpawn = false
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

local espFolder = Instance.new("Folder")
espFolder.Name = "TeleportESP"
espFolder.Parent = playerGui

local waypointSpotFolder = Instance.new("Folder")
waypointSpotFolder.Name = "TeleportWaypointSpots"
waypointSpotFolder.Parent = workspace

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 720, 0, 520)
mainFrame.Position = UDim2.new(0.5, -360, 0.5, -260)
mainFrame.BackgroundColor3 = colors.panel
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui
addCorner(mainFrame, 18)
addStroke(mainFrame, colors.stroke, 1, 0.3)

local sidebar = Instance.new("Frame")
sidebar.Size = UDim2.new(0, 138, 1, 0)
sidebar.BackgroundColor3 = colors.sidebar
sidebar.BorderSizePixel = 0
sidebar.Parent = mainFrame

local contentFrame = Instance.new("Frame")
contentFrame.Size = UDim2.new(1, -138, 1, 0)
contentFrame.Position = UDim2.new(0, 138, 0, 0)
contentFrame.BackgroundColor3 = colors.content
contentFrame.BorderSizePixel = 0
contentFrame.Parent = mainFrame

local controlHoverCount = 0

local function markControl(gui)
	gui.Active = true

	connect(gui.MouseEnter, function()
		controlHoverCount += 1
	end)

	connect(gui.MouseLeave, function()
		controlHoverCount = math.max(0, controlHoverCount - 1)
	end)
end

local dragging = false
local dragStart = nil
local startPos = nil

local function beginDrag(input)
	if unloaded or rebinding or controlHoverCount > 0 then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = mainFrame.Position

		connect(input.Changed, function()
			if input.UserInputState == Enum.UserInputState.End then
				dragging = false
			end
		end)
	end
end

local function addDragArea(gui)
	gui.Active = true
	connect(gui.InputBegan, beginDrag)
end

connect(UserInputService.InputChanged, function(input)
	if not dragging or unloaded then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		local delta = input.Position - dragStart

		mainFrame.Position = UDim2.new(
			startPos.X.Scale,
			startPos.X.Offset + delta.X,
			startPos.Y.Scale,
			startPos.Y.Offset + delta.Y
		)
	end
end)

addDragArea(mainFrame)
addDragArea(sidebar)
addDragArea(contentFrame)

local function createLabel(parent, text, position, size, textSize, color)
	local label = Instance.new("TextLabel")
	label.Size = size
	label.Position = position
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or colors.text
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize or 16
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = parent
	addDragArea(label)
	return label
end

local function createButton(parent, text, position, size, bgColor)
	local button = Instance.new("TextButton")
	button.Size = size
	button.Position = position
	button.BackgroundColor3 = bgColor or colors.button
	button.BorderSizePixel = 0
	button.Text = text
	button.TextColor3 = colors.text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.AutoButtonColor = true
	button.Parent = parent
	addCorner(button, 10)
	addStroke(button, Color3.fromRGB(120, 155, 230), 1, 0.65)
	markControl(button)
	return button
end

local function createTextBox(parent, text, placeholder, position, size)
	local box = Instance.new("TextBox")
	box.Size = size
	box.Position = position
	box.BackgroundColor3 = colors.buttonDark
	box.BorderSizePixel = 0
	box.Text = text or ""
	box.PlaceholderText = placeholder or ""
	box.TextColor3 = colors.text
	box.PlaceholderColor3 = colors.muted
	box.Font = Enum.Font.Gotham
	box.TextSize = 14
	box.ClearTextOnFocus = false
	box.Parent = parent
	addCorner(box, 10)
	addStroke(box, Color3.fromRGB(120, 155, 230), 1, 0.75)
	markControl(box)
	return box
end

local function createSettingCard(parent, title, position, size)
	local card = Instance.new("Frame")
	card.Size = size
	card.Position = position
	card.BackgroundColor3 = colors.card
	card.BorderSizePixel = 0
	card.Parent = parent
	addCorner(card, 10)
	addStroke(card, Color3.fromRGB(72, 101, 160), 1, 0.72)
	addDragArea(card)

	local dot = Instance.new("Frame")
	dot.Size = UDim2.new(0, 12, 0, 12)
	dot.Position = UDim2.new(0, 12, 0, 12)
	dot.BackgroundColor3 = colors.orange
	dot.BorderSizePixel = 0
	dot.Parent = card
	addCorner(dot, 6)
	addDragArea(dot)

	local titleLabel = createLabel(card, title, UDim2.new(0, 32, 0, 4), UDim2.new(1, -44, 0, 28), 14, colors.text)
	titleLabel.Font = Enum.Font.GothamBold

	local divider = Instance.new("Frame")
	divider.Size = UDim2.new(1, -24, 0, 1)
	divider.Position = UDim2.new(0, 12, 0, 34)
	divider.BackgroundColor3 = Color3.fromRGB(52, 72, 108)
	divider.BackgroundTransparency = 0.35
	divider.BorderSizePixel = 0
	divider.Parent = card
	addDragArea(divider)

	return card
end

local function keyName(keyCode)
	return keyCode and keyCode.Name or "NONE"
end

local function setToggleVisual(button, enabled)
	button.Text = enabled and "ON" or "OFF"
	button.BackgroundColor3 = enabled and colors.orange or Color3.fromRGB(45, 54, 70)
end

local function createToggleRow(parent, labelText, y, enabled, x, width)
	local rowX = x or 14
	local rowWidth = width
	local buttonPosition = rowWidth and UDim2.new(0, rowX + rowWidth - 46, 0, y) or UDim2.new(1, -60, 0, y)
	local labelSize = rowWidth and UDim2.new(0, rowWidth - 56, 0, 22) or UDim2.new(1, -78, 0, 22)
	local label = createLabel(parent, labelText, UDim2.new(0, rowX, 0, y), labelSize, 12, colors.text)
	label.Font = Enum.Font.Gotham

	local button = Instance.new("TextButton")
	button.Size = UDim2.new(0, 46, 0, 22)
	button.Position = buttonPosition
	button.BorderSizePixel = 0
	button.TextColor3 = colors.text
	button.Font = Enum.Font.GothamBold
	button.TextSize = 11
	button.AutoButtonColor = true
	button.Parent = parent
	addCorner(button, 11)
	markControl(button)
	setToggleVisual(button, enabled)

	return button
end

local function createKeyRow(parent, labelText, y, x, width)
	local rowX = x or 14
	local rowWidth = width
	local buttonPosition = rowWidth and UDim2.new(0, rowX + rowWidth - 70, 0, y) or UDim2.new(1, -84, 0, y)
	local labelSize = rowWidth and UDim2.new(0, rowWidth - 78, 0, 22) or UDim2.new(1, -112, 0, 22)
	local label = createLabel(parent, labelText, UDim2.new(0, rowX, 0, y), labelSize, 12, colors.text)
	label.Font = Enum.Font.GothamBold

	local button = createButton(parent, "NONE", buttonPosition, UDim2.new(0, 70, 0, 22), colors.buttonDark)
	button.TextSize = 11
	return button
end

local function createDistanceSlider(parent, y)
	local minDistance = 100
	local maxDistance = 5000

	local label = createLabel(parent, "Max Distance", UDim2.new(0, 14, 0, y), UDim2.new(0, 120, 0, 22), 13, colors.text)
	label.Font = Enum.Font.GothamBold

	local valueLabel = createLabel(parent, tostring(espMaxDistance) .. " studs", UDim2.new(1, -118, 0, y), UDim2.new(0, 104, 0, 22), 12, colors.muted)
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Font = Enum.Font.Gotham

	local track = Instance.new("Frame")
	track.Size = UDim2.new(1, -28, 0, 4)
	track.Position = UDim2.new(0, 14, 0, y + 28)
	track.BackgroundColor3 = Color3.fromRGB(50, 59, 78)
	track.BorderSizePixel = 0
	track.Parent = parent
	addCorner(track, 2)
	markControl(track)

	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = colors.orange
	fill.BorderSizePixel = 0
	fill.Parent = track
	addCorner(fill, 2)

	local knob = Instance.new("TextButton")
	knob.Size = UDim2.new(0, 12, 0, 12)
	knob.BackgroundColor3 = colors.text
	knob.BorderSizePixel = 0
	knob.Text = ""
	knob.AutoButtonColor = false
	knob.Parent = track
	addCorner(knob, 6)
	markControl(knob)

	local draggingSlider = false

	local function updateVisual()
		local alpha = math.clamp((espMaxDistance - minDistance) / (maxDistance - minDistance), 0, 1)
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, -6, 0.5, -6)
		valueLabel.Text = tostring(espMaxDistance) .. " studs"
	end

	local function setFromX(x)
		local width = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		local rawDistance = minDistance + ((maxDistance - minDistance) * alpha)
		espMaxDistance = math.floor((rawDistance / 50) + 0.5) * 50
		updateVisual()
	end

	connect(track.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSlider = true
			setFromX(input.Position.X)
		end
	end)

	connect(knob.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSlider = true
		end
	end)

	connect(UserInputService.InputChanged, function(input)
		if not draggingSlider then
			return
		end

		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			setFromX(input.Position.X)
		end
	end)

	connect(UserInputService.InputEnded, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			draggingSlider = false
		end
	end)

	updateVisual()
	return updateVisual
end

local sideTitle = createLabel(sidebar, "Teleport", UDim2.new(0, 18, 0, 18), UDim2.new(1, -30, 0, 30), 19)
local sideSub = createLabel(sidebar, "Control panel", UDim2.new(0, 18, 0, 44), UDim2.new(1, -30, 0, 22), 12, colors.muted)
sideSub.Font = Enum.Font.Gotham

local tpTab = createButton(sidebar, "TP", UDim2.new(0, 14, 0, 92), UDim2.new(1, -28, 0, 44), colors.accent)
local waypointTab = createButton(sidebar, "Waypoints", UDim2.new(0, 14, 0, 146), UDim2.new(1, -28, 0, 44), colors.buttonDark)
local playerTab = createButton(sidebar, "Player", UDim2.new(0, 14, 0, 200), UDim2.new(1, -28, 0, 44), colors.buttonDark)
local settingsTab = createButton(sidebar, "Settings", UDim2.new(0, 14, 0, 254), UDim2.new(1, -28, 0, 44), colors.buttonDark)

local headerTitle = createLabel(contentFrame, "Player Teleport", UDim2.new(0, 26, 0, 18), UDim2.new(1, -52, 0, 30), 21)
local headerSub = createLabel(contentFrame, "Pick a player, set distance, then start.", UDim2.new(0, 26, 0, 46), UDim2.new(1, -52, 0, 22), 12, colors.muted)
headerSub.Font = Enum.Font.Gotham

local pageHolder = Instance.new("Frame")
pageHolder.Size = UDim2.new(1, 0, 1, -78)
pageHolder.Position = UDim2.new(0, 0, 0, 78)
pageHolder.BackgroundTransparency = 1
pageHolder.Parent = contentFrame
addDragArea(pageHolder)

local function createPage()
	local page = Instance.new("Frame")
	page.Size = UDim2.new(1, 0, 1, 0)
	page.BackgroundTransparency = 1
	page.Visible = false
	page.Parent = pageHolder
	addDragArea(page)
	return page
end

local tpPage = createPage()
local waypointPage = createPage()
local playerPage = createPage()
local settingsPage = createPage()

local dropdowns = {}

local function closeAllDropdowns(except)
	for _, dropdown in ipairs(dropdowns) do
		if dropdown ~= except then
			dropdown:SetOpen(false)
		end
	end
end

local function createDropdown(parent, labelText, x, y, width, placeholder)
	createLabel(parent, labelText, UDim2.new(0, x, 0, y), UDim2.new(0, width, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold

	local button = createButton(parent, placeholder, UDim2.new(0, x, 0, y + 26), UDim2.new(0, width, 0, 40), colors.buttonDark)

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(0, width, 0, 0)
	list.Position = UDim2.new(0, x, 0, y + 70)
	list.BackgroundColor3 = Color3.fromRGB(11, 27, 55)
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 4
	list.Visible = false
	list.CanvasSize = UDim2.new(0, 0, 0, 0)
	list.Parent = parent
	addCorner(list, 10)
	addStroke(list, Color3.fromRGB(120, 155, 230), 1, 0.65)
	markControl(list)

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 5)
	padding.PaddingBottom = UDim.new(0, 5)
	padding.PaddingLeft = UDim.new(0, 5)
	padding.PaddingRight = UDim.new(0, 5)
	padding.Parent = list

	local dropdown = {
		Button = button,
		List = list,
		OptionCount = 1,
		OnBeforeOpen = nil,
	}

	function dropdown:SetText(text)
		self.Button.Text = text
	end

	function dropdown:SetOpen(open)
		if open then
			closeAllDropdowns(self)
			local height = math.min(132, math.max(40, self.OptionCount * 38 + 10))
			self.List.Visible = true
			self.List.Size = UDim2.new(0, width, 0, height)
		else
			self.List.Visible = false
			self.List.Size = UDim2.new(0, width, 0, 0)
		end
	end

	function dropdown:Clear()
		for _, child in ipairs(self.List:GetChildren()) do
			if child ~= layout and child ~= padding then
				child:Destroy()
			end
		end
	end

	function dropdown:Populate(items, onSelect, emptyText)
		controlHoverCount = 0
		self:Clear()

		if #items == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, -2, 0, 32)
			empty.BackgroundTransparency = 1
			empty.Text = emptyText or "Nothing found"
			empty.TextColor3 = colors.muted
			empty.Font = Enum.Font.Gotham
			empty.TextSize = 13
			empty.Parent = self.List

			self.OptionCount = 1
			self.List.CanvasSize = UDim2.new(0, 0, 0, 42)
			return
		end

		for index, item in ipairs(items) do
			local option = Instance.new("TextButton")
			option.Size = UDim2.new(1, -2, 0, 34)
			option.BackgroundColor3 = colors.buttonDark
			option.BorderSizePixel = 0
			option.Text = item
			option.TextColor3 = colors.text
			option.Font = Enum.Font.Gotham
			option.TextSize = 13
			option.LayoutOrder = index
			option.Parent = self.List
			addCorner(option, 8)
			markControl(option)

			connect(option.MouseButton1Click, function()
				onSelect(item)
				self:SetOpen(false)
			end)
		end

		self.OptionCount = #items
		self.List.CanvasSize = UDim2.new(0, 0, 0, #items * 38 + 10)

		if self.List.Visible then
			self:SetOpen(true)
		end
	end

	connect(button.MouseButton1Click, function()
		if dropdown.OnBeforeOpen then
			dropdown.OnBeforeOpen()
		end

		dropdown:SetOpen(not dropdown.List.Visible)
	end)

	table.insert(dropdowns, dropdown)
	return dropdown
end

local playerDropdown = createDropdown(tpPage, "Player", 26, 12, 250, "Choose player")
createLabel(tpPage, "Distance", UDim2.new(0, 296, 0, 12), UDim2.new(0, 110, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold
local distanceBox = createTextBox(tpPage, tostring(behindOffset), "125", UDim2.new(0, 296, 0, 38), UDim2.new(0, 100, 0, 40))
local startButton = createButton(tpPage, "Start", UDim2.new(0, 296, 0, 96), UDim2.new(0, 100, 0, 42), colors.green)
local tpStatus = createLabel(tpPage, "Ready.", UDim2.new(0, 26, 0, 250), UDim2.new(0, 370, 0, 30), 12, colors.muted)
tpStatus.Font = Enum.Font.Gotham

local waypointNameBox = createTextBox(waypointPage, "", "Waypoint name", UDim2.new(0, 26, 0, 38), UDim2.new(0, 230, 0, 40))
createLabel(waypointPage, "New waypoint", UDim2.new(0, 26, 0, 12), UDim2.new(0, 230, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold
local saveWaypointButton = createButton(waypointPage, "Save Current", UDim2.new(0, 270, 0, 38), UDim2.new(0, 126, 0, 40), colors.green)

local waypointDropdown = createDropdown(waypointPage, "Saved waypoints", 26, 104, 260, "Choose waypoint")
local waypointSpotsButton = createButton(waypointPage, "Render Spots: Off", UDim2.new(0, 302, 0, 130), UDim2.new(0, 126, 0, 42), colors.buttonDark)
local teleportWaypointButton = createButton(waypointPage, "Teleport", UDim2.new(0, 26, 0, 220), UDim2.new(0, 126, 0, 42), colors.accent)
local deleteWaypointButton = createButton(waypointPage, "Delete", UDim2.new(0, 164, 0, 220), UDim2.new(0, 126, 0, 42), colors.red)
local waypointStatus = createLabel(waypointPage, "No waypoints saved.", UDim2.new(0, 26, 0, 274), UDim2.new(0, 360, 0, 26), 12, colors.muted)
waypointStatus.Font = Enum.Font.Gotham

local movementCard = createSettingCard(playerPage, "Movement", UDim2.new(0, 18, 0, 8), UDim2.new(0, 530, 0, 84))
local noclipButton = createButton(movementCard, "Noclip: Off", UDim2.new(0, 14, 0, 42), UDim2.new(0, 130, 0, 30), colors.buttonDark)
local noclipKeybindButton = createButton(movementCard, "Key: N", UDim2.new(0, 154, 0, 42), UDim2.new(0, 96, 0, 30), colors.buttonDark)
local vehicleFlyButton = createButton(movementCard, "Car Fly: Off", UDim2.new(0, 262, 0, 42), UDim2.new(0, 122, 0, 30), colors.buttonDark)
local vehicleFlyKeybindButton = createButton(movementCard, "Key: V", UDim2.new(0, 394, 0, 42), UDim2.new(0, 70, 0, 30), colors.buttonDark)
local vehicleFlySpeedBox = createTextBox(movementCard, tostring(vehicleFlySpeed), "Speed", UDim2.new(0, 474, 0, 42), UDim2.new(0, 42, 0, 30))
vehicleFlySpeedBox.TextSize = 12

local espGeneralCard = createSettingCard(playerPage, "General", UDim2.new(0, 18, 0, 106), UDim2.new(0, 260, 0, 132))
local espButton = createToggleRow(espGeneralCard, "Enable ESP", 44, espEnabled)
local espToggleKeyButton = createKeyRow(espGeneralCard, "ESP Toggle Key", 70)
local updateEspDistanceSlider = createDistanceSlider(espGeneralCard, 96)

local espDisplayCard = createSettingCard(playerPage, "Display", UDim2.new(0, 294, 0, 106), UDim2.new(0, 254, 0, 132))
local chamsButton = createToggleRow(espDisplayCard, "Chams", 42, chamsEnabled)
local espNamesButton = createToggleRow(espDisplayCard, "Names", 66, espNamesEnabled)
local espDistanceButton = createToggleRow(espDisplayCard, "Distance", 90, espDistanceEnabled)
local espHealthButton = createToggleRow(espDisplayCard, "Health", 114, espHealthEnabled)

local espCategoryCard = createSettingCard(playerPage, "Category Toggles", UDim2.new(0, 18, 0, 252), UDim2.new(0, 530, 0, 158))
local espPlayersButton = createToggleRow(espCategoryCard, "Players", 40, espPlayersEnabled, 14, 228)
local espPlayersKeyButton = createKeyRow(espCategoryCard, "Players Toggle Key", 66, 14, 228)
local espZombiesButton = createToggleRow(espCategoryCard, "Zombies", 92, espZombiesEnabled, 14, 228)
local espZombiesKeyButton = createKeyRow(espCategoryCard, "Zombies Toggle Key", 118, 14, 228)
local espBossOnlyButton = createToggleRow(espCategoryCard, "Boss Only", 132, espBossOnlyEnabled, 14, 228)
local espVehiclesButton = createToggleRow(espCategoryCard, "Vehicles", 40, espVehiclesEnabled, 274, 228)
local espVehiclesKeyButton = createKeyRow(espCategoryCard, "Vehicles Toggle Key", 66, 274, 228)
local espCorpsesButton = createToggleRow(espCategoryCard, "Corpses", 92, espCorpsesEnabled, 274, 228)
local espCorpsesKeyButton = createKeyRow(espCategoryCard, "Corpses Toggle Key", 118, 274, 228)

local playerStatus = createLabel(playerPage, "ESP is subtle: small scaling text, side health, and optional chams.", UDim2.new(0, 18, 0, 418), UDim2.new(0, 530, 0, 26), 12, colors.muted)
playerStatus.Font = Enum.Font.Gotham

createLabel(settingsPage, "Menu keybind", UDim2.new(0, 26, 0, 18), UDim2.new(0, 250, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold
local keybindButton = createButton(settingsPage, "Hide / Show: RightControl", UDim2.new(0, 26, 0, 48), UDim2.new(0, 230, 0, 42), colors.buttonDark)
local unloadButton = createButton(settingsPage, "Unload", UDim2.new(0, 26, 0, 204), UDim2.new(0, 160, 0, 42), colors.red)
local settingsStatus = createLabel(settingsPage, "Press the keybind to hide or show this menu.", UDim2.new(0, 26, 0, 106), UDim2.new(0, 360, 0, 36), 12, colors.muted)
settingsStatus.Font = Enum.Font.Gotham

local pages = {
	TP = tpPage,
	Waypoints = waypointPage,
	Player = playerPage,
	Settings = settingsPage,
}

local tabButtons = {
	TP = tpTab,
	Waypoints = waypointTab,
	Player = playerTab,
	Settings = settingsTab,
}

local function setTab(tabName)
	closeAllDropdowns()
	controlHoverCount = 0

	for name, page in pairs(pages) do
		page.Visible = name == tabName
	end

	for name, button in pairs(tabButtons) do
		button.BackgroundColor3 = name == tabName and colors.accent or colors.buttonDark
	end

	if tabName == "TP" then
		headerTitle.Text = "Player Teleport"
		headerSub.Text = "Pick a player, set distance, then start."
	elseif tabName == "Waypoints" then
		headerTitle.Text = "Waypoints"
		headerSub.Text = "Save positions and teleport back later."
	elseif tabName == "Player" then
		headerTitle.Text = "Player"
		headerSub.Text = "Toggle movement helpers and ESP."
	else
		headerTitle.Text = "Settings"
		headerSub.Text = "Rebind the menu toggle or unload the script."
	end
end

local function stopTeleport()
	running = false

	if unloaded then
		return
	end

	startButton.Text = "Start"
	startButton.BackgroundColor3 = colors.green
end

local function stopWaypointTeleport()
	waypointRunning = false
	activeWaypointLoopName = nil

	if unloaded then
		return
	end

	teleportWaypointButton.Text = "Teleport"
	teleportWaypointButton.BackgroundColor3 = colors.accent
end

local function clearWaypointSpot(name)
	local entry = waypointSpotEntries[name]
	if not entry then
		return
	end

	if entry.marker then
		entry.marker:Destroy()
	end

	waypointSpotEntries[name] = nil
end

local function clearWaypointSpots()
	for _, entry in pairs(waypointSpotEntries) do
		if entry.marker then
			entry.marker:Destroy()
		end
	end

	waypointSpotEntries = {}
end

local function createWaypointSpot(name)
	local waypoint = waypoints[name]
	if not waypoint or not waypoint.cframe then
		return
	end

	clearWaypointSpot(name)

	local marker = Instance.new("Part")
	marker.Name = "WaypointSpot_" .. name
	marker.Size = Vector3.new(0.2, 0.2, 0.2)
	marker.CFrame = waypoint.cframe
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.Transparency = 1
	marker.Parent = waypointSpotFolder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "WaypointLabel"
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 100000
	billboard.Size = UDim2.new(0, 110, 0, 34)
	billboard.StudsOffset = Vector3.new(0, 1.25, 0)
	billboard.Adornee = marker
	billboard.Parent = marker

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 18)
	nameLabel.Position = UDim2.new(0, 0, 0, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.TextColor3 = colors.text
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 10
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.Parent = billboard

	local diamond = Instance.new("Frame")
	diamond.Size = UDim2.new(0, 9, 0, 9)
	diamond.Position = UDim2.new(0.5, -4, 0, 21)
	diamond.BackgroundColor3 = colors.accent
	diamond.BackgroundTransparency = 0.05
	diamond.BorderSizePixel = 0
	diamond.Rotation = 45
	diamond.Parent = billboard
	addStroke(diamond, colors.text, 1, 0.45)

	waypointSpotEntries[name] = {
		marker = marker,
		nameLabel = nameLabel,
	}
end

local function refreshWaypointSpots()
	if not waypointSpotsEnabled then
		return
	end

	local validNames = {}

	for _, name in ipairs(waypointOrder) do
		if waypoints[name] then
			validNames[name] = true

			if waypointSpotEntries[name] then
				waypointSpotEntries[name].marker.CFrame = waypoints[name].cframe
			else
				createWaypointSpot(name)
			end
		end
	end

	for name in pairs(waypointSpotEntries) do
		if not validNames[name] then
			clearWaypointSpot(name)
		end
	end
end

local function updateWaypointSpotDistances()
	if not waypointSpotsEnabled then
		return
	end

	for name, entry in pairs(waypointSpotEntries) do
		local waypoint = waypoints[name]

		if not waypoint or not waypoint.cframe then
			clearWaypointSpot(name)
		elseif entry.marker then
			entry.marker.CFrame = waypoint.cframe
		end
	end
end

local function setWaypointSpotsEnabled(enabled)
	waypointSpotsEnabled = enabled
	waypointSpotsButton.Text = enabled and "Render Spots: On" or "Render Spots: Off"
	waypointSpotsButton.BackgroundColor3 = enabled and colors.green or colors.buttonDark

	if enabled then
		refreshWaypointSpots()
		waypointStatus.Text = "Waypoint spots enabled."
	else
		clearWaypointSpots()
		waypointStatus.Text = "Waypoint spots disabled."
	end
end

local function applyNoclip()
	if not noclipEnabled then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			if noclipOriginalCollisions[descendant] == nil then
				noclipOriginalCollisions[descendant] = descendant.CanCollide
			end

			descendant.CanCollide = false
		end
	end
end

local function setNoclipEnabled(enabled)
	noclipEnabled = enabled

	if not enabled then
		for part, originalCanCollide in pairs(noclipOriginalCollisions) do
			if part and part.Parent then
				part.CanCollide = originalCanCollide
			end
		end

		noclipOriginalCollisions = {}
	end

	noclipButton.Text = enabled and "Noclip: On" or "Noclip: Off"
	noclipButton.BackgroundColor3 = enabled and colors.green or colors.buttonDark
	playerStatus.Text = enabled and "Noclip enabled." or "Noclip disabled."
end

local function updateNoclipKeybindButton()
	if noclipRebinding then
		noclipKeybindButton.Text = "Press a key..."
	else
		noclipKeybindButton.Text = "Key: " .. noclipKey.Name
	end
end

local function clearVehicleFlyForces()
	if vehicleFlyVelocity then
		vehicleFlyVelocity:Destroy()
		vehicleFlyVelocity = nil
	end

	if vehicleFlyGyro then
		vehicleFlyGyro:Destroy()
		vehicleFlyGyro = nil
	end

	if vehicleFlyRoot and vehicleFlyRoot.Parent then
		vehicleFlyRoot.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		vehicleFlyRoot.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end

	vehicleFlyRoot = nil
	vehicleFlySeat = nil
end

local function getSeatedVehicleRoot()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local seatPart = humanoid and humanoid.SeatPart

	if not seatPart and vehicleFlyLastSeat and vehicleFlyLastSeat.Parent and vehicleFlyLastSeat.Occupant == humanoid then
		seatPart = vehicleFlyLastSeat
	end

	if not seatPart and os.clock() >= vehicleFlyNextSeatScan then
		vehicleFlyNextSeatScan = os.clock() + 0.45

		for _, descendant in ipairs(workspace:GetDescendants()) do
			if descendant:IsA("VehicleSeat") and descendant.Occupant == humanoid then
				seatPart = descendant
				vehicleFlyLastSeat = descendant
				break
			end
		end
	end

	if not seatPart or not seatPart:IsA("BasePart") then
		return nil, nil
	end

	vehicleFlyLastSeat = seatPart
	return seatPart.AssemblyRootPart or seatPart, seatPart
end

local function ensureVehicleFlyForces(root, seatPart)
	if vehicleFlyRoot ~= root then
		clearVehicleFlyForces()
		vehicleFlyRoot = root
		vehicleFlySeat = seatPart
	end

	if vehicleFlySeat ~= seatPart then
		vehicleFlySeat = seatPart
	end

	if not vehicleFlyVelocity then
		vehicleFlyVelocity = Instance.new("BodyVelocity")
		vehicleFlyVelocity.Name = "VehicleFlyVelocity"
		vehicleFlyVelocity.MaxForce = Vector3.new(1000000000, 1000000000, 1000000000)
		vehicleFlyVelocity.P = 50000
		vehicleFlyVelocity.Velocity = Vector3.new(0, 0, 0)
		vehicleFlyVelocity.Parent = root
	end

	if not vehicleFlyGyro then
		vehicleFlyGyro = Instance.new("BodyGyro")
		vehicleFlyGyro.Name = "VehicleFlyGyro"
		vehicleFlyGyro.MaxTorque = Vector3.new(1000000000, 1000000000, 1000000000)
		vehicleFlyGyro.P = 50000
		vehicleFlyGyro.D = 900
		vehicleFlyGyro.CFrame = root.CFrame
		vehicleFlyGyro.Parent = root
	end

	pcall(function()
		root:SetNetworkOwner(player)
	end)
end

local function updateVehicleFlyKeybindButton()
	if vehicleFlyRebinding then
		vehicleFlyKeybindButton.Text = "Press..."
	else
		vehicleFlyKeybindButton.Text = "Key: " .. vehicleFlyKey.Name
	end
end

local function setVehicleFlyEnabled(enabled)
	vehicleFlyEnabled = enabled

	if not enabled then
		clearVehicleFlyForces()
	end

	vehicleFlyButton.Text = enabled and "Car Fly: On" or "Car Fly: Off"
	vehicleFlyButton.BackgroundColor3 = enabled and colors.green or colors.buttonDark
	playerStatus.Text = enabled and "Car fly enabled. Sit in a vehicle and use WASD, Space, and Ctrl/Q." or "Car fly disabled."
end

local function updateVehicleFly(deltaTime)
	if not vehicleFlyEnabled then
		return
	end

	local root, seatPart = getSeatedVehicleRoot()
	if not root then
		clearVehicleFlyForces()
		return
	end

	ensureVehicleFlyForces(root, seatPart)

	local camera = workspace.CurrentCamera
	local cameraCFrame = camera and camera.CFrame or root.CFrame
	local forward = Vector3.new(cameraCFrame.LookVector.X, 0, cameraCFrame.LookVector.Z)
	local right = Vector3.new(cameraCFrame.RightVector.X, 0, cameraCFrame.RightVector.Z)
	local movement = Vector3.new(0, 0, 0)

	if forward.Magnitude < 0.01 then
		forward = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	end

	if right.Magnitude < 0.01 then
		right = Vector3.new(root.CFrame.RightVector.X, 0, root.CFrame.RightVector.Z)
	end

	forward = forward.Magnitude > 0 and forward.Unit or Vector3.new(0, 0, -1)
	right = right.Magnitude > 0 and right.Unit or Vector3.new(1, 0, 0)

	if UserInputService:IsKeyDown(Enum.KeyCode.W) then
		movement += forward
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.S) then
		movement -= forward
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.D) then
		movement += right
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.A) then
		movement -= right
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsKeyDown(Enum.KeyCode.E) then
		movement += Vector3.new(0, 1, 0)
	end

	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q) then
		movement -= Vector3.new(0, 1, 0)
	end

	local targetVelocity = Vector3.new(0, 0, 0)

	if movement.Magnitude > 0 then
		targetVelocity = movement.Unit * vehicleFlySpeed
	end

	vehicleFlyVelocity.Velocity = targetVelocity
	root.AssemblyLinearVelocity = targetVelocity
	root.AssemblyAngularVelocity = Vector3.new(0, 0, 0)

	if seatPart and seatPart.Parent then
		seatPart.AssemblyLinearVelocity = targetVelocity
		seatPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end

	local step = math.clamp(deltaTime or 0.016, 0, 0.05)
	local nextPosition = root.Position + (targetVelocity * step)
	local targetCFrame = CFrame.lookAt(nextPosition, nextPosition + forward, Vector3.new(0, 1, 0))

	vehicleFlyGyro.CFrame = targetCFrame
	root.CFrame = targetCFrame
end

local clearWorldEsp
local clearChams

local function clearEspEntry(targetPlayer)
	local entry = espEntries[targetPlayer]
	if not entry then
		return
	end

	if entry.billboard then
		entry.billboard:Destroy()
	end

	if entry.nameBillboard then
		entry.nameBillboard:Destroy()
	end

	if entry.distanceBillboard then
		entry.distanceBillboard:Destroy()
	end

	if entry.healthBillboard then
		entry.healthBillboard:Destroy()
	end

	espEntries[targetPlayer] = nil
end

local function clearEsp()
	for _, entry in pairs(espEntries) do
		if entry.billboard then
			entry.billboard:Destroy()
		end

		if entry.nameBillboard then
			entry.nameBillboard:Destroy()
		end

		if entry.distanceBillboard then
			entry.distanceBillboard:Destroy()
		end

		if entry.healthBillboard then
			entry.healthBillboard:Destroy()
		end
	end

	espEntries = {}
end

local function getEspTextSize(distance)
	local cappedDistance = math.clamp(distance, 0, 220)
	return math.floor(math.clamp(11 - (cappedDistance / 70), 8, 11) + 0.5)
end

local function createEspEntry(targetPlayer)
	if targetPlayer == player or espEntries[targetPlayer] then
		return
	end

	local nameBillboard = Instance.new("BillboardGui")
	nameBillboard.Name = "ESP_Name_" .. targetPlayer.Name
	nameBillboard.AlwaysOnTop = true
	nameBillboard.Enabled = false
	nameBillboard.MaxDistance = 10000
	nameBillboard.Size = UDim2.new(0, 90, 0, 16)
	nameBillboard.StudsOffset = Vector3.new(0, 2.85, 0)
	nameBillboard.Parent = espFolder

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = targetPlayer.Name
	nameLabel.TextColor3 = colors.text
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 9
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.Parent = nameBillboard

	local distanceBillboard = Instance.new("BillboardGui")
	distanceBillboard.Name = "ESP_Distance_" .. targetPlayer.Name
	distanceBillboard.AlwaysOnTop = true
	distanceBillboard.Enabled = false
	distanceBillboard.MaxDistance = 10000
	distanceBillboard.Size = UDim2.new(0, 80, 0, 14)
	distanceBillboard.StudsOffset = Vector3.new(0, -2.65, 0)
	distanceBillboard.Parent = espFolder

	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Size = UDim2.new(1, 0, 1, 0)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.Text = "..."
	distanceLabel.TextColor3 = colors.muted
	distanceLabel.Font = Enum.Font.GothamBold
	distanceLabel.TextSize = 8
	distanceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	distanceLabel.TextStrokeTransparency = 0.35
	distanceLabel.Parent = distanceBillboard

	local healthBillboard = Instance.new("BillboardGui")
	healthBillboard.Name = "ESP_Health_" .. targetPlayer.Name
	healthBillboard.AlwaysOnTop = true
	healthBillboard.Enabled = false
	healthBillboard.MaxDistance = 10000
	healthBillboard.Size = UDim2.new(0, 3, 0, 30)
	healthBillboard.StudsOffset = Vector3.new(1.25, 0.2, 0)
	healthBillboard.Parent = espFolder

	local healthBack = Instance.new("Frame")
	healthBack.Size = UDim2.new(1, 0, 1, 0)
	healthBack.BackgroundColor3 = Color3.fromRGB(18, 28, 45)
	healthBack.BackgroundTransparency = 0.5
	healthBack.BorderSizePixel = 0
	healthBack.Parent = healthBillboard
	addCorner(healthBack, 2)

	local healthFill = Instance.new("Frame")
	healthFill.AnchorPoint = Vector2.new(0, 1)
	healthFill.Position = UDim2.new(0, 0, 1, 0)
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = colors.green
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBack
	addCorner(healthFill, 2)

	espEntries[targetPlayer] = {
		nameBillboard = nameBillboard,
		distanceBillboard = distanceBillboard,
		healthBillboard = healthBillboard,
		nameLabel = nameLabel,
		distanceLabel = distanceLabel,
		healthFill = healthFill,
	}
end

local function setEspEntryEnabled(entry, enabled)
	if entry.nameBillboard then
		entry.nameBillboard.Enabled = enabled and espNamesEnabled
	end

	if entry.distanceBillboard then
		entry.distanceBillboard.Enabled = enabled and espDistanceEnabled
	end

	if entry.healthBillboard then
		entry.healthBillboard.Enabled = enabled and espHealthEnabled
	end
end

local function getModelRoot(model)
	if not model then
		return nil
	end

	if model:IsA("BasePart") then
		return model
	end

	if model:IsA("Model") then
		return model:FindFirstChild("HumanoidRootPart")
			or model.PrimaryPart
			or model:FindFirstChildWhichIsA("BasePart", true)
	end

	return nil
end

local function getWorldDisplayName(instance, category)
	local name = instance and instance.Name or category

	if name == "" then
		return category
	end

	return name
end

local function addWorldTarget(targets, counts, category, instance, root, humanoid, highlightObject)
	if not instance or not root or targets[instance] then
		return
	end

	if counts[category] and counts[category] >= 45 then
		return
	end

	counts[category] = (counts[category] or 0) + 1
	targets[instance] = {
		category = category,
		root = root,
		humanoid = humanoid,
		displayName = getWorldDisplayName(instance, category),
		highlightObject = highlightObject or instance,
	}
end

local function refreshWorldEspTargets()
	local targets = {}
	local counts = {
		Zombies = 0,
		Vehicles = 0,
		Corpses = 0,
	}

	if not espZombiesEnabled and not espVehiclesEnabled and not espCorpsesEnabled then
		worldEspTargets = targets
		return
	end

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant:IsA("Humanoid") then
			local model = descendant.Parent

			if model and model:IsA("Model") and not Players:GetPlayerFromCharacter(model) then
				local root = getModelRoot(model)
				local lowerName = string.lower(model.Name)
				local looksLikeCorpse = descendant.Health <= 0
					or string.find(lowerName, "corpse", 1, true) ~= nil
					or string.find(lowerName, "dead", 1, true) ~= nil
					or string.find(lowerName, "ragdoll", 1, true) ~= nil
				local looksLikeBoss = string.find(lowerName, "boss", 1, true) ~= nil
					or string.find(lowerName, "brute", 1, true) ~= nil
					or descendant.MaxHealth >= 300

				if espCorpsesEnabled and looksLikeCorpse then
					addWorldTarget(targets, counts, "Corpses", model, root, descendant, model)
				elseif espZombiesEnabled and descendant.Health > 0 and (not espBossOnlyEnabled or looksLikeBoss) then
					addWorldTarget(targets, counts, "Zombies", model, root, descendant, model)
				end
			end
		elseif espVehiclesEnabled and descendant:IsA("VehicleSeat") then
			local model = descendant:FindFirstAncestorOfClass("Model")
			local instance = model or descendant
			addWorldTarget(targets, counts, "Vehicles", instance, descendant, nil, instance)
		end
	end

	worldEspTargets = targets
end

local function clearWorldEspEntry(instance)
	local entry = worldEspEntries[instance]
	if not entry then
		return
	end

	if entry.nameBillboard then
		entry.nameBillboard:Destroy()
	end

	if entry.distanceBillboard then
		entry.distanceBillboard:Destroy()
	end

	if entry.healthBillboard then
		entry.healthBillboard:Destroy()
	end

	if entry.highlight then
		entry.highlight:Destroy()
	end

	worldEspEntries[instance] = nil
end

local function createWorldEspEntry(instance)
	if worldEspEntries[instance] then
		return
	end

	local nameBillboard = Instance.new("BillboardGui")
	nameBillboard.Name = "ESP_World_Name"
	nameBillboard.AlwaysOnTop = true
	nameBillboard.Enabled = false
	nameBillboard.MaxDistance = 10000
	nameBillboard.Size = UDim2.new(0, 90, 0, 16)
	nameBillboard.StudsOffset = Vector3.new(0, 2.7, 0)
	nameBillboard.Parent = espFolder

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 1, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = colors.text
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 9
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.TextStrokeTransparency = 0.35
	nameLabel.Parent = nameBillboard

	local distanceBillboard = Instance.new("BillboardGui")
	distanceBillboard.Name = "ESP_World_Distance"
	distanceBillboard.AlwaysOnTop = true
	distanceBillboard.Enabled = false
	distanceBillboard.MaxDistance = 10000
	distanceBillboard.Size = UDim2.new(0, 80, 0, 14)
	distanceBillboard.StudsOffset = Vector3.new(0, -2.45, 0)
	distanceBillboard.Parent = espFolder

	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Size = UDim2.new(1, 0, 1, 0)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.TextColor3 = colors.muted
	distanceLabel.Font = Enum.Font.GothamBold
	distanceLabel.TextSize = 8
	distanceLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	distanceLabel.TextStrokeTransparency = 0.35
	distanceLabel.Parent = distanceBillboard

	local healthBillboard = Instance.new("BillboardGui")
	healthBillboard.Name = "ESP_World_Health"
	healthBillboard.AlwaysOnTop = true
	healthBillboard.Enabled = false
	healthBillboard.MaxDistance = 10000
	healthBillboard.Size = UDim2.new(0, 3, 0, 28)
	healthBillboard.StudsOffset = Vector3.new(1.15, 0.1, 0)
	healthBillboard.Parent = espFolder

	local healthBack = Instance.new("Frame")
	healthBack.Size = UDim2.new(1, 0, 1, 0)
	healthBack.BackgroundColor3 = Color3.fromRGB(18, 28, 45)
	healthBack.BackgroundTransparency = 0.5
	healthBack.BorderSizePixel = 0
	healthBack.Parent = healthBillboard
	addCorner(healthBack, 2)

	local healthFill = Instance.new("Frame")
	healthFill.AnchorPoint = Vector2.new(0, 1)
	healthFill.Position = UDim2.new(0, 0, 1, 0)
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = colors.green
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBack
	addCorner(healthFill, 2)

	local highlight = Instance.new("Highlight")
	highlight.Name = "ESP_World_Chams"
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = colors.orange
	highlight.OutlineColor = colors.text
	highlight.FillTransparency = 0.9
	highlight.OutlineTransparency = 0.46
	highlight.Enabled = false
	highlight.Parent = espFolder

	worldEspEntries[instance] = {
		nameBillboard = nameBillboard,
		distanceBillboard = distanceBillboard,
		healthBillboard = healthBillboard,
		nameLabel = nameLabel,
		distanceLabel = distanceLabel,
		healthFill = healthFill,
		highlight = highlight,
	}
end

local function setWorldEspEntryEnabled(entry, enabled, hasHealth)
	entry.nameBillboard.Enabled = enabled and espNamesEnabled
	entry.distanceBillboard.Enabled = enabled and espDistanceEnabled
	entry.healthBillboard.Enabled = enabled and espHealthEnabled and hasHealth
	entry.highlight.Enabled = enabled and espEnabled and chamsEnabled
end

local function updateWorldEsp(deltaTime)
	if not espEnabled then
		return
	end

	worldEspScanTimer += (deltaTime or 0)

	if worldEspScanTimer >= 0.75 then
		worldEspScanTimer = 0
		refreshWorldEspTargets()
	end

	local myRoot = getRoot(player.Character)
	if not myRoot then
		for _, entry in pairs(worldEspEntries) do
			setWorldEspEntryEnabled(entry, false, false)
		end
		return
	end

	for instance, entry in pairs(worldEspEntries) do
		if not worldEspTargets[instance] or not instance.Parent then
			clearWorldEspEntry(instance)
		end
	end

	for instance, target in pairs(worldEspTargets) do
		if not instance.Parent or not target.root or not target.root.Parent then
			clearWorldEspEntry(instance)
			continue
		end

		if not worldEspEntries[instance] then
			createWorldEspEntry(instance)
		end

		local entry = worldEspEntries[instance]
		local distance = math.floor((myRoot.Position - target.root.Position).Magnitude)

		if distance > espMaxDistance then
			setWorldEspEntryEnabled(entry, false, target.humanoid ~= nil)
			continue
		end

		local textSize = getEspTextSize(distance)
		entry.nameBillboard.Adornee = target.root
		entry.distanceBillboard.Adornee = target.root
		entry.healthBillboard.Adornee = target.root
		entry.highlight.Adornee = target.highlightObject
		entry.nameLabel.Text = target.displayName
		entry.distanceLabel.Text = tostring(distance) .. " studs"
		entry.nameLabel.TextSize = textSize
		entry.distanceLabel.TextSize = math.max(7, textSize - 1)
		entry.nameBillboard.Size = UDim2.new(0, textSize * 11, 0, textSize + 6)
		entry.distanceBillboard.Size = UDim2.new(0, textSize * 9, 0, textSize + 5)

		if target.humanoid then
			local healthPercent = math.clamp(target.humanoid.Health / math.max(target.humanoid.MaxHealth, 1), 0, 1)
			entry.healthFill.Size = UDim2.new(1, 0, healthPercent, 0)

			if healthPercent > 0.5 then
				entry.healthFill.BackgroundColor3 = colors.green
			elseif healthPercent > 0.25 then
				entry.healthFill.BackgroundColor3 = Color3.fromRGB(235, 185, 70)
			else
				entry.healthFill.BackgroundColor3 = colors.red
			end
		end

		setWorldEspEntryEnabled(entry, true, target.humanoid ~= nil)
	end
end

local function updateEsp(deltaTime)
	if not espEnabled then
		return
	end

	if not espPlayersEnabled then
		clearEsp()
		updateWorldEsp(deltaTime)
		return
	end

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player and not espEntries[targetPlayer] then
			createEspEntry(targetPlayer)
		end
	end

	local myRoot = getRoot(player.Character)

	for targetPlayer, entry in pairs(espEntries) do
		if not targetPlayer.Parent then
			clearEspEntry(targetPlayer)
			continue
		end

		local character = targetPlayer.Character
		local root = getRoot(character)
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local head = character and character:FindFirstChild("Head")

		if myRoot and root and humanoid and (head or root) then
			local distance = math.floor((myRoot.Position - root.Position).Magnitude)
			local maxHealth = math.max(humanoid.MaxHealth, 1)
			local healthPercent = math.clamp(humanoid.Health / maxHealth, 0, 1)
			local textSize = getEspTextSize(distance)

			if distance > espMaxDistance then
				setEspEntryEnabled(entry, false)
				continue
			end

			entry.nameBillboard.Adornee = head or root
			entry.distanceBillboard.Adornee = root
			entry.healthBillboard.Adornee = root
			setEspEntryEnabled(entry, true)
			entry.nameBillboard.Size = UDim2.new(0, textSize * 10, 0, textSize + 6)
			entry.distanceBillboard.Size = UDim2.new(0, textSize * 9, 0, textSize + 5)
			entry.nameLabel.Text = targetPlayer.Name
			entry.distanceLabel.Text = tostring(distance) .. " studs"
			entry.nameLabel.TextSize = textSize
			entry.distanceLabel.TextSize = math.max(7, textSize - 1)
			entry.healthFill.Size = UDim2.new(1, 0, healthPercent, 0)

			if healthPercent > 0.5 then
				entry.healthFill.BackgroundColor3 = colors.green
			elseif healthPercent > 0.25 then
				entry.healthFill.BackgroundColor3 = Color3.fromRGB(235, 185, 70)
			else
				entry.healthFill.BackgroundColor3 = colors.red
			end
		else
			setEspEntryEnabled(entry, false)
		end
	end

	updateWorldEsp(deltaTime)
end

local function setEspEnabled(enabled)
	espEnabled = enabled

	setToggleVisual(espButton, enabled)

	if enabled then
		for _, targetPlayer in ipairs(Players:GetPlayers()) do
			createEspEntry(targetPlayer)
		end

		worldEspScanTimer = 1
		playerStatus.Text = "ESP enabled."
	else
		clearEsp()
		clearChams()
		if clearWorldEsp then
			clearWorldEsp()
		end
		playerStatus.Text = "ESP disabled."
	end
end

local function clearChamsEntry(targetPlayer)
	local highlight = chamsEntries[targetPlayer]
	if highlight then
		highlight:Destroy()
	end

	chamsEntries[targetPlayer] = nil
end

clearChams = function()
	for _, highlight in pairs(chamsEntries) do
		if highlight then
			highlight:Destroy()
		end
	end

	chamsEntries = {}
end

local function createChamsEntry(targetPlayer)
	if targetPlayer == player or chamsEntries[targetPlayer] then
		return
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = "ESP_Chams_" .. targetPlayer.Name
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = Color3.fromRGB(75, 112, 255)
	highlight.OutlineColor = colors.text
	highlight.FillTransparency = 0.86
	highlight.OutlineTransparency = 0.32
	highlight.Enabled = false
	highlight.Parent = espFolder

	chamsEntries[targetPlayer] = highlight
end

local function updateChams()
	if not espEnabled or not chamsEnabled or not espPlayersEnabled then
		return
	end

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player and not chamsEntries[targetPlayer] then
			createChamsEntry(targetPlayer)
		end
	end

	for targetPlayer, highlight in pairs(chamsEntries) do
		if not targetPlayer.Parent then
			clearChamsEntry(targetPlayer)
			continue
		end

		local character = targetPlayer.Character
		local myRoot = getRoot(player.Character)
		local root = getRoot(character)
		highlight.Adornee = character
		highlight.Enabled = character ~= nil and myRoot ~= nil and root ~= nil and (myRoot.Position - root.Position).Magnitude <= espMaxDistance
	end
end

local function setChamsEnabled(enabled)
	chamsEnabled = enabled
	setToggleVisual(chamsButton, enabled)

	if enabled then
		updateChams()
		playerStatus.Text = "Chams enabled."
	else
		clearChams()
		for _, entry in pairs(worldEspEntries) do
			if entry.highlight then
				entry.highlight.Enabled = false
			end
		end
		playerStatus.Text = "Chams disabled."
	end
end

connect(RunService.Stepped, applyNoclip)
connect(RunService.RenderStepped, updateVehicleFly)
connect(RunService.RenderStepped, updateWaypointSpotDistances)
connect(RunService.RenderStepped, updateEsp)
connect(RunService.RenderStepped, updateChams)

local function unloadMenu()
	if unloaded then
		return
	end

	running = false
	waypointRunning = false
	setWaypointSpotsEnabled(false)
	setNoclipEnabled(false)
	setVehicleFlyEnabled(false)
	setEspEnabled(false)
	setChamsEnabled(false)
	unloaded = true

	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end

	espFolder:Destroy()
	waypointSpotFolder:Destroy()
	screenGui:Destroy()
end

local function refreshPlayerDropdown()
	local names = {}

	for _, targetPlayer in ipairs(Players:GetPlayers()) do
		if targetPlayer ~= player then
			table.insert(names, targetPlayer.Name)
		end
	end

	table.sort(names)

	playerDropdown:Populate(names, function(name)
		selectedTargetName = name
		playerDropdown:SetText(name)
		tpStatus.Text = "Target: " .. name
	end, "No players")
end

local function makeUniqueWaypointName(rawName)
	local baseName = trim(rawName)

	if baseName == "" then
		local index = 1
		local candidate = "Waypoint " .. index

		while waypoints[candidate] do
			index += 1
			candidate = "Waypoint " .. index
		end

		return candidate
	end

	if not waypoints[baseName] then
		return baseName
	end

	local index = 2
	local candidate = baseName .. " " .. index

	while waypoints[candidate] do
		index += 1
		candidate = baseName .. " " .. index
	end

	return candidate
end

local function refreshWaypointDropdown()
	local names = {}

	for _, name in ipairs(waypointOrder) do
		if waypoints[name] then
			table.insert(names, name)
		end
	end

	waypointDropdown:Populate(names, function(name)
		selectedWaypointName = name
		waypointDropdown:SetText(name)
		waypointStatus.Text = "Selected: " .. name
	end, "No waypoints")
end

local function startTeleport()
	if running then
		return
	end

	if not selectedTargetName then
		tpStatus.Text = "Choose a player first."
		return
	end

	stopWaypointTeleport()
	setVehicleFlyEnabled(false)

	running = true
	startButton.Text = "Stop"
	startButton.BackgroundColor3 = colors.red
	tpStatus.Text = "Teleporting..."

	task.spawn(function()
		local endMessage = "Stopped."

		while running and not unloaded do
			local targetPlayer = Players:FindFirstChild(selectedTargetName)

			if not targetPlayer then
				endMessage = "Target unavailable."
				break
			end

			local myRoot = getRoot(player.Character)
			local targetRoot = getRoot(targetPlayer.Character)

			if not myRoot or not targetRoot then
				task.wait(0.1)
				continue
			end

			myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, behindOffset)

			task.wait(0.09)
		end

		stopTeleport()

		if not unloaded then
			tpStatus.Text = endMessage
		end
	end)
end

local function startWaypointTeleport()
	if waypointRunning then
		return
	end

	if not selectedWaypointName or not waypoints[selectedWaypointName] then
		waypointStatus.Text = "Choose a waypoint first."
		return
	end

	stopTeleport()
	setVehicleFlyEnabled(false)

	activeWaypointLoopName = selectedWaypointName
	waypointRunning = true
	teleportWaypointButton.Text = "Stop"
	teleportWaypointButton.BackgroundColor3 = colors.red
	waypointStatus.Text = "Loop teleporting to: " .. activeWaypointLoopName

	task.spawn(function()
		local endMessage = "Stopped."

		while waypointRunning and not unloaded do
			local waypoint = activeWaypointLoopName and waypoints[activeWaypointLoopName]

			if not waypoint then
				endMessage = "Waypoint unavailable."
				break
			end

			local root = getRoot(player.Character)

			if not root then
				task.wait(0.1)
				continue
			end

			root.CFrame = waypoint.cframe
			task.wait(0.09)
		end

		stopWaypointTeleport()

		if not unloaded then
			waypointStatus.Text = endMessage
		end
	end)
end

local function updateKeybindButton()
	if rebinding then
		keybindButton.Text = "Press a key..."
	else
		keybindButton.Text = "Hide / Show: " .. menuKey.Name
	end
end

local function toggleMenu()
	if unloaded then
		return
	end

	closeAllDropdowns()
	controlHoverCount = 0
	mainFrame.Visible = not mainFrame.Visible
end

local function updateEspKeybindButtons()
	espToggleKeyButton.Text = espKeybindMode == "ESP" and "..." or keyName(espToggleKey)
	espPlayersKeyButton.Text = espKeybindMode == "Players" and "..." or keyName(espPlayersKey)
	espZombiesKeyButton.Text = espKeybindMode == "Zombies" and "..." or keyName(espZombiesKey)
	espVehiclesKeyButton.Text = espKeybindMode == "Vehicles" and "..." or keyName(espVehiclesKey)
	espCorpsesKeyButton.Text = espKeybindMode == "Corpses" and "..." or keyName(espCorpsesKey)
end

local function updateEspToggleButtons()
	setToggleVisual(espButton, espEnabled)
	setToggleVisual(chamsButton, chamsEnabled)
	setToggleVisual(espNamesButton, espNamesEnabled)
	setToggleVisual(espDistanceButton, espDistanceEnabled)
	setToggleVisual(espHealthButton, espHealthEnabled)
	setToggleVisual(espPlayersButton, espPlayersEnabled)
	setToggleVisual(espZombiesButton, espZombiesEnabled)
	setToggleVisual(espBossOnlyButton, espBossOnlyEnabled)
	setToggleVisual(espVehiclesButton, espVehiclesEnabled)
	setToggleVisual(espCorpsesButton, espCorpsesEnabled)
end

local function isEspKeyInUse(keyCode, ignoredMode)
	if not keyCode or keyCode == Enum.KeyCode.Unknown then
		return false
	end

	if keyCode == menuKey or keyCode == noclipKey or keyCode == vehicleFlyKey then
		return true
	end

	if ignoredMode ~= "ESP" and espToggleKey and keyCode == espToggleKey then
		return true
	elseif ignoredMode ~= "Players" and espPlayersKey and keyCode == espPlayersKey then
		return true
	elseif ignoredMode ~= "Zombies" and espZombiesKey and keyCode == espZombiesKey then
		return true
	elseif ignoredMode ~= "Vehicles" and espVehiclesKey and keyCode == espVehiclesKey then
		return true
	elseif ignoredMode ~= "Corpses" and espCorpsesKey and keyCode == espCorpsesKey then
		return true
	end

	return false
end

local function hasEspKey(keyCode)
	return (espToggleKey and keyCode == espToggleKey)
		or (espPlayersKey and keyCode == espPlayersKey)
		or (espZombiesKey and keyCode == espZombiesKey)
		or (espVehiclesKey and keyCode == espVehiclesKey)
		or (espCorpsesKey and keyCode == espCorpsesKey)
end

local function beginEspKeybind(mode)
	rebinding = false
	noclipRebinding = false
	vehicleFlyRebinding = false
	espKeybindMode = mode
	updateKeybindButton()
	updateNoclipKeybindButton()
	updateVehicleFlyKeybindButton()
	updateEspKeybindButtons()
	playerStatus.Text = "Press a keyboard key. Escape cancels."
end

clearWorldEsp = function()
	for _, entry in pairs(worldEspEntries) do
		if entry.nameBillboard then
			entry.nameBillboard:Destroy()
		end

		if entry.distanceBillboard then
			entry.distanceBillboard:Destroy()
		end

		if entry.healthBillboard then
			entry.healthBillboard:Destroy()
		end

		if entry.highlight then
			entry.highlight:Destroy()
		end
	end

	worldEspEntries = {}
	worldEspTargets = {}
end

playerDropdown.OnBeforeOpen = refreshPlayerDropdown
waypointDropdown.OnBeforeOpen = refreshWaypointDropdown

connect(tpTab.MouseButton1Click, function()
	setTab("TP")
end)

connect(waypointTab.MouseButton1Click, function()
	setTab("Waypoints")
end)

connect(playerTab.MouseButton1Click, function()
	setTab("Player")
end)

connect(settingsTab.MouseButton1Click, function()
	setTab("Settings")
end)

connect(distanceBox.FocusLost, function()
	local newDistance = tonumber(distanceBox.Text)

	if newDistance then
		behindOffset = newDistance
		distanceBox.Text = tostring(behindOffset)
		tpStatus.Text = "Distance set to " .. tostring(behindOffset)
	else
		distanceBox.Text = tostring(behindOffset)
		tpStatus.Text = "Enter a valid number."
	end
end)

connect(startButton.MouseButton1Click, function()
	if running then
		stopTeleport()
		tpStatus.Text = "Stopped."
	else
		startTeleport()
	end
end)

connect(saveWaypointButton.MouseButton1Click, function()
	local root = getRoot(player.Character)

	if not root then
		waypointStatus.Text = "Character root not found."
		return
	end

	local name = makeUniqueWaypointName(waypointNameBox.Text)

	waypoints[name] = {
		cframe = root.CFrame,
	}

	table.insert(waypointOrder, name)

	selectedWaypointName = name
	waypointNameBox.Text = name
	waypointDropdown:SetText(name)

	refreshWaypointDropdown()
	refreshWaypointSpots()

	local savedToDisk, saveMessage = saveWaypointsToDisk()
	if savedToDisk then
		waypointStatus.Text = "Saved: " .. name
	else
		waypointStatus.Text = "Saved this session: " .. name .. " (" .. saveMessage .. ")"
	end
end)

connect(waypointSpotsButton.MouseButton1Click, function()
	setWaypointSpotsEnabled(not waypointSpotsEnabled)
end)

connect(teleportWaypointButton.MouseButton1Click, function()
	if waypointRunning then
		stopWaypointTeleport()
		waypointStatus.Text = "Stopped."
	else
		startWaypointTeleport()
	end
end)

connect(deleteWaypointButton.MouseButton1Click, function()
	if not selectedWaypointName or not waypoints[selectedWaypointName] then
		waypointStatus.Text = "Choose a waypoint to delete."
		return
	end

	local deletedName = selectedWaypointName

	if activeWaypointLoopName == deletedName then
		stopWaypointTeleport()
	end

	waypoints[deletedName] = nil

	for index, name in ipairs(waypointOrder) do
		if name == deletedName then
			table.remove(waypointOrder, index)
			break
		end
	end

	selectedWaypointName = nil
	waypointDropdown:SetText("Choose waypoint")

	refreshWaypointDropdown()
	refreshWaypointSpots()

	local savedToDisk, saveMessage = saveWaypointsToDisk()
	if savedToDisk then
		waypointStatus.Text = "Deleted: " .. deletedName
	else
		waypointStatus.Text = "Deleted this session: " .. deletedName .. " (" .. saveMessage .. ")"
	end
end)

connect(noclipButton.MouseButton1Click, function()
	setNoclipEnabled(not noclipEnabled)
end)

connect(noclipKeybindButton.MouseButton1Click, function()
	rebinding = false
	vehicleFlyRebinding = false
	espKeybindMode = nil
	updateKeybindButton()
	updateVehicleFlyKeybindButton()
	updateEspKeybindButtons()
	noclipRebinding = true
	updateNoclipKeybindButton()
	playerStatus.Text = "Press a keyboard key. Escape cancels."
end)

connect(vehicleFlyButton.MouseButton1Click, function()
	if not vehicleFlyEnabled then
		stopTeleport()
		stopWaypointTeleport()
	end

	setVehicleFlyEnabled(not vehicleFlyEnabled)
end)

connect(vehicleFlyKeybindButton.MouseButton1Click, function()
	rebinding = false
	noclipRebinding = false
	espKeybindMode = nil
	updateKeybindButton()
	updateNoclipKeybindButton()
	updateEspKeybindButtons()
	vehicleFlyRebinding = true
	updateVehicleFlyKeybindButton()
	playerStatus.Text = "Press a keyboard key. Escape cancels."
end)

connect(vehicleFlySpeedBox.FocusLost, function()
	local newSpeed = tonumber(vehicleFlySpeedBox.Text)

	if newSpeed then
		vehicleFlySpeed = math.clamp(math.floor(newSpeed), 10, 500)
		vehicleFlySpeedBox.Text = tostring(vehicleFlySpeed)
		playerStatus.Text = "Car fly speed set to " .. tostring(vehicleFlySpeed) .. "."
	else
		vehicleFlySpeedBox.Text = tostring(vehicleFlySpeed)
		playerStatus.Text = "Enter a valid car fly speed."
	end
end)

connect(espButton.MouseButton1Click, function()
	setEspEnabled(not espEnabled)
end)

connect(espToggleKeyButton.MouseButton1Click, function()
	beginEspKeybind("ESP")
end)

connect(chamsButton.MouseButton1Click, function()
	setChamsEnabled(not chamsEnabled)
end)

connect(espNamesButton.MouseButton1Click, function()
	espNamesEnabled = not espNamesEnabled
	updateEspToggleButtons()
	playerStatus.Text = "ESP names " .. (espNamesEnabled and "shown." or "hidden.")
end)

connect(espDistanceButton.MouseButton1Click, function()
	espDistanceEnabled = not espDistanceEnabled
	updateEspToggleButtons()
	playerStatus.Text = "ESP distance " .. (espDistanceEnabled and "shown." or "hidden.")
end)

connect(espHealthButton.MouseButton1Click, function()
	espHealthEnabled = not espHealthEnabled
	updateEspToggleButtons()
	playerStatus.Text = "ESP health " .. (espHealthEnabled and "shown." or "hidden.")
end)

connect(espPlayersButton.MouseButton1Click, function()
	espPlayersEnabled = not espPlayersEnabled
	updateEspToggleButtons()

	if not espPlayersEnabled then
		clearEsp()
		clearChams()
	elseif espEnabled then
		for _, targetPlayer in ipairs(Players:GetPlayers()) do
			createEspEntry(targetPlayer)
		end
	end

	playerStatus.Text = "Player ESP " .. (espPlayersEnabled and "enabled." or "disabled.")
end)

connect(espPlayersKeyButton.MouseButton1Click, function()
	beginEspKeybind("Players")
end)

connect(espZombiesButton.MouseButton1Click, function()
	espZombiesEnabled = not espZombiesEnabled
	worldEspScanTimer = 1
	updateEspToggleButtons()
	playerStatus.Text = "Zombie ESP " .. (espZombiesEnabled and "enabled." or "disabled.")
end)

connect(espZombiesKeyButton.MouseButton1Click, function()
	beginEspKeybind("Zombies")
end)

connect(espBossOnlyButton.MouseButton1Click, function()
	espBossOnlyEnabled = not espBossOnlyEnabled
	worldEspScanTimer = 1
	updateEspToggleButtons()
	playerStatus.Text = "Boss-only zombie filter " .. (espBossOnlyEnabled and "enabled." or "disabled.")
end)

connect(espVehiclesButton.MouseButton1Click, function()
	espVehiclesEnabled = not espVehiclesEnabled
	worldEspScanTimer = 1
	updateEspToggleButtons()
	playerStatus.Text = "Vehicle ESP " .. (espVehiclesEnabled and "enabled." or "disabled.")
end)

connect(espVehiclesKeyButton.MouseButton1Click, function()
	beginEspKeybind("Vehicles")
end)

connect(espCorpsesButton.MouseButton1Click, function()
	espCorpsesEnabled = not espCorpsesEnabled
	worldEspScanTimer = 1
	updateEspToggleButtons()
	playerStatus.Text = "Corpse ESP " .. (espCorpsesEnabled and "enabled." or "disabled.")
end)

connect(espCorpsesKeyButton.MouseButton1Click, function()
	beginEspKeybind("Corpses")
end)

connect(keybindButton.MouseButton1Click, function()
	noclipRebinding = false
	vehicleFlyRebinding = false
	espKeybindMode = nil
	updateNoclipKeybindButton()
	updateVehicleFlyKeybindButton()
	updateEspKeybindButtons()
	rebinding = true
	updateKeybindButton()
	settingsStatus.Text = "Press a keyboard key. Escape cancels."
end)

connect(unloadButton.MouseButton1Click, unloadMenu)

connect(UserInputService.InputBegan, function(input)
	if unloaded then
		return
	end

	if input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end

	if rebinding then
		if input.KeyCode == Enum.KeyCode.Escape then
			rebinding = false
			updateKeybindButton()
			settingsStatus.Text = "Rebind cancelled."
			return
		end

		if input.KeyCode ~= Enum.KeyCode.Unknown then
			if input.KeyCode == noclipKey or input.KeyCode == vehicleFlyKey or hasEspKey(input.KeyCode) then
				settingsStatus.Text = "That key is already used in the Player tab."
				return
			end

			menuKey = input.KeyCode
			rebinding = false
			updateKeybindButton()
			settingsStatus.Text = "Keybind set to " .. menuKey.Name .. "."
			return
		end
	end

	if noclipRebinding then
		if input.KeyCode == Enum.KeyCode.Escape then
			noclipRebinding = false
			updateNoclipKeybindButton()
			playerStatus.Text = "Rebind cancelled."
			return
		end

		if input.KeyCode ~= Enum.KeyCode.Unknown then
			if input.KeyCode == menuKey or input.KeyCode == vehicleFlyKey or hasEspKey(input.KeyCode) then
				playerStatus.Text = "That key is already used."
				return
			end

			noclipKey = input.KeyCode
			noclipRebinding = false
			updateNoclipKeybindButton()
			playerStatus.Text = "Noclip key set to " .. noclipKey.Name .. "."
			return
		end
	end

	if vehicleFlyRebinding then
		if input.KeyCode == Enum.KeyCode.Escape then
			vehicleFlyRebinding = false
			updateVehicleFlyKeybindButton()
			playerStatus.Text = "Rebind cancelled."
			return
		end

		if input.KeyCode ~= Enum.KeyCode.Unknown then
			if input.KeyCode == menuKey or input.KeyCode == noclipKey or hasEspKey(input.KeyCode) then
				playerStatus.Text = "That key is already used."
				return
			end

			vehicleFlyKey = input.KeyCode
			vehicleFlyRebinding = false
			updateVehicleFlyKeybindButton()
			playerStatus.Text = "Car fly key set to " .. vehicleFlyKey.Name .. "."
			return
		end
	end

	if espKeybindMode then
		if input.KeyCode == Enum.KeyCode.Escape then
			espKeybindMode = nil
			updateEspKeybindButtons()
			playerStatus.Text = "Rebind cancelled."
			return
		end

		if input.KeyCode ~= Enum.KeyCode.Unknown then
			if isEspKeyInUse(input.KeyCode, espKeybindMode) then
				playerStatus.Text = "That key is already used."
				return
			end

			if espKeybindMode == "ESP" then
				espToggleKey = input.KeyCode
			elseif espKeybindMode == "Players" then
				espPlayersKey = input.KeyCode
			elseif espKeybindMode == "Zombies" then
				espZombiesKey = input.KeyCode
			elseif espKeybindMode == "Vehicles" then
				espVehiclesKey = input.KeyCode
			elseif espKeybindMode == "Corpses" then
				espCorpsesKey = input.KeyCode
			end

			local reboundMode = espKeybindMode
			espKeybindMode = nil
			updateEspKeybindButtons()
			playerStatus.Text = reboundMode .. " key set to " .. input.KeyCode.Name .. "."
			return
		end
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == menuKey then
		toggleMenu()
		return
	end

	if input.KeyCode == noclipKey then
		setNoclipEnabled(not noclipEnabled)
		return
	end

	if input.KeyCode == vehicleFlyKey then
		if not vehicleFlyEnabled then
			stopTeleport()
			stopWaypointTeleport()
		end

		setVehicleFlyEnabled(not vehicleFlyEnabled)
		return
	end

	if espToggleKey and input.KeyCode == espToggleKey then
		setEspEnabled(not espEnabled)
		return
	end

	if espPlayersKey and input.KeyCode == espPlayersKey then
		espPlayersEnabled = not espPlayersEnabled
		updateEspToggleButtons()

		if not espPlayersEnabled then
			clearEsp()
			clearChams()
		end

		playerStatus.Text = "Player ESP " .. (espPlayersEnabled and "enabled." or "disabled.")
		return
	end

	if espZombiesKey and input.KeyCode == espZombiesKey then
		espZombiesEnabled = not espZombiesEnabled
		worldEspScanTimer = 1
		updateEspToggleButtons()
		playerStatus.Text = "Zombie ESP " .. (espZombiesEnabled and "enabled." or "disabled.")
		return
	end

	if espVehiclesKey and input.KeyCode == espVehiclesKey then
		espVehiclesEnabled = not espVehiclesEnabled
		worldEspScanTimer = 1
		updateEspToggleButtons()
		playerStatus.Text = "Vehicle ESP " .. (espVehiclesEnabled and "enabled." or "disabled.")
		return
	end

	if espCorpsesKey and input.KeyCode == espCorpsesKey then
		espCorpsesEnabled = not espCorpsesEnabled
		worldEspScanTimer = 1
		updateEspToggleButtons()
		playerStatus.Text = "Corpse ESP " .. (espCorpsesEnabled and "enabled." or "disabled.")
	end
end)

connect(player.CharacterAdded, function()
	noclipOriginalCollisions = {}
	clearVehicleFlyForces()
end)

connect(Players.PlayerAdded, function(newPlayer)
	refreshPlayerDropdown()

	if espEnabled and espPlayersEnabled then
		createEspEntry(newPlayer)
	end

	if espEnabled and espPlayersEnabled and chamsEnabled then
		createChamsEntry(newPlayer)
	end
end)

connect(Players.PlayerRemoving, function(leavingPlayer)
	if selectedTargetName == leavingPlayer.Name then
		selectedTargetName = nil
		playerDropdown:SetText("Choose player")
		stopTeleport()
		tpStatus.Text = "Target left."
	end

	clearEspEntry(leavingPlayer)
	clearChamsEntry(leavingPlayer)
	refreshPlayerDropdown()
end)

local loadedWaypointsOk, loadedWaypointCount, loadedWaypointMessage = loadWaypointsFromDisk()
refreshPlayerDropdown()
refreshWaypointDropdown()
updateKeybindButton()
updateNoclipKeybindButton()
updateVehicleFlyKeybindButton()
updateEspToggleButtons()
updateEspKeybindButtons()
setTab("TP")
waypointStatus.Text = loadedWaypointMessage
