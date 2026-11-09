-- Happy Tractor client, part 1/14: Core.
-- Lines 1-426 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Players = game:GetService('Players') C.Players = Players
local shared = game:GetService('ReplicatedStorage'):WaitForChild('Tractor')
local remote = shared:WaitForChild('Action') C.remote = remote
local Cards = require(shared.Cards) C.Cards = Cards
local Catalog = require(shared.Catalog) C.Catalog = Catalog
local Layout = require(shared.TableLayout) C.Layout = Layout
local Structures = require(shared.Structures)(Cards) C.Structures = Structures
local Rules = require(shared.PlayRules)(Cards, Structures) C.Rules = Rules
local playerGui = Players.LocalPlayer:WaitForChild('PlayerGui')

local color = Color3.fromRGB C.color = color
local palette = {
  -- Cool slate surfaces keep the colorful modes, coins and cards in focus.
  emeraldDark = color(12, 19, 34),
  emeraldDeep = color(20, 32, 51),
  panel = color(28, 43, 65),
  panelLight = color(43, 65, 91),
  panelBorder = color(70, 100, 128),
  feltTop = color(40, 155, 92),
  feltBottom = color(24, 115, 66),
  railOuter = color(83, 137, 166),
  railInner = color(48, 165, 100),
  gold = color(255, 205, 69),
  goldBright = color(255, 229, 143),
  goldDark = color(225, 155, 38),
  white = color(255, 255, 255),
  cream = color(255, 255, 245),
  muted = color(169, 190, 211),
  sage = color(160, 220, 190),
  red = color(245, 55, 65),
  ink = color(24, 34, 28),
  green = color(75, 240, 165),
  partnerTop = color(44, 145, 255),
  partnerBottom = color(18, 75, 160),
  opponentTop = color(255, 65, 80),
  opponentBottom = color(160, 24, 36),
  teamBlue = color(44, 145, 255),
  teamBlueDark = color(18, 75, 160),
  teamRed = color(255, 65, 80),
  teamRedDark = color(160, 24, 36),
  dealerRed = color(235, 50, 50),
  cardFace = color(255, 255, 255),
  cardGrad = color(248, 250, 246),
  cardBorder = color(195, 212, 200),
  cardTrumpBorder = color(255, 210, 80),
  tileBg = color(18, 30, 48),
  tileHover = color(38, 65, 91),
  meterBg = color(12, 22, 36),
  darkStroke = color(8, 15, 27),
} C.palette = palette
local symbols = { clubs = '♣', diamonds = '♦', hearts = '♥', spades = '♠' } C.symbols = symbols
local suitColors = {
  spades = color(20, 24, 32),    -- Pitch Black
  hearts = color(220, 38, 38),   -- Crimson Red
  clubs = color(20, 138, 58),    -- Emerald Green
  diamonds = color(28, 115, 230),-- Royal Blue
} C.suitColors = suitColors
local feltThemes = {
  felt_emerald = {
    name = 'Emerald Lounge',
    top = color(40, 155, 92), bottom = color(24, 115, 66),
    railOuter = color(255, 215, 75), railInner = color(48, 165, 100),
  },
  felt_sapphire = {
    name = 'Royal Sapphire',
    top = color(28, 85, 175), bottom = color(14, 42, 95),
    railOuter = color(255, 215, 75), railInner = color(44, 120, 210),
  },
  felt_ruby = {
    name = 'Imperial Ruby',
    top = color(155, 32, 54), bottom = color(85, 16, 30),
    railOuter = color(255, 215, 75), railInner = color(205, 50, 78),
  },
  felt_obsidian = {
    name = 'Obsidian VIP',
    top = color(38, 42, 48), bottom = color(20, 22, 26),
    railOuter = color(255, 215, 75), railInner = color(85, 92, 105),
  },
} C.feltThemes = feltThemes


pcall(function()
  local service = game:GetService('TweenService')
  if service and service.Create then C.TweenService = service end
end)

local function tween(object, info, props)
  if C.TweenService and object and object.Parent then
    local t = C.TweenService:Create(object, info, props)
    t:Play()
    return t
  else
    for k, v in pairs(props) do object[k] = v end
  end
end C.tween = tween

local function make(class, parent, name, props)
  local object = Instance.new(class)
  object.Name = name
  for key, value in pairs(props or {}) do object[key] = value end
  object.Parent = parent
  return object
