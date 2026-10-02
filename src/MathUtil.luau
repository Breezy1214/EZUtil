--!strict
--[=[
	@class MathUtil

	Number helpers: interpolation, rounding, formatting and abbreviating numbers,
	random values, and positions on parts.
]=]

local MathUtil = {}

--[=[
	Interpolates between two numbers.

	#### Example:
	```lua
	MathUtil.lerp(0, 10, .5) -- 5
	MathUtil.lerp(0, 10, 1) -- 10
	```

	@within MathUtil
	@param start number
	@param stop number
	@param alpha number
	@return number
]=]
function MathUtil.lerp(start: number, stop: number, alpha: number): number
	return start * (1 - alpha) + stop * alpha
end

--[=[
	Rounds a number to the nearest integer.

	#### Example:
	```lua
	MathUtil.round(1.5) -- 2
	MathUtil.round(1.4) -- 1
	```

	@within MathUtil
	@param _number number
	@return number
]=]
function MathUtil.round(_number: number): number
	assert(typeof(_number) == "number", "Number argument must be a number")

	local decimal: number = _number % 1

	return math[decimal >= 0.5 and "ceil" or "floor"](_number)
end

--[=[
	Formats a number to have commas.

	#### Example:
	```lua
	MathUtil.formatInt(1000) -- 1,000
	MathUtil.formatInt(1000.01) -- 1,000.01
	```

	@within MathUtil
	@param number number
	@param decimals number? -- The number of decimal places to round to. Defaults to 2.
	@return string
]=]
function MathUtil.formatInt(number: number, decimals: number?): string -- 1000.01 to 1,000.01
	assert(typeof(number) == "number", "Number argument must be a number")

	local numberString: string = tostring(number)

	if not numberString then
		error("Could not convert number to string")
	end

	local minus: string?, int: string?, fraction: string? = numberString:match("([-]?)(%d+)([.]?%d*)")

	if not minus or not int or not fraction then
		return ""
	end

	if #fraction > 0 then
		fraction = fraction:sub(1, (decimals or 2) + 1)
		if #fraction == 1 then
			fraction = ""
		end
	end

	int = string.gsub(int:reverse(), "(%d%d%d)", "%1,"):reverse():gsub("^,", "")

	return `{minus}{int}{fraction}`
end

--[=[
	Returns a random integer between two numbers (inclusive), or a float when `float`
	is true.

	#### Example:
	```lua
	MathUtil.random(1, 10) -- 5
	MathUtil.random(1, 10, true) -- 5.5
	MathUtil.random(10) -- 5 (min defaults to 1)
	```

	@within MathUtil
	@param minValue number -- The minimum, or the maximum when `maxValue` is nil.
	@param maxValue number?
	@param float boolean? -- Whether to return as a float or not. Defaults to false.
	@return number
]=]
function MathUtil.random(minValue: number, maxValue: number?, float: boolean?): number
	assert(typeof(minValue) == "number", "Number1 argument must be a number")
	assert(typeof(maxValue) == "number" or maxValue == nil, "Number2 argument must be a number or nil")
	assert(typeof(float) == "boolean" or float == nil, "Float argument must be a boolean or nil")

	local min: number = not maxValue and 1 or minValue -- If maxValue is not defined, use 1 as min
	local max: number = maxValue or minValue

	return float == true and Random.new():NextNumber(min, max) -- Return float
		or Random.new():NextInteger(min, max) -- Return integer
end

local sharedRandom = Random.new()

--[=[
	Returns a random float between `minValue` and `maxValue`, using a shared Random
	object.

	@within MathUtil
	@param minValue number
	@param maxValue number
	@return number
]=]
function MathUtil.randomRange(minValue: number, maxValue: number): number
	return minValue + sharedRandom:NextNumber() * (maxValue - minValue)
end

local charset: string = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
local charsetLength: number = #charset

--[=[
	Returns a random string of letters and digits.

	#### Example:
	```lua
	MathUtil.randomString() -- "aB3dE9gH1jK0mN4pQr"
	MathUtil.randomString(10) -- "aB3dE9gH1j"
	```

	@within MathUtil
	@param length number? -- The length of the string. Defaults to 18.
	@return string
]=]
function MathUtil.randomString(length: number?): string
	assert(typeof(length) == "number" or length == nil, "Length argument must be a number or nil")

	local res: string = ""

	for _ = 1, (length or 18) do
		local random: number = MathUtil.random(charsetLength)
		res = res .. charset:sub(random, random)
	end

	return res
