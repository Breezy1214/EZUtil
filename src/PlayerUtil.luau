--!strict
--[=[
	@class PlayerUtil

	Helpers for players and their characters: humanoids, animators and animations,
	character measurements, group ranks and permission levels, and hiding player UI.
]=]

local Players = game:GetService("Players")

local groupRankCache = {}
local groupRankCacheExpiration = 60 -- 1 minutes

local PlayerUtil = {}

type Janitor = any

--[=[
	Returns the Animator under the character's Humanoid (or directly under the
	character). If there is none and the character has a Humanoid, a new Animator is
	created under it.

	@within PlayerUtil
	@param character Model
	@return Animator? -- nil if the character has neither an Animator nor a Humanoid.
]=]
function PlayerUtil.ensureAnimator(character: Model): Animator?
	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		or character:FindFirstChildOfClass("Animator")

	if not animator and humanoid ~= nil then
		local newAnimator = Instance.new("Animator")
		newAnimator.Parent = humanoid
		animator = newAnimator
	end

	return animator
end

--[=[
	Loads an animation onto the character's existing Animator with `Action4`
	priority. The janitor stops the track (with a one second fade) and destroys it
	when cleaned up. This does not create an Animator; see [PlayerUtil.ensureAnimator].

	#### Example:
	```lua
	local track = PlayerUtil.loadAnimation(janitor, character, "rbxassetid://1234567890")
	if track then
		track:Play()
	end
	```

	@within PlayerUtil
	@param janitor Janitor
	@param character Model
	@param animationId string
	@return AnimationTrack? -- nil if the character has no Animator.
]=]
function PlayerUtil.loadAnimation(janitor: Janitor, character: Model, animationId: string): AnimationTrack?
	assert(animationId ~= nil, "No animationId provided")
	assert(typeof(animationId) == "string", "Expected string for animationId, got " .. typeof(animationId))

	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
		or character:FindFirstChildOfClass("Animator")

	if not animator then
		return
	end

	local animation: Animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local animTrack: AnimationTrack = animator:LoadAnimation(animation)
	animTrack.Priority = Enum.AnimationPriority.Action4
	animation:Destroy()

	janitor:Add(function()
		if animTrack then
			animTrack:Stop(1)
			animTrack:Destroy()
		end
	end)

	return animTrack
end

--[=[
	Gets a player's rank in a group. Results are cached for 60 seconds, and a failed
	request returns 0.

	#### Example:
	```lua
	PlayerUtil.getGroupRank(player, 1) -- 255
	```

	@within PlayerUtil
	@yields
	@param player Player
	@param groupId number
	@return number
]=]
function PlayerUtil.getGroupRank(player: Player, groupId: number): number
	if not player or not groupId then
		return 0
	end

	local uniqueId: string = `{player.UserId}-{groupId}`
	local cached = groupRankCache[uniqueId]

	if cached and os.clock() - cached.fetchedAt <= groupRankCacheExpiration then
		return cached.rank
	end

	local success, res = pcall(function()
		return player:GetRankInGroup(groupId)
	end)

	local rank = success and res or 0
	groupRankCache[uniqueId] = {
		rank = rank,
		fetchedAt = os.clock(),
	}

	return rank
end

--[=[
	Checks if a player created the game: the owning user, or a rank 255 member of the
	owning group.

	#### Example:
	```lua
	PlayerUtil.isCreator(player) -- true
	```

	@within PlayerUtil
	@yields
	@param player Player
	@return boolean
]=]
function PlayerUtil.isCreator(player: Player): boolean
	return (game.CreatorType == Enum.CreatorType.Group and PlayerUtil.getGroupRank(player, game.CreatorId) >= 255)
		or (game.CreatorType == Enum.CreatorType.User and player.UserId == game.CreatorId)
end

