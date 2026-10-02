--!strict
--[=[
	@class SystemUtil

	General runtime helpers: frame-driven timers, disconnecting connections, cached
	product info and platform checks.
]=]

local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local _cache: { [any]: any } = {}

local SystemUtil = {}

--[=[
	Calls `callback` once at least `delay` seconds have passed, checking every
	`RunService.Stepped`. Does not yield.

	#### Example:
	```lua
	SystemUtil.timeout(1, function()
		print("One second later")
	end)
	```

	@within SystemUtil
	@param delay number -- Seconds to wait.
	@param callback (number) -> () -- Receives the seconds elapsed since the timeout started.
]=]
function SystemUtil.timeout(delay: number, callback: (number) -> boolean?)
	assert(typeof(delay) == "number", "Util.timeout - delay must be a number")
	assert(typeof(callback) == "function", "Util.timeout - callback must be a function")

	task.spawn(function()
		local start = os.clock()
		local connection: RBXScriptConnection
		local elapsedTime: number = 0

		connection = RunService.Stepped:Connect(function(_time: number, deltaTime: number)
			elapsedTime += deltaTime

			if os.clock() - start >= delay then
				connection:Disconnect()
				callback(elapsedTime)
			end
		end)
	end)
end

--[=[
	Calls `callback` every `interval` seconds, checking every `RunService.Stepped`.
	Each call runs in its own thread. Return `false` from the callback, or call
	`:Disconnect()` on the returned connection, to stop the interval.

	#### Example:
	```lua
	local ticks = 0
	SystemUtil.interval(1, function()
		ticks += 1
		return ticks < 10 -- stop after 10 ticks
	end)
	```

	@within SystemUtil
	@param interval number -- Seconds between calls.
	@param callback (number, number) -> boolean? -- Receives the seconds elapsed since the interval started and the last frame's delta time.
	@return RBXScriptConnection
]=]
function SystemUtil.interval(interval: number, callback: (number, number) -> boolean?): RBXScriptConnection
	assert(typeof(interval) == "number", "Util.interval - interval must be a number")
	assert(typeof(callback) == "function", "Util.interval - callback must be a function")

	local elapsedTime: number = 0
	local lastEventAt: number = os.clock()

	local connection: RBXScriptConnection

	connection = RunService.Stepped:Connect(function(_time: number, deltaTime: number)
		elapsedTime += deltaTime

		if os.clock() - lastEventAt >= interval then
			lastEventAt = os.clock()

			task.spawn(function()
				local success = callback(elapsedTime, deltaTime)

				if success == false then
					connection:Disconnect()
				end
			end)
		end
	end)

	return connection
end

--[=[
	Checks if a value is in a table.

	#### Example:
	```lua
	SystemUtil.inTable({ 1, 2, 3 }, 2) -- true
	SystemUtil.inTable({ 1, 2, 3 }, 4) -- false
	SystemUtil.inTable({ Part, 2, 3, Part2 = true }, Part) -- true
	```

	@within SystemUtil
	@param searchTable { [any]: any }
	@param target any
	@return boolean
]=]
function SystemUtil.inTable(searchTable: { [any]: any }, target: any): boolean
	assert(typeof(searchTable) == "table", "Util.inTable - searchTable must be a table")

	for _, value: any in pairs(searchTable) do
		if value == target then
			return true
		end
	end

	return false
end

--[=[
	Disconnects a connection, or every connection in an array. Nil values and
	non-connections in the array are skipped.

	```lua
	SystemUtil.disconnect(connection)
	SystemUtil.disconnect({ connectionA, connectionB })
	```

	@within SystemUtil
	@param connection RBXScriptConnection? | { RBXScriptConnection? }
]=]
function SystemUtil.disconnect(connection: RBXScriptConnection? | { RBXScriptConnection? })
	if connection == nil then
		return
	end

	if typeof(connection) == "table" then
		for _, conn: RBXScriptConnection? in ipairs(connection) do
			if typeof(conn) ~= "RBXScriptConnection" then
				continue
			end
			conn:Disconnect()
			conn = nil
		end

		return
	end

	connection:Disconnect()
	connection = nil
end

--[=[
	Returns `MarketplaceService:GetProductInfo` for a product. Successful results are
	cached for the lifetime of the server or client, and failed requests return nil
	instead of erroring.

	```lua
	local info = SystemUtil.getProductInfo(productId, Enum.InfoType.Product)
	if info then
		print(info.Name, info.PriceInRobux)
	end
	```

	@within SystemUtil
	@yields
	@param productId number
	@param infoType Enum.InfoType? -- Defaults to `Enum.InfoType.Asset`.
	@return { [any]: any }?
]=]
function SystemUtil.getProductInfo(productId: number, infoType: Enum.InfoType?): { [any]: any }?
	local _infoType: Enum.InfoType = infoType or Enum.InfoType.Asset
	local infoTypeName: string = _infoType.Name

	local success: boolean, result: { [any]: any } = pcall(function()
		local cacheIndex: string = `{infoTypeName}-{productId}`

		if _cache[cacheIndex] then
			return _cache[cacheIndex]
		end

		local productInfo: { [any]: any } = MarketplaceService:GetProductInfo(productId, _infoType)

		_cache[cacheIndex] = productInfo

		return productInfo
	end)

	return success and result or nil
end

--[=[
	Returns whether the player is on a touch device: touch is enabled and neither a
	keyboard nor a mouse is. In Studio only `TouchEnabled` is checked, so the device
	emulator counts as mobile.

	@within SystemUtil
	@client
	@return boolean
]=]
function SystemUtil.isMobile(): boolean
	if RunService:IsStudio() then
		return UserInputService.TouchEnabled
	end
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled
end

--[=[
	Returns whether a gamepad is enabled. This is also true on PC or mobile while a
	controller is connected.

	@within SystemUtil
	@client
	@return boolean
]=]
function SystemUtil.isConsole(): boolean
	if UserInputService.GamepadEnabled then
		return true
	end
	return false
end

return SystemUtil
