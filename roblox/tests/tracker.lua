-- VIP card tracker: public information only, and "safe" must be truly safe.
math.clamp = math.clamp or function(value, low, high) return math.max(low, math.min(high, value)) end
local Cards = dofile('roblox/src/shared/Cards.luau')
local S = dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules = dofile('roblox/src/shared/PlayRules.luau')(Cards, S)
local Scoring = dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice = dofile('roblox/src/server/Practice.luau')(Cards, S, Rules, Scoring)
local Tracker = dofile('roblox/src/shared/Tracker.luau')(Cards, S)
local trump = { level = 'K', suit = 'spades' }
local function c(copy, suit, rank) return { id = copy .. ':' .. suit .. ':' .. rank, suit = suit, rank = rank } end
local function find(list, category) for _, e in ipairs(list) do if e.category == category then return e end end end
local function count(parts) local n = 0; for _, p in ipairs(parts) do n = n + #p.cards end; return n end

-- Reading anything but the public fields is an error.
local allowed = { trump = true, playerCount = true, hand = true, history = true, trick = true }
local function guarded(view)
  return setmetatable({}, { __index = function(_, key)
    assert(allowed[key], 'tracker read hidden field ' .. tostring(key))
    return view[key]
  end })
end

-- Voids: failing to follow proves it, following does not.
local view = { trump = trump, playerCount = 4, hand = { c(0, 'clubs', 'A') }, hands = 'SECRET', kitty = 'SECRET', trick = {}, history = {
  { plays = {
    { seat = 1, cards = { c(0, 'hearts', '3') } },
    { seat = 2, cards = { c(0, 'clubs', '4') } },
    { seat = 3, cards = { c(0, 'hearts', '5') } },
    { seat = 4, cards = { c(0, 'spades', '2') } },
  } },
} }
local result = Tracker.analyze(guarded(view))
assert(result.voids[2].hearts and result.voids[4].hearts, 'players who could not follow are out')
assert(not result.voids[3].hearts, 'a player who followed is not out')
assert(not result.voids[2].clubs and not result.voids[2].trump, 'nothing else is inferred')

-- A partial follow to a pair proves the suit is gone.
view.history = { { plays = {
  { seat = 2, cards = { c(0, 'hearts', '3'), c(1, 'hearts', '3') } },
  { seat = 3, cards = { c(0, 'hearts', '5'), c(0, 'spades', '2') } },
  { seat = 4, cards = { c(0, 'hearts', '6'), c(0, 'hearts', '7') } },
  { seat = 1, cards = { c(0, 'hearts', '8'), c(0, 'hearts', '9') } },
} } }
result = Tracker.analyze(guarded(view))
assert(result.voids[3].hearts and not result.voids[4].hearts, 'partial follow')

-- The current trick counts too, and being trump-led tracks trump.
view.history = {}
view.trick = { { seat = 4, cards = { c(0, 'spades', 'A') } }, { seat = 1, cards = { c(0, 'hearts', '2') } }, { seat = 2, cards = { c(0, 'clubs', '2') } } }
result = Tracker.analyze(guarded(view))
assert(result.voids[2].trump, 'trump void from the live trick')

-- Safe: an ace can't be beaten by rank; a queen can while aces are unseen.
view.trick, view.history = {}, {}
view.hand = { c(0, 'clubs', 'A'), c(0, 'clubs', 'Q') }
local clubs = find(Tracker.analyze(guarded(view)).gambles, 'clubs')
assert(count(clubs.safe) == 1 and clubs.safe[1].cards[1].rank == 'A' and count(clubs.risky) == 1 and not clubs.canGamble, 'ace safe, queen risky')

-- Once both aces are played the queen is safe and a gamble is on.
view.history = { { plays = { { seat = 2, cards = { c(1, 'clubs', 'A') } } } }, { plays = { { seat = 3, cards = { c(0, 'hearts', '2') } } } } }
view.hand = { c(0, 'clubs', 'A'), c(0, 'clubs', 'Q') }
clubs = find(Tracker.analyze(guarded(view)).gambles, 'clubs')
assert(count(clubs.safe) == 2 and clubs.canGamble, 'queen safe after the aces are gone')

-- Only suits with two safe parts get markers; a lone safe card is not a gamble.
local marked = Tracker.analyze(guarded(view)).gambleCards
assert(marked[view.hand[1].id] and marked[view.hand[2].id], 'both safe parts are marked')
view.history = {}
marked = Tracker.analyze(guarded(view)).gambleCards
assert(next(marked) == nil, 'one safe part marks nothing')

-- If everyone else is out of a suit, all of it is safe.
view.history = { { plays = { { seat = 1, cards = { c(0, 'diamonds', '2') } }, { seat = 2, cards = { c(0, 'hearts', '3') } }, { seat = 3, cards = { c(1, 'hearts', '3') } }, { seat = 4, cards = { c(0, 'hearts', '4') } } } } }
view.hand = { c(0, 'diamonds', '3'), c(0, 'diamonds', '4'), c(1, 'diamonds', '9') }
local diamonds = find(Tracker.analyze(guarded(view)).gambles, 'diamonds')
assert(#diamonds.risky == 0 and count(diamonds.safe) == 3, 'everyone out means safe')

-- The server view never carries other hands or the kitty.
local state = Practice.new(function(n) return n end, 0, { playerCount = 10 })
local sent = Practice.relativeView(state, 3)
assert(sent.hands == nil and sent.kitty == nil, 'view has no hidden cards')

-- Whatever is marked safe really does pass the game's own gamble check.
math.randomseed(11)
local checked = 0
for _, rules in ipairs({ { level = '7', suit = 'hearts' }, { level = '7' } }) do
for _, players in ipairs({ 4, 6, 10 }) do
  for deal = 1, 12 do
    local deck = Cards.deck(players)
    for i = #deck, 2, -1 do local j = math.random(i); deck[i], deck[j] = deck[j], deck[i] end
    local config = Cards.config(players)
    local hands = {}
    for s = 1, players do hands[s] = {} end
    for i = 1, config.cardCount - config.kittySize do table.insert(hands[(i - 1) % players + 1], deck[i]) end
    -- Reveal some cards publicly, one at a time, so no void is implied.
    local history = {}
    for s = 2, players do
      for _ = 1, deal * 2 do
        local card = table.remove(hands[s])
        table.insert(history, { plays = { { seat = s, cards = { card } } } })
      end
    end
    local others = {}
    for s = 2, players do others[#others + 1] = hands[s] end
    local analysis = Tracker.analyze({ trump = rules, playerCount = players, hand = hands[1], history = history, trick = {} })
    for _, entry in ipairs(analysis.gambles) do
      for _, part in ipairs(entry.safe) do
        checked = checked + 1
        for _, other in ipairs(others) do
          local suited = {}
          for _, card in ipairs(other) do if Cards.category(card, rules) == entry.category then suited[#suited + 1] = card end end
          for _, candidate in ipairs(S.available(suited, rules, part)) do
            assert(candidate.highestPower <= part.highestPower, 'a part marked safe could be beaten')
          end
        end
      end
      if #entry.safe > 1 then assert(not Rules.gamble(entry.safe, others, rules, 'attackers').reduced, 'a safe gamble failed') end
    end
  end
end
end
assert(checked > 0)
print('PASS: card tracker uses public info and safe is safe (' .. checked .. ' checks)')
