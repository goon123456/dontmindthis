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

local selectedTargetName = nil
local selectedWaypointName = nil
local waypoints = {}
local waypointOrder = {}

local running = false
local waypointRunning = false
local activeWaypointLoopName = nil
local noclipEnabled = false
local noclipRebinding = false
local noclipKey = Enum.KeyCode.N
local noclipOriginalCollisions = {}
local espEnabled = false
local espEntries = {}
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
	button = Color3.fromRGB(37, 87, 165),
	buttonDark = Color3.fromRGB(23, 58, 112),
	accent = Color3.fromRGB(75, 112, 255),
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

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 560, 0, 360)
mainFrame.Position = UDim2.new(0.5, -280, 0.5, -180)
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
local teleportWaypointButton = createButton(waypointPage, "Teleport", UDim2.new(0, 26, 0, 220), UDim2.new(0, 126, 0, 42), colors.accent)
local deleteWaypointButton = createButton(waypointPage, "Delete", UDim2.new(0, 164, 0, 220), UDim2.new(0, 126, 0, 42), colors.red)
local waypointStatus = createLabel(waypointPage, "No waypoints saved.", UDim2.new(0, 26, 0, 274), UDim2.new(0, 360, 0, 26), 12, colors.muted)
waypointStatus.Font = Enum.Font.Gotham