end C.make = make

local function rect(object, x, y, w, h)
  if not object then return end
  object.Position = UDim2.fromOffset(x, y)
  object.Size = UDim2.fromOffset(w, h)
end C.rect = rect

local function corner(object, radius)
  return make('UICorner', object, 'Corner', { CornerRadius = UDim.new(0, radius) })
end C.corner = corner

local function outline(object, tint, thickness)
  return make('UIStroke', object, 'Outline', { Color = tint, Thickness = thickness or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border })
end C.outline = outline

local function gradient(object, first, last, rotation)
  return make('UIGradient', object, 'Gradient', { Color = ColorSequence.new(first, last), Rotation = rotation or 90 })
end C.gradient = gradient

local function frame(parent, name, tint, radius)
  local object = make('Frame', parent, name, { BackgroundColor3 = tint or palette.panel, BorderSizePixel = 0 })
  if radius then corner(object, radius) end
  return object
end C.frame = frame

local function label(parent, name, text, size, tint)
  return make('TextLabel', parent, name, {
    BackgroundTransparency = 1,
    Text = text,
    TextColor3 = tint or palette.white,
    TextSize = size or 16,
    Font = Enum.Font.GothamBold,
    TextStrokeTransparency = 1,
    TextStrokeColor3 = palette.darkStroke,
    TextWrapped = true,
    BorderSizePixel = 0,
  })
end C.label = label

local function flatCoinIcon(parent, name)
  local holder = frame(parent, name, palette.emeraldDeep, 999)
  holder.BackgroundTransparency = 1
  local disc = frame(holder, 'CurrencyCoin', palette.gold, 999)
  disc.Size = UDim2.fromScale(0.82, 0.82)
  disc.Position = UDim2.fromScale(0.09, 0.09)
  outline(disc, palette.goldDark, 2)
  local inset = frame(disc, 'Inset', palette.goldBright, 999)
  inset.Size = UDim2.fromScale(0.72, 0.72)
  inset.Position = UDim2.fromScale(0.14, 0.14)
  local dollar = label(inset, 'Currency', '$', 18, palette.ink)
  dollar.TextScaled = true
  dollar.Size = UDim2.fromScale(1, 1)
  for i = 1, 0 do
    local coin = frame(holder, 'Coin' .. i, i == 3 and palette.goldBright or palette.goldDark, 999)
    coin.Size = UDim2.new(0.78, 0, 0.28, 0)
    coin.Position = UDim2.new(0.11, 0, 0.56 - i * 0.14, 0)
    outline(coin, palette.goldDark, 1)
  end
  local mark = label(holder, 'Mark', '$', 12, palette.ink)
  mark.Font = Enum.Font.FredokaOne
  mark.Visible = false
  mark.TextStrokeTransparency = 1
  mark.Size = UDim2.fromScale(0.42, 0.42)
  mark.Position = UDim2.fromScale(0.29, 0.20)
  return holder
end C.flatCoinIcon = flatCoinIcon

local SoundService
pcall(function() SoundService = game:GetService('SoundService') end)
C.sfxEnabled = true
C.bgmEnabled = true
local soundFolder
pcall(function()
  if SoundService then
    soundFolder = SoundService:FindFirstChild('TractorSounds')
    if not soundFolder then
      soundFolder = Instance.new('Folder')
      soundFolder.Name = 'TractorSounds'
      soundFolder.Parent = SoundService
    end
  end
end)

-- Free Creator Store sounds. name = { id, volume, basePitch }
local soundAssets = {
  click       = { 'rbxassetid://88442833509532', 0.35, 1.0 },  -- ui-simple-button-click
  card_select = { 'rbxassetid://3456145589', 0.35, 1.25 },  -- card_flip (light, high)
  card_deal   = { 'rbxassetid://3456145589', 0.30, 1.05 },  -- card_flip
  card_play   = { 'rbxassetid://4839809962', 0.55, 1.0 },   -- cardPlace2 (snap on felt)
  turn_chime  = { 'rbxassetid://73656152208310', 0.40, 1.0 }, -- ui-success ping
  whoosh      = { 'rbxassetid://9126229267', 0.35, 1.0 },   -- PSE whoosh by
  impact      = { 'rbxassetid://9126229255', 0.40, 1.0 },   -- PSE whoosh + thud
  tractor     = { 'rbxassetid://79130903404606', 0.50, 1.0 }, -- crystal fx sparkle
  coin        = { 'rbxassetid://135483737426662', 0.45, 1.0 }, -- coin collect
  win         = { 'rbxassetid://9039636406', 0.45, 1.0 },   -- Can You Feel the Love? (sting b), jazz horns and strings
  defeat      = { 'rbxassetid://97861773515321', 0.40, 1.0 }, -- lose arcade
  error       = { 'rbxassetid://88442833509532', 0.40, 0.6 },  -- low, dull click = "nope"
  chaodi_gong = { 'rbxassetid://88473578863960', 0.60, 1.0 }, -- Chinese gong (Chao Di)
  double_up   = { 'rbxassetid://133977339172345', 0.55, 1.0 }, -- power-up rise (Double)
}

