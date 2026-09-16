import { randomInt, randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import {
  botCommandSchema,
  botMatchViewSchema,
  practiceRoundCreateSchema,
} from '@tractor/protocol';
import { chooseBotBurial, chooseBotPlay, teamAt } from '@tractor/rules';
import type { Declaration } from '@tractor/rules';
import {
  CommandError,
  commandBotMatch,
  legalDeclarations,
  newBotMatch,
} from './bot-match.js';
import type { BotMatch } from './bot-match.js';
import { MatchStore } from './match-store.js';

function declarationView(item: Declaration) {
  return {
    kind: item.kind,
    level: item.level,
    multiplicity: item.multiplicity,
    cardIds: [...item.cardIds],
    suit: item.kind === 'suit' ? item.suit : null,
    joker: item.kind === 'joker' ? item.joker : null,
  };
}

export function botView(id: string, match: BotMatch, revision: number) {
  const { state, settlement } = match;
  const hand =
    state.phase === 'kitty' && state.dealerSeat === 0
      ? [...state.hands[0]!, ...state.kitty]
      : state.hands[0]!;
  const trick = state.trick;
  const seenCounts = { clubs: 0, diamonds: 0, hearts: 0, spades: 0, jokers: 0 };
  for (const card of match.history.flatMap((item) =>
    item.plays.flatMap((play) => [...play.cards]),
  )) {
    if (card.kind === 'joker') seenCounts.jokers += 1;
    else seenCounts[card.suit] += 1;
  }
  const suggestion =
    state.phase === 'kitty' && state.dealerSeat === 0
      ? chooseBotBurial(hand, state.kitty.length, state.trump!)
      : state.phase === 'tricks' && trick?.nextSeat === 0
        ? chooseBotPlay(
            hand,
            trick.plays[0]?.components ?? null,
            state.trump!,
            trick.winnerSeat === null
              ? undefined
              : {
                  seat: 0,
                  winnerSeat: trick.winnerSeat,
                  winning: trick.plays.find(
                    (play) => play.seat === trick.winnerSeat,
                  )!.components!,
                  lastToPlay: trick.plays.length === trick.playerCount - 1,
                },
          )
        : [];
  return botMatchViewSchema.parse({
    seenCounts,
    history: match.history,
    rounds: match.rounds.map(({ round, settlement }) => ({
      round,
      defenderScore: settlement.defenderScore,
      levels: settlement.levels,
      winner: settlement.winner,
    })),
    id,
    revision,
    playerCount: state.playerCount,
    phase: state.phase,
    round: state.round,
    trickNumber: match.trickNumber,
    levels: state.levels,
    attackingTeam: state.attackingTeam,
    dealerSeat: state.dealerSeat,
    defenderScore: state.defenderScore,
    capturedPoints: match.captured,
    penaltyPoints: match.penalties,
    trickPoints: trick?.trickPoints ?? 0,
    trickPenalty: trick?.penaltyPoints ?? 0,
    declarationDeadline: state.declarationDeadline,
    declaration: state.declaration
      ? {
          ...declarationView(state.declaration),
          playerSeat: state.declaration.playerSeat,
        }
      : null,
    declarationOptions: legalDeclarations(state, 0).map(declarationView),
    trump: state.trump,
    hand,
    kittyCount: state.kitty.length,
    seats: state.hands.map((cards, seat) => ({
      seat,
      team: teamAt(seat),
      cardCount: cards.length,
    })),
    plays:
      trick?.plays.map((play) => ({
        seat: play.seat,
        cards: play.cards,
        matchesLead: play.matchesLead,
      })) ?? [],
    nextSeat: trick?.nextSeat ?? null,
    trickComplete: trick?.status === 'complete',
    winnerSeat: trick?.winnerSeat ?? null,
    suggestion,
    message: match.message,
    settlement: settlement
      ? {
          defenderScore: settlement.defenderScore,
          kittyPoints: settlement.kittyPoints,
          kittyMultiplier: settlement.kittyMultiplier,
          levels: settlement.levels,
          attackingTeam: settlement.attackingTeam,
          jackReset: settlement.jackReset,
          winner: settlement.winner,
        }
      : null,
  });
}

export function registerBotRoutes(
  app: FastifyInstance,
  options: {
    now?: () => number;
    pickIndex?: (max: number) => number;
    saveDirectory?: string;
  } = {},
) {
  const now = options.now ?? Date.now;
  const pick = options.pickIndex ?? randomInt;
  // Random IDs act as private local practice-session tokens. No multiplayer identity is implied.
  const sessions = new MatchStore(options.saveDirectory, (id, entry) => {
    botView(id, entry.match, entry.revision);
  });
  const expire = () => {
    for (const [id, entry] of sessions)
      if (entry.touched < now() - 30 * 24 * 60 * 60 * 1000) sessions.delete(id);
  };
  app.post('/api/bot-matches', async (request, reply) => {
    const parsed = practiceRoundCreateSchema.safeParse(request.body);
    if (!parsed.success)
      return reply
        .code(400)
        .send({ message: 'Choose 4, 6, 8, or 10 players.' });
    expire();
    if (sessions.size >= 200)
      return reply
        .code(503)
        .send({ message: 'Practice tables are full. Try again later.' });
    const id = randomUUID();
    const entry = {
      match: newBotMatch(parsed.data.playerCount, now(), pick),
      revision: 0,
      touched: now(),
    };
    sessions.set(id, entry);
    return botView(id, entry.match, entry.revision);
  });
  app.get<{ Params: { id: string } }>(
    '/api/bot-matches/:id',
    async (request, reply) => {
      expire();
      const entry = sessions.get(request.params.id);
      if (!entry)
        return reply
          .code(404)
          .send({ message: 'This match expired. Start a new match.' });
      sessions.set(request.params.id, { ...entry, touched: now() });
      return botView(request.params.id, entry.match, entry.revision);
    },
  );
  app.post<{ Params: { id: string } }>(
    '/api/bot-matches/:id/commands',
    async (request, reply) => {
      expire();
      const entry = sessions.get(request.params.id);
      if (!entry)
        return reply
          .code(404)
          .send({ message: 'This match expired. Start a new match.' });
      const parsed = botCommandSchema
        .extend({ revision: botMatchViewSchema.shape.revision })
        .safeParse(request.body);
      if (!parsed.success)
        return reply.code(400).send({ message: 'Invalid match command.' });
      if (parsed.data.revision !== entry.revision)
        return reply.code(409).send({
          message: 'The table has changed. Refresh the match before playing.',
        });
      try {
        const match = commandBotMatch(entry.match, parsed.data, now(), pick);
        const result = botView(request.params.id, match, entry.revision + 1);
        sessions.set(request.params.id, {
          match,
          revision: entry.revision + 1,
          touched: now(),
        });
        return result;
      } catch (error) {
        if (error instanceof CommandError)
          return reply.code(422).send({ message: error.message });
        throw error;
      }
    },
  );
}
