import { describe, expect, it } from 'vitest';
import {
  availableComponents,
  beatsPlay,
  category,
  createDeck,
  deal,
  decomposeLead,
  homogeneousStructure,
  matchComponents,
  nextTrick,
  PLAYER_COUNTS,
  playCards,
  shuffle,
  startTrick,
  validateFollow,
  validateGamble,
  winningComponents,
} from './index.js';
import type {
  Card,
  Component,
  Rank,
  Suit,
  TrickState,
  Trump,
} from './index.js';

const trump: Trump = { suit: 'spades', level: '2' };
function cards(ranks: string, suit: Suit = 'clubs', tag = 'hand'): Card[] {
  return ranks
    .split(' ')
    .filter(Boolean)
    .map((rank, index) => ({
      id: `${tag}:${suit}:${rank}:${index}`,
      kind: 'suited',
      suit,
      rank: rank as Rank,
    }));
}
function components(
  ranks: string,
  suit: Suit = 'clubs',
  tag = 'lead',
): Component[] {
  return decomposeLead(cards(ranks, suit, tag), trump)!;
}
function follow(hand: Card[], selection: string, lead = components('8 8 9 9')) {
  const needed = selection.split(' ');
  const selected: Card[] = [];
  for (const rank of needed)
    selected.push(
      hand.find(
        (card) =>
          card.kind === 'suited' &&
          card.rank === rank &&
          !selected.includes(card),
      )!,
    );
  return validateFollow(hand, selected, lead, trump);
}

describe('component decomposition and exact matching', () => {
  it('groups 33344455 into a triple tractor plus a pair', () => {
    const lead = components('3 3 3 4 4 4 5 5');
    expect(
      lead.map(({ multiplicity, rankCount }) => [multiplicity, rankCount]),
    ).toEqual([
      [3, 2],
      [2, 1],
    ]);
    expect(
      lead[1]!.cards.every(
        (card) => card.kind === 'suited' && card.rank === '5',
      ),
    ).toBe(true);
  });
  it('is stable under selection order and never consumes a card twice', () => {
    const input = cards('3 3 3 4 4 4 5 5 A 7');
    const grouped = decomposeLead(input, trump)!;
    expect(decomposeLead([...input].reverse(), trump)).toEqual(grouped);
    expect(
      new Set(
        grouped.flatMap((component) => component.cards.map((card) => card.id)),
      ).size,
    ).toBe(input.length);
    expect(input).toHaveLength(10);
    expect(
      decomposeLead([...input, ...cards('A', 'hearts')], trump),
    ).toBeNull();
  });
  it('can cut pairs from triples for beatability, without merging equal-power off-suit levels', () => {
    expect(
      availableComponents(cards('K K K'), trump, {
        multiplicity: 2,
        rankCount: 1,
      }),
    ).toHaveLength(1);
    const equal = [...cards('2', 'hearts'), ...cards('2', 'clubs')];
    expect(
      availableComponents(equal, trump, { multiplicity: 2, rankCount: 1 }),
    ).toHaveLength(0);
  });
  it('matches a response to the lead, including disjoint substructures of a larger set', () => {
    const lead = components('4 4 K K');
    expect(
      matchComponents(cards('6 6 7 7', 'spades'), lead, trump, {
        requireAllCards: true,
      }),
    ).toHaveLength(2);
    expect(
      matchComponents(cards('6 6 6 6', 'spades'), lead, trump, {
        requireAllCards: true,
      }),
    ).toHaveLength(2);
    expect(
      matchComponents(cards('6 6 6 7', 'spades'), lead, trump, {
        requireAllCards: true,
      }),
    ).toBeNull();
  });
  it('does not match a six-card pair tractor as a triple tractor', () => {
    expect(
      matchComponents(cards('6 6 7 7 8 8'), components('3 3 3 4 4 4'), trump, {
        requireAllCards: true,
      }),
    ).toBeNull();
  });
  it('keeps singles separate even when consecutive', () => {
    expect(
      components('3 4 5 6').every((component) => component.cardCount === 1),
    ).toBe(true);
  });
});

