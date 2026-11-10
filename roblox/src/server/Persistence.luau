-- Saves each player's coins, unlocks and once-per-day/once-ever claims in a
-- DataStore. The store, catalog and wait function are injected so tests can
-- substitute doubles. All DataStore calls are wrapped: a failed load marks the
-- session unsaved so defaults never overwrite real progress.
return function(store, catalog, wait)
  local Persistence = {}
  Persistence.VERSION = 1
  Persistence.enabled = store ~= nil
  local MAX_COINS = 1e12
  local ATTEMPTS = 3
  -- Recent Robux purchase IDs, so a retried receipt is never paid twice.
  Persistence.MAX_RECEIPTS = 50

  local items = {}
  local profileItems = {}
  for _, item in ipairs(catalog) do items[item.id] = item end
  for _, item in ipairs(catalog.profile or {}) do
    items[item.id] = item
    profileItems[item.id] = item
  end
  local ownable = { emote = true, cardBack = true, felt = true, frame = true, title = true, banner = true }
  -- Equipment slot for each category that can be worn (slot names match categories).
  local SLOTS = { cardBack = 'cardBack', felt = 'felt', frame = 'frame', title = 'title', banner = 'banner' }
  -- Lifetime counters shown on the stats screen.
  Persistence.STAT_KEYS = { 'roundsPlayed', 'roundsWon', 'matchesWon', 'shutouts', 'overturns', 'chaodis', 'bestGrade', 'biggestWin', 'coinsEarned', 'rankPoints' }

  function Persistence.key(userId) return 'player_' .. tostring(userId) end
  function Persistence.today(now) return math.floor((now or os.time()) / 86400) end

  local function wholeNumber(value, maximum)
    if type(value) ~= 'number' or value ~= value or value == math.huge or value == -math.huge then return nil end
    return math.clamp(math.floor(value), 0, maximum)
  end

  -- Accepts only well-formed values; anything unknown or malformed is dropped.
  function Persistence.sanitize(data)
    if type(data) ~= 'table' then return nil end
    local clean = {
      version = Persistence.VERSION,
      coins = wholeNumber(data.coins, MAX_COINS),
      vaultCoins = wholeNumber(data.vaultCoins, MAX_COINS),
      lastDailyDay = wholeNumber(data.lastDailyDay, 1e7),
      loginStreak = wholeNumber(data.loginStreak, 7),
      luckyDay = wholeNumber(data.luckyDay, 1e7),
      mailClaimed = data.mailClaimed == true,
      tutorialDone = data.tutorialDone == true,
      markerSeconds = wholeNumber(data.markerSeconds, 1e7),
      owned = {},
      equipped = {},
      stats = {},
      receipts = {},
    }
    if type(data.pass) == 'table' and type(data.pass.season) == 'string' and #data.pass.season <= 32 and catalog.pass then
      local maxXp = #catalog.pass.tiers * catalog.pass.xpPerTier
      local function tierList(source)
        local list, seen = {}, {}
        for _, tier in ipairs(type(source) == 'table' and source or {}) do
          -- Out-of-range tiers are dropped, never clamped onto a real tier.
          local whole = type(tier) == 'number' and tier % 1 == 0 and tier >= 1 and tier <= #catalog.pass.tiers and tier or nil
          if whole and not seen[whole] then seen[whole] = true; table.insert(list, whole) end
        end
        table.sort(list)
        return list
      end
      clean.pass = { season = data.pass.season, xp = wholeNumber(data.pass.xp, maxXp) or 0, premium = data.pass.premium == true,
        claimedFree = tierList(data.pass.claimedFree), claimedPremium = tierList(data.pass.claimedPremium) }
    end
    if type(data.receipts) == 'table' then
      for _, id in ipairs(data.receipts) do
        if type(id) == 'string' and #id <= 64 then table.insert(clean.receipts, id) end
      end
      while #clean.receipts > Persistence.MAX_RECEIPTS do table.remove(clean.receipts, 1) end
    end
    if type(data.stats) == 'table' then
      for _, key in ipairs(Persistence.STAT_KEYS) do clean.stats[key] = wholeNumber(data.stats[key], MAX_COINS) or 0 end
    end
    if type(data.owned) == 'table' then
      for id, value in pairs(data.owned) do
        local item = type(id) == 'string' and items[id]
        if value == true and item and ownable[item.category] then clean.owned[id] = true end
      end
    end
    if type(data.equipped) == 'table' then
      for slot, category in pairs(SLOTS) do
        local id = data.equipped[slot]
        local item = type(id) == 'string' and items[id]
        if item and item.category == category then clean.equipped[slot] = id end
      end
    end
    return clean
  end

  function Persistence.snapshot(session)
    return Persistence.sanitize({
      coins = session.coins,
      vaultCoins = session.vaultCoins,
      lastDailyDay = session.lastDailyDay,
      loginStreak = session.loginStreak,
      luckyDay = session.luckyDay,
      mailClaimed = session.mailClaimed,
      tutorialDone = session.tutorialDone,
      markerSeconds = session.markerSeconds,
      owned = session.owned,
      equipped = session.equipped,
      stats = session.stats,
      receipts = session.receipts,
      pass = session.pass,
    })
  end

  -- A stable string of the saved fields, used to skip unchanged autosaves.
  function Persistence.signature(data)
    local owned = {}
    for id in pairs(data.owned) do table.insert(owned, id) end
    table.sort(owned)
    return table.concat({ tostring(data.coins), tostring(data.vaultCoins), tostring(data.lastDailyDay), tostring(data.loginStreak), tostring(data.luckyDay),
      tostring(data.mailClaimed), tostring(data.tutorialDone), table.concat(owned, ','), tostring(data.equipped.cardBack), tostring(data.equipped.felt),
      tostring(data.equipped.frame), tostring(data.equipped.title), tostring(data.equipped.banner), tostring(data.markerSeconds),
      (function()
        local values = {}
        for _, key in ipairs(Persistence.STAT_KEYS) do table.insert(values, tostring(data.stats[key] or 0)) end
        return table.concat(values, ',')
      end)(), table.concat(data.receipts or {}, ','),
      data.pass and table.concat({ data.pass.season, tostring(data.pass.xp), tostring(data.pass.premium), table.concat(data.pass.claimedFree, ','), table.concat(data.pass.claimedPremium, ',') }, ':') or '' }, '|')
  end

  -- Saved values replace defaults; starter unlocks stay owned. Equipped items
  -- apply only if owned after merging, which includes starter items.
  function Persistence.apply(session, data)
    if data.coins then session.coins = data.coins end
    if data.vaultCoins then session.vaultCoins = data.vaultCoins end
    session.lastDailyDay = data.lastDailyDay
    session.loginStreak = data.loginStreak
    session.luckyDay = data.luckyDay
    session.mailClaimed = data.mailClaimed
    session.tutorialDone = data.tutorialDone
    session.markerSeconds = data.markerSeconds
    for id in pairs(data.owned) do session.owned[id] = true end
    for key, value in pairs(data.stats or {}) do session.stats[key] = value end
    session.receipts = data.receipts or {}
    -- A save from an earlier season starts the new one fresh.
    if data.pass and catalog.pass and data.pass.season == catalog.pass.id then session.pass = data.pass end
    for slot, id in pairs(data.equipped) do
      if session.owned[id] then session.equipped[slot] = id end
    end
  end

  -- ===== Login streak =====
  -- The streak day a player is on: today's if claimed, otherwise the next to claim.
  -- Missing a day starts over, and finishing day 7 loops back to day 1.
  function Persistence.streakDay(session, now)
    local today = Persistence.today(now)
    local streak = session.loginStreak or 0
    if session.lastDailyDay == today then return math.max(streak, 1) end
    if session.lastDailyDay == today - 1 and streak > 0 then return streak % 7 + 1 end
    return 1
  end

  -- Pays today's reward once. Returns the day and coins, or nil if already claimed.
  function Persistence.claimDaily(session, now)
    local today = Persistence.today(now)
    if session.lastDailyDay == today then return nil end
    local day = Persistence.streakDay(session, now)
    local coins = catalog.loginStreak[day]
    session.loginStreak, session.lastDailyDay = day, today
    session.coins = session.coins + coins
    return day, coins
  end

  function Persistence.isProfileItem(id) return profileItems[id] ~= nil end

  -- ===== Battle Pass =====
  function Persistence.newPass()
    return { season = catalog.pass.id, xp = 0, premium = false, claimedFree = {}, claimedPremium = {} }
  end
  function Persistence.passTier(xp) return math.min(#catalog.pass.tiers, math.floor((xp or 0) / catalog.pass.xpPerTier)) end

  -- XP for one finished round. Returns the XP gained (0 once the season ends or at max).
  function Persistence.passAddXp(session, won, shutout, now)
    local pass, config = session.pass, catalog.pass
    if not pass or (now or os.time()) >= config.endsAt then return 0 end
    local gain = config.xp.play + (won and config.xp.win or 0) + (shutout and config.xp.shutout or 0)
    local maximum = #config.tiers * config.xpPerTier
    gain = math.min(gain, maximum - pass.xp)
    pass.xp = pass.xp + gain
    return gain
  end

  function Persistence.passUnlock(session)
    if not session.pass or session.pass.premium then return false end
    session.pass.premium = true
    return true
  end

  -- Claims one reward. Returns the reward, or nil and the reason it can't be claimed.
  function Persistence.passClaim(session, track, tier)
    local pass, config = session.pass, catalog.pass
    local rewards = type(tier) == 'number' and config.tiers[tier]
    if not pass or not rewards or (track ~= 'free' and track ~= 'premium') then return nil, 'That reward does not exist.' end
    local reward = rewards[track]
    if not reward then return nil, 'That reward does not exist.' end
    if tier > Persistence.passTier(pass.xp) then return nil, 'Reach that tier first.' end
    if track == 'premium' and not pass.premium then return nil, 'Unlock Premium to claim that.' end
    local claimed = track == 'free' and pass.claimedFree or pass.claimedPremium
    for _, done in ipairs(claimed) do if done == tier then return nil, 'Already claimed.' end end
    if reward.boost then
      if session.vip == true then return nil, 'VIP already includes card markers.' end
      -- Banked play time; stacks onto whatever is left.
      session.markerSeconds = (session.markerSeconds or 0) + reward.boost * 60
    elseif reward.coins then session.coins = session.coins + reward.coins
    elseif reward.item then session.owned[reward.item] = true end
    table.insert(claimed, tier)
    return reward
  end

  -- Seconds of timed card markers left. They only burn during play (tickMarkers).
  function Persistence.markersLeft(session) return math.max(0, session.markerSeconds or 0) end
  function Persistence.tickMarkers(session, elapsed)
    if (session.markerSeconds or 0) > 0 and elapsed > 0 then
      session.markerSeconds = math.max(0, session.markerSeconds - elapsed)
    end
  end

  -- Claims everything available. Returns total coins and how many rewards were claimed.
  function Persistence.passClaimAll(session)
    local coins, count = 0, 0
    for tier = 1, Persistence.passTier(session.pass and session.pass.xp or 0) do
      for _, track in ipairs({ 'free', 'premium' }) do
        -- Timed boosts are claimed one at a time, so players see what they're getting.
        local reward = not catalog.pass.tiers[tier][track].boost and Persistence.passClaim(session, track, tier) or nil
        if reward then count = count + 1; coins = coins + (reward.coins or 0) end
      end
    end
    return coins, count
  end

  -- Wears an owned item in its slot. Returns the item, or nil if it cannot be worn.
  function Persistence.equip(session, id)
    local item = items[id]
    local slot = item and SLOTS[item.category]
    if not slot or not session.owned[id] then return nil end
    session.equipped[slot] = id
    return item
  end

  -- Buys a coin-priced profile item and wears it. Returns item, or nil and a reason.
  function Persistence.buyProfileItem(session, id)
    local item = profileItems[id]
    if not item then return nil, 'That item is not available.' end
    if session.owned[id] then return nil, 'Already unlocked.' end
    if item.unlock or item.vip or type(item.price) ~= 'number' or item.price <= 0 then
      return nil, 'That one has to be earned.'
    end
    if session.coins < item.price then return nil, 'Earn more coins by finishing practice hands.' end
    session.coins = session.coins - item.price
    session.owned[id] = true
    session.equipped[SLOTS[item.category]] = id
    return item
  end

  -- Grants every stat or VIP reward the player now qualifies for; returns the new ones.
  function Persistence.grantEarned(session)
    local granted = {}
    local stats = session.stats or {}
    for _, item in ipairs(catalog.profile or {}) do
      if not session.owned[item.id] then
        local viaStat = item.unlock and (stats[item.unlock.stat] or 0) >= item.unlock.at
        if viaStat or (item.vip and session.vip == true) then
          session.owned[item.id] = true
          table.insert(granted, item)
        end
      end
    end
    return granted
  end

  local function attempt(fn)
    local lastError
    for try = 1, ATTEMPTS do
      local ok, result = pcall(fn)
      if ok then return true, result end
      lastError = result
      if try < ATTEMPTS and wait then wait(try) end
    end
    return false, lastError
  end

  -- Returns ok, data. ok=false means the store failed; data=nil means a new player.
  function Persistence.load(userId)
    if not store then return false, 'DataStore unavailable' end
    local ok, result = attempt(function() return store:GetAsync(Persistence.key(userId)) end)
    if not ok then return false, result end
    return true, Persistence.sanitize(result)
  end

  function Persistence.save(userId, data)
    if not store then return false, 'DataStore unavailable' end
    return attempt(function()
      return store:UpdateAsync(Persistence.key(userId), function() return data end)
    end)
  end

  return Persistence
end
