# Roblox Tractor remake roadmap

This is a presentation and interaction remake of the Roblox client. The rules,
server validation, and Tencent-style quick-match economy remain authoritative;
the client is being rebuilt as a coherent Roblox-native game rather than a set
of incremental overlays.

## Passes

1. **Foundation** — one visual language for buttons, cards, panels, typography,
   highlights, and sound feedback. Every screen should share the same outline,
   spacing, and accent hierarchy.
2. **Front door** — remake the mode-selection lobby, queue state, player count,
   and quick-match flow around a clear featured action and readable table cards.
3. **Table** — rebuild the match HUD, player plates, coins, declaration strip,
   hand, bottom-card interaction, and turn feedback for phone and desktop sizes.
4. **Learning and retention** — replace text-heavy help with diagrams, improve
   rewards/shop presentation, and make daily rewards and emotes feel collectible.
5. **Social and audio** — finish targeted chat, declaration cards over profiles,
   emotes, music, and restrained action feedback.
6. **Verification** — run the native Studio smoke flow for lobby → queue → table
   → declaration → Chao Di → rewards, capture screenshots, and remove regressions.

## Acceptance bar

- No random Roblox profile images in mode selection.
- No legacy `NT` declaration state; jokers and suits are explicit controls.
- Chao Di never exposes an editable bottom hand after the declaration window.
- A declaration is visible above the declaring player's profile.
- Coin totals, quick-match stake settlement, and player counts remain accurate.
- Every visible screen uses the shared foundation helpers and works at the tested
  16:9 and narrow viewport layouts.
