-- Clamp that tolerates max < min (tiny phone screens) instead of erroring.
local function safeClamp(v, lo, hi) if hi < lo then hi = lo end return math.clamp(v, lo, hi) end
-- Happy Tractor client, part 13/14: Render.
-- Lines 5380-6101 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Cards, arena, arenaGradient, arenaUI, button, cardFace, centerDeck, centerMedallion = C.Cards, C.arena, C.arenaGradient, C.arenaUI, C.button, C.cardFace, C.centerDeck, C.centerMedallion
local centerTrumpDisplay, color, command, corner, destroyChildren, feltThemes, formatK, frame = C.centerTrumpDisplay, C.color, C.command, C.corner, C.destroyChildren, C.feltThemes, C.formatK, C.frame
local getRevealedCards, gradient, home, label, make, meterBarFill, meterStatus, meterVal = C.getRevealedCards, C.gradient, C.home, C.label, C.make, C.meterBarFill, C.meterStatus, C.meterVal
local notice, optionsFrame, outline, palette, playLayer, playSound, rect, renderCardBack = C.notice, C.optionsFrame, C.outline, C.palette, C.playLayer, C.playSound, C.rect, C.renderCardBack
local renderDeclarationCards, score, seats, selfDealerSeal, selfDeclarationCards, selfName, settleUI, suitColors = C.renderDeclarationCards, C.score, C.seats, C.selfDealerSeal, C.selfDeclarationCards, C.selfName, C.settleUI, C.suitColors
local symbols, tier, trickLabel, triggerTractorBanner, trump, trumpSuit, tween, wordmark = C.symbols, C.tier, C.trickLabel, C.triggerTractorBanner, C.trump, C.trumpSuit, C.tween, C.wordmark

