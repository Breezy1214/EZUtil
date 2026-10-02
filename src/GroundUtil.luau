--!strict
--[=[
	@class GroundUtil

	Raycasting helpers for finding the ground below a position and for one-off
	raycasts without building RaycastParams by hand.
]=]

local RAY_START_OFFSET = Vector3.new(0, 1, 0)

local GroundUtil = {}

--[=[
	Raycasts straight down from 1 stud above `position` and returns the hit position,
	plus `resultOffset` if one is given.

	```lua
	local groundPosition = GroundUtil.projectDown(target, 50, params, Vector3.new(0, 0.1, 0))
	```

	@within GroundUtil
	@param position Vector3 -- The position to project.
	@param depth number -- How far down to cast, in studs.
	@param raycastParams RaycastParams
	@param resultOffset Vector3? -- Added to the hit position.
	@return Vector3? -- nil if nothing was hit.
]=]
function GroundUtil.projectDown(
	position: Vector3,
	depth: number,
	raycastParams: RaycastParams,
	resultOffset: Vector3?
): Vector3?
	local result = workspace:Raycast(position + RAY_START_OFFSET, Vector3.new(0, -depth, 0), raycastParams)
	return result and result.Position + (resultOffset or Vector3.zero) or nil
end

--[=[
	Raycasts in the workspace, building the RaycastParams from the arguments.

	@within GroundUtil
	@param origin Vector3
	@param direction Vector3 -- The ray's direction and length.
	@param filterList { Instance }? -- Defaults to an empty list.
	@param filterType Enum.RaycastFilterType? -- Defaults to `Exclude`.
	@param collisionGroup string? -- Defaults to `"Default"`.
	@return RaycastResult?
]=]
function GroundUtil.raycast(
	origin: Vector3,
	direction: Vector3,
	filterList: { Instance }?,
	filterType: Enum.RaycastFilterType?,
	collisionGroup: string?
): RaycastResult?
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = filterType or Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = filterList or {}
	raycastParams.CollisionGroup = collisionGroup or "Default"

	return workspace:Raycast(origin, direction, raycastParams)
end

return table.freeze(GroundUtil)
