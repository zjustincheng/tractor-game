export interface RoomRepository<T> {
  get(key: string): T | undefined;
  set(key: string, value: T): void;
  has(key: string): boolean;
  delete(key: string): void;
  [Symbol.iterator](): IterableIterator<[string, T]>;
}

/** Synchronous repository used by the JSON-backed single-process room mode. */
export class MemoryRoomRepository<T> implements RoomRepository<T> {
  private readonly entries = new Map<string, T>();
  get(key: string) {
    return this.entries.get(key);
  }
  set(key: string, value: T) {
    this.entries.set(key, value);
  }
  has(key: string) {
    return this.entries.has(key);
  }
  delete(key: string) {
    this.entries.delete(key);
  }
  [Symbol.iterator]() {
    return this.entries[Symbol.iterator]();
  }
}
