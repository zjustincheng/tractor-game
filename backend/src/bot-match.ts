import { botPlayContext } from './bot-play-context.js';
import { randomInt, randomUUID } from 'node:crypto';
import { learnedBotPolicy } from './training/bot-policy.js';
import { heuristicPolicy } from './bot-policy.js';
import { BOT_DEAL_CARD_INTERVAL_MS } from '@tractor/protocol';
import {
  RULES_VERSION,
  advanceDeclaration,
  cardPoints,
  canOverturn,
  chooseBotGambleLead,
  category,
  chooseBotDeclaration,
  compareComponents,
  createDeck,
  createRound,
  declarationsForHand,
  exchangeKitty,
  nextDealer,
  playCards,
  receiveDeclaration,
  settleRound,
  shuffle,
  startTrick,
  teamAt,
  RANKS,
} from '@tractor/rules';
import type {
  BotLeadContext,
  Declaration,
  MatchState,
  PlayerCount,
  RoundSettlement,
  TrickPlay,
  Trump,
} from '@tractor/rules';
import type { Card } from '@tractor/rules';
import type { BotPolicy, PolicyActionKind } from './bot-policy.js';
import type { PolicyExperience } from './training/learned-policy.js';

export function policyForSeat(
  match: BotMatch,
  seat: number,
  loaded?: BotPolicy,
): BotPolicy | undefined {
  if (match.languageModel) {
    if (seat % 2 === 0) return heuristicPolicy('standard');
    if (!loaded?.forSeat)
      throw new Error(
        'Language-model decisions require the asynchronous turn runner.',
      );
    return loaded.forSeat(match, seat);
  }
  if (!match.playtest)
    return match.difficulty === 'expert' ? loaded : undefined;
  if (seat % 2 === 0) return heuristicPolicy('standard');
  if (match.playtest.opponent === 'sharp') return heuristicPolicy('sharp');
  // Record against this invocation's match, never a cached match closure.
  const record = (kind: PolicyActionKind) => (experience: PolicyExperience) => {
    const samples = match.playtest!.samples;
    if (experience.options.length < 2) return;
    const limit = kind === 'lead' || kind === 'follow' ? 48 : 16;
    const count = ++match.playtest!.observed[kind];
    const existing = samples.filter((sample) => sample.kind === kind);
    const slot = count <= limit ? existing.length : randomInt(count);
    if (slot >= limit) return;
    const sample = {
      id: randomUUID(),
      seat,
      kind,
      ...((kind === 'lead' || kind === 'follow') &&
      match.playtest!.currentDecision
        ? {
            round: match.playtest!.currentDecision.round,
            trick: match.playtest!.currentDecision.trick,
          }
        : {}),
      experience: structuredClone(experience),
    };
    if (slot < existing.length)
      samples[samples.indexOf(existing[slot]!)] = sample;
    else samples.push(sample);
  };
  return learnedBotPolicy(
    match.playtest.models.lead,
    match.playtest.models.follow,
    {
      lead: record('lead'),
      follow: record('follow'),
      declaration: record('declaration'),
      burial: record('burial'),
    },
  );
}

export interface CompletedTrick {
  round: number;
  number: number;
  trump: Trump;
  winnerSeat: number;
  points: number;
  defenderPoints: number;
  penalty: number;
  plays: readonly Pick<TrickPlay, 'seat' | 'cards' | 'matchesLead'>[];
}

export interface BotMatch {
  languageModel?: {
    model: string;
    previousId?: string;
    notes: Record<string, string>;
    decisions: number;
    cache: Record<string, string[]>;
    record: { humanWins: number; modelWins: number; matches: number };
  };
  playtest?: {
    opponent: 'sharp' | 'champion';
    models: NonNullable<BotPolicy['models']>;
    championId: string;
    previousId?: string;
    currentDecision?: { round: number; trick: number };
    feedbackCount: number;
    observed: Record<PolicyActionKind, number>;
    samples: {
      id: string;
      seat: number;
      kind: PolicyActionKind;
      round?: number;
      trick?: number;
      experience: PolicyExperience;
      preferredIndex?: number;
    }[];
  };
  difficulty?: 'relaxed' | 'standard' | 'sharp' | 'expert';
  quickMatch?: boolean;
  replay?: ReplayMetadata;
  dealingStartedAt?: number;
  history: CompletedTrick[];
  rounds: { round: number; settlement: RoundSettlement }[];
  state: MatchState;
  captured: number;
  penalties: number;
  trickNumber: number;
  settlement: RoundSettlement | null;
  message: string;
  botActions?: ReplayAction[];
}