C.render = function()
  C.resize()
  if not C.state or not C.currentLayout then return end
  if C.renderRewardsModal then C.renderRewardsModal() end
  C.updateCoinDisplays(C.state.coins)
  local coins = C.state.coins or 0
  local qualTierName = 'Novice Table · Base 500'
  if coins >= 100000 then
    qualTierName = 'Master Arena · Base 4K'
  elseif coins >= 8000 then
    qualTierName = 'Pro Lounge · Base 1.2K'
  elseif coins < 2000 then
    qualTierName = 'Need 2K Coins (Claim Gift!)'
  end

  if tier.noviceJoinBtn then
    local nGrad = tier.noviceJoinBtn:FindFirstChild('Gradient')
    if coins < 2000 then
      if nGrad then nGrad.Enabled = false end
      tier.noviceJoinBtn.Text = '🔒 LOCKED'
      tier.noviceJoinBtn.BackgroundColor3 = palette.panelLight
      tier.noviceJoinBtn.TextColor3 = palette.white
    elseif coins > 60000 then
      if nGrad then nGrad.Enabled = false end
      tier.noviceJoinBtn.Text = 'MAX 60K COINS'
      tier.noviceJoinBtn.BackgroundColor3 = palette.panelLight
      tier.noviceJoinBtn.TextColor3 = palette.white
    else
      if nGrad then nGrad.Enabled = true end
      tier.noviceJoinBtn.Text = 'PLAY NOVICE ▶'
      tier.noviceJoinBtn.BackgroundColor3 = palette.gold
      tier.noviceJoinBtn.TextColor3 = palette.ink
    end
  end

  if tier.proJoinBtn then
    local pGrad = tier.proJoinBtn:FindFirstChild('Gradient')
    if coins < 8000 then
      if pGrad then pGrad.Enabled = false end
      tier.proJoinBtn.Text = '🔒 LOCKED'
      tier.proJoinBtn.BackgroundColor3 = palette.panelLight
      tier.proJoinBtn.TextColor3 = palette.white
    elseif coins > 200000 then
      if pGrad then pGrad.Enabled = false end
      tier.proJoinBtn.Text = 'MAX 200K COINS'
      tier.proJoinBtn.BackgroundColor3 = palette.panelLight
      tier.proJoinBtn.TextColor3 = palette.white
    else
      if pGrad then pGrad.Enabled = true end
      tier.proJoinBtn.Text = 'PLAY PRO ▶'
      tier.proJoinBtn.BackgroundColor3 = palette.gold
      tier.proJoinBtn.TextColor3 = palette.ink
    end
  end

  if tier.masterJoinBtn then
    local mGrad = tier.masterJoinBtn:FindFirstChild('Gradient')
    if coins < 100000 then
      if mGrad then mGrad.Enabled = false end
      tier.masterJoinBtn.Text = '🔒 LOCKED'
      tier.masterJoinBtn.BackgroundColor3 = palette.panelLight
      tier.masterJoinBtn.TextColor3 = palette.white
    else
      if mGrad then mGrad.Enabled = true end
      tier.masterJoinBtn.Text = 'PLAY MASTER ▶'
      tier.masterJoinBtn.BackgroundColor3 = palette.gold
      tier.masterJoinBtn.TextColor3 = palette.ink
    end
  end

  if C.setupPlayerCount == 4 then
    tier.title.Text = 'CLASSIC TRACTOR (4 PLAYERS · 2 DECKS)'
  elseif C.setupPlayerCount == 6 then
    tier.title.Text = '3-DECK TEAM (6 PLAYERS · 3 DECKS)'
  elseif C.setupPlayerCount == 8 then
    tier.title.Text = '4-DECK EPIC (8 PLAYERS · 4 DECKS)'
  else
    tier.title.Text = '5-DECK MEGA (10 PLAYERS · 5 DECKS)'
  end
  for count, tab in pairs(tier.tabs) do
    local isSel = C.setupPlayerCount == count
    local tGrad = tab:FindFirstChild('Gradient')
    if tGrad then tGrad.Enabled = isSel end
    tab.BackgroundColor3 = isSel and palette.gold or palette.panelLight
    tab.TextColor3 = isSel and palette.ink or palette.white
  end
  if C.renderShopItems then C.renderShopItems() end
  local current = C.state.game
  destroyChildren(optionsFrame)
  destroyChildren(playLayer)
  optionsFrame.Visible = current ~= nil and (current.phase == 'declaration' or (current.phase == 'chaodi' and current.chaodiTurn == 1))
  C.updateAction()
  if not current then return end

  -- Equipped Felt styling
  local equippedFelt = (C.state.equipped and C.state.equipped.felt) or 'felt_emerald'
  local theme = feltThemes[equippedFelt] or feltThemes.felt_emerald
  arenaGradient.Color = ColorSequence.new(theme.top, theme.bottom)
  if arenaUI.arenaStroke then arenaUI.arenaStroke.Color = theme.railOuter end
  if arenaUI.innerRailStroke then arenaUI.innerRailStroke.Color = theme.railInner end

  -- Update Kuaile Shengji Matchup Placard
  if current.trump then
    trumpSuit.Text = (symbols[current.trump.suit] or '★') .. ' ' .. current.trump.level
    trumpSuit.TextColor3 = (current.trump.suit == 'hearts' or current.trump.suit == 'diamonds') and palette.red or palette.goldBright
  end
  local aIsAttacking = current.attackingTeam == 'A'
  local stake = current.chaodiMultiplier or 1
  arenaUI.stakeVal.Text = '×' .. stake
  arenaUI.stakeVal.TextColor3 = stake > 1 and palette.goldBright or palette.white
  arenaUI.stakeOutline.Color = stake > 1 and palette.gold or palette.panelBorder
  arenaUI.stakeOutline.Thickness = stake > 1 and 2 or 1

  -- Update Kuaile Shengji Defender Score Progress Meter & Unified Goal Box
  local oppPoints = current.defenderScore or 0
  local threshold = (current.playerCount or 4) * 20
  local smallThreshold = threshold / 2
  local scoreFraction = oppPoints .. ' / ' .. threshold
  meterVal.Text = scoreFraction
  if arenaUI.goalVal then arenaUI.goalVal.Text = scoreFraction end
  if arenaUI.goalTitle then
    if arenaUI.stakeInTitle and stake > 1 then
      arenaUI.goalTitle.Text = (aIsAttacking and 'OPP PTS' or 'OUR PTS') .. ' · STAKE ×' .. stake
    else
      arenaUI.goalTitle.Text = aIsAttacking and 'OPPONENT POINTS' or 'YOUR TEAM POINTS'
    end
  end
  local pct = safeClamp(oppPoints / threshold, 0, 1)
  meterBarFill.Size = UDim2.fromScale(pct, 1)
  if arenaUI.goalBarFill then arenaUI.goalBarFill.Size = UDim2.fromScale(pct, 1) end

  local statusText, statusCol, gradSeq
  if oppPoints == 0 then
    statusText = 'TOTAL SHUTOUT (+3 LV)'
    statusCol = palette.goldBright
    gradSeq = ColorSequence.new(color(45, 180, 90), color(20, 110, 50))
  elseif oppPoints < smallThreshold then
    statusText = 'SMALL SHUTOUT (+2 LV)'
    statusCol = palette.sage
    gradSeq = ColorSequence.new(color(55, 195, 115), color(35, 130, 75))
  elseif oppPoints < threshold then
    statusText = 'ATTACKERS ADVANCE (+1 LV)'
    statusCol = palette.gold
    gradSeq = ColorSequence.new(color(225, 175, 45), color(165, 115, 20))
  else
    -- Past the line, every further interval raises the payout step.
    local grade = arenaUI.Scoring.payoutGrade('defenders', oppPoints, current.playerCount or 4)
    statusText = 'OVERTURN ×' .. grade .. ' · NEXT AT ' .. math.floor(threshold + grade * smallThreshold)
    statusCol = palette.red
    gradSeq = ColorSequence.new(color(230, 60, 50), color(160, 30, 25))
  end

  if not aIsAttacking then
    -- Your team is collecting points here, so more points is good news.
    if oppPoints >= threshold then
      statusCol = palette.green
      gradSeq = ColorSequence.new(color(55, 195, 115), color(35, 130, 75))
    elseif oppPoints < smallThreshold then
      statusCol = palette.red
      gradSeq = ColorSequence.new(color(230, 60, 50), color(160, 30, 25))
    end
  end
  meterStatus.Text = statusText
  meterStatus.TextColor3 = statusCol
  if arenaUI.goalStatus then
    arenaUI.goalStatus.Text = statusText
    arenaUI.goalStatus.TextColor3 = statusCol
  end
  if arenaUI.meterBarFillGrad then arenaUI.meterBarFillGrad.Color = gradSeq end
  if arenaUI.goalBarFillGrad then arenaUI.goalBarFillGrad.Color = gradSeq end

  local revealed, isDealing, dealtCount = getRevealedCards(current)
  local aw, ah = arena.Size.X.Offset, arena.Size.Y.Offset

  if isDealing then
    notice.Text = 'Cards dealing…'
  else
    -- Whose turn it is already shows in the phase line, so only coach on yours.
    local turnText = current.turn == 1 and 'Your turn. Follow the led suit; level cards and jokers are trump.' or ''
    notice.Text = C.state.message or (current.phase == 'declaration' and 'Declare trump with your level cards.' or (current.phase == 'kitty' and ('Choose ' .. current.kittySize .. ' cards for the kitty.') or turnText))
  end

  -- Center Dealing Deck visual on table during dealing
  centerDeck.Visible = isDealing and not home.view.Visible
  if isDealing then
    C.centerDeckText.Text = 'DEALING…'
    destroyChildren(arenaUI.centerDeckCards)
    local deckW, deckH = 46, 64
    rect(centerDeck, (aw - deckW) / 2, ah * 0.44 - deckH / 2, deckW, deckH + 20)
    local equippedCardBack = (C.state.equipped and C.state.equipped.cardBack) or 'cardback_classic'
    for layer = 1, 3 do
      local offset = (layer - 1) * 2
      local back = renderCardBack(arenaUI.centerDeckCards, deckW, deckH, equippedCardBack)
      rect(back, offset, -offset, deckW, deckH)
    end
    rect(arenaUI.centerDeckBadge, -18, deckH + 4, deckW + 36, 18)
  end

  if current.done then
    local result = current.settlement
    local advancing = result.outcome.advancingRole == 'attackers' and current.attackingTeam or (current.attackingTeam == 'A' and 'B' or 'A')
    local userWon = advancing == 'A'
    -- Layout shows the modal before Render runs, so track the sound with its own flag.
    if not C.settleSoundPlayed then
      C.settleSoundPlayed = true
      playSound(userWon and 'win' or 'defeat')
    end
    if userWon then
      settleUI.banner.BackgroundColor3 = palette.goldDark
      local bannerGradient = settleUI.banner:FindFirstChild('Gradient') or gradient(settleUI.banner, palette.goldBright, palette.goldDark, 90)
      bannerGradient.Color = ColorSequence.new(palette.goldBright, palette.goldDark)
      settleUI.bannerText.Text = result.winner == 'A' and '🏆 MATCH VICTORY!' or '🎉 ROUND WON'
      settleUI.bannerText.TextColor3 = palette.ink
    else
      settleUI.banner.BackgroundColor3 = color(140, 24, 28)
      local bannerGradient = settleUI.banner:FindFirstChild('Gradient') or gradient(settleUI.banner, color(180, 40, 45), color(90, 15, 20), 90)
      bannerGradient.Color = ColorSequence.new(color(180, 40, 45), color(90, 15, 20))
      settleUI.bannerText.Text = result.winner == 'B' and 'MATCH LOST' or (current.attackingTeam == 'A' and 'OVERTURNED' or 'ROUND LOST')
      settleUI.bannerText.TextColor3 = palette.white
    end
    local levelWord = result.outcome.levels == 1 and ' level' or ' levels'
    settleUI.levelTitle.Text = (advancing == 'A' and 'Your team' or 'Opponents') .. ' +' .. result.outcome.levels .. levelWord
      .. '   ·   You ' .. result.levels.A .. '  ·  Them ' .. result.levels.B
    -- In a full match an undecided round continues; otherwise start fresh.
    local continuing = not current.quickMatch and not result.winner
    settleUI.playAgain.Text = continuing and ('▶ NEXT ROUND (' .. (current.round + 1) .. ')') or '▶ PLAY AGAIN'
    if not current.quickMatch then
      settleUI.levelTitle.Text = settleUI.levelTitle.Text .. (result.winner and '' or '   ·   first past A wins')
    end
    settleUI.scoreA.Text = 'Defender points  ' .. result.defenderScore .. '      Kitty  ' .. result.kittyBasePoints .. ' × ' .. result.kittyMultiplier
    settleUI.scoreB.Text = (current.penaltyPoints > 0 and ('Penalty ' .. current.penaltyPoints .. '   ·   ') or '') .. (result.jackReset and 'Jack reset!   ·   ' or '') .. (result.rolesSwapped and 'Dealers swap' or 'Dealers stay')

    local netCoins = result.netCoins or result.earnedCoins or (userWon and 1000 or -500)
    local baseStake = result.baseStake or ((current.tier == 'master' and 5000) or (current.tier == 'pro' and 1500) or 500)
    local totalMult = result.totalMultiplier or 1
    local gradeName = result.gradeName or (userWon and 'Victory' or 'Defeat')
    local kittyFactor = result.kittyFactor or 1
    local chaodiFactor = result.chaodiFactor or 1
    local relief = result.reliefCoins or 0
    local capDesc = ''
    if result.winLossCap and result.winLossCap < baseStake * totalMult then
      capDesc = result.cappedByWallet and (' (capped at your ' .. formatK(result.winLossCap) .. ')') or (' (Cap ' .. formatK(result.winLossCap) .. ')')
    end

    -- Everything this round paid: result payout, captured-point coins, match bonus.
    local roundTotal = netCoins + (result.trickCoins or 0) + (result.matchBonus or 0)
    if userWon then
      settleUI.coinTotal.Text = '+' .. formatK(math.max(0, roundTotal)) .. ' coins'
      settleUI.coinTotal.TextColor3 = palette.goldBright
      local multDesc = totalMult .. 'x (' .. gradeName .. (kittyFactor > 1 and (' · ' .. kittyFactor .. 'x 抠底') or '') .. (chaodiFactor > 1 and (' · ' .. chaodiFactor .. 'x 炒底') or '') .. ')'
      local taxDesc = (result.tax and result.tax > 0) and (' · Fee: -' .. formatK(result.tax)) or ''
      settleUI.coinSub.Text = 'Table ' .. formatK(baseStake) .. ' × ' .. multDesc .. capDesc .. '\n'
        .. ((result.trickCoins or 0) > 0 and ('Points +' .. formatK(result.trickCoins)) or '')
        .. ((result.tax and result.tax > 0) and ('   ·   Fee −' .. formatK(result.tax)) or '')
        .. ((result.matchBonus or 0) > 0 and ('   ·   Match bonus +' .. formatK(result.matchBonus)) or '')
    else
      settleUI.coinTotal.Text = (roundTotal >= 0 and '+' or '−') .. formatK(math.abs(roundTotal)) .. ' coins'
      settleUI.coinTotal.TextColor3 = color(255, 120, 120)
      local multDesc = totalMult .. 'x (' .. gradeName .. (kittyFactor > 1 and (' · ' .. kittyFactor .. 'x 抠底') or '') .. (chaodiFactor > 1 and (' · ' .. chaodiFactor .. 'x 炒底') or '') .. ')'
      local reliefDesc = (relief > 0) and ('  ·  Relief: +' .. formatK(relief)) or ''
      settleUI.coinSub.Text = 'Table ' .. formatK(baseStake) .. ' × ' .. multDesc .. capDesc .. '\n'
        .. ((result.trickCoins or 0) > 0 and ('Points +' .. formatK(result.trickCoins)) or '') .. reliefDesc
    end
    -- Ranked ladder change for this round, when the server sent one.
    if result.rankPoints then
      local change = result.rankDelta or 0
      local sign = change > 0 and '+' or (change < 0 and '−' or '±')
      local sub = settleUI.coinSub.Text
      settleUI.coinSub.Text = sub .. (sub:sub(-1) == '\n' and '' or '   ·   ')
        .. 'Rank ' .. sign .. math.abs(change) .. ' (' .. tostring(result.rankTier or 'Bronze') .. ' ' .. result.rankPoints .. ' RP)'
    end
  end

  if current.phase == 'trick-review' then notice.Text = (current.lastWinnerSeat == 1 and 'You' or arenaUI.playerTag(current.lastWinnerSeat, current.playerCount)) .. ' won. Review the cards, then continue.' end
  if current.error then notice.Text = current.error end

  score.Text = 'ROUND ' .. current.round .. ' · A: ' .. current.levels.A .. ' / B: ' .. current.levels.B .. ' · ' .. current.attackingTeam .. ' attacking'
  trump.Text = current.phase == 'declaration' and 'TRUMP  —' or ('TRUMP  ' .. current.trump.level .. ' ' .. (symbols[current.trump.suit] or '★'))
  local isYourTurn = current.phase == 'tricks' and current.turn == 1
  if isYourTurn and not C.lastTurnWasSelf then
    playSound('turn_chime')
  end
  C.lastTurnWasSelf = isYourTurn
  if not current.done then C.settleSoundPlayed = false end
  -- Other players' cards land with a softer snap (your own play already makes one).
  local trickCount = current.trick and #current.trick or 0
  local lastPlay = current.trick and current.trick[trickCount]
  if C.lastTrickCount and trickCount > C.lastTrickCount and lastPlay and lastPlay.seat ~= 1 then
    playSound('card_play', true, 0.7)
  end
  C.lastTrickCount = trickCount
  local selfWinning = current.phase == 'tricks' and #current.trick > 0 and current.winnerSeat == 1
  selfName.Text = (isYourTurn and '▶ ' or '') .. 'YOU · TEAM BLUE' .. (current.dealer == 1 and ' · [DEALER]' or '') .. (selfWinning and ' · ★ WINNING' or '')
  selfName.TextColor3 = (isYourTurn or selfWinning) and palette.goldBright or palette.teamBlue
  if arenaUI.selfAvatarRing then
    arenaUI.selfAvatarRing.Color = isYourTurn and palette.goldBright or palette.teamBlue
    arenaUI.selfAvatarRing.Thickness = isYourTurn and 4.0 or 2.5
  end
  if arenaUI.selfAvatarScale and C.TweenService then
    C.TweenService:Create(arenaUI.selfAvatarScale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
      Scale = isYourTurn and 1.08 or 1.0
    }):Play()
  end
  selfDealerSeal.Visible = current.dealer == 1

  for seat = 2, 10 do
    local s = seats[seat]
    if current.botCoins and current.botCoins[seat] then
      s.count.Visible = true
      s.count.Text = formatK(current.botCoins[seat]) .. ' COINS'
    else
      s.count.Visible = false
    end
    local isTurn = current.phase == 'tricks' and current.turn == seat
    local isChaodiTurn = current.phase == 'chaodi' and current.chaodiTurn == seat
    local isDeclarant = current.declaration and tonumber(current.declaration.seat) == seat
    local isTrickLeader = current.phase == 'tricks' and #current.trick > 0 and current.winnerSeat == seat
    local teamCol = (seat % 2 == 1) and palette.teamBlue or palette.teamRed
    if isChaodiTurn then
      s.details.Text = 'CHAO DI TURN…'
      s.details.TextColor3 = palette.goldBright
      s.ring.Color = palette.goldBright
      s.ring.Thickness = 4.0
      if s.scale and C.TweenService then
        C.TweenService:Create(s.scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.08 }):Play()
      end
      if s.cardBgStroke then s.cardBgStroke.Color = palette.goldBright; s.cardBgStroke.Thickness = 2.0 end
    elseif isTurn then
      s.details.Text = '● THINKING…'
      s.details.TextColor3 = palette.goldBright
      s.ring.Color = palette.goldBright
      s.ring.Thickness = 4.0
      if s.scale and C.TweenService then
        C.TweenService:Create(s.scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.06 }):Play()
      end
      if s.cardBgStroke then s.cardBgStroke.Color = palette.goldBright; s.cardBgStroke.Thickness = 2.0 end
    elseif isTrickLeader then
      s.details.Text = '★ WINNING TRICK'
      s.details.TextColor3 = palette.gold
      s.ring.Color = palette.gold
      s.ring.Thickness = 3.5
      if s.scale and C.TweenService then
        C.TweenService:Create(s.scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
      end
      if s.cardBgStroke then s.cardBgStroke.Color = palette.gold; s.cardBgStroke.Thickness = 2.0 end
    elseif isDeclarant and (current.phase == 'declaration' or current.phase == 'kitty' or current.phase == 'chaodi') then
      local decl = current.declaration
      local countStr = decl.count == 2 and 'PAIR ×2' or 'SINGLE ×1'
      if decl.joker then countStr = 'JOKERS ×' .. decl.count end
      s.details.Text = (symbols[decl.suit] or '★') .. ' ' .. current.trump.level .. ' · ' .. countStr
      s.details.TextColor3 = suitColors[decl.suit] or palette.goldBright
      s.ring.Color = suitColors[decl.suit] or teamCol
      s.ring.Thickness = 3.0
      if s.cardBgStroke then s.cardBgStroke.Color = palette.panelBorder; s.cardBgStroke.Thickness = 1 end
    else
      local dealerLabel = current.dealer == seat and '[DEALER]' or nil
      s.details.Text = dealerLabel or s.titleText or ((seat == 3 and current.playerCount == 4) and 'TEAM BLUE (PARTNER)' or (seat % 2 == 1 and 'TEAM BLUE' or 'OPPONENT'))
      s.details.TextColor3 = (not dealerLabel and s.titleColor) or teamCol
      s.ring.Color = teamCol
      s.ring.Thickness = 2.5
      if s.scale and C.TweenService then
        C.TweenService:Create(s.scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
      end
      if s.cardBgStroke then s.cardBgStroke.Color = palette.panelBorder; s.cardBgStroke.Thickness = 1 end
    end
    if s.dealerSeal then s.dealerSeal.Visible = current.dealer == seat end
    local remaining = current.counts and current.counts[seat]
    s.handBadge.Visible = remaining ~= nil and current.phase ~= 'declaration'
    if remaining then s.handCountText.Text = tostring(remaining) end

    -- Show the declared level cards above the declarer's profile.  The
    -- projected state intentionally exposes only the count/suit, so these are
    -- lightweight card tiles rather than private hand cards.
    local settingTrump = current.phase == 'declaration' or current.phase == 'kitty' or current.phase == 'chaodi'
    local showDeclaration = settingTrump and current.declaration and (isDeclarant or string.find(s.details.Text, '×') ~= nil)
    renderDeclarationCards(s.declarationCards, current.declaration, current, showDeclaration == true)
  end

  local selfSettingTrump = current.phase == 'declaration' or current.phase == 'kitty' or current.phase == 'chaodi'
  renderDeclarationCards(selfDeclarationCards, current.declaration, current, selfSettingTrump and current.declaration and current.declaration.seat == 1)

  local optionWidth = C.currentLayout.compact and 124 or 156
  local optionSource = current.phase == 'chaodi' and current.chaodiOptions or current.options
  local availableOptions = {}
  for i, option in ipairs(optionSource or {}) do
    local allPresent = true
    if current.phase == 'declaration' then
      for _, id in ipairs(option.cardIds) do
        local hasCard = false
        for _, c in ipairs(revealed) do
          if c.id == id then hasCard = true; break end
        end
        if not hasCard then allPresent = false; break end
      end
    end
    if allPresent then
      table.insert(availableOptions, { index = i, option = option })
    end
  end

  if current.phase == 'declaration' then
    -- Tencent-style declaration strip: the two joker choices sit above the
    -- four suit choices. Each section stays lit while it has a legal next
    -- declaration; pressing the same section again upgrades its count.
    local suitOrder = { 'spades', 'hearts', 'clubs', 'diamonds' }
    local jokerOrder = { 'small', 'big' }
    local candidates = {}
    for _, entry in ipairs(availableOptions) do
      local key = entry.option.joker or entry.option.suit
      if key then
        candidates[key] = candidates[key] or {}
        table.insert(candidates[key], entry)
      end
    end
    local stripW = C.currentLayout.compact and 54 or 64
    local stripGap = C.currentLayout.compact and 4 or 6
    local suitTotal = #suitOrder * stripW + (#suitOrder - 1) * stripGap
    local jokerW = C.currentLayout.compact and 108 or 128
    local jokerTotal = #jokerOrder * jokerW + stripGap
    local startX = math.max(0, (C.currentLayout.width - 32 - suitTotal) / 2)
    local jokerStartX = math.max(0, (C.currentLayout.width - 32 - jokerTotal) / 2)
    local currentDecl = current.declaration

    local function nextCandidate(key)
      local entries = candidates[key] or {}
      local target
      for _, entry in ipairs(entries) do
        local option = entry.option
        local legal = true
        if currentDecl then
          -- Mirrors the server: more cards win; at the same size jokers beat a suit, big beats small.
          local held = currentDecl.count or 0
          if option.count ~= held then
            legal = option.count > held
          elseif currentDecl.suit then
            legal = not option.suit
          else
            legal = currentDecl.joker == 'small' and option.joker == 'big'
          end
        end
        if legal and (not target or option.count < target.option.count) then target = entry end
      end
      return target
    end

    for index, joker in ipairs(jokerOrder) do
      local target = nextCandidate(joker)
      local enabled = target ~= nil
      local text = joker == 'small' and 'SMALL JOKER' or 'BIG JOKER'
      if target then text = text .. '  ' .. tostring(target.option.count) end
      local control = button(optionsFrame, 'DeclareJoker' .. joker, text, function()
        if target then command('declare', target.index) end
      end, enabled and palette.gold or palette.panelLight)
      control.ZIndex = 41
      control.TextColor3 = enabled and (joker == 'big' and palette.red or palette.ink) or palette.muted
      control.AutoButtonColor = enabled
      control.Active = enabled
      if enabled then
        outline(control, palette.goldBright, 1)
      else
        outline(control, palette.panelBorder, 1)
      end
      rect(control, jokerStartX + (index - 1) * (jokerW + stripGap), 0, jokerW, 30)
    end

    for index, suit in ipairs(suitOrder) do
      local target = nextCandidate(suit)
      local enabled = target ~= nil
      local text = symbols[suit] or '?'
      if target then text = text .. '  ' .. tostring(target.option.count) end
      local control = button(optionsFrame, 'DeclareSuit' .. suit, text, function()
        if target then command('declare', target.index) end
      end, enabled and palette.gold or palette.panelLight)
      control.ZIndex = 41
      control.TextColor3 = enabled and (suitColors[suit] or palette.ink) or palette.muted
      control.AutoButtonColor = enabled
      control.Active = enabled
      outline(control, enabled and palette.goldBright or palette.panelBorder, 1)
      rect(control, startX + (index - 1) * (stripW + stripGap), 38, stripW, 30)
    end
    optionsFrame.CanvasSize = UDim2.fromOffset(math.max(suitTotal, C.currentLayout.width - 32), 70)
  else
    local total = #availableOptions * (optionWidth + 8)
    for i, entry in ipairs(availableOptions) do
      local optIdx = entry.index
      local option = entry.option
      local text = option.suit and (option.count .. ' × ' .. current.trump.level .. ' ' .. (symbols[option.suit] or '')) or (option.count .. ' JOKERS ★')
      text = 'CHAO DI  ' .. text .. '  · ×' .. ((current.chaodiMultiplier or 1) * 2)
      local control = button(optionsFrame, 'ChaoDi' .. optIdx, text, function()
        C.selectedChaodiIndex = optIdx
        C.render()
      end, palette.panelLight)
      if C.selectedChaodiIndex == optIdx then
        control.BackgroundColor3 = palette.gold
        control.TextColor3 = palette.ink
      end
      rect(control, math.max(0, (C.currentLayout.width - 32 - total) / 2) + (i - 1) * (optionWidth + 8), 0, optionWidth, 36)
    end
    optionsFrame.CanvasSize = UDim2.fromOffset(math.max(total, C.currentLayout.width - 32), 0)
  end

  local canPeek = current.phase == 'tricks' and #current.trick > 0 and #(current.lastTrick or {}) > 0
  if not canPeek then arenaUI.peekLast = false end
  local live = #current.trick > 0 and not arenaUI.peekLast
  local trick = live and current.trick or current.lastTrick
  arenaUI.peekButton.Visible = canPeek and not home.view.Visible and not settleUI.modal.Visible
  arenaUI.peekButton.Text = arenaUI.peekLast and 'CURRENT TRICK ▶' or '◀ LAST TRICK'
  local aw, ah = arena.Size.X.Offset, arena.Size.Y.Offset
  local multiSeat = current.playerCount > 4
  local portrait = aw < ah
  -- 4-player tables stack the partner's play above yours, so both plays and
  -- their tags must fit between the partner panel (~40px) and the trick label.
  local cardHeight = C.currentLayout.short and 44 or (multiSeat and safeClamp(math.floor(math.min(ah * 0.13, aw * 0.1)), 36, 64) or safeClamp(math.floor(math.min(ah * 0.28, aw * 0.17, (ah - 132) / 2)), 36, 90))
  local cardWidth = math.floor(cardHeight * 0.66)

  -- Non-overlapping diamond trick layout with ample breathing room
  local locations = {
    {0.50, 0.67}, -- Seat 1: South (Player)
    {0.68, 0.48}, -- Seat 2: East (Opponent)
    {0.50, 0.32}, -- Seat 3: North (Partner)
    {0.32, 0.48}, -- Seat 4: West (Opponent)
  }
  if C.currentLayout.short then
    locations = { {0.42, 0.5}, {0.72, 0.5}, {0.58, 0.5}, {0.28, 0.5} }
  elseif portrait then
    -- Narrow tables: stretch the diamond vertically so side plays clear the
    -- seat panels and the partner's play.
    locations = { {0.5, 0.74}, {0.64, 0.5}, {0.5, 0.27}, {0.36, 0.5} }
  end
  if not C.currentLayout.short and not multiSeat and ah > 0 then
    local topCenter = math.max(66 + cardHeight / 2, locations[3][2] * ah)
    local bottomCenter = math.min(ah - 32 - cardHeight / 2, math.max(locations[1][2] * ah, topCenter + cardHeight + 34))
    local middle = (topCenter + bottomCenter) / 2 / ah
    locations = { {locations[1][1], bottomCenter / ah}, {locations[2][1], middle}, {locations[3][1], topCenter / ah}, {locations[4][1], middle} }
  end

  local winner
  local trickPoints = 0
  local winningSeat = live and current.winnerSeat or current.lastWinnerSeat
  for _, play in ipairs(trick) do
    if play.seat == winningSeat then winner = play end
    for _, card in ipairs(play.cards) do trickPoints = trickPoints + Cards.points(card) end
    for _, comp in ipairs(play.components or {}) do
      if comp.rankCount and comp.rankCount > 1 and comp.multiplicity and comp.multiplicity >= 2 then
        local tText = (comp.multiplicity == 3 and 'TRIPLE TRACTOR!' or 'TRACTOR COMBO!') .. (play.seat == 1 and ' (YOU!)' or (play.seat % 2 == 1 and ' (PARTNER!)' or ''))
        if live then task.spawn(function() triggerTractorBanner(current.tricks, tText) end) end
      end
    end
  end
  for _, play in ipairs(trick) do
    local position = locations[play.seat]
    local tagBelow = C.currentLayout.short
    if multiSeat then
      local angle = math.pi/2 - (play.seat-1)*2*math.pi/current.playerCount
      -- Neighbouring seats on the left/right edges differ vertically by
      -- 2·sin(π/n) of the radius; keep that gap larger than a play + its tag.
      local needY = (cardHeight + 36) / (2 * math.sin(math.pi / current.playerCount))
      local ry = math.min(ah / 2 - 8, math.max((portrait and 0.27 or 0.29) * ah, needY))
      local rx = (portrait and 0.28 or 0.3) * aw
      position = {0.5 + rx / aw * math.cos(angle), 0.5 + ry / ah * math.sin(angle)}
      -- Tags sit on the outer side so neighbouring plays never collide, except
      -- straight up where the seat panel would cover them.
      tagBelow = math.sin(angle) > 0 or math.sin(angle) < -0.9
    end
    -- Fan played cards wide enough that each rank/suit corner stays readable.
    local fan = math.max(18, math.floor(cardWidth * 0.52))
    local groupWidth = math.min(aw * (current.playerCount > 4 and 0.2 or 0.3), cardWidth+(#play.cards-1)*fan)
    local step = #play.cards > 1 and math.max(5,(groupWidth-cardWidth)/(#play.cards-1)) or 0
    local groupX, groupY = aw * position[1] - groupWidth / 2, ah * position[2] - cardHeight / 2
    -- In compact layouts the partner panel overlaps the arena's top 34px.
    if C.currentLayout.short then groupY = math.max(groupY, 38) end
    local isWinner = winner == play
    local isTeammate = play.seat % 2 == 1
    local teamCol = isTeammate and palette.teamBlue or palette.teamRed

    -- Team-coloured plate behind each play plus a name tag, so every play is
    -- attributable even when seats are far away or cramped into one row.
    local plate = frame(playLayer, 'PlayPlate' .. play.seat, isWinner and palette.goldDark or palette.emeraldDark, 8)
    plate.BackgroundTransparency = isWinner and 0.45 or 0.6
    plate.ZIndex = 11
    outline(plate, isWinner and palette.goldBright or teamCol, isWinner and 3 or 1.5)
    rect(plate, groupX - 5, groupY - 5, groupWidth + 10, cardHeight + 10)

    local smallTag = C.currentLayout.short or (portrait and multiSeat)
    local tagHeight = smallTag and 14 or 18
    local tagWidth = math.max(groupWidth + 10, smallTag and 60 or 96)
    local tag = label(playLayer, 'PlayTag' .. play.seat, arenaUI.playerTag(play.seat, current.playerCount), smallTag and 9 or 11, isWinner and palette.ink or palette.white)
    tag.BackgroundTransparency = 0
    tag.BackgroundColor3 = isWinner and palette.gold or teamCol
    tag.TextWrapped = false
    tag.ZIndex = 20
    corner(tag, 6)
    if isWinner then
      tag.Text = '★ ' .. tag.Text .. ((portrait and multiSeat) and '' or (live and ' · WINNING' or ' · WON'))
      tag.Font = Enum.Font.GothamBlack
      outline(tag, palette.goldBright, 1.5)
    elseif trick[1] == play then
      tag.Text = tag.Text .. ' · LED'
    end
    -- Compact layouts have seat panels over the top edge, so tag below instead.
    tagWidth = math.max(tagWidth, #tag.Text * tag.TextSize * 0.62 + 14)
    local tagY = tagBelow and (groupY + cardHeight + 6) or (groupY - 5 - tagHeight - 2)
    rect(tag, aw * position[1] - tagWidth / 2, tagY, tagWidth, tagHeight)

    local group = make('ScrollingFrame', playLayer, 'Play' .. play.seat, {
      BackgroundTransparency = 1,
      BorderSizePixel = 0,
      ScrollBarThickness = 2,
      ScrollingDirection = Enum.ScrollingDirection.X,
      CanvasSize = UDim2.fromOffset(cardWidth + math.min(fan, math.max(18, step)) * (#play.cards - 1), 0),
      ZIndex = 12,
    })
    rect(group, groupX, groupY, groupWidth, cardHeight + 18)
    for index, card in ipairs(play.cards) do
      local object, stroke = cardFace(group, card, 'Played_' .. card.id, cardWidth, cardHeight)
      rect(object, (index - 1) * math.min(fan, math.max(18, step)), 0, cardWidth, cardHeight)
      object.ZIndex = 12 + index
      if isWinner then stroke.Color = palette.gold; stroke.Thickness = 3 end
    end

    -- Seat panels draw above the table, so slide any play (cards + tag) that
    -- would sit under one toward the table centre until it is fully visible.
    local tagY = tag.Position.Y.Offset
    local tagX = tag.Position.X.Offset
    local box = { math.min(groupX - 5, tagX), math.min(groupY - 5, tagY), math.max(groupX + groupWidth + 5, tagX + tagWidth), math.max(groupY + cardHeight + 5, tagY + tagHeight) }
    local ox, oy = arena.Position.X.Offset, arena.Position.Y.Offset
    local dx, dy = 0, 0
    for _ = 1, 40 do
      -- Compact landscape rows are already placed below the partner panel.
      if C.currentLayout.short then break end
      local blocked = box[4] + dy > ah - 26 and box[1] + dx < aw * 0.8 and box[3] + dx > aw * 0.2
      for other = 2, current.playerCount do
        if blocked then break end
        local holder = seats[other] and seats[other].holder
        if holder and holder.Visible and holder.Position and holder.Size then
          local hx, hy = holder.Position.X.Offset - ox, holder.Position.Y.Offset - oy
          local hw, hh = holder.Size.X.Offset, holder.Size.Y.Offset
          if box[1] + dx < hx + hw and box[3] + dx > hx and box[2] + dy < hy + hh and box[4] + dy > hy then
            blocked = true
          end
        end
      end
      if not blocked then break end
      local cx, cy = (box[1] + box[3]) / 2 + dx, (box[2] + box[4]) / 2 + dy
      local vx, vy = aw / 2 - cx, ah / 2 - cy
      local len = math.sqrt(vx * vx + vy * vy)
      if len < 4 then break end
      dx, dy = dx + vx / len * 4, dy + vy / len * 4
    end
    if dx ~= 0 or dy ~= 0 then
      for _, object in ipairs({ plate, tag, group }) do
        object.Position = UDim2.fromOffset(object.Position.X.Offset + dx, object.Position.Y.Offset + dy)
      end
    end

    -- New plays slide in from the player's seat so it is clear who played them.
    local playKey = current.round .. ':' .. current.tricks .. ':' .. play.seat
    if live and not arenaUI.seenPlays[playKey] then
      arenaUI.seenPlays[playKey] = true
      local fromX, fromY = aw / 2, ah + 40
      local holder = seats[play.seat] and seats[play.seat].holder
      if play.seat ~= 1 and holder and holder.Position and holder.Size then
        fromX = holder.Position.X.Offset - ox + holder.Size.X.Offset / 2
        fromY = holder.Position.Y.Offset - oy + holder.Size.Y.Offset / 2
      end
      local offX = fromX - (groupX + dx + groupWidth / 2)
      local offY = fromY - (groupY + dy + cardHeight / 2)
      local info = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
      for _, object in ipairs({ plate, tag, group }) do
        local target = object.Position
        object.Position = UDim2.fromOffset(target.X.Offset + offX, target.Y.Offset + offY)
        tween(object, info, { Position = target })
      end
    end
  end

  -- When a trick with points completes, pop the points over the winner:
  -- defenders bank them, attackers keep them off the board.
  if winner and not live and not arenaUI.peekLast and trickPoints > 0 and #trick == current.playerCount
    and arenaUI.pointsShownFor ~= current.round .. ':' .. current.tricks then
    arenaUI.pointsShownFor = current.round .. ':' .. current.tricks
    local winnerTag = playLayer:FindFirstChild('PlayTag' .. winner.seat)
    local defenders = Cards.team(winner.seat) ~= current.attackingTeam
    local yours = winner.seat % 2 == 1
    local popup = label(arena, 'PointsPopup', defenders and ('+' .. trickPoints .. ' PTS') or (trickPoints .. ' PTS SAVED'), C.currentLayout.short and 13 or 18,
      yours and palette.green or palette.red)
    popup.Font = Enum.Font.GothamBlack
    popup.TextStrokeTransparency = 0.2
    popup.TextWrapped = false
    popup.ZIndex = 40
    local px = winnerTag and winnerTag.Position.X.Offset + winnerTag.Size.X.Offset / 2 or aw / 2
    local py = winnerTag and winnerTag.Position.Y.Offset - 4 or ah / 2
    rect(popup, px - 70, py - 24, 140, 24)
    tween(popup, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(px - 70, py - 56), TextTransparency = 1, TextStrokeTransparency = 1 })
    task.delay(1.5, function() if popup.Parent then popup:Destroy() end end)
  end

  -- Trigger point capture animation on completed tricks with points
  if #trick == current.playerCount and trickPoints > 0 and winner then
  end

  -- Autonomous Partner / Opponent reaction on key trick events
  if #trick == current.playerCount and winner and (trickPoints >= 15 or winner.seat % 2 == 1) then
    task.delay(0.8, function()
      if not C.state or not C.state.game or C.state.game.done then return end
      if winner.seat ~= 1 and winner.seat % 2 == 1 then
        local cheers = { 'Brilliant trick, partner!', 'Nice points!', 'Keep it up!' }
        C.triggerEmoteReaction('Partner', cheers[math.random(1, #cheers)])
      elseif winner.seat == 1 and trickPoints >= 10 then
        local cheers = { 'Great follow, partner!', 'Awesome play!', 'Well done!' }
        C.triggerEmoteReaction('Partner', cheers[math.random(1, #cheers)])
      elseif winner.seat % 2 == 0 and trickPoints >= 20 then
        C.triggerEmoteReaction(seats[winner.seat].name.Text, 'We\'ll take those points!')
      end
    end)
  end

  local isTableActive = not home.view.Visible and not tier.view.Visible and current ~= nil
  centerMedallion.Visible = isTableActive and #trick == 0
  if isTableActive and current.trump and current.phase ~= 'declaration' then
    centerTrumpDisplay.Text = (symbols[current.trump.suit] or '★') .. ' ' .. current.trump.level
    centerTrumpDisplay.Visible = true
    arenaUI.centerTag.Text = 'TRUMP SUIT'
    arenaUI.centerTag.Visible = true
    arenaUI.centerSuits.Visible = false
  else
    centerTrumpDisplay.Visible = false
    arenaUI.centerTag.Text = 'TRACTOR'
    arenaUI.centerTag.Visible = true
    arenaUI.centerSuits.Visible = true
  end
  wordmark.Visible = false
  arenaUI.wordmarkSub.Visible = false
  if #trick > 0 then
    -- The per-play tags already name the winner where the table is too short.
    trickLabel.Visible = not home.view.Visible and not settleUI.modal.Visible and not C.currentLayout.short
    local winnerText = winner and (arenaUI.playerTag(winner.seat, current.playerCount) .. (live and ' WINNING' or ' WON')) or nil
    trickLabel.Text = (live and 'CURRENT TRICK' or (arenaUI.peekLast and 'PREVIOUS TRICK' or 'LAST TRICK')) .. (winnerText and ('  ·  ★ ' .. winnerText) or '') .. (trickPoints > 0 and ('  ·  ' .. trickPoints .. ' PTS') or '') .. '  ·  ' .. current.tricks .. ' tricks'
    trickLabel.TextColor3 = winner and palette.goldBright or palette.white
  else
    trickLabel.Visible = false
    trickLabel.Text = ''
  end
end
end
