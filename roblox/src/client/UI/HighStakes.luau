-- Clamp that tolerates max < min (tiny phone screens) instead of erroring.
local function safeClamp(v, lo, hi) if hi < lo then hi = lo end return math.clamp(v, lo, hi) end
-- Happy Tractor client: High Stakes rooms on the tier screen.
-- A STANDARD / HIGH STAKES switch in the tier screen's bottom bar. In High
-- Stakes mode the three table cards become High Roller, Whale Room and
-- Legend Vault (bigger bases; a loss can cost everything you carry), and
-- their PLAY buttons queue for those rooms. The server checks every entry.
return function(C)
local tier, palette, playSound, notice = C.tier, C.palette, C.playSound, C.notice
if not (tier and tier.cardNovice and tier.cardPro and tier.cardMaster) then return end
local TweenService = game:GetService('TweenService')
local color = Color3.fromRGB
local INK = color(20, 16, 30)

local function short(n)
  if n >= 1e6 then return (string.format('%.1f', n / 1e6):gsub('%.0$', '')) .. 'M' end
  if n >= 1e3 then return (string.format('%.1f', n / 1e3):gsub('%.0$', '')) .. 'K' end
  return tostring(math.floor(n))
end

local SLOTS = {
  { card = tier.cardNovice, std = 'novice', key = 'highroller', title = '🎰 HIGH ROLLER', play = 'PLAY HIGH ROLLER ▶',
    base = '15K', entry = 'Entry 250K+', min = 250000, top = color(255, 150, 50), bottom = color(160, 36, 20), banner = color(200, 60, 30) },
  { card = tier.cardPro, std = 'pro', key = 'whale', title = '🐋 WHALE ROOM', play = 'PLAY WHALE ROOM ▶',
    base = '60K', entry = 'Entry 1M+', min = 1000000, top = color(110, 120, 255), bottom = color(40, 18, 130), banner = color(90, 50, 200) },
  { card = tier.cardMaster, std = 'master', key = 'legend', title = '🐉 LEGEND VAULT', play = 'PLAY LEGEND ▶',
    base = '250K', entry = 'Entry 5M+', min = 5000000, top = color(255, 220, 90), bottom = color(150, 60, 10), banner = color(170, 90, 20) },
}
local BY_STD, BY_KEY = {}, {}
for _, s in ipairs(SLOTS) do BY_STD[s.std] = s; BY_KEY[s.key] = s end

-- Remember each card's standard look so switching back restores it exactly.
local function bannerLabel(card) local b = card:FindFirstChild('Banner'); return b and b:FindFirstChild('Text') end
local function stakeVal(card) local p = card:FindFirstChild('StakePill'); return p and p:FindFirstChild('Val') end
for _, s in ipairs(SLOTS) do
  local g = s.card:FindFirstChild('Gradient')
  local b, v, e = bannerLabel(s.card), stakeVal(s.card), s.card:FindFirstChild('Entry')
  local bannerFrame = s.card:FindFirstChild('Banner')
  s.saved = { title = b and b.Text, base = v and v.Text, entry = e and e.Text, gradient = g and g.Color,
    bannerColor = bannerFrame and bannerFrame.BackgroundColor3 }
  -- The Novice card has no lock bar; borrow the Pro card's so High Roller shows progress too.
  if not s.card:FindFirstChild('LockOverlay') and tier.cardPro:FindFirstChild('LockOverlay') then
    local lock = tier.cardPro.LockOverlay:Clone()
    lock.Visible = false
    lock.Parent = s.card
    s.borrowedLock = lock
  end
  -- a small red risk tag, only shown in High Stakes
  local tag = Instance.new('TextLabel')
  tag.Name = 'RiskTag'
  tag.BackgroundColor3 = color(220, 40, 50)
  tag.Text = '☠ HIGH RISK'
  tag.Font = Enum.Font.FredokaOne
  tag.TextSize = 12
  tag.TextColor3 = palette.white
  tag.Size = UDim2.fromOffset(92, 20)
  tag.AnchorPoint = Vector2.new(1, 0)
  tag.Position = UDim2.new(1, -12, 0, 50)
  tag.ZIndex = 9
  tag.Visible = false
  local corner = Instance.new('UICorner'); corner.CornerRadius = UDim.new(0, 6); corner.Parent = tag
  local stroke = Instance.new('UIStroke'); stroke.Color = INK; stroke.Thickness = 1.5; stroke.Parent = tag
  tag.Parent = s.card
  s.riskTag = tag
