-- Happy Tractor client: Battle Pass.
-- 30 tiers with a free and a premium track. The server owns XP, tiers, claims
-- and the premium unlock; this page only displays them and asks to claim.
return function(C)
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')
local MarketplaceService = game:GetService('MarketplaceService')
local Catalog, playSound, remote, palette, home, formatK = C.Catalog, C.playSound, C.remote, C.palette, C.home, C.formatK
local pass = Catalog.pass
if not pass then return end
local color = Color3.fromRGB
local INK = color(20, 16, 30)
local GOLD = color(255, 200, 60)
local MUTED = color(165, 175, 200)
local PURPLE = color(150, 90, 240)
local PANEL_W, PANEL_H = 780, 460
local me = Players.LocalPlayer

local function new(class, parent, props)
  local o = Instance.new(class)
  for k, v in pairs(props or {}) do o[k] = v end
  o.Parent = parent
  return o
end
local function round(o, r) new('UICorner', o, { CornerRadius = UDim.new(0, r or 10) }) end
local function stroke(o, c, t) return new('UIStroke', o, { Color = c or INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function shade2(o, a, b) return new('UIGradient', o, { Color = ColorSequence.new(a, b), Rotation = 90 }) end
local function text(parent, str, size, col, font, props)
  local l = new('TextLabel', parent, { BackgroundTransparency = 1, Text = str, TextSize = size, TextColor3 = col or palette.white, Font = font or Enum.Font.GothamBold, TextWrapped = false })
  for k, v in pairs(props or {}) do l[k] = v end
  return l
end
local function rgb(t) return color(t[1], t[2], t[3]) end
local itemsById = {}
for _, item in ipairs(Catalog.profile or {}) do itemsById[item.id] = item end

local latest = C.state
local function passState() return latest and latest.pass or { xp = 0, premium = false, claimedFree = {}, claimedPremium = {} } end
local function tierOf(xp) return math.min(#pass.tiers, math.floor((xp or 0) / pass.xpPerTier)) end
local function contains(list, value)
  for _, entry in ipairs(list or {}) do if entry == value then return true end end
  return false
end

-- ===== Panel =====
local gui = new('ScreenGui', me:WaitForChild('PlayerGui'), { Name = 'TractorBattlePass', ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 57 })
local dim = new('TextButton', gui, { Name = 'Shade', Text = '', AutoButtonColor = false, BackgroundColor3 = color(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1), Visible = false })
local panel = new('TextButton', dim, { Name = 'Panel', Text = '', AutoButtonColor = false, BackgroundColor3 = palette.white, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(PANEL_W, PANEL_H) })
round(panel, 20); stroke(panel, GOLD, 3)
shade2(panel, color(40, 46, 86), color(16, 18, 38))
local scale = new('UIScale', panel, { Scale = 1 })
local closeBtn = new('TextButton', panel, { Name = 'Close', Text = 'X', TextSize = 18, Font = Enum.Font.FredokaOne, TextColor3 = palette.white, BackgroundColor3 = color(220, 60, 60), Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -20, 0, -14), ZIndex = 5 })
round(closeBtn, 17); stroke(closeBtn, INK, 2)

text(panel, '🎟 ' .. string.upper(pass.name), 24, GOLD, Enum.Font.FredokaOne, { Name = 'Season', Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(400, 32), TextXAlignment = Enum.TextXAlignment.Left })
local subLine = text(panel, '', 13, MUTED, Enum.Font.GothamBold, { Name = 'Progress', Position = UDim2.fromOffset(16, 42), Size = UDim2.fromOffset(420, 18), TextXAlignment = Enum.TextXAlignment.Left })
local barBack = new('Frame', panel, { Name = 'Bar', BackgroundColor3 = color(12, 14, 34), Position = UDim2.fromOffset(16, 64), Size = UDim2.fromOffset(420, 14) })
round(barBack, 7)
local barFill = new('Frame', barBack, { Name = 'Fill', BackgroundColor3 = GOLD, Size = UDim2.fromScale(0, 1) })
round(barFill, 7)
local status = text(panel, '', 12, GOLD, Enum.Font.GothamBold, { Name = 'Status', Position = UDim2.fromOffset(448, 66), Size = UDim2.fromOffset(316, 16), TextXAlignment = Enum.TextXAlignment.Right })

local function headerButton(name, label, x, w, tint, textColor)
  local b = new('TextButton', panel, { Name = name, Text = label, TextSize = 14, Font = Enum.Font.FredokaOne, TextColor3 = textColor or INK, BackgroundColor3 = tint, AutoButtonColor = false, Position = UDim2.fromOffset(x, 18), Size = UDim2.fromOffset(w, 40) })
  round(b, 11); stroke(b, INK, 2)
  return b
end
local claimAll = headerButton('ClaimAll', 'CLAIM ALL', 448, 130, color(70, 200, 120))
local unlock = headerButton('Unlock', 'PREMIUM  R$ ' .. pass.robux, 586, 166, PURPLE, palette.white)

text(panel, 'FREE', 13, palette.white, Enum.Font.FredokaOne, { Position = UDim2.fromOffset(10, 130), Size = UDim2.fromOffset(78, 136) })
text(panel, 'PREMIUM', 12, color(205, 170, 255), Enum.Font.FredokaOne, { Position = UDim2.fromOffset(10, 278), Size = UDim2.fromOffset(78, 136) })

local track = new('ScrollingFrame', panel, { Name = 'Track', BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(92, 92), Size = UDim2.fromOffset(676, 358),
  CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X, ScrollBarThickness = 6, ScrollBarImageColor3 = GOLD, ScrollingDirection = Enum.ScrollingDirection.X })
new('UIListLayout', track, { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })

local cells, tierLabels = {}, {}

local function rewardPreview(reward, area)
  if reward.coins then
    text(area, '●', 26, GOLD, Enum.Font.GothamBold, { Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 8) })
    text(area, formatK(reward.coins), 18, GOLD, Enum.Font.FredokaOne, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 50) })
    return 'Coins'
  end
  if reward.boost then
    text(area, '⏱', 24, color(120, 240, 170), Enum.Font.GothamBold, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 8) })
    text(area, reward.boost .. ' MIN', 18, color(120, 240, 170), Enum.Font.FredokaOne, { Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 50) })
    return 'Card Markers'
  end
  local item = itemsById[reward.item]
  if not item then return '?' end
  if item.category == 'frame' then
    local face = new('ImageLabel', area, { BackgroundColor3 = color(20, 26, 50), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(50, 50), Image = 'rbxthumb://type=AvatarHeadShot&id=' .. me.UserId .. '&w=150&h=150' })
    round(face, 25)
    if C.applyAvatarFrame then C.applyAvatarFrame(face, item.id, 50) end
  elseif item.category == 'title' then
    text(area, item.label, 14, rgb(item.color), Enum.Font.FredokaOne, { Size = UDim2.new(1, -8, 1, 0), Position = UDim2.fromOffset(4, 0), TextWrapped = true })
  elseif item.category == 'banner' then
    area.BackgroundColor3 = palette.white
    shade2(area, rgb(item.colors[1]), rgb(item.colors[2]))
  end
  return item.label
