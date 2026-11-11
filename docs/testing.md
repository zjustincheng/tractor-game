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

`backend/src/training/roblox-guard.test.ts` covers the Roblox-rules best-learner guard: it needs a full four-generation window, keeps the learner ending the best stretch, ignores ordinary swings, returns after a sustained drop, gives a restored learner a fresh window, and survives checkpoint resume. It replays the real scores from the run that declined at generations 237-245. It does not show that the guard makes a run beat the Roblox bots.

`backend/src/training/roblox-burial.test.ts` covers Roblox-rules burial options, which start from the Roblox bot's burial and leave website burials unchanged, and checks that a Roblox-rules generation skips baseline and Sharp when its Roblox score cannot earn promotion. `roblox/tests/parity.mjs` checks that the in-game Luau burial in `roblox/src/server/TrainedBots.luau` picks the same cards.

`roblox/tests/ranked.lua` also covers divisions (400 RP each), season numbering and rising season coins; `server.lua` covers paying season rewards once at rollover. `roblox/tests/ranked.lua` covers Ranked point changes, including the Gold cap for bot-only games, and `roblox/tests/matchmaker.lua` covers its separate queue, longer wait, and rank-based matching that widens from one tier to two to anyone. The server wiring that marks a table as Ranked is not covered because `roblox/tests/server.lua` cannot run against the current server script.

Update 2026-11-10: the Roblox suites run again under Fengari. `server.lua`, `tables.lua`, `crossserver.lua` and `matchserver.lua` stub purchase, badge and analytics services; loops close the Double window; `setup`, `practice`, `moves` and `multiplayer` pin the 8-second declaration window they were written for. `tables.lua` covers away players (two timeouts in a row give a 3-second timer until they act). `client.lua` loads every UI module and checks the home screen, Money/Rank toggle and Friends page, then stops at its first in-game check (declaration buttons hidden in the harness); the rest of its scenario predates the current UI and still needs updating.

Roblox-rules training runs the game's Chao Di round after burial (`playRobloxChaodi` in `backend/src/training/roblox-rules.ts`, covered by `roblox-rules.test.ts`), and `roblox/tests/parity.mjs` checks its call options and bot choices against `Practice.luau` on 320 hands. Chao Di choices still use the game's heuristic for every seat; the trained bot re-buries and plays under the new trump. Quads are not modelled in training: they need four decks, and training runs at four and six players. The Roblox re-test before promotion plays twice the usual deals and is recorded in the report.

`packages/rules/src/trick.test.ts` covers the Roblox-only largest-piece comparison for throws (D16), and `roblox/tests/parity.mjs` checks trick winners, follow features and complete rounds against the game with it on. Learned Chao Di decisions (`choosePolicyChaodi`) are checked against `Trained.chooseChaodi` on random models; the game uses them only for models exported with `robloxChaodi`.

# Roblox foundation

`roblox/tests/practice.lua` exercises the native pure Lua-compatible card and
single-card practice modules: physical deck uniqueness, points, following,
trump ordering, private projection, rejection without mutation, full-hand
completion, and point conservation including the withheld kitty. Run with Lua
5.3+ or Fengari. `node roblox/build.mjs` packages the source into a local Studio
place without external assets or backend access.

The initial Roblox port is an explicitly limited practice exercise, not full
rule parity. Roblox Studio import, visual/touch layout, multiple clients,
RemoteEvent security integration, and coin/emote interactions require the manual
checklist in `roblox/README.md`; standalone tests do not establish those results.
There is no persistent economy in this slice. Browser tests cover the original
web app only and cannot validate a Roblox UI.

Initial port verification (2026-10-30): the standalone practice suite passed
under Fengari, and every platform script parsed. An exhaustive comparison with
the TypeScript card module matched physical IDs and points for all 108 cards,
and category/power for every card under all 65 level/suit combinations (including
no-suit trump). The generated place XML parsed and embedded all five source
scripts verbatim. Studio play, screenshots, touch layout, and multi-client
verification have not been performed.

Roblox setup continuation: `roblox/tests/setup.lua` covers server-time declaration
expiry, eight-second resets, random fallback with a second window, first-round
mixed-joker lock, kitty dealer selection, rejection of malformed/duplicate/unowned
burials without mutation, and card conservation across a bot dealer's exchange
and opening plays. The complete-hand test now starts with declaration and burial.
Both suites pass under Fengari, and the server/client scripts parse. The UI adds
declaration options, a countdown, and eight-card selection; Studio visual and
multi-client checks remain unperformed and are listed in `roblox/README.md`.

