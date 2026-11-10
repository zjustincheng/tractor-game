-- Happy Tractor client: reconnect banner.
-- If you dropped out of a round that other people are still playing, the
-- server offers your seat back for a few minutes. This shows that offer as a
-- banner at the top of the lobby: REJOIN returns you to the table.
return function(C)
local Players = game:GetService('Players')
local palette, playSound = C.palette, C.playSound
if not C.command then return end
local color = Color3.fromRGB
local INK = color(20, 16, 30)
local function new(class, parent, props)
  local o = Instance.new(class)
  for k, v in pairs(props or {}) do o[k] = v end
  o.Parent = parent
  return o
end

local gui = new('ScreenGui', Players.LocalPlayer:WaitForChild('PlayerGui'), { Name = 'TractorRejoin', ResetOnSpawn = false, DisplayOrder = 58, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local bar = new('Frame', gui, { Name = 'Banner', AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(460, 48),
  BackgroundColor3 = color(28, 34, 66), Visible = false })
new('UICorner', bar, { CornerRadius = UDim.new(0, 14) })
new('UIStroke', bar, { Color = color(255, 200, 60), Thickness = 3 })
local scale = new('UIScale', bar, { Scale = 1 })
new('TextLabel', bar, { BackgroundTransparency = 1, Text = 'Your last round is still going!', Font = Enum.Font.FredokaOne, TextSize = 17, TextColor3 = palette.white,
  TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(16, 0), Size = UDim2.new(1, -230, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
local function pill(label, x, w, bg)
  local b = new('TextButton', bar, { Text = label, Font = Enum.Font.FredokaOne, TextSize = 15, TextColor3 = bg and INK or palette.white,
    BackgroundColor3 = bg or color(60, 68, 110), Position = UDim2.new(1, x, 0.5, -16), Size = UDim2.fromOffset(w, 32) })
  new('UICorner', b, { CornerRadius = UDim.new(0, 10) })
  new('UIStroke', b, { Color = INK, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
  return b
end
local rejoin = pill('REJOIN', -208, 96, color(255, 200, 60))
local dismiss = pill('NO THANKS', -104, 96)

local hiddenUntilNextOffer = false
local function refresh()
  local state = C.state
  local offered = state ~= nil and state.rejoinOffer == true
  if not offered then hiddenUntilNextOffer = false end
  local inGame = state ~= nil and state.game ~= nil and not state.game.done
  bar.Visible = offered and not inGame and not hiddenUntilNextOffer
  local cam = workspace.CurrentCamera
  if cam then scale.Scale = math.min(1, (cam.ViewportSize.X - 16) / 460) end
end
rejoin.Activated:Connect(function()
  if playSound then playSound('click') end
  hiddenUntilNextOffer = true
  bar.Visible = false
  C.command('rejoin')
end)
dismiss.Activated:Connect(function()
  if playSound then playSound('click') end
  hiddenUntilNextOffer = true
  bar.Visible = false
  C.command('rejoin_dismiss')
end)

local baseRender = C.render
C.render = function(...)
  baseRender(...)
  refresh()
end
refresh()
end
