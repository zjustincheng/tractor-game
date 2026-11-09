-- Happy Tractor client, part 5/14: ReactionDock.
-- Lines 2211-2478 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Catalog, Players, arenaUI, button, corner, formatK, frame, header = C.Catalog, C.Players, C.arenaUI, C.button, C.corner, C.formatK, C.frame, C.header
local label, make, outline, palette, remote, root, seats, tween = C.label, C.make, C.outline, C.palette, C.remote, C.root, C.seats, C.tween

-- Interactive Table Quick Chat & Reaction Dock (Kuaile Shengji Table Popover)
local chatUI = {
  target = 'auto',
  targetPills = {},
  phraseBtns = {},
  throwableBtns = {},
  targetDefs = {
    { id = 'auto', label = 'AUTO' },
    { id = 'partner', label = 'PARTNER' },
    { id = 'seat2', label = 'SHEDLETSKY' },
    { id = 'seat4', label = 'ROBLOX' },
    { id = 'seat5', label = 'MATT' },
    { id = 'seat6', label = 'BRIGHTEYES' },
  },
} C.chatUI = chatUI
arenaUI.emoteDefs = arenaUI.R.defs
arenaUI.REACTION_COOLDOWN = 1.5 -- matches the server's emote/chat rate limit
function arenaUI.reactionToken(parent, name, def, size)
  return arenaUI.R.tile(parent, name, def, size, size, false)
end

