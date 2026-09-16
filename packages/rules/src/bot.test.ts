import { describe, expect, it } from 'vitest';
import {
  availableComponents,
  category,
  chooseBotPlay,
  chooseBotLead,
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
        knownVoids: ['clubs'],
      }),
    ).toEqual(['kh']);
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
