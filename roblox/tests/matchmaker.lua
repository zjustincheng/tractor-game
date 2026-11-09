-- Pure matchmaking rules: squads stay together, fill, waiting and launching.
local Matchmaker = dofile('roblox/src/server/Matchmaker.luau')()

local nextId = 0
local function ticket(userIds, options)
  options = options or {}
  nextId = nextId + 1
  return { id = 't' .. nextId, userIds = userIds, playerCount = options.playerCount or 4, tier = options.tier or 'novice',
    fullMatch = options.fullMatch or false, fill = options.fill ~= false, queuedAt = options.at or 0 }
end
local function teamOf(seat) return seat % 2 == 1 and 'A' or 'B' end
local function sameTeam(match, a, b)
  local seatA, seatB
  for seat, userId in pairs(match.seats) do
    if userId == a then seatA = seat end
    if userId == b then seatB = seat end
  end
  return seatA and seatB and teamOf(seatA) == teamOf(seatB)
end

-- Squads must fit on one team.
assert(Matchmaker.valid(ticket({ 1, 2 })))
assert(not Matchmaker.valid(ticket({ 1, 2, 3 })), 'A squad of 3 cannot share a 2-person team')
assert(Matchmaker.valid(ticket({ 1, 2, 3 }, { playerCount = 6 })))

-- Four solos make a full match immediately.
local matches, waiting = Matchmaker.form({ ticket({ 1 }), ticket({ 2 }), ticket({ 3 }), ticket({ 4 }) }, 0)
assert(#matches == 1 and #waiting == 0 and matches[1].humans == 4)

-- A squad of two plus two solos: the squad shares a team.
matches = Matchmaker.form({ ticket({ 1 }), ticket({ 10, 11 }), ticket({ 2 }) , ticket({ 3 }) }, 0)
assert(#matches == 1 and sameTeam(matches[1], 10, 11), 'Squad members are teammates')
assert(not sameTeam(matches[1], 1, 10) or not sameTeam(matches[1], 2, 10), 'Solos fill around the squad')

-- Two squads of two face each other.
matches = Matchmaker.form({ ticket({ 1, 2 }), ticket({ 3, 4 }) }, 0)
assert(#matches == 1 and sameTeam(matches[1], 1, 2) and sameTeam(matches[1], 3, 4) and not sameTeam(matches[1], 1, 3))

-- Not enough people: wait, then launch with bots after the limit.
matches, waiting = Matchmaker.form({ ticket({ 1 }, { at = 0 }), ticket({ 2 }, { at = 5 }) }, 10)
assert(#matches == 0 and #waiting == 2, 'Waits for more players')
matches, waiting = Matchmaker.form(waiting, 20)
assert(#matches == 1 and matches[1].humans == 2 and #waiting == 0, 'Launches with bots after the wait')
local seatCount = 0
for _ in pairs(matches[1].seats) do seatCount = seatCount + 1 end
assert(seatCount == 2, 'Only people get seats; the rest are bots')

-- Fill off: a duo in 6-player keeps its third seat for a bot, never a stranger.
local duo = ticket({ 1, 2 }, { playerCount = 6, fill = false, at = 0 })
local solos = { ticket({ 3 }, { playerCount = 6, at = 25 }), ticket({ 4 }, { playerCount = 6, at = 25 }), ticket({ 5 }, { playerCount = 6, at = 25 }), ticket({ 6 }, { playerCount = 6, at = 26 }) }
matches, waiting = Matchmaker.form({ duo, solos[1], solos[2], solos[3], solos[4] }, 30)
assert(#matches == 1 and sameTeam(matches[1], 1, 2))
for _, solo in ipairs({ 3, 4, 5, 6 }) do assert(not sameTeam(matches[1], 1, solo), 'No strangers join a no-fill squad') end
assert(matches[1].humans == 5 and #waiting == 1, 'Three solos fill the other team; the fourth waits')
-- Fill on: the duo gets a stranger on its team.
matches = Matchmaker.form({ ticket({ 1, 2 }, { playerCount = 6, at = 0 }), ticket({ 3 }, { playerCount = 6 }), ticket({ 4 }, { playerCount = 6 }),
  ticket({ 5 }, { playerCount = 6 }), ticket({ 6 }, { playerCount = 6 }) }, 0)
assert(#matches == 1 and matches[1].humans == 6, 'Fill completes the table with strangers')

-- Different modes never mix.
matches, waiting = Matchmaker.form({ ticket({ 1 }), ticket({ 2 }, { tier = 'pro' }), ticket({ 3 }, { fullMatch = true }), ticket({ 4 }) }, 0)
assert(#matches == 0 and #waiting == 4)

-- Oldest first: with five solos for one table, the newest waits.
matches, waiting = Matchmaker.form({ ticket({ 1 }, { at = 1 }), ticket({ 2 }, { at = 2 }), ticket({ 3 }, { at = 3 }), ticket({ 4 }, { at = 4 }), ticket({ 5 }, { at = 5 }) }, 6)
assert(#matches == 1 and #waiting == 1 and waiting[1].userIds[1] == 5)
print('PASS: matchmaker keeps squads on one team, fill on/off, waits then launches with bots, separates modes, oldest first')