function arenaUI.initChatPopover()
  -- Reaction sheet: header, target selector, reaction tiles, quick-chat chips
  -- and a cooldown bar. The body scrolls when the screen is short.
  chatUI.popover = frame(root, 'ChatPopover', palette.emeraldDeep, 16)
  chatUI.popover.Visible = false
  chatUI.popover.ZIndex = 48
  local sheetStroke = outline(chatUI.popover, palette.gold, 1.5)
  sheetStroke.Transparency = 0.35
  chatUI.title = label(chatUI.popover, 'Title', 'REACT', 14, palette.goldBright)
  chatUI.title.Font = Enum.Font.FredokaOne
  chatUI.title.TextXAlignment = Enum.TextXAlignment.Left
  chatUI.hint = label(chatUI.popover, 'Hint', 'Throw something at the table', 10, palette.muted)
  chatUI.hint.TextXAlignment = Enum.TextXAlignment.Left
  chatUI.close = make('TextButton', chatUI.popover, 'Close', { Text = 'X', TextSize = 14, Font = Enum.Font.GothamBold,
    TextColor3 = palette.muted, BackgroundColor3 = palette.panel, AutoButtonColor = false, BorderSizePixel = 0 })
  corner(chatUI.close, 999)
  chatUI.close.Activated:Connect(function() chatUI.popover.Visible = false end)

  chatUI.body = make('ScrollingFrame', chatUI.popover, 'Body', { BackgroundTransparency = 1, BorderSizePixel = 0,
    ScrollBarThickness = 3, ScrollBarImageColor3 = palette.gold, ScrollingDirection = Enum.ScrollingDirection.Y, CanvasSize = UDim2.new() })

  chatUI.targetBar = frame(chatUI.body, 'TargetBar', palette.emeraldDark, 10)
  local function sectionTitle(name, text)
    local t = label(chatUI.body, name, text, 10, palette.muted)
    t.Font = Enum.Font.GothamBlack
    t.TextXAlignment = Enum.TextXAlignment.Left
    return t
  end
  chatUI.itemsTitle = sectionTitle('ItemsTitle', 'REACTIONS')
  chatUI.dialogueTitle = sectionTitle('DialogueTitle', 'QUICK CHAT')

  local function updateTargetPills()
    for id, pill in pairs(chatUI.targetPills) do
      local isSel = id == chatUI.target
      pill.BackgroundTransparency = isSel and 0 or 1
      pill.TextColor3 = isSel and palette.ink or palette.cream
    end
  end
  -- Four players can aim at each opponent; bigger tables aim by team.
  chatUI.rebuildTargets = function(playerCount)
    if chatUI.builtFor == playerCount then return false end
    chatUI.builtFor = playerCount
    for _, pill in pairs(chatUI.targetPills) do pill:Destroy() end
    chatUI.targetPills = {}
    if playerCount == 4 then
      chatUI.targetDefs = {
        { id = 'auto', label = 'Auto' }, { id = 'partner', label = 'Partner' }, { id = 'opponents', label = 'Both opp.' },
        { id = 'seat2', label = seats[2].name.Text }, { id = 'seat4', label = seats[4].name.Text },
      }
    else
      chatUI.targetDefs = { { id = 'auto', label = 'Auto' }, { id = 'team', label = 'My team' }, { id = 'opponents', label = 'Opponents' } }
    end
    local valid = false
    for _, td in ipairs(chatUI.targetDefs) do
      if td.id == chatUI.target then valid = true end
      local pill = make('TextButton', chatUI.targetBar, 'Tgt_' .. td.id, { Text = td.label, TextSize = 11, Font = Enum.Font.GothamBold,
        BackgroundColor3 = palette.gold, BorderSizePixel = 0, AutoButtonColor = false, TextTruncate = Enum.TextTruncate.AtEnd })
      corner(pill, 8)
      pill.Activated:Connect(function()
        chatUI.target = td.id
        updateTargetPills()
      end)
      chatUI.targetPills[td.id] = pill
    end
    if not valid then chatUI.target = 'auto' end
    updateTargetPills()
    return true
  end
  chatUI.rebuildTargets(4)

  chatUI.throwables = {}
  chatUI.tileOrder = {}
  for _, id in ipairs(arenaUI.R.order) do
    local def = arenaUI.R.defs[id]
    local price = 0
    for _, item in ipairs(Catalog) do if item.id == id then price = item.price or 0 end end
    local hit = make('TextButton', chatUI.body, 'Throw_' .. id, { Text = '', BackgroundTransparency = 1, AutoButtonColor = false, BorderSizePixel = 0 })
    hit.Activated:Connect(function() C.sendTableMessage('emote', id) end)
    local lock = label(hit, 'Lock', '🔒 ' .. formatK(price), 9, palette.goldBright)
    lock.Font = Enum.Font.GothamBlack
    lock.BackgroundTransparency = 0.15
    lock.BackgroundColor3 = palette.darkStroke
    lock.TextWrapped = false
    lock.ZIndex = 60
    corner(lock, 999)
    lock.Visible = false
    chatUI.throwables[id] = { button = hit, lock = lock, def = def, price = price }
    table.insert(chatUI.tileOrder, id)
  end

  for _, phrase in ipairs(Catalog.phrases) do
    local chip = make('TextButton', chatUI.body, 'Phrase_' .. phrase.id, { Text = phrase.text, TextSize = 11, Font = Enum.Font.GothamBold,
      TextColor3 = palette.cream, BackgroundColor3 = palette.panel, BorderSizePixel = 0, AutoButtonColor = false,
      TextTruncate = Enum.TextTruncate.AtEnd })
    corner(chip, 999)
    local chipStroke = outline(chip, palette.panelBorder, 1)
    chipStroke.Transparency = 0.4
    chip.Activated:Connect(function() C.sendTableMessage('chat', phrase.id) end)
    table.insert(chatUI.phraseBtns, chip)
  end

  chatUI.cooldown = frame(chatUI.popover, 'Cooldown', palette.emeraldDark, 999)
  chatUI.cooldownFill = frame(chatUI.cooldown, 'Fill', palette.gold, 999)
  chatUI.cooldownFill.Size = UDim2.fromScale(0, 1)

  -- Locked tiles fade and show their price; everything dims while cooling down.
  arenaUI.refreshDock = function()
    local cooling = os.clock() < (arenaUI.reactionReadyAt or 0)
    for id, entry in pairs(chatUI.throwables) do
      local owned = C.state and C.state.owned and C.state.owned[id]
      entry.lock.Visible = not owned
      local tileFrame = entry.button:FindFirstChild('Tile')
      if tileFrame then
        tileFrame.BackgroundTransparency = (not owned) and 0.55 or (cooling and 0.35 or 0)
        tileFrame.Glyph.TextTransparency = (not owned or cooling) and 0.45 or 0
      end
    end
    for _, chip in ipairs(chatUI.phraseBtns) do chip.TextTransparency = cooling and 0.5 or 0 end
  end
  -- Drains the cooldown bar across the reaction cooldown.
  arenaUI.startCooldownBar = function(seconds)
    chatUI.cooldownFill.Size = UDim2.fromScale(1, 1)
    tween(chatUI.cooldownFill, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(0, 1) })
  end

  C.toggleTableChat = function()
    chatUI.popover.Visible = not chatUI.popover.Visible
    if chatUI.popover.Visible then
      if C.resize then C.resize() end
      local scale = chatUI.popover:FindFirstChild('OpenScale') or make('UIScale', chatUI.popover, 'OpenScale', { Scale = 1 })
      scale.Scale = 0.92
      tween(scale, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 })
    end
  end

  C.sendTableMessage = function(kind, id)
    local wasOwnedOrChat = kind == 'chat' or (C.state and C.state.owned and C.state.owned[id])
    arenaUI.sendReaction(kind, id, chatUI.target)
    if wasOwnedOrChat then chatUI.popover.Visible = false end
  end
