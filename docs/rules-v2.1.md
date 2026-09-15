# Complete Tractor (升级 / 拖拉机)

## Game Specification — Version 2.1 (Fully Deterministic)

> Original specification supplied by the project owner, with Markdown formatting added. Later [rule decisions](rules-decisions.md) take precedence where they differ. Original contradictions and superseded rules are retained here for traceability.

This document defines a fully deterministic and implementation-ready rule set.
If behavior is not explicitly allowed here, it is not allowed.

## 1. Game Structure

### 1.1 Supported Player Counts

Rule: 1 deck per 2 players.

- 4 players → 2 decks (108 cards)
- 6 players → 3 decks (162 cards)
- 8 players → 4 decks (216 cards)
- 10 players → 5 decks (270 cards)

### 1.2 Seating & Teams

- Two teams
- Players sit alternating: A → B → A → B → …
- Partners sit opposite each other
- No card communication allowed
- Trick order is always counterclockwise

## 2. Round Roles

Attackers (Declarers)

- Team that won previous round
- Lead first trick
- Objective: Prevent defenders from reaching scoring thresholds

Defenders

- Opposing team
- Objective: Capture point cards and reach thresholds

### 2.1 First Round Special Rule

When starting at level 2: the player who wins trump declaration determines which team begins as attackers.

## 3. Point Cards

Per Deck

- 5 = 5 points
- 10 = 10 points
- K = 10 points
- Total per deck = 100 points

Total Per Round

- 4p → 200
- 6p → 300
- 8p → 400
- 10p → 500

All trick points accumulate to defenders only.

## 4. Leveling System

Checkpoint interval = 20 × number of decks.

### 4.1 4 Players (40-Point Intervals)

- 0 → Attackers +3
- 1–39 → Attackers +2
- 40–79 → Attackers +1
- 80–119 → Swap roles
- 120–159 → Defenders +1 then swap roles
- 160–199 → Defenders +2 then swap roles
- 200 → Defenders +3 then swap roles

### 4.2 6 Players (60-Point Intervals)

- 0 → Attackers +3
- 1–59 → Attackers +2
- 60–119 → Attackers +1
- 120–179 → Swap roles
- 180–239 → Defenders +1 then swap roles
- 240–299 → Defenders +2 then swap roles
- 300 → Defenders +3 then swap roles

### 4.3 8 Players (80-Point Intervals)

- 0 → Attackers +3
- 1–79 → Attackers +2
- 80–159 → Attackers +1
- 160–239 → Swap roles
- 240–319 → Defenders +1 then swap roles
- 320–399 → Defenders +2 then swap roles
- 400 → Defenders +3 then swap roles

### 4.4 10 Players (100-Point Intervals)

- 0 → Attackers +3
- 1–99 → Attackers +2
- 100–199 → Attackers +1
- 200–299 → Swap roles
- 300–399 → Defenders +1 then swap roles
- 400–499 → Defenders +2 then swap roles
- 500 → Defenders +3 then swap roles

### 4.5 Level Progression

All teams start at Level 2:

2 → 3 → 4 → 5 → 6 → 7 → 8 → 9 → 10 → J → Q → K → A

- First team to reach A wins
- No team may skip J
- A team must win while on J to advance beyond J

### 4.6 Jack Reset Rule

If attackers are on J, defenders may reset them to Level 2 ONLY IF:

- Defenders win final trick with a Jack-based homogeneous structure
- Defenders reach at least swap threshold
- If ANY joker wins the final trick, reset does NOT apply
- If a joker wins the final trick, the Jack structure is irrelevant.

## 5. Card Power & Effective Hierarchy

### 5.1 Base Rank (Non-Trump Suits)

A > K > Q > J > 10 > 9 > 8 > 7 > 6 > 5 > 4 > 3 > 2

- Level rank is removed from non-trump ordering
- No wraparound allowed (A highest, 2 lowest)

### 5.2 Jokers

- Big Joker > Small Joker
- Jokers are always trump

### 5.3 Level Cards

- All suits of the current level are in the trump suit
- The current level card is removed from the base non-trump ranking (because it is in the trump suit)

### 5.4 Effective Power (Critical Definition)

- All structure formation and comparison use EFFECTIVE POWER.
- Effective power is determined strictly by the trump hierarchy (Section 6)
- Cards are consecutive ONLY if their effective power values are consecutive
- Equal power cards are NOT consecutive
- No wrapping is allowed

Examples (Spades trump, level = 5)

- Pair 5♠ + Pair Small Joker → legal tractor
- Pair 5♥ + Pair A♠ → legal tractor
- Pair 4♥ + Pair 6♥ → legal tractor
- Pair 5♣ + Pair 5♥ → NOT a tractor (equal power)

## 6. Trump Hierarchy

### 6.1 Suit Trump Exists

Trump Group (highest → lowest)

1. Big Joker
2. Small Joker
3. Level cards of trump suit
4. Level cards of non-trump suits
5. Trump suit non-level cards (A → 2)

All trump cards beat all non-trump cards.

Non-Trump Suits: follow base rank order (excluding level rank).

### 6.2 No-Suit Trump (无主)

Trump Group

1. Big Joker
2. Small Joker
3. All level cards (equal tier)

All other cards follow base rank order.

## 7. Trump Declaration System

### 7.1 Dealing

- Cards automatically dealt one at a time in counterclockwise rotation.
- Each full rotation takes 1 second, regardless of player count (equally split the time over the players)
- Player may declare immediately upon receiving a level card.
- House builder = player who wins final declaration.

### 7.2 Suit Declaration

