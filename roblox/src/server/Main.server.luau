local Players = game:GetService('Players')
local ReplicatedStorage = game:GetService('ReplicatedStorage')
local shared = ReplicatedStorage:WaitForChild('Tractor')
local Cards = require(shared.Cards)
local Catalog = require(shared.Catalog)
local Structures = require(shared.Structures)(Cards)
local Rules = require(shared.PlayRules)(Cards, Structures)
local Scoring = require(shared.Scoring)(Cards)
local Trained = require(script.Parent.TrainedBots)(Cards, Structures, Rules, require(script.Parent.ChampionModel))
local Practice = require(script.Parent.Practice)(Cards, Structures, Rules, Scoring, Trained)
-- DataStores need a published place (and, in Studio, API access enabled).
local progressStore, storeProblem
if game.PlaceId == 0 then
  storeProblem = 'This place is not published, so Roblox cannot save progress. In Studio use File → Publish to Roblox, then Game Settings → Security → Enable Studio Access to API Services.'
else
  local ok, err = pcall(function() progressStore = game:GetService('DataStoreService'):GetDataStore('TractorProgress_v1') end)
  if not ok or not progressStore then
    progressStore = nil
    storeProblem = 'Roblox DataStore is unavailable (' .. tostring(err) .. ').'
  end
end
if storeProblem then warn('[Tractor] Progress saving is OFF: ' .. storeProblem) end

-- Turns a DataStore error into advice the player (or developer) can act on.
local function explainStoreError(err)
  local text = tostring(err)
  if text:find('StudioAccessToApisNotAllowed') or text:find('API Services') or text:find('API access') then
    return 'Studio API access is off. Open Game Settings → Security and turn on Enable Studio Access to API Services, then press Play again.'
  elseif text:find('publish') or text:find('Publish') then
    return 'This place is not published. Use File → Publish to Roblox, enable Studio Access to API Services, then press Play again.'
  end
  return 'Roblox DataStore did not respond (' .. text .. '). Rejoin to try again.'
end
local Persistence = require(script.Parent.Persistence)(progressStore, Catalog, function(seconds)
  if task and task.wait then task.wait(seconds) end
end)
local AUTOSAVE_SECONDS = 60

-- ===== Roblox badges =====
-- IDs live in Catalog.badges (0 = not created yet, skipped). Each badge is
-- tried at most once per session per player; Roblox ignores repeats anyway.
local BadgeService = game:GetService('BadgeService')
local badgesTried = setmetatable({}, { __mode = 'k' }) -- player -> { key = true }
-- Analytics (Creator Hub > Analytics): a new-player funnel and a few custom
-- events. Logging must never interrupt play, so every call is fire-and-forget.
local AnalyticsService = game:GetService('AnalyticsService')
local function funnel(player, step, name)
  task.spawn(pcall, function() AnalyticsService:LogOnboardingFunnelStepEvent(player, step, name) end)
end
local function logEvent(player, name, value)
  task.spawn(pcall, function() AnalyticsService:LogCustomEvent(player, name, value or 1) end)
end
local function awardBadge(player, key)
  local id = Catalog.badges and Catalog.badges[key]
  if not player or type(id) ~= 'number' or id <= 0 then return end
  local tried = badgesTried[player]
  if not tried then tried = {}; badgesTried[player] = tried end
  if tried[key] then return end
  tried[key] = true
  task.spawn(function()
    local ok, has = pcall(function() return BadgeService:UserHasBadgeAsync(player.UserId, id) end)
    if ok and has then return end
    local awarded, err = pcall(function() return BadgeService:AwardBadge(player.UserId, id) end)
    if not awarded then warn('[Tractor] Badge ' .. key .. ' failed: ' .. tostring(err)) end
  end)
end
local HIGH_STAKES = { highroller = true, whale = true, legend = true }

-- ===== Coin leaderboard (global, all servers) =====
-- Each save posts the player's coins to an OrderedDataStore; the top 50 are
-- re-read every 90 seconds and sent to clients that open the leaderboard.
local leaderStore
if progressStore then
  pcall(function() leaderStore = game:GetService('DataStoreService'):GetOrderedDataStore('TractorCoins_v1') end)
end
local LEADER_SIZE = 50
local leaderboard = { entries = {}, updatedAt = 0 }
local nameCache = {}
local function leaderName(userId)
  if nameCache[userId] then return nameCache[userId] end
  local online = Players:GetPlayerByUserId(userId)
  local name = online and online.DisplayName
  if not name then
    local ok, result = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
    name = ok and result or ('Player ' .. tostring(userId))
  end
  nameCache[userId] = name
  return name
end
local function refreshLeaderboard()
  if not leaderStore then return end
  local ok, pages = pcall(function() return leaderStore:GetSortedAsync(false, LEADER_SIZE) end)
  if not ok then warn('[Tractor] Leaderboard read failed: ' .. tostring(pages)) return end
  local list = {}
  for rank, entry in ipairs(pages:GetCurrentPage()) do
    local userId = tonumber(entry.key)
    if userId then table.insert(list, { rank = rank, userId = userId, name = leaderName(userId), coins = entry.value }) end
  end
  leaderboard.entries, leaderboard.updatedAt = list, os.time()
end
local function postLeaderScore(player, coins)
  if not leaderStore then return end
  local ok, err = pcall(function()
    leaderStore:SetAsync(tostring(player.UserId), math.floor(math.clamp(coins or 0, 0, 9e15)))
  end)
  if not ok then warn('[Tractor] Leaderboard write failed: ' .. tostring(err)) end
end
-- ===== Ranked ladder (global, all servers) =====
-- Rank Points live in each player's saved stats; this store only ranks them.
local rankStore
if progressStore then
  pcall(function() rankStore = game:GetService('DataStoreService'):GetOrderedDataStore('TractorRank_v1') end)
end
local rankBoard = { entries = {}, updatedAt = 0 }
local function rankName(points)
  local name = 'Bronze'
  for _, tier in ipairs(Catalog.ranks or {}) do
    if (points or 0) >= tier.at then name = tier.name end
  end
  return name
end
local function refreshRankBoard()
  if not rankStore then return end
  local ok, pages = pcall(function() return rankStore:GetSortedAsync(false, LEADER_SIZE) end)
  if not ok then warn('[Tractor] Rank board read failed: ' .. tostring(pages)) return end
  local list = {}
  for rank, entry in ipairs(pages:GetCurrentPage()) do
    local userId = tonumber(entry.key)
    if userId then table.insert(list, { rank = rank, userId = userId, name = leaderName(userId), points = entry.value, tier = rankName(entry.value) }) end
  end
  rankBoard.entries, rankBoard.updatedAt = list, os.time()
end
local function postRankScore(player, points)
  if not rankStore then return end
  local ok, err = pcall(function()
    rankStore:SetAsync(tostring(player.UserId), math.floor(math.clamp(points or 0, 0, 9e15)))
  end)
  if not ok then warn('[Tractor] Rank board write failed: ' .. tostring(err)) end
end
task.spawn(function()
  while true do
    refreshLeaderboard()
    refreshRankBoard()
    task.wait(90)
  end
end)
local Matchmaker = require(script.Parent.Matchmaker)()
-- Cross-server matchmaking needs a published, live game (MemoryStore,
-- MessagingService and TeleportService do not work in Studio). Otherwise the
-- same matchmaker runs inside this server.
local crossServer
do
  local inStudio = false
  pcall(function() inStudio = game:GetService('RunService'):IsStudio() end)
  if (tonumber(game.PlaceId) or 0) ~= 0 and not inStudio then
    local ok, problem = pcall(function()
      crossServer = require(script.Parent.CrossServer)(Matchmaker, {
        memory = game:GetService('MemoryStoreService'), messaging = game:GetService('MessagingService'),
        teleport = game:GetService('TeleportService'), placeId = game.PlaceId, jobId = game.JobId, warn = warn,
        newTeleportOptions = function() return Instance.new('TeleportOptions') end,
      })
    end)
    if not ok then crossServer = nil; warn('[Tractor] Cross-server matchmaking is off: ' .. tostring(problem)) end
  end
end
local isMatchServer = crossServer ~= nil and (game.PrivateServerId or '') ~= '' and (game.PrivateServerOwnerId or 0) == 0
local remote = Instance.new('RemoteEvent')
remote.Name = 'Action'
remote.Parent = shared
local sessions = {}
local random = Random.new()
local isLive = false
pcall(function()
  local runService = game:GetService('RunService')
  isLive = runService:IsRunning() or runService:IsServer()
end)
local BOT_DELAY = 0.65
-- Defined further down; declared here so earlier functions can call them.
local saveProgress, refreshVip

local function formatK(n)
  n = tonumber(n) or 0
  if n >= 1000000 then
    local m = n / 1000000
    return (m % 1 == 0 and string.format("%dM", m)) or string.format("%.1fM", m)
  elseif n >= 1000 then
    local k = n / 1000
    return (k % 1 == 0 and string.format("%dK", k)) or string.format("%.1fK", k)
  else
    return tostring(n)
  end
end

-- (relayReaction is defined after the seat helpers below.)
-- ==========================================================
-- Shared tables: people take seats, bots fill the rest.
-- ==========================================================
local tables, tableCodes, nextTableId = {}, {}, 0
-- Bot names/avatars by absolute seat; the client shows whoever sits there.
local BOT_NAMES = { 'Telamon', 'Shedletsky', 'Builderman', 'Roblox', 'Matt Dusek', 'BrightEyes', 'Reese', 'Stickmaster', 'Clockwork', 'Erik Cassel' }
local BOT_IDS = { 13645, 261, 156, 1, 16, 18, 20, 158, 684360, 2868 }
local PUBLIC_WAIT_SECONDS = 6 -- a public table waits this long for others to join
local TURN_SECONDS = { tricks = 25, kitty = 45 } -- only enforced with 2+ people
local REVIEW_SECONDS = 2.5 -- completed tricks auto-advance with 2+ people

local function relSeat(tbl, viewer, abs) return (abs - viewer) % tbl.playerCount + 1 end
local function absSeat(tbl, viewer, rel) return (rel - 1 + viewer - 1) % tbl.playerCount + 1 end
local function humanCount(tbl) local n = 0; for _ in pairs(tbl.members) do n = n + 1 end; return n end
local function seatName(tbl, abs)
  local member = tbl.members[abs]
  return member and member.DisplayName or BOT_NAMES[abs] or ('Seat ' .. abs)
end

