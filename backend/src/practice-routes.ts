import type { FastifyInstance } from 'fastify';
import { playCards } from '@tractor/rules';
import {
  exerciseAttemptSchema,
  exerciseListSchema,
  exerciseSuccessSchema,
} from '@tractor/protocol';
import { buildExercise, exerciseSummaries, exerciseView } from './exercises.js';

export function registerPracticeRoutes(app: FastifyInstance) {
  app.get('/api/practice-tricks', async () =>
    exerciseListSchema.parse({ exercises: exerciseSummaries }),
  );
  app.get<{ Params: { id: string } }>(
    '/api/practice-tricks/:id',
    async (request, reply) => {
      const exercise = buildExercise(request.params.id);
      if (!exercise)
        return reply.code(404).send({
          code: 'EXERCISE_NOT_FOUND',
          message: 'Choose an exercise from the list.',
        });
      return exerciseView(exercise);
    },
  );
  app.post<{ Params: { id: string } }>(
    '/api/practice-tricks/:id/attempt',
    async (request, reply) => {
      const exercise = buildExercise(request.params.id);
      if (!exercise)
        return reply.code(404).send({
          code: 'EXERCISE_NOT_FOUND',
          message: 'Choose an exercise from the list.',
        });
      const parsed = exerciseAttemptSchema.safeParse(request.body);
      if (!parsed.success)
        return reply.code(400).send({
          code: 'INVALID_SELECTION',
          message: 'Select distinct cards from the exercise hand.',
        });
      const result = playCards(
        exercise.state,
        exercise.viewerSeat,
        parsed.data.cardIds,
      );
      if (!result.ok)
        return reply
          .code(422)
          .send({ code: result.code, message: result.message });
      const play = result.state.plays.at(-1)!;
      const message = result.reduced
        ? `Gamble failed. Only ${play.cards.length} cards are played; ${result.returned.length} return to your hand. Defender score ${result.penalty > 0 ? '+' : ''}${result.penalty}.`
        : result.state.status === 'complete'
          ? result.state.winnerSeat === exercise.viewerSeat
            ? `You win the trick. Defenders capture ${result.state.capturedDefenderPoints} points.`
            : `${play.matchesLead ? 'Valid follow.' : 'Your play follows legally but cannot win this trick.'} Seat ${result.state.winnerSeat! + 1} wins. Defenders capture ${result.state.capturedDefenderPoints} points.`
          : `Lead accepted. The next player must follow ${play.cards.length} cards.`;
      return exerciseSuccessSchema.parse({
        accepted: true,
        view: exerciseView(exercise, result.state),
        reduced: result.reduced,
        returnedIds: result.returned.map((card) => card.id),
        playedIds: play.cards.map((card) => card.id),
        penalty: result.penalty,
        matchesLead: play.matchesLead,
        message,
      });
    },
  );
}
