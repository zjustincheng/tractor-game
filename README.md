# Tractor · 升级 / 拖拉机

A partnership card game for 4, 6, 8, or 10 players, built around the supplied version 2.1 rules and [confirmed clarifications](docs/rules-decisions.md).

## Current milestone

You can play a complete solo match against bots with 4, 6, 8, or 10 seats: declare trump, exchange the kitty, play tricks, settle each round, and advance through the J checkpoint to A. The backend validates every play. A sample-hand explorer and guided trick drills are also available.

Bots use deterministic strategies with their own hands and public trick information: choose supported declarations, conserve strength behind winning partners, feed points when last to play, choose cheap winning responses against opponents, adjust leads based on attacker/defender role and threshold pressure, and make attacker gambles only after server-side validation. They lead homogeneous structures and follow the existing structure/gamble rules; humans may attempt gambles. Solo matches reveal one card every 400 milliseconds (about ten seconds per deal). You can call trump as soon as the required cards arrive, with at least eight more seconds to call after the deal finishes. Private human rooms support full rounds, reconnect, and dealer/level progression. Hosted deployment remains in [ROADMAP.md](ROADMAP.md).

Bots also count cards that have appeared in completed tricks. They use category freshness as a small lead preference, while the **Public cards tracked** panel shows those same public counts for clubs, diamonds, hearts, spades, and jokers.

Expand that panel to see exact printed-rank counts. A count changes only after a completed trick, so it never reveals a player's unplayed hand or buried cards.

When a player fails to follow the led category, the tracker records a known void for that seat. Bots use this public information to avoid risky attacker leads and to pressure likely-void categories when defending.

## Run locally

Requires Node.js 24 and npm. Use `nvm use` if you manage Node with nvm.

```sh
npm ci
npm run dev
```

Open **http://127.0.0.1:3000**. The frontend proxies `/api` to the backend at `127.0.0.1:4000`. No database, account, or external credentials are required for this milestone.

### Play against bots

1. Click **Play against bots** in the header, choose the table size, and click **Start bot match**.
2. Declare if you can overturn the current declaration. After the countdown, click **Finalize trump**.
3. If you are dealer, select the required cards and click **Bury selected cards**.
4. Select cards and click **Play cards**. **Suggest cards** selects a legal response for you to review.
5. Use **Next trick** to continue, then **Start next round** after settlement. The first team to reach A wins.

You are seat 1 on team A; all remaining seats are bots. Choose **Bot difficulty** before starting: Relaxed avoids aggressive attacker gambles, Standard uses the normal strategy, and Sharp looks for validated gambles. Choose **Bot pace** to reveal turns at your preferred speed, pause them, or show the remaining plays immediately. **Trick history** retains the most recent 100 tricks; **Round history** retains the most recent 20 round results.

**Resume bot match** restores your saved match after a browser refresh or server restart. Matches expire after 30 days of inactivity. The browser remembers the match ID; use the same browser profile to resume.

### Saved matches

The server saves accepted commands before responding. By default, solo snapshots live in `data/matches` relative to the backend's working directory (`backend/data/matches` with `npm run dev`), while multiplayer rooms use the sibling `data/matches/rooms` directory. Set `BOT_MATCH_DIR` to an absolute path to choose another location, or `:memory:` for disposable sessions. Save files contain all private hands and must remain server-side. They are excluded from Git and container builds. A single backend instance must own each solo save directory. Multiplayer rooms can instead use shared PostgreSQL storage, as described below.

Docker Compose uses the `bot-matches` volume, which survives container replacement. Back up the save directory or volume to retain matches elsewhere; deleting the volume deletes its saves. The file store supports one backend process per directory. Invalid saves cause a clear startup failure rather than being silently overwritten. This is snapshot recovery, not a complete event replay system.

