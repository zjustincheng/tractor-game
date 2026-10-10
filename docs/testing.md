# Game Verification

## Saved-match navigation (2026-09-27)

The browser remembers visited bot matches and preserves the previous single-match bookmark when migrating. A new playtest exposes its predecessor ID so the owner of that session can return to the completed match's flashcards. The API still hides the current opponent and review until completion; it does not enumerate other sessions. `saved-bot-matches.spec.ts` covers recovering the predecessor, switching back to the newer match, and returning after reload on desktop and mobile, using only GET requests. Screenshots are recorded in the browser test results. Other older matches visited before this change cannot be discovered from browser storage unless linked as a predecessor.

## Decision review verification (2026-09-25)

The default champion review presents one unanswered lead/follow decision as a flashcard, with its hand and pre-action trick visible. Outcomes are hidden until the answer is submitted. Browser coverage checks selection, successful correction submission, retry after a failed save, resetting selection between cards, skipping without mutation, and agreement with the bot without claiming a training update. Flashcards require a recovered hand; previously corrected decisions and incomplete-context samples remain in the expandable checklist. Skips and agreements are local to the current review session; corrections persist on the server.

Completed Sharp playtests can prepare a bounded deck from validated replay rounds through `POST /api/bot-matches/:id/review`. Preparation creates decision samples without updating weights; it is revision-checked and idempotent. Only actual recorded actions represented in the generated legal options are included. Failed-throw rounds are excluded. API coverage checks preparation, sealing, stale revisions, persistence, and teaching a generated Sharp sample. Corrections update the series' adaptive policy for subsequent champion playtests, not Sharp's heuristic or the saved champion file.

Trick history also exposes animated public-card replay without requiring a champion opponent or teaching samples. The browser suite exercises a Sharp match with an empty review list on desktop and mobile and verifies all four plays are shown without private hand controls.

`decision-clip.test.ts` checks recovery of mislabeled actors from physical card IDs, refusal of ambiguous or mismatched recordings, and withholding a hand when the round is incomplete. Playtest tests cover recording into the current match for both opponent seats and sealing review until match completion. `policy-update.test.ts` verifies that an explicit teacher target overrides the fallback baseline target and increases that action's probability.

`tests/browser/decision-clip.spec.ts` checks the animated table on desktop and mobile: pause before the sampled decision, reveal outcome separately, inspect the decision-time hand, and scroll to the final checklist row. Screenshots are recorded under `test-results/decision-clip-*/decision-clip.png`. The test uses synthetic data, not saved private hands.

A read-only audit of the existing 10-round match recovered all 96 sampled lead/follow decisions and their hands. Seven of its 14 corrections had previously been shown with the wrong actor; the UI now warns when the seat was recovered. A separate in-memory update increased the explicit target probability for each of those 14 examples. This is a mechanism check, not a strength evaluation; it neither validates the human labels strategically nor rewrites existing adaptive weights or the champion. Declaration/burial clips and recordings without unambiguous trick context remain unavailable.

Full rules reconstruction of the saved 32-round Sharp match and 10-round champion match validated 31 and 9 rounds respectively (3,028 positions total). Sharp round 31 and champion round 5 were excluded from offline learning reconstruction because failed-throw context was unavailable. Completed-trick review remains separate from eligibility for offline learning.

Point-margin regressions cover attacker/defender credit both before and after role swaps. Settlement `attackingTeam` names the next round's attackers; scoring must recover the team that attacked the completed round. Checkpoint migration discards pre-fix cached margins, and raw game-log recovery ignores older report caches. Win and level statistics are unaffected by this correction.

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

Run `npm run check` and `npm run test:e2e`. Browser tests require Chromium or an explicitly selected Chrome installation. Run `TEST_DATABASE_URL=... npm run test:postgres` for real PostgreSQL integration tests; normal `npm test` skips that suite without a database URL.

## Latest persistence milestone verification

- `npm run check`: 178 rules/API tests, formatting, lint, typecheck, and both production builds. The two PostgreSQL tests run separately.
- Real PostgreSQL 18 integration: two application instances with independent connection pools, concurrent schema startup, over-subscribed joins, simultaneous ready commands, competing game revisions, restart recovery, token/private-hand/kitty isolation, invite-code collisions, expiry, thrown mutations, and snapshot rollback when event insertion fails.
- Full browser suite with PostgreSQL-backed rooms: 16 desktop/mobile journeys passed. The new four-player journey creates and joins through separate browser sessions, uses UI controls for readiness, kitty exchange and the first trick, drives remaining single-card plays through each player's authorized API, reloads a player during play and the host after settlement, and checks the next round's rotated dealer controls. This is one round plus the next deal, not a complete multiplayer match through A.
- Backend production container build and PostgreSQL startup/room-save smoke check.
- CI now provisions PostgreSQL and runs the database suite; remote CI execution has not been observed in this session.

