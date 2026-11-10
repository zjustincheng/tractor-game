-- Happy Tractor client: rank-up celebration.
-- When a Ranked round promotes you, a medal in the new tier's colours pops
-- up over the result screen. Tap anywhere (or wait) to close it.
return function(C)
local root, palette, playSound, arenaUI = C.root, C.palette, C.playSound, C.arenaUI
local TweenService = game:GetService('TweenService')
local color = Color3.fromRGB
local function new(class, parent, props)
  local o = Instance.new(class)
  for k, v in pairs(props or {}) do o[k] = v end
  o.Parent = parent
  return o
end

local shade = new('TextButton', root, { Name = 'RankUp', Text = '', AutoButtonColor = false, BackgroundColor3 = color(0, 0, 0),
  BackgroundTransparency = 0.4, Size = UDim2.fromScale(1, 1), ZIndex = 120, Visible = false })
local card = new('Frame', shade, { Name = 'Card', AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45),
  Size = UDim2.fromOffset(320, 262), BackgroundColor3 = color(30, 24, 48), ZIndex = 121 })
new('UICorner', card, { CornerRadius = UDim.new(0, 18) })
new('UIStroke', card, { Color = palette.gold, Thickness = 3 })
local scale = new('UIScale', card, { Scale = 1 })
local medal = new('Frame', card, { Name = 'Medal', AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20),
  Size = UDim2.fromOffset(112, 112), BackgroundColor3 = color(205, 127, 50), ZIndex = 122 })
new('UICorner', medal, { CornerRadius = UDim.new(1, 0) })
new('UIStroke', medal, { Color = color(255, 255, 255), Thickness = 4 })
local star = new('TextLabel', medal, { Name = 'Star', Text = '★', TextSize = 66, Font = Enum.Font.GothamBold, BackgroundTransparency = 1,
  Size = UDim2.fromScale(1, 1), TextColor3 = color(120, 70, 25), ZIndex = 123 })
new('TextLabel', card, { Name = 'Heading', Text = 'PROMOTED!', TextSize = 20, Font = Enum.Font.FredokaOne, BackgroundTransparency = 1,
  Position = UDim2.fromOffset(0, 140), Size = UDim2.new(1, 0, 0, 24), TextColor3 = palette.goldBright, ZIndex = 122 })
local tierName = new('TextLabel', card, { Name = 'Tier', Text = '', TextSize = 40, Font = Enum.Font.FredokaOne, BackgroundTransparency = 1,
  Position = UDim2.fromOffset(0, 166), Size = UDim2.new(1, 0, 0, 48), TextColor3 = color(255, 255, 255),
  TextStrokeTransparency = 0.2, TextStrokeColor3 = color(20, 16, 30), ZIndex = 122 })
new('TextLabel', card, { Name = 'Hint', Text = 'Tap to continue', TextSize = 11, Font = Enum.Font.GothamBold, BackgroundTransparency = 1,
  Position = UDim2.fromOffset(0, 226), Size = UDim2.new(1, 0, 0, 16), TextColor3 = palette.muted, ZIndex = 122 })

local showing = 0
shade.Activated:Connect(function() shade.Visible = false end)
local function show(tier)
  local colors = arenaUI.rankColors and arenaUI.rankColors[string.match(tier, '^%a+')]
  if colors then medal.BackgroundColor3, star.TextColor3, tierName.TextColor3 = colors[1], colors[3], colors[1] end
  tierName.Text = string.upper(tier)
  shade.Visible = true
  scale.Scale, medal.Rotation = 0.3, -30
  TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
  TweenService:Create(medal, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Rotation = 0 }):Play()
  if playSound then playSound('double_up') end
  showing = showing + 1
  local token = showing
  task.delay(5, function() if token == showing then shade.Visible = false end end)
end

-- Shown once per promotion, when its round's result arrives.
local shownKey
local baseRender = C.render
C.render = function(...)
  baseRender(...)
  local game = C.state and C.state.game
  local result = game and game.done and game.settlement
  if result and result.rankPromoted then
    local key = tostring(result.rankPromoted) .. ':' .. tostring(result.rankPoints) .. ':' .. tostring(game.revision)
    if key ~= shownKey then
      shownKey = key
      show(result.rankPromoted)
    end
  end
end
end
