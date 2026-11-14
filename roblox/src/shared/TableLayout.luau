-- Shared geometry for the native UI and deterministic viewport checks.
local Layout = {}
function Layout.calculate(width, height, count)
  local compact = width < 600
  local short = height < 500
  -- Landscape phones lose height to Roblox's top bar and the home indicator,
  -- so the hand shrinks a little on the shortest screens.
  local cardHeight = short and math.max(54, math.min(72, math.floor(height * 0.2))) or (compact and math.max(82, math.min(104, math.floor(height * 0.13))) or math.max(82, math.min(148, math.floor(height * 0.20))))
  local cardWidth = math.floor(cardHeight * 0.65)
  local available = width - 32
  local minimumStep = compact and 26 or 29
  local capacity = math.max(1, math.floor((available - cardWidth) / minimumStep) + 1)
  local rows = (compact and height >= 600) and math.max(1, math.ceil(count / capacity)) or 1
  local columns = math.max(1, math.ceil(count / rows))
  local step = columns > 1 and math.max(minimumStep, math.min(53, (available - cardWidth) / (columns - 1))) or 0
  local contentWidth = math.max(available, cardWidth + (columns - 1) * step)
  local handHeight = rows * (cardHeight + 8) + 24
  local footer = 38
  local handY = height - footer - handHeight
  -- Leaves room for a raised (selected) card under the Play/Clear buttons;
  -- short screens use a slimmer button row so the table keeps its height.
  local actionY = handY - (short and 60 or 88)
  local top = short and 52 or (compact and 96 or 76)
  return { width = width, height = height, compact = compact, short = short, cardWidth = cardWidth,
    cardHeight = cardHeight, rows = rows, columns = columns, step = step,
    contentWidth = contentWidth, handHeight = handHeight, handY = handY,
    actionY = actionY, arenaY = top, arenaHeight = math.max(70, actionY - top - 8) }
end
-- Landscape phones with more than four players: the other seats sit in two
-- side columns (upper seats first) and the plays form one row, ordered left
-- to right by where each seat sits around the table.
function Layout.sideSeats(count)
  local left, right, order = {}, {}, {}
  for seat = 1, count do
    local angle = math.pi / 2 - (seat - 1) * 2 * math.pi / count
    local entry = { seat = seat, x = math.cos(angle), y = math.sin(angle) }
    if seat ~= 1 then table.insert(entry.x < -0.01 and left or right, entry) end
    table.insert(order, entry)
  end
  local function byHeight(a, b) return a.y < b.y end
  table.sort(left, byHeight)
  table.sort(right, byHeight)
  table.sort(order, function(a, b)
    if math.abs(a.x - b.x) > 0.01 then return a.x < b.x end
    return a.y > b.y
  end)
  local result = { left = {}, right = {}, slot = {} }
  for i, entry in ipairs(left) do result.left[i] = entry.seat end
  for i, entry in ipairs(right) do result.right[i] = entry.seat end
  for i, entry in ipairs(order) do result.slot[entry.seat] = i end
  return result
end
function Layout.card(layout, index, count)
  local row = math.floor((index - 1) / layout.columns)
  local column = (index - 1) % layout.columns
  local inRow = math.min(layout.columns, count - row * layout.columns)
  local rowWidth = layout.cardWidth + (inRow - 1) * layout.step
  return { x = (layout.contentWidth - rowWidth) / 2 + column * layout.step,
    y = 24 + row * (layout.cardHeight + 8) }
end
return Layout
