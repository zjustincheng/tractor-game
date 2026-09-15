import { describe, expect, it } from 'vitest';
import {
  advanceLevel,
  beatsHomogeneous,
  cardIdentity,
  cardPoints,
  category,
  createDeck,
  deal,
  effectivePower,
  gamblePenalty,
  gameConfig,
  homogeneousStructure,
  nextDealer,
  nextSeat,
  PLAYER_COUNTS,
  RANKS,
  scoreOutcome,
  shuffle,
  SUITS,
  teamAt,
} from './index.js';
import type { Card, Rank, Suit, Trump } from './index.js';

function copies(rank: Rank, suit: Suit, count = 2): Card[] {
  return Array.from({ length: count }, (_, index) => ({
    id: `${index}:${suit}:${rank}`,
    kind: 'suited',
    rank,
    suit,
  }));
}
function jokers(joker: 'small' | 'big', count = 2): Card[] {
  return Array.from({ length: count }, (_, index) => ({
    id: `${index}:joker:${joker}`,
    kind: 'joker',
    joker,
  }));
}
const spadeFive: Trump = { level: '5', suit: 'spades' };

describe.each(PLAYER_COUNTS)(
  '%i-player deck and seating (spec 1, 3, 8, 12; D1, D2)',
  (players) => {
    it('contains exactly the physical cards, point total, hand sizes, and kitty required', () => {
      const deck = createDeck(players);
      const config = gameConfig(players);
      expect(deck).toHaveLength((players / 2) * 54);
      expect(new Set(deck.map((card) => card.id)).size).toBe(deck.length);
      expect(deck.reduce((sum, card) => sum + cardPoints(card), 0)).toBe(
        (players / 2) * 100,
      );
      for (const identity of new Set(deck.map(cardIdentity))) {
        expect(
          deck.filter((card) => cardIdentity(card) === identity),
        ).toHaveLength(players / 2);
      }
      const { hands, kitty } = deal(deck, players, players - 1);
      expect(kitty).toHaveLength(players === 4 ? 8 : players);
      expect(hands.every((hand) => hand.length === config.handSize)).toBe(true);
      expect(hands[players - 1]![0]).toEqual(deck[0]);
      expect(hands[0]![0]).toEqual(deck[1]);
      expect(
        new Set([...hands.flat(), ...kitty].map((card) => card.id)).size,
      ).toBe(deck.length);
      expect(kitty).toEqual(deck.slice(-config.kittySize));
    });
    it('rotates counterclockwise and selects the winning team’s next dealer', () => {
      for (let seat = 0; seat < players; seat++) {
        expect(teamAt(nextSeat(seat, players))).not.toBe(teamAt(seat));
        expect(teamAt(nextDealer(seat, players, false))).toBe(teamAt(seat));
        expect(teamAt(nextDealer(seat, players, true))).not.toBe(teamAt(seat));
      }
      expect(nextSeat(players - 1, players)).toBe(0);
      expect(nextDealer(players - 2, players, false)).toBe(0);
    });
  },
);

describe('pure dealing and shuffle', () => {
  it('replays injected choices without mutating or losing cards', () => {
    const cards = createDeck(4);
    const original = [...cards];
    expect(shuffle(cards, () => 0)).toEqual(shuffle(cards, () => 0));
    expect(shuffle(cards, () => 0)).not.toEqual(cards);
    expect(new Set(shuffle(cards, () => 0))).toEqual(new Set(cards));
    expect(cards).toEqual(original);
    expect(() => shuffle(cards, (maximum) => maximum)).toThrow();
  });
  it('rejects unsupported counts, duplicate cards, incomplete shoes, and invalid seats', () => {
    expect(() => gameConfig(5)).toThrow();
    const deck = createDeck(4);
    expect(() => deal(deck.slice(1), 4)).toThrow();
    expect(() => deal([deck[1]!, ...deck.slice(1)], 4)).toThrow();
    expect(() => deal(deck, 4, -1)).toThrow();
    expect(() => nextSeat(4, 4)).toThrow();
  });
});

describe.each(RANKS)(
  'effective hierarchy at level %s (spec 5–6; D7)',
  (level) => {
    it.each([...SUITS, null])(
      'has consecutive powers within every category for trump %s',
      (suit) => {
        const trump = { level, suit };
        const deck = createDeck(4);
        for (const group of ['trump', ...SUITS] as const) {
          const powers = [
            ...new Set(
              deck
                .filter((card) => category(card, trump) === group)
                .map((card) => effectivePower(card, trump)),
            ),
          ].sort((a, b) => a - b);
          for (let index = 1; index < powers.length; index++)
            expect(powers[index]! - powers[index - 1]!).toBe(1);
        }
        for (const printedSuit of SUITS)
          expect(category(copies(level, printedSuit, 1)[0]!, trump)).toBe(
            'trump',
          );
        expect(effectivePower(jokers('big')[0]!, trump)).toBeGreaterThan(
          effectivePower(jokers('small')[0]!, trump),
        );
      },
    );
  },
);

