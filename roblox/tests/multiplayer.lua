-- Rules-engine support for several human seats at one table.
local Cards=dofile('roblox/src/shared/Cards.luau')
local S=dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules=dofile('roblox/src/shared/PlayRules.luau')(Cards,S)
local Scoring=dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice=dofile('roblox/src/server/Practice.luau')(Cards,S,Rules,Scoring)

local function ids(cards) local result={}; for _,c in ipairs(cards) do table.insert(result,c.id) end; return result end
local function settle(state, humans)
  -- Bots act on their own; humans are driven by autoAct, as when they time out.
  local steps=0
  while not state.done do
    steps=steps+1; assert(steps<2000,'Round did not finish')
    if state.phase=='trick-review' then assert(Practice.nextTrick(state))
    elseif state.phase=='chaodi' then
      if humans[state.chaodiTurn] then assert(Practice.autoAct(state,state.chaodiTurn,0)) else assert(Practice.stepChaodiBot(state,0)) end
    elseif state.phase=='kitty' then assert(Practice.autoAct(state,state.kittyHolder or state.dealer,0))
    elseif state.phase=='tricks' then
      if humans[state.turn] then assert(Practice.autoAct(state,state.turn,0)) else assert(Practice.stepBot(state)) end
    else error('Unexpected phase '..tostring(state.phase)) end
  end
end

-- Bots never act for human seats.
for _,count in ipairs({4,6,10}) do
  local humans={[1]=true,[2]=true,[count]=true}
  local state=Practice.new(function(n)return n end,0,{playerCount=count,humans=humans,paced=true})
  assert(Practice.botDeclare(state,2) or true)
  if state.declaration then assert(not humans[state.declaration.seat],'Bots declared for a human seat') end
  while state.phase=='declaration' do assert(Practice.advance(state,state.deadline,function()return 1 end)) end
  local total=0
  for _,c in ipairs(Cards.deck(count)) do total=total+Cards.points(c) end
  settle(state,humans)
  local points=0; for _,c in ipairs(state.kitty) do points=points+Cards.points(c) end
  assert(state.points[1]+state.points[2]+points==total,'Points are conserved')
  for _,hand in ipairs(state.hands) do assert(#hand==0) end
end

-- Practice.bots stops at the next human; autoAct plays for them.
local humans={[1]=true,[3]=true}
local state=Practice.new(function(n)return n end,0,{humans=humans,paced=true})
assert(Practice.advance(state,8,function()return 1 end)); assert(Practice.advance(state,16,function()return 1 end))
while state.phase~='tricks' do
  if state.phase=='chaodi' then
    if humans[state.chaodiTurn] then assert(Practice.autoAct(state,state.chaodiTurn,0)) else assert(Practice.stepChaodiBot(state,0)) end
  else assert(Practice.autoAct(state,state.kittyHolder or state.dealer,0)) end
end
for _=1,6 do
  Practice.bots(state)
  if state.phase=='trick-review' then assert(Practice.nextTrick(state)) end
  assert(humans[state.turn] or state.done,'Bots stop at a human seat')
  assert(not Practice.stepBot(state),'stepBot refuses a human turn')
  local before=#state.hands[state.turn]
  local seat=state.turn
  assert(Practice.autoAct(state,seat,0),'autoAct plays for an idle human')
  assert(#state.hands[seat]<before)
end

-- Views rotate so the viewer is seat 1; team B viewers see their team as A.
local view2=Practice.relativeView(state,2)
local abs=Practice.view(state,2)
assert(#view2.hand==#state.hands[2],'Viewer sees only their own hand')
assert(view2.turn==(state.turn-2)%4+1 and view2.dealer==(state.dealer-2)%4+1)
assert(view2.attackingTeam==(abs.attackingTeam=='A' and 'B' or 'A'),'Team labels flip for team B')
assert(view2.points[1]==state.points[2] and view2.points[2]==state.points[1])
assert(view2.levels.A==state.levels.B and view2.levels.B==state.levels.A)
for i,play in ipairs(state.trick) do assert(view2.trick[i].seat==(play.seat-2)%4+1) end
for i,entry in ipairs(state.history) do assert(view2.history[i].winnerSeat==(entry.winnerSeat-2)%4+1) end
assert(state.trick[1]==nil or state.trick[1].seat==abs.trick[1].seat,'The real state is not modified')
local view3=Practice.relativeView(state,3)
assert(view3.attackingTeam==abs.attackingTeam and view3.points[1]==state.points[1],'Team A viewers keep labels')
assert(view3.turn==(state.turn-3)%4+1)
local view1=Practice.relativeView(state,1)
assert(view1.turn==state.turn and view1.dealer==state.dealer,'Seat 1 sees the unrotated table')
print('PASS: several human seats per table, bots skip human seats, autoAct for idle humans, conservation, rotated views per seat')
