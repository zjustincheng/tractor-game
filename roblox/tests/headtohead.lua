-- Trained bots vs the built-in Roblox heuristics over paired deals: each deal
-- is played twice with the teams swapped. Measures only; not part of CI.
-- Usage: fengari roblox/tests/headtohead.lua <deals> <playerCount>
local Cards=dofile('roblox/src/shared/Cards.luau')
local S=dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules=dofile('roblox/src/shared/PlayRules.luau')(Cards,S)
local Scoring=dofile('roblox/src/shared/Scoring.luau')(Cards)
local Trained=dofile('roblox/src/server/TrainedBots.luau')(Cards,S,Rules,dofile('roblox/src/server/ChampionModel.luau'))
local Practice=dofile('roblox/src/server/Practice.luau')(Cards,S,Rules,Scoring,Trained)
local deals,playerCount=tonumber(arg[1]) or 50,tonumber(arg[2]) or 4
local function rng(seed)
  local value=seed
  return function(n) value=(value*1664525+1013904223)%4294967296; return math.floor(value/4294967296*n)+1 end
end
local function round(seed,team,attacking)
  local pick=rng(seed)
  local level=Cards.ranks[((seed*7)%12)+1]
  local state=Practice.new(pick,0,{playerCount=playerCount,humans={},levels={A=level,B=level},attackingTeam=attacking,round=2,dealer=attacking=='A' and 1 or 2})
  state.trainedSeats={}
  for seat=1,playerCount do state.trainedSeats[seat]=Cards.team(seat)==team end
  Practice.botDeclare(state,3)
  local now=9
  while state.phase=='declaration' do assert(Practice.advance(state,now,pick) or now<100,'stuck'); now=now+9 end
  if state.phase=='blocked' then return nil end
  local steps=0
  while not state.done do
    steps=steps+1; assert(steps<5000,'round stuck in '..state.phase)
    if state.phase=='chaodi' then Practice.stepChaodiBot(state,now)
    elseif state.phase=='trick-review' then assert(Practice.nextTrick(state))
    elseif state.phase=='tricks' then Practice.bots(state)
    elseif state.phase~='finished' then error('unexpected phase '..state.phase) end
  end
  local s=state.settlement
  local advancing=s.outcome.advancingRole=='attackers' and attacking or (attacking=='A' and 'B' or 'A')
  local levels=(advancing==team and 1 or -1)*s.outcome.levels
  local attackers=attacking==team
  return levels, advancing==team, attackers and -s.defenderScore or s.defenderScore
end
local started=os.clock()
local rounds,wins,total,squares,points,skipped=0,0,0,0,0,0
for deal=1,deals do
  local attacking=deal%2==1 and 'A' or 'B'
  local a,awin,ap=round(deal*2654435+17,'A',attacking)
  local b,bwin,bp=round(deal*2654435+17,'B',attacking)
  if a and b then
    local margin=(a+b)/2
    rounds=rounds+2; wins=wins+(awin and 1 or 0)+(bwin and 1 or 0)
    total=total+margin; squares=squares+margin*margin; points=points+(ap+bp)/2
  else skipped=skipped+1 end
end
local pairsPlayed=rounds/2
local mean=total/pairsPlayed
local se=math.sqrt(math.max(0,squares/pairsPlayed-mean*mean)/pairsPlayed)
print(string.format('%dp: %d paired deals (%d blocked), trained won %.1f%% of rounds, level margin %+.3f (95%% CI %+.3f to %+.3f), defender-point margin %+.1f, %.1fs',
  playerCount,pairsPlayed,skipped,100*wins/rounds,mean,mean-1.96*se,mean+1.96*se,points/pairsPlayed,os.clock()-started))
