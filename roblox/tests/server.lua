-- Service doubles exercise the real server command handler; not a Studio runtime test.
local Cards = dofile('roblox/src/shared/Cards.luau')
local Catalog = dofile('roblox/src/shared/Catalog.luau')
local StructuresFactory = dofile('roblox/src/shared/Structures.luau')
local RulesFactory = dofile('roblox/src/shared/PlayRules.luau')
local ScoringFactory = dofile('roblox/src/shared/Scoring.luau')
local Structures = StructuresFactory(Cards)
local Rules = RulesFactory(Cards, Structures)
local PracticeFactory = dofile('roblox/src/server/Practice.luau')
local PersistenceFactory = dofile('roblox/src/server/Persistence.luau')
-- In-memory DataStore double; `storeDown` makes every call fail.
local saved, storeDown, storeWrites, storeError = {}, false, 0, 'DataStore down'
local fakeStore = {
  GetAsync = function(_, key) if storeDown then error(storeError) end return saved[key] end,
  UpdateAsync = function(_, key, transform)
    if storeDown then error(storeError) end
    storeWrites = storeWrites + 1
    saved[key] = transform(saved[key])
    return saved[key]
  end,
}
local warnings = 0
warn = function() warnings = warnings + 1 end
local player = { DisplayName = 'Player', UserId = 42 }
local now, latest, remote, broadcastCount, lastBroadcast = 0, nil, nil, 0, nil
local inbox, received = {}, {} -- latest state / reaction per player
local function signal()
  return { Connect = function(self, handler) self.handler = handler end }
end
local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {player} end }
local shared = { Cards = Cards, Catalog = Catalog, Structures=StructuresFactory, PlayRules=RulesFactory, Scoring=ScoringFactory }
local storage = { WaitForChild = function() return shared end }
game = { GetService = function(_, name)
  if name == 'Players' then return players end
  if name == 'DataStoreService' then return { GetDataStore = function() return fakeStore end } end
  return storage
end }
script = { Parent = { TrainedBots = dofile('roblox/src/server/TrainedBots.luau'), ChampionModel = dofile('roblox/src/server/ChampionModel.luau'), Practice = PracticeFactory, Persistence = PersistenceFactory, Matchmaker = dofile('roblox/src/server/Matchmaker.luau'), CrossServer = dofile('roblox/src/server/CrossServer.luau') } }
require = function(module) return module end
Random = { new = function() return { NextInteger = function(_, _, maximum) return maximum end } end }
os.clock = function() return now end
math.clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
task = { spawn = function() end, wait = function() end } -- Deadlines are also advanced by incoming commands.
workspace = {}
Vector3 = { new = function() return {} end }
Color3 = { fromRGB = function() return {} end }
CFrame = { lookAt = function() return {} end }
Instance = { new = function(class)
  local object = {}
  if class == 'RemoteEvent' then
    remote = object
    object.OnServerEvent = signal()
    object.FireClient = function(_, recipient, value)
      if value.type == 'emote' then
        received[recipient] = value
        if recipient == player then broadcastCount = broadcastCount + 1; lastBroadcast = value end
      else
        inbox[recipient] = value
        if recipient == player then latest = value end
      end
    end
    object.FireAllClients = function(_, payload) broadcastCount = broadcastCount + 1; lastBroadcast = payload end
  end
  return object
end }
dofile('roblox/src/server/Main.server.luau')
local function command(action, value, revision)
  now = now + 0.2
  remote.OnServerEvent.handler(player, action, value, revision)
