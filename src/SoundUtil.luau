--!strict
--[=[
	@class SoundUtil

	Plays sounds with priorities, fades and cross-fades. A sound player plays any
	Sound it is given, and can also find sounds by name through an optional root
	folder or lookup function. It never changes a Sound it did not create: a sound
	played in place gets every overridden property back when it finishes.

	While sounds play, every sound below the highest playing priority is ducked to
	`duckFactor` of its volume. A sound's volume is its base volume (its own `Volume`
	before playing, or `properties.Volume`) times the optional volume provider's
	multiplier times any ducking.

	```lua
	local sounds = SoundUtil.new({
		sounds = SoundService,
		volume = function(sound: Sound): number
			return if sound.SoundGroup == musicGroup and not settings.Music then 0 else 1
		end,
	})

	sounds:play("ButtonClick")
	sounds:play(script.Hit)
	sounds:play({ name = "BossMusic", looped = true, priority = 1 })
	sounds:playAt("Explosion", position)
	sounds:crossFade("BossMusic", "MainMusic", 2)

	-- When a setting changes
	sounds:refreshVolumes()
	```
]=]

local RunService = game:GetService("RunService")

local Janitor = require(script.Parent.Parent.Janitor)
local MathUtil = require(script.Parent.MathUtil)
local Promise = require(script.Parent.Parent.Promise)

type Promise = typeof(Promise.new())

local DEFAULT_DUCK_FACTOR = 0.1
local DEFAULT_PLAY_AT_LIFETIME = 5
local DESTROYED = "SoundPlayer is destroyed"

--[=[
	A sound to play: `sound`, or a `name` for the lookup.

	@interface SoundConfig
	@within SoundUtil
	.name string? -- The sound's name, passed to the lookup.
	.sound Sound? -- The Sound to play. Takes precedence over `name`.
	.properties { [string]: any }? -- Sound properties to set before playing. `Volume` sets the base volume.
	.instance Instance? -- Plays a clone parented here, destroyed when it finishes. Otherwise the sound itself plays.
	.lifeTime number? -- Stops a looped sound after this many seconds.
	.looped boolean? -- Overrides the sound's `Looped`.
	.priority number? -- Defaults to 0. Lower priorities are ducked while a higher one plays.
]=]
export type SoundConfig = {
	name: string?,
	sound: Sound?,
	properties: { [string]: any }?,
	instance: Instance?,
	lifeTime: number?,
	looped: boolean?,
	priority: number?,
}

--[=[
	Options for [SoundUtil.new]. Every option is optional.

	@interface Options
	@within SoundUtil
	.sounds (Instance | (name: string) -> Sound?)? -- A root whose descendant Sounds are found by name, or a lookup function. Without it, sounds can only be played as Sounds.
	.volume ((sound: Sound) -> number)? -- The volume multiplier for a playing sound. Defaults to 1.
	.duckFactor number? -- The volume multiplier for sounds below the highest playing priority. Defaults to 0.1; 1 turns ducking off.
	.playAtParent BasePart? -- Where `playAt` creates its emitter attachment. Defaults to `workspace.Terrain`.
]=]
export type Options = {
	sounds: (Instance | (name: string) -> Sound?)?,
	volume: ((sound: Sound) -> number)?,
	duckFactor: number?,
	playAtParent: BasePart?,
}

export type Playable = string | Sound | SoundConfig

export type SoundPlayer = {
	play: (self: SoundPlayer, sound: Playable) -> Promise,
	playAt: (self: SoundPlayer, sound: Playable, position: Vector3) -> Promise,
	stop: (self: SoundPlayer, sound: (string | Sound)?, preserve: boolean?) -> boolean,
	pauseSound: (self: SoundPlayer, sound: string | Sound) -> (),
	resumeSound: (self: SoundPlayer, sound: string | Sound) -> (),
	fade: (self: SoundPlayer, sound: string | Sound, targetVolume: number, duration: number) -> Promise,
	crossFade: (self: SoundPlayer, fadeOut: string | Sound, fadeIn: Playable, duration: number) -> Promise,
	getSoundInstance: (self: SoundPlayer, name: string) -> Sound?,
	refreshVolumes: (self: SoundPlayer) -> (),
	Destroy: (self: SoundPlayer) -> (),
}

