import { describe, expect, it } from 'vitest';
import {
  estimatePartnerRuffProbability,
  estimateVoidProbability,
  createDeck,
} from './index.js';

const trump = { level: '2', suit: 'spades' } as const;

describe('public card beliefs', () => {
  it('increases a partner ruff estimate as a suit is publicly exhausted', () => {
    const ownHand = createDeck(4)
      .filter((card) => card.kind === 'suited' && card.suit === 'clubs')
      .slice(0, 3);
    const before = estimatePartnerRuffProbability(
      {
        playerCount: 4,
        ownHand,
        trump,
        cardsRemaining: 8,
      },
      0,
      'hearts',
    );
    const after = estimatePartnerRuffProbability(
      {
        playerCount: 4,
        ownHand,
        trump,
        cardsRemaining: 8,
        knownVoids: [{ seat: 2, category: 'hearts' }],
      },
      0,
      'hearts',
    );
    expect(after).toBe(1);
    expect(after).toBeGreaterThan(before);
  });

  it('never treats a category as certain without public evidence', () => {
    const probability = estimateVoidProbability(
      {
        playerCount: 4,
        ownHand: createDeck(4).slice(0, 8),
        trump,
        cardsRemaining: 8,
      },
      1,
      'diamonds',
    );
    expect(probability).toBeGreaterThan(0);
    expect(probability).toBeLessThan(1);
  });
});