-- Music: upbeat lounge in menus, softer piano at the table. Crossfades.
local MUSIC = {
  menu = { id = 'rbxassetid://130337328182652', volume = 0.18 }, -- Chill Lounge Music
  game = { id = 'rbxassetid://122061441658611', volume = 0.08 }, -- Cozy Piano Evening
}

local robloxGearImages = {
  flower = 'rbxthumb://type=Asset&id=108149171&w=150&h=150',      -- Roblox Classic Rose
  tomato = 'rbxthumb://type=Asset&id=115377964&w=150&h=150',      -- Roblox Classic Tomato
  bomb = 'rbxthumb://type=Asset&id=11999247&w=150&h=150',         -- Roblox Classic Timebomb
  coffee = 'rbxthumb://type=Asset&id=10472779&w=150&h=150',       -- Roblox Bloxy Cola
  tractor_rush = 'rbxthumb://type=Asset&id=99119158&w=150&h=150', -- Roblox Speed Coil
  cheer = 'rbxthumb://type=Asset&id=25162389&w=150&h=150',        -- Roblox Gold Trophy
  wave = 'rbxthumb://type=AvatarHeadShot&id=1&w=150&h=150',        -- Roblox Classic Noob
  laugh = 'rbxthumb://type=Asset&id=7074786&w=150&h=150',          -- Roblox Epic Face
  wow = 'rbxthumb://type=Asset&id=15967743&w=150&h=150',           -- Roblox Cheezburger
  sword = 'rbxthumb://type=Asset&id=125013769&w=150&h=150',       -- Roblox Classic Linked Sword
  dragon = 'rbxthumb://type=Asset&id=67148404&w=150&h=150',        -- Roblox 3D Green Dragon
  tripmine = 'rbxthumb://type=Asset&id=11999236&w=150&h=150',      -- Roblox Subspace Tripmine
  goldTrophy = 'rbxthumb://type=Asset&id=25162389&w=150&h=150',    -- Roblox Bloxy Trophy
} C.robloxGearImages = robloxGearImages
local rewardIconAsset = 'rbxassetid://102050287524162'
local emoteIconAsset = 'rbxassetid://137785351194404'
-- Original in-game emote artwork: six 512px cells in a 3x2 sheet.
local emoteArtSheet = 'rbxassetid://92795511435553'

local soundInstances = {}
if soundFolder then
  for sName, sId in pairs(soundAssets) do
    pcall(function()
      local s = soundFolder:FindFirstChild(sName)
      if not s then
        s = Instance.new('Sound')
        s.Name = sName
        s.Parent = soundFolder
      end
      s.SoundId = sId[1]
      s.Volume = sId[2]
      soundInstances[sName] = s
    end)
  end
end

local tracks = {}
pcall(function()
  for mode, def in pairs(MUSIC) do
    local s = Instance.new('Sound')
    s.Name = 'Music_' .. mode
    s.SoundId = def.id
    s.Volume = 0
    s.Looped = true
    s.Parent = soundFolder or SoundService
    tracks[mode] = s
  end
end)
C.musicMode = 'menu'

local function fadeTo(s, volume, stopAfter)
  local tw = game:GetService('TweenService'):Create(s, TweenInfo.new(1.2, Enum.EasingStyle.Sine), { Volume = volume })
  tw:Play()
  if stopAfter then
    tw.Completed:Connect(function(state)
      if state == Enum.PlaybackState.Completed and s.Volume <= 0.001 then s:Pause() end
    end)
  end
end

