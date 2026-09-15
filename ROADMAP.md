# Tractor Implementation Roadmap

## Goal and Scope

Build a browser-based, server-authoritative multiplayer implementation of Tractor (升级 / 拖拉机), based on the supplied version 2.1 specification. Support private matches with 4, 6, 8, and 10 human players, alternating teams, full declaration and gamble rules, persistent matches, and reconnecting players.

The repository includes playable solo bot matches, a React practice table, a Fastify API, shared TypeScript rules and schemas, automated tests, and local container configuration. Basic bots were added as a playable testing milestone. Human multiplayer, matchmaking, spectators, chat, and alternative rules remain future work.

### Implementation Progress

- [x] Workspace, strict TypeScript, formatting, linting, and CI configuration.
- [x] Decks, points, effective hierarchy, homogeneous recognition/comparison, pure dealing, dealer rotation, and scoring/level advancement.
- [x] Shared validated preview schemas and private viewer-hand projection.
- [x] Declaration eligibility, multiplicity overturning, joker declaration counts, and first-round joker takeover helpers.
- [x] Round declaration windows, deterministic fallback, scheduled-dealer kitty exchange, and transition into trick state.
- [x] Round settlement helper for defender points, kitty multipliers, advancement, role swaps, match victory, and Jack reset gating.
- [x] Development practice-round API for server-side declaration windows and legal declaration options.
- [x] Responsive practice table with 4/6/8/10-seat layouts, card selection, and score exploration.
- [x] Rules/API tests, guided trick drills, and desktop/mobile browser journeys.
- [x] Local frontend/backend containers and an optional PostgreSQL service for later persistence.
- [~] Authoritative match state machine, declaration/kitty transitions, injected timestamps, and replay-ready pure state helpers; command/event persistence remains.
- [x] Solo bot matches: declaration, kitty exchange, successive tricks, round settlement, dealer rotation, J checkpoint, and victory at A.
- [x] Browser match controls, legal-play suggestions, completed-trick review, and session resume.
- [x] Partner-aware tactical follows, point feeding when last to play, trump markers, selection validation, and visible score breakdowns.
- [x] Paced bot-play reveals with pause/skip controls, recent trick and round history, durable single-server snapshots, and Docker save volume.
- [ ] Stronger bot tactics, deliberate bot gambles, and timed dealing animation.
- [ ] Live rooms, reconnect, durable event/state persistence, and production deployment.

See [README.md](README.md) for commands and [docs/testing.md](docs/testing.md) for the exact coverage boundary. These checks represent foundation progress, not completion of the full game.

## 1. Resolve Rules Before Encoding Them

The specification establishes most gameplay, but several cases still need explicit decisions. The original is preserved in [docs/rules-v2.1.md](docs/rules-v2.1.md); confirmed clarifications are recorded in [docs/rules-decisions.md](docs/rules-decisions.md). Map each implemented rule to tests in [docs/testing.md](docs/testing.md). Do not silently substitute familiar Tractor variants.

Confirmed: strictly alternating teams; attacking-team declaration rank; scheduled dealer retains kitty pickup and first lead after the first round regardless of declaration winner; mandatory declaration; failed gambles adjust defender score by +20 for attackers and -20 for defenders, allowing negative scores; attackers advance +3 for final scores at or below zero; intervals are 20 points per deck and role swaps begin at two intervals; advancement continues above nominal totals; available pairs must be included when partially following a pair tractor.

| Decision                               | Why it matters                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Partial following                      | Available standalone pairs must be played, including two nonconsecutive pairs against a four-card pair tractor; against a gamble, match all components when possible, otherwise supply as many required sets as possible, preserve larger sets where other suited cards suffice, and exhaust the led category. Generalize priorities for multiple partial tractors and higher multiplicities.                                                                                        |
| Component decomposition and comparison | Automatically use the largest structures: card count, then multiplicity, then effective power, then stable physical IDs. The lead determines required shape. Later matching responses win if any component beats any structurally comparable previous component, without sorted correspondence. The `33344455♣` gamble fails against a club pair above `55♣`. Generalize overlapping equal-size candidates, gamble follow obligations, and ties between weakest beatable components. |
| Jack reset settlement                  | The whole winning play must contain only Jacks; a Jack component in a mixed-rank gamble does not qualify. Define settlement order relative to leveling and match victory.                                                                                                                                                                                                                                                                                                            |
| Timing and interrupted games           | Define deadline boundary ordering, simultaneous declarations, first dealt seat, reconnect grace, and abandoned-match handling. Do not invent automatic plays or forfeits.                                                                                                                                                                                                                                                                                                            |

