import { randomInt, randomUUID } from 'node:crypto';
import type { FastifyInstance } from 'fastify';
import {
  roomCreateSchema,
  roomJoinSchema,
  roomReadySchema,
  roomViewSchema,
} from '@tractor/protocol';
import type { PLAYER_COUNTS } from '@tractor/rules';

interface RoomPlayer {
  token: string;
  seat: number;
  displayName: string;
  ready: boolean;
}
interface Room {
  code: string;
  playerCount: (typeof PLAYER_COUNTS)[number];
  hostSeat: number;
  players: RoomPlayer[];
  createdAt: number;
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
    };
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
      return { room: project(room, player), playerToken: player.token };
    },
  );
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
      return project(room, player);
    },
  );
}
