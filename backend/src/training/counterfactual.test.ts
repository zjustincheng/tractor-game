import { describe, expect, it } from 'vitest';
import {
  DEFAULT_BOT_LEAD_WEIGHTS,
  startTrick,
  createDeck,
  category,
} from '@tractor/rules';
import type { Card, Suit, Rank } from '@tractor/rules';
import {
  compareAlternatives,
  rolloutRound,
  sampleBeliefWorlds,
} from './counterfactual.js';
import type { RoundPosition } from './counterfactual.js';
import {
  leadOptions,
  newPolicy,
  policyProbabilities,
} from './learned-policy.js';
import type { PolicyExperience } from './learned-policy.js';
import { newOptimizer, updateFromOutcomes } from './policy-update.js';
import { playTrainingMatch, seededRandom } from './self-play.js';

const card = (suit: Suit, rank: Rank): Card => ({
  id: `0:${suit}:${rank}`,
  kind: 'suited',
  suit,
  rank,
});
function position(): RoundPosition {
  const p: RoundPosition = {
    trick: startTrick({
      playerCount: 4,
      trump: { level: '2', suit: 'spades' },
      attackingTeam: 'A',
      leaderSeat: 0,
      hands: [
        [
          { id: '0:joker:big', kind: 'joker', joker: 'big' },
          card('clubs', '3'),
        ],
        [card('clubs', 'A'), card('hearts', '3')],
        [card('clubs', '4'), card('hearts', '4')],
        [card('clubs', '5'), card('hearts', '5')],
      ],
    }),
    levels: { A: '2', B: '2' },
    kitty: [card('diamonds', 'K')],
    captured: 70,
    penalties: 0,
    seenCards: [],
    knownVoids: [],
  };
  const held = new Set([...p.trick.hands.flat(), ...p.kitty].map((c) => c.id));
  p.seenCards = createDeck(4).filter((c) => !held.has(c.id));
  return p;
}
function experience(p: RoundPosition): PolicyExperience {
  const options = leadOptions(p.trick.hands[0]!, p.trick.trump, {
    seat: 0,
    playerCount: 4,
    role: 'attackers',
    defenderScore: 70,
    swapThreshold: 80,
  });
  // Give the bad action a starting preference, to verify simulated results can
  // overcome it. The preference label is not used to decide the reward.
  for (const option of options)
    option.prior = option.cardIds.includes('0:joker:big') ? 0.75 : 0;
  return {
    options,
    chosen: options.findIndex((o) => o.cardIds.includes('0:joker:big')),
    temperature: 0.15,
    advantage: 0,
  };
}

