-- Happy Tractor client, part 2/14: Arena.
-- Lines 427-969 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local arena, arenaUI, button, color, corner, formatK, frame, gradient = C.arena, C.arenaUI, C.button, C.color, C.corner, C.formatK, C.frame, C.gradient
local label, make, outline, palette, playSound, root, tween, wallet = C.label, C.make, C.outline, C.palette, C.playSound, C.root, C.tween, C.wallet

-- Richer felt texture with a vignette
local arenaVignette = frame(arena, 'Vignette', color(10, 42, 26), 84) C.arenaVignette = arenaVignette
arenaVignette.BackgroundTransparency = 0.88
arenaVignette.Size = UDim2.fromScale(1, 1)
arenaVignette.ZIndex = 1
outline(arenaVignette, color(12, 48, 28), 12).Transparency = 0.65

for index, spec in ipairs({ { 0.86, 0.9, 0.955 }, { 0.62, 0.7, 0.955 }, { 0.38, 0.46, 0.96 } }) do
  local spot = frame(arena, 'FeltSpot' .. index, color(255, 255, 240), 999)
  spot.AnchorPoint = Vector2.new(0.5, 0.5)
  spot.Position = UDim2.fromScale(0.5, 0.48)
  spot.Size = UDim2.fromScale(spec[1], spec[2])
  spot.BackgroundTransparency = spec[3]
  spot.ZIndex = 1
end
for index, rotation in ipairs({ 0, 90 }) do
  local edge = frame(arena, 'FeltEdge' .. index, color(4, 20, 12)) -- one UICorner only (pill)
  edge.Size = UDim2.fromScale(1, 1)
  edge.ZIndex = 1
  make('UICorner', edge, 'Corner', { CornerRadius = UDim.new(0.5, 0) })
  make('UIGradient', edge, 'Gradient', { Rotation = rotation, Transparency = NumberSequence.new({
    NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(0.16, 1),
    NumberSequenceKeypoint.new(0.84, 1), NumberSequenceKeypoint.new(1, 0.55),
  }) })
end

local inner = frame(arena, 'InnerRail', palette.feltBottom, 82) C.inner = inner
inner.BackgroundTransparency = 1
inner.Position = UDim2.new(0, 10, 0, 10)
inner.Size = UDim2.new(1, -20, 1, -20)
arenaUI.innerRailStroke = outline(inner, palette.railInner, 1.5)

-- Center Logo or Trump Display in the middle of the table
local centerMedallion = frame(arena, 'CenterMedallion', palette.feltBottom, 999) C.centerMedallion = centerMedallion
centerMedallion.BackgroundTransparency = 0.40
centerMedallion.Size = UDim2.fromOffset(136, 136)
centerMedallion.AnchorPoint = Vector2.new(0.5, 0.5)
centerMedallion.Position = UDim2.fromScale(0.5, 0.46)
centerMedallion.ZIndex = 2
outline(centerMedallion, palette.railOuter, 2.0)
gradient(centerMedallion, palette.feltTop, palette.feltBottom, 90)

arenaUI.centerSuits = label(centerMedallion, 'Suits', '♠  ♥  ♦  ♣', 16, palette.gold)
arenaUI.centerSuits.TextTransparency = 0.35
arenaUI.centerSuits.Size = UDim2.new(1, 0, 0, 24)
arenaUI.centerSuits.Position = UDim2.fromScale(0, 0.12)

local centerTrumpDisplay = label(centerMedallion, 'TrumpVal', '♠ 2', 26, palette.goldBright) C.centerTrumpDisplay = centerTrumpDisplay
centerTrumpDisplay.Font = Enum.Font.FredokaOne
centerTrumpDisplay.Size = UDim2.new(1, 0, 0, 36)
centerTrumpDisplay.Position = UDim2.fromScale(0, 0.38)
centerTrumpDisplay.TextStrokeTransparency = 0.20
centerTrumpDisplay.TextStrokeColor3 = palette.darkStroke

