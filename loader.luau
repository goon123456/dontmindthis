--!nocheck
local behindOffset = 125

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local oldGui = playerGui:FindFirstChild("TeleportDropdownUI")
if oldGui then
	oldGui:Destroy()
end

local selectedTargetName = nil
local selectedWaypointName = nil
local waypoints = {}
local waypointOrder = {}

local running = false
local unloaded = false
local rebinding = false
local menuKey = Enum.KeyCode.RightControl
local connections = {}

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
local settingsTab = createButton(sidebar, "Settings", UDim2.new(0, 14, 0, 200), UDim2.new(1, -28, 0, 44), colors.buttonDark)

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

local playerDropdown = createDropdown(tpPage, "Player", 26, 12, 260, "Choose player")
createLabel(tpPage, "Distance", UDim2.new(0, 26, 0, 118), UDim2.new(0, 180, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold
local distanceBox = createTextBox(tpPage, tostring(behindOffset), "125", UDim2.new(0, 26, 0, 144), UDim2.new(0, 160, 0, 40))
local startButton = createButton(tpPage, "Start", UDim2.new(0, 26, 0, 214), UDim2.new(0, 160, 0, 42), colors.green)
local tpStatus = createLabel(tpPage, "Ready.", UDim2.new(0, 210, 0, 220), UDim2.new(0, 180, 0, 30), 12, colors.muted)
tpStatus.Font = Enum.Font.Gotham

local waypointNameBox = createTextBox(waypointPage, "", "Waypoint name", UDim2.new(0, 26, 0, 38), UDim2.new(0, 230, 0, 40))
createLabel(waypointPage, "New waypoint", UDim2.new(0, 26, 0, 12), UDim2.new(0, 230, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold
local saveWaypointButton = createButton(waypointPage, "Save Current", UDim2.new(0, 270, 0, 38), UDim2.new(0, 126, 0, 40), colors.green)

local waypointDropdown = createDropdown(waypointPage, "Saved waypoints", 26, 104, 260, "Choose waypoint")
local teleportWaypointButton = createButton(waypointPage, "Teleport", UDim2.new(0, 26, 0, 220), UDim2.new(0, 126, 0, 42), colors.accent)
local deleteWaypointButton = createButton(waypointPage, "Delete", UDim2.new(0, 164, 0, 220), UDim2.new(0, 126, 0, 42), colors.red)
local waypointStatus = createLabel(waypointPage, "No waypoints saved.", UDim2.new(0, 26, 0, 274), UDim2.new(0, 360, 0, 26), 12, colors.muted)
waypointStatus.Font = Enum.Font.Gotham

createLabel(settingsPage, "Menu keybind", UDim2.new(0, 26, 0, 18), UDim2.new(0, 250, 0, 22), 13, colors.muted).Font = Enum.Font.GothamBold
local keybindButton = createButton(settingsPage, "Hide / Show: RightControl", UDim2.new(0, 26, 0, 48), UDim2.new(0, 230, 0, 42), colors.buttonDark)
local unloadButton = createButton(settingsPage, "Unload", UDim2.new(0, 26, 0, 204), UDim2.new(0, 160, 0, 42), colors.red)
local settingsStatus = createLabel(settingsPage, "Press the keybind to hide or show this menu.", UDim2.new(0, 26, 0, 106), UDim2.new(0, 360, 0, 36), 12, colors.muted)
settingsStatus.Font = Enum.Font.Gotham

local pages = {
	TP = tpPage,
	Waypoints = waypointPage,
	Settings = settingsPage,
}

local tabButtons = {
	TP = tpTab,
	Waypoints = waypointTab,
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

local function unloadMenu()
	if unloaded then
		return
	end

	unloaded = true
	running = false

	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end

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

	running = true
	startButton.Text = "Stop"
	startButton.BackgroundColor3 = colors.red
	tpStatus.Text = "Teleporting..."

	task.spawn(function()
		local stableTime = 0
		local lastTeleportPos = nil
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

			if lastTeleportPos then
				local myRootPos = myRoot.Position

				local teleportCheck =
					math.abs(myRootPos.X - lastTeleportPos.X) >= 100 or
					math.abs(myRootPos.Y - lastTeleportPos.Y) >= 100 or
					math.abs(myRootPos.Z - lastTeleportPos.Z) >= 100

				if teleportCheck then
					stableTime = 0
				else
					stableTime += 0.09

					if stableTime >= 1.0 then
						endMessage = "Teleport finished."
						break
					end
				end
			end

			myRoot.CFrame = targetRoot.CFrame * CFrame.new(0, 0, behindOffset)
			lastTeleportPos = myRoot.Position

			task.wait(0.09)
		end

		stopTeleport()

		if not unloaded then
			tpStatus.Text = endMessage
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
	waypointStatus.Text = "Saved: " .. name
end)

connect(teleportWaypointButton.MouseButton1Click, function()
	if not selectedWaypointName or not waypoints[selectedWaypointName] then
		waypointStatus.Text = "Choose a waypoint first."
		return
	end

	local root = getRoot(player.Character)

	if not root then
		waypointStatus.Text = "Character root not found."
		return
	end

	root.CFrame = waypoints[selectedWaypointName].cframe
	waypointStatus.Text = "Teleported to: " .. selectedWaypointName
end)

connect(deleteWaypointButton.MouseButton1Click, function()
	if not selectedWaypointName or not waypoints[selectedWaypointName] then
		waypointStatus.Text = "Choose a waypoint to delete."
		return
	end

	local deletedName = selectedWaypointName
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
	waypointStatus.Text = "Deleted: " .. deletedName
end)

connect(keybindButton.MouseButton1Click, function()
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
			menuKey = input.KeyCode
			rebinding = false
			updateKeybindButton()
			settingsStatus.Text = "Keybind set to " .. menuKey.Name .. "."
			return
		end
	end

	if UserInputService:GetFocusedTextBox() then
		return
	end

	if input.KeyCode == menuKey then
		toggleMenu()
	end
end)

connect(Players.PlayerAdded, refreshPlayerDropdown)

connect(Players.PlayerRemoving, function(leavingPlayer)
	if selectedTargetName == leavingPlayer.Name then
		selectedTargetName = nil
		playerDropdown:SetText("Choose player")
		stopTeleport()
		tpStatus.Text = "Target left."
	end

	refreshPlayerDropdown()
end)

refreshPlayerDropdown()
refreshWaypointDropdown()
updateKeybindButton()
setTab("TP")
