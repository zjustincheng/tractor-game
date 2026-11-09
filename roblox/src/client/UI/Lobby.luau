-- Happy Tractor client, part 3/14: Lobby.
-- Lines 970-1985 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Players, arenaUI, button, color, corner, formatK, frame, gradient = C.Players, C.arenaUI, C.button, C.color, C.corner, C.formatK, C.frame, C.gradient
local label, make, notice, outline, palette, rect, remote, robloxGearImages = C.label, C.make, C.notice, C.outline, C.palette, C.rect, C.remote, C.robloxGearImages
local root = C.root

-- Modular Helper: Flat-shaded Casino Chip Stack
local function createChipStack(parent, numChips, chipColor, chipBorder)
  local stackHolder = frame(parent, 'ChipStack', Color3.fromRGB(0, 0, 0), 0)
  stackHolder.BackgroundTransparency = 1
  stackHolder.Size = UDim2.new(0, 48, 0, 32 + numChips * 4)
  stackHolder.AnchorPoint = Vector2.new(0.5, 0.5)

  for i = 1, numChips do
    local chip = frame(stackHolder, 'Chip_' .. i, chipColor, 999)
    chip.Size = UDim2.fromOffset(40, 15)
    chip.Position = UDim2.fromOffset(4, (numChips - i) * 4)
    chip.ZIndex = stackHolder.ZIndex + i
    outline(chip, chipBorder or palette.goldBright, 1.2)

    if i == numChips then
      local innerRing = frame(chip, 'InnerRing', Color3.fromRGB(0, 0, 0), 999)
      innerRing.BackgroundTransparency = 1
      innerRing.Position = UDim2.fromScale(0.2, 0.2)
      innerRing.Size = UDim2.fromScale(0.6, 0.6)
      innerRing.ZIndex = chip.ZIndex + 1
      outline(innerRing, palette.cream, 0.8)
    end
  end
  return stackHolder
end

-- Modular Helper: Illustrated Mode Card Thumbnail
local function buildIllustratedThumbnail(card, modeIdx, titleText, badgeText, teamText, topColor, botColor)
  local thumb = frame(card, 'Thumb', topColor, 12)
  thumb.Position = UDim2.fromOffset(4, 4)
  thumb.Size = UDim2.new(1, -8, 0.58, 0)
  thumb.ClipsDescendants = true
  outline(thumb, palette.darkStroke, 1.8)
  gradient(thumb, topColor, botColor, 135)

  -- Flat-shaded Cartoon Cards
  local c1 = frame(thumb, 'Card1', Color3.fromRGB(255, 255, 255), 4)
  c1.Size = UDim2.fromOffset(26, 36)
  c1.Position = UDim2.fromOffset(14, 8)
  c1.Rotation = -10
  outline(c1, palette.darkStroke, 1.2)
  local c1L = label(c1, 'Rank', modeIdx == 3 and '★' or 'A', 13, modeIdx == 2 and palette.red or palette.ink)
  c1L.Size = UDim2.fromScale(1, 0.6)
  c1L.TextStrokeTransparency = 1
  local c1S = label(c1, 'Suit', modeIdx == 3 and '★' or '♠', 13, modeIdx == 2 and palette.red or palette.ink)
  c1S.Size = UDim2.fromScale(1, 0.5)
  c1S.Position = UDim2.fromScale(0, 0.5)
  c1S.TextStrokeTransparency = 1

  local c2 = frame(thumb, 'Card2', Color3.fromRGB(255, 255, 255), 4)
  c2.Size = UDim2.fromOffset(26, 36)
  c2.Position = UDim2.fromOffset(30, 6)
  c2.Rotation = 12
  outline(c2, palette.darkStroke, 1.2)
  local c2L = label(c2, 'Rank', 'K', 13, palette.red)
  c2L.Size = UDim2.fromScale(1, 0.6)
  c2L.TextStrokeTransparency = 1
  local c2S = label(c2, 'Suit', '♥', 13, palette.red)
  c2S.Size = UDim2.fromScale(1, 0.5)
  c2S.Position = UDim2.fromScale(0, 0.5)
  c2S.TextStrokeTransparency = 1

  -- Casino Chip graphic (flat-shaded discs)
  local chip = frame(thumb, 'Chip', palette.gold, 999)
  chip.Size = UDim2.fromOffset(22, 22)
  chip.Position = UDim2.new(0, 60, 0, 16)
  outline(chip, palette.darkStroke, 1.5)
  local chipInner = frame(chip, 'Inner', Color3.fromRGB(0, 0, 0), 999)
  chipInner.BackgroundTransparency = 1
  chipInner.Size = UDim2.fromScale(0.6, 0.6)
  chipInner.Position = UDim2.fromScale(0.2, 0.2)
  outline(chipInner, palette.cream, 0.8)

  -- Player-Count Badge (top-right pill)
  local pBadge = frame(thumb, 'PlayerCountBadge', Color3.fromRGB(12, 28, 18), 999)
  pBadge.BackgroundTransparency = 0.4
  pBadge.Size = UDim2.fromOffset(86, 20)
  pBadge.Position = UDim2.new(1, -90, 0, 5)
  outline(pBadge, palette.goldDark, 1)

  local dot = frame(pBadge, 'Dot', palette.green, 999)
  dot.Size = UDim2.fromOffset(6, 6)
  dot.Position = UDim2.fromOffset(6, 7)

  local pTxt = label(pBadge, 'Text', teamText, 10, palette.cream)
  pTxt.Size = UDim2.new(1, -16, 1, 0)
  pTxt.Position = UDim2.fromOffset(14, 0)
  pTxt.TextXAlignment = Enum.TextXAlignment.Left

  -- Title Banner on the image
  local titleBanner = frame(thumb, 'TitleBanner', Color3.fromRGB(10, 24, 16), 0)
  titleBanner.BackgroundTransparency = 0.35
  titleBanner.Size = UDim2.new(1, 0, 0, 24)
  titleBanner.Position = UDim2.new(0, 0, 1, -24)
  outline(titleBanner, palette.goldDark, 0.8)

  local titleLbl = label(titleBanner, 'Title', titleText, 13, palette.cream)
  titleLbl.Size = UDim2.fromScale(1, 1)

  -- Lower Card Info
  local badgeLbl = label(card, 'Badge', badgeText, 11, palette.goldBright)
  badgeLbl.Position = UDim2.new(0, 6, 0.60, 4)
  badgeLbl.Size = UDim2.new(1, -12, 0, 16)
end

-- ==========================================================
-- 1. MAIN HOME SCREEN (FORMAT: 1252.jpg)
-- ==========================================================
local home = {} C.home = home
arenaUI.home = home
function arenaUI.initHomeScreen()
  home.view = frame(root, 'HomeScreen', palette.emeraldDeep, 20)
  home.view.BackgroundTransparency = 0.05
  home.view.ZIndex = 25
  outline(home.view, palette.railOuter, 1.8)

-- TOP HEADER BAR (1252.jpg Top Bar)
home.header = frame(home.view, 'HomeHeader', palette.panel, 14)
home.header.BackgroundTransparency = 0.4
outline(home.header, palette.panelBorder, 1)

home.title = label(home.header, 'ModeTitle', 'PLAY TRACTOR', 15, palette.cream)
home.title.Font = Enum.Font.GothamBold
home.title.TextXAlignment = Enum.TextXAlignment.Left