createLabel(playerPage, "Noclip", UDim2.new(0, 26, 0, 18), UDim2.new(0, 230, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold
local noclipButton = createButton(playerPage, "Noclip: Off", UDim2.new(0, 26, 0, 48), UDim2.new(0, 154, 0, 42), colors.buttonDark)
local noclipKeybindButton = createButton(playerPage, "Key: N", UDim2.new(0, 194, 0, 48), UDim2.new(0, 154, 0, 42), colors.buttonDark)

createLabel(playerPage, "ESP", UDim2.new(0, 26, 0, 118), UDim2.new(0, 230, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold
local espButton = createButton(playerPage, "ESP: Off", UDim2.new(0, 26, 0, 148), UDim2.new(0, 154, 0, 42), colors.buttonDark)
local playerStatus = createLabel(playerPage, "Noclip key: N. ESP shows distance and health.", UDim2.new(0, 26, 0, 224), UDim2.new(0, 360, 0, 40), 12, colors.muted)
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

local function clearEspEntry(targetPlayer)
	local entry = espEntries[targetPlayer]
	if not entry then
		return
	end

	if entry.billboard then
		entry.billboard:Destroy()
	end

	espEntries[targetPlayer] = nil
end

local function clearEsp()
	for _, entry in pairs(espEntries) do
		if entry.billboard then
			entry.billboard:Destroy()
		end
	end

	espEntries = {}
end

local function createEspEntry(targetPlayer)
	if targetPlayer == player or espEntries[targetPlayer] then
		return
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ESP_" .. targetPlayer.Name
	billboard.AlwaysOnTop = true
	billboard.Enabled = false
	billboard.MaxDistance = 10000
	billboard.Size = UDim2.new(0, 150, 0, 58)
	billboard.StudsOffset = Vector3.new(0, 3.4, 0)
	billboard.Parent = espFolder

	local container = Instance.new("Frame")
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundColor3 = Color3.fromRGB(4, 12, 24)
	container.BackgroundTransparency = 0.18
	container.BorderSizePixel = 0
	container.Parent = billboard
	addCorner(container, 8)
	addStroke(container, colors.stroke, 1, 0.4)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -10, 0, 20)
	nameLabel.Position = UDim2.new(0, 5, 0, 3)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = targetPlayer.Name
	nameLabel.TextColor3 = colors.text
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = 12
	nameLabel.TextStrokeTransparency = 0.55
	nameLabel.Parent = container

	local distanceLabel = Instance.new("TextLabel")
	distanceLabel.Size = UDim2.new(1, -10, 0, 16)
	distanceLabel.Position = UDim2.new(0, 5, 0, 22)
	distanceLabel.BackgroundTransparency = 1
	distanceLabel.Text = "..."
	distanceLabel.TextColor3 = colors.muted
	distanceLabel.Font = Enum.Font.Gotham
	distanceLabel.TextSize = 11
	distanceLabel.TextStrokeTransparency = 0.65
	distanceLabel.Parent = container

	local healthBar = Instance.new("Frame")
	healthBar.Size = UDim2.new(1, -14, 0, 8)
	healthBar.Position = UDim2.new(0, 7, 0, 43)
	healthBar.BackgroundColor3 = Color3.fromRGB(18, 28, 45)
	healthBar.BorderSizePixel = 0
	healthBar.Parent = container
	addCorner(healthBar, 5)

	local healthFill = Instance.new("Frame")
	healthFill.Size = UDim2.new(1, 0, 1, 0)
	healthFill.BackgroundColor3 = colors.green
	healthFill.BorderSizePixel = 0
	healthFill.Parent = healthBar
	addCorner(healthFill, 5)

	espEntries[targetPlayer] = {
		billboard = billboard,
		nameLabel = nameLabel,
		distanceLabel = distanceLabel,
		healthFill = healthFill,
	}
end

local function updateEsp()
	if not espEnabled then
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

			entry.billboard.Adornee = head or root
			entry.billboard.Enabled = true
			entry.nameLabel.Text = targetPlayer.Name
			entry.distanceLabel.Text = tostring(distance) .. " studs"
			entry.healthFill.Size = UDim2.new(healthPercent, 0, 1, 0)

			if healthPercent > 0.5 then
				entry.healthFill.BackgroundColor3 = colors.green
			elseif healthPercent > 0.25 then
				entry.healthFill.BackgroundColor3 = Color3.fromRGB(235, 185, 70)
			else
				entry.healthFill.BackgroundColor3 = colors.red
			end
		else
			entry.billboard.Enabled = false
		end
	end
end

local function setEspEnabled(enabled)
	espEnabled = enabled

	espButton.Text = enabled and "ESP: On" or "ESP: Off"
	espButton.BackgroundColor3 = enabled and colors.green or colors.buttonDark

	if enabled then
		for _, targetPlayer in ipairs(Players:GetPlayers()) do
			createEspEntry(targetPlayer)
		end

		playerStatus.Text = "ESP enabled."
	else
		clearEsp()
		playerStatus.Text = "ESP disabled."
	end
end

connect(RunService.Stepped, applyNoclip)
connect(RunService.RenderStepped, updateEsp)

local function unloadMenu()
	if unloaded then
		return
	end

	running = false
	waypointRunning = false
	setNoclipEnabled(false)
	setEspEnabled(false)
	unloaded = true

	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end

	espFolder:Destroy()
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

	local savedToDisk, saveMessage = saveWaypointsToDisk()
	if savedToDisk then
		waypointStatus.Text = "Saved: " .. name
	else
		waypointStatus.Text = "Saved this session: " .. name .. " (" .. saveMessage .. ")"
	end
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
	updateKeybindButton()
	noclipRebinding = true
	updateNoclipKeybindButton()
	playerStatus.Text = "Press a keyboard key. Escape cancels."
end)

connect(espButton.MouseButton1Click, function()
	setEspEnabled(not espEnabled)
end)

connect(keybindButton.MouseButton1Click, function()
	noclipRebinding = false
	updateNoclipKeybindButton()
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
			if input.KeyCode == noclipKey then
				settingsStatus.Text = "That key is used for noclip."
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
			if input.KeyCode == menuKey then
				playerStatus.Text = "That key is used to hide/show the menu."
				return
			end

			noclipKey = input.KeyCode
			noclipRebinding = false
			updateNoclipKeybindButton()
			playerStatus.Text = "Noclip key set to " .. noclipKey.Name .. "."
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
	end
end)

connect(player.CharacterAdded, function()
	noclipOriginalCollisions = {}
end)

connect(Players.PlayerAdded, function(newPlayer)
	refreshPlayerDropdown()

	if espEnabled then
		createEspEntry(newPlayer)
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
	refreshPlayerDropdown()
end)

local loadedWaypointsOk, loadedWaypointCount, loadedWaypointMessage = loadWaypointsFromDisk()
refreshPlayerDropdown()
refreshWaypointDropdown()
updateKeybindButton()
updateNoclipKeybindButton()
setTab("TP")
waypointStatus.Text = loadedWaypointMessage
