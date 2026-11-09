-- Pure port of follow.ts/gamble.ts plus the website's deterministic legal bot baseline.
return function(Cards, S)
  local Rules = {}
  local function suited(cards, category, trump)
    local result = {}; for _, card in ipairs(cards) do if Cards.category(card,trump) == category then table.insert(result,card) end end; return result
  end
  local function profile(cards, lead, protect)
    local maximum, groups, result, used = 1, {}, {}, 0
    for _, c in ipairs(lead) do maximum = math.max(maximum,c.multiplicity) end
    for _, group in ipairs(S.groups(cards)) do table.insert(groups,{initial=#group,left=#group}) end
    for tier = maximum,2,-1 do
      local budget = -used
      for _, c in ipairs(lead) do if c.multiplicity >= tier then budget = budget + c.cardCount end end
      local capacity, count = math.floor(budget/tier), 0
      for _, group in ipairs(groups) do
        if not protect or group.initial <= tier then
          local take = math.min(capacity,math.floor(group.left/tier))
          group.left, capacity, count = group.left-take*tier, capacity-take, count+take
        end
      end
      used = used + count*tier; table.insert(result,count)
    end
    return result
  end
  -- Roblox house rule: four of a kind beats a 4-card tractor (two consecutive pairs).
  local function isFourCardTractor(lead) return #lead == 1 and lead[1].multiplicity == 2 and lead[1].rankCount == 2 end
  local function asQuad(cards, trump)
    local component = #cards == 4 and S.homogeneous(cards, trump) or nil
    if not component or component.multiplicity ~= 4 or component.rankCount ~= 1 then return nil end
    component.cards = cards
    return component
  end
  function Rules.follow(hand, played, lead, trump)
    local count = S.count(lead)
    if #played ~= count then return {legal=false,code='WRONG_CARD_COUNT',message='Play exactly ' .. count .. ' cards.'} end
    local owned, seen = {}, {}
    for _, c in ipairs(hand) do owned[c.id] = S.identity(c) end
    for _, c in ipairs(played) do
      if seen[c.id] or owned[c.id] ~= S.identity(c) then return {legal=false,code='INVALID_CARDS',message='Choose distinct cards from your hand.'} end
      seen[c.id] = true
    end
    local category = lead[1].category
    local suitedHand, suitedPlay = suited(hand,category,trump), suited(played,category,trump)
    if #suitedPlay ~= math.min(#suitedHand,count) then
      return {legal=false,code='MUST_FOLLOW_SUIT',message='Use ' .. math.min(#suitedHand,count) .. ' cards from the led category before playing other cards.'}
    end
    local uniform = true
    for _, c in ipairs(played) do if Cards.category(c,trump) ~= Cards.category(played[1],trump) then uniform = false end end
    local components = uniform and S.match(played,lead,trump,{requireAllCards=true}) or nil
    if not components and uniform and isFourCardTractor(lead) then
      local quad = asQuad(played,trump)
      if quad then components = {quad} end
    end
    if #suitedHand >= count and S.match(suitedHand,lead,trump,{protectLargerSets=true}) and not components then
      return {legal=false,code='MUST_MATCH_STRUCTURE',message='Your hand can match the complete led structure. Play a matching structure.'}
    end
    if #suitedHand > count and not components then
      local required, supplied = profile(suitedHand,lead,true), profile(suitedPlay,lead,false)
      for i = 1,#required do
        if supplied[i] > required[i] then break end
        if supplied[i] < required[i] then return {legal=false,code='MUST_PLAY_SETS',message='Include the available sets in the led category before filling with singles.'} end
      end
    end
    local matches = components ~= nil and (Cards.category(played[1],trump) == category or (#suitedHand == 0 and Cards.category(played[1],trump) == 'trump'))
    return {legal=true,matchesLead=matches,components=matches and components or nil}
  end
  function Rules.gamble(components, otherHands, trump, role)
    local cards, beatable = S.flatten(components), {}
    if #components > 1 then
      for _, c in ipairs(components) do
        local beaten = false
        for _, hand in ipairs(otherHands) do
          for _, candidate in ipairs(S.available(suited(hand,c.category,trump),trump,c)) do
            if candidate.highestPower > c.highestPower then beaten = true; break end
          end
          if beaten then break end
        end
        if beaten then table.insert(beatable,c) end
      end
    end
    table.sort(beatable,function(a,b)
      if a.multiplicity ~= b.multiplicity then return a.multiplicity < b.multiplicity end
      if a.highestPower ~= b.highestPower then return a.highestPower < b.highestPower end
      return S.key(a) < S.key(b)
    end)
    if #beatable == 0 then return {reduced=false,components=components,cards=cards,returned={},penalty=0} end
    local weakest = beatable[1]
    return {reduced=true,components={weakest},cards=weakest.cards,returned=S.without(cards,weakest.cards),penalty=role == 'attackers' and 20 or -20}
  end
  local function shapeKey(c) return c.multiplicity .. ':' .. c.rankCount end
  local function keys(components, strength)
    local result = {}; for _, c in ipairs(components) do table.insert(result,shapeKey(c) .. (strength and ':' .. c.highestPower or '')) end
    table.sort(result); return table.concat(result,'|')
  end
  function Rules.beats(challenger,current)
    if #challenger == 0 or #current == 0 or keys(challenger,false) ~= keys(current,false) then return false end
    local category, previous = challenger[1].category, current[1].category
    for _, c in ipairs(challenger) do if c.category ~= category then return false end end
    for _, c in ipairs(current) do if c.category ~= previous then return false end end
    if category ~= previous then return category == 'trump' end
    if keys(challenger,true) == keys(current,true) then return false end
    for _, c in ipairs(challenger) do for _, old in ipairs(current) do
      if S.sameShape(c,old) and c.highestPower > old.highestPower then return true end
    end end
    return false
  end
  function Rules.winning(cards,lead,current,trump)
    if isFourCardTractor(lead) then
      local quad = asQuad(cards,trump)
      if quad then
        local held = current[1]
        if #current ~= 1 then return nil end
        if held.category ~= quad.category and quad.category ~= 'trump' then return nil end
        -- A tractor falls to any quad; a quad only to a higher one or to trump.
        if held.multiplicity == 4 and held.category == quad.category and quad.highestPower <= held.highestPower then return nil end
        return {quad}
      end
    end
    local first = S.match(cards,lead,trump,{requireAllCards=true})
    if not first then return nil end
    if Rules.beats(first,current) then return first end
    local function powers(items)
      local result = {}; for _, c in ipairs(items) do table.insert(result,Cards.category(c,trump) .. ':' .. Cards.power(c,trump)) end
      table.sort(result); return table.concat(result,'|')
    end
    if powers(cards) == powers(S.flatten(current)) then return nil end
    return S.match(cards,lead,trump,{requireAllCards=true,mustBeat=current})
  end
  -- Deterministic legal bot baseline
  function Rules.baseline(hand, lead, trump)
    local ordered = {}; for _, c in ipairs(hand) do table.insert(ordered, c) end
    table.sort(ordered, function(a, b)
      local at, bt = Cards.category(a, trump) == 'trump', Cards.category(b, trump) == 'trump'
      if at ~= bt then return not at end
      local ap, bp = Cards.power(a, trump), Cards.power(b, trump)
      if ap ~= bp then return ap < bp end
      return a.id < b.id
    end)
    if not lead then return S.available(ordered, trump)[1].cards end
    local count, selected = S.count(lead), {}
    local matching = suited(ordered, lead[1].category, trump)
    if #matching <= count then
      for _, c in ipairs(matching) do table.insert(selected, c) end
      local rest = S.without(ordered, matching)
      for i = 1, count - #matching do table.insert(selected, rest[i]) end
    else
      local full = S.match(matching, lead, trump, { protectLargerSets = true })
      if full then selected = S.flatten(full)
      else
        local groups, maximum = {}, 1
        for index, group in ipairs(S.groups(matching)) do table.insert(groups, { cards = group, initial = #group, index = index }) end
        for _, c in ipairs(lead) do maximum = math.max(maximum, c.multiplicity) end
        for tier = maximum, 2, -1 do
          local budget = -#selected
          for _, c in ipairs(lead) do if c.multiplicity >= tier then budget = budget + c.cardCount end end
          local capacity = math.floor(budget / tier)
          for _, group in ipairs(groups) do
            if group.initial <= tier then
              local take = math.min(capacity, math.floor(#group.cards / tier))
              for _ = 1, take * tier do table.insert(selected, table.remove(group.cards, 1)) end
              capacity = capacity - take
            end
          end
        end
        table.sort(groups, function(a, b) if a.initial ~= b.initial then return a.initial < b.initial end; return a.index < b.index end)
        for _, group in ipairs(groups) do for _, c in ipairs(group.cards) do if #selected < count then table.insert(selected, c) end end end
      end
    end
    assert(Rules.follow(hand, selected, lead, trump).legal, 'Bot generated an illegal response')
    return selected
  end

  -- Intelligent Dealer Kitty Burial: voids short suits, preserves trumps and pairs
  function Rules.chooseBurial(cards, size, trump)
    local counts = {}
    for _, card in ipairs(cards) do
      local cat = Cards.category(card, trump)
      counts[cat] = (counts[cat] or 0) + 1
    end
    local groups = S.groups(cards)
    local isMultiple = {}
    for _, group in ipairs(groups) do
      if #group >= 2 then
        for _, c in ipairs(group) do isMultiple[c.id] = true end
      end
    end

    local scored = {}
    for _, card in ipairs(cards) do
      local cat = Cards.category(card, trump)
      local isTrump = (cat == 'trump')
      local pts = Cards.points(card)
      local pow = Cards.power(card, trump)
      local suitCount = counts[cat] or 0
      local score = 0

      if isTrump then
        score = score + 50000
        if card.joker then score = score + 100000 end
      else
        -- Strongly prefer voiding short side suits (1 or 2 cards in hand)
        if suitCount <= 2 then
          score = score - 4000
        elseif suitCount <= 4 then
          score = score - 1500
        else
          score = score + 500
        end

        -- Protect pairs unless entire short suit is being voided
        if isMultiple[card.id] and suitCount > 2 then
          score = score + 3000
        end

        -- Point cards: 5, 10, K
        if pts > 0 then
          if suitCount <= 2 then
            score = score + 200
          else
            score = score + 1800
          end
        end

        -- High cards (A, K, Q) are better retained
        score = score + pow * 50
      end

      table.insert(scored, { card = card, score = score })
    end

    table.sort(scored, function(a, b)
      if a.score ~= b.score then return a.score < b.score end
      return a.card.id < b.card.id
    end)

    local result = {}
    for i = 1, math.min(size, #scored) do
      table.insert(result, scored[i].card)
    end
    return result
  end

  -- Intelligent Trick Lead: leads tractors, boss pairs, and side-suit Aces
  function Rules.chooseLead(hand, trump, context)
    local comps = S.available(hand, trump)
    if #comps == 0 then return {} end

    local scored = {}
    for _, c in ipairs(comps) do
      local isTrump = (c.category == 'trump')
      local pts = 0
      for _, card in ipairs(c.cards) do pts = pts + Cards.points(card) end
      local highestPow = c.highestPower
      local score = 0

      if c.rankCount > 1 and c.multiplicity >= 2 then
        -- Tractors: dominant leads!
        score = score + 2500 + c.cardCount * 200 + highestPow * 20
      elseif c.multiplicity >= 2 then
        -- Pairs
        if not isTrump then
          if highestPow >= 10 then
            score = score + 1500 + highestPow * 30 -- Boss pairs (AA, KK)
          else
            score = score + 600 + highestPow * 15
          end
        else
          score = score + 800 + highestPow * 20
        end
      else
        -- Singles
        if not isTrump then
          if highestPow >= 12 then
            -- Ace of a side suit! Excellent opening lead
            score = score + 1800
          elseif pts > 0 and highestPow < 10 then
            -- Loose 5 or 10 single: avoid leading into opponents
            score = score - 800
          else
            score = score + highestPow * 15
          end
        else
          if c.cards[1] and c.cards[1].joker then
            score = score + 700 -- Big/Small Joker lead to pull trumps
          else
            score = score - 400 -- preserve small trumps
          end
        end
      end

      table.insert(scored, { comp = c, score = score })
    end

    table.sort(scored, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      return S.key(a.comp) < S.key(b.comp)
    end)

    return scored[1].comp.cards
  end

  -- Tactical Follow matching full Shengji partner coordination
  function Rules.tacticalFollow(hand, baseline, lead, trump, context)
    if not context then return baseline end
    local candidates = { baseline }
    local ledCat = lead[1].category
    local matching = suited(hand, ledCat, trump)
    local count = S.count(lead)

    -- If void in led suit:
    if #matching == 0 then
      if count == 1 then
        for _, c in ipairs(hand) do table.insert(candidates, { c }) end
      else
        local trumps = suited(hand, 'trump', trump)
        if #trumps >= count then
          local ruffMatch = S.match(trumps, lead, trump, { protectLargerSets = true })
          if ruffMatch then
            table.insert(candidates, S.flatten(ruffMatch))
          end
        end
      end
    else
      if count == 1 then
        for _, c in ipairs(matching) do table.insert(candidates, { c }) end
      else
        local fullMatch = S.match(matching, lead, trump, { protectLargerSets = false })
        if fullMatch then
          table.insert(candidates, S.flatten(fullMatch))
        end
      end
    end

    local isPartnerWinning = false
    if context.winnerSeat and context.seat then
      isPartnerWinning = (Cards.team(context.winnerSeat) == Cards.team(context.seat))
    end

    local currentWinningComps = context.winningComponents
    local lastToPlay = context.lastToPlay == true

    local function scoreCandidate(cards)
      local follow = Rules.follow(hand, cards, lead, trump)
      if not follow.legal then return { 999999, 999999, 999999 } end
      local wins = follow.matchesLead and currentWinningComps and Rules.winning(cards, lead, currentWinningComps, trump) ~= nil
      local pts = 0
      for _, c in ipairs(cards) do pts = pts + Cards.points(c) end
      local strength = 0
      for _, c in ipairs(cards) do
        strength = strength + Cards.power(c, trump)
        if Cards.category(c, trump) == 'trump' then strength = strength + 30 end
        if c.joker then strength = strength + (c.joker == 'big' and 200 or 100) end
      end

      if isPartnerWinning then
        -- Partner is winning!
        -- If last to play, dump maximum points on partner (-pts comes first)
        if lastToPlay then
          return { -pts, wins and 1 or 0, strength }
        else
          return { -pts * 2, wins and 1 or 0, strength }
        end
      else
        -- Opponent is winning!
        if wins then
          -- Win with minimum strength necessary!
          return { 0, strength, -pts }
        else
          -- Cannot win: shed least points possible, then least strength
          return { 1, pts * 100 + strength, strength }
        end
      end
    end

    table.sort(candidates, function(a, b)
      local sa = scoreCandidate(a)
      local sb = scoreCandidate(b)
      for i = 1, 3 do
        if sa[i] ~= sb[i] then return sa[i] < sb[i] end
      end
      local idA = {}; for _, c in ipairs(a) do table.insert(idA, c.id) end; table.sort(idA)
      local idB = {}; for _, c in ipairs(b) do table.insert(idB, c.id) end; table.sort(idB)
      return table.concat(idA, '|') < table.concat(idB, '|')
    end)

    return candidates[1]
  end

  -- Extracts public trick context for tactical decision-making
  function Rules.playContext(state, seat)
    if not state then return nil end
    seat = seat or 1
    local trick = state.trick or {}
    local lead = trick[1] and trick[1].components
    local trickPoints = 0
    for _, play in ipairs(trick) do
      for _, c in ipairs(play.cards) do trickPoints = trickPoints + Cards.points(c) end
    end
    local winnerSeat = state.winnerSeat
    local currentWinningPlay = nil
    if winnerSeat then
      for _, play in ipairs(trick) do
        if play.seat == winnerSeat then currentWinningPlay = play; break end
      end
    elseif #trick > 0 then
      winnerSeat = trick[1].seat
      currentWinningPlay = trick[1]
      for i = 2, #trick do
        local play = trick[i]
        if play.matchesLead and currentWinningPlay.components and Rules.winning(play.cards, lead, currentWinningPlay.components, state.trump) then
          winnerSeat = play.seat
          currentWinningPlay = play
        end
      end
    end
    local playerCount = state.playerCount or 4
    local lastToPlay = (#trick == playerCount - 1)
    return {
      seat = seat,
      winnerSeat = winnerSeat,
      winningComponents = currentWinningPlay and currentWinningPlay.components,
      trickPoints = trickPoints,
      lastToPlay = lastToPlay,
      playerCount = playerCount,
      dealer = state.dealer,
      attackingTeam = state.attackingTeam,
    }
  end

  -- Unified decision entry point: preserves baseline when no context passed
  function Rules.choose(hand, lead, trump, context)
    if not lead then
      if context then
        return Rules.chooseLead(hand, trump, context)
      end
      local ordered = {}; for _, c in ipairs(hand) do table.insert(ordered, c) end
      table.sort(ordered, function(a, b)
        local at, bt = Cards.category(a, trump) == 'trump', Cards.category(b, trump) == 'trump'
        if at ~= bt then return not at end
        local ap, bp = Cards.power(a, trump), Cards.power(b, trump)
        if ap ~= bp then return ap < bp end
        return a.id < b.id
      end)
      return S.available(ordered, trump)[1].cards
    end

    local baseline = Rules.baseline(hand, lead, trump)
    if context then
      return Rules.tacticalFollow(hand, baseline, lead, trump, context)
    end
    return baseline
  end
  return Rules
end
