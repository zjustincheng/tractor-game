-- Happy Tractor client: the Coins & VIP tab of the shop.
-- A VIP banner across the top and one tall card per coin pack, styled like
-- the shops of the big Roblox games: big glowing art, tier colours, value
-- tags and a Robux price button. Purchases go through Roblox's own prompt;
-- the server pays coins in ProcessReceipt. When coins arrive, a burst of
-- coins flies from the card into the balance, which counts up.
return function(C)
local Catalog, Players, button, corner, formatK, frame = C.Catalog, C.Players, C.button, C.corner, C.formatK, C.frame
local gradient, label, make, outline, palette, playSound = C.gradient, C.label, C.make, C.outline, C.palette, C.playSound
local rect, root, tween = C.rect, C.root, C.tween
local MarketplaceService = game:GetService('MarketplaceService')
local RunService = game:GetService('RunService')
local color = Color3.fromRGB
local ROBUX = 'rbxasset://textures/ui/common/robux.png'
local INK = color(20, 16, 30)

local container = C.categoryContainers.product
if not container then return end

-- Tier styling, smallest pack first. Keyed by catalog id.
local TIERS = {
  product_coins_10k = { top = color(76, 214, 120), bottom = color(18, 120, 64), rim = color(150, 255, 180), glow = color(140, 255, 170), tag = nil },
  product_coins_50k = { top = color(70, 160, 255), bottom = color(22, 62, 170), rim = color(150, 210, 255), glow = color(130, 200, 255), tag = 'MOST POPULAR', tagColor = color(255, 80, 96) },
  product_coins_200k = { top = color(255, 200, 70), bottom = color(196, 92, 14), rim = color(255, 240, 170), glow = color(255, 220, 110), tag = 'BEST VALUE', tagColor = color(60, 200, 110) },
}

local packs, vipItem = {}, nil
for _, item in ipairs(Catalog) do
  if item.category == 'product' then
    if item.gamePassId then vipItem = item elseif item.coins then table.insert(packs, item) end
  end
end
table.sort(packs, function(a, b) return a.coins < b.coins end)

local function commas(n)
  local s = tostring(math.floor(n))
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

local function chunky(parent, name, text, size, tint)
  local l = label(parent, name, text, size, tint or palette.white)
  l.Font = Enum.Font.FredokaOne
  l.TextWrapped = false
  make('UIStroke', l, 'Stroke', { Color = INK, Thickness = math.max(1.5, size / 11), ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
  return l
end

-- Soft round glow made of stacked translucent discs (UIGradient is linear only).
local function glowDisc(parent, tint)
  local holder = make('Frame', parent, 'Glow', { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5) })
  for i = 1, 5 do
    local d = frame(holder, 'Ring' .. i, tint, 999)
    d.AnchorPoint = Vector2.new(0.5, 0.5)
    d.Position = UDim2.fromScale(0.5, 0.5)
    d.Size = UDim2.fromScale(0.35 + i * 0.13, 0.35 + i * 0.13)
    d.BackgroundTransparency = 0.72 + i * 0.05
  end
  return holder
end

-- Light rays: bars through the centre (GUI rotation turns an object about its
-- own middle), bright in the middle and fading to both ends, so together they
-- fan out from behind the art. The animation loop spins the holder.
local function rays(parent, tint, count)
  local holder = make('Frame', parent, 'Rays', { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5) })
  for i = 1, math.floor(count / 2) do
    local ray = make('Frame', holder, 'Ray' .. i, {
      BackgroundColor3 = tint, BorderSizePixel = 0, AnchorPoint = Vector2.new(0.5, 0.5),
      Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 18, 1, 0), Rotation = (i - 1) * 360 / count,
    })
    make('UIGradient', ray, 'Fade', {
      Rotation = 90,
      Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.86), NumberSequenceKeypoint.new(0.5, 0.62), NumberSequenceKeypoint.new(0.7, 0.86), NumberSequenceKeypoint.new(1, 1) }),
    })
  end
  return holder
end

local function robuxPrice(parent, amount)
  local holder = make('Frame', parent, 'Price', { BackgroundTransparency = 1 })
  local list = make('UIListLayout', holder, 'List', {
    FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
    VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 5),
  })
  local icon = make('ImageLabel', holder, 'Robux', { BackgroundTransparency = 1, Image = ROBUX, ImageColor3 = INK, Size = UDim2.fromOffset(20, 20), LayoutOrder = 1 })
  local text = label(holder, 'Amount', tostring(amount), 20, INK)
  text.Font = Enum.Font.FredokaOne
  text.TextWrapped = false
  text.AutomaticSize = Enum.AutomaticSize.X
  text.Size = UDim2.fromOffset(0, 24)
  text.LayoutOrder = 2
  return holder, icon, text, list
