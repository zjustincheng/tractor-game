import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it, vi } from 'vitest';
import { startTrick } from '@tractor/rules';
import type { Card } from '@tractor/rules';
import { newBotMatch, commandBotMatch, policyForSeat } from './bot-match.js';
import { buildApp } from './app.js';
import { MatchStore } from './match-store.js';
import { seededRandom } from './training/self-play.js';
import {
  languageModelTurn,
  openAIClient,
  LanguageModelError,
} from './language-model.js';
import type { LanguageModelClient, ModelDecision } from './language-model.js';

const model = 'test-model';
function fixture() {
  const match = newBotMatch(4, 0, seededRandom(1));
  const hands: Card[][] = Array.from({ length: 4 }, (_, seat) => [
    { id: `${seat}-a`, kind: 'suited', suit: 'clubs', rank: '3' },
    { id: `${seat}-private`, kind: 'suited', suit: 'clubs', rank: 'A' },
  ]);
  const trump = { level: '2', suit: 'hearts' } as const;
  match.state = {
    ...match.state,
    phase: 'tricks',
    hands,
    trump,
    trick: startTrick({
      playerCount: 4,
      hands,
      trump,
      attackingTeam: 'A',
      leaderSeat: 0,
    }),
  };
  match.languageModel = {
    model,
    notes: { '1': 'seat-one-memory', '3': 'seat-three-memory' },
    decisions: 0,
    cache: {},
    record: { matches: 0, humanWins: 0, modelWins: 0 },
  };
  return match;
}
const answer = (request: ModelDecision) => ({
  cardIds: [request.observation.hand[0]!.id],
  opponentNotes: `Public observation from seat ${request.observation.seat}`,
});