describe('strict following (D6 and spec 9.2)', () => {
  it('requires the available pair in 6679J against consecutive pairs', () => {
    const hand = cards('6 6 7 9 J');
    expect(follow(hand, '6 7 9 J')).toMatchObject({
      legal: false,
      code: 'MUST_PLAY_SETS',
    });
    expect(follow(hand, '6 6 7 J')).toMatchObject({
      legal: true,
      matchesLead: false,
    });
  });
  it('requires both nonconsecutive pairs in 33557', () => {
    const hand = cards('3 3 5 5 7');
    expect(follow(hand, '3 3 5 7')).toMatchObject({
      legal: false,
      code: 'MUST_PLAY_SETS',
    });
    expect(follow(hand, '3 3 5 5')).toMatchObject({
      legal: true,
      matchesLead: false,
    });
  });
  it('requires a full tractor when available', () => {
    const hand = cards('3 3 4 4 7 7');
    expect(follow(hand, '3 3 7 7')).toMatchObject({
      legal: false,
      code: 'MUST_MATCH_STRUCTURE',
    });
    expect(follow(hand, '3 3 4 4')).toMatchObject({
      legal: true,
      matchesLead: true,
    });
  });
  it('protects triples when other suited cards suffice, but permits voluntary matching', () => {
    const hand = cards('6 6 6 7 9');
    const lead = components('8 8');
    expect(follow(hand, '7 9', lead)).toMatchObject({
      legal: true,
      matchesLead: false,
    });
    expect(follow(hand, '6 7', lead)).toMatchObject({
      legal: true,
      matchesLead: false,
    });
    expect(follow(hand, '6 6', lead)).toMatchObject({
      legal: true,
      matchesLead: true,
    });
    expect(follow(cards('6 6 6'), '6 6', lead)).toMatchObject({
      legal: true,
      matchesLead: true,
    });
    expect(follow(cards('6 10 10 10'), '6 10', lead)).toMatchObject({
      legal: true,
      matchesLead: false,
    });
  });
  it('does not force a tractor by breaking triples', () => {
    const hand = cards('6 6 6 7 7 7 9 J');
    expect(follow(hand, '6 7 9 J')).toMatchObject({
      legal: true,
      matchesLead: false,
    });
  });
  it('follows effective category, exhausts it, and prevents mixed trump from winning', () => {
    const club = cards('3');
    const spades = cards('K K', 'spades');
    const hand = [...club, ...spades];
    const lead = components('8 8');
    expect(validateFollow(hand, spades, lead, trump)).toMatchObject({
      legal: false,
      code: 'MUST_FOLLOW_SUIT',
    });
    expect(
      validateFollow(hand, [club[0]!, spades[0]!], lead, trump),
    ).toMatchObject({ legal: true, matchesLead: false });
    const levels = cards('2 2', 'hearts');
    expect(validateFollow(levels, levels, lead, trump)).toMatchObject({
      legal: true,
      matchesLead: true,
    });
    const offSuit = cards('K K', 'hearts');
    expect(validateFollow(offSuit, offSuit, lead, trump)).toMatchObject({
      legal: true,
      matchesLead: false,
    });
  });
  it('rejects incorrect counts and duplicate or fabricated ownership', () => {
    const hand = cards('3 3 4 4');
    expect(
      validateFollow(hand, hand.slice(0, 1), components('8 8'), trump),
    ).toMatchObject({ legal: false, code: 'WRONG_CARD_COUNT' });
    expect(() =>
      validateFollow(hand, [hand[0]!, hand[0]!], components('8 8'), trump),
    ).toThrow();
    expect(() =>
      validateFollow(hand, cards('K K'), components('8 8'), trump),
    ).toThrow();
  });
  it('requires available pairs when triples cannot be supplied', () => {
    const hand = cards('3 3 5 7');
    expect(follow(hand, '3 5 7', components('8 8 8'))).toMatchObject({
      legal: false,
      code: 'MUST_PLAY_SETS',
    });
    expect(follow(hand, '3 3 7', components('8 8 8'))).toMatchObject({
      legal: true,
      matchesLead: false,
    });
  });
  it('requires the full mixed structure when available', () => {
    const lead = components('8 8 A');
    const hand = cards('3 3 5 7');
    expect(follow(hand, '3 5 7', lead)).toMatchObject({
      legal: false,
      code: 'MUST_MATCH_STRUCTURE',
    });
    expect(follow(hand, '3 3 5', lead)).toMatchObject({
      legal: true,
      matchesLead: true,
    });
  });
});

