-- Execute the actual client with service/UI doubles. Snapshot mode supports a
-- browser rendering approximation; it is not a Roblox Studio screenshot.
local Cards = dofile('roblox/src/shared/Cards.luau')
local Catalog = dofile('roblox/src/shared/Catalog.luau')
local Layout = dofile('roblox/src/shared/TableLayout.luau')
local Structures = dofile('roblox/src/shared/Structures.luau')(Cards)
local Rules = dofile('roblox/src/shared/PlayRules.luau')(Cards, Structures)
local Scoring = dofile('roblox/src/shared/Scoring.luau')(Cards)
local Practice = dofile('roblox/src/server/Practice.luau')(Cards, Structures, Rules, Scoring)
local width, height = tonumber(arg[2]) or 1440, tonumber(arg[3]) or 900
local function signal()
  return { Connect = function(self, fn) self.handler = fn end }
end
local methods = {}
math.clamp = function(value, minimum, maximum) return math.max(minimum, math.min(maximum,value)) end
-- Value types the client constructs but the harness never inspects.
local function anyNew() return setmetatable({}, {__index=function() return 0 end}) end
NumberSequenceKeypoint = {new=function(time, value) return {Time=time, Value=value} end}
NumberSequence = {new=function(a, b)
  if type(a) == 'table' then return {Keypoints=a} end
  return {Keypoints={{Time=0, Value=a}, {Time=1, Value=b or a}}}
end}; ColorSequenceKeypoint = {new=anyNew}; NumberRange={new=anyNew}; Rect={new=anyNew}; Vector3={new=anyNew}; CFrame={new=anyNew}; Font={new=anyNew, fromName=anyNew, fromEnum=anyNew}
Vector2 = {new=function(x,y) return {X=x,Y=y} end}
TweenInfo = {new=function() return {} end}
local function dim(scale, offset) return { Scale = scale, Offset = offset } end
UDim = { new = dim }
-- UDim2 values add and subtract like Roblox's.
local udim2Meta = {}
UDim2 = { new = function(xs, xo, ys, yo) return setmetatable({ X = dim(xs or 0, xo or 0), Y = dim(ys or 0, yo or 0) }, udim2Meta) end }
udim2Meta.__add = function(a, b) return UDim2.new(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset) end
udim2Meta.__sub = function(a, b) return UDim2.new(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset) end
UDim2.fromOffset = function(x, y) return UDim2.new(0, x, 0, y) end
UDim2.fromScale = function(x, y) return UDim2.new(x, 0, y, 0) end
-- Like Roblox: R/G/B in 0–1; r/g/b (0–255) feed the preview renderer.
Color3 = {
  fromRGB = function(r, g, b) return { r = r, g = g, b = b, R = r / 255, G = g / 255, B = b / 255 } end,
  new = function(R, G, B) return { r = R * 255, g = G * 255, b = B * 255, R = R, G = G, B = B } end,
}
ColorSequence = { new = function(a, b) return { first = a, last = b } end }
Enum = setmetatable({}, { __index = function(_, category)
  return setmetatable({}, { __index = function(_, value) return category .. '.' .. value end })
end })
Instance = { new = function(class)
  return setmetatable({ props = { ClassName = class, Visible = true, BackgroundTransparency = 0, ZIndex = 1, Rotation = 0, ImageTransparency = 0, TextTransparency = 0, Transparency = 0 }, children = {}, signals = {} }, {
    __index = function(self, key)
      if methods[key] then return methods[key] end
      if key == 'AbsoluteSize' then
        local parent = self.props.Parent
        local size = parent and parent.AbsoluteSize or { X = width, Y = height }
        local configured = self.props.Size
        if not configured then return size end
        return { X = size.X * configured.X.Scale + configured.X.Offset, Y = size.Y * configured.Y.Scale + configured.Y.Offset }
      end
      local events={ChildAdded=1,DescendantAdded=1,DescendantRemoving=1,ChildRemoved=1,MouseEnter=1,MouseLeave=1,InputBegan=1,InputEnded=1,InputChanged=1,Heartbeat=1,RenderStepped=1,Stepped=1,MouseButton1Down=1,MouseButton1Up=1,MouseButton1Click=1,FocusLost=1,Focused=1,Changed=1,Ended=1,Completed=1,MouseMoved=1,TouchTap=1,AncestryChanged=1}
      if events[key] and self.props[key]==nil then
        if not self.signals[key] then self.signals[key] = signal() end
        return self.signals[key]
      end
      if key == 'Activated' then
        if not self.signals.Activated then self.signals.Activated = signal() end
        return self.signals.Activated
      end
      if self.props[key] ~= nil then return self.props[key] end
      for _,child in ipairs(self.children) do if child.Name==key then return child end end
      return nil
    end,
    __newindex = function(self, key, value)
      if key == 'Parent' and self.props.Parent then
        for i, child in ipairs(self.props.Parent.children) do if child==self then table.remove(self.props.Parent.children,i);break end end
      end
      self.props[key] = value
      if key == 'Parent' and value then table.insert(value.children, self) end
    end,
  })
end }
function methods:GetChildren() local result = {}; for _, child in ipairs(self.children) do table.insert(result, child) end; return result end
function methods:Destroy()
  if self.Parent then for i, child in ipairs(self.Parent.children) do if child == self then table.remove(self.Parent.children, i); break end end end
end
function methods:GetPropertyChangedSignal(name)
  if not self.signals[name] then self.signals[name] = signal() end
  return self.signals[name]
end

