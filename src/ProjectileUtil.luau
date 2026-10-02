--!strict
--[=[
	@class ProjectileUtil

	Ballistic projectile helpers: solve the launch velocity that reaches a target in a
	given time, move a part along that arc with optional hits and bounces, and draw
	the arc as an aim preview.

	Gravity defaults to `workspace.Gravity` (read when the module is first required),
	pointing down.

	```lua
	local controller = ProjectileUtil.launch({
		part = rock,
		origin = hand.Position,
		target = mouseHit,
		duration = 0.8,
		raycastParams = params,
		onHit = function(position, normal)
			rock:Destroy()
		end,
	})
	```
]=]

local RunService = game:GetService("RunService")

local ProjectileUtil = {}

--[=[
	Options for [ProjectileUtil.launch].

	@interface ProjectileConfig
	@within ProjectileUtil
	.part BasePart -- The part to move. It is anchored for the flight.
	.origin Vector3 -- Where the flight starts.
	.target Vector3 -- Where the arc lands after `duration` seconds.
	.duration number -- Flight time in seconds.
	.faceDirection boolean? -- Point the part along its velocity. Defaults to false.
	.gravity Vector3? -- Defaults to `workspace.Gravity`, pointing down.
	.raycastParams RaycastParams? -- When set, each frame's movement is raycast to detect hits.
	.maxBounces number? -- How many times to bounce off hit surfaces before stopping. Defaults to 0.
	.bounceDamping number? -- Velocity multiplier applied on each bounce. Defaults to 0.7.
	.onHit ((position: Vector3, normal: Vector3?) -> ())? -- Called once when the flight ends. `normal` is nil when it ends by reaching the end of the arc.
	.onBounce ((position: Vector3, normal: Vector3, bouncesLeft: number) -> ())? -- Called after each bounce.
]=]
export type ProjectileConfig = {
	part: BasePart,
	origin: Vector3,
	target: Vector3,
	duration: number,
	faceDirection: boolean?,
	gravity: Vector3?,
	raycastParams: RaycastParams?,
	maxBounces: number?,
	bounceDamping: number?,
	onHit: ((position: Vector3, normal: Vector3?) -> ())?,
	onBounce: ((position: Vector3, normal: Vector3, bouncesLeft: number) -> ())?,
}

--[=[
	Returned by [ProjectileUtil.launch].

	@interface ProjectileController
	@within ProjectileUtil
	.Cancel (self: ProjectileController) -> () -- Stops the flight where it is, without calling `onHit`.
	.IsActive (self: ProjectileController) -> boolean -- Whether the projectile is still flying.
]=]
export type ProjectileController = {
	Cancel: (self: ProjectileController) -> (),
	IsActive: (self: ProjectileController) -> boolean,
}

--[=[
	Options for [ProjectileUtil.createAimBeam].

	@interface AimBeamConfig
	@within ProjectileUtil
	.origin Vector3 -- Where the arc starts.
	.target Vector3 -- Where the arc lands.
	.duration number -- Flight time in seconds, which sets how high the arc goes.
	.gravity Vector3? -- Defaults to `workspace.Gravity`, pointing down.
	.parent Instance -- Where to put the beam's holder part.
	.color Color3? -- Defaults to white.
	.width number? -- Defaults to 0.5.
	.transparency NumberSequence? -- Defaults to 0.5.
]=]
export type AimBeamConfig = {
	origin: Vector3,
	target: Vector3,
	duration: number,
	gravity: Vector3?,
	parent: Instance,
	color: Color3?,
	width: number?,
	transparency: NumberSequence?,
}

--[=[
	Returned by [ProjectileUtil.createAimBeam].

	@interface AimBeam
	@within ProjectileUtil
	.Update (self: AimBeam, origin: Vector3, target: Vector3, duration: number) -> () -- Redraws the arc.
	.Destroy (self: AimBeam) -> () -- Destroys the beam and its holder part.
]=]
export type AimBeam = {
	Update: (self: AimBeam, origin: Vector3, target: Vector3, duration: number) -> (),
	Destroy: (self: AimBeam) -> (),
}

local DEFAULT_GRAVITY = Vector3.new(0, -workspace.Gravity, 0)

local function safeUnit(vector: Vector3, fallback: Vector3): Vector3
	if vector.Magnitude > 1e-4 then
		return vector.Unit
	end
	return fallback
end

