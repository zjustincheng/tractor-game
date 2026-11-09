-- Happy Tractor client: global "Richest Players" leaderboard.
-- A 🏆 button in the home header opens a panel with the top 50 coin holders
-- across all servers (from the server's OrderedDataStore), with avatars,
-- medals for the top 3, and your own rank highlighted.
return function(C)
local Players = game:GetService('Players')
local TweenService = game:GetService('TweenService')
local playSound, remote, palette, home = C.playSound, C.remote, C.palette, C.home
local color = Color3.fromRGB
local INK = color(20, 16, 30)
local GOLD = color(255, 200, 60)
local CREAM = color(255, 246, 220)
local me = Players.LocalPlayer

local function new(class, parent, props)
  local o = Instance.new(class)
  for k, v in pairs(props or {}) do o[k] = v end
  o.Parent = parent
  return o
end
local function round(o, r) new('UICorner', o, { CornerRadius = UDim.new(0, r or 10) }) end
local function stroke(o, c, t) new('UIStroke', o, { Color = c or INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }) end
local function text(parent, str, size, col, font, props)
  local l = new('TextLabel', parent, { BackgroundTransparency = 1, Text = str, TextSize = size, TextColor3 = col or palette.white,
    Font = font or Enum.Font.GothamBold, TextWrapped = false })
  for k, v in pairs(props or {}) do l[k] = v end
  return l
end
local function outlined(l, t)
  new('UIStroke', l, { Color = INK, Thickness = t or 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
  return l
end
local function fmt(n)
  n = math.floor(n or 0)
  local s = tostring(n)
  local out = s:reverse():gsub('(%d%d%d)', '%1,'):reverse()
  return (out:gsub('^,', ''))
end

-- ===== Panel =====
local gui = new('ScreenGui', me:WaitForChild('PlayerGui'), { Name = 'TractorLeaderboard', ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 55, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local shade = new('TextButton', gui, { Name = 'Shade', Text = '', AutoButtonColor = false, BackgroundColor3 = color(0, 0, 0), BackgroundTransparency = 0.4, Size = UDim2.fromScale(1, 1), Visible = false })
local panel = new('Frame', shade, { Name = 'Panel', BackgroundColor3 = palette.white, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(480, 580), Active = true })
round(panel, 22); stroke(panel, GOLD, 4)
new('UIGradient', panel, { Color = ColorSequence.new(color(40, 46, 86), color(16, 18, 38)), Rotation = 90 })
local scale = new('UIScale', panel, { Scale = 1 })

local header = new('Frame', panel, { BackgroundColor3 = palette.white, Size = UDim2.new(1, -24, 0, 70), Position = UDim2.fromOffset(12, 12) })
round(header, 16); stroke(header, INK, 2.5)
new('UIGradient', header, { Color = ColorSequence.new(color(255, 220, 90), color(220, 120, 20)), Rotation = 90 })
outlined(text(header, '🏆 RICHEST PLAYERS', 28, palette.white, Enum.Font.FredokaOne, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 6) }), 2.5)
outlined(text(header, 'TOP 50 · ALL SERVERS', 13, CREAM, Enum.Font.FredokaOne, { Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 44) }), 1.5)

local list = new('ScrollingFrame', panel, { Name = 'List', BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.new(1, -24, 1, -186), Position = UDim2.fromOffset(12, 92),
  CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 6, ScrollBarImageColor3 = GOLD, ScrollingDirection = Enum.ScrollingDirection.Y })
new('UIListLayout', list, { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder })
new('UIPadding', list, { PaddingRight = UDim.new(0, 10) })
local status = text(panel, '', 16, CREAM, Enum.Font.GothamBold, { Size = UDim2.new(1, -40, 0, 60), Position = UDim2.fromOffset(20, 200), TextWrapped = true, Visible = false })

local footer = new('Frame', panel, { BackgroundColor3 = color(60, 140, 255), Size = UDim2.new(1, -24, 0, 70), Position = UDim2.new(0, 12, 1, -82) })
round(footer, 14); stroke(footer, INK, 2)
new('UIGradient', footer, { Color = ColorSequence.new(color(255, 255, 255), color(200, 200, 210)), Rotation = 90 })
local footerAvatar = new('ImageLabel', footer, { BackgroundColor3 = color(30, 40, 70), Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(10, 10),
  Image = 'rbxthumb://type=AvatarHeadShot&id=' .. me.UserId .. '&w=150&h=150' })
round(footerAvatar, 25)
local footerRank = outlined(text(footer, 'YOU', 22, palette.white, Enum.Font.FredokaOne, { Size = UDim2.new(0.5, -70, 1, 0), Position = UDim2.fromOffset(70, 0), TextXAlignment = Enum.TextXAlignment.Left }), 2)
local footerCoins = outlined(text(footer, '', 22, GOLD, Enum.Font.FredokaOne, { Size = UDim2.new(0.5, -16, 1, 0), Position = UDim2.new(0.5, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }), 2)

local closeBtn = new('TextButton', panel, { Text = 'X', TextSize = 18, Font = Enum.Font.FredokaOne, TextColor3 = palette.white, BackgroundColor3 = color(200, 60, 70),
  Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -20, 0, -14) })
round(closeBtn, 17); stroke(closeBtn, INK, 2)

local MEDALS = { '🥇', '🥈', '🥉' }
local RANK_COLORS = { { color(255, 215, 80), color(200, 130, 20) }, { color(220, 225, 240), color(140, 150, 175) }, { color(235, 150, 90), color(150, 80, 40) } }

local function row(entry, mine)
  local top3 = entry.rank <= 3
  local r = new('Frame', list, { Name = 'Row' .. entry.rank, LayoutOrder = entry.rank, BackgroundColor3 = palette.white, Size = UDim2.new(1, 0, 0, top3 and 58 or 48) })
  round(r, 12)
  stroke(r, mine and color(80, 200, 255) or INK, mine and 3 or 1.5)
  local colors = top3 and RANK_COLORS[entry.rank] or (mine and { color(60, 120, 220), color(30, 60, 140) } or { color(50, 58, 96), color(32, 36, 64) })
  new('UIGradient', r, { Color = ColorSequence.new(colors[1], colors[2]), Rotation = 90 })
  local rankText = top3 and MEDALS[entry.rank] or ('#' .. entry.rank)
  outlined(text(r, rankText, top3 and 30 or 18, palette.white, Enum.Font.FredokaOne, { Size = UDim2.new(0, 52, 1, 0), Position = UDim2.fromOffset(4, 0) }), 1.5)
  local size = top3 and 44 or 36
  local avatar = new('ImageLabel', r, { BackgroundColor3 = color(20, 26, 50), Size = UDim2.fromOffset(size, size), Position = UDim2.new(0, 58, 0.5, -size / 2),
    Image = 'rbxthumb://type=AvatarHeadShot&id=' .. tostring(entry.userId) .. '&w=150&h=150' })
  round(avatar, size / 2)
  local name = outlined(text(r, (entry.name or '?') .. (mine and '  (you)' or ''), top3 and 19 or 16, palette.white, Enum.Font.FredokaOne,
    { Size = UDim2.new(1, -250, 1, 0), Position = UDim2.fromOffset(66 + size, 0), TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd }), 1.5)
  outlined(text(r, fmt(entry.coins), top3 and 19 or 16, top3 and palette.white or GOLD, Enum.Font.FredokaOne,
    { Size = UDim2.new(0, 150, 1, 0), Position = UDim2.new(1, -160, 0, 0), TextXAlignment = Enum.TextXAlignment.Right }), 1.5)
  return r
end

local function render(data)
  for _, child in ipairs(list:GetChildren()) do if child:IsA('Frame') then child:Destroy() end end
  status.Visible = false
  if not data.available then
    status.Text = 'The leaderboard turns on once the game is published and saving works.'
    status.Visible = true
  elseif #data.entries == 0 then
    status.Text = 'No scores yet. Play a round and you could be #1!'
    status.Visible = true
  end
  for _, entry in ipairs(data.entries or {}) do row(entry, entry.userId == me.UserId) end
  footerRank.Text = data.yourRank and ('YOU · #' .. data.yourRank) or 'YOU · NOT IN TOP 50'
  footerCoins.Text = fmt(data.yourCoins) .. ' COINS'
end

local function open()
  local cam = workspace.CurrentCamera
  local vp = cam and cam.ViewportSize or Vector2.new(1280, 720)
  scale.Scale = math.min(1, (vp.X - 24) / 480, (vp.Y - 24) / 580)
  status.Text = 'Loading…'
  status.Visible = true
  for _, child in ipairs(list:GetChildren()) do if child:IsA('Frame') then child:Destroy() end end
  footerCoins.Text = fmt(C.state and C.state.coins) .. ' COINS'
  shade.Visible = true
  panel.Size = UDim2.fromOffset(460, 560)
  TweenService:Create(panel, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(480, 580) }):Play()
  remote:FireServer('leaderboard')
end
C.openLeaderboard = open
local function close() shade.Visible = false end
closeBtn.Activated:Connect(function() playSound('click'); close() end)
shade.Activated:Connect(close)

remote.OnClientEvent:Connect(function(message)
  if type(message) == 'table' and message.type == 'leaderboard' and shade.Visible then render(message) end
end)

-- ===== 🏆 button in the home header, just left of the mail button =====
if home and home.mailBtn then
  local mail = home.mailBtn
  local btn = mail:Clone()
  btn.Name = 'LeaderBtn'
  for _, child in ipairs(btn:GetChildren()) do
    if child.Name == 'Badge' or child:IsA('LuaSourceContainer') then child:Destroy() end
  end
  btn.Text = '🏆'
  btn.Parent = mail.Parent
  home.leaderBtn = btn
  local function follow()
    btn.Size = mail.Size
    btn.Position = mail.Position - UDim2.fromOffset(mail.AbsoluteSize.X + 4, 0)
    btn.Visible = mail.Visible
  end
  mail:GetPropertyChangedSignal('Position'):Connect(follow)
  mail:GetPropertyChangedSignal('Size'):Connect(follow)
  mail:GetPropertyChangedSignal('Visible'):Connect(follow)
  follow()
  btn.Activated:Connect(function() playSound('click'); open() end)
end
end