Trump cards are marked in your hand. Selection feedback explains follow obligations and whether a legal selection can compete for the trick; it does not predict unseen cards. The table shows captured points, penalty adjustments, current trick points, and the current winner. Failed-gamble explanations remain visible after the bots finish responding.

| Command              | Purpose                                                                       |
| -------------------- | ----------------------------------------------------------------------------- |
| `npm run dev`        | Start frontend and backend with file watching.                                |
| `npm run check`      | Format check, lint, typecheck, unit/API tests, and production builds.         |
| `npm test`           | Run rules and API tests with Vitest.                                          |
| `npm run test:watch` | Watch unit/API tests during development.                                      |
| `npm run test:e2e`   | Run desktop/mobile browser tests; starts its own servers on ports 3000/4000.  |
| `npm run build`      | Build both applications.                                                      |
| `npm start`          | Run the built backend; use nginx/container setup to serve the frontend build. |
| `npm run format`     | Format source and docs; preserves the existing `AGENTS.md`.                   |

Install the browser once with `npx playwright install chromium`. Alternatively, use `PLAYWRIGHT_CHANNEL=chrome npm run test:e2e` with locally installed Chrome. Stop development servers before browser tests so their ports are available.

To test alongside running dev servers: `E2E_WEB_PORT=3100 E2E_API_PORT=4100 PLAYWRIGHT_CHANNEL=chrome npm run test:e2e`.

## Repository layout

- `packages/rules/src/`: physical cards, effective hierarchy, homogeneous structures, dealing, declarations, round lifecycle, scoring, and dealer rotation. No networking, system clock, or hidden randomness.
- `packages/protocol/src/`: strict request/response schemas shared by both applications.
- `backend/src/`: Fastify API, secure shuffle choices, and private player-view projection.
- `backend/src/exercises.ts` and `backend/src/practice-routes.ts`: fixed trick positions and server-judged drill commands.
- `frontend/src/`: React practice table and responsive card UI. Card faces use CSS and text; no external assets or fonts are fetched.
- `tests/browser/`: Playwright desktop/mobile journeys.
- `infrastructure/`: container builds, nginx proxy, local Compose services.
- `docs/`: rule decisions, architecture, and verification notes.

Colocate rules/API tests as `*.test.ts`; browser tests use `*.spec.ts`. Use strict TypeScript, two-space indentation, Prettier, and ESLint. Seats are zero-indexed **counterclockwise**; even seats are team A, odd seats team B.

## API and configuration

- `GET /api/health`: process health, rules version, and multiplayer persistence mode (`memory`, `file-single-instance`, or `postgres`).
- `POST /api/bot-matches`: `{ "playerCount": 4 }`; creates a solo match.
- `GET /api/bot-matches/:id`: returns the human hand, public table, legal declaration options, and suggested cards.
- `GET /api/bot-matches/:id/replay`: downloads the match's replay metadata and accepted player/bot events as a JSON archive.
- `POST /api/bot-matches/:id/commands`: `{ "action": "play", "cardIds": ["..."], "revision": 3 }`; actions are `declare`, `bury`, `play`, `advance`, and `next-round`. Stale revisions return 409; rejected moves preserve state.
- `POST /api/rooms`: `{ "playerCount": 4, "displayName": "Host" }`; creates a private six-character invite room and returns a player token.
- `POST /api/rooms/:code/join`: `{ "displayName": "Player" }`; assigns the next available seat and returns that player's token.
- `GET /api/rooms/:code?token=...`: returns the authorized lobby view.
- `POST /api/rooms/:code/ready`: `{ "token": "...", "ready": true }`; updates the caller's ready state. The room starts when every seat is occupied and ready.
- `GET /api/rooms/:code/events?token=...&after=1`: returns room changes after a revision and the caller's current lobby view. The web client polls this endpoint to reconnect to a lobby.
- `GET /api/rooms/:code/game?token=...`: returns the authorized player's hand and public game state after the room is ready.
- `POST /api/rooms/:code/game/commands`: `{ "action": "play", "token": "...", "cardIds": ["..."], "revision": 1 }`; validates declaration, timer, kitty, and trick commands per player. The home page includes the create/join lobby and private hand controls.
- `GET /api/config`: supported table sizes, thresholds, and implemented capabilities.