end
command('sync')
assert(latest.saving and latest.saving.enabled, 'Loaded sessions report that progress is saved')
local startCoins = latest.coins
assert(startCoins == 3000 and latest.owned.wave and not latest.owned.laugh)
-- Locked reactions cannot be broadcast before purchase.
command('emote', 'laugh')
assert(broadcastCount == 0, 'Unowned reactions must not broadcast')
command('emote', 'wave')
assert(broadcastCount == 1)
now = now + 3
command('buy', 'laugh')
assert(latest.coins == startCoins - 600 and latest.owned.laugh)
command('buy', 'laugh')
assert(latest.coins == startCoins - 600, 'Buying twice must not charge twice')
command('emote', 'laugh')
assert(broadcastCount == 2)
command('emote', 'laugh')
assert(broadcastCount == 2, 'Emotes have a cooldown')
now = now + 3
command('emote', 'laugh')
assert(broadcastCount == 3)
-- Broadcasts identify the reaction, its kind, sender and target.
now = now + 3
command('emote', { id = 'tomato', target = 'seat2' })
assert(broadcastCount == 4 and lastBroadcast.kind == 'emote' and lastBroadcast.id == 'tomato' and lastBroadcast.target == 'seat2' and lastBroadcast.senderId == 42)
now = now + 3
command('emote', 'felt_ruby')
assert(broadcastCount == 4, 'Only emotes can be thrown, not other owned items')
command('chat', { id = 'wait', target = 'partner' })
assert(broadcastCount == 5 and lastBroadcast.kind == 'chat' and lastBroadcast.emote == 'Wait for my play!', 'Every dock phrase is accepted')
now = now + 3
command('chat', { id = 'not_a_phrase' })
assert(broadcastCount == 5)

local function playRound()
  assert(latest.game.phase == 'declaration')
  now = now + 6
  local revision = latest.game.revision
  command('declare', 1, revision - 1)
  assert(latest.message == 'Table updated. Please choose again.' and latest.game.declaration == nil or latest.game.declaration.seat ~= 1,
    'Index-based commands from a stale view are rejected')
  command('declare', 1, latest.game.revision)
  now = now + 8
  command('sync')
  if latest.game.phase == 'kitty' then
    local ids = {}
    for i = 1, latest.game.kittySize do ids[i] = latest.game.hand[i].id end
    command('bury', ids, latest.game.revision)
  end
  local steps = 0
  while latest.game.phase == 'chaodi' do
    steps = steps + 1; assert(steps < 200, 'Chao Di did not finish')
    if latest.game.chaodiTurn == 1 then command('chaodi_pass', nil, latest.game.revision) else command('sync') end
  end
  assert(latest.game.phase == 'tricks')
  if latest.game.turn ~= 1 then command('sync') end
  local lastId, lastRevision
  local coinsDuringRound = latest.coins
  steps = 0
  while not latest.game.done do
    assert(latest.coins == coinsDuringRound, 'Captured points do not pay until the round ends')
    steps = steps + 1; assert(steps < 400, 'Round did not finish')
    local current = latest.game
    if current.phase == 'trick-review' then command('next-trick', nil, current.revision)
    elseif current.turn ~= 1 then command('sync')
    else
      local chosen = Rules.choose(current.hand, current.trick[1] and current.trick[1].components, current.trump)
      lastId = {}; for _,card in ipairs(chosen) do table.insert(lastId,card.id) end
      lastRevision = current.revision
      command('play', lastId, lastRevision)
    end
  end
  local settlement = latest.game.settlement
  assert(settlement and settlement.netCoins, 'Completed rounds are settled')
  if settlement.userWon then
    assert(settlement.userCarried == 50000 and settlement.winLossCap <= settlement.userCarried
      and settlement.netCoins + settlement.tax <= settlement.userCarried, 'You can win at most what you carried into the round')
  end
  -- Your team's captured points pay per point by table, times the Chao Di stake.
  local perPoint = ({ novice = 10, pro = 30, master = 100 })[_G.sessions[player].game.tier]
  local expectedTrickCoins = 0
  for _, entry in ipairs(latest.game.history) do
    if entry.winnerSeat % 2 == 1 then expectedTrickCoins = expectedTrickCoins + entry.points * perPoint * latest.game.chaodiMultiplier end
  end
  assert(settlement.trickCoins == expectedTrickCoins, 'Trick coins match captured points × table rate × Chao Di stake')
  assert(latest.coins == 50000 + expectedTrickCoins + settlement.netCoins + (settlement.reliefCoins or 0) + (settlement.matchBonus or 0))
  local coins = latest.coins
  if lastId then
    command('play', lastId, lastRevision)
    command('play', lastId, latest.game.revision)
  end
  command('sync')
  assert(latest.coins == coins, 'Replayed commands must not pay out again')
  assert(latest.game.hands == nil and latest.game.kitty == nil and latest.game.events == nil)
