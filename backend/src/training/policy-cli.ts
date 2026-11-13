import {
  appendFileSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  renameSync,
  writeFileSync,
} from 'node:fs';
import { resolve, join, dirname } from 'node:path';
import { availableParallelism } from 'node:os';
import { parseConfig } from './optimizer.js';
import {
  assertEvaluationSize,
  newPolicyCheckpoint,
  parsePolicyCheckpoint,
  recoverChampionMarginSamples,
  trainPolicyGeneration,
} from './policy-training.js';

function main(): void {
  // Evaluation games run on worker threads; TRAINING_WORKERS=1 plays serially.
  process.env.TRAINING_WORKERS ??= String(
    Math.max(1, availableParallelism() - 1),
  );
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log(
      'npm run train:policy -- [--generations 10] [--train-seeds 32] [--validation-seeds 128] [--players 4] [--sharp-gate on|off] [--seed 42] [--max-rounds 60] [--resume FILE] [--out NEW_DIRECTORY]\nTrains a contextual policy with paired end-of-round counterfactual rollouts, clipped updates and fresh promotion confirmation. Promotion must also beat live Sharp, an opponent practice never faces; --sharp-gate off reports that comparison without blocking on it. Champion promotion checks use at least 512 paired seeds; ordinary baseline, archive, and Sharp checks use the configured validation seed count. Resume retains saved settings except validation defaults to at least 128 seeds; --train-seeds, --players and --sharp-gate may be changed on resume. Each generation saves learner and validated champion separately.',
    );
    console.log(
      '--counterfactual-weight 0.1: comparison objective coefficient (0 disables counterfactual learning; range 0–1).',
    );
    return;
  }
  const options = new Map<string, string>();
  const allowed = [
    '--generations',
    '--train-seeds',
    '--validation-seeds',
    '--counterfactual-weight',
    '--players',
    '--sharp-gate',
    '--rules',
    '--seed',
    '--max-rounds',
    '--resume',
    '--out',
  ];
  for (let i = 0; i < args.length; i += 2) {
    const key = args[i]!;
    const value = args[i + 1];
    if (
      !allowed.includes(key) ||
      options.has(key) ||
      !value ||
      value.startsWith('--')
    )
      throw new Error(`Invalid option: ${key}`);
    options.set(key, value);
  }
  const resume = options.get('--resume');
  if (resume && ['--seed', '--max-rounds'].some((key) => options.has(key)))
    throw new Error(
      'Resume keeps the saved deal stream and round cap; omit --seed and --max-rounds',
    );
  const sharpGateOption = options.get('--sharp-gate');
  const rulesOption = options.get('--rules');
  if (rulesOption && !['website', 'roblox'].includes(rulesOption))
    throw new Error('--rules takes website or roblox');
  if (sharpGateOption && !['on', 'off'].includes(sharpGateOption))
    throw new Error('--sharp-gate takes on or off');
  const rawCheckpoint = resume
    ? JSON.parse(readFileSync(resolve(resume), 'utf8'))
    : null;
  let checkpoint = rawCheckpoint
    ? parsePolicyCheckpoint(rawCheckpoint)
    : newPolicyCheckpoint(
        parseConfig({
          seed: Number(options.get('--seed') ?? 42),
          playerCounts: (options.get('--players') ?? '4')
            .split(',')
            .map(Number),
          // Practice, not evaluation, is what the learner actually learns from;
          // a thin generation makes every update a high-variance guess.
          trainSeeds: Number(options.get('--train-seeds') ?? 32),
          validationSeeds: Number(options.get('--validation-seeds') ?? 128),
          counterfactualWeight: Number(
            options.get('--counterfactual-weight') ?? 0.1,
          ),
          maxRounds: Number(options.get('--max-rounds') ?? 60),
        }),
      );
  if (
    resume &&
    rawCheckpoint &&
    typeof rawCheckpoint === 'object' &&
    !Array.isArray(rawCheckpoint) &&
    ((rawCheckpoint as { pointMarginVersion?: unknown }).pointMarginVersion !==
      2 ||
      !Array.isArray(
        (rawCheckpoint as { championMarginSamples?: unknown })
          .championMarginSamples,
      ))
  ) {
    const oldGamesPath = join(dirname(resolve(resume)), 'games.jsonl');
    try {
      const rows = readFileSync(oldGamesPath, 'utf8')
        .split(/\r?\n/)
        .filter(Boolean)
        .flatMap((line) => {
          try {
            return [JSON.parse(line) as unknown];
          } catch {
            return [];
          }
        });
      checkpoint = {
        ...checkpoint,
        championMarginSamples: recoverChampionMarginSamples(checkpoint, rows),
      };
      console.log(
        `Recovered ${(checkpoint.championMarginSamples ?? []).length} pooled champion-comparison pairs from the resumed run log.`,
      );
    } catch {
      // Older checkpoints may have no adjacent game log; training can still proceed.
    }
  }
  if (resume) {
    checkpoint = {
      ...checkpoint,
      config: parseConfig({
        ...checkpoint.config,
        counterfactualWeight: Number(
          options.get('--counterfactual-weight') ??
            checkpoint.config.counterfactualWeight ??
            0.1,
        ),
        validationSeeds: Number(
          options.get('--validation-seeds') ??
            Math.max(128, checkpoint.config.validationSeeds),
        ),
        // Widening practice or table sizes mid-run is allowed on purpose: both
        // broaden what the learner sees. Evaluation seeds stay disjoint either
        // way, so earlier generations remain comparable.
        trainSeeds: Number(
          options.get('--train-seeds') ?? checkpoint.config.trainSeeds,
        ),
        playerCounts: options.has('--players')
          ? options.get('--players')!.split(',').map(Number)
          : checkpoint.config.playerCounts,
      }),
    };
  }
  if (sharpGateOption)
    checkpoint = { ...checkpoint, sharpGate: sharpGateOption === 'on' };
  if (rulesOption)
    checkpoint = { ...checkpoint, robloxRules: rulesOption === 'roblox' };
  if (resume)
    console.log(
      'Resume keeps learner weights; older policies must pass the new evaluation before becoming champion.',
    );
  console.log(
    `Counterfactual objective weight: ${checkpoint.config.counterfactualWeight ?? 0.1}; round-local rewards; fixed baseline prior.`,
  );
  assertEvaluationSize(checkpoint.config);
  const generations = Number(options.get('--generations') ?? 10);
  if (
    !Number.isSafeInteger(generations) ||
    generations < 1 ||
    checkpoint.generation + generations > 10000
  )
    throw new Error('Invalid generation count');
  let directory: string;
  if (options.has('--out')) {
    directory = resolve(options.get('--out')!);
    mkdirSync(directory);
  } else {
    const root = resolve('data/policy-training');
    mkdirSync(root, { recursive: true });
    directory = mkdtempSync(join(root, 'run-'));
  }
  const file = join(directory, 'checkpoint.json');
  function save(): void {
    writeFileSync(file + '.tmp', JSON.stringify(checkpoint, null, 2) + '\n');
    renameSync(file + '.tmp', file);
  }
  save();
  console.log(`Checkpoint: ${file}`);
  for (let i = 0; i < generations; i++) {
    const timings: { phase: string; seconds: number; matches: number }[] = [];
    checkpoint = trainPolicyGeneration(
      checkpoint,
      (phase, result) => {
        appendFileSync(
          join(directory, 'games.jsonl'),
          JSON.stringify({
            generation: checkpoint.generation + 1,
            policyVersion: checkpoint.policyVersion,
            phase,
            result,
          }) + '\n',
        );
        console.log(
          `${phase}: ${result.playerCount} seats, seed ${result.seed}, candidate ${result.candidateTeam}, winner ${result.winner ?? 'capped'}, ${result.rounds} rounds`,
        );
      },
      (phase, milliseconds, matches) =>
        timings.push({ phase, seconds: milliseconds / 1000, matches }),
    );
    save();
    const report = checkpoint.reports.at(-1)!;
    console.log(
      `Generation ${checkpoint.generation}: learned from ${report.decisions} sampled decisions across ${report.learningRounds} rounds (${report.alternativeChoices} alternatives); ${report.vsBaseline.games ? `baseline ${report.vsBaseline.wins}/${report.vsBaseline.games}, champion ${report.vsChampion.wins}/${report.vsChampion.games}` : 'baseline and Sharp skipped'}; ${report.promoted ? 'champion promoted' : 'learner saved; champion unchanged'}`,
    );
    if (report.generationsSincePromotion)
      console.log(
        `Generations since promotion: ${report.generationsSincePromotion}`,
      );
    if (report.nonPromotionStreak)
      console.log(
        `Generations since promotion or learner rollback: ${report.nonPromotionStreak}`,
      );
    if (report.learnerReset)
      console.log(
        `Learner reset to champion after pooled level-margin evidence showed a material regression; Adam moments reset`,
      );
    if (report.robloxGuard)
      console.log(
        report.robloxGuard.returnedToBest
          ? `Roblox guard: learner returned to generation ${report.robloxGuard.bestGeneration} after a sustained drop; Adam moments reset`
          : `Roblox guard: recent ${report.robloxGuard.recentWinRate?.toFixed(3) ?? 'filling'}, best ${report.robloxGuard.bestWinRate?.toFixed(3) ?? 'none'} at generation ${report.robloxGuard.bestGeneration ?? 'none'}`,
      );
    if (report.rollbackCooldown)
      console.log(
        `Rollback held off for ${report.rollbackCooldown} more generation(s) so the learner can recover its step sizes`,
      );
    if (report.championRegression)
      console.log(
        `Pooled level margin vs champion: ${report.championRegression.levelMarginMean?.toFixed(3)} ` +
          `[${report.championRegression.levelMarginLow?.toFixed(3)}, ${report.championRegression.levelMarginHigh?.toFixed(3)}] ` +
          `over ${report.championRegression.pairs} pairs`,
      );
    if (report.comparisons)
      console.log(
        `Comparisons: ${report.comparisons.positions} positions, ${report.comparisons.rollouts} rollouts, ${report.comparisons.informativePairs} informative pairs, ${report.comparisons.betterThanBaseline} alternatives beat baseline in simulation`,
      );
    if (report.explorationBehavior)
      console.log(
        `Practice exploration: ${report.explorationBehavior.differentFromGreedy}/${report.explorationBehavior.sampledDecisions} sampled actions differ from greedy; ` +
          `at the sampling temperature the chosen action held ${report.explorationBehavior.meanChosenProbability.toFixed(3)} ` +
          `and the greedy action ${report.explorationBehavior.meanGreedyProbability.toFixed(3)} mean probability`,
      );
    if (
      report.explorationBehavior &&
      report.explorationBehavior.sampledDecisions > 0 &&
      report.explorationBehavior.meanChosenProbability > 0.95 &&
      report.explorationBehavior.differentFromGreedy /
        report.explorationBehavior.sampledDecisions <
        0.05
    )
      console.log(
        'Warning: practice is nearly deterministic, so self-play results increasingly measure one narrow policy. Investigate the logit spread and prior floor before trusting further gains.',
      );
    if (timings.length)
      console.log(
        `Phase seconds: ${timings
          .map(
            (timing) =>
              `${timing.phase} ${timing.seconds.toFixed(1)}` +
              (timing.matches ? ` (${timing.matches} matches)` : ''),
          )
          .join(', ')}`,
      );
    if (report.evaluationBehavior)
      console.log(
        `Evaluation choices: ${report.evaluationBehavior.differentFromBaseline}/${report.evaluationBehavior.choices} differ from baseline`,
      );
    if (report.update)
      console.log(
        `Updates: lead ${report.update.leadEpochs} epochs, KL ${report.update.leadKL.toFixed(5)}; follow ${report.update.followEpochs} epochs, KL ${report.update.followKL.toFixed(5)}`,
      );
    console.log(
      `Paired margin: ${report.vsBaseline.marginMean?.toFixed(2) ?? 'n/a'} ` +
        `[${report.vsBaseline.marginLow?.toFixed(2) ?? 'n/a'}, ` +
        `${report.vsBaseline.marginHigh?.toFixed(2) ?? 'n/a'}] ` +
        `over ${report.vsBaseline.pairs ?? 0} pairs` +
        (report.vsBaseline.indistinguishable ? ' (indistinguishable)' : ''),
    );
    console.log(
      `Level margin: ${report.vsBaseline.levelMarginMean?.toFixed(2) ?? 'n/a'} ` +
        `[${report.vsBaseline.levelMarginLow?.toFixed(2) ?? 'n/a'}, ` +
        `${report.vsBaseline.levelMarginHigh?.toFixed(2) ?? 'n/a'}]`,
    );
    if (report.evaluationLogits)
      console.log(
        `Learned logit spread: mean ${report.evaluationLogits.meanSpread.toFixed(3)}, ` +
          `p90 ${report.evaluationLogits.p90Spread.toFixed(3)}, ` +
          `baseline prior ${report.evaluationLogits.baselinePrior.toFixed(3)}`,
      );
    if (report.vsRoblox)
      console.log(
        `Roblox bots: ${report.vsRoblox.wins}/${report.vsRoblox.games}, ` +
          `levels ${report.vsRoblox.levelMarginMean?.toFixed(2) ?? 'n/a'} ` +
          `[${report.vsRoblox.levelMarginLow?.toFixed(2) ?? 'n/a'}, ${report.vsRoblox.levelMarginHigh?.toFixed(2) ?? 'n/a'}]`,
      );
    if (report.vsSharp)
      console.log(
        `Held-out live Sharp: ${report.vsSharp.wins}/${report.vsSharp.games}, ` +
          `margin ${report.vsSharp.marginMean?.toFixed(2) ?? 'n/a'} ` +
          `[${report.vsSharp.marginLow?.toFixed(2) ?? 'n/a'}, ${report.vsSharp.marginHigh?.toFixed(2) ?? 'n/a'}]` +
          (checkpoint.sharpGate === false ? ' (reported only)' : ''),
      );
    if (report.confirmation)
      console.log(
        `Fresh confirmation: baseline ${report.confirmation.baseline.wins}/${report.confirmation.baseline.games}, ` +
          `champion ${report.confirmation.champion ? `${report.confirmation.champion.wins}/${report.confirmation.champion.games}` : 'n/a'}` +
          (report.confirmation.sharp
            ? `, live Sharp ${report.confirmation.sharp.wins}/${report.confirmation.sharp.games}`
            : '') +
          (report.confirmation.roblox
            ? `, Roblox bots ${report.confirmation.roblox.wins}/${report.confirmation.roblox.games}` +
              ` (levels ${report.confirmation.roblox.levelMarginMean?.toFixed(2) ?? 'n/a'}` +
              ` [${report.confirmation.roblox.levelMarginLow?.toFixed(2) ?? 'n/a'}, ${report.confirmation.roblox.levelMarginHigh?.toFixed(2) ?? 'n/a'}])`
            : ''),
      );
  }
  console.log(
    `Resume: npm run train:policy -- --resume ${file} --generations 10`,
  );
}
try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
