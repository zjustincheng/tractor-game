import { decisionClip } from './decision-clip.js';
import { reviewSamples } from './training/review-samples.js';
import {
  languageModelTurn,
  LanguageModelError,
  DEFAULT_LANGUAGE_MODEL,
} from './language-model.js';
import type { LanguageModelClient } from './language-model.js';
import { updateFromOutcomes, newOptimizer } from './training/policy-update.js';
import { parsePolicy } from './training/learned-policy.js';
import { randomInt, randomUUID, createHash } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import {
  botCommandSchema,
  botFeedbackSchema,
  botReviewSchema,
  botMatchCreateSchema,
  botMatchViewSchema,
} from '@tractor/protocol';
import {
  category,
  chooseBotBurial,
  chooseBotPlay,
  chooseBotLead,
  teamAt,
  RANKS,
} from '@tractor/rules';
import type { Declaration } from '@tractor/rules';
import {
  CommandError,
  botLeadContext,
  commandBotMatch,
  legalDeclarations,
  newBotMatch,
  policyForSeat,
  progressBotDeclarations,
} from './bot-match.js';
import type { BotMatch } from './bot-match.js';
import { MatchStore } from './match-store.js';
import type { SavedMatch } from './match-store.js';
import type { BotPolicy } from './bot-policy.js';

/** A playtest stays blind: every export of bot decisions waits for the result,
 * or the trace itself identifies the opponent the match is meant to hide. */
function playtestSealed(entry: SavedMatch): boolean {
  return Boolean(
    (entry.match.playtest || entry.match.languageModel) &&
    !entry.match.settlement?.winner,
  );
}

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