**Exit criterion:** every decision has explicit examples and expected outcomes. Unaffected scaffolding and card modeling can proceed while these decisions are pending.

Additional confirmed rules: retained attackers rotate dealer to the next counterclockwise teammate; sets require identical printed rank and suit; triples are protected when other suited cards suffice; Jack reset requires a Jack-only homogeneous structure; card grouping uses largest card count, then multiplicity, then effective power, then stable physical IDs. In the first round, three big jokers beat three small jokers, but four small jokers require four big jokers; mixed three-joker declarations lock against overturning. Respect physical deck limits. If the initial eight-second post-deal window expires without a declaration, randomly choose a player holding a dealt level card, declare that card's suit, and allow another eight-second window for legal overturning. Record the choice for replay.

## 2. Architecture and Repository Layout

Use a TypeScript monorepo as the proposed baseline: a browser frontend, a Node.js backend, a pure rules package, and PostgreSQL persistence. Keep transport and database code outside the rules engine.

```text
frontend/              Lobby, table, hand interaction, round summaries
backend/               Sessions, rooms, commands, timers, persistence
packages/rules/        Cards, structures, legality, scoring, state transitions
packages/protocol/     Validated command and player-view schemas
tests/                 Integration, browser, replay, and load scenarios
assets/                Card faces, suit symbols, and licensed game artwork
infrastructure/        Containers, deployment configuration, operational docs
docs/                  Rule specification, decisions, architecture
```

Model the lifecycle explicitly:

`Lobby → Dealing → Declaration window → Kitty exchange → Tricks → Round settlement → Next round / Match finished`

Declarations are also accepted during dealing. Every transition runs on the server. Clients receive only their own hand and permitted public information. Model physical card IDs separately from rank, printed suit, effective category, and effective power.

## 3. Delivery Milestones

### Milestone 1 — Foundation and Executable Rules

**Backend**

- Implement deck generation, points, team seating, counterclockwise order, and effective hierarchies for suit and no-suit trump.
- Build pure state transitions with an injected clock and recorded shuffle input. Use secure server-side randomness for live deals; keep shuffle data private.
- Define commands, events, stable error codes, rule version, and player-specific state views.

**Frontend**

- Create the application shell, card rendering, selectable hand, and table layouts for all supported player counts using fixtures.
- Include keyboard selection, touch interaction, readable suit labels, and indicators that do not depend solely on color.

**Infrastructure**

- Establish dependency lockfiles, formatting, linting, type checks, and local database setup.
- Add CI checks and document repository scripts such as `dev`, `build`, `lint`, `typecheck`, and `test` once implemented.

**Exit criterion:** deck totals and effective-power examples pass for every player count, level, and trump mode; frontend builds from fixtures.

### Milestone 2 — Structure and Trick Engine

**Backend**

- Implement singles, identical sets, consecutive structures, canonical gamble decomposition, and exact structure comparisons.
- Validate follow obligations against the complete hand, including suit exhaustion, partial structures, and larger-set exceptions.
- Implement gamble validation against other players, including teammates, and breaking their sets when checking beatability. Apply the agreed failure penalty and return unplayed cards.
- Resolve trick winners, earlier-play ties, defender point capture, and equal remaining hand sizes. Compare matching gamble responses sequentially against the current winner; include the confirmed stronger-single/weaker-pair case in regression fixtures.

**Frontend**

- Show selected-card count, structure preview, current lead, whose turn it is, and server rejection explanations.
- Display failed gamble reduction and return cards visibly to the hand without revealing other players' holdings.

**Infrastructure**

- Run deterministic fixtures and generated invariant tests in CI. Benchmark structure search with the largest supported hands.

**Exit criterion:** all supplied hierarchy, follow, gamble, and comparison examples pass, including cases where mismatched trump cannot win.

### Milestone 3 — Complete Local Match

**Backend**

- Deal at one full seating rotation per second using absolute server deadlines; track exactly which cards each player has received.
- Implement declaration, reinforcement, overturning, joker lock and exception, eight-second reset window, and the confirmed random fallback using a dealt level card after the initial window expires.
- Implement private kitty pickup and exact-count burial; exclude kitty cards from declaration eligibility.
- Settle final-trick kitty points using the actual winning structure, then apply agreed penalties, thresholds, Jack reset, level checkpoints, victory, and dealer rotation in a documented order.

