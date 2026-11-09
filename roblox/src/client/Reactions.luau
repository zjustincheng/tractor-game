-- Table reactions: definitions, the reaction tile, the throw (launch, arc,
-- impact), what each reaction leaves on the player it hits, and speech
-- bubbles. UI helpers and services are injected so the visuals stay in one
-- place and can run under the test harness.
return function(ui)
  local make, frame, label, corner, outline = ui.make, ui.frame, ui.label, ui.corner, ui.outline
  local tween, delay, playSound, color = ui.tween, ui.delay, ui.playSound, ui.color
  local layer, shake = ui.layer, ui.shake or function() end
  local Ease, Dir = Enum.EasingStyle, Enum.EasingDirection
  local WHITE, INK = Color3.fromRGB(255, 255, 255), Color3.fromRGB(22, 18, 30)
  local R = {}

  -- glyph: emoji shown on tiles and in flight. word: comic burst on impact.
  -- effect: landing animation. mark: what stays on the target for a moment.
  R.order = { 'wave', 'cheer', 'laugh', 'wow', 'flower', 'tomato', 'bomb', 'coffee', 'tractor_rush' }
  R.defs = {
    wave = { name = 'Wave', glyph = '👋', word = 'HI!', line = 'Hello everyone!', tint = color(52, 132, 230), friendly = true, effect = 'wave', mark = 'sparkle' },
    cheer = { name = 'Trophy', glyph = '🏆', word = 'GG!', line = 'GG! Well played!', tint = color(232, 168, 40), friendly = true, effect = 'confetti', mark = 'glow' },
    laugh = { name = 'Laugh', glyph = '😂', word = 'LOL', line = 'Haha, nice one!', tint = color(156, 84, 214), friendly = true, effect = 'bounce', mark = 'sparkle' },
    wow = { name = 'Wow', glyph = '😮', word = 'WOW!', line = 'Unbelievable hand!', tint = color(32, 162, 196), friendly = true, effect = 'bounce', mark = 'sparkle' },
    flower = { name = 'Rose', glyph = '🌹', word = '♥', line = 'A rose for you!', tint = color(224, 64, 104), friendly = true, effect = 'petals', mark = 'hearts' },
    tomato = { name = 'Tomato', glyph = '🍅', word = 'SPLAT!', line = 'Incoming splat!', tint = color(222, 84, 44), friendly = false, effect = 'splat', mark = 'splat' },
    bomb = { name = 'Bomb', glyph = '💣', word = 'BOOM!', line = 'Boom for you!', tint = color(64, 70, 86), friendly = false, effect = 'blast', mark = 'soot' },
    coffee = { name = 'Coffee', glyph = '☕', word = 'FOCUS!', line = 'Focus up!', tint = color(140, 92, 60), friendly = true, effect = 'steam', mark = 'steam' },
    tractor_rush = { name = 'Tractor', glyph = '🚜', word = 'VROOM!', line = 'Tractor rush!', tint = color(46, 168, 104), friendly = true, effect = 'rush', mark = 'tracks' },
  }

  local function ease(seconds, style, direction)
    return TweenInfo.new(seconds, style or Ease.Quad, direction or Dir.Out)
  end
  local function at(object, x, y, w, h)
    object.Position = UDim2.fromOffset(x - w / 2, y - h / 2)
    object.Size = UDim2.fromOffset(w, h)
  end
  local function lighten(c, amount)
    return Color3.new(c.R + (1 - c.R) * amount, c.G + (1 - c.G) * amount, c.B + (1 - c.B) * amount)
  end
  local function glyph(parent, name, text, size)
    local g = label(parent, name, text, size, WHITE)
    g.Font = Enum.Font.GothamBold
    g.TextWrapped = false
    g.ZIndex = 60
    return g
  end
  local function dot(parent, name, tint, size)
    local d = frame(parent or layer, name, tint, 999)
    d.Size = UDim2.fromOffset(size, size)
    d.ZIndex = 58
    return d
  end
  local function cleanup(object, seconds)
    delay(seconds, function() if object.Parent then object:Destroy() end end)
  end

  -- Reaction tile for the dock and shop: glossy tint, highlight, emoji with a
  -- soft shadow, name, and a gold frame for paid reactions.
  function R.tile(parent, name, def, width, height, withName, premium)
    local tileFrame = frame(parent, name, def.tint, 14)
    tileFrame.Size = UDim2.fromOffset(width, height)
    make('UIGradient', tileFrame, 'Sheen', { Color = ColorSequence.new(lighten(def.tint, 0.25), def.tint), Rotation = 90 })
    local stroke = outline(tileFrame, premium and Color3.fromRGB(255, 214, 102) or lighten(def.tint, 0.45), premium and 1.5 or 1)
    stroke.Transparency = premium and 0 or 0.35
    local gloss = frame(tileFrame, 'Gloss', WHITE, 12)
    gloss.BackgroundTransparency = 0.88
    gloss.Position = UDim2.fromOffset(3, 3)
    gloss.Size = UDim2.new(1, -6, 0.42, 0)
    gloss.ZIndex = tileFrame.ZIndex + 1
    local faceSize = math.floor(math.min(width, height) * (withName and 0.44 or 0.62))
    local shadow = glyph(tileFrame, 'GlyphShadow', def.glyph, faceSize)
    shadow.TextColor3 = INK
    shadow.TextTransparency = 0.7
    shadow.Position = UDim2.fromOffset(1, 3)
    shadow.Size = UDim2.new(1, 0, withName and 0.66 or 1, 0)
    shadow.ZIndex = tileFrame.ZIndex + 2
    local face = glyph(tileFrame, 'Glyph', def.glyph, faceSize)
    face.Size = UDim2.new(1, 0, withName and 0.66 or 1, 0)
    face.ZIndex = tileFrame.ZIndex + 3
    if withName then
      local caption = label(tileFrame, 'Name', def.name, 10, WHITE)
      caption.Font = Enum.Font.GothamBlack
      caption.TextWrapped = false
      caption.TextStrokeTransparency = 0.55
      caption.TextStrokeColor3 = INK
      caption.Position = UDim2.new(0, 0, 0.66, 0)
      caption.Size = UDim2.new(1, 0, 0.28, 0)
      caption.ZIndex = tileFrame.ZIndex + 3
    end
    return tileFrame
  end

  local function ring(x, y, tint, from, to, seconds, thickness)
    local r = frame(layer, 'Ring', tint, 999)
    r.BackgroundTransparency = 1
    r.ZIndex = 57
    local stroke = outline(r, tint, thickness or 3)
    at(r, x, y, from, from)
    tween(r, ease(seconds), { Size = UDim2.fromOffset(to, to), Position = UDim2.fromOffset(x - to / 2, y - to / 2) })
    tween(stroke, ease(seconds), { Transparency = 1, Thickness = 0.5 })
    cleanup(r, seconds + 0.05)
    return r
  end

  local function pop(x, y, text, size, seconds, rise)
    local g = glyph(layer, 'Pop', text, size)
    at(g, x, y, size * 2, size * 2)
    local s = make('UIScale', g, 'Scale', { Scale = 0.3 })
    tween(s, ease(0.22, Ease.Back), { Scale = 1.15 })
    delay(0.22, function()
      if g.Parent then tween(g, ease(seconds), { TextTransparency = 1, Position = UDim2.fromOffset(x - size, y - size - (rise or 18)) }) end
    end)
    cleanup(g, 0.25 + seconds)
    return g
  end

  -- Comic word burst ("SPLAT!") with a thick outline, a tilt and a bounce.
  local function word(x, y, def)
    local w = label(layer, 'Word', def.word, 36, lighten(def.tint, 0.15))
    w.Font = Enum.Font.FredokaOne
    w.TextWrapped = false
    w.TextStrokeColor3 = INK
    w.TextStrokeTransparency = 0
    w.ZIndex = 62
    w.Rotation = def.friendly and -6 or 8
    at(w, x, y - 40, 180, 46)
    local s = make('UIScale', w, 'Scale', { Scale = 0.2 })
    tween(s, ease(0.28, Ease.Back), { Scale = 1.15 })
    delay(0.55, function()
      if not w.Parent then return end
      tween(w, ease(0.4), { TextTransparency = 1, TextStrokeTransparency = 1, Position = UDim2.fromOffset(x - 90, y - 84) })
    end)
    cleanup(w, 1.0)
    return w
  end

  -- Particles flung outward; `fall` pulls them down after the burst.
  local function scatter(x, y, count, radius, makeParticle, seconds, fall)
    for index = 1, count do
      local p = makeParticle(index)
      if not p.Size or p.Size.X.Offset == 0 then p.Size = UDim2.fromOffset(18, 18) end
      local angle = (index / count) * math.pi * 2 + math.random() * 0.5
      local reach = radius * (0.6 + math.random() * 0.5)
      local ex, ey = x + math.cos(angle) * reach, y + math.sin(angle) * reach * (fall and 0.6 or 1) - (fall and 18 or 0)
      local w = p.Size.X.Offset
      at(p, x, y, w, p.Size.Y.Offset)
      tween(p, ease(seconds * 0.45), { Position = UDim2.fromOffset(ex - w / 2, ey - w / 2), Rotation = math.random(-180, 180) })
      delay(seconds * 0.45, function()
        if not p.Parent then return end
        local props = { Position = UDim2.fromOffset(ex - w / 2, ey + (fall and 46 or 10)) }
        if p:IsA('TextLabel') then props.TextTransparency = 1 else props.BackgroundTransparency = 1 end
        tween(p, ease(seconds * 0.55, Ease.Quad, fall and Dir.In or Dir.Out), props)
      end)
      cleanup(p, seconds + 0.05)
    end
  end

  -- Launch: a burst ring and sparks at the sender as the reaction leaves.
  local function launch(x, y, def)
    ring(x, y, lighten(def.tint, 0.3), 12, 64, 0.35, 3)
    for index = 1, 5 do
      local spark = dot(nil, 'Spark', WHITE, 5)
      local angle = index / 5 * math.pi * 2
      at(spark, x, y, 5, 5)
      tween(spark, ease(0.3), { Position = UDim2.fromOffset(x + math.cos(angle) * 26 - 2, y + math.sin(angle) * 26 - 2), BackgroundTransparency = 1 })
      cleanup(spark, 0.35)
    end
  end

  -- Flight: the glyph grows toward the top of its arc and shrinks to land,
  -- with a shadow sliding across the table beneath it and a sparkling trail.
  -- The tractor dashes low and fast instead. Calls onLand(token).
  function R.fly(def, fromX, fromY, toX, toY, onLand)
    local size = 38
    local token = glyph(layer, 'Projectile', def.glyph, size)
    at(token, fromX, fromY, 48, 48)
    local tokenShadow = glyph(token, 'Shadow', def.glyph, size)
    tokenShadow.TextColor3 = INK
    tokenShadow.TextTransparency = 0.72
    tokenShadow.Position = UDim2.fromOffset(2, 4)
    tokenShadow.Size = UDim2.fromScale(1, 1)
    tokenShadow.ZIndex = 59
    local scale = make('UIScale', token, 'Scale', { Scale = 0.2 })
    local ground = dot(nil, 'GroundShadow', INK, 30)
    ground.BackgroundTransparency = 0.7
    ground.ZIndex = 56
    at(ground, fromX, fromY + 16, 30, 10)

    local rush = def.effect == 'rush'
    local distance = math.sqrt((toX - fromX) ^ 2 + (toY - fromY) ^ 2)
    local duration = rush and 0.45 or math.clamp(0.5 + distance / 1300, 0.55, 0.9)
    local lift = rush and 0 or math.clamp(distance * 0.38, 60, 180)
    local cx, cy = (fromX + toX) / 2, math.min(fromY, toY) - lift
    local spin = def.friendly and 0 or 720
    local progress = make('NumberValue', token, 'Progress', { Value = 0 })
    local lastTrail = 0
    progress.Changed:Connect(function(t)
      local u = 1 - t
      local x = u * u * fromX + 2 * u * t * cx + t * t * toX
      local y = u * u * fromY + 2 * u * t * cy + t * t * toY
      local height = math.sin(t * math.pi)
      token.Position = UDim2.fromOffset(x - 24, y - 24)
      token.Rotation = spin * t + (def.friendly and math.sin(t * math.pi * 4) * 12 or 0)
      scale.Scale = 1 + (rush and 0 or 0.45 * height)
      -- The ground shadow travels straight and shrinks while the glyph is high.
      local gx, gy = fromX + (toX - fromX) * t, fromY + (toY - fromY) * t + 16
      local gw = 34 - 16 * height
      ground.Position = UDim2.fromOffset(gx - gw / 2, gy - gw * 0.15)
      ground.Size = UDim2.fromOffset(gw, gw * 0.3)
      ground.BackgroundTransparency = 0.68 + 0.2 * height
      if t - lastTrail > 0.05 then
        lastTrail = t
        local trailSize = rush and 10 or (math.random() < 0.3 and 4 or 7)
        local trail = dot(nil, 'Trail', rush and color(214, 196, 160) or (trailSize == 4 and WHITE or lighten(def.tint, 0.2)), trailSize)
        at(trail, x + math.random(-4, 4), y + (rush and 14 or math.random(-4, 4)), trailSize, trailSize)
        trail.BackgroundTransparency = 0.15
        tween(trail, ease(0.4), { BackgroundTransparency = 1, Size = UDim2.fromOffset(1, 1), Position = UDim2.fromOffset(x, y + 10) })
        cleanup(trail, 0.45)
      end
    end)
    tween(scale, ease(0.16, Ease.Back), { Scale = 1 })
    playSound('whoosh')
    launch(fromX, fromY, def)
    tween(progress, ease(duration, Ease.Sine, Dir.InOut), { Value = 1 })
    delay(duration, function()
      if ground.Parent then ground:Destroy() end
      if not token.Parent then return end
      token.Position = UDim2.fromOffset(toX - 24, toY - 24)
      token.Rotation = 0
      scale.Scale = 1
      onLand(token)
    end)
    return token
  end

  -- What a reaction leaves on the player it hits, cleaned up after a moment.
  local marks = {}
  function marks.splat(target)
    for index, spec in ipairs({ { 0.5, 0.45, 0.62 }, { 0.3, 0.62, 0.22 }, { 0.7, 0.3, 0.18 } }) do
      local blob = frame(target, 'HitSplat', color(206, 40, 32), 999)
      blob.AnchorPoint = Vector2.new(0.5, 0.5)
      blob.Position = UDim2.fromScale(spec[1], spec[2])
      blob.Size = UDim2.fromScale(spec[3], spec[3])
      blob.BackgroundTransparency = 0.15
      blob.ZIndex = 41
      local s = make('UIScale', blob, 'Scale', { Scale = 0.2 })
      tween(s, ease(0.14 + index * 0.03, Ease.Back), { Scale = 1 })
      delay(1.3, function() if blob.Parent then tween(blob, ease(0.5), { BackgroundTransparency = 1 }) end end)
      cleanup(blob, 1.9)
    end
    for index = 1, 3 do
      local drip = frame(target, 'HitDrip', color(206, 40, 32), 999)
      drip.Position = UDim2.new(0.25 + index * 0.15, 0, 0.55, 0)
      drip.Size = UDim2.fromOffset(5, 8)
      drip.ZIndex = 41
      tween(drip, ease(1.2, Ease.Quad, Dir.In), { Position = UDim2.new(0.25 + index * 0.15, 0, 1, 4), Size = UDim2.fromOffset(4, 14), BackgroundTransparency = 1 })
      cleanup(drip, 1.3)
    end
  end
  function marks.soot(target)
    local soot = frame(target, 'HitSoot', color(30, 28, 32), 12)
    soot.Size = UDim2.fromScale(1, 1)
    soot.BackgroundTransparency = 0.25
    soot.ZIndex = 41
    delay(0.9, function() if soot.Parent then tween(soot, ease(0.8), { BackgroundTransparency = 1 }) end end)
    cleanup(soot, 1.8)
    for index = 1, 3 do
      local puff = frame(target, 'HitPuff', color(110, 110, 120), 999)
      puff.AnchorPoint = Vector2.new(0.5, 0.5)
      puff.Position = UDim2.fromScale(0.3 + index * 0.2, 0.3)
      puff.Size = UDim2.fromOffset(14, 14)
      puff.BackgroundTransparency = 0.3
      puff.ZIndex = 42
      tween(puff, ease(1.1), { Position = UDim2.fromScale(0.3 + index * 0.2, -0.5), Size = UDim2.fromOffset(30, 30), BackgroundTransparency = 1 })
      cleanup(puff, 1.2)
    end
  end
  function marks.hearts(target)
    for index = 1, 4 do
      delay((index - 1) * 0.15, function()
        if not target.Parent then return end
        local heart = glyph(target, 'HitHeart', '❤️', 16)
        heart.AnchorPoint = Vector2.new(0.5, 0.5)
        heart.Position = UDim2.fromScale(0.25 + index * 0.13, 0.5)
        heart.Size = UDim2.fromOffset(24, 24)
        heart.ZIndex = 42
        tween(heart, ease(1.1), { Position = UDim2.fromScale(0.2 + index * 0.15, -0.6), TextTransparency = 1, Rotation = (index % 2 == 0) and 15 or -15 })
        cleanup(heart, 1.2)
      end)
    end
  end
  function marks.glow(target, def)
    local glow = frame(target, 'HitGlow', def.tint, 14)
    glow.BackgroundTransparency = 1
    glow.Size = UDim2.fromScale(1, 1)
    glow.ZIndex = 40
    local stroke = outline(glow, Color3.fromRGB(255, 220, 110), 5)
    tween(stroke, ease(0.8), { Transparency = 1, Thickness = 1 })
    cleanup(glow, 0.85)
  end
  function marks.sparkle(target, def)
    marks.glow(target, def)
    for index = 1, 3 do
      local star = glyph(target, 'HitSparkle', '✨', 14)
      star.AnchorPoint = Vector2.new(0.5, 0.5)
      star.Position = UDim2.fromScale(index * 0.25, index % 2 == 0 and 0.1 or 0.9)
      star.Size = UDim2.fromOffset(20, 20)
      star.ZIndex = 42
      tween(star, ease(0.8), { TextTransparency = 1, Rotation = 90 })
      cleanup(star, 0.85)
    end
  end
  function marks.steam(target)
    for index = 1, 3 do
      local wisp = frame(target, 'HitSteam', WHITE, 999)
      wisp.AnchorPoint = Vector2.new(0.5, 0.5)
      wisp.Position = UDim2.fromScale(0.3 + index * 0.2, 0.2)
      wisp.Size = UDim2.fromOffset(10, 10)
      wisp.BackgroundTransparency = 0.4
      wisp.ZIndex = 42
      tween(wisp, ease(1.0), { Position = UDim2.fromScale(0.3 + index * 0.2, -0.6), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1 })
      cleanup(wisp, 1.05)
    end
  end
  function marks.tracks(target)
    for index = 1, 2 do
      local track = frame(target, 'HitTrack', color(70, 52, 34), 2)
      track.Position = UDim2.new(0, -6, 0.35 + index * 0.2, 0)
      track.Size = UDim2.new(1, 12, 0, 4)
      track.BackgroundTransparency = 0.25
      track.ZIndex = 41
      delay(0.7, function() if track.Parent then tween(track, ease(0.6), { BackgroundTransparency = 1 }) end end)
      cleanup(track, 1.35)
    end
  end

  -- Feedback on the seat that was hit: hostile reactions knock it about.
  function R.hit(target, def)
    if not target or not target.Parent then return end
    if not def.friendly then
      for index, angle in ipairs({ 10, -8, 6, -4, 2, 0 }) do
        delay((index - 1) * 0.055, function() if target.Parent then tween(target, ease(0.055), { Rotation = angle }) end end)
      end
    end
    local mark = marks[def.mark]
    if mark then mark(target, def) end
  end

  local effects = {}
  function effects.petals(x, y, token)
    token:Destroy()
    pop(x, y - 6, '❤️', 26, 0.7, 28)
    ring(x, y, color(255, 150, 190), 10, 70, 0.45, 2)
    scatter(x, y, 9, 52, function() return glyph(layer, 'Petal', '🌸', 15) end, 1.2, true)
  end
  function effects.splat(x, y, token)
    token:Destroy()
    for index, spec in ipairs({ { 0, 0, 44 }, { -16, 9, 20 }, { 17, -10, 15 }, { 11, 15, 11 }, { -12, -13, 9 } }) do
      local stain = dot(nil, 'Stain', color(206, 40, 32), spec[3])
      at(stain, x + spec[1], y + spec[2], spec[3], spec[3])
      stain.BackgroundTransparency = 0.05
      local s = make('UIScale', stain, 'Scale', { Scale = 0.2 })
      tween(s, ease(0.12 + index * 0.02, Ease.Back), { Scale = 1 })
      delay(0.9, function() if stain.Parent then tween(stain, ease(0.6), { BackgroundTransparency = 1 }) end end)
      cleanup(stain, 1.55)
    end
    scatter(x, y, 12, 52, function(index) return dot(nil, 'Drop', index % 3 == 0 and color(255, 120, 90) or color(226, 58, 42), index % 3 == 0 and 5 or 8) end, 0.75, true)
  end
  function effects.blast(x, y, token)
    token:Destroy()
    shake(0.35, 7)
    local flash = dot(nil, 'Flash', WHITE, 120)
    at(flash, x, y, 30, 30)
    flash.BackgroundTransparency = 0.05
    tween(flash, ease(0.22), { Size = UDim2.fromOffset(150, 150), Position = UDim2.fromOffset(x - 75, y - 75), BackgroundTransparency = 1 })
    cleanup(flash, 0.25)
    ring(x, y, color(255, 150, 40), 20, 170, 0.5, 6)
    ring(x, y, color(255, 220, 120), 10, 110, 0.38, 3)
    pop(x, y, '💥', 40, 0.5)
    scatter(x, y, 10, 70, function()
      local puff = dot(nil, 'Smoke', color(120, 120, 130), math.random(14, 24))
      puff.BackgroundTransparency = 0.3
      return puff
    end, 1.1, false)
    scatter(x, y, 8, 90, function() return dot(nil, 'Ember', color(255, 170, 60), 5) end, 0.6, true)
  end
  function effects.confetti(x, y, token)
    tween(token, ease(0.25, Ease.Back), { Rotation = -12 })
    delay(0.3, function() if token.Parent then tween(token, ease(0.3), { TextTransparency = 1 }) end end)
    cleanup(token, 0.65)
    ring(x, y, color(255, 214, 102), 12, 90, 0.45, 3)
    local colors = { color(255, 205, 69), color(52, 132, 230), color(224, 64, 104), color(75, 220, 150), WHITE }
    scatter(x, y, 22, 84, function(index)
      local c = frame(layer, 'Confetti', colors[(index % #colors) + 1], 2)
      c.Size = UDim2.fromOffset(5, 10)
      c.ZIndex = 58
      return c
    end, 1.3, true)
    pop(x + 20, y - 18, '✨', 18, 0.5)
  end
  function effects.steam(x, y, token)
    delay(0.5, function() if token.Parent then tween(token, ease(0.3), { TextTransparency = 1 }) end end)
    cleanup(token, 0.85)
    for index = 1, 5 do
      local wisp = dot(nil, 'Steam', WHITE, 10)
      at(wisp, x - 12 + index * 5, y - 14, 10, 10)
      wisp.BackgroundTransparency = 0.35
      delay(index * 0.07, function()
        if not wisp.Parent then return end
        tween(wisp, ease(0.85), { Position = UDim2.fromOffset(x - 18 + index * 6 + math.sin(index) * 9, y - 66), Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1 })
      end)
      cleanup(wisp, 1.05)
    end
  end
  function effects.rush(x, y, token, def, fromX)
    local direction = (x >= (fromX or x)) and 1 or -1
    for index = 1, 5 do
      local line = frame(layer, 'SpeedLine', WHITE, 2)
      line.ZIndex = 57
      line.BackgroundTransparency = 0.25
      at(line, x - direction * 30, y - 16 + index * 7, 46, 2)
      tween(line, ease(0.35), { Position = UDim2.fromOffset(x - direction * 80 - 23, y - 17 + index * 7), BackgroundTransparency = 1 })
      cleanup(line, 0.4)
    end
    scatter(x, y + 12, 8, 34, function() local d = dot(nil, 'Dust', color(214, 196, 160), 11); d.BackgroundTransparency = 0.25; return d end, 0.7, false)
    tween(token, ease(0.35), { Position = UDim2.fromOffset(x - 24 + direction * 30, y - 24), TextTransparency = 1 })
    cleanup(token, 0.4)
  end
  function effects.wave(x, y, token)
    for index, angle in ipairs({ -24, 20, -20, 16, 0 }) do
      delay((index - 1) * 0.12, function() if token.Parent then tween(token, ease(0.12), { Rotation = angle }) end end)
    end
    delay(0.65, function() if token.Parent then tween(token, ease(0.3), { TextTransparency = 1 }) end end)
    cleanup(token, 1.0)
  end
  function effects.bounce(x, y, token)
    for index, offset in ipairs({ -26, 0, -12, 0 }) do
      delay((index - 1) * 0.13, function()
        if token.Parent then tween(token, ease(0.13, Ease.Quad, offset < 0 and Dir.Out or Dir.In), { Position = UDim2.fromOffset(x - 24, y - 24 + offset) }) end
      end)
    end
    for index = 1, 4 do
      delay(0.08 * index, function() pop(x + math.cos(index * 1.7) * 30, y + math.sin(index * 1.7) * 22, '✨', 13, 0.4) end)
    end
    delay(0.6, function() if token.Parent then tween(token, ease(0.25), { TextTransparency = 1 }) end end)
    cleanup(token, 0.9)
  end

  -- One full throw: launch, flight, impact word, landing effect, mark on target.
  function R.throw(def, fromX, fromY, toX, toY, target)
    return R.fly(def, fromX, fromY, toX, toY, function(token)
      playSound('impact')
      word(toX, toY, def)
      local effect = effects[def.effect] or effects.bounce
      effect(toX, toY, token, def, fromX)
      R.hit(target, def)
    end)
  end

  -- Speech bubble that pops in with a tail and fades out; a newer line
  -- replaces an older one. Returns the bubble.
  local bubbleTokens = {}
  function R.say(bubble, text, x, y, width)
    if not bubble or not text or text == '' then return nil end
    width = width or math.clamp(#text * 6 + 24, 90, 190)
    bubble.Text.Text = text
    bubble.Text.Font = Enum.Font.GothamBold
    bubble.Text.TextTransparency = 0
    bubble.BackgroundTransparency = 0
    bubble.Position = UDim2.fromOffset(x, y)
    bubble.Size = UDim2.fromOffset(width, 26)
    local tail = bubble:FindFirstChild('Tail')
    if not tail then
      tail = frame(bubble, 'Tail', bubble.BackgroundColor3, 2)
      tail.Rotation = 45
      tail.ZIndex = bubble.ZIndex - 1
    end
    tail.BackgroundTransparency = 0
    tail.Size = UDim2.fromOffset(10, 10)
    tail.Position = UDim2.new(0.5, -5, 1, -6)
    bubble.Visible = true
    local scale = bubble:FindFirstChild('PopScale') or make('UIScale', bubble, 'PopScale', { Scale = 1 })
    scale.Scale = 0.6
    tween(scale, ease(0.22, Ease.Back), { Scale = 1 })
    local token = {}
    bubbleTokens[bubble] = token
    delay(2.6, function()
      if bubbleTokens[bubble] ~= token then return end
      tween(bubble, ease(0.3), { BackgroundTransparency = 1 })
      tween(bubble.Text, ease(0.3), { TextTransparency = 1 })
      tween(tail, ease(0.3), { BackgroundTransparency = 1 })
      delay(0.32, function() if bubbleTokens[bubble] == token then bubble.Visible = false end end)
    end)
    return bubble
  end

  return R
end
