import { category, createDeck, shuffle } from './cards.js';
import type { Card, PlayerCount, Trump } from './cards.js';

export interface DealBelief {
  playerCount: PlayerCount;
  seat: number;
  ownHand: readonly Card[];
  seenCards: readonly Card[];
  handSizes: readonly number[];
  trump: Trump;
  knownVoids: readonly { seat: number; category: string }[];
  knownKitty?: readonly Card[];
  /** A dealer may have buried an exposed declaration card. */
  exposedCards?: readonly {
    cardId: string;
    seat: number;
    mayBeBuried: boolean;
  }[];
}

/** Randomized bipartite matching: never relax knowledge to fill a hand.
 * Returns null for contradictory observations. Samples are feasible, not a
 * uniform posterior over deals or an inference of opponents' strategy. */
export function samplePossibleDeal(
  input: DealBelief,
  pick: (max: number) => number,
): { hands: Card[][]; kitty: Card[] } | null {
  const deck = createDeck(input.playerCount);
  if (
    !Number.isInteger(input.seat) ||
    input.seat < 0 ||
    input.seat >= input.playerCount ||
    input.handSizes.length !== input.playerCount
  )
    return null;
  const removed = new Set(
    [...input.ownHand, ...input.seenCards, ...(input.knownKitty ?? [])].map(
      (c) => c.id,
    ),
  );
  if (
    removed.size !==
    input.ownHand.length +
      input.seenCards.length +
      (input.knownKitty?.length ?? 0)
  )
    return null;
  if ([...removed].some((id) => !deck.some((c) => c.id === id))) return null;
  const unknown = shuffle(
    deck.filter((c) => !removed.has(c.id)),
    pick,
  );
  const slots: number[] = [];
  for (let seat = 0; seat < input.playerCount; seat++) {
    const size = input.handSizes[seat];
    if (size === undefined || !Number.isInteger(size) || size < 0) return null;
    if (seat === input.seat) {
      if (size !== input.ownHand.length) return null;
    } else slots.push(...Array<number>(size).fill(seat));
  }
  const kittySize = unknown.length - slots.length;
  if (kittySize < 0 || (input.knownKitty && kittySize !== 0)) return null;
  slots.push(...Array<number>(kittySize).fill(-1));
  const eligible = (card: Card, seat: number) => {
    if (
      seat !== -1 &&
      input.knownVoids.some(
        (v) => v.seat === seat && v.category === category(card, input.trump),
      )
    )
      return false;
    return (input.exposedCards ?? [])
      .filter((e) => e.cardId === card.id)
      .every((e) => seat === e.seat || (seat === -1 && e.mayBeBuried));
  };
  if (
    input.ownHand.some((c) => !eligible(c, input.seat)) ||
    input.knownKitty?.some((c) => !eligible(c, -1))
  )
    return null;
  const choices = unknown.map((c) =>
    shuffle(
      slots.flatMap((seat, slot) => (eligible(c, seat) ? [slot] : [])),
      pick,
    ),
  );
  const assigned = Array<number>(slots.length).fill(-1);
  function place(card: number, visited: Set<number>): boolean {
    for (const slot of choices[card]!) {
      if (visited.has(slot)) continue;
      visited.add(slot);
      if (assigned[slot] === -1 || place(assigned[slot]!, visited)) {
        assigned[slot] = card;
        return true;
      }
    }
    return false;
  }
  for (let i = 0; i < unknown.length; i++)
    if (!place(i, new Set())) return null;
  const hands = Array.from({ length: input.playerCount }, () => [] as Card[]);
  hands[input.seat] = [...input.ownHand];
  const kitty = [...(input.knownKitty ?? [])];
  assigned.forEach((card, slot) =>
    (slots[slot] === -1 ? kitty : hands[slots[slot]!]!).push(unknown[card]!),
  );
  return { hands, kitty };
}
