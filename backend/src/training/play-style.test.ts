import { describe, expect, it } from 'vitest';
import { decomposeLead } from '@tractor/rules';
import type { BotLeadContext, BotPlayContext, Card } from '@tractor/rules';
import {
  canKill,
  feedGuard,
  followFlaw,
  followGuard,
  killLeadGuard,
  usesKillInputs,
  leadFlaw,
  leadGuard,
  summarizeFollows,
} from './play-style.js';
import {
  choosePolicyLead,
  leadOptions,
  newPolicy,
  parsePolicy,
  playOptions,
} from './learned-policy.js';
import { seededRandom } from './self-play.js';

const trump = { level: '2', suit: 'spades' } as const;
const suited = (
  rank: Extract<Card, { kind: 'suited' }>['rank'],
  suit: Extract<Card, { kind: 'suited' }>['suit'],
  copy = 0,
): Card => ({ id: `${copy}:${suit}:${rank}`, kind: 'suited', suit, rank });
const big = (copy = 0): Card => ({
  id: `${copy}:joker:big`,
  kind: 'joker',
  joker: 'big',
});
const context: BotLeadContext = {
  seat: 0,
  playerCount: 4,
  dealerSeat: 2,
  cardsRemaining: 8,
  role: 'attackers',
  defenderScore: 0,
  swapThreshold: 80,
  seenCards: [],
  knownVoids: [],
};
const idsOf = (cards: readonly Card[]) => cards.map((card) => card.id);
const zeros = (length: number) => Array<number>(length).fill(0);

describe('lead style', () => {
  const pair = [suited('K', 'hearts'), suited('K', 'hearts', 1)];
  const ace = suited('A', 'hearts');
  const hand = [...pair, ace, suited('3', 'diamonds'), suited('4', 'clubs')];
  const options = leadOptions(hand, trump, context);
  const preference = zeros(options.length);

  it('cashes a safe ace before gambling a side pair', () => {
    expect(leadFlaw(hand, trump, idsOf(pair), options, context)).toBe(
      'pair-before-ace',
    );
    const replaced = leadGuard(
      hand,
      trump,
      idsOf(pair),
      options,
      context,
      preference,
    );
    expect(options[replaced]!.cardIds).toEqual([ace.id]);
  });

  it('does not force an ace from a different suit', () => {
    const otherAce = [...pair, suited('A', 'clubs'), suited('4', 'diamonds')];
    const list = leadOptions(otherAce, trump, context);
    expect(leadFlaw(otherAce, trump, idsOf(pair), list, context)).toBeNull();
  });

  it('allows the pair once an opponent is known to ruff the ace', () => {
    const voids = {
      ...context,
      knownVoids: [{ seat: 1, category: 'hearts' }],
    };
    expect(leadFlaw(hand, trump, idsOf(pair), options, voids)).toBeNull();
  });

  it('plays a small probe instead of a lone high trump with no plan', () => {
    const high = suited('2', 'spades');
    const small = suited('3', 'diamonds');
    const weak = [
      high,
      small,
      suited('Q', 'clubs'),
      suited('K', 'hearts'),
      suited('J', 'hearts'),
    ];
    const list = leadOptions(weak, trump, context);
    const replaced = leadGuard(
      weak,
      trump,
      [high.id],
      list,
      context,
      zeros(list.length),
    );
    expect(list[replaced]!.cardIds).toEqual([small.id]);
  });

  it('holds the big joker until the endgame', () => {
    const joker = big();
    const long = [joker, ...hand];
    const list = leadOptions(long, trump, context);
    expect(leadFlaw(long, trump, [joker.id], list, context)).toBe(
      'big-joker-lead',
    );
    const short = [joker, suited('3', 'clubs')];
    expect(
      leadFlaw(
        short,
        trump,
        [joker.id],
        leadOptions(short, trump, context),
        context,
      ),
    ).toBeNull();
  });

  it('leaves earlier champions playing as they were trained', () => {
    const model = parsePolicy(newPolicy(seededRandom(5)));
    model.output = model.output.map(() => 0);
    const legacy = {
      ...model,
      priorScale: 0,
      input: model.input.map((row) => row.slice(0, 30)),
    };
    const pairFirst = { ...model, priorScale: 0 };
    expect(options[0]!.cardIds).toEqual(idsOf(pair));
    expect(choosePolicyLead(legacy, hand, trump, context)).toEqual(idsOf(pair));
    expect(choosePolicyLead(pairFirst, hand, trump, context)).toEqual([ace.id]);
  });
});

