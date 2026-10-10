import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  writeFileSync,
} from 'node:fs';
import { resolve, join } from 'node:path';
import { parseArgs } from 'node:util';
import type { SavedMatch } from '../match-store.js';
import { parsePolicyCheckpoint } from './policy-training.js';
import { learnRecordedRounds, reconstructMatch } from './match-learning.js';
import type { RecordedRound } from './match-learning.js';

const { values } = parseArgs({
  options: {
    checkpoint: { type: 'string' },
    matches: { type: 'string', default: 'backend/data/matches' },
    output: { type: 'string', default: 'data/policy-training' },
    help: { type: 'boolean' },
  },
});
if (values.help)
  console.log(
    'npm run learn:matches -- --checkpoint FILE [--matches DIRECTORY] [--output DIRECTORY]\nScans all saved solo matches, replays complete rounds and learns from simulated alternative continuations. Saves a new experimental learner; never promotes.',
  );
else {
  if (!values.checkpoint) throw new Error('--checkpoint is required');
  const checkpoint = parsePolicyCheckpoint(
    JSON.parse(readFileSync(values.checkpoint, 'utf8')),
  );
  const rounds: RecordedRound[] = [];
  const sources: {
    file: string;
    recoveredRounds?: number;
    skipped?: unknown;
    error?: string;
  }[] = [];
  for (const file of readdirSync(values.matches)
    .sort()
    .filter((f) => /^[\da-f-]{36}\.json$/.test(f))) {
    try {
      const saved = JSON.parse(
        readFileSync(join(values.matches, file), 'utf8'),
      ) as { format: number; entry: SavedMatch };
      if (saved.format !== 1 || !saved.entry?.match)
        throw new Error('Invalid saved match');
      const result = reconstructMatch(saved.entry.match);
      rounds.push(...result.rounds);
      sources.push({
        file,
        recoveredRounds: result.rounds.length,
        skipped: result.skipped,
      });
      console.log(
        `${file}: ${result.rounds.length} complete rounds; ${result.skipped.length} skipped`,
      );
    } catch (error) {
      sources.push({ file, error: (error as Error).message });
      console.log(`${file}: skipped (${(error as Error).message})`);
    }
  }
  const result = learnRecordedRounds(checkpoint, rounds, (round, pairs) =>
    console.log(
      `Reviewed round ${round.round}: ${pairs} informative alternative comparisons`,
    ),
  );
  if (result.report.rounds === 0) {
    console.log('No new reconstructable rounds. No checkpoint written.');
  } else {
    mkdirSync(values.output, { recursive: true });
    const directory = mkdtempSync(
      join(resolve(values.output), 'human-learning-'),
    );
    writeFileSync(
      join(directory, 'checkpoint.json'),
      JSON.stringify(result.checkpoint),
      { flag: 'wx' },
    );
    writeFileSync(
      join(directory, 'review.json'),
      JSON.stringify(
        {
          sourceCheckpoint: resolve(values.checkpoint),
          sources,
          ...result.report,
          method:
            'Privileged offline round continuations; public-only policy features. Simulation labels, not proven improvements against humans.',
        },
        null,
        2,
      ),
      { flag: 'wx' },
    );
    console.log(JSON.stringify(result.report, null, 2));
    console.log(`Saved experimental learner: ${directory}/checkpoint.json`);
    console.log(
      'Source checkpoint unchanged. Evaluate the learner on separate deals before promotion.',
    );
  }
}