export interface ReplayAction {
  action: 'play' | 'bury' | 'trick-complete';
  cardIds: readonly string[];
  seat?: number;
  round?: number;
  trick?: number;
  team?: 'A' | 'B';
  trump?: Trump;
  ledCategory?: string;
  hadLedCategory?: boolean;
  usedTrump?: boolean;
  jokerCount?: number;
  points?: number;
  winnerBefore?: number | null;
  winnerAfter?: number | null;
  winnerSeat?: number;
  trickPoints?: number;
  rating?:
    | 'lead'
    | 'validated_gamble'
    | 'protected_partner'
    | 'overtook_partner'
    | 'necessary_ruff'
    | 'failed_ruff'
    | 'overtook_opponent'
    | 'safe_follow';
  detail?: string;
}

export interface ReplayMetadata {
  rulesVersion: string;
  createdAt: number;
  dealerSeat: number;
  attackingTeam: 'A' | 'B';
  initialHands: readonly (readonly Card[])[];
  initialKitty: readonly Card[];
  deals: readonly ReplayDeal[];
}
export interface ReplayDeal {
  exposedCards?: { cardId: string; seat: number }[];
  round: number;
  dealerSeat: number;
  attackingTeam: 'A' | 'B';
  hands: readonly (readonly Card[])[];
  kitty: readonly Card[];
}

/** Lead knowledge comes only from public plays in this round. */
export function botLeadContext(match: BotMatch, seat: number): BotLeadContext {
  const history = match.history.filter(
    (item) => item.round === match.state.round,
  );
  const voids = new Map<string, { seat: number; category: string }>();
  for (const item of history) {
    const lead = item.plays[0]?.cards[0];
    if (!lead) continue;
    const ledCategory = category(lead, item.trump);
    for (const play of item.plays.slice(1)) {
      if (
        play.cards.some((card) => category(card, item.trump) !== ledCategory)
      ) {
        voids.set(`${play.seat}:${ledCategory}`, {
          seat: play.seat,
          category: ledCategory,
        });
      }
    }
  }
  return {
    seat,
    dealerSeat: match.state.dealerSeat,
    playerCount: match.state.playerCount,
    ...(match.state.hands[seat]
      ? { cardsRemaining: match.state.hands[seat].length }
      : {}),
    role:
      teamAt(seat) === match.state.attackingTeam ? 'attackers' : 'defenders',
    defenderScore: match.state.defenderScore,
    swapThreshold: match.state.playerCount * 20,
    seenCards: history.flatMap((item) =>
      item.plays.flatMap((play) => [...play.cards]),
    ),
    knownVoids: [...voids.values()],
  };
}

export class CommandError extends Error {}
function requireState(
  result: ReturnType<typeof receiveDeclaration>,
): MatchState {
  if (!result.ok) throw new CommandError(result.message);
  return result.state;
}

export function legalDeclarations(
  state: MatchState,
  seat: number,
): Declaration[] {
  if (state.phase !== 'declaration') return [];
  return declarationsForHand(
    state.hands[seat]!,
    state.playerCount,
    state.levels[state.attackingTeam],
    seat,
  ).filter(
    (option) =>
      !state.declaration ||
      (canOverturn(state.declaration, option, state.round === 1) &&
        !(
          state.declaration.playerSeat === seat &&
          state.declaration.kind === 'suit' &&
          option.kind === 'suit' &&
          option.suit !== state.declaration.suit
        )),
  );
}

function botDeclarations(
  state: MatchState,
  now: number,
  dealtCards = Number.POSITIVE_INFINITY,
  policy?: BotPolicy,
  match?: BotMatch,
  exposed?: { cardId: string; seat: number }[],
): MatchState {
  for (let seat = 1; seat < state.playerCount; seat++) {
    const options = legalDeclarations(state, seat).filter((option) =>
      option.cardIds.every((id) =>
        state.hands[seat]!.slice(0, dealtCards).some((card) => card.id === id),
      ),
    );
    const option = (
      (match ? policyForSeat({ ...match, state }, seat, policy) : policy)
        ?.declare ?? chooseBotDeclaration
    )(
      options,
      state.hands[seat]!.slice(0, dealtCards),
      state.levels[state.attackingTeam],
    );
    if (option) {
      state = requireState(receiveDeclaration(state, seat, option, now));
      exposed?.push(...option.cardIds.map((cardId) => ({ cardId, seat })));
    }
  }
  return state;
}

