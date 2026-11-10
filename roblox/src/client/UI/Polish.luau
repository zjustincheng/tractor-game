-- Clamp that tolerates max < min (tiny phone screens) instead of erroring.
local function safeClamp(v, lo, hi) if hi < lo then hi = lo end return math.clamp(v, lo, hi) end
-- Happy Tractor client: visual polish for the home screen and tier picker.
-- Runs after the screens are built and restyles them in the shop's look:
-- bright gradient cards, big art, chunky titles and coloured buttons. It
-- wraps C.resize so its extra pieces follow the layout.
return function(C)
local arenaUI, corner, frame, label, make, outline, palette = C.arenaUI, C.corner, C.frame, C.label, C.make, C.outline, C.palette
local rect, tween = C.rect, C.tween
local RunService = game:GetService('RunService')
local color = Color3.fromRGB
local INK = color(20, 16, 30)
local home, tier = C.home, C.tier
if not (home and tier) then return end

local function chunky(parent, name, text, size, tint)
  local l = label(parent, name, text, size, tint or palette.white)
  l.Font = Enum.Font.FredokaOne
  l.TextWrapped = false
  make('UIStroke', l, 'Stroke', { Color = INK, Thickness = math.max(1.5, size / 10), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
  return l
end

-- Replace a frame's gradient with a bright one. UIGradient multiplies the
-- background colour, so the base goes white for the true colours to show.
local function brighten(object, top, bottom, rotation)
  if not object then return end
  object.BackgroundColor3 = palette.white
  local g = object:FindFirstChild('Gradient') or make('UIGradient', object, 'Gradient', {})
  g.Color = ColorSequence.new(top, bottom)
  g.Rotation = rotation or 90
  g.Transparency = NumberSequence.new(0)
end

local function chunkyButton(btn, size)
  if not btn then return end
  btn.Font = Enum.Font.FredokaOne
  btn.TextSize = size or 16
  if not btn:FindFirstChild('TextStroke') then
    make('UIStroke', btn, 'TextStroke', { Color = color(255, 246, 210), Thickness = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
  end
  local border = btn:FindFirstChild('Outline')
  if border then border.Color = INK; border.Thickness = 2; border.Transparency = 0 end
end

-- ===== Home: game mode cards =====
local MODES = {
  { card = home.mode1, top = color(255, 150, 50), bottom = color(196, 64, 14), title = 'CLASSIC', sub = '4 PLAYERS · 2 DECKS', fan = 3 },
  { card = home.mode2, top = color(70, 160, 255), bottom = color(22, 62, 170), title = '4-DECK EPIC', sub = '8 PLAYERS · 4 DECKS', fan = 4 },
  { card = home.mode3, top = color(190, 100, 255), bottom = color(84, 24, 160), title = '5-DECK MEGA', sub = '10 PLAYERS · 5 DECKS', fan = 5 },
  { card = home.mode4, top = color(70, 214, 150), bottom = color(14, 120, 86), title = '3-DECK TEAM', sub = '6 PLAYERS · 3 DECKS', fan = 4 },
}
local FAN_CARDS = {
  { rank = 'A', suit = 'spades' }, { rank = 'K', suit = 'hearts' }, { rank = 'Q', suit = 'diamonds' },
  { rank = 'J', suit = 'clubs' }, { joker = 'big' },
}
for index, mode in ipairs(MODES) do
  local card = mode.card
  if card then
    brighten(card, mode.top, mode.bottom, 90)
    local stroke = card:FindFirstChild('Outline')
    if stroke then stroke.Color = color(255, 236, 170); stroke.Thickness = index == 1 and 2.5 or 2 end
    local thumb = card:FindFirstChild('Thumb')
    if thumb then
      thumb.BackgroundTransparency = 1
      local thumbStroke = thumb:FindFirstChild('Outline')
      if thumbStroke then thumbStroke.Enabled = false end
      for _, name in ipairs({ 'Card1', 'Card2', 'Chip', 'TitleBanner' }) do
        local old = thumb:FindFirstChild(name)
        if old then old.Visible = false end
      end
      local g = thumb:FindFirstChild('Gradient'); if g then g.Enabled = false end
    end
    local oldBadge = card:FindFirstChild('Badge'); if oldBadge then oldBadge.Visible = false end
    local oldDesc = card:FindFirstChild('Description'); if oldDesc then oldDesc.Visible = false end
    -- light rays and a soft spotlight behind a fan of real cards
    local art = make('Frame', card, 'PolishArt', { BackgroundTransparency = 1, ClipsDescendants = false })
    local glow = frame(art, 'Glow', palette.white, 999)
    glow.BackgroundTransparency = 0.82
    glow.AnchorPoint = Vector2.new(0.5, 0.5)
    mode.glow = glow
    mode.fanCards = {}  -- built in layout: card faces lay out at creation size
    mode.art = art
    mode.titleLabel = chunky(card, 'PolishTitle', mode.title, 22, palette.white)
    mode.subLabel = label(card, 'PolishSub', mode.sub, 11, color(255, 246, 214))
    mode.subLabel.Font = Enum.Font.GothamBlack
    mode.subLabel.TextWrapped = false
    mode.button = card:FindFirstChild('Action')
    chunkyButton(mode.button, 17)
    mode.phase = index * 1.1
  end
end

-- ===== Home: bottom bar buttons get an icon and their own colour =====
local NAV = {
  { home.shopBtn, '🛒  SHOP', color(255, 120, 150), color(196, 40, 90) },
  { home.historyBtn, '📊  STATS', color(90, 170, 255), color(30, 80, 190) },
  { home.rewardsBtn, '🎁  REWARDS', color(110, 230, 140), color(24, 140, 70) },
  { home.luckyBtn, '🍀  LUCKY', color(190, 120, 255), color(96, 40, 180) },
  { home.vaultBtn, '🏦  VAULT', color(80, 220, 220), color(14, 120, 140) },
}
for _, nav in ipairs(NAV) do
  local btn = nav[1]
  if btn then
    -- A gradient on the button would tint its text too, so the gradient
    -- lives on a background child and the text on a label above it.
    btn.Text = ''
    btn.BackgroundTransparency = 1
    local oldGrad = btn:FindFirstChild('Gradient'); if oldGrad then oldGrad.Enabled = false end
    local bg = frame(btn, 'Bg', palette.white, 10)
    bg.Size = UDim2.fromScale(1, 1)
    make('UIGradient', bg, 'Gradient', { Color = ColorSequence.new(nav[3], nav[4]), Rotation = 90 })
    local text = label(btn, 'Label', nav[2], 15, palette.white)
    text.Font = Enum.Font.FredokaOne
    text.TextWrapped = false
    text.Size = UDim2.fromScale(1, 1)
    text.TextStrokeColor3 = INK
    text.TextStrokeTransparency = 0.15
    nav.label = text
    local border = btn:FindFirstChild('Outline')
    if border then border.Color = INK; border.Thickness = 2; border.Transparency = 0.1 end
  end
end
chunkyButton(tier.createPrivate, 14)
chunkyButton(home.heroBtn, 18)

-- ===== Tier picker: bright tier cards with the coin pack art =====
local TIERS = {
  { card = tier.cardNovice, top = color(76, 214, 120), bottom = color(18, 120, 64), image = 'rbxassetid://84997199523345' },
  { card = tier.cardPro, top = color(70, 160, 255), bottom = color(22, 62, 170), image = 'rbxassetid://83669766952611' },
  { card = tier.cardMaster, top = color(196, 100, 255), bottom = color(80, 20, 150), image = 'rbxassetid://75326390158213' },
}
for index, t in ipairs(TIERS) do
  local card = t.card
  if card then
    brighten(card, t.top, t.bottom, 90)
    local stack = card:FindFirstChild('ChipStack')
    if stack then stack.Visible = false end
    local glow = frame(card, 'PolishGlow', palette.white, 999)
    glow.BackgroundTransparency = 0.84
    glow.AnchorPoint = Vector2.new(0.5, 0.5)
    t.glow = glow
    t.art = make('ImageLabel', card, 'PolishArt', { BackgroundTransparency = 1, Image = t.image, ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5) })
    local pill = card:FindFirstChild('StakePill')
    if pill then pill.BackgroundColor3 = color(14, 18, 34); pill.BackgroundTransparency = 0.35 end
    local val = pill and pill:FindFirstChild('Val')
    if val then
      val.Font = Enum.Font.FredokaOne
      if not val:FindFirstChild('Stroke') then make('UIStroke', val, 'Stroke', { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual }) end
    end
    local entry = card:FindFirstChild('Entry')
    if entry then entry.TextColor3 = color(255, 246, 214); entry.Font = Enum.Font.GothamBlack end
    chunkyButton(card:FindFirstChild('JoinBtn'), 17)
    t.phase = index * 1.4
  end
end

-- ===== Layout: runs after the original resize =====
local function layoutPolish()
  for _, mode in ipairs(MODES) do
    local card = mode.card
    if card and mode.art and card.Visible ~= nil then
      local w, h = card.Size.X.Offset, card.Size.Y.Offset
      if w > 0 and h > 0 then
        local thumb = card:FindFirstChild('Thumb')
        if thumb then rect(thumb, 0, 0, w, h) end
        -- The base layout re-shows the old description; the art replaces it.
        local oldDesc = card:FindFirstChild('Description'); if oldDesc then oldDesc.Visible = false end
        local btnH = 34
        if mode.button then rect(mode.button, 10, h - btnH - 8, w - 20, btnH) end
        local titleY = h - btnH - 8 - 44
        rect(mode.titleLabel, 8, titleY, w - 16, 26)
        mode.titleLabel.TextSize = safeClamp(math.floor(w / 11), 16, 24)
        rect(mode.subLabel, 8, titleY + 26, w - 16, 14)
        local artTop, artBottom = 8, titleY - 4
        local artH = math.max(30, artBottom - artTop)
        rect(mode.art, 0, artTop, w, artH)
        local ch = safeClamp(math.floor(artH * 0.82), 40, 96)
        local cw = math.floor(ch * 0.7)
        if mode.fanSize ~= ch then
          for _, old in ipairs(mode.fanCards) do old:Destroy() end
          mode.fanCards = {}
          for i = 1, mode.fan do
            local face = C.cardFace(mode.art, FAN_CARDS[i], 'FanCard' .. i, cw, ch)
            face.AnchorPoint = Vector2.new(0.5, 1)
            -- At this size the upside-down corner and the big centre rank of the
            -- cards underneath read as stray letters; keep only what shows cleanly.
            for _, part in ipairs({ 'SubRank', 'SubCorner' }) do
              local hidden = face:FindFirstChild(part, true)
              if hidden then hidden.Visible = false end
            end
            if i < mode.fan then
              for _, part in ipairs({ 'Letter', 'Suit', 'CourtPanel' }) do
                local hidden = face:FindFirstChild(part)
                if hidden then hidden.Visible = false end
              end
            end
            table.insert(mode.fanCards, face)
          end
          mode.fanSize = ch
        end
        local n = #mode.fanCards
        local spread = math.min(cw * 0.55, (w * 0.5) / math.max(1, n - 1))
        for i, face in ipairs(mode.fanCards) do
          local k = (i - (n + 1) / 2)
          face.Position = UDim2.fromOffset(w / 2 + k * spread, artH - 2 + math.abs(k) * 4)
          face.Rotation = k * 9
        end
        mode.glow.Size = UDim2.fromOffset(ch * 1.6, ch * 1.6)
        mode.glow.Position = UDim2.fromOffset(w / 2, artH * 0.55)
        mode.artH = artH
      end
    end
  end
  for _, t in ipairs(TIERS) do
    local card = t.card
    if card and t.art then
      local w, h = card.Size.X.Offset, card.Size.Y.Offset
      local short = h < 380
      t.art.Visible, t.glow.Visible = not short, not short
      if not short then
        local pill = card:FindFirstChild('StakePill')
        local pillY = pill and pill.Position.Y.Offset or 140
        local top = 52
        local size = safeClamp(math.min(w - 40, pillY - top - 8), 60, 170)
        t.cx, t.cy = w / 2, top + (pillY - top) / 2
        t.art.Size = UDim2.fromOffset(size, size)
        t.glow.Size = UDim2.fromOffset(size * 1.15, size * 1.15)
        t.glow.Position = UDim2.fromOffset(t.cx, t.cy)
      end
    end
  end
end

-- Push the tier-card content down so the art gets the space under the banner.
local baseResize = C.resize
C.resize = function(...)
  baseResize(...)
  for _, t in ipairs(TIERS) do
    local card = t.card
    if card and card.Size.Y.Offset >= 380 then
      local pill, entry = card:FindFirstChild('StakePill'), card:FindFirstChild('Entry')
      local h = card.Size.Y.Offset
      if pill then
        local pillY = math.max(pill.Position.Y.Offset, h - 196)
        pill.Position = UDim2.fromOffset(pill.Position.X.Offset, pillY)
        if entry then entry.Position = UDim2.fromOffset(entry.Position.X.Offset, pillY + 62) end
      end
      local desc = card:FindFirstChild('Desc'); if desc then desc.Visible = false end
    end
    -- the base layout re-shows the old chip stack; the coin art replaces it
    local stack = card and card:FindFirstChild('ChipStack'); if stack then stack.Visible = false end
  end
  for _, tab in ipairs({ tier.tab4P, tier.tab6P, tier.tab8P, tier.tab10P }) do
    if tab then tab.Font = Enum.Font.FredokaOne; tab.TextSize = 15 end
  end
  layoutPolish()
  for _, nav in ipairs(NAV) do
    if nav[1] then nav[1].Text = '' end
  end
end

-- ===== Idle animation: cards breathe, coin art floats =====
RunService.RenderStepped:Connect(function()
  local now = os.clock()
  if home.view and home.view.Visible then
    for _, mode in ipairs(MODES) do
      if mode.art and mode.artH then
        mode.art.Position = UDim2.fromOffset(0, 8 + math.sin(now * 1.8 + mode.phase) * 3)
      end
    end
  end
  if tier.view and tier.view.Visible then
    for _, t in ipairs(TIERS) do
      if t.cx and t.art then
        t.art.Position = UDim2.fromOffset(t.cx, t.cy + math.sin(now * 2 + t.phase) * 5)
        t.art.Rotation = math.sin(now * 1.3 + t.phase) * 3
      end
    end
  end
end)
end
