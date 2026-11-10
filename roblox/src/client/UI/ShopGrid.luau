-- Clamp that tolerates max < min (tiny phone screens) instead of erroring.
local function safeClamp(v, lo, hi) if hi < lo then hi = lo end return math.clamp(v, lo, hi) end
-- Happy Tractor client: the Emotes, Card Backs and Table Felts tabs of the
-- shop, as grids of rarity-coloured tiles with a big preview of each item.
-- Rarity comes from the price within its tab: free items are Common, paid
-- items split into Rare, Epic and Legendary from cheapest to dearest.
-- Only the price button buys or equips, so a stray click never spends coins.
return function(C)
local Catalog, arenaUI, corner, formatK, frame = C.Catalog, C.arenaUI, C.corner, C.formatK, C.frame
local gradient, label, make, outline, palette, playSound = C.gradient, C.label, C.make, C.outline, C.palette, C.playSound
local rect, remote, tween = C.rect, C.remote, C.tween
local RunService = game:GetService('RunService')
local color = Color3.fromRGB
local INK = color(20, 16, 30)

local RARITY = {
  COMMON = { top = color(78, 96, 124), bottom = color(34, 44, 64), rim = color(150, 170, 200), pill = color(150, 170, 200) },
  RARE = { top = color(64, 146, 255), bottom = color(20, 52, 140), rim = color(150, 205, 255), pill = color(90, 170, 255) },
  EPIC = { top = color(176, 96, 255), bottom = color(72, 24, 152), rim = color(220, 175, 255), pill = color(190, 120, 255) },
  LEGENDARY = { top = color(255, 192, 64), bottom = color(196, 84, 12), rim = color(255, 238, 165), pill = color(255, 200, 70) },
}
local TABS = { emote = true, cardBack = true, felt = true }