--[=[
	The permission levels returned by [PlayerUtil.getUserLevel], from lowest to
	highest: `normal` (0), `premium` (1), `VIP` (2), `moderator` (3), `superuser` (4)
	and `creator` (5).

	```lua
	if PlayerUtil.getUserLevel(player) >= PlayerUtil.userLevel.moderator then
		-- allow moderation commands
	end
	```

	@prop userLevel { [string]: number }
	@within PlayerUtil
]=]
PlayerUtil.userLevel = {
	normal = 0, -- (default)
	premium = 1, -- (requires premium)
	VIP = 2, -- (if game is owned by group, requires rank 10)
	moderator = 3, -- (if game is owned by group, requires rank 50)
	superuser = 4, -- developer (if game is owned by group, requires rank 254)
	creator = 5, -- (requires group rank 255 or if game is owned by user)
}

--[=[
	Gets a player's permission level, one of the [PlayerUtil.userLevel] values:
	- `creator` if [PlayerUtil.isCreator] is true;
	- in a group-owned game: `superuser` for rank 253 and above, `moderator` for
	  rank 99 exactly, and `VIP` for ranks below 10 (including players outside the
	  group);
	- otherwise `premium` for Premium members, or `normal`.

	#### Example:
	```lua
	PlayerUtil.getUserLevel(player) -- 0
	```

	@within PlayerUtil
	@yields
	@param player Player
	@return number
]=]
function PlayerUtil.getUserLevel(player: Player): number
	local isGameOwnedByGroup: boolean = game.CreatorType == Enum.CreatorType.Group

	if PlayerUtil.isCreator(player) then
		return PlayerUtil.userLevel.creator
	elseif isGameOwnedByGroup then
		local playerRank: number = PlayerUtil.getGroupRank(player, game.CreatorId)

		if playerRank >= 253 then
			return PlayerUtil.userLevel.superuser
		elseif playerRank == 99 then
			return PlayerUtil.userLevel.moderator
		elseif playerRank < 10 then
			return PlayerUtil.userLevel.VIP
		end
	end

	return (player.MembershipType == Enum.MembershipType.Premium and PlayerUtil.userLevel.premium)
		or PlayerUtil.userLevel.normal
end

--[=[
	Gets the Humanoid of a Player's character, a character Model, or a Humanoid
	itself. Warns if `object` is not an Instance.

	#### Example:
	```lua
	PlayerUtil.getHumanoid(player) -- Humanoid
	PlayerUtil.getHumanoid(workspace.Zombie) -- Humanoid
	```

	@within PlayerUtil
	@param object Instance?
	@return Humanoid?
]=]
function PlayerUtil.getHumanoid(object: Instance?): Humanoid?
	if typeof(object) ~= "Instance" then
		warn(`Util.getHumanoid - expected Instance, got type "{typeof(object)}"`)
	elseif object:IsA("Humanoid") then
		return object
	elseif object:IsA("Player") then
		return object.Character and object.Character:FindFirstChildOfClass("Humanoid")
	elseif object:IsA("Model") then
		return object:FindFirstChildOfClass("Humanoid")
	end

	return nil
end

--[=[
	Returns the height of the character's bounding box.

	@within PlayerUtil
	@param character Model
	@return number? -- nil if the character has no PrimaryPart.
]=]
function PlayerUtil.getCharacterHeight(character: Model): number?
	if not character or not character.PrimaryPart then
		return nil
	end

	local boundsSize = character:GetExtentsSize()
	return boundsSize.Y
end

--[=[
	Checks if a Player, character Model or Humanoid has a Humanoid with health above 0.
	Returns false if no Humanoid is found.

	#### Example:
	```lua
	PlayerUtil.isAlive(player) -- true
	PlayerUtil.isAlive(workspace.Zombie) -- false
	PlayerUtil.isAlive(workspace.Part) -- false
	```

	@within PlayerUtil
	@param obj Instance
	@return boolean
]=]
function PlayerUtil.isAlive(obj: Instance): boolean
	local humanoid: Humanoid? = PlayerUtil.getHumanoid(obj)

	return humanoid and humanoid.Health > 0 or false
end

--[=[
	Checks if a Player, character Model or Humanoid has a Humanoid.

	#### Example:
	```lua
	PlayerUtil.hasHumanoid(player) -- true
	PlayerUtil.hasHumanoid(workspace.Zombie) -- true
	```

	@within PlayerUtil
	@param obj Instance
	@return boolean
]=]
function PlayerUtil.hasHumanoid(obj: Instance): boolean
	return PlayerUtil.getHumanoid(obj) ~= nil