describe('gamble validation and comparison (D4, D9, D10)', () => {
  it('reduces 33344455 to 55 when another hand has a higher pair, including within a triple', () => {
    const lead = components('3 3 3 4 4 4 5 5');
    const result = validateGamble(lead, [cards('6 6 6')], trump, 'attackers');
    expect(result).toMatchObject({ reduced: true, penalty: 20 });
    expect(
      result.cards.map((card) => card.kind === 'suited' && card.rank),
    ).toEqual(['5', '5']);
    expect(result.returned).toHaveLength(6);
  });
  it('does not invalidate a club gamble because an opponent can trump it', () => {
    expect(
      validateGamble(
        components('K K A'),
        [cards('K K A', 'spades')],
        trump,
        'attackers',
      ).reduced,
    ).toBe(false);
  });
  it('selects only among beatable components, preferring singles over pairs', () => {
    const result = validateGamble(
      components('K K 3 A'),
      [cards('Q Q 4')],
      trump,
      'defenders',
    );
    expect(result.penalty).toBe(-20);
    expect(result.cards).toHaveLength(1);
    expect(result.cards[0]).toMatchObject({ rank: '3' });
  });
  it('a higher single beats despite a losing pair', () => {
    expect(
      beatsPlay(components('Q Q A', 'spades'), components('K K 3', 'spades')),
    ).toBe(true);
  });
  it('compares against any component, including a stronger high pair beating a lower pair', () => {
    expect(
      beatsPlay(
        components('3 3 Q Q', 'spades'),
        components('4 4 K K', 'spades'),
      ),
    ).toBe(true);
  });
  it('identical total strengths keep the earlier play even though internal components differ in power', () => {
    expect(
      beatsPlay(
        components('4 4 K K', 'spades', 'later'),
        components('4 4 K K', 'spades', 'first'),
      ),
    ).toBe(false);
  });
  it('requires the entire shape before accepting a higher component or trump', () => {
    expect(
      beatsPlay(components('A', 'spades'), components('K K 3', 'clubs')),
    ).toBe(false);
    expect(
      beatsPlay(components('3 3 3', 'spades'), components('K K A', 'clubs')),
    ).toBe(false);
    expect(
      beatsPlay(components('Q Q A', 'hearts'), components('K K 3', 'clubs')),
    ).toBe(false);
  });
  it('searches alternative disjoint partitions that can beat the incumbent', () => {
    const lead = [
      {
        ...homogeneousStructure(cards('7 7 8 8'), trump)!,
        cards: cards('7 7 8 8'),
      },
      { ...homogeneousStructure(cards('K K'), trump)!, cards: cards('K K') },
    ];
    const current = [
      {
        ...homogeneousStructure(cards('4 4 5 5', 'spades'), trump)!,
        cards: cards('4 4 5 5', 'spades'),
      },
      {
        ...homogeneousStructure(cards('3 3', 'spades'), trump)!,
        cards: cards('3 3', 'spades'),
      },
    ];
    const candidate = cards('3 3 4 4 5 5', 'spades', 'later');
    // Same card powers and shapes: earlier play wins, regardless of another possible partition.
    expect(winningComponents(candidate, lead, current, trump)).toBeNull();
    const other = cards('6 6 7 7 8 8', 'spades', 'other');
    const strongerCurrent = [
      {
        ...homogeneousStructure(cards('8 8 9 9', 'spades'), trump)!,
        cards: cards('8 8 9 9', 'spades'),
      },
      {
        ...homogeneousStructure(cards('7 7', 'spades'), trump)!,
        cards: cards('7 7', 'spades'),
      },
    ];
    const winning = winningComponents(other, lead, strongerCurrent, trump)!;
    expect(winning).not.toBeNull();
    expect(
      winning.find((component) => component.rankCount === 1)!.cards[0],
    ).toMatchObject({ rank: '8' });
  });
});

