import { describe, expect, it, vi } from 'vitest';
import type { RoundSettlement, Team } from '@tractor/rules';
import { BASELINE_PRIOR, newPolicy, parsePolicy } from './learned-policy.js';
import {
  newPolicyCheckpoint,
  retainArchive,
  POLICY_ARCHIVE_LIMIT,
  trainPolicyGeneration,
} from './policy-training.js';
import { seededRandom } from './self-play.js';
import type * as SelfPlay from './self-play.js';

// Live Sharp is the only opponent passed as a whole BotPolicy; learned pairs
// arrive as individual lead/follow hooks. That is how the stub tells them apart.
const state = vi.hoisted(() => ({ loseToSharp: false }));

// A promotion needs matches the candidate clearly wins on both point and level
// margin. Real play cannot be steered that way, so the match itself is a stub:
// the promotion bookkeeping under test never inspects how the cards fell.
vi.mock('./self-play.js', async (importOriginal) => {
  const original = await importOriginal<typeof SelfPlay>();
  return {
    ...original,
    playTrainingMatch: (
      options: Parameters<typeof original.playTrainingMatch>[0],
    ) => {
      const candidate = options.candidateTeam;
      const other: Team = candidate === 'A' ? 'B' : 'A';
      const loses = state.loseToSharp && options.opponentPolicy !== undefined;
      const winner = loses ? other : candidate;
      const attackingTeam: Team = loses ? candidate : other;
      const levels = { A: '2', B: '2' } as const;
      const settlement = {
        defenderScore: options.playerCount * 40,
        kittyBasePoints: 0,
        kittyMultiplier: 1,
        kittyPoints: 0,
        outcome: { advancingRole: 'defenders', levels: 1, swapRoles: true },
        levels: winner === 'A' ? { A: '5', B: '2' } : { A: '2', B: '5' },
        attackingTeam: winner,
        rolesSwapped: true,
        jackReset: false,
        winner,
      } as unknown as RoundSettlement;
      options.onRound?.(settlement, { levels, attackingTeam });
      return {
        seed: options.seed,
        playerCount: options.playerCount,
        candidateTeam: candidate,
        winner,
        rounds: 1,
        decisions: 0,
        truncated: false,
        levels: settlement.levels,
        settlements: [settlement],
      };
    },
  };
});

function startingCheckpoint() {
  const checkpoint = newPolicyCheckpoint({
    seed: 42,
    playerCounts: [4],
    trainSeeds: 2,
    // Enough paired seeds to clear the minimum evaluation size.
    validationSeeds: 32,
    maxRounds: 1,
  });
  checkpoint.leadLearner = parsePolicy(newPolicy(seededRandom(81)));
  checkpoint.followLearner = parsePolicy(newPolicy(seededRandom(82)));
  checkpoint.learner = checkpoint.leadLearner;
  return checkpoint;
}

describe('promotion saves the evaluated policy', () => {
  it('saves both learner and champion exactly as evaluated', () => {
    state.loseToSharp = false;
    const checkpoint = startingCheckpoint();
    const evaluatedLead = structuredClone(checkpoint.leadLearner);
    const evaluatedFollow = structuredClone(checkpoint.followLearner);
    const phases: string[] = [];
    const next = trainPolicyGeneration(checkpoint, undefined, (phase) =>
      phases.push(phase),
    );
    const report = next.reports[0]!;
    expect(report.promoted).toBe(true);
    // The champion is byte-identical to the models the evaluation played.
    expect(next.leadChampion).toEqual(evaluatedLead);
    expect(next.followChampion).toEqual(evaluatedFollow);
    expect(next.champion).toEqual(evaluatedLead);
    expect(next.leadChampion!.priorScale).toBe(BASELINE_PRIOR);
    // The learner also retains the exact evaluated prior.
    expect(next.leadLearner).toEqual(evaluatedLead);
    expect(next.followLearner).toEqual(evaluatedFollow);
    expect(next.followLearner.priorScale).toBe(next.leadLearner.priorScale);
    expect({ ...next.leadLearner, priorScale: BASELINE_PRIOR }).toEqual(
      evaluatedLead,
    );
    expect(next.generationsSincePromotion).toBe(0);
    // The held-out opponent is part of both promotion stages.
    expect(phases).toContain('validation-sharp');
    expect(phases).toContain('confirmation-sharp');
    expect(report.vsSharp).not.toBeNull();
  }, 20000);

  it('refuses promotion when the held-out Sharp gate fails, and reports it when disabled', () => {
    state.loseToSharp = true;
    const blocked = trainPolicyGeneration(startingCheckpoint());
    expect(blocked.reports[0]!.promoted).toBe(false);
    expect(blocked.leadChampion).toBeNull();
    expect(blocked.leadLearner).toEqual(startingCheckpoint().leadLearner);
    expect(blocked.followLearner).toEqual(startingCheckpoint().followLearner);
    // Failing Sharp stops the run before the same-lineage archive gate.
    expect(blocked.reports[0]!.vsSharp).not.toBeNull();
    expect(blocked.reports[0]!.confirmation).toBeUndefined();
    const ungated = trainPolicyGeneration({
      ...startingCheckpoint(),
      sharpGate: false,
    });
    expect(ungated.reports[0]!.promoted).toBe(true);
    // Still measured, so a regression against Sharp stays visible.
    expect(ungated.reports[0]!.vsSharp).not.toBeNull();
    state.loseToSharp = false;
  }, 30000);
});

describe('opponent archive', () => {
  it('keeps the oldest policy and thins the middle once it is full', () => {
    let archive: string[] = [];
    for (const name of ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h'])
      archive = retainArchive(archive, name);
    expect(archive).toHaveLength(POLICY_ARCHIVE_LIMIT);
    archive = retainArchive(archive, 'i');
    // The first promotion of the run survives; a middle-aged entry gives way.
    expect(archive).toHaveLength(POLICY_ARCHIVE_LIMIT);
    expect(archive[0]).toBe('a');
    expect(archive.at(-1)).toBe('i');
    expect(archive).not.toContain('b');
  });
});
