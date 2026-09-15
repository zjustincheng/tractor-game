import { z } from 'zod';
import { PLAYER_COUNTS, RANKS, SUITS } from '@tractor/rules';

export const previewRequestSchema = z.strictObject({
  playerCount: z.union(PLAYER_COUNTS.map((count) => z.literal(count))),
  level: z.enum(RANKS),
  trumpSuit: z.enum(SUITS).nullable(),
});

export const cardSchema = z.discriminatedUnion('kind', [
  z.strictObject({
    id: z.string(),
    kind: z.literal('suited'),
    suit: z.enum(SUITS),
    rank: z.enum(RANKS),
  }),
  z.strictObject({
    id: z.string(),
    kind: z.literal('joker'),
    joker: z.enum(['small', 'big']),
  }),
]);

export const previewResponseSchema = z.strictObject({
  kind: z.literal('practice-preview'),
  id: z.string().uuid(),
  rulesVersion: z.string(),
  settings: previewRequestSchema,
  viewerSeat: z.literal(0),
  hand: z.array(cardSchema),
  seats: z.array(
    z.strictObject({
      seat: z.number().int().nonnegative(),
      team: z.enum(['A', 'B']),
      cardCount: z.number().int().nonnegative(),
    }),
  ),
  kittyCount: z.number().int().positive(),
});

export type PreviewRequest = z.infer<typeof previewRequestSchema>;
export type PreviewResponse = z.infer<typeof previewResponseSchema>;

export const exerciseSummarySchema = z.strictObject({
  id: z.string().min(1).max(80),
  title: z.string(),
  description: z.string(),
});
export const exerciseListSchema = z.strictObject({
  exercises: z.array(exerciseSummarySchema).min(1),
});
export const exerciseViewSchema = z.strictObject({
  ...exerciseSummarySchema.shape,
  tip: z.string(),
  rulesVersion: z.string(),
  settings: previewRequestSchema,
  viewerSeat: z.number().int().nonnegative(),
  attackingTeam: z.enum(['A', 'B']),
  hand: z.array(cardSchema),
  seats: previewResponseSchema.shape.seats,
  plays: z.array(
    z.strictObject({
      seat: z.number().int().nonnegative(),
      cards: z.array(cardSchema),
      matchesLead: z.boolean(),
    }),
  ),
  nextSeat: z.number().int().nonnegative().nullable(),
  winnerSeat: z.number().int().nonnegative().nullable(),
  status: z.enum(['playing', 'complete']),
  penaltyPoints: z.number().int(),
  capturedDefenderPoints: z.number().int().nonnegative(),
  trickPoints: z.number().int().nonnegative(),
});
export const exerciseAttemptSchema = z.strictObject({
  cardIds: z
    .array(z.string().min(1).max(100))
    .min(1)
    .max(26)
    .refine(
      (ids) => new Set(ids).size === ids.length,
      'Cards must be distinct.',
    ),
});
export const exerciseSuccessSchema = z.strictObject({
  accepted: z.literal(true),
  view: exerciseViewSchema,
  reduced: z.boolean(),
  returnedIds: z.array(z.string()),
  playedIds: z.array(z.string()),
  penalty: z.number().int(),
  matchesLead: z.boolean(),
  message: z.string(),
});
export const exerciseErrorSchema = z.strictObject({
  code: z.string(),
  message: z.string(),
});
export type ExerciseSummary = z.infer<typeof exerciseSummarySchema>;
export type ExerciseView = z.infer<typeof exerciseViewSchema>;
export type ExerciseSuccess = z.infer<typeof exerciseSuccessSchema>;

