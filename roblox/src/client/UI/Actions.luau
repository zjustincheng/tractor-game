-- Happy Tractor client, part 4/14: Actions.
-- Lines 1986-2210 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Rules, Structures, actionBar, arenaUI, button, color, frame, gradient = C.Rules, C.Structures, C.actionBar, C.arenaUI, C.button, C.color, C.frame, C.gradient
local header, label, outline, palette, playSound, remote, root = C.header, C.label, C.outline, C.palette, C.playSound, C.remote, C.root

-- Round Settlement Dialog
local settleUI = {} C.settleUI = settleUI
function arenaUI.initSettlementModal()
arenaUI.settleShade = frame(root, 'SettleShade', palette.emeraldDark, 0)
arenaUI.settleShade.Size = UDim2.fromScale(1, 1)
arenaUI.settleShade.BackgroundTransparency = 0.35
arenaUI.settleShade.ZIndex = 59
arenaUI.settleShade.Visible = false
-- Active makes the shade swallow clicks, so the lobby and table behind the
-- settlement screen cannot be used while it is up. Every other shade is a
-- TextButton, which blocks on its own; this one is a plain Frame.
arenaUI.settleShade.Active = true
local settlementModal = frame(root, 'SettlementModal', palette.emeraldDeep, 22)
settlementModal.BackgroundTransparency = 0.05
settlementModal.Visible = false
settlementModal.ZIndex = 60
settlementModal.Active = true
outline(settlementModal, palette.gold, 2)

local settleBanner = frame(settlementModal, 'Banner', palette.goldDark, 14)
gradient(settleBanner, palette.goldBright, palette.goldDark, 90)
local settleBannerText = label(settleBanner, 'Text', '🏆 ROUND VICTORY', 17, palette.ink)
settleBannerText.Font = Enum.Font.FredokaOne
settleBannerText.Size = UDim2.fromScale(1, 1)

local settleLevelTitle = label(settlementModal, 'LevelTitle', '👑 TOTAL SHUTOUT! (+3 LEVELS)', 18, palette.white)
settleLevelTitle.Font = Enum.Font.GothamBold
settleLevelTitle.TextSize = 13
settleLevelTitle.TextColor3 = palette.cream

local settleGrid = frame(settlementModal, 'Grid', palette.tileBg, 12)
outline(settleGrid, palette.panelBorder, 1)
local settleScoreA = label(settleGrid, 'ScoreA', 'Dealer Team (You): 120 pts', 13, palette.white)
settleScoreA.Font = Enum.Font.GothamBold
local settleScoreB = label(settleGrid, 'ScoreB', 'Challengers (Opponents): 10 pts', 13, palette.white)
settleScoreB.Font = Enum.Font.GothamBold

-- Dedicated Coin Earnings Card (shows how much you earned at end of game)
local settleCoinCard = frame(settlementModal, 'CoinCard', palette.panel, 10)
outline(settleCoinCard, palette.gold, 1.5)
local settleCoinTotal = label(settleCoinCard, 'Total', '💰 +2,000 COINS WON!', 16, palette.goldBright)
settleCoinTotal.Font = Enum.Font.FredokaOne
settleCoinTotal.TextSize = 26
local settleCoinSub = label(settleCoinCard, 'Sub', 'Base: 500  ×  4x (大光 Total Shutout)', 10, palette.white)
settleCoinSub.Font = Enum.Font.GothamBold
settleCoinSub.TextSize = 11
settleCoinSub.TextColor3 = palette.muted
settleCoinSub.TextWrapped = true

local settlePlayAgain = button(settlementModal, 'PlayAgain', '▶ PLAY AGAIN', function()
  settlementModal.Visible = false
  remote:FireServer('play_again', { tier = (C.state and C.state.game and C.state.game.tier) or 'novice' })
end)
settlePlayAgain.TextSize = 13

local settleChangeTable = button(settlementModal, 'ChangeTable', '🔄 NEW TABLE', function()
  settlementModal.Visible = false
  remote:FireServer('change_table')
end, palette.panelLight)
settleChangeTable.TextColor3 = palette.white
settleChangeTable.TextSize = 12

local settleLobby = button(settlementModal, 'ReturnLobby', '⬅ LOBBY', function()
  settlementModal.Visible = false
  C.lobbyMode = 'home'
  remote:FireServer('lobby')
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.updateAction()
  C.render()
end, palette.panelLight)
settleLobby.TextColor3 = palette.white
settleLobby.TextSize = 12
  settleUI.modal = settlementModal
  settleUI.banner = settleBanner
  settleUI.bannerText = settleBannerText
  settleUI.levelTitle = settleLevelTitle
  settleUI.grid = settleGrid
  settleUI.scoreA = settleScoreA
  settleUI.scoreB = settleScoreB
  settleUI.coinCard = settleCoinCard
  settleUI.coinTotal = settleCoinTotal
  settleUI.coinSub = settleCoinSub
  settleUI.playAgain = settlePlayAgain
  settleUI.changeTable = settleChangeTable
  settleUI.lobby = settleLobby
end
arenaUI.initSettlementModal()


local function selectedList()
  local result = {}
  if C.state and C.state.game then
    for _, card in ipairs(C.state.game.hand) do if C.selectedIds[card.id] then table.insert(result, card.id) end end
  end
  return result
