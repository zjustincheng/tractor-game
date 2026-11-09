import { DEFAULT_BOT_LEAD_WEIGHTS } from '@tractor/rules';
import { parseArgs } from 'node:util';
import { resolve } from 'node:path';
import { loadBotPolicy } from './load-policy.js';
import { leadOptions, playOptions } from './learned-policy.js';
import { heuristicPolicy } from '../bot-policy.js';
import type { BotPolicy } from '../bot-policy.js';
import { playTrainingMatch } from './self-play.js';
import { followFlaw, leadFlaw, summarizeFollows } from './play-style.js';

/** Counts how often a policy makes the reviewed play-style mistakes. */
const { values } = parseArgs({
  options: {
    checkpoint: { type: 'string' },
    seeds: { type: 'string', default: '16' },
    'max-rounds': { type: 'string', default: '60' },
    label: { type: 'string', default: 'champion' },
  },
});
const seeds = Number(values.seeds);
const counts = { leads: 0, follows: 0 };
const flaws: Record<string, number> = {
  'pair-before-ace': 0,
  'big-trump-no-plan': 0,
  'big-joker-lead': 0,
  'joker-waste': 0,
  'barely-beat': 0,
};
const base: BotPolicy = values.checkpoint
  ? loadBotPolicy(resolve(values.checkpoint))
  : heuristicPolicy('sharp');
const audited: BotPolicy = {
  ...base,
  lead: (hand, trump, context, others) => {
    const ids = base.lead(hand, trump, context, others);
    counts.leads++;
    const flaw = leadFlaw(
      hand,
      trump,
      ids,
      leadOptions(hand, trump, context),
      context,
    );
    if (flaw) flaws[flaw]!++;
    return ids;
  },
  follow: (hand, lead, trump, context) => {
    const ids = base.follow(hand, lead, trump, context);
    if (!context || !lead) return ids;
    counts.follows++;
    const options = playOptions(hand, lead, trump, context, true);
    const key = [...ids].sort().join('|');
    const index = options.findIndex(
      (option) => [...option.cardIds].sort().join('|') === key,
    );
    if (index >= 0) {
      const summaries = summarizeFollows(hand, lead, trump, context, options);
      const flaw = followFlaw(context, summaries[index]!, summaries);
      if (flaw) flaws[flaw]!++;
    }
    return ids;
  },
};
for (let seed = 0; seed < seeds; seed++)
  for (const candidateTeam of ['A', 'B'] as const)
    playTrainingMatch({
      seed: (9000 + seed) >>> 0,
      playerCount: 4,
      candidateTeam,
      candidate: DEFAULT_BOT_LEAD_WEIGHTS,
      opponent: DEFAULT_BOT_LEAD_WEIGHTS,
      maxRounds: Number(values['max-rounds']),
      candidatePolicy: audited,
      opponentPolicy: heuristicPolicy('sharp'),
    });
const rate = (n: number, of: number) =>
  `${n} (${((100 * n) / of).toFixed(2)}%)`;
console.log(
  `${values.label}: ${counts.leads} leads, ${counts.follows} follows`,
);
for (const name of ['pair-before-ace', 'big-trump-no-plan', 'big-joker-lead'])
  console.log(`  ${name}: ${rate(flaws[name]!, counts.leads)} of leads`);
for (const name of ['joker-waste', 'barely-beat'])
  console.log(`  ${name}: ${rate(flaws[name]!, counts.follows)} of follows`);
