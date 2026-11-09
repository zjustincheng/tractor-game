-- Declarations: Tencent-style joker pairs call no-trump.
math.clamp = math.clamp or function(value, low, high) return math.max(low, math.min(high, value)) end
local Cards = dofile('roblox/src/shared/Cards.luau')
local S = dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules = dofile('roblox/src/shared/PlayRules.luau')(Cards, S)
local Scoring = dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice = dofile('roblox/src/server/Practice.luau')(Cards, S, Rules, Scoring)

local nextId = 0
local function card(rank, suit) nextId = nextId + 1; return { id = 'c' .. nextId, rank = rank, suit = suit } end
local function joker(kind) nextId = nextId + 1; return { id = 'j' .. nextId, joker = kind } end
local function state(hands, extra)
  local s = { phase = 'declaration', trump = { level = '4' }, hands = hands, playerCount = 4, handSize = 25, round = 1,
    deadline = 1000, dealingStartedAt = 0, dealingDuration = 0, revision = 0, events = {}, humans = { [1] = true, [2] = true, [3] = true, [4] = true }, botDeclarations = {} }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end
local function find(options, test) for i, o in ipairs(options) do if test(o) then return i, o end end end

-- A pair of the same joker is offered; one joker or a mixed pair is not.
local s = state({ { joker('big'), joker('big'), joker('small'), card('5', 'clubs') }, {}, {}, {} })
local index, option = find(Practice.options(s, 1), function(o) return o.joker == 'big' and o.count == 2 end)
assert(index and #option.cardIds == 2, 'big joker pair offered')
assert(not find(Practice.options(s, 1), function(o) return o.joker == 'small' end), 'single small joker not offered')
assert(#Practice.options(state({ { joker('big'), joker('small'), card('5', 'clubs') }, {}, {}, {} }), 1) == 0, 'one big and one small joker is not a pair')
assert(Practice.declare(s, 1, index, 1), 'joker pair declares')
assert(s.declaration.joker == 'big' and s.declaration.suit == nil, 'declared no-trump')

-- Overturn order.
local function overturn(firstHand, firstTest, secondHand, secondTest, round)
  local t = state({ firstHand, secondHand, {}, {} }, { round = round or 1 })
  assert(Practice.declare(t, 1, (find(Practice.options(t, 1), firstTest)), 1), 'first declaration')
  local i = find(Practice.options(t, 2), secondTest)
  return i ~= nil and Practice.declare(t, 2, i, 2) == true
end
local bigPair = function(o) return o.joker == 'big' and o.count == 2 end
local smallPair = function(o) return o.joker == 'small' and o.count == 2 end
local suitOne = function(o) return o.suit == 'clubs' and o.count == 1 end
local suitPair = function(o) return o.suit == 'clubs' and o.count == 2 end
local bigs = function() return { joker('big'), joker('big') } end
local smalls = function() return { joker('small'), joker('small') } end
local fours = function(n) local h = {}; for i = 1, n do h[i] = card('4', 'clubs') end; return h end
assert(overturn(fours(1), suitOne, smalls(), smallPair), 'joker pair beats a single')
assert(overturn(fours(2), suitPair, smalls(), smallPair), 'joker pair beats a suit pair')
assert(overturn(smalls(), smallPair, bigs(), bigPair), 'big pair beats small pair')
assert(not overturn(bigs(), bigPair, smalls(), smallPair), 'small pair cannot beat big pair')
assert(not overturn(smalls(), smallPair, fours(2), suitPair), 'suit pair cannot beat a joker pair')

-- One overturn rule at every size and in every round.
local function many(n, make) local h = {}; for i = 1, n do h[i] = make() end; return h end
local function size(n, kind) return function(o) return o.joker == kind and o.count == n end end
local function suits(n) return function(o) return o.suit == 'clubs' and o.count == n end end
local function big() return joker('big') end
local function small() return joker('small') end
local function four() return card('4', 'clubs') end
assert(overturn(many(2, small), smallPair, many(3, four), suits(3)), 'three level cards beat a joker pair')
assert(overturn(many(3, small), size(3, 'small'), many(4, four), suits(4)), 'four level cards beat three jokers')
assert(overturn(many(4, big), size(4, 'big'), many(5, four), suits(5), 2), 'five level cards beat four big jokers in a later round')
assert(overturn(many(3, small), size(3, 'small'), many(3, big), size(3, 'big'), 2), 'three big beat three small in a later round')
assert(not overturn(many(3, big), size(3, 'big'), many(3, small), size(3, 'small')), 'three small cannot beat three big')
assert(overturn(many(3, four), suits(3), many(3, small), size(3, 'small')), 'jokers beat a suit at the same size')
assert(not overturn(many(3, small), size(3, 'small'), many(3, four), suits(3)), 'a suit cannot beat jokers at the same size')
assert(not overturn(many(3, four), suits(3), many(2, big), bigPair), 'fewer jokers cannot beat more level cards')

-- No joker goes to waste: every size is offered, up to the whole holding.
local ten = state({ { joker('big'), joker('big'), joker('big'), joker('big'), joker('big'), joker('small') }, {}, {}, {} }, { playerCount = 10 })
local options = Practice.options(ten, 1)
assert(find(options, size(5, 'big')), 'five big jokers can be called')
local _, mixed = find(options, function(o) return o.joker == 'mixed' and o.count == 6 end)
assert(mixed and #mixed.cardIds == 6, 'all six jokers can be called together')
local ids = {}
local _, four_ = find(options, function(o) return o.joker == 'mixed' and o.count == 4 end)
for _, id in ipairs(four_.cardIds) do assert(not ids[id], 'distinct'); ids[id] = true end
local kinds = {}
for _, c in ipairs(ten.hands[1]) do if ids[c.id] then kinds[c.joker] = true end end
assert(kinds.big and kinds.small, 'a mixed call holds both kinds')

-- Changing the trump suit doubles the stakes; strengthening the same one does not.
local function stakes(steps)
  local hands = {}
  for i = 1, 4 do hands[i] = steps[i] and steps[i].hand or {} end
  local t = state(hands)
  for seat, step in ipairs(steps) do
    assert(Practice.declare(t, seat, (find(Practice.options(t, seat), step.test)), seat), 'declaration ' .. seat)
  end
  return t.chaodiMultiplier or 1, t
end
local function suit(name, n) local h = {}; for i = 1, n do h[i] = card('4', name) end; return h end
local function suited(name, n) return function(o) return o.suit == name and o.count == n end end
assert(stakes({ { hand = suit('clubs', 1), test = suited('clubs', 1) } }) == 1, 'the first declaration changes nothing')
assert(stakes({ { hand = suit('clubs', 1), test = suited('clubs', 1) }, { hand = suit('hearts', 2), test = suited('hearts', 2) } }) == 2, 'a new suit doubles')
assert(stakes({ { hand = suit('clubs', 1), test = suited('clubs', 1) }, { hand = suit('clubs', 2), test = suited('clubs', 2) } }) == 1, 'the same suit does not double')
assert(stakes({ { hand = suit('clubs', 1), test = suited('clubs', 1) }, { hand = many(2, small), test = smallPair } }) == 2, 'suit to no-trump doubles')
assert(stakes({ { hand = many(2, small), test = smallPair }, { hand = many(2, big), test = bigPair } }) == 1, 'small to big jokers stays no-trump')
assert(stakes({ { hand = suit('clubs', 1), test = suited('clubs', 1) }, { hand = suit('hearts', 2), test = suited('hearts', 2) }, { hand = many(2, small), test = smallPair }, { hand = suit('spades', 3), test = suited('spades', 3) } }) == 8, 'each change doubles again')

-- Bots need backing trump before calling no-trump on a pair.
local weak = state({ {}, { joker('big'), joker('big'), card('7', 'clubs'), card('9', 'hearts') }, {}, {} }, { humans = { [1] = true, [3] = true, [4] = true } })
Practice.botDeclare(weak, 2)
assert(weak.declaration == nil, 'weak bot passes on a joker pair')
local strong = state({ {}, { joker('big'), joker('big'), card('4', 'clubs'), card('4', 'hearts'), card('4', 'spades') }, {}, {} }, { humans = { [1] = true, [3] = true, [4] = true } })
Practice.botDeclare(strong, 2)
assert(strong.declaration and strong.declaration.joker == 'big', 'strong bot calls no-trump')

print('PASS: joker pair declarations')