-- Methods on sounds, tweens and text boxes that have no observable effect here.
for _,m in ipairs({'Play','Stop','Pause','Resume','Disconnect','TweenPosition','TweenSize','CaptureFocus','ReleaseFocus'}) do methods[m]=function() return {Play=function() end, Completed={Connect=function() end}} end end
function methods:FindFirstChild(name) for _,c in ipairs(self.children) do if c.Name==name then return c end end end
function methods:FindFirstChildOfClass(cls) for _,c in ipairs(self.children) do if c.ClassName==cls then return c end end end
function methods:IsA() return false end
function methods:ClearAllChildren() self.children={} end
function methods:WaitForChild(name) return self:FindFirstChild(name) end
function methods:Clone()
  local copy = Instance.new(self.ClassName)
  for key, value in pairs(self.props) do if key ~= 'Parent' then copy[key] = value end end
  for _, child in ipairs(self.children) do child:Clone().Parent = copy end
  return copy
end
function methods:FindFirstAncestorOfClass() return nil end
function methods:GetDescendants()
  local result = {}
  local function walk(node) for _, child in ipairs(node.children) do table.insert(result, child); walk(child) end end
  walk(self)
  return result
end
local playerGui = Instance.new('PlayerGui')
local sent = {}
local remote = { OnClientEvent = signal(), FireServer = function(_, ...) table.insert(sent, {...}) end }
local shared = { Cards = Cards, Catalog = Catalog, TableLayout = Layout, Structures = dofile('roblox/src/shared/Structures.luau'), PlayRules = dofile('roblox/src/shared/PlayRules.luau'), Scoring = dofile('roblox/src/shared/Scoring.luau'), Tracker = dofile('roblox/src/shared/Tracker.luau') }
-- Shared modules by name; anything else (the Action remote) is the remote.
shared.WaitForChild = function(_, name) return rawget(shared, name) or remote end
local storage = { WaitForChild = function() return shared end }
local players = { LocalPlayer = { UserId = 7, DisplayName = 'Tester', WaitForChild = function() return playerGui end } }
local services = {}
game = { GetService = function(_, name)
  if name == 'Players' then return players end
  if name == 'ReplicatedStorage' then return storage end
  services[name] = services[name] or Instance.new(name)
  return services[name]
end }
-- Tweens jump straight to their end values so snapshots show final layouts.
function methods:Create(object, _, props)
  for key, value in pairs(props or {}) do object[key] = value end
  return {Play=function() end, Cancel=function() end, Completed={Connect=function() end}}