end

--[=[
	Gets the Player whose character contains a BasePart, by walking up its ancestors
	until one holds a Humanoid. Also available as `PlayerUtil.getPlayerFromPart`.

	#### Example:
	```lua
	hitbox.Touched:Connect(function(part)
		local player = PlayerUtil.getPlayerFromInstance(part)
	end)
	```

	@within PlayerUtil
	@param instance Instance? -- Anything other than a BasePart returns nil.
	@return Player?
]=]
function PlayerUtil.getPlayerFromInstance(instance: Instance?): Player?
	if typeof(instance) ~= "Instance" or not instance:IsA("BasePart") then
		return nil
	end

	local node: Instance? = instance
	local humanoid: Humanoid?

	while node ~= nil and humanoid == nil and node ~= game do
		humanoid = node and node:FindFirstChildOfClass("Humanoid")
		node = node.Parent :: Instance?
	end

	return humanoid and Players:GetPlayerFromCharacter(humanoid.Parent) or nil
end

--[=[
	Gets the position at the feet of a character: its PrimaryPart's position, lowered
	by half the height of the character's bounding box. Errors if the character has
	no PrimaryPart.

	#### Example:
	```lua
	local effectPosition = PlayerUtil.getPositiontAtFeet(player.Character)
	```

	@within PlayerUtil
	@param character Model
	@return Vector3
]=]
function PlayerUtil.getPositiontAtFeet(character: Model): Vector3
	local root: BasePart? = character.PrimaryPart
	assert(root, "Character must have a PrimaryPart")
	return root.Position - Vector3.new(0, character:GetExtentsSize().Y / 2, 0)
end

--[=[
	Alias of [PlayerUtil.getPlayerFromInstance].

	@function getPlayerFromPart
	@within PlayerUtil
	@param instance Instance?
	@return Player?
]=]
PlayerUtil.getPlayerFromPart = PlayerUtil.getPlayerFromInstance

--[=[
	Returns a player's character, its Humanoid and its HumanoidRootPart. Returns
	nothing if the player has no character.

	```lua
	local character, humanoid, rootPart = PlayerUtil.getCharacterInformation(player)
	```

	@within PlayerUtil
	@param player Player
	@return Model?
	@return Humanoid?
	@return BasePart?
]=]
function PlayerUtil.getCharacterInformation(player: Player): (Model?, Humanoid?, BasePart?)
	local character: Model? = player.Character
	if not character then
		return
	end
	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid: Humanoid? = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	return character, humanoid, humanoidRootPart
end

--[=[
	Hides or restores every ScreenGui in the local player's PlayerGui, except the one
	named `exception` and any whose name contains "Topbar". Hiding remembers each
	ScreenGui's `Enabled` state so restoring puts it back.

	```lua
	PlayerUtil.disableOtherUi(true, "ShopGui") -- hide everything but the shop
	PlayerUtil.disableOtherUi(false) -- restore
	```

	@within PlayerUtil
	@client
	@yields
	@param value boolean -- true to hide, false to restore.
	@param exception string? -- The name of a ScreenGui to leave alone.
]=]
function PlayerUtil.disableOtherUi(value: boolean, exception: string?)
	for _, screenGui in Players.LocalPlayer:WaitForChild("PlayerGui"):GetChildren() do
		if not screenGui:IsA("ScreenGui") then
			continue
		end
		if screenGui.Name == exception then
			continue
		end
		if string.match(screenGui.Name, "Topbar") then
			continue
		end

		-- Store original enabled state in an attribute to restore later

		if value == true then
			screenGui:SetAttribute("Enabled", screenGui.Enabled)
			screenGui.Enabled = false
		else
			screenGui.Enabled = screenGui:GetAttribute("Enabled") :: boolean or screenGui.Enabled
			screenGui:SetAttribute("Enabled", nil)
		end
	end
end

return PlayerUtil
