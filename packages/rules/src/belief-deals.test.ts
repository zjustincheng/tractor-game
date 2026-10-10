import { describe, it, expect } from 'vitest';
import { createDeck, category } from './cards.js';
import { samplePossibleDeal } from './belief-deals.js';

describe('constrained hidden deals', () => {
  it('reassigns earlier cards instead of violating a later seat void', () => {
    const deck = createDeck(4);
    const own = deck.find((c) => c.id === '0:spades:3')!;
    const unknown = new Set([
      '0:clubs:3',
      '0:hearts:3',
      '0:diamonds:3',
      own.id,
    ]);
    for (let seed = 1; seed <= 100; seed++) {
      let state = seed;
      const pick = (max: number) => {
        state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
        return Math.floor((state / 2 ** 32) * max);
      };
      const world = samplePossibleDeal(
        {
          playerCount: 4,
          seat: 0,
          ownHand: [own],
          seenCards: deck.filter((c) => !unknown.has(c.id)),
          handSizes: [1, 1, 1, 1],
          trump: { level: '2', suit: 'spades' },
          knownVoids: ['hearts', 'diamonds', 'trump'].map((category) => ({
            seat: 2,
            category,
          })),
        },
        pick,
      )!;
      expect(world).not.toBeNull();
      expect(
        category(world.hands[2]![0]!, { level: '2', suit: 'spades' }),
      ).toBe('clubs');
      expect(new Set(world.hands.flat().map((c) => c.id)).size).toBe(4);
    }
  });
  it('preserves exposed ownership and known kitty, rejecting contradictions', () => {
    const deck = createDeck(4),
      own = deck[0]!,
      exposed = deck[1]!,
      kitty = deck[2]!;
    const input = {
      playerCount: 4 as const,
      seat: 0,
      ownHand: [own],
      seenCards: deck.slice(3),
      handSizes: [1, 1, 0, 0],
      trump: { level: '2' as const, suit: 'spades' as const },
      knownVoids: [],
      knownKitty: [kitty],
      exposedCards: [{ cardId: exposed.id, seat: 1, mayBeBuried: false }],
    };
    expect(samplePossibleDeal(input, () => 0)).toEqual({
      hands: [[own], [exposed], [], []],
      kitty: [kitty],
    });
    expect(
      samplePossibleDeal(
        {
          ...input,
          exposedCards: [{ cardId: exposed.id, seat: 2, mayBeBuried: false }],
        },
        () => 0,
      ),
    ).toBeNull();
    expect(
      samplePossibleDeal(
        {
          ...input,
          exposedCards: [{ cardId: kitty.id, seat: 1, mayBeBuried: false }],
        },
        () => 0,
      ),
    ).toBeNull();
  });
});
