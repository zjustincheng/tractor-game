import { parentPort, workerData } from 'node:worker_threads';
import type { MessagePort } from 'node:worker_threads';
import { playEvaluationMatch, playPracticeMatch } from './evaluation-match.js';
import type { EvaluationMatch, PracticeMatch } from './evaluation-match.js';

// Plays batches of evaluation games for evaluation-pool.ts. The pool waits
// synchronously, so each reply also bumps a shared counter and notifies it.
const { port, done } = workerData as { port: MessagePort; done: Int32Array };
port.on(
  'message',
  (batch: {
    id: number;
    kind: 'evaluation' | 'practice';
    matches: (EvaluationMatch | PracticeMatch)[];
  }) => {
    let reply;
    try {
      reply = {
        id: batch.id,
        outcomes:
          batch.kind === 'practice'
            ? (batch.matches as PracticeMatch[]).map(playPracticeMatch)
            : (batch.matches as EvaluationMatch[]).map(playEvaluationMatch),
      };
    } catch (error) {
      reply = { id: batch.id, error: String((error as Error).stack ?? error) };
    }
    port.postMessage(reply);
    Atomics.add(done, 0, 1);
    Atomics.notify(done, 0);
  },
);
parentPort?.unref();