describe('homogeneous structures (spec 5.4, 8.3, 9.1, 10; D7)', () => {
  it.each([
    [...copies('5', 'spades'), ...jokers('small')],
    [...copies('5', 'hearts'), ...copies('A', 'spades')],
    [...copies('4', 'hearts'), ...copies('6', 'hearts')],
  ])('accepts the supplied effective-adjacency example %#', (...cards) => {
    expect(homogeneousStructure(cards, spadeFive)).toMatchObject({
      multiplicity: 2,
      rankCount: 2,
      cardCount: 4,
    });
  });
  it('rejects equal-power levels as either a mixed pair or consecutive sets', () => {
    expect(
      homogeneousStructure(
        [...copies('5', 'clubs'), ...copies('5', 'hearts')],
        spadeFive,
      ),
    ).toBeNull();
    expect(
      homogeneousStructure(
        [...copies('5', 'clubs', 1), ...copies('5', 'hearts', 1)],
        spadeFive,
      ),
    ).toBeNull();
    expect(
      homogeneousStructure(copies('5', 'hearts'), spadeFive),
    ).toMatchObject({ multiplicity: 2 });
  });
  it('does not wrap, combine suits, treat singles as tractors, or reuse a physical card', () => {
    const card = copies('3', 'clubs', 1)[0]!;
    for (const cards of [
      [],
      [card, card],
      [...copies('A', 'hearts'), ...copies('2', 'hearts')],
      [...copies('3', 'clubs'), ...copies('4', 'hearts')],
      [...copies('3', 'clubs', 1), ...copies('4', 'clubs', 1)],
    ]) {
      expect(homogeneousStructure(cards, spadeFive)).toBeNull();
    }
  });
  it('recognizes sets and tractors up to five copies', () => {
    for (let multiplicity = 1; multiplicity <= 5; multiplicity++) {
      expect(
        homogeneousStructure(copies('7', 'clubs', multiplicity), spadeFive),
      ).toMatchObject({ multiplicity, rankCount: 1 });
      if (multiplicity > 1)
        expect(
          homogeneousStructure(
            [
              ...copies('7', 'clubs', multiplicity),
              ...copies('8', 'clubs', multiplicity),
            ],
            spadeFive,
          ),
        ).toMatchObject({ multiplicity, rankCount: 2 });
    }
  });
  it('recognizes off-suit/main Jack tractors, but not off-suit/off-suit Jack tractors', () => {
    const trump = { level: 'J', suit: 'spades' } as const;
    expect(
      homogeneousStructure(
        [...copies('J', 'hearts'), ...copies('J', 'spades')],
        trump,
      ),
    ).not.toBeNull();
    expect(
      homogeneousStructure(
        [...copies('J', 'hearts'), ...copies('J', 'clubs')],
        trump,
      ),
    ).toBeNull();
  });
  it('matches the complete structure before considering trump or strength; ties do not replace winners', () => {
    const structure = (cards: Card[]) =>
      homogeneousStructure(cards, spadeFive)!;
    const lead = structure([...copies('7', 'clubs'), ...copies('8', 'clubs')]);
    expect(
      beatsHomogeneous(
        structure([...copies('8', 'clubs'), ...copies('9', 'clubs')]),
        lead,
      ),
    ).toBe(true);
    expect(
      beatsHomogeneous(
        structure([...copies('8', 'hearts'), ...copies('9', 'hearts')]),
        lead,
      ),
    ).toBe(false);
    expect(
      beatsHomogeneous(
        structure([...copies('3', 'spades'), ...copies('4', 'spades')]),
        lead,
      ),
    ).toBe(true);
    expect(beatsHomogeneous(structure(jokers('big', 4)), lead)).toBe(false);
    expect(
      beatsHomogeneous(
        structure([...copies('7', 'spades', 3), ...copies('8', 'spades', 3)]),
        structure([
          ...copies('6', 'clubs'),
          ...copies('7', 'clubs'),
          ...copies('8', 'clubs'),
        ]),
      ),
    ).toBe(false);
    expect(beatsHomogeneous(lead, lead)).toBe(false);
  });
});

describe.each(PLAYER_COUNTS)(
  '%i-player score boundaries (D4, D5)',
  (players) => {
    it('covers both sides of every checkpoint including beyond nominal totals', () => {
      const { interval } = gameConfig(players);
      expect(scoreOutcome(players, -20)).toEqual({
        advancingRole: 'attackers',
        levels: 3,
        swapRoles: false,
      });
      expect(scoreOutcome(players, 0).levels).toBe(3);
      expect(scoreOutcome(players, 1).levels).toBe(2);
      expect(scoreOutcome(players, interval - 1).levels).toBe(2);
      expect(scoreOutcome(players, interval).levels).toBe(1);
      expect(scoreOutcome(players, interval * 2 - 1).swapRoles).toBe(false);
      for (let checkpoint = 2; checkpoint <= 10; checkpoint++) {
        for (const offset of [0, 1, interval - 1]) {
          expect(scoreOutcome(players, checkpoint * interval + offset)).toEqual(
            {
              advancingRole: 'defenders',
              levels: checkpoint - 2,
              swapRoles: true,
            },
          );
        }
      }
    });
  },
);

describe('level checkpoints and penalties', () => {
  it('stops incoming advancement at J and permits advancement earned while on J', () => {
    expect(advanceLevel('10', 3)).toEqual({ level: 'J', wonMatch: false });
    expect(advanceLevel('2', 100).level).toBe('J');
    expect(advanceLevel('J', 0).level).toBe('J');
    expect(advanceLevel('J', 1).level).toBe('Q');
    expect(advanceLevel('J', 3)).toEqual({ level: 'A', wonMatch: true });
    expect(advanceLevel('K', 9)).toEqual({ level: 'A', wonMatch: true });
    expect(() => advanceLevel('J', -1)).toThrow();
    expect(() => scoreOutcome(4, NaN)).toThrow();
  });
  it('adjusts the defender score in the confirmed direction', () => {
    expect(10 + gamblePenalty('attackers')).toBe(30);
    expect(10 + gamblePenalty('defenders')).toBe(-10);
  });
});
