# Tractor Rule Decisions

These clarifications supplement the supplied version 2.1 specification. Confirmed decisions take precedence where they conflict with that specification. Pending details are not implementation defaults.

## Confirmed Decisions

### D1 — Alternating Teams

Assign teams by alternating seats for every supported player count. There is no requirement for partners to sit opposite each other.

### D2 — Declaration Rank and Dealer Rotation

The attacking team's current level determines the declaration rank. Attackers are the team preventing defenders from reaching the swap threshold.

When defenders reach that threshold, the next dealer is the player immediately counterclockwise from the previous dealer, on the newly attacking team. Thresholds scale with deck count as specified in D5.

After the first round, the scheduled dealer picks up and buries the kitty and leads the first trick, even if another player wins declaration. The winning declaration determines trump without transferring those dealer duties. The first-round dealer remains the final declaration winner under the original specification.

When attackers retain their role, the dealer moves to the next teammate counterclockwise, skipping the intervening opponent. For example, with seats numbered counterclockwise, dealer seat 0 moves to seat 2 when attackers retain roles, or seat 1 when roles swap.

### D3 — Declaration Required

Someone must declare. Do not automatically finalize no-suit trump solely because nobody declared. This replaces section 7.7's automatic fallback; joker declarations can still establish no-suit trump.

If nobody declares, use a random selection instead of waiting indefinitely. This authorizes a random fallback and supersedes the earlier requirement to wait for a voluntary declaration.

The random declaration does not lock immediately. Allow another eight-second declaration window, with stronger legal declarations resetting the timer under the normal rules.

If the initial eight-second post-deal window expires without a declaration, randomly choose a player holding a dealt level card and declare that card's suit. In the first round, this player becomes the provisional dealer, subject to later legal overturning. The random declaration starts the additional eight-second window described above.

Record the chosen player and card as a server event so replay remains deterministic. Kitty cards remain ineligible for declaration. The user expects an eligible declaration to exist; no automatic redeal has been requested.

### D4 — Failed Gamble Penalty

- An attacker's failed gamble adds 20 points to the defender score.
- A defender's failed gamble subtracts 20 points from the defender score.
- Defender scores may go below zero.

Examples: defender score 10 becomes 30 after an attacker's failed gamble, or -10 after a defender's failed gamble.

If the final adjusted defender score is negative, attackers advance +3, the same as for zero. Existing J checkpoint and A victory rules still apply.

### D5 — Advancement Beyond Nominal Point Totals

Defender advancement continues increasing by one level per additional checkpoint; it does not cap at +3. Existing J checkpoint and A victory rules still apply.

Use one deck per two players: `deckCount = playerCount / 2`. Each checkpoint interval is `I = 20 × deckCount`; the swap threshold is `2 × I`.

| Players | Decks | Interval | Swap threshold |
| ------- | ----- | -------- | -------------- |
| 4       | 2     | 40       | 80             |
| 6       | 3     | 60       | 120            |
| 8       | 4     | 80       | 160            |
| 10      | 5     | 100      | 200            |

For final adjusted defender score `S`, apply:

- `S <= 0`: attackers +3; retain roles.
- `0 < S < I`: attackers +2; retain roles.
- `I <= S < 2 × I`: attackers +1; retain roles.
- `S >= 2 × I`: defenders advance `floor(S / I) - 2`; swap roles. A zero advancement still swaps roles.

Example for six players: 300–359 points gives defenders +3; 360–419 gives +4; 420–479 gives +5, subject to the J barrier and reaching A.

### D6 — Available Pairs Must Be Followed

When following consecutive pairs without a complete matching tractor, a player must include an available pair rather than avoid it by playing singles.

Example: against `3344♣`, a hand of `6679J♣` must play `66♣` plus two of `7♣`, `9♣`, and `J♣`. Playing `679J♣` is illegal. The partial structure cannot win the trick.

When two available pairs can fill a four-card pair-tractor lead, both pairs must be played even if they are not consecutive. Example: clubs non-trump, level 2, lead `8899♣`, and clubs in hand `33557♣`: the required response is `3355♣`. Playing `3357♣` is illegal because it avoids the second available pair. The nonconsecutive response follows legally but cannot win against the tractor.

Players do not have to break a triple to supply a pair when other cards of the required suit can fill the play. They must break it when necessary to meet the suit-following obligation. This does not remove the obligation to play an available standalone pair.

Examples against a club pair: with `66679♣`, playing `79♣` is allowed; with only `666♣` in the required category, the player must play `66♣`. These examples assume clubs are non-trump and the illustrated ranks are not the current level.

Correction to the earlier question: against a four-card lead, selecting `6 + 7 + 9 + 6` from `66679` is the same physical rank selection as `66 + 7 + 9`. It leaves one six, not a pair. Use the two-card examples above to test the exception unambiguously.

Still unresolved: general priorities among multiple partial tractors and higher multiplicities.