describe('follow style', () => {
  const lead = decomposeLead([suited('9', 'clubs')], trump)!;
  const play = (over: Partial<BotPlayContext>): BotPlayContext => ({
    seat: 1,
    winnerSeat: 0,
    winning: lead,
    lastToPlay: false,
    trickPoints: 0,
    opponentsRemaining: 1,
    ...over,
  });
  const hand = [
    suited('10', 'clubs'),
    suited('A', 'clubs'),
    suited('3', 'hearts'),
  ];
  const run = (cards: Card[], over: Partial<BotPlayContext>) => {
    const context = play(over);
    const options = playOptions(cards, lead, trump, context, true);
    return {
      context,
      options,
      all: summarizeFollows(cards, lead, trump, context, options),
    };
  };

  it('uses a strong winner when a lot of points are on the line', () => {
    const { context, options, all } = run(hand, { trickPoints: 20 });
    const ten = options.findIndex((o) => o.cardIds[0] === hand[0]!.id);
    expect(followFlaw(context, all[ten]!, all)).toBe('barely-beat');
    const replaced = followGuard(context, ten, all, zeros(all.length));
    expect(options[replaced]!.cardIds).toEqual([hand[1]!.id]);
  });

  it('allows a cheap win when little is at stake', () => {
    const { context, options, all } = run(hand, { trickPoints: 5 });
    const ten = options.findIndex((o) => o.cardIds[0] === hand[0]!.id);
    expect(followFlaw(context, all[ten]!, all)).toBeNull();
  });

  it('never spends the big joker on a worthless trick', () => {
    const voidHand = [big(), suited('3', 'hearts')];
    const { context, options, all } = run(voidHand, { trickPoints: 0 });
    const joker = options.findIndex((o) => o.cardIds[0] === voidHand[0]!.id);
    expect(joker).toBeGreaterThanOrEqual(0);
    expect(followFlaw(context, all[joker]!, all)).toBe('joker-waste');
    const replaced = followGuard(context, joker, all, zeros(all.length));
    expect(options[replaced]!.cardIds).toEqual([voidHand[1]!.id]);
  });
});

describe('kill rules', () => {
  const opponentOut = [{ seat: 1, category: 'hearts' }];
  const ten = suited('10', 'hearts');
  const hand = [ten, suited('3', 'hearts'), suited('4', 'clubs')];

  it('lets only a seat with trump left kill a side suit', () => {
    expect(canKill(opponentOut, 1, 'hearts')).toBe(true);
    expect(
      canKill([...opponentOut, { seat: 1, category: 'trump' }], 1, 'hearts'),
    ).toBe(false);
    expect(canKill(opponentOut, 1, 'trump')).toBe(false);
  });

  it('does not lead points into a suit an opponent can trump', () => {
    const lead = { ...context, knownVoids: opponentOut };
    const options = leadOptions(hand, trump, lead);
    const chosen = options.findIndex((o) => o.cardIds[0] === ten.id);
    const replaced = killLeadGuard(
      hand,
      trump,
      chosen,
      options,
      lead,
      zeros(options.length),
    );
    expect(options[replaced]!.cardIds).not.toContain(ten.id);
    const low = options.findIndex((o) => o.cardIds[0] === '0:hearts:3');
    expect(
      killLeadGuard(hand, trump, low, options, lead, zeros(options.length)),
    ).toBe(-1);
    expect(options[chosen]!.features.slice(33)).toEqual([1, 10 / 30, 0, 0]);
  });

  it('feeds points when only a partner still to play can trump', () => {
    const lead = decomposeLead([suited('A', 'hearts', 1)], trump)!;
    const follow: BotPlayContext = {
      seat: 2,
      winnerSeat: 1,
      winning: lead,
      lastToPlay: false,
      trickPoints: 0,
      opponentsRemaining: 0,
      seatsToPlay: [0],
      knownVoids: [{ seat: 0, category: 'hearts' }],
    };
    const options = playOptions(hand, lead, trump, follow);
    const low = options.findIndex((o) => o.cardIds[0] === '0:hearts:3');
    const fed = feedGuard(
      hand,
      lead,
      trump,
      follow,
      low,
      options,
      zeros(options.length),
    );
    expect(options[fed]!.cardIds).toEqual([ten.id]);
    expect(options[fed]!.features.slice(33)).toEqual([0, 0, 1, 10 / 30]);
    // An opponent after us who can also trump: no feeding.
    const risky = {
      ...follow,
      seatsToPlay: [0, 3],
      knownVoids: [...follow.knownVoids!, { seat: 3, category: 'hearts' }],
    };
    expect(
      feedGuard(hand, lead, trump, risky, low, options, zeros(options.length)),
    ).toBe(-1);
  });

  it('switches on only for models trained with the kill inputs', () => {
    const old = parsePolicy({
      ...newPolicy(seededRandom(3)),
      input: newPolicy(seededRandom(3)).input.map((row) => row.slice(0, 33)),
    });
    expect(usesKillInputs(old)).toBe(false);
    expect(usesKillInputs(newPolicy(seededRandom(3)))).toBe(true);
  });
});