describe('paired round continuations', () => {
  it('keeps live deal samples consistent with dealer knowledge and current-trick voids', () => {
    let checked = 0;
    playTrainingMatch({
      seed: 42,
      playerCount: 4,
      candidateTeam: 'A',
      candidate: DEFAULT_BOT_LEAD_WEIGHTS,
      opponent: DEFAULT_BOT_LEAD_WEIGHTS,
      maxRounds: 1,
      onPosition(p) {
        const worlds = sampleBeliefWorlds(p, 2);
        expect(worlds).toHaveLength(2);
        for (const world of worlds) {
          checked++;
          const seen = [
            ...p.seenCards,
            ...p.trick.plays.flatMap((x) => x.cards),
          ];
          expect(
            new Set(
              [...world.hands.flat(), ...world.kitty, ...seen].map((c) => c.id),
            ).size,
          ).toBe(108);
          expect(world.hands.map((h) => h.length)).toEqual(
            p.trick.hands.map((h) => h.length),
          );
          if (p.trick.nextSeat === p.dealerSeat)
            expect(world.kitty).toEqual(p.kitty);
          const first = p.trick.plays[0];
          if (first) {
            const led = category(first.cards[0]!, p.trick.trump);
            for (const play of p.trick.plays)
              if (play.cards.some((c) => category(c, p.trick.trump) !== led))
                expect(
                  world.hands[play.seat]!.some(
                    (c) => category(c, p.trick.trump) === led,
                  ),
                ).toBe(false);
          }
          for (const e of p.exposedCards ?? [])
            if (!seen.some((c) => c.id === e.cardId))
              expect(
                world.hands[e.seat]!.some((c) => c.id === e.cardId) ||
                  (e.mayBeBuried && world.kitty.some((c) => c.id === e.cardId)),
              ).toBe(true);
        }
      },
    });
    expect(checked).toBeGreaterThan(0);
  });
  it('values saving a joker for the kitty and never mutates the original deal', () => {
    const p = position(),
      before = structuredClone(p);
    const spent = rolloutRound(p, ['0:joker:big'], 'A');
    const saved = rolloutRound(p, ['0:clubs:3'], 'A');
    expect(saved).toBeGreaterThan(spent);
    expect(rolloutRound(p, ['0:clubs:3'], 'B')).toBe(-saved);
    expect(rolloutRound(p, ['0:joker:big'], 'A')).toBe(spent);
    expect(p).toEqual(before);
    expect(() => rolloutRound(p, ['missing'], 'A')).toThrow(/illegal move/);
  });

  it('learns to change a greedy legal choice from simulated outcomes', () => {
    const p = position();
    p.dealerSeat = 0;
    p.exposedCards = p.trick.hands.flatMap((hand, seat) =>
      hand.map((c) => ({ cardId: c.id, seat, mayBeBuried: false })),
    );
    const e = experience(p);
    const counts = compareAlternatives(p, e, seededRandom(7));
    expect(counts).toEqual({
      positions: 1,
      rollouts: 8,
      informativePairs: 1,
      betterThanBaseline: 1,
    });
    // The counterfactual comparison is usable only when the observed outcome
    // agrees with its direction. Make this fixture represent that case.
    e.advantage = e.comparisons![0]!.better === e.chosen ? 1 : -1;
    let model = newPolicy(seededRandom(42)),
      optimizer = newOptimizer();
    expect(
      policyProbabilities(model, e.options).indexOf(
        Math.max(...policyProbabilities(model, e.options)),
      ),
    ).toBe(e.chosen);
    for (let i = 0; i < 20; i++) {
      const updated = updateFromOutcomes(model, [e], optimizer);
      model = updated.model;
      optimizer = updated.optimizer;
      expect(updated.kl).toBeLessThanOrEqual(0.01);
    }
    const probs = policyProbabilities(model, e.options);
    expect(e.options[probs.indexOf(Math.max(...probs))]!.cardIds).toEqual([
      '0:clubs:3',
    ]);
  });

  it('does not attach privileged simulator state to the recorded experience', () => {
    const p = position(),
      e = experience(p);
    compareAlternatives(p, e, seededRandom(9));
    expect(Object.keys(e).sort()).toEqual([
      'advantage',
      'chosen',
      'comparisons',
      'options',
      'temperature',
    ]);
    const serialized = JSON.stringify(e);
    expect(serialized).not.toContain('0:clubs:A');
    expect(serialized).not.toContain('0:diamonds:K');
  });

  it('does not let hidden hands or kitty change the belief-based comparison', () => {
    const original = position();
    const altered: RoundPosition = {
      ...original,
      trick: {
        ...original.trick,
        hands: [
          original.trick.hands[0]!,
          [card('spades', 'A'), card('hearts', 'K')],
          [card('diamonds', 'A'), card('clubs', '2')],
          [card('diamonds', '3'), card('spades', '4')],
        ],
      },
      kitty: [card('clubs', 'A')],
    };
    const first = experience(original);
    const second = experience(altered);
    expect(compareAlternatives(original, first, seededRandom(17))).toEqual(
      compareAlternatives(altered, second, seededRandom(17)),
    );
    expect(second.comparisons).toEqual(first.comparisons);
  });

  it('leaves actual play and deal randomness unchanged when taking snapshots', () => {
    const options = {
      seed: 42,
      playerCount: 4 as const,
      candidateTeam: 'A' as const,
      candidate: DEFAULT_BOT_LEAD_WEIGHTS,
      opponent: DEFAULT_BOT_LEAD_WEIGHTS,
      maxRounds: 1,
    };
    let calls = 0;
    const result = playTrainingMatch({
      ...options,
      onPosition: (p) => {
        if (calls++ === 0)
          rolloutRound(p, [p.trick.hands[p.trick.nextSeat!]![0]!.id], 'A');
      },
    });
    expect(calls).toBeGreaterThan(0);
    expect(result).toEqual(playTrainingMatch(options));
  }, 20000);
});