`roblox/tests/server.lua` runs the real server handler with service doubles and
passes two complete practice hands through declarations and burial. It verifies
stale revision rejection, no repeat reward after replayed completion commands,
insufficient funds, duplicate purchases, emote ownership and cooldown, private
projections, and reset on reconnect. This does not validate actual Roblox network
transport, scheduler behavior, rendering, or persistent storage.

# Roblox full-screen table UI

`roblox/tests/client.lua` executes the real LocalScript using UI/service doubles.
It verifies a full-screen backdrop, safe-area controls, declaration commands,
33-card burial selection and its eight-card limit, selection before explicit play,
shop commands, mute behavior, and rerendering on viewport changes.
`roblox/tests/layout.lua` checks card bounds, raised selections, action clearance,
and portrait row fitting at 1440×900, 1280×720, 1024×768, 390×844, 375×667,
and 844×390, with 0, 1, 25, and 33 cards.

`roblox/tests/preview.mjs` captures the actual LocalScript's instance tree from
the doubles and renders browser approximations for visual inspection. These are
saved in ignored `roblox/dist/previews/`; they do not establish Studio visual
parity, font support, safe-area correctness, or live touch/Roblox input behavior.
The actual Studio device and multiplayer checklist remains outstanding.

# Roblox Quick Match rules review

The current Roblox rules replace the initial single-card prototype described
above. `npm run test:roblox -- /path/to/lua-or-fengari` runs the native suites and
cross-language fixtures generated directly from the website's TypeScript rules.
The parity run covers 16 declaration sets, 149 decompositions, 244 follow cases,
explicit gamble/winner cases, 44 scoring boundaries, and 12 full rounds with
1,512 per-command comparisons across 4/6/8/10 players. Final kitty settlement uses
the largest winning component, as in `backend/src/bot-match.ts`, rather than
requiring the entire final gamble to be homogeneous. Quick Match winner selection
is tested separately from full-match advancement.

`moves.lua` adds server transition checks for pair submission, wrong-count and
set-avoidance rejection without mutation, failed gamble returns and both penalty
signs, any-component trump overtakes, final-gamble kitty multiplier, dealt-card
eligibility, and first-round joker takeover. The client suite selects and submits
a pair through the real UI callback, then verifies both cards are rendered. The
server suite completes Quick Matches with random starting levels, ensures rewards
cannot repeat, and prevents continuing a Quick Match as a multi-round game.

The existing trained bot-policy tests do not establish strength parity for the
native baseline bots. Browser approximations and service doubles do not verify
Roblox Studio rendering, live networking/scheduling, or device input. See
`docs/roblox-quick-match-review.md` for the feature comparison and `roblox/README.md`
for the outstanding Studio checklist. Native tests require a supplied Lua/Fengari
runtime and are separate from the default TypeScript CI checks.

The mode-selection header now uses a `GAME MODES` title instead of a player
profile. `preview.mjs` includes a home-screen capture and checks that the header
has no player name. Verification on 2026-11-02: formatting and standalone place
build succeeded. Native tests stopped at `practice.lua:35` (round did not finish);
UI preview stopped at the existing hero shimmer because the UI double supplies
no default `ZIndex`. No new home screenshot was generated; Studio visual
verification remains outstanding.

Follow-up Studio verification on 2026-11-02: the connected `Tractor.rbxlx`
contained an older `RobloxMascot` block in `buildIllustratedThumbnail`.
Removed that block from the edit-time `StarterPlayerScripts.Main` using
`ScriptEditorService:UpdateSourceAsync`, then restarted Play. Client inspection
confirmed all four visible mode thumbnails have zero image labels, and a native
Studio screen capture confirmed all four portrait badges are gone. This verifies
the mode-card removal only; the earlier native-suite failures remain unresolved.

# Roblox lobby clarity pass

On 2026-11-02, updated both the local client source and the connected Studio
place: the four mode cards select 4/8/10/6 players, display team sizes instead of
hard-coded online counts, and show short mode descriptions when space permits.
The unsupported Seven Stars label now identifies the existing ten-player mode.
The featured panel explains Classic instead of advertising a static event timer;
the redundant sidebar is hidden so mode cards have more room.

