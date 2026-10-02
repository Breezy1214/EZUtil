--!strict
--[=[
	@class LayoutUtil

	Keeps ScrollingFrame canvases and their items sized correctly as content and
	screen size change. Each `Fix*` function returns a cleanup function that
	disconnects everything it set up.

	```lua
	local cleanup = LayoutUtil.FixScrollingCanvas(list.UIListLayout, list, list:FindFirstChildOfClass("UIPadding"))

	-- When the UI is destroyed
	cleanup()
	```
]=]

local RunService = game:GetService("RunService")

local LayoutUtil = {}

local CONSTRAINT_NAME = "LayoutAspectRatio"

--[=[
	Converts a UDim to pixels: `Offset + Scale * referenceSize`.

	@within LayoutUtil
	@param size UDim
	@param referenceSize number -- The size, in pixels, that `Scale` is relative to.
	@return number
]=]
function LayoutUtil.resolveUDim(size: UDim, referenceSize: number): number
	return size.Offset + size.Scale * referenceSize
end

local resolveUDim = LayoutUtil.resolveUDim

local function paddedSize(contentSize: number, leading: UDim?, trailing: UDim?): number
	if not leading and not trailing then
		return contentSize
	end
	local fixedPadding = (if leading then leading.Offset else 0) + (if trailing then trailing.Offset else 0)
	local proportionalPadding = (if leading then leading.Scale else 0) + (if trailing then trailing.Scale else 0)
	return if proportionalPadding < 1
		then (contentSize + fixedPadding) / (1 - proportionalPadding)
		else contentSize + fixedPadding
end

local function newScheduler(update: () -> ()): (() -> (), () -> ())
	local scheduled = false
	local destroyed = false

	local function schedule(): ()
		if scheduled or destroyed then
			return
		end
		scheduled = true
		task.defer(function()
			RunService.Heartbeat:Wait()
			scheduled = false
			if not destroyed then
				update()
			end
		end)
	end

	return schedule, function()
		destroyed = true
	end
end

local function disconnectAll(connections: { RBXScriptConnection }): ()
	for _, connection in connections do
		connection:Disconnect()
	end
end

--[=[
	Turns off `AutomaticCanvasSize` and keeps `CanvasSize` fitted to the layout's
	content plus any padding, never smaller than the visible window. Only the axes
	the frame scrolls on are sized; the other axis is set to 0.

	Updates are batched to the next Heartbeat after a child is added or removed, the
	content or window size changes, the scrolling direction changes, or the padding
	changes.

	@within LayoutUtil
	@client
	@param layout UIGridStyleLayout -- The UIListLayout or UIGridLayout inside the frame.
	@param scrollingFrame ScrollingFrame
	@param padding UIPadding? -- Padding to add around the content.
	@return () -> () -- Stops updating the canvas.
]=]
function LayoutUtil.FixScrollingCanvas(
	layout: UIGridStyleLayout,
	scrollingFrame: ScrollingFrame,
	padding: UIPadding?
): () -> ()
	local connections: { RBXScriptConnection } = {}

	local function update(): ()
		if not scrollingFrame.Parent then
			return
		end
		local windowSize = scrollingFrame.AbsoluteWindowSize
		local contentSize = layout.AbsoluteContentSize
		local direction = scrollingFrame.ScrollingDirection
		local fitX = direction == Enum.ScrollingDirection.X or direction == Enum.ScrollingDirection.XY
		local fitY = direction == Enum.ScrollingDirection.Y or direction == Enum.ScrollingDirection.XY
		scrollingFrame.CanvasSize = UDim2.fromOffset(
			if fitX
				then math.max(
					windowSize.X,
					paddedSize(contentSize.X, padding and padding.PaddingLeft, padding and padding.PaddingRight)
				)
				else 0,
			if fitY
				then math.max(
					windowSize.Y,
					paddedSize(contentSize.Y, padding and padding.PaddingTop, padding and padding.PaddingBottom)
				)
				else 0
		)
	end

	local scheduleUpdate, destroy = newScheduler(update)

	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	table.insert(connections, scrollingFrame.ChildAdded:Connect(scheduleUpdate))
	table.insert(connections, scrollingFrame.ChildRemoved:Connect(scheduleUpdate))
	table.insert(connections, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(scheduleUpdate))
	table.insert(connections, scrollingFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(scheduleUpdate))
	table.insert(connections, scrollingFrame:GetPropertyChangedSignal("ScrollingDirection"):Connect(scheduleUpdate))
	if padding then
		for _, property in { "PaddingLeft", "PaddingRight", "PaddingTop", "PaddingBottom" } do
			table.insert(connections, padding:GetPropertyChangedSignal(property):Connect(scheduleUpdate))
		end
	end
	scheduleUpdate()

	return function()
		destroy()
		disconnectAll(connections)
	end
