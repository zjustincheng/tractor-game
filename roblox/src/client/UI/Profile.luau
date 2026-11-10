-- Happy Tractor client: player profile page.
-- Tap your avatar in the home header to see your profile card (banner, framed
-- avatar, title, lifetime stats) and customize it. Tap anyone's avatar at the
-- table (or your own, to customize mid-game). Your frame, title and banner are
-- shown on your seat to everyone at your table.
-- The server owns coins, unlocks and what is equipped; this only displays them.
return function(C)
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')
local Catalog, playSound, remote, palette, home, seats, formatK = C.Catalog, C.playSound, C.remote, C.palette, C.home, C.seats, C.formatK
local color = Color3.fromRGB
local INK = color(20, 16, 30)
local GOLD = color(255, 200, 60)
local CREAM = color(255, 246, 220)
local MUTED = color(165, 175, 200)
local me = Players.LocalPlayer
local PANEL_W, PANEL_H = 760, 440

local function new(class, parent, props)
  local o = Instance.new(class)
  for k, v in pairs(props or {}) do o[k] = v end
  o.Parent = parent
  return o
end
local function rgb(t) return color(t[1], t[2], t[3]) end
local function round(o, r) new('UICorner', o, { CornerRadius = UDim.new(0, r or 10) }) end
local function stroke(o, c, t) return new('UIStroke', o, { Color = c or INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function shade2(o, a, b) return new('UIGradient', o, { Color = ColorSequence.new(a, b), Rotation = 90 }) end
local function text(parent, str, size, col, font, props)
  local l = new('TextLabel', parent, { BackgroundTransparency = 1, Text = str, TextSize = size, TextColor3 = col or palette.white,
    Font = font or Enum.Font.GothamBold, TextWrapped = false })
  for k, v in pairs(props or {}) do l[k] = v end
  return l
end
local function headshot(userId) return 'rbxthumb://type=AvatarHeadShot&id=' .. tostring(userId or 1) .. '&w=150&h=150' end

local byId = {}
for _, item in ipairs(Catalog) do byId[item.id] = item end
for _, item in ipairs(Catalog.profile or {}) do byId[item.id] = item end

-- ===== Avatar frames (also used by the table seats) =====
local applied = setmetatable({}, { __mode = 'k' })
local function applyAvatarFrame(avatar, id, size)
  local key = id or false
  if applied[avatar] == key then return end
  applied[avatar] = key
  local old = avatar:FindFirstChild('CosmeticFrame')
  if old then old:Destroy() end
  local item = byId[id]
  if not item or not item.ring then return end
  local thickness = math.max(2, math.floor(size / 16))
  local ring = new('Frame', avatar, { Name = 'CosmeticFrame', BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, thickness * 2, 1, thickness * 2), ZIndex = 5 })
  round(ring, 999)
  local line = stroke(ring, palette.white, thickness)
  local paint = new('UIGradient', line, { Color = ColorSequence.new(rgb(item.ring[1]), rgb(item.ring[2])), Rotation = 45 })
  if item.spin then
    TweenService:Create(paint, TweenInfo.new(3, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1), { Rotation = 405 }):Play()
  end
  if item.glyph and size >= 30 then
    local glyphSize = math.floor(size * 0.36)
    new('TextLabel', ring, { Name = 'Glyph', BackgroundTransparency = 1, Text = item.glyph, TextSize = glyphSize, Font = Enum.Font.GothamBold,
      AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.86, 0.86), Size = UDim2.fromOffset(glyphSize + 4, glyphSize + 4), ZIndex = 6 })
  end
end
C.applyAvatarFrame = applyAvatarFrame

-- ===== Panel =====
local gui = new('ScreenGui', me:WaitForChild('PlayerGui'), { Name = 'TractorProfile', ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 56 })
local dim = new('TextButton', gui, { Name = 'Shade', Text = '', AutoButtonColor = false, BackgroundColor3 = color(0, 0, 0), BackgroundTransparency = 0.45,
  Size = UDim2.fromScale(1, 1), Visible = false })
local panel = new('TextButton', dim, { Name = 'Panel', Text = '', AutoButtonColor = false, BackgroundColor3 = palette.white, AnchorPoint = Vector2.new(0.5, 0.5),
  Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PANEL_W, PANEL_H) })
round(panel, 20); stroke(panel, GOLD, 3)
shade2(panel, color(40, 46, 86), color(16, 18, 38))
local scale = new('UIScale', panel, { Scale = 1 })