end

local function prompt(item)
  if (item.productId or 0) > 0 then
    MarketplaceService:PromptProductPurchase(Players.LocalPlayer, item.productId)
  elseif (item.gamePassId or 0) > 0 then
    if C.state and C.state.vip then return end
    MarketplaceService:PromptGamePassPurchase(Players.LocalPlayer, item.gamePassId)
  else
    C.remote:FireServer('buy_product', item.id)
  end
end

local function hoverScale(target, scale)
  target.MouseEnter:Connect(function() tween(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = 1.025 }) end)
  target.MouseLeave:Connect(function() tween(scale, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Scale = 1 }) end)
  target.MouseButton1Down:Connect(function() tween(scale, TweenInfo.new(0.06), { Scale = 0.96 }) end)
  target.MouseButton1Up:Connect(function() tween(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back), { Scale = 1.025 }) end)
end

-- ===== VIP banner =====
local vip = {}
if vipItem then
  local b = make('TextButton', container, 'VipBanner', { Text = '', AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = color(120, 20, 60) })
  corner(b, 16)
  make('UIGradient', b, 'Gradient', { Color = ColorSequence.new(color(176, 24, 70), color(74, 22, 140)), Rotation = 0 })
  local stroke = outline(b, palette.gold, 2.5)
  vip.button, vip.stroke = b, stroke
  vip.scale = make('UIScale', b, 'Scale', { Scale = 1 })
  hoverScale(b, vip.scale)
  -- Shimmer band sweeping across, clipped by a CanvasGroup.
  local clip = make('CanvasGroup', b, 'Clip', { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1) })
  corner(clip, 16)
  vip.shine = make('Frame', clip, 'Shine', { BackgroundColor3 = palette.white, BorderSizePixel = 0, Size = UDim2.new(0, 70, 1.6, 0), AnchorPoint = Vector2.new(0.5, 0.5), Rotation = 18 })
  make('UIGradient', vip.shine, 'Fade', { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.7), NumberSequenceKeypoint.new(1, 1) }) })
  vip.glow = glowDisc(b, color(255, 200, 90))
  vip.icon = make('ImageLabel', b, 'Icon', { BackgroundTransparency = 1, Image = vipItem.image or '', ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5) })
  vip.title = chunky(b, 'Title', 'VIP TRACTOR PASS', 24, palette.goldBright)
  vip.title.TextXAlignment = Enum.TextXAlignment.Left
  vip.perk = label(b, 'Perk', '2× coins on every win + markers on cards safe to gamble and suits opponents are out of', 13, palette.cream)
  vip.perk.TextXAlignment = Enum.TextXAlignment.Left
  vip.perk.TextWrapped = true
  vip.buy = make('Frame', b, 'Buy', { BackgroundColor3 = palette.gold, BorderSizePixel = 0 })
  corner(vip.buy, 12)
  gradient(vip.buy, palette.goldBright, palette.goldDark, 90)
  outline(vip.buy, INK, 2)
  local priceHolder, _, priceText = robuxPrice(vip.buy, vipItem.robux or 0)
  vip.price, vip.priceText = priceHolder, priceText
  vip.owned = chunky(b, 'Owned', '✓ VIP ACTIVE', 18, color(140, 255, 170))
  vip.owned.Visible = false
  b.Activated:Connect(function() playSound('click'); prompt(vipItem) end)
end

