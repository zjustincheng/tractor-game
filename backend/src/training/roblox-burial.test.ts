import { describe, expect, it } from 'vitest';
import type { Card, Trump } from '@tractor/rules';
import {
  choosePolicyBurial,
  newPolicy,
  robloxBurialChoices,
  type PolicyExperience,
} from './learned-policy.js';
import { robloxBurial } from './roblox-bot.js';
import {
  newPolicyCheckpoint,
  trainPolicyGeneration,
} from './policy-training.js';
import { seededRandom } from './self-play.js';

const card = (rank: string, suit: string, copy = 0): Card =>
  ({ id: `${copy}:${suit}:${rank}`, kind: 'suited', rank, suit }) as Card;
const trump = { level: '2', suit: 'spades' } as unknown as Trump;
const cards = [
  card('3', 'clubs'),
  card('6', 'clubs'),
  card('4', 'hearts'),
  card('7', 'hearts'),
  card('9', 'hearts'),
  card('5', 'diamonds'),
  card('K', 'diamonds'),
  card('8', 'diamonds'),
  card('10', 'diamonds'),
  card('J', 'diamonds'),
  card('3', 'spades'),
  card('A', 'spades'),
];

function offered(robloxRules: boolean) {
  let seen: PolicyExperience | undefined;
  const chosen = choosePolicyBurial(
    newPolicy(seededRandom(5)),
    cards,
    2,
    trump,
    undefined,
    (experience) => (seen = experience),
    robloxRules,
  );
  return { chosen, seen: seen! };
}

describe('Roblox-rules burial', () => {
  it('uses the Roblox burial as its baseline', () => {
    const { seen } = offered(true);
    const baseline = seen.options.filter((option) => option.prior > 0);
    expect(baseline).toHaveLength(1);
    expect(baseline[0]!.cardIds).toEqual(robloxBurial(cards, 2, trump));
  });

  it('offers a choice that empties the shortest suit', () => {
    const voiding = robloxBurialChoices(cards, 2, trump)[1]!;
    expect([...voiding].sort()).toEqual(['0:clubs:3', '0:clubs:6']);
  });

  it('offers only full-size burials that keep trump when it can', () => {
    for (const ids of robloxBurialChoices(cards, 3, trump)) {
      expect(new Set(ids).size).toBe(3);
      expect(ids.some((id) => id.includes('spades'))).toBe(false);
    }
  });

  it('gives its features the same shape as the website burial', () => {
    expect(offered(true).seen.options[0]!.features).toHaveLength(
      offered(false).seen.options[0]!.features.length,
    );
  });

  it('leaves website burials unchanged', () => {
    const { seen } = offered(false);
    expect(seen.options[0]!.features.slice(7).every((v) => v === 0)).toBe(true);
    expect(seen.options.length).toBeLessThanOrEqual(3);
  });

  it('skips baseline and Sharp when the Roblox score cannot promote', () => {
    const next = trainPolicyGeneration({
      ...newPolicyCheckpoint({
        seed: 3,
        trainSeeds: 1,
        validationSeeds: 2,
        maxRounds: 2,
        playerCounts: [4 as const],
      }),
      robloxRules: true,
    });
    const report = next.reports.at(-1)!;
    expect(report.vsRoblox?.games).toBe(4);
    expect(report.vsBaseline.games).toBe(0);
    expect(report.vsSharp).toBeNull();
    expect(report.promoted).toBe(false);
  }, 30000);
});