For the supported single-instance deployment, run `./infrastructure/deploy.sh`. It validates Compose, rebuilds both images, starts the stack, and prints service health. The script requires Docker Compose and a persistent Docker volume for `BOT_MATCH_DIR`.
The backend places an owner lock in the room save directory and refuses a second process on the same volume; use one owner per file save directory. PostgreSQL room mode does not acquire the room file lock; solo save directories must still remain separate per backend instance.

- `POST /api/practice-preview`: `{ "playerCount": 4, "level": "2", "trumpSuit": "spades" }`. Use `null` for no-suit trump. Returns seat 0's hand, public seat counts, and kitty count; never other hands or buried cards. Preview IDs are informational, not resumable sessions.
- `GET /api/practice-tricks`: list fixed rule drills.
- `GET /api/practice-tricks/:id`: return one drill's authorized view.
- `POST /api/practice-tricks/:id/attempt`: `{ "cardIds": ["..."] }`; validates the selection with the pure rules engine and returns a revised view or a stable error.
- `POST /api/practice-rounds`: `{ "playerCount": 4, "attackingTeam": "A" }`; creates an in-memory round with a declaration window.
- `GET /api/practice-rounds/:id`: returns the round phase, public counts, your hand, and legal declaration options.
- `POST /api/practice-rounds/:id/declaration`: submits one of seat 0's legal level-card declarations.
- `POST /api/practice-rounds/:id/advance`: advances a timer-expired declaration window or finalizes the declaration into kitty phase.
- `POST /api/practice-rounds/:id/kitty`: `{ "buriedIds": ["..."] }`; exchanges the exact kitty size and starts the first trick with the scheduled dealer leading.

Practice rounds are intentionally in-memory and expire when the backend restarts. They are a development harness for the pure state machine, not persistent multiplayer sessions.

`PORT` and `HOST` configure the backend (defaults `4000`, `127.0.0.1`). `API_TARGET` configures Vite's backend proxy. Set these in the shell; the backend does not load `.env` files automatically. Never put secrets in frontend configuration.

## Containers

```sh
docker compose -f infrastructure/compose.yaml up --build -d
```

Open **http://127.0.0.1:8080**. The backend is reachable only through the frontend proxy. Stop with `docker compose -f infrastructure/compose.yaml down`.

PostgreSQL is optional and excluded from the default stack. Production hosting, TLS, secrets, backups, and deployments are not provisioned yet.

## Shared multiplayer storage

Start the local database, then select it when running the application:

```sh
docker compose -f infrastructure/compose.yaml --profile persistence up -d postgres
DATABASE_URL=postgres://tractor:tractor-local-only@127.0.0.1:5432/tractor npm run dev
```

Wait for PostgreSQL to become healthy before starting the app. The password above is only for local development. The backend creates the room tables at startup and serializes schema initialization across instances. The database user must be able to create tables. Without `DATABASE_URL`, the existing file or memory mode applies. `/api/health` and `/api/config` report the selected multiplayer persistence mode.

For the container backend, use the Compose service hostname:

```sh
DATABASE_URL=postgres://tractor:tractor-local-only@postgres:5432/tractor docker compose -f infrastructure/compose.yaml --profile persistence up --build -d
```

Each room mutation locks the latest database row before authorization and validation, then commits the new snapshot and a private event atomically. Stale game revisions return 409. The browser automatically restores its room token after refresh and polls the latest player-specific view. Invite codes are reserved atomically; rooms expire 24 hours after creation, and expired database rows/events are removed when another room is created.