-- ===== Coin pack cards =====
local cards = {}
for index, item in ipairs(packs) do
  local tier = TIERS[item.id] or TIERS.product_coins_10k
  local card = {}
  local b = make('TextButton', container, 'Pack_' .. item.id, { Text = '', AutoButtonColor = false, BorderSizePixel = 0, BackgroundColor3 = tier.bottom })
  corner(b, 18)
  make('UIGradient', b, 'Gradient', { Color = ColorSequence.new(tier.top, tier.bottom), Rotation = 90 })
  card.stroke = outline(b, tier.rim, 2.5)
  card.scale = make('UIScale', b, 'Scale', { Scale = 1 })
  hoverScale(b, card.scale)
  local art = make('CanvasGroup', b, 'Art', { BackgroundTransparency = 1 })
  corner(art, 18)
  card.rays = rays(art, palette.white, 12)
  card.glow = glowDisc(art, tier.glow)
  card.icon = make('ImageLabel', b, 'Icon', { BackgroundTransparency = 1, Image = item.image or '', ScaleType = Enum.ScaleType.Fit, AnchorPoint = Vector2.new(0.5, 0.5) })
  card.amount = chunky(b, 'Amount', commas(item.coins), 30, palette.white)
  card.unit = chunky(b, 'Unit', 'COINS', 14, palette.goldBright)
  local bonus = item.label:match('%+(%d+%%)')
  if bonus then
    card.bonus = frame(b, 'Bonus', color(255, 236, 120), 999)
    outline(card.bonus, INK, 2)
    local t = label(card.bonus, 'Text', '+' .. bonus .. ' BONUS', 11, INK)
    t.Font = Enum.Font.FredokaOne
    t.Size = UDim2.fromScale(1, 1)
    t.TextWrapped = false
  end
  card.buy = make('Frame', b, 'Buy', { BackgroundColor3 = palette.gold, BorderSizePixel = 0 })
  corner(card.buy, 12)
  gradient(card.buy, palette.goldBright, palette.goldDark, 90)
  outline(card.buy, INK, 2)
  robuxPrice(card.buy, item.robux or 0)
  if tier.tag then
    card.tag = frame(container, 'Tag_' .. item.id, tier.tagColor, 999)
    card.tag.ZIndex = 5
    outline(card.tag, INK, 2)
    local t = chunky(card.tag, 'Text', tier.tag, 12, palette.white)
    t.Size = UDim2.fromScale(1, 1)
    t.ZIndex = 6
  end
  card.button, card.item, card.tier, card.phase = b, item, tier, index * 1.7
  b.Activated:Connect(function() playSound('click'); prompt(item) end)
  cards[index] = card
end

-- ===== Layout (called from the shop's resize) =====
local layoutInfo = nil
function C.layoutCoinShop(width, height)
  layoutInfo = { width = width, height = height }
  local gap = 12
  local y = 14  -- room for the tags that sit on the card tops
  if vip.button then
    local bh = 104
    rect(vip.button, 0, 0, width - 10, bh)
    local bw = width - 10
    vip.glow.Position = UDim2.fromOffset(56, bh / 2); vip.glow.Size = UDim2.fromOffset(120, 120)
    vip.icon.Position = UDim2.fromOffset(56, bh / 2); vip.icon.Size = UDim2.fromOffset(86, 86)
    local textX = 112
    local buyW = math.clamp(math.floor(bw * 0.24), 96, 130)
    rect(vip.title, textX, 22, bw - textX - buyW - 24, 30)
    rect(vip.perk, textX, 54, bw - textX - buyW - 24, 34)
    rect(vip.buy, bw - buyW - 14, (bh - 44) / 2, buyW, 44)
    rect(vip.price, 0, 0, buyW, 44)
    rect(vip.owned, bw - buyW - 24, (bh - 44) / 2, buyW + 10, 44)
    y = bh + gap + 14
  end
  local n = #cards
  if n > 0 then
    local cw = math.floor((width - 18 - gap * (n - 1)) / n)
    local ch = math.max(230, height - y - 12)  -- room to grow on hover
    for i, card in ipairs(cards) do
      local x = 4 + (i - 1) * (cw + gap)
      rect(card.button, x, y, cw, ch)
      local art = card.button:FindFirstChild('Art')
      rect(art, 0, 0, cw, ch)
      local iconSize = math.min(cw - 24, math.floor(ch * 0.46))
      local cx, cy = cw / 2, 18 + iconSize / 2
      card.rays.Position = UDim2.fromOffset(cx, cy); card.rays.Size = UDim2.fromOffset(cw * 1.9, cw * 1.9)
      card.glow.Position = UDim2.fromOffset(cx, cy); card.glow.Size = UDim2.fromOffset(iconSize * 1.25, iconSize * 1.25)
      card.icon.Size = UDim2.fromOffset(iconSize, iconSize)
      card.cx, card.cy = cx, cy
      local ay = cy + iconSize / 2 + 2
      rect(card.amount, 0, ay, cw, 32)
      card.amount.TextSize = math.clamp(math.floor(cw / 5.2), 20, 32)
      rect(card.unit, 0, ay + 30, cw, 16)
      if card.bonus then rect(card.bonus, (cw - 104) / 2, ay + 50, 104, 22) end
      rect(card.buy, 10, ch - 54, cw - 20, 44)
      rect(card.buy:FindFirstChild('Price'), 0, 0, cw - 20, 44)
      if card.tag then rect(card.tag, x + (cw - 116) / 2, y - 13, 116, 26) end
    end
    C.shopScroll.CanvasSize = UDim2.fromOffset(0, y + ch + 12)
  end
end

-- ===== State (called from renderShopItems) =====
local shownCoins = nil
local pendingBurst = nil  -- the card whose purchase just finished

local function burst(card)
  if not (card and card.button.Parent and C.shopBalance) then return end
  local rootPos = root.AbsolutePosition
  local from = card.icon.AbsolutePosition + card.icon.AbsoluteSize / 2 - rootPos
  local to = C.shopBalance.AbsolutePosition + Vector2.new(24, C.shopBalance.AbsoluteSize.Y / 2) - rootPos
  for i = 1, 14 do
    local coin = make('ImageLabel', root, 'FlyingCoin', {
      BackgroundTransparency = 1, Image = card.item.image or '', ZIndex = 99,
      Size = UDim2.fromOffset(30, 30), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(from.X, from.Y),
    })
    local spread = Vector2.new(math.random(-70, 70), math.random(-80, -20))
    task.delay((i - 1) * 0.035, function()
      if not coin.Parent then return end
      tween(coin, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromOffset(from.X + spread.X, from.Y + spread.Y), Rotation = math.random(-90, 90) })
      task.delay(0.3, function()
        if not coin.Parent then return end
        tween(coin, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromOffset(to.X, to.Y), Size = UDim2.fromOffset(16, 16) })
        task.delay(0.46, function() if coin.Parent then coin:Destroy() end end)
      end)
    end)
  end
  playSound('coin')