function initialDeclarations(state: MatchState, now: number): MatchState {
  return {
    ...state,
    declarationDeadline:
      now + state.hands[0]!.length * BOT_DEAL_CARD_INTERVAL_MS + 8000,
  };
}

/** Let bots call only with cards reached by the synchronized deal clock. */
export function progressBotDeclarations(
  match: BotMatch,
  now: number,
  policy?: BotPolicy,
): BotMatch {
  if (
    match.state.phase !== 'declaration' ||
    match.dealingStartedAt === undefined
  )
    return match;
  const dealt = Math.max(
    0,
    Math.floor((now - match.dealingStartedAt) / BOT_DEAL_CARD_INTERVAL_MS),
  );
  const exposed: { cardId: string; seat: number }[] = [];
  const state = botDeclarations(
    match.state,
    now,
    dealt,
    policy,
    match,
    exposed,
  );
  if (state === match.state) return match;
  return {
    ...recordExposedCards(match, exposed),
    state: {
      ...state,
      declarationDeadline: Math.max(
        state.declarationDeadline,
        match.dealingStartedAt +
          match.state.hands[0]!.length * BOT_DEAL_CARD_INTERVAL_MS +
          8000,
      ),
    },
  };
}

function recordExposedCards(
  match: BotMatch,
  exposed: { cardId: string; seat: number }[],
): BotMatch {
  if (!match.replay || !exposed.length) return match;
  return {
    ...match,
    replay: {
      ...match.replay,
      deals: match.replay.deals.map((deal) =>
        deal.round === match.state.round
          ? {
              ...deal,
              exposedCards: [
                ...new Map(
                  [...(deal.exposedCards ?? []), ...exposed].map((e) => [
                    e.cardId,
                    e,
                  ]),
                ).values(),
              ],
            }
          : deal,
      ),
    },
  };
}

export function newBotMatch(
  playerCount: PlayerCount,
  now: number,
  pick: (max: number) => number,
  difficulty: BotMatch['difficulty'] = 'standard',
  quickMatch = false,
): BotMatch {
  const startingLevel = quickMatch ? RANKS[pick(RANKS.length)]! : '2';
  const state = createRound({
    playerCount,
    dealerSeat: 0,
    attackingTeam: 'A',
    shoe: shuffle(createDeck(playerCount), pick),
    levels: { A: startingLevel, B: startingLevel },
    firstDeclarationDeadline: now + 8000,
  });
  return {
    difficulty,
    ...(quickMatch ? { quickMatch: true } : {}),
    replay: {
      rulesVersion: RULES_VERSION,
      createdAt: now,
      dealerSeat: state.dealerSeat,
      attackingTeam: state.attackingTeam,
      initialHands: state.hands.map((hand) => [...hand]),
      initialKitty: [...state.kitty],
      deals: [
        {
          round: state.round,
          dealerSeat: state.dealerSeat,
          attackingTeam: state.attackingTeam,
          hands: state.hands.map((hand) => [...hand]),
          kitty: [...state.kitty],
        },
      ],
    },
    history: [],
    rounds: [],
    dealingStartedAt: now,
    state: initialDeclarations(state, now),
    captured: 0,
    penalties: 0,
    trickNumber: 1,
    settlement: null,
    message: 'Declare trump or wait for the declaration window to close.',
  };
}

