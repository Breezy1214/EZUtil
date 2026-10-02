--!strict
--[=[
	@class TableDiffUtil

	Helpers for comparing tables.
]=]

local TableDiffUtil = {}

--[=[
	Returns whether two tables have the same keys with equal (`==`) values. Nested
	tables are compared by reference, not by contents.

	```lua
	TableDiffUtil.shallowEqual({ a = 1, b = 2 }, { b = 2, a = 1 }) -- true
	TableDiffUtil.shallowEqual({ a = {} }, { a = {} }) -- false
	```

	@within TableDiffUtil
	@param left { [any]: any }
	@param right { [any]: any }
	@return boolean
]=]
function TableDiffUtil.shallowEqual(left: { [any]: any }, right: { [any]: any }): boolean
	if left == right then
		return true
	end

	for key, value in pairs(left) do
		if right[key] ~= value then
			return false
		end
	end

	for key, value in pairs(right) do
		if left[key] ~= value then
			return false
		end
	end

	return true
end

return TableDiffUtil