end
function methods:GetFocusedTextBox() return nil end
-- TextService: a rough width estimate is enough for layout code.
function methods:GetTextSize(text, size) return { X = #tostring(text) * (size or 14) * 0.55, Y = size or 14 } end
require = function(module) return module end
workspace = { CurrentCamera = { ViewportSize = { X = width, Y = height } } }
-- Client ModuleScripts are siblings of the LocalScript.
-- The client is a folder of UI modules loaded in order by Main.client.luau.
script = { Parent = { WaitForChild = function(_, name)
  if name == 'UI' then
    return { WaitForChild = function(_, module) return dofile('roblox/src/client/UI/' .. module .. '.luau') end }
  end
  return dofile('roblox/src/client/' .. name .. '.luau')
end } }
-- Delayed callbacks queue until a test calls flushDelays(); the clock can be
-- advanced to skip cooldowns.
local pendingDelays = {}
local function flushDelays()
  local list = pendingDelays
  pendingDelays = {}
  for _, fn in ipairs(list) do fn() end
end
local realClock, clockOffset = os.clock, 0
os.clock = function() return realClock() + clockOffset end
task = { delay = function(_, fn, ...)
  local args = table.pack(...)
  if type(fn) == 'function' then table.insert(pendingDelays, function() fn(table.unpack(args, 1, args.n)) end) end
end, spawn = function() end, defer = function() end, wait = function() return 0 end, cancel = function() end }
local function find(parent, name)
  if parent.Name == name then return parent end
  for _, child in ipairs(parent.children) do local result = find(child, name); if result then return result end end
end
local scope -- When set, click() searches only inside this instance.
local mouse = { UserInputType = Enum.UserInputType.MouseButton1 }
local function click(name)
  local item = assert(find(scope or playerGui, name), name)
  assert(item.Visible, name .. ' hidden')
  if item.signals.InputBegan and item.signals.InputBegan.handler then
    -- Hand cards select on press (supporting drag-select) and finish on release.
    item.signals.InputBegan.handler(mouse)
    local input = services.UserInputService
    if input and input.signals.InputEnded and input.signals.InputEnded.handler then input.signals.InputEnded.handler(mouse) end
  else
    item.Activated.handler()
  end
end
local function receive(gameState)
  remote.OnClientEvent.handler({ game = gameState and Practice.view(gameState), coins = 40, owned = { wave = true, cheer = true }, serverTime = 0 })
end
dofile('roblox/src/client/Main.client.luau')
assert(sent[1][1] == 'sync')
assert(find(playerGui, 'TractorBackdrop').ScreenInsets == Enum.ScreenInsets.None)
assert(find(playerGui, 'Backdrop').Size.X.Scale == 1 and find(playerGui, 'Backdrop').Size.Y.Scale == 1)
assert(find(playerGui, 'TractorTable').ScreenInsets == Enum.ScreenInsets.CoreUISafeInsets)
receive(nil)
-- Home screen: Classic opens the table picker in Money mode; in Rank mode it queues Ranked.
scope = find(playerGui, 'Mode1'); click('Action'); scope = nil
assert(find(playerGui, 'TierScreen').Visible and not find(playerGui, 'HomeScreen').Visible, 'Money mode opens the table picker')
click('BackBtn')
assert(find(playerGui, 'HomeScreen').Visible)
click('RankToggle')
scope = find(playerGui, 'Mode2'); click('Action'); scope = nil
assert(sent[#sent][1] == 'queue' and sent[#sent][2].ranked == true and sent[#sent][2].playerCount == 8, 'Rank mode queues Ranked at that size')
click('MoneyToggle')
-- The Friends page holds squads and private tables.
click('FriendsBtn')
assert(find(playerGui, 'FriendsScreen').Visible and find(playerGui, 'CreatePrivate').Visible)
scope = find(playerGui, 'FriendsScreen'); click('BackBtn'); scope = nil
assert(find(playerGui, 'HomeScreen').Visible)
local state = Practice.new(function(n) return n end, 0)
receive(state)
assert(find(playerGui, 'Declarations').Visible and not find(playerGui, 'Primary').Visible)
-- Declarations are grouped by suit; tapping a suit sends its smallest legal reveal.
click('DeclareSuit' .. Practice.options(state, 1)[1].suit)
assert(sent[#sent][1] == 'declare' and sent[#sent][2] == 1 and sent[#sent][3] == 0)
assert(Practice.declare(state, 1, 1, 1))
assert(Practice.advance(state, 9, function() return 1 end))
receive(state)
local function handCount()
  local count = 0
  for _, child in ipairs(find(playerGui, 'Hand'):GetChildren()) do
    if string.sub(child.Name, 1, 5) == 'Card_' then count = count + 1 end
  end
  return count
end
assert(handCount() == 33)
local buried = {}
for i = 1, 8 do buried[i] = state.hands[1][i].id; click('Card_' .. buried[i]) end
assert(find(playerGui, 'Primary').Text == 'BURY 8 CARDS')
local before = #sent
click('Card_' .. state.hands[1][9].id)
assert(#sent == before and find(playerGui, 'Primary').Text == 'BURY 8 CARDS')
click('Primary')
assert(sent[#sent][1] == 'bury' and #sent[#sent][2] == 8)
assert(Practice.bury(state, 1, buried))
-- Burial opens Chao Di; the challenge passes around before trick play.
local chaodiSteps = 0
while state.phase == 'chaodi' do
  chaodiSteps = chaodiSteps + 1; assert(chaodiSteps < 100)
  if state.chaodiTurn == 1 then
    receive(state)
    click('Clear')
    assert(sent[#sent][1] == 'chaodi_pass', 'Clear passes during your Chao Di turn')
    assert(Practice.chaodiPass(state, 1, 0))
  else
    assert(Practice.stepChaodiBot(state, 0))
  end
end
receive(state)
assert(state.phase == 'tricks' and state.turn == 1)
local id = state.hands[1][1].id
assert(find(playerGui, 'Primary').Text ~= 'LEAD 0 CARDS', 'Your turn starts with a suggested play selected')
click('Clear')
before = #sent
click('Card_' .. id)
assert(#sent == before and find(playerGui, 'Primary').Text == 'LEAD 1 CARD')
local second = state.hands[1][2].id
click('Card_' .. second)
assert(find(playerGui,'Primary').Text ~= 'LEAD 1 CARD', 'Second card joins the selection')
click('Card_' .. second)
assert(find(playerGui,'Primary').Text == 'LEAD 1 CARD', 'Tapping again deselects')
click('Primary')
assert(sent[#sent][1] == 'play' and sent[#sent][2][1] == id)
assert(Practice.play(state, 1, {id})); Practice.bots(state)
receive(state)
click('History')
assert(find(playerGui, 'HistoryShade').Visible)
click('CloseHistory')
click('AutoPlay')
assert(find(playerGui,'AutoPlay').Text=='AUTO ON')
click('AutoPlay')
click('ShopToggle')
assert(find(playerGui, 'ModalShade').Visible)
click('Emote_laugh')
assert(sent[#sent][1] == 'buy' and sent[#sent][2] == 'laugh')
click('Emote_wave')
assert(sent[#sent][1] == 'emote')
remote.OnClientEvent.handler({ emote = 'Hello!', sender = 'Partner' })
assert(find(playerGui, 'EmoteToast').Text ~= '')
click('Mute')
assert(find(playerGui, 'EmoteToast').Text == '')
remote.OnClientEvent.handler({ emote = 'Hello!', sender = 'Partner' })
assert(find(playerGui, 'EmoteToast').Text == '')
scope = find(playerGui, 'ModalShade')
click('Close')
scope = nil
assert(not find(playerGui, 'ModalShade').Visible)
-- Submit a real pair through the actual UI callback, then resolve the whole trick.
local pairState=Practice.new(function(n)return n end,0)
pairState.phase,pairState.dealer,pairState.trump='tricks',1,{level='2',suit='spades'}
for seat=1,4 do
  pairState.hands[seat]={}
  for copy=1,2 do pairState.hands[seat][copy]={id='pair:'..seat..':'..copy,rank=tostring(seat+2),suit='clubs'} end
end
receive(pairState)
click('Clear')
click('Card_'..pairState.hands[1][1].id)
click('Card_'..pairState.hands[1][2].id)
assert(find(playerGui,'Primary').Text=='LEAD 2 CARDS')
assert(find(playerGui,'HandHint').Text=='pair')
click('Primary')
assert(#sent[#sent][2]==2)
assert(Practice.play(pairState,1,sent[#sent][2]))
Practice.bots(pairState)
assert(pairState.done and #pairState.lastTrick[1].cards==2)
receive(pairState)
assert(find(playerGui,'Play1') and find(playerGui,'Played_pair:1:1') and find(playerGui,'Played_pair:1:2'))
assert(find(playerGui,'SettlementModal').Visible)
receive(state)
-- A round with one completed trick and `played` cards of the next trick down.
local function trickInProgress(count, played)
  local seed = 23.0
  local function pick(n) seed = (seed * 48271) % 2147483647; return seed % n + 1 end
  local game = Practice.new(pick, 0, { playerCount = count, paced = true })
  assert(Practice.advance(game, 8, function() return 1 end)); assert(Practice.advance(game, 16, function() return 1 end))
  if game.phase == 'kitty' then
    local ids = {}; for i = 1, game.kittySize do ids[i] = game.hands[game.dealer][i].id end
    assert(Practice.bury(game, game.dealer, ids))
  end
  while game.phase == 'chaodi' do
    if game.chaodiTurn == 1 then assert(Practice.chaodiPass(game, 1, 0)) else assert(Practice.stepChaodiBot(game, 0)) end
  end
  local function playOne()
    local seat = game.turn
    local chosen = Rules.choose(game.hands[seat], game.trick[1] and game.trick[1].components, game.trump)
    local ids = {}; for _, c in ipairs(chosen) do table.insert(ids, c.id) end
    assert(Practice.play(game, seat, ids))
  end
  for _ = 1, count do playOne() end
  if game.phase == 'trick-review' then assert(Practice.nextTrick(game)) end
  for _ = 1, played do playOne() end
  return game
end

-- Match length: the table screen toggles Quick Match / Full Match and the
-- queue request carries the choice.
remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0 })
assert(find(playerGui, 'MatchLength').Text == 'QUICK · 1 ROUND')
click('MatchLength')
assert(find(playerGui, 'MatchLength').Text == 'FULL MATCH · TO ACE')
scope = find(playerGui, 'CardNovice')
click('JoinBtn')
scope = nil
assert(sent[#sent][1] == 'queue' and sent[#sent][2].tier == 'novice' and sent[#sent][2].fullMatch == true)
click('MatchLength')
assert(find(playerGui, 'MatchLength').Text == 'QUICK · 1 ROUND')

-- An undecided full-match round offers the next round on the result screen.
local roundOne = trickInProgress(4, 0)
assert(roundOne.quickMatch == false)
while not roundOne.done do
  if roundOne.phase == 'trick-review' then assert(Practice.nextTrick(roundOne)) end
  local seat = roundOne.turn
  local chosen = Rules.choose(roundOne.hands[seat], roundOne.trick[1] and roundOne.trick[1].components, roundOne.trump)
  local ids = {}; for _, c in ipairs(chosen) do table.insert(ids, c.id) end
  assert(Practice.play(roundOne, seat, ids))
end
assert(roundOne.settlement and not roundOne.settlement.winner)
receive(roundOne)
assert(find(playerGui, 'SettlementModal').Visible)
assert(find(playerGui, 'PlayAgain').Text == '▶ NEXT ROUND (2)')

-- Past the overturn line the meter shows the payout step and the next line.
local scored = trickInProgress(4, 1)
scored.points[scored.attackingTeam == 'A' and 2 or 1] = 165
receive(scored)
assert(find(playerGui, 'PointsBox').Status.Text == 'OVERTURN ×3 · NEXT AT 200', find(playerGui, 'PointsBox').Status.Text)

-- When saving is off the player is told why, once, and the balance says so.
remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0, saving = { enabled = false, reason = 'Studio API access is off.' } })
assert(find(playerGui, 'SaveWarningShade').Visible)
assert(find(playerGui, 'SaveWarning').Reason.Text:find('Studio API access is off.', 1, true))
assert(find(playerGui, 'WalletHint').Text == '⚠ NOT SAVING')
assert(find(playerGui, 'SaveChip').Text:find('⚠', 1, true), 'The lobby shows saving is off too')
click('SaveWarningOk')
assert(not find(playerGui, 'SaveWarningShade').Visible)
remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0, saving = { enabled = false, reason = 'Studio API access is off.' } })
assert(not find(playerGui, 'SaveWarningShade').Visible, 'The warning pops up only once per session')
remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0, saving = { enabled = true } })
assert(find(playerGui, 'WalletHint').Text == '' and not find(playerGui, 'SaveChip').Visible, 'Nothing is shown while saving works')

-- The stake pill shows the Chao Di multiplier; a raise announces itself.
local staked = trickInProgress(4, 1)
receive(staked)
local before = staked.chaodiMultiplier or 1
assert(find(playerGui, 'StakePill').Val.Text == '×' .. before)
staked.chaodiMultiplier = before * 2
staked.revision = staked.revision + 1
receive(staked)
assert(find(playerGui, 'StakePill').Val.Text == '×' .. before * 2)
assert(find(playerGui, 'TractorBanner').Visible and find(playerGui, 'TractorBanner').Text.Text == 'CHAO DI!  STAKES ×' .. before * 2)

-- Every play is labelled with its owner; the current winner is marked.
local live = trickInProgress(4, 3)
receive(live)
for _, play in ipairs(live.trick) do
  local tag = assert(find(playerGui, 'PlayTag' .. play.seat), 'Play ' .. play.seat .. ' has a name tag')
  if play.seat == live.winnerSeat then assert(tag.Text:find('WINNING'), 'Winner tag says WINNING') end
end
assert(find(playerGui, 'TrickLabel').Text:find('CURRENT TRICK'))
-- Peek at the previous trick and come back.
assert(find(playerGui, 'PeekLastTrick').Visible)
click('PeekLastTrick')
assert(find(playerGui, 'TrickLabel').Text:find('PREVIOUS TRICK'))
for _, play in ipairs(live.lastTrick) do
  assert(find(playerGui, 'Played_' .. play.cards[1].id), 'Peek shows the previous trick')
end
click('PeekLastTrick')
assert(find(playerGui, 'TrickLabel').Text:find('CURRENT TRICK'))
-- Completing a trick with points pops them over the winner.
while live.phase == 'tricks' and #live.trick > 0 do
  local seat = live.turn
  local chosen = Rules.choose(live.hands[seat], live.trick[1].components, live.trump)
  local ids = {}; for _, c in ipairs(chosen) do table.insert(ids, c.id) end
  assert(Practice.play(live, seat, ids))
end
local points = 0
for _, play in ipairs(live.lastTrick) do for _, c in ipairs(play.cards) do points = points + Cards.points(c) end end
-- Earlier pop-ups linger because the harness never runs task.delay cleanups.
while find(playerGui, 'PointsPopup') do find(playerGui, 'PointsPopup'):Destroy() end
receive(live)
local popup = find(playerGui, 'PointsPopup')
local defenders = Cards.team(live.lastWinnerSeat) ~= live.attackingTeam
if points > 0 then
  assert(popup and popup.Text == (defenders and ('+' .. points .. ' PTS') or (points .. ' PTS SAVED')), 'Points pop up when a scoring trick completes')
else
  assert(not popup, 'No points pop-up for a pointless trick')
end
receive(state)
-- Reactions: locked ones offer to unlock, owned ones fly from seat to seat,
-- a cooldown applies, bots may answer, and our own server echo is skipped.
local function countNamed(name)
  local n = 0
  local function walk(object) if object.Name == name then n = n + 1 end; for _, child in ipairs(object.children) do walk(child) end end
  walk(playerGui)
  return n
end
local function clearFx() for _, child in ipairs(find(playerGui, 'FxLayer'):GetChildren()) do child:Destroy() end end
local realRandom = math.random
if find(playerGui, 'Mute').Text:find('on') then click('Mute') end -- the shop test muted reactions
pendingDelays = {}
clockOffset = clockOffset + 5
local reactGame = trickInProgress(4, 1)
receive(reactGame) -- owns wave and cheer only, 40 coins
clearFx()
assert(find(playerGui, 'Throw_laugh').Lock.Visible and not find(playerGui, 'Throw_cheer').Lock.Visible)
before = #sent
click('Throw_laugh')
assert(#sent == before and find(playerGui, 'Notice').Text:find('unlocks for 600', 1, true), 'Locked reaction explains the price')
math.random = function() return 0.1 end -- the targeted bot will answer
click('Throw_cheer')
assert(sent[#sent][1] == 'emote' and sent[#sent][2].id == 'cheer' and sent[#sent][2].target == 'auto')
assert(countNamed('Projectile') == 1, 'Reaction flies immediately')
assert(find(playerGui, 'SelfChatBubble').Text.Text == 'GG! Well played!')
before = #sent
click('Throw_wave')
assert(#sent == before, 'Cooldown blocks a second reaction')
flushDelays() -- our trophy lands (and lingers briefly) while the partner replies
math.random = realRandom
assert(find(find(playerGui, 'Seat3'), 'ChatBubble').Text.Text == 'GG! Well played!', 'Partner cheers back')
assert(countNamed('Projectile') == 2, 'Reply flies back')
for _ = 1, 10 do flushDelays() end
assert(countNamed('Projectile') == 0 and countNamed('Confetti') == 0, 'Every effect cleans itself up')
-- Our own echo from the server is not replayed; others' reactions are.
clearFx(); pendingDelays = {}
remote.OnClientEvent.handler({ type = 'emote', kind = 'emote', id = 'bomb', sender = 'Tester', senderId = 7, target = 'auto' })
assert(countNamed('Projectile') == 0, 'Own echo skipped')
remote.OnClientEvent.handler({ type = 'emote', kind = 'emote', id = 'bomb', sender = find(find(playerGui, 'Seat2'), 'Name').Text, senderId = 99, target = 'seat1' })
assert(countNamed('Projectile') == 1 and find(find(playerGui, 'Seat2'), 'ChatBubble').Text.Text == 'Boom for you!')
-- Every reaction's flight and landing runs and cleans up after itself.
local allOwned = {}
for _, item in ipairs(Catalog) do if item.category == 'emote' then allOwned[item.id] = true end end
remote.OnClientEvent.handler({ game = Practice.view(reactGame), coins = 3000, owned = allOwned, serverTime = 0 })
for _, id in ipairs({ 'wave', 'cheer', 'laugh', 'wow', 'flower', 'tomato', 'bomb', 'coffee', 'tractor_rush' }) do
  clockOffset = clockOffset + 5
  click('TableChat')
  click('Throw_' .. id)
  assert(sent[#sent][2].id == id and countNamed('Projectile') >= 1, id .. ' launches')
  for _ = 1, 12 do flushDelays() end
  for _, leftover in ipairs({ 'Projectile', 'GroundShadow', 'Trail', 'Spark', 'Ring', 'Pop', 'Word', 'Petal', 'Stain', 'Drop', 'Smoke', 'Ember',
    'Flash', 'Confetti', 'Steam', 'SpeedLine', 'Dust', 'HitGlow', 'HitSplat', 'HitDrip', 'HitSoot', 'HitPuff', 'HitHeart', 'HitSparkle', 'HitSteam', 'HitTrack' }) do
    assert(countNamed(leftover) == 0, id .. ' left a ' .. leftover .. ' behind')
  end
end
assert(find(find(playerGui, 'Seat2'), 'Name') and find(playerGui, 'Seat2').Rotation == 0, 'Hit wobble settles')

-- Ten players: targets switch to team-wide, and Opponents hits all five.
clearFx(); pendingDelays = {}
clockOffset = clockOffset + 5
receive(trickInProgress(10, 1))
assert(find(playerGui, 'Tgt_team') and not find(playerGui, 'Tgt_seat2'), 'Big tables aim by team')
click('Tgt_opponents')
math.random = function() return 0.9 end -- no reply
click('Throw_cheer')
math.random = realRandom
assert(countNamed('Projectile') == 1)
flushDelays() -- the other four launch while the first lands
assert(countNamed('Projectile') == 5, 'Opponents target hits every opponent')
click('Tgt_auto')
clearFx(); pendingDelays = {}
receive(state)

-- Stats: the home STATS button shows lifetime figures from the server.
remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0,
  stats = { roundsPlayed = 8, roundsWon = 6, matchesWon = 1, shutouts = 2, bestGrade = 12, biggestWin = 15400, coinsEarned = 48250 } })
assert(find(playerGui, 'HistoryBtn').Text == 'STATS')
click('HistoryBtn')
assert(find(playerGui, 'StatsShade').Visible)
assert(find(playerGui, 'Stat_winRate').Value.Text == '6 · 75%')
assert(find(playerGui, 'Stat_bestGrade').Value.Text == '×12' and find(playerGui, 'Stat_biggestWin').Value.Text == '15.4K')
assert(find(playerGui, 'Stat_overturns').Value.Text == '0')
click('CloseStats')
assert(not find(playerGui, 'StatsShade').Visible)
receive(state)

-- Multiplayer: waiting room, real names on seats, reactions from a friend.
local function seatsFor(names, humans)
  local list = {}
  for seat, name in ipairs(names) do list[seat] = { name = name, userId = seat, human = humans[seat] == true, host = seat == 1 } end
  return list
end
local waitingTable = { id = 1, code = 'AB2C', private = true, isHost = true, playerCount = 4, tier = 'novice', fullMatch = false,
  status = 'waiting', humans = 2, seats = seatsFor({ 'Tester', 'Shedletsky', 'Ben', 'Roblox' }, { true, false, true, false }) }
remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0, table = waitingTable })
assert(find(playerGui, 'QueueShade').Visible, 'Seated players see the waiting room')
assert(find(playerGui, 'QueueModal').Banner.Text.Text == 'PRIVATE TABLE · AB2C')
assert(find(playerGui, 'QueueModal').Status.Text:find('Share code AB2C', 1, true) and find(playerGui, 'StartNow').Visible)
assert(find(playerGui, 'VsBox').Summary.Text:find('You  ·  Ben', 1, true), 'Ben is on your team')
waitingTable.isHost = false
remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0, table = waitingTable })
assert(not find(playerGui, 'StartNow').Visible and find(playerGui, 'QueueModal').Status.Text:find('host'), 'Guests wait for the host')
local shared4 = trickInProgress(4, 0)
local playing = { id = 1, code = 'AB2C', private = true, isHost = false, playerCount = 4, tier = 'novice', status = 'playing', humans = 2,
  seats = seatsFor({ 'Tester', 'Shedletsky', 'Ben', 'Roblox' }, { true, false, true, false }) }
remote.OnClientEvent.handler({ game = Practice.view(shared4), coins = 3000, owned = { wave = true }, serverTime = 0, table = playing })
assert(not find(playerGui, 'QueueShade').Visible, 'The waiting room closes when cards are dealt')
assert(find(find(playerGui, 'Seat3'), 'Name').Text == 'Ben', 'Seats show real player names')
assert(find(find(playerGui, 'Seat2'), 'Name').Text == 'Shedletsky')
clearFx(); pendingDelays = {}
remote.OnClientEvent.handler({ type = 'emote', kind = 'emote', id = 'flower', sender = 'Ben', senderId = 102, fromSeat = 3, target = 'seat1' })
assert(countNamed('Projectile') == 1 and find(find(playerGui, 'Seat3'), 'ChatBubble').Text.Text == 'A rose for you!', "Ben's reaction comes from his seat")
for _ = 1, 12 do flushDelays() end
-- Private tables from the table screen.
click('CreatePrivate')
assert(find(playerGui, 'PrivatePicker').Visible, 'Create Private asks for the table size')
click('Private6')
assert(sent[#sent][1] == 'create_private' and sent[#sent][2].playerCount == 6 and sent[#sent][2].tier == 'novice')
assert(not find(playerGui, 'PrivatePicker').Visible)
assert(find(playerGui, 'CreatePrivate').Parent.Name == 'BottomBar', 'Private tables are created from the lobby')
find(playerGui, 'CodeBox').Text = 'ab'
before = #sent
click('JoinCode')
assert(#sent == before, 'Short codes are not sent')
find(playerGui, 'CodeBox').Text = 'ab2c'
click('JoinCode')
assert(sent[#sent][1] == 'join_code' and sent[#sent][2] == 'AB2C')
receive(state)

-- Squad lobby: members, leader controls, invites, and the search bar.
local squadBase = { coins = 3000, owned = { wave = true }, serverTime = 0,
  lobby = { { name = 'Cai', userId = 103, inSquad = false }, { name = 'Ben', userId = 102, inSquad = true } } }
local function withSquad(extra)
  local payload = {}
  for k, v in pairs(squadBase) do payload[k] = v end
  for k, v in pairs(extra) do payload[k] = v end
  remote.OnClientEvent.handler(payload)
end
withSquad({ squad = { id = 1, isLeader = true, public = true, members = { { name = 'Tester', userId = 7, leader = true }, { name = 'Ben', userId = 102 } } },
  openSquads = { { leaderId = 104, leaderName = 'Dev', size = 2 } } })
assert(find(playerGui, 'Member_7') and find(playerGui, 'Member_102'), 'Squad members are listed')
assert(find(find(playerGui, 'Member_7'), 'Name').Text == '👑 Tester (you)', 'The leader has a crown')
assert(find(playerGui, 'SquadPrivacy').Text == '🌐 PUBLIC' and find(playerGui, 'SquadLeave').Visible)
assert(find(playerGui, 'HeroAction').Text == 'PLAY ▶')
click('Kick_102')
assert(sent[#sent][1] == 'squad_kick' and sent[#sent][2] == 102, 'The leader can remove a member')
click('SquadPrivacy')
assert(sent[#sent][1] == 'squad_privacy' and sent[#sent][2] == false, 'The leader makes the squad private')
click('SquadInvite')
assert(find(playerGui, 'InviteShade').Visible and find(playerGui, 'Row_103') and find(playerGui, 'Invite_102').Text == 'IN SQUAD')
click('Invite_103')
assert(sent[#sent][1] == 'squad_invite' and sent[#sent][2] == 103)
assert(find(playerGui, 'Row_104') and find(playerGui, 'Invite_104').Text == 'JOIN', 'Public squads are listed to join')
click('Invite_104')
assert(sent[#sent][1] == 'squad_join' and sent[#sent][2] == 104)
click('SquadInvite')
click('CloseInvites')
withSquad({ squad = { id = 1, isLeader = false, public = true, members = { { name = 'Ana', userId = 101, leader = true }, { name = 'Tester', userId = 7 } } } })
assert(find(playerGui, 'HeroAction').Text == 'LEADER PICKS MODE' and not find(playerGui, 'Kick_101'), 'Members cannot kick or pick the mode')
before = #sent
click('HeroAction')
assert(#sent == before and find(playerGui, 'Notice').Text:find('leader'))
withSquad({ squad = { solo = true, isLeader = true, public = true, members = { { name = 'Tester', userId = 7, leader = true } } },
  invites = { { fromId = 101, fromName = 'Ana' } } })
assert(find(playerGui, 'InvitePopup').Visible and find(playerGui, 'InvitePopup').Text.Text:find('Ana invited you'), 'Invites pop up')
assert(not find(playerGui, 'SquadLeave').Visible, 'Solo players have nothing to leave')
click('AcceptInvite')
assert(sent[#sent][1] == 'squad_accept' and sent[#sent][2] == 101)
withSquad({ squad = { solo = true, isLeader = true, public = true, members = { { name = 'Tester', userId = 7, leader = true } } },
  search = { ticketId = 'x', startedAt = 0, playerCount = 4, tier = 'novice', squadSize = 2 } })
local searchText = find(playerGui, 'SearchBar').Text.Text
assert(find(playerGui, 'SearchBar').Visible and searchText:find('4P NOVICE', 1, true) and searchText:find('SQUAD', 1, true), 'The search bar shows mode and squad size')
click('CancelSearch')
assert(sent[#sent][1] == 'cancel_queue')
withSquad({ squad = { solo = true, isLeader = true, public = true, members = { { name = 'Tester', userId = 7, leader = true } } } })
assert(not find(playerGui, 'SearchBar').Visible and not find(playerGui, 'InvitePopup').Visible)
receive(state)

-- Claiming coins updates every balance display, including the lobby's.
remote.OnClientEvent.handler({ coins = 4200, owned = { wave = true }, serverTime = 0, coinBonus = 1000 })
assert(find(find(playerGui, 'HomeScreen'), 'CoinPill').Text.Text == '4.2K', 'The lobby coin pill shows the new balance')
assert(find(find(playerGui, 'TierScreen'), 'CoinPill').Text.Text == '4.2K', 'So does the table screen')
receive(state)

-- Viewport changes exercise the same resize handler used in Studio.
find(playerGui, 'TableRoot'):GetPropertyChangedSignal('AbsoluteSize').handler()
if arg[1] == 'snapshot' then
  if arg[4] == 'home' then
    receive(nil)
  elseif arg[4] == 'kitty' then
    state = Practice.new(function(n) return n end, 0)
    assert(Practice.declare(state, 1, 1, 1)); assert(Practice.advance(state, 9, function() return 1 end))
    receive(state)
    for i = 1, 4 do click('Card_' .. state.hands[1][i].id) end
  elseif arg[4] == 'tier' then
    remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0 })
    click('HeroAction')
    click('MatchLength')
  elseif arg[4] == 'chat' then
    state = trickInProgress(4, 1)
    remote.OnClientEvent.handler({ game = Practice.view(state), coins = 3000, serverTime = 0, saving = { enabled = true },
      owned = { wave = true, cheer = true, flower = true, tomato = true, bomb = true, coffee = true, tractor_rush = true } })
    click('TableChat')
  elseif arg[4] == 'stats' then
    remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0,
      stats = { roundsPlayed = 8, roundsWon = 6, matchesWon = 1, shutouts = 2, overturns = 1, chaodis = 3, bestGrade = 12, biggestWin = 15400, coinsEarned = 48250 } })
    click('HistoryBtn')
  elseif arg[4] == 'waiting' then
    local seatsInfo = {}
    for seat, name in ipairs({ 'Tester', 'Shedletsky', 'Ben', 'Roblox' }) do seatsInfo[seat] = { name = name, userId = seat, human = seat == 1 or seat == 3, host = seat == 1 } end
    remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0,
      table = { id = 1, code = 'AB2C', private = true, isHost = true, playerCount = 4, tier = 'novice', status = 'waiting', humans = 2, seats = seatsInfo } })
  elseif arg[4] == 'squad' then
    remote.OnClientEvent.handler({ coins = 3000, owned = { wave = true }, serverTime = 0,
      squad = { id = 1, isLeader = true, public = true, members = { { name = 'Tester', userId = 7, leader = true }, { name = 'Ben', userId = 102 }, { name = 'Cai', userId = 103 } } },
      search = { ticketId = 'x', startedAt = -42, playerCount = 6, tier = 'novice', squadSize = 3 },
      invites = { { fromId = 104, fromName = 'Dev' } } })
  elseif arg[4] == 'settle' then
    local finished = trickInProgress(4, 0)
    while not finished.done do
      if finished.phase == 'trick-review' then assert(Practice.nextTrick(finished)) end
      local seat = finished.turn
      local chosen = Rules.choose(finished.hands[seat], finished.trick[1] and finished.trick[1].components, finished.trump)
      local ids = {}; for _, c in ipairs(chosen) do table.insert(ids, c.id) end
      assert(Practice.play(finished, seat, ids))
    end
    local view = Practice.view(finished)
    for key, value in pairs({ netCoins = 1400, baseStake = 500, totalMultiplier = 4, gradeName = '小光 (Near Shutout)', kittyFactor = 1, chaodiFactor = 2, trickCoins = 650, tax = 100 }) do view.settlement[key] = value end
    remote.OnClientEvent.handler({ game = view, coins = 4400, owned = { wave = true }, serverTime = 0 })
  elseif string.sub(arg[4] or '', 1, 6) == 'flight' or string.sub(arg[4] or '', 1, 6) == 'impact' then
    -- Freeze-frame: tweens stop 55% of the way, so a capture shows motion.
    local function lerp(from, to, f)
      if type(from) == 'number' and type(to) == 'number' then return from + (to - from) * f end
      if type(from) == 'table' and type(to) == 'table' and from.X and to.X and from.X.Offset then
        return UDim2.new(from.X.Scale + (to.X.Scale - from.X.Scale) * f, from.X.Offset + (to.X.Offset - from.X.Offset) * f,
          from.Y.Scale + (to.Y.Scale - from.Y.Scale) * f, from.Y.Offset + (to.Y.Offset - from.Y.Offset) * f)
      end
      return to
    end
    methods.Create = function(_, object, _, props)
      for key, value in pairs(props or {}) do object[key] = lerp(object[key], value, 0.55) end
      return { Play = function() end, Cancel = function() end, Completed = { Connect = function() end } }
    end
    local reaction = string.match(arg[4], ':(.+)$') or 'tomato'
    local owned = {}
    for _, item in ipairs(Catalog) do if item.category == 'emote' then owned[item.id] = true end end
    state = trickInProgress(4, 1)
    remote.OnClientEvent.handler({ game = Practice.view(state), coins = 3000, owned = owned, serverTime = 0 })
    for _, child in ipairs(find(playerGui, 'FxLayer'):GetChildren()) do child:Destroy() end
    pendingDelays = {}
    clockOffset = clockOffset + 10
    math.random = function(a, b) if a then return math.floor((a + (b or a)) / 2) end return 0.5 end
    click('TableChat')
    click('Tgt_seat2')
    click('Throw_' .. reaction)
    if string.sub(arg[4], 1, 6) == 'flight' then
      local projectile = find(playerGui, 'Projectile')
      projectile.Progress.signals.Changed.handler(0.5)
    else
      flushDelays() -- lands: impact word, effect and target mark mid-animation
    end
  elseif arg[4] == 'private' then
    receive(nil)
    click('CreatePrivate')
  elseif arg[4] == 'shop' then click('ShopToggle')
  elseif arg[4] == 'play' or arg[4] == 'multi' then
    -- A trick in progress after one completed trick, so previews show who
    -- played what and who is winning.
    state = trickInProgress(arg[4] == 'multi' and 10 or 4, (arg[4] == 'multi' and 10 or 4) - 1)
    receive(state)
  end
  local function quote(s) return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r'):gsub('\t', '\\t') .. '"' end
  local function json(value)
    if type(value) == 'string' then return quote(value) end
    if type(value) == 'number' or type(value) == 'boolean' then return tostring(value) end
    if type(value) ~= 'table' then return 'null' end
    local parts = {}
    for key, item in pairs(value) do table.insert(parts, quote(tostring(key)) .. ':' .. json(item)) end
    return '{' .. table.concat(parts, ',') .. '}'
  end
  local function export(object)
    local props = {}
    for key, value in pairs(object.props) do if key ~= 'Parent' then props[key] = value end end
    props.children = {}
    for i, child in ipairs(object.children) do props.children[tostring(i)] = export(child) end
    return props
  end
  print(json(export(playerGui)))
else print('PASS: fullscreen, declarations, burial, Chao Di pass, multi-selection, pair submission/rendering, play tags, last-trick peek, match length, stake multiplier, save status, payout steps, reactions, stats, waiting room, player seats, private codes, squad lobby, invites, search bar, points pop-up, history, autoplay toggle, shop and resize') end
