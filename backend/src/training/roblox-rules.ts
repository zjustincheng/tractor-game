import {
  SUITS,
  canOverturn,
  category,
  startTrick,
  teamAt,
} from '@tractor/rules';
import type {
  Card,
  Declaration,
  MatchState,
  Rank,
  Suit,
  Trump,
} from '@tractor/rules';

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

/** A Chao Di call: a pair or more of level cards in one suit, or of one joker. */
export interface ChaodiCall {
  seat: number;
  suit: Suit | null;
  joker?: 'small' | 'big';
  count: number;
  cardIds: string[];
}
type ChaodiStanding = {
  count: number;
  suit: Suit | null;
  joker?: 'small' | 'big' | 'mixed';
};
const SUIT_RANK: Record<Suit, number> = {
  diamonds: 1,
  clubs: 2,
  hearts: 3,
  spades: 4,
};

/** Matches chaodiStronger in roblox/src/server/Practice.luau. */
export function chaodiStronger(
  current: ChaodiStanding | null,
  option: ChaodiStanding,
): boolean {
  if (!current) return true;
  if (current.count === 1) return option.count >= 2;
  if (current.suit) {
    if (option.count !== current.count) return option.count > current.count;
    if (!option.suit) return true;
    return SUIT_RANK[option.suit] > SUIT_RANK[current.suit];
  }
  if (option.count !== current.count) return option.count > current.count;
  return current.joker !== 'big' && option.joker === 'big';
}

function standingOf(declaration: Declaration | null): ChaodiStanding | null {
  if (!declaration) return null;
  return declaration.kind === 'suit'
    ? { count: declaration.multiplicity, suit: declaration.suit }
    : {
        count: declaration.multiplicity,
        suit: null,
        joker: declaration.joker,
      };
}

/** Matches Practice.chaodiOptions: every legal call, smallest first per kind. */
export function chaodiOptions(
  hand: readonly Card[],
  level: Rank,
  current: Declaration | null,
  seat: number,
): ChaodiCall[] {
  const standing = standingOf(current);
  const result: ChaodiCall[] = [];
  const add = (ids: string[], suit: Suit | null, joker?: 'small' | 'big') => {
    for (let count = 2; count <= ids.length; count++) {
      const call: ChaodiCall = {
        seat,
        suit,
        count,
        cardIds: ids.slice(0, count),
        ...(joker ? { joker } : {}),
      };
      if (chaodiStronger(standing, call)) result.push(call);
    }
  };
  for (const suit of SUITS)
    add(
      hand
        .filter(
          (card) =>
            card.kind === 'suited' && card.rank === level && card.suit === suit,
        )
        .map((card) => card.id),
      suit,
    );
  for (const joker of ['small', 'big'] as const)
    add(
      hand
        .filter((card) => card.kind === 'joker' && card.joker === joker)
        .map((card) => card.id),
      null,
      joker,
    );
  return result;
}

/** Matches Practice.chooseChaodi: call only when the new trump clearly helps. */
export function chooseRobloxChaodi(
  options: readonly ChaodiCall[],
  hand: readonly Card[],
  trump: Trump,
  sameTeamAsHolder: boolean,
): number | null {
  const trumps = (suit: Suit | null) =>
    hand.filter(
      (card) => category(card, { level: trump.level, suit }) === 'trump',
    ).length;
  const current = trumps(trump.suit);
  const needed = sameTeamAsHolder ? 4 : 2;
  let best: number | null = null;
  let bestCount = -1;
  options.forEach((option, index) => {
    const count = trumps(option.suit);
    if (
      count - current >= needed &&
      count >= hand.length / 4 &&
      count >= bestCount
    ) {
      best = index;
      bestCount = count;
    }
  });
  return best;
}

/**
 * The Roblox game's Chao Di round, run after the kitty is buried. Starting
 * after the kitty holder, each seat may overturn trump with a stronger call:
 * it takes the kitty and re-buries, and the challenge passes on. It ends when
 * everyone else passes in a row. The dealer, teams and first leader stay the
 * same. Returns the state with the trick rebuilt for the final trump.
 */
export function playRobloxChaodi(
  state: MatchState,
  choose: (
    seat: number,
    options: readonly ChaodiCall[],
    hand: readonly Card[],
    trump: Trump,
    sameTeamAsHolder: boolean,
  ) => number | null,
  bury: (
    seat: number,
    cards: readonly Card[],
    size: number,
    trump: Trump,
  ) => readonly string[],
  onCall?: (call: ChaodiCall) => void,
): MatchState {
  if (!state.trump) return state;
  let trump: Trump = state.trump;
  let declaration = state.declaration;
  let holder = state.dealerSeat;
  let kitty = [...state.kitty];
  const hands = state.hands.map((hand) => [...hand]);
  const passed = new Set<number>();
  let seat = (holder + 1) % state.playerCount;
  let calls = 0;
  while (passed.size < state.playerCount - 1 && calls < 64) {
    if (seat !== holder) {
      const hand = hands[seat]!;
      const options = chaodiOptions(hand, trump.level, declaration, seat);
      const index = options.length
        ? choose(seat, options, hand, trump, teamAt(seat) === teamAt(holder))
        : null;
      const call = index === null ? undefined : options[index];
      if (call) {
        calls++;
        onCall?.(call);
        trump = { level: trump.level, suit: call.suit };
        declaration = call.joker
          ? {
              kind: 'joker',
              playerSeat: seat,
              level: trump.level,
              joker: call.joker,
              multiplicity: call.count,
              cardIds: call.cardIds,
            }
          : {
              kind: 'suit',
              playerSeat: seat,
              level: trump.level,
              suit: call.suit!,
              multiplicity: call.count,
              cardIds: call.cardIds,
            };
        const pool = [...hand, ...kitty];
        const buriedIds = bury(seat, pool, kitty.length, trump);
        const buried = new Set(buriedIds);
        if (
          buried.size !== kitty.length ||
          [...buried].some((id) => !pool.some((card) => card.id === id))
        )
          throw new Error(
            'Chao Di re-burial must bury exactly the kitty size from hand and kitty.',
          );
        kitty = pool.filter((card) => buried.has(card.id));
        hands[seat] = pool.filter((card) => !buried.has(card.id));
        holder = seat;
        passed.clear();
      } else passed.add(seat);
    }
    seat = (seat + 1) % state.playerCount;
  }
  if (holder === state.dealerSeat && trump === state.trump) return state;
  const trick = startTrick({
    playerCount: state.playerCount,
    trump,
    attackingTeam: state.attackingTeam,
    leaderSeat: state.dealerSeat,
    hands,
  });
  return { ...state, hands, kitty, trump, declaration, trick };
}