Native Studio Play verification used actual mouse clicks on all four mode-card
buttons and checked the resulting tier titles for 4/8/10/6 players. The featured
Classic button also selected four players. A fresh Play session confirmed visible
descriptions and no mascot images on any card; a native screenshot was inspected
at 1920×1080. Formatting and standalone place build passed. Phone layout and full
round completion were not verified by this lobby pass.

# Roblox queued player-count regression

On 2026-11-02, reproduced a ten-player lobby selection starting a four-player
match in native Studio. The server now retains and validates the selected count
through queue creation, automatic starts, Start Now, and Change Table. The queue
screen shows the selected team/deck sizes and explicitly identifies bot seats.

`roblox/tests/queue-studio.luau` is a Client-datamodel integration check for a
fresh Studio Play session with the default novice-eligible balance. It invokes
the real remote and server scheduler. It passed for 4/6/8/10 players, covering
automatic start, Change Table, Start Now, invalid queue/start rejection, and
cancellation beyond the original deadline. It is separate from the CLI suites.
Native mouse clicks also verified the ten-player card → novice join → ten-player
match flow, including automatic dismissal of the queue overlay. A native queue
screenshot confirmed the selected five-versus-five/five-deck/nine-bot summary.
This pass does not establish full-round rule correctness or mobile layout parity.

On 2026-11-03, custom-table bottom challenges were expanded beyond pairs. The
server now exposes stronger triples (and larger same-rank groups where the deck
supports them) to overturn a pair, including joker groups. The live Studio rule
module was exercised with a two-card bottom declaration and a three-card level
group; it returned a valid triple challenge. Formatting, place generation, and
diff checks passed.

The client now renders every valid bottom challenge as a selectable control,
highlights the chosen pair/triple/joker group, and submits that option's index.
The previous default-first-option behavior is gone. A fresh Studio Play session
started successfully with the chooser code; the full hand path still needs a
manual Studio run that reaches a player-controlled Chao Di decision.

An additional live Play run reached a player-controlled Chao Di phase with zero
legal options, correctly showing no challenge buttons and leaving PASS available.
The server-side triple-option case remains covered by the direct live module
check; a naturally dealt player triple still needs a favorable hand to exercise
the visible chooser end to end.

On 2026-11-03, custom-table bot bankrolls and settlement caps were corrected.
The server now creates a bankroll for every bot seat and includes every opposing
seat when calculating the carried-coin cap and distributing match results. A live
10-player Studio match was inspected and contained bankrolls for all seats 2–10.
Formatting, place generation, and diff checks passed.

The match HUD was also cleaned up on 2026-11-03: the unified trump/defender
points box now occupies the old `TRACTOR` header-title position during a match,
while the title remains visible in the lobby. A native 1920×1080 Studio capture
confirmed `TRUMP`, defender points, score progress, and status are grouped in the
header. After Chao Di, the player remains in an editable kitty phase; the hint
now explicitly says the new bottom can be replaced before confirming.

On 2026-11-03, custom-table presentation was corrected: Novice, Pro, and Master
descriptions now say Quick Match without claiming every table is 2v2. The score
meter's small-shutout cutoff now scales with the selected player count instead of
remaining fixed at 40 points. Live Studio checks confirmed the custom descriptions
and room-stake settlement are active; formatting, place generation, and diff
checks passed.

# Roblox Tencent-style earnings and point animation

On 2026-11-03, match settlement earnings were changed to follow a Tencent-style
欢乐升级 room model: the selected room supplies the base stake (Novice 500, Pro
1.5K, Master 5K), then the hand result multiplies it through grade, 抠底, and
炒底 bonuses. Wallet balance controls room eligibility and remains a carried
balance cap; it does not add an arbitrary percentage to a room payout. Winners
pay the room ante as a fee and losers pay the result plus that room fee.

The floating `+PTS!` point-capture animation was removed from the client. Point
capture, vault credit, and quest progress remain server-authoritative. Native
Studio checks confirmed the live server contains `walletMultiplier` and the live
client creates no `ScoreCapturePill`. Formatting, place generation, and diff
checks passed.