end
local stakeOverride
local function complete(options)
  _G.sessions[player].coins = 50000 -- Keep each round inside a table's wallet range.
  command('start', options or { playerCount = 4 })
  if stakeOverride then _G.sessions[player].game.chaodiMultiplier = stakeOverride end
  playRound()
end
complete()
stakeOverride = 4 -- As if two Chao Di challenges happened.
complete()
assert(latest.game.chaodiMultiplier == 4 and latest.game.settlement.chaodiFactor == 4)
-- A huge stake with a small wallet: a win pays at most what you carried.
local capRounds = 0
repeat
  capRounds = capRounds + 1
  _G.sessions[player].coins = 50000
  command('start', { playerCount = 4 })
  local game = _G.sessions[player].game
  game.trainedSeats = {} -- weaker bots, so the player reliably wins one
  game.chaodiMultiplier = 128
  for seat = 2, 4, 2 do game.botCoins[seat] = 10000000 end
  playRound()
until latest.game.settlement.userWon or capRounds >= 30
do
  local s = latest.game.settlement
  assert(s.userWon, 'The capped-win case must actually run')
  assert(s.cappedByWallet and s.winLossCap == 50000 and s.netCoins + s.tax == 50000, 'Winnings are capped by your own balance')
end
stakeOverride = nil
local roundRevision = latest.game.revision
local coins = latest.coins
command('next-round', nil, roundRevision)
assert(latest.game.round == 1 and latest.game.done and latest.coins == coins, 'Quick Match ends after one round')

-- Full match: both teams start at 2 and rounds continue at the same table.
complete({ playerCount = 4, fullMatch = true })
local first = latest.game
assert(first.quickMatch == false and first.round == 1, 'Full match is not a Quick Match')
assert(first.settlement.winner == nil, 'One round cannot win a match from level 2')
local tierName = _G.sessions[player].game.tier
local botCoins = _G.sessions[player].game.botCoins
command('play_again', { tier = tierName }, first.revision)
assert(latest.game.round == 2 and latest.game.phase == 'declaration', 'Play Again continues to the next round')
assert(latest.game.levels.A == first.settlement.levels.A and latest.game.levels.B == first.settlement.levels.B)
assert(_G.sessions[player].game.tier == tierName and _G.sessions[player].game.botCoins == botCoins, 'Table stakes carry over')
_G.sessions[player].coins = 50000
playRound()
assert(latest.game.round == 2)
command('next-round', nil, latest.game.revision)
assert(latest.game.round == 3 and _G.sessions[player].game.tier == tierName, 'Next Round keeps the table too')
-- Change Table keeps the chosen match length.
command('change_table')
assert(_G.sessions[player].search and _G.sessions[player].search.fullMatch == true and not _G.sessions[player].table, 'Change Table searches with the same match length')
now = now + 21
command('sync')
assert(_G.sessions[player].table and _G.sessions[player].table.fullMatch == true and latest.game, 'Alone in the queue, the match starts with bots after the wait')

local coinsBeforeLeaving = latest.coins
local statsBeforeLeaving = latest.stats
assert(statsBeforeLeaving.roundsPlayed == 4 + capRounds and (statsBeforeLeaving.roundsWon or 0) <= statsBeforeLeaving.roundsPlayed, 'Every settled round is counted')
assert((statsBeforeLeaving.coinsEarned or 0) >= (statsBeforeLeaving.biggestWin or 0))
players.PlayerRemoving.handler(player)
players.PlayerAdded.handler(player)
command('sync')
local session = _G.sessions[player]
assert(latest.coins == coinsBeforeLeaving and latest.owned.laugh, 'Coins and unlocks survive rejoining')
assert(latest.stats.roundsPlayed == statsBeforeLeaving.roundsPlayed and latest.stats.roundsWon == statsBeforeLeaving.roundsWon, 'Stats survive rejoining')
assert(saved.player_42.version == 1 and saved.player_42.owned.laugh)

-- Daily reward is once per calendar day, including across rejoin.
command('claim_daily')
assert(latest.coins == coinsBeforeLeaving + 1000 and latest.dailyClaimed)
now = now + 1
command('claim_daily')
assert(latest.coins == coinsBeforeLeaving + 1000, 'Daily reward cannot be claimed twice')
players.PlayerRemoving.handler(player)
players.PlayerAdded.handler(player)
command('sync')
assert(latest.dailyClaimed and latest.coins == coinsBeforeLeaving + 1000, 'Rejoining does not reset the daily reward')

