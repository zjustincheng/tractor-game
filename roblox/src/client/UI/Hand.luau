-- Clamp that tolerates max < min (tiny phone screens) instead of erroring.
local function safeClamp(v, lo, hi) if hi < lo then hi = lo end return math.clamp(v, lo, hi) end
-- Happy Tractor client, part 11/14: Hand.
-- Lines 4285-4535 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Cards, Layout, corner, frame, gradient, handFrame, label, make = C.Cards, C.Layout, C.corner, C.frame, C.gradient, C.handFrame, C.label, C.make
local notice, outline, palette, playSound, rect, selectedList, suitColors, symbols = C.notice, C.outline, C.palette, C.playSound, C.rect, C.selectedList, C.suitColors, C.symbols
local tween = C.tween

local function destroyChildren(parent)
  if not parent then return end
  for _, child in ipairs(parent:GetChildren()) do child:Destroy() end
end C.destroyChildren = destroyChildren

local function renderDeclarationCards(container, decl, current, visible)
  if not container then return end
  destroyChildren(container)
  container.Visible = visible == true and decl ~= nil
  if not container.Visible then return end
  -- Public match projections may omit the private card ids; the declaration
  -- count is enough to render the public reveal above the profile.
  local count = math.min(decl.cardIds and #decl.cardIds or (decl.count or 1), 3)
  local tileW = count > 0 and math.floor(78 / count) or 24
  for index = 1, count do
    local tile = frame(container, 'DeclaredCard' .. index, palette.cream, 4)
    tile.ZIndex = container.ZIndex + 1
    outline(tile, palette.goldDark, 1)
    rect(tile, (index - 1) * tileW, 0, tileW - 2, 22)
    local cardLabel = decl.joker and (decl.joker == 'big' and 'BIG' or 'SM') or ((symbols[decl.suit] or '★') .. ' ' .. tostring(current.trump.level))
    local cardText = label(tile, 'Text', cardLabel, 10, suitColors[decl.suit] or palette.ink)
    cardText.Font = Enum.Font.FredokaOne
    cardText.TextScaled = true
    cardText.ZIndex = tile.ZIndex + 1
    cardText.Size = UDim2.fromScale(1, 1)
  end
end C.renderDeclarationCards = renderDeclarationCards

local function cardFace(parent, card, name, width, height, callback)
  local object = make(callback and 'TextButton' or 'Frame', parent, name, { BackgroundColor3 = palette.cardFace, BorderSizePixel = 0 })
  if callback then
    object.Text = ''
    object.AutoButtonColor = false
    object.InputBegan:Connect(function(input)
      if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        C.handDragActive = true
        C.handDragValue = not C.selectedIds[card.id]
        C.handDragVisited = {}
        callback()
      end
    end)
    object.MouseEnter:Connect(function()
      if C.handDragActive then callback() end
    end)
  end
  object.Size = UDim2.fromOffset(width, height)
  corner(object, safeClamp(math.floor(height * 0.08), 5, 8))
  gradient(object, palette.cardFace, palette.cardGrad, 50)
  local stroke = outline(object, palette.cardBorder, 1)

  local ink
  if card.joker then
    ink = card.joker == 'big' and Color3.fromRGB(214, 32, 48) or Color3.fromRGB(58, 74, 104)
  else
    ink = suitColors[card.suit] or palette.ink
  end
  local symbol = card.joker and '★' or (symbols[card.suit] or '')
  local small = height < 72 -- tiny cards keep just the index and a pip

  -- Corner index (rank over suit), mirrored upside down in the far corner.
  local rankText = card.joker and (card.joker == 'big' and 'BIG' or 'SM') or card.rank
  local rankSize = card.joker and safeClamp(math.floor(height * 0.16), 10, 14) or safeClamp(math.floor(height * 0.23), 14, 26)
  if width < 70 then rankSize = math.min(rankSize, 20) end
  local indexW, rankH, pipH = math.min(24, width - 4), math.floor(height * 0.26), math.floor(height * 0.2)
  local pipSize = safeClamp(math.floor(height * 0.18), 11, 20)
  local rank = label(object, 'Rank', rankText, rankSize, ink)
  rank.Font = Enum.Font.FredokaOne
  rank.TextWrapped = false
  rect(rank, 2, 3, indexW, rankH)
  local pip = label(object, 'CornerSuit', symbol, pipSize, ink)
  pip.Font = Enum.Font.GothamBold
  rect(pip, 2, rankH + 1, indexW, pipH)
  if not small then
    for name, spec in pairs({ SubRank = { rankText, rankSize, height - 3 - rankH }, SubCorner = { symbol, pipSize, height - 3 - rankH - pipH } }) do
      local mirrored = label(object, name, spec[1], spec[2], ink)
      mirrored.Font = name == 'SubRank' and Enum.Font.FredokaOne or Enum.Font.GothamBold
      mirrored.TextWrapped = false
      mirrored.Rotation = 180
      rect(mirrored, width - 2 - indexW, spec[3], indexW, name == 'SubRank' and rankH or pipH)
    end
  end

  -- Centre art: a pip for number cards, a big plain letter for A / K / Q / J, a star for jokers.
  local artX, artY = math.floor(width * 0.26), math.floor(height * 0.2)
  local artW, artH = width - artX * 2 + 2, height - artY * 2
  local isLetter = card.rank == 'A' or card.rank == 'J' or card.rank == 'Q' or card.rank == 'K'
  if isLetter and not card.joker and not small then
    local letter = label(object, 'Letter', card.rank, math.floor(math.min(artW * 1.05, artH * 0.7)), ink)
    letter.Font = Enum.Font.FredokaOne
    letter.TextWrapped = false
    rect(letter, artX, artY, artW, artH)
  elseif card.joker and not small then
    local panel = frame(object, 'CourtPanel', ink, 6)
    panel.BackgroundTransparency = 1
    rect(panel, artX, artY, artW, artH)
    local motif = label(panel, 'Motif', '★', math.floor(math.min(artW, artH) * 0.62), ink)
    motif.Font = Enum.Font.GothamBold
    motif.TextWrapped = false
    rect(motif, 0, 2, artW, artH * 0.72)
    local caption = label(panel, 'Caption', 'JOKER', safeClamp(math.floor(artH * 0.16), 8, 18), ink)
    caption.Font = Enum.Font.FredokaOne
    caption.TextWrapped = false
    rect(caption, 0, artH * 0.7, artW, artH * 0.28)
  else
    local center = label(object, 'Suit', symbol, math.floor(math.min(artW * 0.95, artH * 0.62)), ink)
    center.Font = Enum.Font.GothamBold
    center.TextWrapped = false
    center.TextTransparency = card.rank == 'A' and 0 or 0.08
    rect(center, artX, artY, artW, artH)
  end

  return object, stroke
end C.cardFace = cardFace

C.previouslyRenderedCards = {}
C.lastDealtCount = -1

local function getDealingState()
  if not C.state or not C.state.game then
    return 0, false, 0
  end
  local current = C.state.game
  if current.phase ~= 'declaration' then
    return #current.hand, false, 0
  end
  if not current.dealingDuration or current.dealingDuration <= 0 then return #current.hand, false, 0 end
  local elapsed = math.max(0, (C.state.serverTime + os.clock() - C.receivedAt) - current.dealingStartedAt)
  local total = #current.hand
  local dealtCount = safeClamp(math.floor(elapsed / current.dealingDuration * current.handSize) + 1, 1, total)
  local isDealing = dealtCount < total
  return dealtCount, isDealing, elapsed
end C.getDealingState = getDealingState

local function getRevealedCards(current)
  local dealtCount, isDealing = getDealingState()
  if not isDealing or dealtCount >= #current.hand then
    return current.hand, false, #current.hand
  end
  local revealed = {}
  for i = 1, dealtCount do
    table.insert(revealed, current.hand[i])
  end
  return revealed, true, dealtCount
end C.getRevealedCards = getRevealedCards

local function sortedHand(cards, trump)
  local result = {}
  for _, card in ipairs(cards) do table.insert(result, card) end
  local order = { trump = 0, spades = 1, hearts = 2, clubs = 3, diamonds = 4 }
  table.sort(result, function(a, b)
    local ac, bc = Cards.category(a, trump), Cards.category(b, trump)
    if ac ~= bc then return order[ac] < order[bc] end
    local ap, bp = Cards.power(a, trump), Cards.power(b, trump)
    if ap ~= bp then return ap > bp end
    -- Equal-power trump (off-suit level cards) stays grouped by suit.
    local as, bs = order[a.suit] or 0, order[b.suit] or 0
    if as ~= bs then return as < bs end
    return a.id < b.id
  end)
  return result
end

C.renderHand = function()
  if not C.currentLayout then return end
  destroyChildren(handFrame)
  if not C.state or not C.state.game then return end
  local current, layout = C.state.game, C.currentLayout
  local revealed, isDealing, dealtCount = getRevealedCards(current)
  local hand = sortedHand(revealed, current.trump)
  local totalCards = isDealing and math.max(#revealed, current.handSize or 25) or #hand
  local mid = (totalCards + 1) / 2

  for i, card in ipairs(hand) do
    local chosen = card
    local position = Layout.card(layout, i, totalCards)
    local isSelected = C.selectedIds[card.id] == true
    local isTrump = current.phase ~= 'declaration' and Cards.category(card, current.trump) == 'trump'

    -- Slight convex arc fan: outer cards curve downwards subtly
    local norm = (i - mid) / (mid > 1 and mid or 1)
    local arcY = math.floor((norm * norm) * 12)
    local baseY = position.y + arcY
    local targetY = baseY - (isSelected and 24 or 0)

    -- Card drop shadow for tactile depth
    local shadow = frame(handFrame, 'Shadow_' .. card.id, Color3.fromRGB(0, 0, 0), 10)
    shadow.BackgroundTransparency = 0.68
    shadow.Size = UDim2.fromOffset(layout.cardWidth, layout.cardHeight)
    shadow.Position = UDim2.fromOffset(position.x + 2, targetY + 4)
    shadow.ZIndex = math.max(1, (isSelected and (60 + i) or i) - 1)

    local object, stroke = cardFace(handFrame, card, 'Card_' .. card.id, layout.cardWidth, layout.cardHeight, function()
      if C.busy or current.done then return end
      if current.phase ~= 'kitty' and current.phase ~= 'tricks' then return end
      -- Only the kitty holder picks burial cards (you are seat 1 in this view).
      if current.phase == 'kitty' and (current.kittyHolder or current.dealer) ~= 1 then return end
      if C.handDragVisited[chosen.id] then return end
      C.handDragVisited[chosen.id] = true
      playSound('card_select')
      if not C.handDragValue then
        C.selectedIds[chosen.id] = nil
      elseif current.phase == 'kitty' then
        if #selectedList() >= current.kittySize then notice.Text = 'Choose ' .. current.kittySize .. ' cards. Deselect one to change your selection.' return end
        C.selectedIds[chosen.id] = true
      elseif current.phase == 'tricks' then
        C.selectedIds[chosen.id] = true
      else
        C.selectedIds[chosen.id] = true
      end
      -- Keep the hit targets alive throughout the gesture. Rebuild on release.
      local selected = C.selectedIds[chosen.id] == true
      local tile = handFrame:FindFirstChild('Card_' .. chosen.id)
      if tile then
        tile.Outline.Color = selected and palette.goldBright or palette.cardBorder
        tile.Outline.Thickness = selected and 3.5 or 1
      end
      C.updateAction()
    end)
    object.ZIndex = isSelected and (60 + i) or i

    local isNew = isDealing and not C.previouslyRenderedCards[card.id]
    C.previouslyRenderedCards[card.id] = true
    if isNew then
      playSound('card_deal')
      local fromX = (layout.contentWidth - layout.cardWidth) / 2
      local swing = TweenInfo.new(0.32, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
      object.Position = UDim2.fromOffset(fromX, targetY - 46)
      object.Rotation = position.x < fromX and -14 or 14
      shadow.Position = UDim2.fromOffset(fromX + 2, targetY - 42)
      local pop = make('UIScale', object, 'DealScale', { Scale = 0.7 })
      tween(object, swing, { Position = UDim2.fromOffset(position.x, targetY), Rotation = 0 })
      tween(pop, swing, { Scale = 1 })
      tween(shadow, swing, { Position = UDim2.fromOffset(position.x + 2, targetY + 4) })
    else
      object.Position = UDim2.fromOffset(position.x, targetY)
    end

    if isSelected then
      stroke.Color = palette.goldBright
      stroke.Thickness = 3.5
    elseif isTrump then
      stroke.Color = palette.cardTrumpBorder
      stroke.Thickness = 1.5
    end

    -- Trump marker badge (top golden bar + star badge)
    if isTrump then
      local trumpBar = frame(object, 'TrumpBar', palette.goldBright, 2)
      trumpBar.Size = UDim2.new(1, -6, 0, 3)
      trumpBar.Position = UDim2.fromOffset(3, 2)

      local star = label(object, 'TrumpMarker', '★', 13, palette.goldDark)
      star.Font = Enum.Font.FredokaOne
      local isPoint = chosen.rank == '5'
      rect(star, 4, math.floor(layout.cardHeight * (isPoint and 0.70 or 0.52)), 18, 18)
    end
  end
end
end
