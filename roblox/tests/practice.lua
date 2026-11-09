local Cards=dofile('roblox/src/shared/Cards.luau')
local S=dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules=dofile('roblox/src/shared/PlayRules.luau')(Cards,S)
local Scoring=dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice=dofile('roblox/src/server/Practice.luau')(Cards,S,Rules,Scoring)
-- Completes the Chao Di round that follows every burial: the human passes and
-- bots decide, so tests continue into trick play.
local function finishChaodi(state)
  local steps=0
  while state.phase=='chaodi' do
    steps=steps+1; assert(steps<100,'Chao Di did not finish')
    if state.chaodiTurn==1 then assert(Practice.chaodiPass(state,1,0)) else assert(Practice.stepChaodiBot(state,0)) end
  end
end
local function ids(cards) local result={};for _,c in ipairs(cards) do table.insert(result,c.id) end;return result end
for _,count in ipairs({4,6,8,10}) do
  local state=Practice.new(function(n)return n end,0,{playerCount=count})
  local config=Cards.config(count)
  assert(#state.kitty==config.kittySize and #state.hands==count)
  local seen,total={},0
  for _,c in ipairs(Cards.deck(count)) do assert(not seen[c.id]);seen[c.id]=true;total=total+Cards.points(c) end
  assert(total==count/2*100)
  assert(not Practice.play(state,1,{state.hands[1][1].id}))
  local options=Practice.options(state,1)
  if #options>0 then assert(Practice.declare(state,1,1,1));assert(Practice.advance(state,9,function()return 1 end))
  else assert(Practice.advance(state,8,function()return 1 end));assert(Practice.advance(state,16,function()return 1 end)) end
  if state.phase=='kitty' then
    local buried={};for i=1,state.kittySize do buried[i]=state.hands[1][i].id end
    assert(Practice.bury(state,1,buried))
  end
  finishChaodi(state)
  local revision=state.revision
  assert(not Practice.play(state,2,ids(state.hands[2])))
  assert(not Practice.play(state,1,{'not-owned'}))
  assert(not Practice.play(state,1,{state.hands[1][1].id,state.hands[1][1].id}))
  assert(state.revision==revision)
  local commands=0
  while not state.done do
    if state.phase=='trick-review' then assert(Practice.nextTrick(state));Practice.bots(state) end
    if not state.done and state.phase=='tricks' then
      assert(state.turn==1)
      assert(Practice.play(state,1,ids(Rules.choose(state.hands[1],state.trick[1] and state.trick[1].components,state.trump))))
      Practice.bots(state)
    end
    commands=commands+1;assert(commands<=2*config.handSize+1,'Round did not finish')
  end
  assert(state.tricks<=config.handSize and #state.history==state.tricks)
  for _,hand in ipairs(state.hands) do assert(#hand==0) end
  local points=0;for _,c in ipairs(state.kitty) do points=points+Cards.points(c) end
  assert(state.points[1]+state.points[2]+points==total)
  local view=Practice.view(state)
  assert(view.kitty==nil and view.hands==nil and view.events==nil)
  assert(view.settlement and view.settlement.levels)
  assert(not Practice.play(state,1,{'anything'}))
  local nextState=assert(Practice.nextRound(state,function(n)return n end,30))
  assert(nextState.round==2 and nextState.revision>state.revision)
  local scheduled=nextState.scheduledDealer
  assert(Practice.advance(nextState,38,function()return 1 end))
  assert(Practice.advance(nextState,46,function()return 1 end))
  assert(nextState.dealer==scheduled,'Declaration must not transfer dealer duties after round one')
end
print('PASS: 4/6/8/10-player rounds, multi-card bots, atomic rejection, privacy, conservation, settlement and next-round dealer')
