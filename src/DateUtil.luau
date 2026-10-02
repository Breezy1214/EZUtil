--!strict
--[=[
	@class DateUtil

	Helpers for unix timestamps, fixed-length periods (such as daily or weekly
	resets) and human-readable durations. All timestamps are in seconds.
]=]

local DateUtil = {}

--[=[
	UTC date and time components, as accepted by `DateTime.fromUniversalTime`.

	@interface DateTimeComponents
	@within DateUtil
	.Year number
	.Month number
	.Day number
	.Hour number
	.Minute number
	.Second number
	.Millisecond number
]=]
export type DateTimeComponents = {
	Year: number,
	Month: number,
	Day: number,
	Hour: number,
	Minute: number,
	Second: number,
	Millisecond: number,
}

local secondsInMinute: number = 60
local secondsInHour: number = secondsInMinute * 60
local secondsInDay: number = secondsInHour * 24
local secondsInMonth: number = 2629746
local secondsInYear: number = 31556952

--[=[
	The number of seconds in a day (86400).

	@prop SECONDS_PER_DAY number
	@within DateUtil
]=]
DateUtil.SECONDS_PER_DAY = secondsInDay
--[=[
	The number of seconds in a week (604800).

	@prop SECONDS_PER_WEEK number
	@within DateUtil
]=]
DateUtil.SECONDS_PER_WEEK = 7 * secondsInDay

local timeNames: { { any } } = {
	{ secondsInYear, "year" },
	{ secondsInMonth, "month" },
	{ secondsInDay, "day" },
	{ secondsInHour, "hour" },
	{ secondsInMinute, "minute" },
	{ 1, "second" },
}

--[=[
	Converts UTC date and time components to a unix timestamp in seconds. The
	milliseconds are kept as a fraction.

	```lua
	DateUtil.dateTimeComponentsToTimestamp({
		Year = 2024, Month = 1, Day = 1,
		Hour = 0, Minute = 0, Second = 0, Millisecond = 0,
	}) -- 1704067200
	```

	@within DateUtil
	@param components DateTimeComponents
	@return number
]=]
function DateUtil.dateTimeComponentsToTimestamp(components: DateTimeComponents): number
	assert(typeof(components) == "table", "Components must be a table")
	assert(typeof(components.Year) == "number", "Components.Year must be a number")
	assert(typeof(components.Month) == "number", "Components.Month must be a number")
	assert(typeof(components.Day) == "number", "Components.Day must be a number")
	assert(typeof(components.Hour) == "number", "Components.Hour must be a number")
	assert(typeof(components.Minute) == "number", "Components.Minute must be a number")
	assert(typeof(components.Second) == "number", "Components.Second must be a number")
	assert(typeof(components.Millisecond) == "number", "Components.Millisecond must be a number")

	return DateTime.fromUniversalTime(
		components.Year,
		components.Month,
		components.Day,
		components.Hour,
		components.Minute,
		components.Second,
		components.Millisecond
	).UnixTimestampMillis / 1000
end

--[=[
	Get the current unix timestamp in UTC time.
	This is the number of **seconds** since January 1, 1970.

	@within DateUtil
	@return number
]=]
function DateUtil.unix(): number
	return DateTime.now().UnixTimestamp
end

--[=[
	Returns the index of the fixed-length period that contains `timestamp`, counting
	from the unix epoch shifted by `offset`. Useful for daily or weekly resets: two
	timestamps are in the same period when this returns the same number.

	```lua
	local today = DateUtil.getPeriod(DateUtil.unix(), DateUtil.SECONDS_PER_DAY)

	-- Days that reset at 12:00 UTC instead of midnight
	local shiftedDay = DateUtil.getPeriod(DateUtil.unix(), DateUtil.SECONDS_PER_DAY, 12 * 3600)
	```

	@within DateUtil
	@param timestamp number
	@param duration number -- The period length in seconds. Must be greater than zero.
	@param offset number? -- Shifts where periods start, in seconds. Defaults to 0.
	@return number
]=]
function DateUtil.getPeriod(timestamp: number, duration: number, offset: number?): number
	assert(duration > 0, "Duration must be greater than zero")
	return math.floor((timestamp - (offset or 0)) / duration)
