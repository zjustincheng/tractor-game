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
  -- Where `points` sits on the Ranked ladder. Every tier below the top splits
  -- into three divisions, III then II then I; the top tier is one step.
  -- `step` counts from 1 (Bronze III) to the top tier.
  local NUMERALS = { 'I', 'II', 'III' }
  function Scoring.rankStanding(points, ranks)
    points = math.max(0, points or 0)
    local index = 1
    for position, tier in ipairs(ranks) do if points >= tier.at then index = position end end
    local tier, nextTier = ranks[index], ranks[index + 1]
    if not nextTier then
      return { tier = tier.name, tierIndex = index, step = (index - 1) * 3 + 1, label = tier.name, floor = tier.at }
    end
    local width = nextTier.at - tier.at
    local part = math.min(2, math.floor((points - tier.at) * 3 / width))
    return { tier = tier.name, tierIndex = index, division = 3 - part, step = (index - 1) * 3 + part + 1,
      label = tier.name .. ' ' .. NUMERALS[3 - part], floor = tier.at + math.ceil(width * part / 3),
      nextAt = part < 2 and tier.at + math.ceil(width * (part + 1) / 3) or nextTier.at }
  end
  function Scoring.rankStepLabel(step, ranks)
    local index = math.min(#ranks, math.ceil(step / 3))
    if index == #ranks then return ranks[index].name end
    return ranks[index].name .. ' ' .. NUMERALS[3 - (step - 1) % 3]
  end
  -- The Ranked season number at `now` (1 for the first `days` after `start`)
  -- and the time it ends.
  function Scoring.rankSeason(now, config)
    local length = (config.days or 30) * 86400
    local index = math.max(0, math.floor((now - (config.start or 0)) / length))
    return index + 1, (config.start or 0) + (index + 1) * length
  end
  -- Ranked Points for one round. `margin` is the round's payout grade (1-4):
  -- a narrow hold or overturn is 1, a shutout or a big overturn is 4, so a
  -- more decisive win earns more and a heavier loss costs more:
  --   against people   win +150 / +200 / +250 / +300   loss -50 / -75 / -100 / -125
  --   against bots     win  +75 / +100 / +125 / +150   loss -25 / -35 / -45 / -55
  -- With 400 RP divisions a typical player moves up one in about five games.
  -- Bot-only games stop counting at `botCap`, in both directions; a human
  -- opponent always counts. Below `safeBelow` (Bronze) a loss costs nothing.
  -- Returns the change and whether the bot cap held it at zero.
  function Scoring.rankDelta(before, won, vsPeople, margin, botCap, safeBelow)
    margin = math.max(1, math.min(4, margin or 1))
    if not vsPeople and before >= botCap then return 0, true end
    if won then
      if vsPeople then return 100 + 50 * margin, false end
      return math.min(50 + 25 * margin, botCap - before), false
    end
    if before < (safeBelow or 100) then return 0, false end
    return vsPeople and -(25 + 25 * margin) or -(15 + 10 * margin), false
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