local function getBallisticBeamCurve(
	gravity: Vector3,
	velocity: Vector3,
	origin: Vector3,
	duration: number
): (number, number, CFrame, CFrame)
	-- Cubic Bézier control points fitted to the ballistic arc
	local c = 0.125
	local gtt = gravity * (duration * duration)
	local vt = velocity * duration
	local p3 = 0.5 * gtt + vt + origin
	local p2 = p3 - (gtt + vt) / 3
	local p1 = (c * gtt + 0.5 * vt + origin - c * (origin + p3)) / (3 * c) - p2

	local curve0 = (p1 - origin).Magnitude
	local curve1 = (p2 - p3).Magnitude

	local backAxis = safeUnit(origin - p3, Vector3.new(0, 0, -1))
	local tangent0 = safeUnit(p1 - origin, -backAxis)
	local up0 = safeUnit(tangent0:Cross(backAxis), Vector3.new(0, 1, 0))
	local tangent1 = safeUnit(p2 - p3, tangent0)
	local up1 = safeUnit(tangent1:Cross(backAxis), up0)
	local adjustedBack = safeUnit(up0:Cross(tangent0), backAxis)

	local cf0 = CFrame.fromMatrix(origin, tangent0, up0, adjustedBack)
	local cf1 = CFrame.fromMatrix(p3, tangent1, up1, adjustedBack)

	return curve0, -curve1, cf0, cf1
end

--[=[
	Returns the initial velocity that carries a projectile from `origin` to `target`
	in exactly `duration` seconds under `gravity`.

	@within ProjectileUtil
	@param origin Vector3
	@param target Vector3
	@param duration number -- Flight time in seconds.
	@param gravity Vector3? -- Defaults to `workspace.Gravity`, pointing down.
	@return Vector3
]=]
function ProjectileUtil.calculateLaunchVelocity(
	origin: Vector3,
	target: Vector3,
	duration: number,
	gravity: Vector3?
): Vector3
	local g = gravity or DEFAULT_GRAVITY
	return (target - origin - 0.5 * g * duration * duration) / duration
end

--[=[
	Returns the projectile's position `time` seconds after launch.

	@within ProjectileUtil
	@param origin Vector3
	@param velocity Vector3 -- The launch velocity.
	@param time number -- Seconds since launch.
	@param gravity Vector3? -- Defaults to `workspace.Gravity`, pointing down.
	@return Vector3
]=]
function ProjectileUtil.getPositionAtTime(origin: Vector3, velocity: Vector3, time: number, gravity: Vector3?): Vector3
	local g = gravity or DEFAULT_GRAVITY
	return 0.5 * g * time * time + velocity * time + origin
end

--[=[
	Returns the projectile's velocity `time` seconds after launch.

	@within ProjectileUtil
	@param velocity Vector3 -- The launch velocity.
	@param time number -- Seconds since launch.
	@param gravity Vector3? -- Defaults to `workspace.Gravity`, pointing down.
	@return Vector3
]=]
function ProjectileUtil.getVelocityAtTime(velocity: Vector3, time: number, gravity: Vector3?): Vector3
	local g = gravity or DEFAULT_GRAVITY
	return g * time + velocity
end

