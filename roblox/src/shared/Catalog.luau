return {
  { id = 'wave', label = 'Noob Wave', price = 0, category = 'emote', image = 'rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150' },
  { id = 'cheer', label = 'Bloxy Trophy', price = 0, category = 'emote', image = 'rbxthumb://type=Asset&id=25162389&w=150&h=150' },
  { id = 'laugh', label = 'Epic Face', price = 600, category = 'emote', image = 'rbxthumb://type=Asset&id=7074786&w=150&h=150' },
  { id = 'wow', label = 'Cheezburger', price = 1000, category = 'emote', image = 'rbxthumb://type=Asset&id=15967743&w=150&h=150' },
  { id = 'flower', label = 'Roblox Rose', price = 0, category = 'emote', image = 'rbxthumb://type=Asset&id=108149171&w=150&h=150' },
  { id = 'tomato', label = 'Splat Tomato', price = 600, category = 'emote', image = 'rbxthumb://type=Asset&id=115377964&w=150&h=150' },
  { id = 'bomb', label = 'Timebomb', price = 1500, category = 'emote', image = 'rbxthumb://type=Asset&id=11999247&w=150&h=150' },
  { id = 'coffee', label = 'Bloxy Cola', price = 800, category = 'emote', image = 'rbxthumb://type=Asset&id=10472779&w=150&h=150' },
  { id = 'tractor_rush', label = 'Speed Coil', price = 3000, category = 'emote', image = 'rbxthumb://type=Asset&id=99119158&w=150&h=150' },

  { id = 'cardback_classic', label = 'Classic Emerald', price = 0, category = 'cardBack', desc = 'Classic emerald felt with gold diamond trim' },
  { id = 'cardback_dragon', label = 'Imperial Dragon', price = 8000, category = 'cardBack', robux = 49, image = 'rbxthumb://type=Asset&id=67148404&w=150&h=150', desc = 'Golden imperial dragon on crimson silk' },
  { id = 'cardback_cyber', label = 'Neon Matrix', price = 18000, category = 'cardBack', robux = 79, image = 'rbxthumb://type=Asset&id=11999236&w=150&h=150', desc = 'Futuristic glowing cyan circuit lattice' },
  { id = 'cardback_gold', label = 'Royale Sovereign', price = 50000, category = 'cardBack', robux = 149, image = 'rbxthumb://type=Asset&id=25162389&w=150&h=150', desc = '24K reflective gold foil with ornate filigree' },

  { id = 'felt_emerald', label = 'Emerald Lounge', price = 0, category = 'felt', desc = 'Classic club emerald felt with golden stitch' },
  { id = 'felt_sapphire', label = 'Royal Sapphire', price = 6000, category = 'felt', robux = 49, desc = 'Deep sapphire velvet felt with brass rails' },
  { id = 'felt_ruby', label = 'Imperial Ruby', price = 15000, category = 'felt', robux = 69, desc = 'Crimson wine velvet felt with gold trim' },
  { id = 'felt_obsidian', label = 'Obsidian VIP', price = 40000, category = 'felt', robux = 99, desc = 'Matte carbon obsidian felt with platinum rail' },

  -- productId / gamePassId: paste the IDs from Creator Hub (Monetization).
  -- 0 means not on sale yet; the shop says so instead of prompting.
  { id = 'product_coins_10k', label = '50K Coins', price = 0, category = 'product', robux = 39, coins = 50000, productId = 3729878183, image = 'rbxassetid://84997199523345', desc = 'Starter bag of coins' },
  { id = 'product_coins_50k', label = '250K Coins (+30%)', price = 0, category = 'product', robux = 149, coins = 250000, productId = 3729878307, image = 'rbxassetid://83669766952611', desc = 'Great value coin sack' },
  { id = 'product_coins_200k', label = '1.2M Coins (+88%)', price = 0, category = 'product', robux = 499, coins = 1200000, productId = 3729878374, image = 'rbxassetid://75326390158213', desc = 'Whale Room treasure chest' },
  { id = 'gamepass_vip', label = 'VIP Tractor Pass', price = 0, category = 'product', robux = 199, gamePassId = 2075164460, image = 'rbxassetid://137651052301606', desc = 'Permanent 2x coins plus gamble and suit markers' },

  -- Profile cosmetics (avatar frames, titles, banners). Kept out of the list
  -- above so they only appear on the profile page. An item is obtained with
  -- coins (price), by reaching a lifetime stat (unlock), or by owning VIP (vip).
  profile = {
    { id = 'frame_none', label = 'No Frame', category = 'frame', starter = true },
    { id = 'frame_bamboo', label = 'Bamboo Ring', category = 'frame', price = 2500, ring = { { 150, 220, 110 }, { 40, 120, 70 } }, glyph = '🎋' },
    { id = 'frame_sakura', label = 'Cherry Blossom', category = 'frame', price = 6000, ring = { { 255, 190, 215 }, { 225, 80, 140 } }, glyph = '🌸' },
    { id = 'frame_gold', label = 'Gold Laurel', category = 'frame', price = 15000, ring = { { 255, 225, 120 }, { 190, 120, 20 } }, glyph = '👑' },
    { id = 'frame_neon', label = 'Neon Pulse', category = 'frame', price = 30000, ring = { { 60, 230, 255 }, { 240, 60, 220 } }, glyph = '⚡', spin = true },
    { id = 'frame_dragon', label = 'Imperial Dragon', category = 'frame', price = 75000, ring = { { 255, 215, 90 }, { 200, 30, 40 } }, glyph = '🐉', spin = true },
    { id = 'frame_shutout', label = 'Shutout Crown', category = 'frame', unlock = { stat = 'shutouts', at = 10, label = 'Shutouts' }, ring = { { 245, 245, 255 }, { 120, 140, 200 } }, glyph = '🏅' },
    { id = 'frame_vip', label = 'VIP Diamond', category = 'frame', vip = true, ring = { { 190, 240, 255 }, { 90, 110, 255 } }, glyph = '💎', spin = true },

    { id = 'title_newcomer', label = 'Newcomer', category = 'title', starter = true, color = { 215, 225, 235 } },
    { id = 'title_shark', label = 'Card Shark', category = 'title', unlock = { stat = 'roundsWon', at = 25, label = 'Wins' }, color = { 130, 215, 255 } },
    { id = 'title_driver', label = 'Tractor Driver', category = 'title', unlock = { stat = 'roundsPlayed', at = 100, label = 'Rounds' }, color = { 160, 235, 130 } },
    { id = 'title_shutout', label = 'Shutout Artist', category = 'title', unlock = { stat = 'shutouts', at = 5, label = 'Shutouts' }, color = { 255, 170, 90 } },
    { id = 'title_comeback', label = 'Comeback Kid', category = 'title', unlock = { stat = 'overturns', at = 10, label = 'Comebacks' }, color = { 255, 130, 170 } },
    { id = 'title_chaodi', label = 'Chao Di Master', category = 'title', unlock = { stat = 'chaodis', at = 10, label = 'Chao Di' }, color = { 200, 160, 255 } },
    { id = 'title_champion', label = 'Match Champion', category = 'title', unlock = { stat = 'matchesWon', at = 10, label = 'Matches' }, color = { 255, 215, 90 } },
    { id = 'title_roller', label = 'High Roller', category = 'title', price = 20000, color = { 255, 200, 60 } },
    { id = 'title_legend', label = 'Legend of Tractor', category = 'title', price = 100000, color = { 255, 95, 80 } },
    { id = 'title_vip', label = 'VIP Member', category = 'title', vip = true, color = { 190, 240, 255 } },

    { id = 'banner_forest', label = 'Bamboo Forest', category = 'banner', starter = true, colors = { { 36, 120, 80 }, { 12, 52, 40 } } },
    { id = 'banner_dusk', label = 'Lantern Dusk', category = 'banner', price = 4000, colors = { { 240, 140, 70 }, { 110, 40, 90 } } },
    { id = 'banner_ocean', label = 'Deep Ocean', category = 'banner', price = 8000, colors = { { 50, 150, 220 }, { 16, 36, 100 } } },
    { id = 'banner_ember', label = 'Red Ember', category = 'banner', price = 20000, colors = { { 225, 60, 50 }, { 70, 10, 30 } } },
    { id = 'banner_galaxy', label = 'Night Galaxy', category = 'banner', price = 50000, colors = { { 120, 70, 230 }, { 12, 12, 50 } } },

    -- Ranked season rewards (see Catalog.rankSeason.rewards): only obtainable
    -- by reaching that tier in a season.
    { id = 'frame_rank_bronze', label = 'Bronze Ranked', category = 'frame', rank = 'Bronze', ring = { { 205, 127, 50 }, { 92, 52, 22 } }, glyph = '🥉' },
    { id = 'frame_rank_silver', label = 'Silver Ranked', category = 'frame', rank = 'Silver', ring = { { 210, 220, 235 }, { 90, 104, 130 } }, glyph = '🥈' },
    { id = 'frame_rank_gold', label = 'Gold Ranked', category = 'frame', rank = 'Gold', ring = { { 255, 210, 70 }, { 160, 100, 12 } }, glyph = '🥇' },
    { id = 'frame_rank_platinum', label = 'Platinum Ranked', category = 'frame', rank = 'Platinum', ring = { { 90, 225, 210 }, { 16, 96, 108 } }, glyph = '💠', spin = true },
    { id = 'frame_rank_diamond', label = 'Diamond Ranked', category = 'frame', rank = 'Diamond', ring = { { 120, 190, 255 }, { 30, 56, 170 } }, glyph = '💎', spin = true },
    { id = 'frame_rank_master', label = 'Master Crown', category = 'frame', rank = 'Master', ring = { { 230, 110, 245 }, { 92, 20, 130 } }, glyph = '👑', spin = true },
    { id = 'title_rank_bronze', label = 'Bronze Contender', category = 'title', rank = 'Bronze', color = { 215, 145, 80 } },
    { id = 'title_rank_silver', label = 'Silver Contender', category = 'title', rank = 'Silver', color = { 200, 210, 228 } },
    { id = 'title_rank_gold', label = 'Gold Contender', category = 'title', rank = 'Gold', color = { 255, 205, 70 } },
    { id = 'title_rank_platinum', label = 'Platinum Ace', category = 'title', rank = 'Platinum', color = { 90, 225, 210 } },
    { id = 'title_rank_diamond', label = 'Diamond Ace', category = 'title', rank = 'Diamond', color = { 120, 190, 255 } },
    { id = 'title_rank_master', label = 'Ranked Master', category = 'title', rank = 'Master', color = { 230, 120, 245 } },

    -- Battle Pass exclusives: only obtainable by claiming that tier.
    { id = 'title_lantern', label = 'Lantern Keeper', category = 'title', pass = true, color = { 255, 190, 110 } },
    { id = 'banner_lantern', label = 'Lantern Festival', category = 'banner', pass = true, colors = { { 240, 120, 60 }, { 120, 24, 40 } } },
    { id = 'frame_lantern', label = 'Paper Lantern', category = 'frame', pass = true, ring = { { 255, 180, 90 }, { 215, 60, 50 } }, glyph = '🏮' },
    { id = 'title_season1', label = 'Season One Veteran', category = 'title', pass = true, color = { 170, 220, 255 } },
    { id = 'title_ace', label = 'Ace of Trumps', category = 'title', pass = true, color = { 255, 120, 120 } },
    { id = 'frame_phoenix', label = 'Phoenix Flame', category = 'frame', pass = true, ring = { { 255, 210, 80 }, { 240, 70, 30 } }, glyph = '🔥', spin = true },
    { id = 'banner_aurora', label = 'Aurora Night', category = 'banner', pass = true, colors = { { 60, 220, 180 }, { 50, 30, 120 } } },
    { id = 'frame_jade', label = 'Imperial Jade', category = 'frame', pass = true, ring = { { 170, 255, 200 }, { 20, 130, 90 } }, glyph = '🍀', spin = true },
    { id = 'title_grandmaster', label = 'Grandmaster', category = 'title', pass = true, color = { 215, 170, 255 } },
    { id = 'frame_season1', label = 'Season One Crown', category = 'frame', pass = true, ring = { { 255, 240, 170 }, { 160, 90, 255 } }, glyph = '👑', spin = true },
  },

  -- Coins for each day of the 7-day login streak.
  -- (Trimmed so free coins don't undercut the Robux packs: ~63K per week.)
  loginStreak = { 3000, 4000, 5000, 6000, 7000, 8000, 30000 },

  -- Ranked seasons: 30 days each from Season 1's start (2026-11-10 UTC). Every
  -- player's Rank Points go back to 0 when a new season begins.
  -- When a season ends, players get the coins of the best division they
  -- reached that season, plus the frame and title of that tier and every tier
  -- below. Coins climb a little with each division and steeply toward Master.
  rankSeason = { start = 1794268800, days = 30,
    stepCoins = {
      10000, 15000, 25000, -- Bronze III, II, I
      40000, 60000, 85000, -- Silver III, II, I
      125000, 175000, 250000, -- Gold III, II, I
      350000, 475000, 650000, -- Platinum III, II, I
      900000, 1250000, 1750000, -- Diamond III, II, I
      2500000, -- Master
    },
    rewards = {
      Bronze = { frame = 'frame_rank_bronze', title = 'title_rank_bronze' },
      Silver = { frame = 'frame_rank_silver', title = 'title_rank_silver' },
      Gold = { frame = 'frame_rank_gold', title = 'title_rank_gold' },
      Platinum = { frame = 'frame_rank_platinum', title = 'title_rank_platinum' },
      Diamond = { frame = 'frame_rank_diamond', title = 'title_rank_diamond' },
      Master = { frame = 'frame_rank_master', title = 'title_rank_master' },
    },
  },

  -- Ranked ladder: Rank Points (RP) needed to reach each tier (each tier below
  -- Master splits into three divisions; see Scoring.rankStanding). A win earns RP
  -- and a loss costs some (more against people than against bots); Bronze
  -- players never lose RP. The amounts are in the server's settlement code.
  -- 1,200 RP per tier, so each of its three divisions is 400 RP: about five
  -- games for a typical player (see Scoring.rankDelta).
  ranks = {
    { name = 'Bronze', at = 0 }, { name = 'Silver', at = 1200 }, { name = 'Gold', at = 2400 },
    { name = 'Platinum', at = 3600 }, { name = 'Diamond', at = 4800 }, { name = 'Master', at = 6000 },
  },

  -- Roblox badges: paste each Badge ID from Creator Hub (Engagement > Badges).
  -- 0 means that badge is not created yet and is simply skipped.
  badges = {
    welcome = 3252681235058986,      -- joined Happy Tractor
    first_win = 42513605240980,    -- won a round
    chaodi = 2815072982860861,       -- 'The Overturn': made a successful Chao Di
    shutout = 1343966510173496,      -- won a round with a shutout
    high_roller = 1881009317192411,  -- played a round in a High Stakes room
    millionaire = 0,  -- held 1,000,000 coins
  },

  -- Battle Pass season. Change id to start a new season (XP and claims reset).
  -- productId: paste the Developer Product ID from Creator Hub; 0 means not on sale yet.
  pass = {
    id = 's1', name = 'Lantern Season', endsAt = 1798761600, xpPerTier = 150, robux = 199, productId = 3730084242,
    xp = { play = 25, win = 25, shutout = 15 },
    tiers = {
      { free = { coins = 1650 }, premium = { coins = 5100 } },
      { free = { coins = 1800 }, premium = { coins = 5700 } },
      { free = { boost = 30 }, premium = { coins = 6300 } },
      { free = { coins = 2100 }, premium = { coins = 6900 } },
      { free = { item = 'title_lantern' }, premium = { item = 'title_ace' } },
      { free = { coins = 2400 }, premium = { coins = 8100 } },
      { free = { coins = 2550 }, premium = { coins = 8700 } },
      { free = { boost = 30 }, premium = { coins = 9300 } },
      { free = { coins = 2850 }, premium = { coins = 9900 } },
      { free = { item = 'banner_lantern' }, premium = { item = 'frame_phoenix' } },
      { free = { coins = 3150 }, premium = { coins = 11100 } },
      { free = { coins = 3300 }, premium = { coins = 11700 } },
      { free = { boost = 60 }, premium = { coins = 12300 } },
      { free = { coins = 3600 }, premium = { coins = 12900 } },
      { free = { item = 'frame_lantern' }, premium = { item = 'banner_aurora' } },
      { free = { coins = 3900 }, premium = { coins = 14100 } },
      { free = { coins = 4050 }, premium = { coins = 14700 } },
      { free = { boost = 30 }, premium = { coins = 15300 } },
      { free = { coins = 4350 }, premium = { coins = 15900 } },
      { free = { coins = 4500 }, premium = { item = 'frame_jade' } },
      { free = { coins = 4650 }, premium = { coins = 17100 } },
      { free = { coins = 4800 }, premium = { coins = 17700 } },
      { free = { boost = 60 }, premium = { coins = 18300 } },
      { free = { coins = 5100 }, premium = { coins = 18900 } },
      { free = { coins = 5250 }, premium = { item = 'title_grandmaster' } },
      { free = { coins = 5400 }, premium = { coins = 20100 } },
      { free = { coins = 5550 }, premium = { coins = 20700 } },
      { free = { boost = 60 }, premium = { coins = 21300 } },
      { free = { coins = 5850 }, premium = { coins = 21900 } },
      { free = { item = 'title_season1' }, premium = { item = 'frame_season1' } },
    },
  },

  -- Quick-chat lines, shared so the server accepts exactly what the dock offers.
  phrases = {
    { id = 'nice_play', text = 'Nice play, partner!' },
    { id = 'good_luck', text = 'Good luck!' },
    { id = 'watch_trump', text = 'Watch out for trump!' },
    { id = 'push_shutout', text = 'Push for shutout!' },
    { id = 'tractor_rush', text = 'Tractor rush incoming!' },
    { id = 'wait', text = 'Wait for my play!' },
    { id = 'thinking', text = 'Thinking about this move…' },
    { id = 'good_game', text = 'Good game everyone!' },
  },
}
