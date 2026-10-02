--!strict
--[=[
	@class JanitorUtil

	Helpers for working with [Janitor](https://github.com/howmanysmall/Janitor) objects.
]=]

local Janitor = require(script.Parent.Parent.Janitor)

type Janitor = typeof(Janitor.new())

local JanitorUtil = {}

--[=[
	Destroys a Janitor unless it is nil, not a table, or already cleaning up. Errors
	thrown while destroying are caught and printed as a warning instead.

	@within JanitorUtil
	@param janitor Janitor?
]=]
function JanitorUtil.safeDestroy(janitor: Janitor?)
	if janitor and typeof(janitor) == "table" and not (janitor :: any).CurrentlyCleaning then
		local success, err = pcall(function()
			(janitor :: any):Destroy()
		end)
		if not success then
			warn("[JanitorUtil] Failed to destroy janitor:", err)
		end
	end
end

return JanitorUtil
