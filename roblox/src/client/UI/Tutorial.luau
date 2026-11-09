-- Happy Tractor client: first-time tutorial.
-- 1) A short "How to play" slideshow (shown once to new players, and any time
--    from the home screen's ? button).
-- 2) Coach tips during the player's first round: one bubble per new moment
--    (declare, bury, Chao Di, Double, lead, follow, trick won, round over).
-- Finishing the first round tells the server (once ever, +1K coins).
return function(C)
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')
local playSound, remote, palette = C.playSound, C.remote, C.palette
local color = Color3.fromRGB
local INK = color(20, 16, 30)
local GOLD = color(255, 200, 60)
local CREAM = color(255, 246, 220)

local player = Players.LocalPlayer
local gui = Instance.new('ScreenGui')
gui.Name = 'TractorTutorial'
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 60
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild('PlayerGui')

local function new(class, parent, props)
  local o = Instance.new(class)
  for k, v in pairs(props or {}) do o[k] = v end
  o.Parent = parent
  return o
end
local function round(o, r) new('UICorner', o, { CornerRadius = UDim.new(0, r or 12) }) end
local function stroke(o, c, t) return new('UIStroke', o, { Color = c or INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function text(parent, str, size, col, font, props)
  local l = new('TextLabel', parent, {
    BackgroundTransparency = 1, Text = str, TextSize = size, TextColor3 = col or palette.white,
    Font = font or Enum.Font.GothamBold, TextWrapped = true,
  })
  for k, v in pairs(props or {}) do l[k] = v end
  return l
end
local function outlined(l, t)
  new('UIStroke', l, { Color = INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
  return l
end
local function pill(parent, label, top, bottom, onClick)
  local b = new('TextButton', parent, { Text = '', AutoButtonColor = false, BackgroundColor3 = palette.white, BorderSizePixel = 0 })
  round(b, 12)
  stroke(b, INK, 2)
  new('UIGradient', b, { Color = ColorSequence.new(top, bottom), Rotation = 90 })
  local l = outlined(text(b, label, 18, palette.white, Enum.Font.FredokaOne, { Size = UDim2.fromScale(1, 1), TextWrapped = false }), 1.5)
  b.Activated:Connect(function() playSound('click'); onClick() end)
  b.MouseEnter:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), { Size = b.Size + UDim2.fromOffset(4, 2) }):Play() end)
  b.MouseLeave:Connect(function() TweenService:Create(b, TweenInfo.new(0.12), { Size = b.Size - UDim2.fromOffset(4, 2) }):Play() end)
  return b, l
end

-- Small card pictures for the slides, drawn with the game's own card faces.
local function cardRow(parent, cards, w, h, gap)
  local holder = new('Frame', parent, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
  local total = #cards * w + (#cards - 1) * gap
  for i, spec in ipairs(cards) do
    local slot = new('Frame', holder, {
      BackgroundTransparency = 1, Size = UDim2.fromOffset(w, h),
      Position = UDim2.new(0.5, -total / 2 + (i - 1) * (w + gap), 0.5, -h / 2 + (spec.lift or 0)),
    })
    if spec.card then
      local face = C.cardFace(slot, spec.card, 'Card', w, h)
      face.Position = UDim2.fromOffset(0, 0)
    end
    if spec.tag then
      -- span = how many cards the label sits under (e.g. a pair or a tractor)
      local span = spec.span or 1
      local width = span * w + (span - 1) * gap
      local tag = outlined(text(slot, spec.tag, 15, spec.tagColor or GOLD, Enum.Font.FredokaOne,
        { Size = UDim2.new(0, width + 20, 0, 20), Position = UDim2.new(0, -10, 1, 4), TextWrapped = false }), 1.5)
      tag.ZIndex = 5
    end
  end
  return holder
end

local function seatsPicture(parent)
  local holder = new('Frame', parent, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
  local felt = new('Frame', holder, { BackgroundColor3 = color(22, 110, 70), Size = UDim2.fromOffset(250, 120), Position = UDim2.new(0.5, -125, 0.5, -60) })
  round(felt, 60); stroke(felt, GOLD, 3)
  local function seat(name, col, x, y)
    local s = new('Frame', holder, { BackgroundColor3 = col, Size = UDim2.fromOffset(96, 30), Position = UDim2.new(0.5, x - 48, 0.5, y - 15) })
    round(s, 10); stroke(s, INK, 2)
    outlined(text(s, name, 14, palette.white, Enum.Font.FredokaOne, { Size = UDim2.fromScale(1, 1), TextWrapped = false }), 1.5)
  end
  seat('YOU', color(60, 140, 255), 0, 56)
  seat('PARTNER', color(60, 140, 255), 0, -56)
  seat('OPPONENT', color(230, 70, 80), -150, 0)
  seat('OPPONENT', color(230, 70, 80), 150, 0)
  return holder
end

local function levelPicture(parent)
  local holder = new('Frame', parent, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
  local ranks = { '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A' }
  local w, gap = 30, 4
  local total = #ranks * w + (#ranks - 1) * gap
  for i, r in ipairs(ranks) do
    local hot = i == 1 or i == #ranks
    local chip = new('Frame', holder, {
      BackgroundColor3 = hot and GOLD or color(40, 46, 70), Size = UDim2.fromOffset(w, 40),
      Position = UDim2.new(0.5, -total / 2 + (i - 1) * (w + gap), 0.5, -26),
    })
    round(chip, 8); stroke(chip, INK, 2)
    text(chip, r, 15, hot and INK or palette.white, Enum.Font.FredokaOne, { Size = UDim2.fromScale(1, 1), TextWrapped = false })
  end
  outlined(text(holder, 'START', 17, GOLD, Enum.Font.FredokaOne,
    { Size = UDim2.fromOffset(80, 24), Position = UDim2.new(0.5, -total / 2 + w / 2 - 40, 0.5, 22), TextWrapped = false }), 1.5)
  outlined(text(holder, 'WIN!', 17, GOLD, Enum.Font.FredokaOne,
    { Size = UDim2.fromOffset(80, 24), Position = UDim2.new(0.5, total / 2 - w / 2 - 40, 0.5, 22), TextWrapped = false }), 1.5)
  local track = new('Frame', holder, { BackgroundColor3 = GOLD, BackgroundTransparency = 0.5, BorderSizePixel = 0,
    Size = UDim2.fromOffset(total - 140, 4), Position = UDim2.new(0.5, -total / 2 + 70, 0.5, 32) })
  round(track, 2)
  return holder
end

local function badgesPicture(parent)
  local holder = new('Frame', parent, { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
  local list = {
    { '🎴 KITTY', color(90, 110, 160) }, { '🔥 CHAO DI ×2', color(230, 70, 60) }, { '⚡ DOUBLE ×2', color(150, 80, 230) },
  }
  for i, b in ipairs(list) do
    local chip = new('Frame', holder, { BackgroundColor3 = b[2], Size = UDim2.fromOffset(150, 46), Position = UDim2.new(0.5, -240 + (i - 1) * 165, 0.5, -23) })
    round(chip, 14); stroke(chip, INK, 2.5)
    outlined(text(chip, b[1], 17, palette.white, Enum.Font.FredokaOne, { Size = UDim2.fromScale(1, 1), TextWrapped = false }), 1.5)
  end
  return holder
end

local SLIDES = {
  { title = 'WELCOME TO HAPPY TRACTOR', emoji = '🚜',
    body = 'A team card game for 4 players. The player across from you is your partner — you win and lose together.',
    picture = seatsPicture },
  { title = 'CLIMB THE LEVELS', emoji = '📈',
    body = 'Both teams start at level 2. Win rounds to move up: 2, 3, 4… all the way to A. The first team to win at A wins the match!',
    picture = levelPicture },
  { title = 'TRUMP BEATS EVERYTHING', emoji = '👑',
    body = 'Trumps are the two Jokers, every card of the current level (like all the 2s), and the trump suit. Claim the trump suit by showing a level card while the cards are dealt.',
    picture = function(p) return cardRow(p, {
      { card = { joker = 'big' }, tag = 'BIG' }, { card = { joker = 'small' }, tag = 'SMALL' },
      { card = { rank = '2', suit = 'spades' }, tag = 'LEVEL' }, { card = { rank = '2', suit = 'hearts' }, tag = 'LEVEL' },
      { card = { rank = 'A', suit = 'spades' }, tag = 'SUIT' },
    }, 54, 78, 10) end },
  { title = 'PLAYING A TRICK', emoji = '🃏',
    body = 'The leader plays a single card, a pair, or a TRACTOR (pairs in a row). Everyone else must follow the same suit, and match a pair with a pair if they can. Highest card wins and leads next.',
    picture = function(p) return cardRow(p, {
      { card = { rank = '7', suit = 'hearts' }, tag = 'PAIR', span = 2 }, { card = { rank = '7', suit = 'hearts' } },
      { card = { rank = '8', suit = 'diamonds' }, tag = 'TRACTOR!', span = 4 }, { card = { rank = '8', suit = 'diamonds' } },
      { card = { rank = '9', suit = 'diamonds' } }, { card = { rank = '9', suit = 'diamonds' } },
    }, 48, 70, 6) end },
  { title = 'POINTS WIN ROUNDS', emoji = '💰',
    body = 'Only 5s, 10s and Kings score: a 5 is worth 5, a 10 or K is worth 10. The team without the deal collects points — 80 or more and they take over!',
    picture = function(p) return cardRow(p, {
      { card = { rank = '5', suit = 'hearts' }, tag = '+5' }, { card = { rank = '10', suit = 'spades' }, tag = '+10' },
      { card = { rank = 'K', suit = 'clubs' }, tag = '+10' },
    }, 60, 86, 22) end },
  { title = 'BIG MOMENTS', emoji = '🔥',
    body = 'KITTY: the dealer picks up the hidden bottom cards and buries the same number. CHAO DI: show a stronger set of level cards to steal the kitty and double the stakes. DOUBLE: right after, double your own stake if you feel lucky!',
    picture = badgesPicture },
}

-- ===== Slideshow =====
local shade = new('Frame', gui, { Name = 'Shade', BackgroundColor3 = color(0, 0, 0), BackgroundTransparency = 0.35, Size = UDim2.fromScale(1, 1), Visible = false, Active = true })
local panel = new('Frame', shade, { Name = 'Panel', BackgroundColor3 = palette.white, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(620, 470) })
round(panel, 22); stroke(panel, GOLD, 4)
new('UIGradient', panel, { Color = ColorSequence.new(color(46, 54, 96), color(20, 22, 44)), Rotation = 90 })
local scale = new('UIScale', panel, { Scale = 1 })

local header = new('Frame', panel, { BackgroundColor3 = palette.white, Size = UDim2.new(1, -24, 0, 60), Position = UDim2.fromOffset(12, 12) })
round(header, 16); stroke(header, INK, 2.5)
new('UIGradient', header, { Color = ColorSequence.new(color(255, 170, 50), color(214, 90, 20)), Rotation = 90 })
local emojiLabel = text(header, '', 30, palette.white, Enum.Font.GothamBold, { Size = UDim2.fromOffset(56, 60), Position = UDim2.fromOffset(6, 0), TextWrapped = false })
local titleLabel = outlined(text(header, '', 26, palette.white, Enum.Font.FredokaOne, { Size = UDim2.new(1, -124, 1, 0), Position = UDim2.fromOffset(62, 0), TextWrapped = false, TextScaled = true }), 2.5)
new('UITextSizeConstraint', titleLabel, { MaxTextSize = 26 })
local stepLabel = outlined(text(header, '', 16, CREAM, Enum.Font.FredokaOne, { Size = UDim2.fromOffset(56, 60), Position = UDim2.new(1, -60, 0, 0), TextWrapped = false }), 1.5)

local pictureBox = new('Frame', panel, { BackgroundColor3 = color(14, 18, 34), Size = UDim2.new(1, -24, 0, 160), Position = UDim2.fromOffset(12, 84), ClipsDescendants = true })
round(pictureBox, 14); stroke(pictureBox, color(80, 90, 140), 2)
local bodyLabel = text(panel, '', 19, CREAM, Enum.Font.GothamBold, { Size = UDim2.new(1, -48, 0, 116), Position = UDim2.fromOffset(24, 254), TextYAlignment = Enum.TextYAlignment.Top, LineHeight = 1.15 })

local dots = new('Frame', panel, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), Position = UDim2.new(0, 0, 1, -92) })
new('UIListLayout', dots, { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center, Padding = UDim.new(0, 8) })
local dotFrames = {}
for i = 1, #SLIDES do
  local d = new('Frame', dots, { BackgroundColor3 = color(90, 96, 130), Size = UDim2.fromOffset(12, 12), LayoutOrder = i })
  round(d, 6)
  dotFrames[i] = d
end

local index = 1
local onFinish
local backBtn = pill(panel, '◀ BACK', color(120, 130, 170), color(70, 76, 110), function() end)
backBtn.Size = UDim2.fromOffset(130, 50); backBtn.Position = UDim2.new(0, 24, 1, -70)
local rulesBtn = pill(panel, '📖 FULL RULES', color(70, 160, 255), color(22, 62, 170), function()
  shade.Visible = false
  if C.openRulesModal then C.openRulesModal() end
end)
rulesBtn.Size = UDim2.fromOffset(170, 50); rulesBtn.Position = UDim2.new(0.5, -85, 1, -70)
local nextBtn, nextLabel = pill(panel, 'NEXT ▶', color(255, 214, 70), color(230, 140, 20), function() end)
nextBtn.Size = UDim2.fromOffset(150, 50); nextBtn.Position = UDim2.new(1, -174, 1, -70)
local closeBtn = new('TextButton', panel, { Text = 'X', TextSize = 18, Font = Enum.Font.FredokaOne, TextColor3 = palette.white, BackgroundColor3 = color(200, 60, 70), Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -20, 0, -14), AutoButtonColor = true })
round(closeBtn, 17); stroke(closeBtn, INK, 2)

local function show(i)
  index = math.clamp(i, 1, #SLIDES)
  local s = SLIDES[index]
  emojiLabel.Text = s.emoji
  titleLabel.Text = s.title
  bodyLabel.Text = s.body
  stepLabel.Text = index .. '/' .. #SLIDES
  for k, d in ipairs(dotFrames) do
    d.BackgroundColor3 = k == index and GOLD or color(90, 96, 130)
    d.Size = k == index and UDim2.fromOffset(26, 12) or UDim2.fromOffset(12, 12)
  end
  for _, child in ipairs(pictureBox:GetChildren()) do if not child:IsA('UICorner') and not child:IsA('UIStroke') then child:Destroy() end end
  local ok, err = pcall(s.picture, pictureBox)
  if not ok then warn('[Tutorial] picture failed: ' .. tostring(err)) end
  backBtn.Visible = index > 1
  nextLabel.Text = index == #SLIDES and "LET'S PLAY! ▶" or 'NEXT ▶'
  nextBtn.Size = index == #SLIDES and UDim2.fromOffset(176, 50) or UDim2.fromOffset(150, 50)
  nextBtn.Position = UDim2.new(1, index == #SLIDES and -200 or -174, 1, -70)
end

local function fit()
  local cam = workspace.CurrentCamera
  local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
  scale.Scale = math.min(1, (vp.X - 24) / 620, (vp.Y - 24) / 470)
end

-- ===== Pointer at the Classic PLAY button after the slideshow =====
local pointer = new('Frame', gui, { Name = 'Pointer', BackgroundTransparency = 1, Size = UDim2.fromOffset(200, 30), Visible = false })
local pointerLabel = outlined(text(pointer, 'START HERE! ⬇', 20, GOLD, Enum.Font.FredokaOne, { Size = UDim2.fromScale(1, 1), TextWrapped = false }), 2.5)
local pointerTarget, pointerGlow
task.spawn(function()
  local t = 0
  while gui.Parent do
    t += task.wait()
    if pointer.Visible and pointerTarget and pointerTarget.Parent then
      local onScreen = pointerTarget.AbsoluteSize.X > 0 and pointerTarget.Visible
      local p = pointerTarget
      while onScreen and p and p:IsA('GuiObject') do onScreen = p.Visible; p = p.Parent end
      pointerLabel.Visible = onScreen
      local pos, size = pointerTarget.AbsolutePosition, pointerTarget.AbsoluteSize
      -- Only add the top-bar inset if the target's screen does not already ignore it.
      local targetGui = pointerTarget:FindFirstAncestorWhichIsA('ScreenGui')
      local insetY = (targetGui and not targetGui.IgnoreGuiInset) and game:GetService('GuiService'):GetGuiInset().Y or 0
      pointer.Position = UDim2.fromOffset(pos.X + size.X / 2 - 100, pos.Y + insetY - 30 + math.sin(t * 5) * 4)
      if pointerGlow then pointerGlow.Thickness = 3 + math.sin(t * 6) * 1.5 end
    end
  end
end)
local function hidePointer()
  pointer.Visible = false; pointerTarget = nil
  if pointerGlow then pointerGlow:Destroy(); pointerGlow = nil end
end

-- ===== Coach tips during the first round =====
C.tutorialActive = false
local tipsShown = {}
local bubble = new('Frame', gui, { Name = 'Coach', BackgroundColor3 = palette.white, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 196), Size = UDim2.fromOffset(470, 132), Visible = false })
round(bubble, 18); stroke(bubble, GOLD, 3)
new('UIGradient', bubble, { Color = ColorSequence.new(color(46, 54, 96), color(22, 24, 48)), Rotation = 90 })
local bubbleScale = new('UIScale', bubble, { Scale = 1 })
local coachIcon = text(bubble, '🎓', 34, palette.white, Enum.Font.GothamBold, { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(10, 10), TextWrapped = false })
local coachTitle = outlined(text(bubble, '', 20, GOLD, Enum.Font.FredokaOne, { Size = UDim2.new(1, -80, 0, 26), Position = UDim2.fromOffset(68, 10), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = false }), 1.5)
local coachBody = text(bubble, '', 15, CREAM, Enum.Font.GothamBold, { Size = UDim2.new(1, -84, 0, 58), Position = UDim2.fromOffset(68, 38), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top })
local gotIt = pill(bubble, 'GOT IT', color(255, 214, 70), color(230, 140, 20), function() bubble.Visible = false end)
gotIt.Size = UDim2.fromOffset(110, 34); gotIt.Position = UDim2.new(1, -124, 1, -44)
local skipBtn = new('TextButton', bubble, { Text = 'Skip tutorial', TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = color(170, 176, 210), BackgroundTransparency = 1, Size = UDim2.fromOffset(110, 30), Position = UDim2.new(0, 64, 1, -40) })

local function coach(key, icon, title, body)
  if tipsShown[key] then return end
  tipsShown[key] = true
  coachIcon.Text, coachTitle.Text, coachBody.Text = icon, title, body
  local cam = workspace.CurrentCamera
  local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
  bubbleScale.Scale = math.min(1, (vp.X - 16) / 470)
  bubble.Visible = true
  bubble.Size = UDim2.fromOffset(470, 120)
  TweenService:Create(bubble, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(470, 132) }):Play()
  playSound('turn_chime', false, 0.6)
  -- Tips tidy themselves away if the player keeps playing without tapping GOT IT.
  local shownKey = key
  task.delay(18, function()
    if bubble.Visible and tipsShown[shownKey] and coachTitle.Text == title then bubble.Visible = false end
  end)
end

local finishedSent = false
local function finish(how)
  C.tutorialActive = false
  bubble.Visible = false
  hidePointer()
  if not finishedSent and C.state and C.state.tutorialDone == false then
    finishedSent = true
    remote:FireServer('tutorial_done', how)
  end
end
skipBtn.Activated:Connect(function() finish('skipped') end)

-- Opens the slideshow. `firstTime` = the automatic one for new players.
function C.openTutorial(firstTime)
  hidePointer()
  fit()
  show(1)
  shade.Visible = true
  panel.Size = UDim2.fromOffset(600, 450)
  TweenService:Create(panel, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(620, 470) }):Play()
  onFinish = function()
    shade.Visible = false
    -- Coach tips for the next round, and point at the Classic PLAY button.
    C.tutorialActive = true
    tipsShown = {}
    local homeView = C.home and C.home.view
    if homeView and homeView.Visible and C.home.mode1 then
      pointerTarget = C.home.mode1:FindFirstChild('Action') or C.home.mode1
      pointer.Visible = true
      pointerGlow = new('UIStroke', pointerTarget, { Name = 'TutorialGlow', Color = GOLD, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
    end
  end
  closeBtn.Visible = not firstTime
end
backBtn.Activated:Connect(function() show(index - 1) end)
nextBtn.Activated:Connect(function()
  if index < #SLIDES then show(index + 1) elseif onFinish then onFinish() end
end)
closeBtn.Activated:Connect(function() playSound('click'); shade.Visible = false end)

-- The home screen's ? button now opens this tutorial (Full Rules is one tap inside).
if C.home and C.home.rulesBtn then
  local old = C.home.rulesBtn
  local replacement = old:Clone()
  for _, child in ipairs(replacement:GetChildren()) do if child:IsA('LuaSourceContainer') then child:Destroy() end end
  replacement.Name = 'TutorialBtn'
  replacement.Parent = old.Parent
  old.Visible = false
  C.home.tutorialBtn = replacement
  replacement.Activated:Connect(function() playSound('click'); C.openTutorial(false) end)
  -- keep the copy where the layout puts the original
  old:GetPropertyChangedSignal('Position'):Connect(function() replacement.Position = old.Position end)
  old:GetPropertyChangedSignal('Size'):Connect(function() replacement.Size = old.Size end)
  old:GetPropertyChangedSignal('Visible'):Connect(function() if old.Visible then old.Visible = false end end)
end

-- ===== React to game state =====
local autoShown = false
local function onState()
  local s = C.state
  if not s then return end
  -- First visit: show the slideshow once the home screen is up.
  if s.tutorialDone == false and not autoShown and not C.tutorialActive then
    autoShown = true
    task.delay(1, function()
      if not shade.Visible then C.openTutorial(true) end
    end)
  end
  local g = s.game
  if pointer.Visible and (g or s.search) then hidePointer() end
  if not C.tutorialActive or not g then return end
  local myTurnTricks = g.phase == 'tricks' and g.turn == 1
  if g.done then
    coach('done', '🏁', 'ROUND OVER!',
      'Points decide who moves up a level. Tap NEXT ROUND to keep going. You know the basics now. Have fun!')
    finish('finished')
  elseif g.phase == 'declaration' then
    coach('declare', '👑', 'CHOOSE TRUMP',
      'Cards are being dealt. Got a card of the level shown at top left? Tap its suit button below to make that suit trump. Or just wait, someone will.')
  elseif g.phase == 'kitty' and (g.kittyHolder or g.dealer) == 1 then
    coach('kitty', '🂠', 'BURY THE KITTY',
      'You picked up the bottom cards! Choose ' .. tostring(g.kittySize or 8) .. ' cards you do not need and tap BURY. Tap the button with nothing picked to auto-select.')
  elseif g.phase == 'chaodi' and g.chaodiTurn == 1 then
    coach('chaodi', '🔥', 'CHAO DI?',
      'If you hold a stronger set of level cards you can steal the kitty and double the stakes. No good set? Just tap PASS.')
  elseif g.phase == 'doubling' then
    coach('double', '⚡', 'DOUBLE OR NOT?',
      'You have a few seconds to tap DOUBLE ×2. It doubles what you win, or lose, this round. Only do it with a strong hand!')
  elseif myTurnTricks and not (g.trick and g.trick[1]) then
    coach('lead', '🃏', 'YOUR LEAD!',
      'Suggested cards are already picked for you. Tap PLAY, or tap cards to choose your own. Pairs and tractors are strong leads.')
  elseif myTurnTricks then
    coach('follow', '🃏', 'FOLLOW THE SUIT',
      'Play the same suit that was led, and a pair if a pair was led. Out of that suit? Play a trump to win it, or throw a low card.')
  elseif g.phase == 'trick-review' then
    coach('trick', '💰', 'TRICK WON!',
      'The winner takes any 5s, 10s and Kings in the trick and leads next. Watch the points bar at the top left.')
  end
end
remote.OnClientEvent:Connect(function(message)
  if type(message) ~= 'table' or message.hint or message.type then return end
  task.defer(onState)  -- after Events has stored the new state
end)
end
