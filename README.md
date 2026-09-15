# Tractor · 升级 / 拖拉机

A partnership card game for 4, 6, 8, or 10 players, built around the supplied version 2.1 rules and [confirmed clarifications](docs/rules-decisions.md).

## Current milestone

The foundation includes a browser practice table, a stateless practice-deal API, guided trick drills, and a pure TypeScript rules package. You can deal sample hands, change player count/level/trump, inspect homogeneous structures, explore scoring thresholds, and submit card selections to server-validated follow/gamble positions.

**This is not yet a playable multiplayer game.** Timed declaration, kitty exchange, complete follow/gamble decomposition, multi-trick state, full round settlement, rooms, and persistence are subsequent milestones in [ROADMAP.md](ROADMAP.md). The practice table lets you choose trump directly for exploration; it does not bypass declarations in a live match. Rule drills are fixed teaching positions, not multiplayer rooms.

## Run locally

Requires Node.js 24 and npm. Use `nvm use` if you manage Node with nvm.

```sh
npm ci
npm run dev
```

Open **http://127.0.0.1:3000**. The frontend proxies `/api` to the backend at `127.0.0.1:4000`. No database, account, or external credentials are required for this milestone.

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

## Repository layout

- `packages/rules/src/`: physical cards, effective hierarchy, homogeneous structures, dealing, scoring, and dealer rotation. No networking, system clock, or hidden randomness.
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
- `GET /api/config`: supported table sizes, thresholds, and implemented capabilities.
- `POST /api/practice-preview`: `{ "playerCount": 4, "level": "2", "trumpSuit": "spades" }`. Use `null` for no-suit trump. Returns seat 0's hand, public seat counts, and kitty count; never other hands or buried cards. Preview IDs are informational, not resumable sessions.
- `GET /api/practice-tricks`: list fixed rule drills.
- `GET /api/practice-tricks/:id`: return one drill's authorized view.
- `POST /api/practice-tricks/:id/attempt`: `{ "cardIds": ["..."] }`; validates the selection with the pure rules engine and returns a revised view or a stable error.

`PORT` and `HOST` configure the backend (defaults `4000`, `127.0.0.1`). `API_TARGET` configures Vite's backend proxy. Set these in the shell; the backend does not load `.env` files automatically. Never put secrets in frontend configuration.

## Containers

```sh
docker compose -f infrastructure/compose.yaml up --build -d
```

Open **http://127.0.0.1:8080**. The backend is reachable only through the frontend proxy. Stop with `docker compose -f infrastructure/compose.yaml down`.

PostgreSQL is reserved for the persistence milestone and excluded from the default stack. Start it separately with `docker compose -f infrastructure/compose.yaml --profile persistence up -d postgres`. Its default password is for local development only; the practice API does not connect to it. Production hosting, TLS, secrets, backups, and deployments are not provisioned yet.