### D7 — Identical Sets Require Printed Identity

A pair or larger set requires the same printed rank and suit. Equal effective power does not make different printed cards a set. Joker sets require the same joker type.

Example: with spades trump and level 5, `5♥ + 5♣` is not a pair; `5♥ + 5♥` is a pair. Off-suit level sets can share effective power without being consecutive.

### D8 — Jack-Only Reset Structure

The final winning homogeneous structure must contain only Jacks to trigger the Jack reset. A tractor of an off-suit Jack pair and the main-trump Jack pair qualifies when J is the level, since those tiers are consecutive. A tractor containing any non-Jack rank does not qualify.

The original conditions still apply: attackers must be on J, defenders must win the final trick and reach the swap threshold, and a winning joker prevents reset. A winning gamble containing both a Jack pair and a joker single therefore does not trigger reset.

A Jack pair inside a winning gamble that also contains a non-Jack pair does not trigger reset, even without jokers. The whole winning play must contain only Jacks; the original homogeneous-structure requirement still applies.

Still unresolved: the precise settlement order relative to advancement and match victory.

### D9 — Automatic Largest-Structure Grouping

The game automatically groups selected cards into the largest available homogeneous structures. Players do not manually split structures into weaker components. For example, selected `3344` in one category forms a four-card tractor when those powers are consecutive, rather than two separate pairs.

Still unresolved: deterministic tie-breaking when equally large structures overlap, and whether maximizing the largest component takes precedence over other decomposition objectives. Four unrelated singles remain four single components, not a four-card homogeneous structure.

The user clarified that the first play determines whether a triple tractor or pair tractor is the required structure. Equal card count does not let a pair tractor beat a triple tractor, or vice versa. This resolves comparison across these shapes, but does not determine how to decompose one lead selection with overlapping candidates.

Confirmed gamble-validation example: with level 2 and clubs non-trump, selected `33344455♣` is a gamble. Another player's club pair higher than `55♣` makes the gamble fail. This is consistent with the components `333444♣` (triple tractor) and `55♣` (pair); use this as a regression fixture rather than treating the eight cards as one homogeneous structure. It does not establish a universal tie-break for every overlapping selection. Apply the existing weakest-beatable-component reduction and penalty when validation fails.

The automatic grouping order is now confirmed: choose the largest structure by card count first; when candidates use the same number of cards, prefer higher multiplicity; when those are equal, prefer the higher effective power. Remaining physical-card ties use stable card IDs for deterministic replay.

### D12 — Following a Gamble

When following a gamble, first match all of its components whenever the hand allows it. If a complete match is impossible, supply as many required sets as possible, preserve larger sets when other cards in the led category can fill the play, and exhaust the led category before using unrelated cards. A partial or nonmatching response follows legally when these obligations are met but cannot win the trick.

This is the same priority used by the pair and triple examples in D6, applied component by component to gambles.

### D10 — Beating a Gamble Component

The user specified that beating any component is sufficient, rather than beating every component. The existing requirement to match the whole play's structure still applies. Same-category beatability during lead validation remains distinct from comparing later trump responses.

Confirmed example: spades trump, level 2; a valid club gamble leads one pair plus one single. Two players void in clubs respond in this order:

1. `KK♠ + 3♠`
2. `QQ♠ + A♠`

The second response takes the lead because its ace beats the first response's single three, even though its queen pair loses to the king pair. A later matching response replaces the current winner when any of its components beats any structurally comparable component of the current winner; it need not win every component. Identical strength alone still leaves the earlier play winning.

Resolve eligible responses sequentially in counterclockwise play order against the current winner. Do not sort plays by a presumed total strength ordering: this component comparison is not transitive.

Do not require components to be paired weakest-to-weakest or strongest-to-strongest. The user clarified that beating any previous comparable component is sufficient. For example, against current winner `44♠ + KK♠`, a later `55♠ + QQ♠` can win because either later pair beats `44♠`; neither needs to beat `KK♠`. Full response structure matching and suit eligibility remain prerequisites. This comparison does not allow a lone higher pair to replace a required four-card response.

### D11 — First-Round Joker Takeover

Three big jokers can overturn three small jokers in the first round. In four-player games, mixed three-joker declarations lock permanently against overturning; the exception applies only to an all-small declaration.

Deck availability still applies: two decks contain only two big and two small jokers. Therefore every legal three-joker declaration in a four-player match is mixed, and the three-big-over-three-small case is possible only with at least three decks.

In the first round, four small jokers require four big jokers to overturn; three big jokers are insufficient. This applies when the deck count supplies enough copies, including eight-player matches. “Locked” here concerns further overturning; declaration finalization still follows the applicable timer rules.

## Remaining Decisions

The unresolved details above and the timing cases listed in [the roadmap](../ROADMAP.md) need concrete examples before dependent rules are implemented.