-- Equipped items must be owned; unknown ids and bad numbers are dropped.
saved.player_42 = { coins = -5, vaultCoins = 0/0, owned = { laugh = true, hacked_item = true, product_coins_10k = true },
  equipped = { cardBack = 'cardback_gold', felt = 'felt_ruby' }, mailClaimed = 'yes' }
players.PlayerRemoving.handler(player)
saved.player_42 = { coins = -5, vaultCoins = 0/0, owned = { laugh = true, hacked_item = true, product_coins_10k = true },
  equipped = { cardBack = 'cardback_gold', felt = 'felt_ruby' }, mailClaimed = 'yes', stats = { roundsPlayed = -3, roundsWon = 'lots', hacked = 99 } }
players.PlayerAdded.handler(player)
command('sync')
assert(latest.coins == 0, 'Negative coins clamp to zero')
assert(latest.stats.roundsPlayed == 0 and latest.stats.roundsWon == 0 and latest.stats.hacked == nil, 'Corrupt stats are cleaned')
assert(latest.owned.laugh and not latest.owned.hacked_item and not latest.owned.product_coins_10k)
assert(latest.equipped.cardBack == 'cardback_classic', 'Cannot equip an unowned card back')
assert(latest.equipped.felt == 'felt_ruby', 'Starter-owned felt can stay equipped')

-- A failed load never overwrites saved progress.
players.PlayerRemoving.handler(player)
saved.player_42 = { coins = 99999, owned = {}, equipped = {} }
storeDown = true
players.PlayerAdded.handler(player)
assert(latest.message and latest.message:find('could not be loaded'), 'Player is told progress will not be saved')
assert(latest.saving and latest.saving.enabled == false and latest.saving.reason:find('Rejoin'), 'Status says saving is off')
assert(warnings > 0, 'The outage is logged for the developer')
assert(latest.coins == 3000)
storeDown = false
command('buy', 'laugh')
local writes = storeWrites
players.PlayerRemoving.handler(player)
assert(storeWrites == writes and saved.player_42.coins == 99999, 'Unloaded sessions are never saved')
players.PlayerAdded.handler(player)
command('sync')
assert(latest.coins == 99999, 'Progress is intact after the outage')
-- Studio with API access off gets the exact setting to change.
players.PlayerRemoving.handler(player)
storeDown, storeError = true, 'StudioAccessToApisNotAllowed: Studio access to APIs is not allowed'
players.PlayerAdded.handler(player)
assert(latest.saving.enabled == false and latest.saving.reason:find('Enable Studio Access to API Services'))
players.PlayerRemoving.handler(player)
storeDown, storeError = false, 'DataStore down'
players.PlayerAdded.handler(player)
command('sync')
assert(latest.saving.enabled and latest.coins == 99999)
-- Unchanged sessions skip the write.
writes = storeWrites
players.PlayerRemoving.handler(player)
assert(storeWrites == writes, 'Unchanged progress is not rewritten')
-- Payout grade keeps climbing past the overturn line: 80/120/160/200/240… (4 players).
local Scoring = ScoringFactory(Cards)
local grades = {}
for _, score in ipairs({ 80, 119, 120, 160, 200, 240, 280 }) do table.insert(grades, (Scoring.payoutGrade('defenders', score, 4))) end
assert(table.concat(grades, ',') == '1,1,2,3,4,5,6', table.concat(grades, ','))
assert(Scoring.payoutGrade('defenders', 180, 6) == 2, 'Six players step every 60 past 120')
assert(Scoring.payoutGrade('attackers', 0, 4) == 4 and Scoring.payoutGrade('attackers', 30, 4) == 2 and Scoring.payoutGrade('attackers', 60, 4) == 1)
print('PASS: real command handler with service doubles: stale commands, Chao Di, settlement, replay safety, full-match rounds, purchases, cooldown, saved progress, daily limit, data sanitizing, load-failure safety, end-of-round point coins, open-ended payout grades, reaction broadcasts and saved stats')
