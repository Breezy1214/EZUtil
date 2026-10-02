--!strict
--[=[
	@class ParticleUtil

	Helpers for particle effects: waiting for effect templates, emitting one-shot
	bursts, and switching effects off so their particles fade out before cleanup.

	Burst templates are Attachments whose ParticleEmitters use these attributes:
	- `EmitCount` (number): how many particles to emit. Emitters without it are skipped.
	- `EmitDelay` (number, optional): seconds to wait before emitting.
]=]

local Debris = game:GetService("Debris")

local CLEANUP_PADDING = 0.5
local TEMPLATE_TIMEOUT = 5

local ParticleUtil = {}

local function numberAttribute(instance: Instance, name: string): number?
	local value = instance:GetAttribute(name)
	return if typeof(value) == "number" then value else nil
end

local function getLifetime(emitter: ParticleEmitter): number
	return emitter.Lifetime.Max / math.max(emitter.TimeScale, 1e-3)
end

local function emit(emitter: ParticleEmitter, count: number, delay: number): ()
	if delay <= 0 then
		emitter:Emit(count)
		return
	end

	task.delay(delay, function()
		if emitter.Parent then
			emitter:Emit(count)
		end
	end)
end

local function waitForAsset(folder: Instance, name: string, className: string): Instance?
	local asset = folder:WaitForChild(name, TEMPLATE_TIMEOUT)

	if not asset or not asset:IsA(className) then
		warn(`[ParticleUtil] {folder:GetFullName()}.{name} must be a {className}`)
		return nil
	end

	return asset
end

--[=[
	Waits up to 5 seconds for an Attachment named `name` in `folder`. Warns and
	returns nil if it does not appear or is not an Attachment.

	@within ParticleUtil
	@yields
	@param name string
	@param folder Instance
	@return Attachment?
]=]
function ParticleUtil.waitForTemplate(name: string, folder: Instance): Attachment?
	return waitForAsset(folder, name, "Attachment") :: Attachment?
end

--[=[
	Waits up to 5 seconds for a BasePart named `name` in `folder`. Warns and returns
	nil if it does not appear or is not a BasePart.

	@within ParticleUtil
	@yields
	@param name string
	@param folder Instance
	@return BasePart?
]=]
function ParticleUtil.waitForPart(name: string, folder: Instance): BasePart?
	return waitForAsset(folder, name, "BasePart") :: BasePart?
end

--[=[
	Waits up to 5 seconds for a Model named `name` in `folder`. Warns and returns nil
	if it does not appear or is not a Model.

	@within ParticleUtil
	@yields
	@param name string
	@param folder Instance
	@return Model?
]=]
function ParticleUtil.waitForModel(name: string, folder: Instance): Model?
	return waitForAsset(folder, name, "Model") :: Model?
end

--[=[
	Clones `template` into `workspace.Terrain` at `cframe` and emits every
	ParticleEmitter that has an `EmitCount` attribute, after its optional
	`EmitDelay`. The clone is removed once the last particle can have expired.

	```lua
	local template = ParticleUtil.waitForTemplate("Explosion", ReplicatedStorage.Effects)
	if template then
		ParticleUtil.burst(template, CFrame.new(position))
	end
	```

	@within ParticleUtil
	@param template Attachment
	@param cframe CFrame -- The world CFrame to emit from.
]=]
function ParticleUtil.burst(template: Attachment, cframe: CFrame): ()
	local attachment = template:Clone()
	attachment.Parent = workspace.Terrain
	attachment.WorldCFrame = cframe

	local lifetime = 0

	for _, descendant in attachment:GetDescendants() do
		if not descendant:IsA("ParticleEmitter") then
			continue
		end

		local count = numberAttribute(descendant, "EmitCount")
		local delay = numberAttribute(descendant, "EmitDelay") or 0

		if count then
			emit(descendant, count, delay)
			lifetime = math.max(lifetime, delay + getLifetime(descendant))
		end
	end

	Debris:AddItem(attachment, lifetime + CLEANUP_PADDING)
end

--[=[
	Sets `Enabled` on every ParticleEmitter under `root`.

	@within ParticleUtil
	@param root Instance
	@param enabled boolean
]=]
function ParticleUtil.setEnabled(root: Instance, enabled: boolean): ()
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = enabled
		end
	end
end

--[=[
	Disables every ParticleEmitter and Light under `root`, then destroys `root` once
	the particles already emitted have had time to expire.

	@within ParticleUtil
	@param root Instance
]=]
function ParticleUtil.release(root: Instance): ()
	local lifetime = 0

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("ParticleEmitter") then
			descendant.Enabled = false
			lifetime = math.max(lifetime, getLifetime(descendant))
		elseif descendant:IsA("Light") then
			descendant.Enabled = false
		end
	end

	Debris:AddItem(root, lifetime)
end

return ParticleUtil