## Earlier foundation validation results

- 177 rules/API tests passed, including four complete matches, private room creation/join/ready flow, private ready-room game projection, room restart recovery, revisioned room events, cross-room isolation, known-void lead avoidance, validated attacker gambles, suit/rank freshness leads, supported declaration tie-breaking, tactical follows, failed-gamble feedback, snapshot restart recovery, failed writes, corrupt files, and expiry.
- Twelve Playwright journeys passed across desktop Chrome and mobile Chrome emulation. Bot journeys cover paced turns, pause/skip controls, per-card dealing progress and lock, a complete round, history, resume after refresh, and starting round two.
- Formatting, ESLint, TypeScript checks, and both production builds passed.
- Both container images built; the local stack became healthy. HTTP smoke checks verified the frontend and private preview responses for all four player counts through nginx.
- Desktop/mobile ten-player screenshots were inspected. These earlier checks predated the PostgreSQL milestone above.

## Coverage boundaries

Solo matches run the existing follow/gamble engine across successive tricks and rounds. Ready private rooms create and accept server-validated gameplay commands, and the home page provides a polling lobby plus private hand controls covered by a browser room journey. Completed room tricks advance authoritatively, and final hands use the shared settlement engine for defender scoring and level results. Room snapshots can be restored after a clean backend restart; the container persists them on a shared match-data volume. Room clients receive a server-issued deal start timestamp and rotation duration for synchronized progress display. The solo tracker now includes deterministic category odds alongside exact public counts and known voids. PostgreSQL room coordination is now tested across independent application instances. Solo snapshot sharing remains unsupported. Saved solo snapshots restore across server restarts; tests exercise graceful application restarts and failed writes, not physical power loss. Full-match simulations use legal bot suggestions for the human seat; they do not exhaust every possible human gamble or rule combination. Remaining rule decisions in the decision log still need concrete examples.

Container configuration can be checked with `docker compose -f infrastructure/compose.yaml config --quiet`; CI also builds both production images with `docker compose -f infrastructure/compose.yaml build --pull=false`. A running Docker daemon is required for these checks. Hosted deployment, crash/power-loss testing, operational backup/restore, complete deterministic event replay, and shared solo-session routing remain outside the verified scope.

## Slower solo dealing

Solo dealing now uses a shared 400 ms card interval and a persisted server start time. The timing regression checks that undealt cards cannot be declared, dealt cards can be declared, and an early call preserves the entire deal plus eight seconds afterward. Browser coverage checks calls during the reveal without resetting progress on desktop and mobile, alongside bot-round/resume and paced-turn checks. `npm run check` passed with 179 rules/API tests; the PostgreSQL suite remains separately enabled.

## Bot declaration choices

Bot declaration ranking keeps joker and declaration multiplicity priority, then scores each suit from its length, repeated ranks, adjacent repeated-rank pairs (tractors), level cards, and A/K/Q support. A deterministic tie break preserves repeatable matches. Tests cover a long low-card coordinated suit beating a short high-card suit while retaining the existing supported-suit and joker behavior.

## Felt table redesign

Solo manual play and watch mode now share the same felt-table component, with per-seat plays and a horizontal, suit-grouped hand. Trump cards stay at the left, strongest first. Match history and setup controls sit in a collapsed details panel. Four-player mobile tables keep the surrounding-seat layout; larger mobile tables use two columns to avoid overlapping seats and plays.

Desktop Chrome and Pixel 7 emulation checks cover four- and ten-player layouts, card selection, submitting suggested plays, watch/pause/manual handoff, and page overflow. Screenshots from these checks were visually inspected for hand spacing and seat/card collisions. The existing browser journeys also cover live dealing/declarations, paced reveal/pause/skip, round completion, resume, history, and the next round. Ten browser cases passed. `npm run check` passed with 192 rules/API tests; two PostgreSQL tests were skipped because that optional database suite was not enabled. These visual changes apply to solo bot matches; multiplayer rooms and the replay viewer retain their existing layouts.