- Must reveal level card.
- Sets trump suit.
- Dipai (cards on the bottom given to the winner of the declaration) cannot be used to declare/change the trump suit.

### 7.3 Overturning

- Must use same rank (level rank).
- Must reveal strictly greater multiplicity. (i.e pair of level cards to beat a single level card)
- Equal multiplicity cannot overturn.
- If Player A declares 7♣, Player B cannot declare 7♦ unless B reveals strictly more copies.

### 7.4 Reinforcement

- Declarer may reveal additional same-suit level cards.
- Cannot change suit unless overturned first.

Example: [No example was supplied.]

### 7.5 Joker Declaration

- 4p → any 3 jokers
- 6/8/10p → 4 jokers OR 3 big OR 3 small
- Joker declaration overrides all suit declarations. Once joker trump is declared, no further overturning is allowed. (Small exception: If joker trump is declared with small jokers and you are playing the first round of a match, then you can use big jokers to claim possession and become house builder)

### 7.6 Lock Timer

- After the final card is dealt, an 8-second window begins.
- Any stronger declaration resets timer.
- After 8 uninterrupted seconds, the trump suit is declared/finalized for the round.

### 7.7 No Declaration Fallback

If no player declares before the lock timer expires: the round defaults to NO-SUIT TRUMP (无主).

## 8. Dipai (Kitty)

### 8.1 Size

- 4p → 8
- 6p → 6
- 8p → 8
- 10p → 10

The dealer picks up dipai and buries/exchanges the same number of cards.
No burial/exchange restrictions.

### 8.2 Dipai Resolution

The final trick winner captures dipai.
If defenders win final trick:

- Sum dipai point cards
- Determine the largest homogeneous structure within the actual winning structure only
- Multiplier = structureSize × 2
- dipaiScore = basePoints × multiplier
- Add to defenders' captured points

### 8.3 Homogeneous Structure Definition

A contiguous group of cards that:

- Share identical multiplicity per rank.
- Are consecutive in an effective hierarchy.
- Belong to a single suit category (or trump group).

Includes:

- Single
- Pair
- Triple
- Quad
- N-of-a-kind
- Consecutive pairs
- Consecutive triples
- Consecutive quads
- Consecutive N-of-a-kind

Only largest homogeneous group counts for dipai multiplier. Example: KKQQ = 4 cards total and consecutive pair → count 4. Four singles → count 1. 444555 = 6 cards total and consecutive triple → count 6.

## 9. Structure & Follow Rules

### 9.1 Legal Leads

- Any single homogeneous structure
- Or valid gamble (Section 11)
- Non-trump structures → must be same suit
- Trump structures → may mix trump components, but consecutiveness must follow effective power

### 9.2 Follow Rules (Strict)

If lead is multiplicity m and length k:

- MUST follow same suit category if possible
- MUST match multiplicity and length if possible in that suit
- If unable to fully match multiplicity → you MUST match the number of cards played (ex: play a pair on a triple)
- After exhausting suit category → may play any cards to reach k total cards
- If structure is not fully matched → play can NEVER win (i.e if you do not have a triple and the lead is a triple)
- Players are NOT required to break larger sets unless breaking is the ONLY way to follow suit.

Example:
Hand: 6♣, 10♣, 10♣, 10♣
Lead: Pair of Clubs
You may play 6♣ + 10♣ and keep the remaining 10♣ 10♣.

## 10. Turn Resolution

### 10.1 Main Suit

Determined by first play unless trump overrides.

### 10.2 Winning Logic (Explicit)

- If no trump is played → ONLY higher structure in main suit may win
- A different non-trump suit can NEVER win
- If trump is played → trump may win ONLY IF structure exactly matches multiplicity, length, and homogenous structure(s)
- If multiplicity and length do not match → cannot win (even if trump)

### 10.3 Tractor Comparison

A tractor = 2+ consecutive pairs (or multiplicity ≥2) in effective power order.
Comparison rules:

- Structures must match multiplicity AND total length
- Compare highest effective rank within structure
- Any trump tractor beats non-trump tractor of same structure

### 10.4 Identical Strength

If identical → earlier played wins/the first one who played the comparable hand.

## 11. Gambling (甩牌)

### 11.1 Definition

- Gamble = combining multiple homogeneous components from a single suit category.
- Gamble CANNOT mix trump and non-trump categories

### 11.2 Validation

- A gamble fails if ANY player possesses a structure in that SAME suit category capable of beating ANY homogeneous component.
- Validation checks ALL players
- It counts even if a player must break a tractor or larger set
- Trump beatability does NOT invalidate non-trump gamble
- The gamble may be beat if someone plays ALL cards on the trump AND matches the structure of the gamble. (i.e. 2 pairs + 4 single non-trump, then 2 trump suit pairs + 4 trump suit singles win)

### 11.3 Failure

If gamble fails:

- Team gains/loses 20 points
- Identify weakest beatable component
- Only that component is played
- All other cards return to player

### 11.4 Weakest Determination

Weakest must be a beatable component.
Among beatable components:

- Compare multiplicity tier (Single < Pair < Triple < Quad < …)
- If equal multiplicity → compare effective power

## 12. Trick Card Count Rule

Every player must play exactly the same number of cards as the lead in each trick.
After every trick: all players will have equal remaining card counts.

## 13. Dealer Rotation

- First round dealer = final declaration winner
- After each round → winning team's next counterclockwise player becomes dealer
- Dealer rotation is independent of level movement

END OF SPECIFICATION

This specification defines all gameplay behavior deterministically and unambiguously.
