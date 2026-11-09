local Cards=dofile('roblox/src/shared/Cards.luau')
local S=dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules=dofile('roblox/src/shared/PlayRules.luau')(Cards,S)
local Scoring=dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice=dofile('roblox/src/server/Practice.luau')(Cards,S,Rules,Scoring)

-- Builds a Chao Di state where seat 2 holds the given level cards and jokers.
local function setup(declaration, hand)
  local state=Practice.new(function(n)return n end,0,{playerCount=6,level='5'})
  state.phase='chaodi'
  state.dealer=1
  state.chaodiTurn=2
  state.declaration=declaration
  state.hands[2]=hand
  return state
end
local function card(id, suit, rank) return {id=id, suit=suit, rank=rank} end
local function joker(id, kind) return {id=id, joker=kind} end
local function has(options, predicate)
  for _,o in ipairs(options) do if predicate(o) then return true end end
  return false
end

local bigPair={seat=1,joker='big',count=2,cardIds={'b1','b2'}}
local smallPair={seat=1,joker='small',count=2,cardIds={'s1','s2'}}
local triple={card('h1','hearts','5'),card('h2','hearts','5'),card('h3','hearts','5')}
local pair={card('h1','hearts','5'),card('h2','hearts','5')}

-- Three of a kind overturns either joker pair.
for _,decl in ipairs({bigPair,smallPair}) do
  local options=Practice.chaodiOptions(setup(decl,triple),2)
  assert(has(options,function(o) return o.suit=='hearts' and o.count==3 end),'Triple must overturn a '..decl.joker..' joker pair')
  assert(not has(options,function(o) return o.suit=='hearts' and o.count==2 end),'A level pair must not overturn a joker pair')
end

-- A level pair still cannot beat a joker pair; big jokers still beat small jokers.
assert(#Practice.chaodiOptions(setup(bigPair,pair),2)==0)
local bigs={joker('x1','big'),joker('x2','big')}
assert(has(Practice.chaodiOptions(setup(smallPair,bigs),2),function(o) return o.joker=='big' end))
assert(#Practice.chaodiOptions(setup(bigPair,bigs),2)==0)

-- A triple declaration is not overturned by a joker pair.
local tripleDecl={seat=1,suit='spades',count=3,cardIds={'a','b','c'}}
assert(#Practice.chaodiOptions(setup(tripleDecl,bigs),2)==0)

-- Choosing the triple applies the overturn.
local state=setup(bigPair,triple)
local index
for i,o in ipairs(Practice.chaodiOptions(state,2)) do if o.count==3 then index=i end end
local attacking=state.attackingTeam
assert(Practice.chaodi(state,2,index,1))
assert(state.declaration.count==3 and state.trump.suit=='hearts')
-- Chao Di changes trump and who re-buries, not the dealer or the teams.
assert(state.dealer==1 and state.scheduledDealer==1 and state.attackingTeam==attacking)
assert(state.kittyHolder==2 and #state.kitty==state.kittySize,'Bot challenger re-buries the kitty')
assert(state.phase=='chaodi' and state.chaodiTurn==3,'Challenge passes on after the challenger')
for seat=3,6 do assert(Practice.chaodiPass(state,seat,2)) end
assert(state.phase=='chaodi' and state.chaodiTurn==1,'The original dealer may still challenge back')
assert(Practice.chaodiPass(state,1,2))
assert(state.phase=='tricks' and state.turn==1 and state.dealer==1,'Original dealer leads the first trick')
-- Bots challenge only when the new suit clearly helps their hand.
local function hand(levelHearts, otherHearts, filler)
  local cards = {}
  for i = 1, levelHearts do table.insert(cards, card('lh' .. i, 'hearts', '5')) end
  for i = 1, otherHearts do table.insert(cards, card('oh' .. i, 'hearts', tostring(5 + (i % 8) + 1))) end
  for i = 1, filler do table.insert(cards, card('fc' .. i, 'clubs', tostring(6 + (i % 8)))) end
  return cards
end
local spadesPair = { seat = 1, suit = 'spades', count = 2, cardIds = { 's1', 's2' } }
local function botState(seat, cards)
  local st = setup(spadesPair, cards)
  st.trump = { level = '5', suit = 'spades' }
  st.chaodiTurn = seat
  st.hands[seat] = cards
  st.kittyHolder = 1
  return st
end
local strong = botState(2, hand(3, 6, 8)) -- 9 hearts would become trump
local pick = Practice.chooseChaodi(strong, 2)
assert(pick and Practice.chaodiOptions(strong, 2)[pick].suit == 'hearts', 'Strong opponent hand challenges into hearts')
local weak = botState(2, hand(3, 0, 14)) -- only the 3 level cards gain
assert(Practice.chooseChaodi(weak, 2) == nil, 'A level triple alone is not worth challenging')
local teammate = botState(3, hand(3, 1, 13)) -- +1 trump over spades for the dealer's partner
assert(Practice.chooseChaodi(teammate, 3) == nil, "Teammates need a bigger gain to override their side's trump")
local teammateStrong = botState(3, hand(3, 6, 8))
assert(Practice.chooseChaodi(teammateStrong, 3), 'A teammate with a much better suit still challenges')
assert(Practice.stepChaodiBot(weak, 0) and weak.chaodiPasses[2], 'A weak bot passes')

print('PASS: three of a kind overturns joker pairs in Chao Di; Chao Di keeps the dealer and teams; bots challenge only for a clearly better suit')
