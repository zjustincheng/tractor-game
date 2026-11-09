# Roblox Quick Match review

Scope: the user requested the website's **Quick Match** gameplay. Private rooms,
saved-game/replay persistence, training tools, and decision flashcards are outside
this pass. The existing Roblox table, cosmetics, reactions, and animations are
preserved.

## Findings and implementation

The previous Roblox engine accepted only a single physical card per command,
completed every hand after exactly 25 tricks, used fixed level 2, and displayed
level rewards without authoritative settlement. Changing selection alone would
have allowed illegal plays and incorrect winners.

| Website Quick Match behavior                                                              | Roblox implementation                                                                                                                    |
| ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| One round at a server-chosen random level from 2 through A                                | `Practice.new` with `quickMatch`; recorded random starting level; round outcome determines the match winner                              |
| 4, 6, 8, or 10 players; alternating teams; scaled decks/kitty/thresholds                  | Player-count selector, dynamic seats, `Cards.config`, private per-player projection                                                      |
| Dealing, declarations, stronger overturns, joker trump, fallback and eight-second windows | Server-timed setup; only dealt cards may declare; bots can declare from their own hands; explicit animation duration                     |
| Dealer picks up/buries kitty and leads                                                    | Authoritative distinct-card validation and dealer-only pickup                                                                            |
| Select multiple cards; identical printed sets and consecutive tractors                    | Array commands, independent card selection, `Structures.homogeneous` and canonical decomposition                                         |
| Automatic largest-structure grouping and gamble validation                                | Largest count, multiplicity, power, then physical-ID ordering; weakest beatable component reduction                                      |
| Failed gamble returns unused cards and adjusts defender score ±20                         | Only reduced cards leave the hand; penalty accumulated independently of captured points                                                  |
| Follow count, category exhaustion, full structure and available-set obligations           | `PlayRules.follow`, including protected larger sets and partial responses that cannot win                                                |
| Sequential winner comparison; any comparable gamble component can beat                    | `PlayRules.winning`; alternate disjoint partitions and identical-strength ties                                                           |
| Multi-card bots and legal hints                                                           | Own-hand/public-lead deterministic baseline; no access to hidden opponent hands for bot or hint selection                                |
| Finish when hands empty; pause between tricks                                             | `trick-review`, explicit Next Trick, and completion by card exhaustion rather than a fixed trick count                                   |
| Kitty multiplier, penalties, score thresholds, level checkpoints and Jack reset           | `Scoring.settle`; kitty multiplier uses the largest winning component, matching `backend/src/bot-match.ts`                               |
| Quick Match winner and another fresh deal                                                 | Authoritative outcome winner, New Match, deliberate confirmation when abandoning an active hand, monotonic revisions across replacements |
| Inspect completed plays, play manually or automatically                                   | Public per-round history, Hint, Clear, autoplay, Enter to submit, H for hint, Escape to clear                                            |
| Display played combinations and selection feedback                                        | Scrollable multi-card groups, authoritative winner highlighting, structural/legal selection feedback                                     |

## Boundaries

This is gameplay-rule parity over tested cases, not a claim that the complete web
application or every possible state has been ported. The web game's trained
Expert/Champion model, difficulty-specific tactical policies, belief search,
and configurable replay-animation speed are not duplicated. Roblox uses the
website's deterministic legal selection baseline; bot strength is not equivalent
to the website's advanced policies. Autoplay uses a fixed 1.2-second cadence.

History is public played cards from the current round, not a persistent replay
library. Coins and cosmetics remain session-based prototype features. The shop's
monetization prototype is unrelated to the Quick Match rules and has not been
integrated with real Roblox receipts in this pass.

## Verification

`npm run test:roblox -- /path/to/lua-or-fengari` runs native state, setup, move,
server-handler, client-handler, and viewport suites, then generates expectations
from the actual TypeScript implementation. The parity suite compares:

- 16 declaration-option sets, including multi-deck joker options.
- 149 structure decompositions and 244 legal/illegal follow cases.
- Targeted gamble reduction/penalty and non-transitive winner comparisons.
- 44 settlement boundary cases.
- 12 seeded complete rounds across all four player counts, totaling 1,512 commands,
  with per-command hands, actual played cards, winner, score, and penalty checks.

Additional native tests cover duplicate/unowned/malformed commands, rejection
without mutation, a pair submitted through the actual client callback, multi-card
rendering, both gamble penalty directions, the largest-component kitty multiplier,
card conservation, one-time rewards, stale commands, and Quick Match termination.

Browser previews come from the actual LocalScript instance tree via service
doubles. They are **not Roblox Studio screenshots**. Studio import, touch input,
real scheduler/network behavior, and native font rendering still require the
manual checklist in `roblox/README.md`.
