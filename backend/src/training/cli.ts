import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  writeFileSync,
  appendFileSync,
  renameSync,
} from 'node:fs';
import { resolve, join } from 'node:path';
import {
  newCheckpoint,
  parseCheckpoint,
  parseConfig,
  trainGeneration,
} from './optimizer.js';
import type { Checkpoint, Evaluation } from './optimizer.js';

const help = `Usage: npm run train:bots -- [options]
  --generations N        Additional generations (default: 3)
  --seed N               Reproducible random seed (default: 42)
  --players 4,6,8,10     Table sizes (default: 4)
  --train-seeds N        Training deals per generation and table size (default: 4)
  --validation-seeds N   Separate validation deals (default: 8)
  --max-rounds N         Full-match round limit, at most 200 (default: 60)
  --out DIRECTORY        New output directory (must not already exist)
  --resume FILE          Resume checkpoint; uses its saved training configuration
  --trace                Save each decision and terminal team rewards as JSONL
  --help                 Show this help

Every seed runs on both teams. Checkpoints save after each generation.
This is offline lead-weight training; live games are not changed automatically.`;

function main(): void {
  const args = process.argv.slice(2);
  if (args.includes('--help')) {
    console.log(help);
    return;
  }
  const values = new Map<string, string>();
  let trace = false;
  const allowed = new Set([
    '--generations',
    '--seed',
    '--players',
    '--train-seeds',
    '--validation-seeds',
    '--max-rounds',
    '--out',
    '--resume',
  ]);
  for (let index = 0; index < args.length; index++) {
    const key = args[index]!;
    if (key === '--trace' && !trace) {
      trace = true;
      continue;
    }
    if (!allowed.has(key) || values.has(key))
      throw new Error(`Unknown or repeated option: ${key}`);
    const value = args[++index];
    if (!value || value.startsWith('--'))
      throw new Error(`Missing value for ${key}`);
    values.set(key, value);
  }
  const generations = Number(values.get('--generations') ?? 3);
  if (
    !Number.isSafeInteger(generations) ||
    generations < 1 ||
    generations > 10000
  )
    throw new Error('generations must be an integer between 1 and 10000');
  let checkpoint: Checkpoint;
  const resume = values.get('--resume');
  if (resume) {
    if (
      [
        '--seed',
        '--players',
        '--train-seeds',
        '--validation-seeds',
        '--max-rounds',
      ].some((key) => values.has(key))
    )
      throw new Error(
        'Resume uses the saved configuration; omit configuration flags',
      );
    checkpoint = parseCheckpoint(
      JSON.parse(readFileSync(resolve(resume), 'utf8')),
    );
  } else {
    checkpoint = newCheckpoint(
      parseConfig({
        seed: Number(values.get('--seed') ?? 42),
        playerCounts: (values.get('--players') ?? '4').split(',').map(Number),
        trainSeeds: Number(values.get('--train-seeds') ?? 4),
        validationSeeds: Number(values.get('--validation-seeds') ?? 8),
        maxRounds: Number(values.get('--max-rounds') ?? 60),
      }),
    );
  }
  if (checkpoint.generation + generations > 10000)
    throw new Error('Maximum checkpoint generation is 10000');
  let directory: string;
  const requestedDirectory = values.get('--out');
  if (requestedDirectory) {
    directory = resolve(requestedDirectory);
    mkdirSync(directory); // Fail on existing output instead of overwriting an earlier run.
  } else {
    const root = resolve('data/bot-training');
    mkdirSync(root, { recursive: true });
    directory = mkdtempSync(join(root, 'run-'));
  }
  const modelPath = join(directory, 'checkpoint.json');
  const gamePath = join(directory, 'games.jsonl');
  const tracePath = join(directory, 'decisions.jsonl');
  function save(): void {
    const temporary = modelPath + '.tmp';
    writeFileSync(temporary, JSON.stringify(checkpoint, null, 2) + '\n');
    renameSync(temporary, modelPath);
  }
  function summary(evaluation: Evaluation): string {
    return `${evaluation.wins}/${evaluation.games} wins (${(evaluation.winRate * 100).toFixed(1)}%), ${evaluation.truncated} capped`;
  }
  writeFileSync(
    join(directory, 'run.json'),
    JSON.stringify(
      {
        startedAt: new Date().toISOString(),
        resumedFrom: resume ? resolve(resume) : null,
        config: checkpoint.config,
        rulesVersion: checkpoint.rulesVersion,
        policyVersion: checkpoint.policyVersion,
        trace,
      },
      null,
      2,
    ) + '\n',
  );
  save();
  console.log(`Checkpoint: ${modelPath}`);
  console.log(`Match results: ${gamePath}`);
  if (trace) console.log(`Decision records: ${tracePath}`);
  for (let index = 0; index < generations; index++) {
    checkpoint = trainGeneration(checkpoint, {
      onGame: (game) => {
        appendFileSync(gamePath, JSON.stringify(game) + '\n');
        if (trace)
          appendFileSync(
            tracePath,
            JSON.stringify({
              type: 'match_result',
              generation: game.generation,
              phase: game.phase,
              ...game.result,
              // Capped matches have no reward, rather than being mislabeled as losses.
              rewards: game.result.winner
                ? {
                    A: game.result.winner === 'A' ? 1 : -1,
                    B: game.result.winner === 'B' ? 1 : -1,
                  }
                : null,
            }) + '\n',
          );
        console.log(
          `Generation ${game.generation} ${game.phase}: ${game.result.playerCount} seats, seed ${game.result.seed}, candidate ${game.result.candidateTeam}, ${game.result.truncated ? 'round limit reached' : `winner ${game.result.winner}`} (${game.result.rounds} rounds)`,
        );
      },
      ...(trace
        ? {
            onDecision: (game, decision) => {
              appendFileSync(
                tracePath,
                JSON.stringify({ type: 'decision', ...game, ...decision }) +
                  '\n',
              );
            },
          }
        : {}),
    });
    save();
    const report = checkpoint.reports.at(-1)!;
    console.log(
      `Generation ${checkpoint.generation}: ${report.accepted ? 'candidate accepted' : 'incumbent retained'}; training ${summary(report.training)}`,
    );
    console.log(
      `Post-game scorer: ${report.postGameAnalysis.leadDecisions} leads from ${report.postGameAnalysis.matches} completed candidate matches; ${report.postGameAnalysis.applied ? 'adjustments tested on validation' : 'not enough mixed results to adjust'}.`,
    );
    if (report.validationCandidate && report.validationIncumbent)
      console.log(
        `Validation vs baseline: candidate ${summary(report.validationCandidate)}; incumbent ${summary(report.validationIncumbent)}`,
      );
  }
  console.log(
    `Saved generation ${checkpoint.generation}. Resume with --resume ${modelPath}`,
  );
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}
