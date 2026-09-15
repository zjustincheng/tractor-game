import { describe, expect, it } from 'vitest';
import {
  canOverturn,
  chooseRandomFallback,
  declarationsForHand,
  declarationRank,
  validateDeclaration,
} from './declarations.js';
import type { Declaration } from './declarations.js';
import type { Card } from './cards.js';

function suited(
  rank: '2' | '5' | '7',
  suit: 'clubs' | 'diamonds' | 'hearts' | 'spades',
  n: number,
): Card[] {
  return Array.from({ length: n }, (_, index) => ({
    id: `${index}:${suit}:${rank}`,
    kind: 'suited',
    rank,
    suit,
  }));
}
function jokers(joker: 'small' | 'big', n: number): Card[] {
  return Array.from({ length: n }, (_, index) => ({
    id: `${index}:joker:${joker}`,
    kind: 'joker',
    joker,
  }));
}

describe('declarations', () => {
  it('finds suit multiplicities without using jokers or kitty cards', () => {
    const hand = [
      ...suited('5', 'clubs', 2),
      ...suited('5', 'hearts', 1),
      ...jokers('small', 2),
    ];
    const declarations = declarationsForHand(hand, 4, '5', 2);
    expect(
      declarations
        .filter((item) => item.kind === 'suit')
        .map((item) => [item.suit, item.multiplicity]),
    ).toEqual([
      ['clubs', 1],
      ['clubs', 2],
      ['hearts', 1],
    ]);
    expect(declarations.some((item) => item.kind === 'joker')).toBe(false);
  });
  it('enforces joker declaration counts by player count and type', () => {
    const four = declarationsForHand(
      [...jokers('small', 2), ...jokers('big', 1)],
      4,
      '5',
      0,
    );
    expect(
      four
        .filter((item) => item.kind === 'joker')
        .map((item) => [item.joker, item.multiplicity]),
    ).toContainEqual(['mixed', 3]);
    const six = declarationsForHand(
      [...jokers('small', 4), ...jokers('big', 4)],
      6,
      '5',
      0,
    ).filter((item) => item.kind === 'joker');
    expect(
      six.some((item) => item.joker === 'small' && item.multiplicity === 3),
    ).toBe(true);
    expect(
      six.some((item) => item.joker === 'big' && item.multiplicity === 3),
    ).toBe(true);
    expect(
      six.some((item) => item.joker === 'mixed' && item.multiplicity === 4),
    ).toBe(true);
  });
  it('validates physical level cards and rejects fabricated or wrong-rank declarations', () => {
    const hand = suited('5', 'clubs', 2);
    const declaration = declarationsForHand(hand, 4, '5', 0).find(
      (item) => item.kind === 'suit' && item.multiplicity === 2,
    )!;
    expect(validateDeclaration(declaration, hand, 4, '5')).toBe(true);
    expect(
      validateDeclaration(
        { ...declaration, cardIds: ['fake', 'fake2'] },
        hand,
        4,
        '5',
      ),
    ).toBe(false);
    expect(
      validateDeclaration({ ...declaration, level: '7' }, hand, 4, '5'),
    ).toBe(false);
    expect(
      validateDeclaration({ ...declaration, playerSeat: 4 }, hand, 4, '5'),
    ).toBe(false);
  });
  it('overturns same-rank suits only with greater multiplicity and gives jokers priority', () => {
    const one: Declaration = {
      kind: 'suit',
      playerSeat: 0,
      level: '5',
      suit: 'clubs',
      multiplicity: 1,
      cardIds: ['a'],
    };
    const pair: Declaration = {
      kind: 'suit',
      playerSeat: 1,
      level: '5',
      suit: 'hearts',
      multiplicity: 2,
      cardIds: ['b', 'c'],
    };
    const joker: Declaration = {
      kind: 'joker',
      playerSeat: 2,
      level: '5',
      joker: 'small',
      multiplicity: 3,
      cardIds: ['d', 'e', 'f'],
    };
    expect(canOverturn(one, pair)).toBe(true);
    expect(canOverturn(pair, one)).toBe(false);
    expect(canOverturn(one, { ...pair, level: '7' })).toBe(false);
    expect(canOverturn(one, joker)).toBe(true);
    expect(canOverturn(joker, pair)).toBe(false);
  });
  it('supports only the first-round small-to-big joker takeover at equal or greater count', () => {
    const small: Declaration = {
      kind: 'joker',
      playerSeat: 0,
      level: '5',
      joker: 'small',
      multiplicity: 4,
      cardIds: ['a', 'b', 'c', 'd'],
    };
    const big3: Declaration = {
      kind: 'joker',
      playerSeat: 1,
      level: '5',
      joker: 'big',
      multiplicity: 3,
      cardIds: ['e', 'f', 'g'],
    };
    const big4: Declaration = {
      ...big3,
      multiplicity: 4,
      cardIds: ['e', 'f', 'g', 'h'],
    };
    expect(canOverturn(small, big3, true)).toBe(false);
    expect(canOverturn(small, big4, true)).toBe(true);
    expect(canOverturn(small, big4, false)).toBe(false);
  });
  it('chooses a deterministic eligible suit declaration for fallback', () => {
    const selected = chooseRandomFallback(
      [suited('5', 'clubs', 1), suited('5', 'hearts', 1)],
      4,
      '5',
      (maximum) => maximum - 1,
    );
    expect(selected).toMatchObject({
      kind: 'suit',
      playerSeat: 1,
      suit: 'hearts',
    });
    expect(declarationRank(selected)).toBe(1);
    expect(() =>
      chooseRandomFallback([suited('7', 'clubs', 1)], 4, '5', () => 0),
    ).toThrow();
  });
});
