-- Pure port of packages/rules/src/cards.ts. No platform services or randomness.
local Cards = {}
Cards.ranks = { '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', 'A' }
Cards.suits = { 'clubs', 'diamonds', 'hearts', 'spades' }
function Cards.config(playerCount)
  assert(playerCount == 4 or playerCount == 6 or playerCount == 8 or playerCount == 10, 'Choose 4, 6, 8 or 10 players.')
  local decks = playerCount / 2
  local kittySize = playerCount == 4 and 8 or playerCount
  return { playerCount=playerCount, decks=decks, kittySize=kittySize,
    handSize=(decks*54-kittySize)/playerCount, cardCount=decks*54, interval=decks*20, swapThreshold=decks*40 }
end
function Cards.team(seat) return seat % 2 == 1 and 'A' or 'B' end
function Cards.deck(playerCount)
  local cards = {}
  for copy = 0, Cards.config(playerCount or 4).decks-1 do
    for _, suit in ipairs(Cards.suits) do
      for _, rank in ipairs(Cards.ranks) do
        table.insert(cards, { id = copy .. ':' .. suit .. ':' .. rank, suit = suit, rank = rank })
      end
    end
    for _, joker in ipairs({ 'small', 'big' }) do
      table.insert(cards, { id = copy .. ':joker:' .. joker, joker = joker })
    end
  end
  return cards
end
function Cards.category(card, trump)
  if card.joker or card.rank == trump.level or card.suit == trump.suit then return 'trump' end
  return card.suit
end
function Cards.power(card, trump)
  if card.joker then
    if trump.suit == nil then return card.joker == 'big' and 2 or 1 end
    return card.joker == 'big' and 15 or 14
  end
  if card.rank == trump.level then
    if trump.suit == nil then return 0 end
    return card.suit == trump.suit and 13 or 12
  end
  local power = 0
  for _, rank in ipairs(Cards.ranks) do
    if rank ~= trump.level then
      if card.rank == rank then return power end
      power = power + 1
    end
  end
  error('Invalid card')
end
function Cards.points(card)
  if card.rank == '5' then return 5 end
  if card.rank == '10' or card.rank == 'K' then return 10 end
  return 0
end
function Cards.label(card)
  if card.joker then return card.joker == 'big' and 'BIG JOKER' or 'SMALL JOKER' end
  return card.rank .. ' ' .. card.suit
end
function Cards.legal(hand, card, lead, trump)
  if not lead then return true end
  local required = Cards.category(lead, trump)
  if Cards.category(card, trump) == required then return true end
  for _, held in ipairs(hand) do
    if Cards.category(held, trump) == required then return false end
  end
  return true
end
function Cards.beats(card, winner, trump)
  local category, previous = Cards.category(card, trump), Cards.category(winner, trump)
  if category == previous then return Cards.power(card, trump) > Cards.power(winner, trump) end
  return category == 'trump'
end
return Cards
