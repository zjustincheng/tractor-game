# Tractor · 升级 / 拖拉机

A partnership card game for 4, 6, 8, or 10 players, built around the supplied version 2.1 rules and [confirmed clarifications](docs/rules-decisions.md).

## Current milestone

You can play a complete solo match against bots with 4, 6, 8, or 10 seats: declare trump, exchange the kitty, play tricks, settle each round, and advance through the J checkpoint to A. The backend validates every play. A sample-hand explorer and guided trick drills are also available.

Bots use deterministic strategies with their own hands and public trick information: choose supported declarations, conserve strength behind winning partners, feed points when last to play, choose cheap winning responses against opponents, adjust leads based on attacker/defender role and threshold pressure, and make attacker gambles only after server-side validation. They lead homogeneous structures and follow the existing structure/gamble rules; humans may attempt gambles. Solo matches show a counterclockwise per-card dealing phase before the eight-second declaration window. Human multiplayer and deployment remain in [ROADMAP.md](ROADMAP.md).

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

You are seat 1 on team A; all remaining seats are bots. Choose **Bot pace** to reveal turns at your preferred speed, pause them, or show the remaining plays immediately. **Trick history** retains the most recent 100 tricks; **Round history** retains the most recent 20 round results.

**Resume bot match** restores your saved match after a browser refresh or server restart. Matches expire after 30 days of inactivity. The browser remembers the match ID; use the same browser profile to resume.

### Saved matches

The server saves accepted commands before responding. By default, snapshots live in `data/matches` relative to the backend's working directory (`backend/data/matches` with `npm run dev`). Set `BOT_MATCH_DIR` to an absolute path to choose another location, or `:memory:` for disposable sessions. Save files contain all private hands and must remain server-side. They are excluded from Git and container builds.

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

- `GET /api/health`: process health and rules version.
- `POST /api/bot-matches`: `{ "playerCount": 4 }`; creates a solo match.
- `GET /api/bot-matches/:id`: returns the human hand, public table, legal declaration options, and suggested cards.
- `POST /api/bot-matches/:id/commands`: `{ "action": "play", "cardIds": ["..."], "revision": 3 }`; actions are `declare`, `bury`, `play`, `advance`, and `next-round`. Stale revisions return 409; rejected moves preserve state.
- `GET /api/config`: supported table sizes, thresholds, and implemented capabilities.
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

PostgreSQL is reserved for the persistence milestone and excluded from the default stack. Start it separately with `docker compose -f infrastructure/compose.yaml --profile persistence up -d postgres`. Its default password is for local development only; the practice API does not connect to it. Production hosting, TLS, secrets, backups, and deployments are not provisioned yet.