The match HUD declaration pass now uses a transparent placard group with only
the trump and defender-point pills filled, avoiding the pasted outer rectangle.
Declaration controls are rendered as a Tencent-style NT/spades/hearts/clubs/
diamonds strip; each suit lights only when a legal next declaration exists, and
pressing the same suit again advances to its next legal count. The active
declarer also receives small declared-card tiles above their profile. After a
Chao Di, the action button explicitly changes to `REPLACE BOTTOM` while keeping
the kitty cards selectable. The rebuilt LocalScript was injected into the open
Studio place and ran without new console errors; a full naturally-dealt
declaration visual still needs a favorable hand to exercise every lit suit.

The declaration strip was subsequently split into two rows: Small Joker and Big
Joker controls above the four suit controls. Joker labels now map to their
specific server-side declaration kind instead of using a generic NT button.

# Roblox native suites restored, Chao Di and trick clarity

On 2026-11-06 the native suites that had stopped at `practice.lua:35`,
`setup.lua:35`, `server.lua:44`, and the client load were brought up to date with
the Chao Di phase and the coin economy. All suites pass under Fengari 0.1.5:
headroom probe, practice, setup, moves, chaodi, server, layout, client, and the
website parity run.

- `chaodi.lua` (new): three of a kind overturns either joker pair; a level pair
  still cannot, a joker pair cannot overturn a triple, and big jokers still beat
  small jokers. A successful Chao Di changes trump and who re-buries
  (`kittyHolder`) but keeps the dealer, scheduled dealer, and attacking team; the
  original dealer can still challenge back and leads the first trick.
- `practice.lua`/`setup.lua` complete the Chao Di round (human passes, bots
  decide) before trick play.
- `server.lua` now covers the 3,000-coin starting balance, priced unlocks,
  ownership-gated emote broadcasts (a fix: unowned reactions previously
  broadcast), emote cooldown, Chao Di passes through the real handler, settlement
  payout equal to `netCoins + reliefCoins`, replay safety, and session reset.
- `client.lua` service doubles gained the Roblox APIs the client now uses (sound
  playback, tweens that apply end values, input events, `task.defer`). New checks:
  Chao Di pass via Clear, owner tags on every play with the winner marked,
  the last-trick peek and return, and the exact points pop-up text.
- `run.mjs` first compiles the client with 12 extra top-level locals appended.
  Lua and Luau cap a function at 200 locals; the client had reached that limit,
  which would have stopped the LocalScript compiling in Studio.

`preview.mjs` play/multi modes now render a trick in progress (one completed
trick plus a partial one), and hide fully transparent text. These remain browser
approximations; Studio rendering, fonts, tween timing, and device input were not
verified in this pass.

# Roblox full matches and saved progress

On 2026-11-06 added Full Match (rounds to Ace) alongside Quick Match, and
DataStore-backed progress. All native suites pass under Fengari 0.1.5.

- `server.lua`: a full match starts at level 2 and is not decided by one round;
  Play Again and Next Round both continue at the same table, keeping its stake
  tier and bot balances and the settled levels; Change Table keeps the match
  length. Payouts include the full-match bonus field.
- `server.lua` persistence, through an in-memory DataStore double: coins and
  unlocks survive rejoin; the daily reward is once per calendar day across rejoin
  (previously rejoining reset it); corrupt saves are sanitized (negative/NaN
  numbers, unknown ids, coin products, unowned equipped items) while starter-owned
  items stay equippable; a failed load warns the player and never writes, leaving
  the saved data intact; unchanged sessions skip the write.
- `client.lua`: the match-length toggle and its `fullMatch` queue flag; an
  undecided full-match round shows `▶ NEXT ROUND (2)`.
- `preview.mjs` adds table-screen captures (`tier`, `tier-phone`).

Not verified: real DataStore behaviour, throttling and retries in Studio or live
servers (requires a published place with API access), autosave timing, shutdown
saves, the leave-during-load path, and multi-server concurrency (saves are
last-writer-wins without a session lock). The table-selection screen has a
600px minimum width and overflows portrait phones; this predates the toggle.

# Roblox trick coins and Chao Di stakes

Update 2026-11-10: captured-point coins are paid only on rounds the player wins; `roblox/tests/server.lua` asserts this.

On 2026-11-06: captured points now pay coins per trick (10/30/100 per point by
table) times the Chao Di stake, including the final trick, which previously paid
nothing. The round multiplier cap rose from ×64 to ×256. `server.lua` checks that
trick coins equal the history's team points × table rate × stake, that a ×4 stake
pays four times as much, and that the wallet equals the start balance plus trick
coins plus settlement. `client.lua` checks the stake pill and the "CHAO DI! STAKES
×N" banner when the stake rises. Studio feel of the payout sizes is not verified.

