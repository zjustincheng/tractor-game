-- VIP card tracker. Works only from what a player is allowed to know: their own
-- hand and the cards played in front of everyone this round. It reads nothing
-- else from the game view, so it cannot reveal another player's hand or the kitty.
return function(Cards, S)
  local Tracker = {}

  -- Every trick so far, finished or still on the table.
  local function tricksOf(view)
    local tricks = {}
    for _, entry in ipairs(view.history or {}) do table.insert(tricks, entry.plays) end
    if view.trick and #view.trick > 0 then table.insert(tricks, view.trick) end
    return tricks
  end

  function Tracker.analyze(view)
    local trump, playerCount, hand = view.trump, view.playerCount, view.hand or {}
    local seen, voids = {}, {}
    for seat = 2, playerCount do voids[seat] = {} end

    -- Not following the led suit in full proves a player has run out of it.
    for _, plays in ipairs(tricksOf(view)) do
      local lead = plays[1]
      local category = Cards.category(lead.cards[1], trump)
      for _, play in ipairs(plays) do
        local inCategory = 0
        for _, card in ipairs(play.cards) do
          seen[card.id] = true
          if Cards.category(card, trump) == category then inCategory = inCategory + 1 end
        end
        if play ~= lead and voids[play.seat] and inCategory < #lead.cards then voids[play.seat][category] = true end
      end
    end

    -- Cards that could still be in someone's hand or the kitty.
    for _, card in ipairs(hand) do seen[card.id] = true end
    local unseen = {}
    for _, card in ipairs(Cards.deck(playerCount)) do
      if not seen[card.id] then table.insert(unseen, card) end
    end

    local categories = {}
    for _, suit in ipairs(Cards.suits) do
      if suit ~= trump.suit then table.insert(categories, suit) end
    end
    table.insert(categories, 'trump')

    local function inCategory(cards, category)
      local result = {}
      for _, card in ipairs(cards) do
        if Cards.category(card, trump) == category then table.insert(result, card) end
      end
      return result
    end

    -- A part is safe only if nothing unseen could beat it, or nobody else can
    -- hold that suit. Safe is therefore certain; risky only means it might lose.
    local gambles = {}
    for _, category in ipairs(categories) do
      local cards = inCategory(hand, category)
      if #cards > 0 then
        local pool = inCategory(unseen, category)
        local everyoneOut = playerCount > 1
        for seat = 2, playerCount do
          if not voids[seat][category] then everyoneOut = false end
        end
        local safe, risky = {}, {}
        for _, component in ipairs(S.decompose(cards, trump)) do
          local beatable = false
          if not everyoneOut then
            for _, candidate in ipairs(S.available(pool, trump, component)) do
              if candidate.highestPower > component.highestPower then beatable = true; break end
            end
          end
          table.insert(beatable and risky or safe, component)
        end
        local strongestFirst = function(a, b)
          if a.highestPower ~= b.highestPower then return a.highestPower > b.highestPower end
          return S.key(a) < S.key(b)
        end
        table.sort(safe, strongestFirst)
        table.sort(risky, strongestFirst)
        table.insert(gambles, { category = category, safe = safe, risky = risky, canGamble = #safe >= 2 })
      end
    end
    -- Cards worth marking: a gamble needs at least two safe parts in one suit.
    local gambleCards = {}
    for _, entry in ipairs(gambles) do
      if entry.canGamble then
        for _, component in ipairs(entry.safe) do
          for _, card in ipairs(component.cards) do gambleCards[card.id] = true end
        end
      end
    end
    return { voids = voids, gambles = gambles, categories = categories, gambleCards = gambleCards }
  end

  return Tracker
end
