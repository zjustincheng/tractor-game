import {
  advanceDeclaration,
  canOverturn,
  chooseBotBurial,
  chooseBotLead,
  chooseBotGambleLead,
  chooseBotDeclaration,
  chooseBotPlay,
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
} from '@tractor/rules';
import type {
  Declaration,
  MatchState,
  PlayerCount,
  RoundSettlement,
  TrickPlay,
  Trump,
} from '@tractor/rules';

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
  history: CompletedTrick[];
  rounds: { round: number; settlement: RoundSettlement }[];
  state: MatchState;
  captured: number;
  penalties: number;
  trickNumber: number;
  settlement: RoundSettlement | null;
  message: string;
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

function botDeclarations(state: MatchState, now: number): MatchState {
  for (let seat = 1; seat < state.playerCount; seat++) {
    const options = legalDeclarations(state, seat);
    const option = chooseBotDeclaration(
      options,
      state.hands[seat]!,
      state.levels[state.attackingTeam],
    );
    if (option)
      state = requireState(receiveDeclaration(state, seat, option, now));
  }
  return state;
}

export function newBotMatch(
  playerCount: PlayerCount,
  now: number,
  pick: (max: number) => number,
): BotMatch {
  const state = createRound({
    playerCount,
    dealerSeat: 0,
    attackingTeam: 'A',
    shoe: shuffle(createDeck(playerCount), pick),
    firstDeclarationDeadline: now + 8000,
  });
  return {
    history: [],
    rounds: [],
    state: botDeclarations(state, now),
    captured: 0,
    penalties: 0,
    trickNumber: 1,
    settlement: null,
    message: 'Declare trump or wait for the declaration window to close.',
  };
}

/** Stop at each human decision and each completed trick so the table can be reviewed. */
function runBots(match: BotMatch): BotMatch {
  let state = match.state;
  if (state.phase === 'kitty' && state.dealerSeat !== 0) {
    state = requireState(
      exchangeKitty(
        state,
        chooseBotBurial(
          [...state.hands[state.dealerSeat]!, ...state.kitty],
          state.kitty.length,
          state.trump!,
        ),
      ),
    );
  }
  let trick = state.trick;
  while (
    state.phase === 'tricks' &&
    trick?.status === 'playing' &&
    trick.nextSeat !== 0
  ) {
    const seat = trick.nextSeat!;
    const winnerSeat = trick.winnerSeat;
    const cards =
      trick.plays.length === 0
        ? (() => {
            const role =
              teamAt(seat) === trick.attackingTeam ? 'attackers' : 'defenders';
            const gamble = chooseBotGambleLead(
              trick.hands[seat]!,
              trick.hands.filter((_, index) => index !== seat),
              trick.trump,
              role,
            );
            return (
              gamble ??
              chooseBotLead(trick.hands[seat]!, trick.trump, {
                role,
                defenderScore: state.defenderScore,
                swapThreshold: trick.playerCount * 20,
                seenCards: match.history.flatMap((item) =>
                  item.plays.flatMap((play) => [...play.cards]),
                ),
              })
            );
          })()
        : chooseBotPlay(
            trick.hands[seat]!,
            trick.plays[0]!.components,
            trick.trump,
            trick.winnerSeat === null
              ? undefined
              : {
                  seat,
                  winnerSeat: trick.winnerSeat,
                  winning: trick.plays.find((play) => play.seat === winnerSeat)!
                    .components!,
                  lastToPlay: trick.plays.length === trick.playerCount - 1,
                },
          );
    const result = playCards(trick, seat, cards);
    if (!result.ok) throw new Error(result.message);
    trick = result.state;
  }
  if (trick) state = { ...state, trick, hands: trick.hands };
  match = { ...match, state };
  if (trick?.status === 'complete') {
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
      ].slice(-100),
      message: `${match.message.startsWith('Gamble failed;') ? match.message + ' ' : ''}Seat ${trick.winnerSeat! + 1} won trick ${match.trickNumber} (${trick.trickPoints} points).`,
    };
    if (trick.hands.every((hand) => hand.length === 0)) {
      const winning = trick.plays.find(
        (play) => play.seat === trick.winnerSeat,
      )!;
      const largest = [...winning.components!].sort(compareComponents)[0]!;
      const settlement = settleRound({
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
      match = {
        ...match,
        state: {
          ...state,
          phase: 'finished',
          defenderScore: settlement.defenderScore,
        },
        settlement,
        rounds: [...match.rounds, { round: state.round, settlement }].slice(
          -20,
        ),
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
    state = botDeclarations(
      requireState(receiveDeclaration(state, 0, option, now)),
      now,
    );
    return {
      ...match,
      state,
      message:
        'Declaration updated. Stronger declarations restart the eight-second window.',
    };
  }
  if (command.action === 'bury') {
    if (state.phase !== 'kitty' || state.dealerSeat !== 0)
      throw new CommandError('It is not your kitty exchange.');
    return runBots({
      ...match,
      state: requireState(exchangeKitty(state, command.cardIds ?? [])),
      message: 'Kitty buried. Lead the first trick.',
    });
  }
  if (command.action === 'play') {
    if (state.phase !== 'tricks' || !state.trick || state.trick.nextSeat !== 0)
      throw new CommandError('It is not your turn.');
    const result = playCards(state.trick, 0, command.cardIds ?? []);
    if (!result.ok) throw new CommandError(result.message);
    return runBots({
      ...match,
      state: { ...state, trick: result.state, hands: result.state.hands },
      message: result.reduced
        ? `Gamble failed; the weakest beatable component was played. Defender score adjustment: ${result.penalty}.`
        : 'Cards played.',
    });
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
      history: match.history,
      rounds: match.rounds,
      state: botDeclarations(state, now),
      captured: 0,
      penalties: 0,
      settlement: null,
      trickNumber: 1,
      message: 'New round. Declare trump or wait for the window to close.',
    };
  }
  if (state.phase === 'declaration') {
    state = requireState(advanceDeclaration(state, now, pick));
    if (state.phase === 'kitty' && state.round === 1)
      state = {
        ...state,
        dealerSeat: state.houseBuilderSeat!,
        attackingTeam: teamAt(state.houseBuilderSeat!),
      };
    return runBots({
      ...match,
      state,
      message:
        state.phase === 'kitty'
          ? 'Trump finalized. The dealer exchanges the kitty.'
          : 'A random declaration starts another eight-second window.',
    });
  }
  if (state.phase === 'tricks' && state.trick?.status === 'complete') {
    const trick = startTrick({
      playerCount: state.playerCount,
      trump: state.trump!,
      attackingTeam: state.attackingTeam,
      leaderSeat: state.trick.winnerSeat!,
      hands: state.hands,
    });
    return runBots({
      ...match,
      state: { ...state, trick },
      trickNumber: match.trickNumber + 1,
      message: 'Next trick.',
    });
  }
  throw new CommandError('There is no transition available.');
}