Save-status follow-up (2026-11-06): the server reports `saving = {enabled, reason}`
to the client; unpublished places (`PlaceId == 0`) skip the DataStore with a
publish/API-access explanation, and Studio API-access errors map to the exact
setting. `server.lua` covers enabled status, outage and API-access reasons, and
the warning log; `client.lua` covers the once-per-session popup and the balance
status text. Shutdown now waits for in-flight leave saves; this wait is not
exercised by the doubles.

Payout follow-up (2026-11-06): captured-point coins are no longer credited per
trick; they are tallied and paid with the settlement at the final Chao Di stake.
`Scoring.payoutGrade` (shared, outside the website-parity rules) grades defenders
one step per interval past the overturn line without the previous ×4 ceiling.
`server.lua` asserts the wallet does not change during trick play, the settlement
total, and grades 80/119/120/160/200/240/280 → 1,1,2,3,4,5,6 (and six-player
steps); `client.lua` asserts the meter text `OVERTURN ×3 · NEXT AT 200` at 165.

# Roblox reactions overhaul

On 2026-11-06 reactions moved to one definition table (`arenaUI.emoteDefs`) used by
the dock, shop and animations, and quick-chat lines to `Catalog.phrases` shared
with the server. Fixed: the Laugh reaction referenced a missing colour and errored;
own reactions played twice (local + server echo); a fake "+1" coin toast on every
send; 6–10 player bots threw from the local player's seat and targets listed fixed
names; purchased reactions were unusable from the dock; "Wait for my play!" and
"Good luck!" were dropped by the server; any owned item (e.g. felts) could be
broadcast as an emote.

`client.lua` (with queued `task.delay` callbacks it can flush, a controllable
clock and stubbed `math.random`) covers: locked reaction price prompt, immediate
throw and bubble, cooldown, a bot reply, skipping our own server echo, playing
another sender's reaction from their seat, team targets at ten players, and
Opponents hitting all five. `server.lua` covers broadcast fields, phrase
acceptance, and non-emote rejection. `preview.mjs` adds `chat` and `chat-phone`.
Not verified in Studio: sheet art, sounds, tween feel, and bubble placement at
every seat.

Reaction redesign (2026-11-06): visuals moved to `src/client/Reactions.luau`
(packaged beside the LocalScript, matching the Rojo layout). `client.lua` throws
all nine reactions through the real sheet and asserts each launches, every effect
instance (trail, rings, pops, petals, stains, droplets, smoke, flash, confetti,
steam, speed lines, dust, hit glow) is cleaned up, and the hit wobble settles at
0°; this caught zero-size emoji particles. Preview screenshots cover the sheet on
desktop and phone. Motion timing, arc shape, emoji rendering and sounds have not
been seen in Studio; the previews show static end states only.

# Roblox lobby phones, crowded seats, bot Chao Di, stats

On 2026-11-06:

- Lobby (home and table selection) uses a stacked layout below 600px wide;
  previews `home-phone`, `tier-phone`, `tier-landscape` confirm no overflow.
- Ten-player seats switch from an ellipse to a superellipse when side seats would
  overlap; preview `ten-player-short` (1280×620) shows no overlapping panels.