arenaUI.centerTag = label(centerMedallion, 'Tag', 'TRUMP', 10, palette.gold)
arenaUI.centerTag.Font = Enum.Font.FredokaOne
arenaUI.centerTag.Size = UDim2.new(1, 0, 0, 18)
arenaUI.centerTag.Position = UDim2.fromScale(0, 0.76)

local wordmark = label(arena, 'Wordmark', '', 42, color(85, 205, 135)) C.wordmark = wordmark
wordmark.Visible = false
arenaUI.wordmarkSub = label(arena, 'WordmarkSub', '', 11, color(110, 225, 155))
arenaUI.wordmarkSub.Visible = false

-- Authentic Kuaile Shengji Table Placards (Matchup Level Placard & Defender Points Meter)
local matchupPlacard = frame(arena, 'MatchupPlacard', palette.panel, 12) C.matchupPlacard = matchupPlacard
-- The placard is a transparent HUD group; only its two inner pills carry the
-- fill/stroke so it reads as one intentional control instead of a pasted box.
matchupPlacard.BackgroundTransparency = 1
matchupPlacard.Visible = false
matchupPlacard.Parent = root
matchupPlacard.ZIndex = 30
local matchupOutline = outline(matchupPlacard, palette.railOuter, 1.5)
matchupOutline.Enabled = false

local trumpGem = frame(matchupPlacard, 'TrumpGem', palette.emeraldDark, 8) C.trumpGem = trumpGem
outline(trumpGem, palette.gold, 1)
arenaUI.trumpTag = label(trumpGem, 'Tag', 'TRUMP', 8, palette.white)
arenaUI.trumpTag.Font = Enum.Font.GothamBold
local trumpSuit = label(trumpGem, 'Suit', '♠ 2', 18, palette.goldBright) C.trumpSuit = trumpSuit
trumpSuit.Font = Enum.Font.FredokaOne
trumpSuit.TextStrokeTransparency = 0.65
trumpSuit.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

-- Current Points & Goal Section inside Top-Left Placard (Refined Top-Left HUD)
arenaUI.goalBox = frame(matchupPlacard, 'PointsBox', color(18, 52, 34), 8)
outline(arenaUI.goalBox, palette.panelBorder, 1)

arenaUI.goalTitle = label(arenaUI.goalBox, 'Title', 'DEFENDER POINTS', 9, palette.white)
arenaUI.goalTitle.Font = Enum.Font.GothamBold

arenaUI.goalVal = label(arenaUI.goalBox, 'Val', '0 / 80', 14, palette.white)
arenaUI.goalVal.Font = Enum.Font.FredokaOne
arenaUI.goalVal.TextStrokeTransparency = 0.65
arenaUI.goalVal.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

arenaUI.goalBar = frame(arenaUI.goalBox, 'Bar', palette.meterBg, 4)
outline(arenaUI.goalBar, palette.panelBorder, 1)
arenaUI.goalBarFill = frame(arenaUI.goalBar, 'Fill', palette.gold, 4)
arenaUI.goalBarFillGrad = gradient(arenaUI.goalBarFill, palette.goldBright, palette.goldDark, 0)
arenaUI.goalTick40 = frame(arenaUI.goalBar, 'Tick40', color(255, 255, 255), 0)
arenaUI.goalTick40.BackgroundTransparency = 0.4

arenaUI.goalStatus = label(arenaUI.goalBox, 'Status', 'TOTAL SHUTOUT (+3 LV)', 8, palette.goldBright)
arenaUI.goalStatus.Font = Enum.Font.GothamBold

-- Current stake multiplier: every Chao Di doubles it, scaling trick coins and
-- the round payout.
arenaUI.stakePill = frame(matchupPlacard, 'StakePill', color(18, 52, 34), 8)
arenaUI.stakeTag = label(arenaUI.stakePill, 'Tag', 'STAKE', 8, palette.muted)
arenaUI.stakeTag.Font = Enum.Font.GothamBold
arenaUI.stakeVal = label(arenaUI.stakePill, 'Val', '×1', 15, palette.white)
arenaUI.stakeVal.Font = Enum.Font.GothamBlack
arenaUI.stakeOutline = outline(arenaUI.stakePill, palette.panelBorder, 1)