describe('language-model opponent', () => {
  it('continues a finished series once, retaining separate memories and recording the result', async () => {
    const directory = mkdtempSync(join(tmpdir(), 'tractor-llm-series-'));
    const id = '11111111-1111-4111-8111-111111111111';
    const match = fixture();
    match.state = { ...match.state, phase: 'finished' };
    match.settlement = {
      defenderScore: 0,
      kittyBasePoints: 0,
      kittyMultiplier: 1,
      kittyPoints: 0,
      outcome: { advancingRole: 'attackers', levels: 1, swapRoles: false },
      levels: { A: 'A', B: '2' },
      attackingTeam: 'A',
      rolesSwapped: false,
      jackReset: false,
      winner: 'A',
    };
    new MatchStore(directory).set(id, { match, revision: 1, touched: 100 });
    const app = buildApp({
      saveDirectory: directory,
      now: () => 100,
      languageModel: { model, decide: async (r) => answer(r) },
    });
    try {
      const command = {
        method: 'POST' as const,
        url: '/api/bot-matches',
        payload: {
          playerCount: 4,
          languageModel: true,
          previousModelMatchId: id,
        },
      };
      const response = await app.inject(command);
      expect(response.statusCode).toBe(200);
      const next = response.json();
      expect(next.languageModel.record).toEqual({
        matches: 1,
        humanWins: 1,
        modelWins: 0,
      });
      expect((await app.inject(command)).json().id).toBe(next.id);
      expect(
        new MatchStore(directory).get(next.id)!.match.languageModel?.notes,
      ).toEqual(match.languageModel!.notes);
      const replay = (
        await app.inject({
          method: 'GET',
          url: `/api/bot-matches/${id}/replay`,
        })
      ).json();
      expect(replay.languageModel.model).toBe(model);
      expect(replay.languageModel.notes).toBeUndefined();
    } finally {
      await app.close();
      rmSync(directory, { recursive: true, force: true });
    }
  });
  it('makes live choices with only its own hand, public actions, and its own memory', async () => {
    const match = fixture();
    const before = structuredClone(match);
    const requests: ModelDecision[] = [];
    const client: LanguageModelClient = {
      model,
      async decide(request) {
        requests.push(request);
        return answer(request);
      },
    };
    const next = await languageModelTurn(
      match,
      client,
      (working, policy, pick) =>
        commandBotMatch(
          working,
          { action: 'play', cardIds: ['0-a'] },
          100,
          pick,
          policy,
        ),
      seededRandom(2),
    );
    expect(requests.map((r) => r.observation.seat)).toEqual([1, 3]);
    expect(requests.map((r) => r.memory)).toEqual([
      'seat-one-memory',
      'seat-three-memory',
    ]);
    for (const request of requests) {
      expect(request.observation.hand.map((c) => c.id)).toEqual([
        `${request.observation.seat}-a`,
        `${request.observation.seat}-private`,
      ]);
      for (const seat of [0, 1, 2, 3].filter(
        (s) => s !== request.observation.seat,
      ))
        expect(JSON.stringify(request)).not.toContain(`${seat}-private`);
      expect(JSON.stringify(request)).not.toContain('initialHands');
      expect(JSON.stringify(request)).not.toContain('kitty');
    }
    expect(requests[1]!.observation.currentTrick!.plays).toHaveLength(3);
    expect(next.languageModel?.decisions).toBe(2);
    expect(next.languageModel?.notes['1']).toBe(
      'Public observation from seat 1',
    );
    expect(match).toEqual(before);
    expect(next.state.trick?.status).toBe('complete');
  });

  it('rejects illegal model responses, rather than substituting a heuristic move', async () => {
    const match = fixture();
    const before = structuredClone(match);
    const decide = vi.fn(async () => ({
      cardIds: ['0-private'],
      opponentNotes: '',
    }));
    await expect(
      languageModelTurn(
        match,
        { model, decide },
        (working, policy, pick) =>
          commandBotMatch(
            working,
            { action: 'play', cardIds: ['0-a'] },
            100,
            pick,
            policy,
          ),
        seededRandom(2),
      ),
    ).rejects.toBeInstanceOf(LanguageModelError);
    expect(decide).toHaveBeenCalledTimes(2);
    expect(decide.mock.calls[1]?.length).toBe(1);
    expect(match).toEqual(before);
  });

  it('lets the model declare and bury arbitrary owned cards', async () => {
    const match = fixture();
    const requests: ModelDecision[] = [];
    const client: LanguageModelClient = {
      model,
      async decide(request) {
        requests.push(request);
        return {
          cardIds:
            request.observation.kind === 'declare'
              ? [...request.observation.legalDeclarationChoices![1]!]
              : [request.observation.hand[1]!.id],
          opponentNotes: 'one public observation',
        };
      },
    };
    const next = await languageModelTurn(
      match,
      client,
      (working, policy) => {
        const seat = policyForSeat(working, 1, policy)!;
        const declaration = {
          kind: 'suit',
          suit: 'clubs',
          level: '2',
          multiplicity: 1,
          playerSeat: 1,
          cardIds: ['1-a'],
        } as const;
        expect(
          seat.declare([declaration], working.state.hands[1]!, '2')?.playerSeat,
        ).toBe(1);
        expect(
          seat.bury(working.state.hands[1]!, 1, working.state.trump!),
        ).toEqual(['1-private']);
        return working;
      },
      seededRandom(1),
    );
    expect(requests.map((r) => r.observation.kind)).toEqual([
      'declare',
      'bury',
    ]);
    expect(next.languageModel?.decisions).toBe(2);
  });

  it('uses strict Responses output, disables provider storage, and reports failures without exposing secrets', async () => {
    let captured: ModelDecision | undefined;
    await expect(
      languageModelTurn(
        fixture(),
        {
          model,
          async decide(request) {
            captured = request;
            throw new LanguageModelError('capture');
          },
        },
        (working, policy, pick) =>
          commandBotMatch(
            working,
            { action: 'play', cardIds: ['0-a'] },
            100,
            pick,
            policy,
          ),
        seededRandom(1),
      ),
    ).rejects.toThrow('capture');
    const fetcher = vi.fn<typeof fetch>(async (_url, init) => {
      const body = JSON.parse(String(init?.body));
      expect(body.model).toBe(model);
      expect(body.store).toBe(false);
      expect(body.text.format.strict).toBe(true);
      expect(body.input).not.toContain('test-secret');
      return new Response(
        JSON.stringify({
          status: 'completed',
          output: [
            { type: 'reasoning' },
            {
              type: 'message',
              content: [
                {
                  type: 'output_text',
                  text: JSON.stringify(answer(captured!)),
                },
              ],
            },
          ],
        }),
      );
    });
    expect(
      (await openAIClient('test-secret', model, fetcher).decide(captured!))
        .cardIds,
    ).toEqual(['1-a']);
    const failed = openAIClient(
      'test-secret',
      model,
      async () => new Response('test-secret provider details', { status: 401 }),
    );
    await expect(failed.decide(captured!)).rejects.toThrow('HTTP 401');
    const incomplete = openAIClient(
      'test-secret',
      model,
      async () =>
        new Response(JSON.stringify({ status: 'incomplete', output: [] })),
    );
    await expect(incomplete.decide(captured!)).rejects.toThrow(
      'did not finish',
    );
  });

  it('commits once, survives restart, blocks concurrent moves, and rolls back failed saves', async () => {
    const directory = mkdtempSync(join(tmpdir(), 'tractor-llm-'));
    const id = '11111111-1111-4111-8111-111111111111';
    new MatchStore(directory).set(id, {
      match: fixture(),
      revision: 0,
      touched: 100,
    });
    let release!: () => void;
    let started!: () => void;
    const waiting = new Promise<void>((resolve) => {
      release = resolve;
    });
    const began = new Promise<void>((resolve) => {
      started = resolve;
    });
    let calls = 0;
    const client: LanguageModelClient = {
      model,
      async decide(request) {
        calls++;
        if (calls === 1) {
          started();
          await waiting;
        }
        return answer(request);
      },
    };
    let app = buildApp({
      saveDirectory: directory,
      now: () => 100,
      languageModel: client,
    });
    const command = {
      method: 'POST' as const,
      url: `/api/bot-matches/${id}/commands`,
      payload: { revision: 0, action: 'play', cardIds: ['0-a'] },
    };
    try {
      const first = app.inject(command);
      // Fastify injection is thenable; start it before waiting for the model.
      const done = Promise.resolve(first);
      await began;
      expect((await app.inject(command)).statusCode).toBe(409);
      const refresh = await app.inject({
        method: 'GET',
        url: `/api/bot-matches/${id}`,
      });
      expect(refresh.json().revision).toBe(0);
      expect(refresh.body).not.toContain('seat-one-memory');
      expect(
        (
          await app.inject({
            method: 'GET',
            url: `/api/bot-matches/${id}/replay`,
          })
        ).statusCode,
      ).toBe(403);
      const failure = vi
        .spyOn(MatchStore.prototype, 'set')
        .mockImplementationOnce(() => {
          throw new Error('disk failure');
        });
      release();
      expect((await done).statusCode).toBe(500);
      failure.mockRestore();
      expect(
        (
          await app.inject({ method: 'GET', url: `/api/bot-matches/${id}` })
        ).json().revision,
      ).toBe(0);
      expect(
        new MatchStore(directory).get(id)!.match.languageModel?.decisions,
      ).toBe(0);
      const accepted = await app.inject(command);
      expect(accepted.statusCode).toBe(200);
      expect(accepted.json().languageModel.decisions).toBe(2);
      expect(accepted.json().revision).toBe(1);
      expect((await app.inject(command)).statusCode).toBe(409);
      await app.close();
      app = buildApp({
        saveDirectory: directory,
        now: () => 100,
        languageModel: client,
      });
      expect(
        (
          await app.inject({ method: 'GET', url: `/api/bot-matches/${id}` })
        ).json().revision,
      ).toBe(1);
      expect(
        new MatchStore(directory).get(id)!.match.languageModel?.notes['3'],
      ).toBe('Public observation from seat 3');
    } finally {
      release();
      await app.close();
      rmSync(directory, { recursive: true, force: true });
    }
  });

  it('requires explicit configuration and a four-player language-model mode', async () => {
    const app = buildApp();
    try {
      expect(
        (
          await app.inject({
            method: 'POST',
            url: '/api/bot-matches',
            payload: { playerCount: 4, languageModel: true },
          })
        ).statusCode,
      ).toBe(503);
      expect(
        (
          await app.inject({
            method: 'GET',
            url: '/api/bot-matches/language-model',
          })
        ).json().available,
      ).toBe(false);
    } finally {
      await app.close();
    }
  });
});