local function updateSoundtrack()
  for mode, s in pairs(tracks) do
    pcall(function()
      if C.bgmEnabled and mode == C.musicMode then
        if not s.IsPlaying then s:Resume() end
        fadeTo(s, MUSIC[mode].volume, false)
      else
        fadeTo(s, 0, true)
      end
    end)
  end
end C.updateSoundtrack = updateSoundtrack

function C.setMusicMode(mode)
  if mode == C.musicMode or not MUSIC[mode] then return end
  C.musicMode = mode
  updateSoundtrack()
end
updateSoundtrack()

-- Menu music while the home/stake screens are up, table music during a game.
task.spawn(function()
  while true do
    task.wait(0.5)
    pcall(function()
      local gui = game:GetService('Players').LocalPlayer.PlayerGui:FindFirstChild('TractorTable')
      local tableRoot = gui and gui:FindFirstChild('TableRoot')
      if not tableRoot then return end
      local home = tableRoot:FindFirstChild('HomeScreen')
      local tierScreen = tableRoot:FindFirstChild('TierScreen')
      local inMenu = (home and home.Visible) or (tierScreen and tierScreen.Visible)
      local game_ = C.state and C.state.game
      C.setMusicMode((not inMenu and game_ and not game_.done) and 'game' or 'menu')
    end)
  end
end)

local function playSound(name, pitchVariation, volumeMult)
  if not C.sfxEnabled then return end
  pcall(function()
    local s = soundInstances[name]
    if s then
      local def = soundAssets[name]
      s.TimePosition = 0
      local basePitch = def[3] or 1
      -- Small random pitch on every play so repeats don't sound robotic.
      local spread = pitchVariation and 8 or 3
      s.PlaybackSpeed = basePitch + (math.random(-spread, spread) / 100)
      -- Volume is always computed from the base, so it never drifts.
      s.Volume = math.clamp(def[2] * (volumeMult or 1), 0, 1)
      s:Play()
    end
  end)
end C.playSound = playSound

-- Signature stings for the big moments (Chao Di = gong, Double = power-up).
function C.say(kind)
  playSound(kind == 'chaodi' and 'chaodi_gong' or 'double_up')
end

local function button(parent, name, text, callback, tint)
  local isShade = text == ''
  local isPrimary = not tint or tint == palette.gold or tint == palette.goldBright
  local object = make('TextButton', parent, name, {
    Text = text,
    TextSize = 16,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    TextWrapped = false,
    TextColor3 = (isPrimary and not isShade) and palette.ink or palette.cream,
    -- Rounded display face for primary calls to action, clean sans elsewhere.
    Font = isPrimary and Enum.Font.FredokaOne or Enum.Font.GothamBold,
    TextStrokeTransparency = 1,
    BackgroundColor3 = tint or palette.gold,
    BorderSizePixel = 0,
    AutoButtonColor = false,
  })
  -- One control language: soft corners, a hairline border, and (for gold
  -- primaries) a gentle light-to-warm ramp. No stacked shine/bevel strips.
  corner(object, 10)
  if not isShade then
    if isPrimary then gradient(object, palette.goldBright, palette.gold, 90) end
    local border = outline(object, isPrimary and palette.goldDark or palette.panelBorder, 1)
    border.Transparency = isPrimary and 0.15 or 0.5
  end

  local scale = make('UIScale', object, 'Scale', { Scale = 1.0 })
  if C.TweenService then
    local spring = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    local squash = TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
    object.MouseEnter:Connect(function()
      C.TweenService:Create(scale, spring, { Scale = 1.035 }):Play()
    end)
    object.MouseLeave:Connect(function()
      C.TweenService:Create(scale, spring, { Scale = 1.0 }):Play()
    end)
    object.MouseButton1Down:Connect(function()
      C.TweenService:Create(scale, squash, { Scale = 0.92 }):Play()
    end)
    object.MouseButton1Up:Connect(function()
      C.TweenService:Create(scale, spring, { Scale = 1.035 }):Play()
    end)
  end

  object.Activated:Connect(function(...)
    playSound('click')
    if callback then callback(...) end
  end)
  return object
end C.button = button

local customIconAsset = 'rbxassetid://122633101230144' C.customIconAsset = customIconAsset
local function customIcon(parent, name, rectOffset, size)
  local icon = make('ImageLabel', parent, name, {
    BackgroundTransparency = 1,
    Image = customIconAsset,
    ImageRectSize = Vector2.new(512, 1024),
    ImageRectOffset = Vector2.new(rectOffset, 0),
    Size = UDim2.fromOffset(size, size),
    Position = UDim2.fromOffset(4, 3),
    ZIndex = 4,
  })
  return icon