Multiple backend instances can share **multiplayer rooms** through this database. Solo matches remain local to each backend's file directory; do not share solo save directories or treat this as a complete load-balanced solo deployment. Existing JSON rooms are not automatically imported into PostgreSQL. The event log records accepted actions, but is not yet a complete deterministic replay log. Database tables contain private hands and session tokens and are never exposed directly to browsers.

## Match data backups

For file-backed solo matches and single-instance rooms, create a compressed backup before upgrades or maintenance:

```sh
npm run backup:data -- data/matches /secure/backups/tractor-20260916.tar.gz
npm run validate:backup -- /secure/backups/tractor-20260916.tar.gz
```

The backup script archives the selected directory without deleting or modifying its source. Keep backups in a protected location because snapshots contain private hands and session tokens. PostgreSQL deployments should use database-native backups and point-in-time recovery; the script does not dump PostgreSQL.

Run the real database tests against a local test database:

```sh
TEST_DATABASE_URL=postgres://tractor:tractor-local-only@127.0.0.1:5432/tractor npm run test:postgres
```

The tests create and remove isolated schemas; the test user needs schema creation permissions. `npm test` skips these tests unless `TEST_DATABASE_URL` is set. CI runs them with a PostgreSQL service.

## Offline bot self-play training

For the newer contextual learner, use `train:policy` below. `train:bots` remains the older coefficient-search experiment; its checkpoints and training runs are independent.

Run a small local experiment without starting the website:

```sh
npm run train:bots -- --generations 3 --train-seeds 2 --validation-seeds 4 --seed 42
```

This performs evolutionary search over `BotLeadWeights`: mutate a few coefficients, play full matches against the current best policy, then analyse the completed games before validation. All seats are automated. A match runs through level progression to an actual winner. The candidate plays both teams on each seeded deal, and each round has an independent seeded shuffle. Choose table sizes with `--players 4,6,8,10` (default: 4).

Feedback comes from match wins and losses, with no human labels. Candidates must win more than half their training matches against the incumbent. Those that qualify play the default baseline on fresh validation seeds; the incumbent plays that baseline on the same seeds. Promotion requires the candidate to beat both 50% and the incumbent's validation win rate. Capped matches block promotion; `--max-rounds` defaults to 60. This is an experimental screening rule, not statistical proof of stronger play. Use substantially more seeds and multiple table sizes before judging playing strength.

After each training set, the post-game scorer groups the candidate's leads by completed match result. It compares the average public-state features used in wins and losses: structure, trump, freshness, joker preservation, known opponent/partner voids, and endgame strength or points. When it has at least 12 finished matches with both wins and losses, it makes a bounded adjustment to the proposed weights. These correlations are only hypotheses from the training deals; they are tested on the held-out deals and discarded if validation fails. A capped match contributes no score.

Every generation saves an atomic `checkpoint.json` under a new, ignored `data/bot-training/run-*` directory. The command prints the path. `games.jsonl` contains complete match outcomes and round settlements; the checkpoint records candidate weights, acceptance decisions, rules/policy versions, and configuration. Resume from that file to retain learned weights and continue the deterministic sequence:

```sh
npm run train:bots -- --resume data/bot-training/run-XXXXXX/checkpoint.json --generations 10
```

Replace `run-XXXXXX` with the printed run directory. Resume writes a new output directory and uses the checkpoint's configuration; omit seed, player-count, and sampling flags. `--out DIRECTORY` selects a new directory explicitly and refuses to overwrite an existing one. Interrupting a run preserves the last completed generation; unfinished generations restart deterministically on resume.

Add `--trace` to export `decisions.jsonl`. Each decision contains that player's own hand, chosen cards, trump, score, and public trick/history information. Join decisions to `match_result` records using generation, phase, playerCount, seed, and candidateTeam. Completed matches assign +1 to the winning team and -1 to the losing team; capped matches have null rewards. Trace files can become large and stay in local developer output; they are not served through the website. Spreadsheet telemetry labels such as “necessary ruff” are not training rewards.

