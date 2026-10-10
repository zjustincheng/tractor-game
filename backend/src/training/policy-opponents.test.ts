import { describe, expect, it, vi } from 'vitest';
import * as policy from './learned-policy.js';
import {
  newPolicyCheckpoint,
  parsePolicyCheckpoint,
  trainPolicyGeneration,
} from './policy-training.js';
import { seededRandom } from './self-play.js';
import type * as SelfPlay from './self-play.js';

vi.mock('./learned-policy.js', async (importOriginal) => {
  const original = await importOriginal<typeof policy>();
  return {
    ...original,
    choosePolicyLead: vi.fn(() => []),
    choosePolicyPlay: vi.fn(() => []),
    choosePolicyDeclaration: vi.fn(() => null),
    choosePolicyBurial: vi.fn(() => []),
  };
});
vi.mock('./self-play.js', async (importOriginal) => {
  const original = await importOriginal<typeof SelfPlay>();
  return {
    ...original,
    playTrainingMatch: (
      options: Parameters<typeof original.playTrainingMatch>[0],
    ) => {
      const trump = { level: '2', suit: 'spades' } as const;
      options.opponentLead?.([], trump, {
        seat: 1,
        role: 'defenders',
        defenderScore: 0,
        swapThreshold: 80,
      });
      options.opponentPlay?.([], [], trump, {
        seat: 1,
        winnerSeat: 0,
        winning: [],
        lastToPlay: true,
      });
      options.opponentDeclaration?.([], [], '2');
      options.opponentBurial?.([], 0, trump);
      return {
        seed: options.seed,
        playerCount: options.playerCount,
        candidateTeam: options.candidateTeam,
        winner: null,
        rounds: 1,
        decisions: 0,
        truncated: true,
        levels: { A: '2', B: '2' },
        settlements: [],
      };
    },
  };
});

describe('complete opponent policies', () => {
  it('uses the follow network for follows, calls and burial when facing a champion', () => {
    const c = newPolicyCheckpoint({
      seed: 42,
      playerCounts: [4],
      trainSeeds: 2,
      validationSeeds: 1,
      maxRounds: 1,
    });
    c.leadChampion = policy.newPolicy(seededRandom(8));
    c.followChampion = policy.newPolicy(seededRandom(9));
    c.champion = c.leadChampion;
    trainPolicyGeneration(c);
    for (const call of vi.mocked(policy.choosePolicyLead).mock.calls)
      expect(call[0]).toBe(c.leadChampion);
    for (const fn of [
      policy.choosePolicyPlay,
      policy.choosePolicyDeclaration,
      policy.choosePolicyBurial,
    ]) {
      expect(fn).toHaveBeenCalled();
      for (const call of vi.mocked(fn).mock.calls)
        expect(call[0]).toBe(c.followChampion);
    }
  });

  it('skips archive evaluation once an earlier promotion gate fails', () => {
    const c = newPolicyCheckpoint({
      seed: 42,
      playerCounts: [4],
      trainSeeds: 2,
      validationSeeds: 1,
      maxRounds: 1,
    });
    c.leadChampion = policy.newPolicy(seededRandom(10));
    c.followChampion = policy.newPolicy(seededRandom(11));
    c.champion = c.leadChampion;
    c.policyArchive = [
      {
        lead: policy.newPolicy(seededRandom(12)),
        follow: policy.newPolicy(seededRandom(13)),
      },
    ];
    const phases: string[] = [];
    const next = trainPolicyGeneration(c, undefined, (phase) =>
      phases.push(phase),
    );
    expect(next.reports[0]!.promoted).toBe(false);
    expect(phases).toContain('validation-baseline');
    expect(phases).toContain('validation-champion');
    expect(phases).not.toContain('validation-archive');
    expect(next.reports[0]!.vsArchive).toBeNull();
  });

  it('keeps old learner weights but invalidates old champion eligibility', () => {
    const c = newPolicyCheckpoint({
      seed: 42,
      playerCounts: [4],
      trainSeeds: 1,
      validationSeeds: 1,
      maxRounds: 1,
    });
    c.policyVersion = 'contextual-leads-v5-adaptive-prior';
    c.champion = c.leadChampion = c.leadLearner;
    c.followChampion = c.followLearner;
    const archived = {
      lead: policy.newPolicy(seededRandom(14)),
      follow: policy.newPolicy(seededRandom(15)),
    };
    c.policyArchive = [archived];
    const migrated = parsePolicyCheckpoint(c);
    expect(migrated.leadLearner).toEqual(c.leadLearner);
    expect(migrated.champion).toBeNull();
    expect(migrated.followChampion).toBeNull();
    // The champion must re-earn its place, but sparring partners are kept:
    // discarding them on every version bump is what narrowed the pool.
    expect(migrated.policyArchive).toEqual([archived]);
  });
});
