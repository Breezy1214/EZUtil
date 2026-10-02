--!strict
--[=[
	@class AimIndicator

	A single flat, neon disc that marks where an ability will land. The module keeps
	one indicator at a time: creating a new one destroys the previous one.

	```lua
	AimIndicator.create(8, Color3.fromRGB(80, 160, 255))

	RunService.RenderStepped:Connect(function()
		AimIndicator.update(mouseHitPosition)
	end)

	-- Later
	AimIndicator.destroy()
	```
]=]

local AimIndicator = {}

local CYLINDER_ROTATION = CFrame.Angles(0, 0, math.rad(90))
local indicator: BasePart? = nil

--[=[
	Destroys any existing indicator and creates a new anchored, non-colliding,
	half-transparent neon cylinder lying flat. It starts out of sight (100 studs below
	the origin) until [AimIndicator.update] moves it.

	@within AimIndicator
	@param size number -- The diameter of the disc, in studs.
	@param color Color3? -- Defaults to `Color3.fromRGB(255, 80, 60)`.
	@param parent Instance? -- Defaults to `workspace`.
	@return BasePart -- The indicator part.
]=]
function AimIndicator.create(size: number, color: Color3?, parent: Instance?): BasePart
	AimIndicator.destroy()

	local part = Instance.new("Part")
	part.Name = "AimIndicator"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(0.1, size, size)
	part.CFrame = CFrame.new(0, -100, 0) * CYLINDER_ROTATION
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Color = color or Color3.fromRGB(255, 80, 60)
	part.Material = Enum.Material.Neon
	part.Transparency = 0.5
	part.Parent = parent or workspace
	indicator = part
	return part
end

--[=[
	Moves the indicator so it lies flat on `position`, raised 0.15 studs to avoid
	z-fighting with the ground. Does nothing if no indicator exists.

	@within AimIndicator
	@param position Vector3 -- A position on the ground.
]=]
function AimIndicator.update(position: Vector3)
	if not indicator then
		return
	end
	indicator.CFrame = CFrame.new(position.X, position.Y + 0.15, position.Z) * CYLINDER_ROTATION
end

--[=[
	Destroys the current indicator, if there is one.

	@within AimIndicator
]=]
function AimIndicator.destroy()
	if indicator then
		indicator:Destroy()
		indicator = nil
	end
end

return AimIndicator