end

local function makeCell(parent, y, kind, tier, reward)
  if not reward then return end
  local premium = kind == 'premium'
  local box = new('Frame', parent, { Name = kind, BackgroundColor3 = premium and color(52, 38, 92) or color(30, 36, 70), Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 142) })
  round(box, 11)
  local line = stroke(box, INK, 1.5)
  local area = new('Frame', box, { Name = 'Preview', BackgroundColor3 = color(14, 18, 40), Position = UDim2.fromOffset(5, 5), Size = UDim2.new(1, -10, 0, 80), ClipsDescendants = reward.coins ~= nil })
  round(area, 8)
  local name = rewardPreview(reward, area)
  text(box, name, 11, palette.white, Enum.Font.FredokaOne, { Name = 'Label', Position = UDim2.fromOffset(4, 87), Size = UDim2.new(1, -8, 0, 16), TextTruncate = Enum.TextTruncate.AtEnd })
  local action = new('TextButton', box, { Name = 'Action', Text = '', TextSize = 12, Font = Enum.Font.FredokaOne, AutoButtonColor = false, Position = UDim2.fromOffset(5, 106), Size = UDim2.new(1, -10, 0, 30) })
  round(action, 8)
  local cell = { kind = kind, tier = tier, action = action, line = line, canClaim = false, boost = reward.boost ~= nil }
  action.Activated:Connect(function()
    if not cell.canClaim then return end
    playSound('coin')
    remote:FireServer('pass_claim', { track = kind, tier = tier })
  end)
  table.insert(cells, cell)
