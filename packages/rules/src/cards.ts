export const PLAYER_COUNTS = [4, 6, 8, 10] as const;
export const SUITS = ['clubs', 'diamonds', 'hearts', 'spades'] as const;
export const RANKS = [
  '2',
  '3',
  '4',
  '5',
  '6',
  '7',
  '8',
  '9',
  '10',
  'J',
  'Q',
  'K',
  'A',
] as const;
export const RULES_VERSION = '2.1-clarified.1';

export type PlayerCount = (typeof PLAYER_COUNTS)[number];
export type Suit = (typeof SUITS)[number];
export type Rank = (typeof RANKS)[number];
export type Team = 'A' | 'B';
export type Card =
  | {
      readonly id: string;
      readonly kind: 'suited';
      readonly suit: Suit;
      readonly rank: Rank;
    }
  | {
      readonly id: string;
      readonly kind: 'joker';
      readonly joker: 'small' | 'big';
    };
export type Trump = { readonly level: Rank; readonly suit: Suit | null };
export type Category = Suit | 'trump';

export function gameConfig(playerCount: number) {
  if (!PLAYER_COUNTS.includes(playerCount as PlayerCount)) {
    throw new RangeError('Player count must be 4, 6, 8, or 10.');
  }
  const decks = playerCount / 2;
  const kittySize = playerCount === 4 ? 8 : playerCount;
  return {
    playerCount: playerCount as PlayerCount,
    decks,
    cardCount: decks * 54,
    kittySize,
    handSize: (decks * 54 - kittySize) / playerCount,
    basePoints: decks * 100,
    interval: decks * 20,
    swapThreshold: decks * 40,
  };
}

export function createDeck(playerCount: PlayerCount): Card[] {
  const cards: Card[] = [];
  for (let deck = 0; deck < gameConfig(playerCount).decks; deck++) {
    for (const suit of SUITS) {
      for (const rank of RANKS) {
        cards.push({
          id: `${deck}:${suit}:${rank}`,
          kind: 'suited',
          suit,
          rank,
        });
      }
    }
    for (const joker of ['small', 'big'] as const) {
      cards.push({ id: `${deck}:joker:${joker}`, kind: 'joker', joker });
    }
  }
  return cards;
}

export function cardIdentity(card: Card): string {
  return card.kind === 'joker'
    ? `joker:${card.joker}`
    : `${card.suit}:${card.rank}`;
}

export function cardPoints(card: Card): number {
  if (card.kind === 'joker') return 0;
  return card.rank === '5'
    ? 5
    : card.rank === '10' || card.rank === 'K'
      ? 10
      : 0;
}

export function category(card: Card, trump: Trump): Category {
  if (
    card.kind === 'joker' ||
    card.rank === trump.level ||
    card.suit === trump.suit
  )
    return 'trump';
  return card.suit;
}

/** Power is meaningful only within an effective category, never across plain suits. */
export function effectivePower(card: Card, trump: Trump): number {
  if (trump.suit === null) {
    if (card.kind === 'joker') return card.joker === 'big' ? 2 : 1;
    if (card.rank === trump.level) return 0;
  } else {
    if (card.kind === 'joker') return card.joker === 'big' ? 15 : 14;
    if (card.rank === trump.level) return card.suit === trump.suit ? 13 : 12;
  }
  // Removing the level closes the gap: e.g. 4 and 6 are adjacent at level 5.
  return RANKS.filter((rank) => rank !== trump.level).indexOf(card.rank);
}

export function teamAt(seat: number): Team {
  if (!Number.isSafeInteger(seat) || seat < 0)
    throw new RangeError('Invalid seat.');
  return seat % 2 === 0 ? 'A' : 'B';
}

/** Seat indices increase counterclockwise. */
export function nextSeat(
  seat: number,
  playerCount: PlayerCount,
  distance = 1,
): number {
  gameConfig(playerCount);
  if (
    !Number.isSafeInteger(seat) ||
    seat < 0 ||
    seat >= playerCount ||
    !Number.isSafeInteger(distance) ||
    distance < 0
  ) {
    throw new RangeError('Invalid seat or distance.');
  }
  return (seat + distance) % playerCount;
}

export function nextDealer(
  seat: number,
  playerCount: PlayerCount,
  swapRoles: boolean,
): number {
  return nextSeat(seat, playerCount, swapRoles ? 1 : 2);
}

/** Inject integer choices for repeatable tests; production supplies crypto.randomInt. */
export function shuffle<T>(
  items: readonly T[],
  pickIndex: (exclusiveMaximum: number) => number,
): T[] {
  const copy = [...items];
  for (let index = copy.length - 1; index > 0; index--) {
    const chosen = pickIndex(index + 1);
    if (!Number.isInteger(chosen) || chosen < 0 || chosen > index)
      throw new RangeError('Invalid shuffle choice.');
    [copy[index], copy[chosen]] = [copy[chosen]!, copy[index]!];
  }
  return copy;
}

/** Pure partition of a previously shuffled shoe. The bottom remains private. */
export function deal(
  cards: readonly Card[],
  playerCount: PlayerCount,
  firstSeat = 0,
) {
  const config = gameConfig(playerCount);
  nextSeat(firstSeat, playerCount, 0);
  if (
    cards.length !== config.cardCount ||
    new Set(cards.map((card) => card.id)).size !== cards.length
  ) {
    throw new Error(
      'Deal requires a complete shoe with unique physical cards.',
    );
  }
  const hands: Card[][] = Array.from({ length: playerCount }, () => []);
  const dealtCount = cards.length - config.kittySize;
  cards.slice(0, dealtCount).forEach((card, index) => {
    hands[(firstSeat + index) % playerCount]!.push(card);
  });
  return { hands, kitty: cards.slice(dealtCount) };
}
