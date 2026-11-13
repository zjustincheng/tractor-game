local Cards=dofile('roblox/src/shared/Cards.luau')
local S=dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules=dofile('roblox/src/shared/PlayRules.luau')(Cards,S)
local Scoring=dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice=dofile('roblox/src/server/Practice.luau')(Cards,S,Rules,Scoring)
local fixtures=dofile(arg[1])
local function equal(actual,expected,path)
  path=path or 'value'
  assert(type(actual)==type(expected),path .. ': type ' .. type(actual) .. ' ~= ' .. type(expected))
  if type(actual)~='table' then assert(actual==expected,path .. ': ' .. tostring(actual) .. ' ~= ' .. tostring(expected)); return end
  for k,v in pairs(expected) do equal(actual[k],v,path .. '.' .. k) end
  for k in pairs(actual) do assert(expected[k]~=nil,path .. ': unexpected key ' .. k) end
end
for i,f in ipairs(fixtures.declarations) do
  local state={phase='declaration',trump=f.trump,hands=f.hands,playerCount=f.playerCount}
  -- Roblox also allows joker pairs and calls above the website's size cap.
  local actual={}
  local minimum=f.playerCount==4 and 3 or 4
  for _,o in ipairs(Practice.options(state,1)) do if not (o.joker and (o.count==2 or o.count>minimum)) then table.insert(actual,o) end end
  equal(actual,f.expected,'declaration '..i)
end
for i,f in ipairs(fixtures.structures) do equal(S.decompose(f.cards,f.trump),f.expected,'structure' .. i) end
for i,f in ipairs(fixtures.follows) do
  local r=Rules.follow(f.hand,f.played,f.lead,f.trump)
  equal(r.legal and {legal=true,matchesLead=r.matchesLead} or {legal=false,code=r.code},f.expected,'follow' .. i)
end
for i,f in ipairs(fixtures.gambles) do equal(Rules.gamble(f.components,f.otherHands,f.trump,f.role),f.expected,'gamble' .. i) end
for i,f in ipairs(fixtures.winners) do equal(Rules.winning(f.cards,f.lead,f.current,f.trump),f.expected,'winner' .. i) end
for i,f in ipairs(fixtures.settlements) do equal(Scoring.settle(f.input),f.expected,'settlement' .. i) end
-- Chao Di port used by training (backend/src/training/roblox-rules.ts).
local chaodiCalls=0
for i,f in ipairs(fixtures.chaodi) do
  local hands={}; for seat=1,f.playerCount do hands[seat]={} end; hands[1]=f.hand
  local state={phase='chaodi',hands=hands,trump=f.trump,declaration=f.current,playerCount=f.playerCount,kittyHolder=f.holder,dealer=f.holder}
  equal(Practice.chaodiOptions(state,1),f.expectedOptions,'chaodi options '..i)
  equal(Practice.chooseChaodi(state,1) or 0,f.expectedChoice,'chaodi choice '..i)
  if f.expectedChoice>0 then chaodiCalls=chaodiCalls+1 end
