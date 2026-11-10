-- Clamp that tolerates max < min (tiny phone screens) instead of erroring.
local function safeClamp(v, lo, hi) if hi < lo then hi = lo end return math.clamp(v, lo, hi) end
-- Happy Tractor client, part 8/14: Modals.
-- Lines 3168-3979 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local arenaUI, button, color, customIconAsset, flatCoinIcon, formatK, frame, home = C.arenaUI, C.button, C.color, C.customIconAsset, C.flatCoinIcon, C.formatK, C.frame, C.home
local label, make, outline, palette, playSound, rect, remote, root = C.label, C.make, C.outline, C.palette, C.playSound, C.rect, C.remote, C.root
local updateSoundtrack = C.updateSoundtrack

-- ==========================================================
-- 3. SETTINGS, RULES, MAIL, LUCKY WHEEL & VAULT MODALS
-- ==========================================================
local settingsUI = {} C.settingsUI = settingsUI
function arenaUI.initSettingsModal()
  local sShade = button(root, 'SettingsShade', '', function() end, palette.emeraldDark)
  sShade.BackgroundTransparency = 0.22
  sShade.Size = UDim2.fromScale(1, 1)
  sShade.Visible = false
  sShade.ZIndex = 58

  local sModal = frame(sShade, 'SettingsModal', palette.panel, 20)
  outline(sModal, palette.railOuter, 1.5)

  local sTitle = label(sModal, 'Title', 'GAME SETTINGS', 18, palette.gold)
  sTitle.Font = Enum.Font.FredokaOne
  local sClose = button(sModal, 'Close', '×', function() sShade.Visible = false end, palette.panelLight)
  sClose.TextSize = 16

  -- 1. SFX Toggle
  local sfxRow = frame(sModal, 'SfxRow', palette.tileBg, 10)
  outline(sfxRow, palette.panelBorder, 1)
  local sfxLabel = label(sfxRow, 'Label', 'Sound Effects (SFX)', 12, palette.cream)
  sfxLabel.Font = Enum.Font.GothamBold
  sfxLabel.TextXAlignment = Enum.TextXAlignment.Left
  local sfxBtn = button(sfxRow, 'Toggle', 'SFX: ON', function() end, palette.panelLight)
  sfxBtn.TextSize = 11

  -- 2. BGM Atmosphere Toggle
  local bgmRow = frame(sModal, 'BgmRow', palette.tileBg, 10)
  outline(bgmRow, palette.panelBorder, 1)
  local bgmLabel = label(bgmRow, 'Label', 'Audio Atmosphere', 12, palette.cream)
  bgmLabel.Font = Enum.Font.GothamBold
  bgmLabel.TextXAlignment = Enum.TextXAlignment.Left
  local bgmBtn = button(bgmRow, 'Toggle', 'BGM: ON', function() end, palette.panelLight)
  bgmBtn.TextSize = 11

  -- 3. Table Reactions Toggle
  local reactRow = frame(sModal, 'ReactRow', palette.tileBg, 10)
  outline(reactRow, palette.panelBorder, 1)
  local reactLabel = label(reactRow, 'Label', 'Table Quick Chat & Emotes', 12, palette.cream)
  reactLabel.Font = Enum.Font.GothamBold
  reactLabel.TextXAlignment = Enum.TextXAlignment.Left
  local reactBtn = button(reactRow, 'Toggle', 'ALLOWED', function() end, palette.panelLight)
  reactBtn.TextSize = 11

  -- 4. Table Felt Theme Quick Selector
  local feltRow = frame(sModal, 'FeltRow', palette.tileBg, 10)
  outline(feltRow, palette.panelBorder, 1)
  local feltLabel = label(feltRow, 'Label', 'Table Felt Theme', 12, palette.gold)
  feltLabel.Font = Enum.Font.GothamBold
  feltLabel.TextXAlignment = Enum.TextXAlignment.Left

  local feltBtns = {}
  local feltList = {
    { id = 'felt_emerald', label = 'Emerald' },
    { id = 'felt_sapphire', label = 'Sapphire' },
    { id = 'felt_ruby', label = 'Ruby' },
    { id = 'felt_obsidian', label = 'Obsidian' },
  }
  for _, f in ipairs(feltList) do
    local b = button(feltRow, 'Felt_' .. f.id, f.label, function()
      remote:FireServer('equip', f.id)
      if C.state and C.state.equipped then C.state.equipped.felt = f.id end
      C.render()
    end, palette.panel)
    b.TextSize = 10
    feltBtns[f.id] = b
  end

  local rulesShortcut = button(sModal, 'RulesShortcut', 'HOW TO PLAY TRACTOR (RULES GUIDE)', function()
    sShade.Visible = false
    C.openRulesModal()
  end)
  rulesShortcut.TextSize = 12

  local function layoutSettings()
    local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
    local smW = safeClamp(w - 40, 360, 520)
    local smH = 340
    rect(sModal, (w - smW) / 2, (h - smH) / 2, smW, smH)
    rect(sTitle, 20, 14, smW - 70, 26)
    rect(sClose, smW - 44, 12, 32, 32)

    rect(sfxRow, 20, 52, smW - 40, 42)
    rect(sfxLabel, 14, 10, smW - 160, 22)
    rect(sfxBtn, smW - 140, 7, 90, 28)

    rect(bgmRow, 20, 102, smW - 40, 42)
    rect(bgmLabel, 14, 10, smW - 160, 22)
    rect(bgmBtn, smW - 140, 7, 90, 28)

    rect(reactRow, 20, 152, smW - 40, 42)
    rect(reactLabel, 14, 10, smW - 160, 22)
    rect(reactBtn, smW - 140, 7, 90, 28)

    rect(feltRow, 20, 202, smW - 40, 68)
    rect(feltLabel, 14, 6, smW - 68, 20)
    local fW = math.floor((smW - 40 - 28) / 4)
    for i, f in ipairs(feltList) do
      rect(feltBtns[f.id], 14 + (fW + 4) * (i - 1), 32, fW, 28)
    end

    rect(rulesShortcut, 20, 282, smW - 40, 38)
  end

  local function refreshSettings()
    sfxBtn.Text = C.sfxEnabled and 'SFX: ON' or 'SFX: OFF'
    sfxBtn.TextColor3 = C.sfxEnabled and palette.green or palette.red
    bgmBtn.Text = C.bgmEnabled and 'BGM: ON' or 'BGM: OFF'
    bgmBtn.TextColor3 = C.bgmEnabled and palette.green or palette.red
    reactBtn.Text = not C.muted and 'ALLOWED' or 'MUTED'
    reactBtn.TextColor3 = not C.muted and palette.green or palette.red

    local currentFelt = (C.state and C.state.equipped and C.state.equipped.felt) or 'felt_emerald'
    for id, b in pairs(feltBtns) do
      local isActive = id == currentFelt
      b.BackgroundColor3 = isActive and palette.gold or palette.panel
      b.TextColor3 = isActive and palette.ink or palette.white
    end
  end

  sfxBtn.Activated:Connect(function()
    C.sfxEnabled = not C.sfxEnabled
    refreshSettings()
  end)
  bgmBtn.Activated:Connect(function()
    C.bgmEnabled = not C.bgmEnabled
    updateSoundtrack()
    refreshSettings()
  end)
  reactBtn.Activated:Connect(function()
    C.muted = not C.muted
    refreshSettings()
  end)

  C.openSettingsModal = function()
    layoutSettings()
    refreshSettings()
    sShade.Visible = true
  end

  settingsUI.shade = sShade
  settingsUI.layout = layoutSettings
