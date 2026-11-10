-- Clamp that tolerates max < min (tiny phone screens) instead of erroring.
local function safeClamp(v, lo, hi) if hi < lo then hi = lo end return math.clamp(v, lo, hi) end
-- Happy Tractor client, part 12/14: Layout.
-- Lines 4536-5379 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Catalog, Layout, Rules, Structures, actionBar, arena, arenaUI, arenaVignette = C.Catalog, C.Layout, C.Rules, C.Structures, C.actionBar, C.arena, C.arenaUI, C.arenaVignette
local centerDeck, chatUI, clear, defenderMeterPlacard, emoteLine, footer, formatK, handFrame = C.centerDeck, C.chatUI, C.clear, C.defenderMeterPlacard, C.emoteLine, C.footer, C.formatK, C.handFrame
local handHint, header, headerChangeTableBtn, headerLobbyBtn, home, inner, luckyUI, mailUI = C.handHint, C.header, C.headerChangeTableBtn, C.headerLobbyBtn, C.home, C.inner, C.luckyUI, C.mailUI
local matchupPlacard, notice, optionsFrame, palette, phaseLine, phaseRibbon, queueUI, rect = C.matchupPlacard, C.notice, C.optionsFrame, C.palette, C.phaseLine, C.phaseRibbon, C.queueUI, C.rect
local rewardsUI, root, rulesUI, score, seats, selectedList, selfAvatar, selfDeclarationCards = C.rewardsUI, C.root, C.rulesUI, C.score, C.seats, C.selectedList, C.selfAvatar, C.selfDeclarationCards
local selfName, settingsUI, settleUI, shopItemControls, shopStatus, shopTabs, subtitle, tableChatBtn = C.selfName, C.settingsUI, C.settleUI, C.shopItemControls, C.shopStatus, C.shopTabs, C.subtitle, C.tableChatBtn
local tier, title, trickLabel, trump, trumpGem, trumpSuit, vaultUI, wallet = C.tier, C.title, C.trickLabel, C.trump, C.trumpGem, C.trumpSuit, C.vaultUI, C.wallet
local walletHint, wordmark = C.walletHint, C.wordmark

C.updateAction = function()
  local current = C.state and C.state.game
  local count = #selectedList()
  local isHome = current == nil or current.done
  -- In play the hint starts empty; the branches below fill it when they have
  -- something to say, so lobby text never lingers at the table.
  if current and not current.done then handHint.Text = '' end

  home.view.Visible = isHome and C.lobbyMode == 'home' and not (current and current.done)
  tier.view.Visible = isHome and C.lobbyMode == 'tier' and not (current and current.done)
  -- Sitting down at a table (a private one included) leaves the Friends page.
  if C.lobbyMode == 'friends' and C.state and C.state.table then C.lobbyMode = 'home' end
  C.friends.view.Visible = isHome and C.lobbyMode == 'friends' and not (current and current.done)
  home.view.Visible = isHome and C.lobbyMode == 'home' and not (current and current.done)
  arenaUI.lobbyBackdrop.Visible = home.view.Visible or tier.view.Visible or C.friends.view.Visible
  settleUI.modal.Visible = current ~= nil and current.done == true
  arenaUI.settleShade.Visible = settleUI.modal.Visible
  actionBar.Visible = not settleUI.modal.Visible
  matchupPlacard.Visible = current ~= nil and not isHome
  defenderMeterPlacard.Visible = false
  if chatUI and chatUI.popover and isHome then chatUI.popover.Visible = false end

  notice.Visible = not isHome
  phaseLine.Visible = not isHome
  phaseRibbon.Visible = not isHome
  score.Visible = false
  trump.Visible = false
  header.Visible = not isHome
  title.Visible = isHome
  footer.Visible = not isHome
  for seat = 2, 10 do seats[seat].holder.Visible = not isHome and seat <= (current and current.playerCount or 4) end

  C.primary.Visible = not current or (current.phase ~= 'declaration' and (current.phase ~= 'chaodi' or (current.chaodiTurn == 1 and C.selectedChaodiIndex ~= nil)))
  -- While someone else plays, the phase line (with its countdown) says so;
  -- a greyed-out "THINKING" button would only repeat it.
  if current and not current.done and current.phase == 'tricks' and current.turn ~= 1 and not C.busy then
    C.primary.Visible = false
  end
  clear.Visible = current ~= nil and not current.done and (current.phase == 'kitty' or (current.phase == 'chaodi' and current.chaodiTurn == 1) or (current.phase == 'tricks' and current.turn == 1))
  clear.Text = (current and current.phase == 'chaodi') and 'PASS (不炒)' or 'Clear'
  tableChatBtn.Visible = current ~= nil and not isHome
  arenaUI.doubleBtn.Visible = current ~= nil and not isHome and current.canDouble == true
  -- The Double phase shows only the button, centred.
  if current and current.phase == 'doubling' then
    C.primary.Visible = false
    arenaUI.doubleBtn.Position = UDim2.new(0.5, -70, 0, 0)
    arenaUI.doubleBtn.Size = UDim2.fromOffset(140, 38)
  end

  local isActionActive = false
  local actionText = 'SELECT CARDS'
  local isLegalPlay = false

  if C.busy then
    isActionActive = false
    actionText = 'SENDING…'
  elseif not current then
    isActionActive = true
    actionText = '▶ QUICK MATCH'
    handHint.Text = 'Finish a round to earn match coins'
  elseif current.done then
    isActionActive = true
    actionText = current.settlement.winner and 'NEW MATCH' or 'NEXT ROUND'
    handHint.Text = current.settlement.winner and 'Match complete · tap New Match' or 'Round complete · tap Next Round'
  elseif current.phase == 'blocked' then
    isActionActive = true
    actionText = 'NEW QUICK MATCH'
    handHint.Text = 'Round blocked · tap to restart'
  elseif current.phase == 'kitty' then
    isActionActive = true
    actionText = count == current.kittySize and ('BURY ' .. count .. ' CARDS') or ('BURY CARDS  ' .. count .. ' / ' .. current.kittySize)
    local replacingKitty = (current.chaodiCount or 0) > 0
    if replacingKitty and count == current.kittySize then
      actionText = 'REPLACE BOTTOM ' .. count .. ' CARDS'
    elseif replacingKitty then
      actionText = 'REPLACE BOTTOM  ' .. count .. ' / ' .. current.kittySize
    end
    handHint.Text = count == current.kittySize and (replacingKitty and 'New bottom ready · tap to confirm' or 'Ready to bury kitty · tap to confirm') or (replacingKitty and ('Choose any ' .. current.kittySize .. ' cards to replace the bottom') or ('Choose ' .. current.kittySize .. ' cards to bury · tap button to auto-select'))
  elseif current.phase == 'chaodi' then
    if current.chaodiTurn == 1 then
      local canChao = current.chaodiOptions and #current.chaodiOptions > 0
      isActionActive = canChao and C.selectedChaodiIndex ~= nil
      actionText = isActionActive and ('炒底 CHAO DI (' .. ((current.chaodiMultiplier or 1) * 2) .. 'x)') or (canChao and 'SELECT A BOTTOM CHALLENGE' or 'PASS (NO CHAO)')
      handHint.Text = canChao and 'Choose a legal pair or triple below, then confirm.' or 'No legal Chao Di cards · tap PASS'
    else
      isActionActive = false
      actionText = 'WAITING FOR CHAO DI…'
      handHint.Text = arenaUI.role(current.chaodiTurn) .. ' is deciding whether to Chao Di…'
    end
  elseif current.phase == 'doubling' then
    isActionActive = false
    actionText = ''
    handHint.Text = ''
  elseif current.phase == 'trick-review' then
    isActionActive = true
    actionText = 'NEXT TRICK'
    handHint.Text = (current.lastWinnerSeat == 1 and 'You won the trick!' or (current.lastWinnerSeat % 2 == 1 and 'Your team won the trick!' or 'Opponents won the trick!')) .. ' Tap Next Trick'
  elseif current.phase == 'tricks' then
    if current.turn ~= 1 then
      isActionActive = false
      actionText = arenaUI.role(current.turn, true) .. ' THINKING…'
      handHint.Text = ''
    else
      if count == 0 then
        isActionActive = true
        actionText = 'SELECT CARDS'
        handHint.Text = 'Tap SELECT CARDS to auto-select · or choose cards to play'
      else
        local cards = {}
        for _, card in ipairs(current.hand) do
          if C.selectedIds[card.id] then table.insert(cards, card) end
        end
        if current.trick[1] then
          local follow = Rules.follow(current.hand, cards, current.trick[1].components, current.trump)
          isLegalPlay = follow.legal == true
          if isLegalPlay then
            isActionActive = true
            actionText = 'PLAY ' .. count .. ' ' .. (count == 1 and 'CARD' or 'CARDS')
            handHint.Text = follow.matchesLead and 'Matching response' or 'Legal follow · cannot win'
          else
            isActionActive = false
            actionText = 'CANNOT PLAY'
            handHint.Text = follow.message or 'Invalid follow combination'
          end
        else
          local comp = Structures.decompose(cards, current.trump)
          isLegalPlay = comp ~= nil
          if isLegalPlay then
            isActionActive = true
            actionText = 'LEAD ' .. count .. ' ' .. (count == 1 and 'CARD' or 'CARDS')
            handHint.Text = Structures.describe(comp)
          else
            isActionActive = false
            actionText = 'INVALID LEAD'
            handHint.Text = 'Lead cards must be the same suit or trump combination'
          end
        end
      end
    end
  end

  local primaryGrad = C.primary:FindFirstChild('Gradient')
  if primaryGrad then primaryGrad.Enabled = isActionActive end
  C.primary.TextColor3 = isActionActive and palette.ink or palette.muted
  C.primary.BackgroundColor3 = isActionActive and palette.gold or palette.panelLight
  local primaryBorder = C.primary:FindFirstChild('Outline')
  if primaryBorder then primaryBorder.Color = isActionActive and palette.goldDark or palette.panelBorder end
  C.primary.Text = actionText
