import {
  canOverturn,
  chooseRandomFallback,
  declarationsForHand,
  validateDeclaration,
} from './declarations.js';
import { deal, gameConfig, nextSeat } from './cards.js';
import type { Card, PlayerCount, Rank, Team, Trump } from './cards.js';
import { startTrick } from './trick.js';
import type { TrickState } from './trick.js';

export type MatchPhase = 'declaration' | 'kitty' | 'tricks' | 'finished';
export interface MatchState {
  readonly rulesVersion: string;
  readonly playerCount: PlayerCount;
  readonly round: number;
  readonly dealerSeat: number;
  readonly attackingTeam: Team;
  readonly levels: Readonly<Record<Team, Rank>>;
  readonly defenderScore: number;
  readonly hands: readonly (readonly Card[])[];
  readonly kitty: readonly Card[];
  readonly phase: MatchPhase;
  readonly declarationDeadline: number;
  readonly declaration: ReturnType<typeof declarationsForHand>[number] | null;
  readonly houseBuilderSeat: number | null;
  readonly trump: Trump | null;
  readonly trick: TrickState | null;
}

export type MatchError =
  | 'ROUND_NOT_OPEN'
  | 'NOT_YOUR_CARDS'
  | 'INVALID_DECLARATION'
  | 'DECLARATION_NOT_STRONGER'
  | 'DECLARATION_LOCKED'
  | 'NOT_DEALER'
  | 'INVALID_BURY'
  | 'ROUND_NOT_READY';
export type MatchResult =
  | { ok: true; state: MatchState }
  | { ok: false; code: MatchError; message: string };

export function createRound(input: {
  playerCount: PlayerCount;
  round?: number;
  dealerSeat: number;
  attackingTeam: Team;
  levels?: Readonly<Record<Team, Rank>>;
  defenderScore?: number;
  shoe: readonly Card[];
  firstDeclarationDeadline: number;
  rulesVersion?: string;
}): MatchState {
  const config = gameConfig(input.playerCount);
  nextSeat(input.dealerSeat, input.playerCount, 0);
  if (!Number.isSafeInteger(input.firstDeclarationDeadline))
    throw new RangeError('Declaration deadline must be an integer timestamp.');
  const levels = input.levels ?? { A: '2', B: '2' };
  const { hands, kitty } = deal(
    input.shoe,
    input.playerCount,
    input.dealerSeat,
  );
  if (hands.some((hand) => hand.length !== config.handSize))
    throw new Error('Round deal has unequal hand sizes.');
  return {
    rulesVersion: input.rulesVersion ?? '2.1-clarified.1',
    playerCount: input.playerCount,
    round: input.round ?? 1,
    dealerSeat: input.dealerSeat,
    attackingTeam: input.attackingTeam,
    levels,
    defenderScore: input.defenderScore ?? 0,
    hands,
    kitty,
    phase: 'declaration',
    declarationDeadline: input.firstDeclarationDeadline,
    declaration: null,
    houseBuilderSeat: null,
    trump: null,
    trick: null,
  };
}

export function receiveDeclaration(
  state: MatchState,
  seat: number,
  declaration: MatchState['declaration'],
  now: number,
): MatchResult {
  if (state.phase !== 'declaration')
    return {
      ok: false,
      code: 'ROUND_NOT_OPEN',
      message: 'The declaration window is closed.',
    };
  if (
    !declaration ||
    declaration.playerSeat !== seat ||
    !Number.isSafeInteger(now)
  )
    return {
      ok: false,
      code: 'INVALID_DECLARATION',
      message: 'That declaration is invalid.',
    };
  if (
    !validateDeclaration(
      declaration,
      state.hands[seat]!,
      state.playerCount,
      state.levels[state.attackingTeam],
    )
  )
    return {
      ok: false,
      code: 'INVALID_DECLARATION',
      message: 'Reveal the required level cards from your hand.',
    };
  if (
    state.declaration &&
    !canOverturn(state.declaration, declaration, state.round === 1)
  )
    return {
      ok: false,
      code: 'DECLARATION_NOT_STRONGER',
      message: 'That declaration cannot overturn the current declaration.',
    };
  return {
    ok: true,
    state: {
      ...state,
      declaration,
      declarationDeadline: now + 8000,
      houseBuilderSeat: declaration.playerSeat,
    },
  };
}