-- Table summary from one member's seat (seats rotated so they are seat 1).
local function tableView(tbl, viewer)
  local seatsInfo = {}
  for abs = 1, tbl.playerCount do
    local member = tbl.members[abs]
    seatsInfo[relSeat(tbl, viewer, abs)] = {
      name = seatName(tbl, abs),
      userId = member and member.UserId or BOT_IDS[abs],
      human = member ~= nil,
      host = member ~= nil and member == tbl.host,
      frame = member and sessions[member] and sessions[member].equipped.frame or nil,
      title = member and sessions[member] and sessions[member].equipped.title or nil,
      banner = member and sessions[member] and sessions[member].equipped.banner or nil,
    }
  end
  return {
    id = tbl.id, code = tbl.code, private = tbl.private, isHost = tbl.members[viewer] == tbl.host,
    playerCount = tbl.playerCount, tier = tbl.tier, fullMatch = tbl.fullMatch,
    status = tbl.game and 'playing' or 'waiting', startsAt = tbl.startAt, humans = humanCount(tbl), seats = seatsInfo,
  }
end

local squadView, lobbyList, squadsOpen -- defined with squads below

-- Double (加倍): each player may double their own stake for the round, but
-- only during the short window that opens once Chao Di is finished.
local function canDouble(game, seat)
  if not game or game.done or game.phase ~= 'doubling' then return false end
  if game.doubled and game.doubled[seat] then return false end
  return true
end

-- True once every person at the table has doubled, so the window can close.
local function everyoneDoubled(game)
  for seat in pairs(game.humans or {}) do
    if not (game.doubled and game.doubled[seat]) then return false end
  end
  return true
end

local function send(player, session, message, coinBonus)
  if (session.coins or 0) >= 1000000 then awardBadge(player, 'millionaire') end
  local earned = Persistence.grantEarned(session)
  if #earned > 0 then
    local names = {}
    for _, item in ipairs(earned) do table.insert(names, item.label) end
    message = (message and (message .. ' · ') or '') .. '🏅 Profile unlock: ' .. table.concat(names, ', ')
  end
  local stats = player:FindFirstChild('leaderstats')
  local coinStat = stats and stats:FindFirstChild('Coins')
  if coinStat then coinStat.Value = math.floor(session.coins or 0) end
  local tbl = session.table
  local view
  if tbl and tbl.game then
    view = Practice.relativeView(tbl.game, session.seat)
    view.turnDeadline = tbl.turnDeadline
    view.canDouble = canDouble(tbl.game, session.seat)
    view.doubled = (tbl.game.doubled and tbl.game.doubled[session.seat]) == true
    -- Everyone who has doubled this round, as seats relative to this viewer (1 = you),
    -- so clients can announce other players' Doubles too.
    local count = tbl.game.playerCount or 4
    view.doubledSeats = {}
    for seat, on in pairs(tbl.game.doubled or {}) do
      if on then table.insert(view.doubledSeats, (seat - session.seat) % count + 1) end
    end
    -- This player's own settlement figures (payout, multipliers) for the round.
    if view.settlement and session.settlementKey == tbl.roundKey and session.settlementExtra then
      for key, value in pairs(session.settlementExtra) do view.settlement[key] = value end
    end
  end
  remote:FireClient(player, {
    game = view,
    table = tbl and tableView(tbl, session.seat),
    squad = squadView and squadView(player, session),
    search = session.search,
    invites = session.invites and (function()
      local list = {}
      for _, invite in pairs(session.invites) do table.insert(list, { fromId = invite.fromId, fromName = invite.fromName }) end
      return list
    end)(),
    lobby = lobbyList and lobbyList(player, session),
    openSquads = squadsOpen and squadsOpen(player, session),
    crossServer = crossServer ~= nil,
    matchServer = isMatchServer,
    coins = session.coins,
    dailyClaimed = session.lastDailyDay == Persistence.today(),
    streakDay = Persistence.streakDay(session),
    nextGiftAt = session.nextGiftAt,
    mailClaimed = session.mailClaimed,
    -- First-time players get the tutorial; anyone who already played a round skips it.
    tutorialDone = session.tutorialDone == true or ((session.stats and session.stats.roundsPlayed or 0) > 0),
    vaultCoins = session.vaultCoins or 1500,
    luckySpinAt = session.luckySpinAt or 0,
    luckySpun = session.luckyDay == Persistence.today(),
    luckyResetIn = 86400 - os.time() % 86400,
    luckyResult = session.luckyResult,
    quests = session.quests,
    owned = session.owned,
    equipped = session.equipped,
    message = message,
    coinBonus = coinBonus,
    saving = session.saveStatus,
    stats = session.stats,
    rejoinOffer = (session.rejoinOffer or 0) > os.time() or nil,
    vip = session.vip == true,
    pass = session.pass,
    markersLeft = Persistence.markersLeft(session),
    serverTime = os.clock(),
    seat = 1,
  })
end
-- Sends a reaction to everyone at the sender's table. Each copy says which
-- seat it came from and where it is aimed, from that receiver's point of view.
local function relayReaction(player, session, payload, target)
  local tbl = session.table
  if not tbl then
    payload.fromSeat, payload.target = 1, target
    remote:FireClient(player, payload)
    return
  end
  local fromAbs = session.seat
  local targetRel = type(target) == 'string' and tonumber(string.match(target, '^seat(%d+)$'))
  local targetAbs = targetRel and targetRel >= 1 and targetRel <= tbl.playerCount and absSeat(tbl, fromAbs, targetRel) or nil
  for seat, member in pairs(tbl.members) do
    local copy = {}
    for key, value in pairs(payload) do copy[key] = value end
    copy.fromSeat = relSeat(tbl, seat, fromAbs)
    copy.target = targetAbs and ('seat' .. relSeat(tbl, seat, targetAbs)) or target
    remote:FireClient(member, copy)
  end
end
local function broadcast(tbl, message)
  for _, member in pairs(tbl.members) do
    local session = sessions[member]
    if session then send(member, session, message) end
  end
end
local function pick(maximum) return random:NextInteger(1, maximum) end

local function makeBotCoins(playerCount, botScale)
  local result = {}
  for seat = 1, playerCount do
    result[seat] = math.floor(botScale * (seat % 2 == 0 and 0.95 or 1.05) + math.random(100, 500))
  end
  return result
end

local TIER_CONFIG = {
  novice = { name = 'Novice Table', min = 2000, max = 60000, base = 500, ante = 100 },
  pro = { name = 'Pro Lounge', min = 8000, max = 200000, base = 1500, ante = 400 },
  master = { name = 'Master Arena', min = 100000, max = math.huge, base = 5000, ante = 1500 },
  -- High Stakes rooms: big bases, and a loss can cost everything you carry.
  highroller = { name = 'High Roller', min = 250000, max = math.huge, base = 15000, ante = 4500 },
  whale = { name = 'Whale Room', min = 1000000, max = math.huge, base = 60000, ante = 18000 },
  legend = { name = 'Legend Vault', min = 5000000, max = math.huge, base = 250000, ante = 75000 },
}

-- Coins per captured point at each table, paid only on rounds you win; Chao Di
-- multiplies them.
local POINT_COINS = { novice = 10, pro = 30, master = 100, highroller = 300, whale = 1200, legend = 5000 }

-- Tallies your team's captured points once per completed trick. The coins are
-- credited with the round settlement, not immediately; the vault and points
-- quest still progress as tricks are won.
-- `state` is this player's rotated view, so winnerSeat parity means their team.
local function payTrickCoins(session, state)
  if session.paidRound ~= state.roundKey then
    session.paidRound, session.paidTricks, session.matchTrickCoins = state.roundKey, {}, 0
  end
  local paid = 0
  for _, entry in ipairs(state.history or {}) do
    if not session.paidTricks[entry.number] then
      session.paidTricks[entry.number] = true
      local points = entry.points or 0
      if points > 0 and entry.winnerSeat % 2 == 1 then
        local coins = points * (POINT_COINS[state.tier] or POINT_COINS.novice)
        session.matchTrickCoins = (session.matchTrickCoins or 0) + coins
        session.vaultCoins = (session.vaultCoins or 0) + math.max(50, math.floor(points * 2))
        paid = paid + coins
        if session.quests and session.quests.points then
          session.quests.points.progress = math.min(session.quests.points.target, session.quests.points.progress + points)
        end
      end
    end
  end
  return paid
end

-- Odd seats first so friends who join together become teammates.
local function seatOrder(count)
  local order = {}
  for seat = 1, count, 2 do table.insert(order, seat) end
  for seat = 2, count, 2 do table.insert(order, seat) end
  return order
end

local function joinTable(player, session, tbl)
  for _, seat in ipairs(seatOrder(tbl.playerCount)) do
    if not tbl.members[seat] then
      tbl.members[seat] = player
      session.table, session.seat, session.game = tbl, seat, tbl.game
      if tbl.game then Practice.setHuman(tbl.game, seat, true) end
      return seat
    end
  end
  return nil
end

