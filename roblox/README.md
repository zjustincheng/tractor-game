# Roblox Quick Match

A native Luau port of the website's Quick Match rules, with the existing Roblox
table, shop, and reactions. See the [feature review](../docs/roblox-quick-match-review.md)
for the comparison and remaining boundaries.

## Open the updated version

**Live sync with Rojo (recommended).** Install Rojo once (`brew install rojo`,
then `rojo plugin install` for the Studio plugin), then:

1. `npm run roblox:build` and, in Studio, **File → Open from File** →
   `roblox/dist/Tractor.rbxlx` (or open your published place).
2. `npm run roblox:serve` in a terminal and leave it running.
3. In Studio: **Plugins → Rojo → Connect** (localhost:34872).

From then on, saving any file under `roblox/src/` updates the open place
immediately; stop and press **Play** to run the new code. Nothing needs reopening,
and a published place keeps its DataStore access while syncing. The built place
uses the same `TractorServer`/`TractorClient` folders as `default.project.json`, so
connecting replaces scripts rather than duplicating them.

**Without Rojo:** run `npm run roblox:build`, then close the place in Studio
(don't save) and reopen `roblox/dist/Tractor.rbxlx`. An already-open place does
not reload rebuilt files.

Quick Match deals one round at a random level from 2 through A. Declare trump or
wait for the bots/fallback. If you are dealer, select the indicated number of
cards and bury them. Select **all** cards you want to play—pairs, tractors, sets,
or a gamble—then press **Play N Cards**. Tap selected cards again to deselect.
The server validates the entire response and returns unplayed cards from failed
gambles. Use **Next Trick** to continue after reviewing a completed trick.

Each play on the table carries its owner's name; the current winner's play is
gold and tagged **★ WINNING**. **◀ Last Trick** shows the previous trick on the
table, and a completed scoring trick pops its points over the winner (`+N PTS`
for defenders, `N PTS SAVED` for attackers).

After burial, players may **Chao Di** in turn with a stronger reveal: a pair beats
a single, three of a kind beats any pair (including a joker pair), and big jokers
beat small jokers. Chao Di changes the trump suit and who re-buries the kitty; it
does not change the dealer or which team attacks.

- **Hint** selects a legal response from your own hand and public information.
- **Clear** removes the selection.
- **History** reviews public plays in the current round.
- **Auto** toggles automatic legal play with pauses between actions.
- **Enter** submits, **H** selects a hint, **Escape** clears the selection.
- **New Match** requires a second click before abandoning an unfinished hand.
- The reaction button opens the existing cosmetic/emote shop.

The full-screen background covers the viewport while controls respect Roblox and
device safe areas. Portrait hands use multiple rows; narrow landscape hands and
large played combinations scroll horizontally.

The server owns all opponent hands, kitty cards, random choices, timers, move
validation, settlement, and rewards. Only your hand and public information are
sent to your client. No hosted HTTP backend or credentials are required.

## Scope and limitations

Pairs, higher sets, tractors, gambles, follow obligations, trump declarations,
kitty scoring, level checkpoints/Jack reset, and Quick Match results use native
ports of the website's rules. Choose the match length on the table screen:
**Quick · 1 Round** starts at a random level and is decided after one round;
**Full Match · To Ace** starts both teams at 2 and continues with **Next Round**
at the same table (stakes and bot balances carry over) until a team passes Ace.
Coins settle every round; winning a full match adds a bonus of 10× the table base.

**Coins and Chao Di stakes.** Points your team captures are tallied during the
round and paid with the round result (10 per point at Novice, 30 at Pro, 100 at
Master, times the final stake); nothing is paid mid-round. Each successful Chao Di
doubles the stake (×2, ×4, ×8…), shown in the **STAKE** pill and announced with
a banner. The round payout is base × result grade × kitty × stake, capped at ×256.
Defenders' grade keeps rising every interval past the overturn line — with four
players ×1 at 80, ×2 at 120, ×3 at 160, ×4 at 200, ×5 at 240, and so on (60-point
steps from 120 with six players, etc.); the meter shows the current step and the
next line. Attackers earn ×4 for a shutout, ×2 for a near shutout.

### Squads and matchmaking

**Squad (party).** The home screen's left card is your squad. **👥 Squad up**
lists public squads in this server you can **Join** without an invite, players
here you can invite, and your online Roblox friends (friends in another server
get the invite there, and accepting brings them into your server and squad).
Squads hold up to 5; the leader (👑) can remove members and toggles
**🌐 Public / 🔒 Private** — public squads appear in everyone's Squad up list;
private squads are invite-only. Invites pop up at the top with **Join** / ✕.

**Matchmaking.** Choosing a table (mode + stakes) queues the whole squad. A squad
always sits on one team, so it can be at most half the table (2 for 4 players,
3 for 6, …). Open seats are filled by other queued players, then bots. A match
starts as soon as every seat has a person, or after 20 seconds with bots in the
empty seats. A bar at the top shows the search time with **Cancel**.

**Cross-server** (published game only): tickets go to a shared MemoryStore
queue; one server at a time (a 6-second lock) forms matches, reserves a private
server per match, records the seats, and announces it over MessagingService.
Each server teleports its matched players; the match server seats arrivals
from the shared record (teleport data only carries the match id), waits up to
15 seconds for everyone, then deals with bots for no-shows. Lobby returns you to
a public server. Code: `src/server/Matchmaker.luau` (pure rules) and
`src/server/CrossServer.luau` (Roblox services).

**In Studio / unpublished places** teleports and MemoryStore are unavailable, so
the same matchmaker runs inside the current server — use **Test → Clients and
Servers** with 2–4 players to try squads and fill. To test cross-server for
real: publish, enable Studio API access, and join with two accounts in
different servers (e.g. set Max Players low so they land apart).

**Private tables** (Create private / Join by code) still work within one server.
In shared tables everyone sees themselves at the bottom with their team in blue;
real players show in gold. With 2+ people turns time out (25 s play, 45 s bury)
with a suggested move, finished tricks advance after 2.5 s, and leaving hands
your seat to a bot. Each person settles their own coins and stats.

### Reactions

**CHAT** opens the reaction sheet: a target selector (Auto, Partner, Both
opponents, or a named opponent with four players; Auto, My team, Opponents at
bigger tables), nine emoji reaction tiles, and quick-chat chips. Locked tiles show
a padlock and price; tapping one unlocks it if you have the coins. A gold bar
drains across the 1.5-second cooldown shared with chat.

Reactions fly on an arc with a trail (the tractor dashes low and fast) and land
with their own effect: rose petals and a heart, a tomato splat with droplets, a
bomb flash with blast rings and smoke, trophy confetti, coffee steam, tractor
speed lines and dust, a waving hand, or a bounce with sparkles. Hostile hits
wobble the target's seat; friendly ones glow. Speech bubbles pop in with a tail
and fade out. Bots sometimes answer what you throw at them. Visuals live in
`src/client/Reactions.luau`, a ModuleScript beside the client LocalScript.

### Stats

**STATS** on the home screen shows lifetime figures: rounds played and won (with
win rate), full matches won, shutouts, overturns, Chao Di made, best round
multiplier, biggest round, and total coins earned. They are saved with your
progress.

### Saved progress

Coins, vault coins, unlocks, equipped items, the mailbox claim, and the date of
the last daily reward are saved per player in the `TractorProgress_v1` DataStore
(`src/server/Persistence.luau`). Progress loads before the session goes live,
saves on leave, every 60 seconds if it changed, and at server shutdown. Lifetime stats are saved too. Saved data
is sanitized: unknown items, products, negative or non-numeric balances, and
equipped items the player does not own are dropped. If loading fails, the player
is told and that session is never saved, so an outage cannot overwrite progress.

Saving only works in a **published** place. In Studio: File → Publish to Roblox,
then Game Settings → Security → **Enable Studio Access to API Services**, then
Play. Otherwise the balance shows **⚠ NOT SAVING**, a one-time popup gives the
exact reason, and Output logs `[Tractor] Progress saving is OFF`. Opening a fresh
`dist/Tractor.rbxlx` creates an unpublished copy, so to keep saving while
iterating, open the published place and sync scripts into it (for example with
Rojo and `roblox/default.project.json`) or republish over the same game.
Shutdown waits up to 25 seconds for in-flight saves. Saves are last-writer-wins: there is no
cross-server session lock, so a player in two servers at once could lose the
older session's changes. Quests, gift timers and lucky-wheel cooldowns are not
saved.

The bots use the website's deterministic legal baseline, not its trained
Expert/Champion or difficulty-specific advanced strategies. Private multiplayer,
replays, and training tools are outside the current scope. Existing
cosmetic/Robux UI is a prototype, not verified monetization.

## Tests

Use Node 24 and the repository's installed npm dependencies. Install/provide a
Lua 5.3+ interpreter or the Fengari CLI, then run:

```sh
npm run test:roblox -- /path/to/lua-or-fengari
```

This runs pure rules/state tests, real client and server handlers with service
doubles, viewport checks, and a cross-language parity suite. Expectations come
from the actual TypeScript rules, including twelve complete rounds across all
supported player counts. Generated fixtures stay in ignored `roblox/dist/`.
The runner checks completion markers because Fengari may report Lua assertion
errors without a nonzero process status.

For visual layout approximations using local Chrome and existing Playwright:

```sh
node roblox/tests/preview.mjs /path/to/lua-or-fengari
```

Previews in `roblox/dist/previews/` render the actual LocalScript's instance tree
through service doubles. They are **not Studio screenshots** and do not verify
Roblox font rendering, transport, safe insets, or actual touch interactions.

## Studio checklist before publishing

- Start each player count; verify random level, seat layout, and private hands.
- With API access enabled, buy an item, leave, rejoin, and confirm coins/unlock
  persist; claim the daily reward, rejoin, and confirm it stays claimed.
- Play a Full Match through at least two rounds and confirm Next Round keeps the
  table and levels.
- Declare during dealing; verify unavailable cards cannot declare. Test stronger
  declarations, joker takeover, and fallback's additional eight-second window.
- Pick up and bury the kitty as dealer; verify the required count (8/6/8/10).
- Lead a pair, a tractor, and a successful/failed gamble. Check returned cards,
  penalty signs, count/suit/structure errors, and the authoritative winner.
- Follow partial tractors and mixed gambles, including mandatory available pairs.
- Finish a hand; verify kitty multiplier, adjusted defender score, Quick Match
  winner, and exactly one +20 coin award. Start a fresh Quick Match.
- Check Hint, Clear, autoplay, keyboard input outside chat, Next Trick, and History.
- Confirm restart replaces a hand only after confirmation; stale requests cannot
  change the replacement game.
- Use phone/tablet emulation, including ten players and a full dealer hand.
- Test reactions, cooldown, mute, and cosmetic controls with two Studio clients.

For Rojo, `default.project.json` maps the same source; provide a baseplate and spawn
in that place. The standalone builder supplies both. Generated places are ignored
by git; edit the source rather than treating generated place edits as canonical.

Visual references: `frontend/src/GameTable.tsx`, `frontend/src/game-table.css`, and
[Happy Shengji screenshots](https://www.mydown.com/game/324/725709324.shtml).
Full-screen behavior follows [Roblox ScreenInsets](https://create.roblox.com/docs/reference/engine/enums/ScreenInsets).