end

--[=[
	Locks each item and the layout's padding to the height they were authored with,
	resolved against the scrolling frame's visible height. Scale heights then stay
	relative to the viewport instead of growing with the canvas. Each item gets a
	UISizeConstraint, and the layout's `Padding` is rewritten in pixels whenever the
	window resizes.

	@within LayoutUtil
	@client
	@param scrollingFrame ScrollingFrame
	@param layout UIListLayout
	@param items { GuiObject } -- The list items, whose current `Size.Y` is kept.
	@return () -> () -- Disconnects and destroys the size constraints. The layout's padding is not restored.
]=]
function LayoutUtil.FixAuthoredListHeights(
	scrollingFrame: ScrollingFrame,
	layout: UIListLayout,
	items: { GuiObject }
): () -> ()
	local authoredPadding = layout.Padding
	local constraints: { UISizeConstraint } = {}
	local authoredHeights: { UDim } = {}

	for index, item in items do
		local constraint = Instance.new("UISizeConstraint")
		constraint.Name = "AuthoredHeightConstraint"
		constraint.Parent = item
		constraints[index] = constraint
		authoredHeights[index] = item.Size.Y
	end

	local function update(): ()
		local viewportHeight = scrollingFrame.AbsoluteWindowSize.Y
		layout.Padding = UDim.new(0, resolveUDim(authoredPadding, viewportHeight))
		for index, constraint in constraints do
			local height = resolveUDim(authoredHeights[index], viewportHeight)
			constraint.MinSize = Vector2.new(0, height)
			constraint.MaxSize = Vector2.new(math.huge, height)
		end
	end

	local connection = scrollingFrame:GetPropertyChangedSignal("AbsoluteWindowSize"):Connect(update)
	update()

	return function()
		connection:Disconnect()
		for _, constraint in constraints do
			constraint:Destroy()
		end
	end
end

