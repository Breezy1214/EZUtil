--!strict
--[=[
	@class DragDrop
	@client

	A UI drag-and-drop controller. Sources are GuiObjects that get a `UIDragDetector`;
	targets are GuiObjects that a drag can be released on. Each controller owns its
	sources and targets, runs at most one drag at a time, and reports everything
	through callbacks, so the game decides what a drop means.

	A press stays pending until the pointer moves `moveThreshold` pixels, then it
	becomes a drag. On touch, a press inside an overflowing ScrollingFrame scrolls the
	frame instead, unless it is held still for `touchHoldTime` seconds first. A press
	that never moves is a tap: an enabled `UIDragDetector` swallows its button's
	`Activated`, so taps come back through the source's `onTap`. A new press cancels a
	pending press, or any press from the same source, whose release was never reported.

	```lua
	local drag = DragDrop.new({
		ghost = function(itemId: string): GuiObject
			local ghost = template:Clone()
			ghost.Icon.Image = icons[itemId]
			return ghost
		end,
		onClearing = function(clearing: boolean)
			ghostStroke.Color = if clearing then Color3.new(1, 0, 0) else Color3.new(1, 1, 1)
		end,
		onDrop = function(itemId: string, _sourceId, slot)
			if slot then
				equip(itemId, slot)
			else
				unequip(itemId)
			end
		end,
	})

	for index, slotFrame in hotbarSlots do
		drag:addTarget(index, slotFrame)
		drag:addSource(index, slotFrame, {
			payload = function()
				return hotbar[index]
			end,
			targetId = index, -- dropping back onto its own slot snaps back
			canClear = true, -- releasing away from every slot calls onDrop with no target
			onTap = function()
				select(index)
			end,
		})
	end

	-- When the hotbar changes
	drag:refresh()

	-- When the UI is destroyed
	drag:Destroy()
	```
]=]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Janitor = require(script.Parent.Parent.Janitor)
local LayoutUtil = require(script.Parent.LayoutUtil)

local DEFAULT_MOVE_THRESHOLD = 8
local DEFAULT_TOUCH_HOLD_TIME = 0.25
local DEFAULT_SNAP_BACK_TIME = 0.12
local DEFAULT_DISPLAY_ORDER = 100
local SCROLL_OVERFLOW = 1
local SCROLL_TOLERANCE = 0.5

--[=[
	A source or target id, such as a slot index or an item name.

	@type Id string | number
	@within DragDrop
]=]
export type Id = string | number

--[=[
	How the ghost is sized. The reference's size is multiplied by `scale`, then scaled
	uniformly so its width stays between `min` and `max` pixels.

	@interface GhostSize
	@within DragDrop
	.reference (GuiObject | () -> GuiObject?)? -- Defaults to the dragged source.
	.scale number? -- Defaults to 1.
	.min number? -- Minimum width in pixels. Defaults to 0.
	.max number? -- Maximum width in pixels. Defaults to no limit.
]=]
export type GhostSize = {
	reference: (GuiObject | () -> GuiObject?)?,
	scale: number?,
	min: number?,
	max: number?,
}

