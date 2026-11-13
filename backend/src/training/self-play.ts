import { botPlayContext } from '../bot-play-context.js';
import type { BotPolicy } from '../bot-policy.js';
import {
  advanceDeclaration,
  category,
  chooseBotBurial,
  chooseBotDeclaration,
  chooseBotLead,
  chooseBotPlay,
  compareComponents,
  createDeck,
  createRound,
  exchangeKitty,
  nextDealer,
  playCards,
  receiveDeclaration,
  settleRound,
  shuffle,
  startTrick,
  teamAt,
} from '@tractor/rules';
import type {
  BotLeadWeights,
  Card,
  Declaration,
  MatchState,
  PlayerCount,
  RoundSettlement,
  Team,
  TrickState,
  Trump,
} from '@tractor/rules';
import { legalDeclarations } from '../bot-match.js';
import {
  chooseRobloxChaodi,
  playRobloxChaodi,
  robloxJokerPairs,
} from './roblox-rules.js';
import type { ChaodiCall } from './roblox-rules.js';
import type { LeadPolicy, PlayPolicy } from './learned-policy.js';
import type { RoundPosition } from './counterfactual.js';

export const TRAINING_POLICY_VERSION = 'lead-search-v2-postgame-scorer';

export function seededRandom(seed: number): (max: number) => number {
  let value = seed >>> 0;
  return (max) => {
    value = (Math.imul(value, 1664525) + 1013904223) >>> 0;
    return Math.floor((value / 0x100000000) * max);
  };
}

export interface TrainingDecision {
  round: number;
  trick: number;
  seat: number;
  team: Team;
  role: 'attackers' | 'defenders';
  hand: readonly Card[];
  trump: Trump;
  publicPlays: { seat: number; cards: readonly Card[] }[];
  seenCards: readonly Card[];
  knownVoids: { seat: number; category: string }[];
  defenderScore: number;
  winnerBefore: number | null;
  chosenCards: readonly string[];
  winnerAfter: number | null;
}

export interface SelfPlayResult {
  seed: number;
  playerCount: PlayerCount;
  candidateTeam: Team;
  winner: Team | null;
  rounds: number;
  decisions: number;
  truncated: boolean;
  levels: MatchState['levels'];
  settlements: RoundSettlement[];
}

/** All seats act. Learned adapters ignore privileged hands; the live Sharp
 * adapter uses them only for its existing validated-throw behavior. */