This first trainer tunes lead selection only. Declaration, burial, and following policies remain fixed. The trainer never passes opponents' hands into strategy decisions and does not use Sharp's hidden-hand gamble validation. It is a separate offline policy, not an exact reproduction of the live Standard/Sharp modes. Saved weights can be passed to `chooseBotLead` through `BotLeadContext.weights`; the website does not yet load checkpoints or update itself from watched games. No model API, GPU, or additional dependencies are required. `npm run train:bots -- --help` lists all options.

## Learning a contextual move policy

The trainer uses completed round rewards, clipped probability-ratio updates, Adam, and an empirical KL limit. Rewards do not carry into earlier rounds. Counterfactuals compare actions across four feasible hidden deals with the same frozen learned-policy continuation in every branch. Samples respect known voids (including the current trick), exposed declaration ownership, remaining hand sizes, and the dealer's known kitty. Contradictory observations produce no comparison targets, and a sampled comparison is applied only when the observed round outcome agrees with its direction; neutral or conflicting pairs are discarded. Feasible sampling is not a uniform posterior over deals. The comparison objective has a separate coefficient of 0.1; use `--counterfactual-weight 0` to disable it for a controlled comparison, or a value from 0 to 1 to set it. Selected experiences occur only once in the update. The baseline prior stays fixed, so saved models match the evaluated policy except for an explicitly reported rollback. One quarter of practice seeds face the handcrafted baseline, with the remainder facing available champion/archive policies (or baseline if none exist).

The opponent pool is the main thing standing between self-play and a policy that has merely learned its own relatives' habits. Promotion archives past champions and keeps up to eight of them, retaining the oldest alongside every recent one so the pool spans the run instead of one recent stretch; a policy-version migration retires the champion but no longer discards these sparring partners. Promotion also has to beat live Sharp, which practice never plays, so that gate cannot be passed by learning the pool. Sharp uses its own validated-throw information, exactly as a player meets it, so a candidate that only beats its own lineage will fail there. `--sharp-gate off` keeps measuring that comparison while letting promotions through without it, for runs where the bar stops everything.

Sharp live play still has its public-belief search. Offline training no longer changes its lead preference using a search teacher only during practice, which previously made practice and evaluation inconsistent.

Start a fresh run when comparing training methods. Resuming v4 through v8 preserves learner weights but resets optimizer state, clears champion eligibility and the incomplete old opponent archive, and requires fresh validation. Original checkpoint files remain intact. Earlier evaluation scores are not directly comparable: the old opponent path incorrectly used its lead network for following and omitted its learned declaration/burial policy. The trainer reports counterfactual positions, rollouts, informative pairs, and how many evaluated choices differ from the handcrafted baseline.

```sh
npm run train:policy -- --generations 10 --train-seeds 32 --validation-seeds 128 --players 4 --seed 42
```

This separate trainer learns a small neural scorer (22 observation/action features, 16 hidden units) with outcome-driven policy-gradient updates. It enumerates every single-category structure offered by the rules engine: singles, repeated sets, and tractors, including smaller structures cut from larger ones. It also explores legal single-card follows. Features describe the player's own hand, public history, team role, score, candidate cards, and what the candidate leaves in hand. Other players' hands are never inputs. Nonlinear combinations let it learn different preferences in different situations. The existing bot's chosen move supplies an initial preference, which the learned score can overcome.

Lead and follow choices have separate networks and separate gradients. The learner can explore after an inconclusive generation, while the validated champion remains unchanged. It rolls back to the champion only after at least 64 paired comparisons pooled against that same champion have a 95% level-margin interval wholly below −0.5 levels; both Adam optimizers reset with it. A regression that clears zero by a hair describes a learner that is indistinguishable in practice, not one that has gone wrong. A reset then starts a four-generation cooldown during which no further rollback fires, and the same evidence can no longer reset the learner twice in one generation. Improving on a champion means being allowed to be slightly worse on the way, and a reset also clears the step sizes the learner needs to recover; without the cooldown, evidence rebuilds in two generations and the learner is thrown back before it can. The checkpoint stores this evidence and the remaining cooldown across resumes. A lack of promotion alone does not trigger rollback.

