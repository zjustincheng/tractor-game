import {
  closeSync,
  existsSync,
  fsyncSync,
  mkdirSync,
  openSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { join } from 'node:path';
import type { BotMatch } from './bot-match.js';

export interface SavedMatch {
  match: BotMatch;
  revision: number;
  touched: number;
}
const validId =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

/** Single-process storage. Write and sync a replacement before publishing it in memory. */
export class MatchStore {
  private entries = new Map<string, SavedMatch>();
  constructor(
    private directory?: string,
    validate?: (id: string, entry: SavedMatch) => void,
  ) {
    if (!directory) return;
    mkdirSync(directory, { recursive: true, mode: 0o700 });
    for (const file of readdirSync(directory)) {
      if (!file.endsWith('.json')) continue;
      const id = file.slice(0, -5);
      if (!validId.test(id)) continue;
      try {
        const saved = JSON.parse(readFileSync(join(directory, file), 'utf8'));
        if (
          saved.format !== 1 ||
          !Number.isSafeInteger(saved.entry?.revision) ||
          saved.entry.revision < 0 ||
          !Number.isSafeInteger(saved.entry.touched)
        )
          throw new Error('Unsupported or invalid snapshot.');
        validate?.(id, saved.entry);
        this.entries.set(id, saved.entry);
      } catch (error) {
        throw new Error(
          `Cannot restore match ${id}. Preserve the save file and repair or move it before restarting.`,
          { cause: error },
        );
      }
    }
  }
  get size() {
    return this.entries.size;
  }
  get(id: string) {
    return this.entries.get(id);
  }
  [Symbol.iterator]() {
    return this.entries[Symbol.iterator]();
  }
  set(id: string, entry: SavedMatch) {
    if (!validId.test(id)) throw new Error('Invalid match ID.');
    if (this.directory) {
      const target = join(this.directory, `${id}.json`);
      const temporary = `${target}.tmp`;
      const descriptor = openSync(temporary, 'w', 0o600);
      try {
        writeFileSync(descriptor, JSON.stringify({ format: 1, entry }));
        fsyncSync(descriptor);
      } finally {
        closeSync(descriptor);
      }
      renameSync(temporary, target);
      const folder = openSync(this.directory, 'r');
      try {
        fsyncSync(folder);
      } finally {
        closeSync(folder);
      }
    }
    this.entries.set(id, entry);
  }
  delete(id: string) {
    if (this.directory && validId.test(id)) {
      const file = join(this.directory, `${id}.json`);
      if (existsSync(file)) rmSync(file);
    }
    this.entries.delete(id);
  }
}