/** Stop at each human decision and each completed trick so the table can be reviewed. */
function runBots(match: BotMatch, policy?: BotPolicy): BotMatch {
  let state = match.state;
  const botActions: ReplayAction[] = [];
  if (state.phase === 'kitty' && state.dealerSeat !== 0) {
    const burial = (
      policyForSeat(match, state.dealerSeat, policy) ??
      heuristicPolicy('standard')
    ).bury(
      [...state.hands[state.dealerSeat]!, ...state.kitty],
      state.kitty.length,
      state.trump!,
    );
    state = requireState(exchangeKitty(state, burial));
    botActions.push({
      action: 'bury',
      cardIds: burial,
      seat: state.dealerSeat,
    });
  }
  let trick = state.trick;
  while (
    state.phase === 'tricks' &&
    trick?.status === 'playing' &&
    trick.nextSeat !== 0
  ) {
    const seat = trick.nextSeat!;
    if (match.playtest)
      match.playtest.currentDecision = {
        round: state.round,
        trick: match.trickNumber,
      };
    const cards =
      trick.plays.length === 0
        ? (() => {
            const leadContext = {
              ...botLeadContext(match, seat),
              beliefSearch:
                match.difficulty === 'sharp' || match.difficulty === 'expert',
            };
            return (
              policyForSeat(
                { ...match, state: { ...state, trick, hands: trick.hands } },
                seat,
                policy,
              ) ??
              heuristicPolicy(
                match.difficulty === 'relaxed'
                  ? 'relaxed'
                  : match.difficulty === 'sharp' ||
                      match.difficulty === 'expert' ||
                      seat === 3
                    ? 'sharp'
                    : 'standard',
              )
            ).lead(
              trick.hands[seat]!,
              trick.trump,
              { ...leadContext, cardsRemaining: trick.hands[seat]!.length },
              trick.hands.filter((_, index) => index !== seat),
            );
          })()
        : (
            policyForSeat(
              { ...match, state: { ...state, trick, hands: trick.hands } },
              seat,
              policy,
            ) ??
            heuristicPolicy(
              match.difficulty === 'sharp' || match.difficulty === 'expert'
                ? 'sharp'
                : 'standard',
            )
          ).follow(
            trick.hands[seat]!,
            trick.plays[0]!.components,
            trick.trump,
            trick.winnerSeat === null
              ? undefined
              : botPlayContext(trick, state.dealerSeat),
          );
    const result = playCards(trick, seat, cards);
    if (!result.ok) throw new Error(result.message);
    const wasOpeningGamble =
      !match.languageModel &&
      match.difficulty !== 'relaxed' &&
      trick.plays.length === 0 &&
      chooseBotGambleLead(
        trick.hands[seat]!,
        trick.hands.filter((_, index) => index !== seat),
        trick.trump,
        teamAt(seat) === trick.attackingTeam ? 'attackers' : 'defenders',
      )?.join('|') === cards.join('|');
    const playedCards = cards.map((id) =>
      trick!.hands[seat]!.find((card) => card.id === id)!,
    );
    const ledCategory =
      trick!.plays[0]?.components?.[0]?.category ??
      category(playedCards[0]!, trick!.trump);
    const partnerWinning =
      trick.winnerSeat !== null && teamAt(trick.winnerSeat) === teamAt(seat);
    const rating =
      trick.plays.length === 0
        ? wasOpeningGamble
          ? 'validated_gamble'
          : 'lead'
        : partnerWinning
          ? result.state.winnerSeat === seat
            ? 'overtook_partner'
            : 'protected_partner'
          : !trick.hands[seat]!.some(
                (card) => category(card, trick!.trump) === ledCategory,
              ) &&
              playedCards.some(
                (card) => category(card, trick!.trump) === 'trump',
              )
            ? result.state.winnerSeat === seat
              ? 'necessary_ruff'
              : 'failed_ruff'
            : result.state.winnerSeat === seat
              ? 'overtook_opponent'
              : 'safe_follow';
    botActions.push({
      action: 'play',
      cardIds: cards,
      seat,
      round: state.round,
      trick: match.trickNumber,
      team: teamAt(seat),
      trump: trick.trump,
      ledCategory,
      ...(trick.plays.length === 0
        ? {}
        : {
            hadLedCategory: trick.hands[seat]!.some(
              (card) => category(card, trick!.trump) === ledCategory,
            ),
          }),
      usedTrump: playedCards.some(
        (card) => category(card, trick!.trump) === 'trump',
      ),
      jokerCount: playedCards.filter((card) => card.kind === 'joker').length,
      points: playedCards.reduce((sum, card) => sum + cardPoints(card), 0),
      winnerBefore: trick.winnerSeat,
      winnerAfter: result.state.winnerSeat,
      rating,
      detail: trick.plays.length === 0 ? 'lead' : 'follow',
      ...(wasOpeningGamble ? { detail: 'validated gamble' } : {}),
    });
    trick = result.state;
  }
  if (trick) state = { ...state, trick, hands: trick.hands };
  match = { ...match, state, botActions };
  if (trick?.status === 'complete') {
    botActions.push({
      action: 'trick-complete',
      cardIds: [],
      seat: trick.winnerSeat!,
      round: state.round,
      trick: match.trickNumber,
      team: teamAt(trick.winnerSeat!),
      winnerSeat: trick.winnerSeat!,
      trickPoints: trick.trickPoints,
      detail: `Seat ${trick.winnerSeat! + 1} won for ${trick.trickPoints} points`,
    });
    const captured = match.captured + trick.capturedDefenderPoints;
    const penalties = match.penalties + trick.penaltyPoints;
    state = { ...state, defenderScore: captured + penalties };
    match = {
      ...match,
      captured,
      penalties,
      state,
      history: [
        ...match.history,
        {
          round: state.round,
          number: match.trickNumber,
          trump: state.trump!,
          winnerSeat: trick.winnerSeat!,
          points: trick.trickPoints,
          defenderPoints: trick.capturedDefenderPoints,
          penalty: trick.penaltyPoints,
          plays: trick.plays.map(({ seat, cards, matchesLead }) => ({
            seat,
            cards,
            matchesLead,
          })),
        },
      ],
      message: `${match.message.startsWith('Gamble failed;') ? match.message + ' ' : ''}Seat ${trick.winnerSeat! + 1} won trick ${match.trickNumber} (${trick.trickPoints} points).`,
    };
    if (trick.hands.every((hand) => hand.length === 0)) {
      const winning = trick.plays.find(
        (play) => play.seat === trick.winnerSeat,
      )!;
      const largest = [...winning.components!].sort(compareComponents)[0]!;
      const settled = settleRound({
        playerCount: state.playerCount,
        attackingTeam: state.attackingTeam,
        levels: state.levels,
        trickPoints: captured,
        gamblePenaltyPoints: penalties,
        finalTrickWinnerTeam: teamAt(trick.winnerSeat!),
        finalWinningCards: winning.cards,
        finalWinningStructure: largest,
        kitty: state.kitty,
      });
      const settlement = match.quickMatch
        ? {
            ...settled,
            winner:
              settled.outcome.advancingRole === 'attackers'
                ? state.attackingTeam
                : state.attackingTeam === 'A'
                  ? 'B'
                  : 'A',
          }
        : settled;
      match = {
        ...match,
        state: {
          ...state,
          phase: 'finished',
          defenderScore: settlement.defenderScore,
        },
        settlement,
        rounds: [...match.rounds, { round: state.round, settlement }],
        message: settlement.winner
          ? `Team ${settlement.winner} wins the match!`
          : `Round ${state.round} complete.`,
      };
    }
  }
  return match;
}

