--!strict
--[=[
	@class TableUtil

	Table and string helpers: flipping, mapping, filtering and merging tables, reading
	paths through nested tables or Instances, splitting and joining strings, and
	random picks.
]=]

local valueClasses = {
	BoolValue = true,
	BrickColorValue = true,
	CFrameValue = true,
	Color3Value = true,
	IntValue = true,
	NumberValue = true,
	ObjectValue = true,
	RayValue = true,
	StringValue = true,
	Vector3Value = true,
}

local TableUtil = {}

--[=[
	Flips the table's keys with its values.
	If `mergeDuplicates` is `true`, All values will be stored in a table at the key's index, instead of overwriting them.

	#### Example:
	```lua
	TableUtil.flip({ a = 1, b = 2 }) -- { [1] = "a", [2] = "b" }
	TableUtil.flip({ a = 1, b = 2 }, true) -- { [1] = { "a" }, [2] = { "b" } }

	-- Use case: finding all keys with the same value
	local newTable = TableUtil.flip({ a = 1, b = 2, c = 2 }, true) -- { [1] = { "a" }, [2] = { "b", "c" } }
	print(#newTable[2]) -- 2
	```

	@within TableUtil
	@param source { [any]: any } -- The table you want to flip
	@param mergeDuplicates boolean? -- Merge key duplicates into a table instead of overwriting them.
	@return { [any]: any }
]=]
function TableUtil.flip(source: { [any]: any }, mergeDuplicates: boolean?): { [any]: any }
	assert(typeof(source) == "table", `Util.flip - Cannot index {typeof(source)}`)
	assert(
		mergeDuplicates == nil or typeof(mergeDuplicates) == "boolean",
		"Util.flip - mergeDuplicates must be a boolean or nil"
	)

	local res: { [any]: any } = {}
	local duplicates: { [any]: { any } } = {}

	for key: any, value: any in pairs(source) do
		if res[value] == nil then
			res[value] = key
		elseif mergeDuplicates then
			if not duplicates[value] then
				duplicates[value] = { key }
				res[value] = duplicates[value]
			else
				duplicates[value][#duplicates[value] + 1] = key
			end
		end
	end

	return res
end

--[=[
	Maps a table or instance to a new table.

	#### Example:
	```lua
	TableUtil.map({ 1, 2, 3 }, function(v)
		return v * 2
	end) -- { 2, 4, 6 }

	TableUtil.map({ 1, 2, 3 }, function(v, i)
		return i * 2
	end) -- { 2, 4, 6 }
	```

	@within TableUtil
	@param source { [any]: any } -- The table you want to map
	@param callbackFn (any, any, any) -> (any, any) -- The function to map the table with
	@return { [any]: any }
]=]
function TableUtil.map(source: { [any]: any }, callbackFn: (any, any, any) -> (any, any)): { [any]: any }
	assert(typeof(source) == "table" or typeof(source) == "Instance", "source must be a table or instance")
	assert(callbackFn == nil or typeof(callbackFn) == "function", "callbackFn must be a function or nil")

	local res = {}

	for key: any, value: any in
		pairs(
			-- If instance, convert variable to a table of its children
			typeof(source) == "Instance" and source:GetChildren() or source
		)
	do
		local index: any = #res + 1

		if callbackFn then
			local result, secondResult = callbackFn(value, key, source)

			if secondResult ~= nil then -- Both the index and value are specified
				index = result
				value = secondResult
			else -- If there is no second result, we will use "#res + 1" as the index
				value = result -- Use the first result as the value
			end
		end

		res[index] = value
	end

	return res
end

--[=[
	Filters a table, or an Instance's children, into a new array.

	#### Example:
	```lua
	local noTwo = TableUtil.filter({ 1, 2, 3 }, function(value)
		return value ~= 2
	end) -- { 1, 3 }

	local parts = TableUtil.filter(workspace, function(value)
		return value:IsA("Part")
	end) -- { Part, Part2 }
	```

	@within TableUtil
	@param source { [any]: any } | Instance -- The table you want to filter
	@param callbackFn (any, any, any) -> (boolean?) -- The function to filter the table with (element, index, source). Keeps elements it returns exactly `true` for.
	@return { any }
]=]
function TableUtil.filter(source: { [any]: any }, callbackFn: (any, any, any) -> boolean?): { [any]: any }
	assert(typeof(source) == "table" or typeof(source) == "Instance", "source must be a table or instance")
	assert(callbackFn == nil or typeof(callbackFn) == "function", "callbackFn must be a function or nil")

	local res = {}

	for key: any, value: any in
		pairs(
			-- If instance, convert variable to a table of its children
			typeof(source) == "Instance" and source:GetChildren() or source
		)
	do
		if callbackFn(value, key, source) == true then
			res[#res + 1] = value
		end
	end

	return res
end

-- Map an object by index

--[=[
	Maps an array to a new table. The callback can return a new value, and optionally
	a new key to store it under; otherwise each value keeps its position.

	#### Example:
	```lua
	TableUtil.mapIndex({ 1, 2, 3 }) -- { [1] = 1, [2] = 2, [3] = 3 }

	TableUtil.mapIndex({ 1, 2, 3 }, function(v)
		return v * 2
	end) -- { [1] = 2, [2] = 4, [3] = 6 }

	TableUtil.mapIndex({ "a", "b" }, function(v, i)
		return i, v
	end) -- { a = 1, b = 2 }
	```

	@within TableUtil
	@param source { any } -- The array you want to map
	@param filterFn ((value: any, index: number, source: { any }) -> (any?, any?))? -- Returns the new value and, optionally, the new key
	@return { [any]: any }
]=]
function TableUtil.mapIndex(source: { [any]: any }, filterFn: (any, any, any) -> (any, any)): { [any]: any }
	assert(typeof(source) == "table", "source must be a table")
	assert(filterFn == nil or typeof(filterFn) == "function", "filterFn must be a function or nil")

	local res = {}

	for key: any, value: any in ipairs(source) do
		local index = #res + 1

		if filterFn then
			local fnVal, fnKey = filterFn(value, key, source)

			if fnKey then
				index = fnKey
			end

			if fnVal ~= nil then
				value = fnVal
			end
		end

		res[index] = value
	end

	return res
end

--[=[
	Trims leading and trailing whitespace from a string.

	#### Example:
	```lua
	TableUtil.trimWhitespace("  Hello, world!  ") -- "Hello, world!"
	```

	@within TableUtil
	@param text string
	@return string
]=]
function TableUtil.trimWhitespace(text: string): string
	assert(typeof(text) == "string", "text must be a string")

	return string.match(text, "^%s*(.-)%s*$") :: string
end

--[=[
	Trims leading whitespace from a string.

	#### Example:
	```lua
	TableUtil.trimLeadingWhitespace("  Hello, world!") -- "Hello, world!"
	```

	@within TableUtil
	@param text string
	@return string
]=]
function TableUtil.trimLeadingWhitespace(text: string): string
	assert(typeof(text) == "string", "text must be a string")

	return string.match(text, "^%s*(.-)$") :: string
end

--[=[
	Trims trailing whitespace from a string.

	#### Example:
	```lua
	TableUtil.trimTrailingWhitespace("Hello, world!  ") -- "Hello, world!"
	```

	@within TableUtil
	@param text string
	@return string
]=]
function TableUtil.trimTrailingWhitespace(text: string): string
	assert(typeof(text) == "string", "text must be a string")

	return string.match(text, "^(.-)%s*$") :: string
end

--[=[
	Splits a string into a table of strings using a delimiter.
	If `delimiter` is not provided, it defaults to a space.

	Setting `trimTrailingDelimiter` to `false` will result in an empty string at the end of the table if the text ends with the delimiter

	Setting `trim` to `false` will result in whitespace not being trimmed from each chunk

	#### Example:
	```lua
	TableUtil.split("Hello, world!") -- { "Hello,", "world!" }
	TableUtil.split("Hello, world!", ", ") -- { "Hello", "world!" }
	TableUtil.split("Hello, world!", ",", nil, false) -- { "Hello", " world!" } -- no whitespace is trimmed
	TableUtil.split("Hello, world!,", ",", false) -- { "Hello", "world!", "" } -- trailing delimiter is included

	TableUtil.split("path/to/file", "/") -- { "path", "to", "file" }
	TableUtil.split("path/to/file/", "/") -- { "path", "to", "file" } -- trailing delimiter is trimmed
	```

	@within TableUtil
	@param text string | number?
	@param delimiter string?
	@param trimTrailingDelimiter boolean?
	@param trim boolean? -- Trim whitespace from each chunk
	@return { string }
]=]
function TableUtil.split(
	text: string | number?,
	delimiter: string?,
	trimTrailingDelimiter: boolean?,
	trim: boolean?
): { string }
	if typeof(text) == "number" then
		text = tostring(text) :: string
	end

	if not text then
		return {}
	end

	assert(typeof(text) == "string", "text must be a string")
	assert(delimiter == nil or typeof(delimiter) == "string", "delimiter must be a string or nil")
	assert(
		trimTrailingDelimiter == nil or typeof(trimTrailingDelimiter) == "boolean",
		"trimTrailingDelimiter must be a boolean or nil"
	)
	assert(trim == nil or typeof(trim) == "boolean", "trim must be a boolean or nil")

	if trimTrailingDelimiter == nil then
		trimTrailingDelimiter = true
	end

	if trim == nil then
		trim = true
	end

	if not delimiter then
		delimiter = " " :: string
	end

	text = tostring(text)

	local chunks: { string } = {}

	if not trimTrailingDelimiter and text:sub(0, 1) == delimiter then
		chunks[1] = ""
	end

	-- Trim trailing spaces
	while string.len(text) > 0 and string.sub(text, -1, -1) == " " do
		text = text:sub(0, -2)
	end

	for match: string in string.gmatch(text, `([^{delimiter}]+)`) do
		chunks[#chunks + 1] = trim and TableUtil.trimWhitespace(match) or match
	end

	if not trimTrailingDelimiter and text:sub(-1, -1) == delimiter then
		chunks[#chunks + 1] = ""
	end

	return chunks
end

--[[
-- Todo: add nested merge
function TableUtil.mergeNested(to, from) -- Merges to the first given table
	assert(typeof(to) == "table", "First argument must be a table")
	assert(typeof(from) == "table", "Second argument must be a table")

	for k, v in pairs(from) do
		to[k] = v

		if typeof(v) == "table" then
			TableUtil.mergeNested(to[k], v)
		end
	end
end]]

--[=[
	Joins an array of strings and numbers into a single string, with `separator`
	between each element.

	#### Example:
	```lua
	TableUtil.join({ "Hello", "world!" }, ",") -- "Hello,world!"
	TableUtil.join({ "Hello", "world!" }, ", ") -- "Hello, world!"
	```

	@within TableUtil
	@param stringTable { [any]: string | number } -- The table you want to join
	@param separator string? -- The separator to use when joining the table. Defaults to `","`.
	@return string
]=]
function TableUtil.join(stringTable: { [any]: string | number }, separator: string?): string
	assert(stringTable, "Util.join - Missing object")
	assert(typeof(stringTable) == "table", "Util.join - Cannot index " .. typeof(stringTable))
	assert(separator == nil or typeof(separator) == "string", "Util.join - Separator must be a string or nil")

	local _separator: string = separator or ","

	local res: string = ""

	for index: number, value: string | number in ipairs(stringTable) do
		local _value: string | number? = value

		if typeof(_value) == "number" then
			_value = tostring(_value) :: string
		end

		if typeof(_value) == "string" then
			res = res .. (index == #stringTable and _value or _value .. _separator)
		end
	end

	return res
end

--[=[
	Extends a table with one or more tables, in order, and returns it. The target
	table is modified in place.

	#### Example:
	```lua
	TableUtil.extend({ a = 1 }, { b = 2 }, { c = 3 }) -- { a = 1, b = 2, c = 3 }
	TableUtil.extend({ a = 1 }, { a = 2 }, { a = 3 }) -- { a = 3 } -- Last argument overwrites previous arguments
	TableUtil.extend({ a = 1 }, { a = 2 }, { a = 3 }, true) -- Error: Argument #3 must be a table
	```

	#### Config override example:
	```lua
	local function getDefaultConfig()
		return {
			health = 100
		}
	end

	local buffConfig = {
		health = 150,
		speed = 1.5
	}

	local playerConfig: { [any]: any } = TableUtil.extend(getDefaultConfig(), buffConfig) -- { health = 150, speed = 1.5 }
	```

	Pass `true` as the first argument for deep mode, in which case the target table
	is the second argument. Note that nested tables are currently assigned by
	reference rather than merged key by key.

	@within TableUtil
	@param arg1 boolean | { [any]: any } -- The target table, or `true` for deep mode
	@param arg2 { [any]: any } -- The first table to merge in, or the target table in deep mode
	@param ... { [any]: any } -- The tables you want to merge into the target table
	@return { [any]: any }
]=]
function TableUtil.extend(arg1: boolean | { [any]: any }, arg2: { [any]: any }, ...): { [any]: any }
	local deep: boolean = typeof(arg1) == "boolean" and arg1 or false
	local targetTable = deep and arg2 or arg1 :: { [any]: any }

	assert(typeof(targetTable) == "table", "targetTable must be a table")

	local args: { [any]: any } = deep and { ... } or { arg2, ... }

	for argIndex: number, sourceTable in pairs(args) do
		assert(typeof(sourceTable) == "table", `Argument #{argIndex} must be a table`)

		for key, value in pairs(sourceTable) do
			targetTable[key] = value

			if deep and typeof(value) == "table" then
				targetTable[key] = TableUtil.extend(targetTable[key], value)
			end
		end
	end

	return targetTable
end

--[=[
	The assign function copies all properties from one or more source objects to a target object.

	Alias for `TableUtil.extend`.

	@within TableUtil
	@param targetTable { [any]: any } -- The target table you want to assign values to
	@param ... { [any]: any } -- The tables you want to merge into the target table
	@return { [any]: any }
]=]
function TableUtil.assign(targetTable: { [any]: any }, ...): { [any]: any }
	return TableUtil.extend(targetTable, ...)
end

--[=[
	Gets a value from a table or Instance using a path.

	#### Example:
	```lua
	TableUtil.treePath({ a = { b = { c = 1 } } }, "a.b.c") -- 1
	TableUtil.treePath({ a = { b = { c = 1 } } }, "a.b") -- { c = 1 }
	TableUtil.treePath(game.Workspace, "House.Door") -- Door instance
	TableUtil.treePath(script, "NonexistantChild") -- nil
	```

	@within TableUtil
	@param tree { [any]: any } | Instance -- The table or instance you want to get the value from
	@param path string -- The path to the value
	@param delimiter string? -- The delimiter to use when splitting the path
	@return any
]=]
function TableUtil.treePath(tree: { [any]: any } | Instance, path: string, delimiter: string?): any
	assert(typeof(tree) == "table" or typeof(tree) == "Instance", "Tree must be a table or instance")
	assert(typeof(path) == "string", "path must be a string")

	local node = tree
	local steps: { string } = TableUtil.split(path, delimiter or ".")
	local stepIndex: number = 1

	if #steps == 0 then
		return node -- Return the root node
	end

	while node ~= nil and stepIndex <= #steps do
		local childNode = steps[stepIndex]

		if typeof(node) ~= "Instance" and node[childNode] then
			node = node[childNode] :: { [any]: any }
		elseif typeof(node) == "Instance" and node:FindFirstChild(childNode) then
			node = node:FindFirstChild(childNode) :: Instance
		else
			return nil
		end

		stepIndex += 1
	end

	-- Reached last step in path, return the node
	return node
end

-- Inserts a value into a table if the test condition is true

--[=[
	Inserts a value into a table if the test condition is true.

	#### Example:
	```lua
	TableUtil.insertIf({ 1, 2, 3 }, 4, true) -- { 1, 2, 3, 4 }
	TableUtil.insertIf({ 1, 2, 3 }, 4, false) -- { 1, 2, 3 }
	TableUtil.insertIf({ 1, 2, 3 }, 4, function()
		return true
	end) -- { 1, 2, 3, 4 }
	```

	@within TableUtil
	@param target { [any]: any } -- The table you want to insert the value into
	@param value any -- The value you want to insert
	@param condition nil | boolean | () -> boolean? -- The test condition
	@return nil
]=]
function TableUtil.insertIf(target: { [any]: any }, value: any, condition: nil | boolean | (() -> boolean?)): nil
	assert(typeof(target) == "table", "Target is missing")
	assert(typeof(value) ~= "nil", "Value is missing")
	assert(
		condition == nil or typeof(condition) == "function" or typeof(condition) == "boolean",
		"Test must be a function, boolean, or nil"
	)

	local canInsert: boolean? = if typeof(condition) ~= "function" then condition else condition()

	if canInsert == true then
		target[#target + 1] = value
	end

	return nil
end

--[=[
	Collects all children of an instance into a table.

	#### Example:
	```lua
	TableUtil.instanceChildrenToTable(game.Workspace) -- { Part = Instance, Part2 = Instance }
	TableUtil.instanceChildrenToTable(game.ReplicatedStorage.Config) -- { Config1 = CFrameValue, Config2 = StringValue }
	```

	@within TableUtil
	@param instance Instance -- The instance you want to collect children from
	@return { [string]: Instance }
]=]
function TableUtil.instanceChildrenToTable(instance: Instance): { [string]: Instance }
	assert(typeof(instance) == "Instance", "Instance is missing")

	local children = {}

	for _, child in pairs(instance:GetChildren()) do
		children[child.Name] = child
	end

	return children
end

--[=[
	Returns the total amount of values in a table.

	#### Example:
	```lua
	TableUtil.tableLength({ 1, 2, 3 }) -- 3
	TableUtil.tableLength({ a = 1, b = 2, c = 3 }) -- 3
	```

	@within TableUtil
	@param source { [any]: any }
	@return number
]=]
function TableUtil.tableLength(source: { [any]: any }): number
	assert(source, "Util.tableLength - Missing object")

	local length: number = 0

	for _index, _value in pairs(source) do
		length += 1
	end

	return length
end

--[=[
	Returns a random index from a table or instance.

	#### Example:
	```lua
	TableUtil.tableRandomIndex({ 1, 2, 3 }) -- 2
	TableUtil.tableRandomIndex({ a = 1, b = 2, c = 3 }) -- "b"
	```

	@within TableUtil
	@param obj { [any]: any } | Instance -- The table or instance you want to get a random index from
	@return any
]=]
function TableUtil.tableRandomIndex(obj: { [any]: any } | Instance): any
	assert(typeof(obj) == "table" or typeof(obj) == "Instance", "Util.tableRandomIndex - Cannot index " .. typeof(obj))

	local collection: { [any]: any } = if typeof(obj) == "Instance" then obj:GetChildren() else obj

	local indexes = {}

	-- Map all children names and indexes into a table
	for index, _ in pairs(collection) do
		indexes[#indexes + 1] = index
	end

	return #indexes > 0 and indexes[Random.new():NextInteger(1, #indexes)] or nil
end

--[=[
	Returns the key of the first value equal to `value`, or 0 if there is none.

	```lua
	TableUtil.indexOf({ "a", "b", "c" }, "b") -- 2
	TableUtil.indexOf({ "a", "b", "c" }, "z") -- 0
	```

	@within TableUtil
	@param obj { [any]: any }
	@param value any
	@return any
]=]
function TableUtil.indexOf(obj, value)
	assert(obj, "Util.indexOf - Missing object")
	assert(typeof(obj) == "table", "Util.indexOf - Cannot index " .. typeof(obj))

	for k, v in pairs(obj) do
		if v == value then
			return k
		end
	end

	return 0 -- No index found
end

--[=[
	Returns a random value from a table, or a random child of an Instance.

	```lua
	TableUtil.tableRandom({ "a", "b", "c" }) -- "b"
	TableUtil.tableRandom({ x = 1, y = 2 }) -- 2
	```

	@within TableUtil
	@param obj { [any]: any } | Instance -- The table or Instance to select from.
	@return any -- nil if the table is empty.
]=]
function TableUtil.tableRandom(obj: { [any]: any } | Instance): any
	assert(obj, "Util.tableRandom - Missing object")
	assert(typeof(obj) == "table" or typeof(obj) == "Instance", "Util.tableRandomIndex - Cannot index " .. typeof(obj))

	local collection: { [any]: any } = if typeof(obj) == "Instance" then obj:GetChildren() else obj

	return collection[TableUtil.tableRandomIndex(collection)]
end

--[=[
	Creates a nested table of value instances from a Folder or Configuration instance.

	#### Example:

	- Config (Folder) -- in ReplicatedStorage
	  - Origin (CFrameValue), Value = CFrame.new(0, 1, 0)
	  - WelcomeMessage (StringValue), Value = "Hello, world!"

	```lua
	TableUtil.makeConfigFromValues(game.ReplicatedStorage.Config)
	```

	Result:
	```lua
	{
		Origin = CFrame.new(0, 1, 0),
		WelcomeMessage = "Hello, world!"
	}
	```

	@within TableUtil
	@param folder Folder | Configuration -- The folder or Configuration you want to make a table from
	@return { [string]: any }
]=]
function TableUtil.makeConfigFromValues(folder: Folder | Configuration): { [string]: any }
	assert(
		typeof(folder) == "Instance" and (folder:IsA("Folder") or folder:IsA("Configuration")),
		"Util.makeConfigFromValues - Folder is missing"
	)

	local config: { [string]: any } = {}

	for _, child: Instance in pairs(folder:GetChildren()) do
		if child:IsA("Folder") or child:IsA("Configuration") then -- Nest
			config[child.Name] = TableUtil.makeConfigFromValues(child)
		elseif valueClasses[child.ClassName] then
			config[child.Name] = (child :: any).Value
		else --elseif configClasses[el.ClassName] then
			config[child.Name] = child
		end
	end

	return config
end

--[=[
	Removes elements from an array in place, shifting the remaining elements down.

	#### Example:
	```lua
	local list = { "a", "b", "c" }
	TableUtil.tableRemove(list, 2) -- list is now { "a", "c" }

	local values = { 1, 2, 3, 2 }
	TableUtil.tableRemove(values, { 2 }) -- values is now { 1, 3 }
	```

	@within TableUtil
	@param obj { any } -- The array you want to remove elements from
	@param removeTest number | { any } -- The index to remove, or a list of values to remove
	@return nil
]=]
function TableUtil.tableRemove(obj: { [any]: any }, removeTest: number | { any }): nil
	-- Convert to a test function if the test value is a number or table
	local test: (any, number, number) -> boolean

	if typeof(removeTest) == "number" then
		test = function(_value, _newIndex, i)
			return i == removeTest
		end
	elseif typeof(removeTest) == "table" then
		test = function(value, _newIndex, _i)
			for _, v in ipairs(removeTest) do
				if value == v then
					return true
				end
			end

			return false
		end
	end

	local newIndex = 1

	for i, value in ipairs(obj) do
		if not test(value, newIndex, i) then
			if i ~= newIndex then
				obj[newIndex] = obj[i] -- Move to new index
				obj[i] = nil -- Delete from old index
			end

			newIndex += 1 -- Increment index
		else
			obj[i] = nil
		end
	end

	return nil
end

return TableUtil
