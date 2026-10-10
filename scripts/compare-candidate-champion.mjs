/* global process, console */
import fs from 'node:fs';
import { parsePolicy } from '../backend/src/training/learned-policy.ts';
import { parsePolicyCheckpoint } from '../backend/src/training/policy-training.ts';
import {
  evaluatePolicyFresh,
  formatPolicyEvaluation,
} from '../backend/src/training/policy-evaluation.ts';

const candidatePath = process.argv[2];
const championPath = process.argv[3];
if (!candidatePath || !championPath)
  throw new Error('candidate and champion checkpoints are required');
const candidate = parsePolicyCheckpoint(
  JSON.parse(fs.readFileSync(candidatePath, 'utf8')),
);
const championRaw = JSON.parse(fs.readFileSync(championPath, 'utf8'));
const champion = {
  lead: parsePolicy(championRaw.leadChampion ?? championRaw.champion),
  follow: parsePolicy(championRaw.followChampion ?? championRaw.champion),
};
const result = evaluatePolicyFresh(
  { lead: candidate.leadLearner, follow: candidate.followLearner },
  candidate.config,
  128,
  1794000000,
  (done) => {
    if (done % 16 === 0) console.log(`Completed ${done}/128 paired seeds`);
  },
  champion,
);
console.log(formatPolicyEvaluation('Candidate vs current champion', result));
