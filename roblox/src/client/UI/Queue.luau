-- Happy Tractor client, part 7/14: Queue.
-- Lines 2943-3167 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Players, arenaUI, button, color, corner, frame, gradient, label = C.Players, C.arenaUI, C.button, C.color, C.corner, C.frame, C.gradient, C.label
local make, notice, outline, palette, queueUI, remote, root = C.make, C.notice, C.outline, C.palette, C.queueUI, C.remote, C.root

function arenaUI.initQueueModal()
  local qShade = button(root, 'QueueShade', '', function() end, palette.emeraldDark)
  qShade.BackgroundTransparency = 0.22
  qShade.Size = UDim2.fromScale(1, 1)
  qShade.Visible = false
  qShade.ZIndex = 55

  local qModal = frame(qShade, 'QueueModal', palette.emeraldDeep, 22)
  outline(qModal, palette.gold, 2)

  local qBanner = frame(qModal, 'Banner', palette.goldDark, 14)
  gradient(qBanner, palette.goldBright, palette.goldDark, 90)
  local qBannerText = label(qBanner, 'Text', 'PREPARING YOUR TABLE', 16, palette.ink)
  qBannerText.Font = Enum.Font.FredokaOne
  qBannerText.Size = UDim2.fromScale(1, 1)

  local qTierLabel = label(qModal, 'TierLabel', 'NOVICE TABLE · BASE 500', 14, palette.goldBright)
  qTierLabel.Font = Enum.Font.FredokaOne

  local qVsBox = frame(qModal, 'VsBox', palette.tileBg, 14)
  outline(qVsBox, palette.panelBorder, 1)

  -- Team A (Left): You + Partner
  local teamABox = frame(qVsBox, 'TeamA', palette.panel, 10)
  outline(teamABox, palette.green, 1.2)
  local teamATitle = label(teamABox, 'Title', 'TEAM A (YOU & PARTNER)', 11, palette.green)
  teamATitle.Font = Enum.Font.GothamBold

  local slot1 = frame(teamABox, 'Slot1', palette.tileBg, 8)
  local s1Img = make('ImageLabel', slot1, 'Img', {
    BackgroundTransparency = 1,
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.fromOffset(6, 6),
    Image = 'rbxthumb://type=AvatarHeadShot&id=' .. tostring((Players.LocalPlayer and Players.LocalPlayer.UserId) or 1) .. '&w=150&h=150',
  })
  corner(s1Img, 999)
  local s1Name = label(slot1, 'Name', (Players.LocalPlayer and Players.LocalPlayer.DisplayName) or 'YOU', 11, palette.cream)
  s1Name.Font = Enum.Font.GothamBold
  s1Name.Position = UDim2.fromOffset(40, 4)
  s1Name.Size = UDim2.new(1, -44, 0, 16)
  s1Name.TextXAlignment = Enum.TextXAlignment.Left
  local s1Role = label(slot1, 'Role', 'READY  ✓', 9, palette.green)
  s1Role.Font = Enum.Font.GothamBold
  s1Role.Position = UDim2.fromOffset(40, 20)
  s1Role.Size = UDim2.new(1, -44, 0, 14)
  s1Role.TextXAlignment = Enum.TextXAlignment.Left

  local slot3 = frame(teamABox, 'Slot3', palette.tileBg, 8)
  local s3Img = make('ImageLabel', slot3, 'Img', {
    BackgroundTransparency = 1,
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.fromOffset(6, 6),
    Image = 'rbxthumb://type=AvatarHeadShot&id=156&w=150&h=150',
  })
  corner(s3Img, 999)
  local s3Name = label(slot3, 'Name', 'Builderman', 11, palette.cream)
  s3Name.Font = Enum.Font.GothamBold
  s3Name.Position = UDim2.fromOffset(40, 4)
  s3Name.Size = UDim2.new(1, -44, 0, 16)
  s3Name.TextXAlignment = Enum.TextXAlignment.Left
  local s3Role = label(slot3, 'Role', 'PARTNER MATCHED  ✓', 9, palette.green)
  s3Role.Font = Enum.Font.GothamBold
  s3Role.Position = UDim2.fromOffset(40, 20)
  s3Role.Size = UDim2.new(1, -44, 0, 14)
  s3Role.TextXAlignment = Enum.TextXAlignment.Left

  -- Center VS label
  local vsLabel = label(qVsBox, 'VS', 'VS', 20, palette.gold)
  vsLabel.Font = Enum.Font.FredokaOne

  -- Team B (Right): Rivals
  local teamBBox = frame(qVsBox, 'TeamB', palette.panel, 10)
  outline(teamBBox, color(180, 80, 200), 1.2)
  local teamBTitle = label(teamBBox, 'Title', 'TEAM B (OPPONENTS)', 11, color(220, 140, 240))
  teamBTitle.Font = Enum.Font.GothamBold

  local slot2 = frame(teamBBox, 'Slot2', palette.tileBg, 8)
  local s2Img = make('ImageLabel', slot2, 'Img', {
    BackgroundTransparency = 1,
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.fromOffset(6, 6),
    Image = 'rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150',
  })
  corner(s2Img, 999)
  local s2Name = label(slot2, 'Name', 'Roblox', 11, palette.cream)
  s2Name.Font = Enum.Font.GothamBold
  s2Name.Position = UDim2.fromOffset(40, 4)
  s2Name.Size = UDim2.new(1, -44, 0, 16)
  s2Name.TextXAlignment = Enum.TextXAlignment.Left
  local s2Role = label(slot2, 'Role', 'OPPONENT MATCHED  ✓', 9, color(220, 140, 240))
  s2Role.Font = Enum.Font.GothamBold
  s2Role.Position = UDim2.fromOffset(40, 20)
  s2Role.Size = UDim2.new(1, -44, 0, 14)
  s2Role.TextXAlignment = Enum.TextXAlignment.Left

  local slot4 = frame(teamBBox, 'Slot4', palette.tileBg, 8)
  local s4Img = make('ImageLabel', slot4, 'Img', {
    BackgroundTransparency = 1,
    Size = UDim2.fromOffset(28, 28),
    Position = UDim2.fromOffset(6, 6),
    Image = 'rbxthumb://type=AvatarHeadShot&id=261&w=150&h=150',
  })
  corner(s4Img, 999)
  local s4Name = label(slot4, 'Name', 'Shedletsky', 11, palette.cream)
  s4Name.Font = Enum.Font.GothamBold
  s4Name.Position = UDim2.fromOffset(40, 4)
  s4Name.Size = UDim2.new(1, -44, 0, 16)
  s4Name.TextXAlignment = Enum.TextXAlignment.Left
  local s4Role = label(slot4, 'Role', 'OPPONENT MATCHED  ✓', 9, color(220, 140, 240))
  s4Role.Font = Enum.Font.GothamBold
  s4Role.Position = UDim2.fromOffset(40, 20)
  s4Role.Size = UDim2.new(1, -44, 0, 14)
  s4Role.TextXAlignment = Enum.TextXAlignment.Left

  teamABox.Visible = false
  teamBBox.Visible = false
  vsLabel.Visible = false
  local qSummary = label(qVsBox, 'Summary', '', 14, palette.cream)
  qSummary.Position = UDim2.fromOffset(12, 8)
  qSummary.Size = UDim2.new(1, -24, 1, -16)
  qSummary.TextWrapped = true

  local qStatus = label(qModal, 'Status', 'Your table starts automatically in a moment.', 12, palette.goldBright)

  local qStartBtn = button(qModal, 'StartNow', 'START NOW ▶', function()
    remote:FireServer('start_now')
  end)
  qStartBtn.TextSize = 13

  local qCancelBtn = button(qModal, 'Cancel', 'CANCEL', function()
    qShade.Visible = false
    remote:FireServer('cancel_queue')
  end, palette.panelLight)
  qCancelBtn.TextSize = 12

  queueUI.shade = qShade
  queueUI.modal = qModal
  queueUI.tierLabel = qTierLabel
  queueUI.statusLabel = qStatus
  queueUI.banner = qBanner
  queueUI.bannerText = qBannerText
  queueUI.vsBox = qVsBox
  queueUI.teamABox = teamABox
  queueUI.teamATitle = teamATitle
  queueUI.slot1 = slot1
  queueUI.slot3 = slot3
  queueUI.vsLabel = vsLabel
  queueUI.teamBBox = teamBBox
  queueUI.teamBTitle = teamBTitle
  queueUI.slot2 = slot2
  queueUI.slot4 = slot4
  queueUI.startBtn = qStartBtn
  queueUI.cancelBtn = qCancelBtn

  C.cancelQueue = function()
    qShade.Visible = false
    remote:FireServer('cancel_queue')
  end

  -- Waiting room: who is seated (you, friends, bots), the code to share, and
  -- Start for the host. Opens for anyone seated at a table not yet dealt.
  local tierTitles = { novice = 'NOVICE TABLE · BASE 500', pro = 'PRO LOUNGE · BASE 1.5K', master = 'MASTER ARENA · BASE 5K',
    highroller = '🎰 HIGH ROLLER · BASE 15K', whale = '🐋 WHALE ROOM · BASE 60K', legend = '🐉 LEGEND VAULT · BASE 250K' }
  queueUI.renderTable = function(info)
    if not info then return end
    if info.status ~= 'waiting' then
      qShade.Visible = false
      return
    end
    qShade.Visible = true
    local yours, theirs = {}, {}
    for seat = 1, info.playerCount do
      local entry = info.seats[seat] or {}
      local name = seat == 1 and 'You' or (entry.name or ('Seat ' .. seat))
      if entry.human and entry.host and seat ~= 1 then name = name .. ' (host)' end
      if not entry.human then name = name .. ' · bot' end
      table.insert(seat % 2 == 1 and yours or theirs, name)
    end
    qBannerText.Text = info.private and ('PRIVATE TABLE · ' .. tostring(info.code)) or (info.playerCount .. '-PLAYER TABLE')
    qTierLabel.Text = tierTitles[info.tier] or tierTitles.novice
    qSummary.Text = 'YOUR TEAM\n' .. table.concat(yours, '  ·  ') .. '\n\nOPPONENTS\n' .. table.concat(theirs, '  ·  ')
      .. (info.fullMatch and '\n\nFull match: rounds until a team passes Ace.' or '')
    if info.private then
      qStatus.Text = info.isHost
        and ('Share code ' .. tostring(info.code) .. ' so friends can join (' .. info.humans .. '/' .. info.playerCount .. ' seated). Start when ready; bots fill empty seats.')
        or 'Waiting for the host to start…'
    else
      local remaining = info.startsAt and C.state and C.state.serverTime and math.max(0, math.ceil(info.startsAt - C.state.serverTime))
      qStatus.Text = (info.humans > 1 and (info.humans .. ' players seated. ') or 'Looking for players. ')
        .. (remaining and ('Dealing in ' .. remaining .. 's.') or '')
    end
    qStartBtn.Visible = info.isHost == true
    qStartBtn.Text = 'START ▶'
    qCancelBtn.Text = 'LEAVE'
  end

  C.openQueue = function(chosenTier)
    chosenTier = chosenTier or 'novice'
    if C.state and C.state.coins then
      if chosenTier == 'master' and C.state.coins < 100000 then
        notice.Text = 'Master Arena requires 100K+ Coins!'
        return
      elseif chosenTier == 'pro' and C.state.coins < 8000 then
        notice.Text = 'Pro Lounge requires 8K–200K Coins!'
        return
      elseif chosenTier == 'novice' and C.state.coins < 2000 then
        notice.Text = 'Novice Table requires 2K–60K Coins!'
        return
      end
    end
    if C.updateCoinDisplays then C.updateCoinDisplays() end
    remote:FireServer('queue', { tier = chosenTier, playerCount = C.setupPlayerCount, fullMatch = arenaUI.fullMatch })
    C.lobbyMode = 'home'
    C.render()
    do return end
    local tierTitle = (chosenTier == 'master' and 'MASTER ARENA · BASE 4K') or (chosenTier == 'pro' and 'PRO LOUNGE · BASE 1.2K') or 'NOVICE TABLE · BASE 500'
    qTierLabel.Text = tierTitle
    qBannerText.Text = tostring(C.setupPlayerCount) .. '-PLAYER TABLE'
    qSummary.Text = tostring(C.setupPlayerCount / 2) .. ' vs ' .. tostring(C.setupPlayerCount / 2) .. '  ·  ' .. tostring(C.setupPlayerCount / 2) .. ' decks\n\nYou + ' .. tostring(C.setupPlayerCount - 1) .. ' bots\n\nDeclare trump, build combinations, and win tricks with your team.'
    qStatus.Text = 'Starting shortly. Press Start Now to skip the wait.'
    if arenaUI.fullMatch then qSummary.Text = qSummary.Text .. '\n\nFull match: play rounds until a team passes Ace.' end
    remote:FireServer('queue', { tier = chosenTier, playerCount = C.setupPlayerCount, fullMatch = arenaUI.fullMatch })
  end
end
arenaUI.initQueueModal()
end
