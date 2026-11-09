-- Happy Tractor client, part 6/14: ShopRewards.
-- Lines 2479-2942 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local arenaUI, button, color, flatCoinIcon, formatK, frame, gradient, header = C.arenaUI, C.button, C.color, C.flatCoinIcon, C.formatK, C.frame, C.gradient, C.header
local label, make, outline, palette, playSound, rect, remote, rewardsUI = C.label, C.make, C.outline, C.palette, C.playSound, C.rect, C.remote, C.rewardsUI
local robloxGearImages, root = C.robloxGearImages, C.root

-- Card Back Visual Helper
local function renderCardBack(parent, w, h, themeId)
  local card = frame(parent, 'CardBack', palette.panel, math.clamp(math.floor(h * 0.08), 4, 7))
  card.Size = UDim2.fromOffset(w, h)
  card.BorderSizePixel = 0
  -- Shared pieces for the premium backs: an inset frame line, a round
  -- medallion and a glyph, all drawn (no borrowed Roblox item pictures).
  local function inset(tint, alpha)
    local pad = math.max(2, math.floor(w * 0.08))
    local line = frame(card, 'Inset', tint, math.clamp(math.floor(h * 0.05), 2, 5))
    line.BackgroundTransparency = 1
    outline(line, tint, 1).Transparency = alpha or 0.25
    rect(line, pad, pad, w - pad * 2, h - pad * 2)
    return pad
  end
  local function medallion(fill, rim, glyph, glyphTint, scale)
    local size = math.floor(math.min(w, h) * (scale or 0.56))
    local m = frame(card, 'Medallion', fill, 999)
    outline(m, rim, math.max(1, math.floor(size / 18)))
    rect(m, (w - size) / 2, (h - size) / 2, size, size)
    local g = label(m, 'Emblem', glyph, math.max(8, math.floor(size * 0.62)), glyphTint)
    g.Font = Enum.Font.GothamBold
    g.Size = UDim2.fromScale(1, 1)
    return m
  end
  if themeId == 'cardback_dragon' then
    -- Imperial Dragon: crimson silk, gold double frame, gold dragon seal.
    card.BackgroundColor3 = palette.white
    gradient(card, color(196, 36, 44), color(96, 12, 22), 45)
    outline(card, palette.gold, 1.5)
    local pad = inset(palette.gold, 0.15)
    local lattice = label(card, 'Lattice', string.rep('❖ ❖ ❖ ❖ ❖\n', 8), math.max(5, math.floor(w * 0.12)), palette.gold)
    lattice.TextTransparency = 0.8
    lattice.ClipsDescendants = true
    rect(lattice, pad + 1, pad + 1, w - pad * 2 - 2, h - pad * 2 - 2)
    medallion(color(120, 14, 24), palette.gold, '龍', palette.goldBright, 0.6)
  elseif themeId == 'cardback_cyber' then
    -- Neon Matrix: midnight navy with a glowing cyan circuit grid.
    local cyan = color(70, 230, 255)
    card.BackgroundColor3 = palette.white
    gradient(card, color(22, 34, 76), color(6, 10, 26), 135)
    outline(card, cyan, 1.5)
    card.ClipsDescendants = true
    local steps = 5
    for i = 1, steps - 1 do
      local v = frame(card, 'GridV' .. i, cyan, 0)
      v.BackgroundTransparency = 0.72
      rect(v, math.floor(w * i / steps), 0, 1, h)
      local hz = frame(card, 'GridH' .. i, cyan, 0)
      hz.BackgroundTransparency = 0.72
      rect(hz, 0, math.floor(h * i / steps), w, 1)
    end
    for i, p in ipairs({ { 0.2, 0.2 }, { 0.8, 0.4 }, { 0.4, 0.8 }, { 0.6, 0.2 } }) do
      local node = frame(card, 'Node' .. i, cyan, 999)
      local s = math.max(2, math.floor(w * 0.06))
      rect(node, math.floor(w * p[1]) - s / 2, math.floor(h * p[2]) - s / 2, s, s)
    end
    medallion(color(8, 16, 40), cyan, '◆', cyan, 0.46)
  elseif themeId == 'cardback_gold' then
    -- Royale Sovereign: polished gold foil, ivory frame, royal spade seal.
    card.BackgroundColor3 = palette.white
    gradient(card, color(255, 236, 140), color(196, 132, 26), 45)
    outline(card, color(255, 248, 205), 2)
    local pad = inset(color(150, 92, 12), 0.2)
    local lattice = label(card, 'Lattice', string.rep('◆ ◆ ◆ ◆ ◆\n', 8), math.max(5, math.floor(w * 0.13)), color(150, 92, 12))
    lattice.TextTransparency = 0.78
    lattice.ClipsDescendants = true
    rect(lattice, pad + 1, pad + 1, w - pad * 2 - 2, h - pad * 2 - 2)
    medallion(color(255, 222, 110), color(150, 92, 12), '♠', color(150, 92, 12), 0.6)
  else
    card.BackgroundColor3 = color(16, 75, 44)
    gradient(card, color(26, 104, 62), color(10, 48, 28), 90)
    outline(card, palette.gold, 1.4)
    local inset = math.max(2, math.floor(w * 0.08))
    local frameLine = frame(card, 'Inset', palette.goldBright, math.clamp(math.floor(h * 0.05), 2, 5))
    frameLine.BackgroundTransparency = 1
    outline(frameLine, palette.goldBright, 1).Transparency = 0.35
    rect(frameLine, inset, inset, w - inset * 2, h - inset * 2)
    local lattice = label(card, 'Lattice', string.rep('◆ ◆ ◆ ◆ ◆\n', 8), math.max(5, math.floor(w * 0.13)), palette.goldBright)
    lattice.TextTransparency = 0.82
    lattice.ClipsDescendants = true
    rect(lattice, inset + 1, inset + 1, w - inset * 2 - 2, h - inset * 2 - 2)
    local medallion = frame(card, 'Medallion', color(12, 58, 34), 999)
    outline(medallion, palette.gold, 1)
    local size = math.floor(math.min(w, h) * 0.5)
    rect(medallion, (w - size) / 2, (h - size) / 2, size, size)
    local emblem = label(medallion, 'Emblem', '❖', math.max(8, math.floor(size * 0.6)), palette.goldBright)
    emblem.Font = Enum.Font.GothamBold
    emblem.Size = UDim2.fromScale(1, 1)
  end
  return card
