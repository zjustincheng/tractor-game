-- A lobby server with cross-server matchmaking: tickets go to the shared
-- queue, the matchmaker reserves a server and announces it, and this server
-- teleports its players. Invites from other servers arrive and are followed.
local fakes = dofile('roblox/tests/server_fakes.lua')({ jobId = 'server-A' })
local ana, ben = fakes.person('Ana', 101), fakes.person('Ben', 102)
local cai, dev = fakes.person('Cai', 103), fakes.person('Dev', 104)
assert(fakes.inbox[ana].crossServer == true and not fakes.inbox[ana].matchServer)

fakes.command(ana, 'squad_invite', 102)
fakes.command(ben, 'squad_accept', 101)
fakes.command(ana, 'queue', { playerCount = 4, tier = 'novice' })
local queue = fakes.maps.TractorQueue.data
local count = 0
for _, ticket in pairs(queue) do count = count + 1; assert(#ticket.userIds == 2 and ticket.fill == true) end
assert(count == 1 and fakes.inbox[ben].search, 'The squad is one ticket in the shared queue')
fakes.wall = fakes.wall + 3
fakes.command(cai, 'queue', { playerCount = 4, tier = 'novice' })
fakes.wall = fakes.wall + 3
fakes.command(dev, 'queue', { playerCount = 4, tier = 'novice' })
assert(next(queue) == nil, 'Matched tickets leave the queue')
assert(fakes.reserved == 1, 'One private server is reserved for the match')
local record
for _, value in pairs(fakes.maps.TractorMatches.data) do record = value end
assert(record and record.accessCode == 'access-1' and record.playerCount == 4)
assert(record.seats['1'] and record.seats['3'], 'Seats are recorded for the match server')
local seatOf = {}
for seat, userId in pairs(record.seats) do seatOf[userId] = tonumber(seat) end
assert(seatOf[101] % 2 == seatOf[102] % 2, 'The squad is on one team')
local sent = {}
for _, trip in ipairs(fakes.teleports) do
  assert(trip.options.ReservedServerAccessCode == 'access-1' and trip.options.data.matchId == record.matchId)
  for _, person in ipairs(trip.players) do sent[person.UserId] = true end
end
assert(sent[101] and sent[102] and sent[103] and sent[104], 'Everyone in the match is teleported')
assert(fakes.inbox[cai].message:find('Teleporting'))

-- The matchmaker lock stops two servers matching at once.
fakes.maps.TractorLock.data.matchmaker = { jobId = 'server-B', expires = fakes.wall + 60 }
fakes.wall = fakes.wall + 3
local eve = fakes.person('Eve', 105)
fakes.command(eve, 'queue', { playerCount = 4, tier = 'novice' })
fakes.wall = fakes.wall + 30
fakes.command(eve, 'sync')
assert(fakes.reserved == 1, 'Another server holds the lock, so this one does not match')
fakes.maps.TractorLock.data.matchmaker.expires = fakes.wall - 1
fakes.wall = fakes.wall + 3
fakes.command(eve, 'sync')
assert(fakes.reserved == 2, 'An expired lock is taken over; Eve gets a bot match after waiting')

-- Invites from friends in other servers.
fakes.subscribers.TractorInvite({ Data = { to = 105, fromId = 555, fromName = 'Zed', jobId = 'server-B', placeId = 7 } })
assert(fakes.events[eve].type == 'invite' and fakes.inbox[eve].invites[1].fromName == 'Zed')
local before = #fakes.teleports
fakes.command(eve, 'squad_accept', 555)
local trip = fakes.teleports[before + 1]
assert(trip and trip.options.ServerInstanceId == 'server-B' and trip.options.data.joinSquad == 555, "Accepting joins Zed's server")
-- Inviting someone who is elsewhere publishes a cross-server invite.
fakes.command(ana, 'squad_invite', 999)
local last = fakes.published[#fakes.published]
assert(last.topic == 'TractorInvite' and last.data.to == 999 and last.data.jobId == 'server-A')
print('PASS: cross-server queue, squad ticket, reserved match server, teleports, matchmaker lock and takeover, invites from and to other servers')
