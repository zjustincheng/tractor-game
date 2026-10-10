import { learnedBotPolicy } from './bot-policy.js';
import type { BotPolicy } from '../bot-policy.js';
import { readFileSync } from 'node:fs';
import { choosePolicyLead, parsePolicy } from './learned-policy.js';
import type { LeadPolicy, PolicyModel } from './learned-policy.js';
import { parsePolicyCheckpoint } from './policy-training.js';

/** Serve a saved v10 champion using its original 22-input inference path.
 * Training imports still migrate and retire its validation. Live loading must
 * not silently replace a validated champion with a migrated learner.
 */
function loadCheckpoint(path: string, experimental: boolean) {
  const saved = JSON.parse(readFileSync(path, 'utf8'));
  const checkpoint = parsePolicyCheckpoint(saved);
  if (
    !experimental &&
    saved.policyVersion === 'contextual-leads-v10-adaptive-prior'
  ) {
    const legacy = (model: PolicyModel | null | undefined) => {
      if (!model) return null;
      const parsed = parsePolicy(model);
      return { ...parsed, input: parsed.input.map((row) => row.slice(0, 22)) };
    };
    checkpoint.champion = checkpoint.leadChampion = legacy(
      saved.leadChampion ?? saved.champion,
    );
    checkpoint.followChampion = legacy(saved.followChampion ?? saved.champion);
  }
  return checkpoint;
}

export function loadPolicyLead(
  path: string,
  experimentalLearner = false,
): LeadPolicy {
  const checkpoint = loadCheckpoint(path, experimentalLearner);
  const policy = experimentalLearner ? checkpoint.learner : checkpoint.champion;
  if (!policy)
    throw new Error(
      'This checkpoint has no validated champion. Continue training, or set BOT_POLICY_USE_LEARNER=1 to explicitly try the experimental learner.',
    );
  return (hand, trump, context) =>
    choosePolicyLead(policy, hand, trump, context);
}

export function loadBotPolicy(
  path: string,
  experimentalLearner = false,
): BotPolicy {
  const checkpoint = loadCheckpoint(path, experimentalLearner);
  const lead = experimentalLearner
    ? checkpoint.leadLearner
    : checkpoint.leadChampion;
  const follow = experimentalLearner
    ? checkpoint.followLearner
    : checkpoint.followChampion;
  if (!lead || !follow)
    throw new Error(
      'This checkpoint has no validated champion. Set BOT_POLICY_USE_LEARNER=1 to try the learner.',
    );
  return {
    ...learnedBotPolicy(lead, follow),
    ...(experimentalLearner ? {} : { models: { lead, follow } }),
  };
}