local function chunky(parent, name, text, size, tint)
  local l = label(parent, name, text, size, tint or palette.white)
  l.Font = Enum.Font.FredokaOne
  l.TextWrapped = false
  make('UIStroke', l, 'Stroke', { Color = INK, Thickness = math.max(1.4, size / 11), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
  return l
end

-- Items per tab, and each paid item's rarity from its price rank.
local byTab, rarityOf = {}, {}
for _, item in ipairs(Catalog) do
  local tab = item.category or 'emote'
  if TABS[tab] then
    byTab[tab] = byTab[tab] or {}
    table.insert(byTab[tab], item)
  end
end
for _, items in pairs(byTab) do
  local paid = {}
  for _, item in ipairs(items) do if (item.price or 0) > 0 then table.insert(paid, item) end end
  table.sort(paid, function(a, b) return a.price < b.price end)
  for rank, item in ipairs(paid) do
    local f = rank / #paid
    rarityOf[item.id] = f <= 1 / 3 and 'RARE' or (f <= 2 / 3 and 'EPIC' or 'LEGENDARY')
  end
  for _, item in ipairs(items) do rarityOf[item.id] = rarityOf[item.id] or 'COMMON' end
end

-- ===== Previews =====
local function feltPreview(parent, theme)
  local holder = make('Frame', parent, 'Preview', { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5) })
  local table_ = frame(holder, 'Table', theme.bottom, 999)
  table_.Size = UDim2.fromScale(1, 1)
  gradient(table_, theme.top, theme.bottom, 90)
  outline(table_, theme.railOuter, 5)
  local inner = frame(table_, 'Inner', theme.top, 999)
  inner.BackgroundTransparency = 1
  inner.AnchorPoint = Vector2.new(0.5, 0.5)
  inner.Position = UDim2.fromScale(0.5, 0.5)
  inner.Size = UDim2.new(1, -14, 1, -14)
  outline(inner, theme.railInner, 2).Transparency = 0.2
  for i, spec in ipairs({ { '♥', color(220, 38, 38), -12, 0.42 }, { '♠', color(20, 24, 32), 10, 0.58 } }) do
    local card = frame(table_, 'Card' .. i, palette.cardFace, 4)
    card.AnchorPoint = Vector2.new(0.5, 0.5)
    card.Position = UDim2.fromScale(spec[4], 0.5)
    card.Size = UDim2.fromScale(0.16, 0.5)
    card.Rotation = spec[3]
    outline(card, palette.cardBorder, 1)
    local suit = label(card, 'Suit', spec[1], 16, spec[2])
    suit.Size = UDim2.fromScale(1, 1)
    suit.TextScaled = true
  end
  return holder
end

local function cardBackPreview(parent, id, w, h)
  local holder = make('Frame', parent, 'Preview', { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(w * 1.5, h * 1.1) })
  make('UIScale', holder, 'Fit', { Scale = 1 })  -- sized to the tile in layout
  local back = C.renderCardBack(holder, w, h, id)
  back.AnchorPoint = Vector2.new(0.5, 0.5)
  back.Position = UDim2.new(0.5, -w * 0.18, 0.5, 2)
  back.Rotation = -9
  local front = C.renderCardBack(holder, w, h, id)
  front.AnchorPoint = Vector2.new(0.5, 0.5)
  front.Position = UDim2.new(0.5, w * 0.16, 0.5, 0)
  front.Rotation = 7
  return holder
end

-- ===== Tiles =====
local tiles = {}  -- tab -> list of tile records
local function actionFor(item)
  local s = C.state
  if not s then return end
  local owned = s.owned and s.owned[item.id]
  local tab = item.category or 'emote'
  if tab == 'emote' then
    if owned then arenaUI.sendReaction('emote', item.id, 'auto') else remote:FireServer('buy', item.id) end
  elseif owned then
    remote:FireServer('equip', item.id)
  elseif (item.price or 0) > 0 then
    remote:FireServer('buy', item.id)
  elseif item.robux then
    remote:FireServer('buy_product', item.id)
  end
end

for tab, items in pairs(byTab) do
  tiles[tab] = {}
  local container = C.categoryContainers[tab]
  for index, item in ipairs(items) do
    local rarity = rarityOf[item.id]
    local style = RARITY[rarity]
    local t = { item = item, tab = tab, rarity = rarity, style = style, phase = index * 1.3 }
    -- White base: a UIGradient multiplies the background colour, so white
    -- lets the gradient show its true colours.
    local f = frame(container, 'Tile_' .. item.id, palette.white, 16)
    make('UIGradient', f, 'Gradient', { Color = ColorSequence.new(style.top, style.bottom), Rotation = 90 })
    t.stroke = outline(f, style.rim, 2)
    t.scale = make('UIScale', f, 'Scale', { Scale = 1 })
    f.MouseEnter:Connect(function() tween(t.scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1.03 }) end)
    f.MouseLeave:Connect(function() tween(t.scale, TweenInfo.new(0.15), { Scale = 1 }) end)
    -- soft spotlight behind the preview
    t.glow = frame(f, 'Glow', palette.white, 999)
    t.glow.BackgroundTransparency = 0.88
    t.glow.AnchorPoint = Vector2.new(0.5, 0.5)
    if tab == 'emote' and arenaUI.emoteDefs and arenaUI.emoteDefs[item.id] then
      t.preview = arenaUI.reactionToken(f, 'Preview', arenaUI.emoteDefs[item.id], 76)
      t.preview.AnchorPoint = Vector2.new(0.5, 0.5)
      t.previewSize = 76
    elseif tab == 'cardBack' then
      t.preview = cardBackPreview(f, item.id, 62, 88)
    elseif tab == 'felt' and C.feltThemes[item.id] then
      t.preview = feltPreview(f, C.feltThemes[item.id])
    end
    local displayName = (tab == 'emote' and arenaUI.emoteDefs and arenaUI.emoteDefs[item.id] and arenaUI.emoteDefs[item.id].name) or item.label
    t.name = chunky(f, 'Name', displayName, 16, palette.white)
    t.desc = label(f, 'Desc', item.desc or '', 10, palette.cream)
    t.desc.TextTransparency = 0.15
    t.pill = frame(f, 'Rarity', style.pill, 999)
    outline(t.pill, INK, 1.5)
    local pillText = label(t.pill, 'Text', rarity, 9, INK)
    pillText.Font = Enum.Font.GothamBlack
    pillText.Size = UDim2.fromScale(1, 1)
    pillText.TextWrapped = false
    -- action button: gold for buying, green to equip, dark when equipped/sending
    t.button = make('TextButton', f, 'Action', { Text = '', AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = palette.white })
    corner(t.button, 11)
    t.buttonGradient = gradient(t.button, palette.goldBright, palette.goldDark, 90)
    t.buttonStroke = outline(t.button, INK, 2)
    t.coin = C.flatCoinIcon(t.button, 'Coin')
    t.coin.Size = UDim2.fromOffset(20, 20)
    t.buttonText = label(t.button, 'Text', '', 15, INK)
    t.buttonText.Font = Enum.Font.FredokaOne
    t.buttonText.TextWrapped = false
    local press = make('UIScale', t.button, 'Press', { Scale = 1 })
    t.button.MouseButton1Down:Connect(function() tween(press, TweenInfo.new(0.06), { Scale = 0.94 }) end)
    t.button.MouseButton1Up:Connect(function() tween(press, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }) end)
    t.button.MouseLeave:Connect(function() tween(press, TweenInfo.new(0.12), { Scale = 1 }) end)
    t.button.Activated:Connect(function() playSound('click'); actionFor(item) end)
    t.frame = f
    table.insert(tiles[tab], t)
  end
