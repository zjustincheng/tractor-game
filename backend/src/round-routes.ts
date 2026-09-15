import { randomInt, randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import {
  createDeck,
  createRound,
  declarationsForHand,
  receiveDeclaration,
  advanceDeclaration,
  exchangeKitty,
  shuffle,
  RULES_VERSION,
  teamAt,
} from '@tractor/rules';
import type { Declaration, MatchState } from '@tractor/rules';
import {
  practiceRoundCreateSchema,
  practiceRoundDeclarationSchema,
  practiceRoundKittySchema,
  practiceRoundViewSchema,
} from '@tractor/protocol';

function declarationView(declaration: Declaration) {
  return {
    kind: declaration.kind,
    level: declaration.level,
    suit: declaration.kind === 'suit' ? declaration.suit : null,
    joker: declaration.kind === 'joker' ? declaration.joker : null,
    multiplicity: declaration.multiplicity,
    cardIds: [...declaration.cardIds],
  };
}

function view(id: string, state: MatchState) {
  const hand = state.hands[0]!;
  return practiceRoundViewSchema.parse({
    id,
    rulesVersion: RULES_VERSION,
    playerCount: state.playerCount,
    round: state.round,
    phase: state.phase,
    dealerSeat: state.dealerSeat,
    attackingTeam: state.attackingTeam,
    levels: state.levels,
    defenderScore: state.defenderScore,
    declarationDeadline: state.declarationDeadline,
    declaration: state.declaration ? declarationView(state.declaration) : null,
    houseBuilderSeat: state.houseBuilderSeat,
    trump: state.trump,
    viewerSeat: 0,
    hand,
    seats: state.hands.map((cards, seat) => ({
      seat,
      team: teamAt(seat),
      cardCount: cards.length,
    })),
    kittyCount: state.kitty.length,
    declarationOptions: declarationsForHand(
      hand,
      state.playerCount,
      state.levels[state.attackingTeam],
      0,
    ).map(declarationView),
  });
}

export function registerRoundRoutes(
  app: FastifyInstance,
  options: { pickIndex?: (max: number) => number; now?: () => number } = {},
) {
  const rounds = new Map<string, MatchState>();
  const pick = options.pickIndex ?? randomInt;
  const clock = options.now ?? Date.now;
  app.post('/api/practice-rounds', async (request, reply) => {
    const parsed = practiceRoundCreateSchema.safeParse(request.body);
    if (!parsed.success)
      return reply.code(400).send({
        code: 'INVALID_SETTINGS',
        message: 'Choose a supported player count and team.',
      });
    const id = randomUUID();
    const now = clock();
    const state = createRound({
      playerCount: parsed.data.playerCount,
      dealerSeat: 0,
      attackingTeam: parsed.data.attackingTeam,
      shoe: shuffle(createDeck(parsed.data.playerCount), pick),
      firstDeclarationDeadline: now + 8000,
    });
    rounds.set(id, state);
    return view(id, state);
  });
  app.get<{ Params: { id: string } }>(
    '/api/practice-rounds/:id',
    async (request, reply) => {
      const state = rounds.get(request.params.id);
      if (!state)
        return reply.code(404).send({
          code: 'ROUND_NOT_FOUND',
          message: 'That practice round has expired.',
        });
      return view(request.params.id, state);
    },
  );
  app.post<{ Params: { id: string } }>(
    '/api/practice-rounds/:id/declaration',
    async (request, reply) => {
      const state = rounds.get(request.params.id);
      if (!state)
        return reply.code(404).send({
          code: 'ROUND_NOT_FOUND',
          message: 'That practice round has expired.',
        });
      const parsed = practiceRoundDeclarationSchema.safeParse(request.body);
      if (!parsed.success)
        return reply.code(400).send({
          code: 'INVALID_DECLARATION',
          message: 'Choose a declaration from your available cards.',
        });
      const options = declarationsForHand(
        state.hands[0]!,
        state.playerCount,
        state.levels[state.attackingTeam],
        0,
      );
      const ids = [...parsed.data.cardIds].sort().join('|');
      const declaration = options.find(
        (item) => [...item.cardIds].sort().join('|') === ids,
      );
      if (!declaration)
        return reply.code(422).send({
          code: 'INVALID_DECLARATION',
          message: 'That declaration is not legal from your hand.',
        });
      const result = receiveDeclaration(state, 0, declaration, clock());
      if (!result.ok)
        return reply
          .code(422)
          .send({ code: result.code, message: result.message });
      rounds.set(request.params.id, result.state);
      return view(request.params.id, result.state);
    },
  );
  app.post<{ Params: { id: string } }>(
    '/api/practice-rounds/:id/advance',
    async (request, reply) => {
      const state = rounds.get(request.params.id);
      if (!state)
        return reply.code(404).send({
          code: 'ROUND_NOT_FOUND',
          message: 'That practice round has expired.',
        });
      const result = advanceDeclaration(state, clock(), pick);
      if (!result.ok)
        return reply
          .code(409)
          .send({ code: result.code, message: result.message });
      rounds.set(request.params.id, result.state);
      return view(request.params.id, result.state);
    },
  );
  app.post<{ Params: { id: string } }>(
    '/api/practice-rounds/:id/kitty',
    async (request, reply) => {
      const state = rounds.get(request.params.id);
      if (!state)
        return reply.code(404).send({
          code: 'ROUND_NOT_FOUND',
          message: 'That practice round has expired.',
        });
      const parsed = practiceRoundKittySchema.safeParse(request.body);
      if (!parsed.success)
        return reply.code(400).send({
          code: 'INVALID_BURY',
          message: 'Choose the cards to bury from the dealer hand.',
        });
      const result = exchangeKitty(state, parsed.data.buriedIds);
      if (!result.ok)
        return reply
          .code(422)
          .send({ code: result.code, message: result.message });
      rounds.set(request.params.id, result.state);
      return view(request.params.id, result.state);
    },
  );
}
