-- Happy Tractor client, part 10/14: TableReactions.
-- Lines 4117-4284 of the original single script. Shared values arrive in
-- `C`: ones that change at runtime are read as C.name; fixed ones are
-- copied into locals below.
return function(C)
local Catalog, arenaUI, footer, formatK, notice, remote, root, seats = C.Catalog, C.arenaUI, C.footer, C.formatK, C.notice, C.remote, C.root, C.seats
local selfAvatar, selfBubble = C.selfAvatar, C.selfBubble

-- Animated Table Throwables & Chat Bubble Reaction FX
-- ==========================================================
-- TABLE REACTIONS: definitions, seat geometry, bubbles, throws and bot replies
-- ==========================================================
-- Centre of a seat, relative to the table root (seat 1 is your avatar).
function arenaUI.seatPoint(seat)
  if seat == 1 then
    return footer.Position.X.Offset + selfAvatar.Position.X.Offset + selfAvatar.Size.X.Offset / 2,
      footer.Position.Y.Offset + selfAvatar.Position.Y.Offset + selfAvatar.Size.Y.Offset / 2
  end
  local holder = seats[seat] and seats[seat].holder
  if holder and holder.Position and holder.Size then
    return holder.Position.X.Offset + holder.Size.X.Offset / 2, holder.Position.Y.Offset + holder.Size.Y.Offset / 2
  end
  return root.AbsoluteSize.X / 2, root.AbsoluteSize.Y / 2
end

-- Seats a reaction lands on. 'auto' aims friendly reactions at a teammate and
-- hostile ones at one opponent (the trick leader if it is an opponent).
function arenaUI.resolveTargets(fromSeat, target, id)
  local count = (C.state and C.state.game and C.state.game.playerCount) or 4
  local seatNum = type(target) == 'string' and tonumber(string.match(target, '^seat(%d+)$'))
  if seatNum and seatNum ~= fromSeat and seatNum >= 1 and seatNum <= count then return { seatNum } end
  local def = arenaUI.emoteDefs[id]
  local wantTeam
  if target == 'partner' or target == 'team' then wantTeam = true
  elseif target == 'opponents' then wantTeam = false
  else wantTeam = not def or def.friendly end
  local result = {}
  for seat = 1, count do
    if seat ~= fromSeat and ((seat % 2 == fromSeat % 2) == wantTeam) then table.insert(result, seat) end
  end
  if (target == nil or target == 'auto' or target == 'partner') and #result > 1 then
    local leader = C.state and C.state.game and (C.state.game.winnerSeat or C.state.game.lastWinnerSeat)
    local chosen = result[1]
    for _, seat in ipairs(result) do if seat == leader then chosen = seat end end
    result = { chosen }
  end
  while #result > 5 do table.remove(result) end
  return result
end

