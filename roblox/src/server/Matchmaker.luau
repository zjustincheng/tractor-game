-- Pure matchmaking: groups queued tickets (a solo player or a squad) into
-- matches. A squad always shares one team. Squads with fill on can share their
-- team with other fill tickets; with fill off, their team's spare seats are
-- bots. A match launches when every seat has a person, or when its oldest
-- ticket has waited `maxWait` seconds (bots take the rest).
--
-- ticket = { id, userIds = {...}, playerCount, tier, fullMatch, fill, queuedAt }
-- match  = { key, playerCount, tier, fullMatch, tickets = {...},
--            seats = { [seat] = userId }, humans = n }
return function()
  local Matchmaker = {}
  Matchmaker.MAX_WAIT = 20

  function Matchmaker.modeKey(ticket)
    return ticket.playerCount .. ':' .. ticket.tier .. ':' .. (ticket.fullMatch and 'full' or 'quick')
  end

  function Matchmaker.teamSize(playerCount) return playerCount / 2 end

  -- A ticket is valid if its squad fits on one team.
  function Matchmaker.valid(ticket)
    local count = ticket.playerCount
    if count ~= 4 and count ~= 6 and count ~= 8 and count ~= 10 then return false, 'Choose 4, 6, 8 or 10 players.' end
    if #ticket.userIds < 1 then return false, 'Empty squad.' end
    if #ticket.userIds > Matchmaker.teamSize(count) then
      return false, 'Your squad of ' .. #ticket.userIds .. ' is too big for a ' .. count .. '-player table (teams of ' .. Matchmaker.teamSize(count) .. ').'
    end
    return true
  end

  -- Team A takes odd seats, team B even seats.
  local function seatsFor(team, playerCount)
    local seats = {}
    for seat = team == 1 and 1 or 2, playerCount, 2 do table.insert(seats, seat) end
    return seats
  end

  -- Tries to fit `ticket` onto one of the teams. A team is closed to others
  -- once a no-fill squad sits on it, and a no-fill squad needs an empty team.
  local function place(teams, ticket, size)
    for _, team in ipairs(teams) do
      local used = 0
      for _, t in ipairs(team.tickets) do used = used + #t.userIds end
      local open = #team.tickets == 0 or (ticket.fill and not team.closed)
      if open and used + #ticket.userIds <= size then
        table.insert(team.tickets, ticket)
        if not ticket.fill then team.closed = true end
        return true
      end
    end
    return false
  end

  -- Builds the best match around the oldest ticket of each mode.
  -- Returns matches to launch and the tickets still waiting.
  function Matchmaker.form(tickets, now, maxWait)
    maxWait = maxWait or Matchmaker.MAX_WAIT
    local byMode, order = {}, {}
    for _, ticket in ipairs(tickets) do
      local key = Matchmaker.modeKey(ticket)
      if not byMode[key] then byMode[key] = {}; table.insert(order, key) end
      table.insert(byMode[key], ticket)
    end
    local matches, waiting = {}, {}
    for _, key in ipairs(order) do
      local pool = byMode[key]
      table.sort(pool, function(a, b)
        if a.queuedAt ~= b.queuedAt then return a.queuedAt < b.queuedAt end
        return tostring(a.id) < tostring(b.id)
      end)
      local used = {}
      while true do
        local anchor
        for _, ticket in ipairs(pool) do if not used[ticket] then anchor = ticket; break end end
        if not anchor then break end
        local size = Matchmaker.teamSize(anchor.playerCount)
        local teams = { { tickets = {} }, { tickets = {} } }
        place(teams, anchor, size)
        -- Bigger squads first so they still fit, then by queue age.
        local rest = {}
        for _, ticket in ipairs(pool) do if not used[ticket] and ticket ~= anchor then table.insert(rest, ticket) end end
        table.sort(rest, function(a, b)
          if #a.userIds ~= #b.userIds then return #a.userIds > #b.userIds end
          return a.queuedAt < b.queuedAt
        end)
        local chosen = { anchor }
        local humans = #anchor.userIds
        for _, ticket in ipairs(rest) do
          if humans >= anchor.playerCount then break end
          if place(teams, ticket, size) then
            table.insert(chosen, ticket)
            humans = humans + #ticket.userIds
          end
        end
        local full = humans >= anchor.playerCount
        if full or now - anchor.queuedAt >= maxWait then
          local seats = {}
          for teamIndex, team in ipairs(teams) do
            local free = seatsFor(teamIndex, anchor.playerCount)
            local slot = 1
            for _, ticket in ipairs(team.tickets) do
              for _, userId in ipairs(ticket.userIds) do
                seats[free[slot]] = userId
                slot = slot + 1
              end
            end
          end
          for _, ticket in ipairs(chosen) do used[ticket] = true end
          table.insert(matches, { key = key, playerCount = anchor.playerCount, tier = anchor.tier, fullMatch = anchor.fullMatch,
            tickets = chosen, seats = seats, humans = humans })
        else
          -- The oldest ticket keeps waiting; so does everyone behind it.
          for _, ticket in ipairs(pool) do if not used[ticket] then table.insert(waiting, ticket) end end
          break
        end
      end
    end
    return matches, waiting
  end

  return Matchmaker
end
