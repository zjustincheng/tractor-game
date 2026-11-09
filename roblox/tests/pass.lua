-- Battle Pass: XP, tiers, claiming, saving and season resets.
math.clamp = math.clamp or function(value, low, high) return math.max(low, math.min(high, value)) end
local Catalog = dofile('roblox/src/shared/Catalog.luau')
local Persistence = dofile('roblox/src/server/Persistence.luau')(nil, Catalog, nil)
local pass = Catalog.pass
local NOW = pass.endsAt - 1000
local function session(xp, premium)
  local s = { coins = 0, stats = {}, owned = {}, equipped = {}, receipts = {}, pass = Persistence.newPass() }
  s.pass.xp, s.pass.premium = xp or 0, premium == true
  return s
end

-- Catalog: 30 tiers, every reward exists, every pass item is reachable exactly once.
assert(#pass.tiers == 30)
local items, granted = {}, {}
for _, item in ipairs(Catalog.profile) do items[item.id] = item end
for _, rewards in ipairs(pass.tiers) do
  for _, track in ipairs({ 'free', 'premium' }) do
    local reward = rewards[track]
    assert(reward and (reward.coins or reward.item or reward.boost))
    if reward.boost then assert(track == 'free' and (reward.boost == 30 or reward.boost == 60), 'boosts are free-track, 30 or 60 minutes') end
    if reward.item then
      assert(items[reward.item] and items[reward.item].pass, reward.item .. ' must be a pass item')
      assert(not granted[reward.item], reward.item .. ' appears twice')
      granted[reward.item] = true
    end
  end
end
for id, item in pairs(items) do if item.pass then assert(granted[id], id .. ' is unobtainable') end end

-- XP.
local s = session()
assert(Persistence.passAddXp(s, false, false, NOW) == pass.xp.play)
assert(Persistence.passAddXp(s, true, false, NOW) == pass.xp.play + pass.xp.win)
assert(Persistence.passAddXp(s, true, true, NOW) == pass.xp.play + pass.xp.win + pass.xp.shutout)
assert(Persistence.passAddXp(session(), true, true, pass.endsAt) == 0, 'no XP after the season')
local max = #pass.tiers * pass.xpPerTier
local nearMax = session(max - 5)
assert(Persistence.passAddXp(nearMax, true, true, NOW) == 5 and nearMax.pass.xp == max, 'XP stops at the top')
assert(Persistence.passTier(pass.xpPerTier - 1) == 0 and Persistence.passTier(pass.xpPerTier) == 1 and Persistence.passTier(max * 2) == 30)

-- Claiming.
s = session(pass.xpPerTier)
local reward, problem = Persistence.passClaim(s, 'free', 2)
assert(not reward and problem == 'Reach that tier first.' and s.coins == 0)
reward = Persistence.passClaim(s, 'free', 1)
assert(reward and s.coins == pass.tiers[1].free.coins, 'coins paid')
reward, problem = Persistence.passClaim(s, 'free', 1)
assert(not reward and problem == 'Already claimed.' and s.coins == pass.tiers[1].free.coins, 'no double claim')
reward, problem = Persistence.passClaim(s, 'premium', 1)
assert(not reward and problem == 'Unlock Premium to claim that.' and s.coins == pass.tiers[1].free.coins, 'premium is locked')
for _, bad in ipairs({ { 'free', 0 }, { 'free', 31 }, { 'free', 1.5 }, { 'free', 'x' }, { 'nope', 1 } }) do
  assert(not Persistence.passClaim(s, bad[1], bad[2]), 'bad claim refused')
end

-- Premium, items and claim all.
s = session(5 * pass.xpPerTier, true)
local coins, count = Persistence.passClaimAll(s)
assert(count == 9, 'five tiers on both tracks, minus the timed boost')
local expected = 0
for tier = 1, 5 do expected = expected + (pass.tiers[tier].free.coins or 0) + (pass.tiers[tier].premium.coins or 0) end
assert(coins == expected and s.coins == expected)
assert(s.owned.title_lantern and s.owned.title_ace, 'tier 5 items granted')
assert(select(2, Persistence.passClaimAll(s)) == 0, 'nothing left')
assert(Persistence.equip(s, 'title_ace').id == 'title_ace', 'claimed cosmetics can be worn')
local free = session(5 * pass.xpPerTier, false)
assert(select(2, Persistence.passClaimAll(free)) == 4 and not free.owned.title_ace, 'free players get only the free track')
assert(Persistence.markersLeft(free) == 0, 'claim all skips timed boosts')

-- Timed card markers: banked play time, spent only when ticked.
local boosted = session(3 * pass.xpPerTier, false)
assert(Persistence.markersLeft(boosted) == 0)
local granted30 = Persistence.passClaim(boosted, 'free', 3)
assert(granted30 and granted30.boost == 30 and Persistence.markersLeft(boosted) == 1800, '30 minutes')
Persistence.tickMarkers(boosted, 600)
assert(Persistence.markersLeft(boosted) == 1200, 'burns only when ticked')
Persistence.tickMarkers(boosted, 5000)
assert(Persistence.markersLeft(boosted) == 0, 'never goes below zero')
assert(not Persistence.passClaim(boosted, 'free', 3), 'one claim only')
local stacking = session(13 * pass.xpPerTier, false)
Persistence.passClaim(stacking, 'free', 3)
Persistence.passClaim(stacking, 'free', 13)
assert(Persistence.markersLeft(stacking) == 1800 + 3600, 'time stacks')
local vipPlayer = session(3 * pass.xpPerTier, false)
vipPlayer.vip = true
local refused, why = Persistence.passClaim(vipPlayer, 'free', 3)
assert(not refused and why == 'VIP already includes card markers.' and Persistence.markersLeft(vipPlayer) == 0)
local saved = session(0, false)
saved.markerSeconds = 900.7
local snap = Persistence.snapshot(saved)
assert(snap.markerSeconds == 900, 'time left is saved')
local plain = session(0, false)
assert(Persistence.signature(Persistence.snapshot(plain)) ~= Persistence.signature(snap), 'a change counts as unsaved')
local restored = session(0, false)
Persistence.apply(restored, snap)
assert(Persistence.markersLeft(restored) == 900, 'time left is restored')

-- Pass items can't be bought with coins.
local rich = session(0)
rich.coins = 1e9
assert(not Persistence.buyProfileItem(rich, 'frame_season1') and rich.coins == 1e9)

-- Unlock once.
s = session()
assert(Persistence.passUnlock(s) and s.pass.premium and not Persistence.passUnlock(s))

-- Saving keeps progress, rejects junk and notices changes.
s = session(450, true)
Persistence.passClaim(s, 'free', 3); Persistence.passClaim(s, 'premium', 1)
local data = Persistence.snapshot(s)
assert(data.pass.xp == 450 and data.pass.premium and #data.pass.claimedFree == 1 and #data.pass.claimedPremium == 1)
local forged = Persistence.sanitize({ pass = { season = 's1', xp = 1e12, premium = 'yes', claimedFree = { 1, 1, 99, 'x', 2 } } })
assert(forged.pass.xp == max and forged.pass.premium == false and #forged.pass.claimedFree == 2, 'forged data cleaned')
local before = Persistence.signature(data)
local changed = session(450, true); Persistence.passClaim(changed, 'free', 3); Persistence.passClaim(changed, 'premium', 1); Persistence.passClaim(changed, 'free', 2)
assert(Persistence.signature(Persistence.snapshot(changed)) ~= before, 'a claim counts as unsaved progress')

-- A new season starts fresh; this season's save is restored.
local loaded = session()
Persistence.apply(loaded, { owned = {}, stats = {}, equipped = {}, pass = { season = 'old', xp = 900, premium = true, claimedFree = {}, claimedPremium = {} } })
assert(loaded.pass.xp == 0 and not loaded.pass.premium, 'old season discarded')
Persistence.apply(loaded, { owned = {}, stats = {}, equipped = {}, pass = data.pass })
assert(loaded.pass.xp == 450, 'current season restored')

print('PASS: battle pass')