export function botView(
  id: string,
  match: BotMatch,
  revision: number,
  policy?: BotPolicy,
) {
  const { state, settlement } = match;
  policy = policyForSeat(match, 0, policy);
  const hand =
    state.phase === 'kitty' && state.dealerSeat === 0
      ? [...state.hands[0]!, ...state.kitty]
      : state.hands[0]!;
  const trick = state.trick;
  const seenCounts = { clubs: 0, diamonds: 0, hearts: 0, spades: 0, jokers: 0 };
  const seenRankCounts = Object.fromEntries(
    RANKS.map((rank) => [rank, 0]),
  ) as Record<string, number>;
  const knownVoids = match.history.flatMap((item) => {
    const lead = item.plays[0]?.cards[0];
    if (!lead) return [];
    const leadCategory = category(lead, item.trump);
    return item.plays
      .slice(1)
      .filter(
        (play) =>
          play.cards[0] && category(play.cards[0], item.trump) !== leadCategory,
      )
      .map((play) => ({ seat: play.seat, category: leadCategory }));
  });
  for (const card of match.history.flatMap((item) =>
    item.plays.flatMap((play) => [...play.cards]),
  )) {
    if (card.kind === 'joker') seenCounts.jokers += 1;
    else {
      seenCounts[card.suit] += 1;
      seenRankCounts[card.rank] = (seenRankCounts[card.rank] ?? 0) + 1;
    }
  }
  const decks = state.playerCount / 2;
  const categoryTotals = {
    clubs: 13 * decks,
    diamonds: 13 * decks,
    hearts: 13 * decks,
    spades: 13 * decks,
    jokers: 4 * decks,
  };
  const ownCounts = { clubs: 0, diamonds: 0, hearts: 0, spades: 0, jokers: 0 };
  for (const card of hand)
    ownCounts[card.kind === 'joker' ? 'jokers' : card.suit] += 1;
  const seenTotal = Object.values(seenCounts).reduce(
    (sum, count) => sum + count,
    0,
  );
  const unknownPool = Math.max(0, 54 * decks - seenTotal - hand.length);
  const opponentSlots = state.hands
    .slice(1)
    .reduce((sum, cards) => sum + cards.length, 0);
  const categoryOdds = Object.fromEntries(
    Object.keys(categoryTotals).map((key) => {
      const categoryKey = key as keyof typeof categoryTotals;
      const remaining = Math.max(
        0,
        categoryTotals[categoryKey] -
          seenCounts[categoryKey] -
          ownCounts[categoryKey],
      );
      let miss = 1;
      for (let i = 0; i < Math.min(opponentSlots, unknownPool); i++)
        miss *= Math.max(0, (unknownPool - remaining - i) / (unknownPool - i));
      return [key, Number((1 - miss).toFixed(3))];
    }),
  );
  const suggestion =
    state.phase === 'kitty' && state.dealerSeat === 0
      ? (policy?.bury ?? chooseBotBurial)(
          hand,
          state.kitty.length,
          state.trump!,
        )
      : state.phase === 'tricks' && trick?.nextSeat === 0
        ? trick.plays.length === 0
          ? (policy?.lead ?? chooseBotLead)(
              hand,
              state.trump!,
              botLeadContext(match, 0),
              match.playtest ? [] : state.hands.slice(1),
            )
          : (policy?.follow ?? chooseBotPlay)(
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
  const allCards = [
    ...(match.replay?.initialHands.flat() ?? []),
    ...(match.replay?.initialKitty ?? []),
    ...(match.replay?.deals.flatMap((deal) => [
      ...deal.hands.flat(),
      ...deal.kitty,
    ]) ?? []),
  ];
  const labels = new Map(
    allCards.map((card) => [
      card.id,
      card.kind === 'joker'
        ? `${card.joker} joker`
        : `${card.rank} ${card.suit}`,
    ]),
  );
  const review =
    match.playtest && settlement?.winner
      ? match.playtest.samples.map((sample) => ({
          id: sample.id,
          seat: decisionClip(match, sample)?.seat ?? sample.seat,
          kind: sample.kind,
          options: sample.experience.options.map((option) => ({
            cards: option.cardIds.map((id) => labels.get(id) ?? 'card'),
            cardIds: option.cardIds,
          })),
          chosen: sample.experience.chosen,
          preferredIndex: sample.preferredIndex ?? null,
          round: sample.round ?? null,
          trick: sample.trick ?? null,
          clip: decisionClip(match, sample),
        }))
      : [];
  return botMatchViewSchema.parse({
    languageModel: match.languageModel
      ? {
          model: match.languageModel.model,
          decisions: match.languageModel.decisions,
          previousMatchId: match.languageModel.previousId ?? null,
          record: {
            matches:
              match.languageModel.record.matches +
              Number(Boolean(settlement?.winner)),
            humanWins:
              match.languageModel.record.humanWins +
              Number(settlement?.winner === 'A'),
            modelWins:
              match.languageModel.record.modelWins +
              Number(settlement?.winner === 'B'),
          },
        }
      : null,
    difficulty: match.difficulty ?? 'standard',
    playtest: match.playtest
      ? {
          opponent: settlement?.winner ? match.playtest.opponent : null,
          championId: settlement?.winner ? match.playtest.championId : null,
          previousPlaytestId: match.playtest.previousId ?? null,
          feedbackCount: match.playtest.feedbackCount,
          review,
        }
      : null,
    seenCounts,
    seenRankCounts,
    categoryOdds,
    knownVoids,
    // Keep live responses bounded; the durable save and replay export retain
    // the full record for offline learning.
    history: match.history.slice(-100),
    rounds: match.rounds.slice(-20).map(({ round, settlement }) => ({
      round,
      defenderScore: settlement.defenderScore,
      levels: settlement.levels,
      winner: settlement.winner,
    })),
    id,
    revision,
    playerCount: state.playerCount,
    quickMatch: Boolean(match.quickMatch),
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
    dealingStartedAt: match.dealingStartedAt ?? null,
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
    botPolicy?: BotPolicy;
    now?: () => number;
    pickIndex?: (max: number) => number;
    saveDirectory?: string;
    languageModel?: LanguageModelClient;
  } = {},
) {
  const now = options.now ?? Date.now;
  const pendingModelTurns = new Set<string>();
  const pick = options.pickIndex ?? randomInt;
  // Random IDs act as private local practice-session tokens. No multiplayer identity is implied.
  const sessions = new MatchStore(options.saveDirectory, (id, entry) => {
    if (entry.match.playtest) {
      // Older saved playtests predate explicit feedback counting. Keep those
      // sessions restorable after adding the human-review feedback field.
      entry.match.playtest.feedbackCount ??= 0;
      parsePolicy(entry.match.playtest.models.lead);
      parsePolicy(entry.match.playtest.models.follow);
      if (!['sharp', 'champion'].includes(entry.match.playtest.opponent))
        throw new Error('Invalid playtest assignment');
    }
    botView(id, entry.match, entry.revision, options.botPolicy);
  });
  const expire = () => {
    for (const [id, entry] of sessions)
      if (
        !pendingModelTurns.has(id) &&
        entry.touched < now() - 30 * 24 * 60 * 60 * 1000
      )
        sessions.delete(id);
  };
  app.get('/api/bot-matches/language-model', async () => ({
    available: Boolean(options.languageModel),
    model: options.languageModel?.model ?? DEFAULT_LANGUAGE_MODEL,
  }));
  app.post('/api/bot-matches', async (request, reply) => {
    const parsed = botMatchCreateSchema.safeParse(request.body);
    if (!parsed.success)
      return reply
        .code(400)
        .send({ message: 'Choose 4, 6, 8, or 10 players.' });
    expire();
    let languageModel: BotMatch['languageModel'];
    if (parsed.data.previousModelMatchId && !parsed.data.languageModel)
      return reply.code(400).send({
        message:
          'Continuing a language-model series requires language-model mode.',
      });
    if (parsed.data.languageModel) {
      if (
        parsed.data.playerCount !== 4 ||
        parsed.data.playtest ||
        parsed.data.previousPlaytestId
      )
        return reply.code(400).send({
          message:
            'Language-model mode uses four players and its own match series.',
        });
      if (!options.languageModel)
        return reply.code(503).send({
          message:
            'Set OPENAI_API_KEY on the backend to enable the language-model opponent. Never put the key in the browser.',
        });
      const previous = parsed.data.previousModelMatchId
        ? sessions.get(parsed.data.previousModelMatchId)
        : undefined;
      if (
        parsed.data.previousModelMatchId &&
        (!previous?.match.languageModel || !previous.match.settlement?.winner)
      )
        return reply.code(400).send({
          message:
            'Finish the previous language-model match before continuing.',
        });
      if (previous) {
        if (previous.match.languageModel!.model !== options.languageModel.model)
          return reply.code(409).send({
            message:
              'Restore the previous model to continue this series, or start a new series.',
          });
        for (const [id, existing] of sessions)
          if (
            existing.match.languageModel?.previousId ===
            parsed.data.previousModelMatchId
          )
            return botView(
              id,
              existing.match,
              existing.revision,
              options.botPolicy,
            );
      }
      const record = previous
        ? {
            ...previous.match.languageModel!.record,
            matches: previous.match.languageModel!.record.matches + 1,
            humanWins:
              previous.match.languageModel!.record.humanWins +
              Number(previous.match.settlement!.winner === 'A'),
            modelWins:
              previous.match.languageModel!.record.modelWins +
              Number(previous.match.settlement!.winner === 'B'),
          }
        : { matches: 0, humanWins: 0, modelWins: 0 };
      languageModel = {
        model: options.languageModel.model,
        notes: structuredClone(previous?.match.languageModel?.notes ?? {}),
        decisions: 0,
        cache: {},
        record,
        ...(parsed.data.previousModelMatchId
          ? { previousId: parsed.data.previousModelMatchId }
          : {}),
      };
    }
    let playtest: BotMatch['playtest'];
    if (parsed.data.previousPlaytestId && !parsed.data.playtest)
      return reply
        .code(400)
        .send({ message: 'Continuation requires human playtest mode.' });
    if (parsed.data.playtest) {
      if (parsed.data.playerCount !== 4)
        return reply
          .code(400)
          .send({ message: 'Human playtests use four players.' });
      const previous = parsed.data.previousPlaytestId
        ? sessions.get(parsed.data.previousPlaytestId)
        : undefined;
      if (
        parsed.data.previousPlaytestId &&
        (!previous?.match.playtest || !previous.match.settlement?.winner)
      )
        return reply.code(400).send({
          message: 'Finish the previous playtest match before continuing.',
        });
      if (previous) {
        for (const [existingId, existing] of sessions) {
          if (
            existing.match.playtest?.previousId ===
            parsed.data.previousPlaytestId
          )
            return botView(
              existingId,
              existing.match,
              existing.revision,
              options.botPolicy,
            );
        }
      }
      const models =
        previous?.match.playtest?.models ?? options.botPolicy?.models;
      if (!models)
        return reply.code(400).send({
          message:
            'Load a saved champion with BOT_POLICY_FILE to start a human playtest.',
        });
      playtest = {
        feedbackCount: previous?.match.playtest?.feedbackCount ?? 0,
        observed: { lead: 0, follow: 0, declaration: 0, burial: 0 },
        samples: [],
        opponent: previous?.match.playtest
          ? previous.match.playtest.opponent === 'sharp'
            ? 'champion'
            : 'sharp'
          : pick(2) === 0
            ? 'sharp'
            : 'champion',
        models: structuredClone(models),
        championId:
          previous?.match.playtest?.championId ??
          createHash('sha256').update(JSON.stringify(models)).digest('hex'),
        ...(parsed.data.previousPlaytestId
          ? { previousId: parsed.data.previousPlaytestId }
          : {}),
      };
    }
    if (sessions.size >= 200)
      return reply
        .code(503)
        .send({ message: 'Practice tables are full. Try again later.' });
    const id = randomUUID();
    const entry = {
      match: newBotMatch(
        parsed.data.playerCount,
        now(),
        pick,
        parsed.data.difficulty,
        parsed.data.quickMatch,
      ),
      revision: 0,
      touched: now(),
      events: [],
    };
    if (playtest) {
      entry.match.playtest = playtest;
      entry.match.difficulty = 'standard';
    }
    if (languageModel) entry.match.languageModel = languageModel;
    sessions.set(id, entry);
    return botView(id, entry.match, entry.revision, options.botPolicy);
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
      // A refresh never makes paid calls or mutates a pending model turn.
      if (entry.match.languageModel)
        return botView(
          request.params.id,
          entry.match,
          entry.revision,
          options.botPolicy,
        );
      const progressed = progressBotDeclarations(
        entry.match,
        now(),
        options.botPolicy,
      );
      const events = entry.events ?? [];
      const nextEntry =
        progressed === entry.match
          ? { ...entry, touched: now(), events }
          : {
              match: progressed,
              revision: entry.revision + 1,
              touched: now(),
              events: [
                ...events,
                {
                  revision: entry.revision + 1,
                  actor: 'bot' as const,
                  action: 'bot-declaration',
                  at: now(),
                },
              ],
            };
      sessions.set(request.params.id, nextEntry);
      return botView(
        request.params.id,
        nextEntry.match,
        nextEntry.revision,
        options.botPolicy,
      );
    },
  );
  app.get<{ Params: { id: string } }>(
    '/api/bot-matches/:id/replay',
    async (request, reply) => {
      expire();
      const entry = sessions.get(request.params.id);
      if (!entry)
        return reply
          .code(404)
          .send({ message: 'This match expired. Start a new match.' });
      if (playtestSealed(entry))
        return reply.code(403).send({
          message: 'Replay export unlocks after the playtest match ends.',
        });
      return reply
        .type('application/json; charset=utf-8')
        .header(
          'Content-Disposition',
          `attachment; filename="tractor-match-${request.params.id}.json"`,
        )
        .send({
          playtest: entry.match.playtest
            ? {
                opponent: entry.match.playtest.opponent,
                championId: entry.match.playtest.championId,
                previousId: entry.match.playtest.previousId,
                winner: entry.match.settlement?.winner,
              }
            : null,
          format: 1,
          languageModel: entry.match.languageModel
            ? botView(request.params.id, entry.match, entry.revision)
                .languageModel
            : null,
          id: request.params.id,
          replay: entry.match.replay ?? null,
          events: entry.events ?? [],
        });
    },
  );
  app.get<{ Params: { id: string } }>(
    '/api/bot-matches/:id/player-actions.csv',
    async (request, reply) => {
      expire();
      const entry = sessions.get(request.params.id);
      if (!entry)
        return reply.code(404).send({ message: 'This match expired.' });
      if (!entry.match.playtest)
        return reply.code(400).send({
          message: 'This export is available for human playtests.',
        });
      const escape = (value: unknown) => {
        const text = String(value ?? '');
        return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
      };
      const rows = (entry.events ?? [])
        .filter((event) => event.actor === 'player')
        .map((event) =>
          [
            event.revision,
            event.at,
            event.action,
            event.round,
            event.trick,
            (event.cardIds ?? []).join(' | '),
          ]
            .map(escape)
            .join(','),
        );
      return reply
        .type('text/csv; charset=utf-8')
        .header(
          'Content-Disposition',
          `attachment; filename="tractor-human-actions-${request.params.id}.csv"`,
        )
        .send(
          ['revision,timestamp,action,round,trick,card_ids', ...rows].join(
            '\n',
          ),
        );
    },
  );
  app.get<{ Params: { id: string } }>(
    '/api/bot-matches/:id/behavior.csv',
    async (request, reply) => {
      expire();
      const entry = sessions.get(request.params.id);
      if (!entry)
        return reply.code(404).send({ message: 'This match expired.' });
      if (playtestSealed(entry))
        return reply.code(403).send({
          message: 'Bot behavior export unlocks after the playtest match ends.',
        });
      const escape = (value: unknown) => {
        const text = String(value ?? '');
        return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
      };
      const rows = (entry.events ?? [])
        .filter((event) => event.actor === 'bot')
        .map((event) => {
          const cards = event.cardIds ?? [];
          const detail = event.detail ?? '';
          return [
            event.revision,
            event.at,
            event.action,
            event.seat,
            event.round,
            event.trick,
            event.team,
            event.trump
              ? `${event.trump.level} ${event.trump.suit ?? 'no-suit'}`
              : '',
            event.ledCategory,
            event.hadLedCategory,
            event.usedTrump,
            event.jokerCount,
            event.points,
            event.winnerBefore,
            event.winnerAfter,
            event.winnerSeat,
            event.trickPoints,
            event.rating,
            detail,
            cards.length,
            cards.join(' | '),
          ]
            .map(escape)
            .join(',');
        });
      const csv = [
        'revision,timestamp,action,seat,round,trick,team,trump,led_category,had_led_category,used_trump,joker_count,points,winner_before,winner_after,winner_seat,trick_points,rating,decision,card_count,card_ids',
        ...rows,
      ].join('\n');
      return reply
        .type('text/csv; charset=utf-8')
        .header(
          'Content-Disposition',
          `attachment; filename="tractor-bot-behavior-${request.params.id}.csv"`,
        )
        .send(csv);
    },
  );
  app.get<{ Params: { id: string } }>(
    '/api/bot-matches/:id/behavior-summary.csv',
    async (request, reply) => {
      expire();
      const entry = sessions.get(request.params.id);
      if (!entry)
        return reply.code(404).send({ message: 'This match expired.' });
      if (playtestSealed(entry))
        return reply.code(403).send({
          message: 'Bot behavior export unlocks after the playtest match ends.',
        });
      const escape = (value: unknown) => {
        const text = String(value ?? '');
        return /[",\n]/.test(text) ? `"${text.replaceAll('"', '""')}"` : text;
      };
      const bots = (entry.events ?? []).filter(
        (event) => event.actor === 'bot' && event.action === 'play',
      );
      const completedTricks = (entry.events ?? []).filter(
        (event) =>
          event.action === 'trick-complete' && event.winnerSeat !== undefined,
      );
      const seats = [
        ...new Set(
          bots
            .map((event) => event.seat)
            .filter((seat): seat is number => seat !== undefined),
        ),
      ].sort((a, b) => a - b);
      const totals = new Array(18).fill(0) as number[];
      const rows = seats.map((seat) => {
        const plays = bots.filter((event) => event.seat === seat);
        const leads = plays.filter(
          (event) =>
            event.detail === 'lead' || event.detail === 'validated gamble',
        ).length;
        const follows = plays.length - leads;
        const trumpPlays = plays.filter((event) => event.usedTrump).length;
        const jokers = plays.reduce(
          (sum, event) => sum + (event.jokerCount ?? 0),
          0,
        );
        const ruffs = plays.filter(
          (event) => event.hadLedCategory === false && event.usedTrump,
        ).length;
        const successfulRuffs = plays.filter(
          (event) =>
            event.hadLedCategory === false &&
            event.usedTrump &&
            event.winnerAfter === seat,
        ).length;
        const partnerOvertakes = plays.filter(
          (event) =>
            event.winnerBefore !== undefined &&
            event.winnerBefore !== null &&
            event.team &&
            teamAt(event.winnerBefore) === event.team &&
            event.winnerAfter === seat,
        ).length;
        const trickWins = completedTricks.filter(
          (event) => event.winnerSeat === seat,
        ).length;
        const teamPointsCaptured = completedTricks
          .filter((event) => event.team === plays[0]?.team)
          .reduce((sum, event) => sum + (event.trickPoints ?? 0), 0);
        const points = plays.reduce(
          (sum, event) => sum + (event.points ?? 0),
          0,
        );
        const ratingCount = (rating: string) =>
          plays.filter((event) => event.rating === rating).length;
        const values = [
          seat,
          plays[0]?.team,
          leads,
          follows,
          plays.length,
          trumpPlays,
          jokers,
          ruffs,
          successfulRuffs,
          partnerOvertakes,
          trickWins,
          points,
          teamPointsCaptured,
          ratingCount('necessary_ruff'),
          ratingCount('failed_ruff'),
          ratingCount('protected_partner'),
          ratingCount('overtook_partner'),
          ratingCount('overtook_opponent'),
        ];
        values.forEach((value, index) => {
          if (typeof value === 'number')
            totals[index] = (totals[index] ?? 0) + value;
        });
        return [entry.match.difficulty ?? 'standard', ...values]
          .map(escape)
          .join(',');
      });
      rows.push(['TOTAL', '', ...totals.slice(2)].map(escape).join(','));
      const csv = [
        'difficulty,seat,team,leads,follows,total_plays,trump_plays,jokers,ruffs,successful_ruffs,partner_overtakes,trick_wins,points_played,team_points_captured,necessary_ruff,failed_ruff,protected_partner,overtook_partner,overtook_opponent',
        ...rows,
      ].join('\n');
      return reply
        .type('text/csv; charset=utf-8')
        .header(
          'Content-Disposition',
          `attachment; filename="tractor-bot-summary-${request.params.id}.csv"`,
        )
        .send(csv);
    },
  );
  app.post<{ Params: { id: string } }>(
    '/api/bot-matches/:id/review',
    async (request, reply) => {
      const original = sessions.get(request.params.id);
      if (!original)
        return reply.code(404).send({ message: 'This match expired.' });
      const parsed = botReviewSchema.safeParse(request.body);
      if (!parsed.success)
        return reply
          .code(400)
          .send({ message: 'Provide the current match revision.' });
      if (parsed.data.revision !== original.revision)
        return reply
          .code(409)
          .send({ message: 'Refresh this match before preparing flashcards.' });
      if (!original.match.playtest || !original.match.settlement?.winner)
        return reply.code(403).send({
          message: 'Flashcards are available after a completed human playtest.',
        });
      if (original.match.playtest.samples.length)
        return botView(
          request.params.id,
          original.match,
          original.revision,
          options.botPolicy,
        );
      const entry = structuredClone(original);
      const samples = reviewSamples(entry.match);
      if (!samples.length)
        return reply.code(422).send({
          message:
            'This recording has no decisions with enough replay context for flashcards.',
        });
      entry.match.playtest!.samples = samples;
      entry.revision++;
      entry.touched = now();
      sessions.set(request.params.id, entry);
      return botView(
        request.params.id,
        entry.match,
        entry.revision,
        options.botPolicy,
      );
    },
  );
  app.post<{ Params: { id: string } }>(
    '/api/bot-matches/:id/feedback',
    async (request, reply) => {
      const saved = sessions.get(request.params.id);
      if (!saved)
        return reply.code(404).send({ message: 'This match expired.' });
      const entry = structuredClone(saved);
      const parsed = botFeedbackSchema.safeParse(request.body);
      if (!parsed.success)
        return reply
          .code(400)
          .send({ message: 'Choose one of the listed actions.' });
      if (parsed.data.revision !== entry.revision)
        return reply
          .code(409)
          .send({ message: 'Refresh this match before teaching a decision.' });
      const playtest = entry.match.playtest;
      if (!playtest || !entry.match.settlement?.winner)
        return reply.code(403).send({
          message:
            'Decision feedback is available after a completed human playtest.',
        });
      const sample = playtest.samples.find(
        (item) => item.id === parsed.data.sampleId,
      );
      if (
        !sample ||
        !Number.isSafeInteger(parsed.data.preferredIndex) ||
        parsed.data.preferredIndex < 0 ||
        parsed.data.preferredIndex >= sample.experience.options.length
      )
        return reply.code(400).send({
          message: 'That decision or preferred action is unavailable.',
        });
      if (sample.preferredIndex !== undefined)
        return reply
          .code(409)
          .send({ message: 'This decision already has feedback.' });
      if (parsed.data.preferredIndex === sample.experience.chosen)
        return reply.code(400).send({
          message:
            'Choose a different action; keeping the bot’s choice does not teach it a correction.',
        });
      const experience = {
        ...sample.experience,
        chosen: parsed.data.preferredIndex,
        advantage: 0.25,
        temperature: 1,
      };
      const lead = sample.kind === 'lead';
      const updated = updateFromOutcomes(
        lead ? playtest.models.lead : playtest.models.follow,
        [experience],
        newOptimizer(),
      );
      if (updated.epochs === 0)
        return reply.code(422).send({
          message: 'No policy update was accepted for this feedback.',
        });
      if (lead) playtest.models.lead = updated.model;
      else playtest.models.follow = updated.model;
      sample.preferredIndex = parsed.data.preferredIndex;
      playtest.feedbackCount++;
      const revision = entry.revision + 1;
      sessions.set(request.params.id, { ...entry, revision, touched: now() });
      return botView(
        request.params.id,
        entry.match,
        revision,
        options.botPolicy,
      );
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
      if (pendingModelTurns.has(request.params.id))
        return reply.code(409).send({
          message:
            'The language model is already deciding this turn. Wait, then refresh.',
        });
      if (entry.match.languageModel && !options.languageModel)
        return reply.code(503).send({
          message:
            'Restore OPENAI_API_KEY on the backend to resume this language-model match.',
        });
      if (
        entry.match.languageModel &&
        entry.match.languageModel.model !== options.languageModel?.model
      )
        return reply.code(409).send({
          message:
            'Restore the original model to resume this match, or start a new series.',
        });
      if (entry.match.languageModel) pendingModelTurns.add(request.params.id);
      try {
        const started = now();
        const match = entry.match.languageModel
          ? await languageModelTurn(
              entry.match,
              options.languageModel!,
              (working, policy, random) => {
                if (
                  parsed.data.action === 'advance' &&
                  working.state.phase === 'declaration'
                ) {
                  // Give bots their fully dealt declaration decision before finalization.
                  // Freeze the decision window during network work, then reopen it below.
                  const declared = progressBotDeclarations(
                    working,
                    Math.min(started, working.state.declarationDeadline - 1),
                    policy,
                  );
                  if (declared !== working) return declared;
                }
                return commandBotMatch(
                  working,
                  parsed.data,
                  started,
                  random,
                  policy,
                );
              },
              pick,
            )
          : commandBotMatch(
              entry.match,
              parsed.data,
              now(),
              pick,
              options.botPolicy,
            );
        if (entry.match.languageModel) {
          if (sessions.get(request.params.id)?.revision !== entry.revision)
            return reply.code(409).send({
              message:
                'The table changed during the model decision. Refresh before retrying.',
            });
          if (
            match.state.phase === 'declaration' &&
            JSON.stringify(match.state.declaration) !==
              JSON.stringify(entry.match.state.declaration)
          )
            match.state = {
              ...match.state,
              declarationDeadline: Math.max(
                match.state.declarationDeadline,
                now() + 8000,
              ),
            };
        }
        const result = botView(
          request.params.id,
          match,
          entry.revision + 1,
          options.botPolicy,
        );
        const botActions = match.botActions ?? [];
        const persistedMatch = { ...match };
        delete persistedMatch.botActions;
        sessions.set(request.params.id, {
          match: persistedMatch,
          revision: entry.revision + 1,
          touched: now(),
          events: [
            ...(entry.events ?? []),
            {
              revision: entry.revision + 1,
              actor: 'player' as const,
              action: parsed.data.action,
              at: now(),
              ...(parsed.data.cardIds ? { cardIds: parsed.data.cardIds } : {}),
            },
            ...botActions.map((botAction) => ({
              revision: entry.revision + 1,
              actor:
                botAction.action === 'trick-complete'
                  ? ('system' as const)
                  : ('bot' as const),
              action: botAction.action,
              at: now(),
              ...(botAction.seat === undefined ? {} : { seat: botAction.seat }),
              ...(botAction.round === undefined
                ? {}
                : { round: botAction.round }),
              ...(botAction.trick === undefined
                ? {}
                : { trick: botAction.trick }),
              ...(botAction.team === undefined ? {} : { team: botAction.team }),
              ...(botAction.trump === undefined
                ? {}
                : { trump: botAction.trump }),
              ...(botAction.ledCategory === undefined
                ? {}
                : { ledCategory: botAction.ledCategory }),
              ...(botAction.hadLedCategory === undefined
                ? {}
                : { hadLedCategory: botAction.hadLedCategory }),
              ...(botAction.usedTrump === undefined
                ? {}
                : { usedTrump: botAction.usedTrump }),
              ...(botAction.jokerCount === undefined
                ? {}
                : { jokerCount: botAction.jokerCount }),
              ...(botAction.points === undefined
                ? {}
                : { points: botAction.points }),
              ...(botAction.winnerBefore === undefined
                ? {}
                : { winnerBefore: botAction.winnerBefore }),
              ...(botAction.winnerAfter === undefined
                ? {}
                : { winnerAfter: botAction.winnerAfter }),
              ...(botAction.winnerSeat === undefined
                ? {}
                : { winnerSeat: botAction.winnerSeat }),
              ...(botAction.trickPoints === undefined
                ? {}
                : { trickPoints: botAction.trickPoints }),
              ...(botAction.rating === undefined
                ? {}
                : { rating: botAction.rating }),
              cardIds: [...botAction.cardIds],
              ...(botAction.detail ? { detail: botAction.detail } : {}),
            })),
          ],
        });
        return result;
      } catch (error) {
        if (error instanceof LanguageModelError)
          return reply.code(503).send({ message: error.message });
        if (error instanceof CommandError)
          return reply.code(422).send({ message: error.message });
        throw error;
      } finally {
        pendingModelTurns.delete(request.params.id);
      }
    },
  );
}
