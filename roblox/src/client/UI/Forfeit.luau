-- Happy Tractor client: Concede button.
-- A small button in the footer (left of AUTO) while tricks are being played.
-- The first tap arms it ("SURE?"), a second tap within 4 seconds concedes the
-- round for your team. With a human partner, both must press it.
return function(C)
local footer, button, palette, rect, handHint = C.footer, C.button, C.palette, C.rect, C.handHint
if not (footer and button and rect and C.command) then return end

local armedUntil = 0
local concede
local function label()
  concede.Text = os.clock() < armedUntil and 'SURE?' or 'CONCEDE'
  concede.TextColor3 = os.clock() < armedUntil and palette.red or palette.muted
end
concede = button(footer, 'Concede', 'CONCEDE', function()
  if os.clock() < armedUntil then
    armedUntil = 0
    C.command('forfeit')
  else
    armedUntil = os.clock() + 4
    task.delay(4.1, function() if concede.Parent then label() end end)
  end
  label()
end, palette.panelLight)
concede.TextSize = 10
concede.Visible = false
label()

local function refresh()
  local game = C.state and C.state.game
  local playing = game ~= nil and not game.done and (game.phase == 'tricks' or game.phase == 'trick-review')
  concede.Visible = playing
  if not playing then armedUntil = 0; label() end
  local w = C.currentLayout and C.currentLayout.width
  if w then
    rect(concede, w - 262, 3, 74, 24)
    -- Keep the hint text clear of the extra button.
    if playing and handHint then
      local x = handHint.Position.X.Offset
      handHint.Size = UDim2.fromOffset(math.max(40, (w - 270) - x), handHint.Size.Y.Offset)
    end
  end
end

local baseRender = C.render
C.render = function(...)
  baseRender(...)
  refresh()
end
local baseResize = C.resize
C.resize = function(...)
  baseResize(...)
  refresh()
end
refresh()
end
