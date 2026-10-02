--!strict
--[=[
	@class ProfileUtil

	Helpers for labelling code in the MicroProfiler.
]=]

local ProfileUtil = {}

--[=[
	Runs `callback` inside a MicroProfiler scope named `label` and returns whatever it
	returns. The scope is always closed, and an error thrown by `callback` is
	re-raised after it closes.

	Only use this for synchronous code: `callback` must not yield.

	```lua
	local path = ProfileUtil.scope("ComputePath", function()
		return computePath(start, goal)
	end)
	```

	@within ProfileUtil
	@param label string -- The name shown in the MicroProfiler.
	@param callback () -> T... -- A function that does not yield.
	@return T... -- The values returned by `callback`.
]=]
function ProfileUtil.scope<T...>(label: string, callback: () -> T...): T...
	debug.profilebegin(label)

	local results = table.pack(pcall(callback))

	debug.profileend()

	if not results[1] then
		error(results[2], 2)
	end

	return table.unpack(results, 2, results.n)
end

return table.freeze(ProfileUtil)