end C.renderCardBack = renderCardBack

C.activeShopTab = 'emote'
local shopTabs = {} C.shopTabs = shopTabs
local categoryContainers = {} C.categoryContainers = categoryContainers
local shopItemControls = {} C.shopItemControls = shopItemControls






function arenaUI.initShopUI()
  C.shade = button(root, 'ModalShade', '', function() end, palette.emeraldDark)
  C.shade.BackgroundTransparency = 0.22
  C.shade.Size = UDim2.fromScale(1, 1)
  C.shade.Visible = false
  C.shade.ZIndex = 50

  C.shop = frame(C.shade, 'EmoteShop', palette.panel, 22)
  outline(C.shop, palette.railOuter, 1.5)
  local shopTitle = label(C.shop, 'Title', 'CARD SHOP & COSMETICS', 20, palette.gold)
  shopTitle.Font = Enum.Font.FredokaOne
  local shopHint = label(C.shop, 'Hint', 'Customize your card backs, felt themes, table emotes, or get coins & VIP!', 11, palette.muted)
  local close = button(C.shop, 'Close', '×', function() C.shade.Visible = false end, palette.panelLight)

  local shopTabBar = frame(C.shop, 'TabBar', palette.emeraldDark, 10)
  outline(shopTabBar, palette.panelBorder, 1)

  local tabsDef = {
    { id = 'emote', label = 'EMOTES' },
    { id = 'cardBack', label = 'CARD BACKS' },
    { id = 'felt', label = 'TABLE FELTS' },
    { id = 'product', label = 'COINS & VIP' },
  }

  C.shopScroll = make('ScrollingFrame', C.shop, 'ShopScroll', {
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = palette.gold,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    CanvasSize = UDim2.new(),
  })

  for _, tab in ipairs(tabsDef) do
    local cFrame = frame(C.shopScroll, 'Category_' .. tab.id)
    cFrame.BackgroundTransparency = 1
    cFrame.Size = UDim2.fromScale(1, 1)
    cFrame.Visible = tab.id == 'emote'
    categoryContainers[tab.id] = cFrame
  end

  C.selectShopTab = function(tabId)
    C.activeShopTab = tabId
    for id, btn in pairs(shopTabs) do
      if id == tabId then
        btn.BackgroundColor3 = palette.tileHover
        btn.TextColor3 = palette.goldBright
      else
        btn.BackgroundColor3 = palette.tileBg
        btn.TextColor3 = palette.white
      end
    end
    for id, cFrame in pairs(categoryContainers) do
      cFrame.Visible = id == tabId
    end
    if C.resize then C.resize() end
    if C.renderShopItems then C.renderShopItems() end
  end

  for _, tab in ipairs(tabsDef) do
    local tabId = tab.id
    local tabBtn = button(shopTabBar, 'Tab_' .. tabId, tab.label, function()
      C.selectShopTab(tabId)
    end, palette.tileBg)
    tabBtn.TextSize = 11
    tabBtn.Font = Enum.Font.GothamBold
    shopTabs[tabId] = tabBtn
  end

  C.shopToggle = button(header, 'ShopToggle', '☺', function()
    C.shade.Visible = not C.shade.Visible
    if C.shade.Visible and C.renderShopItems then C.renderShopItems() end
  end, palette.tileBg)
  C.shopToggle.Font = Enum.Font.GothamBold
