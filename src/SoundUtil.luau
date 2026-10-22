--!strict
--[=[
	@class SoundUtil

	Plays named sounds with priorities, fades and cross-fades. A sound player finds
	its sounds through a root folder or a lookup function, and asks an optional
	volume provider for each sound's category volume, so it works with any settings
	system.

	While sounds play, every sound below the highest playing priority is ducked to
	`duckFactor` of its volume. A sound's volume is its base volume (its own `Volume`
	when first found, or `properties.Volume`) times its category volume times any
	ducking.

	```lua
	local sounds = SoundUtil.new({
		sounds = SoundService,
		volume = function(category: string): number
			return if category == "Music" and not settings.Music then 0 else 1
		end,
	})

	sounds:play("ButtonClick")
	sounds:play({ name = "BossMusic", looped = true, priority = 1 })
	sounds:playAt("Explosion", position)
	sounds:crossFade("BossMusic", "MainMusic", 2)

	-- When a setting changes
	sounds:refreshVolumes()
	```
]=]

local RunService = game:GetService("RunService")

local Janitor = require(script.Parent.Parent.Janitor)
local Promise = require(script.Parent.Parent.Promise)

type Promise = typeof(Promise.new())

local DEFAULT_DUCK_FACTOR = 0.1
local DEFAULT_PLAY_AT_LIFETIME = 5

--[=[
	A sound to play. Only `name` is required.

	@interface SoundConfig
	@within SoundUtil
	.name string? -- The sound's name, passed to the lookup.
	.properties { [string]: any }? -- Sound properties to set before playing. `Volume` sets the base volume.
	.instance Instance? -- Plays a clone parented here, destroyed when it finishes. Otherwise the found sound itself plays.
	.lifeTime number? -- Stops a looped sound after this many seconds.
	.looped boolean? -- Overrides the sound's `Looped`.
	.priority number? -- Defaults to 0. Lower priorities are ducked while a higher one plays.
]=]
export type SoundConfig = {
	name: string?,
	properties: { [string]: any }?,
	instance: Instance?,
	lifeTime: number?,
	looped: boolean?,
	priority: number?,
}

--[=[
	Options for [SoundUtil.new].

	@interface Options
	@within SoundUtil
	.sounds Instance | (name: string) -> Sound? -- A root whose descendant Sounds are found by name, or a lookup function.
	.volume ((category: string) -> number)? -- The volume multiplier for a category: the name of the sound's SoundGroup, or `""` without one. Defaults to 1.
	.duckFactor number? -- The volume multiplier for sounds below the highest playing priority. Defaults to 0.1.
	.playAtParent Instance? -- Where `playAt` creates its emitter part. Defaults to `workspace`.
]=]
export type Options = {
	sounds: Instance | (name: string) -> Sound?,
	volume: ((category: string) -> number)?,
	duckFactor: number?,
	playAtParent: Instance?,
}

export type SoundPlayer = {
	play: (self: SoundPlayer, nameOrConfig: string | SoundConfig) -> Promise,
	playAt: (self: SoundPlayer, nameOrConfig: string | SoundConfig, position: Vector3) -> Promise,
	stop: (self: SoundPlayer, sound: (string | Sound)?, preserve: boolean?) -> boolean,
	pauseSound: (self: SoundPlayer, sound: string | Sound) -> (),
	resumeSound: (self: SoundPlayer, sound: string | Sound) -> (),
	fade: (self: SoundPlayer, sound: string | Sound, targetVolume: number, duration: number) -> Promise,
	crossFade: (self: SoundPlayer, fadeOut: string | Sound, fadeIn: string | SoundConfig, duration: number) -> Promise,
	getSoundInstance: (self: SoundPlayer, name: string) -> Sound?,
	refreshVolumes: (self: SoundPlayer) -> (),
	Destroy: (self: SoundPlayer) -> (),
}

type Playback = {
	sound: Sound,
	cloned: boolean,
	base: number,
	priority: number,
	connections: { RBXScriptConnection },
	lifeTimeThread: thread?,
	onFinished: { (Sound) -> () },
}

local SoundUtil = {}

local function categoryOf(sound: Sound): string
	local group = sound.SoundGroup or sound:FindFirstAncestorOfClass("SoundGroup")
	return if group then group.Name else ""
end

