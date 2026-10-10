import { RANKS } from '@tractor/rules';
import type { Team, RoundSettlement } from '@tractor/rules';

/** Round reward uses actual level progress, including resets and match victory.
 * A bounded score term supplies feedback even when neither team advances. */
export function roundReward(
  before: Record<Team, (typeof RANKS)[number]>,
  settlement: RoundSettlement,
  team: Team,
  playerCount: number,
  attackingTeam: Team,
): number {
  const enemy = team === 'A' ? 'B' : 'A';
  const gain = (side: Team) =>
    RANKS.indexOf(settlement.levels[side]) - RANKS.indexOf(before[side]);
  const score = Math.max(
    -1,
    Math.min(
      1,
      (settlement.defenderScore - playerCount * 20) / (playerCount * 20),
    ),
  );
  return (
    (gain(team) - gain(enemy)) / 4 +
    (team === attackingTeam ? -score : score) * 0.1 +
    (settlement.winner ? (settlement.winner === team ? 1 : -1) : 0)
  );
}