-- Hidden Top-Right placard stub for backwards compatibility
local defenderMeterPlacard = frame(arena, 'DefenderMeterPlacard', palette.panel, 12) C.defenderMeterPlacard = defenderMeterPlacard
defenderMeterPlacard.Visible = false
local meterVal = label(defenderMeterPlacard, 'Val', '', 1, palette.cream) C.meterVal = meterVal
local meterBar = frame(defenderMeterPlacard, 'Bar', palette.meterBg, 1)
local meterBarFill = frame(meterBar, 'Fill', palette.gold, 1) C.meterBarFill = meterBarFill
local meterStatus = label(defenderMeterPlacard, 'Status', '', 1, palette.goldBright) C.meterStatus = meterStatus

-- Center Table Deck for Sequential Dealing Animation
local centerDeck = frame(arena, 'CenterDeck', palette.panel, 8) C.centerDeck = centerDeck
centerDeck.BackgroundTransparency = 1
centerDeck.Visible = false
centerDeck.ZIndex = 12


arenaUI.centerDeckCards = frame(centerDeck, 'DeckCards')
arenaUI.centerDeckCards.BackgroundTransparency = 1
arenaUI.centerDeckCards.Size = UDim2.fromScale(1, 1)
arenaUI.centerDeckBadge = frame(centerDeck, 'Badge', palette.tileBg, 6)
outline(arenaUI.centerDeckBadge, palette.gold, 1)
C.centerDeckText = label(arenaUI.centerDeckBadge, 'Text', 'DEALING', 10, palette.white)
C.centerDeckText.Font = Enum.Font.GothamBold
C.centerDeckText.Size = UDim2.fromScale(1, 1)

local score = label(root, 'Score', 'YOUR TEAM   0     ·     0   OPPONENTS', 12, palette.white) C.score = score
score.Font = Enum.Font.GothamBold
local trump = label(root, 'Trump', 'TRUMP  —', 12, palette.gold) C.trump = trump
trump.Font = Enum.Font.GothamBold

local trickLabel = label(arena, 'TrickLabel', '', 12, palette.white) C.trickLabel = trickLabel
trickLabel.Visible = false
local playLayer = frame(arena, 'PlayedCards') C.playLayer = playLayer
-- Lets players look back at the previous trick without opening History.
arenaUI.peekLast = false
arenaUI.peekButton = button(arena, 'PeekLastTrick', '◀ LAST TRICK', function()
  arenaUI.peekLast = not arenaUI.peekLast
  C.render()
end, palette.panelLight)
arenaUI.peekButton.TextSize = 11
arenaUI.peekButton.ZIndex = 25
arenaUI.peekButton.Visible = false
arenaUI.seenPlays = {}

-- Explains, once per session, why progress is not being saved.
arenaUI.saveShade = button(root, 'SaveWarningShade', '', function() end, palette.emeraldDark)
arenaUI.saveShade.BackgroundTransparency = 0.35
arenaUI.saveShade.Size = UDim2.fromScale(1, 1)
arenaUI.saveShade.ZIndex = 90
arenaUI.saveShade.Visible = false
arenaUI.saveModal = frame(arenaUI.saveShade, 'SaveWarning', palette.panel, 14)
arenaUI.saveModal.ZIndex = 91
arenaUI.saveModal.AnchorPoint = Vector2.new(0.5, 0.5)
arenaUI.saveModal.Position = UDim2.fromScale(0.5, 0.5)
arenaUI.saveModal.Size = UDim2.fromOffset(360, 210)
outline(arenaUI.saveModal, palette.gold, 2)
arenaUI.saveTitle = label(arenaUI.saveModal, 'Title', '⚠ PROGRESS IS NOT BEING SAVED', 15, palette.goldBright)
arenaUI.saveTitle.Font = Enum.Font.FredokaOne
arenaUI.saveTitle.ZIndex = 92
arenaUI.saveTitle.Position = UDim2.fromOffset(16, 14)
arenaUI.saveTitle.Size = UDim2.new(1, -32, 0, 22)
arenaUI.saveReason = label(arenaUI.saveModal, 'Reason', '', 12, palette.cream)
arenaUI.saveReason.ZIndex = 92
arenaUI.saveReason.Position = UDim2.fromOffset(16, 44)
arenaUI.saveReason.Size = UDim2.new(1, -32, 0, 110)
arenaUI.saveOk = button(arenaUI.saveModal, 'SaveWarningOk', 'GOT IT', function() arenaUI.saveShade.Visible = false end)
arenaUI.saveOk.ZIndex = 92
arenaUI.saveOk.Position = UDim2.new(0.5, -60, 1, -50)
arenaUI.saveOk.Size = UDim2.fromOffset(120, 36)

