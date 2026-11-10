-- Port of backend/src/training/learned-policy.ts inference and the website
-- heuristics it uses as its baseline (packages/rules/src/bot.ts). Roblox's own
-- PlayRules heuristics are a different bot, so they are not reused here.
-- Uses only the bot's hand and public table state. Server-only: the weights
-- never reach clients. tests/parity.mjs checks this against the TypeScript.
return function(Cards, S, Rules, Model)
  local Trained = {}
  local BASELINE_PRIOR = 0.35
  local STYLE_INPUTS, CONTESTED_POINTS, SMALL_POWER, ENDGAME_CARDS = 33, 10, 7, 4

  local function isTrump(card, trump) return Cards.category(card, trump) == 'trump' end
  local function number(value) return value and 1 or 0 end
  local function idsOf(cards)
    local ids = {}
    for _, card in ipairs(cards) do table.insert(ids, card.id) end
    return ids
  end
  local function sortedKey(ids)
    local copy = table.clone and table.clone(ids) or { table.unpack(ids) }
    table.sort(copy)
    return table.concat(copy, '|')
  end
  local function pointsOf(cards)
    local total = 0
    for _, card in ipairs(cards) do total = total + Cards.points(card) end
    return total
  end
  local function powerOf(cards, trump)
    local total = 0
    for _, card in ipairs(cards) do total = total + Cards.power(card, trump) end
    return total
  end
  local function filter(cards, keep)
    local result = {}
    for _, card in ipairs(cards) do if keep(card) then table.insert(result, card) end end
    return result
  end
  local function inCategory(cards, category, trump)
    return filter(cards, function(card) return Cards.category(card, trump) == category end)
  end
  local function selectIds(cards, ids)
    local wanted = {}
    for _, id in ipairs(ids) do wanted[id] = true end
    return filter(cards, function(card) return wanted[card.id] end)
  end
  local function count(cards, keep)
    return #filter(cards, keep)
  end
  local function isBig(card) return card.joker == 'big' end
  local function isSmall(card) return card.joker == 'small' end
  local function isJoker(card) return card.joker ~= nil end
  local function allAces(cards)
    return count(cards, function(card) return card.rank == 'A' and not card.joker end) == #cards
  end
  -- Lua's sort is unstable; these keep JavaScript's stable order on ties.
  local function stableSort(items, compare)
    local tagged = {}
    for index, item in ipairs(items) do tagged[index] = { item = item, index = index } end
    table.sort(tagged, function(a, b)
      local order = compare(a.item, b.item)
      if order ~= 0 then return order < 0 end
      return a.index < b.index
    end)
    local result = {}
    for index, entry in ipairs(tagged) do result[index] = entry.item end
    return result
  end
  local function byText(a, b) return a == b and 0 or (a < b and -1 or 1) end
  local function distinctSeats(voids, keep)
    local seats, total = {}, 0
    for _, entry in ipairs(voids) do
      if keep(entry) and not seats[entry.seat] then seats[entry.seat], total = true, total + 1 end
    end
    return total
  end

  -- Play-style rules from backend/src/training/play-style.ts --------------------
  local function isHighTrumpSingle(cards, trump)
    return #cards == 1 and isTrump(cards[1], trump) and (cards[1].joker ~= nil or cards[1].rank == trump.level)
  end
  local function isSideAce(cards, trump)
    for _, card in ipairs(cards) do
      if card.joker or card.rank ~= 'A' or isTrump(card, trump) then return false end
    end
    return true
  end
  local function isSmallProbe(cards, trump)
    local card = cards[1]
    return #cards == 1 and not card.joker and card.rank ~= trump.level
      and Cards.points(card) == 0 and Cards.power(card, trump) <= SMALL_POWER
  end
  local function isSidePairWithoutAce(cards, trump)
    local first = cards[1]
    if #cards < 2 or first.joker or isTrump(first, trump) or first.rank == 'A' then return false end
    for _, card in ipairs(cards) do
      if card.joker or card.rank ~= first.rank then return false end
    end
    return true
  end
  local function hasBig(cards) return count(cards, isBig) > 0 end
  local function safeAces(hand, trump, options, context)
    local result = {}
    for index, option in ipairs(options) do
      local cards = selectIds(hand, option.cardIds)
      if #cards > 0 and isSideAce(cards, trump) then
        local suit, ruffed = Cards.category(cards[1], trump), false
        for _, entry in ipairs(context.knownVoids or {}) do
          if entry.category == suit and Cards.team(entry.seat) ~= Cards.team(context.seat) then ruffed = true end
        end
        if not ruffed then table.insert(result, index) end
      end
    end
    return result
  end
  local function preferred(indexes, scores)
    local top = -1
    for _, index in ipairs(indexes) do
      if top < 0 or scores[index] > scores[top] then top = index end
    end
    return top
  end
  local function leadGuard(hand, trump, chosen, options, context, scores)
    local cards = selectIds(hand, options[chosen].cardIds)
    local aces = safeAces(hand, trump, options, context)
    if isSidePairWithoutAce(cards, trump) then
      local sameSuit = {}
      for _, index in ipairs(aces) do
        if Cards.category(selectIds(hand, options[index].cardIds)[1], trump) == Cards.category(cards[1], trump) then
          table.insert(sameSuit, index)
        end
      end
      if #sameSuit > 0 then return preferred(sameSuit, scores) end
    end
    local function matching(keep)
      local indexes = {}
      for index, option in ipairs(options) do
        if keep(selectIds(hand, option.cardIds)) then table.insert(indexes, index) end
      end
      return indexes
    end
    if #cards == 1 and hasBig(cards) and #hand > ENDGAME_CARDS and #options > 1 then
      return preferred(matching(function(list) return not hasBig(list) end), scores)
    end
    if not isHighTrumpSingle(cards, trump) or #aces > 0 or #hand <= ENDGAME_CARDS then return -1 end
    for _, option in ipairs(options) do
      if #option.cardIds >= 2 then return -1 end
    end
    return preferred(matching(function(list) return isSmallProbe(list, trump) end), scores)
  end
  local function summarizeFollows(hand, lead, trump, context, options)
    local summaries = {}
    for index, option in ipairs(options) do
      local cards = selectIds(hand, option.cardIds)
      local follow = Rules.follow(hand, cards, lead, trump)
      summaries[index] = {
        index = index, cards = cards, big = hasBig(cards), joker = count(cards, isJoker) > 0, power = powerOf(cards, trump),
        wins = follow.legal and follow.matchesLead == true and Rules.winning(cards, lead, context.winning, trump) ~= nil,
      }
    end
    return summaries
  end
  local function followGuard(context, chosen, all, scores)
    local partner = Cards.team(context.seat) == Cards.team(context.winnerSeat)
    local contested = context.trickPoints >= CONTESTED_POINTS and context.opponentsRemaining > 0
    local picked = all[chosen]
    local function where(keep)
      local list = {}
      for _, option in ipairs(all) do if keep(option) then table.insert(list, option) end end
      return list
    end
    local function strongest(list)
      local top = list[1]
      for _, option in ipairs(list) do if option.power > top.power then top = option end end
      return top.index
    end
    local function favourite(list)
      local indexes = {}
      for _, option in ipairs(list) do table.insert(indexes, option.index) end
      return preferred(indexes, scores)
    end
    local noBig = where(function(option) return not option.big end)
    if picked.big and #noBig > 0 then
      local winners = where(function(option) return option.wins and not option.big end)
      if partner or not picked.wins or #winners > 0 or context.trickPoints < CONTESTED_POINTS then
        if not partner and #winners > 0 then
          return contested and strongest(winners) or favourite(winners)
        end
        return favourite(noBig)
      end
    end
    if not partner and picked.wins and not picked.joker and contested then
      local plain = where(function(option) return option.wins and not option.joker end)
      for _, option in ipairs(plain) do
        if option.power > picked.power then return strongest(plain) end
      end
    end
    return -1
  end

  -- chooseBotLead helpers ----------------------------------------------------
  local function preserveFriendlyTrump(context)
    if not context.seat or not context.playerCount then return false end
    local voidSeats = {}
    for _, entry in ipairs(context.knownVoids or {}) do
      if entry.category == 'trump' then voidSeats[entry.seat] = true end
    end
    local partnerCanTrump = false
    local team = Cards.team(context.seat)
    for seat = 1, context.playerCount do
      if Cards.team(seat) ~= team then
        if not voidSeats[seat] then return false end
      elseif seat ~= context.seat and not voidSeats[seat] then
        partnerCanTrump = true
      end
    end
    return partnerCanTrump
  end

  -- Chance the partner is void, treating unseen cards as exchangeable.
  local function partnerRuffChance(hand, trump, context, target)
    if target == 'trump' then return 0 end
    local partner = (context.seat - 1 + 2) % context.playerCount + 1
    for _, entry in ipairs(context.knownVoids or {}) do
      if entry.seat == partner and entry.category == target then return 1 end
    end
    local removed = {}
    for _, card in ipairs(hand) do removed[card.id] = true end
    for _, card in ipairs(context.seenCards or {}) do removed[card.id] = true end
    local unknown, matching = 0, 0
    for _, card in ipairs(Cards.deck(context.playerCount)) do
      if not removed[card.id] then
        unknown = unknown + 1
        if Cards.category(card, trump) == target then matching = matching + 1 end
      end
    end
    if unknown == 0 then return 0 end
    local handSize = math.max(1, context.cardsRemaining or #hand)
    return math.max(0, math.min(1, (1 - matching / unknown) ^ handSize))
  end

  function Trained.baselineLead(hand, trump, context)
    local components = S.available(hand, trump)
    local sideSuits = filter(components, function(c) return c.category ~= 'trump' end)
    local candidates = (preserveFriendlyTrump(context) and #sideSuits > 0) and sideSuits or components
    local nearThreshold = context.defenderScore >= context.swapThreshold - 20
    local attackers = context.role == 'attackers'
    local known = context.knownVoids or {}
    local seen = context.seenCards or {}
    local ruffCache, ranked = {}, {}
    for _, component in ipairs(candidates) do
      local points, jokerCost = pointsOf(component.cards), 0
      for _, card in ipairs(component.cards) do
        if card.joker then jokerCost = jokerCost + (card.joker == 'big' and 45 or 15) end
      end
      local structure = component.rankCount > 1 and 25 + component.cardCount * 2 or 0
      local trumpBonus = component.category == 'trump' and 15 or 0
      local seenInCategory = inCategory(seen, component.category, trump)
      local seenHigh = count(seenInCategory, function(card) return Cards.power(card, trump) >= component.highestPower end)
      local freshness = math.max(0, 12 - #seenInCategory) + math.max(0, 6 - seenHigh) * 2
      local opponentVoids = distinctSeats(known, function(entry)
        return entry.category == component.category and (not context.seat or Cards.team(entry.seat) ~= Cards.team(context.seat))
      end)
      local partnerVoids = distinctSeats(known, function(entry)
        return entry.category == component.category and context.seat ~= nil
          and Cards.team(entry.seat) == Cards.team(context.seat) and entry.seat ~= context.seat
      end)
      local voidAdjustment = 0
      if component.category ~= 'trump' then
        voidAdjustment = attackers and partnerVoids * 18 - opponentVoids * 20 or partnerVoids * 12 + opponentVoids * 5
      end
      local endgame = 0
      if context.cardsRemaining and context.cardsRemaining <= 4 then
        endgame = component.highestPower * 0.6 + points * 2
      end
      local pointTerm = (not attackers and nearThreshold) and points * 10 or -points
      local score = structure + trumpBonus + freshness + voidAdjustment + pointTerm - jokerCost + endgame
      if context.seat and context.playerCount then
        if ruffCache[component.category] == nil then
          ruffCache[component.category] = partnerRuffChance(hand, trump, context, component.category)
        end
        score = score + ruffCache[component.category] * (attackers and 14 or 9)
      end
      table.insert(ranked, { component = component, score = score, key = table.concat(idsOf(component.cards), '|') })
    end
    table.sort(ranked, function(a, b)
      if a.score ~= b.score then return a.score > b.score end
      if a.component.cardCount ~= b.component.cardCount then return a.component.cardCount > b.component.cardCount end
      if a.component.multiplicity ~= b.component.multiplicity then return a.component.multiplicity > b.component.multiplicity end
      if a.component.highestPower ~= b.component.highestPower then return a.component.highestPower > b.component.highestPower end
      return a.key < b.key
    end)
    return idsOf(ranked[1].component.cards)
  end

  -- chooseBotPlay with its tactical follow ------------------------------------
  local function followBaseline(hand, baseline, lead, trump, context)
    local candidates = { baseline }
    local led = inCategory(hand, lead[1].category, trump)
    local pool = #led > 0 and led or inCategory(hand, 'trump', trump)
    if #lead == 1 then
      for _, item in ipairs(S.available(pool, trump, lead[1])) do table.insert(candidates, item.cards) end
    else
      local winning = S.match(pool, lead, trump, { mustBeat = context.winning })
      if winning then table.insert(candidates, S.flatten(winning)) end
    end
    if #lead == 1 and lead[1].cardCount == 1 and #led == 0 then
      for _, card in ipairs(hand) do table.insert(candidates, { card }) end
    end
    local partnerWinning = Cards.team(context.seat) == Cards.team(context.winnerSeat)
    local function score(cards)
      local follow = Rules.follow(hand, cards, lead, trump)
      local wins = follow.legal and follow.matchesLead and Rules.winning(cards, lead, context.winning, trump) ~= nil
      local points, strength = pointsOf(cards), 0
      for _, card in ipairs(cards) do
        strength = strength + Cards.power(card, trump) + (isTrump(card, trump) and 30 or 0)
        if card.joker then strength = strength + (card.joker == 'big' and 220 or 90) end
      end
      if partnerWinning then return { context.lastToPlay and -points or points, number(wins), strength } end
      return { wins and 0 or 1, wins and strength or points, strength }
    end
    local legal = filter(candidates, function(cards) return Rules.follow(hand, cards, lead, trump).legal end)
    local scored = {}
    for _, cards in ipairs(legal) do table.insert(scored, { cards = cards, score = score(cards), key = table.concat(idsOf(cards), '|') }) end
    local ordered = stableSort(scored, function(a, b)
      for index = 1, 3 do
        if a.score[index] ~= b.score[index] then return a.score[index] - b.score[index] end
      end
      return byText(a.key, b.key)
    end)
    return ordered[1].cards
  end

  function Trained.baselinePlay(hand, lead, trump, context)
    return idsOf(followBaseline(hand, Rules.baseline(hand, lead, trump), lead, trump, context))
  end

  function Trained.baselineDeclaration(options, hand, level)
    local rankOrder = Cards.ranks
    local ranked = {}
    for _, option in ipairs(options) do
      local suited = option.suit and filter(hand, function(card) return not card.joker and card.suit == option.suit end) or {}
      local byRank = {}
      for _, card in ipairs(suited) do byRank[card.rank] = (byRank[card.rank] or 0) + 1 end
      local pairsCount, tractors = 0, 0
      for _, size in pairs(byRank) do pairsCount = pairsCount + math.max(0, size - 1) end
      for index = 1, #rankOrder - 1 do
        if (byRank[rankOrder[index]] or 0) >= 2 and (byRank[rankOrder[index + 1]] or 0) >= 2 then tractors = tractors + 1 end
      end
      local highCards = count(suited, function(card)
        return card.rank == level or card.rank == 'A' or card.rank == 'K' or card.rank == 'Q'
      end)
      local suitPower, voidSuits = 0, 0
      if option.suit then
        local powers = {}
        for _, card in ipairs(suited) do table.insert(powers, Cards.power(card, { level = level, suit = option.suit })) end
        table.sort(powers, function(a, b) return a > b end)
        for index = 1, math.min(5, #powers) do suitPower = suitPower + powers[index] end
        for _, suit in ipairs(Cards.suits) do
          if suit ~= option.suit and count(hand, function(card) return not card.joker and card.suit == suit end) == 0 then
            voidSuits = voidSuits + 1
          end
        end
      end
      local quality = #suited * 8 + pairsCount * 14 + tractors * 12 + highCards * 3 + suitPower * 0.5 + voidSuits * 18
      table.insert(ranked, { option = option, key = table.concat(option.cardIds, '|'),
        score = (option.joker and 1000 or 0) + option.count * 100 + quality })
    end
    local ordered = stableSort(ranked, function(a, b)
      if a.score ~= b.score then return b.score - a.score end
      if #a.option.cardIds ~= #b.option.cardIds then return #b.option.cardIds - #a.option.cardIds end
      return byText(a.key, b.key)
    end)
    return ordered[1].option
  end

  function Trained.baselineBurial(cards, size, trump)
    local ordered = stableSort(cards, function(a, b)
      local at, bt = number(isTrump(a, trump)), number(isTrump(b, trump))
      if at ~= bt then return at - bt end
      if Cards.points(a) ~= Cards.points(b) then return Cards.points(a) - Cards.points(b) end
      if Cards.power(a, trump) ~= Cards.power(b, trump) then return Cards.power(a, trump) - Cards.power(b, trump) end
      return byText(a.id, b.id)
    end)
    local ids = {}
    for index = 1, size do ids[index] = ordered[index].id end
    return ids
  end

  -- Candidate actions and their network inputs --------------------------------
  function Trained.leadOptions(hand, trump, context)
    local baselineKey = sortedKey(Trained.baselineLead(hand, trump, context))
    local handTrumps = count(hand, function(card) return isTrump(card, trump) end)
    local beforeGroups = {}
    for _, card in ipairs(hand) do
      local key = S.identity(card)
      beforeGroups[key] = (beforeGroups[key] or 0) + 1
    end
    local known, seenAll = context.knownVoids or {}, context.seenCards or {}
    local options = {}
    for _, component in ipairs(S.available(hand, trump)) do
      local remaining = S.without(hand, component.cards)
      local suitCards = inCategory(hand, component.category, trump)
      local remainingSuit = inCategory(remaining, component.category, trump)
      local afterGroups = {}
      for _, card in ipairs(remaining) do
        local key = S.identity(card)
        afterGroups[key] = (afterGroups[key] or 0) + 1
      end
      local broken = 0
      for key, size in pairs(beforeGroups) do
        local left = afterGroups[key] or 0
        if size >= 2 and left > 0 and left < size then broken = broken + 1 end
      end
      local function voidCount(ally)
        return distinctSeats(known, function(entry)
          return entry.category == component.category and entry.seat ~= context.seat
            and (Cards.team(entry.seat) == Cards.team(context.seat)) == ally
        end)
      end
      local seen = inCategory(seenAll, component.category, trump)
      local isTrumpLead = component.category == 'trump'
      local lowestTrump, highestSuit = math.huge, -math.huge
      for _, card in ipairs(hand) do
        if isTrump(card, trump) then lowestTrump = math.min(lowestTrump, Cards.power(card, trump)) end
      end
      for _, card in ipairs(suitCards) do highestSuit = math.max(highestSuit, Cards.power(card, trump)) end
      local ids = idsOf(component.cards)
      table.insert(options, {
        cardIds = ids,
        prior = sortedKey(ids) == baselineKey and BASELINE_PRIOR or 0,
        features = {
          #hand / 30,
          handTrumps / #hand,
          number(context.role == 'attackers'),
          math.min(2, context.defenderScore / context.swapThreshold),
          (context.playerCount or 4) / 10,
          component.cardCount / #hand,
          component.multiplicity / 5,
          component.rankCount / 13,
          component.highestPower / 30,
          number(isTrumpLead),
          pointsOf(component.cards) / 100,
          count(component.cards, isBig) / 5,
          count(component.cards, isSmall) / 5,
          #suitCards / #hand,
          number(#remainingSuit == 0),
          broken / 5,
          count(remaining, function(card) return isTrump(card, trump) end) / #hand,
          pointsOf(remaining) / 200,
          #seen / 65,
          count(seen, function(card) return Cards.power(card, trump) >= component.highestPower end) / 20,
          voidCount(true) / 5,
          voidCount(false) / 5,
          number(context.dealerSeat ~= nil and context.seat == context.dealerSeat),
          number(#seenAll == 0),
          number(not isTrumpLead and allAces(component.cards)),
          number(not isTrumpLead and #remainingSuit == 0),
          number(isTrumpLead and component.highestPower == lowestTrump),
          number(not isTrumpLead and #suitCards <= 2),
          number(not isTrumpLead and voidCount(false) > 0),
          number(not isTrumpLead and component.highestPower == highestSuit),
          number(isHighTrumpSingle(component.cards, trump)),
          number(isSidePairWithoutAce(component.cards, trump) and count(hand, function(card) return isSideAce({ card }, trump) end) > 0),
          number(isSmallProbe(component.cards, trump)),
        },
      })
    end
    return options
  end

  function Trained.playOptions(hand, lead, trump, context)
    local baseline = Trained.baselinePlay(hand, lead, trump, context)
    local baselineKey = sortedKey(baseline)
    local candidates = { baseline }
    local total = S.count(lead)
    for _, component in ipairs(S.available(hand, trump)) do
      if component.cardCount == total and Rules.follow(hand, component.cards, lead, trump).legal then
        table.insert(candidates, idsOf(component.cards))
      end
    end
    -- Like a JavaScript Map: first position wins, last value wins.
    local order, byKey = {}, {}
    for _, ids in ipairs(candidates) do
      local key = sortedKey(ids)
      if not byKey[key] then table.insert(order, key) end
      byKey[key] = ids
    end
    local ledCategory = lead[1].category
    local options = {}
    for _, key in ipairs(order) do
      local ids = byKey[key]
      local cards = selectIds(hand, ids)
      local legal = Rules.follow(hand, cards, lead, trump)
      local matchesLead = legal.legal and legal.matchesLead == true
      local points = pointsOf(cards)
      local partner = number(Cards.team(context.seat) == Cards.team(context.winnerSeat))
      local wins = matchesLead and Rules.winning(cards, lead, context.winning, trump) ~= nil
      local trickPoints, opponents = context.trickPoints, context.opponentsRemaining
      local contest = number(wins and trickPoints > 0 and opponents > 0 and partner == 0)
      local topOfCategory = true
      for _, card in ipairs(cards) do
        local best = -math.huge
        for _, held in ipairs(inCategory(hand, Cards.category(card, trump), trump)) do
          best = math.max(best, Cards.power(held, trump))
        end
        if Cards.power(card, trump) ~= best then topOfCategory = false end
      end
      table.insert(options, {
        cardIds = ids,
        prior = key == baselineKey and BASELINE_PRIOR or 0,
        features = {
          0,
          #hand / 30,
          partner,
          number(context.lastToPlay),
          lead[1].cardCount / 4,
          number(matchesLead),
          number(isTrump(cards[1], trump)),
          #cards / 4,
          points / 30,
          powerOf(cards, trump) / 100,
          count(cards, isBig) / 2,
          count(cards, isSmall) / 2,
          number(ledCategory == 'trump'),
          number(count(cards, isJoker) > 0),
          number(#context.winning > 0),
          number(key == baselineKey),
          number(count(cards, function(card) return Cards.category(card, trump) ~= ledCategory end) == #cards),
          contest * (trickPoints / 100) * (opponents / 3),
          0, 0, 0, 0,
          trickPoints / 100,
          number(wins),
          opponents / 5,
          number(context.dealerSeat ~= nil and context.seat == context.dealerSeat),
          number(allAces(cards) and not isTrump(cards[1], trump)),
          number(wins) * trickPoints / 100,
          partner * points / 30,
          number(topOfCategory),
        },
      })
    end
    -- Inputs that compare an option with the other legal options.
    local summaries = summarizeFollows(hand, lead, trump, context, options)
    local topOpponent, strongestPlain, hasPlain, cheaperWinner = 0, -math.huge, false, false
    for _, component in ipairs(context.winning) do topOpponent = math.max(topOpponent, component.highestPower) end
    for _, s in ipairs(summaries) do
      if s.wins and not s.joker then strongestPlain = math.max(strongestPlain, s.power) end
      if not s.big then hasPlain = true end
      if s.wins and not s.big then cheaperWinner = true end
    end
    local partnerWinning = Cards.team(context.seat) == Cards.team(context.winnerSeat)
    for index, s in ipairs(summaries) do
      local highest = -math.huge
      for _, card in ipairs(s.cards) do highest = math.max(highest, Cards.power(card, trump)) end
      local features = options[index].features
      features[31] = number(s.big and hasPlain and (partnerWinning or not s.wins or cheaperWinner or context.trickPoints < CONTESTED_POINTS))
      features[32] = s.wins and (highest - topOpponent) / 15 or 0
      features[33] = number(s.wins and not s.joker and s.power == strongestPlain)
    end
    return options
  end

  function Trained.declarationOptions(options, hand, level)
    local baseline = Trained.baselineDeclaration(options, hand, level)
    local result = {}
    for index, option in ipairs(options) do
      local cards = selectIds(hand, option.cardIds)
      result[index] = {
        cardIds = option.cardIds,
        choice = option,
        prior = option == baseline and BASELINE_PRIOR or 0,
        features = {
          0,
          #hand / 30,
          number(option.joker ~= nil),
          option.count / 5,
          #cards / 5,
          pointsOf(cards) / 30,
          count(cards, isJoker) / 5,
          number(option.suit ~= nil),
          number(option.joker == 'big'),
          number(option.joker == 'mixed'),
        },
      }
    end
    table.insert(result, { cardIds = {}, prior = 0, features = {} }) -- not calling is a choice
    return result
  end

  -- Matches robloxBurialChoices in backend/src/training/learned-policy.ts.
  function Trained.burialOptions(cards, size, trump)
    local order = Rules.chooseBurial(cards, #cards, trump)
    local function firstIds(list)
      local ids = {}
      for index = 1, size do ids[index] = list[index].id end
      return ids
    end
    -- Empty the shortest suits outright, then fall back to the Roblox order.
    local suits, bySuit = {}, {}
    for _, card in ipairs(order) do
      if not isTrump(card, trump) then
        local group = Cards.category(card, trump)
        if not bySuit[group] then
          bySuit[group] = {}
          table.insert(suits, bySuit[group])
        end
        table.insert(bySuit[group], card)
      end
    end
    local voiding, taken = {}, {}
    for _, suit in ipairs(stableSort(suits, function(a, b) return #a - #b end)) do
      if #voiding + #suit <= size then
        for _, card in ipairs(suit) do
          table.insert(voiding, card.id)
          taken[card.id] = true
        end
      end
    end
    for _, card in ipairs(order) do
      if #voiding < size and not taken[card.id] then table.insert(voiding, card.id) end
    end
    -- The Roblox order, but point cards go only when nothing else is left.
    local savingPoints = stableSort(order, function(a, b)
      local at, bt = number(isTrump(a, trump)), number(isTrump(b, trump))
      if at ~= bt then return at - bt end
      return number(Cards.points(a) > 0) - number(Cards.points(b) > 0)
    end)

    local function suitLengths(list)
      local lengths, total = {}, 0
      for _, card in ipairs(list) do
        if not isTrump(card, trump) then
          local group = Cards.category(card, trump)
          if not lengths[group] then total = total + 1 end
          lengths[group] = (lengths[group] or 0) + 1
        end
      end
      return lengths, total
    end
    local function identities(list)
      local counts = {}
      for _, card in ipairs(list) do
        local key = S.identity(card)
        counts[key] = (counts[key] or 0) + 1
      end
      return counts
    end
    local _, suitsBefore = suitLengths(cards)
    local allCounts = identities(cards)

    local options, seen = {}, {}
    for index, ids in ipairs({ firstIds(order), voiding, firstIds(savingPoints) }) do
      local key = sortedKey(ids)
      if not seen[key] then
        seen[key] = true
        local selected = selectIds(cards, ids)
        local wanted = {}
        for _, id in ipairs(ids) do wanted[id] = true end
        local kept = filter(cards, function(card) return not wanted[card.id] end)
        local after, suitsAfter = suitLengths(kept)
        local shortest = math.huge
        for _, length in pairs(after) do shortest = math.min(shortest, length) end
        local remaining, brokenPairs = identities(kept), 0
        for identity, total in pairs(allCounts) do
          if total >= 2 and (remaining[identity] or 0) == 1 then brokenPairs = brokenPairs + 1 end
        end
        table.insert(options, {
          cardIds = ids,
          prior = index == 1 and BASELINE_PRIOR or 0,
          features = {
            0,
            #cards / 30,
            number(count(selected, function(card) return isTrump(card, trump) end) > 0),
            pointsOf(selected) / 50,
            powerOf(selected, trump) / 100,
            count(selected, isJoker) / 2,
            number(count(selected, isJoker) > 0),
            (suitsBefore - suitsAfter) / 4,
            brokenPairs / math.max(1, #selected),
            suitsAfter > 0 and shortest / 13 or 0,
          },
        })
      end
    end
    return options
  end

  -- The network ---------------------------------------------------------------
  local function tanh(x)
    if x > 20 then return 1 elseif x < -20 then return -1 end
    local up, down = math.exp(x), math.exp(-x)
    return (up - down) / (up + down)
  end
  local function score(model, option)
    local total = option.prior > 0 and model.priorScale or 0
    for unit, row in ipairs(model.input) do
      local sum = model.bias[unit]
      for index, weight in ipairs(row) do sum = sum + weight * (option.features[index] or 0) end
      total = total + tanh(sum) * model.output[unit]
    end
    return total
  end
  local function best(model, options)
    local chosen, top, scores = 1, -math.huge, {}
    for index, option in ipairs(options) do
      local value = score(model, option)
      scores[index] = value
      if value > top then chosen, top = index, value end
    end
    return chosen, scores
  end
  local function usesStyle(model) return #model.input[1] >= STYLE_INPUTS end
  Trained.score = score

  function Trained.chooseLead(hand, trump, context, models)
    local options = Trained.leadOptions(hand, trump, context)
    local model = (models or Model).lead
    local chosen, scores = best(model, options)
    if usesStyle(model) then
      local guard = leadGuard(hand, trump, chosen, options, context, scores)
      if guard >= 0 then chosen = guard end
    end
    return options[chosen].cardIds
  end

  function Trained.choosePlay(hand, lead, trump, context, models)
    local options = Trained.playOptions(hand, lead, trump, context)
    local model = (models or Model).follow
    local chosen, scores = best(model, options)
    -- Website guard: secure a contested point trick with a winning ace.
    if context.trickPoints > 0 and context.opponentsRemaining > 0 and options[chosen].features[3] == 0 then
      for index, option in ipairs(options) do
        if option.features[24] == 1 and option.features[27] == 1 then chosen = index; break end
      end
    end
    if usesStyle(model) then
      local guard = followGuard(context, chosen, summarizeFollows(hand, lead, trump, context, options), scores)
      if guard >= 0 then chosen = guard end
    end
    return options[chosen].cardIds
  end

  -- Returns one of `options`, or nil to stay quiet.
  function Trained.chooseDeclaration(options, hand, level, models)
    if #options == 0 then return nil end
    local list = Trained.declarationOptions(options, hand, level)
    return list[best((models or Model).follow, list)].choice
  end

  function Trained.chooseBurial(cards, size, trump, models)
    local options = Trained.burialOptions(cards, size, trump)
    return options[best((models or Model).follow, options)].cardIds
  end

  -- Public table state, in the shape the policy was trained on ----------------
  function Trained.leadContext(state, seat)
    local voids, voidSeen, seen = {}, {}, {}
    for _, item in ipairs(state.history) do
      local ledCategory = Cards.category(item.plays[1].cards[1], state.trump)
      for _, play in ipairs(item.plays) do
        for _, card in ipairs(play.cards) do table.insert(seen, card) end
        if count(play.cards, function(card) return Cards.category(card, state.trump) ~= ledCategory end) > 0 then
          local key = play.seat .. ':' .. ledCategory
          if not voidSeen[key] then
            voidSeen[key] = true
            table.insert(voids, { seat = play.seat, category = ledCategory })
          end
        end
      end
    end
    return {
      seat = seat,
      dealerSeat = state.kittyHolder or state.dealer,
      playerCount = state.playerCount,
      cardsRemaining = #state.hands[seat],
      role = Cards.team(seat) == state.attackingTeam and 'attackers' or 'defenders',
      defenderScore = state.points[state.attackingTeam == 'A' and 2 or 1] + state.penaltyPoints,
      swapThreshold = state.playerCount * 20,
      seenCards = seen,
      knownVoids = voids,
    }
  end

  function Trained.playContext(state, seat)
    local base = Rules.playContext(state, seat)
    local played, opponents = {}, 0
    for _, play in ipairs(state.trick) do played[play.seat] = true end
    for other = 1, state.playerCount do
      if other ~= seat and not played[other] and Cards.team(other) ~= Cards.team(seat) then opponents = opponents + 1 end
    end
    return {
      seat = seat,
      winnerSeat = base.winnerSeat,
      winning = base.winningComponents,
      lastToPlay = base.lastToPlay,
      trickPoints = base.trickPoints,
      opponentsRemaining = opponents,
      dealerSeat = state.kittyHolder or state.dealer,
    }
  end

  return Trained
end
