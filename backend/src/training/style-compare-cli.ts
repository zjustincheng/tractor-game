import { readFileSync } from 'node:fs';
import { parseArgs } from 'node:util';
import { resolve } from 'node:path';
import { parsePolicy } from './learned-policy.js';
import type { PolicyModel } from './learned-policy.js';
import { evaluatePolicyFresh } from './policy-evaluation.js';
import { heuristicPolicy } from '../bot-policy.js';
import { parseConfig } from './optimizer.js';

/** Paired matches: a v11 champion with the play-style guards vs without them. */
const { values } = parseArgs({
  options: {
    checkpoint: { type: 'string' },
    seeds: { type: 'string', default: '64' },
    opponent: { type: 'string', default: 'self' },
  },
});
const saved = JSON.parse(readFileSync(resolve(values.checkpoint!), 'utf8')) as {
  leadChampion: PolicyModel;
  followChampion: PolicyModel;
};
const guarded = {
  lead: parsePolicy(saved.leadChampion),
  follow: parsePolicy(saved.followChampion),
};
const slice = (model: PolicyModel) => ({
  ...model,
  input: model.input.map((row) => row.slice(0, 30)),
});
const plain = { lead: slice(guarded.lead), follow: slice(guarded.follow) };
const config = parseConfig({
  seed: 1,
  playerCounts: [4],
  trainSeeds: 1,
  validationSeeds: Number(values.seeds),
  maxRounds: 60,
});
const seeds = Number(values.seeds);
const report = (
  label: string,
  evaluation: ReturnType<typeof evaluatePolicyFresh>,
) =>
  console.log(
    `${label}: ${evaluation.wins}-${evaluation.losses} matches, rounds ${evaluation.roundWins}/${evaluation.completedRounds}, level margin ${evaluation.levelMarginMean?.toFixed(2)} (${evaluation.levelMarginLow?.toFixed(2)} to ${evaluation.levelMarginHigh?.toFixed(2)})`,
  );
if (values.opponent === 'self')
  report(
    'guarded vs plain champion',
    evaluatePolicyFresh(guarded, config, seeds, 700000, undefined, plain),
  );
else {
  report(
    'guarded vs sharp',
    evaluatePolicyFresh(
      guarded,
      config,
      seeds,
      800000,
      undefined,
      null,
      heuristicPolicy('sharp'),
    ),
  );
  report(
    'plain vs sharp',
    evaluatePolicyFresh(
      plain,
      config,
      seeds,
      800000,
      undefined,
      null,
      heuristicPolicy('sharp'),
    ),
  );
}
