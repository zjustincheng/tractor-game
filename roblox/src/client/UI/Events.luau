-- Happy Tractor client, part 14/14: Events.
-- Lines 6102-6296 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Players, arenaUI, chatUI, emoteLine, getDealingState, home, notice, palette = C.Players, C.arenaUI, C.chatUI, C.emoteLine, C.getDealingState, C.home, C.notice, C.palette
local phaseLine, playSound, queueUI, recommendCards, remote, rewardsUI, root, seats = C.phaseLine, C.playSound, C.queueUI, C.recommendCards, C.remote, C.rewardsUI, C.root, C.seats
local selectedList, submitSelection, symbols, triggerTractorBanner, walletHint = C.selectedList, C.submitSelection, C.symbols, C.triggerTractorBanner, C.walletHint

remote.OnClientEvent:Connect(function(nextState)
  if nextState.hint then
    C.selectedIds = {}
    for _, id in ipairs(nextState.hint) do C.selectedIds[id] = true end
    C.renderHand()
    C.updateAction()
    return
  end
  if nextState.type == 'leaderboard' then return end -- handled by the Leaderboard module
  if nextState.type == 'profile' then return end -- handled by the Profile module
  if nextState.type == 'invite' then
    playSound('turn_chime')
    return
  end
  if nextState.type == 'emote' or nextState.emote then
    local mine = nextState.senderId ~= nil and Players.LocalPlayer and nextState.senderId == Players.LocalPlayer.UserId
    if not C.muted and not mine then
      local def = nextState.id and arenaUI.emoteDefs[nextState.id]
      local text = (nextState.sender or 'Player') .. '  ·  ' .. ((nextState.kind ~= 'chat' and def and def.name) or nextState.emote or '')
      emoteLine.Text = text
      if nextState.fromSeat then
        arenaUI.react(nextState.fromSeat, nextState.kind == 'emote' and 'emote' or 'chat', nextState.id, nextState.emote, nextState.target)
      elseif nextState.kind == 'emote' and def then
        C.triggerEmoteReaction(nextState.sender, nextState.id, nextState.target)
      else
        C.triggerEmoteReaction(nextState.sender, nextState.emote, nextState.target)
      end
      task.delay(4, function() if emoteLine.Text == text then emoteLine.Text = '' end end)
    end
    return
  end
  local prevTurn = C.state and C.state.game and C.state.game.turn
  local prevStake = C.state and C.state.game and C.state.game.chaodiMultiplier
  local prevPhase = C.state and C.state.game and C.state.game.phase
  local prevRev = C.state and C.state.game and C.state.game.revision
  local prevDoubled = {}
  for _, s in ipairs(C.state and C.state.game and C.state.game.doubledSeats or {}) do prevDoubled[s] = true end

  local isNewHand = not C.state or not C.state.game or not nextState.game
    or (nextState.game.revision < C.state.game.revision)
    or (C.state.game.phase == 'declaration' and nextState.game.phase == 'declaration' and nextState.game.revision == 0)
    or (C.state.game.phase ~= 'declaration' and nextState.game.phase == 'declaration')

  local isNewTurn = isNewHand
    or (C.state and C.state.game and nextState.game and (prevRev ~= nextState.game.revision or prevTurn ~= nextState.game.turn or prevPhase ~= nextState.game.phase))

  if isNewTurn then
    C.selectedIds = {}
    C.selectedChaodiIndex = nil
    arenaUI.peekLast = false
  end
  if isNewHand then
    C.previouslyRenderedCards = {}
    C.lastDealtCount = -1
    arenaUI.seenPlays = {}
    arenaUI.pointsShownFor = nil
  end
  local wasSearching = C.state ~= nil and C.state.search ~= nil
  local wasInGame = C.state ~= nil and C.state.game ~= nil
  C.state, C.busy, C.receivedAt = nextState, false, os.clock()
  if nextState.search and not wasSearching then playSound('whoosh') end -- joined the queue
  if nextState.game and not wasInGame then playSound('tractor') end -- match found
  if not isNewHand and prevStake and nextState.game and (nextState.game.chaodiMultiplier or 1) > prevStake then
    local inDeclaration = nextState.game.phase == 'declaration'
    triggerTractorBanner(nil, (inDeclaration and 'TRUMP CHANGED!  STAKES ×' or 'CHAO DI!  STAKES ×') .. nextState.game.chaodiMultiplier)
    C.say(inDeclaration and 'double' or 'chaodi')
  end
  -- Announce each new Double (yours or another player's).
  if not isNewHand and nextState.game then
    for _, s in ipairs(nextState.game.doubledSeats or {}) do
      if not prevDoubled[s] then
        local who = arenaUI.playerTag(s, nextState.game.playerCount)
        triggerTractorBanner(nil, who .. ' DOUBLED ×2')
        C.say('double')
        break
      end
    end
  end
  if nextState.game and queueUI and queueUI.shade then
    queueUI.shade.Visible = false
  end
  C.updateCoinDisplays(C.state.coins)
  if nextState.table then arenaUI.applySeats(nextState.table) end
  arenaUI.renderSquad()
  arenaUI.renderInvites()
  arenaUI.renderSearch()
  if queueUI.renderTable then queueUI.renderTable(nextState.table) end
  if C.state.game and chatUI.rebuildTargets then
    if chatUI.rebuildTargets(C.state.game.playerCount or 4) and C.resize then C.resize() end
  end
  if arenaUI.refreshDock then arenaUI.refreshDock() end
  if arenaUI.statsShade.Visible then arenaUI.renderStats(nextState.stats) end
  if nextState.saving then
    local saving = nextState.saving.enabled
    home.saveChip.Text = (C.currentLayout and C.currentLayout.width < 600) and '⚠' or '⚠ Not saving'
    home.saveChip.Visible = not saving
    home.saveChip.TextColor3 = saving and palette.green or palette.goldBright
    walletHint.Text = saving and '' or '⚠ NOT SAVING'
    walletHint.TextColor3 = saving and palette.green or palette.gold
    if not saving then
      arenaUI.saveReason.Text = (nextState.saving.reason or 'Saving is unavailable.') .. '\n\nCoins and unlocks from this session will reset when you leave.'
      if not arenaUI.saveWarned then
        arenaUI.saveWarned = true
        arenaUI.saveShade.Visible = true
      end
    end
  end
  if nextState.coinBonus and C.triggerCoinToast then
    C.triggerCoinToast(nextState.coinBonus)
  end
  if C.state.game and C.state.game.done then C.autoPlay=false; C.autoButton.Text='AUTO OFF' end

  if isNewTurn and C.state.game and not C.state.game.done then
    if C.state.game.phase == 'tricks' and C.state.game.turn == 1 then
      playSound('turn_chime')
      recommendCards()
    elseif C.state.game.phase == 'chaodi' and C.state.game.chaodiTurn == 1 then
      playSound('turn_chime')
    end
  end

  C.render()
end)

-- Match the website's keyboard play/clear workflow without intercepting chat.
arenaUI.inputService = game:GetService('UserInputService')
arenaUI.inputService.InputEnded:Connect(function(input)
  if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
    if C.handDragActive then
      C.handDragActive = false
      C.handDragVisited = {}
      C.renderHand()
      C.updateAction()
    end
  end
end)
if arenaUI.inputService and arenaUI.inputService.InputBegan then
  arenaUI.inputService.InputBegan:Connect(function(input, processed)
    if processed or arenaUI.inputService:GetFocusedTextBox() then return end
    if input.KeyCode == Enum.KeyCode.Return then submitSelection()
    elseif input.KeyCode == Enum.KeyCode.H then recommendCards()
    elseif input.KeyCode == Enum.KeyCode.Escape then
      C.historyShade.Visible=false
      if not C.busy then C.selectedIds={}; C.renderHand(); C.updateAction() end
    end
  end)
end
root:GetPropertyChangedSignal('AbsoluteSize'):Connect(function() if C.state then C.render() else C.resize() end end)
C.resize()
remote:FireServer('sync')
task.spawn(function()
  while task.wait(0.08) do
    if arenaUI.searchBar.Visible then arenaUI.renderSearch() end
    if rewardsUI and rewardsUI.shade and rewardsUI.shade.Visible and C.renderRewardsModal then
      C.renderRewardsModal()
    end
    if C.state and C.state.game then
      local current = C.state.game
      if current.done and C.autoPlay then C.autoPlay=false; C.autoButton.Text='AUTO OFF' end
      if C.autoPlay and not C.busy and os.clock()>=C.nextAutoAt then
        C.nextAutoAt=os.clock()+1.2
        if current.phase=='kitty' or (current.phase=='tricks' and current.turn==1) then
          recommendCards(); submitSelection()
        elseif current.phase=='trick-review' then submitSelection() end
      end
      if current.phase == 'declaration' then
        local dealtCount, isDealing = getDealingState()
        if dealtCount ~= C.lastDealtCount then
          C.lastDealtCount = dealtCount
          C.render()
        else
          local remaining = math.max(0, math.ceil(current.deadline - (C.state.serverTime + os.clock() - C.receivedAt)))
          local declaration = current.declaration
          local declarantName = declaration and arenaUI.role(declaration.seat)
          local countStr = ''
          if declaration then
            countStr = declaration.count == 2 and ' (PAIR ×2)' or ' (SINGLE ×1)'
            if declaration.joker then countStr = ' (JOKERS ×' .. declaration.count .. ')' end
          end
          if isDealing then
            notice.Text = 'Cards dealing…'
            phaseLine.Text = (declaration and (declarantName .. ' declared ' .. (symbols[declaration.suit] or '★') .. ' ' .. current.trump.level .. countStr) or ('Cards dealing… Declare level ' .. current.trump.level)) .. '  ·  ' .. remaining .. 's'
          else
            phaseLine.Text = (declaration and (declarantName .. ' declared ' .. (symbols[declaration.suit] or '★') .. ' ' .. current.trump.level .. countStr) or 'Waiting for a declaration') .. '  ·  ' .. remaining .. 's'
          end
        end
      elseif current.phase == 'kitty' then phaseLine.Text = 'BURY ' .. #selectedList() .. ' / ' .. current.kittySize .. ' CARDS'
      elseif current.phase == 'chaodi' then
        local multStr = '×' .. (current.chaodiMultiplier or 1)
        if current.chaodiTurn == 1 then
          local canChao = current.chaodiOptions and #current.chaodiOptions > 0
          phaseLine.Text = 'CHAO DI PHASE (' .. multStr .. ') · YOUR TURN TO ' .. (canChao and 'CHAO DI OR PASS' or 'PASS') .. '!'
        else
          local actorName = arenaUI.role(current.chaodiTurn, true)
          phaseLine.Text = 'CHAO DI PHASE (' .. multStr .. ') · ' .. actorName .. ' IS DECIDING…'
        end
      elseif current.phase == 'doubling' then
        phaseLine.Text = ''
      elseif current.phase == 'trick-review' then phaseLine.Text = 'Trick complete · ' .. arenaUI.playerTag(current.lastWinnerSeat, current.playerCount) .. ' (' .. (current.lastWinnerSeat % 2 == 1 and 'YOUR TEAM' or 'OPPONENTS') .. ') won'
      elseif current.done then
        local tierReward = (current.tier == 'master' and '+8K coins earned') or (current.tier == 'pro' and '+2.5K coins earned') or '+1K coins earned'
        phaseLine.Text = tierReward .. ' · Quick Match complete'
      elseif current.phase == 'tricks' then
        if current.turn == 1 then
          phaseLine.Text = C.busy and 'Playing…' or ('YOUR TURN  ·  SELECT → PLAY' .. arenaUI.countdown(current))
        else
          local thinker = seats[current.turn] and seats[current.turn].human and arenaUI.playerTag(current.turn, current.playerCount) or arenaUI.role(current.turn, true)
          phaseLine.Text = thinker .. ' IS THINKING…' .. arenaUI.countdown(current)
        end
      else phaseLine.Text = '' end
    end
  end
end)

end
