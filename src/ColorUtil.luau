--!strict
--[=[
	@class ColorUtil

	Converts Color3 values to and from plain `{ R, G, B }` tables of 0-255 integers,
	which can be saved to a DataStore or sent over a remote, and compares and keys
	colors by those 8-bit channels.

	```lua
	local saved = ColorUtil.serialize(Color3.fromRGB(217, 169, 135)) -- { R = 217, G = 169, B = 135 }
	local color = ColorUtil.deserialize(saved, Color3.new(1, 1, 1))
	print(ColorUtil.toKey(color)) -- "217,169,135"
	```
]=]

--[=[
	A color as 0-255 integer channels.

	@interface SerializedColor
	@within ColorUtil
	.R number
	.G number
	.B number
]=]
export type SerializedColor = {
	R: number,
	G: number,
	B: number,
}

--[=[
	@type ColorLike Color3 | SerializedColor
	@within ColorUtil
]=]
export type ColorLike = Color3 | SerializedColor

local ColorUtil = {}

local function isChannel(value: any): boolean
	return type(value) == "number" and value >= 0 and value <= 255 and value % 1 == 0
end

local function channels(color: ColorLike): (number, number, number)
	if typeof(color) == "Color3" then
		local color3 = color :: Color3
		return math.round(color3.R * 255), math.round(color3.G * 255), math.round(color3.B * 255)
	end
	local serialized = color :: SerializedColor
	return serialized.R, serialized.G, serialized.B
end

--[=[
	Whether `value` is a table with integer `R`, `G` and `B` fields from 0 to 255.

	@within ColorUtil
	@param value any
	@return boolean
]=]
function ColorUtil.isSerialized(value: any): boolean
	return type(value) == "table" and isChannel(value.R) and isChannel(value.G) and isChannel(value.B)
end

--[=[
	Converts a Color3, or copies a serialized color, to a new `{ R, G, B }` table.
	Channels are rounded to the nearest 8-bit value.

	@within ColorUtil
	@param color ColorLike
	@return SerializedColor
]=]
function ColorUtil.serialize(color: ColorLike): SerializedColor
	local r, g, b = channels(color)
	return { R = r, G = g, B = b }
end

--[=[
	Converts a serialized color to a Color3. Returns `fallback` when `value` is not a
	valid serialized color, such as missing or corrupted saved data.

	@within ColorUtil
	@param value any
	@param fallback Color3?
	@return Color3? -- nil when `value` is invalid and no fallback is given.
]=]
function ColorUtil.deserialize(value: any, fallback: Color3?): Color3?
	if ColorUtil.isSerialized(value) then
		return Color3.fromRGB(value.R, value.G, value.B)
	end
	return fallback
end

--[=[
	Converts a serialized color to a Color3.

	@within ColorUtil
	@param value SerializedColor
	@return Color3
]=]
function ColorUtil.toColor3(value: SerializedColor): Color3
	return Color3.fromRGB(value.R, value.G, value.B)
end

--[=[
	Whether two colors have the same 8-bit channels. Either side can be a Color3 or a
	serialized color. Anything else is never equal.

	```lua
	ColorUtil.equals(Color3.fromRGB(10, 20, 30), { R = 10, G = 20, B = 30 }) -- true
	```

	@within ColorUtil
	@param left any
	@param right any
	@return boolean
]=]
function ColorUtil.equals(left: any, right: any): boolean
	local leftValid = typeof(left) == "Color3" or ColorUtil.isSerialized(left)
	local rightValid = typeof(right) == "Color3" or ColorUtil.isSerialized(right)
	if not leftValid or not rightValid then
		return false
	end
	local r1, g1, b1 = channels(left)
	local r2, g2, b2 = channels(right)
	return r1 == r2 and g1 == g2 and b1 == b2
end

--[=[
	Returns the index of the first palette color equal to `value`, or nil.

	```lua
	local index = ColorUtil.findInPalette(saved, SKIN_COLORS)
	local isAllowed = index ~= nil
	```

	@within ColorUtil
	@param value any
	@param palette { ColorLike }
	@return number?
]=]
function ColorUtil.findInPalette(value: any, palette: { ColorLike }): number?
	for index, color in palette do
		if ColorUtil.equals(value, color) then
			return index
		end
	end
	return nil
end

--[=[
	A string key for a color, such as `"217,169,135"`. Equal colors give equal keys,
	so it can index a dictionary.

	@within ColorUtil
	@param color ColorLike
	@return string
]=]
function ColorUtil.toKey(color: ColorLike): string
	local r, g, b = channels(color)
	return `{r},{g},{b}`
end

--[=[
	Parses a key made by [ColorUtil.toKey] back into a Color3.

	@within ColorUtil
	@param key string
	@return Color3? -- nil when the key is malformed.
]=]
function ColorUtil.fromKey(key: string): Color3?
	local r, g, b = string.match(key, "^(%d+),(%d+),(%d+)$")
	local red, green, blue = tonumber(r), tonumber(g), tonumber(b)
	if red and green and blue and red <= 255 and green <= 255 and blue <= 255 then
		return Color3.fromRGB(red, green, blue)
	end
	return nil
end

return table.freeze(ColorUtil)
