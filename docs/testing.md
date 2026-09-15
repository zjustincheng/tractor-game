# Foundation Verification

## Implemented rule coverage

| Specification / decision | Verification                                                                                                                                                                                     |
| ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| 1, 3, 8, 12; D1–D2       | Every deck count, 54-card deck identity/multiplicity, 100 points per deck, kitty/hand sizes, card conservation, alternating teams, counterclockwise dealer rotation.                             |
| 5–6; D7                  | Every level and trump mode; level removal, category boundaries, adjacent effective powers, joker ordering, printed set identity.                                                                 |
| 7.2–7.5; D11             | Legal suit/joker declarations, same-rank multiplicity overturning, first-round small-to-big joker takeover, mixed joker counts, and physical-card validation.                                    |
| Round lifecycle          | Equal deterministic deals, declaration lock/reset windows, random fallback, scheduled-dealer kitty exchange, first-lead ownership, and transition to trick state.                                |
| Round settlement         | Defender point totals, kitty base points and structure multipliers, penalties, checkpoint advancement, role swaps, match victory, and Jack reset gating.                                         |
| 5.4, 8.3, 9.1, 10        | Supplied adjacency examples, singles through five-of-a-kind, no wraparound, no equal-power tractors, no cross-suit structures, exact structure comparison before trump, earlier-play ties.       |
| 4; D4–D5                 | Negative/zero scores, each side of every checkpoint, advancement beyond nominal totals, J barrier, reaching A, failed-gamble penalty direction.                                                  |
| Private API projection   | Only the viewer's hand, supported settings, no additional command fields, no-store responses, malformed/oversized request rejection.                                                             |
| Browser journey          | Every player count, keyboard card selection, no-suit preview, deck-scaled score exploration, failed-request recovery, mobile layout without horizontal overflow, and a server-judged rule drill. |

Run `npm run check` and `npm run test:e2e`. Browser tests require Chromium or an explicitly selected Chrome installation.

## Foundation validation results

- 147 rules/API tests passed.
- Eight Playwright journeys passed across desktop Chrome and mobile Chrome emulation.
- Formatting, ESLint, TypeScript checks, and both production builds passed.
- Both container images built; the local stack became healthy. HTTP smoke checks verified the frontend and private preview responses for all four player counts through nginx.
- Desktop/mobile ten-player screenshots were inspected. The optional PostgreSQL profile and remote CI execution have not been exercised.

## Not implemented yet

The foundation does not claim coverage of physical timed dealing animation, complete live follow enforcement outside the guided positions (D6, D12), full gamble decomposition/comparison (D9–D10), round-to-round dealer persistence, room transport, reconnect, persistence, or complete match lifecycle. Declaration, kitty, settlement, and development practice-round transitions are pure or in-memory helpers; wire them to authenticated commands and durable events in the next milestone. The three-joker/four-joker and unresolved higher-multiplicity examples in the decision log remain requirements, not passing tests.

Container configuration can be checked with `docker compose -f infrastructure/compose.yaml config --quiet`; a running Docker daemon is required to build and smoke-test images. CI runs code checks and browser tests, but production deployment verification belongs to a later milestone.
