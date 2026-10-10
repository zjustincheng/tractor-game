import type { BotMatchView } from '@tractor/protocol';

export interface SavedBotMatch {
  id: string;
  round: number | null;
  completed: boolean;
}
const key = 'tractor-saved-bot-matches';
const validId =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** Only keep session IDs already available to this browser. */
export function savedBotMatches(): SavedBotMatch[] {
  let items: SavedBotMatch[] = [];
  try {
    const parsed: unknown = JSON.parse(localStorage.getItem(key) ?? '[]');
    if (Array.isArray(parsed))
      items = parsed.filter(
        (item): item is SavedBotMatch =>
          item &&
          typeof item.id === 'string' &&
          validId.test(item.id) &&
          (item.round === null ||
            (Number.isSafeInteger(item.round) && item.round > 0)) &&
          typeof item.completed === 'boolean',
      );
  } catch {
    /* Recover the old single-match bookmark even if the list is damaged. */
  }
  try {
    const current = localStorage.getItem('tractor-bot-match');
    if (
      current &&
      validId.test(current) &&
      !items.some((item) => item.id === current)
    )
      items.unshift({ id: current, round: null, completed: false });
  } catch {
    /* Browsing still works without local storage. */
  }
  return items
    .filter(
      (item, index) =>
        items.findIndex((other) => other.id === item.id) === index,
    )
    .slice(0, 30);
}

export function rememberBotMatch(view: BotMatchView): SavedBotMatch[] {
  const entries = savedBotMatches().filter((item) => item.id !== view.id);
  const previous = view.playtest?.previousPlaytestId;
  if (previous && !entries.some((item) => item.id === previous))
    entries.push({ id: previous, round: null, completed: true });
  const next = [
    {
      id: view.id,
      round: view.round,
      completed: Boolean(view.settlement?.winner),
    },
    ...entries,
  ].slice(0, 30);
  try {
    localStorage.setItem(key, JSON.stringify(next));
    localStorage.setItem('tractor-bot-match', view.id);
  } catch {
    /* Keep the current navigation available in memory. */
  }
  return next;
}
