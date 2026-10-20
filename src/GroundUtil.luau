--!strict
--[=[
	@class GroundUtil

	Raycasting helpers for finding the ground below a position, snapping models onto
	the floor, point-in-part tests, and one-off raycasts without building
	RaycastParams by hand.
]=]

local RAY_START_OFFSET = Vector3.new(0, 1, 0)
local DEFAULT_SNAP_DEPTH = 100

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

--[=[
	Whether `point` lies inside a part's box, taking its rotation into account. The
	part's shape is ignored: a ball or cylinder is tested as its bounding box.

	@within GroundUtil
	@param part BasePart
	@param point Vector3
	@return boolean -- Points on the surface count as inside.
]=]
function GroundUtil.isPointInPart(part: BasePart, point: Vector3): boolean
	local localPoint = part.CFrame:PointToObjectSpace(point)
	local half = part.Size * 0.5
	return math.abs(localPoint.X) <= half.X and math.abs(localPoint.Y) <= half.Y and math.abs(localPoint.Z) <= half.Z
end

--[=[
	Returns `pivot` moved down so the model, centred on its pivot, rests on the
	floor below it. The pivot's rotation is kept. Returns `pivot` unchanged when no
	floor is found within `depth` studs.

	```lua
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { workspace.Map }

	model:PivotTo(GroundUtil.getSnappedCFrame(model, spawnCFrame, params))
	```

	@within GroundUtil
	@param model Model
	@param pivot CFrame -- Where the model would be placed. The ray starts here.
	@param raycastParams RaycastParams? -- Defaults to excluding the model itself.
	@param depth number? -- How far down to look, in studs. Defaults to 100.
	@return CFrame
]=]
function GroundUtil.getSnappedCFrame(model: Model, pivot: CFrame, raycastParams: RaycastParams?, depth: number?): CFrame
	local params = raycastParams
	if not params then
		local excludeModel = RaycastParams.new()
		excludeModel.FilterType = Enum.RaycastFilterType.Exclude
		excludeModel.FilterDescendantsInstances = { model }
		params = excludeModel
	end

	local floor = workspace:Raycast(pivot.Position, Vector3.new(0, -(depth or DEFAULT_SNAP_DEPTH), 0), params)
	if not floor then
		return pivot
	end
	return pivot.Rotation + floor.Position + Vector3.new(0, model:GetExtentsSize().Y / 2, 0)
end

--[=[
	Pivots `model` onto the floor below `pivot`. See [GroundUtil.getSnappedCFrame].

	@within GroundUtil
	@param model Model
	@param pivot CFrame
	@param raycastParams RaycastParams? -- Defaults to excluding the model itself.
	@param depth number? -- Defaults to 100.
	@return CFrame -- The CFrame the model was pivoted to.
]=]
function GroundUtil.snapToFloorPivot(model: Model, pivot: CFrame, raycastParams: RaycastParams?, depth: number?): CFrame
	local snapped = GroundUtil.getSnappedCFrame(model, pivot, raycastParams, depth)
	model:PivotTo(snapped)
	return snapped
end

return table.freeze(GroundUtil)