-- Lifetime stats: a 3×3 grid of figures, sized by scale so it fits phones.
arenaUI.statsShade = button(root, 'StatsShade', '', function() arenaUI.statsShade.Visible = false end, palette.emeraldDark)
arenaUI.statsShade.BackgroundTransparency = 0.35
arenaUI.statsShade.Size = UDim2.fromScale(1, 1)
arenaUI.statsShade.ZIndex = 85
arenaUI.statsShade.Visible = false
arenaUI.statsPanel = frame(arenaUI.statsShade, 'StatsPanel', palette.emeraldDeep, 16)
arenaUI.statsPanel.ZIndex = 86
arenaUI.statsPanel.Active = true
arenaUI.statsPanel.AnchorPoint = Vector2.new(0.5, 0.5)
arenaUI.statsPanel.Position = UDim2.fromScale(0.5, 0.5)
arenaUI.statsPanel.Size = UDim2.new(0.92, 0, 0, 300)
make('UISizeConstraint', arenaUI.statsPanel, 'MaxSize', { MaxSize = Vector2.new(420, 300) })
outline(arenaUI.statsPanel, palette.gold, 1.5)
do
  local title = label(arenaUI.statsPanel, 'Title', 'YOUR STATS', 16, palette.goldBright)
  title.Font = Enum.Font.FredokaOne
  title.TextXAlignment = Enum.TextXAlignment.Left
  title.Position = UDim2.fromOffset(16, 12)
  title.Size = UDim2.new(1, -60, 0, 24)
  title.ZIndex = 87
  local close = make('TextButton', arenaUI.statsPanel, 'CloseStats', { Text = 'X', TextSize = 14, Font = Enum.Font.GothamBold,
    TextColor3 = palette.muted, BackgroundColor3 = palette.panel, AutoButtonColor = false, BorderSizePixel = 0, ZIndex = 87 })
  corner(close, 999)
  close.Position = UDim2.new(1, -40, 0, 12)
  close.Size = UDim2.fromOffset(26, 26)
  close.Activated:Connect(function() arenaUI.statsShade.Visible = false end)
end
arenaUI.statCells = {}
for index, spec in ipairs({
  { 'roundsPlayed', 'Rounds played' }, { 'winRate', 'Win rate' }, { 'matchesWon', 'Full matches won' },
  { 'shutouts', 'Shutouts' }, { 'overturns', 'Overturns' }, { 'chaodis', 'Chao Di made' },
  { 'bestGrade', 'Best multiplier' }, { 'biggestWin', 'Biggest round' }, { 'coinsEarned', 'Coins earned' },
}) do
  local col, row = (index - 1) % 3, math.floor((index - 1) / 3)
  local cell = frame(arenaUI.statsPanel, 'Stat_' .. spec[1], palette.panel, 10)
  cell.ZIndex = 87
  cell.Position = UDim2.new(col / 3, col == 0 and 12 or 4, 0, 48 + row * 80)
  cell.Size = UDim2.new(1 / 3, -16, 0, 72)
  local value = label(cell, 'Value', '0', 20, palette.cream)
  value.Font = Enum.Font.FredokaOne
  value.Position = UDim2.fromOffset(0, 10)
  value.Size = UDim2.new(1, 0, 0, 28)
  value.ZIndex = 88
  local caption = label(cell, 'Caption', spec[2], 10, palette.muted)
  caption.Position = UDim2.fromOffset(4, 42)
  caption.Size = UDim2.new(1, -8, 0, 22)
  caption.ZIndex = 88
  arenaUI.statCells[spec[1]] = value
