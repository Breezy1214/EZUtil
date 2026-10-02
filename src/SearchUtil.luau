--!strict
--[=[
	@class SearchUtil

	Helpers for searching Instance trees and nested tables: counting and collecting
	parts, walking up ancestors, depth-limited searches, and checking that named
	children exist.
]=]

local SearchUtil = {}

--[=[
	Counts the BaseParts among the descendants of the given instance. Warns and
	returns 0 if `instance` is nil.

	Example:
	```lua
	SearchUtil.getPartCount(workspace.NPC) -- 5
	```

	@within SearchUtil
	@param instance Instance?
	@return number
]=]
function SearchUtil.getPartCount(instance: Instance?): number
	if instance == nil then
		warn("Util.getPartCount() - instance is nil")
		return 0
	end

	assert(typeof(instance) == "Instance", "Util.getPartCount() - argument must be an Instance")

	local count: number = 0

	for _, part in pairs(instance:GetDescendants()) do
		if part:IsA("BasePart") then
			count += 1
		end
	end

	return count
end

--[=[
	Gets all parts in the given instance

	Example:
	```lua
	SearchUtil.getDescendantParts(game.Workspace.LightPost) -- { [1] = Light, [2] = PostMeshPart }
	```

	@within SearchUtil
	@param instance Instance
	@return { BasePart }
]=]
function SearchUtil.getDescendantParts(instance: Instance): { BasePart }
	assert(typeof(instance) == "Instance", "Util.getDescendantParts() - argument must be an Instance")

	local parts: { BasePart } = {}

	for _, part in pairs(instance:GetDescendants()) do
		if part:IsA("BasePart") then
			parts[#parts + 1] = part
		end
	end

	return parts
end

--[=[
	Walks up from `child`, starting with `child` itself, and returns the first
	instance that matches `condition`. A string matches by name; a function matches
	when it returns true. Returns nil if nothing matches.

	Example 1:
	```lua
	local map = SearchUtil.getAncestor(part, "Map")
	```

	Example 2:
	```lua
	detector.Touched:Connect(function(part: BasePart)
		local bot: Model? = SearchUtil.getAncestor(part, function(instance: Instance)
			return instance:HasTag("NPC")
		end)

		if bot ~= nil then
			print("NPC bot touched the detector")
		end
	end)
	```

	@within SearchUtil
	@param child Instance
	@param condition string | (obj: Instance) -> boolean
	@return Instance?
]=]
function SearchUtil.getAncestor(child: Instance, condition: string | (obj: Instance) -> boolean): any
	assert(typeof(child) == "Instance", "Util.getAncestor() - child argument must be an Instance")
	assert(
		typeof(condition) == "string" or typeof(condition) == "function",
		"Util.getAncestor() - condition argument must be a string name or function"
	)

	if typeof(condition) == "string" then
		local searchString = condition

		condition = function(_child: Instance)
			return _child.Name == searchString
		end
	end

	local _condition = condition :: (_child: Instance) -> boolean

	while child do
		if _condition(child) then
			return child
		elseif child.Parent then
			child = child.Parent :: Instance
		else
			break
		end
	end

	return nil
end

--[=[
	Searches the children of `node` (an Instance's children, or a table's values)
	level by level and returns the first match. The search continues until
	`maxDepth` is reached, a match is found, or there is nothing left to search.
	Returns nil when no match is found.

	By default `maxDepth` is 1, so only the direct children of `node` are searched.

	`condition` can be:
	- a function, called with each child; the first child it returns true for is returned;
	- a key, checked on each child: for Instance children, the child's own child with
	  that name is returned; for table children, the table that has that key is
	  returned.

	Function condition example:
	```lua
	local player: Player? = SearchUtil.find(game.Players, function(player: Player)
		return player.Name == "Player1"
	end)
	```

	Key example:
	```lua
	-- The first Humanoid inside a direct child of workspace
	local humanoid = SearchUtil.find(workspace, "Humanoid")
	```

	Table example:
	```lua
	local NPCs = {
		{ Name = "NPC1", Health = 0 },
		{ Name = "NPC2", Health = 20 },
		{ Name = "NPC3", Health = 0 },
	}

	local firstAliveNPC = SearchUtil.find(NPCs, function(NPC)
		return NPC.Health > 0
	end) -- { Name = "NPC2", Health = 20 }
	```

	@within SearchUtil
	@param node Instance | { [any]: any }
	@param condition any | (obj: any) -> boolean -- A predicate, or a key to look for.
	@param maxDepth number? -- How many levels to search. Defaults to 1.
	@param _depth number? -- Internal: tracks the current depth. Leave as nil.
	@return any
]=]
function SearchUtil.find(
	node: Instance | { [any]: any },
	condition: any | (obj: Instance) -> boolean,
	maxDepth: number?,
	_depth: number?
): any
	assert(
		typeof(node) == "Instance" or typeof(node) == "table",
		"Util.find() - node argument must be an Instance or table"
	)
	assert(condition ~= nil, "Util.find() - condition argument must be a function or key")
	assert(typeof(maxDepth) == "number" or maxDepth == nil, "Util.find() - maxDepth must be a number or nil")
	assert(typeof(_depth) == "number" or _depth == nil, "Util.find() - _depth must be a number or nil")

	local function test(child: Instance): (boolean, any)
		if typeof(condition) == "function" then
			local runner = condition :: (child: Instance) -> boolean
			return runner(child), child
		end

		if typeof(child) == "Instance" then
			local result = child:FindFirstChild(condition)

			return result ~= nil, result
		end

		return child[condition] ~= nil, child
	end
	local currentDepth: number = _depth or 1
	local children: { [any]: any } = {}

	local nodes: { [any]: any } = {}

	if typeof(node) == "Instance" then
		nodes = node:GetChildren()
	elseif typeof(node) == "table" then
		nodes = node
	end

	for _, child: any in pairs(nodes) do
		local childIsInstance: boolean = typeof(child) == "Instance"
		local success: boolean, match: any = test(child)

		if success then
			return match -- Test passed, return the match
		elseif (childIsInstance and #child:GetChildren() or #child) > 0 then
			table.insert(children, child) -- Add to search the children of this node later
		end
	end

	if currentDepth >= (maxDepth or 1) then
		return nil
	end

	for _, child: any in pairs(children) do
		if not child then
			continue
		end

		local match: any = SearchUtil.find(child, condition, maxDepth, currentDepth + 1)

		if match ~= nil then
			return match
		end
	end

	return nil
end

--[=[
	Checks if the given node has children (for an Instance) or keys (for a table)
	with the given names. A single name can be passed as a string, or several names
	as a table. Returns false if `children` is nil.

	Instance node example:
	```lua
	SearchUtil.exists(
		character,
		{ "Head", "UpperTorso", "LeftUpperArm", "RightUpperArm" }
	) -- true

	SearchUtil.exists(character, "Head") -- true
	```

	Table node example:
	```lua
	local config = { Damage = 10, Range = 20 }

	SearchUtil.exists(config, { "Damage", "Range" }) -- true
	SearchUtil.exists(config, "Cooldown") -- false
	```

	@within SearchUtil
	@param node Instance | { [string]: any }
	@param children (string | { string })?
	@return boolean
]=]
function SearchUtil.exists(node: Instance | { [string]: any }, children: (string | { string })?): boolean
	assert(
		typeof(node) == "Instance" or typeof(node) == "table",
		"Util.exists() - node argument must be an Instance or table"
	)
	assert(
		typeof(children) == "string" or typeof(children) == "table" or children == nil,
		"Util.exists() - children argument must be a string or table"
	)

	if children == nil then
		return false
	end

	local nodes: { [string]: any } = {}

	if typeof(node) == "Instance" then
		-- Insert all children into a table with their name as the key
		for _, child: Instance in pairs(node:GetChildren()) do
			nodes[child.Name] = child
		end
	elseif typeof(node) == "table" then
		nodes = node
	end

	if typeof(children) == "string" then
		-- Search a single child name

		return nodes[children] ~= nil
	elseif typeof(children) == "table" then
		-- Search multiple child names

		for _, childName: string in pairs(children) do
			if nodes[childName] == nil then
				return false
			end
		end

		return true
	end

	return false
end

--[=[
	Returns the first BasePart among the direct children of the given instance.

	Example:
	```lua
	SearchUtil.getFirstPart(workspace.Player1) -- Head
	```

	@within SearchUtil
	@param instance Instance?
	@return BasePart?
]=]
function SearchUtil.getFirstPart(instance: Instance?): BasePart?
	if instance == nil then
		return nil
	end

	assert(typeof(instance) == "Instance", "instance argument must be an Instance")

	local children: { BasePart | Instance } = instance:GetChildren()

	if not children or #children == 0 then
		return
	end

	local index: number = 1
	local current: Instance? = nil

	while index <= #children do
		current = children[index]

		if current and current:IsA("BasePart") then
			return current
		end

		index += 1
	end

	return nil
end

return SearchUtil
