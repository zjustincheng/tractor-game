# Repository Guidelines

## Project structure

This is a TypeScript npm workspace for Tractor (升级 / 拖拉机). `frontend/` contains the React/Vite browser app, `backend/` the Fastify API and persistence, `packages/rules/` pure game logic, and `packages/protocol/` shared validated schemas. Browser tests live in `tests/browser/`; rules and API tests are colocated as `*.test.ts`. Deployment files and SQL live in `infrastructure/`, supporting scripts in `scripts/`, and rule decisions and architecture notes in `docs/`.

Keep network, database, clock, and random-number access outside the pure rules package. The server validates moves and projects only the requesting player's hand and permitted public state. Changes to game rules must follow `docs/rules-decisions.md` and the supplied specification.

## Commands

Use Node.js 24 and `npm ci`. Run `npm run dev` for local development, `npm run check` for formatting, lint, typecheck, unit/API tests, and builds, and `npm run test:e2e` for browser tests. Install Chromium with `npx playwright install chromium`, or use `PLAYWRIGHT_CHANNEL=chrome` for local Chrome. Override `E2E_WEB_PORT` and `E2E_API_PORT` when development servers occupy default ports.

`TEST_DATABASE_URL=... npm run test:postgres` verifies PostgreSQL storage using isolated temporary schemas in a test database. PostgreSQL is optional for normal local play. See `README.md` for exact setup and configuration.

## Style and testing

Use strict TypeScript, descriptive names, two-space indentation, Prettier, and ESLint. Keep modules focused and avoid unrelated refactoring. Run `npm run format` after edits; `AGENTS.md` is intentionally excluded from formatting. Commit the dependency lockfile when changing dependencies.

Favor deterministic rule and state-transition tests. Persistence changes must cover concurrent mutations, rejected commands, rollback, and recovery. Visual or interactive changes need relevant browser coverage and recorded verification. Document coverage boundaries in `docs/testing.md`.

## Commits and pull requests

Use concise imperative subjects and focused commits. Explain the problem and resulting behavior, list verification, and link issues when relevant. Include screenshots for visible changes and state setup changes or known limitations.

## Security and configuration

Never commit secrets, credentials, generated output, dependencies, or saved hands. Room tokens and private database events stay server-side except for the requesting player's session token. PostgreSQL shares multiplayer rooms only; solo snapshots still require a single process per save directory. Production hosting, TLS, backups, and paid provisioning require separate scope.