end
function arenaUI.renderStats(stats)
  stats = stats or {}
  local played, won = stats.roundsPlayed or 0, stats.roundsWon or 0
  for key, value in pairs(arenaUI.statCells) do
    if key == 'winRate' then
      value.Text = played > 0 and (math.floor(won / played * 100 + 0.5) .. '%') or '—'
    elseif key == 'bestGrade' then
      value.Text = (stats.bestGrade or 0) > 0 and ('×' .. stats.bestGrade) or '—'
    elseif key == 'biggestWin' or key == 'coinsEarned' then
      value.Text = formatK(stats[key] or 0)
    else
      value.Text = tostring(stats[key] or 0)
    end
  end
end
function arenaUI.openStats()
  arenaUI.renderStats(C.state and C.state.stats)
  arenaUI.statsShade.Visible = true
end
playLayer.BackgroundTransparency = 1
playLayer.Size = UDim2.fromScale(1, 1)
playLayer.ZIndex = 12

-- Animation FX Container for Table Throwables & Points
local fxLayer = frame(root, 'FxLayer')
fxLayer.BackgroundTransparency = 1
fxLayer.Size = UDim2.fromScale(1, 1)
fxLayer.ZIndex = 40
arenaUI.R = require(C.folder:WaitForChild('Reactions'))({
  make = make, frame = frame, label = label, corner = corner, outline = outline, tween = tween,
  delay = function(seconds, fn) task.delay(seconds, fn) end, playSound = playSound, color = color, layer = fxLayer,
  -- Big impacts nudge the whole table for a moment, then put it back.
  shake = function(seconds, magnitude)
    if arenaUI.shaking then return end
    arenaUI.shaking = true
    local rest = root.Position or UDim2.new(0, 0, 0, 0)
    local steps = math.max(1, math.floor(seconds / 0.04))
    for step = 1, steps do
      task.delay(step * 0.04, function()
        local m = math.max(1, math.floor(magnitude * (1 - step / steps)))
        root.Position = UDim2.new(rest.X.Scale, rest.X.Offset + math.random(-m, m), rest.Y.Scale, rest.Y.Offset + math.random(-m, m))
      end)
    end
    task.delay(seconds + 0.05, function()
      root.Position = rest
      arenaUI.shaking = false
    end)
  end,
})

-- Tractor! Special Combo Banner
local tractorBanner = frame(root, 'TractorBanner', palette.goldDark, 14)
tractorBanner.BackgroundTransparency = 0.1
tractorBanner.Visible = false
tractorBanner.ZIndex = 45
outline(tractorBanner, palette.goldBright, 2)
gradient(tractorBanner, palette.goldBright, palette.goldDark, 90)
local tractorBannerText = label(tractorBanner, 'Text', 'TRACTOR COMBO!', 18, palette.ink)
tractorBannerText.Font = Enum.Font.GothamBold
tractorBannerText.Size = UDim2.fromScale(1, 1)