local CODE_LETTERS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function createTable(player, session, options)
  nextTableId = nextTableId + 1
  local tbl = { id = nextTableId, playerCount = options.playerCount, tier = options.tier, fullMatch = options.fullMatch,
    private = options.private, host = player, members = {}, serial = 0 }
  if options.private then
    repeat
      local code = ''
      for _ = 1, 4 do local index = pick(#CODE_LETTERS); code = code .. string.sub(CODE_LETTERS, index, index) end
      tbl.code = code
    until not tableCodes[tbl.code]
    tableCodes[tbl.code] = tbl
  end
  tables[tbl.id] = tbl
  joinTable(player, session, tbl)
  return tbl
end

local function resetTimers(tbl)
  tbl.startAt, tbl.nextBotAt, tbl.nextChaodiAt, tbl.waitKey, tbl.turnDeadline, tbl.reviewUntil = nil, nil, nil, nil, nil, nil
end
local function shareGame(tbl)
  for _, member in pairs(tbl.members) do
    local session = sessions[member]
    if session then session.game = tbl.game end
  end
end

-- Deals a new match. Quick Match settles after one round at a random level;
-- a full match starts both teams at 2 and continues until a team passes Ace.
local function startGame(tbl, now)
  local cfg = TIER_CONFIG[tbl.tier] or TIER_CONFIG.novice
  local humans = {}
  for seat in pairs(tbl.members) do humans[seat] = true end
  tbl.serial = tbl.serial + 1
  tbl.roundKey = tbl.id .. ':' .. tbl.serial
  local revision = tbl.game and tbl.game.revision + 1 or 0
  tbl.game = Practice.new(pick, now, { playerCount = tbl.playerCount, quickMatch = not tbl.fullMatch, dealingDuration = 5.5,
    paced = isLive, humans = humans, revision = revision })
  tbl.game.tier = tbl.tier
  local hostSession = tbl.host and sessions[tbl.host]
  local botScale = math.clamp(hostSession and hostSession.coins or cfg.base * 20, cfg.base * 10, cfg.base * 50)
  tbl.game.botCoins = makeBotCoins(tbl.playerCount, botScale)
  resetTimers(tbl)
  shareGame(tbl)
  return cfg
end

-- Moves a full match on to its next round at the same table.
local function continueMatch(tbl, now)
  local nextState, reason = Practice.nextRound(tbl.game, pick, now)
  if not nextState then return nil, reason end
  nextState.tier = tbl.game.tier
  nextState.botCoins = tbl.game.botCoins
  nextState.humans = {}
  for seat in pairs(tbl.members) do nextState.humans[seat] = true end
  tbl.serial = tbl.serial + 1
  tbl.roundKey = tbl.id .. ':' .. tbl.serial
  tbl.game = nextState
  resetTimers(tbl)
  shareGame(tbl)
  return nextState
end

-- A leaving player's seat goes to a bot; empty tables close.
local function leaveTable(player, session)
  local tbl = session.table
  if not tbl then return end
  tbl.members[session.seat] = nil
  if tbl.game then Practice.setHuman(tbl.game, session.seat, false) end
  session.table, session.seat, session.game = nil, 1, nil
  if tbl.host == player then
    tbl.host = nil
    for _, seat in ipairs(seatOrder(tbl.playerCount)) do
      if tbl.members[seat] then tbl.host = tbl.members[seat]; break end
    end
  end
  if humanCount(tbl) == 0 then
    tables[tbl.id] = nil
    if tbl.code then tableCodes[tbl.code] = nil end
    return
  end
  if tbl.game and not isLive then Practice.bots(tbl.game) end
  broadcast(tbl, player.DisplayName .. ' left the table; a bot took their seat.')
end

-- ==========================================================
-- Squads (parties) and matchmaking
-- ==========================================================
local squads, nextSquadId, nextTicketId = {}, 0, 0
local localTickets = {} -- this server's queue when cross-server play is unavailable
local MAX_SQUAD = 5 -- the largest team (10-player tables)
local ARRIVAL_WAIT = 15 -- a match server waits this long for teleporting players

local function playerByUserId(userId)
  for player in pairs(sessions) do
    if player.UserId == userId then return player end
  end
  return nil
end
local function squadMembers(player, session)
  return session.squad and session.squad.members or { player }
end
squadView = function(player, session)
  local squad = session.squad
  if not squad then return { solo = true, isLeader = true, public = session.public ~= false, members = { { name = player.DisplayName, userId = player.UserId, leader = true } } } end
  local members = {}
  for _, member in ipairs(squad.members) do
    table.insert(members, { name = member.DisplayName, userId = member.UserId, leader = member == squad.leader })
  end
  return { id = squad.id, isLeader = squad.leader == player, public = squad.public, members = members }
end
lobbyList = function(player, session)
  local list = {}
  for other, otherSession in pairs(sessions) do
    if other ~= player and #list < 30 then
      local together = session.squad ~= nil and otherSession.squad == session.squad
      table.insert(list, { name = other.DisplayName, userId = other.UserId, inSquad = together, busy = otherSession.table ~= nil })
    end
  end
  table.sort(list, function(a, b) return a.name < b.name end)
  return list
end
-- Public squads in this server with room, excluding your own.
local function openSquads(player, session)
  local list = {}
  for other, otherSession in pairs(sessions) do
    local squad = otherSession.squad
    local isLeader = squad == nil or squad.leader == other
    local public = squad and squad.public or (squad == nil and otherSession.public ~= false)
    local size = squad and #squad.members or 1
    if other ~= player and isLeader and public and size < MAX_SQUAD and (session.squad == nil or session.squad ~= squad) and #list < 20 then
      table.insert(list, { leaderId = other.UserId, leaderName = other.DisplayName, size = size, playing = otherSession.table ~= nil })
    end
  end
  table.sort(list, function(a, b) return a.leaderName < b.leaderName end)
  return list
end
squadsOpen = openSquads
local function sendSquad(squad, message)
  for _, member in ipairs(squad.members) do
    local session = sessions[member]
    if session then send(member, session, message) end
  end
end

-- Stops a search for everyone it covers.
local function cancelSearch(player, session, message)
  local search = session.search
  if not search then return end
  if crossServer then crossServer.cancel(search.ticketId) end
  for index, ticket in ipairs(localTickets) do
    if ticket.id == search.ticketId then table.remove(localTickets, index) break end
  end
  for _, member in ipairs(squadMembers(player, session)) do
    local memberSession = sessions[member]
    if memberSession and memberSession.search and memberSession.search.ticketId == search.ticketId then
      memberSession.search = nil
      if message then send(member, memberSession, message) end
    end
  end
end

local function leaveSquad(player, session, message)
  local squad = session.squad
  if not squad then return end
  cancelSearch(player, session, 'Search cancelled: your squad changed.')
  for index, member in ipairs(squad.members) do
    if member == player then table.remove(squad.members, index) break end
  end
  session.squad = nil
  if squad.leader == player then squad.leader = squad.members[1] end
  if #squad.members <= 1 then
    squads[squad.id] = nil
    local last = squad.members[1]
    if last and sessions[last] then
      sessions[last].squad = nil
      send(last, sessions[last], message or (player.DisplayName .. ' left the squad.'))
    end
  else
    sendSquad(squad, message or (player.DisplayName .. ' left the squad.'))
  end
end

local function createSquad(player, session)
  nextSquadId = nextSquadId + 1
  local squad = { id = nextSquadId, leader = player, members = { player }, public = session.public ~= false, invited = {} }
  squads[squad.id] = squad
  session.squad = squad
  return squad
end

-- An invite waits in the target's session until accepted or declined.
local function deliverInvite(target, invite)
  local session = sessions[target]
  if not session then return end
  session.invites = session.invites or {}
  session.invites[invite.fromId] = invite
  remote:FireClient(target, { type = 'invite', fromId = invite.fromId, fromName = invite.fromName })
  send(target, session)
end

local function seatAt(player, session, tbl, seat)
  tbl.members[seat] = player
  session.table, session.seat, session.game = tbl, seat, tbl.game
  if tbl.game then Practice.setHuman(tbl.game, seat, true) end
end

-- A formed match becomes a table in this server (used when cross-server play
-- is unavailable, e.g. in Studio).
local function launchLocalMatch(match, now)
  nextTableId = nextTableId + 1
  local tbl = { id = nextTableId, playerCount = match.playerCount, tier = match.tier, fullMatch = match.fullMatch,
    private = false, members = {}, serial = 0 }
  tables[tbl.id] = tbl
  for _, seat in ipairs(seatOrder(match.playerCount)) do
    local player = match.seats[seat] and playerByUserId(match.seats[seat])
    local session = player and sessions[player]
    if session then
      session.search = nil
      if session.table then leaveTable(player, session) end
      seatAt(player, session, tbl, seat)
      tbl.host = tbl.host or player
    end
  end
  if not tbl.host then tables[tbl.id] = nil return end
  startGame(tbl, now)
  broadcast(tbl, humanCount(tbl) > 1 and ('Match found: ' .. humanCount(tbl) .. ' players at the table!') or 'No other players found yet, so bots fill the table.')
end

local function localMatchmaking(now)
  if crossServer or #localTickets == 0 then return end
  local matches, waiting = Matchmaker.form(localTickets, now)
  localTickets = waiting
  for _, match in ipairs(matches) do launchLocalMatch(match, now) end
end

-- Queues the player's squad (or just them) for a mode.
local function startSearch(player, session, options, cfg, now)
  if session.squad and session.squad.leader ~= player then
    send(player, session, 'Only the squad leader can start matchmaking.') return
  end
  local members = squadMembers(player, session)
  local userIds = {}
  for _, member in ipairs(members) do
    local memberSession = sessions[member]
    if memberSession and memberSession.coins < cfg.min then
      send(player, session, member.DisplayName .. ' needs ' .. formatK(cfg.min) .. ' coins for ' .. cfg.name .. '.') return
    end
    table.insert(userIds, member.UserId)
  end
  nextTicketId = nextTicketId + 1
  local ticket = { id = tostring(game.JobId or 'local') .. ':' .. nextTicketId, userIds = userIds, playerCount = options.playerCount,
    tier = options.tier, fullMatch = options.fullMatch, fill = true,
    queuedAt = crossServer and os.time() or now }
  local valid, problem = Matchmaker.valid(ticket)
  if not valid then send(player, session, problem) return end
  cancelSearch(player, session)
  for _, member in ipairs(members) do
    local memberSession = sessions[member]
    if memberSession then
      if memberSession.table then leaveTable(member, memberSession) end
      memberSession.search = { ticketId = ticket.id, startedAt = now, playerCount = options.playerCount, tier = options.tier,
        fullMatch = options.fullMatch, squadSize = #members }
    end
  end
  if crossServer then
    if not crossServer.enqueue(ticket) then
      for _, member in ipairs(members) do if sessions[member] then sessions[member].search = nil end end
      send(player, session, 'Matchmaking is unavailable right now. Try again shortly.') return
    end
  else
    table.insert(localTickets, ticket)
  end
  for _, member in ipairs(members) do
    if sessions[member] then send(member, sessions[member], 'Searching for players…') end
  end
  if crossServer then crossServer.tick(os.time(), true) else localMatchmaking(now) end
end

if crossServer then
  -- A match formed anywhere: send our players named in it to its server.
  crossServer.onMatch(function(record)
    local travellers = {}
    for _, userId in pairs(record.seats or {}) do
      local player = playerByUserId(userId)
      local session = player and sessions[player]
      if session then
        session.search = nil
        send(player, session, 'Match found! Teleporting to your table…')
        table.insert(travellers, player)
      end
    end
    if #travellers > 0 then crossServer.travel(record, travellers) end
  end)
  crossServer.onInvite(function(invite)
    local player = playerByUserId(invite.to)
    if player and invite.jobId ~= game.JobId then deliverInvite(player, invite) end
  end)
end

-- Match servers: seat each arriving player where the match record says.
local matchTables = {}
local function arriveForMatch(player, session, joinData, now)
  if not crossServer or type(joinData) ~= 'table' then return false end
  if joinData.joinSquad then
    local leader = playerByUserId(joinData.joinSquad)
    local squad = leader and sessions[leader] and sessions[leader].squad
    if squad and squad.invited[player.UserId] and #squad.members < MAX_SQUAD then
      squad.invited[player.UserId] = nil
      table.insert(squad.members, player)
      session.squad = squad
      sendSquad(squad, player.DisplayName .. ' joined the squad.')
    end
    return false
  end
  if type(joinData.matchId) ~= 'string' then return false end
  local tbl = matchTables[joinData.matchId]
  -- A reconnecting player whose match table has since closed has no seat.
  if tbl and tables[tbl.id] ~= tbl then return false end
  if not tbl then
    local record = crossServer.loadMatch(joinData.matchId)
    if not record then return false end
    nextTableId = nextTableId + 1
    tbl = { id = nextTableId, playerCount = record.playerCount, tier = record.tier, fullMatch = record.fullMatch,
      private = false, members = {}, serial = 0, expected = record.seats, startAt = now + ARRIVAL_WAIT, matchId = joinData.matchId }
    tables[tbl.id] = tbl
    matchTables[joinData.matchId] = tbl
  end
  for seat, userId in pairs(tbl.expected) do
    if userId == player.UserId and not tbl.members[seat] then
      seatAt(player, session, tbl, seat)
      tbl.host = tbl.host or player
    end
  end
  if session.table ~= tbl then return false end -- not in this match's record
  local everyone = true
  for seat in pairs(tbl.expected) do if not tbl.members[seat] then everyone = false end end
  if everyone and not tbl.game then tbl.startAt = now end
  broadcast(tbl, player.DisplayName .. ' arrived.')
  return true
end

-- Settles one player's round. `state` is that player's rotated view (their
-- team is A); the caller guarantees this runs once per player per round.
local function awardMatchCompletion(player, session, state)
  payTrickCoins(session, state)
  -- What you carried into the round caps what the result can win you.
  local carriedIn = session.coins

  local settlement = state.settlement
  local isAttacking = state.attackingTeam == 'A'
  local advancingRole = settlement and settlement.outcome and settlement.outcome.advancingRole
  local advancingTeam = advancingRole and (advancingRole == 'attackers' and state.attackingTeam or (state.attackingTeam == 'A' and 'B' or 'A')) or (isAttacking and 'A' or 'B')
  local userWon = (advancingTeam == 'A')

  -- Captured-point coins are paid only on a win, at the round's final Chao Di stake.
  local roundTrickCoins = userWon and (session.matchTrickCoins or 0) * (state.chaodiMultiplier or 1) or 0
  session.coins = session.coins + roundTrickCoins

  local defScore = (settlement and settlement.defenderScore) or ((state.points and (state.points[isAttacking and 2 or 1] or 0) or 0) + (state.penaltyPoints or 0))

  -- 1. Tencent Kuaile Shengji Grade Multiplier (输赢级数/胜负倍数)
  local gradeMultiplier, gradeName = Scoring.payoutGrade(advancingRole or 'attackers', defScore, state.playerCount)

  -- 2. Tencent Kitty Multiplier (抠底翻倍: 单张×2, 对子×4, 拖拉机×8)
  local kittyFactor = 1
  local kittyMult = (settlement and settlement.kittyMultiplier) or 0
  if kittyMult > 0 and advancingRole == 'defenders' then
    if kittyMult >= 8 then
      kittyFactor = 8
    elseif kittyMult >= 4 then
      kittyFactor = 4
    elseif kittyMult >= 2 then
      kittyFactor = 2
    end
  end

  -- 3. Tencent Chao Di Multiplier (炒底倍数: ×2, ×4, ×8...)
  local chaodiFactor = state.chaodiMultiplier or 1

  -- 4. Your own Double (加倍) before your first play.
  local doubleFactor = state.selfDoubled and 2 or 1

  -- Total Multiplier (grade × kitty × chaodi × double)
  -- Every Chao Di doubles the stake; the cap leaves room for several rounds of it.
  local totalMultiplier = math.min(512, gradeMultiplier * kittyFactor * chaodiFactor * doubleFactor)

  -- 4. Tencent 携带输赢原则 (Wallet Cap: scaled with own coins and opponents' carried coins)
  local cfg = TIER_CONFIG[state.tier] or TIER_CONFIG.novice
  local baseStake = cfg.base
  local botCoins = state.botCoins or {}
  local oppCarried = 0
  for seat = 2, state.playerCount, 2 do
    oppCarried = oppCarried + (botCoins[seat] or baseStake * 20)
  end
  if oppCarried <= 0 then oppCarried = baseStake * 40 end

  local userCarried = carriedIn
  -- 携带输赢: you can win at most what you carried in (and no more than the
  -- losing side holds), and lose at most what you carry.
  local winLossCap = userWon and math.min(userCarried, oppCarried) or session.coins
  local cappedByWallet = userWon and userCarried < oppCarried and userCarried < baseStake * totalMultiplier
  -- Tencent-style room settlement: the selected room's base stake is multiplied
  -- by the hand result. Carrying more coins unlocks higher rooms; it does not
  -- create an arbitrary percentage bonus inside a room.
  local uncappedAmount = baseStake * totalMultiplier
  local rawAmount = math.min(winLossCap, uncappedAmount)

  local netAmount = 0
  local tax = 0
  local relief = 0

  if userWon then
    tax = math.min(cfg.ante, rawAmount)
    netAmount = rawAmount - tax
    session.coins = session.coins + netAmount
    if state.botCoins then
      local remaining = rawAmount
      for seat = 2, state.playerCount, 2 do
        local carried = state.botCoins[seat] or 0
        local taken = math.min(carried, remaining)
        state.botCoins[seat] = carried - taken
        remaining = remaining - taken
        if remaining <= 0 then break end
      end
    end
  else
    local loss = math.min(session.coins, rawAmount + math.min(cfg.ante, rawAmount))
    session.coins = session.coins - loss
    netAmount = -loss
    if state.botCoins then
      local botTeam = {}
      for seat = 2, state.playerCount, 2 do table.insert(botTeam, seat) end
      local remaining = loss
      for index, seat in ipairs(botTeam) do
        local share = index == #botTeam and remaining or math.floor(loss / #botTeam)
        state.botCoins[seat] = (state.botCoins[seat] or 0) + share
        remaining = remaining - share
      end
    end
    if session.coins < 1000 then
      relief = 2000
      session.coins = session.coins + relief
    end
  end

  -- VIP pass: winnings are paid twice (a bonus on top, not taken from bots).
  local vipBonus = 0
  if session.vip and userWon and netAmount > 0 then
    vipBonus = netAmount
    session.coins = session.coins + vipBonus
  end

  local matchBonus = 0
  if not state.quickMatch and settlement and settlement.winner == 'A' then
    matchBonus = baseStake * 10
    session.coins = session.coins + matchBonus
  end
  session.vaultCoins = (session.vaultCoins or 0) + 500
  session.matchTrickCoins = 0
  if session.quests and session.quests.play then
    session.quests.play.progress = math.min(session.quests.play.target, session.quests.play.progress + 1)
  end

  if settlement then
    settlement.userWon = userWon
    settlement.baseStake = baseStake
    settlement.gradeMultiplier = gradeMultiplier
    settlement.kittyFactor = kittyFactor
    settlement.chaodiFactor = chaodiFactor
    settlement.doubleFactor = doubleFactor
    settlement.totalMultiplier = totalMultiplier
    settlement.roomBase = baseStake
    settlement.roomFee = math.min(cfg.ante, rawAmount)
    settlement.gradeName = gradeName
    settlement.userCarried = userCarried
    settlement.oppCarried = oppCarried
    settlement.winLossCap = winLossCap
    settlement.cappedByWallet = cappedByWallet
    settlement.tax = tax
    settlement.netCoins = netAmount
    settlement.earnedCoins = netAmount
    settlement.reliefCoins = relief
    settlement.matchBonus = matchBonus
    settlement.vipBonus = vipBonus
    settlement.trickCoins = roundTrickCoins
  end

  local msg
  if userWon then
    msg = string.format('🏆 VICTORY! +%s Coins (Room %s × %dx %s · Fee %s%s%s)',
      formatK(netAmount), formatK(baseStake), totalMultiplier, gradeName, formatK(tax),
      chaodiFactor > 1 and string.format(' · 炒底×%d', chaodiFactor) or '', doubleFactor > 1 and ' · Doubled ×2' or '')
    if vipBonus > 0 then msg = msg .. ' · VIP ×2 +' .. formatK(vipBonus) end
    if matchBonus > 0 then msg = msg .. ' · 🏁 Match won! +' .. formatK(matchBonus) end
  else
    msg = string.format('Match Complete! -%s Coins (Room %s × %dx · Fee %s%s%s)',
      formatK(math.abs(netAmount)), formatK(baseStake), totalMultiplier, formatK(tax),
      chaodiFactor > 1 and string.format(' · 炒底×%d', chaodiFactor) or '', doubleFactor > 1 and ' · Doubled ×2' or '')
    if relief > 0 then
      msg = msg .. ' · 🎁 +2K Relief Granted!'
    end
  end
  if roundTrickCoins > 0 then msg = msg .. ' · Points +' .. formatK(roundTrickCoins) end
  local gained = roundTrickCoins + math.max(0, netAmount) + vipBonus + matchBonus

  -- Lifetime stats (saved with progress).
  local stats = session.stats
  local function bump(key, amount) stats[key] = (stats[key] or 0) + (amount or 1) end
  bump('roundsPlayed')
  if stats.roundsPlayed == 1 then funnel(player, 3, 'First round finished') end
  logEvent(player, 'RoundPlayed_' .. tostring(state.tier or 'unknown'))
  -- Ranked ladder. RP scales with how decisive the round was (the levels the
  -- winning team took), so a shutout is worth far more than a squeaker:
  --   against people   win +30 / +40 / +50    loss -25 / -30 / -35
  --   against bots     win +15 / +20 / +25    loss -17 / -20 / -23
  -- Bot tables move it about half as much and are slightly negative at an even
  -- win rate, so the ladder measures wins against people, not bot grinding.
  -- Points never drop below 0 and Bronze (under 100) never loses any.
  do
    local tbl, vsPeople = session.table, false
    if tbl then
      for seat in pairs(tbl.members) do
        if Cards.team(seat) ~= Cards.team(session.seat) then vsPeople = true end
      end
    end
    local levels = math.clamp((settlement and settlement.outcome and settlement.outcome.levels) or 1, 1, 3)
    local before = stats.rankPoints or 0
    local delta
    if userWon then delta = vsPeople and (20 + 10 * levels) or (10 + 5 * levels)
    elseif before < 100 then delta = 0
    else delta = vsPeople and -(20 + 5 * levels) or -(14 + 3 * levels) end
    stats.rankPoints = math.max(0, before + delta)
    local change = stats.rankPoints - before
    if settlement then settlement.rankDelta, settlement.rankPoints, settlement.rankTier = change, stats.rankPoints, rankName(stats.rankPoints) end
    if change ~= 0 then
      msg = msg .. string.format(' · Rank %s%d (%s %d RP)', change > 0 and '+' or '', change, rankName(stats.rankPoints), stats.rankPoints)
    end
    if rankName(stats.rankPoints) ~= rankName(before) and change > 0 then
      msg = msg .. ' · Promoted to ' .. rankName(stats.rankPoints) .. '!'
    end
  end
  if HIGH_STAKES[state.tier] then awardBadge(player, 'high_roller') end
  if userWon then
    bump('roundsWon')
    if stats.roundsWon == 1 then funnel(player, 4, 'First win') end
    awardBadge(player, 'first_win')
    stats.bestGrade = math.max(stats.bestGrade or 0, totalMultiplier)
  end
  if not state.quickMatch and settlement and settlement.winner == 'A' then bump('matchesWon') end
  if advancingRole == 'attackers' and isAttacking and defScore <= 0 then
    bump('shutouts')
    awardBadge(player, 'shutout')
  end
  if advancingRole == 'defenders' and not isAttacking then bump('overturns') end
  stats.biggestWin = math.max(stats.biggestWin or 0, gained)
  bump('coinsEarned', gained)
  local passXp = Persistence.passAddXp(session, userWon, advancingRole == 'attackers' and isAttacking and defScore <= 0, os.time())
  if passXp > 0 then msg = msg .. ' · 🎟 +' .. passXp .. ' Pass XP' end
  session.settlementExtra, session.settlementKey = settlement, state.roundKey
  send(player, session, msg, gained > 0 and gained or nil)
end

-- Settles a finished round for every person at the table, once each.
-- Returns the members settled (and already messaged) by this call.
local function rewardMembers(tbl)
  local settled = {}
  for seat, member in pairs(tbl.members) do
    local session = sessions[member]
    if session and session.rewardedKey ~= tbl.roundKey then
      session.rewardedKey = tbl.roundKey
      local view = Practice.relativeView(tbl.game, seat)
      view.roundKey = tbl.roundKey
      view.selfDoubled = tbl.game.doubled and tbl.game.doubled[seat] or nil
      awardMatchCompletion(member, session, view)
      settled[member] = true
      -- Coins just changed hands; save now instead of waiting for autosave.
      task.spawn(saveProgress, member, session, false)
      -- Bot balances changed in this player's view; keep them for bot seats.
      for rel, coins in pairs(view.botCoins or {}) do
        local abs = absSeat(tbl, seat, rel)
        if not tbl.members[abs] then tbl.game.botCoins[abs] = coins end
      end
    end
  end
  return settled
end

-- Vault/quest progress as tricks complete (coins are paid at settlement).
local function trackTricks(tbl)
  if tbl.game.phase ~= 'trick-review' then return end
  for seat, member in pairs(tbl.members) do
    local session = sessions[member]
    if session then
      local view = Practice.relativeView(tbl.game, seat)
      view.roundKey = tbl.roundKey
      payTrickCoins(session, view)
    end
  end
end

-- Starts the idle timer when a person becomes the one the table waits on
-- (only with several people). Returns the waiting seat, if any.
local function refreshDeadline(tbl, now)
  local game = tbl.game
  if humanCount(tbl) < 2 or game.done then tbl.waitKey, tbl.turnDeadline = nil, nil return nil end
  local waitingSeat = (game.phase == 'tricks' and game.turn) or (game.phase == 'kitty' and (game.kittyHolder or game.dealer)) or nil
  if not (waitingSeat and Practice.isHuman(game, waitingSeat)) then tbl.waitKey, tbl.turnDeadline = nil, nil return nil end
  local key = game.phase .. ':' .. waitingSeat .. ':' .. game.tricks .. ':' .. #game.trick
  if tbl.waitKey ~= key then tbl.waitKey, tbl.turnDeadline = key, now + TURN_SECONDS[game.phase] end
  return waitingSeat
end

-- Pushes a table change to everyone; the actor can get their own message.
local function afterChange(tbl, message, actor, actorMessage)
  refreshDeadline(tbl, os.clock())
  trackTricks(tbl)
  local settled = tbl.game.done and rewardMembers(tbl) or {}
  for _, member in pairs(tbl.members) do
    local session = sessions[member]
    if session and not settled[member] then
      send(member, session, member == actor and actorMessage or message)
    end
  end
end

-- Server-owned table clock: bots, Chao Di turns, idle timers and reviews.
local function tableTick(tbl, now)
  local game = tbl.game
  if not game then
    if tbl.startAt and now >= tbl.startAt then
      startGame(tbl, now)
      broadcast(tbl, humanCount(tbl) > 1 and 'Table full of friends — dealing!' or 'Dealing. Empty seats are played by bots.')
    end
    return
  end
  local changed, message = false, nil
  if Practice.botDeclare(game, now) then changed = true end
  if Practice.advance(game, now, pick) then changed = true end
  local several = humanCount(tbl) > 1

  if game.phase == 'tricks' and not game.done and not Practice.isHuman(game, game.turn) then
    if not isLive then
      local played = Practice.bots(game)
      if played then changed, message = true, played end
    elseif not tbl.nextBotAt then
      tbl.nextBotAt = now + BOT_DELAY
    elseif now >= tbl.nextBotAt then
      tbl.nextBotAt = now + BOT_DELAY
      local ok, played = Practice.stepBot(game)
      if ok then changed, message = true, played end
    end
  else
    tbl.nextBotAt = nil
  end

  if game.phase == 'chaodi' then
    if not Practice.isHuman(game, game.chaodiTurn) then
      if not tbl.nextChaodiAt then
        tbl.nextChaodiAt = now + (isLive and 1.2 or 0.2)
      elseif now >= tbl.nextChaodiAt then
        tbl.nextChaodiAt = nil
        if Practice.stepChaodiBot(game, now) then changed = true end
      end
    else
      tbl.nextChaodiAt = nil
      if now >= (game.chaodiDeadline or now + 10) and Practice.chaodiPass(game, game.chaodiTurn, now) then changed = true end
    end
  else
    tbl.nextChaodiAt = nil
  end

  -- Bots with a trump-heavy hand Double too (their own stake only), a moment
  -- into the window so it reads like a decision.
  if game.phase == 'doubling' then
    if not game.botDoubleAt then
      game.botDoubleAt = {}
      for seat = 1, game.playerCount or 4 do
        local hand = game.hands and game.hands[seat]
        if hand and #hand > 0 and not Practice.isHuman(game, seat) then
          local trumps = Practice.trumpCount(hand, game.trump.level, game.trump.suit)
          if trumps >= #hand * 0.42 then game.botDoubleAt[seat] = now + 1 + math.random() * 3 end
        end
      end
    end
    for seat, at in pairs(game.botDoubleAt) do
      if now >= at then
        game.botDoubleAt[seat] = nil
        if canDouble(game, seat) and not Practice.isHuman(game, seat) then
          game.doubled = game.doubled or {}
          game.doubled[seat] = true
          broadcast(tbl, seatName(tbl, seat) .. ' doubled! ×2 stakes')
          changed = true
        end
      end
    end
  end

  -- The Double window closes on its timer, or early once every person doubled.
  if game.phase == 'doubling' and Practice.endDoubling(game, now, everyoneDoubled(game)) then
    changed = true
  end

  -- With several people, nobody can stall the table.
  if several and not game.done then
    local previousKey = tbl.waitKey
    local waitingSeat = refreshDeadline(tbl, now)
    if waitingSeat and tbl.waitKey ~= previousKey then
      changed = true
    elseif waitingSeat and now >= tbl.turnDeadline then
      local name = seatName(tbl, waitingSeat)
      if Practice.autoAct(game, waitingSeat, now) then
        changed, message = true, name .. ' ran out of time, so a suggested move was played.'
      end
    end
    if game.phase == 'trick-review' then
      tbl.reviewUntil = tbl.reviewUntil or now + REVIEW_SECONDS
      if now >= tbl.reviewUntil then
        tbl.reviewUntil = nil
        if Practice.nextTrick(game) then changed = true end
      end
    else
      tbl.reviewUntil = nil
    end
  else
    tbl.waitKey, tbl.turnDeadline = nil, nil
  end

  if changed then afterChange(tbl, message) end
end

local pendingSaves = 0 -- in-flight writes; shutdown waits for these
-- Writes a player's progress if it loaded successfully and has changed.
function saveProgress(player, session, force)
  if not session.loaded then return false end
  local data = Persistence.snapshot(session)
  local signature = Persistence.signature(data)
  if not force and signature == session.savedSignature then return true end
  pendingSaves = pendingSaves + 1
  local ok, err = Persistence.save(player.UserId, data)
  pendingSaves = pendingSaves - 1
  if ok then
    session.savedSignature = signature
    session.lastSavedAt = os.clock()
    session.saveStatus = { enabled = true }
    if session.leaderCoins ~= data.coins then
      session.leaderCoins = data.coins
      task.spawn(postLeaderScore, player, data.coins)
    end
    local rankPoints = data.stats and data.stats.rankPoints or 0
    if rankPoints > 0 and session.leaderRank ~= rankPoints then
      session.leaderRank = rankPoints
      task.spawn(postRankScore, player, rankPoints)
    end
  else
    session.saveStatus = { enabled = false, reason = 'The last save failed. ' .. explainStoreError(err) }
    warn('[Tractor] Could not save progress for ' .. tostring(player.UserId) .. ': ' .. tostring(err))
  end
  return ok
end

-- ===== Reconnecting =====
-- Someone who drops out of a round that other people are still playing can
-- take their seat back (a bot holds it meanwhile) for a few minutes.
local REJOIN_SECONDS = 240
local rejoinSeats = {} -- userId -> { tbl, seat, roundKey, expires }
local function rememberSeat(userId, tbl, seat)
  rejoinSeats[userId] = { tbl = tbl, seat = seat, roundKey = tbl.roundKey, expires = os.time() + REJOIN_SECONDS }
  if crossServer then task.spawn(crossServer.rememberSeat, userId, tbl.matchId, REJOIN_SECONDS) end
end
local function seatStillOpen(entry)
  local tbl = entry.tbl
  return tables[tbl.id] == tbl and tbl.game ~= nil and not tbl.game.done and tbl.roundKey == entry.roundKey
    and not tbl.members[entry.seat] and os.time() < entry.expires
end
local function forgetSeat(userId)
  rejoinSeats[userId] = nil
  if crossServer then task.spawn(crossServer.forgetSeat, userId) end
end
-- Puts a returning player straight back in their seat. True if it worked.
local function retakeSeat(player, session)
  local entry = rejoinSeats[player.UserId]
  if not (entry and seatStillOpen(entry)) or session.table then return false end
  forgetSeat(player.UserId)
  seatAt(player, session, entry.tbl, entry.seat)
  broadcast(entry.tbl, player.DisplayName .. ' is back at the table.')
  return true
end
-- On joining: offer the seat back if the round is still going, here or in
-- another server.
local function offerRejoin(player, session)
  local entry = rejoinSeats[player.UserId]
  if entry then
    if seatStillOpen(entry) then session.rejoinOffer = entry.expires return end
    rejoinSeats[player.UserId] = nil
  end
  if not crossServer then return end
  task.spawn(function()
    local record = crossServer.recallSeat(player.UserId)
    if record and record.jobId ~= game.JobId and sessions[player] == session and not session.table then
      session.rejoinRemote = record
      session.rejoinOffer = os.time() + REJOIN_SECONDS
      send(player, session)
    end
  end)
end

local loading = {} -- player -> true while loading, false if they left meanwhile
local function connect(player)
  if sessions[player] or loading[player] ~= nil then return end
  loading[player] = true
  local session = {
    coins = 3000,
    lastDailyDay = nil,
    stats = {},
    nextGiftAt = 0,
    mailClaimed = false,
    vaultCoins = 1500,
    luckySpinAt = 0,
    quests = {
      play = { label = 'Play 1 Match', progress = 0, target = 1, reward = 500, claimed = false },
      points = { label = 'Capture 40+ Points', progress = 0, target = 40, reward = 750, claimed = false },
      emote = { label = 'Send a Table Emote', progress = 0, target = 1, reward = 250, claimed = false },
    },
    owned = {
      wave = true,
      cheer = true,
      flower = true,
      tomato = true,
      bomb = true,
      coffee = true,
      tractor_rush = true,
      cardback_classic = true,
      felt_emerald = true,
      felt_sapphire = true,
      felt_ruby = true,
      felt_obsidian = true,
      frame_none = true,
      title_newcomer = true,
      banner_forest = true,
    },
    equipped = { cardBack = 'cardback_classic', felt = 'felt_emerald', frame = 'frame_none', title = 'title_newcomer', banner = 'banner_forest' },
    pass = Persistence.newPass(),
    lastAction = -math.huge,
    lastEmote = -math.huge,
    nextBotPlayAt = nil,
    queue = nil,
    party = nil,
    seat = 1,
    player = player,
    public = true, -- solo players' squads start public; anyone here can join
    invites = {},
    loaded = false,
  }
  -- Load before the session goes live so early commands cannot be overwritten.
  local ok, data = Persistence.load(player.UserId)
  local stillHere = loading[player]
  loading[player] = nil
  if not stillHere then return end
  local loadMessage
  if ok then
    session.loaded = true
    session.saveStatus = { enabled = true }
    if data then Persistence.apply(session, data) end
    session.savedSignature = Persistence.signature(Persistence.snapshot(session))
  else
    local reason = storeProblem or explainStoreError(data)
    session.saveStatus = { enabled = false, reason = reason }
    loadMessage = 'Progress could not be loaded, so this session will not be saved. ' .. reason
    warn('[Tractor] Progress saving is OFF for ' .. tostring(player.UserId) .. ': ' .. tostring(storeProblem or data))
  end
  session.lastSavedAt = os.clock()
  sessions[player] = session
  -- Coins in Roblox's own player list (top right).
  local stats = Instance.new('Folder')
  stats.Name = 'leaderstats'
  local coinStat = Instance.new('IntValue')
  coinStat.Name = 'Coins'
  coinStat.Value = session.coins
  coinStat.Parent = stats
  stats.Parent = player
  awardBadge(player, 'welcome')
  funnel(player, 1, 'Joined')
  task.spawn(refreshVip, player, session)
  local joinData
  pcall(function() joinData = player:GetJoinData().TeleportData end)
  if arriveForMatch(player, session, joinData, os.clock()) then
    rejoinSeats[player.UserId] = nil
    if crossServer then task.spawn(crossServer.forgetSeat, player.UserId) end
    return
  end
  -- Came back through a reconnect teleport: sit straight down again.
  if type(joinData) == 'table' and joinData.rejoin and retakeSeat(player, session) then return end
  if not isMatchServer then pcall(offerRejoin, player, session) end
  if isMatchServer then
    -- Only matched players belong in a match server.
    send(player, session, 'That match has no seat for you. Returning to the lobby…')
    crossServer.returnToLobby({ player })
    return
  end
  send(player, session, loadMessage)
end
Players.PlayerAdded:Connect(connect)
Players.PlayerRemoving:Connect(function(player)
  if loading[player] then loading[player] = false end
  local session = sessions[player]
  if session then
    -- Cleanup must never stop the save below.
    local ok, problem = pcall(function()
      -- Mid-round with other people still playing: keep the seat reclaimable.
      local tbl, seat = session.table, session.seat
      local midRound = tbl ~= nil and tbl.game ~= nil and not tbl.game.done and humanCount(tbl) > 1
      cancelSearch(player, session)
      leaveSquad(player, session)
      leaveTable(player, session)
      if midRound then rememberSeat(player.UserId, tbl, seat) end
    end)
    if not ok then warn('[Tractor] Cleanup on leave failed: ' .. tostring(problem)) end
  end
  sessions[player] = nil
  if session then saveProgress(player, session, false) end
end)
-- ==========================================================
-- Robux purchases: coin bags (developer products) and the VIP pass.
-- ==========================================================
local MarketplaceService = game:GetService('MarketplaceService')
local coinProducts, vipPassId = {}, nil
for _, item in ipairs(Catalog) do
  if type(item.productId) == 'number' and item.productId > 0 and item.coins then coinProducts[item.productId] = item end
  if item.id == 'gamepass_vip' and type(item.gamePassId) == 'number' and item.gamePassId > 0 then vipPassId = item.gamePassId end
end

function refreshVip(player, session)
  if not vipPassId then return end
  local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(player.UserId, vipPassId) end)
  if ok and owns and not session.vip then
    session.vip = true
    send(player, session)
  end
end

-- Coins are granted only once the save that records them succeeds, and each
-- PurchaseId is remembered so a retried receipt is never paid twice. If
-- anything fails, Roblox retries the receipt later (e.g. on the next join).
MarketplaceService.ProcessReceipt = function(receipt)
  local NOT_YET = Enum.ProductPurchaseDecision.NotProcessedYet
  local item = coinProducts[receipt.ProductId]
  local isPass = (Catalog.pass.productId or 0) > 0 and receipt.ProductId == Catalog.pass.productId
  local player = Players:GetPlayerByUserId(receipt.PlayerId)
  local session = player and sessions[player]
  if not (item or isPass) or not session or not session.loaded then return NOT_YET end
  session.receipts = session.receipts or {}
  local purchaseId = tostring(receipt.PurchaseId)
  if table.find(session.receipts, purchaseId) then return Enum.ProductPurchaseDecision.PurchaseGranted end
  local unlockedPass = isPass and Persistence.passUnlock(session)
  if item then session.coins = session.coins + item.coins end
  table.insert(session.receipts, purchaseId)
  while #session.receipts > Persistence.MAX_RECEIPTS do table.remove(session.receipts, 1) end
  if saveProgress(player, session, true) then
    if item then send(player, session, 'Purchased ' .. formatK(item.coins) .. ' Coins!', item.coins)
    else send(player, session, '🎟 Battle Pass Premium unlocked!') end
    return Enum.ProductPurchaseDecision.PurchaseGranted
  end
  -- Not saved: undo, and let Roblox retry.
  if item then session.coins = session.coins - item.coins end
  if unlockedPass then session.pass.premium = false end
  local index = table.find(session.receipts, purchaseId)
  if index then table.remove(session.receipts, index) end
  return NOT_YET
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
  local session = sessions[player]
  if purchased and session and vipPassId and passId == vipPassId then
    session.vip = true
    send(player, session, 'VIP Tractor Pass unlocked! Your winnings are now doubled.')
  end
end)

pcall(function()
  game:BindToClose(function()
    for player, session in pairs(sessions) do task.spawn(saveProgress, player, session, false) end
    -- Leave handlers may still be writing (e.g. pressing Stop in Studio).
    local waited = 0
    repeat task.wait(0.1); waited = waited + 0.1 until pendingSaves == 0 or waited >= 25
  end)
end)
for _, player in ipairs(Players:GetPlayers()) do connect(player) end
_G.sessions = sessions
remote.OnServerEvent:Connect(function(player, action, value, revision)
  local session = sessions[player]
  if not session or type(action) ~= 'string' then return end
  local now = os.clock()
  if now - session.lastAction < 0.15 then return end
  session.lastAction = now
  localMatchmaking(now)
  if crossServer then crossServer.tick(os.time()) end
  if session.table then tableTick(session.table, now) end
  if action == 'sync' then send(player, session) return end
  if action == 'claim_daily' then
    local day, coins = Persistence.claimDaily(session)
    if day then
      send(player, session, '🎁 Day ' .. day .. ' Streak Claimed! +' .. formatK(coins) .. ' Coins added!', coins)
      task.spawn(saveProgress, player, session, false)
    else
      send(player, session, 'Daily Reward already claimed today!')
    end
    return
  end
  if action == 'claim_gift' then
    if now >= (session.nextGiftAt or 0) then
      local giftAmt = session.coins < 2000 and 1000 or 500
      session.coins = session.coins + giftAmt
      session.nextGiftAt = now + 90
      send(player, session, '🎁 Free Gift Claimed! +' .. formatK(giftAmt) .. ' Coins added!' .. (giftAmt == 1000 and ' (Relief Bonus!)' or ''), giftAmt)
    else
      local waitSec = math.ceil(session.nextGiftAt - now)
      send(player, session, 'Next gift available in ' .. waitSec .. 's!')
    end
    return
  end
  if action == 'claim_quest' then
    local q = session.quests and session.quests[value]
    if q and q.progress >= q.target and not q.claimed then
      q.claimed = true
      session.coins = session.coins + q.reward
      send(player, session, '🎯 Quest Complete: ' .. q.label .. '! +' .. formatK(q.reward) .. ' Coins!', q.reward)
    else
      send(player, session, 'Quest not completed yet.')
    end
    return
  end
  if action == 'pass_claim' then
    if type(value) ~= 'table' then return end
    local reward, problem = Persistence.passClaim(session, value.track, value.tier)
    if reward then
      local label = reward.boost and (reward.boost .. ' minutes of card markers') or (reward.coins and (formatK(reward.coins) .. ' Coins') or 'a new cosmetic')
      send(player, session, '🎟 Claimed ' .. label .. '!', reward.coins)
      task.spawn(saveProgress, player, session, false)
    else
      send(player, session, problem)
    end
    return
  end
  if action == 'pass_claim_all' then
    local coins, count = Persistence.passClaimAll(session)
    if count > 0 then
      send(player, session, '🎟 Claimed ' .. count .. ' reward' .. (count == 1 and '' or 's') .. '!', coins > 0 and coins or nil)
      task.spawn(saveProgress, player, session, false)
    end
    return
  end
  if action == 'view_profile' then
    -- Public profile of someone at this table; value is their seat from the viewer's side.
    local tbl = session.table
    if not tbl or type(value) ~= 'number' or value % 1 ~= 0 or value < 1 or value > tbl.playerCount then return end
    local abs = absSeat(tbl, session.seat, value)
    local member = tbl.members[abs]
    local other = member and sessions[member]
    local stats = {}
    if other then
      for _, key in ipairs({ 'roundsPlayed', 'roundsWon', 'matchesWon', 'shutouts', 'overturns', 'chaodis', 'bestGrade', 'biggestWin', 'rankPoints' }) do
        stats[key] = other.stats[key] or 0
      end
    end
    remote:FireClient(player, {
      type = 'profile', human = other ~= nil, name = seatName(tbl, abs),
      userId = member and member.UserId or BOT_IDS[abs],
      equipped = other and other.equipped or {}, stats = stats,
    })
    return
  end
  if action == 'rejoin' then
    session.rejoinOffer = nil
    if retakeSeat(player, session) then return end
    local record = session.rejoinRemote
    session.rejoinRemote = nil
    rejoinSeats[player.UserId] = nil
    if record and crossServer and not session.table then
      if record.matchId then
        local match = crossServer.loadMatch(record.matchId)
        if match then
          send(player, session, 'Returning to your table…')
          crossServer.travel(match, { player })
          return
        end
      elseif record.jobId then
        send(player, session, 'Returning to your table…')
        crossServer.rejoinServer(player, record.jobId)
        return
      end
    end
    send(player, session, 'That round has already finished.')
    return
  end
  if action == 'rejoin_dismiss' then
    session.rejoinOffer, session.rejoinRemote = nil, nil
    forgetSeat(player.UserId)
    send(player, session)
    return
  end
  if action == 'leaderboard' then
    local you
    for _, entry in ipairs(leaderboard.entries) do
      if entry.userId == player.UserId then you = entry.rank end
    end
    remote:FireClient(player, {
      type = 'leaderboard', entries = leaderboard.entries, updatedAt = leaderboard.updatedAt,
      yourRank = you, yourCoins = session.coins, available = leaderStore ~= nil,
      rankEntries = rankBoard.entries, yourRankPoints = session.stats.rankPoints or 0,
      yourRankTier = rankName(session.stats.rankPoints or 0), ranks = Catalog.ranks,
    })
    return
  end
  if action == 'tutorial_done' then
    -- Once ever: finishing (not skipping) the tutorial pays a small welcome bonus.
    if not session.tutorialDone then
      session.tutorialDone = true
      funnel(player, 2, 'Tutorial closed')
      logEvent(player, value == 'finished' and 'TutorialFinished' or 'TutorialSkipped')
      if value == 'finished' then
        session.coins = session.coins + 1000
        send(player, session, '🎓 Tutorial complete! +1K Coins', 1000)
        return
      end
    end
    send(player, session)
    return
  end
  if action == 'claim_mail' then
    if not session.mailClaimed then
      session.mailClaimed = true
      session.coins = session.coins + 1500
      send(player, session, '✉️ Club Mailbox Bonus Claimed! +1.5K Coins added!', 1500)
    else
      send(player, session, 'Mailbox rewards already claimed!')
    end
    return
  end
  if action == 'lucky_spin' then
    -- One spin per day, checked here on the server (the day is saved, so
    -- rejoining does not reset it). The server picks the prize and tells the
    -- client which slot to land on.
    local today = Persistence.today()
    if session.luckyDay == today then
      local left = 86400 - os.time() % 86400
      send(player, session, '🎡 Already spun today! Next spin in ' .. math.floor(left / 3600) .. 'h ' .. math.floor(left % 3600 / 60) .. 'm.')
      return
    end
    -- Bigger prizes, weighted so the big ones stay rare (weights add to 100).
    local prizes = { 2000, 3000, 5000, 7500, 10000, 15000, 25000, 50000 }
    local weights = { 25, 20, 18, 14, 10, 7, 4, 2 }
    local roll, index = random:NextInteger(1, 100), #prizes
    for i, w in ipairs(weights) do
      if roll <= w then index = i break end
      roll -= w
    end
    local prize = prizes[index]
    session.luckyDay = today
    session.luckyResult = index
    session.coins = session.coins + prize
    send(player, session, '🎡 Lucky Wheel Winner! +' .. formatK(prize) .. ' Coins!', prize)
    session.luckyResult = nil
    task.spawn(saveProgress, player, session, false)
    return
  end
  if action == 'claim_vault' then
    local vCoins = session.vaultCoins or 1500
    if vCoins > 0 then
      session.coins = session.coins + vCoins
      session.vaultCoins = 0
      send(player, session, '🏦 Match Vault Cracked! +' .. formatK(vCoins) .. ' Coins added!', vCoins)
    else
      send(player, session, 'Vault is empty. Win tricks and matches to bank coins!')
    end
    return
  end
  -- Table settings from a lobby request, checked against the player's coins.
  local function tableOptions(request)
    local playerCount = type(request) == 'table' and request.playerCount or (session.table and session.table.playerCount) or 4
    if playerCount ~= 4 and playerCount ~= 6 and playerCount ~= 8 and playerCount ~= 10 then return nil, 'Choose 4, 6, 8 or 10 players.' end
    local chosenTier = type(request) == 'table' and TIER_CONFIG[request.tier] and request.tier or (session.table and session.table.tier)
    if not chosenTier then
      chosenTier = session.coins >= 100000 and 'master' or (session.coins >= 8000 and 'pro' or 'novice')
    end
    local cfg = TIER_CONFIG[chosenTier]
    if session.coins < cfg.min then
      return nil, cfg.name .. ' requires ' .. formatK(cfg.min) .. '–' .. (cfg.max == math.huge and '∞' or formatK(cfg.max)) .. ' Coins! Current balance: ' .. formatK(session.coins)
    end
    local fullMatch = type(request) == 'table' and request.fullMatch == true
    return { playerCount = playerCount, tier = chosenTier, fullMatch = fullMatch }, nil, cfg
  end

  if action == 'queue' or action == 'create_private' then
    local options, problem, cfg = tableOptions(value)
    if not options then send(player, session, problem) return end
    leaveTable(player, session)
    if action == 'create_private' then
      options.private = true
      local tbl = createTable(player, session, options)
      send(player, session, 'Private table ' .. tbl.code .. ' created. Share the code with friends, then press Start.')
      return
    end
    -- Matchmaking: your squad (or just you) joins the queue for this mode.
    startSearch(player, session, options, cfg, now)
    return
  end
  if action == 'join_code' then
    local code = string.upper(type(value) == 'string' and value or ''):gsub('[^%w]', '')
    local tbl = tableCodes[code]
    if not tbl then send(player, session, 'No table found with code ' .. code .. '.') return end
    if session.table == tbl then send(player, session) return end
    local cfg = TIER_CONFIG[tbl.tier]
    if session.coins < cfg.min then send(player, session, cfg.name .. ' requires ' .. formatK(cfg.min) .. ' Coins to join.') return end
    if humanCount(tbl) >= tbl.playerCount then send(player, session, 'That table is full.') return end
    leaveTable(player, session)
    joinTable(player, session, tbl)
    broadcast(tbl, player.DisplayName .. ' joined the table.')
    return
  end
  if action == 'cancel_queue' and session.search then
    cancelSearch(player, session, 'Search cancelled.')
    return
  end
  if action == 'cancel_queue' or action == 'leave' or action == 'lobby' then
    leaveTable(player, session)
    if isMatchServer then
      send(player, session, 'Heading back to the lobby…')
      crossServer.returnToLobby({ player })
      return
    end
    send(player, session, 'Returned to Lobby')
    return
  end
  if action == 'change_table' then
    local tbl = session.table
    local options, problem, cfg = tableOptions({ playerCount = tbl and tbl.playerCount or 4, tier = tbl and tbl.tier or 'novice', fullMatch = tbl and tbl.fullMatch or false })
    leaveTable(player, session)
    if not options then send(player, session, problem) return end
    startSearch(player, session, options, cfg, now)
    return
  end
  -- Squads: invite, accept/decline, leave, kick, and fill for open team seats.
  if action == 'squad_invite' then
    local userId = tonumber(value)
    if not userId or userId == player.UserId then return end
    local squad = session.squad or createSquad(player, session)
    if squad.leader ~= player then send(player, session, 'Only the squad leader can invite.') return end
    if #squad.members >= MAX_SQUAD then send(player, session, 'Your squad is full.') return end
    squad.invited[userId] = now
    local target = playerByUserId(userId)
    if target then
      deliverInvite(target, { fromId = player.UserId, fromName = player.DisplayName })
      send(player, session, 'Invite sent to ' .. target.DisplayName .. '.')
    elseif crossServer then
      crossServer.invite(userId, { userId = player.UserId, name = player.DisplayName })
      send(player, session, 'Invite sent. They will join this server if they accept.')
    else
      send(player, session, 'That player is not in this server.')
    end
    return
  end
  if action == 'squad_accept' or action == 'squad_decline' then
    local fromId = tonumber(value)
    local invite = fromId and session.invites and session.invites[fromId]
    if session.invites and fromId then session.invites[fromId] = nil end
    if not invite then send(player, session, 'That invite has expired.') return end
    if action == 'squad_decline' then send(player, session) return end
    if invite.jobId and invite.jobId ~= game.JobId then
      if crossServer then
        send(player, session, 'Joining ' .. invite.fromName .. "'s server…")
        crossServer.followInvite(player, invite)
      end
      return
    end
    local leader = playerByUserId(fromId)
    local squad = leader and sessions[leader] and sessions[leader].squad
    if not (squad and squad.invited[player.UserId]) then send(player, session, 'That invite has expired.') return end
    if #squad.members >= MAX_SQUAD then send(player, session, 'That squad is full.') return end
    leaveSquad(player, session)
    cancelSearch(player, session)
    cancelSearch(leader, sessions[leader], 'Search cancelled: ' .. player.DisplayName .. ' joined the squad.')
    squad.invited[player.UserId] = nil
    table.insert(squad.members, player)
    session.squad = squad
    session.invites = {}
    sendSquad(squad, player.DisplayName .. ' joined the squad.')
    return
  end
  if action == 'squad_leave' then
    leaveSquad(player, session)
    send(player, session, 'You left the squad.')
    return
  end
  if action == 'squad_kick' then
    local squad = session.squad
    local target = playerByUserId(tonumber(value) or 0)
    if not squad or squad.leader ~= player or not target or sessions[target] == nil or sessions[target].squad ~= squad or target == player then return end
    leaveSquad(target, sessions[target], target.DisplayName .. ' was removed from the squad.')
    send(target, sessions[target], 'You were removed from the squad.')
    return
  end
  if action == 'squad_privacy' then
    local public = value == true
    if session.squad then
      if session.squad.leader ~= player then send(player, session, 'Only the squad leader can change this.') return end
      session.squad.public = public
      sendSquad(session.squad, public and 'Squad is public: players in this server can join.' or 'Squad is private: invite only.')
    else
      session.public = public
      send(player, session, public and 'Squad is public: players in this server can join.' or 'Squad is private: invite only.')
    end
    for other, otherSession in pairs(sessions) do
      if otherSession.squad == nil or otherSession.squad ~= session.squad then
        if other ~= player then send(other, otherSession) end
      end
    end
    return
  end
  if action == 'squad_join' then
    local leader = playerByUserId(tonumber(value) or 0)
    local leaderSession = leader and sessions[leader]
    if not leaderSession or leader == player then send(player, session, 'That squad is no longer available.') return end
    local squad = leaderSession.squad
    local public = squad and squad.public or (squad == nil and leaderSession.public ~= false)
    if squad and squad.leader ~= leader then squad = nil; public = false end
    if not public then send(player, session, 'That squad is private now.') return end
    if session.squad and session.squad == squad then return end
    if squad and #squad.members >= MAX_SQUAD then send(player, session, 'That squad is full.') return end
    leaveSquad(player, session)
    cancelSearch(player, session)
    squad = leaderSession.squad or createSquad(leader, leaderSession)
    cancelSearch(leader, leaderSession, 'Search cancelled: ' .. player.DisplayName .. ' joined the squad.')
    table.insert(squad.members, player)
    session.squad = squad
    session.invites = {}
    sendSquad(squad, player.DisplayName .. ' joined the squad.')
    -- Everyone else's open-squad lists change too.
    for other, otherSession in pairs(sessions) do
      if otherSession.squad ~= squad then send(other, otherSession) end
    end
    return
  end
  if action == 'start' or action == 'start_now' or action == 'play_again' then
    local tbl = session.table
    -- Asking for different settings means a different table.
    if tbl and type(value) == 'table' and ((value.playerCount and value.playerCount ~= tbl.playerCount)
      or (value.fullMatch ~= nil and (value.fullMatch == true) ~= tbl.fullMatch)) then
      leaveTable(player, session)
      tbl = nil
    end
    if not tbl then
      local options, problem, cfg = tableOptions(value)
      if not options then send(player, session, problem) return end
      options.private = false
      tbl = createTable(player, session, options)
      startGame(tbl, now)
      send(player, session, 'Joined ' .. cfg.name .. ' (Base: ' .. formatK(cfg.base) .. '). Declare with level cards, then play!')
      return
    end
    local game = tbl.game
    if not game then
      if tbl.host ~= player then send(player, session, 'Waiting for the host to start the table.') return end
      startGame(tbl, now)
      broadcast(tbl, 'Dealing! Empty seats are played by bots.')
      return
    end
    if not game.done and game.phase ~= 'blocked' then
      if action ~= 'start' or type(value) ~= 'table' or value.restart ~= true or revision ~= game.revision then
        send(player, session, 'Finish this hand first or change table.') return
      end
      if tbl.host ~= player and humanCount(tbl) > 1 then send(player, session, 'Only the host can restart the hand.') return end
    end
    if game.done and game.settlement and not game.settlement.winner then
      local nextState = continueMatch(tbl, now)
      if nextState then
        broadcast(tbl, 'Round ' .. nextState.round .. ': declaring level ' .. nextState.trump.level .. '.')
        return
      end
    end
    local _, problem = tableOptions({ playerCount = tbl.playerCount, tier = tbl.tier, fullMatch = tbl.fullMatch })
    if problem then send(player, session, problem) return end
    startGame(tbl, now)
    broadcast(tbl, player.DisplayName .. ' started a new match.')
  elseif action == 'play' or action == 'declare' or action == 'bury' or action == 'chaodi' or action == 'chaodi_pass' or action == 'next-round' or action == 'next-trick' or action == 'hint' then
    local tbl = session.table
    local game = tbl and tbl.game
    if not game then return end
    local seat = session.seat
    if action == 'hint' then
      local hintIds = Practice.hint(game, seat)
      if hintIds then remote:FireClient(player, { hint = hintIds }) end
      return
    end
    -- Index-based choices must refer to the state the player saw; plays and
    -- burials are validated directly, so others' moves do not void them.
    if (action == 'declare' or action == 'chaodi' or action == 'next-round' or action == 'next-trick') and revision ~= game.revision then
      send(player, session, 'Table updated. Please choose again.') return
    end
    if action == 'next-round' then
      local nextState, reason = continueMatch(tbl, now)
      if not nextState then send(player, session, reason) return end
      broadcast(tbl, 'Round ' .. nextState.round .. ': declaring level ' .. nextState.trump.level .. '.')
      return
    end
    local accepted, reason
    if action == 'play' then
      accepted, reason = Practice.play(game, seat, value)
    elseif action == 'next-trick' then
      accepted, reason = Practice.nextTrick(game)
    elseif action == 'declare' then accepted, reason = Practice.declare(game, seat, value, now)
    elseif action == 'chaodi' then
      accepted, reason = Practice.chaodi(game, seat, value, now)
      if accepted then
      session.stats.chaodis = (session.stats.chaodis or 0) + 1
      awardBadge(player, 'chaodi')
    end
    elseif action == 'chaodi_pass' then accepted, reason = Practice.chaodiPass(game, seat, now)
    else accepted, reason = Practice.bury(game, seat, value, now) end
    if not accepted then send(player, session, reason) return end
    tbl.waitKey = nil
    local message = reason
    if not isLive then message = Practice.bots(game) or reason end
    afterChange(tbl, nil, player, message)
  elseif action == 'forfeit' then
    -- Concede the round. Every person on the team must agree; bots go along.
    local tbl = session.table
    local game = tbl and tbl.game
    if not game or game.done then return end
    if game.phase ~= 'tricks' and game.phase ~= 'trick-review' then
      send(player, session, 'You can concede once play has started.') return
    end
    local team = Cards.team(session.seat)
    game.forfeitVotes = game.forfeitVotes or {}
    local already = game.forfeitVotes[session.seat]
    game.forfeitVotes[session.seat] = true
    local waiting = 0
    for seat, human in pairs(game.humans or {}) do
      if human and Cards.team(seat) == team and not game.forfeitVotes[seat] then waiting = waiting + 1 end
    end
    if waiting > 0 then
      if not already then broadcast(tbl, player.DisplayName .. ' wants to concede. Teammates: press Concede to agree.') end
      return
    end
    local ok, reason = Practice.forfeit(game, session.seat, now)
    if not ok then send(player, session, reason) return end
    tbl.waitKey = nil
    logEvent(player, 'Conceded')
    afterChange(tbl, player.DisplayName .. "'s team conceded the round.", player, 'Your team conceded the round.')
  elseif action == 'double' then
    local tbl = session.table
    local game = tbl and tbl.game
    if not game then return end
    if not canDouble(game, session.seat) then
      send(player, session, 'You can only double right after Chao Di.') return
    end
    game.doubled = game.doubled or {}
    game.doubled[session.seat] = true
    broadcast(tbl, player.DisplayName .. ' doubled! ×2 stakes')
  elseif action == 'chat' then
    local chatId = type(value) == 'table' and value.id or value
    local chatTarget = type(value) == 'table' and value.target or 'auto'
    if type(chatId) ~= 'string' then return end
    local phrase
    for _, entry in ipairs(Catalog.phrases or {}) do
      if entry.id == chatId then phrase = entry.text end
    end
    if type(chatTarget) ~= 'string' or #chatTarget > 16 then chatTarget = 'auto' end
    if phrase and now - session.lastEmote >= 1.5 then
      session.lastEmote = now
      if session.quests and session.quests.emote then
        session.quests.emote.progress = math.min(session.quests.emote.target, session.quests.emote.progress + 1)
      end
      relayReaction(player, session, { type = 'emote', kind = 'chat', id = chatId, emote = phrase, sender = player.DisplayName, senderId = player.UserId }, chatTarget)
    end
  elseif action == 'buy' or action == 'emote' or action == 'equip' or action == 'buy_product' then
    local emoteTarget = 'auto'
    if action == 'emote' and type(value) == 'table' then
      emoteTarget = type(value.target) == 'string' and #value.target <= 16 and value.target or 'auto'
      value = value.id
    end
    if type(value) ~= 'string' then return end
    if action == 'equip' then
      local item = Persistence.equip(session, value)
      if item then send(player, session, 'Equipped ' .. item.label) end
      return
    end
    if action == 'buy' and Persistence.isProfileItem(value) then
      local item, problem = Persistence.buyProfileItem(session, value)
      send(player, session, item and (item.label .. ' unlocked!') or problem)
      if item then task.spawn(saveProgress, player, session, false) end
      return
    end
    -- Robux items are bought through the Roblox purchase prompt and paid in
    -- ProcessReceipt; this action only explains items that are not on sale.
    if action == 'buy_product' then
      send(player, session, 'That item is not on sale yet.')
      return
    end
    if action == 'emote' then
      local isEmote = false
      for _, item in ipairs(Catalog) do
        if item.id == value and item.category == 'emote' then isEmote = true end
      end
      if not isEmote then return end
      if not session.owned[value] then send(player, session, 'Unlock that reaction first.') return end
      if now - session.lastEmote >= 1.5 then
        session.lastEmote = now
        if session.quests and session.quests.emote then
          session.quests.emote.progress = math.min(session.quests.emote.target, session.quests.emote.progress + 1)
        end
        local itemLabel, itemIcon = value, '✦'
        for _, item in ipairs(Catalog) do
          if item.id == value then itemLabel = item.label; itemIcon = item.icon; break end
        end
        relayReaction(player, session, { type = 'emote', kind = 'emote', id = value, emote = itemLabel, icon = itemIcon, sender = player.DisplayName, senderId = player.UserId }, emoteTarget)
      end
      return
    end
    for _, item in ipairs(Catalog) do
      if item.id == value then
        if action == 'buy' then
          if session.owned[value] then send(player, session, 'Already unlocked.') return end
          if session.coins < item.price then send(player, session, 'Earn more coins by finishing practice hands.') return end
          session.coins = session.coins - item.price
          session.owned[value] = true
          if item.category == 'cardBack' then session.equipped.cardBack = value end
          if item.category == 'felt' then session.equipped.felt = value end
          send(player, session, item.label .. ' unlocked!')
          task.spawn(saveProgress, player, session, false)
        end
        return
      end
    end
  end
end)
-- Timers are server-owned and progress even when clients send no commands.
task.spawn(function()
  while task.wait(0.08) do
    local now = os.clock()
    localMatchmaking(now)
    if crossServer then crossServer.tick(os.time()) end
    for _, tbl in pairs(tables) do tableTick(tbl, now) end
    for player, session in pairs(sessions) do
      -- Timed card markers only burn while tricks are being played.
      local liveGame = session.table and session.table.game
      if liveGame and not liveGame.done and (liveGame.phase == 'tricks' or liveGame.phase == 'trick-review') then
        Persistence.tickMarkers(session, now - (session.markerTickAt or now))
      end
      session.markerTickAt = now
      if session.loaded and not session.saving and now - (session.lastSavedAt or now) >= AUTOSAVE_SECONDS then
        session.saving = true
        session.lastSavedAt = now
        task.spawn(function()
          saveProgress(player, session, false)
          session.saving = false
        end)
      end
    end
  end
end)
-- A small physical table for the initial Studio place.
local tablePart = Instance.new('Part')
tablePart.Name = 'CardTable'
tablePart.Anchored = true
tablePart.Size = Vector3.new(16, 1, 12)
tablePart.Position = Vector3.new(0, 3, 0)
tablePart.Color = Color3.fromRGB(28, 92, 73)
tablePart.Parent = workspace
for i = 1, 4 do
  local angle = (i - 1) * math.pi / 2
  local seat = Instance.new('Seat')
  seat.Anchored = true
  seat.Size = Vector3.new(3, 1, 3)
  local position = Vector3.new(math.sin(angle) * 11, 2, math.cos(angle) * 9)
  seat.CFrame = CFrame.lookAt(position, Vector3.new(0, 2, 0))
  seat.Parent = workspace
end