During practice, legal actions are sampled and recorded with their sampling temperature. Completed rounds give feedback for level progress, match victory, and a small bounded score term. Discounted future round rewards reach earlier decisions; round returns are centered before training. Completed rounds from capped matches remain useful, but a capped match never qualifies a champion. Four update epochs reuse the current batch with clipped importance ratios; a KL limit shrinks overly large steps. Optimizer moments are checkpointed for deterministic continuation.

Each generation logs sampled decisions, choices differing from the baseline, completed training rounds, accepted update epochs, policy divergence, and the mean/p90 learned-logit spread beside the effective baseline prior. It also logs wall-clock seconds and match counts for practice, the learning updates, each evaluation phase, and the generation as a whole; how often temperature sampling moved practice off the greedy action, with the mean probability the sampling distribution itself put on the chosen and on the greedy action; and two separate counters: generations since the last promotion, and generations since the last promotion or learner rollback. Validation pairs the two games sharing each seed, averages candidate-normalized per-round point margin and match level margin, and bootstraps 95% intervals for both. A baseline-identical policy has margin exactly zero and is reported as indistinguishable. Promotion requires a level-margin interval lower bound above zero and a point-margin lower bound of at least −0.01 against baseline, champion, held-out live Sharp, and a rotating archived policy; each evaluation also needs at least 64 games, at least 95% of expected pairs, and no more than 2% truncated games. It must then clear the same gate again on separate fresh confirmation seeds. A failed baseline or champion gate skips the Sharp and archive evaluations, and a failed Sharp gate skips the archive, since those gates could only refuse a promotion already refused; a generation that fails early pays nothing for them. Promotion stores the models exactly as they were evaluated: the recalibrated baseline prior changes action selection, so it reaches only the next generation's learner, never the champion being saved. The default validation set is 128 paired seeds; resumed runs raise older smaller configurations to at least 128 unless explicitly overridden. Practice defaults to 32 paired training seeds, because the learner only learns from practice and a thin generation makes every update a high-variance guess; a resume may raise `--train-seeds` or widen `--players` mid-run, which broadens what the learner sees without disturbing the disjoint evaluation seeds. A warning appears when practice becomes nearly deterministic — over 95% mean probability on the chosen action with under 5% disagreement from greedy — because self-play results then describe one narrow policy rather than a strategy. These are screening gates, not proof of human-level strength; the scores measure the entire learned offline policy, and live loading below uses the same complete policy.

Outputs go to an ignored `data/policy-training/run-*` directory. `checkpoint.json` stores the practicing learner, validated champion (initially null), opponent archive, configuration, and reports. `games.jsonl` records practice and validation results. Resume from the printed path:

```sh
npm run train:policy -- --resume data/policy-training/run-XXXXXX/checkpoint.json --generations 10
```

Compare the saved learner and champion against the baseline on fresh paired deals, and summarize saved validation history:

```sh
npm run evaluate:policy -- --checkpoint data/policy-training/run-XXXXXX/checkpoint.json --seeds 128
```

The fresh results are the candidate-specific comparison. By default, history is read from that checkpoint's own run. You can pass `--history DIR_OR_FILE` to inspect a wider set; rows from older policy versions are excluded, and matching-version history is grouped by run and generation with a pooled descriptive interval. The pooled interval mixes generations and should not be treated as a promotion test.

Revalidate a saved learner without running another training generation, and promote it only if it clears the normal screening and independent confirmation gates:

```sh
npm run evaluate:policy -- --checkpoint data/policy-training/run-XXXXXX/checkpoint.json --promote --seeds 128
```

