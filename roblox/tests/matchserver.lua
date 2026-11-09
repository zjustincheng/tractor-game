-- A reserved match server: players arrive with a match id, are seated from
-- the shared match record (not from client data), and play; Lobby returns them.
local fakes = dofile('roblox/tests/server_fakes.lua')({ jobId = 'match-1', privateServerId = 'private-1' })
local matchMap = game:GetService('MemoryStoreService'):GetSortedMap('TractorMatches')
matchMap:SetAsync('m1', { matchId = 'm1', accessCode = 'access-1', playerCount = 4, tier = 'novice', fullMatch = false,
  seats = { ['1'] = 101, ['3'] = 102, ['2'] = 103 } })
local ana = fakes.person('Ana', 101, { matchId = 'm1' })
assert(fakes.inbox[ana].matchServer == true)
assert(fakes.inbox[ana].table and fakes.inbox[ana].table.status == 'waiting', 'Seated, waiting for the others')
local ben = fakes.person('Ben', 102, { matchId = 'm1' })
assert(fakes.inbox[ben].table.seats[3].name == 'Ana', 'Ben sits opposite Ana as recorded')
local stranger = fakes.person('Mal', 999, { matchId = 'm1' })
assert(fakes.inbox[stranger].table == nil and fakes.inbox[stranger].message:find('no seat'), 'Players not in the record get no seat')
assert(fakes.teleports[#fakes.teleports].players[1] == stranger, 'and are sent back to the lobby')
local cai = fakes.person('Cai', 103, { matchId = 'm1' })
fakes.command(ana, 'sync')
assert(fakes.inbox[ana].game and fakes.inbox[cai].game, 'Everyone arrived, so the match is dealt')
assert(fakes.inbox[ana].table.humans == 3 and fakes.inbox[ana].table.seats[4].human == false, 'The missing seat is a bot')
-- A late or missing player does not hold the table forever.
matchMap:SetAsync('m2', { matchId = 'm2', accessCode = 'access-2', playerCount = 4, tier = 'novice', seats = { ['1'] = 201, ['2'] = 202 } })
local dee = fakes.person('Dee', 201, { matchId = 'm2' })
fakes.command(dee, 'sync')
assert(not fakes.inbox[dee].game, 'Waits for the other player')
fakes.clock = fakes.clock + 16
fakes.command(dee, 'sync')
assert(fakes.inbox[dee].game, 'Starts with a bot after the arrival wait')
-- Lobby sends players back to a public server.
local before = #fakes.teleports
fakes.command(ana, 'lobby')
local trip = fakes.teleports[before + 1]
assert(trip and trip.placeId == 7 and trip.players[1] == ana and trip.options == nil)
print('PASS: match server seats arrivals from the shared record, ignores strangers, deals when all arrive or after the wait, returns players to the lobby')
