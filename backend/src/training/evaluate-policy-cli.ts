import {
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
  renameSync,
  writeFileSync,
} from 'node:fs';
import { dirname, relative, resolve, join } from 'node:path';
import { POLICY_VERSION } from './learned-policy.js';
import {
  parsePolicyCheckpoint,
  policyPasses,
  PROMOTION_CHAMPION_SEEDS,
} from './policy-training.js';
import { heuristicPolicy } from '../bot-policy.js';
import type { PolicyCheckpoint, PolicyReport } from './policy-training.js';
import {
  evaluatePolicyFresh,
  formatPolicyEvaluation,
  parseHistoricalPolicyGame,
  summarizePolicyHistory,
} from './policy-evaluation.js';
import type { HistoricalPolicyGame, PolicyPair } from './policy-evaluation.js';

function commitPromotion(
  checkpointPath: string,
  checkpoint: PolicyCheckpoint,
  learner: PolicyPair,
  champion: PolicyPair | null,
  promotionRevalidation: NonNullable<PolicyReport['promotionRevalidation']>,
): void {
  const lastIndex = checkpoint.reports.length - 1;
  if (lastIndex < 0)
    throw new Error('Cannot promote before the first generation');
  const updated: PolicyCheckpoint = {
    ...checkpoint,
    leadChampion: learner.lead,
    followChampion: learner.follow,
    champion: learner.lead,
    leadLearner: learner.lead,
    followLearner: learner.follow,
    learner: learner.lead,
    policyArchive: champion
      ? [...(checkpoint.policyArchive ?? []), champion].slice(-4)
      : (checkpoint.policyArchive ?? []),
    archive: champion
      ? [...checkpoint.archive, checkpoint.leadChampion!].slice(-4)
      : checkpoint.archive,
    championMarginSamples: [],
    championLevelMarginSamples: [],
    nonPromotionStreak: 0,
    generationsSincePromotion: 0,
    rollbackCooldown: 0,
    reports: checkpoint.reports.map((report, index) =>
      index === lastIndex
        ? {
            ...report,
            promoted: true,
            nonPromotionStreak: 0,
            generationsSincePromotion: 0,
            confirmation: {
              baseline: promotionRevalidation.confirmation.baseline,
              champion: promotionRevalidation.confirmation.champion,
            },
            promotionRevalidation,
          }
        : report,
    ),
  };
  writeFileSync(
    checkpointPath + '.tmp',
    JSON.stringify(updated, null, 2) + '\n',
  );
  renameSync(checkpointPath + '.tmp', checkpointPath);
}

function findGameLogs(path: string): string[] {
  if (!existsSync(path))
    throw new Error(`History path does not exist: ${path}`);
  if (statSync(path).isFile())
    return path.endsWith('.jsonl') ? [resolve(path)] : [];
  return readdirSync(path, { withFileTypes: true }).flatMap((entry) => {
    const child = resolve(path, entry.name);
    if (entry.isFile() && entry.name === 'games.jsonl') return [child];
    if (entry.isDirectory()) return findGameLogs(child);
    return [];
  });
}

function loadHistory(paths: string[]): {
  entries: HistoricalPolicyGame[];
  excluded: number;
} {
  const entries: HistoricalPolicyGame[] = [];
  let excluded = 0;
  for (const path of paths) {
    let fallbackVersion: string | undefined;
    const checkpointPath = join(dirname(path), 'checkpoint.json');
    const runPath = join(dirname(path), 'run.json');
    if (existsSync(runPath)) {
      try {
        const saved = JSON.parse(readFileSync(runPath, 'utf8')) as {
          policyVersion?: unknown;
        };
        if (typeof saved.policyVersion === 'string')
          fallbackVersion = saved.policyVersion;
      } catch {
        // Fall back to the checkpoint for runs created before run metadata.
      }
    }
    if (!fallbackVersion && existsSync(checkpointPath)) {
      try {
        const saved = JSON.parse(readFileSync(checkpointPath, 'utf8')) as {
          policyVersion?: unknown;
        };
        if (typeof saved.policyVersion === 'string')
          fallbackVersion = saved.policyVersion;
      } catch {
        // A malformed sibling checkpoint cannot identify legacy row versions.
      }
    }
    const lines = readFileSync(path, 'utf8').split(/\r?\n/);
    for (let index = 0; index < lines.length; index++) {
      const line = lines[index]!.trim();
      if (!line) continue;
      let row: unknown;
      try {
        row = JSON.parse(line);
      } catch {
        throw new Error(`Invalid JSON at ${path}:${index + 1}`);
      }
      const parsed = parseHistoricalPolicyGame(
        row,
        relative(process.cwd(), path),
        fallbackVersion,
      );
      if (parsed) entries.push(parsed);
      else excluded++;
    }
  }
  return { entries, excluded };
}