export function playTrainingMatch(options: {
  seed: number;
  playerCount: PlayerCount;
  candidateTeam: Team;
  candidate: BotLeadWeights;
  opponent: BotLeadWeights;
  maxRounds: number;
  /** Also allow the Roblox game's joker-pair no-trump calls. */
  robloxRules?: boolean;
  candidatePolicy?: BotPolicy;
  opponentPolicy?: BotPolicy;
  candidateLead?: LeadPolicy;
  opponentLead?: LeadPolicy;
  candidatePlay?: PlayPolicy;
  opponentPlay?: PlayPolicy;
  candidateDeclaration?: (
    options: readonly Declaration[],
    hand: readonly Card[],
    level: Declaration['level'],
  ) => Declaration | null;
  candidateBurial?: (
    cards: readonly Card[],
    size: number,
    trump: Trump,
  ) => string[];
  opponentDeclaration?: NonNullable<
    Parameters<typeof playTrainingMatch>[0]['candidateDeclaration']
  >;
  opponentBurial?: NonNullable<
    Parameters<typeof playTrainingMatch>[0]['candidateBurial']
  >;
  /** Overrides every seat's Chao Di choice (tests); the Roblox heuristic otherwise. */
  chaodiDecision?: Parameters<typeof playRobloxChaodi>[1];
  /** Per-team Chao Di choices; the Roblox heuristic when absent. */
  candidateChaodi?: NonNullable<BotPolicy['chaodi']>;
  opponentChaodi?: NonNullable<BotPolicy['chaodi']>;
  /** Told about every Chao Di call (Roblox rules only). */
  onChaodi?: (call: ChaodiCall) => void;
  onRound?: (
    settlement: RoundSettlement,
    context: { levels: MatchState['levels']; attackingTeam: Team },
  ) => void;
  /** Offline trainer hook, never supplied to an acting policy. */
  onPosition?: (position: RoundPosition) => void;
  onDecision?: (decision: TrainingDecision) => void;
}): SelfPlayResult {
  if (!Number.isSafeInteger(options.maxRounds) || options.maxRounds < 1)
    throw new Error('maxRounds must be a positive integer');
  let levels: MatchState['levels'] = { A: '2', B: '2' };
  let attackingTeam: Team = 'A';
  let dealerSeat = 0;
  let decisions = 0;
  const settlements: RoundSettlement[] = [];
  for (let round = 1; round <= options.maxRounds; round++) {
    // Each round has its own random stream: earlier policy choices cannot shift later deals.
    const pick = seededRandom(
      (options.seed + Math.imul(round, 2654435761)) >>> 0,
    );
    let state = createRound({
      playerCount: options.playerCount,
      round,
      levels,
      attackingTeam,
      dealerSeat,
      shoe: shuffle(createDeck(options.playerCount), pick),
      firstDeclarationDeadline: 8000,
    });
    // Reveal every seat's cards in order, allowing calls using only cards already dealt.
    let now = 0;
    const exposed = new Map<string, number>();
    for (let dealt = 1; dealt <= state.hands[0]!.length; dealt++) {
      now += 400;
      for (let seat = 0; seat < options.playerCount; seat++) {
        const hand = state.hands[seat]!.slice(0, dealt);
        const ids = new Set(hand.map((card) => card.id));
        const declarationOptions = [
          ...legalDeclarations(state, seat).filter((option) =>
            option.cardIds.every((id) => ids.has(id)),
          ),
          ...(options.robloxRules ? robloxJokerPairs(state, seat, hand) : []),
        ];
        const declarationPolicy =
          teamAt(seat) === options.candidateTeam
            ? (options.candidatePolicy?.declare ?? options.candidateDeclaration)
            : (options.opponentPolicy?.declare ?? options.opponentDeclaration);
        const call = (declarationPolicy ?? chooseBotDeclaration)(
          declarationOptions,
          hand,
          levels[attackingTeam],
        );
        if (call) {
          const declared = receiveDeclaration(state, seat, call, now);
          if (!declared.ok) throw new Error(declared.message);
          state = declared.state;
          for (const id of call.cardIds) exposed.set(id, seat);
        }
      }
    }
    while (state.phase === 'declaration') {
      const advanced = advanceDeclaration(
        state,
        Math.max(now, state.declarationDeadline),
        pick,
      );
      if (!advanced.ok) throw new Error(advanced.message);
      state = advanced.state;
      if (state.declaration)
        for (const id of state.declaration.cardIds)
          exposed.set(id, state.declaration.playerSeat);
    }
    if (round === 1)
      state = {
        ...state,
        dealerSeat: state.houseBuilderSeat!,
        attackingTeam: teamAt(state.houseBuilderSeat!),
      };
    const burialPolicy =
      teamAt(state.dealerSeat) === options.candidateTeam
        ? (options.candidatePolicy?.bury ?? options.candidateBurial)
        : (options.opponentPolicy?.bury ?? options.opponentBurial);
    const buried = (burialPolicy ?? chooseBotBurial)(
      [...state.hands[state.dealerSeat]!, ...state.kitty],
      state.kitty.length,
      state.trump!,
    );
    const exchanged = exchangeKitty(state, buried);
    if (!exchanged.ok) throw new Error(exchanged.message);
    state = exchanged.state;
    // Roblox: after burial anyone may Chao Di (overturn trump, take and
    // re-bury the kitty) before the dealer leads.
    if (options.robloxRules)
      state = playRobloxChaodi(
        state,
        options.chaodiDecision ??
          ((seat, calls, hand, trump, sameTeam) =>
            (
              (teamAt(seat) === options.candidateTeam
                ? (options.candidatePolicy?.chaodi ?? options.candidateChaodi)
                : (options.opponentPolicy?.chaodi ?? options.opponentChaodi)) ??
              chooseRobloxChaodi
            )(calls, hand, trump, sameTeam)),
        (seat, cards, size, trump) =>
          (
            (teamAt(seat) === options.candidateTeam
              ? (options.candidatePolicy?.bury ?? options.candidateBurial)
              : (options.opponentPolicy?.bury ?? options.opponentBurial)) ??
            chooseBotBurial
          )(cards, size, trump),
        (call) => {
          for (const id of call.cardIds) exposed.set(id, call.seat);
          options.onChaodi?.(call);
        },
      );
    // Roblox (D16): throws are won or lost on their largest piece.
    let trick: TrickState = options.robloxRules
      ? { ...state.trick!, largestPatternWins: true }
      : state.trick!;
    let captured = 0;
    let penalties = 0;
    let trickNumber = 1;
    const seenCards: Card[] = [];
    const voids = new Map<string, { seat: number; category: string }>();
    for (;;) {
      const seat = trick.nextSeat!;
      const team = teamAt(seat);
      const role = team === state.attackingTeam ? 'attackers' : 'defenders';
      const hand = trick.hands[seat]!;
      const weights =
        team === options.candidateTeam ? options.candidate : options.opponent;
      const knownVoids = [...voids.values()];
      const cards =
        trick.plays.length === 0
          ? (
              (team === options.candidateTeam
                ? (options.candidatePolicy?.lead ?? options.candidateLead)
                : (options.opponentPolicy?.lead ?? options.opponentLead)) ??
              chooseBotLead
            )(
              hand,
              trick.trump,
              {
                seat,
                dealerSeat: state.dealerSeat,
                playerCount: options.playerCount,
                cardsRemaining: hand.length,
                role,
                defenderScore: captured + penalties,
                swapThreshold: options.playerCount * 20,
                seenCards,
                knownVoids,
                weights,
              },
              trick.hands.filter((_, index) => index !== seat),
            )
          : (
              (team === options.candidateTeam
                ? (options.candidatePolicy?.follow ?? options.candidatePlay)
                : (options.opponentPolicy?.follow ?? options.opponentPlay)) ??
              chooseBotPlay
            )(
              hand,
              trick.plays[0]!.components!,
              trick.trump,
              botPlayContext(trick, state.dealerSeat, knownVoids),
            );
      options.onPosition?.({
        trick,
        exposedCards: [...exposed].map(([cardId, seat]) => ({
          cardId,
          seat,
          mayBeBuried: seat === state.dealerSeat,
        })),
        dealerSeat: state.dealerSeat,
        levels,
        kitty: state.kitty,
        captured,
        penalties,
        seenCards: [...seenCards],
        knownVoids,
      });
      const result = playCards(trick, seat, cards);
      if (!result.ok)
        throw new Error(`Training produced an illegal move: ${result.message}`);
      options.onDecision?.({
        round,
        trick: trickNumber,
        seat,
        team,
        role,
        hand: [...hand],
        trump: trick.trump,
        publicPlays: trick.plays.map((play) => ({
          seat: play.seat,
          cards: [...play.cards],
        })),
        seenCards: [...seenCards],
        knownVoids,
        defenderScore: captured + penalties,
        winnerBefore: trick.winnerSeat,
        chosenCards: cards,
        winnerAfter: result.state.winnerSeat,
      });
      decisions++;
      trick = result.state;
      if (trick.status !== 'complete') continue;
      captured += trick.capturedDefenderPoints;
      penalties += trick.penaltyPoints;
      const ledCategory = category(trick.plays[0]!.cards[0]!, trick.trump);
      for (const play of trick.plays) {
        seenCards.push(...play.cards);
        if (
          play.cards.some((card) => category(card, trick.trump) !== ledCategory)
        )
          voids.set(`${play.seat}:${ledCategory}`, {
            seat: play.seat,
            category: ledCategory,
          });
      }
      if (trick.hands.every((hand) => hand.length === 0)) break;
      trick = startTrick({
        playerCount: options.playerCount,
        hands: trick.hands,
        trump: trick.trump,
        attackingTeam: state.attackingTeam,
        leaderSeat: trick.winnerSeat!,
        ...(options.robloxRules ? { largestPatternWins: true } : {}),
      });
      trickNumber++;
    }
    const winning = trick.plays.find((play) => play.seat === trick.winnerSeat)!;
    const settlement = settleRound({
      playerCount: options.playerCount,
      attackingTeam: state.attackingTeam,
      levels,
      trickPoints: captured,
      gamblePenaltyPoints: penalties,
      finalTrickWinnerTeam: teamAt(trick.winnerSeat!),
      finalWinningCards: winning.cards,
      finalWinningStructure: [...winning.components!].sort(
        compareComponents,
      )[0]!,
      kitty: state.kitty,
    });
    settlements.push(settlement);
    options.onRound?.(settlement, {
      levels,
      attackingTeam: state.attackingTeam,
    });
    levels = settlement.levels;
    if (settlement.winner)
      return {
        seed: options.seed,
        playerCount: options.playerCount,
        candidateTeam: options.candidateTeam,
        winner: settlement.winner,
        rounds: round,
        decisions,
        truncated: false,
        levels,
        settlements,
      };
    dealerSeat = nextDealer(
      state.dealerSeat,
      options.playerCount,
      settlement.rolesSwapped,
    );
    attackingTeam = settlement.attackingTeam;
  }
  return {
    seed: options.seed,
    playerCount: options.playerCount,
    candidateTeam: options.candidateTeam,
    winner: null,
    rounds: options.maxRounds,
    decisions,
    truncated: true,
    levels,
    settlements,
  };
}