The command leaves the checkpoint untouched if either stage fails. If both pass, it atomically updates the checkpoint's champion and records the revalidation results in the latest generation report.

Resume uses the saved configuration and writes a new directory. The checkpoint distinguishes this policy from older weight-search models and validates model versions, dimensions, and finite coefficient bounds. `train:bots` checkpoints cannot be resumed by `train:policy`; old training output is retained.

To play against a validated champion locally, restart the development server with the checkpoint selected:

```sh
BOT_POLICY_FILE="$PWD/data/policy-training/run-XXXXXX/checkpoint.json" npm run dev
```

If no champion has qualified yet, explicitly opt into trying the experimental learner:

```sh
BOT_POLICY_FILE="$PWD/data/policy-training/run-XXXXXX/checkpoint.json" BOT_POLICY_USE_LEARNER=1 npm run dev
```

The model is loaded and validated once at server startup. It controls leads, following, declarations, and burial for solo bots, plus play and burial suggestions used by watch mode; the existing difficulty setting does not override the loaded policy. Multiplayer is unchanged. Remove these environment variables and restart to restore ordinary solo behavior. Checkpoint selection is server-side and adds no controls or information to the game table.

This learner can discover new choices and combinations within generated leads, single-card follows, declarations, and burial alternatives. Multi-component gambles, multi-card follows, long-term memory, and search over future plays are not implemented here. Offline evaluation and live model loading use the same adapter for these learned round decisions. Stronger play must be measured on more seeds and against people; simply running longer does not guarantee improvement. No external model service or extra dependencies are required.

### Compare the deployed policy against Sharp

The server loads a complete policy when `BOT_POLICY_FILE` is set: leads, following, trump declarations, and burial. It loads the saved champion by default; `BOT_POLICY_USE_LEARNER=1` selects the experimental learner. This policy overrides the built-in difficulty decision logic for bot seats. Without a checkpoint, the existing difficulty modes remain available. Restart the server to load a different checkpoint.

Live play and offline evaluation share the learned adapter, including disabling Sharp belief-search changes to the learned baseline preference. Sharp comparisons use its actual opening-lead rule and existing server-side hidden-hand throw validation; the learned adapter ignores those hidden hands.

```sh
npm run compare:live -- --checkpoint data/policy-training/run-PtEwtC/checkpoint.json --seeds 32
```

This read-only command plays both team assignments for each seed against Sharp, using the checkpoint's player counts and round cap. It neither trains nor promotes and writes no run directory. `--learner` selects the learner; `--seed-start` sets a separate evaluation seed range (default 3000000000). A small run checks the pipeline; use more paired seeds and a separate final seed range before concluding that the policy is stronger. This is a bot-team comparison, not a measurement of human playing experience. Previous offline baseline results are not results against Sharp, and old champion promotion scores may describe the prior-mismatch model rather than the stored one.

### Human playtests

Start the server with `BOT_POLICY_FILE` pointing to the frozen champion checkpoint above, then select **Human playtest** before starting a bot match. This mode uses four seats: you and a fixed Standard partner against either Sharp or the champion. Suggestions and watch-mode autoplay are disabled. The opponent label, replay export, and both bot-behavior CSV exports unlock after the full match ends, not after an individual round.

Choose **Next playtest** after completion to alternate opponents. After a champion match, review up to 128 sampled policy choices and teach a preferred legal action for decisions you would change. Each correction updates a separate adaptive policy that carries into later champion-assigned matches in the same series; Sharp matches do not update it. The saved champion checkpoint remains unchanged. This is supervised learning from your corrections, not automatic learning from every observed move or match result. The first assignment is random; models and assignment are stored with the private solo session, survive restart, and persist across rounds. Resuming or continuing a saved playtest does not require the current server's checkpoint to match. Starting a fresh series requires a champion (experimental learner loading does not qualify). Ordinary **New bot match** starts ordinary play and does not continue the series.

