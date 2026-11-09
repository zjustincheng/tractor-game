-- Several people at shared tables, through the real server command handler
-- with service doubles. Not a Studio or network test.
local Cards = dofile('roblox/src/shared/Cards.luau')
local Catalog = dofile('roblox/src/shared/Catalog.luau')
local StructuresFactory = dofile('roblox/src/shared/Structures.luau')
local RulesFactory = dofile('roblox/src/shared/PlayRules.luau')
local ScoringFactory = dofile('roblox/src/shared/Scoring.luau')
local Rules = RulesFactory(Cards, StructuresFactory(Cards))
local saved = {}
local fakeStore = {
  GetAsync = function(_, key) return saved[key] end,
  UpdateAsync = function(_, key, transform) saved[key] = transform(saved[key]); return saved[key] end,
}
warn = function() end
local now, remote = 0, nil
local inbox, reactions = {}, {}
local function signal() return { Connect = function(self, handler) self.handler = handler end } end
local players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return {} end }
local shared = { Cards = Cards, Catalog = Catalog, Structures = StructuresFactory, PlayRules = RulesFactory, Scoring = ScoringFactory }
game = { PlaceId = 7, GetService = function(_, name)
  if name == 'Players' then return players end
  if name == 'DataStoreService' then return { GetDataStore = function() return fakeStore end } end
  return { WaitForChild = function() return shared end }
end }
script = { Parent = { TrainedBots = dofile('roblox/src/server/TrainedBots.luau'), ChampionModel = dofile('roblox/src/server/ChampionModel.luau'), Practice = dofile('roblox/src/server/Practice.luau'), Persistence = dofile('roblox/src/server/Persistence.luau'), Matchmaker = dofile('roblox/src/server/Matchmaker.luau'), CrossServer = dofile('roblox/src/server/CrossServer.luau') } }
require = function(module) return module end
Random = { new = function() return { NextInteger = function(_, _, maximum) return maximum end } end }
os.clock = function() return now end
math.clamp = function(value, low, high) return math.max(low, math.min(high, value)) end
task = { spawn = function() end, wait = function() end }
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
      if value.type then reactions[recipient] = value else inbox[recipient] = value end
    end
  end
  return object
end }
dofile('roblox/src/server/Main.server.luau')

local function person(name, id)
  local p = { DisplayName = name, UserId = id }
  players.PlayerAdded.handler(p)
  return p
end
local function command(p, action, value, revision)
  now = now + 0.2
  remote.OnServerEvent.handler(p, action, value, revision)
  return inbox[p]
end
local function view(p) return inbox[p].game end
local ana, ben, cai, dev = person('Ana', 101), person('Ben', 102), person('Cai', 103), person('Dev', 104)

