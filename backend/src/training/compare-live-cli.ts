import { readFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { heuristicPolicy } from '../bot-policy.js';
import { parsePolicyCheckpoint } from './policy-training.js';
import {
  evaluatePolicyFresh,
  formatPolicyEvaluation,
} from './policy-evaluation.js';

const { values } = parseArgs({
  options: {
    checkpoint: { type: 'string' },
    seeds: { type: 'string', default: '32' },
    'seed-start': { type: 'string', default: '3000000000' },
    learner: { type: 'boolean', default: false },
    help: { type: 'boolean', default: false },
  },
});
if (values.help) {
  console.log(
    'npm run compare:live -- --checkpoint FILE [--seeds 32] [--seed-start 3000000000] [--learner]\nRead-only paired matches: the complete saved policy versus live Sharp. Uses checkpoint player counts and round cap; never promotes or trains.',
  );
} else {
  if (!values.checkpoint) throw new Error('--checkpoint is required');
  const seeds = Number(values.seeds);
  const seedStart = Number(values['seed-start']);
  if (
    !Number.isSafeInteger(seeds) ||
    seeds < 1 ||
    seeds > 10000 ||
    !Number.isSafeInteger(seedStart) ||
    seedStart < 0 ||
    seedStart + seeds > 0x100000000
  )
    throw new Error('Invalid seed count or range');
  const checkpoint = parsePolicyCheckpoint(
    JSON.parse(readFileSync(values.checkpoint, 'utf8')),
  );
  const lead = values.learner
    ? checkpoint.leadLearner
    : checkpoint.leadChampion;
  const follow = values.learner
    ? checkpoint.followLearner
    : checkpoint.followChampion;
  if (!lead || !follow)
    throw new Error(
      'No saved champion. Use --learner to explicitly evaluate the learner.',
    );
  console.log(
    `Generation ${checkpoint.generation}; ${values.learner ? 'learner' : 'champion'} vs live Sharp; ${seeds} paired seeds per table size; max ${checkpoint.config.maxRounds} rounds. Sharp retains its existing privileged throw validation.`,
  );
  const result = evaluatePolicyFresh(
    { lead, follow },
    checkpoint.config,
    seeds,
    seedStart,
    (done, total) => console.log(`Completed ${done}/${total} pairs`),
    null,
    heuristicPolicy('sharp'),
  );
  console.log(formatPolicyEvaluation('Saved policy vs live Sharp', result));
  console.log(
    'A small run is a pipeline check, not evidence of superiority. Use separate seeds for a final comparison.',
  );
}
