-- Ranked Points: people always count; bot-only games stop at Gold.
local Cards=dofile('roblox/src/shared/Cards.luau')
local Scoring = dofile('roblox/src/shared/Scoring.luau')(Cards)
local S = dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules = dofile('roblox/src/shared/PlayRules.luau')(Cards, S)
local Practice = dofile('roblox/src/server/Practice.luau')(Cards, S, Rules, Scoring)
local GOLD = 250
local function rank(before, won, vsPeople, levels) return Scoring.rankDelta(before, won, vsPeople, levels, GOLD) end

-- Decisive rounds are worth more, and people are worth about double.
assert(rank(500, true, true, 1) == 30 and rank(500, true, true, 3) == 50)
assert(rank(500, false, true, 1) == -25 and rank(500, false, true, 3) == -35)
assert(rank(100, true, false, 1) == 15 and rank(100, true, false, 3) == 25)
assert(rank(100, false, false, 1) == -17 and rank(100, false, false, 3) == -23)
assert(rank(500, true, true, 4) == 60 and rank(500, false, true, 4) == -40, 'a shutout is worth the most')
assert(rank(100, true, false, 4) == 30 and rank(100, false, false, 4) == -26)
assert(rank(500, true, true, 0) == 30 and rank(500, true, true, 9) == 60, 'margins are limited to 1-4')

-- Bronze never loses points.
assert(rank(99, false, true, 3) == 0 and rank(99, false, false, 3) == 0)

-- Bot games climb to Gold exactly, then stop counting either way.
assert(rank(240, true, false, 3) == 10, 'a bot win stops at the cap')
local delta, capped = rank(250, true, false, 3)
assert(delta == 0 and capped == true)
delta, capped = rank(800, false, false, 3)
assert(delta == 0 and capped == true, 'bots cannot cost points above the cap either')

-- The cap never applies to a game with people.
delta, capped = rank(800, true, true, 2)
assert(delta == 40 and capped == false)
assert(rank(800, false, true, 2) == -30)
-- Ranked keeps Chao Di but has no Double: once everyone passes, play starts.
for _, ranked in ipairs({ true, false }) do
  local state = Practice.new(function() return 1 end, 0, { playerCount = 4, ranked = ranked, humans = { [1] = true } })
  state.phase, state.dealer, state.kittyHolder, state.chaodiTurn, state.chaodiPasses = 'chaodi', 1, 1, 2, {}
  state.trump = { level = '2', suit = 'spades' }
  for seat = 2, 4 do assert(Practice.chaodiPass(state, seat, 5)) end
  assert(state.phase == (ranked and 'tricks' or 'doubling'), 'ranked skips only the Double window')
end
print('PASS: ranked points and phases')