home.coinPill = frame(home.header, 'CoinPill', palette.tileBg, 999)
outline(home.coinPill, palette.gold, 1)
local homeCoinDot = frame(home.coinPill, 'Dot', palette.goldBright, 999)
homeCoinDot.Size = UDim2.fromOffset(14, 14)
homeCoinDot.Position = UDim2.fromOffset(6, 7)
local homeCoinDotTxt = label(homeCoinDot, 'Sym', '$', 9, palette.ink)
homeCoinDotTxt.Size = UDim2.fromScale(1, 1)
homeCoinDotTxt.Font = Enum.Font.GothamBlack
home.coinText = label(home.coinPill, 'Text', '3K', 12, palette.goldBright)
home.coinText.Font = Enum.Font.FredokaOne
home.coinText.Size = UDim2.new(1, -40, 1, 0)
home.coinText.Position = UDim2.fromOffset(24, 0)
home.coinText.TextXAlignment = Enum.TextXAlignment.Left

local homeCoinPlus = label(home.coinPill, 'Plus', '+', 13, palette.goldBright)
homeCoinPlus.Font = Enum.Font.GothamBold
homeCoinPlus.Size = UDim2.fromOffset(18, 24)
homeCoinPlus.Position = UDim2.new(1, -20, 0, 2)
homeCoinPlus.TextXAlignment = Enum.TextXAlignment.Center

home.vipBadge = frame(home.header, 'VipBadge', color(170, 50, 40), 999)
outline(home.vipBadge, palette.goldBright, 1)
local homeVipText = label(home.vipBadge, 'Text', 'VIP', 9, palette.goldBright)
homeVipText.Font = Enum.Font.GothamBlack
homeVipText.Size = UDim2.fromScale(1, 1)

home.passBadge = frame(home.header, 'PassBadge', color(35, 95, 160), 999)
outline(home.passBadge, palette.goldBright, 1)
local homePassText = label(home.passBadge, 'Text', 'PASS', 9, palette.cream)
homePassText.Font = Enum.Font.GothamBold
homePassText.Size = UDim2.fromScale(1, 1)

home.settingsBtn = button(home.header, 'SettingsBtn', '⚙', function()
  if C.openSettingsModal then C.openSettingsModal() end
end, palette.panelLight)
home.settingsBtn.TextSize = 13

home.rulesBtn = button(home.header, 'RulesBtn', '?', function()
  if C.openRulesModal then C.openRulesModal() end
end, palette.panelLight)
home.rulesBtn.TextSize = 13

home.profileBtn = button(home.header, 'ProfileBtn', '', function()
  if C.openProfile then C.openProfile() end
end, palette.panelLight)
home.mailBtn = button(home.header, 'MailBtn', '✉', function()
  if C.openMailModal then C.openMailModal() end
end, palette.panelLight)
home.mailBtn.TextSize = 13

home.mailDot = frame(home.mailBtn, 'Badge', palette.red, 999)
home.mailDot.Position = UDim2.new(1, -7, 0, -3)
home.mailDot.Size = UDim2.fromOffset(10, 10)
outline(home.mailDot, palette.cream, 1)

-- HERO EVENT BANNER (1252.jpg Left Featured Card)
home.heroCard = frame(home.view, 'HeroCard', palette.tileBg, 16)
outline(home.heroCard, palette.goldBright, 2.5)
gradient(home.heroCard, color(38, 91, 141), color(19, 35, 60), 135)

home.heroTag = frame(home.heroCard, 'Tag', color(16, 52, 34), 8)
outline(home.heroTag, palette.gold, 1.2)
local homeHeroTagText = label(home.heroTag, 'Text', 'QUICK MATCH  ·  START HERE', 11, palette.goldBright)
homeHeroTagText.Size = UDim2.fromScale(1, 1)

home.dragonFrame = frame(home.heroCard, 'DragonIllustration', Color3.fromRGB(0, 0, 0), 0)
home.dragonFrame.BackgroundTransparency = 1
home.dragonFrame.Size = UDim2.new(1, -16, 0, 68)
home.dragonFrame.Position = UDim2.fromOffset(8, 32)

home.dragonAura = frame(home.dragonFrame, 'Aura', palette.goldBright, 999)
home.dragonAura.Size = UDim2.fromOffset(60, 60)
home.dragonAura.Position = UDim2.new(0.5, -30, 0, 4)
home.dragonAura.BackgroundTransparency = 0.82
outline(home.dragonAura, palette.gold, 1.5)

home.heroIcon = make('ImageLabel', home.dragonAura, 'Icon', {
  BackgroundTransparency = 1,
  Size = UDim2.fromScale(1, 1),
  Position = UDim2.fromScale(0, 0),
  Image = robloxGearImages.dragon,
  ZIndex = 3,
})
corner(home.heroIcon, 999)
home.heroIcon.Visible = false
local quickGlyph = label(home.dragonAura, 'QuickGlyph', '★', 30, palette.goldBright)
quickGlyph.Size = UDim2.fromScale(1, 1)
quickGlyph.Position = UDim2.fromScale(0, 0)
quickGlyph.TextStrokeTransparency = 0.1
quickGlyph.TextStrokeColor3 = palette.darkStroke
quickGlyph.Visible = false
home.dragonAura.BackgroundTransparency = 1
home.dragonAura.Outline.Enabled = false
for index, face in ipairs({{'A', '♠'}, {'K', '♥'}, {'A', '♠'}}) do
  local tile = frame(home.dragonAura, 'HeroPlayingCard' .. index, palette.cardFace, 5)
  tile.Size = UDim2.fromOffset(34, 47)
  tile.Position = UDim2.fromOffset(-4 + (index - 1) * 19, index == 2 and 0 or 7)
  tile.Rotation = (index - 2) * 16
  outline(tile, palette.darkStroke, 2)
  local rank = label(tile, 'Rank', face[1], 14, index == 2 and palette.red or palette.ink)
  rect(rank, 3, 2, 16, 18)
  local suit = label(tile, 'Suit', face[2], 20, index == 2 and palette.red or palette.ink)
  rect(suit, 5, 19, 24, 24)
end

home.heroTitle = label(home.heroCard, 'Title', 'TRACTOR QUICK MATCH', 18, palette.goldBright)
home.heroTitle.TextStrokeTransparency = 0.15
home.heroTitle.TextStrokeColor3 = palette.darkStroke

home.heroDesc = label(home.heroCard, 'Desc', 'YOUR PARTNER. YOUR PLAY.\n\nBuild pairs. Declare trump.\nTake the winning trick.', 12, palette.cream)

home.heroBtn = button(home.heroCard, 'HeroAction', 'PLAY QUICK MATCH ▶', function()
  if C.state and C.state.squad and not C.state.squad.isLeader then notice.Text = 'Your squad leader picks the mode.' return end
  C.lobbyMode = 'tier'
  C.setupPlayerCount = 4
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.updateAction()
  C.render()
end)
home.heroBtn.TextSize = 13