end

--[=[
	Returns the timestamp at which `period` ends (and the next one starts). Use the
	same `duration` and `offset` that were passed to [DateUtil.getPeriod].

	```lua
	local today = DateUtil.getPeriod(DateUtil.unix(), DateUtil.SECONDS_PER_DAY)
	local secondsUntilReset = DateUtil.getPeriodEnd(today, DateUtil.SECONDS_PER_DAY) - DateUtil.unix()
	```

	@within DateUtil
	@param period number -- A period index from [DateUtil.getPeriod].
	@param duration number -- The period length in seconds. Must be greater than zero.
	@param offset number? -- Defaults to 0.
	@return number
]=]
function DateUtil.getPeriodEnd(period: number, duration: number, offset: number?): number
	assert(duration > 0, "Duration must be greater than zero")
	return (offset or 0) + (period + 1) * duration
end

--[=[
	Formats a duration as hours, minutes and seconds. Negative durations are treated
	as 0 and fractions of a second are dropped.

	```lua
	DateUtil.formatDuration(3725) -- "1h 2m 5s"
	DateUtil.formatDuration(59) -- "0h 0m 59s"
	```

	@within DateUtil
	@param seconds number
	@return string
]=]
function DateUtil.formatDuration(seconds: number): string
	assert(typeof(seconds) == "number", "Seconds must be a number")

	local remaining = math.max(0, math.floor(seconds))
	local hours = math.floor(remaining / secondsInHour)
	local minutes = math.floor((remaining % secondsInHour) / secondsInMinute)
	local secondsPart = remaining % secondsInMinute

	return `{hours}h {minutes}m {secondsPart}s`
end

--[=[
	Returns the number of seconds between `timestamp` and `endTimestamp`.

	@within DateUtil
	@param timestamp number
	@param endTimestamp number? -- The timestamp to compare to. Defaults to the current time.
	@return number
]=]
function DateUtil.timeAgoUnix(timestamp: number, endTimestamp: number?): number
	assert(typeof(timestamp) == "number", "Timestamp must be a number")
	assert(typeof(endTimestamp) == "number" or endTimestamp == nil, "toTimestamp must be a number or nil")

	return (endTimestamp or DateUtil.unix()) - timestamp
end