local function toConfig(nameOrConfig: string | SoundConfig): SoundConfig
	return if typeof(nameOrConfig) == "string" then { name = nameOrConfig } else nameOrConfig
end

--[=[
	Creates a sound player.

	When `sounds` is an Instance, its descendant Sounds are indexed by name, including
	ones added later. A Sound without a `SoundGroup` is assigned its nearest ancestor
	SoundGroup. Duplicate names warn and keep the first sound.

	@within SoundUtil
	@param options Options
	@return SoundPlayer
]=]
function SoundUtil.new(options: Options): SoundPlayer
	local volumeOf = options.volume
	local duckFactor = options.duckFactor or DEFAULT_DUCK_FACTOR
	local janitor = Janitor.new()
	local byName: { [string]: Sound } = {}
	local baseVolumes: { [Sound]: number } = setmetatable({}, { __mode = "k" }) :: any
	local playing: { [Sound]: Playback } = {}
	local fades: { [Sound]: RBXScriptConnection } = {}

	local function baseOf(sound: Sound): number
		local base = baseVolumes[sound]
		if base == nil then
			base = sound.Volume
			baseVolumes[sound] = base
		end
		return base
	end

	local function index(instance: Instance): ()
		if not instance:IsA("Sound") then
			return
		end
		baseOf(instance)
		if not instance.SoundGroup then
			instance.SoundGroup = instance:FindFirstAncestorOfClass("SoundGroup")
		end
		local existing = byName[instance.Name]
		if existing and existing ~= instance then
			warn(`[SoundUtil] Duplicate sound name '{instance.Name}': {instance:GetFullName()}`)
			return
		end
		byName[instance.Name] = instance
	end

	local lookup: (name: string) -> Sound?
	local source = options.sounds
	if typeof(source) == "Instance" then
		local root = source :: Instance
		for _, descendant in root:GetDescendants() do
			index(descendant)
		end
		janitor:Add(root.DescendantAdded:Connect(index))
		janitor:Add(root.DescendantRemoving:Connect(function(descendant: Instance)
			if descendant:IsA("Sound") and byName[descendant.Name] == descendant then
				byName[descendant.Name] = nil
			end
		end))
		lookup = function(name: string): Sound?
			return byName[name]
		end
	else
		lookup = source :: (name: string) -> Sound?
	end

	local function resolve(sound: string | Sound): Sound?
		return if typeof(sound) == "string" then lookup(sound) else sound
	end

	local function volumeFor(playback: Playback, maxPriority: number): number
		local category = if volumeOf then volumeOf(categoryOf(playback.sound)) else 1
		local duck = if playback.priority < maxPriority then duckFactor else 1
		return playback.base * category * duck
	end

	local function applyVolumes(): ()
		local maxPriority = -math.huge
		for _, playback in playing do
			maxPriority = math.max(maxPriority, playback.priority)
		end
		for sound, playback in playing do
			sound.Volume = volumeFor(playback, maxPriority)
		end
	end

	local function stopFade(sound: Sound): ()
		local connection = fades[sound]
		if connection then
			connection:Disconnect()
			fades[sound] = nil
		end
	end

	local function finish(playback: Playback, destroying: boolean?): ()
		local sound = playback.sound
		if playing[sound] ~= playback then
			return
		end
		playing[sound] = nil
		stopFade(sound)
		for _, connection in playback.connections do
			connection:Disconnect()
		end
		local lifeTimeThread = playback.lifeTimeThread
		if lifeTimeThread and lifeTimeThread ~= coroutine.running() then
			task.cancel(lifeTimeThread)
		end
		if not destroying then
			if playback.cloned then
				sound:Destroy()
			else
				sound.Volume = baseOf(sound)
			end
		end
		applyVolumes()
		for _, callback in playback.onFinished do
			task.spawn(callback, sound)
		end
	end

	local function start(config: SoundConfig): (Playback?, string?)
		local name = config.name
		if not name or name == "" then
			return nil, "Sound name is required"
		end
		local template = lookup(name)
		if not template then
			return nil, `Sound not found: {name}`
		end

		local properties = config.properties
		local base = if properties and type(properties.Volume) == "number" then properties.Volume else baseOf(template)
		local sound = template
		if config.instance then
			sound = template:Clone()
			sound.Parent = config.instance
		else
			local previous = playing[sound]
			if previous then
				finish(previous)
			end
			if sound.IsPlaying then
				sound:Stop()
			end
		end

		if properties then
			for property, value in properties do
				(sound :: any)[property] = value
			end
		end
		if config.looped ~= nil then
			sound.Looped = config.looped
		end

		local playback: Playback = {
			sound = sound,
			cloned = config.instance ~= nil,
			base = base,
			priority = config.priority or 0,
			connections = {},
			lifeTimeThread = nil,
			onFinished = {},
		}
		local function onEnded(): ()
			if not sound.IsPlaying then
				finish(playback)
			end
		end
		table.insert(playback.connections, sound.Ended:Connect(onEnded))
		table.insert(playback.connections, sound.Stopped:Connect(onEnded))
		table.insert(
			playback.connections,
			sound.Destroying:Connect(function()
				finish(playback, true)
			end)
		)
		if sound.Looped and config.lifeTime then
			playback.lifeTimeThread = task.delay(config.lifeTime, function()
				finish(playback)
				if not playback.cloned then
					sound:Stop()
				end
			end)
		end

		playing[sound] = playback
		applyVolumes()
		sound:Play()
		return playback, nil
	end

	local function playConfig(config: SoundConfig): Promise
		return Promise.new(function(resolvePromise, reject, onCancel)
			local playback, err = start(config)
			if not playback then
				reject(err)
				return
			end
			if playback.sound.Looped and not config.lifeTime then
				resolvePromise(playback.sound)
				return
			end
			table.insert(playback.onFinished, resolvePromise)
			onCancel(function()
				local sound = playback.sound
				finish(playback)
				if not playback.cloned then
					sound:Stop()
				end
			end)
		end)
	end

	local function fadeSound(sound: Sound, targetVolume: number, duration: number): Promise
		return Promise.new(function(resolvePromise, _, onCancel)
			stopFade(sound)
			local playback = playing[sound]
			local startVolume = if playback then playback.base else sound.Volume
			local startTime = os.clock()

			local function step(alpha: number): ()
				local volume = startVolume + (targetVolume - startVolume) * alpha
				if playback and playing[sound] == playback then
					playback.base = volume
					applyVolumes()
				else
					sound.Volume = volume
				end
			end

			if duration <= 0 then
				step(1)
				resolvePromise(sound)
				return
			end

			local connection: RBXScriptConnection
			connection = RunService.Heartbeat:Connect(function()
				local alpha = math.min((os.clock() - startTime) / duration, 1)
				step(alpha)
				if alpha >= 1 then
					connection:Disconnect()
					if fades[sound] == connection then
						fades[sound] = nil
					end
					resolvePromise(sound)
				end
			end)
			fades[sound] = connection
			onCancel(function()
				connection:Disconnect()
				if fades[sound] == connection then
					fades[sound] = nil
				end
			end)
		end)
	end

	local player = {} :: SoundPlayer

	--[=[
		Plays a sound by name or config.

		@within SoundUtil
		@method play
		@param nameOrConfig string | SoundConfig
		@return Promise<Sound> -- Resolves when the sound ends or stops, or at once for a looped sound without `lifeTime`. Rejects when the sound is not found. Cancelling it stops the sound.
	]=]
	function player.play(_: SoundPlayer, nameOrConfig: string | SoundConfig): Promise
		return playConfig(toConfig(nameOrConfig))
	end

	--[=[
		Plays a clone of a sound from an invisible, anchored part at `position`. The
		part is destroyed when the sound finishes. A looped sound stops after
		`lifeTime` seconds, 5 by default.

		@within SoundUtil
		@method playAt
		@param nameOrConfig string | SoundConfig -- `instance` is ignored.
		@param position Vector3
		@return Promise<Sound>
	]=]
	function player.playAt(_: SoundPlayer, nameOrConfig: string | SoundConfig, position: Vector3): Promise
		local config = toConfig(nameOrConfig)
		local part = Instance.new("Part")
		part.Name = "SoundEmitter"
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Transparency = 1
		part.Size = Vector3.one
		part.Position = position
		part.Parent = options.playAtParent or workspace

		return playConfig({
			name = config.name,
			properties = config.properties,
			instance = part,
			lifeTime = config.lifeTime or DEFAULT_PLAY_AT_LIFETIME,
			looped = config.looped,
			priority = config.priority,
		}):finally(function()
			part:Destroy()
		end)
	end

	--[=[
		Stops a sound, or pauses it when `preserve` is true. A name refers to the found
		sound itself, not to clones played with `instance`.

		@within SoundUtil
		@method stop
		@param sound (string | Sound)?
		@param preserve boolean? -- Pause instead of stopping.
		@return boolean -- Whether the sound was playing.
	]=]
	function player.stop(_: SoundPlayer, sound: (string | Sound)?, preserve: boolean?): boolean
		local target = if sound then resolve(sound) else nil
		if not target or not target.IsPlaying then
			return false
		end
		if preserve then
			target:Pause()
			return true
		end
		local playback = playing[target]
		if playback then
			finish(playback)
		end
		if target.Parent then
			target:Stop()
		end
		return true
	end

	--[=[
		Pauses a playing sound.

		@within SoundUtil
		@method pauseSound
		@param sound string | Sound
	]=]
	function player.pauseSound(_: SoundPlayer, sound: string | Sound): ()
		local target = resolve(sound)
		if target and target.IsPlaying then
			target:Pause()
		end
	end

	--[=[
		Resumes a paused sound from where it stopped.

		@within SoundUtil
		@method resumeSound
		@param sound string | Sound
	]=]
	function player.resumeSound(_: SoundPlayer, sound: string | Sound): ()
		local target = resolve(sound)
		if target and not target.IsPlaying then
			target:Resume()
		end
	end

	--[=[
		Fades a sound's volume to `targetVolume` over `duration` seconds. For a sound
		this player is playing, the base volume is faded, so category volume and
		ducking still apply. A new fade on the same sound replaces the old one.

		@within SoundUtil
		@method fade
		@param sound string | Sound
		@param targetVolume number
		@param duration number -- Seconds.
		@return Promise<Sound> -- Rejects when the sound is not found.
	]=]
	function player.fade(_: SoundPlayer, sound: string | Sound, targetVolume: number, duration: number): Promise
		local target = resolve(sound)
		if not target then
			return Promise.reject("Sound not found")
		end
		return fadeSound(target, targetVolume, duration)
	end

	--[=[
		Fades a playing sound out while a new one fades in from silence to its base
		volume, then stops the first.

		@within SoundUtil
		@method crossFade
		@param fadeOut string | Sound -- Must be playing.
		@param fadeIn string | SoundConfig
		@param duration number -- Seconds.
		@return Promise<Sound> -- Resolves with the faded-in sound.
	]=]
	function player.crossFade(
		self: SoundPlayer,
		fadeOut: string | Sound,
		fadeIn: string | SoundConfig,
		duration: number
	): Promise
		local outgoing = resolve(fadeOut)
		if not outgoing or not outgoing.IsPlaying then
			return Promise.reject("Fade out sound not found or not playing")
		end

		local config = table.clone(toConfig(fadeIn))
		local template = if config.name then lookup(config.name) else nil
		if not template then
			return Promise.reject(`Sound not found: {config.name}`)
		end
		local properties = table.clone(config.properties or {})
		local targetVolume = if type(properties.Volume) == "number" then properties.Volume else baseOf(template)
		properties.Volume = 0
		config.properties = properties

		local playback, err = start(config)
		if not playback then
			return Promise.reject(err)
		end
		local incoming = playback.sound

		return Promise.all({
			fadeSound(outgoing, 0, duration),
			fadeSound(incoming, targetVolume, duration),
		}):andThen(function()
			self:stop(outgoing)
			return incoming
		end)
	end

	--[=[
		Returns a sound by name, as the lookup finds it.

		@within SoundUtil
		@method getSoundInstance
		@param name string
		@return Sound?
	]=]
	function player.getSoundInstance(_: SoundPlayer, name: string): Sound?
		return lookup(name)
	end

	--[=[
		Re-applies the volume provider and ducking to every playing sound. Call it when
		a volume setting changes.

		@within SoundUtil
		@method refreshVolumes
	]=]
	function player.refreshVolumes(_: SoundPlayer): ()
		applyVolumes()
	end

	--[=[
		Stops every sound this player started and disconnects the sound index.

		@within SoundUtil
		@method Destroy
	]=]
	function player.Destroy(_: SoundPlayer): ()
		for sound, playback in playing do
			finish(playback)
			if not playback.cloned and sound.Parent then
				sound:Stop()
			end
		end
		for sound in fades do
			stopFade(sound)
		end
		janitor:Destroy()
	end

	return player
end

return table.freeze(SoundUtil)
