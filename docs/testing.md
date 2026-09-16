# Game Verification

## Implemented rule coverage

| Specification / decision | Verification                                                                                                                                                                                                                       |
| ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1, 3, 8, 12; D1–D2       | Every deck count, 54-card deck identity/multiplicity, 100 points per deck, kitty/hand sizes, card conservation, alternating teams, counterclockwise dealer rotation.                                                               |
| 5–6; D7                  | Every level and trump mode; level removal, category boundaries, adjacent effective powers, joker ordering, printed set identity.                                                                                                   |
| 7.2–7.5; D11             | Legal suit/joker declarations, same-rank multiplicity overturning, first-round small-to-big joker takeover, mixed joker counts, and physical-card validation.                                                                      |
| Round lifecycle          | Equal deterministic deals, declaration lock/reset windows, random fallback, scheduled-dealer kitty exchange, first-lead ownership, and transition to trick state.                                                                  |
| Round settlement         | Defender point totals, kitty base points and structure multipliers, penalties, checkpoint advancement, role swaps, match victory, and Jack reset gating.                                                                           |
| Solo bot matches         | Seeded full matches through A at all four player counts, legal homogeneous/gamble follows, equal remaining hands, dealer rotation, next-round levels, hidden-hand projection, stale-command rejection, and app-instance isolation. |
| 5.4, 8.3, 9.1, 10        | Supplied adjacency examples, singles through five-of-a-kind, no wraparound, no equal-power tractors, no cross-suit structures, exact structure comparison before trump, earlier-play ties.                                         |
| 4; D4–D5                 | Negative/zero scores, each side of every checkpoint, advancement beyond nominal totals, J barrier, reaching A, failed-gamble penalty direction.                                                                                    |
| Private API projection   | Only the viewer's hand, supported settings, no additional command fields, no-store responses, malformed/oversized request rejection.                                                                                               |
| Browser journey          | Every player count, keyboard card selection, no-suit preview, deck-scaled score exploration, failed-request recovery, mobile layout without horizontal overflow, and a server-judged rule drill.                                   |

Run `npm run check` and `npm run test:e2e`. Browser tests require Chromium or an explicitly selected Chrome installation.

## Foundation validation results

- 177 rules/API tests passed, including four complete matches, private room creation/join/ready flow, private ready-room game projection, room restart recovery, revisioned room events, cross-room isolation, known-void lead avoidance, validated attacker gambles, suit/rank freshness leads, supported declaration tie-breaking, tactical follows, failed-gamble feedback, snapshot restart recovery, failed writes, corrupt files, and expiry.
- Twelve Playwright journeys passed across desktop Chrome and mobile Chrome emulation. Bot journeys cover paced turns, pause/skip controls, per-card dealing progress and lock, a complete round, history, resume after refresh, and starting round two.
- Formatting, ESLint, TypeScript checks, and both production builds passed.
- Both container images built; the local stack became healthy. HTTP smoke checks verified the frontend and private preview responses for all four player counts through nginx.
- Desktop/mobile ten-player screenshots were inspected. The optional PostgreSQL profile and remote CI execution have not been exercised.

## Not implemented yet

Solo matches run the existing follow/gamble engine across successive tricks and rounds. Ready private rooms create and accept server-validated gameplay commands, and the home page provides a polling lobby plus private hand controls covered by a browser room journey. Completed room tricks advance authoritatively, and final hands use the shared settlement engine for defender scoring and level results. Room snapshots can be restored after a clean backend restart; the container persists them on a shared match-data volume. Room clients receive a server-issued deal start timestamp and rotation duration for synchronized progress display. The solo tracker now includes deterministic category odds alongside exact public counts and known voids. Multi-process coordination is still pending. Saved solo snapshots restore across server restarts; tests exercise graceful application restarts and failed writes, not physical power loss. Full-match simulations use legal bot suggestions for the human seat; they do not exhaust every possible human gamble or rule combination. Remaining rule decisions in the decision log still need concrete examples.

Container configuration can be checked with `docker compose -f infrastructure/compose.yaml config --quiet`; CI also builds both production images with `docker compose -f infrastructure/compose.yaml build --pull=false`. A running Docker daemon is required for these checks. Multi-process coordination and hosted deployment remain outside the current scope.
