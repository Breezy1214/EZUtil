# EZUtil

[Documentation](https://breezy1214.github.io/EZUtil/)

EZUtil is a collection of small, game-agnostic Roblox utilities: tables, math, dates, instances, players, UI layout, projectiles, particles and VFX. It has no game config, Knit services or hardcoded game paths, so you can drop it into any project.

## Installation

Add the package to your [Wally](https://wally.run) manifest:

```toml
[dependencies]
EZUtil = "breezy1214/ezutil@0.1.0"
```

EZUtil depends on [Janitor](https://github.com/howmanysmall/Janitor) and [Promise](https://github.com/evaera/roblox-lua-promise); Wally installs both for you.

## Usage

```lua
local EZUtil = require(ReplicatedStorage.Packages.EZUtil)

print(EZUtil.MathUtil.shortenNumber(1200)) -- 1.2K
print(EZUtil.DateUtil.formatDuration(3725)) -- 1h 2m 5s

-- Or require a single module directly
local TableUtil = require(ReplicatedStorage.Packages.EZUtil.TableUtil)
```

Each module is required lazily, the first time its field is read, so a client-only module never runs on the server (and the reverse). The package root is fully typed, so `EZUtil.` autocompletes every module and its functions.

## Modules

### AimIndicator

A single neon disc that marks where an ability will land.

- `create(size, color?, parent?)`: replaces any existing indicator with a new disc, parented to `parent` (defaults to `workspace`).
- `update(position)`: moves the indicator onto a ground position.
- `destroy()`: removes the indicator.

### CharacterRigUtil

Helpers for character rigs, humanoids and skinned meshes.

- `waitForHumanoid(character, timeout)`: returns the character's Humanoid, waiting up to `timeout` seconds.
- `waitForAnimator(humanoid, timeout)`: returns the humanoid's Animator, waiting up to `timeout` seconds.
- `findBodyPart(character, name)`: finds a body part by name, resolving accessory handles to their MeshPart.
- `waitForBodyPart(character, name, timeout)`: polls `findBodyPart` until it succeeds, times out, or the character is removed.
- `getFeetY(rootPart, humanoid)`: the world Y of the character's feet.
- `standRootOn(character, rootPart, humanoid, groundCFrame)`: pivots the character so its feet rest on `groundCFrame`.
- `isGroundedState(state)`: whether a HumanoidStateType counts as grounded.
- `findSkinnedMesh(character)`: the MeshPart whose Bones pose a skinned character, or nil for a jointed rig.
- `collectCharacterBones(character)`: every Bone under the character, parents before children.

### DateUtil

Timestamps, periods and human-readable durations.

- `SECONDS_PER_DAY`, `SECONDS_PER_WEEK`: constants.
- `dateTimeComponentsToTimestamp(components)`: converts UTC date components to a unix timestamp in seconds.
- `unix()`: the current UTC unix timestamp in seconds.
- `getPeriod(timestamp, duration, offset?)`: the index of the fixed-length period containing `timestamp`.
- `getPeriodEnd(period, duration, offset?)`: the timestamp at which a period ends.
- `formatDuration(seconds)`: formats seconds as `1h 2m 5s`.
- `timeAgoUnix(timestamp, endTimestamp?)`: seconds elapsed since `timestamp`.
- `formatUnix(timestamp, format, locale?)`: formats a timestamp with a DateTime format string.
- `unixToClockFormat(timestamp, format?, locale?)`: formats a timestamp as `mm:ss` by default.
- `timeAgo(timestamp, endTimestamp?)`: a readable "time ago" string, such as `1 minute 20 seconds ago`.
- `totalTime(timestamp, endTimestamp?, separator?, depth?)`: a readable total duration with an optional unit limit.

### FixedRewardSequence

- `build(weights)`: builds a deterministic, evenly spread reward sequence whose frequencies match `weights`, starting at the rarest reward.

### GroundUtil

- `projectDown(position, depth, raycastParams, resultOffset?)`: raycasts straight down and returns the hit position plus an optional offset.
- `raycast(origin, direction, filterList?, filterType?, collisionGroup?)`: a one-call raycast that builds its RaycastParams for you.

### InstanceUtil

- `FindFirstAncestorWithTag(instance, tag)`: the nearest ancestor with a CollectionService tag.
- `GetDescendantsWithTag(instance, tag)`: every descendant with a tag.
- `ExpectChild(parent, name)`: returns a child, or errors with its full path if it is missing.
- `findFirstChildWithTag(instance, tagName)`: the first direct child with a tag.
- `weldParts(part0, part1)`: welds two parts with a WeldConstraint.
- `weldAttachments(attach1, attach2)`: joins two attachments with a RigidConstraint.
- `lookAt(object, target, rotateOnYAxis?)`: tweens a part to face a target and returns a Promise that resolves when the tween ends.

### JanitorUtil

- `safeDestroy(janitor?)`: destroys a Janitor unless it is nil or already cleaning, and warns instead of throwing on failure.

### LayoutUtil

Keeps ScrollingFrame canvases and items sized correctly.

- `resolveUDim(size, referenceSize)`: converts a UDim to pixels against a reference size.
- `FixScrollingCanvas(layout, scrollingFrame, padding?)`: keeps CanvasSize fitted to the layout's content and padding. Returns a cleanup function.
- `FixAuthoredListHeights(scrollingFrame, layout, items)`: locks list items and padding to their authored heights relative to the viewport. Returns a cleanup function.
- `FixLayout(layout, scrollingFrame, itemAspectRatio?, padding?)`: applies aspect-ratio constraints to items and keeps the vertical canvas fitted. Returns a cleanup function.

### MathUtil

- `lerp(start, stop, alpha)`: linear interpolation.
- `round(number)`: rounds to the nearest integer.
- `roundNumber(num, numPlaces)`: rounds to the nearest value with a number of decimal places.
- `formatInt(number, decimals?)`: adds thousands separators, such as `1,000.01`.
- `shortenNumber(number, minimumTiers?)`: abbreviates large numbers, such as `1.2K` or `3M`.
- `random(min, max?, float?)`: a random integer or float. `min` defaults to 1 when only one number is given.
- `randomRange(min, max)`: a random float in a range.
- `randomString(length?)`: a random alphanumeric string, 18 characters by default.
- `randomObj(tableOrInstance)`: a random array element or child.
- `randomInDisc(radius)`: a uniformly random flat offset inside a disc.
- `getRandomInPart(part)`: a random CFrame on a part's XZ plane.
- `getVector3(object)`: extracts a position from a Vector3, CFrame, Attachment, BasePart, value object or Camera.
- `getDistance(origin, target)`: the distance between any two values `getVector3` supports.
- `getPartBottomSurface(part)`: the CFrame at the centre of a part's bottom face.
- `isNumberSecure(value)`: true only for non-negative numbers.

### ParticleUtil

- `waitForTemplate(name, folder)`, `waitForPart(name, folder)`, `waitForModel(name, folder)`: wait up to 5 seconds for a typed asset in `folder`, and warn if it is missing or the wrong class.
- `burst(template, cframe)`: clones an attachment, emits each emitter's `EmitCount` attribute after its optional `EmitDelay`, then cleans up.
- `setEnabled(root, enabled)`: toggles every ParticleEmitter under `root`.
- `release(root)`: stops emitters and lights, then destroys `root` after its particles finish.

### PlayerUtil

- `ensureAnimator(character)`: returns the character's Animator, creating one if needed.
- `loadAnimation(janitor, character, animationId)`: loads an Action4 track that the Janitor stops and destroys.
- `getHumanoid(object)`: the Humanoid of a Player, character Model or Humanoid.
- `isAlive(object)`, `hasHumanoid(object)`: humanoid health and presence checks.
- `getCharacterHeight(character)`: the character's bounding-box height.
- `getPositiontAtFeet(character)`: the world position at the character's feet.
- `getCharacterInformation(player)`: returns the character, Humanoid and HumanoidRootPart.
- `getPlayerFromInstance(part)` (alias `getPlayerFromPart`): the Player whose character contains a part.
- `getGroupRank(player, groupId)`: a cached group rank lookup.
- `isCreator(player)`, `getUserLevel(player)`, `userLevel`: checks for the game creator, group staff and Premium.
- `disableOtherUi(value, exception?)`: client only. Hides or restores every ScreenGui except `exception` and Topbar GUIs.

### ProfileUtil

- `scope(label, callback)`: runs a non-yielding callback inside a named MicroProfiler scope and returns its results.

### ProjectileUtil

Ballistic projectiles and aim previews.

- `calculateLaunchVelocity(origin, target, duration, gravity?)`: the launch velocity needed to hit `target` in `duration` seconds.
- `getPositionAtTime(origin, velocity, time, gravity?)`, `getVelocityAtTime(velocity, time, gravity?)`: the arc's position and velocity at a time.
- `launch(config)`: animates an anchored part along the arc, with optional raycast hits and bounces. Returns a controller with `Cancel` and `IsActive`.
- `createAimBeam(config)`: draws the arc with a single curved Beam. Returns an object with `Update` and `Destroy`.

### SearchUtil

- `getPartCount(instance)`, `getDescendantParts(instance)`: count or collect descendant BaseParts.
- `getFirstPart(instance)`: the first BasePart child.
- `getAncestor(child, nameOrPredicate)`: the first ancestor, or the instance itself, that matches.
- `find(node, keyOrPredicate, maxDepth?)`: a breadth-limited search through Instance children or nested tables.
- `exists(node, names)`: whether every named child or key exists.

### SystemUtil

- `timeout(delay, callback)`: runs `callback` after `delay` seconds.
- `interval(interval, callback)`: runs `callback(elapsed, dt)` every `interval` seconds until it returns `false`. Returns the connection.
- `inTable(table, value)`: whether a value is in a table.
- `disconnect(connectionOrList)`: disconnects one connection or a list of them.
- `getProductInfo(productId, infoType?)`: a cached, pcall-wrapped `MarketplaceService:GetProductInfo`.
- `isMobile()`, `isConsole()`: input-based platform checks.

### TableDiffUtil

- `shallowEqual(left, right)`: whether two tables have the same keys and values.

### TableUtil

- `flip`, `map`, `filter`, `mapIndex`: transform tables, or an Instance's children.
- `extend`, `assign`: merge tables, with an optional deep merge.
- `split`, `join`, `trimWhitespace`, `trimLeadingWhitespace`, `trimTrailingWhitespace`: string helpers.
- `treePath(tree, path, delimiter?)`: reads a dotted path through a table or Instance tree.
- `insertIf(target, value, condition)`: appends a value only if the condition passes.
- `instanceChildrenToTable(instance)`: maps child names to children.
- `makeConfigFromValues(folder)`: converts a Folder or Configuration of value objects into a nested table.
- `tableLength`, `indexOf`, `tableRandom`, `tableRandomIndex`, `tableRemove`: counting, lookup, random picks and in-place removal.

### VfxUtil

Plays VFX templates whose emitters are configured with `EmitCount`, `EmitDelay` and `EmitDuration` attributes.

- `uprightAt(template, position)`: a CFrame at `position` that keeps the template's rotation.
- `play(template, cframe, parent?)`: plays a one-shot clone, parented to `parent` (defaults to `workspace`), and cleans it up when finished.
- `attach(template, part)`: welds a continuously emitting clone to `part` and returns a stop function.

## License

MIT
