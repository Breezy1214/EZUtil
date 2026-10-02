--!strict
--[=[
	@class EZUtil

	EZUtil is a collection of small, game-agnostic Roblox utilities. Every module is
	exposed as a field of the package root and is required lazily, the first time
	that field is read, so a client-only module never runs on the server (and the
	reverse).

	```lua
	local ReplicatedStorage = game:GetService("ReplicatedStorage")

	local EZUtil = require(ReplicatedStorage.Packages.EZUtil)

	print(EZUtil.TableUtil.tableLength({ a = 1, b = 2 })) -- 2
	print(EZUtil.MathUtil.shortenNumber(1200)) -- 1.2K
	print(EZUtil.DateUtil.formatDuration(3725)) -- 1h 2m 5s

	-- Modules can also be required on their own.
	local TableUtil = require(ReplicatedStorage.Packages.EZUtil.TableUtil)
	```

	The package root is fully typed, so `EZUtil.` autocompletes every module and its
	functions.

	#### Modules

	- [AimIndicator]: a neon disc that marks where an ability will land.
	- [CharacterRigUtil]: humanoids, animators, body parts and skinned mesh rigs.
	- [DateUtil]: timestamps, periods and human-readable durations.
	- [FixedRewardSequence]: deterministic, evenly spread reward sequences.
	- [GroundUtil]: downward ground projection and one-call raycasts.
	- [InstanceUtil]: tag lookups, welds and look-at tweens.
	- [JanitorUtil]: safe Janitor destruction.
	- [LayoutUtil]: ScrollingFrame canvas and item sizing.
	- [MathUtil]: rounding, formatting, random values and positions.
	- [ParticleUtil]: particle templates, bursts and cleanup.
	- [PlayerUtil]: humanoids, animations, group ranks and player UI.
	- [ProfileUtil]: named MicroProfiler scopes.
	- [ProjectileUtil]: ballistic projectiles and aim preview beams.
	- [SearchUtil]: searching Instance trees and nested tables.
	- [SystemUtil]: timers, connections, product info and platform checks.
	- [TableDiffUtil]: shallow table comparison.
	- [TableUtil]: table and string helpers.
	- [VfxUtil]: attribute-driven VFX templates.
]=]

export type EZUtil = {
	AimIndicator: typeof(require(script.AimIndicator)),
	CharacterRigUtil: typeof(require(script.CharacterRigUtil)),
	DateUtil: typeof(require(script.DateUtil)),
	FixedRewardSequence: typeof(require(script.FixedRewardSequence)),
	GroundUtil: typeof(require(script.GroundUtil)),
	InstanceUtil: typeof(require(script.InstanceUtil)),
	JanitorUtil: typeof(require(script.JanitorUtil)),
	LayoutUtil: typeof(require(script.LayoutUtil)),
	MathUtil: typeof(require(script.MathUtil)),
	ParticleUtil: typeof(require(script.ParticleUtil)),
	PlayerUtil: typeof(require(script.PlayerUtil)),
	ProfileUtil: typeof(require(script.ProfileUtil)),
	ProjectileUtil: typeof(require(script.ProjectileUtil)),
	SearchUtil: typeof(require(script.SearchUtil)),
	SystemUtil: typeof(require(script.SystemUtil)),
	TableDiffUtil: typeof(require(script.TableDiffUtil)),
	TableUtil: typeof(require(script.TableUtil)),
	VfxUtil: typeof(require(script.VfxUtil)),
}

local EZUtil = {}

local function loadModule(name: string): any
	local child = script:FindFirstChild(name)
	if not child or not child:IsA("ModuleScript") then
		return nil
	end

	local module = (require :: any)(child)
	rawset(EZUtil, name, module)
	return module
end

setmetatable(EZUtil, {
	__index = function(_, key: any)
		if typeof(key) ~= "string" then
			return nil
		end
		return loadModule(key)
	end,
})

return (EZUtil :: any) :: EZUtil
