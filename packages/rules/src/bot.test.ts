import { describe, expect, it } from 'vitest';
import {
  availableComponents,
  category,
  chooseBotPlay,
  chooseBotLead,
  chooseBotOpeningLead,
  chooseBotBurial,
  chooseBotGambleLead,
  chooseBotDeclaration,
  createDeck,
  deal,
  decomposeLead,
  PLAYER_COUNTS,
  shuffle,
  validateFollow,
} from './index.js';
import type { Card, Rank, Suit, Trump } from './index.js';

const trump: Trump = { level: '2', suit: 'spades' };
const card = (rank: Rank, suit: Suit = 'clubs', id = rank + suit): Card => ({
  id,
  kind: 'suited',
  rank,
  suit,
});
function select(
  hand: Card[],
  leadCards: Card[],
  partner: boolean,
  lastToPlay = false,
) {
  const lead = decomposeLead(leadCards, trump)!;
  return chooseBotPlay(hand, lead, trump, {
    seat: 0,
    winnerSeat: partner ? 2 : 1,
    winning: lead,
    lastToPlay,
  });
}

describe('bot follow selection', () => {
  it.each(PLAYER_COUNTS)(
    'preserves friendly trump after every opponent shows out with %i seats',
    (playerCount) => {
      const hand = [
        card('3', 'spades', 's3'),
        card('3', 'spades', 's3b'),
        card('4', 'spades', 's4'),
        card('4', 'spades', 's4b'),
        card('A', 'clubs', 'ca'),
      ];
      const knownVoids = Array.from({ length: playerCount }, (_, seat) => seat)
        .filter((seat) => seat % 2 === 1)
        .map((seat) => ({ seat, category: 'trump' }));
      for (const role of ['attackers', 'defenders'] as const) {
        const context = {
          seat: 0,
          playerCount,
          role,
          defenderScore: 70,
          swapThreshold: 80,
          knownVoids,
        };
        for (const difficulty of ['relaxed', 'standard', 'sharp'] as const) {
          expect(
            chooseBotOpeningLead(
              hand,
              [[card('5', 'hearts')]],
              trump,
              context,
              difficulty,
            ),
          ).toEqual(['ca']);
        }
        // Repeated observations of one opponent must not imply everyone is void.
        expect(
          chooseBotLead(hand, trump, {
            ...context,
            defenderScore: 0,
            knownVoids: [knownVoids[0]!, knownVoids[0]!],
          }),
        ).not.toEqual(['ca']);
        // Once allies also show out, cashing trump no longer drains their hand.
        expect(
          chooseBotLead(hand, trump, {
            ...context,
            defenderScore: 0,
            knownVoids: Array.from({ length: playerCount - 1 }, (_, index) => ({
              seat: index + 1,
              category: 'trump',
            })),
          }),
        ).not.toEqual(['ca']);
        expect(
          chooseBotLead(hand.slice(0, 4), trump, context).length,
        ).toBeGreaterThan(0);
      }
    },
  );

  it('does not confuse allies showing out with opponents showing out', () => {
    const hand = [card('3', 'spades', 's3'), card('3', 'clubs', 'c3')];
    expect(
      chooseBotLead(hand, trump, {
        seat: 1,
        playerCount: 4,
        role: 'attackers',
        defenderScore: 0,
        swapThreshold: 80,
        knownVoids: [{ seat: 3, category: 'trump' }],
      }),
    ).toEqual(['s3']);
    expect(
      chooseBotLead(hand, trump, {
        seat: 1,
        playerCount: 4,
        role: 'attackers',
        defenderScore: 0,
        swapThreshold: 80,
        knownVoids: [
          { seat: 0, category: 'trump' },
          { seat: 2, category: 'trump' },
        ],
      }),
    ).toEqual(['c3']);
  });

  it('saves a big joker when an ordinary lead is available', () => {
    const bigJoker: Card = { id: 'big', kind: 'joker', joker: 'big' };
    expect(
      chooseBotLead([bigJoker, card('3', 'clubs', '3c')], trump, {
        role: 'attackers',
        defenderScore: 0,
        swapThreshold: 80,
      }),
    ).toEqual(['3c']);
  });

  it('leads a strong structure for attackers and points near the defender threshold', () => {
    const hand: Card[] = [
      card('3', 'clubs', '3c'),
      card('3', 'clubs', '3c2'),
      card('4', 'clubs', '4c'),
      card('4', 'clubs', '4c2'),
      card('K', 'hearts', 'kh'),
    ];
    expect(
      chooseBotLead(hand, trump, {
        role: 'attackers',
        defenderScore: 0,
        swapThreshold: 80,
      }),
    ).toEqual(['3c', '3c2', '4c', '4c2']);
    expect(
      chooseBotLead(hand, trump, {
        role: 'defenders',
        defenderScore: 70,
        swapThreshold: 80,
      }),
    ).toEqual(['kh']);
  });
  it('chooses an attacker gamble only when its components survive validation', () => {
    const hand = [
      card('3', 'clubs', 'a'),
      card('3', 'clubs', 'b'),
      card('4', 'clubs', 'c'),
      card('4', 'clubs', 'd'),
      card('K', 'clubs', 'e'),
    ];
    const otherHands = [[card('2', 'hearts')], [card('A', 'hearts')]];
    expect(chooseBotGambleLead(hand, otherHands, trump, 'attackers')).toEqual([
      'a',
      'b',
      'c',
      'd',
      'e',
    ]);
    expect(
      chooseBotGambleLead(hand, [[card('A', 'clubs')]], trump, 'attackers'),
    ).toBeNull();
  });
  it('only enables validated opening gambles at Sharp difficulty', () => {
    const hand = [
      card('3', 'clubs', 'a'),
      card('3', 'clubs', 'b'),
      card('4', 'clubs', 'c'),
      card('4', 'clubs', 'd'),
      card('K', 'clubs', 'e'),
    ];
    const others = [[card('2', 'hearts')], [card('A', 'hearts')]];
    const context = {
      role: 'attackers' as const,
      defenderScore: 0,
      swapThreshold: 80,
    };
    expect(chooseBotOpeningLead(hand, others, trump, context, 'sharp')).toEqual(
      ['a', 'b', 'c', 'd', 'e'],
    );
    expect(
      chooseBotOpeningLead(hand, others, trump, context, 'relaxed'),
    ).not.toEqual(['a', 'b', 'c', 'd', 'e']);
  });
  it('prefers a supported suit when declaration strength is tied', () => {
    const options = [
      {
        kind: 'suit' as const,
        playerSeat: 1,
        level: '2' as Rank,
        suit: 'clubs' as Suit,
        multiplicity: 1,
        cardIds: ['call-clubs'],
      },
      {
        kind: 'suit' as const,
        playerSeat: 1,
        level: '2' as Rank,
        suit: 'hearts' as Suit,
        multiplicity: 1,
        cardIds: ['call-hearts'],
      },
    ];
    const hand = [
      card('A', 'hearts', 'ha'),
      card('K', 'hearts', 'hk'),
      card('Q', 'hearts', 'hq'),
    ];
    const choice = chooseBotDeclaration(options, hand, '2');
    expect(choice?.kind === 'suit' ? choice.suit : null).toBe('hearts');
  });
  it('prefers a long coordinated suit over a short high-card suit', () => {
    const options = [
      {
        kind: 'suit' as const,
        playerSeat: 1,
        level: '2' as Rank,
        suit: 'clubs' as Suit,
        multiplicity: 1,
        cardIds: ['call-clubs'],
      },
      {
        kind: 'suit' as const,
        playerSeat: 1,
        level: '2' as Rank,
        suit: 'hearts' as Suit,
        multiplicity: 1,
        cardIds: ['call-hearts'],
      },
    ];
    const hand = [
      card('3', 'clubs', 'c3a'),
      card('3', 'clubs', 'c3b'),
      card('4', 'clubs', 'c4a'),
      card('4', 'clubs', 'c4b'),
      card('5', 'clubs', 'c5'),
      card('6', 'clubs', 'c6'),
      card('A', 'hearts', 'ha'),
      card('K', 'hearts', 'hk'),
      card('Q', 'hearts', 'hq'),
    ];
    const choice = chooseBotDeclaration(options, hand, '2');
    expect(choice?.kind === 'suit' ? choice.suit : null).toBe('clubs');
  });
  it('values a trump suit that creates a void in another suit', () => {
    const options = [
      {
        kind: 'suit' as const,
        playerSeat: 1,
        level: '2' as Rank,
        suit: 'clubs' as Suit,
        multiplicity: 1,
        cardIds: ['call-clubs'],
      },
      {
        kind: 'suit' as const,
        playerSeat: 1,
        level: '2' as Rank,
        suit: 'hearts' as Suit,
        multiplicity: 1,
        cardIds: ['call-hearts'],
      },
    ];
    const hand = [
      card('A', 'clubs', 'ca'),
      card('K', 'clubs', 'ck'),
      card('Q', 'clubs', 'cq'),
      card('J', 'clubs', 'cj'),
      card('10', 'clubs', 'c10'),
      card('A', 'hearts', 'ha'),
      card('K', 'hearts', 'hk'),
      card('Q', 'hearts', 'hq'),
      card('3', 'diamonds', 'd3'),
    ];
    const choice = chooseBotDeclaration(options, hand, '2');
    expect(choice?.kind === 'suit' ? choice.suit : null).toBe('clubs');
  });
  it('prefers a fresher category when otherwise equivalent', () => {
    const hand = [card('3', 'clubs', '3c'), card('K', 'hearts', 'kh')];
    const seen = Array.from({ length: 12 }, (_, index) =>
      card('4', 'clubs', `seen-${index}`),
    );
    expect(
      chooseBotLead(hand, trump, {
        role: 'attackers',
        defenderScore: 0,
        swapThreshold: 80,
        seenCards: seen,
      }),
    ).toEqual(['kh']);
  });
  it('avoids an attacker lead where an opponent is known void', () => {
    const hand = [card('3', 'clubs', '3c'), card('K', 'hearts', 'kh')];
    expect(
      chooseBotLead(hand, trump, {
        role: 'attackers',
        defenderScore: 0,
        swapThreshold: 80,
        seat: 0,
        playerCount: 4,
        knownVoids: [{ seat: 1, category: 'clubs' }],
      }),
    ).toEqual(['kh']);
  });
  it('can lead a suit for a teammate who is void and can ruff', () => {
    const hand = [card('3', 'clubs', '3c'), card('K', 'hearts', 'kh')];
    expect(
      chooseBotLead(hand, trump, {
        seat: 0,
        playerCount: 4,
        role: 'attackers',
        defenderScore: 0,
        swapThreshold: 80,
        knownVoids: [{ seat: 2, category: 'clubs' }],
      }),
    ).toEqual(['3c']);
  });
  it('cash-outs a strong winner when the hand is nearly empty', () => {
    const hand = [card('3', 'clubs', 'low'), card('A', 'hearts', 'ace')];
    const context = {
      role: 'attackers' as const,
      defenderScore: 0,
      swapThreshold: 80,
      cardsRemaining: 2,
    };
    expect(chooseBotLead(hand, trump, context)).toEqual(['ace']);
  });
  it('accepts tunable lead weights without changing legality', () => {
    const hand = [card('3', 'clubs', 'low'), card('A', 'hearts', 'ace')];
    expect(
      chooseBotLead(hand, trump, {
        role: 'attackers',
        defenderScore: 0,
        swapThreshold: 80,
        weights: { freshness: 0, endgamePoints: 20 },
      }),
    ).toEqual(['ace']);
  });
  it('beats an opponent with the cheapest winning single', () => {
    expect(
      select([card('3'), card('10'), card('K'), card('A')], [card('9')], false),
    ).toEqual(['10clubs']);
  });
  it('preserves high cards when a partner already wins', () => {
    expect(
      select([card('3'), card('Q'), card('A')], [card('K')], true),
    ).toEqual(['3clubs']);
  });
  it('feeds points to a winning partner when playing last', () => {
    expect(
      select([card('3'), card('10'), card('A')], [card('K')], true, true),
    ).toEqual(['10clubs']);
  });
  it('ruffs with the cheapest trump when void against opponents', () => {
    expect(
      select(
        [card('3', 'diamonds'), card('3', 'spades'), card('A', 'spades')],
        [card('K')],
        false,
      ),
    ).toEqual(['3spades']);
  });
  it('uses an ordinary trump before spending a joker to overtake', () => {
    const smallJoker: Card = { id: 'small', kind: 'joker', joker: 'small' };
    expect(
      select(
        [card('3', 'diamonds'), card('3', 'spades'), smallJoker],
        [card('K')],
        false,
      ),
    ).toEqual(['3spades']);
  });
  it('does not spend trump over a partner and can discard points when void', () => {
    expect(
      select(
        [card('10', 'diamonds'), card('3', 'spades')],
        [card('K')],
        true,
        true,
      ),
    ).toEqual(['10diamonds']);
  });
  it('uses the cheapest matching pair to win and retains the higher pair', () => {
    expect(
      select(
        [
          card('10', 'clubs', 't1'),
          card('10', 'clubs', 't2'),
          card('K', 'clubs', 'k1'),
          card('K', 'clubs', 'k2'),
        ],
        [card('9', 'clubs', 'n1'), card('9', 'clubs', 'n2')],
        false,
      ),
    ).toEqual(['t1', 't2']);
  });
  it.each(PLAYER_COUNTS)(
    'follows homogeneous and gamble leads legally with %i players',
    (count) => {
      let seed = count;
      const pick = (max: number) => {
        seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
        return seed % max;
      };
      for (let iteration = 0; iteration < 40; iteration++) {
        const trump: Trump = {
          level: iteration % 2 ? 'J' : '5',
          suit: iteration % 3 ? 'spades' : null,
        };
        const { hands } = deal(shuffle(createDeck(count), pick), count);
        const leadHand = hands[0]!;
        const suited = leadHand.filter(
          (card) => category(card, trump) === category(leadHand[0]!, trump),
        );
        const leads = [
          decomposeLead(suited, trump)!,
          ...availableComponents(leadHand, trump)
            .slice(0, 5)
            .map((component) => [component]),
        ];
        for (const lead of leads) {
          for (const hand of hands.slice(1)) {
            const ids = chooseBotPlay(hand, lead, trump, {
              seat: 1,
              winnerSeat: 0,
              winning: lead,
              lastToPlay: false,
            });
            expect(new Set(ids).size).toBe(ids.length);
            expect(
              validateFollow(
                hand,
                ids.map((id) => hand.find((card) => card.id === id)!),
                lead,
                trump,
              ).legal,
            ).toBe(true);
          }
        }
      }
    },
  );
});

describe('bot reserve decisions', () => {
  it('does not bury a big joker when ordinary cards are available', () => {
    const bigJoker: Card = { id: 'big', kind: 'joker', joker: 'big' };
    expect(
      chooseBotBurial(
        [bigJoker, card('3', 'clubs', '3c'), card('5', 'hearts', '5h')],
        1,
        trump,
      ),
    ).toEqual(['3c']);
  });
});
