-- Shared geometry for the native UI and deterministic viewport checks.
local Layout = {}
function Layout.calculate(width, height, count)
  local compact = width < 600
  local short = height < 500
  local cardHeight = short and 72 or (compact and math.max(82, math.min(104, math.floor(height * 0.13))) or math.max(82, math.min(148, math.floor(height * 0.20))))
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
  local actionY = handY - 76
  local top = short and 52 or (compact and 96 or 76)
  return { width = width, height = height, compact = compact, short = short, cardWidth = cardWidth,
    cardHeight = cardHeight, rows = rows, columns = columns, step = step,
    contentWidth = contentWidth, handHeight = handHeight, handY = handY,
    actionY = actionY, arenaY = top, arenaHeight = math.max(70, actionY - top - 8) }
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