- Bots Chao Di only for ≥3 more trumps (≥5 for the kitty holder's team) and at
  least a quarter of the hand in trump. `chaodi.lua` covers strong, weak, and
  teammate hands and a passing bot.
- Lifetime stats are tracked at settlement and saved/sanitized with progress;
  `server.lua` checks round counting, survival across rejoin, and cleaning of
  corrupt stats. `client.lua` checks the STATS panel values; preview
  `stats-phone`. `preview.mjs` now honours AnchorPoint and UISizeConstraint.

# Roblox shared multiplayer tables

On 2026-11-06 the server moved from one bot game per player to shared tables.

- `multiplayer.lua` (rules engine): several human seats at 4/6/10 players play a
  full round with bots skipping human seats, `autoAct` for idle humans, points
  conserved; `relativeView` rotates seats for every viewer, swaps team labels,
  levels and points for team-B viewers, and leaves the real state untouched.
- `tables.lua` (real server handler, four simulated players): private table
  creation and join by code (case-insensitive, unknown codes refused), friends
  seated as teammates, host-only start, private hands, rotated views, reactions
  routed between seats and isolated per table, a full shared round settled once
  per player with matching results, idle timeout auto-play with a table message,
  leaving (bot takes the seat, host passes on), quick join pairing strangers with
  equal settings, and disconnects.
- `server.lua` keeps the solo flow; stale-command coverage moved to declarations,
  since plays are validated directly and no longer require the latest revision.
- `client.lua` covers the waiting room (host vs guest), real seat names, a friend's
  reaction from their seat, and Create private / Join by code; previews `waiting`,
  `waiting-phone`, `tier`, `tier-phone`.
  Not verified: real Roblox networking with several clients (use Studio's
  Clients and Servers test), turn-timer countdown rendering, and cross-server play.

# Roblox squads and cross-server matchmaking

On 2026-11-06:

- `matchmaker.lua` (pure): squads stay on one team, squads larger than a team are
  rejected, fill on/off (no strangers join a no-fill squad's team), waiting then
  launching with bots after 20 s, modes never mix, oldest ticket first.
- `tables.lua`: same-server squads — invite/accept, leader-only queue, squad and
  two solos dealt at once with the squad as teammates, size limit, kick (search
  cancelled), fill toggle, disconnect dissolving a squad, solo wait then bots,
  separate modes.
- `crossserver.lua` (MemoryStore/Messaging/Teleport doubles): squad becomes one
  shared ticket, a full match reserves one server, records seats (squad on one
  team), teleports all four with the access code and match id, removes tickets;
  another server's live lock blocks matching and an expired lock is taken over;
  invites arrive from another server and accepting teleports to that server with
  joinSquad; inviting an absent friend publishes a cross-server invite.
- `matchserver.lua`: a reserved server seats arrivals from the shared record,
  sends unlisted players back to the lobby, deals when all arrive or after 15 s,
  and Lobby teleports to a public server.
- `client.lua`: squad panel (crown, kick, fill, leave, leader-only Play), invite
  list and send, invite pop-up accept, search bar text and cancel; previews
  `squad`, `squad-phone`. `PREVIEW_ONLY=name,…` renders a subset.
  Not verified: real MemoryStore/MessagingService/TeleportService behaviour,
  limits and failures, teleport latency, GetFriendsOnline/PromptGameInvite, and
  reserved-server lifecycle — these need the published game with two accounts.

# Roblox visual polish pass

On 2026-11-06, from a full preview audit (21 captures):

- Buttons: one flat style (soft corners, hairline border, gold gradient for
  primaries) replacing stacked shine/bevel strips; disabled primaries turn grey
  with muted text.
- In-game header: controls flow right-to-left with fixed gaps (previously CHAT,
  LOBBY and the settings button overlapped and the rewards text was cut off);
  phones use two rows with the trump/points panel centred underneath; the
  reactions/shop button joined the flow.
- Removed: an always-visible empty status box, declaration tiles lingering into
  trick play, a hero-button shimmer drawn outside the button (grey box), a new
  banner gradient created on every render, and a duplicate Next Round button
  under the result screen; Change Table no longer double-queues.
- Lobby: its own backdrop instead of the game table, VIP/PASS prototype badges
  hidden, bottom bar spread evenly, squad card with invite slots.
- Result screen: dimmed background, clear headline, sized to content, payout on
  readable lines.
- `preview.mjs` now honours UIPadding, ClipsDescendants, text transparency and
  disabled gradients, raises its output buffer (10-player captures failed), and
  adds `settle`/`settle-phone`.
  Not verified in Studio: font rendering of the new button faces, emoji in
  labels, and touch feel.

Visual polish, second pass (2026-11-06): felt lighting (layered centre ellipses
plus crossing edge-shade gradients, pill-shaped), card faces (mirrored corner
index, centred pip, unframed crown/joker art; cards under 72px keep the simple
face), classic card back (inset frame, lattice, medallion), seat panels
(gradient, team accent, drop shadow, hand-count badge with a drawn mini card),
and a dealing swing-in (rotation + pop from the hand's centre). `preview.mjs`
renders gradient transparency and scale corner radii; the client harness keeps
NumberSequence keypoints. Motion (deal swing) is not visible in static previews.

Squads public/private and save visibility (2026-11-06): Fill was replaced by a
squad privacy toggle (`squad_privacy`); public squads (and public solo players)
are listed in `openSquads` and can be joined with `squad_join`; matchmaking always
fills open seats. `tables.lua` covers listing, joining a public squad without an
invite, private squads being unlisted and refusing joins. The lobby header shows
save status (✓ Saved / ⚠ Not saving; tap to reopen the explanation) because the
in-game status line is hidden behind the lobby backdrop. Leaving the game now
always saves even if table/squad cleanup fails (pcall-guarded).

Reactions v3 (2026-11-06): launch burst at the sender; flight with arc scaling,
a ground shadow and sparkle trail; comic impact words; richer landing effects;
target marks (splat + drips, soot + smoke, rising hearts, glow/sparkles, steam,
tyre tracks); bomb table shake; glossy tiles with gold frames for paid
reactions; impacts land just inside the target seat. `client.lua` asserts every
new effect instance is cleaned up. `preview.mjs` adds freeze-frame captures
(`flight`, `impact-*`) where tweens stop at 55% and the flight is sampled at
mid-arc, and now renders Rotation, UIScale and text strokes.

Lobby private tables (2026-11-06): CREATE PRIVATE, the code box and JOIN moved
from the stake screen to the lobby bottom bar (desktop: right of the nav
buttons; phones: their own row). CREATE PRIVATE opens a 4/6/8/10-player size
picker. `client.lua` checks the picker and that the controls live in the lobby
bar; `preview.mjs` adds `private-picker` and `private-picker-phone`. Stake
cards no longer show the info rows.

Wallet-capped winnings (2026-11-06): a round's result pays at most the coins
you carried into it (and no more than the losing side holds); losses were
already capped by your balance. Settlement sends `cappedByWallet` and the
modal reads "capped at your 3K". `server.lua` plays a ×128-stake round
against rich bots with a 50K wallet and asserts the win pays exactly 50K.

Roblox trained bots (2026-11-09): `roblox/src/server/TrainedBots.luau` ports the
website's learned-policy inference and its heuristic baseline;
`ChampionModel.luau` holds the weights from `run-wtIbnC` (exported by
`roblox/export-champion.mjs`). Bots at 4-player tables use it for leads, follows,
declarations and burial; Chao Di, 6/8/10-player tables, idle-player autoplay and
hints keep the existing Roblox heuristics. `parity.mjs` compares inputs, baseline
flags and choices against the TypeScript (random models always; the real champion
when `data/` is present, 508 choices). `trained.lua` covers table-size gating,
public-only context, and fallback on a crash or illegal choice.
`tests/headtohead.lua` (manual) measured trained vs Roblox heuristics over paired
deals with swapped teams: 4p 200 deals 52.0% of rounds, level margin +0.003 (95%
CI -0.054 to +0.059); no measurable advantage. 6p/8p/10p samples (25-40 deals)
were also indistinguishable. Rounds ran under Fengari, not Studio.

Play-style guards and Roblox-targeted training (2026-11-09): `play-style.ts`
encodes reviewed champion mistakes (side pair led before a safe ace of that suit, lone high
trump with no plan, early big-joker lead, big joker spent unnecessarily, barely
winning a contested trick). Models with 33 inputs (`contextual-leads-v12-play-style`)
replace those moves and receive a teacher signal; v10/v11 champions keep their
original inference through `load-policy.ts`. `style-audit-cli.ts` counts each
flaw and `style-compare-cli.ts` measures the guards on v11 weights. `roblox-bot.ts`
is the Roblox heuristic as a practice opponent and promotion gate; `parity.mjs`
checks it, the v12 inputs and the guards against the Luau. Trick play is shared
with the website, but Chao Di is not simulated during training. Training covers
4-player tables only.

## Roblox profile page

`roblox/tests/profile.lua` covers the cosmetic catalog, saving and rejecting forged items, equipping, coin purchases, and stat or VIP unlocks. The profile UI and server message path were checked in a Roblox Studio playtest. Frames shown to other human players at a table need a multiplayer test.

## Roblox VIP table markers

`roblox/tests/tracker.lua` covers suit voids inferred from public plays, the rule that the tracker reads only public fields, and that every part marked safe passes the real gamble check against hidden hands across random deals.

## Roblox Battle Pass

`roblox/tests/pass.lua` covers the reward catalog, XP limits, timed card-marker boosts, claim rules, premium locks, saving, forged data, and season resets. Paying out a real premium purchase needs a live test once a Developer Product ID is set.
