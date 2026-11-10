-- Cross-server matchmaking and squad invites.
--   * Tickets live in a MemoryStore sorted map shared by every server.
--   * One server at a time holds a short lock and forms matches with the pure
--     Matchmaker, reserves a private server per match, records the match, and
--     announces it over MessagingService.
--   * Every server teleports its own players named in an announcement.
--   * Squad invites to friends in other servers travel over MessagingService;
--     accepting teleports the friend into the leader's server.
-- Roblox services are injected (`deps`) so tests can supply doubles.
return function(Matchmaker, deps)
  local CrossServer = {}
  local memory, messaging, teleport = deps.memory, deps.messaging, deps.teleport
  local placeId, jobId = deps.placeId, deps.jobId
  local QUEUE_TTL, LOCK_TTL, MATCH_TTL = 180, 6, 1800 -- match records outlive a round so players can reconnect
  local queueMap = memory:GetSortedMap('TractorQueue')
  local lockMap = memory:GetSortedMap('TractorLock')
  local matchMap = memory:GetSortedMap('TractorMatches')
  local nextMatchAt = 0
  local handlers = { match = nil, invite = nil, cancelled = nil }

  local function try(fn)
    local ok, result = pcall(fn)
    if not ok and deps.warn then deps.warn('[Tractor] Cross-server: ' .. tostring(result)) end
    return ok, result
  end

  function CrossServer.onMatch(fn) handlers.match = fn end
  function CrossServer.onInvite(fn) handlers.invite = fn end

  -- Every server listens for match announcements and invites.
  try(function()
    messaging:SubscribeAsync('TractorMatch', function(message)
      if handlers.match then handlers.match(message.Data) end
    end)
  end)
  try(function()
    messaging:SubscribeAsync('TractorInvite', function(message)
      if handlers.invite then handlers.invite(message.Data) end
    end)
  end)

  function CrossServer.enqueue(ticket)
    return try(function() queueMap:SetAsync(ticket.id, ticket, QUEUE_TTL) end)
  end

  function CrossServer.cancel(ticketId)
    return try(function() queueMap:RemoveAsync(ticketId) end)
  end

  -- Becomes matchmaker for a few seconds if nobody else is.
  local function acquireLock(now)
    local ok, held = try(function()
      return lockMap:UpdateAsync('matchmaker', function(current)
        if current == nil or current.jobId == jobId or current.expires < now then
          return { jobId = jobId, expires = now + LOCK_TTL }
        end
        return nil -- leave someone else's lock alone
      end, LOCK_TTL)
    end)
    return ok and type(held) == 'table' and held.jobId == jobId
  end

  -- Runs about every 2 seconds from the server loop; `force` runs it right
  -- after a ticket is queued so a full table forms without waiting.
  function CrossServer.tick(now, force)
    if now < nextMatchAt and not force then return 0 end
    nextMatchAt = now + 2
    if not acquireLock(now) then return 0 end
    local ok, entries = try(function() return queueMap:GetRangeAsync(Enum.SortDirection.Ascending, 200) end)
    if not ok or not entries then return 0 end
    local tickets = {}
    for _, entry in ipairs(entries) do
      if type(entry.value) == 'table' then table.insert(tickets, entry.value) end
    end
    local matches = Matchmaker.form(tickets, now)
    for _, match in ipairs(matches) do
      local reserved, accessCode = try(function() return teleport:ReserveServer(placeId) end)
      if reserved and accessCode then
        local matchId = tostring(jobId) .. ':' .. tostring(now) .. ':' .. match.key .. ':' .. tostring(match.tickets[1].id)
        local seats = {}
        for seat, userId in pairs(match.seats) do seats[tostring(seat)] = userId end
        local record = { matchId = matchId, accessCode = accessCode, playerCount = match.playerCount, tier = match.tier,
          fullMatch = match.fullMatch, seats = seats }
        if try(function() matchMap:SetAsync(matchId, record, MATCH_TTL) end) then
          for _, ticket in ipairs(match.tickets) do queueMap:RemoveAsync(ticket.id) end
          try(function() messaging:PublishAsync('TractorMatch', record) end)
        end
      end
    end
    return #matches
  end

  -- Sends `players` (all in this server) to the match's reserved server.
  function CrossServer.travel(record, players)
    return try(function()
      local options = deps.newTeleportOptions()
      options.ReservedServerAccessCode = record.accessCode
      options:SetTeleportData({ matchId = record.matchId })
      teleport:TeleportAsync(placeId, players, options)
    end)
  end

  -- Reserved servers read their match from the shared record (not from the
  -- client-forwarded teleport data, which only carries the id).
  function CrossServer.loadMatch(matchId)
    local ok, record = try(function() return matchMap:GetAsync(matchId) end)
    if not ok or type(record) ~= 'table' then return nil end
    local seats = {}
    for seat, userId in pairs(record.seats or {}) do seats[tonumber(seat)] = userId end
    record.seats = seats
    return record
  end

  -- Squad invite to a friend who may be in another server.
  function CrossServer.invite(toUserId, from)
    return try(function()
      messaging:PublishAsync('TractorInvite', { to = toUserId, fromId = from.userId, fromName = from.name,
        jobId = jobId, placeId = placeId })
    end)
  end

  -- Accepting a remote invite joins the leader's server and squad.
  function CrossServer.followInvite(player, invite)
    return try(function()
      local options = deps.newTeleportOptions()
      options.ServerInstanceId = invite.jobId
      options:SetTeleportData({ joinSquad = invite.fromId })
      teleport:TeleportAsync(invite.placeId, { player }, options)
    end)
  end

  -- Reconnecting: remembers which server holds a player's unfinished round.
  local rejoinMap = memory:GetSortedMap('TractorRejoin')
  function CrossServer.rememberSeat(userId, matchId, seconds)
    return try(function() rejoinMap:SetAsync(tostring(userId), { jobId = jobId, matchId = matchId }, seconds) end)
  end
  function CrossServer.recallSeat(userId)
    local ok, record = try(function() return rejoinMap:GetAsync(tostring(userId)) end)
    return ok and type(record) == 'table' and record or nil
  end
  function CrossServer.forgetSeat(userId)
    return try(function() rejoinMap:RemoveAsync(tostring(userId)) end)
  end
  -- Back to a public server that still has the player's table.
  function CrossServer.rejoinServer(player, targetJobId)
    return try(function()
      local options = deps.newTeleportOptions()
      options.ServerInstanceId = targetJobId
      options:SetTeleportData({ rejoin = true })
      teleport:TeleportAsync(placeId, { player }, options)
    end)
  end

  -- From a match server back to a regular public lobby server.
  function CrossServer.returnToLobby(players)
    return try(function() teleport:TeleportAsync(placeId, players) end)
  end

  return CrossServer
end