-- Speech bubble above a seat, kept on screen.
function arenaUI.showBubble(seat, text)
  local bubble = seat == 1 and selfBubble or (seats[seat] and seats[seat].bubble)
  if not bubble or not text or text == '' then return end
  local width = math.clamp(#text * 6 + 24, 90, 190)
  if seat == 1 then
    arenaUI.R.say(bubble, text, 28, -32, width)
    return
  end
  local holder = seats[seat].holder
  local hx, hw = holder.Position.X.Offset, holder.Size.X.Offset
  local bx = (hw - width) / 2
  local rootW = root.AbsoluteSize.X
  if hx + bx + width > rootW - 4 then bx = rootW - 4 - width - hx end
  if hx + bx < 4 then bx = 4 - hx end
  arenaUI.R.say(bubble, text, bx, -34, width)
end

-- Throws one reaction between seats; the module animates flight and landing.
function arenaUI.throwReaction(fromSeat, toSeat, def)
  local startX, startY = arenaUI.seatPoint(fromSeat)
  local targetX, targetY = arenaUI.seatPoint(toSeat)
  local target = toSeat == 1 and selfAvatar or (seats[toSeat] and seats[toSeat].holder)
  -- Land just inside the seat, toward the table, so the burst plays over the
  -- felt instead of being cut off at the screen edge.
  local centreX, centreY = root.AbsoluteSize.X / 2, root.AbsoluteSize.Y * 0.42
  local dx, dy = centreX - targetX, centreY - targetY
  local distance = math.sqrt(dx * dx + dy * dy)
  if distance > 1 then
    local pull = math.min(70, distance * 0.35)
    targetX, targetY = targetX + dx / distance * pull, targetY + dy / distance * pull
  end
  return arenaUI.R.throw(def, startX, startY, targetX, targetY, target)
end

-- Plays a chat line or a reaction from a seat. Returns the seats it targets.
function arenaUI.react(fromSeat, kind, id, text, target)
  if C.muted then return {} end
  if kind == 'chat' then
    arenaUI.showBubble(fromSeat, text)
    return {}
  end
  local def = arenaUI.emoteDefs[id]
  if not def then return {} end
  arenaUI.showBubble(fromSeat, def.line)
  local targets = arenaUI.resolveTargets(fromSeat, target, id)
  for index, seat in ipairs(targets) do
    if index == 1 then arenaUI.throwReaction(fromSeat, seat, def)
    else task.delay((index - 1) * 0.08, function() arenaUI.throwReaction(fromSeat, seat, def) end) end
  end
  return targets
end

-- Bots sometimes answer a reaction aimed at them: teammates cheer back,
-- opponents wave off a kind gesture or return fire. `roll` is for tests.
function arenaUI.botReply(seat, id, roll)
  local def = arenaUI.emoteDefs[id]
  if not seat or seat == 1 or not def or not seats[seat] then return nil end
  roll = roll or math.random()
  if roll > 0.6 then return nil end
  local teammate = seat % 2 == 1
  local reply
  if def.friendly then reply = teammate and 'cheer' or (roll < 0.3 and 'laugh' or 'wave')
  elseif teammate then reply = 'line:Hey! Same team!'
  else reply = roll < 0.35 and 'tomato' or 'line:Is that all you’ve got?' end
  task.delay(1.1, function()
    if not C.state or not C.state.game then return end
    if string.sub(reply, 1, 5) == 'line:' then arenaUI.react(seat, 'chat', nil, string.sub(reply, 6))
    else arenaUI.react(seat, 'emote', reply, nil, 'seat1') end
  end)
  return reply
end

-- Sends your reaction: plays it immediately, then the server broadcasts it
-- (our own echo is skipped). Locked reactions offer to unlock instead.
function arenaUI.sendReaction(kind, id, target)
  if not C.state then return end
  if os.clock() < (arenaUI.reactionReadyAt or 0) then
    notice.Text = 'Reactions are cooling down…'
    return
  end
  local text
  if kind == 'chat' then
    for _, entry in ipairs(Catalog.phrases or {}) do if entry.id == id then text = entry.text end end
    if not text then return end
  else
    if not arenaUI.emoteDefs[id] then return end
    if not (C.state.owned and C.state.owned[id]) then
      local price
      for _, item in ipairs(Catalog) do if item.id == id then price = item.price end end
      if price and (C.state.coins or 0) >= price then
        remote:FireServer('buy', id)
        notice.Text = 'Unlocking ' .. arenaUI.emoteDefs[id].name .. ' for ' .. formatK(price) .. ' coins…'
      else
        notice.Text = arenaUI.emoteDefs[id].name .. ' unlocks for ' .. formatK(price or 0) .. ' coins.'
      end
      return
    end
  end
  arenaUI.reactionReadyAt = os.clock() + arenaUI.REACTION_COOLDOWN
  remote:FireServer(kind == 'chat' and 'chat' or 'emote', { id = id, target = target or 'auto' })
  if arenaUI.startCooldownBar then arenaUI.startCooldownBar(arenaUI.REACTION_COOLDOWN) end
  local targets = arenaUI.react(1, kind, id, text, target)
  if kind == 'emote' and targets[1] then arenaUI.botReply(targets[1], id) end
  if C.state.quests and C.state.quests.emote then
    C.state.quests.emote.progress = math.min(C.state.quests.emote.target, C.state.quests.emote.progress + 1)
  end
  if arenaUI.refreshDock then
    arenaUI.refreshDock()
    task.delay(arenaUI.REACTION_COOLDOWN + 0.05, arenaUI.refreshDock)
  end
end

-- Older callers pass a sender name and free text; map them onto seats.
C.triggerEmoteReaction = function(senderName, emoteText, targetMode)
  local fromSeat = 1
  if senderName == 'Partner' then fromSeat = 3 end
  for seat = 2, 10 do
    if seats[seat] and seats[seat].name.Text == senderName then fromSeat = seat end
  end
  for id, def in pairs(arenaUI.emoteDefs) do
    if emoteText == id or emoteText == def.name then return arenaUI.react(fromSeat, 'emote', id, nil, targetMode) end
  end
  return arenaUI.react(fromSeat, 'chat', nil, emoteText)
end
end