local closeBtn = new('TextButton', panel, { Name = 'Close', Text = 'X', TextSize = 18, Font = Enum.Font.FredokaOne, TextColor3 = palette.white,
  BackgroundColor3 = color(220, 60, 60), Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -20, 0, -14), ZIndex = 5 })
round(closeBtn, 17); stroke(closeBtn, INK, 2)

-- Profile card (left)
local card = new('Frame', panel, { Name = 'Card', BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(272, 416) })
local banner = new('Frame', card, { Name = 'Banner', BackgroundColor3 = palette.white, Size = UDim2.fromOffset(272, 178) })
round(banner, 14); stroke(banner, INK, 2)
local bannerPaint = shade2(banner, color(36, 120, 80), color(12, 52, 40))
local cardAvatar = new('ImageLabel', banner, { Name = 'Avatar', BackgroundColor3 = color(20, 26, 50), Size = UDim2.fromOffset(92, 92), Position = UDim2.fromOffset(90, 14) })
round(cardAvatar, 46)
local cardName = text(banner, '', 20, palette.white, Enum.Font.FredokaOne, { Name = 'PlayerName', Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 112),
  TextTruncate = Enum.TextTruncate.AtEnd })
new('UIStroke', cardName, { Color = INK, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
local titlePill = new('Frame', banner, { Name = 'TitlePill', BackgroundColor3 = color(10, 14, 30), BackgroundTransparency = 0.25, AnchorPoint = Vector2.new(0.5, 0),
  Position = UDim2.new(0.5, 0, 0, 142), Size = UDim2.fromOffset(170, 26) })
round(titlePill, 13)
local cardTitle = text(titlePill, '', 14, CREAM, Enum.Font.FredokaOne, { Name = 'Title', Size = UDim2.fromScale(1, 1) })

local STAT_CELLS = {
  { label = 'ROUNDS', value = function(s) return formatK(s.roundsPlayed or 0) end },
  { label = 'WIN RATE', value = function(s)
    local played = s.roundsPlayed or 0
    return played > 0 and (math.floor((s.roundsWon or 0) / played * 100 + 0.5) .. '%') or '—'
  end },
  { label = 'MATCHES WON', value = function(s) return formatK(s.matchesWon or 0) end },
  { label = 'SHUTOUTS', value = function(s) return formatK(s.shutouts or 0) end },
  { label = 'COMEBACKS', value = function(s) return formatK(s.overturns or 0) end },
  { label = 'CHAO DI', value = function(s) return formatK(s.chaodis or 0) end },
  { label = 'BEST MULTIPLIER', value = function(s) return (s.bestGrade or 0) > 0 and ('×' .. s.bestGrade) or '—' end },
  { label = 'BIGGEST WIN', value = function(s) return formatK(s.biggestWin or 0) end },
}
local statValues = {}
for index, cell in ipairs(STAT_CELLS) do
  local col, row = (index - 1) % 2, math.floor((index - 1) / 2)
  local box = new('Frame', card, { Name = 'Stat' .. index, BackgroundColor3 = color(30, 36, 70), Position = UDim2.fromOffset(col * 139, 186 + row * 58), Size = UDim2.fromOffset(133, 52) })
  round(box, 10)
  statValues[index] = text(box, '—', 18, GOLD, Enum.Font.FredokaOne, { Size = UDim2.new(1, 0, 0, 26), Position = UDim2.fromOffset(0, 5) })
  text(box, cell.label, 10, MUTED, Enum.Font.GothamBold, { Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 33) })
end

-- Customize column (right)
local customize = new('Frame', panel, { Name = 'Customize', BackgroundTransparency = 1, Position = UDim2.fromOffset(294, 12), Size = UDim2.fromOffset(454, 416) })
local coinsLabel = text(customize, '', 15, GOLD, Enum.Font.FredokaOne, { Name = 'Coins', Size = UDim2.new(0.5, 0, 0, 24), Position = UDim2.fromOffset(4, 44), TextXAlignment = Enum.TextXAlignment.Left })
local hintLabel = text(customize, '', 12, MUTED, Enum.Font.GothamBold, { Name = 'Hint', Size = UDim2.new(0.6, -6, 0, 24), Position = UDim2.new(0.4, 0, 0, 44), TextXAlignment = Enum.TextXAlignment.Right })

local SLOT_DEFAULT = { frame = 'frame_none', title = 'title_newcomer', banner = 'banner_forest', cardBack = 'cardback_classic', felt = 'felt_emerald' }
local FELT_COLORS = {
  felt_emerald = { { 30, 130, 80 }, { 10, 60, 40 } }, felt_sapphire = { { 40, 90, 180 }, { 16, 36, 100 } },
  felt_ruby = { { 170, 36, 60 }, { 80, 12, 30 } }, felt_obsidian = { { 60, 60, 70 }, { 18, 18, 24 } },
}
local TABS = {
  { id = 'frame', label = 'Frames', hint = 'Everyone at your table sees your frame' },
  { id = 'title', label = 'Titles', hint = 'Shown under your name' },
  { id = 'banner', label = 'Banners', hint = 'The background of your card' },
  { id = 'cardBack', label = 'Card Backs', hint = 'Your deck on the table' },
  { id = 'felt', label = 'Felts', hint = 'Your table color' },
}
local tabs, tiles, activeTab = {}, {}, 'frame'
local latest = C.state

local function previewFor(item, area)
  if item.category == 'frame' then
    local face = new('ImageLabel', area, { BackgroundColor3 = color(20, 26, 50), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
      Size = UDim2.fromOffset(58, 58), Image = headshot(me.UserId) })
    round(face, 29)
    applyAvatarFrame(face, item.id, 58)
  elseif item.category == 'title' then
    text(area, item.label, 15, item.color and rgb(item.color) or CREAM, Enum.Font.FredokaOne, { Size = UDim2.new(1, -10, 1, 0), Position = UDim2.fromOffset(5, 0), TextWrapped = true })
  elseif item.category == 'banner' then
    area.BackgroundColor3 = palette.white
    shade2(area, rgb(item.colors[1]), rgb(item.colors[2]))
  elseif item.category == 'felt' then
    local paint = FELT_COLORS[item.id] or FELT_COLORS.felt_emerald
    area.BackgroundColor3 = palette.white
    shade2(area, rgb(paint[1]), rgb(paint[2]))
  elseif item.category == 'cardBack' and C.renderCardBack then
    local back = C.renderCardBack(area, 48, 72, item.id)
    if back then back.Position = UDim2.fromOffset(40, 7) end
  end
end

local function updateTile(tile)
  local s = latest or {}
  local item = tile.item
  local owned = s.owned and s.owned[item.id] == true
  local worn = ((s.equipped and s.equipped[item.category]) or SLOT_DEFAULT[item.category]) == item.id
  local tint, label
  if worn then
    tile.mode, tint, label = 'none', color(60, 66, 100), 'EQUIPPED'
  elseif owned then
    tile.mode, tint, label = 'equip', color(60, 180, 100), 'EQUIP'
  elseif item.unlock then
    local have = (s.stats and s.stats[item.unlock.stat]) or 0
    tile.mode, tint, label = 'none', color(50, 54, 82), '🔒 ' .. item.unlock.label .. ' ' .. math.min(have, item.unlock.at) .. '/' .. item.unlock.at
  elseif item.rank then
    tile.mode, tint, label = 'none', color(50, 54, 82), '🏆 REACH ' .. string.upper(item.rank) .. ' IN A SEASON'
  elseif item.vip then
    tile.mode, tint, label = 'none', color(50, 54, 82), '🔒 VIP ONLY'
  elseif item.pass then
    tile.mode, tint, label = 'none', color(50, 54, 82), '🎟 BATTLE PASS'
  else
    tile.mode, tint, label = 'buy', GOLD, '● ' .. formatK(item.price or 0)
  end
  tile.action.BackgroundColor3 = tint
  tile.action.Text = label
  tile.action.TextColor3 = tile.mode == 'buy' and INK or palette.white
  tile.stroke.Color = worn and GOLD or INK
  tile.stroke.Thickness = worn and 3 or 1.5
end

local function refreshTiles() for _, tile in ipairs(tiles) do updateTile(tile) end end

local function selectTab(id)
  activeTab = id
  for _, tab in ipairs(TABS) do
    local entry = tabs[tab.id]
    entry.page.Visible = tab.id == id
    entry.button.BackgroundColor3 = tab.id == id and GOLD or color(40, 46, 86)
    entry.button.TextColor3 = tab.id == id and INK or palette.white
    if tab.id == id then hintLabel.Text = tab.hint end
  end
end

for index, tab in ipairs(TABS) do
  local btn = new('TextButton', customize, { Name = 'Tab_' .. tab.id, Text = tab.label, TextSize = 13, Font = Enum.Font.FredokaOne,
    Position = UDim2.fromOffset((index - 1) * 91, 0), Size = UDim2.fromOffset(86, 36), AutoButtonColor = false })
  round(btn, 10); stroke(btn, INK, 1.5)
  local page = new('ScrollingFrame', customize, { Name = 'Page_' .. tab.id, BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 74),
    Size = UDim2.fromOffset(454, 342), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = GOLD,
    ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false })
  new('UIGridLayout', page, { CellSize = UDim2.fromOffset(142, 158), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder })
  tabs[tab.id] = { button = btn, page = page }
  btn.Activated:Connect(function() playSound('click'); selectTab(tab.id) end)