## Preserving friendly trump

Bot lead selection now retains seat identities for public suit exhaustion, deduplicates observations, and limits evidence to the current round. A partial follow containing an off-suit card also confirms that the player exhausted the led category. When every opponent has shown out of trump and an ally has not, bots choose a side-suit lead if available. This applies to standard leads, Sharp gambles, and the suggested lead used by watch mode. Trump remains available when it is the only category held or all allies have also shown out. The policy does not infer exhaustion from hidden hands.

Regression tests cover all supported player counts and difficulties, both teams' roles, repeated observations of one opponent, teammate/opponent distinction, trump-only hands, all allies out, partial follows, previous-round isolation, and the watch-mode suggestion projection.

## Developer bot behavior export

Each accepted bot action is retained in the solo session event stream. The collapsed match details panel exposes a developer-only CSV download with revision, timestamp, bot seat, lead/follow/bury decision, card count, joker count, and physical card IDs. It is intended for local strategy review after running matches; expired sessions and multiplayer rooms do not expose it.

The detailed export also labels plays as leads, validated gambles, protected or overtaken partners, necessary or failed ruffs, opponent takeovers, and safe follows. A companion summary export aggregates those ratings per bot seat for quick difficulty comparisons.

Summary `trick_wins` now counts only final trick-completion events, while `team_points_captured` reports the points won by that bot's team. `points_played` remains the point value carried by cards the bot itself played.

Summary exports identify the match difficulty and include a `TOTAL` row, making separate Standard and Sharp files easier to compare or combine.

The replay desk now supports play/pause playback at 0.5×, 1×, 2×, and 4× speeds. Beginning and Latest stop playback so review can be resumed deliberately from a known point.

Bots now receive an endgame lead bonus when four or fewer cards remain, favoring strong winners and point cards while retaining earlier-hand joker conservation. A regression fixture covers a nearly empty hand choosing an ace over a low card; the full rules suite covers the existing lead and follow legality guarantees.

Lead strategy values are now exposed through `BotLeadWeights` with stable defaults. A trainer can provide partial weight overrides through `BotLeadContext.weights`, allowing deterministic self-play experiments without changing move legality or the production defaults.

Bot leads also give a measured bonus to suits a teammate is publicly void in, creating opportunities for that teammate to ruff. Opponent voids continue to reduce a suit's priority, so the signal is only used when the public information supports it.

## Offline self-play trainer

`backend/src/training/training.test.ts` covers deterministic full matches through a terminal match winner for 4, 6, 8, and 10 seats, all-seat participation, own-hand decision records, reproducibility, round-limit truncation, bounded mutations, disjoint training/validation seeds (including integer wraparound), promotion rules, invalid checkpoint/config rejection, and deterministic continuation after checkpoint serialization. It also covers the post-game scorer: only twelve or more completed mixed-outcome matches can adjust weights, a winning feature association adjusts in the matching direction, and unchanged features remain unchanged. A concrete hand verifies that changing weights changes the selected legal lead.

The trainer uses shared rule functions to validate every play and settle each round. Earlier backend tests described as “complete matches” stop at `state.phase === 'finished'`, which is a completed round; the training tests explicitly require a non-null `settlement.winner` after level progression. Browser tests do not cover this local CLI, and no website UI has changed.

Small seeded training runs verify that the optimizer can retain an incumbent, accept a candidate after validation, and save/resume checkpoints. Those runs establish pipeline behavior, not statistically reliable playing strength. Training currently optimizes lead coefficients only and does not validate live model loading, neural-network learning, or learning directly from watched games.

## Contextual policy training and local play

The v10 trainer has numerical gradient checks, probability normalization and legal action tests, including the option to pass a declaration. Lead/follow networks remain separate. Practice and greedy evaluation have identical action logits at different temperatures. Counterfactual tests verify deterministic continuation, kitty scoring, joker-saving choices, legal branch validation, score-margin filtering, and that privileged simulator state is never attached to policy experiences.

`policy-update.test.ts` checks delayed round credit, opposite team rewards, deterministic Adam serialization, invalid optimizer rejection, and learning a rewarded alternative that overrides the baseline preference. It checks the empirical KL bound throughout that controlled experiment. These synthetic outcomes demonstrate update mechanics, not playing strength. The updater clips probability ratios, uses a weak baseline anchor, and shrinks oversized Adam steps rather than stalling.

