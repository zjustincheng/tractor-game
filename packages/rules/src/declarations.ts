import { cardIdentity, createDeck, gameConfig } from './cards.js';
import type { Card, PlayerCount, Rank, Suit } from './cards.js';

export type Declaration =
  | {
      readonly kind: 'suit';
      readonly playerSeat: number;
      readonly level: Rank;
      readonly suit: Suit;
      readonly multiplicity: number;
      readonly cardIds: readonly string[];
    }
  | {
      readonly kind: 'joker';
      readonly playerSeat: number;
      readonly level: Rank;
      readonly joker: 'small' | 'big' | 'mixed';
      readonly multiplicity: number;
      readonly cardIds: readonly string[];
    };

export function declarationRank(declaration: Declaration): number {
  return declaration.kind === 'joker'
    ? 100 + declaration.multiplicity
    : declaration.multiplicity;
}

function cardsForRank(hand: readonly Card[], level: Rank): Card[] {
  return hand.filter((card) => card.kind === 'suited' && card.rank === level);
}

function jokerCards(hand: readonly Card[], joker?: 'small' | 'big'): Card[] {
  return hand.filter(
    (card) => card.kind === 'joker' && (!joker || card.joker === joker),
  );
}

export function declarationsForHand(
  hand: readonly Card[],
  playerCount: PlayerCount,
  level: Rank,
  playerSeat: number,
): Declaration[] {
  const levelCards = cardsForRank(hand, level);
  const result: Declaration[] = [];
  for (const suit of ['clubs', 'diamonds', 'hearts', 'spades'] as const) {
    const cards = levelCards.filter(
      (card) => card.kind === 'suited' && card.suit === suit,
    );
    for (let multiplicity = 1; multiplicity <= cards.length; multiplicity++)
      result.push({
        kind: 'suit',
        playerSeat,
        level,
        suit,
        multiplicity,
        cardIds: cards.slice(0, multiplicity).map((card) => card.id),
      });
  }
  const jokerMinimum = playerCount === 4 ? 3 : 4;
  for (const joker of ['small', 'big'] as const) {
    const cards = jokerCards(hand, joker);
    if (cards.length >= (playerCount === 4 ? 3 : 3)) {
      const max = Math.min(cards.length, jokerMinimum);
      for (let multiplicity = 3; multiplicity <= max; multiplicity++)
        result.push({
          kind: 'joker',
          playerSeat,
          level,
          joker,
          multiplicity,
          cardIds: cards.slice(0, multiplicity).map((card) => card.id),
        });
    }
  }
  const mixedMinimum = playerCount === 4 ? 3 : 4;
  const allJokers = hand.filter(
    (card): card is Extract<Card, { kind: 'joker' }> => card.kind === 'joker',
  );
  if (
    allJokers.length >= mixedMinimum &&
    allJokers.some((card) => card.joker === 'small') &&
    allJokers.some((card) => card.joker === 'big')
  ) {
    result.push({
      kind: 'joker',
      playerSeat,
      level,
      joker: 'mixed',
      multiplicity: mixedMinimum,
      cardIds: allJokers.slice(0, mixedMinimum).map((card) => card.id),
    });
  }
  return result;
}

export function validateDeclaration(
  declaration: Declaration,
  hand: readonly Card[],
  playerCount: PlayerCount,
  expectedLevel: Rank,
): boolean {
  if (
    declaration.level !== expectedLevel ||
    declaration.playerSeat < 0 ||
    declaration.playerSeat >= playerCount ||
    new Set(declaration.cardIds).size !== declaration.cardIds.length
  )
    return false;
  const byId = new Map(hand.map((card) => [card.id, card]));
  const selected = declaration.cardIds.map((id) => byId.get(id));
  if (selected.some((card) => !card)) return false;
  const actual = selected as Card[];
  if (declaration.kind === 'suit')
    return (
      declaration.multiplicity === actual.length &&
      actual.every(
        (card) =>
          card.kind === 'suited' &&
          card.rank === expectedLevel &&
          card.suit === declaration.suit,
      )
    );
  if (actual.length !== declaration.multiplicity) return false;
  if (declaration.joker === 'mixed')
    return actual.every((card) => card.kind === 'joker');
  return actual.every(
    (card) => card.kind === 'joker' && card.joker === declaration.joker,
  );
}

export function canOverturn(
  current: Declaration,
  challenger: Declaration,
  firstRound = false,
): boolean {
  if (challenger.kind === 'joker' && current.kind === 'suit') return true;
  if (challenger.kind === 'suit' && current.kind === 'joker') return false;
  if (current.kind === 'suit' && challenger.kind === 'suit')
    return (
      challenger.level === current.level &&
      challenger.multiplicity > current.multiplicity
    );
  if (current.kind === 'joker' && challenger.kind === 'joker') {
    if (current.joker === 'small' && challenger.joker === 'big' && firstRound)
      return challenger.multiplicity >= current.multiplicity;
    return false;
  }
  return false;
}

export function chooseRandomFallback(
  hands: readonly (readonly Card[])[],
  playerCount: PlayerCount,
  level: Rank,
  pickIndex: (exclusiveMaximum: number) => number,
): Declaration {
  const eligible = hands.flatMap((hand, playerSeat) =>
    declarationsForHand(hand, playerCount, level, playerSeat).filter(
      (declaration) => declaration.kind === 'suit',
    ),
  );
  if (!eligible.length)
    throw new Error('No eligible declaration exists for fallback.');
  const index = pickIndex(eligible.length);
  if (!Number.isInteger(index) || index < 0 || index >= eligible.length)
    throw new RangeError('Invalid fallback choice.');
  return eligible[index]!;
}

export function declarationCardCount(declaration: Declaration): number {
  return declaration.cardIds.length;
}

export function verifyDeclarationDeck(playerCount: PlayerCount): boolean {
  const cards = createDeck(playerCount);
  const identities = new Set(cards.map(cardIdentity));
  return (
    identities.size > 0 && cards.length === gameConfig(playerCount).cardCount
  );
}