end C.selectedList = selectedList

local function command(action, value)
  if C.busy or not C.state or not C.state.game then return end
  C.busy = true
  C.updateAction()
  remote:FireServer(action, value, C.state.game.revision)
  task.delay(0.5, function() if C.busy then remote:FireServer('sync') end end)
end C.command = command

local function recommendCards()
  if C.busy or not C.state or not C.state.game then return end
  local current = C.state.game
  if current.done then return end

  local ids = current.hint
  if not ids or #ids == 0 then
    if current.phase == 'kitty' then
      if (current.kittyHolder or current.dealer) ~= 1 then return end
      local buried = Rules.chooseBurial(current.hand, current.kittySize, current.trump)
      ids = {}; for _, c in ipairs(buried) do table.insert(ids, c.id) end
    elseif current.phase == 'tricks' and current.turn == 1 then
      local context = Rules.playContext(current, 1)
      local chosen = Rules.choose(current.hand, current.trick[1] and current.trick[1].components, current.trump, context)
      ids = {}; for _, c in ipairs(chosen) do table.insert(ids, c.id) end
    end
  end

  if ids and #ids > 0 then
    C.selectedIds = {}
    for _, id in ipairs(ids) do C.selectedIds[id] = true end
    C.renderHand()
    C.updateAction()
  end
end C.recommendCards = recommendCards

local function submitSelection()
  if C.busy or not C.state then return end
  local current = C.state.game
  if not current or current.phase == 'blocked' or (current.done and current.settlement.winner) then
    remote:FireServer('start', {playerCount=C.setupPlayerCount}) return
  end
  if current.done then command('next-round') return end
  if current.phase == 'trick-review' then command('next-trick') return end
  if current.phase == 'chaodi' then
    if current.chaodiTurn == 1 and C.selectedChaodiIndex then
      playSound('turn_chime')
      command('chaodi', C.selectedChaodiIndex)
    end
    return
  end
  local ids = selectedList()
  if current.phase == 'kitty' then
    -- Only the kitty holder buries (seats are rotated so you are seat 1).
    if (current.kittyHolder or current.dealer) ~= 1 then return end
    if #ids == current.kittySize then
      playSound('card_play')
      command('bury', ids)
    else
      recommendCards()
    end
    return
  elseif current.phase == 'tricks' then
    if current.turn ~= 1 then return end
    if #ids == 0 then
      recommendCards()
      return
    end
    local cards = {}
    for _, card in ipairs(current.hand) do
      if C.selectedIds[card.id] then table.insert(cards, card) end
    end
    local isLegal = false
    if current.trick[1] then
      local follow = Rules.follow(current.hand, cards, current.trick[1].components, current.trump)
      isLegal = follow.legal == true
    else
      isLegal = Structures.decompose(cards, current.trump) ~= nil
    end
    if not isLegal then
      playSound('error')
      return
    end
    playSound('card_play', true)
    command('play', ids)
  end
end C.submitSelection = submitSelection
C.primary = button(actionBar, 'Primary', 'QUICK MATCH', submitSelection)

-- Double (加倍): raise your own stake ×2 before your first play.
arenaUI.doubleBtn = button(actionBar, 'DoubleBtn', 'DOUBLE ×2', function()
  remote:FireServer('double')
end, color(205, 38, 65))
arenaUI.doubleBtn.TextColor3 = palette.white
arenaUI.doubleBtn.Visible = false
local clear = button(actionBar, 'Clear', 'Clear', function()
  if C.busy then return end
  local current = C.state and C.state.game
  if current and current.phase == 'chaodi' and current.chaodiTurn == 1 then
    playSound('click')
    command('chaodi_pass')
    return
  end
  C.selectedIds = {}
  C.renderHand()
  C.updateAction()
end, palette.panel) C.clear = clear
clear.TextColor3 = palette.white


local tableChatBtn = button(actionBar, 'TableChat', 'CHAT', function()
  if C.toggleTableChat then C.toggleTableChat() end
end, palette.panelLight) C.tableChatBtn = tableChatBtn
tableChatBtn.TextColor3 = palette.white
tableChatBtn.TextSize = 11
tableChatBtn.TextXAlignment = Enum.TextXAlignment.Center
tableChatBtn.TextYAlignment = Enum.TextYAlignment.Center
tableChatBtn.AnchorPoint = Vector2.new(0.5, 0)
tableChatBtn.Text = 'CHAT'
tableChatBtn.BackgroundColor3 = palette.panel
outline(tableChatBtn, palette.goldDark, 2)
local function removeChatDecoration(child)
  if child:IsA('ImageLabel') or child:IsA('ImageButton') or child.Name == 'ChatIcon' then child:Destroy() end
end
for _, child in ipairs(tableChatBtn:GetChildren()) do removeChatDecoration(child) end
tableChatBtn.ChildAdded:Connect(removeChatDecoration)
tableChatBtn.DescendantAdded:Connect(removeChatDecoration)
-- The legacy icon is inserted by an older UI initializer after this script
-- creates the control, so keep the text-only button clean through that pass.
task.defer(function()
  for _ = 1, 8 do
    local icon = tableChatBtn:FindFirstChild('ChatIcon')
    if icon then icon:Destroy() end
    task.wait(0.1)
  end
end)
tableChatBtn.Parent = header
end