end

--[=[
	Returns a random element of an array, or a random child of an Instance.

	#### Example:
	```lua
	MathUtil.randomObj({ "a", "b", "c" }) -- "b"
	MathUtil.randomObj(workspace.Map.SpawnPoints) -- SpawnPoint3
	```

	@within MathUtil
	@param obj { any } | Instance
	@return any
]=]
function MathUtil.randomObj(obj: { [any]: any } | Instance): any
	assert(typeof(obj) == "table" or typeof(obj) == "Instance", "Object argument must be a table or Instance")

	if typeof(obj) == "Instance" then
		-- Convert to a table
		obj = obj:GetChildren()
	end

	if typeof(obj) == "table" then
		return obj[MathUtil.random(1, #obj)]
	end

	return
end

local shortNumberSuffixes: { string } = { "K", "M", "B", "T", "Q" }

--[=[
	Shortens a large number to a readable format.
	Useful for displaying large numbers that don't require exact precision.
	Common use cases are for displaying XP, money in leaderboards, damage etc.

	Shortened numbers keep one decimal place, truncated rather than rounded, so a value never
	reads as more than it is: 999,999 shortens to 999.9K instead of rolling up to 1,000K.

	#### Example:
	```lua
	MathUtil.shortenNumber(1000) -- 1K
	MathUtil.shortenNumber(1200) -- 1.2K
	MathUtil.shortenNumber(999999) -- 999.9K
	MathUtil.shortenNumber(1000000) -- 1M
	MathUtil.shortenNumber(1000000000) -- 1B
	MathUtil.shortenNumber(1000000000000) -- 1T
	MathUtil.shortenNumber(1000000000000000) -- 1Q
	```

	minimumTiers is useful for when you want to shorten a number but only if it's at least a certain tier.
	For example, to only shorten numbers of 1,000,000 or more:
	```lua
	MathUtil.shortenNumber(250000, 2) -- 250,000
	MathUtil.shortenNumber(1000000, 2) -- 1M
	```

	A tier is the amount of commas in a number. For example, 1,000,000 has 2 tiers and 1,000 has 1 tier.

	Tier list and their abbreviations:
	- 1,000 = K
	- 1,000,000 = M
	- 1,000,000,000 = B
	- 1,000,000,000,000 = T
	- 1,000,000,000,000,000 = Q

	@within MathUtil
	@param number number | string
	@param minimumTiers number? -- The minimum number of tiers to shorten. Defaults to 1.
	@return string
]=]
function MathUtil.shortenNumber(number: number | string, minimumTiers: number?): string
	assert(typeof(number) == "number" or typeof(number) == "string", "Number argument must be a number or string")
	assert(typeof(minimumTiers) == "number" or minimumTiers == nil, "MinimumTiers argument must be a number or nil")

	number = typeof(number) == "string" and tonumber(number) or number

	assert(typeof(number) == "number", "Number argument be a number or string that can be converted to a number")

	local negative: number = math.abs(number) == number and 1 or -1
	number = math.abs(number)

	local tier: number = math.log10(number) / 3

	if tier < (minimumTiers or 1) then -- If tier is less than minimumTiers, return the number
		return MathUtil.formatInt(number * negative, 0)
	end

	tier = math.floor(tier)

	local tierSuffix: string? = shortNumberSuffixes[tier] or shortNumberSuffixes[#shortNumberSuffixes] -- Get tier or use highest tier if # too high

	if not tierSuffix then
		return ""
	end

	-- The epsilon absorbs binary representation error, so 13200/1000 truncates to 13.2 and not 13.1.
	local scaled: number = number / 10 ^ (3 * tier)
	local truncated: number = math.floor(scaled * 10 + 1e-9) / 10

	return MathUtil.formatInt(truncated * negative, 1) .. tierSuffix
end

--[=[
	Gets a Vector3 from an object containing a Vector3 or CFrame.

	#### Supports:
	- Vector3
	- CFrame
	- Attachment
	- BasePart
	- CFrameValue
	- Vector3Value
	- Camera

	@within MathUtil
	@param object Vector3 | CFrame | Instance
	@return Vector3?
]=]
function MathUtil.getVector3(
	object: Vector3 | CFrame | Attachment | BasePart | CFrameValue | Vector3Value | Camera
): Vector3?
	return (typeof(object) == "Vector3" and object)
		or (typeof(object) == "CFrame" and object.Position)
		or (typeof(object) == "Instance" and ((object:IsA("Attachment") and object.WorldPosition) or (object:IsA(
			"BasePart"
		) and object.Position) or (object:IsA("CFrameValue") and object.Value and object.Value.Position) or (object:IsA(
			"Vector3Value"
		) and object.Value) or (object:IsA("Camera") and object.CFrame.Position)))
		or nil
end

--[=[
	Gets the distance between two positions. Accepts anything [MathUtil.getVector3]
	supports, and errors if either value has no position.

	@within MathUtil
	@param origin Vector3 | CFrame | Instance
	@param target Vector3 | CFrame | Instance
	@return number
]=]
function MathUtil.getDistance(origin: any, target: any)
	local originVector3: Vector3? = MathUtil.getVector3(origin)
	local targetVector3: Vector3? = MathUtil.getVector3(target)

	assert(
		originVector3,
		"Util.getDistance - Parameter 1 is missing a Vector3 value or an Instance with a Vector3 Position"
	)
	assert(
		targetVector3,
		"Util.getDistance - Parameter 2 is missing a Vector3 value or an Instance with a Vector3 Position"
	)

	return (originVector3 - targetVector3).Magnitude
end

--[=[
	Returns the CFrame at the centre of a part's bottom face, keeping the part's
	rotation.

	@within MathUtil
	@param part BasePart
	@return CFrame
]=]
function MathUtil.getPartBottomSurface(part: BasePart): CFrame
	return part.CFrame * CFrame.new(0, -part.Size.Y / 2, 0)
end

--[=[
	Returns a random flat offset (Y = 0) inside a disc of the given radius. Points are
	spread evenly over the disc's area rather than bunched at its centre.

	```lua
	local spawnPosition = center + MathUtil.randomInDisc(20)
	```

	@within MathUtil
	@param radius number
	@return Vector3
]=]
function MathUtil.randomInDisc(radius: number): Vector3
	local angle = math.random() * 2 * math.pi
	local distance = math.sqrt(math.random()) * radius

	return Vector3.new(math.cos(angle) * distance, 0, math.sin(angle) * distance)
end

--[=[
	Returns a random CFrame across the part's X and Z extents, at the height of the
	part's centre and with the part's rotation.

	@within MathUtil
	@param part BasePart
	@return CFrame
]=]
function MathUtil.getRandomInPart(part: BasePart): CFrame
	local random = Random.new()
	local randomCFrame = part.CFrame
		* CFrame.new(
			random:NextNumber(-part.Size.X / 2, part.Size.X / 2),
			0,
			random:NextNumber(-part.Size.Z / 2, part.Size.Z / 2)
		)
	return randomCFrame
end

--[=[
	Rounds `num` to the nearest value with `numPlaces` decimal places.

	```lua
	MathUtil.roundNumber(1.236, 2) -- 1.24
	MathUtil.roundNumber(1.231, 2) -- 1.23
	```

	@within MathUtil
	@param num number
	@param numPlaces number
	@return number
]=]
function MathUtil.roundNumber(num: number, numPlaces: number): number
	local scale = 10 ^ numPlaces
	return math.round(num * scale) / scale
end

--[=[
	Returns true only when `number` is a number and not negative. Useful for
	validating amounts sent by clients.

	```lua
	MathUtil.isNumberSecure(5) -- true
	MathUtil.isNumberSecure(-5) -- false
	MathUtil.isNumberSecure("5") -- false
	```

	@within MathUtil
	@param number any
	@return boolean
]=]
function MathUtil.isNumberSecure(number: any): boolean
	if number == nil then
		return false
	end
	if typeof(number) ~= "number" then
		return false
	end
	if number < 0 then
		return false
	end

	return true
end

return MathUtil
