-- Profile cosmetics: catalog integrity, saving, equipping, buying and earning.
math.clamp = math.clamp or function(value, low, high) return math.max(low, math.min(high, value)) end
local Catalog = dofile('roblox/src/shared/Catalog.luau')
local Persistence = dofile('roblox/src/server/Persistence.luau')(nil, Catalog, nil)

local function session(extra)
  local s = { coins = 10000, stats = {}, owned = { frame_none = true, title_newcomer = true, banner_forest = true },
    equipped = { frame = 'frame_none', title = 'title_newcomer', banner = 'banner_forest' }, receipts = {} }
  for k, v in pairs(extra or {}) do s[k] = v end
  return s
end

-- Every item has exactly one way to obtain it and what the page needs to draw it.
local seen = {}
for _, item in ipairs(Catalog) do seen[item.id] = true end
for _, item in ipairs(Catalog.profile) do
  assert(not seen[item.id], 'duplicate id ' .. item.id); seen[item.id] = true
  local ways = (item.starter and 1 or 0) + (item.price and 1 or 0) + (item.unlock and 1 or 0) + (item.vip and 1 or 0) + (item.pass and 1 or 0)
  assert(ways == 1, item.id .. ' must have one way to obtain it')
  if item.category == 'frame' and item.id ~= 'frame_none' then assert(item.ring and #item.ring == 2, item.id) end
  if item.category == 'title' then assert(item.color and #item.color == 3, item.id) end
  if item.category == 'banner' then assert(item.colors and #item.colors == 2, item.id) end
  if item.unlock then assert(item.unlock.stat and item.unlock.at > 0 and item.unlock.label, item.id) end
end
for _, stat in ipairs(Persistence.STAT_KEYS) do seen['stat:' .. stat] = true end
for _, item in ipairs(Catalog.profile) do
  if item.unlock then assert(seen['stat:' .. item.unlock.stat], item.id .. ' uses an unsaved stat') end
end

-- Saving keeps valid cosmetics and drops forged ones.
local clean = Persistence.sanitize({
  owned = { frame_gold = true, title_roller = true, banner_ocean = true, forged = true },
  equipped = { frame = 'frame_gold', title = 'banner_ocean', banner = 'forged' },
})
assert(clean.owned.frame_gold and clean.owned.title_roller and clean.owned.banner_ocean and not clean.owned.forged)
assert(clean.equipped.frame == 'frame_gold', 'valid frame kept')
assert(clean.equipped.title == nil, 'item in the wrong slot dropped')
assert(clean.equipped.banner == nil, 'unknown item dropped')

-- A changed frame, title or banner must count as unsaved progress.
local before = Persistence.snapshot(session({ owned = { frame_none = true, frame_gold = true } }))
local changed = Persistence.snapshot(session({ owned = { frame_none = true, frame_gold = true }, equipped = { frame = 'frame_gold', title = 'title_newcomer', banner = 'banner_forest' } }))
assert(Persistence.signature(before) ~= Persistence.signature(changed), 'equipping changes the save signature')

-- Loaded equipment applies only if it is owned.
local loaded = session()
Persistence.apply(loaded, { owned = {}, stats = {}, equipped = { frame = 'frame_dragon' } })
assert(loaded.equipped.frame == 'frame_none', 'unowned frame not worn after load')

-- Equipping needs ownership and a wearable slot.
local wearer = session()
assert(Persistence.equip(wearer, 'frame_gold') == nil and wearer.equipped.frame == 'frame_none', 'cannot wear unowned')
wearer.owned.frame_gold = true
assert(Persistence.equip(wearer, 'frame_gold').id == 'frame_gold' and wearer.equipped.frame == 'frame_gold')
wearer.owned.wave = true
assert(Persistence.equip(wearer, 'wave') == nil, 'emotes have no slot')
assert(Persistence.equip(wearer, 'nonsense') == nil)

-- Buying charges once, wears the item, and refuses everything else.
local buyer = session({ coins = 3000 })
local item, problem = Persistence.buyProfileItem(buyer, 'frame_bamboo')
assert(item and buyer.coins == 500 and buyer.owned.frame_bamboo and buyer.equipped.frame == 'frame_bamboo', problem)
item, problem = Persistence.buyProfileItem(buyer, 'frame_bamboo')
assert(not item and problem == 'Already unlocked.' and buyer.coins == 500, 'no double charge')
item = Persistence.buyProfileItem(buyer, 'frame_sakura')
assert(not item and buyer.coins == 500 and not buyer.owned.frame_sakura, 'cannot afford')
local rich = session({ coins = 1e9 })
for _, id in ipairs({ 'frame_shutout', 'frame_vip', 'title_shark', 'frame_none', 'cardback_dragon', 'nonsense' }) do
  item = Persistence.buyProfileItem(rich, id)
  assert(not item and rich.coins == 1e9 and (id == 'frame_none' or not rich.owned[id]), id .. ' is not for sale here')
end

-- Earned items arrive at the threshold and only once.
local player = session({ stats = { shutouts = 4 } })
assert(#Persistence.grantEarned(player) == 0, 'below every threshold')
player.stats.shutouts = 5
local granted = Persistence.grantEarned(player)
assert(#granted == 1 and granted[1].id == 'title_shutout' and player.owned.title_shutout)
assert(#Persistence.grantEarned(player) == 0, 'granted once')
player.stats.shutouts = 10
assert(Persistence.grantEarned(player)[1].id == 'frame_shutout')
local vip = session({ vip = true })
local vipIds = {}
for _, entry in ipairs(Persistence.grantEarned(vip)) do vipIds[entry.id] = true end
assert(vipIds.frame_vip and vipIds.title_vip, 'VIP rewards')

print('PASS: profile cosmetics')