-- Shimmer effect on ENTER button
home.heroBtn.ClipsDescendants = true -- the shimmer rests outside between sweeps
local heroShimmer = frame(home.heroBtn, 'Shimmer', Color3.fromRGB(255, 255, 255), 8)
heroShimmer.Size = UDim2.new(0.4, 0, 1.5, 0)
heroShimmer.Position = UDim2.new(-0.8, 0, -0.25, 0)
heroShimmer.Rotation = 25
heroShimmer.BackgroundTransparency = 0.65
heroShimmer.ZIndex = home.heroBtn.ZIndex + 2
heroShimmer.Active = false
gradient(heroShimmer, Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 255, 255), 0)
local heroShimGrad = heroShimmer:FindFirstChild('Gradient')
if heroShimGrad then
  heroShimGrad.Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 1),
    NumberSequenceKeypoint.new(0.5, 0.4),
    NumberSequenceKeypoint.new(1, 1),
  })
end
if C.TweenService then
  task.spawn(function()
    while home.heroBtn and home.heroBtn.Parent do
      heroShimmer.Position = UDim2.new(-0.8, 0, -0.25, 0)
      local t = C.TweenService:Create(heroShimmer, TweenInfo.new(1.0, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Position = UDim2.new(1.8, 0, -0.25, 0)
      })
      t:Play()
      task.wait(3.5)
    end
  end)
end

-- GAME MODES 2x2 GRID (1252.jpg Center-Right Cards)
home.mode1 = frame(home.view, 'Mode1', palette.tileBg, 14)
outline(home.mode1, palette.gold, 1.5)
buildIllustratedThumbnail(home.mode1, 1, 'CLASSIC TRACTOR', '4 PLAYERS · 2 DECKS', '2 vs 2', color(240, 130, 30), color(160, 60, 15))
local m1Btn = button(home.mode1, 'Action', 'PLAY ▶', function()
  C.setupPlayerCount = 4
  C.lobbyMode = 'tier'
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.updateAction()
  C.render()
end, palette.gold)
m1Btn.TextSize = 13

home.mode2 = frame(home.view, 'Mode2', palette.tileBg, 14)
outline(home.mode2, palette.panelBorder, 1.5)
buildIllustratedThumbnail(home.mode2, 2, '4-DECK EPIC', '8 PLAYERS · 4 DECKS', '4 vs 4', color(38, 135, 230), color(16, 60, 140))
local m2Btn = button(home.mode2, 'Action', 'PLAY ▶', function()
  C.setupPlayerCount = 8
  C.lobbyMode = 'tier'
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.updateAction()
  C.render()
end, palette.gold)
m2Btn.TextSize = 13

home.mode3 = frame(home.view, 'Mode3', palette.tileBg, 14)
outline(home.mode3, palette.panelBorder, 1.5)
buildIllustratedThumbnail(home.mode3, 3, '5-DECK MEGA', '10 PLAYERS · 5 DECKS', '5 vs 5', color(155, 48, 215), color(80, 18, 125))
local m3Btn = button(home.mode3, 'Action', 'PLAY ▶', function()
  C.setupPlayerCount = 10
  C.lobbyMode = 'tier'
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.updateAction()
  C.render()
end, palette.gold)
m3Btn.TextSize = 13

home.mode4 = frame(home.view, 'Mode4', palette.tileBg, 14)
outline(home.mode4, palette.panelBorder, 1.5)
buildIllustratedThumbnail(home.mode4, 4, '3-DECK TEAM', '6 PLAYERS · 3 DECKS', '3 vs 3', color(28, 155, 125), color(12, 75, 60))
local m4Btn = button(home.mode4, 'Action', 'PLAY ▶', function()
  C.setupPlayerCount = 6
  C.lobbyMode = 'tier'
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.updateAction()
  C.render()
end, palette.gold)
m4Btn.TextSize = 13

local modeDescriptions = {
  { home.mode1, 'The classic partnership game. A great place to start.' },
  { home.mode2, 'Larger teams and more copies of every card.' },
  { home.mode3, 'Our biggest table: ten seats, five decks.' },
  { home.mode4, 'Three teammates on each side. More room for teamwork.' },
}
for _, entry in ipairs(modeDescriptions) do
  local description = label(entry[1], 'Description', entry[2], 11, palette.cream)
  description.TextWrapped = true
end

home.sidePills = {
  button(home.view, 'SidePill1', 'GRAND SLAM', function()
    C.setupPlayerCount = 4; C.lobbyMode = 'tier'; if C.updateCoinDisplays then C.updateCoinDisplays() end; C.updateAction(); C.render()
  end, palette.panelLight),
  button(home.view, 'SidePill2', '10P MEGA', function()
    C.setupPlayerCount = 10; C.lobbyMode = 'tier'; if C.updateCoinDisplays then C.updateCoinDisplays() end; C.updateAction(); C.render()
  end, palette.panelLight),
  button(home.view, 'SidePill3', '3-VS-1 SOLO', function()
    C.setupPlayerCount = 4; C.lobbyMode = 'tier'; if C.updateCoinDisplays then C.updateCoinDisplays() end; C.updateAction(); C.render()
  end, palette.panelLight),
}
for _, pill in ipairs(home.sidePills) do pill.TextSize = 10 end

-- BOTTOM NAVIGATION BAR (1252.jpg Bottom Icons & Quick Start)
home.bottomBar = frame(home.view, 'BottomBar', palette.panel, 14)
home.bottomBar.BackgroundTransparency = 0.4
outline(home.bottomBar, palette.panelBorder, 1)

home.shopBtn = button(home.bottomBar, 'ShopBtn', 'SHOP', function() end, palette.panelLight)
home.shopBtn.TextSize = 12

home.emoteBtn = button(home.bottomBar, 'EmoteBtn', 'EMOTES', function() end, palette.panelLight)
home.emoteBtn.TextSize = 12

home.historyBtn = button(home.bottomBar, 'HistoryBtn', 'STATS', function() end, palette.panelLight)
home.historyBtn.TextSize = 12

home.rewardsBtn = button(home.bottomBar, 'RewardsBtn', 'REWARDS', function()
  if C.openRewardsModal then C.openRewardsModal() end
end, palette.panelLight)
home.rewardsBtn.TextSize = 12

home.luckyBtn = button(home.bottomBar, 'LuckyBtn', 'LUCKY', function()
  if C.openLuckyModal then C.openLuckyModal() end
end, palette.panelLight)
home.luckyBtn.TextSize = 12

home.vaultBtn = button(home.bottomBar, 'VaultBtn', 'VAULT', function()
  if C.openVaultModal then C.openVaultModal() end
end, palette.panelLight)
home.vaultBtn.TextSize = 12

end
arenaUI.initHomeScreen()

-- ==========================================================
-- SQUAD LOBBY: party panel, invites, matchmaking status
-- ==========================================================
-- The lobby has its own backdrop instead of the game table behind it.
arenaUI.lobbyBackdrop = frame(root, 'LobbyBackdrop', palette.emeraldDark, 0)
arenaUI.lobbyBackdrop.Size = UDim2.fromScale(1, 1)
arenaUI.lobbyBackdrop.ZIndex = 24
arenaUI.lobbyBackdrop.Visible = false
gradient(arenaUI.lobbyBackdrop, color(26, 44, 70), color(10, 16, 28), 90)
for index, spec in ipairs({ { '♠', 0.08, 0.18, 220 }, { '♥', 0.9, 0.14, 180 }, { '♣', 0.06, 0.86, 170 }, { '♦', 0.92, 0.82, 230 } }) do
  local suit = label(arenaUI.lobbyBackdrop, 'Suit' .. index, spec[1], spec[4], palette.white)
  suit.TextTransparency = 0.94
  suit.TextWrapped = false
  suit.AnchorPoint = Vector2.new(0.5, 0.5)
  suit.Position = UDim2.fromScale(spec[2], spec[3])
  suit.Size = UDim2.fromOffset(spec[4], spec[4])
  suit.ZIndex = 24