end

for tier, rewards in ipairs(pass.tiers) do
  local column = new('Frame', track, { Name = 'Tier' .. tier, LayoutOrder = tier, BackgroundTransparency = 1, Size = UDim2.fromOffset(112, 346) })
  tierLabels[tier] = text(column, tostring(tier), 16, MUTED, Enum.Font.FredokaOne, { Size = UDim2.new(1, 0, 0, 26) })
  makeCell(column, 30, 'free', tier, rewards.free)
  makeCell(column, 178, 'premium', tier, rewards.premium)
end

local function seasonOver() return os.time() >= pass.endsAt end
local function isVip() return latest ~= nil and latest.vip == true end
-- Timed boosts start when claimed, so Claim All leaves them for the player.
local function claimableCount(includeBoosts)
  local s, n = passState(), 0
  local reached = tierOf(s.xp)
  for _, cell in ipairs(cells) do
    local claimed = contains(cell.kind == 'free' and s.claimedFree or s.claimedPremium, cell.tier)
    local usable = not cell.boost or (includeBoosts and not isVip())
    if cell.tier <= reached and not claimed and usable and (cell.kind == 'free' or s.premium) then n = n + 1 end
  end
  return n
end

local function refresh()
  local s = passState()
  local reached = tierOf(s.xp)
  local isMax = reached >= #pass.tiers
  local into = isMax and pass.xpPerTier or (s.xp or 0) % pass.xpPerTier
  barFill.Size = UDim2.fromScale(into / pass.xpPerTier, 1)
  local daysLeft = math.max(0, math.ceil((pass.endsAt - os.time()) / 86400))
  subLine.Text = 'Tier ' .. reached .. ' / ' .. #pass.tiers .. '   ·   ' .. (isMax and 'Maxed out' or (into .. ' / ' .. pass.xpPerTier .. ' XP')) .. '   ·   ' .. (seasonOver() and 'Season over' or (daysLeft .. ' days left'))
  for tier, label in pairs(tierLabels) do label.TextColor3 = tier <= reached and GOLD or MUTED end
  for _, cell in ipairs(cells) do
    local claimed = contains(cell.kind == 'free' and s.claimedFree or s.claimedPremium, cell.tier)
    local open = cell.tier <= reached
    local locked = cell.kind == 'premium' and not s.premium
    cell.canClaim = open and not claimed and not locked and not (cell.boost and isVip())
    local tint, label, ink = color(50, 54, 82), '🔒', MUTED
    if claimed then tint, label, ink = color(40, 110, 70), '✓ CLAIMED', palette.white
    elseif cell.canClaim then tint, label, ink = GOLD, 'CLAIM', INK
    elseif open and locked then tint, label, ink = PURPLE, '🔒 PREMIUM', palette.white
    elseif cell.boost and isVip() then tint, label, ink = color(40, 110, 70), 'VIP ✓', palette.white
    end
    cell.action.BackgroundColor3, cell.action.Text, cell.action.TextColor3 = tint, label, ink
    cell.line.Color = cell.canClaim and GOLD or INK
    cell.line.Thickness = cell.canClaim and 3 or 1.5
  end
  local count = claimableCount(false)
  if not isVip() and latest and (latest.markersLeft or 0) > 0 then
    status.Text = 'Card markers: ' .. math.ceil(latest.markersLeft / 60) .. ' min of play left'
  end
  claimAll.BackgroundColor3 = count > 0 and color(70, 200, 120) or color(50, 54, 82)
  claimAll.Text = count > 0 and ('CLAIM ALL (' .. count .. ')') or 'CLAIM ALL'
  claimAll.TextColor3 = count > 0 and INK or MUTED
  unlock.Text = s.premium and '✓ PREMIUM' or ('PREMIUM  R$ ' .. pass.robux)
  unlock.BackgroundColor3 = s.premium and color(40, 110, 70) or PURPLE