export const practiceRoundCreateSchema = z.strictObject({
  playerCount: z.union(PLAYER_COUNTS.map((count) => z.literal(count))),
  attackingTeam: z.enum(['A', 'B']).default('A'),
});
export const declarationViewSchema = z.strictObject({
  kind: z.enum(['suit', 'joker']),
  level: z.enum(RANKS),
  suit: z.enum(SUITS).nullable(),
  joker: z.enum(['small', 'big', 'mixed']).nullable(),
  multiplicity: z.number().int().positive(),
  cardIds: z.array(z.string()),
});
export const practiceRoundViewSchema = z.strictObject({
  id: z.string().uuid(),
  rulesVersion: z.string(),
  playerCount: z.union(PLAYER_COUNTS.map((count) => z.literal(count))),
  round: z.number().int().positive(),
  phase: z.enum(['declaration', 'kitty', 'tricks', 'finished']),
  dealerSeat: z.number().int().nonnegative(),
  attackingTeam: z.enum(['A', 'B']),
  levels: z.strictObject({ A: z.enum(RANKS), B: z.enum(RANKS) }),
  defenderScore: z.number().int(),
  declarationDeadline: z.number().int(),
  declaration: declarationViewSchema.nullable(),
  houseBuilderSeat: z.number().int().nonnegative().nullable(),
  trump: z
    .strictObject({ level: z.enum(RANKS), suit: z.enum(SUITS).nullable() })
    .nullable(),
  viewerSeat: z.literal(0),
  hand: z.array(cardSchema),
  seats: z.array(
    z.strictObject({
      seat: z.number().int().nonnegative(),
      team: z.enum(['A', 'B']),
      cardCount: z.number().int().nonnegative(),
    }),
  ),
  kittyCount: z.number().int().positive(),
  declarationOptions: z.array(declarationViewSchema),
});
export const practiceRoundDeclarationSchema = z.strictObject({
  cardIds: z.array(z.string().min(1).max(100)).min(1).max(4),
});
export const practiceRoundKittySchema = z.strictObject({
  buriedIds: z.array(z.string().min(1).max(100)).min(1).max(10),
});
export type PracticeRoundCreate = z.infer<typeof practiceRoundCreateSchema>;

export const botCommandSchema = z.strictObject({
  action: z.enum(['declare', 'bury', 'play', 'advance', 'next-round']),
  cardIds: z.array(z.string().min(1).max(100)).max(36).optional(),
});
export const botMatchViewSchema = z.strictObject({
  history: z
    .array(
      z.strictObject({
        round: z.number().int(),
        number: z.number().int(),
        trump: z.strictObject({
          level: z.enum(RANKS),
          suit: z.enum(SUITS).nullable(),
        }),
        winnerSeat: z.number().int(),
        points: z.number().int(),
        defenderPoints: z.number().int(),
        penalty: z.number().int(),
        plays: exerciseViewSchema.shape.plays,
      }),
    )
    .max(100),
  rounds: z
    .array(
      z.strictObject({
        round: z.number().int(),
        defenderScore: z.number().int(),
        levels: practiceRoundViewSchema.shape.levels,
        winner: z.enum(['A', 'B']).nullable(),
      }),
    )
    .max(20),
  capturedPoints: z.number().int().nonnegative(),
  penaltyPoints: z.number().int(),
  trickPoints: z.number().int().nonnegative(),
  trickPenalty: z.number().int(),
  id: z.string().uuid(),
  revision: z.number().int(),
  playerCount: previewRequestSchema.shape.playerCount,
  phase: practiceRoundViewSchema.shape.phase,
  round: z.number().int(),
  trickNumber: z.number().int(),
  levels: practiceRoundViewSchema.shape.levels,
  attackingTeam: z.enum(['A', 'B']),
  dealerSeat: z.number().int(),
  defenderScore: z.number().int(),
  declarationDeadline: z.number().int(),
  declaration: declarationViewSchema
    .extend({ playerSeat: z.number().int() })
    .nullable(),
  declarationOptions: z.array(declarationViewSchema),
  trump: practiceRoundViewSchema.shape.trump,
  hand: z.array(cardSchema),
  kittyCount: z.number().int(),
  seats: previewResponseSchema.shape.seats,
  plays: exerciseViewSchema.shape.plays,
  nextSeat: z.number().int().nullable(),
  trickComplete: z.boolean(),
  winnerSeat: z.number().int().nullable(),
  suggestion: z.array(z.string()),
  message: z.string(),
  settlement: z
    .strictObject({
      defenderScore: z.number().int(),
      kittyPoints: z.number().int(),
      kittyMultiplier: z.number().int(),
      levels: practiceRoundViewSchema.shape.levels,
      attackingTeam: z.enum(['A', 'B']),
      jackReset: z.boolean(),
      winner: z.enum(['A', 'B']).nullable(),
    })
    .nullable(),
});
export type BotMatchView = z.infer<typeof botMatchViewSchema>;