--[=[
	Options for [DragDrop.new]. Every field is optional.

	@interface Options
	@within DragDrop
	.moveThreshold number? -- Pixels a press moves before it becomes a drag or a scroll. Defaults to 8.
	.touchHoldTime number? -- Seconds a touch press inside a scroll list is held still before it becomes a drag. Defaults to 0.25.
	.slop number? -- Pixels added around every target's rect when hit-testing. Defaults to 0.
	.trackCenter boolean? -- Hit-test and place the ghost at the source's centre plus the pointer's movement, instead of at the pointer. Defaults to false.
	.safeZone (GuiObject | () -> GuiObject?)? -- Releasing inside this GuiObject, away from every target, cancels instead of clearing. A function is called on every move, so the zone can be built after the controller.
	.ghost ((payload: T, sourceId: Id) -> GuiObject)? -- Builds the ghost that follows the drag. No ghost without it.
	.ghostParent GuiBase2d? -- Where ghosts are parented. Defaults to a ScreenGui the controller creates in PlayerGui.
	.ghostDisplayOrder number? -- DisplayOrder of the created ScreenGui. Defaults to 100.
	.ghostSize GhostSize? -- Defaults to the source's size.
	.snapBackTime number? -- Seconds the ghost tweens back to its source on cancel. 0 removes it at once. Defaults to 0.12.
	.clickSound (() -> ())? -- Called before a tap's `onTap` while the game is running.
	.hoverSound (() -> ())? -- Called when a drag enters a target while the game is running.
	.onDragStart ((payload: T, sourceId: Id) -> ())?
	.onMove ((point: Vector2) -> ())? -- The drag's hit point, in absolute pixels, on every move.
	.onTargetChanged ((targetId: Id?) -> ())?
	.onClearing ((clearing: boolean) -> ())? -- Whether releasing now would clear: away from every target, from a source with `canClear`.
	.onDrop ((payload: T, sourceId: Id, targetId: Id?) -> ())? -- `targetId` is nil when the drag was released to clear.
	.onCancel ((payload: T, sourceId: Id) -> ())? -- Called once the snap-back finishes.
]=]
export type Options<T> = {
	moveThreshold: number?,
	touchHoldTime: number?,
	slop: number?,
	trackCenter: boolean?,
	safeZone: (GuiObject | () -> GuiObject?)?,
	ghost: ((payload: T, sourceId: Id) -> GuiObject)?,
	ghostParent: GuiBase2d?,
	ghostDisplayOrder: number?,
	ghostSize: GhostSize?,
	snapBackTime: number?,
	clickSound: (() -> ())?,
	hoverSound: (() -> ())?,
	onDragStart: ((payload: T, sourceId: Id) -> ())?,
	onMove: ((point: Vector2) -> ())?,
	onTargetChanged: ((targetId: Id?) -> ())?,
	onClearing: ((clearing: boolean) -> ())?,
	onDrop: ((payload: T, sourceId: Id, targetId: Id?) -> ())?,
	onCancel: ((payload: T, sourceId: Id) -> ())?,
}

--[=[
	Options for [DragDrop:addSource].

	@interface SourceOptions
	@within DragDrop
	.payload () -> T? -- What a drag from this source carries. nil means there is nothing to drag.
	.enabled (() -> boolean)? -- Whether the source can be dragged. Re-read by `refresh`.
	.onTap (() -> ())? -- A press that never became a drag.
	.canClear boolean? -- Releasing away from every target calls `onDrop` with no target, instead of cancelling.
	.targetId Id? -- The target this source sits on. Releasing onto it cancels.
	.safeZone (GuiObject | () -> GuiObject?)? -- Overrides the controller's `safeZone` for drags from this source.
]=]
export type SourceOptions<T> = {
	payload: () -> T?,
	enabled: (() -> boolean)?,
	onTap: (() -> ())?,
	canClear: boolean?,
	targetId: Id?,
	safeZone: (GuiObject | () -> GuiObject?)?,
}

--[=[
	Options for [DragDrop:addTarget].

	@interface TargetOptions
	@within DragDrop
	.accept ((payload: T, targetId: Id) -> boolean)? -- Whether this target takes a payload. Defaults to always.
	.slop number? -- Overrides the controller's `slop` for this target.
]=]
export type TargetOptions<T> = {
	accept: ((payload: T, targetId: Id) -> boolean)?,
	slop: number?,
}

--[=[
	A registered source, returned by [DragDrop:addSource].

	@interface Source
	@within DragDrop
	.refresh (self: Source) -> () -- Re-reads `enabled` and `payload`, and cancels this source's drag if it can no longer drag.
	.Destroy (self: Source) -> () -- Removes the detector and cancels this source's drag.
]=]
export type Source = {
	refresh: (self: Source) -> (),
	Destroy: (self: Source) -> (),
}

