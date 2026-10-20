--!strict
--[=[
	@class HighlightUtil

	Adds and removes `Highlight` instances on models and parts, at most one per
	object, with an optional pulsing fill. Each highlighter keeps its own cache, and
	every pulse shares a single Heartbeat connection.

	```lua
	local highlighter = HighlightUtil.new({
		ignore = function(object: Instance): boolean
			return object.Name == "Baseplate"
		end,
	})

	highlighter:add(chest, { outlineColor = Color3.fromRGB(255, 200, 0) })
	highlighter:addPulse(door, { fillColor = Color3.fromRGB(0, 170, 255), pulseSpeed = 2 })

	-- Later
	highlighter:remove(chest)
	highlighter:Destroy() -- removes every highlight it added
	```
]=]

local RunService = game:GetService("RunService")

local DEFAULT_FILL_COLOR = Color3.fromRGB(255, 0, 0)
local DEFAULT_OUTLINE_COLOR = Color3.fromRGB(255, 255, 255)

--[=[
	How a highlight looks. Every field is optional.

	@interface HighlightConfig
	@within HighlightUtil
	.fillColor Color3? -- Defaults to red.
	.fillTransparency number? -- Defaults to 1 (no fill).
	.outlineColor Color3? -- Defaults to white.
	.outlineTransparency number? -- Defaults to 0.
	.depthMode Enum.HighlightDepthMode? -- Defaults to `Occluded`.
]=]
export type HighlightConfig = {
	fillColor: Color3?,
	fillTransparency: number?,
	outlineColor: Color3?,
	outlineTransparency: number?,
	depthMode: Enum.HighlightDepthMode?,
}

--[=[
	Like [HighlightConfig], but the fill transparency pulses between two values.
	Every field is optional.

	@interface PulseConfig
	@within HighlightUtil
	.fillColor Color3?
	.outlineColor Color3?
	.outlineTransparency number?
	.depthMode Enum.HighlightDepthMode?
	.pulseSpeed number? -- Full pulses per two seconds. Defaults to 1.
	.minTransparency number? -- Defaults to 0.3.
	.maxTransparency number? -- Defaults to 0.8.
]=]
export type PulseConfig = {
	fillColor: Color3?,
	outlineColor: Color3?,
	outlineTransparency: number?,
	depthMode: Enum.HighlightDepthMode?,
	pulseSpeed: number?,
	minTransparency: number?,
	maxTransparency: number?,
}

--[=[
	Options for [HighlightUtil.new].

	@interface Options
	@within HighlightUtil
	.ignore ((object: Instance) -> boolean)? -- Objects this returns true for are never highlighted.
	.parent Instance? -- Where highlights are parented. Defaults to the highlighted object.
]=]
export type Options = {
	ignore: ((object: Instance) -> boolean)?,
	parent: Instance?,
}

export type Highlighter = {
	add: (self: Highlighter, object: Instance, config: HighlightConfig?) -> Highlight?,
	addPulse: (self: Highlighter, object: Instance, config: PulseConfig?) -> Highlight?,
	remove: (self: Highlighter, object: Instance) -> (),
	addBulk: (self: Highlighter, objects: { Instance }, config: HighlightConfig?) -> (),
	removeBulk: (self: Highlighter, objects: { Instance }) -> (),
	get: (self: Highlighter, object: Instance) -> Highlight?,
	clear: (self: Highlighter) -> (),
	Destroy: (self: Highlighter) -> (),
}

type Pulse = {
	speed: number,
	min: number,
	max: number,
	startedAt: number,
}

type Entry = {
	highlight: Highlight,
	pulse: Pulse?,
	connection: RBXScriptConnection,
}

local HighlightUtil = {}