local lastTractorTrick = -1
local function triggerTractorBanner(trickNum, customText)
  if trickNum and lastTractorTrick == trickNum then return end
  if trickNum then lastTractorTrick = trickNum end
  tractorBannerText.Text = customText or 'TRACTOR COMBO!'
  tractorBanner.Visible = true
  tractorBanner.Position = UDim2.fromScale(0.5, 0.44)
  tractorBanner.AnchorPoint = Vector2.new(0.5, 0.5)
  tractorBanner.Size = UDim2.fromOffset(260, 44)
  playSound('tractor')
  tween(tractorBanner, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
    Size = UDim2.fromOffset(300, 50),
  })
  task.delay(1.5, function()
    if tractorBanner.Visible then
      tween(tractorBanner, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
        Position = UDim2.fromScale(0.5, 0.38),
        BackgroundTransparency = 1,
      })
      task.delay(0.4, function()
        tractorBanner.Visible = false
        tractorBanner.BackgroundTransparency = 0.1
        tractorBanner.Position = UDim2.fromScale(0.5, 0.44)
      end)
    end
  end)
end C.triggerTractorBanner = triggerTractorBanner

local seats = {} C.seats = seats
function arenaUI.initSeats()
local botProfiles = {
  [2] = { name = 'Shedletsky', userId = 261 },
  [3] = { name = 'Builderman', userId = 156 },
  [4] = { name = 'Roblox', userId = 1 },
  [5] = { name = 'Matt Dusek', userId = 16 },
  [6] = { name = 'BrightEyes', userId = 18 },
  [7] = { name = 'Reese', userId = 20 },
  [8] = { name = 'Stickmaster', userId = 158 },
  [9] = { name = 'Clockwork', userId = 684360 },
  [10] = { name = 'Erik Cassel', userId = 2868 },
}