**Frontend**

- Add declaration controls and countdown, kitty exchange, team levels, defender score, and trick history.
- Explain round settlement with separate trick points, kitty base points, multiplier, penalty, level movement, and next dealer.

**Infrastructure**

- Add repeatable match fixtures and a development-only multi-seat harness. Ensure hidden-hand debug tools are excluded from production.

**Exit criterion:** automated complete matches reach a valid winner for 4, 6, 8, and 10 players, including forced rare scenarios.

### Milestone 4 — Online Multiplayer and Recovery

**Backend**

- Add resumable guest sessions, private room codes, seat assignment, ready state, and authenticated real-time commands.
- Serialize commands per match. Require request IDs and expected state revisions; reject stale actions and deduplicate retries.
- Persist accepted events and state revisions atomically before acknowledging them. Store snapshots and durable timer deadlines.
- Recover matches after restart and provide fresh authorized snapshots when event catch-up is unavailable.

**Frontend**

- Implement create/join room, lobby, ready controls, connection status, pending-action feedback, and reconnect flow.
- Reconcile with server state after every reconnect; animations must never determine legality or timing.

**Infrastructure**

- Deploy a staging frontend, persistent backend service with real-time connection support, and managed database.
- Add schema migrations, TLS, secret injection, backups, health checks, structured logs, and restricted database access.

**Exit criterion:** separate browsers complete matches; duplicate packets, stale commands, disconnections, and backend restarts cause no double plays, lost acknowledged actions, or private-card disclosure.

### Milestone 5 — Production Readiness

**Backend**

- Validate message size and schemas, room membership, turn ownership, card ownership, and session expiry on every command.
- Add rate limits and redacted diagnostics. Test that clients cannot read opponents' hands, buried cards, or shuffle inputs.

**Frontend**

- Polish desktop and mobile layouts, rule explanations, accessibility, error recovery, and match results.
- Test 10-seat readability and hands containing many duplicate cards.

**Infrastructure**

- Separate staging and production, automate deployment, and document rollback and active-match draining.
- Test backup restoration and monitor command latency, timer lag, reconnect failures, rejected actions, and match failures without logging private hands.
- Agree on target concurrent rooms and measure capacity. Begin with one authoritative backend instance; introduce multi-instance match ownership, fencing, and routing only when required by measured load.

**Exit criterion:** browser acceptance, security, load, deployment rollback, and restore checks pass against documented release targets.

## 4. Verification Matrix

| Layer             | Required coverage                                                                                                                          |
| ----------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Rules unit tests  | Every specification clause and resolved decision; all levels, trump categories, supported multiplicities, and player counts.               |
| Boundary tests    | Scores at 0, 1, and immediately below/at/above every checkpoint; J barrier; reaching A; multiplied scores outside nominal totals.          |
| Invariant tests   | Card conservation, unique physical ownership, correct play counts, equal post-trick hand sizes, rejected commands leaving state unchanged. |
| Replay tests      | Identical initial state, ordered commands, shuffle, clock events, and rules version produce identical outcomes.                            |
| Integration tests | Declaration/deal races, exact timer boundaries, database failures, retries, restart recovery, and authorized state projection.             |
| Browser tests     | Full multiplayer journeys, kitty exchange, gamble failure, scoring explanation, keyboard use, mobile layout, and reconnect.                |

Prioritize meaningful rule coverage over a percentage-only target. Keep known tricky cases as permanent regression fixtures.

## 5. Delivery Order and Technical Notes

Deliver in this order: **rule decisions → foundation → trick engine → full match → online recovery → production**. Frontend fixture work and infrastructure scaffolding can progress alongside the engine. The first playable milestone is a complete local match; the release target includes all four player counts and all specified rules.

For transport, Socket.IO is a candidate, but recovery can fail; implement application-level snapshot synchronization as described in its [connection recovery documentation](https://socket.io/docs/v4/connection-state-recovery/).

Use database transactions to commit each accepted action's event and state update together; PostgreSQL documents their all-or-nothing behavior in its [transaction guide](https://www.postgresql.org/docs/current/tutorial-transactions.html).

Choose a hosting provider and exact dependency versions during foundation work based on deployment constraints. This roadmap does not authorize provisioning paid infrastructure or deploying the game.