end
arenaUI.initChatPopover()

local handFrame = make('ScrollingFrame', root, 'Hand', { BackgroundTransparency = 1,
  BorderSizePixel = 0, CanvasSize = UDim2.new(), ScrollBarThickness = 4,
  ScrollBarImageColor3 = palette.gold, ScrollingDirection = Enum.ScrollingDirection.X }) C.handFrame = handFrame

local footer = frame(root, 'Footer', palette.emeraldDeep, 10) C.footer = footer
footer.BackgroundTransparency = 0.2
outline(footer, palette.panelBorder, 1)
local selfAvatar = frame(footer, 'SelfAvatar', palette.teamBlue, 999) C.selfAvatar = selfAvatar
arenaUI.selfAvatarRing = outline(selfAvatar, palette.teamBlue, 2.5)
arenaUI.selfAvatarScale = make('UIScale', selfAvatar, 'Scale', { Scale = 1.0 })
do
  local selfAvatarImg = make('ImageLabel', selfAvatar, 'Headshot', {
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Image = 'rbxthumb://type=AvatarHeadShot&id=' .. tostring((Players.LocalPlayer and Players.LocalPlayer.UserId) or 1) .. '&w=150&h=150',
  })
  corner(selfAvatarImg, 999)
end

local selfDealerSeal = frame(selfAvatar, 'DealerSeal', palette.dealerRed, 999) C.selfDealerSeal = selfDealerSeal
selfDealerSeal.Size = UDim2.fromOffset(16, 16)
selfDealerSeal.Position = UDim2.fromOffset(-4, -4)
selfDealerSeal.Visible = false
selfDealerSeal.ZIndex = 5
outline(selfDealerSeal, palette.gold, 1.2)
do
  local selfDealerText = label(selfDealerSeal, 'Text', 'D', 10, palette.goldBright)
  selfDealerText.Font = Enum.Font.GothamBold
  selfDealerText.Size = UDim2.fromScale(1, 1)
  selfDealerText.ZIndex = 6
end

local selfBubble = frame(footer, 'SelfChatBubble', palette.cream, 8) C.selfBubble = selfBubble
selfBubble.Visible = false
selfBubble.ZIndex = 45
outline(selfBubble, palette.railOuter, 1)
local selfBubbleText = label(selfBubble, 'Text', '', 10, palette.ink)
selfBubbleText.Font = Enum.Font.GothamBold
selfBubbleText.Size = UDim2.fromScale(1, 1)