end

C.resize = function()
  local size = root.AbsoluteSize
  if size.X < 1 or size.Y < 1 then return end
  local current = C.state and C.state.game
  local isHome = current == nil or current.done
  local l = Layout.calculate(size.X, size.Y, current and #current.hand or 25)
  C.currentLayout = l
  -- Landscape phones: while declaring / Chao Di, the option strip needs room,
  -- so borrow a little height from the table instead of burying the hand.
  local tightPhase = current and not current.done and (current.phase == 'declaration' or current.phase == 'chaodi')
  if l.short and tightPhase then
    l.actionY = l.actionY - 14
    l.arenaHeight = math.max(70, l.arenaHeight - 14)
  elseif l.short and current and not current.done then
    -- During play a landscape phone shows one status line, not two, and the
    -- table gets the height back so played cards stay clear of the text.
    l.oneLine = true
    l.arenaHeight = l.arenaHeight + 20
  end
  local w, h = l.width, l.height

  -- Header. The trump/points panel sits on the left in play; controls flow
  -- right-to-left with fixed gaps so nothing overlaps at any width. Phones
  -- use two rows: controls on top, the trump/points panel beneath.
  local inGame = current ~= nil and not isHome
  local headerH = l.compact and 84 or (l.short and 44 or 56)
  rect(header, 14, 6, w - 28, headerH)
  title.Visible, subtitle.Visible = not inGame, not inGame and not l.short and not l.compact
  rect(title, 16, 7, l.compact and 190 or 250, 26)
  title.TextSize = l.compact and 19 or 24
  rect(subtitle, 18, 33, 260, 15)
  C.headerSettingsBtn.Visible, headerLobbyBtn.Visible, headerChangeTableBtn.Visible = inGame, inGame, inGame
  tableChatBtn.Visible = inGame
  local controlH = l.short and 28 or 30
  local rowY = l.compact and 6 or math.floor((headerH - controlH) / 2)
  local cursor = w - 28 - 6
  local function place(object, width, height)
    cursor = cursor - width
    rect(object, cursor, rowY + math.floor((controlH - (height or controlH)) / 2), width, height or controlH)
    cursor = cursor - 8
  end
  if inGame then place(C.headerSettingsBtn, controlH) end
  C.shopToggle.Visible = inGame
  if C.shopToggle.Visible then place(C.shopToggle, controlH) end
  local showRewards = not l.compact and (not inGame or w >= 1100)
  C.rewardsToggle.Visible = showRewards
  if showRewards then place(C.rewardsToggle, 138) end
  walletHint.Visible = not l.compact and not l.short
  wallet.TextSize = l.compact and 14 or (l.short and 15 or 18)
  local walletW = l.compact and 76 or (l.short and 120 or 150)
  cursor = cursor - walletW
  rect(wallet, cursor, rowY - (walletHint.Visible and 4 or 0), walletW, walletHint.Visible and 24 or controlH)
  rect(walletHint, cursor, rowY + 20, walletW, 13)
  wallet.TextXAlignment = Enum.TextXAlignment.Right
  walletHint.TextXAlignment = Enum.TextXAlignment.Right
  cursor = cursor - 14
  if inGame then
    if l.compact then
      -- Phones: controls start at the left of the top row.
      local x = 8
      for _, entry in ipairs({ { headerLobbyBtn, 66 }, { headerChangeTableBtn, 70 }, { tableChatBtn, 60 } }) do
        rect(entry[1], x, rowY, entry[2], controlH)
        x = x + entry[2] + 6
      end
    else
      place(headerChangeTableBtn, l.short and 84 or 96)
      place(headerLobbyBtn, l.short and 84 or 92)
      place(tableChatBtn, l.short and 70 or 84)
    end
  end
  for _, control in ipairs({ headerLobbyBtn, headerChangeTableBtn, tableChatBtn, C.rewardsToggle }) do
    control.TextSize = l.short and 11 or 12
  end

  rect(score, 24, l.short and 48 or (l.compact and 60 or 66), w * 0.58, 20)
  score.TextXAlignment = Enum.TextXAlignment.Left
  rect(trump, w * 0.62, l.short and 48 or (l.compact and 60 or 66), w * 0.38 - 24, 20)

  local arenaY = l.arenaY + 16
  local arenaHeight = l.arenaHeight - 16
  local tablePlayers = current and current.playerCount or C.setupPlayerCount
  local arenaInset = l.compact and 18 or (tablePlayers >= 8 and 52 or 38)
  rect(arena, arenaInset, arenaY, w - arenaInset * 2, arenaHeight)
  local aw, ah = w - arenaInset * 2, arenaHeight
  -- Rounded ends track the available table height on every viewport.
  arena.Corner.CornerRadius = UDim.new(0.5, 0)
  inner.Corner.CornerRadius = UDim.new(0.5, 0)
  arenaVignette.Corner.CornerRadius = UDim.new(0.5, 0)
  rect(wordmark, aw * 0.25, ah * 0.38, aw * 0.5, 52)
  rect(arenaUI.wordmarkSub, aw * 0.25, ah * 0.38 + 50, aw * 0.5, 18)

  -- Kuaile Shengji Unified Matchup & Goal Placard (Top-Left Arena)
  -- Kuaile Shengji Unified Trump & Points Placard (Top-Left Arena)
  local matchH = (l.short or l.compact) and 44 or 50
  local gemW = matchH - 8
  local boxH = matchH - 8
  local goalW = (l.short or l.compact) and 170 or 204
  local matchW = gemW + goalW + 12
  if l.compact then
    rect(matchupPlacard, math.floor((w - 260) / 2), 6 + 40, 260, 40)
  else
    rect(matchupPlacard, 22, l.short and 8 or 11, 300, l.short and 40 or 46)
  end

  rect(trumpGem, 4, 4, gemW, gemW)
  rect(arenaUI.trumpTag, 0, 2, gemW, 10)
  rect(trumpSuit, 0, 14, gemW, gemW - 14)

  rect(arenaUI.goalBox, gemW + 8, 4, goalW, boxH)
  rect(arenaUI.goalTitle, 8, 2, goalW - 80, 11)
  arenaUI.goalTitle.TextXAlignment = Enum.TextXAlignment.Left
  rect(arenaUI.goalVal, goalW - 74, 1, 66, 14)
  arenaUI.goalVal.TextXAlignment = Enum.TextXAlignment.Right
  local goalBarH = 5
  rect(arenaUI.goalBar, 8, 17, goalW - 16, goalBarH)
  rect(arenaUI.goalTick40, math.floor((goalW - 16) * 0.5) - 1, 0, 2, goalBarH)
  rect(arenaUI.goalStatus, 8, 25, goalW - 16, 13)
  arenaUI.goalStatus.TextXAlignment = Enum.TextXAlignment.Center
  local stakeX = gemW + goalW + 12
  local stakeW = (l.compact and 260 or 300) - stakeX - 4
  rect(arenaUI.stakePill, stakeX, 4, stakeW, boxH)
  -- Short screens put header buttons over this corner, and compact panels
  -- leave no room; the points title carries the stake there instead.
  arenaUI.stakeInTitle = l.short or stakeW < 30
  -- Ranked has no coin stake to show.
  local ranked = C.state and C.state.game and C.state.game.ranked
  arenaUI.stakePill.Visible = not arenaUI.stakeInTitle and not ranked
  rect(arenaUI.stakeTag, 0, 3, stakeW, 10)
  rect(arenaUI.stakeVal, 0, 14, stakeW, boxH - 16)

  defenderMeterPlacard.Visible = false

  rect(trickLabel, aw * 0.20, ah - 24, aw * 0.6, l.short and 14 or 18)
  if l.short then
    rect(arenaUI.peekButton, aw - 112, 4, 104, 20)
  else
    rect(arenaUI.peekButton, aw - 146, ah - 30, 132, 24)
  end
  trickLabel.TextSize = l.short and 9 or 12

  local deckW, deckH = 46, 64
  rect(centerDeck, (aw - deckW) / 2, ah * 0.44 - deckH / 2, deckW, deckH + 20)
  rect(arenaUI.centerDeckBadge, -18, deckH + 4, deckW + 36, 18)

  for seat = 2, 10 do
    local s = seats[seat]
    local sw = l.compact and 90 or 120
    local avatarSize = l.short and 28 or (l.compact and 34 or 38)
    local sh = avatarSize + 58
    local x = seat == 2 and w - sw - 14 or (seat == 4 and 14 or (w - sw) / 2)
    local y = seat % 2 == 1 and (arenaY - 18) or (arenaY + safeClamp(math.floor(ah * 0.48 - sh * 0.5) + 14, 76, ah - sh))
    rect(s.holder, x, y, sw, sh)
    rect(s.avatar, (sw - avatarSize) / 2, 6, avatarSize, avatarSize)
    rect(s.name, 0, avatarSize + 8, sw, 15)
    rect(s.details, 0, avatarSize + 23, sw, 14)
    rect(s.count, 8, avatarSize + 38, sw - 16, 16)
    s.count.TextXAlignment = Enum.TextXAlignment.Center
    rect(s.declarationCards, (sw - 82) / 2, -25, 82, 24)
    s.details.TextSize = l.compact and 8 or 9
    s.count.Visible = current and current.botCoins and current.botCoins[seat] ~= nil or false
    if s.count.Visible then s.count.Text = formatK(current.botCoins[seat]) .. ' COINS' end

    if seat == 3 then
      local partnerWidth = 188
      rect(s.holder, (w - partnerWidth) / 2, arenaY - 18, partnerWidth, 52)
      rect(s.avatar, 6, 4, 28, 28)
      rect(s.name, 40, 2, partnerWidth - 46, 15)
      s.name.TextXAlignment = Enum.TextXAlignment.Left
      rect(s.details, 40, 18, partnerWidth - 46, 13)
      rect(s.count, 40, 33, partnerWidth - 48, 16)
      s.details.TextXAlignment = Enum.TextXAlignment.Left
      s.details.TextSize = 10
      rect(s.declarationCards, partnerWidth - 74, -22, 68, 22)
      -- Landscape phones: keep the partner panel and its declared-card chip
      -- below the header buttons instead of on top of them.
      if l.short then
        -- Well left of centre, clear of every played card in the middle.
        rect(s.holder, math.max(140, w / 2 - partnerWidth - 96), arenaY - 2, partnerWidth, 52)
        rect(s.declarationCards, partnerWidth + 6, 15, 68, 22)
      end
      s.count.Visible = current and current.botCoins and current.botCoins[seat] ~= nil or false
    end
    s.details.Visible = not l.short
    s.count.Visible = current and current.botCoins and current.botCoins[seat] ~= nil or false
    if current and current.playerCount > 4 then
      local angle = math.pi/2 - (seat-1)*2*math.pi/current.playerCount
      local boxW = l.compact and 54 or 78
      local av = l.compact and 26 or 34
      local boxH = av + 34
      local radiusX = (aw - boxW) * 0.5
      local radiusY = math.max(0, (ah - boxH) * 0.5)
      -- On short tables an ellipse stacks the side seats; a racetrack
      -- (superellipse) shape spreads them toward the corners instead.
      local cx, cy = math.cos(angle), math.sin(angle)
      if 2 * math.sin(math.pi / current.playerCount) * radiusY < boxH + 6 then
        cx = (cx < 0 and -1 or 1) * math.abs(cx) ^ 0.5
        cy = (cy < 0 and -1 or 1) * math.abs(cy) ^ 0.5
      end
      rect(s.holder,arenaInset+aw/2+radiusX*cx-boxW/2,arenaY+ah/2+radiusY*cy-boxH/2,boxW,boxH)
      rect(s.avatar,(boxW-av)/2,3,av,av)
      rect(s.name,0,av+2,boxW,14); s.name.TextSize=l.compact and 9 or 11
      rect(s.count,4,av+18,boxW-8,13); s.count.TextSize=l.compact and 8 or 9
      s.count.Visible = current and current.botCoins and current.botCoins[seat] ~= nil or false
      s.details.Visible=false
      rect(s.declarationCards, (boxW - 64) / 2, -19, 64, 20)
      s.name.TextXAlignment=Enum.TextXAlignment.Center
    end
  end

  -- Home Screen (1252.jpg format) & Tier Screen (1251.jpg format) Layout
  -- Below 600px wide the lobby stacks vertically instead of overflowing.
  local narrowLobby = w < 600
  local lobbyW = narrowLobby and (w - 16) or safeClamp(w - 24, 600, 1040)
  local lobbyH = narrowLobby and math.min(h - 24, 900) or safeClamp(h - 36, 360, 580)
  local lobbyX = math.floor((w - lobbyW) / 2)
  local lobbyY = math.max(10, math.floor((h - lobbyH) / 2))

  rect(home.view, lobbyX, lobbyY, lobbyW, lobbyH)
  rect(tier.view, lobbyX, lobbyY, lobbyW, lobbyH)
  rect(C.friends.view, lobbyX, lobbyY, lobbyW, lobbyH)
  arenaUI.layoutFriends(lobbyW, lobbyH, narrowLobby)

  for _, object in ipairs({ home.dragonFrame, home.heroDesc, tier.rulesBtn }) do
    object.Visible = not narrowLobby
  end
  home.vipBadge.Visible, home.passBadge.Visible = false, false -- not real purchases yet
  for _, card in ipairs({ tier.cardNovice, tier.cardPro, tier.cardMaster }) do
    local stack = card:FindFirstChild('ChipStack')
    if stack then stack.Visible = not narrowLobby end
  end
  if narrowLobby then
    local innerW = lobbyW - 24
    -- Home: header, featured card, 2×2 modes, bottom bar.
    rect(home.header, 12, 10, innerW, 46)
    home.title.Visible = false -- the profile avatar takes this spot on narrow screens
    rect(home.profileBtn, 10, 7, 32, 32)
    rect(home.title, 12, 14, 92, 18)
    rect(home.coinPill, 108, 9, 96, 28)
    -- Phones: a compact warning button, only when saving is off.
    home.saveChip.Visible = C.state ~= nil and C.state.saving ~= nil and not C.state.saving.enabled
    home.saveChip.Text = '⚠'
    rect(home.saveChip, 208, 9, 28, 28)
    rect(home.mailBtn, innerW - 110, 7, 32, 32)
    rect(home.rulesBtn, innerW - 74, 7, 32, 32)
    rect(home.settingsBtn, innerW - 38, 7, 32, 32)
    local heroH = 300
    rect(home.heroCard, 12, 64, innerW, heroH)
    arenaUI.layoutHeroCard(innerW, heroH)
    local gridY = 64 + heroH + 10
    local modeW = math.floor((innerW - 10) / 2)
    local modeH = math.floor((lobbyH - 54 - 10 - gridY - 10) / 2)
    rect(home.mode1, 12, gridY, modeW, modeH)
    -- Smallest table first: 2v2, 3v3 on top, then 4v4, 5v5.
    rect(home.mode4, 12 + modeW + 10, gridY, modeW, modeH)
    rect(home.mode2, 12, gridY + modeH + 10, modeW, modeH)
    rect(home.mode3, 12 + modeW + 10, gridY + modeH + 10, modeW, modeH)
    for _, card in ipairs({ home.mode1, home.mode2, home.mode3, home.mode4 }) do
      local thumbH = math.floor(modeH * 0.58)
      local thumb, badge, btn = card:FindFirstChild('Thumb'), card:FindFirstChild('Badge'), card:FindFirstChild('Action')
      if thumb then rect(thumb, 4, 4, modeW - 8, thumbH) end
      if badge then rect(badge, 6, thumbH + 6, modeW - 12, 16) end
      local description = card:FindFirstChild('Description')
      if description then
        description.Visible = thumbH - 72 >= 18
        rect(description, 10, 46, modeW - 20, math.max(0, thumbH - 72))
      end
      if btn then rect(btn, 8, modeH - 32, modeW - 16, 26) end
    end
    for _, pill in ipairs(home.sidePills) do pill.Visible = false end
    rect(home.bottomBar, 12, lobbyH - 54, innerW, 46)
    home.emoteBtn.Visible = false
    local navW = math.floor((innerW - 16 - 4 * 4) / 5)
    for index, navButton in ipairs({ home.shopBtn, home.historyBtn, home.rewardsBtn, home.luckyBtn, home.vaultBtn }) do
      navButton.Visible = true
      navButton.TextSize = 10
      rect(navButton, 8 + (navW + 4) * (index - 1), 7, navW, 32)
    end

    -- Tier: two-row header, count tabs in a row, stacked table cards.
    rect(tier.header, 12, 10, innerW, 84)
    rect(tier.backBtn, 10, 7, 86, 32)
    rect(tier.coinPill, innerW - 106, 9, 96, 28)
    rect(tier.title, 10, 46, innerW - 190, 32)
    tier.title.TextSize = 12
    rect(tier.matchLength, innerW - 170, 46, 160, 32)
    local tabsY = 10 + 84 + 8
    rect(tier.sidebar, 12, tabsY, innerW, 40)
    local tabW = math.floor((innerW - 12 - 3 * 4) / 4)
    for index, tab in ipairs({ tier.tab6P, tier.tab8P, tier.tab4P, tier.tab10P }) do
      rect(tab, 6 + (tabW + 4) * (index - 1), 4, tabW, 32)
    end
    local cardsY = tabsY + 48
    local cardGap = 8
    local tierH = math.min(144, math.floor((lobbyH - 54 - 8 - cardsY - cardGap * 2) / 3))
    for index, card in ipairs({ tier.cardNovice, tier.cardPro, tier.cardMaster }) do
      rect(card, 12, cardsY + (tierH + cardGap) * (index - 1), innerW, tierH)
      local banner, stakePill, entry = card:FindFirstChild('Banner'), card:FindFirstChild('StakePill'), card:FindFirstChild('Entry')
      local joinBtn, badge, lock = card:FindFirstChild('JoinBtn'), card:FindFirstChild('Badge'), card:FindFirstChild('LockOverlay')
      if banner then rect(banner, 8, 8, innerW - 16, 28) end
      local pillW = math.floor((innerW - 24) * 0.42)
      if stakePill then
        rect(stakePill, 12, 42, pillW, 44)
        local tag, val = stakePill:FindFirstChild('Tag'), stakePill:FindFirstChild('Val')
        if tag then rect(tag, 0, 3, pillW, 12) end
        if val then rect(val, 0, 16, pillW, 26) end
      end
      if entry then rect(entry, 12 + pillW + 8, 52, innerW - pillW - 36, 24) end
      if joinBtn then
        joinBtn.ZIndex = 10
        rect(joinBtn, 12, tierH - 42, innerW - 24, 34)
      end
      if badge then rect(badge, innerW - 54, 10, 46, 18) end
      if lock then rect(lock, 12 + pillW + 8, 44, innerW - pillW - 32, 40) end
      local desc = card:FindFirstChild('Desc')
      if desc then
        rect(desc, 18, 92, innerW - 36, math.max(0, tierH - 92 - 50))
        desc.TextXAlignment = Enum.TextXAlignment.Left
        desc.TextYAlignment = Enum.TextYAlignment.Center
      end
      local best = card:FindFirstChild('BestBadge')
      if best then rect(best, 14, 13, 96, 18) end
    end
    rect(tier.bottomBar, 12, lobbyH - 54, innerW, 46)
    tier.bottomTip.Visible = true
    rect(tier.bottomTip, 14, 6, innerW - 28, 34)
  else
  tier.title.TextSize = 15
  -- 1252.jpg HOME VIEW LAYOUT
  rect(home.header, 12, 10, lobbyW - 24, 46)
  home.title.Visible = true
  rect(home.profileBtn, 10, 7, 32, 32)
  rect(home.title, 50, 14, 124, 18)
  rect(home.coinPill, 178, 9, 100, 28)
  -- Only shown when saving is off.
  home.saveChip.Visible = C.state ~= nil and C.state.saving ~= nil and not C.state.saving.enabled
  rect(home.saveChip, 286, 11, 112, 24)
  rect(home.vipBadge, 286, 11, 58, 24)
  rect(home.passBadge, 350, 11, 64, 24)
  rect(home.settingsBtn, lobbyW - 24 - 38, 7, 32, 32)
  rect(home.rulesBtn, lobbyW - 24 - 74, 7, 32, 32)
  rect(home.mailBtn, lobbyW - 24 - 110, 7, 32, 32)

  local centerH = lobbyH - 128
  local heroW = safeClamp(math.floor(lobbyW * 0.30), 160, 260)
  rect(home.heroCard, 12, 64, heroW, centerH)
  home.dragonFrame.Visible, home.heroDesc.Visible = false, false
  arenaUI.layoutHeroCard(heroW, centerH)

  local hasSideCol = false
  local sideColW = hasSideCol and 110 or 0
  local gridX = 12 + heroW + 10
  local gridW = lobbyW - 24 - heroW - 10 - (hasSideCol and (sideColW + 10) or 0)
  local cardW = math.floor((gridW - 10) / 2)
  local cardH = math.floor((centerH - 10) / 2)

  rect(home.mode1, gridX, 64, cardW, cardH)
  -- Smallest table first: 2v2, 3v3 on top, then 4v4, 5v5.
  rect(home.mode4, gridX + cardW + 10, 64, cardW, cardH)
  rect(home.mode2, gridX, 64 + cardH + 10, cardW, cardH)
  rect(home.mode3, gridX + cardW + 10, 64 + cardH + 10, cardW, cardH)

  local function layoutModeCard(card)
    local thumb = card:FindFirstChild('Thumb')
    local badge = card:FindFirstChild('Badge')
    local btn = card:FindFirstChild('Action')
    local thumbH = math.floor(cardH * 0.58)
    if thumb then rect(thumb, 4, 4, cardW - 8, thumbH) end
    if badge then rect(badge, 6, thumbH + 6, cardW - 12, 16) end
    local description = card:FindFirstChild('Description')
    if description then
      local available = thumbH - 72
      description.Visible = available >= 18
      rect(description, 12, 46, cardW - 24, math.max(0, available))
    end
    if btn then rect(btn, 8, cardH - 32, cardW - 16, 26) end
  end
  layoutModeCard(home.mode1)
  layoutModeCard(home.mode2)
  layoutModeCard(home.mode3)
  layoutModeCard(home.mode4)

  for _, pill in ipairs(home.sidePills) do
    pill.Visible = hasSideCol
  end
  if hasSideCol then
    local sideX = gridX + gridW + 10
    local sideH = math.floor((centerH - 16) / 3)
    for i, pill in ipairs(home.sidePills) do
      rect(pill, sideX, 64 + (sideH + 8) * (i - 1), sideColW, sideH)
    end
  end

  rect(home.bottomBar, 12, lobbyH - 54, lobbyW - 24, 46)
  local homeBarW = lobbyW - 24
  local bBtnW = math.floor((homeBarW - 16 - 4 * 8) / 5)
  home.emoteBtn.Visible = false
  for index, navButton in ipairs({ home.shopBtn, home.historyBtn, home.rewardsBtn, home.luckyBtn, home.vaultBtn }) do
    navButton.TextSize = 12
    rect(navButton, 8 + (bBtnW + 8) * (index - 1), 7, bBtnW, 32)
  end
  home.luckyBtn.Visible = true
  home.vaultBtn.Visible = true

  -- 1251.jpg TIER VIEW LAYOUT
  rect(tier.header, 12, 10, lobbyW - 24, 46)
  rect(tier.backBtn, 10, 7, 86, 32)
  rect(tier.rulesBtn, 102, 7, 32, 32)
  rect(tier.title, 142, 12, lobbyW - 440, 22)
  rect(tier.matchLength, lobbyW - 24 - 105 - 168, 7, 160, 32)
  rect(tier.coinPill, lobbyW - 24 - 105, 9, 96, 28)

  local tierSideW = safeClamp(math.floor(lobbyW * 0.20), 110, 160)
  rect(tier.sidebar, 12, 64, tierSideW, centerH)
  local tierTabH = math.floor((centerH - 24) / 4)
  rect(tier.tab6P, 6, 6 + (tierTabH + 4) * 0, tierSideW - 12, tierTabH)
  rect(tier.tab8P, 6, 6 + (tierTabH + 4) * 1, tierSideW - 12, tierTabH)
  rect(tier.tab4P, 6, 6 + (tierTabH + 4) * 2, tierSideW - 12, tierTabH)
  rect(tier.tab10P, 6, 6 + (tierTabH + 4) * 3, tierSideW - 12, tierTabH)

  local tierCardsX = 12 + tierSideW + 10
  local tierCardsW = lobbyW - 24 - tierSideW - 10
  local tierCardW = math.floor((tierCardsW - 16) / 3)
  rect(tier.cardNovice, tierCardsX, 64, tierCardW, centerH)
  rect(tier.cardPro, tierCardsX + tierCardW + 8, 64, tierCardW, centerH)
  rect(tier.cardMaster, tierCardsX + (tierCardW + 8) * 2, 64, tierCardW, centerH)

  local function layoutTierCard(card)
    local banner, stack, stakePill = card:FindFirstChild('Banner'), card:FindFirstChild('ChipStack'), card:FindFirstChild('StakePill')
    local entry, desc, joinBtn = card:FindFirstChild('Entry'), card:FindFirstChild('Desc'), card:FindFirstChild('JoinBtn')
    local badge, lock, best = card:FindFirstChild('Badge'), card:FindFirstChild('LockOverlay'), card:FindFirstChild('BestBadge')
    local w, h = tierCardW, centerH
    local short = h < 380 -- landscape phones: banner, stake, entry, lock, button
    if banner then rect(banner, 10, 10, w - 20, 34) end
    -- Centre the chips, stake and entry between the banner and the button.
    local dy = short and 0 or math.max(0, math.floor((h - 98 - 210) / 2))
    if stack then stack.Position = UDim2.fromOffset(w / 2, 92 + dy); stack.Visible = not short end
    if desc then desc.Visible = not short end
    if short then
      if stakePill then
        rect(stakePill, 16, 52, w - 32, 50)
        local tag, val = stakePill:FindFirstChild('Tag'), stakePill:FindFirstChild('Val')
        if tag then rect(tag, 0, 4, w - 32, 12) end
        if val then rect(val, 0, 16, w - 32, 30); val.TextSize = 24 end
      end
      if entry then rect(entry, 12, 106, w - 24, 18) end
      if joinBtn then joinBtn.ZIndex = 10; rect(joinBtn, 14, h - 48, w - 28, 36) end
      if lock then rect(lock, 12, h - 90, w - 24, 36) end
      if badge then rect(badge, w - 62, 128, 50, 18) end
      if best then rect(best, 14, 128, 96, 18) end
      return
    end
    if stakePill then
      rect(stakePill, 16, 122 + dy, w - 32, 56)
      local tag, val = stakePill:FindFirstChild('Tag'), stakePill:FindFirstChild('Val')
      if tag then rect(tag, 0, 5, w - 32, 12) end
      if val then rect(val, 0, 18, w - 32, 34); val.TextSize = 28 end
    end
    if entry then rect(entry, 12, 184 + dy, w - 24, 18) end
    if desc then
      rect(desc, 18, 210, w - 36, math.max(0, h - 210 - 112))
      desc.TextXAlignment = Enum.TextXAlignment.Left
      desc.TextYAlignment = Enum.TextYAlignment.Top
      desc.LineHeight = 1.35
    end
    if joinBtn then
      joinBtn.ZIndex = 10
      rect(joinBtn, 14, h - 50, w - 28, 38)
    end
    if lock then rect(lock, 12, h - 98, w - 24, 40) end
    if badge then rect(badge, w - 62, 16, 50, 20) end
    if best then rect(best, 14, 50, 96, 18) end
  end
  layoutTierCard(tier.cardNovice)
  layoutTierCard(tier.cardPro)
  layoutTierCard(tier.cardMaster)

  rect(tier.bottomBar, 12, lobbyH - 54, lobbyW - 24, 46)
  tier.bottomTip.Visible = true
  local barW = lobbyW - 24
  rect(tier.bottomTip, 14, 12, barW - 28, 22)
  end

  -- Phones: below the lobby header (it holds the coins and buttons).
  local barW = math.min(w - 24, 460)
  local barY = narrowLobby and (lobbyY + 62) or 8
  rect(arenaUI.searchBar, (w - barW) / 2, barY, barW, 38)
  rect(arenaUI.invitePopup, (w - barW) / 2, barY + 44, barW, 54)
  arenaUI.compactSearch = narrowLobby
  arenaUI.renderSquad()

  -- Settlement modal, sized to its content.
  local settleW = safeClamp(w - 24, 340, 520)
  local settleH = 312
  rect(settleUI.modal, (w - settleW) / 2, (h - settleH) / 2, settleW, settleH)
  rect(settleUI.banner, 16, 14, settleW - 32, 44)
  settleUI.bannerText.TextSize = 20
  rect(settleUI.levelTitle, 16, 64, settleW - 32, 20)
  settleUI.levelTitle.TextSize = settleW < 420 and 11 or 13
  rect(settleUI.grid, 16, 92, settleW - 32, 56)
  rect(settleUI.scoreA, 10, 6, settleW - 52, 22)
  rect(settleUI.scoreB, 10, 28, settleW - 52, 22)
  rect(settleUI.coinCard, 16, 156, settleW - 32, 86)
  rect(settleUI.coinTotal, 10, 6, settleW - 52, 34)
  rect(settleUI.coinSub, 10, 42, settleW - 52, 38)

  local sBtnH = 40
  local sBtnY = settleH - 56
  local b1W = math.floor((settleW - 56) * 0.42)
  local b2W = math.floor((settleW - 56) * 0.36)
  local b3W = (settleW - 56) - b1W - b2W
  rect(settleUI.playAgain, 16, sBtnY, b1W, sBtnH)
  rect(settleUI.changeTable, 16 + b1W + 12, sBtnY, b2W, sBtnH)
  rect(settleUI.lobby, 16 + b1W + 12 + b2W + 12, sBtnY, b3W, sBtnH)

  local primaryW = l.compact and 170 or 220
  local clearW = l.compact and 54 or 66
  local chatW = l.compact and 60 or 76
  local gap = l.compact and 8 or 10
  local totalBarW = clearW + gap + primaryW + gap + chatW
  local startX = (w - totalBarW) / 2

  if current and current.done then
    C.primary.Visible = false
  elseif isHome then
    C.primary.Visible = false
  else
    C.primary.Parent = actionBar
    C.primary.Visible = true
    rect(C.primary, startX + clearW + gap, 0, primaryW, 38)
  end

  if queueUI and queueUI.modal then
    local qW = safeClamp(w - 48, 380, 520)
    local qH = safeClamp(h - 60, 320, 380)
    rect(queueUI.modal, (w - qW) / 2, (h - qH) / 2, qW, qH)
    rect(queueUI.banner, 16, 14, qW - 32, 36)
    rect(queueUI.tierLabel, 16, 54, qW - 32, 22)

    local vsBoxH = qH - 180
    rect(queueUI.vsBox, 16, 78, qW - 32, vsBoxH)
    local colW = math.floor((qW - 32 - 40) / 2)
    rect(queueUI.teamABox, 8, 8, colW, vsBoxH - 16)
    rect(queueUI.teamATitle, 6, 6, colW - 12, 16)
    rect(queueUI.slot1, 6, 26, colW - 12, 40)
    rect(queueUI.slot3, 6, 70, colW - 12, 40)

    rect(queueUI.vsLabel, colW + 8, (vsBoxH - 30) / 2, 24, 30)

    rect(queueUI.teamBBox, colW + 32, 8, colW, vsBoxH - 16)
    rect(queueUI.teamBTitle, 6, 6, colW - 12, 16)
    rect(queueUI.slot2, 6, 26, colW - 12, 40)
    rect(queueUI.slot4, 6, 70, colW - 12, 40)

    rect(queueUI.statusLabel, 16, 78 + vsBoxH + 6, qW - 32, 20)
    rect(queueUI.startBtn, 16, qH - 52, qW - 140, 38)
    rect(queueUI.cancelBtn, qW - 116, qH - 52, 100, 38)
  end

  rect(notice, 16, l.oneLine and (l.actionY + 19) or (l.actionY - 2), w - 32, 22)
  notice.TextSize = l.compact and 11 or 14
  rect(phaseRibbon, 16, l.oneLine and -200 or (l.actionY + 19), w - 32, 22)
  rect(phaseLine, 20, l.oneLine and -200 or (l.actionY + 21), w - 40, 18)
  rect(actionBar, 0, l.actionY + 43, w, 40)
  rect(clear, startX, 0, clearW, 38)
  if current and current.phase == 'doubling' then
    arenaUI.doubleBtn.Position = UDim2.new(0.5, -70, 0, 0)
    arenaUI.doubleBtn.Size = UDim2.fromOffset(140, 38)
  else
    rect(arenaUI.doubleBtn, math.max(0, startX - 122), 0, 114, 38)
  end
  tableChatBtn.AnchorPoint = Vector2.new(0, 0)
  tableChatBtn.TextXAlignment = Enum.TextXAlignment.Center
  tableChatBtn.TextYAlignment = Enum.TextYAlignment.Center

  if chatUI and chatUI.popover then
    local cpW = safeClamp(w - 24, 300, 420)
    local pad, gap = 12, 8
    local innerW = cpW - pad * 2
    -- Targets: one row when every pill fits at 64px, otherwise rows of three.
    local targetCount = #chatUI.targetDefs
    local perRow = (innerW - 8) / targetCount >= 64 and targetCount or 3
    local targetRows = math.ceil(targetCount / perRow)
    local pillW = math.floor((innerW - 8 - (perRow - 1) * 4) / perRow)
    local y = 0
    rect(chatUI.targetBar, 0, y, innerW, 8 + targetRows * 28)
    for i, td in ipairs(chatUI.targetDefs) do
      local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
      rect(chatUI.targetPills[td.id], 4 + col * (pillW + 4), 4 + row * 28, pillW, 24)
    end
    y = y + 8 + targetRows * 28 + 10
    rect(chatUI.itemsTitle, 2, y, innerW, 14)
    y = y + 18
    local cols = 5
    local tileW = math.floor((innerW - (cols - 1) * gap) / cols)
    local tileH = math.min(72, math.floor(tileW * 1.05))
    for index, id in ipairs(chatUI.tileOrder) do
      local entry = chatUI.throwables[id]
      local col, row = (index - 1) % cols, math.floor((index - 1) / cols)
      rect(entry.button, col * (tileW + gap), y + row * (tileH + gap), tileW, tileH)
      local tileFrame = entry.button:FindFirstChild('Tile')
      if not tileFrame or tileFrame.Size.X.Offset ~= tileW or tileFrame.Size.Y.Offset ~= tileH then
        if tileFrame then tileFrame:Destroy() end
        tileFrame = arenaUI.R.tile(entry.button, 'Tile', entry.def, tileW, tileH, true, entry.price > 0)
      end
      rect(entry.lock, tileW - 42, 3, 39, 15)
    end
    y = y + math.ceil(#chatUI.tileOrder / cols) * (tileH + gap) + 4
    rect(chatUI.dialogueTitle, 2, y, innerW, 14)
    y = y + 18
    local chipW = math.floor((innerW - gap) / 2)
    for index, chip in ipairs(chatUI.phraseBtns) do
      local col, row = (index - 1) % 2, math.floor((index - 1) / 2)
      rect(chip, col * (chipW + gap), y + row * 34, chipW, 28)
    end
    y = y + math.ceil(#chatUI.phraseBtns / 2) * 34
    local headerH = 46
    local cpH = math.min(headerH + y + 18, math.max(220, l.actionY - 16))
    local cpX = safeClamp(startX + totalBarW - cpW, 12, w - cpW - 12)
    local cpY = math.max(12, l.actionY - cpH - 8)
    rect(chatUI.popover, cpX, cpY, cpW, cpH)
    rect(chatUI.title, pad, 8, 120, 18)
    rect(chatUI.hint, pad, 25, cpW - 80, 14)
    rect(chatUI.close, cpW - pad - 26, 10, 26, 26)
    rect(chatUI.body, pad, headerH, innerW + 4, cpH - headerH - 14)
    chatUI.body.CanvasSize = UDim2.fromOffset(0, y)
    rect(chatUI.cooldown, pad, cpH - 9, innerW, 3)
    if arenaUI.refreshDock then arenaUI.refreshDock() end
  end
  local declarationStripHeight = current and current.phase == 'declaration' and 76 or 40
  rect(optionsFrame, 16, l.actionY + 43, w - 32, declarationStripHeight)
  if current and current.phase == 'chaodi' then
    rect(actionBar, 0, l.actionY + 85, w, 40)
  end
  local declarationHandOffset = current and (current.phase == 'declaration' or current.phase == 'chaodi') and (l.short and 22 or 44) or 0
  rect(handFrame, 16, l.handY + declarationHandOffset, w - 32, math.max(80, l.handHeight - declarationHandOffset))
  handFrame.CanvasSize = UDim2.fromOffset(l.contentWidth, 0)
  rect(footer, 12, h - 34, w - 24, 30)
  rect(selfAvatar, 8, 4, 22, 22)
  rect(selfDeclarationCards, 2, -24, 82, 22)
  rect(selfName, 36, 0, l.compact and 100 or 150, 30)
  rect(handHint, l.compact and 140 or 192, 0, w - (l.compact and 328 or 390), 30)
  handHint.TextSize = l.compact and 9 or 11
  rect(C.historyButton,w-110,3,74,24)
  rect(C.autoButton,w-182,3,66,24)
  local historyW, historyH = math.min(640,w-24), math.min(560,h-24)
  rect(C.historyPanel,(w-historyW)/2,(h-historyH)/2,historyW,historyH)
  rect(C.historyTitle,16,12,historyW-80,32)
  rect(C.historyClose,historyW-52,10,36,32)
  rect(C.historyBody,12,54,historyW-24,historyH-66)
  rect(emoteLine, w * 0.2, l.arenaY + l.arenaHeight * 0.68, w * 0.6, 34)

  -- Every tab shows big tiles (CoinShop / ShopGrid), so the shop is roomy.
  local coinTab = C.activeShopTab == 'product'
  local shopWidth = math.min(640, w - 24)
  local shopHeight = math.min(600, h - 24)
  rect(C.shop, (w - shopWidth) / 2, (h - shopHeight) / 2, shopWidth, shopHeight)
  if C.shop then
    rect(C.shop:FindFirstChild('Title'), 18, 14, shopWidth - 76, 26)
    rect(C.shop:FindFirstChild('Close'), shopWidth - 46, 12, 34, 34)
    rect(C.shop:FindFirstChild('Hint'), 18, 42, shopWidth - 36, 18)
    rect(C.shop:FindFirstChild('TabBar'), 16, 64, shopWidth - 32, 32)
  end

  local tabW = math.floor((shopWidth - 32 - 12) / 4)
  local tabIds = { 'emote', 'cardBack', 'felt', 'product' }
  for idx, tid in ipairs(tabIds) do
    if shopTabs[tid] then
      rect(shopTabs[tid], (idx - 1) * (tabW + 4), 2, tabW, 28)
    end
  end

  local scrollY = 102
  local scrollH = shopHeight - scrollY - 68
  rect(C.shopScroll, 16, scrollY, shopWidth - 32, scrollH)

  -- Layout rows in each category
  local rowH = 46
  local rowGap = 6
  local categoryCounts = {}
  for _, item in ipairs(Catalog) do
    local cat = item.category or 'emote'
    categoryCounts[cat] = (categoryCounts[cat] or 0) + 1
    local ctrl = shopItemControls[item.id]
    if ctrl then
      local yIdx = categoryCounts[cat] - 1
      rect(ctrl.row, 0, yIdx * (rowH + rowGap), shopWidth - 44, rowH)
      rect(ctrl.icon, 8, 8, 30, 30)
      rect(ctrl.name, 44, 6, shopWidth - 190, 18)
      rect(ctrl.desc, 44, 24, shopWidth - 190, 14)
      rect(ctrl.button, shopWidth - 180, 8, 128, 30)
    end
  end

  local currentCatCount = categoryCounts[C.activeShopTab] or 4
  C.shopScroll.CanvasSize = UDim2.fromOffset(0, currentCatCount * (rowH + rowGap) + 10)
  if coinTab and C.layoutCoinShop then C.layoutCoinShop(shopWidth - 32, scrollH) end
  if not coinTab and C.layoutShopGrid then C.layoutShopGrid(C.activeShopTab, shopWidth - 32, scrollH) end

  local footY = shopHeight - 58
  local muteW = math.floor((shopWidth - 42) * 0.52)
  rect(C.muteButton, 18, footY, muteW, 28)
  C.muteButton.TextSize = 11
  rect(C.shopBalance, 18 + muteW + 8, footY, shopWidth - 44 - muteW - 8, 28)
  rect(shopStatus, 18, shopHeight - 26, shopWidth - 36, 18)
  if rewardsUI and rewardsUI.layout then
    rewardsUI.layout(w, h)
  end
  if settingsUI and settingsUI.layout then settingsUI.layout() end
  if rulesUI and rulesUI.layout then rulesUI.layout() end
  if mailUI and mailUI.layout then mailUI.layout() end
  if luckyUI and luckyUI.layout then luckyUI.layout() end
  if vaultUI and vaultUI.layout then vaultUI.layout() end
  C.renderHand()
end
end