end

C.highStakes = false

-- ===== The switch =====
local bar = tier.bottomBar
local toggle = Instance.new('Frame')
toggle.Name = 'StakesToggle'
toggle.BackgroundColor3 = color(12, 16, 30)
toggle.Size = UDim2.fromOffset(300, 34)
toggle.AnchorPoint = Vector2.new(1, 0.5)
toggle.Position = UDim2.new(1, -8, 0.5, 0)
toggle.ZIndex = 5
do
  local c = Instance.new('UICorner'); c.CornerRadius = UDim.new(0, 10); c.Parent = toggle
  local s = Instance.new('UIStroke'); s.Color = color(80, 90, 140); s.Thickness = 1.5; s.Parent = toggle
end
toggle.Parent = bar
local knob = Instance.new('Frame')
knob.Name = 'Knob'
knob.BackgroundColor3 = palette.white
knob.Size = UDim2.new(0.5, -4, 1, -6)
knob.Position = UDim2.fromOffset(3, 3)
knob.ZIndex = 5
do
  local c = Instance.new('UICorner'); c.CornerRadius = UDim.new(0, 8); c.Parent = knob
  local g = Instance.new('UIGradient'); g.Name = 'Gradient'; g.Rotation = 90; g.Parent = knob
end
knob.Parent = toggle
local function option(text, x)
  local b = Instance.new('TextButton')
  b.BackgroundTransparency = 1
  b.Text = text
  b.Font = Enum.Font.FredokaOne
  b.TextSize = 14
  b.TextColor3 = palette.white
  b.Size = UDim2.new(0.5, 0, 1, 0)
  b.Position = UDim2.fromScale(x, 0)
  b.ZIndex = 6
  local s = Instance.new('UIStroke'); s.Color = INK; s.Thickness = 1.2; s.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual; s.Parent = b
  b.Parent = toggle
  return b
end
local stdBtn = option('STANDARD', 0)
local highBtn = option('🔥 HIGH STAKES', 0.5)

local tipStd = tier.bottomTip and tier.bottomTip.Text