end

-- Save status in the lobby header (the in-game header is hidden here).
home.saveChip = button(home.header, 'SaveChip', '✓ Saved', function()
  if C.state and C.state.saving and not C.state.saving.enabled then arenaUI.saveShade.Visible = true end
end, palette.panelLight)
home.saveChip.TextSize = 11

-- The home screen's featured card becomes your squad: members (leader has a
-- crown and can remove others), Invite, Fill, Leave, and Play for the leader.
home.heroTag.Text.Text = 'SQUAD'
home.squadMembers = frame(home.heroCard, 'SquadMembers', palette.emeraldDark, 10)
home.squadMembers.BackgroundTransparency = 0.35
home.squadInvite = button(home.heroCard, 'SquadInvite', '👥 SQUAD UP', function() arenaUI.openInvites() end, palette.panelLight)
home.squadInvite.TextSize = 11
home.squadFill = button(home.heroCard, 'SquadPrivacy', '🌐 PUBLIC', function()
  local squad = C.state and C.state.squad
  if squad and not squad.isLeader then notice.Text = 'Only the squad leader can change this.' return end
  remote:FireServer('squad_privacy', not (squad == nil or squad.public ~= false))
end, palette.panelLight)
home.squadFill.TextSize = 11
home.squadLeave = button(home.heroCard, 'SquadLeave', 'LEAVE', function() remote:FireServer('squad_leave') end, palette.panelLight)
home.squadLeave.TextSize = 11
arenaUI.squadLayout = { narrow = false, rowH = 34 }