export function advanceDeclaration(
  state: MatchState,
  now: number,
  pickIndex: (exclusiveMaximum: number) => number,
): MatchResult {
  if (state.phase !== 'declaration')
    return {
      ok: false,
      code: 'ROUND_NOT_OPEN',
      message: 'The declaration window is closed.',
    };
  if (!Number.isSafeInteger(now) || now < state.declarationDeadline)
    return {
      ok: false,
      code: 'DECLARATION_LOCKED',
      message: 'The declaration window is still open.',
    };
  if (!state.declaration) {
    const fallback = chooseRandomFallback(
      state.hands,
      state.playerCount,
      state.levels[state.attackingTeam],
      pickIndex,
    );
    return {
      ok: true,
      state: {
        ...state,
        declaration: fallback,
        houseBuilderSeat: fallback.playerSeat,
        declarationDeadline: now + 8000,
      },
    };
  }
  const trump: Trump = {
    level: state.declaration.level,
    suit: state.declaration.kind === 'suit' ? state.declaration.suit : null,
  };
  return {
    ok: true,
    state: {
      ...state,
      phase: 'kitty',
      trump,
      declarationDeadline: now,
      houseBuilderSeat: state.declaration.playerSeat,
    },
  };
}

export function exchangeKitty(
  state: MatchState,
  buriedIds: readonly string[],
): MatchResult {
  if (
    state.phase !== 'kitty' ||
    !state.trump ||
    state.houseBuilderSeat === null
  )
    return {
      ok: false,
      code: 'ROUND_NOT_READY',
      message: 'The round is not ready for kitty exchange.',
    };
  if (state.dealerSeat < 0 || state.dealerSeat >= state.playerCount)
    return {
      ok: false,
      code: 'NOT_DEALER',
      message: 'The scheduled dealer is invalid.',
    };
  const dealerHand = [...state.hands[state.dealerSeat]!, ...state.kitty];
  const byId = new Map(dealerHand.map((card) => [card.id, card]));
  if (
    buriedIds.length !== state.kitty.length ||
    new Set(buriedIds).size !== buriedIds.length ||
    buriedIds.some((id) => !byId.has(id))
  )
    return {
      ok: false,
      code: 'INVALID_BURY',
      message: `Bury exactly ${state.kitty.length} cards from the dealer hand and kitty.`,
    };
  const buried = buriedIds.map((id) => byId.get(id)!);
  const hands = state.hands.map((hand, seat) =>
    seat === state.dealerSeat
      ? dealerHand.filter((card) => !buried.includes(card))
      : [...hand],
  );
  const trick = startTrick({
    playerCount: state.playerCount,
    trump: state.trump,
    attackingTeam: state.attackingTeam,
    leaderSeat: state.dealerSeat,
    hands,
  });
  return {
    ok: true,
    state: { ...state, hands, kitty: buried, phase: 'tricks', trick },
  };
}

export function declareOptions(state: MatchState, seat: number) {
  if (state.phase !== 'declaration' || seat < 0 || seat >= state.playerCount)
    return [];
  return declarationsForHand(
    state.hands[seat]!,
    state.playerCount,
    state.levels[state.attackingTeam],
    seat,
  );
}

export function defenderTeam(state: MatchState): Team {
  return state.attackingTeam === 'A' ? 'B' : 'A';
}

export function legalNextDeclarationSeat(state: MatchState): number[] {
  return Array.from({ length: state.playerCount }, (_, seat) => seat).filter(
    (seat) => declareOptions(state, seat).length > 0,
  );
}