end
arenaUI.initSettingsModal()

local rulesUI = {} C.rulesUI = rulesUI
function arenaUI.initRulesModal()
  local ruShade = button(root, 'RulesShade', '', function() end, palette.emeraldDark)
  ruShade.BackgroundTransparency = 0.22
  ruShade.Size = UDim2.fromScale(1, 1)
  ruShade.Visible = false
  ruShade.ZIndex = 58

  local ruModal = frame(ruShade, 'RulesModal', palette.panel, 20)
  outline(ruModal, palette.railOuter, 1.5)

  local ruTitle = label(ruModal, 'Title', 'TRACTOR (升级) GAME GUIDE', 18, palette.gold)
  ruTitle.Font = Enum.Font.FredokaOne
  local ruClose = button(ruModal, 'Close', '×', function() ruShade.Visible = false end, palette.panelLight)
  ruClose.TextSize = 16

  local tabButtons = {}
  local currentRulesTab = 'basics'
  local tabContainer = frame(ruModal, 'Tabs', palette.emeraldDark, 10)
  outline(tabContainer, palette.panelBorder, 1)

  local tabDefs = {
    { id = 'basics', label = '2v2 BASICS' },
    { id = 'ranks', label = 'CARD RANKS' },
    { id = 'tractors', label = 'TRACTORS' },
    { id = 'scoring', label = 'SCORING' },
    { id = 'declare', label = 'DECLARE' },
    { id = 'kitty', label = 'KITTY' },
    { id = 'follow', label = 'FOLLOW SUIT' },
    { id = 'chaodi', label = 'CHAO DI' },
  }

  local contentBox = frame(ruModal, 'Content', palette.tileBg, 12)
  outline(contentBox, palette.panelBorder, 1)

  local contentTitle = label(contentBox, 'Heading', '', 14, palette.goldBright)
  contentTitle.Font = Enum.Font.GothamBold
  contentTitle.TextXAlignment = Enum.TextXAlignment.Left

  local contentBody = label(contentBox, 'Body', '', 11, palette.cream)
  contentBody.TextXAlignment = Enum.TextXAlignment.Left
  contentBody.TextYAlignment = Enum.TextYAlignment.Top

  local guideVisual = make('ImageLabel', contentBox, 'GuideVisual', {
    BackgroundTransparency = 1,
    Image = customIconAsset,
    ImageRectSize = Vector2.new(512, 1024),
    ImageRectOffset = Vector2.new(1024, 0),
  })
  -- The lesson is intentionally code-native: the four large nodes stay crisp
  -- at every viewport instead of depending on a low-resolution art crop.
  guideVisual.Visible = false
  local guideDiagram = label(contentBox, 'GuideDiagram', 'DEAL  →  DECLARE  →  PLAY  →  SCORE', 10, palette.goldBright)
  guideDiagram.Font = Enum.Font.GothamBold
  guideDiagram.TextXAlignment = Enum.TextXAlignment.Center
  local diagramNodes = {}
  local diagramArrows = {}
  for i = 1, 4 do
    local node = frame(contentBox, 'DiagramNode' .. i, palette.emeraldDeep, 8)
    outline(node, palette.gold, 1)
    local badge = frame(node, 'Step', palette.gold, 999)
    outline(badge, palette.goldBright, 1)
    local badgeText = label(badge, 'Text', tostring(i), 9, palette.ink)
    badgeText.Font = Enum.Font.GothamBlack
    badgeText.Size = UDim2.fromScale(1, 1)
    local icon = label(node, 'Icon', '★', 22, palette.goldBright)
    icon.Font = Enum.Font.GothamBlack
    icon.Size = UDim2.new(1, -8, 0, 24)
    icon.Position = UDim2.fromOffset(4, 8)
    local nodeText = label(node, 'Text', '', 10, palette.cream)
    nodeText.Font = Enum.Font.GothamBlack
    nodeText.TextScaled = false
    nodeText.Size = UDim2.new(1, -8, 0, 15)
    nodeText.Position = UDim2.new(0, 4, 1, -23)
    local nodeHint = label(node, 'Hint', '', 8, palette.muted)
    nodeHint.Font = Enum.Font.GothamBold
    nodeHint.TextScaled = false
    nodeHint.Size = UDim2.new(1, -8, 0, 12)
    nodeHint.Position = UDim2.new(0, 4, 1, -11)
    diagramNodes[i] = { frame = node, text = nodeText, hint = nodeHint, icon = icon, badge = badge }
    if i < 4 then
      local arrow = label(contentBox, 'DiagramArrow' .. i, '›', 28, palette.goldBright)
      arrow.Font = Enum.Font.GothamBlack
      arrow.TextStrokeTransparency = 1
      diagramArrows[i] = arrow
    end
  end

  local rulesTexts = {
    basics = {
      title = '2v2 Partnership & Objectives',
      body = '• Teams: South (You) and North (Partner) form Team A; East and West form Team B.\n' ..
        '• Attacking vs Defending: The dealer team attacks and attempts to advance their level. The opposing defending team tries to capture points to overturn the dealers.\n' ..
        '• Level Climb: Both teams start at Level 2 and race to climb past Ace!\n' ..
        '• Declarations: During dealing, reveal your level cards to declare trump suit. Pair reveals strengthen trump lock.\n' ..
        '• The Kitty: The dealer takes the bottom kitty cards, reorganizes their hand, and buries equal cards. Kitty point cards are doubled or quadrupled at round end!',
    },
    ranks = {
      title = 'Strict Card Hierarchy (Trump Dominance)',
      body = '1. Big Red Joker (★ Red) — Highest card in the game\n' ..
        '2. Small Black Joker (★ Black) — Second highest\n' ..
        '3. Trump Level Rank (matches declared trump suit, e.g. 10♠ if spades declared)\n' ..
        '4. Off-Suit Level Ranks (matches current level in side suits, e.g. 10♥, 10♦, 10♣)\n' ..
        '5. Trump Suit Ace down to 2 (A, K, Q, J, 9, 8, 7, 6, 5, 4, 3, 2)\n' ..
        '6. Side Suits Ace down to 2 (Must follow suit led; cannot trump unless void in led suit!)',
    },
    tractors = {
      title = 'Tractor Combinations & Adjacent Pairs',
      body = '• What is a Tractor? 2 or more consecutive pairs in the same suit (e.g. 9♠ 9♠ 10♠ 10♠).\n' ..
        '• The Level Jump Rule: The active level rank is trump! Therefore, side suit pairs connect directly across the level (e.g. if 10 is trump, 9♦ 9♦ and J♦ J♦ connect into a tractor!).\n' ..
        '• Following Tractors: If a tractor is led, other players MUST follow with pairs and tractors of the led suit if they have them.\n' ..
        '• Trumping Tractors: A non-trump tractor can ONLY be beaten by a higher trump tractor with the same number of cards!',
    },
    scoring = {
      title = 'Point Cards & Shutout Multipliers',
      body = '• Point Cards: 5 = 5 pts, 10 = 10 pts, King = 10 pts. (100 total points in 2-deck).\n' ..
        '• 0 Defender Points: TOTAL SHUTOUT! Attackers advance +3 Levels!\n' ..
        '• < 40 Defender Points: SMALL SHUTOUT! Attackers advance +2 Levels!\n' ..
        '• 40 – 79 Points: Attackers advance +1 Level.\n' ..
        '• 80 – 119 Points: DEFENDERS OVERTURN! Defending team captures dealership!\n' ..
        '• 120+ Points: DEFENDERS OVERTURN + ADVANCE (+1 Level for Defenders)!',
    },
  }

  local illustration = frame(contentBox, 'LessonIllustration', palette.emeraldDark, 12)
  local scene = frame(illustration, 'Scene')
  scene.BackgroundTransparency = 1
  scene.Size = UDim2.fromOffset(520, 170)
  local sceneScale = make('UIScale', scene, 'ResponsiveScale', { Scale = 1 })
  local quizActive = false
  local function drawLesson(tabId)
    for _, child in ipairs(scene:GetChildren()) do
      if child ~= sceneScale then child:Destroy() end
    end
    local function caption(text, x, y, width, tint)
      local object = label(scene, 'Caption', text, 12, tint or palette.cream)
      rect(object, x, y, width, 24)
      return object
    end
    local function card(rank, suit, x, y, tint)
      local tile = frame(scene, 'ExampleCard', palette.cardFace, 7)
      rect(tile, x, y, 52, 78)
      outline(tile, tint or palette.cardBorder, 2)
      local ink = suit == '♥' and palette.red or palette.ink
      local index = label(tile, 'Rank', rank, 18, ink)
      rect(index, 3, 2, 44, 24)
      local pip = label(tile, 'Suit', suit, 28, ink)
      rect(pip, 5, 29, 42, 40)
    end
    if tabId == 'basics' then
      local tableShape = frame(scene, 'Table', color(25, 94, 77), 60)
      rect(tableShape, 135, 30, 250, 110)
      outline(tableShape, palette.panelBorder, 2)
      local connection = frame(scene, 'PartnerConnection', palette.teamBlue, 2)
      rect(connection, 258, 27, 4, 114)
      local function seat(text, x, y, tint)
        local plate = frame(scene, 'Seat', tint, 8)
        rect(plate, x, y, 110, 28)
        local title = label(plate, 'Name', text, 12, palette.white)
        title.Size = UDim2.fromScale(1, 1)
      end
      seat('PARTNER', 205, 5, palette.teamBlueDark)
      seat('YOU', 205, 137, palette.teamBlueDark)
      seat('OPPONENT', 44, 70, palette.teamRedDark)
      seat('OPPONENT', 366, 70, palette.teamRedDark)
      card('A', '♠', 188, 47)
      card('K', '♥', 280, 47)
    elseif tabId == 'tractors' then
      for i, rank in ipairs(quizActive and {'9', '9', 'J', 'J'} or {'9', '9', '10', '10'}) do
        card(rank, '♠', 104 + (i - 1) * 70, 35, palette.gold)
      end
      caption('PAIR', 104, 6, 122, palette.goldBright)
      caption(quizActive and 'SECOND PAIR' or 'NEXT PAIR', 244, 6, 122, palette.goldBright)
      local bracket = frame(scene, 'TractorBracket', palette.gold, 3)
      rect(bracket, 104, 123, 262, 3)
      caption(quizActive and 'LEVEL 2 • ARE THESE CARDS A TRACTOR?' or 'LEVEL 2 • ONE TRACTOR, FOUR CARDS', 40, 137, 440)
    elseif tabId == 'ranks' then
      local ranks = {'BIG', 'SMALL', '10', 'A'}
      local suits = {'★', '★', '♠', '♠'}
      for i = 1, 4 do
        card(ranks[i], suits[i], 62 + (i - 1) * 114, 44)
        if i < 4 then caption('>', 122 + (i - 1) * 114, 70, 36, palette.gold) end
      end
      caption('EXAMPLE: LEVEL 10 • SPADES ARE TRUMP', 20, 5, 480, palette.goldBright)
      caption('STRONGEST', 34, 133, 110)
      caption('TRUMP SUIT', 368, 133, 120)
    elseif tabId == 'declare' then
      caption('EXAMPLE: LEVEL 2', 20, 5, 480, palette.goldBright)
      card('2', '♥', 100, 42, palette.gold)
      caption('→', 185, 65, 50, palette.gold)
      card('2', '♥', 270, 42, palette.gold)
      card('2', '♥', 332, 42, palette.gold)
      caption('SINGLE REVEAL', 60, 133, 150)
      caption('PAIR REVEAL', 250, 133, 170)
    elseif tabId == 'kitty' then
      for i = 1, 3 do card('?', '♦', 72 + (i - 1) * 30, 32) end
      caption('→', 220, 56, 50, palette.gold)
      local pile = frame(scene, 'BuriedCards', palette.partnerBottom, 7)
      rect(pile, 330, 34, 62, 82)
      outline(pile, palette.gold, 2)
      caption('PICK UP BOTTOM', 38, 132, 180)
      caption('BURY EQUAL COUNT', 288, 132, 200)
    elseif tabId == 'follow' then
      card('A', '♠', 68, 30)
      caption('SPADES LED', 30, 116, 130)
      caption('→', 166, 56, 42, palette.gold)
      card('4', '♠', 246, 30, palette.green)
      card('K', '♥', 366, 30)
      caption('FOLLOW ♠', 218, 116, 110, palette.green)
      caption('KEEP ♥', 338, 116, 110)
      caption('WHEN YOU STILL HAVE SPADES', 110, 143, 330)
    elseif tabId == 'chaodi' then
      card('2', '♠', 78, 24, palette.gold)
      card('2', '♠', 140, 24, palette.gold)
      caption('→', 225, 48, 40, palette.gold)
      caption('TAKE KITTY', 300, 30, 160, palette.green)
      caption('RE-BURY', 300, 62, 160)
      caption('MULTIPLIER ×2', 300, 94, 160, palette.goldBright)
      caption('SAME SIZE: ♦ < ♣ < ♥ < ♠ < JOKERS', 20, 141, 480, palette.goldBright)
    else
      for i, rank in ipairs({'5', '10', 'K'}) do
        local x = 100 + (i - 1) * 132
        card(rank, '♥', x, 26)
        caption(i == 1 and '+5 POINTS' or '+10 POINTS', x - 24, 112, 100, palette.goldBright)
      end
      caption('Other ranks and jokers = 0 points', 30, 141, 460)
    end
  end

  local lessonProgress = label(ruModal, 'LessonProgress', '', 11, palette.muted)
  local quizControls = frame(contentBox, 'QuizControls')
  quizControls.BackgroundTransparency = 1
  local exercises = {
    basics = { question = 'Which player shares your team result?', answers = {'OPPOSITE', 'BESIDE YOU'}, correct = 1,
      explanation = 'Your partner sits opposite you. The players beside you are opponents.' },
    ranks = { question = 'Level 10, spades trump: which card is stronger?', answers = {'A OF SPADES', '10 OF SPADES'}, correct = 2,
      explanation = 'The trump level card, 10 of spades, ranks above the trump Ace.' },
    tractors = { question = 'At level 2, do these two pairs form a tractor?', answers = {'YES', 'NO'}, correct = 2,
      explanation = '10 sits between 9 and J at level 2. The missing rank breaks the tractor.' },
    scoring = { question = 'You capture all three cards shown. How many points?', answers = {'25 POINTS', '30 POINTS'}, correct = 1,
      explanation = '5 + 10 + 10 = 25 points. A King is worth 10, not 15.' },
  }
  local answerYes, answerNo
  local completedLessons = {}
  local function answerExercise(choice)
    if not quizActive then return end
    local exercise = exercises[currentRulesTab]
    local correct = choice == exercise.correct
    contentBody.Text = (correct and 'Correct! ' or 'Try again. ') .. exercise.explanation
    contentBody.TextColor3 = correct and palette.green or palette.goldBright
    if correct then completedLessons[currentRulesTab] = true end
    local selected = choice == 1 and answerYes or answerNo
    selected.Outline.Color = correct and palette.green or palette.gold
    selected.Outline.Thickness = 2
  end
  local tryExample = button(quizControls, 'TryExample', 'TRY AN EXAMPLE', function()
    quizActive = true
    drawLesson(currentRulesTab)
    contentBody.Text = exercises[currentRulesTab].question
    contentBody.TextColor3 = palette.cream
    answerYes.Visible = true
    answerNo.Visible = true
    answerYes.Outline.Color = palette.darkStroke
    answerNo.Outline.Color = palette.darkStroke
  end, palette.panelLight)
  answerYes = button(quizControls, 'AnswerYes', '', function() answerExercise(1) end, palette.panelLight)
  answerNo = button(quizControls, 'AnswerNo', '', function() answerExercise(2) end, palette.panelLight)
  answerYes.TextSize = 10
  answerNo.TextSize = 10
  local function selectRulesTab(tabId)
    quizActive = false
    contentBody.TextColor3 = palette.cream
    quizControls.Visible = tabId == 'tractors'
    answerYes.Visible = false
    answerNo.Visible = false
    answerYes.Text = 'YES'
    answerNo.Text = 'NO'
    tryExample.Text = completedLessons[tabId] and 'PRACTICE AGAIN' or 'TRY AN EXAMPLE'
    for i, def in ipairs(tabDefs) do
      if def.id == tabId then lessonProgress.Text = tostring(i) .. ' / ' .. tostring(#tabDefs) end
    end
    currentRulesTab = tabId
    for id, b in pairs(tabButtons) do
      local isActive = id == tabId
      b.BackgroundColor3 = isActive and palette.gold or palette.panel
      b.TextColor3 = isActive and palette.ink or palette.cream
    end
    local text = rulesTexts[tabId] or rulesTexts.basics
    contentTitle.Text = text.title
    local extraTitles = { declare = 'Choose the trump suit', kitty = 'Pick up and bury the bottom cards', follow = 'Follow the suit that was led', chaodi = 'Challenge the bottom: Chao Di' }
    contentTitle.Text = extraTitles[tabId] or text.title
    local captions = {
      basics = 'Your partner sits opposite you. You share a team result; the two players beside you are opponents.',
      ranks = 'Jokers beat level cards. Follow the led suit first; use trump when you have none of that suit.',
      tractors = 'Two matching 9s plus two matching 10s in the same suit form a tractor when those ranks are adjacent.',
      scoring = 'Capture 5s, 10s and Kings in winning tricks. These are the only point cards.',
      declare = 'Reveal level cards while dealing. Lit buttons show legal declarations; press the same suit again when a stronger reveal is available. Changing the trump suit doubles the stakes.',
      kitty = 'The kitty holder takes the bottom cards, then selects exactly the required number to bury. The counter shows how many you still need.',
      follow = 'If you have the led suit, you must follow it. Match the number of cards led; pairs and tractors also have matching requirements.',
      chaodi = 'On your turn, choose an available stronger reveal and confirm, or pass. More cards always wins. With the same number of cards, suits rank Diamonds < Clubs < Hearts < Spades, and jokers beat any suit. A successful challenge takes the kitty to re-bury and doubles the Chao Di multiplier. Three of a kind overturns a pair of jokers.',
    }
    contentBody.Text = captions[tabId]
    drawLesson(tabId)
    guideDiagram.Text = tabId == 'basics' and 'DEAL  →  DECLARE  →  BURY  →  PLAY' or (tabId == 'ranks' and 'JOKERS  >  TRUMP LEVEL  >  TRUMP SUIT  >  SIDE SUITS' or (tabId == 'tractors' and 'PAIR  +  PAIR  =  TRACTOR' or '5  /  10  /  K  →  POINTS  →  LEVELS'))
    local nodes, hints, icons
    if tabId == 'basics' then
      nodes, hints, icons = {'DEAL', 'DECLARE', 'BURY', 'PLAY'}, {'cards arrive', 'choose trump', 'hide kitty', 'win trick'}, {'A', '♠', 'K', '★'}
    elseif tabId == 'ranks' then
      nodes, hints, icons = {'BIG JOKER', 'SMALL JOKER', 'LEVEL CARD', 'SUIT'}, {'highest', 'second', 'current level', 'follow led'}, {'★', '☆', '10', '♣'}
    elseif tabId == 'tractors' then
      nodes, hints, icons = {'PAIR', 'NEXT PAIR', 'MATCH', 'TRACTOR'}, {'9♠ + 9♠', '10♠ + 10♠', 'same suit', 'play together'}, {'9', '+', '10', '⚡'}
    else
      nodes, hints, icons = {'FIVE', 'TEN', 'KING', 'LEVEL UP'}, {'5 points', '10 points', '10 points', 'capture more'}, {'5', '10', 'K', '↑'}
    end
    for i, node in ipairs(diagramNodes) do
      node.frame.Visible = false
      node.text.Text = nodes[i]
      node.hint.Text = hints[i]
      node.icon.Text = icons[i]
      node.frame.BackgroundColor3 = i == 4 and palette.goldDark or palette.emeraldDeep
      node.text.TextColor3 = i == 4 and palette.ink or palette.cream
      node.hint.TextColor3 = i == 4 and palette.ink or palette.muted
      node.icon.TextColor3 = palette.ink
    end
  end

  for _, def in ipairs(tabDefs) do
    local b = button(tabContainer, 'Tab_' .. def.id, def.label, function()
      selectRulesTab(def.id)
    end, palette.panel)
    b.TextSize = 10
    tabButtons[def.id] = b
  end

  local function stepLesson(delta)
    for i, def in ipairs(tabDefs) do
      if def.id == currentRulesTab then
        selectRulesTab(tabDefs[((i - 1 + delta) % #tabDefs) + 1].id)
        return
      end
    end
  end
  local previousLesson = button(ruModal, 'PreviousLesson', '← PREVIOUS', function() stepLesson(-1) end, palette.panelLight)
  local nextLesson = button(ruModal, 'NextLesson', 'NEXT LESSON →', function() stepLesson(1) end)
  local function layoutRules()
    local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
    local rmW = safeClamp(w - 40, 420, 620)
    local rmH = safeClamp(h - 40, 390, 540)
    rect(ruModal, (w - rmW) / 2, (h - rmH) / 2, rmW, rmH)
    rect(ruTitle, 20, 14, rmW - 70, 26)
    rect(ruClose, rmW - 44, 12, 32, 32)

    rect(tabContainer, 18, 52, rmW - 36, 70)
    local tW = math.floor((rmW - 36 - 16) / 4)
    for i, def in ipairs(tabDefs) do
      rect(tabButtons[def.id], 4 + (tW + 4) * ((i - 1) % 4), 3 + math.floor((i - 1) / 4) * 34, tW, 30)
    end

    rect(contentBox, 18, 132, rmW - 36, rmH - 198)
    rect(previousLesson, 18, rmH - 52, 150, 34)
    rect(nextLesson, rmW - 188, rmH - 52, 170, 34)
    rect(lessonProgress, rmW / 2 - 24, rmH - 46, 48, 22)
    rect(contentTitle, 16, 12, rmW - 68, 22)
    rect(guideVisual, rmW - 126, 38, 74, 54)
    guideDiagram.Visible = false
    local visualScale = math.min((rmW - 68) / 520, math.max(0.25, (rmH - 354) / 170))
    rect(illustration, 16, 42, rmW - 68, 170 * visualScale)
    sceneScale.Scale = visualScale
    scene.Position = UDim2.fromOffset((rmW - 68 - 520 * visualScale) / 2, 0)
    local nodeW = math.floor((rmW - 92) / 4)
    for i, node in ipairs(diagramNodes) do
      rect(node.frame, 16 + (i - 1) * (nodeW + 8), 66, nodeW, 100)
      rect(node.badge, 7, 7, 18, 18)
      rect(node.icon, 30, 5, nodeW - 36, 54)
      node.icon.BackgroundTransparency = 0
      node.icon.BackgroundColor3 = palette.cardFace
      rect(node.text, 4, 68, nodeW - 8, 15)
      rect(node.hint, 4, 84, nodeW - 8, 11)
    end
    for i, arrow in ipairs(diagramArrows) do
      arrow.Visible = false
      rect(arrow, 16 + i * (nodeW + 4) - 8, 80, 16, 28)
    end
    rect(contentBody, 16, 48 + 170 * visualScale, rmW - 68, 42)
    rect(quizControls, 16, 96 + 170 * visualScale, rmW - 68, 30)
    local quizWidth = (rmW - 84) / 3
    rect(tryExample, 0, 0, quizWidth, 28)
    rect(answerYes, quizWidth + 8, 0, quizWidth, 28)
    rect(answerNo, (quizWidth + 8) * 2, 0, quizWidth, 28)
  end

  -- Seed the first lesson immediately so the guide is never an empty shell if
  -- it is opened by automation or restored while the lobby is still resizing.
  selectRulesTab('basics')

  C.openRulesModal = function(tabId)
    layoutRules()
    selectRulesTab(tabId or 'basics')
    ruShade.Visible = true
  end

  rulesUI.shade = ruShade
  rulesUI.layout = layoutRules
end
arenaUI.initRulesModal()

local mailUI = {} C.mailUI = mailUI
function arenaUI.initMailModal()
  local mShade = button(root, 'MailShade', '', function() end, palette.emeraldDark)
  mShade.BackgroundTransparency = 0.22
  mShade.Size = UDim2.fromScale(1, 1)
  mShade.Visible = false
  mShade.ZIndex = 58

  local mModal = frame(mShade, 'MailModal', palette.panel, 20)
  outline(mModal, palette.railOuter, 1.5)

  local mTitle = label(mModal, 'Title', 'CLUB MAILBOX', 18, palette.gold)
  mTitle.Font = Enum.Font.FredokaOne
  local mClose = button(mModal, 'Close', '×', function() mShade.Visible = false end, palette.panelLight)
  mClose.TextSize = 16

  local mailCard1 = frame(mModal, 'Mail1', palette.tileBg, 10)
  outline(mailCard1, palette.panelBorder, 1)
  local m1Title = label(mailCard1, 'Title', 'Welcome to Tractor Card Club!', 12, palette.goldBright)
  m1Title.Font = Enum.Font.GothamBold
  m1Title.TextXAlignment = Enum.TextXAlignment.Left
  local m1Body = label(mailCard1, 'Body', 'Welcome to official Tractor 2v2 party play. Enjoy +1.0K starting chips on us!', 10, palette.cream)
  m1Body.TextXAlignment = Enum.TextXAlignment.Left

  local mailCard2 = frame(mModal, 'Mail2', palette.tileBg, 10)
  outline(mailCard2, palette.panelBorder, 1)
  local m2Title = label(mailCard2, 'Title', 'Daily Welfare Grant', 12, palette.goldBright)
  m2Title.Font = Enum.Font.GothamBold
  m2Title.TextXAlignment = Enum.TextXAlignment.Left
  local m2Body = label(mailCard2, 'Body', 'Play matches, communicate with table emotes, and claim your +500 welfare bonus!', 10, palette.cream)
  m2Body.TextXAlignment = Enum.TextXAlignment.Left

  local claimMailBtn = button(mModal, 'ClaimMail', 'CLAIM MAILBOX BONUS (+1.5K COINS)', function()
    remote:FireServer('claim_mail')
    if home and home.mailDot then home.mailDot.Visible = false end
    task.delay(0.2, function() mShade.Visible = false end)
  end)
  claimMailBtn.TextSize = 13

  local function layoutMail()
    local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
    local mmW = safeClamp(w - 40, 380, 500)
    local mmH = 290
    rect(mModal, (w - mmW) / 2, (h - mmH) / 2, mmW, mmH)
    rect(mTitle, 20, 14, mmW - 70, 26)
    rect(mClose, mmW - 44, 12, 32, 32)

    rect(mailCard1, 20, 52, mmW - 40, 68)
    rect(m1Title, 14, 8, mmW - 68, 20)
    rect(m1Body, 14, 28, mmW - 68, 34)

    rect(mailCard2, 20, 130, mmW - 40, 68)
    rect(m2Title, 14, 8, mmW - 68, 20)
    rect(m2Body, 14, 28, mmW - 68, 34)

    rect(claimMailBtn, 20, 218, mmW - 40, 42)
  end

  C.openMailModal = function()
    layoutMail()
    mShade.Visible = true
  end

  mailUI.shade = mShade
  mailUI.layout = layoutMail
end
arenaUI.initMailModal()

local luckyUI = {} C.luckyUI = luckyUI
function arenaUI.initLuckyModal()
  local lShade = button(root, 'LuckyShade', '', function() end, palette.emeraldDark)
  lShade.BackgroundTransparency = 0.22
  lShade.Size = UDim2.fromScale(1, 1)
  lShade.Visible = false
  lShade.ZIndex = 58

  local lModal = frame(lShade, 'LuckyModal', palette.panel, 20)
  outline(lModal, palette.gold, 1.8)

  local lTitle = label(lModal, 'Title', 'DAILY LUCKY WHEEL', 18, palette.goldBright)
  lTitle.Font = Enum.Font.FredokaOne
  local lClose = button(lModal, 'Close', '×', function() lShade.Visible = false end, palette.panelLight)
  lClose.TextSize = 16

  local prizes = {
    { text = '2K Coins', offset = 0 }, { text = '3K Coins', offset = 0 },
    { text = '5K Coins', offset = 0 }, { text = '7.5K Coins', offset = 0 },
    { text = '10K Coins', offset = 0 }, { text = '15K Coins', offset = 0 },
    { text = '25K Coins', offset = 512 }, { text = '50K JACKPOT', offset = 1536 },
  }

  local prizeCards = {}
  local gridFrame = frame(lModal, 'Grid', palette.emeraldDark, 12)
  outline(gridFrame, palette.panelBorder, 1)

  for i, p in ipairs(prizes) do
    local c = frame(gridFrame, 'Prize' .. i, palette.tileBg, 8)
    local isJackpot = i == 8
    outline(c, isJackpot and palette.goldBright or palette.panelBorder, 1)
    local ic = flatCoinIcon(c, 'Icon')
    local tx = label(c, 'Text', p.text, 10, isJackpot and palette.goldBright or palette.cream)
    tx.Font = Enum.Font.GothamBold
    prizeCards[i] = { frame = c, outline = c:FindFirstChild('Outline'), icon = ic, text = tx }
  end

  local isSpinning = false
  local spinBtn
  -- Time until tomorrow's free spin, from the server's last message.
  local function resetLeft()
    local s = C.state
    if not (s and s.luckyResetIn) then return 0 end
    return math.max(0, s.luckyResetIn - (os.clock() - (C.receivedAt or os.clock())))
  end
  local function spunToday() return C.state ~= nil and C.state.luckySpun == true and resetLeft() > 0 end
  local function refreshSpinButton()
    if isSpinning then return end
    if spunToday() then
      local left = resetLeft()
      spinBtn.Text = string.format('NEXT FREE SPIN IN %dH %02dM', math.floor(left / 3600), math.floor(left % 3600 / 60))
    else
      spinBtn.Text = 'SPIN LUCKY WHEEL! (FREE)'
    end
  end
  local function highlight(idx)
    for j, pc in ipairs(prizeCards) do
      if pc.outline then
        pc.outline.Color = j == idx and palette.goldBright or (j == 8 and palette.gold or palette.panelBorder)
        pc.outline.Thickness = j == idx and 3 or 1
      end
      pc.frame.BackgroundColor3 = j == idx and palette.tileHover or palette.tileBg
    end
  end
  spinBtn = button(lModal, 'SpinBtn', 'SPIN LUCKY WHEEL! (FREE)', function()
    if isSpinning then return end
    if spunToday() then refreshSpinButton(); playSound('error'); return end
    isSpinning = true
    spinBtn.Text = 'SPINNING…'
    remote:FireServer('lucky_spin')
    task.spawn(function()
      -- Spin until the server says which prize was won (up to ~4s), then
      -- slow down and stop exactly on that prize.
      local idx, target, waited = 0, nil, 0
      while not target and waited < 4 do
        idx = idx % #prizes + 1
        highlight(idx)
        playSound('click')
        task.wait(0.05); waited += 0.05
        target = C.state and C.state.luckyResult
      end
      if target then
        local steps = 8 + ((target - idx - 1) % #prizes) + 1
        for step = 1, steps do
          idx = idx % #prizes + 1
          highlight(idx)
          playSound('click')
          task.wait(0.05 + (step / steps) * 0.18)
        end
        playSound('coin')
      end
      task.wait(0.4)
      isSpinning = false
      refreshSpinButton()
    end)
  end)
  spinBtn.TextSize = 13
  lShade:GetPropertyChangedSignal('Visible'):Connect(function()
    if lShade.Visible then refreshSpinButton() end
  end)
  task.spawn(function()
    while true do
      task.wait(20)
      if lShade.Visible then refreshSpinButton() end
    end
  end)

  local function layoutLucky()
    local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
    local lmW = safeClamp(w - 40, 380, 520)
    local lmH = 340
    rect(lModal, (w - lmW) / 2, (h - lmH) / 2, lmW, lmH)
    rect(lTitle, 20, 14, lmW - 70, 26)
    rect(lClose, lmW - 44, 12, 32, 32)

    rect(gridFrame, 18, 52, lmW - 36, 210)
    local cW = math.floor((lmW - 36 - 28) / 4)
    local cH = math.floor((210 - 20) / 2)
    for i = 1, 8 do
      local col = (i - 1) % 4
      local row = math.floor((i - 1) / 4)
      local pc = prizeCards[i]
      rect(pc.frame, 8 + (cW + 4) * col, 8 + (cH + 4) * row, cW, cH)
      rect(pc.icon, math.floor((cW - 24) / 2), 8, 24, 24)
      rect(pc.text, 0, 42, cW, 20)
    end

    rect(spinBtn, 20, 276, lmW - 40, 42)
  end

  C.openLuckyModal = function()
    layoutLucky()
    lShade.Visible = true
  end

  luckyUI.shade = lShade
  luckyUI.layout = layoutLucky
end
arenaUI.initLuckyModal()

local vaultUI = {} C.vaultUI = vaultUI
function arenaUI.initVaultModal()
  local vShade = button(root, 'VaultShade', '', function() end, palette.emeraldDark)
  vShade.BackgroundTransparency = 0.22
  vShade.Size = UDim2.fromScale(1, 1)
  vShade.Visible = false
  vShade.ZIndex = 58

  local vModal = frame(vShade, 'VaultModal', palette.panel, 20)
  outline(vModal, palette.railOuter, 1.5)

  local vTitle = label(vModal, 'Title', 'MATCH COIN VAULT', 18, palette.gold)
  vTitle.Font = Enum.Font.FredokaOne
  local vClose = button(vModal, 'Close', '×', function() vShade.Visible = false end, palette.panelLight)
  vClose.TextSize = 16

  local vCard = frame(vModal, 'Card', palette.tileBg, 12)
  outline(vCard, palette.gold, 1.2)
  local vIcon = flatCoinIcon(vCard, 'Icon')
  local vAmt = label(vCard, 'Amt', '1.5K COINS BANKED', 18, palette.goldBright)
  vAmt.Font = Enum.Font.FredokaOne
  local vDesc = label(vCard, 'Desc', 'Every time you capture point cards or complete matches, coins accumulate in your personal vault. Crack the vault to add them to your wallet!', 10, palette.muted)

  local crackBtn = button(vModal, 'Crack', 'CRACK VAULT & CLAIM COINS', function()
    remote:FireServer('claim_vault')
    task.delay(0.2, function() vShade.Visible = false end)
  end)
  crackBtn.TextSize = 13

  local function layoutVault()
    local w, h = root.AbsoluteSize.X, root.AbsoluteSize.Y
    local vmW = safeClamp(w - 40, 360, 480)
    local vmH = 280
    rect(vModal, (w - vmW) / 2, (h - vmH) / 2, vmW, vmH)
    rect(vTitle, 20, 14, vmW - 70, 26)
    rect(vClose, vmW - 44, 12, 32, 32)

    rect(vCard, 20, 52, vmW - 40, 140)
    rect(vIcon, math.floor((vmW - 40 - 48) / 2), 8, 48, 48)
    rect(vAmt, 0, 58, vmW - 40, 24)
    rect(vDesc, 14, 88, vmW - 68, 44)

    rect(crackBtn, 20, 208, vmW - 40, 42)

    local currentVault = (C.state and C.state.vaultCoins) or 1500
    vAmt.Text = formatK(currentVault) .. ' COINS BANKED'
  end

  C.openVaultModal = function()
    layoutVault()
    vShade.Visible = true
  end

  vaultUI.shade = vShade
  vaultUI.layout = layoutVault
end
arenaUI.initVaultModal()

home.shopBtn.Activated:Connect(function()
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.selectShopTab('cardBack')
  C.shade.Visible = true
  if C.renderShopItems then C.renderShopItems() end
end)
home.emoteBtn.Activated:Connect(function()
  if C.updateCoinDisplays then C.updateCoinDisplays() end
  C.selectShopTab('emote')
  C.shade.Visible = true
  if C.renderShopItems then C.renderShopItems() end
end)
home.historyBtn.Activated:Connect(function()
  arenaUI.openStats()
end)
home.coinPill.InputBegan:Connect(function(input)
  if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
    if C.updateCoinDisplays then C.updateCoinDisplays() end
    C.selectShopTab('product')
    C.shade.Visible = true
    if C.renderShopItems then C.renderShopItems() end
  end
end)
home.vipBadge.InputBegan:Connect(function(input)
  if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
    if C.updateCoinDisplays then C.updateCoinDisplays() end
    C.selectShopTab('product')
    C.shade.Visible = true
    if C.renderShopItems then C.renderShopItems() end
  end
end)

local emoteButtons = {} C.emoteButtons = emoteButtons
end