end
local total=0
for i,f in ipairs(fixtures.rounds) do
  local state=Practice.new(function(n)return n end,0,{playerCount=f.playerCount,levels={A=f.trump.level,B="2"}})
  state.quickMatch=f.quickMatch
  state.hands,state.kitty,state.trump,state.phase,state.dealer=f.hands,f.kitty,f.trump,'tricks',1
  for index,command in ipairs(f.commands) do
    if state.phase=='trick-review' then assert(Practice.nextTrick(state)) end
    local ok,message=Practice.play(state,command.seat,command.ids)
    assert(ok,'round '..i..' command '..index..': '..tostring(message))
    local expected=command.expected
    local hands={}
    for seat,hand in ipairs(state.hands) do hands[seat]={}; for _,c in ipairs(hand) do table.insert(hands[seat],c.id) end end
    equal(hands,expected.hands,'round hands '..i..':'..index)
    equal(state.points,expected.points,'round points')
    equal(state.penaltyPoints,expected.penaltyPoints,'penalty')
    equal(state.winnerSeat or state.lastWinnerSeat,expected.winnerSeat,'winner seat')
    local trick=#state.trick>0 and state.trick or state.lastTrick
    local ids={};for _,c in ipairs(trick[#trick].cards) do table.insert(ids,c.id) end
    equal(ids,expected.played,'actual cards')
    equal(message~=nil,expected.reduced,'gamble reduced')
    total=total+1
  end
  assert(state.done and state.phase=='finished')
  equal(state.settlement,f.settlement,'round settlement '..i)
end
-- Trained-bot port. The weights file is checked against the checkpoint too.
local Model=dofile('roblox/src/server/ChampionModel.luau')
local Trained=dofile('roblox/src/server/TrainedBots.luau')(Cards,S,Rules,Model)
local function sameOptions(actual,expected,path)
  assert(#actual==#expected,path..': '..#actual..' options, expected '..#expected)
  for i,want in ipairs(expected) do
    equal(actual[i].cardIds,want.ids,path..' option '..i)
    assert(math.abs(actual[i].prior-want.prior)<1e-9,path..' prior '..i)
    for j=1,37 do
      local have,goal=actual[i].features[j] or 0,want.features[j] or 0
      assert(math.abs(have-goal)<1e-9,path..' option '..i..' feature '..(j-1)..': '..have..' ~= '..goal)
    end
  end
end
local function sameCards(cards,ids,path)
  local have={}
  for _,c in ipairs(cards) do table.insert(have,c.id) end
  local want={table.unpack(ids)}
  table.sort(have); table.sort(want)
  equal(have,want,path)
end
local policy,champions=fixtures.policy,0
local function matchesChampion(actual,expected,path)
  if fixtures.policy.champion then equal(actual,expected,path); champions=champions+1 end
end
if policy.champion then
  for _,name in ipairs({'lead','follow'}) do
    local want,have=policy.champion[name],Model[name]
    assert(have.priorScale==want.priorScale,'champion prior')
    for u=1,16 do
      assert(have.bias[u]==want.bias[u] and have.output[u]==want.output[u],'champion unit '..u)
      for j=1,#want.input[u] do assert(have.input[u][j]==want.input[u][j],'champion weight '..u..':'..j) end
    end
  end
end
for i,f in ipairs(policy.leads) do
  sameOptions(Trained.leadOptions(f.hand,f.trump,f.context),f.options,'lead '..i)
  equal(Trained.chooseLead(f.hand,f.trump,f.context,f.models),f.expected,'lead choice '..i)
  matchesChampion(Trained.chooseLead(f.hand,f.trump,f.context),f.champion,'champion lead '..i)
  sameCards(Rules.choose(f.hand,nil,f.trump,f.context),f.roblox,'roblox lead '..i)
end
for i,f in ipairs(policy.chaodi or {}) do
  sameOptions(Trained.chaodiOptions(f.calls,f.hand,f.trump,f.sameTeam,f.heuristic),f.options,'chaodi policy '..i)
  equal(Trained.chooseChaodi(f.calls,f.hand,f.trump,f.sameTeam,f.heuristic,f.models) or 0,f.expected,'chaodi policy choice '..i)
end
for i,f in ipairs(policy.plays) do
  sameOptions(Trained.playOptions(f.hand,f.lead,f.trump,f.context),f.options,'play '..i)
  equal(Trained.choosePlay(f.hand,f.lead,f.trump,f.context,f.models),f.expected,'play choice '..i)
  matchesChampion(Trained.choosePlay(f.hand,f.lead,f.trump,f.context),f.champion,'champion play '..i)
  sameCards(Rules.choose(f.hand,f.lead,f.trump,{seat=f.context.seat,winnerSeat=f.context.winnerSeat,winningComponents=f.context.winning,lastToPlay=f.context.lastToPlay}),f.roblox,'roblox follow '..i)
end
for i,f in ipairs(policy.burials) do
  equal(Trained.baselineBurial(f.cards,f.size,f.trump),f.baseline,'burial baseline '..i)
  equal(Trained.chooseBurial(f.cards,f.size,f.trump,f.models),f.expected,'burial '..i)
  matchesChampion(Trained.chooseBurial(f.cards,f.size,f.trump),f.champion,'champion burial '..i)
  sameCards(Rules.chooseBurial(f.cards,f.size,f.trump),f.roblox,'roblox burial '..i)
end
for i,f in ipairs(policy.declarations) do
  local function index(chosen) for n,o in ipairs(f.options) do if o==chosen then return n end end return 0 end
  equal(index(Trained.chooseDeclaration(f.options,f.hand,f.level,f.models)),f.expected,'declaration choice '..i)
  matchesChampion(index(Trained.chooseDeclaration(f.options,f.hand,f.level)),f.champion,'champion declaration '..i)
end
print('PASS: trained bot port: '..#(policy.chaodi or {})..' Chao Di decisions, '..#policy.leads..' leads, '..#policy.plays..' follows, '..#policy.burials..' burials, '..#policy.declarations..' declarations; '..champions..' champion choices')
print('PASS: website/native parity: '..#fixtures.chaodi..' Chao Di hands ('..chaodiCalls..' calls), '..#fixtures.declarations..' declaration sets, '..#fixtures.structures..' structures, '..#fixtures.follows..' follows, '..#fixtures.gambles..' gambles, '..#fixtures.winners..' winners, '..#fixtures.settlements..' settlements, '..#fixtures.rounds..' complete rounds / '..total..' commands')