end
arenaUI.initShopUI()

function arenaUI.initRewardsUI()
  local rShade = button(root, 'RewardsShade', '', function() end, palette.emeraldDark)
  rShade.BackgroundTransparency = 0.22
  rShade.Size = UDim2.fromScale(1, 1)
  rShade.Visible = false
  rShade.ZIndex = 50

  local rModal = frame(rShade, 'RewardsModal', palette.panel, 22)
  outline(rModal, palette.railOuter, 1.5)

  local rTitle = label(rModal, 'Title', 'DAILY REWARDS & FREE COINS', 19, palette.gold)
  rTitle.Font = Enum.Font.FredokaOne
  local rHint = label(rModal, 'Hint', 'Log in daily, claim timed gifts, and complete match quests for coins!', 10, palette.muted)
  local rClose = button(rModal, 'Close', '×', function() rShade.Visible = false end, palette.panelLight)
  rClose.TextSize = 16

  local rScroll = make('ScrollingFrame', rModal, 'RewardsScroll', {
    BackgroundTransparency = 1,
    BorderSizePixel = 0,
    ScrollBarThickness = 4,
    ScrollBarImageColor3 = palette.gold,
    ScrollingDirection = Enum.ScrollingDirection.Y,
    CanvasSize = UDim2.new(),
  })

  -- 1. Daily Login Streaks Section
  local streakSection = frame(rScroll, 'StreakSection', palette.emeraldDark, 12)
  outline(streakSection, palette.panelBorder, 1)
  local streakTitle = label(streakSection, 'Title', '7-DAY LOGIN STREAK  ·  CLAIM YOUR DROP', 13, palette.goldBright)
  streakTitle.Font = Enum.Font.FredokaOne
  streakTitle.TextXAlignment = Enum.TextXAlignment.Left

  local streakRewards = C.Catalog.loginStreak
  local streakCards = {}
  for day = 1, 7 do
    local sCard = frame(streakSection, 'Day' .. day, palette.tileBg, 8)
    outline(sCard, day == 7 and palette.goldBright or palette.panelBorder, 1)
    gradient(sCard, day == 7 and palette.goldBright or palette.panelLight, day == 7 and palette.goldDark or palette.tileBg, 90)
    local sDay = label(sCard, 'DayLabel', 'DAY ' .. day, 9, day == 7 and palette.gold or palette.muted)
    sDay.Font = Enum.Font.GothamBold
    local sIcon = flatCoinIcon(sCard, 'CoinIcon')
    sIcon.ZIndex = 2
    local sAmt = label(sCard, 'AmtLabel', '+' .. formatK(streakRewards[day]), 10, palette.goldBright)
    sAmt.Font = Enum.Font.GothamBold
    sAmt.TextSize = 13
    local sRarity = label(sCard, 'Rarity', day == 7 and 'JACKPOT' or (day >= 4 and 'RARE' or 'DAILY'), 7, day == 7 and palette.ink or palette.muted)
    sRarity.Font = Enum.Font.GothamBold
    streakCards[day] = { card = sCard, day = sDay, icon = sIcon, amt = sAmt, rarity = sRarity }
  end

  local claimDailyBtn = button(streakSection, 'ClaimDaily', 'CLAIM DAY 1', function()
    if C.state and not C.state.dailyClaimed then
      remote:FireServer('claim_daily')
    end
  end)
  claimDailyBtn.TextSize = 12

  -- 2. Timed Free Gift Section
  local giftSection = frame(rScroll, 'GiftSection', palette.emeraldDark, 12)
  outline(giftSection, palette.panelBorder, 1)
  local giftTitle = label(giftSection, 'Title', 'FREE TIMED BONUS', 13, palette.goldBright)
  giftTitle.Font = Enum.Font.GothamBold
  giftTitle.TextXAlignment = Enum.TextXAlignment.Left
  local giftDesc = label(giftSection, 'Desc', 'Free gift ready every 90 seconds. Keep playing to collect more!', 10, palette.muted)
  giftDesc.TextXAlignment = Enum.TextXAlignment.Left

  local claimGiftBtn = button(giftSection, 'ClaimGift', 'CLAIM FREE GIFT (+500 COINS)', function()
    remote:FireServer('claim_gift')
  end)
  claimGiftBtn.TextSize = 12

  -- 3. Daily Quests Section
  local questSection = frame(rScroll, 'QuestSection', palette.emeraldDark, 12)
  outline(questSection, palette.panelBorder, 1)
  local questTitle = label(questSection, 'Title', 'DAILY MATCH QUESTS', 13, palette.goldBright)
  questTitle.Font = Enum.Font.GothamBold
  questTitle.TextXAlignment = Enum.TextXAlignment.Left

  local questRows = {}
  local questKeys = { 'play', 'points', 'emote' }
  for _, qKey in ipairs(questKeys) do
    local qRow = frame(questSection, 'Quest_' .. qKey, palette.tileBg, 8)
    outline(qRow, palette.panelBorder, 1)
    local qName = label(qRow, 'Name', '', 11, palette.cream)
    qName.Font = Enum.Font.GothamBold
    qName.TextXAlignment = Enum.TextXAlignment.Left
    local qProg = label(qRow, 'Progress', '', 10, palette.muted)
    qProg.TextXAlignment = Enum.TextXAlignment.Left

    local qBtn = button(qRow, 'Claim', 'CLAIM', function()
      remote:FireServer('claim_quest', qKey)
    end, palette.panelLight)
    qBtn.TextSize = 10
    questRows[qKey] = { row = qRow, name = qName, prog = qProg, btn = qBtn }
  end

  -- 4. In-Game Earning Summary Pill
  local tipsSection = frame(rScroll, 'TipsSection', palette.tileBg, 10)
  outline(tipsSection, palette.gold, 1)
  local tipsTitle = label(tipsSection, 'Title', 'HOW TO EARN MORE COINS IN TRACTOR', 11, palette.goldBright)
  tipsTitle.Font = Enum.Font.GothamBold
  tipsTitle.TextXAlignment = Enum.TextXAlignment.Left
  local tipsBody = label(tipsSection, 'Body',
    '• Novice (2K–60K Coins): +1K Win (+500 Shutout Bonus)\n' ..
    '• Pro (8K–200K Coins): +2.5K Win (+1.2K Shutout Bonus)\n' ..
    '• Master (100K+ Coins): +8K Win (+4K Shutout Bonus)\n' ..
    '• Daily Login Streaks: Log in 7 days in a row, up to +100K Coins! Missing a day starts over.',
    9, palette.cream)
  tipsBody.TextXAlignment = Enum.TextXAlignment.Left

  local function layoutRewards(w, h)
    if not rShade.Visible then return end
    local mw = math.clamp(w - 40, 320, 560)
    local mh = math.clamp(h - 40, 360, 530)
    rect(rModal, (w - mw) / 2, (h - mh) / 2, mw, mh)
    rect(rTitle, 20, 14, mw - 60, 22)
    rect(rHint, 20, 38, mw - 60, 14)
    rect(rClose, mw - 38, 12, 26, 26)

    local scrollY = 58
    local scrollH = mh - scrollY - 14
    rect(rScroll, 16, scrollY, mw - 32, scrollH)

    local secW = mw - 32
    -- 1. Streaks
    rect(streakSection, 0, 0, secW, 154)
    rect(streakTitle, 12, 10, secW - 24, 18)
    local cardSpacing = 5
    local cardW = math.floor((secW - 24 - (6 * cardSpacing)) / 7)
    for day = 1, 7 do
      local item = streakCards[day]
      rect(item.card, 12 + (day - 1) * (cardW + cardSpacing), 34, cardW, 68)
      rect(item.day, 0, 4, cardW, 12)
      rect(item.icon, math.floor((cardW - 30) / 2), 17, 30, 30)
      rect(item.amt, 0, 45, cardW, 13)
      rect(item.rarity, 0, 57, cardW, 9)
    end
    rect(claimDailyBtn, 12, 112, secW - 24, 32)

    -- 2. Timed Gift
    rect(giftSection, 0, 164, secW, 82)
    rect(giftTitle, 12, 8, secW - 24, 16)
    rect(giftDesc, 12, 26, secW - 24, 14)
    rect(claimGiftBtn, 12, 44, secW - 24, 30)

    -- 3. Quests
    rect(questSection, 0, 256, secW, 172)
    rect(questTitle, 12, 8, secW - 24, 16)
    local qy = 30
    for _, qKey in ipairs(questKeys) do
      local qRow = questRows[qKey]
      rect(qRow.row, 12, qy, secW - 24, 42)
      rect(qRow.name, 10, 6, secW - 130, 15)
      rect(qRow.prog, 10, 22, secW - 130, 14)
      rect(qRow.btn, secW - 130, 7, 90, 28)
      qy = qy + 46
    end

    tipsSection.Visible = false -- the "how to earn more coins" tips were removed
    rScroll.CanvasSize = UDim2.fromOffset(0, 430)
  end

  C.renderRewardsModal = function()
    if not rShade.Visible then return end
    local s = C.state
    local now = os.clock()

    -- 1. Daily Login Streak
    local claimedDaily = s and s.dailyClaimed
    local streakDay = (s and s.streakDay) or 1
    if claimedDaily then
      claimDailyBtn.Text = '✓ DAY ' .. streakDay .. ' CLAIMED (Come back tomorrow!)'
      claimDailyBtn.BackgroundColor3 = palette.panelLight
      claimDailyBtn.TextColor3 = palette.white
    else
      claimDailyBtn.Text = 'CLAIM DAY ' .. streakDay .. ' (+' .. formatK(streakRewards[streakDay]) .. ' COINS)'
      claimDailyBtn.BackgroundColor3 = palette.gold
      claimDailyBtn.TextColor3 = palette.ink
    end
    for day = 1, 7 do
      local item = streakCards[day]
      local done = day < streakDay or (day == streakDay and claimedDaily)
      item.amt.Text = done and '✓' or ('+' .. formatK(streakRewards[day]))
      if done then
        item.card.BackgroundColor3 = palette.tileBg
        item.day.TextColor3 = palette.white
      elseif day == streakDay then
        item.card.BackgroundColor3 = palette.tileHover
        item.day.TextColor3 = palette.goldBright
      else
        item.card.BackgroundColor3 = palette.emeraldDeep
        item.day.TextColor3 = palette.white
      end
    end

    -- 2. Timed Free Gift
    local nextGift = s and s.nextGiftAt or 0
    if now >= nextGift then
      claimGiftBtn.Text = 'CLAIM FREE GIFT (+500 COINS)'
      claimGiftBtn.BackgroundColor3 = palette.gold
      claimGiftBtn.TextColor3 = palette.ink
    else
      local waitSec = math.ceil(nextGift - now)
      claimGiftBtn.Text = 'FREE GIFT IN ' .. waitSec .. 's'
      claimGiftBtn.BackgroundColor3 = palette.panelLight
      claimGiftBtn.TextColor3 = palette.white
    end

    -- 3. Daily Quests
    local quests = s and s.quests or {
      play = { label = 'Play 1 Match', progress = 0, target = 1, reward = 500, claimed = false },
      points = { label = 'Capture 40+ Points', progress = 0, target = 40, reward = 750, claimed = false },
      emote = { label = 'Send a Table Emote', progress = 0, target = 1, reward = 250, claimed = false },
    }
    for _, qKey in ipairs(questKeys) do
      local qData = quests[qKey]
      local qRow = questRows[qKey]
      if qData and qRow then
        qRow.name.Text = qData.label .. ' (+' .. formatK(qData.reward) .. ' Coins)'
        qRow.prog.Text = 'Progress: ' .. qData.progress .. ' / ' .. qData.target
        if qData.claimed then
          qRow.btn.Text = '✓ CLAIMED'
          qRow.btn.BackgroundColor3 = palette.panelLight
          qRow.btn.TextColor3 = palette.white
        elseif qData.progress >= qData.target then
          qRow.btn.Text = 'CLAIM (+' .. formatK(qData.reward) .. ')'
          qRow.btn.BackgroundColor3 = palette.gold
          qRow.btn.TextColor3 = palette.ink
        else
          qRow.btn.Text = math.floor(qData.progress / qData.target * 100) .. '%'
          qRow.btn.BackgroundColor3 = palette.panelLight
          qRow.btn.TextColor3 = palette.white
        end
      end
    end
  end

  C.openRewardsModal = function()
    rShade.Visible = true
    if C.currentLayout then
      layoutRewards(C.currentLayout.width, C.currentLayout.height)
    elseif root then
      local sz = root.AbsoluteSize
      layoutRewards(sz.X, sz.Y)
    end
    C.renderRewardsModal()
  end

  C.triggerCoinToast = function(amount)
    if not amount or amount <= 0 then return end
    playSound('coin')
    local toast = frame(root, 'CoinToast', palette.emeraldDark, 14)
    toast.ZIndex = 95
    outline(toast, palette.goldBright, 2)
    local tLabel = label(toast, 'Label', '💰 +' .. formatK(amount) .. ' COINS!', 16, palette.goldBright)
    tLabel.Font = Enum.Font.GothamBold
    tLabel.Size = UDim2.fromScale(1, 1)

    local sw = C.currentLayout and C.currentLayout.width or 800
    local sh = C.currentLayout and C.currentLayout.height or 600
    local toastW, toastH = 210, 42
    local startX = (sw - toastW) / 2
    local startY = sh * 0.42
    rect(toast, startX, startY, toastW, toastH)
    toast.BackgroundTransparency = 0.05

    if C.TweenService then
      local moveTween = C.TweenService:Create(toast, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.fromOffset(startX, startY - 55),
      })
      local fadeTween = C.TweenService:Create(toast, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        BackgroundTransparency = 1,
      })
      local textFade = C.TweenService:Create(tLabel, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        TextTransparency = 1,
      })
      moveTween:Play()
      fadeTween:Play()
      textFade:Play()
      task.delay(1.4, function() toast:Destroy() end)
    else
      task.delay(1.4, function() toast:Destroy() end)
    end
  end

  C.rewardsToggle = button(header, 'RewardsToggle', 'FREE', function()
    if rShade.Visible then
      rShade.Visible = false
    else
      C.openRewardsModal()
    end
  end, palette.tileBg)
  C.rewardsToggle.Font = Enum.Font.GothamBold
  C.rewardsToggle.Text = 'FREE REWARDS'
  C.rewardsToggle.TextSize = 9
  C.rewardsToggle.TextXAlignment = Enum.TextXAlignment.Center
  C.rewardsToggle.BackgroundColor3 = palette.goldDark
  -- Coin badge on the left, label in the remaining space.
  C.rewardsToggle.Text = ''
  local rewardsLabel = label(C.rewardsToggle, 'Label', 'FREE REWARDS', 11, palette.ink)
  rewardsLabel.Font = Enum.Font.GothamBold
  rewardsLabel.TextWrapped = false
  rewardsLabel.Position = UDim2.fromOffset(28, 0)
  rewardsLabel.Size = UDim2.new(1, -32, 1, 0)
  local freeCoin = frame(C.rewardsToggle, 'FreeCoin', palette.goldBright, 999)
  freeCoin.Size = UDim2.fromOffset(18, 18)
  freeCoin.Position = UDim2.new(0, 6, 0.5, -9)
  outline(freeCoin, palette.ink, 1.2)
  local coinFace = label(freeCoin, 'CoinFace', 'C', 10, palette.ink)
  coinFace.Font = Enum.Font.GothamBlack
  coinFace.Size = UDim2.fromScale(1, 1)
  local freeDot = frame(C.rewardsToggle, 'ReadyDot', palette.green, 999)
  freeDot.Size = UDim2.fromOffset(7, 7)
  freeDot.Position = UDim2.new(1, -10, 0, 4)

  rewardsUI.shade = rShade
  rewardsUI.modal = rModal
  rewardsUI.layout = layoutRewards
end
arenaUI.initRewardsUI()
end
