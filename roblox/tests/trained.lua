-- How the trained bots plug into rounds: which tables use them, public-only
-- context, and that a failure can never stall a table.
local Cards=dofile('roblox/src/shared/Cards.luau')
local S=dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules=dofile('roblox/src/shared/PlayRules.luau')(Cards,S)
local Scoring=dofile('roblox/src/shared/Scoring.luau')(Cards)
local Real=dofile('roblox/src/server/TrainedBots.luau')(Cards,S,Rules,dofile('roblox/src/server/ChampionModel.luau'))
local warnings=0
warn=function() warnings=warnings+1 end
local function rng(seed)
  local value=seed
  return function(n) value=(value*1664525+1013904223)%4294967296; return math.floor(value/4294967296*n)+1 end
end
-- Wraps every decision so the test can count or sabotage them.
local function instrumented(sabotage)
  local calls={lead=0,play=0,burial=0,declaration=0}
  local wrapped=setmetatable({},{__index=Real})
  local function wrap(name,key)
    wrapped[name]=function(...)
      calls[key]=calls[key]+1
      if sabotage then return sabotage(name,...) end
      return Real[name](...)
    end
  end
  wrap('chooseLead','lead'); wrap('choosePlay','play'); wrap('chooseBurial','burial'); wrap('chooseDeclaration','declaration')
  return wrapped,calls
end
local function playRound(Practice,playerCount,seed,inspect)
  local pick=rng(seed)
  local state=Practice.new(pick,0,{playerCount=playerCount,humans={},round=2,dealer=1})
  Practice.botDeclare(state,3)
  local now=9
  while state.phase=='declaration' do assert(Practice.advance(state,now,pick) or now<100); now=now+9 end
  local steps=0
  while not state.done do
    steps=steps+1; assert(steps<5000,'stuck in '..state.phase)
    if state.phase=='chaodi' then Practice.stepChaodiBot(state,now)
    elseif state.phase=='doubling' then assert(Practice.endDoubling(state,now,true))
    elseif state.phase=='trick-review' then assert(Practice.nextTrick(state))
    elseif state.phase=='tricks' then
      if inspect then inspect(state) end
      Practice.stepBot(state)
    end
  end
  return state
end
local function practiceWith(trained) return dofile('roblox/src/server/Practice.luau')(Cards,S,Rules,Scoring,trained) end

-- Four-player tables use the trained bots for every kind of decision.
local bots,calls=instrumented()
local state=playRound(practiceWith(bots),4,11,function(current)
  local seat=current.turn
  local context=Real.leadContext(current,seat)
  local played={}
  for _,item in ipairs(current.history) do for _,play in ipairs(item.plays) do for _,c in ipairs(play.cards) do played[c.id]=true end end end
  for _,c in ipairs(context.seenCards) do assert(played[c.id],'The policy only sees cards already played') end
  assert(context.cardsRemaining==#current.hands[seat] and context.otherHands==nil)
end)
assert(state.done and calls.lead>0 and calls.play>calls.lead and calls.burial>=1 and warnings==0)
assert(calls.lead+calls.play>=#state.history*4,'Every trained seat decides with the model')

-- Trained at four players and better than the old bots at six; eight and ten
-- keep the old bots.
local six,six_calls=instrumented()
assert(playRound(practiceWith(six),6,5,nil).done)
assert(six_calls.lead>0 and six_calls.play>0,'6-player tables use the trained model')
for _,count in ipairs({8,10}) do
  local larger,larger_calls=instrumented()
  assert(playRound(practiceWith(larger),count,5,nil).done)
  assert(larger_calls.lead==0 and larger_calls.play==0 and larger_calls.burial==0 and larger_calls.declaration==0,'Only 4- and 6-player tables use the trained model')
end

-- Without the module (and for seats in an override) the old bots still play.
assert(playRound(practiceWith(nil),4,7,nil).done)

-- Crashes and illegal answers fall back for that decision; the round finishes.
local crashing,crash_calls=instrumented(function() error('boom') end)
warnings=0
assert(playRound(practiceWith(crashing),4,13,nil).done and crash_calls.lead>0 and warnings>0,'A crashing model falls back to heuristics')
local illegal,illegal_calls=instrumented(function(name,...)
  if name=='chooseLead' or name=='choosePlay' then return {'not-a-card'} end
  return Real[name](...)
end)
warnings=0
assert(playRound(practiceWith(illegal),4,17,nil).done and illegal_calls.play>0 and warnings>0,'An illegal choice falls back to heuristics')
print('PASS: trained bots: 4- and 6-player tables, public context, every decision type, crash and illegal-move fallback')