export type DragDrop<T> = {
	addSource: (self: DragDrop<T>, id: Id, gui: GuiObject, options: SourceOptions<T>) -> Source,
	addTarget: (self: DragDrop<T>, id: Id, gui: GuiObject, options: TargetOptions<T>?) -> () -> (),
	removeTarget: (self: DragDrop<T>, id: Id) -> (),
	refresh: (self: DragDrop<T>) -> (),
	cancel: (self: DragDrop<T>) -> (),
	isDragging: (self: DragDrop<T>) -> boolean,
	getActive: (self: DragDrop<T>) -> (T?, Id?),
	Destroy: (self: DragDrop<T>) -> (),
}

type Mode = "Pending" | "Scroll" | "Drag"

type SourceRecord<T> = {
	id: Id,
	gui: GuiObject,
	detector: UIDragDetector,
	options: SourceOptions<T>,
	destroy: () -> (),
}

type TargetRecord<T> = {
	id: Id,
	gui: GuiObject,
	options: TargetOptions<T>?,
	connection: RBXScriptConnection,
}

type Press<T> = {
	source: SourceRecord<T>,
	payload: T,
	start: Vector2,
	last: Vector2,
	startCenter: Vector2,
	mode: Mode,
	scroller: ScrollingFrame?,
	canvas: Vector2,
	written: Vector2,
	target: Id?,
	clearing: boolean,
	ghost: GuiObject?,
}

local DragDrop = {}

local function isShown(gui: GuiObject): boolean
	local node: Instance? = gui
	while node do
		if node:IsA("GuiObject") then
			if not node.Visible then
				return false
			end
		elseif node:IsA("LayerCollector") then
			return node.Enabled
		end
		node = node.Parent
	end
	return false
end

local function containsPoint(gui: GuiObject, point: Vector2, slop: number): boolean
	local min = gui.AbsolutePosition - Vector2.one * slop
	local max = gui.AbsolutePosition + gui.AbsoluteSize + Vector2.one * slop
	return point.X >= min.X and point.X <= max.X and point.Y >= min.Y and point.Y <= max.Y
end

local function resolve(gui: (GuiObject | () -> GuiObject?)?): GuiObject?
	return if typeof(gui) == "function" then (gui :: () -> GuiObject?)() else gui :: GuiObject?
end

local function centerOf(gui: GuiObject): Vector2
	return gui.AbsolutePosition + gui.AbsoluteSize / 2
end

-- UIDragDetector reports positions relative to its LayerCollector, which is offset by the GUI inset.
local function toAbsolute(detector: UIDragDetector, position: Vector2): Vector2
	local layer = detector:FindFirstAncestorWhichIsA("LayerCollector")
	return if layer then position + layer.AbsolutePosition else position
end

local function scrollerFor(gui: GuiObject): ScrollingFrame?
	if UserInputService:GetLastInputType() ~= Enum.UserInputType.Touch then
		return nil
	end
	local scroller = gui:FindFirstAncestorWhichIsA("ScrollingFrame")
	if not scroller or not scroller.ScrollingEnabled then
		return nil
	end
	local overflow = scroller.AbsoluteCanvasSize - scroller.AbsoluteWindowSize
	local direction = scroller.ScrollingDirection
	local scrollsX = direction ~= Enum.ScrollingDirection.Y and overflow.X > SCROLL_OVERFLOW
	local scrollsY = direction ~= Enum.ScrollingDirection.X and overflow.Y > SCROLL_OVERFLOW
	return if scrollsX or scrollsY then scroller else nil
end