end

local function addTile(item, order)
  local page = tabs[item.category] and tabs[item.category].page
  if not page then return end
  local box = new('Frame', page, { Name = item.id, LayoutOrder = order, BackgroundColor3 = color(30, 36, 70) })
  round(box, 12)
  local line = stroke(box, INK, 1.5)
  local area = new('Frame', box, { Name = 'Preview', BackgroundColor3 = color(14, 18, 40), Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0, 86), ClipsDescendants = item.category ~= 'frame' })
  round(area, 8)
  previewFor(item, area)
  text(box, item.label, 13, palette.white, Enum.Font.FredokaOne, { Name = 'Label', Size = UDim2.new(1, -10, 0, 18), Position = UDim2.fromOffset(5, 96), TextTruncate = Enum.TextTruncate.AtEnd })
  local action = new('TextButton', box, { Name = 'Action', Text = '', TextSize = 12, Font = Enum.Font.FredokaOne, AutoButtonColor = false,
    Position = UDim2.fromOffset(6, 120), Size = UDim2.new(1, -12, 0, 32) })
  round(action, 9); stroke(action, INK, 1.5)
  local tile = { item = item, action = action, stroke = line, mode = 'none' }
  action.Activated:Connect(function()
    if tile.mode == 'none' then return end
    playSound('click')
    remote:FireServer(tile.mode, item.id)
  end)
  table.insert(tiles, tile)