Export the completed replay to retain opponent identity, champion fingerprint, previous playtest ID, winner, and game events. The adaptive policy remains in the playtest series save; it does not automatically replace the server checkpoint and is removed when the session expires. Keep notes about experience level and suspected mistakes alongside these exports. Assignment labels are hidden during play, but alternation after a revealed result can be inferred; this is an informal comparison, not a rigorously blinded study. Session saves still expire after 30 days of inactivity. Abandoned matches are not completed results, and single-process solo persistence limitations still apply.

### Learn from recorded matches

Point-margin scoring version 2 uses the attacking team for the round just completed, undoing the settlement's role swap. Older point-margin reports used the next round's attackers and could reverse credit. Their point statistics must be recomputed from game records; win counts and level margins are unaffected. Loading an older checkpoint discards its cached point samples, and training resume rebuilds them from adjacent game logs when available.

```sh
npm run learn:matches -- --checkpoint data/policy-training/run-4p2W8U/checkpoint.json
```

This scans every solo save in `backend/data/matches` (override with `--matches DIRECTORY`), including completed rounds inside unfinished matches. It reconstructs each complete round and checks card ownership, move legality, trick results, and final settlement against the saved record. For each usable lead/follow decision, the existing counterfactual simulator compares up to three legal alternatives through the end of the round with identical continuation policies. Informative comparisons train a new experimental learner. No manual labels are required, and a lost match does not label every move as wrong.

The command writes `data/policy-training/human-learning-*/checkpoint.json` and a `review.json` with coverage, exclusions, rollout counts, and update statistics. Pass that new checkpoint to the next `learn:matches` run; recorded round hashes prevent training on the same round twice, including copied saves. Learning is an explicit batch command, not a background process. The server does not automatically switch to this candidate. Evaluate with `compare:live -- --checkpoint FILE --learner` and use the normal evaluation/promotion workflow before changing the champion.

New saves retain all completed tricks, round results, and action events. Old saves may already have discarded earlier rounds; those cannot be recovered. Partial rounds, incompatible records, and rounds with unavailable failed-throw context are skipped with reasons. This workflow currently covers solo saves, not multiplayer room storage, and trains lead/follow choices rather than declaration or burial decisions. Hidden hands are used only by the offline simulator; policy features remain limited to the acting hand and public information. These are simulator-derived labels, not proof of improved strength against humans.

Tactical policy v11 uses 30 inputs, including separate dealer/opening context,
side-suit ace and suit-exhaustion indicators, public trick points, opponents still
to act, and legal overtaking. Follow candidates include complete pairs and tractors
as well as single cards. Old 22-input checkpoints are explicitly zero-extended;
their saved champion validation and replay deduplication cache are retired during
migration. The source file stays untouched. Run `learn:matches` to generate an
experimental learner and evaluate on fresh paired deals before promoting it.
These signals express opportunities, not guarantees that an ace or an overtake wins.
Live loading of a saved v10 champion preserves its original inference path while
experimental training migration happens separately. An unsuccessful experiment
therefore does not require switching the website to the new learner.

For a faster human comparison, select **One-round quick match** when creating a bot game. It chooses a starting level randomly from 2 through A, uses the normal level declaration rules, and ends after that round settles.

Policy selection uses level performance as the primary objective. Rollback requires at least 64 paired level samples whose 95% interval upper bound is below −0.5 levels; point-only regressions do not reset the learner. The existing four-generation cooldown remains. New `championLevelMarginSamples` are saved separately from legacy point samples and reset on promotion, rollback, feature migration, or human-learning updates. Old checkpoints start with no level rollback evidence. Round wins in evaluation output are descriptive counts within full matches, not an independent random-level quick-match benchmark. Choose unused screening and confirmation seeds before evaluating under the revised gate; historic reports are not fresh validation.