--[=[
	Adds a UIAspectRatioConstraint to each visible item in the scrolling frame and
	keeps the vertical canvas fitted to the content plus any top and bottom padding.
	Items added later are constrained as they arrive. Items that already have a
	UIAspectRatioConstraint of their own are left alone.

	`itemAspectRatio` decides the ratio:
	- a positive number is used for every item;
	- a UDim2 is converted to a ratio once, against the frame's canvas size minus padding;
	- any other number (0, negative or infinite) gives each item the ratio of its own
	  `Size` against the frame's size, re-applied whenever the frame resizes;
	- nil adds no constraints and only fixes the canvas.

	@within LayoutUtil
	@client
	@param layout UIGridStyleLayout
	@param scrollingFrame ScrollingFrame
	@param itemAspectRatio (number | UDim2)?
	@param padding UIPadding?
	@return () -> () -- Disconnects and destroys the constraints this call created.
]=]
function LayoutUtil.FixLayout(
	layout: UIGridStyleLayout,
	scrollingFrame: ScrollingFrame,
	itemAspectRatio: (number | UDim2)?,
	padding: UIPadding?
): () -> ()
	local connections: { RBXScriptConnection } = {}
	local createdConstraints: { UIAspectRatioConstraint } = {}

	local function isValidAspectRatio(aspectRatio: number): boolean
		return aspectRatio > 0 and aspectRatio < math.huge
	end

	local function contentAxisSize(totalSize: number, leading: UDim?, trailing: UDim?): number
		local contentSize = totalSize
		if leading then
			contentSize -= resolveUDim(leading, totalSize)
		end
		if trailing then
			contentSize -= resolveUDim(trailing, totalSize)
		end
		return contentSize
	end

	local function sizeAspectRatio(itemSize: UDim2, referenceWidth: number, referenceHeight: number): number?
		local aspectRatio = resolveUDim(itemSize.X, referenceWidth) / resolveUDim(itemSize.Y, referenceHeight)
		return if isValidAspectRatio(aspectRatio) then aspectRatio else nil
	end

	local function authoredAspectRatio(itemSize: UDim2): number?
		local canvasSize = scrollingFrame.AbsoluteCanvasSize
		return sizeAspectRatio(
			itemSize,
			contentAxisSize(canvasSize.X, padding and padding.PaddingLeft, padding and padding.PaddingRight),
			contentAxisSize(canvasSize.Y, padding and padding.PaddingTop, padding and padding.PaddingBottom)
		)
	end

	local resolvedItemAspectRatio = if typeof(itemAspectRatio) == "UDim2"
		then authoredAspectRatio(itemAspectRatio)
		else itemAspectRatio

	local derivesFromParentSize = resolvedItemAspectRatio ~= nil and not isValidAspectRatio(resolvedItemAspectRatio)

	local function resolveAspectRatio(item: GuiObject): number?
		if resolvedItemAspectRatio == nil then
			return nil
		end
		if not derivesFromParentSize then
			return resolvedItemAspectRatio
		end

		local parentSize = scrollingFrame.AbsoluteSize
		return sizeAspectRatio(item.Size, parentSize.X, parentSize.Y)
	end

	local function constrainItem(item: Instance): ()
		if not item:IsA("GuiObject") or not item.Visible then
			return
		end

		local existingConstraint = item:FindFirstChildWhichIsA("UIAspectRatioConstraint")
		if existingConstraint and existingConstraint.Name ~= CONSTRAINT_NAME then
			return
		end

		local aspectRatio = resolveAspectRatio(item)
		if not aspectRatio then
			return
		end

		local constraint = existingConstraint or Instance.new("UIAspectRatioConstraint")
		constraint.Name = CONSTRAINT_NAME
		constraint.AspectRatio = aspectRatio
		constraint.AspectType = Enum.AspectType.ScaleWithParentSize
		constraint.DominantAxis = Enum.DominantAxis.Width
		if not existingConstraint then
			constraint.Parent = item
			table.insert(createdConstraints, constraint)
		end
	end

	local function constrainItems(): ()
		for _, child in scrollingFrame:GetChildren() do
			constrainItem(child)
		end
	end

	local function updateCanvas(): ()
		if not scrollingFrame.Parent then
			return
		end
		scrollingFrame.CanvasSize = UDim2.fromOffset(
			0,
			paddedSize(layout.AbsoluteContentSize.Y, padding and padding.PaddingTop, padding and padding.PaddingBottom)
		)
	end

	local scheduleUpdate, destroy = newScheduler(updateCanvas)

	local function onResize(): ()
		if derivesFromParentSize then
			constrainItems()
		end
		scheduleUpdate()
	end

	scrollingFrame.AutomaticCanvasSize = Enum.AutomaticSize.None
	constrainItems()

	table.insert(
		connections,
		scrollingFrame.ChildAdded:Connect(function(item: Instance)
			constrainItem(item)
			scheduleUpdate()
		end)
	)
	table.insert(connections, scrollingFrame.ChildRemoved:Connect(scheduleUpdate))
	table.insert(connections, layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(scheduleUpdate))
	table.insert(connections, scrollingFrame:GetPropertyChangedSignal("AbsoluteSize"):Connect(onResize))
	if padding then
		table.insert(connections, padding:GetPropertyChangedSignal("PaddingTop"):Connect(scheduleUpdate))
		table.insert(connections, padding:GetPropertyChangedSignal("PaddingBottom"):Connect(scheduleUpdate))
	end

	scheduleUpdate()

	return function()
		destroy()
		disconnectAll(connections)
		for _, constraint in createdConstraints do
			constraint:Destroy()
		end
	end
end

return LayoutUtil
