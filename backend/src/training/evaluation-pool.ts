import {
  MessageChannel,
  Worker,
  receiveMessageOnPort,
} from 'node:worker_threads';
import type { MessagePort } from 'node:worker_threads';
import { playEvaluationMatch, playPracticeMatch } from './evaluation-match.js';
import type {
  EvaluationMatch,
  EvaluationOutcome,
  PracticeMatch,
  PracticeOutcome,
} from './evaluation-match.js';

/**
 * Plays evaluation games on worker threads while keeping the caller
 * synchronous: it blocks on a shared counter, then reads every reply with
 * receiveMessageOnPort. Games are seeded and independent, so the outcomes
 * (returned in input order) match a serial run exactly.
 */
export class EvaluationPool {
  private readonly workers: { worker: Worker; port: MessagePort }[] = [];
  private readonly done = new Int32Array(new SharedArrayBuffer(4));
  private batch = 0;

  constructor(size: number) {
    for (let i = 0; i < size; i++) {
      const { port1, port2 } = new MessageChannel();
      const worker = new Worker(
        new URL('./evaluation-worker.ts', import.meta.url),
        {
          workerData: { port: port2, done: this.done },
          transferList: [port2],
        },
      );
      worker.unref();
      this.workers.push({ worker, port: port1 });
    }
  }

  run(
    kind: 'evaluation',
    matches: readonly EvaluationMatch[],
  ): EvaluationOutcome[];
  run(kind: 'practice', matches: readonly PracticeMatch[]): PracticeOutcome[];
  run(
    kind: 'evaluation' | 'practice',
    matches: readonly (EvaluationMatch | PracticeMatch)[],
  ): (EvaluationOutcome | PracticeOutcome)[] {
    if (!matches.length) return [];
    // Interleave, so slow and fast seeds spread evenly across threads.
    const slices = this.workers.map(() => [] as number[]);
    matches.forEach((_, index) => {
      slices[index % slices.length]!.push(index);
    });
    const id = ++this.batch;
    Atomics.store(this.done, 0, 0);
    let sent = 0;
    slices.forEach((indexes, w) => {
      if (!indexes.length) return;
      this.workers[w]!.port.postMessage({
        id,
        kind,
        matches: indexes.map((i) => matches[i]),
      });
      sent++;
    });
    while (Atomics.load(this.done, 0) < sent)
      Atomics.wait(this.done, 0, Atomics.load(this.done, 0), 1000);
    const outcomes = Array<EvaluationOutcome | PracticeOutcome>(matches.length);
    slices.forEach((indexes, w) => {
      if (!indexes.length) return;
      const reply = receiveMessageOnPort(this.workers[w]!.port)?.message as
        | {
            id: number;
            outcomes?: (EvaluationOutcome | PracticeOutcome)[];
            error?: string;
          }
        | undefined;
      if (!reply || reply.id !== id || !reply.outcomes)
        throw new Error(
          `Evaluation worker failed: ${reply?.error ?? 'no reply'}`,
        );
      indexes.forEach((matchIndex, k) => {
        outcomes[matchIndex] = reply.outcomes![k]!;
      });
    });
    return outcomes;
  }

  close() {
    for (const { worker } of this.workers) void worker.terminate();
  }
}

let shared: EvaluationPool | null | undefined;
/** TRAINING_WORKERS sets the thread count; unset, 0 or 1 plays serially.
 * The worker loads TypeScript, so the process must run under tsx. */
export function evaluationPool(): EvaluationPool | null {
  if (shared !== undefined) return shared;
  const requested = Number(process.env.TRAINING_WORKERS ?? 1);
  shared = requested > 1 ? new EvaluationPool(requested) : null;
  return shared;
}

export function playEvaluationMatches(
  matches: readonly EvaluationMatch[],
): EvaluationOutcome[] {
  const pool = evaluationPool();
  return pool
    ? pool.run('evaluation', matches)
    : matches.map(playEvaluationMatch);
}

export function playPracticeMatches(
  matches: readonly PracticeMatch[],
): PracticeOutcome[] {
  const pool = evaluationPool();
  return pool ? pool.run('practice', matches) : matches.map(playPracticeMatch);
}