--[=[
	Creates a drag-and-drop controller. See [DragDrop] for an example.

	@within DragDrop
	@client
	@param options Options<T>?
	@return DragDrop<T>
]=]
function DragDrop.new<T>(options: Options<T>?): DragDrop<T>
	local config: Options<T> = options or {}
	local moveThreshold = config.moveThreshold or DEFAULT_MOVE_THRESHOLD
	local touchHoldTime = config.touchHoldTime or DEFAULT_TOUCH_HOLD_TIME
	local defaultSlop = config.slop or 0
	local snapBackTime = config.snapBackTime or DEFAULT_SNAP_BACK_TIME

	local janitor = Janitor.new()
	local sources: { [SourceRecord<T>]: true } = {}
	local targets: { TargetRecord<T> } = {}
	local press: Press<T>? = nil
	local snapping: { press: Press<T>, tween: Tween }? = nil
	local ghostScreen: ScreenGui? = nil
	local destroyed = false

	local function playSound(sound: (() -> ())?): ()
		if sound and RunService:IsRunning() then
			sound()
		end
	end

	local function targetAt(point: Vector2, payload: T): Id?
		for _, target in targets do
			local targetOptions = target.options
			local slop = if targetOptions and targetOptions.slop then targetOptions.slop else defaultSlop
			if containsPoint(target.gui, point, slop) and isShown(target.gui) then
				local accept = targetOptions and targetOptions.accept
				if not accept or accept(payload, target.id) then
					return target.id
				end
			end
		end
		return nil
	end

	local function ghostLayer(source: GuiObject): GuiBase2d
		if config.ghostParent then
			return config.ghostParent
		end
		local screen = ghostScreen
		if screen and screen.Parent then
			return screen
		end
		local player = Players.LocalPlayer
		local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return source:FindFirstAncestorWhichIsA("LayerCollector") or source
		end
		local created = Instance.new("ScreenGui")
		created.Name = "DragDropGhost"
		created.DisplayOrder = config.ghostDisplayOrder or DEFAULT_DISPLAY_ORDER
		created.IgnoreGuiInset = true
		created.ResetOnSpawn = false
		created.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		created.Parent = playerGui
		janitor:Add(created, "Destroy", "GhostScreen")
		ghostScreen = created
		return created
	end

	local function parentScale(ghost: GuiObject): number
		local parent = ghost.Parent
		return if parent then LayoutUtil.getInheritedScale(parent) else 1
	end

	-- Converts an absolute point to an offset inside the ghost's parent, undoing any UIScale above it.
	local function toLocal(ghost: GuiObject, point: Vector2): UDim2
		local parent = ghost.Parent
		local origin = if parent and parent:IsA("GuiBase2d") then parent.AbsolutePosition else Vector2.zero
		local offset = (point - origin) / parentScale(ghost)
		return UDim2.fromOffset(offset.X, offset.Y)
	end

	local function sizeGhost(ghost: GuiObject, source: GuiObject): ()
		local sizing = config.ghostSize
		local reference = sizing and resolve(sizing.reference)
		local size = (reference or source).AbsoluteSize * (if sizing and sizing.scale then sizing.scale else 1)
		if sizing and size.X > 0 then
			local width = math.clamp(math.round(size.X), sizing.min or 0, sizing.max or math.huge)
			size = Vector2.new(width, math.round(size.Y * width / size.X))
		end
		local scale = parentScale(ghost)
		ghost.Size = UDim2.fromOffset(size.X / scale, size.Y / scale)
	end

	local function destroyGhost(current: Press<T>): ()
		local ghost = current.ghost
		current.ghost = nil
		if ghost then
			ghost:Destroy()
		end
	end

	local function setTarget(current: Press<T>, target: Id?): ()
		if current.target == target then
			return
		end
		current.target = target
		if target ~= nil then
			playSound(config.hoverSound)
		end
		if config.onTargetChanged then
			config.onTargetChanged(target)
		end
	end

	local function setClearing(current: Press<T>, clearing: boolean): ()
		if current.clearing == clearing then
			return
		end
		current.clearing = clearing
		if config.onClearing then
			config.onClearing(clearing)
		end
	end

	local function isInSafeZone(current: Press<T>, point: Vector2): boolean
		local safeZone = resolve(current.source.options.safeZone or config.safeZone)
		return safeZone ~= nil and containsPoint(safeZone, point, 0) and isShown(safeZone)
	end

	local function update(current: Press<T>, pointer: Vector2): ()
		local point = if config.trackCenter then current.startCenter + (pointer - current.start) else pointer
		local ghost = current.ghost
		if ghost then
			ghost.Position = toLocal(ghost, point)
		end
		local target = targetAt(point, current.payload)
		setTarget(current, target)
		setClearing(
			current,
			target == nil and current.source.options.canClear == true and not isInSafeZone(current, point)
		)
		if config.onMove then
			config.onMove(point)
		end
	end

	local function settle(current: Press<T>): ()
		destroyGhost(current)
		if config.onCancel then
			config.onCancel(current.payload, current.source.id)
		end
	end

	local function flushSnap(): ()
		local active = snapping
		snapping = nil
		if active then
			active.tween:Cancel()
			settle(active.press)
		end
	end

	local function snapBack(current: Press<T>): ()
		local ghost = current.ghost
		local source = current.source.gui
		if destroyed or not ghost or snapBackTime <= 0 or not source:IsDescendantOf(game) then
			settle(current)
			return
		end
		local tween = TweenService:Create(
			ghost,
			TweenInfo.new(snapBackTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = toLocal(ghost, centerOf(source)) }
		)
		snapping = { press = current, tween = tween }
		tween.Completed:Once(function()
			local active = snapping
			if active and active.tween == tween then
				snapping = nil
				settle(current)
			end
		end)
		tween:Play()
	end

	local function begin(current: Press<T>): ()
		flushSnap()
		current.mode = "Drag"
		local factory = config.ghost
		if factory then
			local ghost = factory(current.payload, current.source.id)
			ghost.AnchorPoint = Vector2.new(0.5, 0.5)
			ghost.Parent = ghostLayer(current.source.gui)
			sizeGhost(ghost, current.source.gui)
			current.ghost = ghost
		end
		if config.onDragStart then
			config.onDragStart(current.payload, current.source.id)
		end
		update(current, current.last)
	end

	local function finish(current: Press<T>, cancelled: boolean): ()
		press = nil
		if current.mode == "Pending" and not cancelled then
			playSound(config.clickSound)
			local onTap = current.source.options.onTap
			if onTap then
				onTap()
			end
			return
		end
		if current.mode ~= "Drag" then
			return
		end

		local target, clearing = current.target, current.clearing
		setTarget(current, nil)
		setClearing(current, false)
		local ownTarget = current.source.options.targetId
		local drops = not cancelled and (if target ~= nil then target ~= ownTarget else clearing)
		if not drops then
			snapBack(current)
			return
		end

		destroyGhost(current)
		if config.onDrop then
			config.onDrop(current.payload, current.source.id, target)
		end
	end

	local function scroll(current: Press<T>, pointer: Vector2): ()
		local scroller = current.scroller
		if not scroller then
			return
		end
		-- Something else moved the canvas (such as native touch scrolling), so stop driving it.
		if (scroller.CanvasPosition - current.written).Magnitude > SCROLL_TOLERANCE then
			current.scroller = nil
			return
		end
		local limit = scroller.AbsoluteCanvasSize - scroller.AbsoluteWindowSize
		local direction = scroller.ScrollingDirection
		local wanted = current.canvas - (pointer - current.start)
		local written = Vector2.new(
			if direction == Enum.ScrollingDirection.Y
				then current.canvas.X
				else math.clamp(wanted.X, 0, math.max(0, limit.X)),
			if direction == Enum.ScrollingDirection.X
				then current.canvas.Y
				else math.clamp(wanted.Y, 0, math.max(0, limit.Y))
		)
		scroller.CanvasPosition = written
		current.written = written
	end

	local function draggablePayload(record: SourceRecord<T>): T?
		local enabled = record.options.enabled
		if enabled and not enabled() then
			return nil
		end
		return record.options.payload()
	end

	local function onStart(record: SourceRecord<T>, pointer: Vector2): ()
		if destroyed then
			return
		end
		local previous = press
		if previous then
			-- Its release was never reported, unless it is another source's drag (multi-touch).
			if previous.source ~= record and previous.mode ~= "Pending" then
				return
			end
			finish(previous, true)
		end
		local payload = draggablePayload(record)
		if payload == nil then
			return
		end

		local scroller = scrollerFor(record.gui)
		local canvas = if scroller then scroller.CanvasPosition else Vector2.zero
		local current: Press<T> = {
			source = record,
			payload = payload,
			start = pointer,
			last = pointer,
			startCenter = centerOf(record.gui),
			mode = "Pending",
			scroller = scroller,
			canvas = canvas,
			written = canvas,
			target = nil,
			clearing = false,
			ghost = nil,
		}
		press = current

		if scroller then
			task.delay(touchHoldTime, function()
				if press == current and current.mode == "Pending" then
					begin(current)
				end
			end)
		end
	end

	local function onMove(record: SourceRecord<T>, pointer: Vector2): ()
		local current = press
		if not current or current.source ~= record then
			return
		end
		current.last = pointer

		if current.mode == "Pending" then
			if (pointer - current.start).Magnitude < moveThreshold then
				return
			end
			if not current.scroller then
				begin(current)
				return
			end
			current.mode = "Scroll"
		end

		if current.mode == "Scroll" then
			scroll(current, pointer)
		else
			update(current, pointer)
		end
	end

	local function onEnd(record: SourceRecord<T>, pointer: Vector2): ()
		local current = press
		if not current or current.source ~= record then
			return
		end
		if current.mode == "Drag" then
			update(current, pointer)
		end
		finish(current, false)
	end

	local function cancelFrom(record: SourceRecord<T>?): ()
		local current = press
		if current and (record == nil or current.source == record) then
			finish(current, true)
		end
	end

	local function refreshSource(record: SourceRecord<T>): ()
		local active = draggablePayload(record) ~= nil
		record.detector.Enabled = active
		if not active then
			cancelFrom(record)
		end
	end

	local function removeTarget(id: Id): ()
		for index, target in targets do
			if target.id == id then
				target.connection:Disconnect()
				table.remove(targets, index)
				return
			end
		end
	end

	local controller = {} :: DragDrop<T>

	--[=[
		Parents a `UIDragDetector` to `gui` and makes it a drag source. The source is
		removed when `gui` is destroyed.

		@within DragDrop
		@method addSource
		@param id Id -- Passed back to the callbacks as `sourceId`.
		@param gui GuiObject
		@param options SourceOptions<T>
		@return Source
	]=]
	function controller.addSource(_: DragDrop<T>, id: Id, gui: GuiObject, sourceOptions: SourceOptions<T>): Source
		assert(not destroyed, "DragDrop controller is destroyed")
		local sourceJanitor = Janitor.new()
		local alive = true

		local detector = Instance.new("UIDragDetector")
		detector.Name = "DragDrop"
		detector.ResponseStyle = Enum.UIDragDetectorResponseStyle.CustomOffset
		sourceJanitor:Add(detector, "Destroy")

		local record: SourceRecord<T>
		local function destroySource(): ()
			if not alive then
				return
			end
			alive = false
			sources[record] = nil
			cancelFrom(record)
			sourceJanitor:Destroy()
		end

		record = {
			id = id,
			gui = gui,
			detector = detector,
			options = sourceOptions,
			destroy = destroySource,
		}

		sourceJanitor:Add(detector.DragStart:Connect(function(position: Vector2)
			onStart(record, toAbsolute(detector, position))
		end))
		sourceJanitor:Add(detector.DragContinue:Connect(function(position: Vector2)
			onMove(record, toAbsolute(detector, position))
		end))
		sourceJanitor:Add(detector.DragEnd:Connect(function(position: Vector2)
			onEnd(record, toAbsolute(detector, position))
		end))
		sourceJanitor:Add(gui.Destroying:Connect(destroySource))

		sources[record] = true
		refreshSource(record)
		detector.Parent = gui

		local handle = {} :: Source
		function handle.refresh(_: Source): ()
			if alive then
				refreshSource(record)
			end
		end
		function handle.Destroy(_: Source): ()
			destroySource()
		end
		return handle
	end

	--[=[
		Registers `gui` as a drop target. A target is hit when the drag's point is
		inside its rect plus slop, it and every ancestor are visible, and `accept`
		takes the payload. Targets are tested in the order they were added; adding an
		id again replaces it. The target is removed when `gui` is destroyed.

		@within DragDrop
		@method addTarget
		@param id Id -- Passed to the callbacks as `targetId`.
		@param gui GuiObject
		@param options TargetOptions<T>?
		@return () -> () -- Removes the target.
	]=]
	function controller.addTarget(_: DragDrop<T>, id: Id, gui: GuiObject, targetOptions: TargetOptions<T>?): () -> ()
		assert(not destroyed, "DragDrop controller is destroyed")
		removeTarget(id)
		local record: TargetRecord<T>
		local function remove(): ()
			if table.find(targets, record) then
				removeTarget(id)
			end
		end
		record = {
			id = id,
			gui = gui,
			options = targetOptions,
			connection = gui.Destroying:Connect(remove),
		}
		table.insert(targets, record)
		return remove
	end

	--[=[
		Removes a drop target.

		@within DragDrop
		@method removeTarget
		@param id Id
	]=]
	function controller.removeTarget(_: DragDrop<T>, id: Id): ()
		removeTarget(id)
	end

	--[=[
		Re-reads every source's `enabled` and `payload`. Call it when the state they
		read changes; a source that can no longer drag cancels its drag.

		@within DragDrop
		@method refresh
	]=]
	function controller.refresh(_: DragDrop<T>): ()
		for record in sources do
			refreshSource(record)
		end
	end

	--[=[
		Cancels the current press or drag. The ghost snaps back, then `onCancel` runs.

		@within DragDrop
		@method cancel
	]=]
	function controller.cancel(_: DragDrop<T>): ()
		cancelFrom(nil)
	end

	--[=[
		Whether a drag is in progress. A pending press or a touch scroll is not a drag.

		@within DragDrop
		@method isDragging
		@return boolean
	]=]
	function controller.isDragging(_: DragDrop<T>): boolean
		local current = press
		return current ~= nil and current.mode == "Drag"
	end

	--[=[
		The payload and source id of the drag in progress.

		@within DragDrop
		@method getActive
		@return T? -- nil when nothing is being dragged.
		@return Id?
	]=]
	function controller.getActive(_: DragDrop<T>): (T?, Id?)
		local current = press
		if current and current.mode == "Drag" then
			return current.payload, current.source.id
		end
		return nil, nil
	end

	--[=[
		Cancels any drag at once (`onCancel` still runs), removes every detector and
		target, and destroys the ghost and the ScreenGui the controller created.

		@within DragDrop
		@method Destroy
	]=]
	function controller.Destroy(_: DragDrop<T>): ()
		if destroyed then
			return
		end
		destroyed = true
		cancelFrom(nil)
		flushSnap()
		for record in sources do
			record.destroy()
		end
		for _, target in targets do
			target.connection:Disconnect()
		end
		table.clear(targets)
		janitor:Destroy()
	end

	return controller
end

return table.freeze(DragDrop)
