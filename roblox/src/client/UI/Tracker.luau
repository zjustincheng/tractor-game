-- Happy Tractor client: VIP table markers.
-- A green tick on the cards in your hand that are safe to gamble, and an "OUT"
-- tag on each opponent showing the suits they have run out of. VIPs always have
-- these; free players earn 30 or 60 minutes of play time on the Battle Pass. Everything
-- comes from shared/Tracker, which uses only your own hand and cards already played.
return function(C)
local Cards, S, palette, symbols, seats, handFrame = C.Cards, C.Structures, C.palette, C.symbols, C.seats, C.handFrame
local Tracker = require(game:GetService('ReplicatedStorage'):WaitForChild('Tractor'):WaitForChild('Tracker'))(Cards, S)
local color = Color3.fromRGB
local GREEN = color(40, 190, 100)

local function new(class, parent, props)
  local o = Instance.new(class)
  for k, v in pairs(props or {}) do o[k] = v end
  o.Parent = parent
  return o
end

-- One tag under each seat; only opponents' tags are ever shown.
local tags = {}
for seat, s in pairs(seats) do
  local tag = new('TextLabel', s.holder, { Name = 'OutOf', Text = '', TextSize = 12, Font = Enum.Font.GothamBold, TextColor3 = palette.white, BackgroundColor3 = color(200, 50, 60),
    AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 3), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X, ZIndex = 28, Visible = false })
  new('UICorner', tag, { CornerRadius = UDim.new(0, 6) })
  new('UIPadding', tag, { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) })
  tags[seat] = tag
end

local function boostSeconds()
  if not C.state then return 0 end
  local left = C.state.markersLeft or 0
  -- The time only runs down while tricks are being played.
  local current = C.state.game
  if current and not current.done and (current.phase == 'tricks' or current.phase == 'trick-review') then
    left = left - (os.clock() - (C.receivedAt or os.clock()))
  end
  return math.max(0, left)
end
local function markersOn() return C.state ~= nil and (C.state.vip == true or boostSeconds() > 0) end

local function liveRound()
  local current = C.state and C.state.game
  if markersOn() and current and not current.done and (current.phase == 'tricks' or current.phase == 'trick-review') then return current end
  return nil
end

local function tick(tile, card, height)
  -- Cards fan to the right, so the left edge is the part always visible.
  local isLowStar = card.rank == '5' and Cards.category(card, C.state.game.trump) == 'trump'
  local mark = new('TextLabel', tile, { Name = 'GambleMark', Text = '✓', TextSize = 13, Font = Enum.Font.GothamBold, TextColor3 = palette.white, BackgroundColor3 = GREEN,
    Position = UDim2.fromOffset(4, math.floor(height * (isLowStar and 0.5 or 0.74))), Size = UDim2.fromOffset(18, 18), ZIndex = (tile.ZIndex or 1) + 2 })
  new('UICorner', mark, { CornerRadius = UDim.new(1, 0) })
end

local function apply()
  local current = liveRound()
  local analysis = current and Tracker.analyze(current)
  for seat, tag in pairs(tags) do
    local out = {}
    if analysis and seat % 2 == 0 and seat <= current.playerCount then
      for _, category in ipairs(analysis.categories) do
        if analysis.voids[seat][category] then table.insert(out, category == 'trump' and 'TRUMP' or symbols[category]) end
      end
    end
    tag.Visible = #out > 0
    if #out > 0 then tag.Text = 'OUT  ' .. table.concat(out, ' ') end
  end
  local safe = analysis and analysis.gambleCards or {}
  local byId = {}
  for _, card in ipairs(current and current.hand or {}) do byId[card.id] = card end
  for _, tile in ipairs(handFrame:GetChildren()) do
    local id = string.match(tile.Name, '^Card_(.+)$')
    if id then
      local mark = tile:FindFirstChild('GambleMark')
      if safe[id] and not mark and byId[id] then tick(tile, byId[id], tile.AbsoluteSize.Y)
      elseif mark and not safe[id] then mark:Destroy() end
    end
  end
end

-- Countdown shown to players on a timed boost.
local pill = new('TextLabel', C.arena, { Name = 'MarkerTimer', Text = '', TextSize = 11, Font = Enum.Font.FredokaOne, TextColor3 = palette.white, BackgroundColor3 = GREEN,
  Position = UDim2.new(0, 10, 1, -32), Size = UDim2.fromOffset(128, 22), ZIndex = 25, Visible = false })
new('UICorner', pill, { CornerRadius = UDim.new(0, 7) })
local function updatePill()
  local seconds = boostSeconds()
  local isBoost = C.state ~= nil and C.state.vip ~= true and seconds > 0
  pill.Visible = isBoost and liveRound() ~= nil
  if pill.Visible then pill.Text = string.format('✓ MARKERS %d:%02d', math.floor(seconds / 60), math.floor(seconds % 60)) end
end
local wasOn = false
task.spawn(function()
  while true do
    task.wait(1)
    updatePill()
    local on = markersOn()
    if on ~= wasOn then
      wasOn = on
      apply()
    end
  end
end)

local baseRender = C.render
C.render = function(...)
  baseRender(...)
  apply()
  updatePill()
end
local baseHand = C.renderHand
C.renderHand = function(...)
  baseHand(...)
  apply()
end
end
