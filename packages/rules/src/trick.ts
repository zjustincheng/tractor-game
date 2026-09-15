import { cardPoints, gameConfig, nextSeat, teamAt } from './cards.js';
import type { Card, PlayerCount, Team, Trump } from './cards.js';
import { decomposeLead, withoutCards } from './components.js';
import type { Component } from './components.js';
import { validateFollow } from './follow.js';
import type { FollowError } from './follow.js';
import { validateGamble, winningComponents } from './gamble.js';

export interface TrickPlay {
  readonly seat: number;
  readonly cards: readonly Card[];
  readonly components: readonly Component[] | null;
  readonly matchesLead: boolean;
}

export interface TrickState {
  readonly playerCount: PlayerCount;
  readonly trump: Trump;
  readonly attackingTeam: Team;
  readonly leaderSeat: number;
  readonly nextSeat: number | null;
  readonly hands: readonly (readonly Card[])[];
  readonly plays: readonly TrickPlay[];
  readonly winnerSeat: number | null;
  readonly status: 'playing' | 'complete';
  readonly penaltyPoints: number;
  readonly capturedDefenderPoints: number;
  readonly trickPoints: number;
}

export type PlayError =
  | FollowError
  | 'TRICK_COMPLETE'
  | 'NOT_YOUR_TURN'
  | 'INVALID_CARDS'
  | 'INVALID_LEAD';
export type PlayResult =
  | { ok: false; code: PlayError; message: string }
  | {
      ok: true;
      state: TrickState;
      reduced: boolean;
      returned: readonly Card[];
      penalty: number;
    };

export function startTrick(input: {
  playerCount: PlayerCount;
  trump: Trump;
  attackingTeam: Team;
  leaderSeat: number;
  hands: readonly (readonly Card[])[];
}): TrickState {
  const { playerCount, hands, leaderSeat } = input;
  const config = gameConfig(playerCount);
  nextSeat(leaderSeat, playerCount, 0);
  const firstLength = hands[0]?.length ?? 0;
  const cards = hands.flat();
  if (
    hands.length !== playerCount ||
    firstLength === 0 ||
    firstLength > config.handSize ||
    hands.some((hand) => hand.length !== firstLength) ||
    new Set(cards.map((card) => card.id)).size !== cards.length
  )
    throw new Error(
      'Start a trick with equal, nonempty, disjoint hands of the supported size.',
    );
  return {
    ...input,
    hands: hands.map((hand) => [...hand]),
    trump: { ...input.trump },
    nextSeat: leaderSeat,
    plays: [],
    winnerSeat: null,
    status: 'playing',
    penaltyPoints: 0,
    capturedDefenderPoints: 0,
    trickPoints: 0,
  };
}

/** Pure command transition: rejected commands never consume cards or mutate the input state. */
export function playCards(
  state: TrickState,
  seat: number,
  cardIds: readonly string[],
): PlayResult {
  if (state.status === 'complete')
    return {
      ok: false,
      code: 'TRICK_COMPLETE',
      message: 'This trick is complete.',
    };
  if (seat !== state.nextSeat)
    return {
      ok: false,
      code: 'NOT_YOUR_TURN',
      message: 'Wait for your counterclockwise turn.',
    };
  const hand = state.hands[seat]!;
  const byId = new Map(hand.map((card) => [card.id, card]));
  if (
    cardIds.length === 0 ||
    new Set(cardIds).size !== cardIds.length ||
    cardIds.some((id) => !byId.has(id))
  )
    return {
      ok: false,
      code: 'INVALID_CARDS',
      message: 'Choose distinct cards from your own hand.',
    };
  const selected = cardIds.map((id) => byId.get(id)!);
  let cards: readonly Card[] = selected;
  let components: readonly Component[] | null;
  let matchesLead = true;
  let reduced = false;
  let returned: readonly Card[] = [];
  let penalty = 0;
  if (state.plays.length === 0) {
    components = decomposeLead(selected, state.trump);
    if (!components)
      return {
        ok: false,
        code: 'INVALID_LEAD',
        message: 'Lead cards must belong to one suit category or to trump.',
      };
    const gamble = validateGamble(
      components,
      state.hands.filter((_, index) => index !== seat),
      state.trump,
      teamAt(seat) === state.attackingTeam ? 'attackers' : 'defenders',
    );
    ({ components, cards, reduced, returned, penalty } = gamble);
  } else {
    const follow = validateFollow(
      hand,
      selected,
      state.plays[0]!.components!,
      state.trump,
    );
    if (!follow.legal)
      return { ok: false, code: follow.code, message: follow.message };
    components = follow.components;
    matchesLead = follow.matchesLead;
  }
  const currentWinner = state.plays.find(
    (previous) => previous.seat === state.winnerSeat,
  );
  const winningPartition =
    currentWinner && matchesLead
      ? winningComponents(
          cards,
          state.plays[0]!.components!,
          currentWinner.components!,
          state.trump,
        )
      : null;
  if (winningPartition) components = winningPartition;
  const winnerSeat =
    !currentWinner || winningPartition ? seat : currentWinner.seat;
  const play: TrickPlay = { seat, cards: [...cards], components, matchesLead };
  const plays = [...state.plays, play];
  const hands = state.hands.map((oldHand, index) =>
    index === seat ? withoutCards(oldHand, cards) : [...oldHand],
  );
  const complete = plays.length === state.playerCount;
  const trickPoints = plays
    .flatMap((previous) => previous.cards)
    .reduce((sum, card) => sum + cardPoints(card), 0);
  const capturedDefenderPoints =
    complete && teamAt(winnerSeat) !== state.attackingTeam ? trickPoints : 0;
  if (
    complete &&
    hands.some((remaining) => remaining.length !== hands[0]!.length)
  )
    throw new Error('Trick card-count invariant violated.');
  return {
    ok: true,
    reduced,
    returned,
    penalty,
    state: {
      ...state,
      hands,
      plays,
      winnerSeat,
      nextSeat: complete ? null : nextSeat(seat, state.playerCount),
      status: complete ? 'complete' : 'playing',
      penaltyPoints: state.penaltyPoints + penalty,
      capturedDefenderPoints,
      trickPoints,
    },
  };
}

export function nextTrick(state: TrickState): TrickState {
  if (state.status !== 'complete' || state.winnerSeat === null)
    throw new Error('Finish the current trick first.');
  return startTrick({
    playerCount: state.playerCount,
    trump: state.trump,
    attackingTeam: state.attackingTeam,
    leaderSeat: state.winnerSeat,
    hands: state.hands,
  });
}
