--!strict
--[=[
	@class CharacterRigUtil

	Helpers for character rigs: finding humanoids, animators and body parts, standing
	a character on the ground, and working with skinned mesh (Bone based) characters.
]=]

local CharacterRigUtil = {}

--[=[
	Returns the character's Humanoid, waiting up to `timeout` seconds for a child
	named `Humanoid` if none exists yet.

	@within CharacterRigUtil
	@yields
	@param character Model
	@param timeout number -- Maximum time to wait, in seconds.
	@return Humanoid? -- nil if no Humanoid appeared in time.
]=]
function CharacterRigUtil.waitForHumanoid(character: Model, timeout: number): Humanoid?
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", timeout)
	return if humanoid and humanoid:IsA("Humanoid") then humanoid else nil
end

--[=[
	Returns the humanoid's Animator, waiting up to `timeout` seconds for a child
	named `Animator` if none exists yet.

	@within CharacterRigUtil
	@yields
	@param humanoid Humanoid
	@param timeout number -- Maximum time to wait, in seconds.
	@return Animator? -- nil if no Animator appeared in time.
]=]
function CharacterRigUtil.waitForAnimator(humanoid: Humanoid, timeout: number): Animator?
	local animator = humanoid:FindFirstChildOfClass("Animator") or humanoid:WaitForChild("Animator", timeout)
	return if animator and animator:IsA("Animator") then animator else nil
end

--[=[
	Finds a body part by name. If the named child is an Accessory, its handle's
	MeshPart is returned instead.

	@within CharacterRigUtil
	@param character Model
	@param name string -- The name of the body part or accessory.
	@return BasePart?
]=]
function CharacterRigUtil.findBodyPart(character: Model, name: string): BasePart?
	local part = character:FindFirstChild(name)

	if part and part:IsA("Accessory") then
		local handle = part:FindFirstChild("Handle")
		part = if handle then handle:FindFirstChildWhichIsA("MeshPart") else nil
	end

	return if part and part:IsA("BasePart") then part else nil
end

--[=[
	Polls [CharacterRigUtil.findBodyPart] every frame until it finds the part,
	`timeout` seconds pass, or the character is removed from the DataModel.

	@within CharacterRigUtil
	@yields
	@param character Model
	@param name string -- The name of the body part or accessory.
	@param timeout number -- Maximum time to wait, in seconds.
	@return BasePart?
]=]
function CharacterRigUtil.waitForBodyPart(character: Model, name: string, timeout: number): BasePart?
	local deadline = os.clock() + timeout
	local part = CharacterRigUtil.findBodyPart(character, name)

	while not part and os.clock() < deadline and character.Parent do
		task.wait()
		part = CharacterRigUtil.findBodyPart(character, name)
	end

	return part
end

local function getRootHeight(rootPart: BasePart, humanoid: Humanoid): number
	return humanoid.HipHeight + rootPart.Size.Y / 2
end

--[=[
	Returns the world Y coordinate of the character's feet, worked out from the root
	part's position, its height and the humanoid's `HipHeight`.

	@within CharacterRigUtil
	@param rootPart BasePart -- The character's HumanoidRootPart.
	@param humanoid Humanoid
	@return number
]=]
function CharacterRigUtil.getFeetY(rootPart: BasePart, humanoid: Humanoid): number
	return rootPart.Position.Y - getRootHeight(rootPart, humanoid)
end

--[=[
	Pivots the whole character so its feet rest on `groundCFrame`, keeping the
	offset between the root part and the character's pivot.

	@within CharacterRigUtil
	@param character Model
	@param rootPart BasePart -- The character's HumanoidRootPart.
	@param humanoid Humanoid
	@param groundCFrame CFrame -- Where the feet should stand. Its rotation is applied to the root part.
	@return CFrame -- The root part's new CFrame.
]=]
function CharacterRigUtil.standRootOn(
	character: Model,
	rootPart: BasePart,
	humanoid: Humanoid,
	groundCFrame: CFrame
): CFrame
	local targetRootCFrame = groundCFrame + Vector3.yAxis * getRootHeight(rootPart, humanoid)
	character:PivotTo(targetRootCFrame * rootPart.CFrame:Inverse() * character:GetPivot())
	return targetRootCFrame
end

--[=[
	Returns whether a humanoid state counts as standing on the ground: `Running`,
	`RunningNoPhysics`, `Landed` or `None`.

	@within CharacterRigUtil
	@param state Enum.HumanoidStateType
	@return boolean
]=]
function CharacterRigUtil.isGroundedState(state: Enum.HumanoidStateType): boolean
	return state == Enum.HumanoidStateType.Running
		or state == Enum.HumanoidStateType.RunningNoPhysics
		or state == Enum.HumanoidStateType.Landed
		or state == Enum.HumanoidStateType.None
end

--[=[
	Returns the MeshPart whose Bone hierarchy poses the character, if the character
	is built as a skinned mesh rather than as jointed R15 limbs. The PrimaryPart is
	checked first, then every descendant. Returns nil for a conventional rig, which
	has no bones.

	@within CharacterRigUtil
	@param character Model
	@return MeshPart?
]=]
function CharacterRigUtil.findSkinnedMesh(character: Model): MeshPart?
	local primary = character.PrimaryPart
	if primary and primary:IsA("MeshPart") and primary:FindFirstChildOfClass("Bone") then
		return primary
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("MeshPart") and descendant:FindFirstChildOfClass("Bone") then
			return descendant
		end
	end

	return nil
end

--[=[
	Returns every Bone under `character`, ordered so a bone always appears after its
	parent. A character can contain several independent bone trees, including trees
	rooted under non-MeshParts.

	@within CharacterRigUtil
	@param character Model
	@return { Bone }
]=]
function CharacterRigUtil.collectCharacterBones(character: Model): { Bone }
	local ordered: { Bone } = {}

	local function walk(instance: Instance): ()
		for _, child in instance:GetChildren() do
			if child:IsA("Bone") then
				table.insert(ordered, child)
			end

			walk(child)
		end
	end

	walk(character)
	return ordered
end

return CharacterRigUtil
