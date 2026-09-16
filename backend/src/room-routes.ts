import { randomInt, randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import {
  roomCreateSchema,
  roomJoinSchema,
  roomReadySchema,
  roomEventsSchema,
  roomViewSchema,
  roomGameCommandSchema,
  roomGameViewSchema,
} from '@tractor/protocol';
import {
  advanceDeclaration,
  createDeck,
  createRound,
  declarationsForHand,
  exchangeKitty,
  playCards,
  receiveDeclaration,
  shuffle,
} from '@tractor/rules';
import type { MatchState, PLAYER_COUNTS } from '@tractor/rules';

interface RoomPlayer {
  token: string;
  seat: number;
  displayName: string;
  ready: boolean;
}
interface RoomEvent {
  revision: number;
  type: 'room-created' | 'player-joined' | 'player-ready' | 'player-left';
  seat: number;
  displayName?: string;
  ready?: boolean;
}
interface Room {
  code: string;
  playerCount: (typeof PLAYER_COUNTS)[number];
  hostSeat: number;
  players: RoomPlayer[];
  createdAt: number;
  revision: number;
  events: RoomEvent[];
  match?: MatchState;
  matchRevision: number;
}
const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function code() {
  let value = '';
  for (let i = 0; i < 6; i++) value += alphabet[randomInt(alphabet.length)];
  return value;
}
function findRoom(rooms: Map<string, Room>, value: string) {
  return rooms.get(value.toUpperCase());
}
function authorized(room: Room | undefined, token: string | undefined) {
  return room?.players.find((player) => player.token === token);
}
function addEvent(room: Room, value: Omit<RoomEvent, 'revision'>) {
  room.revision += 1;
  room.events.push({ ...value, revision: room.revision });
  if (room.events.length > 100) room.events.shift();
}
function project(room: Room, viewer: RoomPlayer) {
  return roomViewSchema.parse({
    code: room.code,
    playerCount: room.playerCount,
    hostSeat: room.hostSeat,
    viewerSeat: viewer.seat,
    players: room.players.map(({ seat, displayName, ready }) => ({
      seat,
      displayName,
      ready,
    })),
    started:
      room.players.length === room.playerCount &&
      room.players.every((player) => player.ready),
  });
}
function gameProject(room: Room, viewer: RoomPlayer) {
  const state = room.match;
  if (!state) return null;
  return roomGameViewSchema.parse({
    code: room.code,
    revision: room.matchRevision,
    viewerSeat: viewer.seat,
    playerCount: state.playerCount,
    phase: state.phase,
    hand: state.hands[viewer.seat],
    players: state.hands.map((hand, seat) => ({
      seat,
      displayName: room.players.find((player) => player.seat === seat)!
        .displayName,
      cardCount: hand.length,
    })),
    declarationDeadline: state.declarationDeadline,
    declaration: state.declaration
      ? {
          kind: state.declaration.kind,
          level: state.declaration.level,
          suit:
            state.declaration.kind === 'suit' ? state.declaration.suit : null,
          joker:
            state.declaration.kind === 'joker' ? state.declaration.joker : null,
          multiplicity: state.declaration.multiplicity,
          cardIds: [...state.declaration.cardIds],
        }
      : null,
    trump: state.trump,
    nextSeat: state.trick?.nextSeat ?? null,
    plays:
      state.trick?.plays.map((play) => ({
        seat: play.seat,
        cards: play.cards,
        matchesLead: play.matchesLead,
      })) ?? [],
    kittyCount: state.kitty.length,
    message:
      state.phase === 'declaration'
        ? 'Declaration window is open.'
        : state.phase === 'kitty'
          ? 'Dealer must exchange the kitty.'
          : 'Play proceeds counterclockwise.',
  });
}

export function registerRoomRoutes(
  app: FastifyInstance,
  options: { now?: () => number } = {},
) {
  const rooms = new Map<string, Room>();
  const now = options.now ?? Date.now;
  const cleanup = () => {
    for (const [key, room] of rooms)
      if (room.createdAt < now() - 24 * 60 * 60 * 1000) rooms.delete(key);
  };
  app.post('/api/rooms', async (request, reply) => {
    const parsed = roomCreateSchema.safeParse(request.body);
    if (!parsed.success)
      return reply.code(400).send({
        code: 'INVALID_ROOM',
        message: 'Choose a supported player count and display name.',
      });
    cleanup();
    let roomCode = code();
    while (rooms.has(roomCode)) roomCode = code();
    const player = {
      token: randomUUID(),
      seat: 0,
      displayName: parsed.data.displayName,
      ready: false,
    };
    const room: Room = {
      code: roomCode,
      playerCount: parsed.data.playerCount,
      hostSeat: 0,
      players: [player],
      createdAt: now(),
      revision: 0,
      events: [],
      matchRevision: 0,
    };
    addEvent(room, {
      type: 'room-created',
      seat: 0,
      displayName: player.displayName,
      ready: false,
    });
    rooms.set(roomCode, room);
    return { room: project(room, player), playerToken: player.token };
  });
  app.post<{ Params: { code: string } }>(
    '/api/rooms/:code/join',
    async (request, reply) => {
      cleanup();
      const room = findRoom(rooms, request.params.code);
      if (!room)
        return reply.code(404).send({
          code: 'ROOM_NOT_FOUND',
          message: 'That room is no longer available.',
        });
      if (room.players.length >= room.playerCount)
        return reply
          .code(409)
          .send({ code: 'ROOM_FULL', message: 'That room is full.' });
      const parsed = roomJoinSchema.safeParse(request.body);
      if (!parsed.success)
        return reply.code(400).send({
          code: 'INVALID_PLAYER',
          message: 'Choose a display name from 1 to 32 characters.',
        });
      const occupied = new Set(room.players.map((player) => player.seat));
      let seat = 0;
      while (occupied.has(seat)) seat++;
      const player = {
        token: randomUUID(),
        seat,
        displayName: parsed.data.displayName,
        ready: false,
      };
      room.players.push(player);
      addEvent(room, {
        type: 'player-joined',
        seat,
        displayName: player.displayName,
        ready: false,
      });
      return { room: project(room, player), playerToken: player.token };
    },
  );
  app.get<{
    Params: { code: string };
    Querystring: { token?: string; after?: string };
  }>('/api/rooms/:code/events', async (request, reply) => {
    cleanup();
    const room = findRoom(rooms, request.params.code);
    const viewer = authorized(room, request.query.token);
    if (!room || !viewer)
      return reply.code(404).send({
        code: 'ROOM_NOT_FOUND',
        message: 'Room or player session not found.',
      });
    const after =
      request.query.after === undefined ? 0 : Number(request.query.after);
    if (!Number.isSafeInteger(after) || after < 0 || after > room.revision)
      return reply.code(400).send({
        code: 'INVALID_REVISION',
        message: 'Use a valid room revision.',
      });
    return roomEventsSchema.parse({
      revision: room.revision,
      events: room.events.filter((item) => item.revision > after),
      room: project(room, viewer),
    });
  });
  app.get<{ Params: { code: string }; Querystring: { token?: string } }>(
    '/api/rooms/:code',
    async (request, reply) => {
      cleanup();
      const room = findRoom(rooms, request.params.code);
      const viewer = authorized(room, request.query.token);
      if (!room || !viewer)
        return reply.code(404).send({
          code: 'ROOM_NOT_FOUND',
          message: 'Room or player session not found.',
        });
      return project(room, viewer);
    },
  );
  app.post<{ Params: { code: string } }>(
    '/api/rooms/:code/ready',
    async (request, reply) => {
      const room = findRoom(rooms, request.params.code);
      const parsed = roomReadySchema.safeParse(request.body);
      const player = authorized(
        room,
        parsed.success ? parsed.data.token : undefined,
      );
      if (!room || !player)
        return reply.code(404).send({
          code: 'ROOM_NOT_FOUND',
          message: 'Room or player session not found.',
        });
      if (!parsed.success)
        return reply.code(400).send({
          code: 'INVALID_READY',
          message: 'Provide a valid player token and ready state.',
        });
      if (room.players.length === room.playerCount && !parsed.data.ready)
        room.players.forEach((item) => {
          item.ready = false;
        });
      player.ready = parsed.data.ready;
      addEvent(room, {
        type: 'player-ready',
        seat: player.seat,
        ready: player.ready,
      });
      if (
        room.players.length === room.playerCount &&
        room.players.every((item) => item.ready) &&
        !room.match
      ) {
        room.match = createRound({
          playerCount: room.playerCount,
          dealerSeat: 0,
          attackingTeam: 'A',
          shoe: shuffle(createDeck(room.playerCount), randomInt),
          firstDeclarationDeadline: now() + 8000,
        });
        room.matchRevision = 1;
      }
      return project(room, player);
    },
  );
  app.get<{ Params: { code: string }; Querystring: { token?: string } }>(
    '/api/rooms/:code/game',
    async (request, reply) => {
      cleanup();
      const room = findRoom(rooms, request.params.code);
      const viewer = authorized(room, request.query.token);
      const game = room && viewer ? gameProject(room, viewer) : null;
      if (!game)
        return reply.code(404).send({
          code: 'GAME_NOT_READY',
          message: 'The room is not full and ready yet.',
        });
      return game;
    },
  );
  app.post<{ Params: { code: string } }>(
    '/api/rooms/:code/game/commands',
    async (request, reply) => {
      const room = findRoom(rooms, request.params.code);
      const parsed = roomGameCommandSchema.safeParse(request.body);
      const viewer = authorized(
        room,
        parsed.success ? parsed.data.token : undefined,
      );
      if (!room || !viewer || !room.match)
        return reply.code(404).send({
          code: 'GAME_NOT_READY',
          message: 'The room game is not ready.',
        });
      if (!parsed.success)
        return reply.code(400).send({
          code: 'INVALID_COMMAND',
          message: 'Provide a valid game command.',
        });
      if (parsed.data.revision !== room.matchRevision)
        return reply.code(409).send({
          code: 'STALE_REVISION',
          message: 'Refresh the room before trying again.',
        });
      let result: ReturnType<typeof receiveDeclaration>;
      const state = room.match;
      if (parsed.data.action === 'declare') {
        const option = declarationsForHand(
          state.hands[viewer.seat]!,
          state.playerCount,
          state.levels[state.attackingTeam],
          viewer.seat,
        ).find(
          (item) =>
            item.cardIds.slice().sort().join('|') ===
            (parsed.data.cardIds ?? []).slice().sort().join('|'),
        );
        result = receiveDeclaration(state, viewer.seat, option ?? null, now());
      } else if (parsed.data.action === 'advance')
        result = advanceDeclaration(state, now(), randomInt);
      else if (parsed.data.action === 'bury')
        result = exchangeKitty(state, parsed.data.cardIds ?? []);
      else {
        if (state.phase !== 'tricks' || !state.trick)
          return reply.code(422).send({
            code: 'ROUND_NOT_READY',
            message: 'The trick is not ready.',
          });
        const played = playCards(
          state.trick,
          viewer.seat,
          parsed.data.cardIds ?? [],
        );
        result = played.ok
          ? {
              ok: true,
              state: {
                ...state,
                phase: played.state.status === 'complete' ? 'tricks' : 'tricks',
                hands: played.state.hands,
                trick: played.state,
              },
            }
          : { ok: false, code: 'INVALID_DECLARATION', message: played.message };
      }
      if (!result.ok)
        return reply
          .code(422)
          .send({ code: result.code, message: result.message });
      room.match = result.state;
      room.matchRevision += 1;
      return gameProject(room, viewer);
    },
  );
}
