-- Pure settlement port: scoring.ts, including kitty multiplier and J checkpoint/reset.
return function(Cards)
  local Scoring = {}
  function Scoring.outcome(playerCount, score)
    local interval = 20*(playerCount/2)
    if score <= 0 then return {advancingRole='attackers',levels=3,swapRoles=false} end
    if score < interval then return {advancingRole='attackers',levels=2,swapRoles=false} end
    if score < 2*interval then return {advancingRole='attackers',levels=1,swapRoles=false} end
    return {advancingRole='defenders',levels=math.floor(score/interval)-2,swapRoles=true}
  end
  -- Coin payout grade (not part of the website rules). Attackers earn more for
  -- holding defenders low; defenders earn one more step for every interval
  -- past the overturn line (80/120/160/200/240… with four players), unbounded.
  function Scoring.payoutGrade(role, score, playerCount)
    local interval = 20*(playerCount/2)
    if role == 'attackers' then
      if score <= 0 then return 4, '大光 (Total Shutout)' end
      if score < interval then return 2, '小光 (Near Shutout)' end
      return 1, '保庄 (Dealer Defended)'
    end
    local steps = math.max(0, math.floor((score - 2*interval)/interval))
    local grade = 1 + steps
    if steps == 0 then return grade, '破庄 (Overturn)' end
    return grade, '闲家 +' .. steps .. ' (Challengers ×' .. grade .. ')'
  end
  function Scoring.advance(level, steps)
    local start, jack = 1,10
    for i, rank in ipairs(Cards.ranks) do if rank == level then start=i end; if rank=='J' then jack=i end end
    local target = math.min(start+steps,start<jack and jack or #Cards.ranks)
    return {level=Cards.ranks[target],wonMatch=Cards.ranks[target]=='A'}
  end
  function Scoring.settle(input)
    local defenders = input.attackingTeam == 'A' and 'B' or 'A'
    local base = 0; for _, c in ipairs(input.kitty) do base=base+Cards.points(c) end
    local multiplier = input.finalTrickWinnerTeam == defenders and input.finalWinningStructure and input.finalWinningStructure.cardCount*2 or 0
    local score = input.trickPoints + base*multiplier + (input.gamblePenaltyPoints or 0)
    local outcome = Scoring.outcome(input.playerCount,score)
    local levels = {A=input.levels.A,B=input.levels.B}
    local advancing = outcome.advancingRole=='attackers' and input.attackingTeam or defenders
    local advancement = Scoring.advance(levels[advancing],outcome.levels)
    levels[advancing] = advancement.level
    local jackOnly = #input.finalWinningCards>0
    for _, c in ipairs(input.finalWinningCards) do if c.joker or c.rank~='J' then jackOnly=false end end
    local reset = input.finalTrickWinnerTeam==defenders and input.levels[input.attackingTeam]=='J'
      and score>=input.playerCount*20 and input.finalWinningStructure~=nil
      and input.finalWinningStructure.cardCount==#input.finalWinningCards and jackOnly
    if reset then levels[input.attackingTeam]='2' end
    return {defenderScore=score,kittyBasePoints=base,kittyMultiplier=multiplier,kittyPoints=base*multiplier,
      outcome=outcome,levels=levels,attackingTeam=outcome.swapRoles and defenders or input.attackingTeam,
      rolesSwapped=outcome.swapRoles,jackReset=reset,winner=advancement.wonMatch and advancing or nil}
  end
  return Scoring
end