for seat = 2, 10 do
  local profile = botProfiles[seat] or { name = seat == 3 and 'Partner' or ('Player ' .. seat), userId = 1 }
  local holder = frame(root, 'Seat' .. seat)
  holder.BackgroundTransparency = 1

  local isBlueTeam = seat % 2 == 1
  local teamCol = isBlueTeam and palette.teamBlue or palette.teamRed
  local shadowPlate = frame(holder, 'SeatShadow', color(0, 0, 0), 12)
  shadowPlate.BackgroundTransparency = 0.6
  shadowPlate.Position = UDim2.fromOffset(2, 4)
  shadowPlate.Size = UDim2.fromScale(1, 1)
  local cardBg = frame(holder, 'SeatCard', palette.emeraldDeep, 10)
  cardBg.BackgroundTransparency = 0
  cardBg.Size = UDim2.fromScale(1, 1)
  gradient(cardBg, color(34, 52, 78), color(18, 28, 44), 90)
  local cardBgStroke = outline(cardBg, palette.panelBorder, 1)
  local accent = frame(cardBg, 'TeamAccent', teamCol, 2)
  accent.Position = UDim2.new(0.2, 0, 0, 0)
  accent.Size = UDim2.new(0.6, 0, 0, 3)
  -- Cards left in this player's hand, shown as a mini card back + count.
  local handBadge = frame(holder, 'HandCount', color(16, 75, 44), 6)
  handBadge.AnchorPoint = Vector2.new(1, 0)
  handBadge.Position = UDim2.new(1, 6, 0, -8)
  handBadge.Size = UDim2.fromOffset(34, 20)
  handBadge.ZIndex = 6
  handBadge.Visible = false
  outline(handBadge, palette.gold, 1)
  local miniBack = frame(handBadge, 'MiniBack', color(26, 104, 62), 2)
  miniBack.Position = UDim2.fromOffset(5, 4)
  miniBack.Size = UDim2.fromOffset(9, 12)
  miniBack.ZIndex = 7
  outline(miniBack, palette.goldBright, 1)
  local handCountText = label(handBadge, 'Text', '0', 11, palette.goldBright)
  handCountText.Font = Enum.Font.GothamBold
  handCountText.TextWrapped = false
  handCountText.Position = UDim2.fromOffset(15, 0)
  handCountText.Size = UDim2.new(1, -17, 1, 0)
  handCountText.ZIndex = 7
  local teamDarkCol = isBlueTeam and palette.teamBlueDark or palette.teamRedDark
  local avatar = frame(holder, 'Avatar', teamCol, 999)
  gradient(avatar, teamCol, teamDarkCol, 90)
  local ring = outline(avatar, teamCol, 2.5)
  local avatarScale = make('UIScale', avatar, 'Scale', { Scale = 1.0 })

  local botImg = make('ImageLabel', avatar, 'Headshot', {
    BackgroundTransparency = 1,
    Size = UDim2.fromScale(1, 1),
    Image = 'rbxthumb://type=AvatarHeadShot&id=' .. tostring(profile.userId) .. '&w=150&h=150',
    ZIndex = 2,
  })
  corner(botImg, 999)
  botImg.Visible = true
  local avatarGlyph = label(avatar, 'AvatarGlyph', string.sub(profile.name, 1, 1), 22, palette.white)
  avatarGlyph.Font = Enum.Font.GothamBlack
  avatarGlyph.TextStrokeTransparency = 0.35
  avatarGlyph.Size = UDim2.fromScale(1, 1)
  avatarGlyph.Visible = false
  avatarGlyph.ZIndex = 3
  local name = label(holder, 'Name', profile.name, 13, palette.white)
  name.Font = Enum.Font.FredokaOne
  local details = label(holder, 'Details', seat == 3 and 'TEAM BLUE (PARTNER)' or (isBlueTeam and 'TEAM BLUE' or 'OPPONENT'), 10, teamCol)
  details.TextWrapped = false
  local count = label(holder, 'Count', '', 11, palette.cream)
  count.BackgroundColor3 = palette.emeraldDark
  count.BackgroundTransparency = 0
  count.TextColor3 = palette.goldBright
  count.Font = Enum.Font.GothamBold
  corner(count, 5)
  count.Visible = false
  local dealerSeal = frame(avatar, 'DealerSeal', palette.dealerRed, 999)
  dealerSeal.Size = UDim2.fromOffset(20, 20)
  dealerSeal.Position = UDim2.fromOffset(-4, -4)
  dealerSeal.Visible = false
  dealerSeal.ZIndex = 5
  outline(dealerSeal, palette.gold, 1.5)
  local dealerText = label(dealerSeal, 'Text', 'D', 12, palette.goldBright)
  dealerText.Font = Enum.Font.FredokaOne
  dealerText.Size = UDim2.fromScale(1, 1)
  dealerText.ZIndex = 6

  -- Animated Chat Bubble above avatar
  local bubble = frame(holder, 'ChatBubble', palette.cream, 8)
  bubble.Visible = false
  bubble.ZIndex = 35
  outline(bubble, palette.railOuter, 1)
  local bubbleText = label(bubble, 'Text', '', 10, palette.ink)
  bubbleText.Font = Enum.Font.FredokaOne
  bubbleText.Size = UDim2.fromScale(1, 1)

  -- Latest declaration cards float just above the profile, matching the
  -- compact card reveal used by Kuaile Shengji.
  local declarationCards = frame(holder, 'DeclarationCards', palette.cream, 5)
  declarationCards.BackgroundTransparency = 1
  declarationCards.Visible = false
  declarationCards.ZIndex = 28

  seats[seat] = {
    handBadge = handBadge,
    handCountText = handCountText,
    headshot = botImg,
    holder = holder,
    cardBg = cardBg,
    cardBgStroke = cardBgStroke,
    avatar = avatar,
    avatarGlyph = avatarGlyph,
    ring = ring,
    scale = avatarScale,
    name = name,
    details = details,
    count = count,
    dealerSeal = dealerSeal,
    bubble = bubble,
    declarationCards = declarationCards,
    isBlueTeam = isBlueTeam,
  }
end
end
arenaUI.initSeats()

-- Short, readable owner label for a play on the table.
-- 'You' / 'Partner' (any teammate) / 'Opponent'. Teams alternate seats.
function arenaUI.role(seat, upper)
  local text = seat == 1 and 'You' or (seat % 2 == 1 and 'Partner' or 'Opponent')
  return upper and string.upper(text) or text
end