end

local animatingTo = nil
local function countTo(target)
  local start = shownCoins or target
  shownCoins = target
  animatingTo = target
  if start == target or not C.shopBalance then return end
  local t0 = os.clock()
  task.spawn(function()
    while true do
      local t = math.min(1, (os.clock() - t0) / 1.1)
      local eased = 1 - (1 - t) ^ 3
      if animatingTo ~= target then break end
      if C.shopBalance then C.shopBalance.Text = '●  ' .. formatK(start + (target - start) * eased) .. ' COINS' end
      if t >= 1 then break end
      RunService.RenderStepped:Wait()
    end
  end)
end

function C.renderCoinShop()
  local s = C.state
  if not s then return end
  if vip.button then
    local owned = s.vip == true
    vip.buy.Visible = not owned
    vip.owned.Visible = owned
    vip.perk.Text = owned and 'Double winnings and table markers are active in every round.' or '2× coins on every win + markers on cards safe to gamble and suits opponents are out of'
  end
  if shownCoins and s.coins > shownCoins and C.activeShopTab == 'product' and C.shade and C.shade.Visible then
    -- Hold the old balance on screen until the flying coins land.
    local before = shownCoins
    if C.shopBalance then C.shopBalance.Text = '●  ' .. formatK(before) .. ' COINS' end
    if pendingBurst then burst(pendingBurst); pendingBurst = nil end
    local target = s.coins
    task.delay(0.6, function() countTo(target) end)
  else
    shownCoins = s.coins
  end
end

pcall(function()
  MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId, productId, purchased)
    if not purchased or userId ~= Players.LocalPlayer.UserId then return end
    for _, card in ipairs(cards) do
      if card.item.productId == productId then pendingBurst = card end
    end
  end)
end)

-- ===== Idle animation: bobbing icons, spinning rays, shimmer, glowing rims =====
RunService.RenderStepped:Connect(function()
  if not (C.shade and C.shade.Visible and C.activeShopTab == 'product') then return end
  local t = os.clock()
  for _, card in ipairs(cards) do
    if card.cx then
      card.icon.Position = UDim2.fromOffset(card.cx, card.cy + math.sin(t * 2.2 + card.phase) * 5)
      card.icon.Rotation = math.sin(t * 1.3 + card.phase) * 4
    end
    card.rays.Rotation = (t * 14 + card.phase * 20) % 360
    card.stroke.Transparency = 0.25 + 0.25 * math.sin(t * 3 + card.phase)
  end
  local best = cards[#cards]
  if best then best.stroke.Thickness = 2.5 + 1.5 * (0.5 + 0.5 * math.sin(t * 4)) end
  if vip.button and layoutInfo then
    local w = layoutInfo.width
    vip.shine.Position = UDim2.fromOffset(((t * 260) % (w + 400)) - 200, 52)
    vip.icon.Rotation = math.sin(t * 1.6) * 5
    vip.stroke.Transparency = 0.15 + 0.2 * math.sin(t * 3)
  end
end)
end
