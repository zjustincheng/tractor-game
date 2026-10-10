import { readFile } from 'node:fs/promises';
import { Pool } from 'pg';
import { ROOM_LIFETIME_MS } from './room-repository.js';
import type {
  RoomRecord,
  RoomRepository,
  SaveRoom,
} from './room-repository.js';

/** Each mutation validates the latest state while holding the room row lock. */
export class PostgresRoomStore<
  T extends RoomRecord,
> implements RoomRepository<T> {
  readonly pool: Pool;
  constructor(
    connectionString: string,
    private readonly now: () => number = Date.now,
  ) {
    this.pool = new Pool({
      connectionString,
      max: 10,
      connectionTimeoutMillis: 5000,
    });
  }
  async initialize() {
    const sql = await readFile(
      new URL('../../infrastructure/rooms.sql', import.meta.url),
      'utf8',
    );
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      // Serialize schema initialization across replicas, including an empty database.
      await client.query('select pg_advisory_xact_lock(734821906)');
      await client.query(sql);
      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  }
  async close() {
    await this.pool.end();
  }
  async read(code: string) {
    const result = await this.pool.query<{ payload: T }>(
      'select payload from tractor_rooms where code = $1',
      [code],
    );
    const room = result.rows[0]?.payload;
    return room && room.createdAt > this.now() - ROOM_LIFETIME_MS
      ? room
      : undefined;
  }
  async create(room: T, event: unknown) {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      await client.query(
        "delete from tractor_rooms where (payload->>'createdAt')::bigint <= $1",
        [this.now() - ROOM_LIFETIME_MS],
      );
      const inserted = await client.query(
        'insert into tractor_rooms(code, payload, revision, match_revision) values ($1, $2, 1, $3) on conflict (code) do nothing returning code',
        [room.code, room, room.matchRevision],
      );
      if (inserted.rowCount)
        await client.query(
          'insert into tractor_room_events(code, revision, payload) values ($1, 1, $2)',
          [room.code, event],
        );
      await client.query('commit');
      return inserted.rowCount === 1;
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  }
  async transact<R>(
    code: string,
    action: (room: T | undefined, save: SaveRoom<T>) => R,
  ) {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      const current = await client.query<{ payload: T }>(
        'select payload from tractor_rooms where code = $1 for update',
        [code],
      );
      const room = current.rows[0]?.payload;
      let pending: { room: T; event: unknown } | undefined;
      const result = action(
        room && room.createdAt > this.now() - ROOM_LIFETIME_MS
          ? room
          : undefined,
        (updated, event) => {
          pending = { room: updated, event };
        },
      );
      if (pending) {
        const updated = await client.query<{ revision: string }>(
          'update tractor_rooms set payload = $2, revision = revision + 1, match_revision = $3, touched_at = now() where code = $1 returning revision',
          [code, pending.room, pending.room.matchRevision],
        );
        if (!updated.rows[0])
          throw new Error('Room disappeared during transaction');
        await client.query(
          'insert into tractor_room_events(code, revision, payload) values ($1, $2, $3)',
          [code, updated.rows[0].revision, pending.event],
        );
      }
      await client.query('commit');
      return result;
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  }
}