function arenaUI.playerTag(seat, playerCount)
  if seat == 1 then return 'YOU' end
  local name = seats[seat] and seats[seat].name.Text or ('SEAT ' .. seat)
  if playerCount == 4 and seat == 3 and not (seats[seat] and seats[seat].human) then return 'PARTNER' end
  return string.upper(name)
end

-- Shows who actually sits in each seat (people in gold, bots in white).
-- '  ·  12s' while a multiplayer turn timer runs, else ''.
function arenaUI.countdown(current)
  if not current or not current.turnDeadline or not C.state or not C.state.serverTime then return '' end
  local remaining = math.max(0, math.ceil(current.turnDeadline - (C.state.serverTime + os.clock() - C.receivedAt)))
  return '  ·  ' .. remaining .. 's'
end

function arenaUI.applySeats(tableInfo)
  if not tableInfo or not tableInfo.seats then return end
  local signature = ''
  for seat = 2, tableInfo.playerCount or 4 do
    local info, s = tableInfo.seats[seat], seats[seat]
    if info and s then
      s.name.Text = info.name
      s.name.TextColor3 = info.human and palette.goldBright or palette.white
      s.human = info.human
      s.headshot.Image = 'rbxthumb://type=AvatarHeadShot&id=' .. tostring(info.userId or 1) .. '&w=150&h=150'
      if C.applySeatCosmetics then C.applySeatCosmetics(s, info) end
      signature = signature .. info.name .. (info.human and '*' or '') .. ';'
    end
  end
  -- Target buttons in the reaction sheet use seat names; rebuild if they changed.
  if chatUI and arenaUI.seatSignature ~= signature then
    arenaUI.seatSignature = signature
    chatUI.builtFor = nil
  end
end

local notice = label(root, 'Notice', 'Your table is ready. Play a hand, earn coins, make it yours.', 14, palette.white) C.notice = notice
local phaseLine = label(root, 'Phase', '', 12, palette.gold) C.phaseLine = phaseLine
-- Compact match-state ribbon keeps the action prompt readable over the felt
-- without competing with the cards or the defender meter.
local phaseRibbon = frame(root, 'PhaseRibbon', palette.tileBg, 8) C.phaseRibbon = phaseRibbon
phaseRibbon.BackgroundTransparency = 1
phaseRibbon.ZIndex = 15
phaseLine.ZIndex = 16
local actionBar = frame(root, 'ActionBar') C.actionBar = actionBar
actionBar.BackgroundTransparency = 1

local optionsFrame = make('ScrollingFrame', root, 'Declarations', { BackgroundTransparency = 1,
  BorderSizePixel = 0, CanvasSize = UDim2.new(), ScrollBarThickness = 3,
  ScrollingDirection = Enum.ScrollingDirection.X, Visible = false, ZIndex = 40 }) C.optionsFrame = optionsFrame

local lastCoinsVal = 3000
C.refreshTierLocks = nil

C.updateCoinDisplays = function(coins)
  coins = coins or (C.state and C.state.coins) or 3000
  local prevCoins = lastCoinsVal
  lastCoinsVal = coins
  local kStr = formatK(coins)
  if wallet then wallet.Text = '●  ' .. kStr .. ' coins' end
  -- `home`/`tier` are declared further down, so reach them through arenaUI.
  local home, tier = arenaUI.home, arenaUI.tier
  if home and home.coinText then home.coinText.Text = kStr end
  if tier and tier.coinText then tier.coinText.Text = kStr end
  if C.shopBalance then C.shopBalance.Text = '●  ' .. kStr .. ' COINS' end

  if coins > prevCoins and home and home.coinPill then
    local pScale = home.coinPill:FindFirstChild('PillScale')
    if not pScale then pScale = make('UIScale', home.coinPill, 'PillScale', { Scale = 1.0 }) end
    if C.TweenService then
      C.TweenService:Create(pScale, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.18 }):Play()
      task.delay(0.15, function()
        C.TweenService:Create(pScale, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1.0 }):Play()
      end)
    end
    playSound('coin')
  end
  if C.refreshTierLocks then C.refreshTierLocks() end
end
end