--[=[
	Formats a unix timestamp in local time with a
	[DateTime](https://create.roblox.com/docs/reference/engine/datatypes/DateTime)
	format string.

	#### Example
	```lua
	local secondsLeft: number = 80

	DateUtil.formatUnix(secondsLeft, "mm:ss") -- 01:20
	DateUtil.formatUnix(DateUtil.unix(), "YYYY-MM-DD") -- today's date
	```

	@within DateUtil
	@param timestamp number -- Rounded down to a whole second.
	@param format string -- The DateTime format string to use.
	@param locale string? -- The locale to use. Defaults to `en-us`.
	@return string -- The formatted time in local time.
]=]
function DateUtil.formatUnix(timestamp: number, format: string, locale: string?): string
	assert(typeof(timestamp) == "number", "Timestamp must be a number")
	assert(typeof(format) == "string", "format must be a string")
	assert(typeof(locale) == "string" or locale == nil, "locale must be a string or nil")

	local dateTime = DateTime.fromUnixTimestamp(math.floor(timestamp))

	return dateTime:FormatLocalTime(format, locale or "en-us")
end

--[=[
	Formats a timestamp or a number of seconds as a clock, `mm:ss` by default
	(e.g. 01:20). See [DateUtil.formatUnix].

	#### Example
	```lua
	local secondsLeft: number = 80

	DateUtil.unixToClockFormat(secondsLeft) -- 01:20
	```

	@within DateUtil
	@param timestamp number
	@param format string? -- The format to use. Defaults to `mm:ss`.
	@param locale string? -- The locale to use. Defaults to `en-us`.
	@return string -- The formatted time in local time.
]=]
function DateUtil.unixToClockFormat(timestamp: number, format: string?, locale: string?): string
	return DateUtil.formatUnix(timestamp, format or "mm:ss", locale)
end

--[=[
	Describes how long ago `timestamp` was, listing every non-zero unit from years
	down to seconds. Returns `"now"` for less than a second.

	Months and years are averages (30.44 and 365.24 days).

	#### Example
	```lua
	DateUtil.timeAgo(DateUtil.unix() - 80) -- "1 minute 20 seconds ago"
	DateUtil.timeAgo(100, 160) -- "1 minute ago"
	DateUtil.timeAgo(100, 100) -- "now"
	```

	@within DateUtil
	@param timestamp number
	@param endTimestamp number? -- The timestamp to compare to. Defaults to the current time.
	@return string
]=]
function DateUtil.timeAgo(timestamp: number, endTimestamp: number?): string
	assert(typeof(timestamp) == "number", "Timestamp must be a number")
	assert(typeof(endTimestamp) == "number" or endTimestamp == nil, "endTimestamp must be a number or nil")

	local timeAgo: number = DateUtil.timeAgoUnix(timestamp, endTimestamp)
	local result: string = ""

	if timeAgo < 1 then
		return "now"
	end

	local current: number = 1
	local previousUnitSeconds: number = 0

	while current <= #timeNames do
		local _time: {} = timeNames[current]
		local unitThreshold: number = timeNames[current][1]
		local unit: string = timeNames[current][2]

		if (timeAgo >= unitThreshold) and current <= #timeNames then
			local amount: number = math.floor((timeAgo - previousUnitSeconds) / unitThreshold)

			previousUnitSeconds += amount * unitThreshold

			if amount > 0 then
				local plural: string = amount > 1 and "s" or ""

				result = `{result}{amount} {unit}{plural} `
			end
		end

		current += 1
	end

	return `{result}ago`
end

--[=[
	Like [DateUtil.timeAgo], but without the "ago" suffix, with a custom separator
	and an optional limit on how many units are listed. Returns `"now"` for less than
	a second.

	#### Example
	```lua
	DateUtil.totalTime(0, 3725) -- "1 hour 2 minutes 5 seconds"
	DateUtil.totalTime(0, 3725, ", ") -- "1 hour, 2 minutes, 5 seconds"
	DateUtil.totalTime(0, 3725, " ", 2) -- "1 hour 2 minutes"
	```

	@within DateUtil
	@param timestamp number
	@param endTimestamp number? -- The timestamp to compare to. Defaults to the current time.
	@param separator string? -- The separator to use between each unit. Defaults to a space.
	@param depth number? -- The maximum number of units to return.
	@return string
]=]
function DateUtil.totalTime(timestamp: number, endTimestamp: number?, separator: string?, depth: number?): string
	assert(typeof(timestamp) == "number", "Timestamp must be a number")
	assert(typeof(endTimestamp) == "number" or endTimestamp == nil, "endTimestamp must be a number or nil")
	assert(typeof(separator) == "string" or separator == nil, "separator must be a string or nil")
	assert(typeof(depth) == "number" or depth == nil, "depth must be a number or nil")

	local _separator: string = separator or " "

	local timeAgo: number = DateUtil.timeAgoUnix(timestamp, endTimestamp)
	local result: string = ""

	if timeAgo < 1 then
		return "now"
	end

	local current: number = 1
	local previousUnitSeconds: number = 0
	local iteration: number = 0

	while current <= #timeNames and (depth == nil or iteration < depth) do
		local _time: {} = timeNames[current]
		local unitThreshold: number = timeNames[current][1]
		local unit: string = timeNames[current][2]

		if (timeAgo >= unitThreshold) and current <= #timeNames then
			local amount: number = math.floor((timeAgo - previousUnitSeconds) / unitThreshold)

			previousUnitSeconds += amount * unitThreshold

			if amount > 0 then
				local plural: string = amount > 1 and "s" or ""

				result = `{result}{amount} {unit}{plural}{_separator}`
				iteration += 1
			end
		end

		current += 1
	end

	-- Trim last separator and return
	return string.sub(result, 1, string.len(result) - string.len(_separator))
end

return DateUtil
