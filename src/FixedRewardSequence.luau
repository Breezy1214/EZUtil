--!strict
--[=[
	@class FixedRewardSequence

	Builds deterministic reward sequences. Instead of rolling a random reward each
	time, step through a pre-built cycle whose reward frequencies match the weights
	exactly and whose rewards are spread out as evenly as possible.

	```lua
	local sequence = FixedRewardSequence.build({ 70, 25, 5 })

	local step = 0
	local function nextReward(): number
		step = step % #sequence + 1
		return sequence[step] -- 1, 2 or 3
	end
	```
]=]

local FixedRewardSequence = {}

--[=[
	Builds a frozen cycle of reward indices whose counts are proportional to
	`weights`. The cycle has at least 100 entries (more when the rarest weight is
	under 1% of the total), its counts are allocated by largest remainder, its
	entries are interleaved as evenly as possible, and it starts at the first
	occurrence of the rarest reward. A single weight returns `{ 1 }`.

	@within FixedRewardSequence
	@param weights { number } -- Positive weights, one per reward. Errors if empty or if any weight is not positive.
	@return { number } -- A frozen array of indices into `weights`.
]=]
function FixedRewardSequence.build(weights: { number }): { number }
	assert(#weights > 0, "A fixed reward sequence needs rewards")
	if #weights == 1 then
		return table.freeze({ 1 })
	end

	local totalWeight = 0
	local minWeight = math.huge
	for _, weight in weights do
		assert(weight > 0, "Fixed reward weights must be positive")
		totalWeight += weight
		minWeight = math.min(minWeight, weight)
	end

	local cycleSize = math.max(100, math.ceil(totalWeight / minWeight))
	local counts = {}
	local fractions = {}
	local remainderOrder = {}
	local allocated = 0
	for index, weight in weights do
		local exact = weight / totalWeight * cycleSize
		local count = math.floor(exact)
		counts[index] = count
		fractions[index] = exact - count
		table.insert(remainderOrder, index)
		allocated += count
	end

	table.sort(remainderOrder, function(left, right)
		return if fractions[left] == fractions[right] then left < right else fractions[left] > fractions[right]
	end)
	for offset = 1, cycleSize - allocated do
		counts[remainderOrder[offset]] += 1
	end

	local sequence = table.create(cycleSize)
	local scores = table.create(#weights, 0)
	for _ = 1, cycleSize do
		local chosen = 1
		for index, count in counts do
			scores[index] += count
			if scores[index] > scores[chosen] then
				chosen = index
			end
		end

		table.insert(sequence, chosen)
		scores[chosen] -= cycleSize
	end

	local rarestIndex = 1
	for index = 2, #weights do
		if counts[index] < counts[rarestIndex] then
			rarestIndex = index
		end
	end

	local firstRarest = table.find(sequence, rarestIndex) :: number
	local rotated = table.create(cycleSize)
	for offset = 1, cycleSize do
		table.insert(rotated, sequence[(firstRarest + offset - 1) % cycleSize + 1])
	end

	return table.freeze(rotated)
end

return table.freeze(FixedRewardSequence)