Training tests cover learning from completed rounds even when a full match is capped, deterministic resume, rollback to champion on material pooled regression with optimizer reset, the cooldown that leaves a recovering learner alone and decays each generation, and the indistinguishable band that no longer triggers a reset, and legal full matches with 4, 6, 8, and 10 seats. Promotion still excludes capped matches. v4 through v9 resumes preserve learner weights, reset optimizer state and champion eligibility, and discard incomplete opponent bundles. Current archives store separate lead and follow networks, and opponents use learned declarations and burial too. Validation uses paired team-assignment games, point- and level-margin bootstrap intervals, learned-logit spread diagnostics, an adaptive baseline prior, a level-margin safeguard, and an explicit zero-margin indistinguishable sanity case. The evaluation-only command compares saved learner/champion models against fresh paired baseline games and reads saved validation `games.jsonl`; pooled history is explicitly descriptive when it mixes generations. Promising candidates require the interval lower bound to clear zero again on fresh paired confirmation games. A held-out Sharp gate is covered both ways: a candidate that beats it promotes and records both Sharp stages, and one that loses to it is refused before the archive gate, while `sharpGate: false` still measures and reports the comparison. Archive retention is covered for the full-pool case, keeping the oldest entry and dropping a middle-aged one, and a version migration now preserves the archive while still retiring the champion. Further tests pin that promotion saves the exact evaluated models rather than their recalibrated-prior copies, that a learner rollback restarts the rollback streak without resetting generations since promotion, that a failed baseline or champion gate skips the archive evaluation, and, with stubbed matches that clear the promotion gates, that a complete generation saves a champion byte-identical to the evaluated models while the recalibrated prior reaches only the learner.

Sharp live turns retain the public-belief search; the offline trainer does not use a different search teacher during practice. Long-run convergence and superiority over baseline or humans require held-out experiments and are not established by unit tests.

Solo command tests exercise the injected policy for bot leads and watch-mode suggestions through a completed round. No browser layout changes are made. The offline learner now explores leads, single-card follows, declarations, and burial alternatives; live loading now injects all four decision types through the shared adapter. Long-run convergence, superiority to human players, and broader strategy discovery are not established by this test suite.

## Complete live policy and Sharp comparison

Live checkpoint loading now uses the same four-decision adapter as offline evaluation: lead, follow, declaration, and burial. Adapter tests cover invariant learned choices across difficulty/hidden-hand inputs, exact Sharp opening behavior, and all four learned decisions during paired simulator rounds. The live bot journey unit test checks injected lead/follow/declaration/burial decisions and watch suggestions, including limiting declaration inputs to dealt cards. The existing promotion and deterministic-continuation tests remain applicable.

`compare:live` is read-only, defaults to the saved champion, and uses the checkpoint's table sizes and round cap against the built-in Sharp adapter. Sharp retains its existing privileged throw validation. These tests establish legal execution and shared decision paths; they do not establish superiority over Sharp or human-level strength. No long training run is part of verification.

Verification: `npm run check` passed (274 tests; two optional PostgreSQL tests skipped). Chrome desktop and mobile round/resume/next-round journeys passed with `run-PtEwtC/checkpoint.json` loaded through `BOT_POLICY_FILE`. A read-only `compare:live --seeds 1` smoke check completed two full matches without truncation. Its one win in two games is not a strength estimate.

## Human playtest assignments

Playtest tests cover fixed partner routing, round-to-round assignment retention, missing-champion and table-size rejection, hidden projections, replay export restrictions, restart with frozen model recovery, completed-match reveal, and idempotent concurrent continuation with alternating opponents. Standard match storage supplies atomic snapshot writes; no multi-file series transaction is introduced. A continuation links to the completed parent and duplicate requests reuse the existing child.

The browser playtest case checks the setup control, hidden opponent label, disabled autoplay and disabled replay/behavior-CSV exports, resume, and page overflow on desktop and mobile. It requires `BOT_POLICY_FILE` and otherwise skips. API tests also cover that the replay and both behavior CSVs return 403 during an active playtest and 200 once it ends. Full-match completion and next-assignment projection are covered with a terminal fixture in API tests, not a long human-style browser match. These checks establish assignment and measurement mechanics, not strength against humans.

Verification: `npm run check` passed with 277 tests (two optional PostgreSQL cases skipped). The human-playtest browser case passed on desktop Chrome and Pixel 7 emulation with the frozen champion loaded; both screenshots were inspected for layout and hidden labels.

