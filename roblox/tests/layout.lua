local Layout = dofile('roblox/src/shared/TableLayout.luau')
for _, viewport in ipairs({ {1440, 900}, {1280, 720}, {1024, 768}, {390, 844}, {375, 667}, {844, 390}, {760, 310}, {740, 300} }) do
  for _, count in ipairs({0, 1, 25, 26, 33, 36}) do
    local l = Layout.calculate(viewport[1], viewport[2], count)
    assert(l.actionY > l.arenaY and l.handY > l.actionY)
    for i = 1, count do
      local p = Layout.card(l, i, count)
      assert(p.x >= 0 and p.x + l.cardWidth <= l.contentWidth + 0.01)
      assert(p.y - 18 >= 0 and p.y + l.cardHeight <= l.handHeight)
      assert(l.handY + p.y + l.cardHeight < viewport[2] - 34)
      -- Landscape phones use a slimmer button row (Layout.luau places it at actionY + 24).
      assert(l.actionY + (l.short and 24 or 43) + 38 <= l.handY + p.y - 18)
    end
    if l.compact then assert(l.contentWidth <= viewport[1] - 32 + 0.01) end
  end
end
-- Landscape phones with 6+ players: side columns hold every other seat and
-- every seat gets its own slot in the row of plays.
for _, count in ipairs({6, 8, 10}) do
  local sides = Layout.sideSeats(count)
  assert(#sides.left + #sides.right == count - 1)
  local slots = {}
  for seat = 1, count do assert(sides.slot[seat] and not slots[sides.slot[seat]]); slots[sides.slot[seat]] = true end
end
print('PASS: hand bounds and raised selections at desktop, tablet, portrait, landscape and phone sizes; phone seat columns')