end

-- ===== Layout: columns per tab, tile sizes from the available width =====
local COLUMNS = { emote = 3, cardBack = 4, felt = 2 }
local layoutInfo = {}
function C.layoutShopGrid(tab, width, height)
  local list = tiles[tab]
  if not list then return end
  local cols = COLUMNS[tab] or 3
  if width < 420 then cols = math.max(2, cols - 1) end
  local gap, pad = 10, 4
  local tw = math.floor((width - 2 * pad - 10 - gap * (cols - 1)) / cols)
  local th = tab == 'emote' and 216 or (tab == 'cardBack' and math.max(250, height - 12) or math.max(196, math.floor((height - 12 - gap) / 2)))
  layoutInfo[tab] = { width = width, tw = tw, th = th }
  for i, t in ipairs(list) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    rect(t.frame, pad + col * (tw + gap), pad + row * (th + gap), tw, th)
    rect(t.pill, 10, 10, 78, 18)
    local previewH = tab == 'felt' and math.floor(th * 0.36) or (tab == 'cardBack' and math.floor(th * 0.52) or 96)
    local pcx, pcy = tw / 2, 30 + previewH / 2
    local glowSize = math.min(previewH * 1.15, tw - 16)
    t.glow.Position = UDim2.fromOffset(pcx, pcy)
    t.glow.Size = UDim2.fromOffset(glowSize, glowSize)
    t.cx, t.cy = pcx, pcy
    if t.preview then
      if tab == 'felt' then
        t.preview.Size = UDim2.fromOffset(math.min(tw - 40, previewH * 1.9), previewH)
      elseif tab == 'cardBack' then
        -- 62x88 cards fanned in a 93x97 holder: grow to fill the tile.
        t.preview.Fit.Scale = math.max(0.8, math.min(previewH / 100, (tw - 20) / 93))
      end
      t.preview.Position = UDim2.fromOffset(pcx, pcy)
    end
    local y = 30 + previewH + 8
    rect(t.name, 8, y, tw - 16, 20)
    t.name.TextSize = safeClamp(math.floor(tw / 9), 13, 17)
    -- Description only where it fits between the name and the button.
    local room = (th - 52) - (y + 22)
    local descH = tab == 'emote' and 0 or math.min(30, room)
    rect(t.desc, 10, y + 22, tw - 20, math.max(0, descH))
    t.desc.Visible = descH >= 13
    rect(t.button, 10, th - 46, tw - 20, 36)
  end
  local rows = math.ceil(#list / cols)
  C.shopScroll.CanvasSize = UDim2.fromOffset(0, pad * 2 + rows * th + (rows - 1) * gap)
end

-- ===== State: button labels and colours =====
local function styleButton(t, mode, text, coin)
  t.buttonText.Text = text
  t.coin.Visible = coin == true
  if coin then
    rect(t.coin, 0, 0, 20, 20)
    local info = layoutInfo[t.tab]
    local w = info and (info.tw - 20) or t.button.AbsoluteSize.X
    local textW = game:GetService('TextService'):GetTextSize(text, 15, Enum.Font.FredokaOne, Vector2.new(400, 40)).X
    local start = math.floor((w - textW - 26) / 2)
    t.coin.Position = UDim2.new(0, start, 0.5, -10)
    t.buttonText.Position = UDim2.new(0, start + 26, 0, 0)
    t.buttonText.Size = UDim2.new(0, textW + 4, 1, 0)
    t.buttonText.TextXAlignment = Enum.TextXAlignment.Left
  else
    t.buttonText.Position = UDim2.new()
    t.buttonText.Size = UDim2.fromScale(1, 1)
    t.buttonText.TextXAlignment = Enum.TextXAlignment.Center
  end
  if mode == 'buy' then
    t.buttonGradient.Color = ColorSequence.new(color(255, 218, 92), color(236, 148, 26))
    t.buttonText.TextColor3 = INK
  elseif mode == 'poor' then
    t.buttonGradient.Color = ColorSequence.new(color(120, 128, 140), color(70, 76, 88))
    t.buttonText.TextColor3 = color(230, 232, 240)
  elseif mode == 'equip' then
    t.buttonGradient.Color = ColorSequence.new(color(120, 255, 170), color(30, 170, 90))
    t.buttonText.TextColor3 = INK
  else -- 'done' (equipped) or 'send'
    t.buttonGradient.Color = ColorSequence.new(color(52, 70, 96), color(26, 36, 54))
    t.buttonText.TextColor3 = mode == 'done' and palette.goldBright or palette.white
  end
end

function C.renderShopGrid()
  local s = C.state
  if not s then return end
  local equipped = s.equipped or {}
  local equippedOf = { cardBack = equipped.cardBack or 'cardback_classic', felt = equipped.felt or 'felt_emerald' }
  for tab, list in pairs(tiles) do
    for _, t in ipairs(list) do
      local item = t.item
      local owned = s.owned and s.owned[item.id] == true
      t.equipped = equippedOf[tab] == item.id
      if tab == 'emote' then
        if owned then styleButton(t, 'send', 'SEND')
        else styleButton(t, (s.coins or 0) >= (item.price or 0) and 'buy' or 'poor', formatK(item.price or 0), true) end
      elseif t.equipped then
        styleButton(t, 'done', '✓ EQUIPPED')
      elseif owned or (item.price or 0) == 0 and not item.robux then
        styleButton(t, 'equip', 'EQUIP')
      elseif (item.price or 0) > 0 then
        styleButton(t, (s.coins or 0) >= item.price and 'buy' or 'poor', formatK(item.price), true)
      else
        styleButton(t, 'buy', 'R$ ' .. tostring(item.robux or 0))
      end
      t.stroke.Thickness = t.equipped and 3 or 2
      t.stroke.Color = t.equipped and palette.goldBright or t.style.rim
    end
  end
end

-- ===== Idle animation: previews float, equipped and legendary rims glow =====
RunService.RenderStepped:Connect(function()
  local tab = C.activeShopTab
  if not (C.shade and C.shade.Visible and tiles[tab]) then return end
  local now = os.clock()
  for _, t in ipairs(tiles[tab]) do
    if t.preview and t.cx then
      t.preview.Position = UDim2.fromOffset(t.cx, t.cy + math.sin(now * 2 + t.phase) * 3)
    end
    if t.equipped or t.rarity == 'LEGENDARY' then
      t.stroke.Transparency = 0.1 + 0.3 * (0.5 + 0.5 * math.sin(now * 3 + t.phase))
    end
  end
end)
end
