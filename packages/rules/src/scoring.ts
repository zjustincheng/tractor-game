import { gameConfig, RANKS } from './cards.js';
import type { PlayerCount, Rank } from './cards.js';

/** Apply to the final adjusted defender score, including penalties and kitty points. */
export function scoreOutcome(playerCount: PlayerCount, defenderScore: number) {
  if (!Number.isSafeInteger(defenderScore))
    throw new RangeError('Score must be a safe integer.');
  const { interval } = gameConfig(playerCount);
  if (defenderScore <= 0)
    return { advancingRole: 'attackers', levels: 3, swapRoles: false } as const;
  if (defenderScore < interval)
    return { advancingRole: 'attackers', levels: 2, swapRoles: false } as const;
  if (defenderScore < interval * 2)
    return { advancingRole: 'attackers', levels: 1, swapRoles: false } as const;
  return {
    advancingRole: 'defenders',
    levels: Math.floor(defenderScore / interval) - 2,
    swapRoles: true,
  } as const;
}

/** Call only for awarded advancement; a team arriving at J must stop there. */
export function advanceLevel(level: Rank, steps: number) {
  if (!Number.isSafeInteger(steps) || steps < 0)
    throw new RangeError('Advancement must be a nonnegative integer.');
  const start = RANKS.indexOf(level);
  const jack = RANKS.indexOf('J');
  const target = Math.min(
    start + steps,
    start < jack ? jack : RANKS.length - 1,
  );
  const nextLevel = RANKS[target]!;
  return { level: nextLevel, wonMatch: nextLevel === 'A' };
}

export function gamblePenalty(failedRole: 'attackers' | 'defenders'): number {
  return failedRole === 'attackers' ? 20 : -20;
}