end

-- Edge-to-edge vibrant emerald backdrop decoration; controls in CoreUISafeInsets.
local backdropGui = make('ScreenGui', playerGui, 'TractorBackdrop', { ResetOnSpawn = false,
  ScreenInsets = Enum.ScreenInsets.None, DisplayOrder = 10, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local backdrop = frame(backdropGui, 'Backdrop', palette.emeraldDark)
backdrop.Size = UDim2.fromScale(1, 1)
gradient(backdrop, color(24, 42, 68), color(8, 14, 27), 90)

local halo = frame(backdrop, 'TableGlow', color(38, 142, 88), 999)
halo.Position = UDim2.fromScale(0.03, 0.05)
halo.Size = UDim2.fromScale(0.94, 0.88)
halo.BackgroundTransparency = 1

local gui = make('ScreenGui', playerGui, 'TractorTable', { ResetOnSpawn = false,
  ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets, DisplayOrder = 11, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
local root = frame(gui, 'TableRoot') C.root = root
root.BackgroundTransparency = 1
root.Size = UDim2.fromScale(1, 1)

local function formatK(n)
  n = tonumber(n) or 0
  if n >= 1000000 then
    local m = n / 1000000
    return (m % 1 == 0 and string.format("%dM", m)) or string.format("%.1fM", m)
  elseif n >= 1000 then
    local k = n / 1000
    return (k % 1 == 0 and string.format("%dK", k)) or string.format("%.1fK", k)
  else
    return tostring(n)
  end
end C.formatK = formatK

C.state = {
  coins = 3000,
  dailyClaimed = false,
  nextGiftAt = 0,
  quests = {
    play = { label = 'Play 1 Match', progress = 0, target = 1, reward = 500, claimed = false },
    points = { label = 'Capture 40+ Points', progress = 0, target = 40, reward = 750, claimed = false },
    emote = { label = 'Send a Table Emote', progress = 0, target = 1, reward = 250, claimed = false },
  },
  owned = { wave = true, cheer = true, flower = true, cardback_classic = true, felt_emerald = true },
  equipped = { cardBack = 'cardback_classic', felt = 'felt_emerald' },
}
C.busy, C.muted, C.selectedIds, C.selectedChaodiIndex = false, false, {}, nil
C.handDragActive, C.handDragValue, C.handDragVisited = false, true, {}
C.setupPlayerCount = 4
C.lobbyMode = 'home'
C.autoPlay, C.nextAutoAt = false, 0
C.receivedAt, C.currentLayout = os.clock(), nil


local header = frame(root, 'Header', palette.emeraldDeep, 16) C.header = header
header.BackgroundTransparency = 0.15
outline(header, palette.panelBorder, 1)
local title = label(header, 'Title', 'TRACTOR', 24, palette.gold) C.title = title
title.Font = Enum.Font.FredokaOne
title.TextStrokeTransparency = 0.65
title.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
title.TextXAlignment = Enum.TextXAlignment.Left

local subtitle = label(header, 'Subtitle', '2v2 PARTY MATCH  /  RANDOM LEVEL', 10, palette.white) C.subtitle = subtitle
subtitle.TextXAlignment = Enum.TextXAlignment.Left

local wallet = label(header, 'Wallet', '●  3K coins', 18, palette.gold) C.wallet = wallet
wallet.Font = Enum.Font.FredokaOne
wallet.TextStrokeTransparency = 0.70
wallet.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
local walletHint = label(header, 'WalletHint', 'SESSION BALANCE', 9, palette.white) C.walletHint = walletHint


local rewardsUI = {} C.rewardsUI = rewardsUI


local queueUI; C.openQueue, C.cancelQueue, queueUI = nil, nil, {} C.queueUI = queueUI
C.lastTurnWasSelf = false

local arenaUI = {} C.arenaUI = arenaUI
arenaUI.Scoring = require(shared.Scoring)(Cards)
local arena = frame(root, 'Arena', palette.feltBottom, 90) C.arena = arena
local arenaGradient = gradient(arena, palette.feltTop, palette.feltBottom, 90) C.arenaGradient = arenaGradient
arenaUI.arenaStroke = outline(arena, palette.railOuter, 3.0)
end