function arenaUI.renderSquad()
  local me = Players.LocalPlayer
  local squad = C.state and C.state.squad or { solo = true, isLeader = true, fill = true,
    members = { { name = me and me.DisplayName or 'You', userId = me and me.UserId or 0, leader = true } } }
  home.heroTitle.Text = 'YOUR SQUAD  ' .. #squad.members .. '/5'
  home.squadFill.Text = squad.public ~= false and '🌐 PUBLIC' or '🔒 PRIVATE'
  home.squadFill.TextColor3 = squad.public ~= false and palette.goldBright or palette.cream
  home.squadLeave.Visible = not squad.solo
  home.heroBtn.Text = squad.isLeader and 'PLAY ▶' or 'LEADER PICKS MODE'
  for _, child in ipairs(home.squadMembers:GetChildren()) do
    if string.sub(child.Name, 1, 7) == 'Member_' then child:Destroy() end
  end
  local layout = arenaUI.squadLayout
  local areaW = home.squadMembers.Size.X.Offset
  for index, member in ipairs(squad.members) do
    local row = frame(home.squadMembers, 'Member_' .. tostring(member.userId), palette.panel, 8)
    row.BackgroundTransparency = 1
    local avatar = make('ImageLabel', row, 'Avatar', { BackgroundColor3 = palette.panelLight, BorderSizePixel = 0,
      Image = 'rbxthumb://type=AvatarHeadShot&id=' .. tostring(member.userId) .. '&w=150&h=150' })
    corner(avatar, 999)
    local isMe = me and member.userId == me.UserId
    local name = label(row, 'Name', (member.leader and '👑 ' or '') .. member.name .. (isMe and ' (you)' or ''), 11, member.leader and palette.goldBright or palette.cream)
    name.Font = Enum.Font.GothamBold
    name.TextWrapped = false
    name.TextTruncate = Enum.TextTruncate.AtEnd
    if layout.narrow then
      local colW = math.floor(areaW / 5)
      rect(row, (index - 1) * colW, 2, colW, 54)
      rect(avatar, (colW - 34) / 2, 2, 34, 34)
      rect(name, 2, 38, colW - 4, 14)
      name.TextSize = 9
      if squad.isLeader and not isMe then
        local kick = make('TextButton', row, 'Kick_' .. tostring(member.userId), { Text = 'X', TextSize = 10, Font = Enum.Font.GothamBold,
          TextColor3 = palette.cream, BackgroundColor3 = palette.darkStroke, BorderSizePixel = 0 })
        corner(kick, 999)
        rect(kick, (colW + 34) / 2 - 10, 0, 16, 16)
        kick.Activated:Connect(function() remote:FireServer('squad_kick', member.userId) end)
      end
    else
      rect(row, 4, 4 + (index - 1) * layout.rowH, areaW - 8, layout.rowH - 4)
      local size = math.min(28, layout.rowH - 6)
      rect(avatar, 2, (layout.rowH - 4 - size) / 2, size, size)
      rect(name, size + 8, 0, areaW - size - 44, layout.rowH - 4)
      name.TextXAlignment = Enum.TextXAlignment.Left
      if squad.isLeader and not isMe then
        local kick = make('TextButton', row, 'Kick_' .. tostring(member.userId), { Text = 'X', TextSize = 12, Font = Enum.Font.GothamBold,
          TextColor3 = palette.muted, BackgroundTransparency = 1, BorderSizePixel = 0 })
        rect(kick, areaW - 36, 0, 24, layout.rowH - 4)
        kick.Activated:Connect(function() remote:FireServer('squad_kick', member.userId) end)
      end
    end
  end
  -- Empty slots invite friends (leaders only; members just see the space).
  local slots = math.min(5, math.max(#squad.members + 1, layout.narrow and 5 or 4))
  for index = #squad.members + 1, slots do
    local slot = make('TextButton', home.squadMembers, 'Member_slot' .. index, { Text = '', BackgroundTransparency = 1, BorderSizePixel = 0, AutoButtonColor = false })
    local ring = frame(slot, 'SlotRing', palette.panel, 999)
    ring.BackgroundTransparency = 0.5
    local ringStroke = outline(ring, palette.panelBorder, 1)
    ringStroke.Transparency = 0.3
    local plus = label(ring, 'Plus', '+', 16, palette.muted)
    plus.Size = UDim2.fromScale(1, 1)
    local hint = label(slot, 'Hint', squad.isLeader and 'Invite a friend' or 'Open slot', 11, palette.muted)
    hint.TextWrapped = false
    if layout.narrow then
      local colW = math.floor(areaW / 5)
      rect(slot, (index - 1) * colW, 2, colW, 54)
      rect(ring, (colW - 34) / 2, 2, 34, 34)
      rect(hint, 2, 38, colW - 4, 14)
      hint.Text = squad.isLeader and 'Invite' or ''
      hint.TextSize = 9
    else
      rect(slot, 4, 4 + (index - 1) * layout.rowH, areaW - 8, layout.rowH - 4)
      local size = math.min(28, layout.rowH - 6)
      rect(ring, 2, (layout.rowH - 4 - size) / 2, size, size)
      rect(hint, size + 8, 0, areaW - size - 12, layout.rowH - 4)
      hint.TextXAlignment = Enum.TextXAlignment.Left
    end
    if squad.isLeader then slot.Activated:Connect(function() arenaUI.openInvites() end) end
  end
end

-- Invite panel: players in this server and online Roblox friends.
arenaUI.inviteShade = button(root, 'InviteShade', '', function() arenaUI.inviteShade.Visible = false end, palette.emeraldDark)
arenaUI.inviteShade.BackgroundTransparency = 0.35
arenaUI.inviteShade.Size = UDim2.fromScale(1, 1)
arenaUI.inviteShade.ZIndex = 85
arenaUI.inviteShade.Visible = false
arenaUI.invitePanel = frame(arenaUI.inviteShade, 'InvitePanel', palette.emeraldDeep, 16)
arenaUI.invitePanel.ZIndex = 86
arenaUI.invitePanel.Active = true
arenaUI.invitePanel.AnchorPoint = Vector2.new(0.5, 0.5)
arenaUI.invitePanel.Position = UDim2.fromScale(0.5, 0.5)
arenaUI.invitePanel.Size = UDim2.new(0.92, 0, 0, 400)
make('UISizeConstraint', arenaUI.invitePanel, 'MaxSize', { MaxSize = Vector2.new(420, 400) })
outline(arenaUI.invitePanel, palette.gold, 1.5)
do
  local title = label(arenaUI.invitePanel, 'Title', 'SQUAD UP', 16, palette.goldBright)
  title.Font = Enum.Font.FredokaOne
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.Position = UDim2.fromOffset(16, 12)
  title.Size = UDim2.new(1, -60, 0, 24)
  title.ZIndex = 87
  local close = make('TextButton', arenaUI.invitePanel, 'CloseInvites', { Text = 'X', TextSize = 14, Font = Enum.Font.GothamBold,
    TextColor3 = palette.muted, BackgroundColor3 = palette.panel, AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 87 })
  corner(close, 999)
  close.Position = UDim2.new(1, -40, 0, 12)
  close.Size = UDim2.fromOffset(26, 26)
  close.Activated:Connect(function() arenaUI.inviteShade.Visible = false end)
end
arenaUI.inviteList = make('ScrollingFrame', arenaUI.invitePanel, 'InviteList', { BackgroundTransparency = 1, BorderSizePixel = 0,
  ScrollBarThickness = 3, ScrollBarImageColor3 = palette.gold, CanvasSize = UDim2.new(), ZIndex = 87 })
arenaUI.inviteList.Position = UDim2.fromOffset(12, 48)
arenaUI.inviteList.Size = UDim2.new(1, -24, 1, -104)
arenaUI.inviteGame = button(arenaUI.invitePanel, 'InviteRobloxFriends', 'INVITE ROBLOX FRIENDS TO THE GAME', function()
  pcall(function() game:GetService('SocialService'):PromptGameInvite(Players.LocalPlayer) end)
end, palette.panelLight)
arenaUI.inviteGame.TextSize = 11
arenaUI.inviteGame.ZIndex = 87
arenaUI.inviteGame.Position = UDim2.new(0, 12, 1, -48)
arenaUI.inviteGame.Size = UDim2.new(1, -24, 0, 36)

function arenaUI.renderInviteList(friends)
  for _, child in ipairs(arenaUI.inviteList:GetChildren()) do child:Destroy() end
  local y = 0
  local function heading(text)
    local h = label(arenaUI.inviteList, 'Heading', text, 10, palette.muted)
    h.Font = Enum.Font.GothamBlack
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.ZIndex = 88
    h.Position = UDim2.fromOffset(4, y)
    h.Size = UDim2.new(1, -8, 0, 18)
    y = y + 22
  end
  local function row(name, userId, status, action)
    local entry = frame(arenaUI.inviteList, 'Row_' .. tostring(userId), palette.panel, 10)
    entry.ZIndex = 88
    entry.Position = UDim2.fromOffset(0, y)
    entry.Size = UDim2.new(1, -6, 0, 40)
    local avatar = make('ImageLabel', entry, 'Avatar', { BackgroundColor3 = palette.panelLight, BorderSizePixel = 0, ZIndex = 89,
      Image = 'rbxthumb://type=AvatarHeadShot&id=' .. tostring(userId) .. '&w=150&h=150' })
    corner(avatar, 999)
    avatar.Position = UDim2.fromOffset(6, 6)
    avatar.Size = UDim2.fromOffset(28, 28)
    local text = label(entry, 'Name', name, 12, palette.cream)
    text.Font = Enum.Font.GothamBold
    text.TextXAlignment = Enum.TextXAlignment.Left
    text.TextTruncate = Enum.TextTruncate.AtEnd
    text.ZIndex = 89
    text.Position = UDim2.fromOffset(42, 0)
    text.Size = UDim2.new(1, -150, 1, 0)
    local control = button(entry, 'Invite_' .. tostring(userId), status, action or function() end, action and palette.gold or palette.panelLight)
    control.TextSize = 10
    control.ZIndex = 89
    control.Position = UDim2.new(1, -104, 0, 6)
    control.Size = UDim2.fromOffset(96, 28)
    y = y + 46
  end
  local open = C.state and C.state.openSquads or {}
  if #open > 0 then
    heading('JOIN A PUBLIC SQUAD')
    for _, squad in ipairs(open) do
      row(squad.leaderName .. "'s squad  ·  " .. squad.size .. '/5' .. (squad.playing and '  · playing' or ''), squad.leaderId, 'JOIN',
        function() remote:FireServer('squad_join', squad.leaderId); arenaUI.inviteShade.Visible = false end)
    end
  end
  heading('INVITE PLAYERS HERE')
  local lobby = C.state and C.state.lobby or {}
  if #lobby == 0 then
    local empty = label(arenaUI.inviteList, 'Empty', 'Nobody else is here yet.', 11, palette.muted)
    empty.ZIndex = 88
    empty.Position = UDim2.fromOffset(4, y)
    empty.Size = UDim2.new(1, -8, 0, 20)
    y = y + 26
  end
  for _, other in ipairs(lobby) do
    local leading = not (C.state and C.state.squad) or C.state.squad.isLeader
    if other.inSquad then row(other.name, other.userId, 'IN SQUAD', nil)
    elseif leading then row(other.name, other.userId, 'INVITE', function() remote:FireServer('squad_invite', other.userId) end)
    else row(other.name, other.userId, 'LEADER INVITES', nil) end
  end
  if friends and #friends > 0 then
    heading('ONLINE FRIENDS')
    for _, friend in ipairs(friends) do
      local playingTractor = friend.PlaceId == game.PlaceId
      row(friend.DisplayName or friend.UserName or 'Friend', friend.VisitorId, playingTractor and 'INVITE' or 'NOT PLAYING',
        playingTractor and function() remote:FireServer('squad_invite', friend.VisitorId) end or nil)
    end
  end
  arenaUI.inviteList.CanvasSize = UDim2.fromOffset(0, y)
end

function arenaUI.openInvites()
  arenaUI.renderInviteList(nil)
  arenaUI.inviteShade.Visible = true
  -- Online friends come from a web call; fill them in when it returns.
  task.spawn(function()
    local ok, friends = pcall(function() return Players.LocalPlayer:GetFriendsOnline(30) end)
    if ok and type(friends) == 'table' and arenaUI.inviteShade.Visible then arenaUI.renderInviteList(friends) end
  end)
end

-- Incoming invite pop-up (top of the screen).
arenaUI.invitePopup = frame(root, 'InvitePopup', palette.panel, 14)
arenaUI.invitePopup.ZIndex = 95
arenaUI.invitePopup.Visible = false
outline(arenaUI.invitePopup, palette.gold, 1.5)
arenaUI.invitePopupText = label(arenaUI.invitePopup, 'Text', '', 12, palette.cream)
arenaUI.invitePopupText.Font = Enum.Font.GothamBold
arenaUI.invitePopupText.TextXAlignment = Enum.TextXAlignment.Left
arenaUI.invitePopupText.ZIndex = 96
arenaUI.invitePopupText.Position = UDim2.fromOffset(14, 0)
arenaUI.invitePopupText.Size = UDim2.new(1, -150, 1, 0)
arenaUI.inviteAccept = button(arenaUI.invitePopup, 'AcceptInvite', 'JOIN', function()
  local invite = C.state and C.state.invites and C.state.invites[1]
  if invite then remote:FireServer('squad_accept', invite.fromId) end
  arenaUI.invitePopup.Visible = false
end)
arenaUI.inviteAccept.TextSize = 12
arenaUI.inviteAccept.ZIndex = 96
arenaUI.inviteAccept.Position = UDim2.new(1, -132, 0, 10)
arenaUI.inviteAccept.Size = UDim2.fromOffset(76, 34)
arenaUI.inviteDecline = button(arenaUI.invitePopup, 'DeclineInvite', 'X', function()
  local invite = C.state and C.state.invites and C.state.invites[1]
  if invite then remote:FireServer('squad_decline', invite.fromId) end
  arenaUI.invitePopup.Visible = false
end, palette.panelLight)
arenaUI.inviteDecline.TextSize = 12
arenaUI.inviteDecline.ZIndex = 96
arenaUI.inviteDecline.Position = UDim2.new(1, -48, 0, 10)
arenaUI.inviteDecline.Size = UDim2.fromOffset(36, 34)

function arenaUI.renderInvites()
  local invite = C.state and C.state.invites and C.state.invites[1]
  arenaUI.invitePopup.Visible = invite ~= nil
  if invite then arenaUI.invitePopupText.Text = '👥 ' .. invite.fromName .. ' invited you to their squad' end
end

-- Matchmaking status: a slim bar you can browse under, with Cancel.
arenaUI.searchBar = frame(root, 'SearchBar', palette.emeraldDeep, 999)
arenaUI.searchBar.ZIndex = 94
arenaUI.searchBar.Visible = false
outline(arenaUI.searchBar, palette.gold, 1.5)
arenaUI.searchText = label(arenaUI.searchBar, 'Text', '', 12, palette.goldBright)
arenaUI.searchText.Font = Enum.Font.GothamBold
arenaUI.searchText.ZIndex = 95
arenaUI.searchText.TextXAlignment = Enum.TextXAlignment.Left
arenaUI.searchText.Position = UDim2.fromOffset(18, 0)
arenaUI.searchText.Size = UDim2.new(1, -110, 1, 0)
arenaUI.searchCancel = button(arenaUI.searchBar, 'CancelSearch', 'CANCEL', function() remote:FireServer('cancel_queue') end, palette.panelLight)
arenaUI.searchCancel.TextSize = 11
arenaUI.searchCancel.ZIndex = 95
arenaUI.searchCancel.Position = UDim2.new(1, -88, 0, 5)
arenaUI.searchCancel.Size = UDim2.fromOffset(80, 28)

function arenaUI.renderSearch()
  local search = C.state and C.state.search
  arenaUI.searchBar.Visible = search ~= nil
  if not search then return end
  local elapsed = math.max(0, math.floor((C.state.serverTime or 0) + os.clock() - C.receivedAt - (search.startedAt or 0)))
  local tierName = string.upper(search.tier or 'novice')
  if arenaUI.compactSearch then
    arenaUI.searchText.Text = string.format('🔍 %d:%02d · %dP %s', math.floor(elapsed / 60), elapsed % 60, search.playerCount or 4, tierName)
      .. ((search.squadSize or 1) > 1 and (' · SQUAD ' .. search.squadSize) or '')
  else
    arenaUI.searchText.Text = string.format('🔍 SEARCHING  %d:%02d  ·  %dP %s', math.floor(elapsed / 60), elapsed % 60, search.playerCount or 4, tierName)
      .. ((search.squadSize or 1) > 1 and ('  ·  SQUAD OF ' .. search.squadSize) or '')
  end
end

-- ==========================================================
-- 2. MODE TIER SCREEN (FORMAT: 1251.jpg)
-- ==========================================================
local tier = {} C.tier = tier
arenaUI.tier = tier
function arenaUI.initTierScreen()
  tier.view = frame(root, 'TierScreen', palette.emeraldDeep, 20)
  tier.view.BackgroundTransparency = 0.05
  tier.view.ZIndex = 25
  tier.view.Visible = false
  outline(tier.view, palette.railOuter, 1.8)

-- TOP BAR (1251.jpg Top Bar)
tier.header = frame(tier.view, 'TierHeader', palette.panel, 14)
tier.header.BackgroundTransparency = 0.4
outline(tier.header, palette.panelBorder, 1)

tier.backBtn = button(tier.header, 'BackBtn', '⬅ LOBBY', function()
  C.lobbyMode = 'home'
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.updateAction()
  C.render()
end, palette.panelLight)
tier.backBtn.TextSize = 12

tier.rulesBtn = button(tier.header, 'RulesBtn', '?', function()
  if C.openRulesModal then C.openRulesModal() end
end, palette.panelLight)
tier.rulesBtn.TextSize = 13

tier.title = label(tier.header, 'Title', '3 DECKS · 6 PLAYERS', 15, palette.gold)
tier.title.Font = Enum.Font.FredokaOne

-- Quick Match settles after one round; Full Match plays rounds until a team
-- passes Ace.
arenaUI.fullMatch = false
tier.matchLength = button(tier.header, 'MatchLength', 'QUICK · 1 ROUND', function()
  arenaUI.fullMatch = not arenaUI.fullMatch
  tier.matchLength.Text = arenaUI.fullMatch and 'FULL MATCH · TO ACE' or 'QUICK · 1 ROUND'
  tier.matchLength.BackgroundColor3 = arenaUI.fullMatch and palette.gold or palette.panelLight
  tier.matchLength.TextColor3 = arenaUI.fullMatch and palette.ink or palette.white
end, palette.panelLight)
tier.matchLength.TextSize = 11

tier.coinPill = frame(tier.header, 'CoinPill', palette.tileBg, 999)
outline(tier.coinPill, palette.gold, 1)
local tierCoinDot = frame(tier.coinPill, 'Dot', palette.goldBright, 999)
tierCoinDot.Size = UDim2.fromOffset(14, 14)
tierCoinDot.Position = UDim2.fromOffset(6, 7)
local tierCoinDotTxt = label(tierCoinDot, 'Sym', '$', 9, palette.ink)
tierCoinDotTxt.Size = UDim2.fromScale(1, 1)
tierCoinDotTxt.Font = Enum.Font.GothamBlack
tier.coinText = label(tier.coinPill, 'Text', '3K', 12, palette.goldBright)
tier.coinText.Font = Enum.Font.FredokaOne
tier.coinText.Size = UDim2.new(1, -26, 1, 0)
tier.coinText.Position = UDim2.fromOffset(24, 0)
tier.coinText.TextXAlignment = Enum.TextXAlignment.Left

-- LEFT SIDEBAR TABS (1251.jpg Mode Switcher)
tier.sidebar = frame(tier.view, 'TierSidebar', palette.panel, 14)
tier.sidebar.BackgroundTransparency = 0.5
outline(tier.sidebar, palette.panelBorder, 1)

tier.tab6P = button(tier.sidebar, 'Tab6P', '3 DECKS (6P)', function()
  C.setupPlayerCount = 6
  C.updateAction(); C.render()
end, palette.panelLight)
tier.tab6P.TextSize = 10

tier.tab8P = button(tier.sidebar, 'Tab8P', '4 DECKS (8P)', function()
  C.setupPlayerCount = 8
  C.updateAction(); C.render()
end, palette.panelLight)
tier.tab8P.TextSize = 10

tier.tab4P = button(tier.sidebar, 'Tab4P', 'CLASSIC (4P)', function()
  C.setupPlayerCount = 4
  C.updateAction(); C.render()
end, palette.panelLight)
tier.tab4P.TextSize = 10

tier.tab10P = button(tier.sidebar, 'Tab10P', '5 DECKS (10P)', function()
  C.setupPlayerCount = 10
  C.updateAction(); C.render()
end, palette.panelLight)
tier.tab10P.TextSize = 10

tier.tabs = {
  [4] = tier.tab4P,
  [6] = tier.tab6P,
  [8] = tier.tab8P,
  [10] = tier.tab10P,
}

-- 3 TIER ROOM CARDS (1251.jpg Center Cards)
-- Tier 1: Novice Table (新手场)
tier.cardNovice = frame(tier.view, 'CardNovice', palette.tileBg, 16)
outline(tier.cardNovice, palette.panelBorder, 1.5)
gradient(tier.cardNovice, color(24, 85, 58), color(14, 46, 32), 90)

local noviceBanner = frame(tier.cardNovice, 'Banner', color(30, 115, 175), 10)
local noviceBannerText = label(noviceBanner, 'Text', '🌱 NOVICE TABLE', 14, palette.cream)
noviceBannerText.Font = Enum.Font.FredokaOne
noviceBannerText.Size = UDim2.fromScale(1, 1)

createChipStack(tier.cardNovice, 3, color(45, 175, 100), palette.gold)

local noviceStakePill = frame(tier.cardNovice, 'StakePill', color(16, 52, 36), 8)
label(noviceStakePill, 'Tag', 'BASE', 9, palette.muted)
local noviceStakeVal = label(noviceStakePill, 'Val', '500', 20, palette.goldBright)
noviceStakeVal.Font = Enum.Font.FredokaOne

label(tier.cardNovice, 'Entry', 'Entry 2K – 60K', 12, palette.sage)

local noviceJoinBtn = button(tier.cardNovice, 'JoinBtn', 'PLAY NOVICE ▶', function()
  if C.openQueue then C.openQueue('novice') else remote:FireServer('queue', { playerCount = C.setupPlayerCount, tier = 'novice', fullMatch = arenaUI.fullMatch }) end
end)
noviceJoinBtn.TextSize = 13
tier.noviceJoinBtn = noviceJoinBtn

-- Tier 2: Pro Lounge (进阶场)
tier.cardPro = frame(tier.view, 'CardPro', palette.tileBg, 16)
outline(tier.cardPro, palette.gold, 1.8)
gradient(tier.cardPro, color(32, 105, 80), color(16, 52, 36), 90)

local proBanner = frame(tier.cardPro, 'Banner', color(40, 130, 205), 10)
local proBannerText = label(proBanner, 'Text', '💎 PRO LOUNGE', 14, palette.cream)
proBannerText.Font = Enum.Font.FredokaOne
proBannerText.Size = UDim2.fromScale(1, 1)

createChipStack(tier.cardPro, 6, color(35, 140, 230), palette.goldBright)

local proStakePill = frame(tier.cardPro, 'StakePill', color(16, 52, 36), 8)
label(proStakePill, 'Tag', 'BASE', 9, palette.muted)
local proStakeVal = label(proStakePill, 'Val', '1.5K', 20, palette.goldBright)
proStakeVal.Font = Enum.Font.FredokaOne

label(tier.cardPro, 'Entry', 'Entry 8K – 200K', 12, palette.gold)

-- Padlock & Progress Bar for Pro Tier
local proLock = frame(tier.cardPro, 'LockOverlay', color(14, 26, 20), 16)
proLock.BackgroundTransparency = 0.15
proLock.ZIndex = 8
proLock.Visible = false
local proLockIcon = label(proLock, 'Icon', '🔒', 16, palette.goldBright)
proLockIcon.Position = UDim2.fromOffset(6, 0)
proLockIcon.Size = UDim2.new(0, 22, 1, 0)
local proBar = frame(proLock, 'Bar', color(12, 36, 24), 6)
proBar.Position = UDim2.new(0, 32, 0.5, -11)
proBar.Size = UDim2.new(1, -40, 0, 22)
outline(proBar, palette.goldDark, 1.2)
local proFill = frame(proBar, 'Fill', palette.gold, 6)
proFill.Size = UDim2.new(0.375, 0, 1, 0)
local proBarText = label(proBar, 'Text', '3K / 8K', 11, palette.cream)
proBarText.Size = UDim2.fromScale(1, 1)
proBarText.TextStrokeTransparency = 0.3
proBarText.TextStrokeColor3 = palette.darkStroke

local proJoinBtn = button(tier.cardPro, 'JoinBtn', 'PLAY PRO ▶', function()
  if C.openQueue then C.openQueue('pro') else remote:FireServer('queue', { playerCount = C.setupPlayerCount, tier = 'pro', fullMatch = arenaUI.fullMatch }) end
end)
proJoinBtn.TextSize = 13
tier.proJoinBtn = proJoinBtn

-- Tier 3: Master Arena (高手场 - 天命)
tier.cardMaster = frame(tier.view, 'CardMaster', palette.tileBg, 16)
outline(tier.cardMaster, color(230, 80, 80), 1.8)
gradient(tier.cardMaster, color(65, 24, 48), color(24, 12, 28), 90)

local masterBanner = frame(tier.cardMaster, 'Banner', color(175, 45, 140), 10)
local masterBannerText = label(masterBanner, 'Text', '👑 MASTER ARENA', 14, palette.cream)
masterBannerText.Font = Enum.Font.FredokaOne
masterBannerText.Size = UDim2.fromScale(1, 1)

createChipStack(tier.cardMaster, 10, color(205, 38, 65), palette.goldBright)

local masterBadge = frame(tier.cardMaster, 'Badge', color(225, 45, 45), 6)
local masterBadgeText = label(masterBadge, 'Text', '★ ELITE', 9, palette.cream)
masterBadgeText.Font = Enum.Font.FredokaOne
masterBadgeText.Size = UDim2.fromScale(1, 1)

local masterStakePill = frame(tier.cardMaster, 'StakePill', color(28, 14, 32), 8)
label(masterStakePill, 'Tag', 'BASE', 9, palette.muted)
local masterStakeVal = label(masterStakePill, 'Val', '5K', 20, palette.goldBright)
masterStakeVal.Font = Enum.Font.FredokaOne

label(tier.cardMaster, 'Entry', 'Entry 100K+', 12, palette.goldBright)

-- Padlock & Progress Bar for Master Tier
local masterLock = frame(tier.cardMaster, 'LockOverlay', color(18, 14, 24), 16)
masterLock.BackgroundTransparency = 0.15
masterLock.ZIndex = 8
masterLock.Visible = false
local masterLockIcon = label(masterLock, 'Icon', '🔒', 16, palette.goldBright)
masterLockIcon.Position = UDim2.fromOffset(6, 0)
masterLockIcon.Size = UDim2.new(0, 22, 1, 0)
local masterBar = frame(masterLock, 'Bar', color(24, 12, 28), 6)
masterBar.Position = UDim2.new(0, 32, 0.5, -11)
masterBar.Size = UDim2.new(1, -40, 0, 22)
outline(masterBar, palette.goldDark, 1.2)
local masterFill = frame(masterBar, 'Fill', palette.gold, 6)
masterFill.Size = UDim2.new(0.03, 0, 1, 0)
local masterBarText = label(masterBar, 'Text', '3K / 100K', 11, palette.cream)
masterBarText.Size = UDim2.fromScale(1, 1)
masterBarText.TextStrokeTransparency = 0.3
masterBarText.TextStrokeColor3 = palette.darkStroke

local masterJoinBtn = button(tier.cardMaster, 'JoinBtn', 'PLAY MASTER ▶', function()
  if C.openQueue then C.openQueue('master') else remote:FireServer('queue', { playerCount = C.setupPlayerCount, tier = 'master', fullMatch = arenaUI.fullMatch }) end
end)
masterJoinBtn.TextSize = 13
tier.masterJoinBtn = masterJoinBtn

for _, card in ipairs({ tier.cardNovice, tier.cardPro, tier.cardMaster }) do
  local best = frame(card, 'BestBadge', palette.gold, 6)
  best.ZIndex = 9
  best.Visible = false
  local bestText = label(best, 'Text', 'BEST FOR YOU', 9, palette.ink)
  bestText.Font = Enum.Font.GothamBlack
  bestText.TextWrapped = false
  bestText.Size = UDim2.fromScale(1, 1)
  bestText.ZIndex = 10
end

C.refreshTierLocks = function()
  local coins = (C.state and C.state.coins) or 3000
  -- The richest table you can sit at is the suggested one.
  local bestCard = coins >= 100000 and tier.cardMaster or (coins >= 8000 and tier.cardPro or tier.cardNovice)
  for _, card in ipairs({ tier.cardNovice, tier.cardPro, tier.cardMaster }) do
    card.BestBadge.Visible = card == bestCard
  end
  local proLocked = coins < 8000
  if tier and tier.cardPro then
    local pLock = tier.cardPro:FindFirstChild('LockOverlay')
    if pLock then
      pLock.Visible = proLocked
      local bar = pLock:FindFirstChild('Bar')
      if bar then
        local fill = bar:FindFirstChild('Fill')
        if fill then fill.Size = UDim2.new(math.clamp(coins / 8000, 0, 1), 0, 1, 0) end
        local txt = bar:FindFirstChild('Text')
        local short = C.currentLayout and (C.currentLayout.width < 600 or C.currentLayout.short)
        if txt then txt.Text = 'Need ' .. formatK(math.max(0, 8000 - coins)) .. ' more' .. (short and '' or ('  ·  ' .. formatK(coins) .. ' / 8K')) end
      end
    end
    if tier.proJoinBtn then
      local grad = tier.proJoinBtn:FindFirstChild('Gradient')
      if grad then grad.Enabled = not proLocked end
      tier.proJoinBtn.Text = proLocked and '🔒 LOCKED' or 'PLAY PRO ▶'
      tier.proJoinBtn.BackgroundColor3 = proLocked and palette.panelLight or palette.gold
      tier.proJoinBtn.TextColor3 = proLocked and palette.white or palette.ink
    end
  end

  local masterLocked = coins < 100000
  if tier and tier.cardMaster then
    local mLock = tier.cardMaster:FindFirstChild('LockOverlay')
    if mLock then
      mLock.Visible = masterLocked
      local bar = mLock:FindFirstChild('Bar')
      if bar then
        local fill = bar:FindFirstChild('Fill')
        if fill then fill.Size = UDim2.new(math.clamp(coins / 100000, 0, 1), 0, 1, 0) end
        local txt = bar:FindFirstChild('Text')
        local short = C.currentLayout and (C.currentLayout.width < 600 or C.currentLayout.short)
        if txt then txt.Text = 'Need ' .. formatK(math.max(0, 100000 - coins)) .. ' more' .. (short and '' or ('  ·  ' .. formatK(coins) .. ' / 100K')) end
      end
    end
    if tier.masterJoinBtn then
      local grad = tier.masterJoinBtn:FindFirstChild('Gradient')
      if grad then grad.Enabled = not masterLocked end
      tier.masterJoinBtn.Text = masterLocked and '🔒 LOCKED' or 'PLAY MASTER ▶'
      tier.masterJoinBtn.BackgroundColor3 = masterLocked and palette.panelLight or palette.gold
      tier.masterJoinBtn.TextColor3 = masterLocked and palette.white or palette.ink
    end
  end
end
C.refreshTierLocks()

-- TIER BOTTOM BAR (1251.jpg Bottom)
tier.bottomBar = frame(tier.view, 'TierBottomBar', palette.panel, 14)
tier.bottomBar.BackgroundTransparency = 0.4
outline(tier.bottomBar, palette.panelBorder, 1)

tier.bottomTip = label(tier.bottomBar, 'Tip', '💡 Tip: Base stakes determine round settlement bonus coins and level climb acceleration.', 11, palette.sage)

-- Play with friends from the lobby: a private Novice table with a join code
-- (pick its size first), or join one by code.
tier.privatePicker = frame(home.view, 'PrivatePicker', palette.panel, 12)
tier.privatePicker.Visible = false
tier.privatePicker.ZIndex = 30
outline(tier.privatePicker, palette.gold, 1.5)
local pickerTitle = label(tier.privatePicker, 'Title', 'PRIVATE TABLE SIZE', 11, palette.goldBright)
pickerTitle.Font = Enum.Font.GothamBlack
pickerTitle.ZIndex = 31
rect(pickerTitle, 0, 6, 300, 18)
for index, count in ipairs({ 4, 6, 8, 10 }) do
  local option = button(tier.privatePicker, 'Private' .. count, count .. 'P', function()
    tier.privatePicker.Visible = false
    remote:FireServer('create_private', { playerCount = count, tier = 'novice', fullMatch = arenaUI.fullMatch })
  end)
  option.TextSize = 13
  option.ZIndex = 31
  rect(option, 10 + (index - 1) * 72, 28, 64, 34)
end
tier.createPrivate = button(home.bottomBar, 'CreatePrivate', 'CREATE PRIVATE', function()
  tier.privatePicker.Visible = not tier.privatePicker.Visible
end)
tier.createPrivate.TextSize = 12
tier.codeBox = make('TextBox', home.bottomBar, 'CodeBox', { Text = '', PlaceholderText = 'CODE', TextSize = 14,
  Font = Enum.Font.GothamBold, TextColor3 = palette.cream, PlaceholderColor3 = palette.muted, BackgroundColor3 = palette.emeraldDark,
  BorderSizePixel = 0, ClearTextOnFocus = false })
corner(tier.codeBox, 8)
outline(tier.codeBox, palette.panelBorder, 1)
tier.joinCode = button(home.bottomBar, 'JoinCode', 'JOIN', function()
  local code = string.upper(tier.codeBox.Text or ''):gsub('[^%w]', '')
  if #code ~= 4 then notice.Text = 'Enter the 4-character table code.' return end
  remote:FireServer('join_code', code)
end, palette.panelLight)
tier.joinCode.TextSize = 12
tier.bottomTip.TextXAlignment = Enum.TextXAlignment.Left

end
arenaUI.initTierScreen()
end