--[=[
	Anchors `config.part` and moves it along the ballistic arc from `config.origin` to
	`config.target` every Heartbeat.

	Without `raycastParams` the part flies the full arc and `onHit` is called with
	the final position and a nil normal. With `raycastParams`, each frame's movement
	is raycast: on a hit the part either bounces (reflecting its velocity, scaled by
	`bounceDamping`, while bounces remain) or stops and calls `onHit` with the hit
	position and surface normal.

	@within ProjectileUtil
	@param config ProjectileConfig
	@return ProjectileController
]=]
function ProjectileUtil.launch(config: ProjectileConfig): ProjectileController
	local part = config.part
	local gravity = config.gravity or DEFAULT_GRAVITY
	local maxBounces = config.maxBounces or 0
	local bounceDamping = config.bounceDamping or 0.7
	local faceDirection = config.faceDirection or false

	part.Anchored = true

	local origin = config.origin
	local v0 = ProjectileUtil.calculateLaunchVelocity(origin, config.target, config.duration, gravity)
	local elapsed = 0
	local bouncesLeft = maxBounces
	local active = true
	local connection: RBXScriptConnection? = nil
	local duration = config.duration

	part.CFrame = CFrame.new(origin)

	local controller = {} :: ProjectileController

	function controller:Cancel()
		if not active then
			return
		end
		active = false
		if connection then
			connection:Disconnect()
			connection = nil
		end
	end

	function controller:IsActive(): boolean
		return active
	end

	connection = RunService.Heartbeat:Connect(function(dt: number)
		if not active then
			return
		end

		local prevPos = ProjectileUtil.getPositionAtTime(origin, v0, elapsed, gravity)
		elapsed += dt

		if elapsed >= duration then
			local finalPos = ProjectileUtil.getPositionAtTime(origin, v0, duration, gravity)
			part.CFrame = CFrame.new(finalPos)
			controller:Cancel()
			if config.onHit then
				config.onHit(finalPos, nil)
			end
			return
		end

		local newPos = ProjectileUtil.getPositionAtTime(origin, v0, elapsed, gravity)

		if config.raycastParams then
			local direction = newPos - prevPos
			local result = workspace:Raycast(prevPos, direction, config.raycastParams)

			if result then
				local hitPos = result.Position
				local hitNormal = result.Normal

				if bouncesLeft > 0 then
					local hitTime = elapsed - dt + dt * ((hitPos - prevPos).Magnitude / direction.Magnitude)
					local vHit = ProjectileUtil.getVelocityAtTime(v0, hitTime - (elapsed - dt), gravity)
					local vReflected = vHit - 2 * vHit:Dot(hitNormal) * hitNormal
					vReflected = vReflected * bounceDamping

					origin = hitPos
					v0 = vReflected
					elapsed = 0
					bouncesLeft -= 1

					local gravityDir = gravity.Unit
					local vy = -vReflected:Dot(gravityDir)
					if vy > 0.1 then
						duration = 2 * vy / gravity.Magnitude
						duration = math.max(duration, 0.2)
					else
						duration = 0.2
					end

					part.CFrame = CFrame.new(hitPos)
					if config.onBounce then
						config.onBounce(hitPos, hitNormal, bouncesLeft)
					end
					return
				else
					part.CFrame = CFrame.new(hitPos)
					controller:Cancel()
					if config.onHit then
						config.onHit(hitPos, hitNormal)
					end
					return
				end
			end
		end

		if faceDirection then
			local vel = ProjectileUtil.getVelocityAtTime(v0, elapsed, gravity)
			if vel.Magnitude > 0.01 then
				part.CFrame = CFrame.lookAlong(newPos, vel.Unit)
			else
				part.CFrame = CFrame.new(newPos)
			end
		else
			part.CFrame = CFrame.new(newPos)
		end
	end)

	return controller
end

--[=[
	Draws the ballistic arc from `config.origin` to `config.target` with a single
	curved Beam, held by an invisible, anchored, non-colliding part parented to
	`config.parent`. Call `Update` to redraw it as the aim changes.

	```lua
	local beam = ProjectileUtil.createAimBeam({
		origin = hand.Position,
		target = mouseHit,
		duration = 0.8,
		parent = workspace,
	})

	RunService.RenderStepped:Connect(function()
		beam:Update(hand.Position, mouseHit, 0.8)
	end)
	```

	@within ProjectileUtil
	@param config AimBeamConfig
	@return AimBeam
]=]
function ProjectileUtil.createAimBeam(config: AimBeamConfig): AimBeam
	local gravity = config.gravity or DEFAULT_GRAVITY
	local color = config.color or Color3.new(1, 1, 1)
	local width = config.width or 0.5
	local transparency = config.transparency or NumberSequence.new(0.5)

	local holder = Instance.new("Part")
	holder.Name = "AimBeamHolder"
	holder.Anchored = true
	holder.CanCollide = false
	holder.CanQuery = false
	holder.CanTouch = false
	holder.Transparency = 1
	holder.Size = Vector3.new(0.1, 0.1, 0.1)
	holder.Parent = config.parent

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "AimBeamAttachment0"
	attachment0.Parent = holder

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "AimBeamAttachment1"
	attachment1.Parent = holder

	local beam = Instance.new("Beam")
	beam.Attachment0 = attachment0
	beam.Attachment1 = attachment1
	beam.Color = ColorSequence.new(color)
	beam.Width0 = width
	beam.Width1 = width
	beam.Transparency = transparency
	beam.FaceCamera = false
	beam.Segments = 24
	beam.Parent = holder

	local function updateCurve(origin: Vector3, target: Vector3, duration: number)
		local holderCf = CFrame.new(origin)
		holder.CFrame = holderCf
		local v0 = ProjectileUtil.calculateLaunchVelocity(origin, target, duration, gravity)
		local curve0, curve1, worldCf0, worldCf1 = getBallisticBeamCurve(gravity, v0, origin, duration)

		beam.CurveSize0 = curve0
		beam.CurveSize1 = curve1
		attachment0.CFrame = holderCf:ToObjectSpace(worldCf0)
		attachment1.CFrame = holderCf:ToObjectSpace(worldCf1)
	end

	updateCurve(config.origin, config.target, config.duration)

	local aimBeam = {} :: AimBeam

	function aimBeam:Update(newOrigin: Vector3, newTarget: Vector3, newDuration: number)
		updateCurve(newOrigin, newTarget, newDuration)
	end

	function aimBeam:Destroy()
		holder:Destroy()
	end

	return aimBeam
end

return ProjectileUtil
