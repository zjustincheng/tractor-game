import { gameConfig, RANKS } from './cards.js';
import type { Card, PlayerCount, Rank, Team } from './cards.js';
import type { Structure } from './structures.js';

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

export interface RoundSettlementInput {
  readonly playerCount: PlayerCount;
  readonly attackingTeam: Team;
  readonly levels: Readonly<Record<Team, Rank>>;
  readonly trickPoints: number;
  readonly finalTrickWinnerTeam: Team;
  readonly finalWinningCards: readonly Card[];
  readonly finalWinningStructure: Structure | null;
  readonly kitty: readonly Card[];
  readonly gamblePenaltyPoints?: number;
}

export interface RoundSettlement {
  readonly defenderScore: number;
  readonly kittyBasePoints: number;
  readonly kittyMultiplier: number;
  readonly kittyPoints: number;
  readonly outcome: ReturnType<typeof scoreOutcome>;
  readonly levels: Readonly<Record<Team, Rank>>;
  readonly attackingTeam: Team;
  readonly rolesSwapped: boolean;
  readonly jackReset: boolean;
  readonly winner: Team | null;
}

function isJackOnly(cards: readonly Card[], level: Rank): boolean {
  return (
    level === 'J' &&
    cards.length > 0 &&
    cards.every((card) => card.kind === 'suited' && card.rank === 'J')
  );
}

/** Settles only a completed round; callers provide the accumulated trick score. */
export function settleRound(input: RoundSettlementInput): RoundSettlement {
  if (!Number.isSafeInteger(input.trickPoints) || input.trickPoints < 0)
    throw new RangeError('Trick points must be a nonnegative integer.');
  const defenderTeam: Team = input.attackingTeam === 'A' ? 'B' : 'A';
  const kittyBasePoints = input.kitty.reduce(
    (sum, card) =>
      sum +
      (card.kind === 'suited' && card.rank === '5'
        ? 5
        : card.kind === 'suited' && (card.rank === '10' || card.rank === 'K')
          ? 10
          : 0),
    0,
  );
  const kittyMultiplier =
    input.finalTrickWinnerTeam === defenderTeam && input.finalWinningStructure
      ? input.finalWinningStructure.cardCount * 2
      : 0;
  const kittyPoints = kittyBasePoints * kittyMultiplier;
  const defenderScore =
    input.trickPoints + kittyPoints + (input.gamblePenaltyPoints ?? 0);
  const outcome = scoreOutcome(input.playerCount, defenderScore);
  const nextLevels: Record<Team, Rank> = {
    A: input.levels.A,
    B: input.levels.B,
  };
  let winner: Team | null = null;
  const advancingTeam =
    outcome.advancingRole === 'attackers' ? input.attackingTeam : defenderTeam;
  const advancement = advanceLevel(nextLevels[advancingTeam], outcome.levels);
  nextLevels[advancingTeam] = advancement.level;
  if (advancement.wonMatch) winner = advancingTeam;
  const jackReset =
    input.finalTrickWinnerTeam === defenderTeam &&
    input.levels[input.attackingTeam] === 'J' &&
    defenderScore >= gameConfig(input.playerCount).swapThreshold &&
    isJackOnly(input.finalWinningCards, input.levels[input.attackingTeam]) &&
    !input.finalWinningCards.some((card) => card.kind === 'joker');
  if (jackReset) nextLevels[input.attackingTeam] = '2';
  return {
    defenderScore,
    kittyBasePoints,
    kittyMultiplier,
    kittyPoints,
    outcome,
    levels: nextLevels,
    attackingTeam: outcome.swapRoles ? defenderTeam : input.attackingTeam,
    rolesSwapped: outcome.swapRoles,
    jackReset,
    winner,
  };
}