describe('pure trick transitions', () => {
  function initial(): TrickState {
    return startTrick({
      playerCount: 4,
      trump,
      attackingTeam: 'A',
      leaderSeat: 0,
      hands: [
        [...cards('5 5', 'clubs', 'a'), ...cards('3', 'hearts', 'a')],
        [...cards('K K', 'clubs', 'b'), ...cards('4', 'hearts', 'b')],
        [...cards('Q Q', 'clubs', 'c'), ...cards('5', 'hearts', 'c')],
        [...cards('4 4', 'spades', 'd'), ...cards('6', 'hearts', 'd')],
      ],
    });
  }
  it('rejects bad commands without mutating state and captures points only for defenders', () => {
    let state = initial();
    const original = structuredClone(state);
    expect(playCards(state, 1, [state.hands[1]![0]!.id])).toMatchObject({
      ok: false,
      code: 'NOT_YOUR_TURN',
    });
    expect(playCards(state, 0, ['fake'])).toMatchObject({
      ok: false,
      code: 'INVALID_CARDS',
    });
    expect(
      playCards(state, 0, [state.hands[0]![0]!.id, state.hands[0]![0]!.id]),
    ).toMatchObject({ ok: false, code: 'INVALID_CARDS' });
    expect(state).toEqual(original);
    for (let seat = 0; seat < 4; seat++) {
      const before = structuredClone(state);
      const result = playCards(
        state,
        seat,
        state.hands[seat]!.slice(0, 2).map((card) => card.id),
      );
      expect(result.ok).toBe(true);
      if (!result.ok) throw new Error(result.message);
      expect(state).toEqual(before);
      state = result.state;
    }
    expect(state).toMatchObject({
      status: 'complete',
      winnerSeat: 3,
      capturedDefenderPoints: 30,
      trickPoints: 30,
      nextSeat: null,
    });
    expect(state.hands.map((hand) => hand.length)).toEqual([1, 1, 1, 1]);
    expect(playCards(state, 0, [])).toMatchObject({
      ok: false,
      code: 'TRICK_COMPLETE',
    });
    expect(nextTrick(state)).toMatchObject({
      leaderSeat: 3,
      nextSeat: 3,
      status: 'playing',
    });
  });
  it('checks teammates as well as opponents when reducing a gamble', () => {
    const state = startTrick({
      playerCount: 4,
      trump,
      attackingTeam: 'A',
      leaderSeat: 0,
      hands: [
        cards('K K 3', 'clubs', 'a'),
        cards('3 4 5', 'hearts', 'b'),
        cards('4 6 7', 'clubs', 'c'),
        cards('6 7 8', 'hearts', 'd'),
      ],
    });
    const result = playCards(
      state,
      0,
      state.hands[0]!.map((card) => card.id),
    );
    expect(result).toMatchObject({ ok: true, reduced: true, penalty: 20 });
    if (!result.ok) throw new Error(result.message);
    expect(result.returned).toHaveLength(2);
    expect(result.state.plays[0]!.cards).toHaveLength(1);
    expect(result.state.hands[0]).toHaveLength(2);
    expect(result.state.nextSeat).toBe(1);
    expect(result.state.penaltyPoints).toBe(20);
  });
  it.each(PLAYER_COUNTS)(
    'conserves all cards and hand counts across a full single-card round at %i players',
    (playerCount) => {
      const { hands, kitty } = deal(
        shuffle(createDeck(playerCount), (max) => Math.floor(max / 2)),
        playerCount,
      );
      let state = startTrick({
        playerCount,
        trump,
        attackingTeam: 'A',
        leaderSeat: playerCount - 1,
        hands,
      });
      const captured: Card[] = [];
      const handSize = hands[0]!.length;
      for (let trick = 0; trick < handSize; trick++) {
        for (let turn = 0; turn < playerCount; turn++) {
          const seat = state.nextSeat!;
          const hand = state.hands[seat]!;
          const ledCategory = state.plays[0]?.components?.[0]?.category;
          const card =
            hand.find((item) => category(item, trump) === ledCategory) ??
            hand[0]!;
          const result = playCards(state, seat, [card.id]);
          expect(result.ok).toBe(true);
          if (!result.ok) throw new Error(result.message);
          state = result.state;
        }
        expect(
          state.hands.every((hand) => hand.length === handSize - trick - 1),
        ).toBe(true);
        if (state.winnerSeat! % 2 === 0)
          expect(state.capturedDefenderPoints).toBe(0);
        captured.push(...state.plays.flatMap((play) => play.cards));
        if (trick + 1 < handSize) state = nextTrick(state);
      }
      expect(captured.length + kitty.length).toBe(
        createDeck(playerCount).length,
      );
      expect(new Set([...captured, ...kitty].map((card) => card.id)).size).toBe(
        createDeck(playerCount).length,
      );
      expect(() => nextTrick(state)).toThrow();
    },
  );
});
