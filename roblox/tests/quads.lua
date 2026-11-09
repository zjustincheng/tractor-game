-- Four of a kind beats a 4-card tractor (Roblox house rule).
math.clamp = math.clamp or function(value, low, high) return math.max(low, math.min(high, value)) end
local Cards = dofile('roblox/src/shared/Cards.luau')
local S = dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules = dofile('roblox/src/shared/PlayRules.luau')(Cards, S)
local trump = { level = 'K', suit = 'spades' }
local n = 0
local function cards(ranks, suit)
  local out = {}
  for _, rank in ipairs(ranks) do n = n + 1; out[#out + 1] = { id = 'c' .. n, rank = rank, suit = suit or 'clubs' } end
  return out
end
local function comps(list) return S.decompose(list, trump) end
local function join(a, b) local out = {}; for _, c in ipairs(a) do out[#out + 1] = c end; for _, c in ipairs(b) do out[#out + 1] = c end; return out end
local tractor = comps(cards({ '3', '3', '4', '4' }))
local bigTractor = comps(cards({ 'A', 'A', 'Q', 'Q' }))
assert(tractor[1].rankCount == 2 and bigTractor[1].rankCount == 2, 'tractors')

-- Following: a quad in the led suit is legal, matches, and wins.
local quad = cards({ '7', '7', '7', '7' })
local result = Rules.follow(quad, quad, tractor, trump)
assert(result.legal and result.matchesLead and result.components[1].multiplicity == 4, 'quad follows a tractor')
assert(Rules.winning(quad, tractor, tractor, trump), 'quad beats the tractor it follows')
assert(Rules.winning(cards({ '2', '2', '2', '2' }), bigTractor, bigTractor, trump), 'the lowest quad beats the highest tractor')

-- It may be chosen over a real tractor in hand.
local filler = cards({ '5', '5', '6', '6' })
result = Rules.follow(join(quad, filler), quad, tractor, trump)
assert(result.legal and result.matchesLead, 'quad may replace a held tractor')

-- A trump quad wins when void; an off-suit quad does not count.
local trumpQuad = cards({ '7', '7', '7', '7' }, 'spades')
result = Rules.follow(trumpQuad, trumpQuad, tractor, trump)
assert(result.legal and result.matchesLead, 'trump quad when void')
assert(Rules.winning(trumpQuad, tractor, tractor, trump), 'trump quad beats a suit tractor')
local offSuit = cards({ '7', '7', '7', '7' }, 'hearts')
result = Rules.follow(offSuit, offSuit, tractor, trump)
assert(result.legal and not result.matchesLead, 'off-suit quad cannot win')

-- Against what is already winning.
local trumpTractor = comps(cards({ '3', '3', '4', '4' }, 'spades'))
assert(not Rules.winning(quad, tractor, trumpTractor, trump), 'led-suit quad cannot beat a trump tractor')
assert(Rules.winning(trumpQuad, tractor, trumpTractor, trump), 'trump quad beats a trump tractor')
local heldQuad = comps(cards({ '9', '9', '9', '9' }))
assert(not Rules.winning(quad, tractor, heldQuad, trump), 'lower quad loses to a higher quad')
assert(Rules.winning(cards({ 'J', 'J', 'J', 'J' }), tractor, heldQuad, trump), 'higher quad beats a quad')
assert(Rules.winning(trumpQuad, tractor, heldQuad, trump), 'trump quad beats a suit quad')
assert(not Rules.winning(cards({ '5', '5', '6', '6' }), tractor, heldQuad, trump), 'a tractor cannot beat a quad')

-- Only four-card tractors: a 6-card tractor and a plain pair are unaffected.
local six = comps(cards({ '2', '2', '3', '3', '4', '4' }))
assert(not Rules.winning(quad, six, six, trump), 'not a 6-card tractor')
local pair = comps(cards({ '3', '3' }))
assert(not Rules.winning(quad, pair, pair, trump), 'not a pair')

print('PASS: quads beat four-card tractors')