end

claimAll.Activated:Connect(function()
  if claimableCount(false) == 0 then return end
  playSound('coin')
  remote:FireServer('pass_claim_all')
end)
unlock.Activated:Connect(function()
  if passState().premium then return end
  playSound('click')
  if (pass.productId or 0) > 0 then
    MarketplaceService:PromptProductPurchase(me, pass.productId)
  else
    status.Text = 'Premium is not on sale yet.'
  end
end)

local function open()
  local cam = workspace.CurrentCamera
  local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
  scale.Scale = math.min(1, (vp.X - 28) / PANEL_W, (vp.Y - 28) / PANEL_H)
  status.Text = ''
  refresh()
  dim.Visible = true
  panel.Size = UDim2.fromOffset(PANEL_W - 24, PANEL_H - 24)
  TweenService:Create(panel, TweenInfo.new(0.22, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(PANEL_W, PANEL_H) }):Play()
  -- Start at the next tier to work toward.
  track.CanvasPosition = Vector2.new(math.max(0, (tierOf(passState().xp) - 1) * 118), 0)
end
C.openBattlePass = open
local function close() dim.Visible = false end
closeBtn.Activated:Connect(function() playSound('click'); close() end)
dim.Activated:Connect(close)

-- ===== Lobby button, left of the leaderboard =====
local badge
if home and home.mailBtn then
  local mail = home.mailBtn
  local btn = mail:Clone()
  btn.Name = 'PassBtn'
  for _, child in ipairs(btn:GetChildren()) do
    if child.Name == 'Badge' or child:IsA('LuaSourceContainer') then child:Destroy() end
  end
  btn.Text = '🎟'
  btn.Parent = mail.Parent
  home.battlePassBtn = btn
  local function follow()
    btn.Size = mail.Size
    btn.Position = mail.Position - UDim2.fromOffset((mail.AbsoluteSize.X + 4) * 2, 0)
    btn.Visible = mail.Visible
  end
  mail:GetPropertyChangedSignal('Position'):Connect(follow)
  mail:GetPropertyChangedSignal('Size'):Connect(follow)
  mail:GetPropertyChangedSignal('Visible'):Connect(follow)
  follow()
  btn.Activated:Connect(function() playSound('click'); open() end)
  badge = new('Frame', btn, { Name = 'ClaimDot', BackgroundColor3 = color(230, 60, 60), Position = UDim2.new(1, -9, 0, -3), Size = UDim2.fromOffset(12, 12), ZIndex = (btn.ZIndex or 1) + 2, Visible = false })
  round(badge, 6)
end

local function onState(message)
  latest = message
  if badge then badge.Visible = claimableCount(true) > 0 end
  if dim.Visible then refresh() end
end
if latest and latest.owned then onState(latest) end
remote.OnClientEvent:Connect(function(message)
  if type(message) == 'table' and message.owned then onState(message) end
end)
end