export type BotCommand = {
  action: 'declare' | 'bury' | 'play' | 'advance' | 'next-round';
  cardIds?: string[] | undefined;
};

export function commandBotMatch(
  match: BotMatch,
  command: BotCommand,
  now: number,
  pick: (max: number) => number,
  policy?: BotPolicy,
): BotMatch {
  let state = match.state;
  if (command.action === 'declare') {
    if (now >= state.declarationDeadline)
      throw new CommandError(
        'The declaration window has closed. Continue to finalize trump.',
      );
    const ids = [...(command.cardIds ?? [])].sort().join('|');
    const option = legalDeclarations(state, 0).find(
      (item) => [...item.cardIds].sort().join('|') === ids,
    );
    if (!option) throw new CommandError('Choose an available declaration.');
    if (match.dealingStartedAt !== undefined) {
      const dealt = Math.max(
        0,
        Math.floor((now - match.dealingStartedAt) / BOT_DEAL_CARD_INTERVAL_MS),
      );
      const available = new Set(
        state.hands[0]!.slice(0, dealt).map((card) => card.id),
      );
      if (!option.cardIds.every((id) => available.has(id)))
        throw new CommandError(
          'Wait for those cards to be dealt before declaring.',
        );
    }
    state = requireState(receiveDeclaration(state, 0, option, now));
    match = recordExposedCards(
      match,
      option.cardIds.map((cardId) => ({ cardId, seat: 0 })),
    );
    if (match.dealingStartedAt !== undefined)
      state = {
        ...state,
        declarationDeadline: Math.max(
          state.declarationDeadline,
          match.dealingStartedAt +
            state.hands[0]!.length * BOT_DEAL_CARD_INTERVAL_MS +
            8000,
        ),
      };
    const progressed = progressBotDeclarations(
      { ...match, state },
      now,
      policy,
    );
    return {
      ...progressed,
      message:
        'Declaration updated. Stronger declarations restart the eight-second window.',
    };
  }
  if (command.action === 'bury') {
    if (state.phase !== 'kitty' || state.dealerSeat !== 0)
      throw new CommandError('It is not your kitty exchange.');
    return runBots(
      {
        ...match,
        state: requireState(exchangeKitty(state, command.cardIds ?? [])),
        message: 'Kitty buried. Lead the first trick.',
      },
      policy,
    );
  }
  if (command.action === 'play') {
    if (state.phase !== 'tricks' || !state.trick || state.trick.nextSeat !== 0)
      throw new CommandError('It is not your turn.');
    const result = playCards(state.trick, 0, command.cardIds ?? []);
    if (!result.ok) throw new CommandError(result.message);
    return runBots(
      {
        ...match,
        state: { ...state, trick: result.state, hands: result.state.hands },
        message: result.reduced
          ? `Gamble failed; the weakest beatable component was played. Defender score adjustment: ${result.penalty}.`
          : 'Cards played.',
      },
      policy,
    );
  }
  if (command.action === 'next-round') {
    if (!match.settlement || match.settlement.winner)
      throw new CommandError('The next round is not available.');
    state = createRound({
      playerCount: state.playerCount,
      round: state.round + 1,
      dealerSeat: nextDealer(
        state.dealerSeat,
        state.playerCount,
        match.settlement.rolesSwapped,
      ),
      attackingTeam: match.settlement.attackingTeam,
      levels: match.settlement.levels,
      shoe: shuffle(createDeck(state.playerCount), pick),
      firstDeclarationDeadline: now + 8000,
    });
    return {
      difficulty: match.difficulty ?? 'standard',
      ...(match.quickMatch ? { quickMatch: true } : {}),
      ...(match.languageModel ? { languageModel: match.languageModel } : {}),
      ...(match.playtest ? { playtest: match.playtest } : {}),
      ...(match.replay
        ? {
            replay: {
              ...match.replay,
              deals: [
                ...match.replay.deals,
                {
                  round: state.round,
                  dealerSeat: state.dealerSeat,
                  attackingTeam: state.attackingTeam,
                  hands: state.hands.map((hand) => [...hand]),
                  kitty: [...state.kitty],
                },
              ],
            },
          }
        : {}),
      history: match.history,
      rounds: match.rounds,
      dealingStartedAt: now,
      state: initialDeclarations(state, now),
      captured: 0,
      penalties: 0,
      settlement: null,
      trickNumber: 1,
      message: 'New round. Declare trump or wait for the window to close.',
    };
  }
  if (state.phase === 'declaration') {
    state = requireState(advanceDeclaration(state, now, pick));
    if (state.declaration)
      match = recordExposedCards(
        match,
        state.declaration.cardIds.map((cardId) => ({
          cardId,
          seat: state.declaration!.playerSeat,
        })),
      );
    if (state.phase === 'kitty' && state.round === 1)
      state = {
        ...state,
        dealerSeat: state.houseBuilderSeat!,
        attackingTeam: teamAt(state.houseBuilderSeat!),
      };
    return runBots(
      {
        ...match,
        state,
        message:
          state.phase === 'kitty'
            ? 'Trump finalized. The dealer exchanges the kitty.'
            : 'A random declaration starts another eight-second window.',
      },
      policy,
    );
  }
  if (state.phase === 'tricks' && state.trick?.status === 'complete') {
    const trick = startTrick({
      playerCount: state.playerCount,
      trump: state.trump!,
      attackingTeam: state.attackingTeam,
      leaderSeat: state.trick.winnerSeat!,
      hands: state.hands,
    });
    return runBots(
      {
        ...match,
        state: { ...state, trick },
        trickNumber: match.trickNumber + 1,
        message: 'Next trick.',
      },
      policy,
    );
  }
  throw new CommandError('There is no transition available.');
}