--[=[
	Creates a highlighter with its own cache of highlighted objects.

	@within HighlightUtil
	@param options Options?
	@return Highlighter
]=]
function HighlightUtil.new(options: Options?): Highlighter
	local ignore = options and options.ignore
	local parentOverride = options and options.parent
	local entries: { [Instance]: Entry } = {}
	local pulseCount = 0
	local pulseConnection: RBXScriptConnection? = nil

	local function updatePulses(): ()
		local now = os.clock()
		for _, entry in entries do
			local pulse = entry.pulse
			if pulse then
				local wave = math.sin((now - pulse.startedAt) * pulse.speed * math.pi) * 0.5 + 0.5
				entry.highlight.FillTransparency = pulse.min + (pulse.max - pulse.min) * wave
			end
		end
	end

	local function setPulseCount(count: number): ()
		pulseCount = count
		if pulseCount > 0 and not pulseConnection then
			pulseConnection = RunService.Heartbeat:Connect(updatePulses)
		elseif pulseCount == 0 and pulseConnection then
			pulseConnection:Disconnect()
			pulseConnection = nil
		end
	end

	local function forget(object: Instance): Entry?
		local entry = entries[object]
		if not entry then
			return nil
		end
		entries[object] = nil
		entry.connection:Disconnect()
		if entry.pulse then
			setPulseCount(pulseCount - 1)
		end
		return entry
	end

	local function canHighlight(object: Instance?, method: string): boolean
		if not object then
			return false
		end
		if ignore and ignore(object) then
			return false
		end
		if not object:IsA("PVInstance") then
			warn(`[HighlightUtil] {method} called on a non-PVInstance: {object:GetFullName()}`)
			return false
		end
		return true
	end

	local function create(object: Instance, config: HighlightConfig, pulse: Pulse?): Highlight
		local highlight = Instance.new("Highlight")
		highlight.FillColor = config.fillColor or DEFAULT_FILL_COLOR
		highlight.FillTransparency = if pulse then pulse.max else config.fillTransparency or 1
		highlight.OutlineColor = config.outlineColor or DEFAULT_OUTLINE_COLOR
		highlight.OutlineTransparency = config.outlineTransparency or 0
		highlight.DepthMode = config.depthMode or Enum.HighlightDepthMode.Occluded
		highlight.Adornee = object
		highlight.Parent = parentOverride or object

		entries[object] = {
			highlight = highlight,
			pulse = pulse,
			connection = highlight.Destroying:Connect(function()
				local entry = entries[object]
				if entry and entry.highlight == highlight then
					forget(object)
				end
			end),
		}
		if pulse then
			setPulseCount(pulseCount + 1)
		end
		return highlight
	end

	local highlighter = {} :: Highlighter

	--[=[
		Highlights `object`. Does nothing if it is already highlighted, ignored, or not
		a model or part.

		@within HighlightUtil
		@method add
		@param object Instance
		@param config HighlightConfig?
		@return Highlight? -- The object's highlight, new or existing. nil when skipped.
	]=]
	function highlighter.add(_: Highlighter, object: Instance, config: HighlightConfig?): Highlight?
		local existing = entries[object]
		if existing then
			return existing.highlight
		end
		if not canHighlight(object, "add") then
			return nil
		end
		return create(object, config or {}, nil)
	end

	--[=[
		Highlights `object` with a fill that pulses between two transparencies,
		replacing any highlight it already has.

		@within HighlightUtil
		@method addPulse
		@param object Instance
		@param config PulseConfig?
		@return Highlight? -- nil when skipped.
	]=]
	function highlighter.addPulse(self: Highlighter, object: Instance, config: PulseConfig?): Highlight?
		if not canHighlight(object, "addPulse") then
			return nil
		end
		self:remove(object)
		local pulseConfig: PulseConfig = config or {}
		return create(object, {
			fillColor = pulseConfig.fillColor,
			outlineColor = pulseConfig.outlineColor,
			outlineTransparency = pulseConfig.outlineTransparency,
			depthMode = pulseConfig.depthMode,
		}, {
			speed = pulseConfig.pulseSpeed or 1,
			min = pulseConfig.minTransparency or 0.3,
			max = pulseConfig.maxTransparency or 0.8,
			startedAt = os.clock(),
		})
	end

	--[=[
		Removes the highlight from `object`, if it has one.

		@within HighlightUtil
		@method remove
		@param object Instance
	]=]
	function highlighter.remove(_: Highlighter, object: Instance): ()
		local entry = forget(object)
		if entry then
			entry.highlight:Destroy()
		end
	end

	--[=[
		Calls `add` for each object.

		@within HighlightUtil
		@method addBulk
		@param objects { Instance }
		@param config HighlightConfig?
	]=]
	function highlighter.addBulk(self: Highlighter, objects: { Instance }, config: HighlightConfig?): ()
		for _, object in objects do
			self:add(object, config)
		end
	end

	--[=[
		Calls `remove` for each object.

		@within HighlightUtil
		@method removeBulk
		@param objects { Instance }
	]=]
	function highlighter.removeBulk(self: Highlighter, objects: { Instance }): ()
		for _, object in objects do
			self:remove(object)
		end
	end

	--[=[
		The highlight this highlighter added to `object`.

		@within HighlightUtil
		@method get
		@param object Instance
		@return Highlight?
	]=]
	function highlighter.get(_: Highlighter, object: Instance): Highlight?
		local entry = entries[object]
		return entry and entry.highlight
	end

	--[=[
		Removes every highlight this highlighter added.

		@within HighlightUtil
		@method clear
	]=]
	function highlighter.clear(self: Highlighter): ()
		for object in entries do
			self:remove(object)
		end
	end

	--[=[
		Removes every highlight. The highlighter can still be used afterwards.

		@within HighlightUtil
		@method Destroy
	]=]
	function highlighter.Destroy(self: Highlighter): ()
		self:clear()
	end

	return highlighter
end

return table.freeze(HighlightUtil)
