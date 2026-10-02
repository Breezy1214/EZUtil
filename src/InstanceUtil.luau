--!strict
--!optimize 2
--[=[
	@class InstanceUtil

	Helpers for finding tagged instances, requiring children, welding and turning
	parts to face a target.
]=]

local TweenService = game:GetService("TweenService")

local Promise = require(script.Parent.Parent.Promise)

type Promise = typeof(Promise.new())

local InstanceUtil = {}

--[=[
	Returns the nearest ancestor of `instance` that has the CollectionService tag
	`tag`. The instance itself is not checked.

	@within InstanceUtil
	@param instance Instance
	@param tag string
	@return Instance?
]=]
function InstanceUtil.FindFirstAncestorWithTag(instance: Instance, tag: string): Instance?
	local ancestor = instance.Parent

	while true do
		if not ancestor then
			break
		end

		if ancestor:HasTag(tag) then
			break
		end

		ancestor = ancestor.Parent
	end

	return ancestor
end

--[=[
	Returns every descendant of `instance` that has the CollectionService tag `tag`.

	@within InstanceUtil
	@param instance Instance
	@param tag string
	@return { Instance }
]=]
function InstanceUtil.GetDescendantsWithTag(instance: Instance, tag: string)
	local descendants = instance:GetDescendants()

	for i = #descendants, 1, -1 do
		local descendant = descendants[i]
		if descendant:HasTag(tag) then
			continue
		end

		table.remove(descendants, i)
	end

	return descendants
end

--[=[
	Returns the child of `parent` named `name`, or errors with the parent's full path
	if it does not exist. Does not wait for the child.

	```lua
	local door = InstanceUtil.ExpectChild(workspace.House, "Door")
	```

	@within InstanceUtil
	@param parent Instance
	@param name string
	@return Instance
]=]
function InstanceUtil.ExpectChild(parent: Instance, name: string): Instance
	local found = parent:FindFirstChild(name)
	assert(found, `"{parent:GetFullName()}" has no "{name}"`)
	return found
end

--[=[
	Returns the first direct child of `instance` that has the CollectionService tag
	`tagName`.

	@within InstanceUtil
	@param instance Instance
	@param tagName string
	@return Instance?
]=]
function InstanceUtil.findFirstChildWithTag(instance: Instance, tagName: string): Instance?
	for _, v in instance:GetChildren() do
		if v:HasTag(tagName) then
			return v
		end
	end

	return nil
end

--[=[
	Welds two parts together with a WeldConstraint parented to `part0`.

	@within InstanceUtil
	@param part0 BasePart
	@param part1 BasePart
	@return WeldConstraint
]=]
function InstanceUtil.weldParts(part0: BasePart, part1: BasePart): WeldConstraint
	assert(part0:IsA("BasePart"), "Part1 must be a BasePart")
	assert(part1:IsA("BasePart"), "Part2 must be a BasePart")

	local wc = Instance.new("WeldConstraint")
	wc.Parent = part0
	wc.Part0 = part0
	wc.Part1 = part1

	return wc
end

--[=[
	Joins two attachments with a RigidConstraint parented to `attach1`'s parent.

	@within InstanceUtil
	@param attach1 Attachment -- Becomes `Attachment0`.
	@param attach2 Attachment -- Becomes `Attachment1`.
	@return RigidConstraint
]=]
function InstanceUtil.weldAttachments(attach1: Attachment, attach2: Attachment): RigidConstraint
	assert(attach1:IsA("Attachment"), "attach1 must be an Attachment")
	assert(attach2:IsA("Attachment"), "attach2 must be an Attachment")

	local rc = Instance.new("RigidConstraint")
	rc.Attachment0 = attach1
	rc.Attachment1 = attach2
	rc.Parent = attach1.Parent
	return rc
end

--[=[
	Tweens `object` over 0.2 seconds so it faces `target`, without moving it.

	By default the object stays level and only turns around its Y axis. Pass
	`rotateOnYAxis = true` to aim it straight at the target, tilting up or down too.

	```lua
	InstanceUtil.lookAt(turret, enemy.PrimaryPart):andThen(function()
		fire()
	end)
	```

	@within InstanceUtil
	@param object BasePart -- The part to turn.
	@param target BasePart -- The part to face.
	@param rotateOnYAxis boolean? -- Aim directly at the target instead of staying level.
	@return Promise -- Resolves when the tween completes, or rejects if `object` or `target` is nil.
]=]
function InstanceUtil.lookAt(object: BasePart, target: BasePart, rotateOnYAxis: boolean?): Promise
	return Promise.new(function(resolve, reject)
		if not (object and target) then
			reject("object and target cannot be nil")
			return
		end

		local look_at_Obj: CFrame
		if rotateOnYAxis then
			look_at_Obj = CFrame.lookAt(object.Position, target.Position)
		else
			-- Only rotate on X and Z axes, keep original Y rotation
			local targetPosition = Vector3.new(target.Position.X, object.Position.Y, target.Position.Z)
			look_at_Obj = CFrame.lookAt(object.Position, targetPosition)
		end

		local tween = TweenService:Create(object, TweenInfo.new(0.2), { CFrame = look_at_Obj })
		tween:Play()

		tween.Completed:Once(function()
			tween:Destroy()
			resolve()
		end)
	end)
end

return InstanceUtil
