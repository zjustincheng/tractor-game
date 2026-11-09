local Cards=dofile('roblox/src/shared/Cards.luau')
local S=dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules=dofile('roblox/src/shared/PlayRules.luau')(Cards,S)
local Scoring=dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice=dofile('roblox/src/server/Practice.luau')(Cards,S,Rules,Scoring)
local index=0
local function cards(ranks,suit)
  local result={}
  for _,rank in ipairs(ranks) do index=index+1;table.insert(result,{id='test:'..index,rank=rank,suit=suit or 'clubs'}) end
  return result
end
local function ids(items) local result={};for _,card in ipairs(items) do table.insert(result,card.id) end;return result end
local function fixture(hands)
  local state=Practice.new(function(n)return n end,0)
  state.hands,state.trump,state.phase,state.dealer=hands,{level='2',suit='spades'},'tricks',1
  return state
end
local state=fixture({cards({'3','3','5','7'}),cards({'4','4','8','9'}),cards({'6','6','10','J'}),cards({'Q','Q','K','A'})})
local revision=state.revision
assert(not Practice.play(state,1,{state.hands[1][1].id,state.hands[1][1].id}))
assert(not Practice.play(state,1,{state.hands[2][1].id}))
assert(not Practice.play(state,1,'single-id-is-not-an-array'))
assert(state.revision==revision and #state.hands[1]==4)
assert(Practice.play(state,1,{state.hands[1][1].id,state.hands[1][2].id}))
revision=state.revision
assert(not Practice.play(state,2,{state.hands[2][3].id,state.hands[2][4].id}))
assert(state.revision==revision and #state.hands[2]==4)
assert(not Practice.play(state,2,{state.hands[2][1].id}))
assert(Practice.play(state,2,{state.hands[2][1].id,state.hands[2][2].id}))
-- Failed throw returns every unplayed selected card and penalizes the correct role.
for _,role in ipairs({'A','B'}) do
  state=fixture({cards({'3','3','5','7'}),cards({'6','6','8','9'}),cards({'10','10','J','Q'}),cards({'K','K','A','A'})})
  state.attackingTeam=role
  local wanted={state.hands[1][1],state.hands[1][2],state.hands[1][3]}
  local ok,message=Practice.play(state,1,ids(wanted))
  assert(ok and message and #state.trick[1].cards==1 and state.trick[1].cards[1].rank=='5')
  assert(#state.hands[1]==3 and state.penaltyPoints==(role=='A' and 20 or -20))
  assert(S.homogeneous({state.hands[1][1],state.hands[1][2]},state.trump).multiplicity==2)
end
-- A successful pair+single gamble can be overtaken by any comparable component,
-- even if the new pair loses to the old pair (D10).
local lead=cards({'A','A','K'})
local previous=cards({'K','K','3'},'spades')
local challenger=cards({'Q','Q','A'},'spades')
state=fixture({lead,previous,challenger,cards({'4','4','5'},'hearts')})
assert(Practice.play(state,1,ids(lead)))
assert(#state.trick[1].cards==3 and state.penaltyPoints==0)
assert(Practice.play(state,2,ids(previous)))
assert(state.winnerSeat==2)
assert(Practice.play(state,3,ids(challenger)))
assert(state.winnerSeat==3)
assert(Practice.play(state,4,ids(state.hands[4])))
assert(state.done and state.lastWinnerSeat==3)
-- Final gamble uses its largest winning component for kitty multiplier.
local pairLow=cards({'3','3','4'})
state=fixture({pairLow,cards({'A','A','K'},'spades'),cards({'5','5','6'},'hearts'),cards({'7','7','8'},'diamonds')})
state.kitty=cards({'5','10'})
assert(Practice.play(state,1,ids(pairLow)))
for seat=2,4 do assert(Practice.play(state,seat,ids(state.hands[seat]))) end
assert(state.settlement.kittyMultiplier==4 and state.settlement.kittyPoints==60)
-- Random Quick Match starting level, dealt-card validation and no second round.
state=Practice.new(function(n)return n end,100,{quickMatch=true,dealingDuration=5.5})
assert(state.quickMatch and state.trump.level=='A' and state.deadline==113.5)
revision=state.revision
assert(not Practice.declare(state,1,1,100))
assert(state.revision==revision)
assert(Practice.declare(state,1,1,106))
-- First-round small/big joker takeover respects 3-vs-4 multiplicity.
state=Practice.new(function(n)return n end,0,{playerCount=8})
local small,big={},{}
for i=1,4 do small[i]={id='small'..i,joker='small'};big[i]={id='big'..i,joker='big'} end
state.hands[1],state.hands[2]=small,big
assert(Practice.declare(state,1,2,1)) -- four small
assert(not Practice.declare(state,2,1,2)) -- three big cannot beat four small
assert(Practice.declare(state,2,2,2)) -- four big can
print('PASS: pair command/follow rejection, atomicity, both gamble penalties, any-component wins, gamble kitty multiplier, quick setup and joker takeover')
