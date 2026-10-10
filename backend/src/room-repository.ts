import {
  closeSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';

export interface RoomRecord {
  code: string;
  createdAt: number;
  revision: number;
  matchRevision: number;
}
export type SaveRoom<T> = (room: T, event: unknown) => void;
export interface RoomRepository<T extends RoomRecord> {
  initialize(): Promise<void>;
  close(): Promise<void>;
  read(code: string): Promise<T | undefined>;
  create(room: T, event: unknown): Promise<boolean>;
  transact<R>(
    code: string,
    action: (room: T | undefined, save: SaveRoom<T>) => R,
  ): Promise<R>;
}
export const ROOM_LIFETIME_MS = 24 * 60 * 60 * 1000;

/** Copy-on-write keeps failed commands and failed disk writes out of live state. */
export class MemoryRoomRepository<
  T extends RoomRecord,
> implements RoomRepository<T> {
  private readonly entries = new Map<string, T>();
  private ownsLock = false;
  constructor(
    private readonly now: () => number = Date.now,
    private readonly directory?: string,
  ) {}
  async initialize() {
    if (!this.directory) return;
    mkdirSync(this.directory, { recursive: true, mode: 0o700 });
    const lock = join(this.directory, '.owner.lock');
    let descriptor: number;
    try {
      descriptor = openSync(lock, 'wx', 0o600);
    } catch {
      throw new Error(
        'Another backend process already owns the room save directory.',
      );
    }
    this.ownsLock = true;
    try {
      writeFileSync(descriptor, String(process.pid));
    } finally {
      closeSync(descriptor);
    }
    try {
      for (const file of readdirSync(this.directory)) {
        if (!file.endsWith('.json')) continue;
        const room = JSON.parse(
          readFileSync(join(this.directory, file), 'utf8'),
        ) as T;
        if (!room.code || !Number.isFinite(room.createdAt))
          throw new Error(`Invalid room snapshot: ${file}`);
        this.entries.set(room.code, room);
      }
      this.cleanup();
    } catch (error) {
      await this.close();
      throw error;
    }
  }
  async close() {
    if (this.directory && this.ownsLock) {
      rmSync(join(this.directory, '.owner.lock'), { force: true });
      this.ownsLock = false;
    }
  }
  private cleanup() {
    for (const [code, room] of this.entries) {
      if (room.createdAt > this.now() - ROOM_LIFETIME_MS) continue;
      if (this.directory)
        rmSync(join(this.directory, `${code}.json`), { force: true });
      this.entries.delete(code);
    }
  }
  private publish(room: T) {
    if (this.directory) {
      const target = join(this.directory, `${room.code}.json`);
      const temporary = `${target}.tmp`;
      const descriptor = openSync(temporary, 'w', 0o600);
      try {
        writeFileSync(descriptor, JSON.stringify(room));
        fsyncSync(descriptor);
      } finally {
        closeSync(descriptor);
      }
      renameSync(temporary, target);
    }
    this.entries.set(room.code, structuredClone(room));
  }
  async read(code: string) {
    this.cleanup();
    const room = this.entries.get(code);
    return room ? structuredClone(room) : undefined;
  }
  async create(room: T, event: unknown) {
    void event;
    this.cleanup();
    if (this.entries.has(room.code)) return false;
    this.publish(room);
    return true;
  }
  async transact<R>(
    code: string,
    action: (room: T | undefined, save: SaveRoom<T>) => R,
  ) {
    this.cleanup();
    const current = this.entries.get(code);
    let pending: T | undefined;
    const result = action(
      current ? structuredClone(current) : undefined,
      (room) => {
        pending = room;
      },
    );
    if (pending) this.publish(pending);
    return result;
  }
}