local selfName = label(footer, 'SelfName', 'YOU  ·  TEAM A', 11, palette.green) C.selfName = selfName
selfName.Font = Enum.Font.GothamBold
selfName.TextXAlignment = Enum.TextXAlignment.Left
local selfDeclarationCards = frame(footer, 'DeclarationCards', palette.cream, 5) C.selfDeclarationCards = selfDeclarationCards
selfDeclarationCards.BackgroundTransparency = 1
selfDeclarationCards.Visible = false
selfDeclarationCards.ZIndex = 28
local handHint = label(footer, 'HandHint', 'Win matches & capture point cards for coin bonuses!', 11, palette.white) C.handHint = handHint

C.autoButton = button(footer, 'AutoPlay', 'AUTO OFF', function()
  C.autoPlay = not C.autoPlay
  C.autoButton.Text = C.autoPlay and 'AUTO ON' or 'AUTO OFF'
  C.nextAutoAt = os.clock()+1.2
end,palette.panelLight)
C.autoButton.TextColor3 = palette.white
C.autoButton.TextSize=9
local headerLobbyBtn = button(header, 'HeaderLobby', '⬅ LOBBY', function()
  if C.busy then return end
  remote:FireServer('lobby')
  C.lobbyMode = 'home'
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.updateAction()
  C.render()
end, palette.panelLight) C.headerLobbyBtn = headerLobbyBtn
headerLobbyBtn.TextColor3 = palette.white
headerLobbyBtn.TextSize = 11

local headerChangeTableBtn = button(header, 'HeaderChangeTable', '🔄 TABLE', function()
  if C.busy then return end
  local chosenTier = (C.state and C.state.game and C.state.game.tier) or 'novice'
  remote:FireServer('change_table')
  if C.openQueue then C.openQueue(chosenTier) end
end, palette.panelLight) C.headerChangeTableBtn = headerChangeTableBtn
headerChangeTableBtn.TextColor3 = palette.white
headerChangeTableBtn.TextSize = 11

C.headerSettingsBtn = button(header, 'HeaderSettings', '⚙', function()
  if C.openSettingsModal then C.openSettingsModal() end
end, palette.tileBg)
C.headerSettingsBtn.TextSize = 13


function arenaUI.initHistoryModal()
  C.historyShade = button(root, 'HistoryShade', '', function() end, palette.emeraldDeep)
  C.historyShade.BackgroundTransparency = 0.22
  C.historyShade.Visible = false
  C.historyShade.ZIndex = 50
  C.historyPanel = frame(C.historyShade, 'HistoryPanel', palette.panel, 16)
  outline(C.historyPanel, palette.panelBorder, 1)
  C.historyTitle = label(C.historyPanel, 'Title', 'ROUND HISTORY', 20, palette.gold)
  C.historyTitle.Font = Enum.Font.FredokaOne
  C.historyClose = button(C.historyPanel, 'CloseHistory', '×', function() C.historyShade.Visible = false end, palette.panelLight)
  C.historyClose.TextSize = 14
  C.historyBody = make('ScrollingFrame', C.historyPanel, 'HistoryBody', {BackgroundTransparency=1,BorderSizePixel=0,
    ScrollBarThickness=4,ScrollBarImageColor3=palette.gold,CanvasSize=UDim2.new(0,0,0,0),AutomaticCanvasSize=Enum.AutomaticSize.Y})
  C.historyButton = button(footer, 'History', 'HISTORY', function()
    C.historyShade.Visible = true
  end, palette.panelLight)
end
arenaUI.initHistoryModal()
C.historyButton.TextSize=10
local emoteLine = label(root, 'EmoteToast', '', 16, palette.gold) C.emoteLine = emoteLine
emoteLine.ZIndex = 30
end