end
for order, item in ipairs(Catalog.profile or {}) do addTile(item, order) end
for order, item in ipairs(Catalog) do
  if item.category == 'cardBack' or item.category == 'felt' then addTile(item, order) end
end

-- Another player's loadout (right column when viewing someone else)
local showcase = new('Frame', panel, { Name = 'Showcase', BackgroundTransparency = 1, Position = UDim2.fromOffset(294, 12), Size = UDim2.fromOffset(454, 416), Visible = false })
local showcaseTitle = text(showcase, 'LOADOUT', 22, GOLD, Enum.Font.FredokaOne, { Size = UDim2.new(1, 0, 0, 36) })
local loadoutRows = {}
for index, tab in ipairs(TABS) do
  local rowBox = new('Frame', showcase, { Name = 'Row_' .. tab.id, BackgroundColor3 = color(30, 36, 70), Position = UDim2.fromOffset(0, 48 + (index - 1) * 62), Size = UDim2.fromOffset(454, 54) })
  round(rowBox, 10)
  text(rowBox, tab.label, 14, MUTED, Enum.Font.GothamBold, { Size = UDim2.new(0.4, 0, 1, 0), Position = UDim2.fromOffset(14, 0), TextXAlignment = Enum.TextXAlignment.Left })
  loadoutRows[tab.id] = text(rowBox, '—', 17, palette.white, Enum.Font.FredokaOne, { Size = UDim2.new(0.6, -14, 1, 0), Position = UDim2.fromScale(0.4, 0), TextXAlignment = Enum.TextXAlignment.Right })
end

-- ===== Showing a profile =====
local viewingOther = false
local function showCard(name, userId, equipped, stats)
  equipped = equipped or {}
  stats = stats or {}
  local bannerItem = byId[equipped.banner] or byId[SLOT_DEFAULT.banner]
  bannerPaint.Color = ColorSequence.new(rgb(bannerItem.colors[1]), rgb(bannerItem.colors[2]))
  cardAvatar.Image = headshot(userId)
  applyAvatarFrame(cardAvatar, equipped.frame, 92)
  cardName.Text = name or ''
  local titleItem = byId[equipped.title] or byId[SLOT_DEFAULT.title]
  cardTitle.Text = titleItem.label
  cardTitle.TextColor3 = rgb(titleItem.color)
  for index, cell in ipairs(STAT_CELLS) do statValues[index].Text = cell.value(stats) end
end

local function showOwn()
  local s = latest or {}
  showCard(me.DisplayName, me.UserId, s.equipped, s.stats)
  coinsLabel.Text = '● ' .. formatK(s.coins or 0) .. ' coins'
  refreshTiles()
end

