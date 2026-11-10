-- Ranked Points: people always count; bot-only games stop at Gold.
local Cards=dofile('roblox/src/shared/Cards.luau')
local Scoring = dofile('roblox/src/shared/Scoring.luau')(Cards)
local S = dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules = dofile('roblox/src/shared/PlayRules.luau')(Cards, S)
local Practice = dofile('roblox/src/server/Practice.luau')(Cards, S, Rules, Scoring)
local GOLD, SILVER = 2400, 1200
local function rank(before, won, vsPeople, levels) return Scoring.rankDelta(before, won, vsPeople, levels, GOLD, SILVER) end

-- Decisive rounds are worth more, and people are worth about double.
assert(rank(2600, true, true, 1) == 150 and rank(2600, true, true, 4) == 300)
assert(rank(2600, false, true, 1) == -50 and rank(2600, false, true, 4) == -125)
assert(rank(1300, true, false, 1) == 75 and rank(1300, true, false, 4) == 150)
assert(rank(1300, false, false, 1) == -25 and rank(1300, false, false, 4) == -55)
assert(rank(2600, true, true, 0) == 150 and rank(2600, true, true, 9) == 300, 'margins are limited to 1-4')

-- Bronze never loses points.
assert(rank(1199, false, true, 3) == 0 and rank(1199, false, false, 3) == 0)

-- Bot games climb to Gold exactly, then stop counting either way.
assert(rank(2390, true, false, 3) == 10, 'a bot win stops at the cap')
local delta, capped = rank(2400, true, false, 3)
assert(delta == 0 and capped == true)
delta, capped = rank(2600, false, false, 3)
assert(delta == 0 and capped == true, 'bots cannot cost points above the cap either')

-- The cap never applies to a game with people.
delta, capped = rank(2600, true, true, 2)
assert(delta == 200 and capped == false)
assert(rank(2600, false, true, 2) == -75)

-- A typical player (55% against people, mostly narrow results) clears a
-- 400 RP division in about five games.
local perGame = 0.55 * rank(2600, true, true, 2) + 0.45 * rank(2600, false, true, 1)
assert(400 / perGame >= 4 and 400 / perGame <= 6, 'about five games per division')

-- Each tier below Master splits into three divisions; Master is one step.
local Catalog = dofile('roblox/src/shared/Catalog.luau')
local ranks = Catalog.ranks
local function standing(points) return Scoring.rankStanding(points, ranks) end
assert(standing(0).label == 'Bronze III' and standing(0).step == 1 and standing(0).nextAt == 400)
assert(standing(399).label == 'Bronze III' and standing(400).label == 'Bronze II' and standing(800).label == 'Bronze I')
assert(standing(1199).label == 'Bronze I' and standing(1199).nextAt == 1200)
assert(standing(1200).label == 'Silver III' and standing(1200).step == 4 and standing(1200).floor == 1200)
assert(standing(2799).label == 'Gold III' and standing(2800).label == 'Gold II' and standing(2800).floor == 2800)
assert(standing(5999).label == 'Diamond I' and standing(5999).step == 15)
assert(standing(6000).label == 'Master' and standing(6000).step == 16 and standing(6000).nextAt == nil and standing(9000).step == 16)
-- Every division is the same 400 RP.
for step = 1, 15 do
  local tier = ranks[math.ceil(step / 3)]
  assert((ranks[math.ceil(step / 3) + 1].at - tier.at) / 3 == 400)
end
assert(Scoring.rankStepLabel(1, ranks) == 'Bronze III' and Scoring.rankStepLabel(9, ranks) == 'Gold I' and Scoring.rankStepLabel(16, ranks) == 'Master')
-- Season coins rise with every division, and there is one amount per step.
local coins = Catalog.rankSeason.stepCoins
assert(#coins == (#ranks - 1) * 3 + 1 and coins[#coins] == 2500000)
for step = 2, #coins do assert(coins[step] > coins[step - 1], 'each division pays more than the one below') end

-- Seasons last 30 days from the start, numbered from 1.
local season = { start = 1000, days = 30 }
local number, endsAt = Scoring.rankSeason(1000, season)
assert(number == 1 and endsAt == 1000 + 30 * 86400)
assert(Scoring.rankSeason(1000 + 30 * 86400 - 1, season) == 1 and Scoring.rankSeason(1000 + 30 * 86400, season) == 2)
assert(Scoring.rankSeason(0, season) == 1, 'before the start counts as Season 1')

-- Ranked keeps Chao Di but has no Double: once everyone passes, play starts.
for _, ranked in ipairs({ true, false }) do
  local state = Practice.new(function() return 1 end, 0, { playerCount = 4, ranked = ranked, humans = { [1] = true } })
  state.phase, state.dealer, state.kittyHolder, state.chaodiTurn, state.chaodiPasses = 'chaodi', 1, 1, 2, {}
  state.trump = { level = '2', suit = 'spades' }
  for seat = 2, 4 do assert(Practice.chaodiPass(state, seat, 5)) end
  assert(state.phase == (ranked and 'tricks' or 'doubling'), 'ranked skips only the Double window')
end
print('PASS: ranked points, divisions, seasons and phases')
