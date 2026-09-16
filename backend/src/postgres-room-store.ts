import { readFile } from 'node:fs/promises';
import { Pool } from 'pg';

/** Shared-store primitive for the future multi-process room route adapter. */
export class PostgresRoomStore {
  readonly pool: Pool;
  constructor(connectionString: string) {
    this.pool = new Pool({ connectionString, max: 10 });
  }
  async migrate() {
    const sql = await readFile(
      new URL('../../infrastructure/rooms.sql', import.meta.url),
      'utf8',
    );
    await this.pool.query(sql);
  }
  async close() {
    await this.pool.end();
  }
  async read<T>(code: string) {
    const result = await this.pool.query<{ payload: T }>(
      'select payload from tractor_rooms where code = $1',
      [code],
    );
    return result.rows[0]?.payload ?? null;
  }
  async write(
    code: string,
    payload: unknown,
    revision: number,
    matchRevision: number,
  ) {
    const client = await this.pool.connect();
    try {
      await client.query('begin');
      const current = await client.query<{ revision: number }>(
        'select revision from tractor_rooms where code = $1 for update',
        [code],
      );
      if (current.rows[0] && current.rows[0].revision >= revision)
        throw new Error('STALE_ROOM_REVISION');
      await client.query(
        'insert into tractor_rooms(code, payload, revision, match_revision) values ($1, $2, $3, $4) on conflict (code) do update set payload = excluded.payload, revision = excluded.revision, match_revision = excluded.match_revision, touched_at = now()',
        [code, payload, revision, matchRevision],
      );
      await client.query('commit');
    } catch (error) {
      await client.query('rollback');
      throw error;
    } finally {
      client.release();
    }
  }
}
