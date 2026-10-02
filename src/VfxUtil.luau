--!strict
--[=[
	@class VfxUtil

	Plays VFX templates: BaseParts holding ParticleEmitters, Lights and other parts.
	Emitters are configured with attributes:
	- `EmitCount` (number): particles to emit. Defaults to the emitter's `Rate`.
	- `EmitDelay` (number): seconds to wait before starting. Defaults to 0.
	- `EmitDuration` (number): when above 0, the emitter is enabled for this many
	  seconds instead of emitting `EmitCount` once. Falls back to the template
	  part's own `EmitDuration` attribute, then 0.
]=]

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local VfxUtil = {}

local LIGHT_FADE_TIME = 0.35
local CLEANUP_GRACE = 0.5

local function numberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

local function startEmitter(emitter: ParticleEmitter, count: number, duration: number): ()
	if not emitter.Parent then
		return
	end

	if duration <= 0 then
		emitter:Emit(count)
		return
	end

	emitter.Enabled = true
	task.delay(duration, function(): ()
		if emitter.Parent then
			emitter.Enabled = false
		end
	end)
end

local function neuter(part: BasePart): ()
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Massless = true
end

local function playDescendants(root: BasePart): number
	local rootDuration = numberAttribute(root, "EmitDuration") or 0
	local longest = 0

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitter = descendant :: ParticleEmitter
			local count = numberAttribute(emitter, "EmitCount") or emitter.Rate
			local emitDelay = numberAttribute(emitter, "EmitDelay") or 0
			local duration = numberAttribute(emitter, "EmitDuration") or rootDuration

			emitter.Enabled = false
			longest = math.max(longest, emitDelay + duration + emitter.Lifetime.Max)

			if emitDelay <= 0 then
				startEmitter(emitter, count, duration)
			else
				task.delay(emitDelay, startEmitter, emitter, count, duration)
			end
		elseif descendant:IsA("Light") then
			local light = descendant :: Light
			TweenService:Create(light, TweenInfo.new(LIGHT_FADE_TIME), { Brightness = 0 }):Play()
		elseif descendant:IsA("BasePart") then
			neuter(descendant)
		end
	end

	return longest
end

--[=[
	Returns a CFrame at `position` that keeps the template's own rotation.

	@within VfxUtil
	@param template BasePart
	@param position Vector3
	@return CFrame
]=]
function VfxUtil.uprightAt(template: BasePart, position: Vector3): CFrame
	return CFrame.new(position) * template.CFrame.Rotation
end

--[=[
	Plays a one-shot copy of `template` at `cframe`. The clone and every part inside
	it are anchored and made non-colliding, each ParticleEmitter is played according
	to its attributes, Lights fade to zero brightness over 0.35 seconds, and the
	clone is destroyed once its longest emitter has finished.

	```lua
	VfxUtil.play(effects.Slam, VfxUtil.uprightAt(effects.Slam, hitPosition))
	```

	@within VfxUtil
	@param template BasePart
	@param cframe CFrame
	@param parent Instance? -- Defaults to `workspace`.
	@return BasePart -- The playing clone.
]=]
function VfxUtil.play(template: BasePart, cframe: CFrame, parent: Instance?): BasePart
	local clone = template:Clone()
	neuter(clone)
	clone.CFrame = cframe
	clone.Parent = parent or workspace

	Debris:AddItem(clone, playDescendants(clone) + CLEANUP_GRACE)

	return clone
end

--[=[
	Welds a copy of `template` to `part` and enables all of its emitters, returning
	the stop function. Stopping switches the emitters and lights off, which lets the
	particles already in flight fade out on their own before the clone is cleaned up.
	Calling the stop function more than once does nothing.

	```lua
	local stop = VfxUtil.attach(effects.Aura, character.HumanoidRootPart)
	task.wait(5)
	stop()
	```

	@within VfxUtil
	@param template BasePart
	@param part BasePart -- The part to weld the effect to.
	@return () -> () -- Stops the effect and cleans it up.
]=]
function VfxUtil.attach(template: BasePart, part: BasePart): () -> ()
	local clone = template:Clone()
	clone.Anchored = false
	clone.CanCollide = false
	clone.CanQuery = false
	clone.CanTouch = false
	clone.Massless = true
	clone.CFrame = part.CFrame
	clone.Parent = part

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = part
	weld.Part1 = clone
	weld.Parent = clone

	local lifetime = 0
	for _, descendant in clone:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			local emitter = descendant :: ParticleEmitter
			lifetime = math.max(lifetime, emitter.Lifetime.Max)
			emitter.Enabled = true
		end
	end

	local stopped = false
	return function(): ()
		if stopped then
			return
		end
		stopped = true

		for _, descendant in clone:GetDescendants() do
			if descendant:IsA("ParticleEmitter") then
				local emitter = descendant :: ParticleEmitter
				emitter.Enabled = false
			elseif descendant:IsA("Light") then
				local light = descendant :: Light
				light.Enabled = false
			end
		end

		Debris:AddItem(clone, lifetime + CLEANUP_GRACE)
	end
end

return table.freeze(VfxUtil)