local function applyLooks()
  local coins = (C.state and C.state.coins) or 0
  local high = C.highStakes
  knob:FindFirstChild('Gradient').Color = high and ColorSequence.new(color(255, 110, 60), color(200, 30, 40))
    or ColorSequence.new(color(255, 214, 70), color(230, 140, 20))
  TweenService:Create(knob, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { Position = high and UDim2.new(0.5, 1, 0, 3) or UDim2.fromOffset(3, 3) }):Play()
  if tier.bottomTip then
    tier.bottomTip.Text = high and '⚠ High Stakes: huge wins, but a lost round can cost everything you carry in.' or tipStd
    tier.bottomTip.TextColor3 = high and color(255, 150, 130) or (palette.sage or palette.white)
  end
  if not high then
    for _, s in ipairs(SLOTS) do
      local b, v, e, g = bannerLabel(s.card), stakeVal(s.card), s.card:FindFirstChild('Entry'), s.card:FindFirstChild('Gradient')
      if b and s.saved.title then b.Text = s.saved.title end
      if v and s.saved.base then v.Text = s.saved.base end
      if e and s.saved.entry then e.Text = s.saved.entry end
      if g and s.saved.gradient then g.Color = s.saved.gradient end
      local bannerFrame = s.card:FindFirstChild('Banner')
      if bannerFrame and s.saved.bannerColor then bannerFrame.BackgroundColor3 = s.saved.bannerColor end
      if s.borrowedLock then s.borrowedLock.Visible = false end
      s.riskTag.Visible = false
      local badge = s.card:FindFirstChild('Badge'); if badge then badge.Visible = true end
    end
    return
  end
  for _, s in ipairs(SLOTS) do
    local card = s.card
    local b, v, e, g = bannerLabel(card), stakeVal(card), card:FindFirstChild('Entry'), card:FindFirstChild('Gradient')
    if b then b.Text = s.title end
    if v then v.Text = s.base end
    if e then e.Text = s.entry end
    if g then g.Color = ColorSequence.new(s.top, s.bottom) end
    local bannerFrame = card:FindFirstChild('Banner')
    if bannerFrame then bannerFrame.BackgroundColor3 = s.banner end
    s.riskTag.Visible = true
    local badge = card:FindFirstChild('Badge'); if badge then badge.Visible = false end
    local best = card:FindFirstChild('BestBadge'); if best then best.Visible = false end
    local locked = coins < s.min
    local lock = card:FindFirstChild('LockOverlay')
    if lock then
      lock.Visible = locked
      local barFrame = lock:FindFirstChild('Bar')
      if barFrame then
        local fill, txt = barFrame:FindFirstChild('Fill'), barFrame:FindFirstChild('Text')
        if fill then fill.Size = UDim2.new(safeClamp(coins / s.min, 0, 1), 0, 1, 0) end
        if txt then txt.Text = 'Need ' .. short(math.max(0, s.min - coins)) .. ' more  ·  ' .. short(coins) .. ' / ' .. short(s.min) end
      end
    end
    local join = card:FindFirstChild('JoinBtn')
    if join then
      local jg = join:FindFirstChild('Gradient')
      if jg then jg.Enabled = not locked end
      join.Text = locked and '🔒 LOCKED' or s.play
      join.BackgroundColor3 = locked and palette.panelLight or palette.gold
      join.TextColor3 = locked and palette.white or palette.ink
    end
  end
end

local function setHigh(on)
  if C.highStakes == on then return end
  C.highStakes = on
  playSound(on and 'double_up' or 'click', nil, on and 0.3 or nil)
  if C.render then C.render() else applyLooks() end
end
stdBtn.Activated:Connect(function() setHigh(false) end)
highBtn.Activated:Connect(function() setHigh(true) end)

-- Re-apply after anything that redraws the tier cards.
local baseRender = C.render
C.render = function(...)
  baseRender(...)
  applyLooks()
end
if C.refreshTierLocks then
  local baseLocks = C.refreshTierLocks
  C.refreshTierLocks = function(...)
    baseLocks(...)
    if C.highStakes then applyLooks() end
  end
end
local baseResize = C.resize
C.resize = function(...)
  baseResize(...)
  -- Leave room for the switch beside the tip.
  if tier.bottomTip then
    tier.bottomTip.Size = UDim2.new(tier.bottomTip.Size.X.Scale, math.max(60, bar.AbsoluteSize.X - 28 - 316), tier.bottomTip.Size.Y.Scale, tier.bottomTip.Size.Y.Offset)
  end
end

-- PLAY buttons queue for the High Stakes room when the switch is on.
local baseOpen = C.openQueue
if baseOpen then
  C.openQueue = function(chosenTier)
    if C.highStakes then
      local s = BY_STD[chosenTier or 'novice'] or BY_KEY[chosenTier]
      if s then
        if ((C.state and C.state.coins) or 0) < s.min then
          if notice then notice.Text = (s.title:gsub('^%S+%s', '')) .. ' requires ' .. short(s.min) .. '+ Coins!' end
          return
        end
        return baseOpen(s.key)
      end
    end
    return baseOpen(chosenTier)
  end
end

applyLooks()
end