function parseArgs(): Map<string, string> {
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log(
      'npm run evaluate:policy -- --checkpoint FILE [--history DIR_OR_FILE] [--seeds 128] [--seed 900000] [--promote]\nEvaluates saved learner/champion policies against fresh paired seeds. --promote revalidates the learner on screening and independent confirmation seeds, then updates the checkpoint champion only if every gate passes. History defaults to the checkpoint run and filters to the current policy version.',
    );
    process.exit(0);
  }
  const allowed = new Set([
    '--checkpoint',
    '--history',
    '--seeds',
    '--seed',
    '--promote',
  ]);
  const options = new Map<string, string>();
  for (let i = 0; i < args.length;) {
    const key = args[i]!;
    if (key === '--promote') {
      if (options.has(key)) throw new Error(`Invalid option: ${key}`);
      options.set(key, 'true');
      i++;
      continue;
    }
    const value = args[i + 1];
    if (
      !allowed.has(key) ||
      options.has(key) ||
      !value ||
      value.startsWith('--')
    )
      throw new Error(`Invalid option: ${key}`);
    options.set(key, value);
    i += 2;
  }
  if (!options.has('--checkpoint')) throw new Error('--checkpoint is required');
  return options;
}

function main() {
  const options = parseArgs();
  const checkpointPath = resolve(options.get('--checkpoint')!);
  const checkpoint = parsePolicyCheckpoint(
    JSON.parse(readFileSync(checkpointPath, 'utf8')),
  );
  const seeds = Number(options.get('--seeds') ?? 128);
  const seed = Number(options.get('--seed') ?? 900000);
  if (!Number.isSafeInteger(seeds) || seeds < 1 || seeds > 10000)
    throw new Error('--seeds must be an integer from 1 to 10000');
  if (!Number.isSafeInteger(seed) || seed < 0 || seed > 0xffffffff)
    throw new Error('--seed must be an unsigned 32-bit integer');
  const learner: PolicyPair = {
    lead: checkpoint.leadLearner,
    follow: checkpoint.followLearner,
  };
  const champion =
    checkpoint.leadChampion && checkpoint.followChampion
      ? { lead: checkpoint.leadChampion, follow: checkpoint.followChampion }
      : null;

  // Always evaluate the exact current learner. Historical reports may describe
  // different weights or priors and are not fresh evidence for a revised gate.
  console.log(
    `Fresh paired evaluation: ${seeds} seeds per table size, max ${checkpoint.config.maxRounds} rounds; ` +
      `${checkpoint.config.playerCounts.length * seeds * 2} matches per policy; seed base ${seed}`,
  );
  const evaluateFresh = (
    label: string,
    policy: PolicyPair,
    seedStart: number,
    opposingPolicy: PolicyPair | null = null,
    // Live Sharp is the held-out opponent: training never practises against it.
    opponentBot?: ReturnType<typeof heuristicPolicy>,
    seedCount = seeds,
  ) => {
    console.log(`Starting ${label} (${seedCount} seeds)...`);
    const evaluation = evaluatePolicyFresh(
      policy,
      checkpoint.config,
      seedCount,
      seedStart,
      (completed, total, playerCount) => {
        if (completed % 8 === 0 || completed === total)
          console.log(
            `${label}: ${completed}/${total} paired seeds complete (${playerCount}-seat table)`,
          );
      },
      opposingPolicy,
      opponentBot,
    );
    console.log(formatPolicyEvaluation(label, evaluation));
    return evaluation;
  };
  if (champion) evaluateFresh('Validated champion vs baseline', champion, seed);
  const learnerVsBaseline = evaluateFresh(
    'Current learner vs baseline',
    learner,
    seed,
  );

  if (options.has('--promote')) {
    const archivedPolicies = checkpoint.policyArchive ?? [];
    const archived = archivedPolicies.length
      ? archivedPolicies[(checkpoint.generation - 1) % archivedPolicies.length]!
      : null;
    const learnerVsChampion = champion
      ? evaluateFresh(
          'Promotion screen: learner vs champion',
          learner,
          seed,
          champion,
          undefined,
          seeds >= 128 ? Math.max(seeds, PROMOTION_CHAMPION_SEEDS) : seeds,
        )
      : null;
    const learnerVsArchive = archived
      ? evaluateFresh(
          'Promotion screen: learner vs archive',
          learner,
          seed,
          archived,
        )
      : null;
    const sharpGate = checkpoint.sharpGate ?? true;
    const learnerVsSharp = sharpGate
      ? evaluateFresh(
          'Promotion screen: learner vs live Sharp (held out)',
          learner,
          seed,
          null,
          heuristicPolicy('sharp'),
        )
      : null;
    const screenChecks = [
      ['baseline', learnerVsBaseline] as const,
      ...(learnerVsChampion ? [['champion', learnerVsChampion] as const] : []),
      ...(learnerVsArchive ? [['archive', learnerVsArchive] as const] : []),
      ...(learnerVsSharp ? [['sharp', learnerVsSharp] as const] : []),
    ];
    const failedScreen = screenChecks.filter(
      ([, evaluation]) => !policyPasses(evaluation),
    );
    const screened = failedScreen.length === 0;
    if (!screened) {
      console.log(
        `Promotion screen failed (${failedScreen
          .map(
            ([label, evaluation]) =>
              `${label}: ${evaluation.truncated}/${evaluation.games} truncated, ${evaluation.pairs ?? 0}/${evaluation.games / 2} pairs`,
          )
          .join('; ')}); checkpoint was not changed.`,
      );
    } else {
      const confirmSeed = (seed + 1_000_000_000) >>> 0;
      const confirmationBaseline = evaluateFresh(
        'Promotion confirmation: learner vs baseline',
        learner,
        confirmSeed,
      );
      const confirmationChampion = champion
        ? evaluateFresh(
            'Promotion confirmation: learner vs champion',
            learner,
            confirmSeed,
            champion,
            undefined,
            seeds >= 128 ? Math.max(seeds, PROMOTION_CHAMPION_SEEDS) : seeds,
          )
        : null;
      const confirmationArchive = archived
        ? evaluateFresh(
            'Promotion confirmation: learner vs archive',
            learner,
            confirmSeed,
            archived,
          )
        : null;
      const confirmationSharp = sharpGate
        ? evaluateFresh(
            'Promotion confirmation: learner vs live Sharp (held out)',
            learner,
            confirmSeed,
            null,
            heuristicPolicy('sharp'),
          )
        : null;
      const confirmationChecks = [
        ['baseline', confirmationBaseline] as const,
        ...(confirmationChampion
          ? [['champion', confirmationChampion] as const]
          : []),
        ...(confirmationArchive
          ? [['archive', confirmationArchive] as const]
          : []),
        ...(confirmationSharp ? [['sharp', confirmationSharp] as const] : []),
      ];
      const failedConfirmation = confirmationChecks.filter(
        ([, evaluation]) => !policyPasses(evaluation),
      );
      const confirmed = failedConfirmation.length === 0;
      if (!confirmed) {
        console.log(
          `Promotion confirmation failed (${failedConfirmation
            .map(
              ([label, evaluation]) =>
                `${label}: ${evaluation.truncated}/${evaluation.games} truncated, ${evaluation.pairs ?? 0}/${evaluation.games / 2} pairs`,
            )
            .join('; ')}); checkpoint was not changed.`,
        );
      } else {
        commitPromotion(checkpointPath, checkpoint, learner, champion, {
          validatedAt: new Date().toISOString(),
          baseline: learnerVsBaseline,
          champion: learnerVsChampion ?? learnerVsBaseline,
          archive: learnerVsArchive,
          sharp: learnerVsSharp,
          confirmation: {
            baseline: confirmationBaseline,
            champion: confirmationChampion,
            archive: confirmationArchive,
            sharp: confirmationSharp,
          },
        });
        console.log(
          `Promotion passed on fresh seeds. Checkpoint champion updated at generation ${checkpoint.generation}.`,
        );
      }
    }
  }

  const historyPath = resolve(
    options.get('--history') ?? dirname(checkpointPath),
  );
  const files = findGameLogs(historyPath);
  const loaded = loadHistory(files);
  const history = summarizePolicyHistory(loaded.entries);
  console.log(
    `\nSaved validation history: ${loaded.entries.length} ${POLICY_VERSION} games; excluded ${loaded.excluded} stale, unversioned, or non-validation rows from ${files.length} files`,
  );
  console.log(
    formatPolicyEvaluation(
      'Pooled matching-version history (descriptive; may mix generations)',
      history.pooled,
    ),
  );
  const modifiedAt = new Map<string, number>();
  const fileTime = (file: string) => {
    let value = modifiedAt.get(file);
    if (value === undefined) {
      value = statSync(resolve(file)).mtimeMs;
      modifiedAt.set(file, value);
    }
    return value;
  };
  const recentHistory = [...history.groups]
    .sort((a, b) => {
      const modifiedDifference = fileTime(a.file) - fileTime(b.file);
      return modifiedDifference || a.generation - b.generation;
    })
    .slice(-12);
  for (const group of recentHistory)
    console.log(
      formatPolicyEvaluation(
        `${group.file} generation ${group.generation}`,
        group.evaluation,
      ),
    );
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
