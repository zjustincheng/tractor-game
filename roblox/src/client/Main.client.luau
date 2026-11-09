-- Happy Tractor client entry point.
--
-- The interface lives in the ModuleScripts under UI and runs in the order
-- below (the same order as the original single script). Each module is a
-- function that receives one shared table, C:
--   * values that never change after they are created (helpers, frames,
--     palettes) are exported once as C.name and copied into locals by the
--     modules that use them;
--   * values that change while playing (state, busy, selectedIds, render,
--     updateAction…) are always read and written as C.name, so every module
--     sees the same current value.
-- A module may only use values exported by modules earlier in the list.
local ui = script.Parent:WaitForChild('UI')
local C = { folder = script.Parent }
for _, name in ipairs({
  'Core',           -- services, palette, UI helpers, sounds, shared state
  'Arena',          -- table felt, placards, seats, stats, reaction module
  'Lobby',          -- home screen, squad lobby, invites, tier screen
  'Actions',        -- settlement dialog, play/bury/Chao Di/Double commands
  'ReactionDock',   -- quick chat and reaction sheet, history panel
  'ShopRewards',    -- card backs, shop, rewards
  'Queue',          -- matchmaking / waiting room modal
  'Modals',         -- settings, rules lesson, mail, lucky wheel, vault
  'CatalogRows',    -- shop item rows
  'CoinShop',       -- Coins & VIP tab: VIP banner and coin pack cards
  'ShopGrid',       -- Emotes, Card Backs and Felts tabs: rarity tiles
  'TableReactions', -- throwing reactions and speech bubbles between seats
  'Hand',           -- card faces and the player's hand
  'Layout',         -- action bar state and responsive layout (resize)
  'Polish',         -- restyles home and tier screens; wraps resize
  'Render',         -- drawing the table from the latest game state
  'Events',         -- server messages, keyboard input, timers
  'Tutorial',       -- first-time How to Play slides and coach tips
  'HighStakes',     -- High Stakes switch on the tier screen (bigger rooms)
  'Leaderboard',    -- global richest-players leaderboard (🏆 button)
  'Profile',        -- player profile page and cosmetics (avatar in the home header)
  'Tracker',        -- VIP markers: cards safe to gamble, suits opponents are out of
  'BattlePass',     -- seasonal XP, free and premium reward tracks
}) do
  require(ui:WaitForChild(name))(C)
end
