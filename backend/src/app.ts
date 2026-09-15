import { randomInt, randomUUID } from 'node:crypto';
import Fastify from 'fastify';
import {
  createDeck,
  deal,
  gameConfig,
  PLAYER_COUNTS,
  RULES_VERSION,
  shuffle,
  teamAt,
} from '@tractor/rules';
import { previewRequestSchema, previewResponseSchema } from '@tractor/protocol';
import { registerPracticeRoutes } from './practice-routes.js';
import { registerRoundRoutes } from './round-routes.js';

export function buildApp(
  options: { logger?: boolean; pickIndex?: (maximum: number) => number } = {},
) {
  const app = Fastify({ logger: options.logger ?? false, bodyLimit: 4096 });
  const pickIndex = options.pickIndex ?? randomInt;

  app.addHook('onSend', async (_request, reply) => {
    reply.header('Cache-Control', 'no-store');
    reply.header('X-Content-Type-Options', 'nosniff');
  });

  app.get('/api/health', async () => ({
    status: 'ok',
    rulesVersion: RULES_VERSION,
  }));
  app.get('/api/config', async () => ({
    rulesVersion: RULES_VERSION,
    modes: PLAYER_COUNTS.map(gameConfig),
    capabilities: {
      practicePreview: true,
      practiceTricks: true,
      multiplayer: false,
    },
  }));

  registerPracticeRoutes(app);
  registerRoundRoutes(app);

  // Stateless practice deal, not a live match. No endpoint exposes the other hands.
  app.post('/api/practice-preview', async (request, reply) => {
    const parsed = previewRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({
        code: 'INVALID_SETTINGS',
        message: 'Choose a supported player count, level, and trump suit.',
      });
    }
    const settings = parsed.data;
    const { hands, kitty } = deal(
      shuffle(createDeck(settings.playerCount), pickIndex),
      settings.playerCount,
    );
    return previewResponseSchema.parse({
      kind: 'practice-preview',
      id: randomUUID(),
      rulesVersion: RULES_VERSION,
      settings,
      viewerSeat: 0,
      hand: hands[0],
      seats: hands.map((hand, seat) => ({
        seat,
        team: teamAt(seat),
        cardCount: hand.length,
      })),
      kittyCount: kitty.length,
    });
  });

  app.setErrorHandler((error, request, reply) => {
    const statusCode =
      error instanceof Error &&
      'statusCode' in error &&
      typeof error.statusCode === 'number'
        ? error.statusCode
        : 500;
    const status = statusCode >= 400 && statusCode < 500 ? statusCode : 500;
    if (status === 500) request.log.error({ err: error }, 'Request failed');
    void reply.code(status).send({
      code: status === 500 ? 'INTERNAL_ERROR' : 'INVALID_REQUEST',
      message:
        status === 500
          ? 'Something went wrong. Please try again.'
          : 'The request could not be accepted.',
    });
  });
  return app;
}