local function fit()
  local cam = workspace.CurrentCamera
  local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
  scale.Scale = math.min(1, (vp.X - 28) / PANEL_W, (vp.Y - 28) / PANEL_H)
  if not dim.Visible then
    panel.Size = UDim2.fromOffset(PANEL_W - 24, PANEL_H - 24)
    TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(PANEL_W, PANEL_H) }):Play()
  end
  dim.Visible = true
end

local function openOwn()
  viewingOther = false
  customize.Visible, showcase.Visible = true, false
  selectTab(activeTab)
  showOwn()
  fit()
end
C.openProfile = openOwn

local function showOther(data)
  viewingOther = true
  customize.Visible, showcase.Visible = false, true
  showCard(data.name, data.userId, data.equipped, data.stats)
  showcaseTitle.Text = data.human and 'LOADOUT' or 'COMPUTER PLAYER'
  for id, row in pairs(loadoutRows) do
    local item = byId[data.equipped and data.equipped[id]]
    row.Text = item and item.label or '—'
  end
  fit()
end

local function close() dim.Visible = false end
closeBtn.Activated:Connect(function() playSound('click'); close() end)
dim.Activated:Connect(close)

-- ===== Entry points =====
local homeAvatar
if home and home.profileBtn then
  home.profileBtn.BackgroundTransparency = 1
  for _, child in ipairs(home.profileBtn:GetChildren()) do
    if child:IsA('UIStroke') or child:IsA('UIGradient') then child:Destroy() end
  end
  homeAvatar = new('ImageLabel', home.profileBtn, { Name = 'Avatar', BackgroundColor3 = color(20, 26, 50), Size = UDim2.fromScale(1, 1), Image = headshot(me.UserId), ZIndex = (home.profileBtn.ZIndex or 1) + 1 })
  round(homeAvatar, 999)
  new('UIStroke', homeAvatar, { Color = GOLD, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end

-- Tapping anywhere on a seat opens that player's profile.
for seat, s in pairs(seats or {}) do
  local tap = new('TextButton', s.holder, { Name = 'ProfileTap', Text = '', BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 30 })
  tap.Activated:Connect(function()
    playSound('click')
    remote:FireServer('view_profile', seat)
  end)
end

-- Your own avatar and name at the table open your editable profile.
for _, spot in ipairs({ C.selfAvatar, C.selfName }) do
  local tap = new('TextButton', spot, { Name = 'ProfileTap', Text = '', BackgroundTransparency = 1, AutoButtonColor = false, Size = UDim2.fromScale(1, 1), ZIndex = 30 })
  tap.Activated:Connect(function()
    playSound('click')
    openOwn()
  end)
end

-- What a player wears on their seat: frame, title (under the name) and banner tint.
function C.applySeatCosmetics(s, info)
  applyAvatarFrame(s.avatar, info.frame, 40)
  local title = byId[info.title]
  local isDefaultTitle = not title or info.title == SLOT_DEFAULT.title
  s.titleText = (not isDefaultTitle) and title.label or nil
  s.titleColor = (not isDefaultTitle) and rgb(title.color) or nil
  -- At Ranked tables the title line shows the player's tier instead.
  if info.rankTier then
    local colors = C.arenaUI and C.arenaUI.rankColors and C.arenaUI.rankColors[string.match(info.rankTier, '^%a+')]
    s.titleText = '★ ' .. string.upper(info.rankTier)
    s.titleColor = colors and colors[1] or s.titleColor
  end
  local paint = s.cardBg and s.cardBg:FindFirstChildOfClass('UIGradient')
  if paint then
    local banner = info.banner ~= SLOT_DEFAULT.banner and byId[info.banner]
    if banner then
      local a, b = banner.colors[1], banner.colors[2]
      paint.Color = ColorSequence.new(color(a[1] * 0.65, a[2] * 0.65, a[3] * 0.65), color(b[1] * 0.65, b[2] * 0.65, b[3] * 0.65))
    else
      paint.Color = ColorSequence.new(color(34, 52, 78), color(18, 28, 44))
    end
  end
end

local function onState(message)
  latest = message
  if homeAvatar then applyAvatarFrame(homeAvatar, message.equipped and message.equipped.frame, 32) end
  if C.selfAvatar then applyAvatarFrame(C.selfAvatar, message.equipped and message.equipped.frame, 22) end
  if dim.Visible and not viewingOther then showOwn() end
end
if latest and latest.owned then onState(latest) end

remote.OnClientEvent:Connect(function(message)
  if type(message) ~= 'table' then return end
  if message.type == 'profile' then showOther(message)
  elseif message.owned then onState(message) end
end)
end
