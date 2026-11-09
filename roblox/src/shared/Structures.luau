-- Pure port of structures.ts/components.ts. Stable physical IDs break ties.
return function(Cards)
  local S = {}
  local function copy(items) local result = {}; for _, item in ipairs(items) do table.insert(result, item) end; return result end
  function S.identity(card) return card.joker and ('joker:' .. card.joker) or (card.suit .. ':' .. card.rank) end
  function S.without(cards, removed)
    local ids, result = {}, {}
    for _, card in ipairs(removed) do ids[card.id] = true end
    for _, card in ipairs(cards) do if not ids[card.id] then table.insert(result, card) end end
    return result
  end
  function S.groups(cards)
    local groups, ordered = {}, {}
    for _, card in ipairs(cards) do
      local key = S.identity(card)
      if not groups[key] then groups[key] = {}; table.insert(ordered, groups[key]) end
      table.insert(groups[key], card)
    end
    for _, group in ipairs(ordered) do table.sort(group, function(a,b) return a.id < b.id end) end
    return ordered
  end
  function S.key(component)
    local ids = {}; for _, card in ipairs(component.cards) do table.insert(ids, card.id) end
    table.sort(ids); return table.concat(ids, '|')
  end
  function S.sameShape(a,b) return a.multiplicity == b.multiplicity and a.rankCount == b.rankCount end
  function S.homogeneous(cards, trump)
    if #cards == 0 then return nil end
    local category, ids = Cards.category(cards[1], trump), {}
    for _, card in ipairs(cards) do
      if ids[card.id] or Cards.category(card, trump) ~= category then return nil end
      ids[card.id] = true
    end
    local groups = S.groups(cards)
    local multiplicity, powers = #groups[1], {}
    if #groups > 1 and multiplicity < 2 then return nil end
    for _, group in ipairs(groups) do
      if #group ~= multiplicity then return nil end
      table.insert(powers, Cards.power(group[1], trump))
    end
    table.sort(powers)
    for i = 2, #powers do if powers[i] ~= powers[i-1]+1 then return nil end end
    return { category = category, multiplicity = multiplicity, rankCount = #groups,
      cardCount = #cards, highestPower = powers[#powers] }
  end
  function S.compare(a,b)
    if a.cardCount ~= b.cardCount then return a.cardCount > b.cardCount end
    if a.multiplicity ~= b.multiplicity then return a.multiplicity > b.multiplicity end
    if a.highestPower ~= b.highestPower then return a.highestPower > b.highestPower end
    return S.key(a) < S.key(b)
  end
  function S.available(cards, trump, shape)
    if #cards == 0 then return {} end
    local groups, result, maximum = S.groups(cards), {}, 0
    for _, group in ipairs(groups) do maximum = math.max(maximum, #group) end
    local function add(chosen)
      local component = S.homogeneous(chosen, trump)
      if component and (not shape or S.sameShape(component, shape)) then
        component.cards = copy(chosen); table.insert(result, component)
      end
    end
    for multiplicity = shape and shape.multiplicity or 1, shape and shape.multiplicity or maximum do
      local eligible, tiers = {}, {}
      for _, group in ipairs(groups) do
        if #group >= multiplicity then
          table.insert(eligible, group)
          local power = Cards.power(group[1], trump)
          tiers[power] = tiers[power] or {}; table.insert(tiers[power], group)
          if not shape or shape.rankCount == 1 then
            local chosen = {}; for i = 1, multiplicity do chosen[i] = group[i] end; add(chosen)
          end
        end
      end
      if multiplicity >= 2 and (not shape or shape.rankCount ~= 1) then
        local function extend(chosen, power, category, ranks)
          if ranks >= 2 and (not shape or ranks == shape.rankCount) then add(chosen) end
          if shape and ranks >= shape.rankCount then return end
          for _, group in ipairs(tiers[power+1] or {}) do
            if Cards.category(group[1], trump) == category then
              local nextCards = copy(chosen)
              for i = 1, multiplicity do table.insert(nextCards, group[i]) end
              extend(nextCards, power+1, category, ranks+1)
            end
          end
        end
        for _, group in ipairs(eligible) do
          local chosen = {}; for i = 1, multiplicity do chosen[i] = group[i] end
          extend(chosen, Cards.power(group[1], trump), Cards.category(group[1], trump), 1)
        end
      end
    end
    table.sort(result, S.compare)
    return result
  end
  function S.decompose(cards, trump)
    if #cards == 0 then return nil end
    local category, seen = Cards.category(cards[1], trump), {}
    for _, card in ipairs(cards) do
      if seen[card.id] or Cards.category(card,trump) ~= category then return nil end
      seen[card.id] = true
    end
    local remaining, result = copy(cards), {}
    while #remaining > 0 do
      local component = S.available(remaining, trump)[1]
      table.insert(result, component); remaining = S.without(remaining, component.cards)
    end
    return result
  end
  function S.match(cards, shapes, trump, options)
    options = options or {}
    local ordered, needed = copy(shapes), 0
    table.sort(ordered, function(a,b)
      if a.multiplicity ~= b.multiplicity then return a.multiplicity > b.multiplicity end
      return a.rankCount > b.rankCount
    end)
    for _, shape in ipairs(ordered) do needed = needed + shape.multiplicity * shape.rankCount end
    if needed > #cards or (options.requireAllCards and needed ~= #cards) then return nil end
    -- Avoid exploring every partition when no comparable component can possibly beat.
    if options.mustBeat then
      local possible = false
      for _, shape in ipairs(ordered) do
        for _, candidate in ipairs(S.available(cards,trump,shape)) do
          for _, current in ipairs(options.mustBeat) do
            if S.sameShape(candidate,current) and
              ((candidate.category==current.category and candidate.highestPower>current.highestPower) or
              (candidate.category~=current.category and candidate.category=='trump')) then possible=true; break end
          end
          if possible then break end
        end
        if possible then break end
      end
      if not possible then return nil end
    end
    local sourceCounts, failed = {}, {}
    for _, group in ipairs(S.groups(cards)) do sourceCounts[S.identity(group[1])] = #group end
    local function search(remaining, index, hasBeaten)
      local shape = ordered[index]
      if not shape then if not options.mustBeat or hasBeaten then return {} end; return nil end
      local key = index .. ':' .. tostring(hasBeaten) .. ':' .. S.key({cards=remaining})
      if failed[key] then return nil end
      for _, candidate in ipairs(S.available(remaining, trump, shape)) do
        local protected, beats = false, false
        if options.protectLargerSets and shape.multiplicity > 1 then
          for _, card in ipairs(candidate.cards) do if sourceCounts[S.identity(card)] > shape.multiplicity then protected = true end end
        end
        if not protected then
          for _, current in ipairs(options.mustBeat or {}) do
            if S.sameShape(candidate,current) and
              ((candidate.category == current.category and candidate.highestPower > current.highestPower) or
              (candidate.category ~= current.category and candidate.category == 'trump')) then beats = true end
          end
          local rest = search(S.without(remaining,candidate.cards), index+1, hasBeaten or beats)
          if rest then table.insert(rest,1,candidate); return rest end
        end
      end
      failed[key] = true
      return nil
    end
    return search(cards,1,false)
  end
  function S.flatten(components)
    local result = {}; for _, component in ipairs(components) do for _, card in ipairs(component.cards) do table.insert(result,card) end end
    return result
  end
  function S.count(components)
    local count = 0; for _, component in ipairs(components) do count = count + component.cardCount end; return count
  end
  function S.describe(components)
    if not components then return 'Mixed categories' end
    local names = {}
    for _, c in ipairs(components) do
      local name = c.multiplicity == 1 and 'single' or (c.multiplicity == 2 and 'pair' or (c.multiplicity .. '-of-a-kind'))
      if c.rankCount > 1 then name = c.rankCount .. ' consecutive ' .. name .. 's' end
      table.insert(names, name)
    end
    return (#components > 1 and 'Gamble: ' or '') .. table.concat(names, ' + ')
  end
  return S
end
