-- Seven-day login streak.
math.clamp = math.clamp or function(value, low, high) return math.max(low, math.min(high, value)) end
local Catalog = dofile('roblox/src/shared/Catalog.luau')
local Persistence = dofile('roblox/src/server/Persistence.luau')(nil, Catalog, nil)
local DAY = 86400
local START = 20000 * DAY + 100
local function session() return { coins = 0, stats = {}, owned = {}, equipped = {}, receipts = {} } end
assert(#Catalog.loginStreak == 7 and Catalog.loginStreak[1] == 3000 and Catalog.loginStreak[7] == 30000)

-- A new player starts on day 1 and is paid once a day.
local s = session()
assert(Persistence.streakDay(s, START) == 1)
local day, coins = Persistence.claimDaily(s, START)
assert(day == 1 and coins == 3000 and s.coins == 3000)
assert(Persistence.streakDay(s, START) == 1, 'still shows the day just claimed')
assert(Persistence.claimDaily(s, START + 60) == nil and s.coins == 3000, 'one claim per day')

-- Each following day pays the next amount, then day 7 loops back to day 1.
local total = 3000
for expected = 2, 7 do
  local now = START + (expected - 1) * DAY
  assert(Persistence.streakDay(s, now) == expected, 'next day shown before claiming')
  day, coins = Persistence.claimDaily(s, now)
  total = total + Catalog.loginStreak[expected]
  assert(day == expected and coins == Catalog.loginStreak[expected] and s.coins == total)
end
assert(Persistence.streakDay(s, START + 7 * DAY) == 1, 'loops after day 7')
assert(Persistence.claimDaily(s, START + 7 * DAY) == 1)

-- Missing a day starts over.
local missed = session()
Persistence.claimDaily(missed, START)
Persistence.claimDaily(missed, START + DAY)
assert(missed.loginStreak == 2)
assert(Persistence.streakDay(missed, START + 3 * DAY) == 1, 'a missed day resets')
assert(Persistence.claimDaily(missed, START + 3 * DAY) == 1)

-- A save from before streaks existed behaves.
local old = session()
old.lastDailyDay = Persistence.today(START) - 1
assert(Persistence.streakDay(old, START) == 1)
old.lastDailyDay = Persistence.today(START)
assert(Persistence.streakDay(old, START) == 1 and Persistence.claimDaily(old, START) == nil)

-- It saves and restores, and forged values are limited.
local saved = session()
Persistence.claimDaily(saved, START)
Persistence.claimDaily(saved, START + DAY)
local data = Persistence.snapshot(saved)
assert(data.loginStreak == 2)
local restored = session()
Persistence.apply(restored, data)
assert(Persistence.streakDay(restored, START + 2 * DAY) == 3)
assert(Persistence.sanitize({ loginStreak = 999 }).loginStreak == 7)
local other = session(); other.lastDailyDay, other.loginStreak = saved.lastDailyDay, 1
assert(Persistence.signature(Persistence.snapshot(other)) ~= Persistence.signature(data), 'streak changes count as unsaved')
print('PASS: login streak')