Empty gateway responses are covered by desktop/mobile browser tests: a simulated empty HTTP 502 must show a server-unavailable message and re-enable the start button. Both cases, lint, and typecheck passed. A local startup failure was recovered by preserving a stale room-owner lock only after verifying its recorded PID no longer existed; the live proxy health check then returned HTTP 200.

Completed champion playtests collect bounded, private policy experiences for lead, follow, declaration, and burial decisions. The post-match review exposes only legal action labels and IDs after the result; a submitted preferred action updates the series-specific learner through the existing clipped policy optimizer. Feedback is applied once, only to a sampled decision from a completed champion match, and the child match inherits the adapted models. Sharp matches create no policy samples. The loaded checkpoint remains unchanged. This is human preference supervision; match outcomes and unreviewed observations do not train the policy.

Recorded-match learning (`match-learning.test.ts`) reconstructs a generated completed game, verifies preserved source data and public history, rejects truncated and inconsistent rounds, and checks that informative counterfactual comparisons change learner weights without changing the champion. It verifies round deduplication after checkpoint serialization and retention beyond the old 100-trick limit. Reconstruction checks every accepted move, ownership, winners, captured points, and final settlement before any position from a round can train. Coverage excludes missing old history, incomplete rounds, and failed throws whose original attempted cards were not retained. Simulator comparisons demonstrate an update mechanism; human strength still needs held-out evaluation.

Tactical policy v11 adds eight inputs alongside the original 22. Tests in
`backend/src/training/tactical-policy.test.ts` cover zero-weight legacy migration,
retirement of obsolete validation/replay caches, legal pair alternatives,
suit-aware overtaking, dealer/ace lead context, and public trick point totals.
Live play, self-play and recorded-match learning share `botPlayContext`; opponent
hands are never passed through that context. Options still do not enumerate every
mixed-card response to complex throws. Replay counterfactual labels use constrained
sampled deals with learned-policy continuation, so changed choices are not evidence of
improvement against human opponents. New model versions must earn fresh promotion.

`belief-deals.test.ts` covers a feasible assignment that requires reassigning earlier cards, hard void constraints, exposed ownership, known kitty, and rejection of contradictory information. Counterfactual tests check full-deck conservation, unequal mid-trick hand sizes, current-trick voids, dealer kitty and declaration constraints through a live round. Update tests cover duplicate reference removal, disabling comparisons, and round-local default returns. Promotion tests verify both saved models retain the evaluated prior. Newly recorded solo declarations are retained for replay learning; older replays without that metadata cannot reconstruct all historical declaration knowledge. Sampling does not infer opponent strategy or all structural information from past follows. These checks establish consistency, not a playing-strength gain.

Live loading of a saved v10 champion retains the original 22-input inference and
singleton-only follow alternatives. This keeps the deployed champion available
while v11 training imports migrate separately and require new validation.

# Language-model opponent coverage

`backend/src/language-model.test.ts` mocks the provider to verify seat-specific private information boundaries, live legal choices, declaration and burial selection, illegal-response rejection, strict API output handling, concurrent-command exclusion, failed-save rollback, restart recovery, and idempotent series continuation. Completed replay exports include public model provenance without opponent notes. `tests/browser/language-model.spec.ts` checks configuration guidance, selecting the opponent, result display, disabled autoplay, and continuation with memory on desktop and mobile; it records a result-screen screenshot.

These tests do not contact a paid API, measure model quality, or establish strength against humans. Live API access, latency, declaration strategy, and multi-match adaptation need validation with a configured account. Existing deterministic rules tests remain responsible for legal game transitions.

# Website polish

`tests/browser/site-polish.spec.ts` checks the one-round setup selection, live match creation, quick-match access outside collapsed settings, the friends navigation link, and viewport overflow on desktop and mobile. It saves full-page setup and table screenshots. Existing table-layout and saved-match browser tests cover card interactions and recovery; this visual pass does not change game rules.

# Level-based policy selection

Policy evaluation tests cover promotion with a positive level interval and point uncertainty crossing zero, rejection beyond the −0.01 point tolerance, level-based rollback, separate point/level evidence, invalid evidence, legacy checkpoint loading, and descriptive round-win counts. Existing generation tests cover optimizer reset and cooldown, and the integration promotion test verifies the saved model matches the evaluated model. No long training or fresh-seed strength evaluation is part of these automated tests; random-level quick-match strength remains unmeasured.
