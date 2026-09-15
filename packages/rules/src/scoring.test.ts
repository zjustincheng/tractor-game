import { describe, expect, it } from 'vitest';
import { homogeneousStructure, settleRound } from './index.js';
import type { Card } from './index.js';

function card(
  rank: 'J' | '5' | '10' | 'K',
  suit: 'clubs' | 'spades' = 'clubs',
  id = rank + suit,
): Card {
  return { id, kind: 'suited', rank, suit };
}

describe('round settlement', () => {
  it('does not reset J for an all-Jack gamble of equal-power off-suit singles', () => {
    const cards: Card[] = [
      card('J', 'clubs'),
      { id: 'jh', kind: 'suited', rank: 'J', suit: 'hearts' },
    ];
    const result = settleRound({
      playerCount: 4,
      attackingTeam: 'A',
      levels: { A: 'J', B: '2' },
      trickPoints: 80,
      finalTrickWinnerTeam: 'B',
      finalWinningCards: cards,
      finalWinningStructure: homogeneousStructure([cards[0]!], {
        level: 'J',
        suit: 'spades',
      }),
      kitty: [],
    });
    expect(result.jackReset).toBe(false);
  });
  it('multiplies kitty points by the actual final winning structure', () => {
    const structure = homogeneousStructure(
      [
        card('J', 'clubs', 'j1'),
        card('J', 'clubs', 'j2'),
        card('J', 'spades', 'j3'),
        card('J', 'spades', 'j4'),
      ],
      { level: 'J', suit: 'spades' },
    );
    const result = settleRound({
      playerCount: 4,
      attackingTeam: 'A',
      levels: { A: '7', B: 'J' },
      trickPoints: 40,
      finalTrickWinnerTeam: 'B',
      finalWinningCards: [card('J', 'clubs', 'j1'), card('J', 'clubs', 'j2')],
      finalWinningStructure: structure,
      kitty: [card('5'), card('10')],
    });
    expect(result.kittyBasePoints).toBe(15);
    expect(result.kittyMultiplier).toBe(8);
    expect(result.kittyPoints).toBe(120);
    expect(result.defenderScore).toBe(160);
    expect(result.rolesSwapped).toBe(true);
  });
  it('does not count kitty or multiplier when attackers win the final trick', () => {
    const result = settleRound({
      playerCount: 4,
      attackingTeam: 'A',
      levels: { A: '2', B: '2' },
      trickPoints: 20,
      finalTrickWinnerTeam: 'A',
      finalWinningCards: [card('K')],
      finalWinningStructure: null,
      kitty: [card('5'), card('K')],
    });
    expect(result.kittyBasePoints).toBe(15);
    expect(result.kittyMultiplier).toBe(0);
    expect(result.defenderScore).toBe(20);
  });
  it('resets J attackers only for a Jack-only defender win at the threshold', () => {
    const structure = homogeneousStructure(
      [card('J', 'clubs', 'a'), card('J', 'clubs', 'b')],
      { level: 'J', suit: 'spades' },
    );
    const result = settleRound({
      playerCount: 4,
      attackingTeam: 'A',
      levels: { A: 'J', B: '2' },
      trickPoints: 80,
      finalTrickWinnerTeam: 'B',
      finalWinningCards: [card('J', 'clubs', 'a'), card('J', 'clubs', 'b')],
      finalWinningStructure: structure,
      kitty: [],
    });
    expect(result.jackReset).toBe(true);
    expect(result.levels.A).toBe('2');
    const jokerResult = settleRound({
      playerCount: 4,
      attackingTeam: 'A',
      levels: { A: 'J', B: '2' },
      trickPoints: 80,
      finalTrickWinnerTeam: 'B',
      finalWinningCards: [{ id: 'joker', kind: 'joker', joker: 'big' }],
      finalWinningStructure: structure,
      kitty: [],
    });
    expect(jokerResult.jackReset).toBe(false);
  });
  it('continues advancement above the nominal round total and applies penalties', () => {
    const result = settleRound({
      playerCount: 6,
      attackingTeam: 'A',
      levels: { A: 'Q', B: 'J' },
      trickPoints: 300,
      finalTrickWinnerTeam: 'B',
      finalWinningCards: [card('K')],
      finalWinningStructure: null,
      kitty: [],
      gamblePenaltyPoints: 60,
    });
    expect(result.defenderScore).toBe(360);
    expect(result.outcome.levels).toBe(4);
    expect(result.levels.B).toBe('A');
    expect(result.winner).toBe('B');
  });
});