type Playback = {
	sound: Sound,
	cloned: boolean,
	base: number,
	resting: number,
	priority: number,
	restore: { { property: string, value: any } }?,
	connections: { RBXScriptConnection },
	lifeTimeThread: thread?,
	onFinished: { (Sound) -> () },
}

type Fade = {
	sound: Sound,
	from: number,
	to: number,
	duration: number,
	startTime: number,
	done: (Sound) -> (),
}

local SoundUtil = {}

local function toConfig(sound: Playable): SoundConfig
	if typeof(sound) == "string" then
		return { name = sound }
	elseif typeof(sound) == "Instance" then
		return { sound = sound :: Sound }
	end
	return sound :: SoundConfig
end

--[=[
	Creates a sound player.

	When `sounds` is an Instance, its descendant Sounds are indexed by name, including
	ones added later. Duplicate names warn and keep the first sound.

	@within SoundUtil
	@param options Options?
	@return SoundPlayer
]=]
function SoundUtil.new(options: Options?): SoundPlayer
	local settings: Options = options or {}
	local volumeProvider = settings.volume
	local duckFactor = settings.duckFactor or DEFAULT_DUCK_FACTOR
	local janitor = Janitor.new()
	local playing: { [Sound]: Playback } = {}
	local priorityCounts: { [number]: number } = {}
	local maxPriority = -math.huge
	local fades: { [Sound]: Fade } = {}
	local fadeConnection: RBXScriptConnection? = nil
	local destroyed = false

	local lookup: (name: string) -> Sound?
	local source = settings.sounds
	if typeof(source) == "Instance" then
		local byName: { [string]: Sound } = {}
		local function index(instance: Instance): ()
			if not instance:IsA("Sound") then
				return
			end
			local existing = byName[instance.Name]
			if existing and existing ~= instance then
				warn(`[SoundUtil] Duplicate sound name '{instance.Name}': {instance:GetFullName()}`)
				return
			end
			byName[instance.Name] = instance
		end

		for _, descendant in source:GetDescendants() do
			index(descendant)
		end
		janitor:Add(source.DescendantAdded:Connect(index))
		janitor:Add(source.DescendantRemoving:Connect(function(descendant: Instance)
			if descendant:IsA("Sound") and byName[descendant.Name] == descendant then
				byName[descendant.Name] = nil
			end
		end))
		lookup = function(name: string): Sound?
			return byName[name]
		end
	elseif source then
		lookup = source :: (name: string) -> Sound?
	else
		lookup = function(): Sound?
			return nil
		end
	end

	local function resolve(sound: string | Sound): Sound?
		return if typeof(sound) == "string" then lookup(sound) else sound
	end

	local function templateOf(config: SoundConfig): (Sound?, string?)
		if config.sound then
			return config.sound, nil
		end
		local name = config.name
		if not name or name == "" then
			return nil, "Sound or name is required"
		end
		local found = lookup(name)
		if not found then
			return nil, `Sound not found: {name}`
		end
		return found, nil
	end

	local function restingVolume(sound: Sound): number
		local playback = playing[sound]
		return if playback then playback.resting else sound.Volume
	end

	local function applyVolume(playback: Playback): ()
		local multiplier = if volumeProvider then volumeProvider(playback.sound) else 1
		local duck = if playback.priority < maxPriority then duckFactor else 1
		playback.sound.Volume = playback.base * multiplier * duck
	end

	local function applyVolumes(): ()
		for _, playback in playing do
			applyVolume(playback)
		end
	end

	local function countPriority(priority: number, delta: number): boolean
		local count = (priorityCounts[priority] or 0) + delta
		priorityCounts[priority] = if count > 0 then count else nil
		local highest = -math.huge
		for counted in priorityCounts do
			highest = math.max(highest, counted)
		end
		if highest == maxPriority then
			return false
		end
		maxPriority = highest
		return true
	end

	local function stopFade(sound: Sound): ()
		fades[sound] = nil
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
			local restore = playback.restore
			if restore then
				local target: any = sound
				for i = #restore, 1, -1 do
					target[restore[i].property] = restore[i].value
				end
				sound.Volume = playback.resting
			else
				pcall(sound.Destroy, sound)
			end
		end
		if countPriority(playback.priority, -1) then
			applyVolumes()
		end
		for _, callback in playback.onFinished do
			task.spawn(callback, sound)
		end
	end

	local function start(config: SoundConfig): (Playback?, string?)
		local template, err = templateOf(config)
		if not template then
			return nil, err
		end

		local cloned = config.instance ~= nil
		local resting = restingVolume(template)
		local sound = template
		if cloned then
			sound = template:Clone()
		else
			local previous = playing[sound]
			if previous then
				finish(previous)
			end
			if sound.IsPlaying then
				sound:Stop()
			end
		end

		local properties = config.properties
		local playback: Playback = {
			sound = sound,
			cloned = cloned,
			base = if properties and type(properties.Volume) == "number" then properties.Volume else resting,
			resting = resting,
			priority = config.priority or 0,
			restore = if cloned then nil else {},
			connections = {},
			lifeTimeThread = nil,
			onFinished = {},
		}

		local target: any = sound
		local restore = playback.restore
		local function override(property: string, value: any): ()
			if restore then
				table.insert(restore, { property = property, value = target[property] })
			end
			target[property] = value
		end
		if properties then
			for property, value in properties do
				if property ~= "Volume" then
					override(property, value)
				end
			end
		end
		if config.looped ~= nil then
			override("Looped", config.looped)
		end
		if cloned then
			sound.Parent = config.instance
		end

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
				if not cloned then
					sound:Stop()
				end
			end)
		end

		playing[sound] = playback
		if countPriority(playback.priority, 1) then
			applyVolumes()
		else
			applyVolume(playback)
		end
		sound:Play()
		return playback, nil
	end

	local function playConfig(config: SoundConfig): Promise
		if destroyed then
			return Promise.reject(DESTROYED)
		end
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
				finish(playback)
				if not playback.cloned then
					playback.sound:Stop()
				end
			end)
		end)
	end

	local function setFadeVolume(fade: Fade, alpha: number): ()
		local volume = MathUtil.lerp(fade.from, fade.to, alpha)
		local playback = playing[fade.sound]
		if playback then
			playback.base = volume
			applyVolume(playback)
		else
			fade.sound.Volume = volume
		end
	end

	local function stepFades(): ()
		local now = os.clock()
		local completed: { Fade }? = nil
		for _, fade in fades do
			local alpha = math.min((now - fade.startTime) / fade.duration, 1)
			setFadeVolume(fade, alpha)
			if alpha >= 1 then
				completed = completed or {}
				table.insert(completed :: { Fade }, fade)
			end
		end
		if completed then
			for _, fade in completed do
				if fades[fade.sound] == fade then
					fades[fade.sound] = nil
				end
				fade.done(fade.sound)
			end
		end
		if next(fades) == nil and fadeConnection then
			fadeConnection:Disconnect()
			fadeConnection = nil
		end
	end

	local function fadeSound(sound: Sound, targetVolume: number, duration: number): Promise
		if destroyed then
			return Promise.reject(DESTROYED)
		end
		return Promise.new(function(resolvePromise, _, onCancel)
			local playback = playing[sound]
			local fade: Fade = {
				sound = sound,
				from = if playback then playback.base else sound.Volume,
				to = targetVolume,
				duration = duration,
				startTime = os.clock(),
				done = resolvePromise,
			}
			if duration <= 0 then
				stopFade(sound)
				setFadeVolume(fade, 1)
				resolvePromise(sound)
				return
			end
			fades[sound] = fade
			if not fadeConnection then
				fadeConnection = RunService.Heartbeat:Connect(stepFades)
			end
			onCancel(function()
				if fades[sound] == fade then
					fades[sound] = nil
				end
			end)
		end)
	end

	local player = {} :: SoundPlayer

	--[=[
		Plays a Sound, a sound by name, or a config.

		@within SoundUtil
		@method play
		@param sound string | Sound | SoundConfig
		@return Promise<Sound> -- Resolves when the sound ends or stops, or at once for a looped sound without `lifeTime`. Rejects when the sound is not found. Cancelling it stops the sound.
	]=]
	function player.play(_: SoundPlayer, sound: Playable): Promise
		return playConfig(toConfig(sound))
	end

	--[=[
		Plays a clone of a sound from an attachment at `position`. The attachment is
		destroyed when the sound finishes. A looped sound stops after `lifeTime`
		seconds, 5 by default.

		@within SoundUtil
		@method playAt
		@param sound string | Sound | SoundConfig -- `instance` is ignored.
		@param position Vector3
		@return Promise<Sound>
	]=]
	function player.playAt(_: SoundPlayer, sound: Playable, position: Vector3): Promise
		if destroyed then
			return Promise.reject(DESTROYED)
		end
		local emitter = Instance.new("Attachment")
		emitter.Name = "SoundEmitter"
		emitter.Parent = settings.playAtParent or workspace.Terrain
		emitter.WorldPosition = position

		local config = table.clone(toConfig(sound))
		config.instance = emitter
		config.lifeTime = config.lifeTime or DEFAULT_PLAY_AT_LIFETIME
		return playConfig(config):finally(function()
			emitter:Destroy()
		end)
	end

	--[=[
		Stops a sound, or pauses it when `preserve` is true. A name refers to the found
		sound itself, not to clones played with `instance`.

		@within SoundUtil
		@method stop
		@param sound (string | Sound)?
		@param preserve boolean? -- Pause instead of stopping.
		@return boolean -- Whether the sound was playing or paused.
	]=]
	function player.stop(_: SoundPlayer, sound: (string | Sound)?, preserve: boolean?): boolean
		local target = if sound then resolve(sound) else nil
		if not target then
			return false
		end
		local playback = playing[target]
		if not playback and not target.IsPlaying then
			return false
		end
		if preserve then
			target:Pause()
			return true
		end
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
		this player is playing, the base volume is faded, so the volume provider and
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
		@param fadeIn string | Sound | SoundConfig
		@param duration number -- Seconds.
		@return Promise<Sound> -- Resolves with the faded-in sound.
	]=]
	function player.crossFade(self: SoundPlayer, fadeOut: string | Sound, fadeIn: Playable, duration: number): Promise
		if destroyed then
			return Promise.reject(DESTROYED)
		end
		local outgoing = resolve(fadeOut)
		if not outgoing or not outgoing.IsPlaying then
			return Promise.reject("Fade out sound not found or not playing")
		end

		local config = table.clone(toConfig(fadeIn))
		local template, templateErr = templateOf(config)
		if not template then
			return Promise.reject(templateErr)
		end
		local properties = table.clone(config.properties or {})
		local targetVolume = if type(properties.Volume) == "number" then properties.Volume else restingVolume(template)
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
		Stops every sound this player started and disconnects the sound index. Calls
		that play or fade afterwards reject.

		@within SoundUtil
		@method Destroy
	]=]
	function player.Destroy(_: SoundPlayer): ()
		if destroyed then
			return
		end
		destroyed = true
		for sound, playback in playing do
			finish(playback)
			if not playback.cloned and sound.Parent then
				sound:Stop()
			end
		end
		table.clear(fades)
		if fadeConnection then
			fadeConnection:Disconnect()
			fadeConnection = nil
		end
		janitor:Destroy()
	end

	return player
end

return table.freeze(SoundUtil)
