import { describe, expect, it } from 'vitest';
import { newPolicy } from './learned-policy.js';
import {
  newPolicyCheckpoint,
  parsePolicyCheckpoint,
  resolveRobloxGuard,
  type RobloxGuard,
} from './policy-training.js';
import { seededRandom } from './self-play.js';

const pair = (seed: number) => ({
  lead: newPolicy(seededRandom(seed)),
  follow: newPolicy(seededRandom(seed + 1000)),
});

/** Feed win counts out of 256, one generation each, starting at `first`. */
function replay(scores: number[], first: number, start?: RobloxGuard) {
  let guard = start;
  const returns: { generation: number; to: unknown }[] = [];
  scores.forEach((wins, index) => {
    const generation = first + index;
    const result = resolveRobloxGuard({
      guard,
      winRate: wins / 256,
      generation,
      evaluated: pair(generation),
    });
    guard = result.guard;
    if (result.returnTo) returns.push({ generation, to: result.returnTo });
  });
  return { guard: guard!, returns };
}

describe('Roblox best-learner guard', () => {
  it('waits for a full window before keeping anything', () => {
    const { guard, returns } = replay([120, 120, 120], 1);
    expect(guard.best).toBeNull();
    expect(returns).toHaveLength(0);
  });

  it('keeps the learner that ended the best stretch', () => {
    const { guard } = replay([100, 100, 100, 100, 130, 130, 130, 130], 1);
    expect(guard.best?.generation).toBe(8);
    expect(guard.best?.winRate).toBeCloseTo(130 / 256);
    expect(guard.best?.lead).toEqual(pair(8).lead);
    expect(guard.best?.follow).toEqual(pair(8).follow);
  });

  it('rides out ordinary swings', () => {
    const { returns } = replay(
      [110, 110, 110, 110, 100, 120, 98, 118, 104, 112],
      1,
    );
    expect(returns).toHaveLength(0);
  });

  it('would have caught the decline in the generation 226-245 run', () => {
    const scores = [
      105, 104, 116, 117, 117, 120, 99, 115, 103, 103, 112, 92, 102, 80,
    ];
    const { guard, returns } = replay(scores, 226);
    expect(returns.map((entry) => entry.generation)).toEqual([239]);
    expect(returns[0]!.to).toEqual(pair(231));
    expect(guard.best?.generation).toBe(231);
    expect(guard.recent).toEqual([]);
  });

  it('gives a restored learner a full window before judging it again', () => {
    const start: RobloxGuard = {
      recent: [],
      best: { generation: 5, winRate: 0.5, ...pair(5) },
    };
    const early = replay([60, 60, 60], 6, start);
    expect(early.returns).toHaveLength(0);
    const full = replay([60, 60, 60, 60], 6, start);
    expect(full.returns.map((entry) => entry.generation)).toEqual([9]);
  });

  it('replaces the best once a restored learner does better', () => {
    const start: RobloxGuard = {
      recent: [],
      best: { generation: 5, winRate: 0.45, ...pair(5) },
    };
    const { guard, returns } = replay([125, 125, 125, 125], 6, start);
    expect(returns).toHaveLength(0);
    expect(guard.best?.generation).toBe(9);
  });

  it('survives a checkpoint save and resume', () => {
    const config = {
      seed: 1,
      trainSeeds: 2,
      validationSeeds: 2,
      maxRounds: 2,
      playerCounts: [4 as const],
    };
    const robloxGuard: RobloxGuard = {
      recent: [0.4, 0.42],
      best: { generation: 0, winRate: 0.45, ...pair(3) },
    };
    const loaded = parsePolicyCheckpoint(
      JSON.parse(
        JSON.stringify({ ...newPolicyCheckpoint(config), robloxGuard }),
      ),
    );
    expect(loaded.robloxGuard).toEqual(robloxGuard);
    expect(
      'robloxGuard' in
        parsePolicyCheckpoint(
          JSON.parse(JSON.stringify(newPolicyCheckpoint(config))),
        ),
    ).toBe(false);
  });
});
