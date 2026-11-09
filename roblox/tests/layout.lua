local Layout = dofile('roblox/src/shared/TableLayout.luau')
for _, viewport in ipairs({ {1440, 900}, {1280, 720}, {1024, 768}, {390, 844}, {375, 667}, {844, 390} }) do
  for _, count in ipairs({0, 1, 25, 26, 33, 36}) do
    local l = Layout.calculate(viewport[1], viewport[2], count)
    assert(l.actionY > l.arenaY and l.handY > l.actionY)
    for i = 1, count do
      local p = Layout.card(l, i, count)
      assert(p.x >= 0 and p.x + l.cardWidth <= l.contentWidth + 0.01)
      assert(p.y - 18 >= 0 and p.y + l.cardHeight <= l.handHeight)
      assert(l.handY + p.y + l.cardHeight < viewport[2] - 34)
      assert(l.actionY + 43 + 38 <= l.handY + p.y - 18)
    end
    if l.compact then assert(l.contentWidth <= viewport[1] - 32 + 0.01) end
  end
end
print('PASS: hand bounds and raised selections at desktop, tablet, portrait and landscape sizes')