-- Private table: create, share the code, friends join as teammates first.
local created = command(ana, 'create_private', { playerCount = 4, tier = 'novice' })
local code = created.table.code
assert(type(code) == 'string' and #code == 4 and created.table.private and created.table.isHost and created.table.status == 'waiting')
assert(command(ben, 'join_code', 'zzzz').message:find('No table found'), 'Unknown codes are refused')
command(ben, 'join_code', string.lower(code))
assert(inbox[ben].table.code == code and not inbox[ben].table.isHost)
assert(inbox[ana].table.humans == 2 and inbox[ana].table.seats[3].name == 'Ben' and inbox[ana].table.seats[3].human, 'Ben sits opposite Ana as her partner')
assert(inbox[ben].table.seats[3].name == 'Ana', 'Ben sees Ana opposite him')
assert(inbox[ana].table.seats[2].human == false and inbox[ana].table.seats[2].name ~= '', 'Empty seats show bot names')
assert(command(ben, 'start').message:find('host'), 'Only the host starts a private table')
assert(not view(ana), 'Nothing is dealt before the host starts')
command(ana, 'start')
assert(view(ana) and view(ben), 'Both players get the deal')
assert(#view(ana).hand > 0 and #view(ben).hand > 0)
local anaIds, benIds = {}, {}
for _, c in ipairs(view(ana).hand) do anaIds[c.id] = true end
for _, c in ipairs(view(ben).hand) do assert(not anaIds[c.id], 'Each player sees only their own cards') end
assert(view(ben).turn == (view(ana).turn + 1) % 4 + 1, 'Views are rotated per seat')

-- Reactions travel between seats, rotated for each receiver.
now = now + 3
command(ana, 'emote', { id = 'tomato', target = 'seat2' })
assert(reactions[ben].fromSeat == 3 and reactions[ben].target == 'seat4', 'Ben sees Ana (opposite) throw at the seat to his left')
assert(reactions[ana].fromSeat == 1 and reactions[ana].target == 'seat2')
assert(reactions[cai] == nil, 'People at other tables do not see it')

-- Play the round: whoever's turn it is acts from their own view.
local people = { ana, ben }
local function act()
  for _, p in ipairs(people) do
    local g = view(p)
    if g and not g.done then
      if g.phase == 'declaration' then
        now = now + 3
      elseif g.phase == 'kitty' and g.kittyHolder == 1 then
        local ids = {}; for i = 1, g.kittySize do ids[i] = g.hand[i].id end
        command(p, 'bury', ids, g.revision); return true
      elseif g.phase == 'chaodi' and g.chaodiTurn == 1 then
        command(p, 'chaodi_pass', nil, g.revision); return true
      elseif g.phase == 'tricks' and g.turn == 1 then
        local chosen = Rules.choose(g.hand, g.trick[1] and g.trick[1].components, g.trump)
        local ids = {}; for _, c in ipairs(chosen) do table.insert(ids, c.id) end
        command(p, 'play', ids, g.revision); return true
      end
    end
  end
  command(ana, 'sync')
end
local steps = 0
while not view(ana).done do
  steps = steps + 1; assert(steps < 2000, 'Shared round did not finish')
  act()
end
assert(view(ben).done and view(ana).settlement and view(ben).settlement)
assert(inbox[ana].stats.roundsPlayed == 1 and inbox[ben].stats.roundsPlayed == 1, 'Both players are settled once')
assert(view(ana).settlement.netCoins ~= nil and view(ben).settlement.netCoins ~= nil, 'Each sees their own payout')
assert(view(ana).settlement.winner == view(ben).settlement.winner, 'Teammates see the same result')

-- Idle players are auto-played so the table never stalls.
command(ana, 'start')
local idleSteps = 0
while not (view(ben).phase == 'tricks' and view(ben).turn == 1) and not view(ana).done do
  idleSteps = idleSteps + 1; assert(idleSteps < 500)
  local g = view(ana)
  if g.phase == 'kitty' and g.kittyHolder == 1 then act()
  elseif g.phase == 'chaodi' and g.chaodiTurn == 1 then act()
  elseif g.phase == 'tricks' and g.turn == 1 then act()
  else now = now + 1; command(ana, 'sync') end
end
if not view(ana).done then
  local before = #view(ben).hand
  assert(view(ben).turnDeadline, 'A turn timer is shown with several people')
  now = now + 26
  command(ana, 'sync')
  assert(#view(ben).hand < before, 'Ben timed out and a move was played for him')
  assert(inbox[ben].message and inbox[ben].message:find('ran out of time'), 'The table is told why')
end

-- Leaving: the seat goes to a bot and the host role passes on.
command(ana, 'leave')
assert(inbox[ana].table == nil and inbox[ana].game == nil)
assert(inbox[ben].table.isHost and inbox[ben].table.humans == 1, 'Ben becomes host')
assert(inbox[ben].table.seats[3].human == false, "Ana's seat is now a bot")
assert(inbox[ben].message:find('Ana left'))

-- Squads: invite and accept in the same server.
command(ben, 'leave')
command(ana, 'squad_invite', 102)
assert(reactions[ben] and reactions[ben].type == 'invite' and reactions[ben].fromName == 'Ana', 'Ben gets a squad invite')
assert(inbox[ben].invites[1] and inbox[ben].invites[1].fromId == 101)
command(ben, 'squad_accept', 101)
assert(#inbox[ana].squad.members == 2 and inbox[ana].squad.isLeader and not inbox[ben].squad.isLeader, 'Ana leads a squad of two')
assert(command(ben, 'queue', { playerCount = 4, tier = 'novice' }).message:find('leader'), 'Only the leader queues')
-- Squad + two solos fill a 4-player table at once, squad on one team.
command(ana, 'queue', { playerCount = 4, tier = 'novice' })
assert(inbox[ben].search and inbox[ana].search.squadSize == 2, 'The whole squad searches together')
command(cai, 'queue', { playerCount = 4, tier = 'novice' })
command(dev, 'queue', { playerCount = 4, tier = 'novice' })
assert(view(ana) and view(ben) and view(cai) and view(dev), 'A full table is dealt immediately')
assert(inbox[ana].table.id == inbox[cai].table.id and inbox[ana].table.humans == 4)
assert(inbox[ana].table.seats[3].name == 'Ben', 'Squad members are teammates')
assert(inbox[cai].table.seats[3].name == 'Dev', 'The solos make up the other team')
for _, p in ipairs({ ana, ben, cai, dev }) do command(p, 'leave') end
-- Squads must fit on a team; changing the squad cancels its search.
local eve = person('Eve', 105)
command(ana, 'squad_invite', 105)
command(eve, 'squad_accept', 101)
assert(command(ana, 'queue', { playerCount = 4, tier = 'novice' }).message:find('too big'), 'A squad of 3 cannot queue for teams of 2')
command(ana, 'queue', { playerCount = 6, tier = 'novice' })
assert(inbox[eve].search, 'A squad of 3 can queue for 6 players')
command(ana, 'squad_kick', 105)
assert(inbox[eve].squad.solo and inbox[eve].message:find('removed'), 'The leader can remove someone')
assert(not inbox[ana].search, 'Changing the squad cancels the search')
-- Public squads: others in the server can join without an invite.
command(ana, 'squad_privacy', true)
local listed = false
for _, open in ipairs(inbox[eve].openSquads) do if open.leaderId == 101 then listed = open.size == 2 end end
assert(listed, "Eve sees Ana's public squad of two")
command(eve, 'squad_join', 101)
assert(#inbox[ana].squad.members == 3 and inbox[eve].squad.members[1].name == 'Ana', 'Eve joined without an invite')
command(eve, 'squad_leave')
command(ana, 'squad_privacy', false)
for _, open in ipairs(inbox[eve].openSquads) do assert(open.leaderId ~= 101, 'Private squads are not listed') end
assert(command(eve, 'squad_join', 101).message:find('private'), 'Private squads refuse direct joins')
assert(inbox[ben].squad.public == false)
players.PlayerRemoving.handler(ben)
command(ana, 'sync')
assert(inbox[ana].squad.solo, 'A squad of one dissolves when the other leaves')
-- Solos wait, then play with bots; different modes stay apart.
command(cai, 'queue', { playerCount = 4, tier = 'novice' })
command(dev, 'queue', { playerCount = 6, tier = 'novice' })
assert(not inbox[cai].table and inbox[cai].search, 'Waiting in the queue')
now = now + 21
command(cai, 'sync')
assert(view(cai) and inbox[cai].table.humans == 1, 'After the wait, bots fill the table')
assert(view(dev) and inbox[dev].table.id ~= inbox[cai].table.id and inbox[dev].table.playerCount == 6)
players.PlayerRemoving.handler(dev)
command(cai, 'sync')
assert(inbox[cai].table.humans == 1, 'Others leaving never affects your table')
print('PASS: private codes, rotated seats and views, host start, shared round settled per player, reactions between seats, idle auto-play, leaving and host handover, squads (invite, accept, leader-only queue, teammates, size limit, kick, public/private join, disconnect), matchmaking wait and bots')
