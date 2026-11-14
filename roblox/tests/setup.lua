local Cards = dofile('roblox/src/shared/Cards.luau')
local Structures = dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules = dofile('roblox/src/shared/PlayRules.luau')(Cards, Structures)
local Scoring = dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice = dofile('roblox/src/server/Practice.luau')(Cards, Structures, Rules, Scoring)
-- These checks were written for an 8-second declaration window; the game now
-- uses a longer one, so pin the timing they assume.
Practice.DECLARE_SECONDS = 8
-- Completes the Chao Di round that follows every burial: the human passes and
-- bots decide, so tests continue into trick play.
local function finishChaodi(state)
  local steps=0
  while state.phase=='chaodi' do
    steps=steps+1; assert(steps<100,'Chao Di did not finish')
    if state.chaodiTurn==1 then assert(Practice.chaodiPass(state,1,0)) else assert(Practice.stepChaodiBot(state,0)) end
  end
  -- The Double window follows Chao Di; close it so play can start.
  if state.phase=='doubling' then assert(Practice.endDoubling(state,0,true)) end
end
local function new() return Practice.new(function(n) return n end, 100) end
local state = new()
assert(not Practice.advance(state, 107.99, function() error('Too early') end))
assert(Practice.advance(state, 108, function() return 1 end))
assert(state.phase == 'declaration' and state.deadline == 116)
assert(state.events[1].kind == 'fallback' and #state.events[1].declaration.cardIds == 1)
local revision = state.revision
assert(not Practice.declare(state, 1, 1, 109)) -- equal cannot overturn
assert(not Practice.declare(state, 1, 0/0, 109))
assert(not Practice.declare(state, 1, {}, 109))
assert(not Practice.declare(state, 1, 1, 116))
assert(state.revision == revision)
assert(Practice.advance(state, 116, function() error('Already declared') end))
assert(state.phase == 'kitty' and state.dealer == 1)
assert(#Practice.view(state).hand == 33)
assert(Practice.view(state).kitty == nil and Practice.view(state).events == nil)
local ids = {}
for i = 1, 8 do ids[i] = state.hands[1][i].id end
local bad = { ids[1], ids[1], ids[3], ids[4], ids[5], ids[6], ids[7], ids[8] }
revision = state.revision
assert(not Practice.bury(state, 2, ids))
assert(not Practice.bury(state, 1, bad))
bad[2] = 'not-owned'
assert(not Practice.bury(state, 1, bad))
assert(not Practice.bury(state, 1, 'malformed'))
bad[2], bad.extra = ids[2], ids[2]
assert(not Practice.bury(state, 1, bad))
assert(state.revision == revision and #state.hands[1] == 33 and #state.kitty == 0)
assert(Practice.bury(state, 1, ids))
assert(state.phase == 'chaodi' and state.kittyHolder == 1 and #state.kitty == 8 and #state.hands[1] == 25)
finishChaodi(state)
assert(state.phase == 'tricks' and state.dealer == 1)
assert(not Practice.bury(state, 1, ids))
assert(not Practice.declare(state, 1, 1, 120))
assert(not Practice.advance(state, 120, function() error('Must not pick') end))

-- Explicit hands exercise double level declarations and mixed-joker lock.
local fixture = new()
fixture.hands = {
  { {id='a', rank='2', suit='clubs'} },
  { {id='b', rank='2', suit='hearts'}, {id='c', rank='2', suit='hearts'} },
  { {id='d', joker='small'}, {id='e', joker='small'}, {id='f', joker='big'} },
  { {id='g', rank='2', suit='spades'} },
}
assert(Practice.declare(fixture, 1, 1, 101))
assert(Practice.declare(fixture, 2, 2, 107))
assert(fixture.deadline == 115 and fixture.declaration.seat == 2)
assert(Practice.declare(fixture, 3, 1, 114))
assert(fixture.deadline == 122 and fixture.declaration.suit == nil)
revision = fixture.revision
assert(not Practice.declare(fixture, 2, 2, 115))
assert(fixture.revision == revision)

-- Bot dealer picks up and buries privately, leads, then stops at the human.
local bot = new()
assert(Practice.declare(bot, 2, 1, 101))
assert(Practice.advance(bot, 109, function() return 1 end))
assert(bot.phase == 'chaodi' and bot.dealer == 2)
-- The Chao Di clock starts when the bot buries, not at time zero, so the next
-- seat (often the human) gets its full turn instead of an instant pass.
assert(bot.chaodiDeadline == 109 + Practice.CHAODI_SECONDS, 'Bot burial starts the Chao Di clock now')
finishChaodi(bot)
assert(bot.phase == 'tricks' and bot.dealer == 2 and bot.turn == 1)
assert(#bot.kitty == 8 and #Practice.view(bot).hand == 25)
assert(Practice.view(bot).hands == nil and Practice.view(bot).kitty == nil)
assert(bot.lastTrick[1] == nil and bot.trick[1].seat == 2)
local seen, total = {}, 0
local function count(cards)
  for _, card in ipairs(cards) do
    assert(not seen[card.id]); seen[card.id] = true; total = total + 1
  end
end
for _, hand in ipairs(bot.hands) do count(hand) end
count(bot.kitty)
for _, play in ipairs(bot.trick) do count(play.cards) end
assert(total == 108)

-- No silent no-suit default or automatic redeal when fallback has no candidate.
local blocked = new()
blocked.hands = { {}, {}, {}, {} }
assert(Practice.advance(blocked, 108, function() error('No candidates') end))
assert(blocked.phase == 'blocked' and blocked.declaration == nil)
print('PASS: declaration deadlines, fallback, overturns, joker lock, atomic burial, dealer privacy and conservation')
