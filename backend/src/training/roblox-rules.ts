import { canOverturn } from '@tractor/rules';
import type { Card, Declaration, MatchState } from '@tractor/rules';

/** Trump a bot must hold, jokers included, to call no-trump on a joker pair. */
export const ROBLOX_JOKER_PAIR_TRUMP = 5;

/**
 * The Roblox game also lets two of the same joker call no-trump. The website
 * rules stay as they are, so training adds these options itself. Matches
 * botWants in roblox/src/server/Practice.luau: bots use a bare pair only with
 * enough other trump behind it.
 */
export function robloxJokerPairs(
  state: MatchState,
  seat: number,
  dealt: readonly Card[],
): Declaration[] {
  if (state.phase !== 'declaration') return [];
  const level = state.levels[state.attackingTeam];
  const trumpCount = dealt.filter(
    (card) => card.kind === 'joker' || card.rank === level,
  ).length;
  if (trumpCount < ROBLOX_JOKER_PAIR_TRUMP) return [];
  const pairs: Declaration[] = [];
  for (const joker of ['small', 'big'] as const) {
    const cards = dealt.filter(
      (card) => card.kind === 'joker' && card.joker === joker,
    );
    if (cards.length < 2) continue;
    const option: Declaration = {
      kind: 'joker',
      playerSeat: seat,
      level,
      joker,
      multiplicity: 2,
      cardIds: cards.slice(0, 2).map((card) => card.id),
    };
    if (
      !state.declaration ||
      canOverturn(state.declaration, option, state.round === 1)
    )
      pairs.push(option);
  }
  return pairs;
}
