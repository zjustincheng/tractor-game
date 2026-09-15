import { cardIdentity, category, effectivePower } from './cards.js';
import type { Card, Trump } from './cards.js';
import { homogeneousStructure } from './structures.js';
import type { Structure } from './structures.js';

export interface Component extends Structure {
  readonly cards: readonly Card[];
}

export type Shape = Pick<Structure, 'multiplicity' | 'rankCount'>;

export function sameShape(a: Shape, b: Shape): boolean {
  return a.multiplicity === b.multiplicity && a.rankCount === b.rankCount;
}

export function withoutCards(
  cards: readonly Card[],
  removed: readonly Card[],
): Card[] {
  const ids = new Set(removed.map((card) => card.id));
  return cards.filter((card) => !ids.has(card.id));
}

export function identityGroups(cards: readonly Card[]): Card[][] {
  const groups = new Map<string, Card[]>();
  for (const card of cards) {
    const key = cardIdentity(card);
    const group = groups.get(key) ?? [];
    group.push(card);
    groups.set(key, group);
  }
  return [...groups.values()].map((group) =>
    group.sort((a, b) => compareText(a.id, b.id)),
  );
}

function compareText(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

export function componentKey(component: Component): string {
  return component.cards
    .map((card) => card.id)
    .sort()
    .join('|');
}

/** Largest first; equal size prefers multiplicity, power, then stable physical IDs. */
export function compareComponents(a: Component, b: Component): number {
  return (
    b.cardCount - a.cardCount ||
    b.multiplicity - a.multiplicity ||
    b.highestPower - a.highestPower ||
    compareText(componentKey(a), componentKey(b))
  );
}

/** Enumerate structures inside a single category, including structures cut from larger sets. */
export function availableComponents(
  cards: readonly Card[],
  trump: Trump,
  shape?: Shape,
): Component[] {
  if (cards.length === 0) return [];
  const groups = identityGroups(cards);
  const result: Component[] = [];
  const maxMultiplicity = Math.max(...groups.map((group) => group.length));
  const add = (chosen: readonly Card[]) => {
    const structure = homogeneousStructure(chosen, trump);
    if (structure && (!shape || sameShape(structure, shape)))
      result.push({ ...structure, cards: [...chosen] });
  };

  for (
    let multiplicity = shape?.multiplicity ?? 1;
    multiplicity <= (shape?.multiplicity ?? maxMultiplicity);
    multiplicity++
  ) {
    const eligible = groups.filter((group) => group.length >= multiplicity);
    const byPower = new Map<number, Card[][]>();
    for (const group of eligible) {
      const power = effectivePower(group[0]!, trump);
      const tier = byPower.get(power) ?? [];
      tier.push(group);
      byPower.set(power, tier);
      if (!shape || shape.rankCount === 1) add(group.slice(0, multiplicity));
    }
    if (multiplicity < 2 || shape?.rankCount === 1) continue;
    const extend = (
      chosen: Card[],
      power: number,
      groupCategory: string,
      ranks: number,
    ) => {
      if (!shape || ranks === shape.rankCount) {
        if (ranks >= 2) add(chosen);
      }
      if (shape && ranks >= shape.rankCount) return;
      for (const next of byPower.get(power + 1) ?? []) {
        if (category(next[0]!, trump) === groupCategory)
          extend(
            [...chosen, ...next.slice(0, multiplicity)],
            power + 1,
            groupCategory,
            ranks + 1,
          );
      }
    };
    for (const group of eligible)
      extend(
        group.slice(0, multiplicity),
        effectivePower(group[0]!, trump),
        category(group[0]!, trump),
        1,
      );
  }
  return result.sort(compareComponents);
}

/** Canonical grouping of a lead. Followers are partitioned against the lead's shapes. */
export function decomposeLead(
  cards: readonly Card[],
  trump: Trump,
): Component[] | null {
  const first = cards[0];
  if (
    !first ||
    new Set(cards.map((card) => card.id)).size !== cards.length ||
    cards.some((card) => category(card, trump) !== category(first, trump))
  )
    return null;
  let remaining = [...cards];
  const components: Component[] = [];
  while (remaining.length) {
    const component = availableComponents(remaining, trump)[0]!;
    components.push(component);
    remaining = withoutCards(remaining, component.cards);
  }
  return components;
}

/** Find disjoint components of the requested shapes. Larger source sets may be protected. */
export function matchComponents(
  cards: readonly Card[],
  shapes: readonly Shape[],
  trump: Trump,
  options: {
    protectLargerSets?: boolean;
    requireAllCards?: boolean;
    mustBeat?: readonly Component[];
  } = {},
): Component[] | null {
  const ordered = [...shapes].sort(
    (a, b) => b.multiplicity - a.multiplicity || b.rankCount - a.rankCount,
  );
  const needed = ordered.reduce(
    (sum, shape) => sum + shape.multiplicity * shape.rankCount,
    0,
  );
  if (
    needed > cards.length ||
    (options.requireAllCards && needed !== cards.length)
  )
    return null;
  const sourceCounts = new Map(
    identityGroups(cards).map((group) => [
      cardIdentity(group[0]!),
      group.length,
    ]),
  );
  const failed = new Set<string>();
  function search(
    remaining: readonly Card[],
    index: number,
    hasBeaten: boolean,
  ): Component[] | null {
    const shape = ordered[index];
    if (!shape) return !options.mustBeat || hasBeaten ? [] : null;
    const key = `${index}:${hasBeaten}:${remaining
      .map((card) => card.id)
      .sort()
      .join('|')}`;
    if (failed.has(key)) return null;
    const candidates = availableComponents(remaining, trump, shape);
    for (const candidate of candidates) {
      if (
        options.protectLargerSets &&
        shape.multiplicity > 1 &&
        candidate.cards.some(
          (card) => sourceCounts.get(cardIdentity(card))! > shape.multiplicity,
        )
      )
        continue;
      const beats =
        options.mustBeat?.some(
          (current) =>
            sameShape(candidate, current) &&
            (candidate.category === current.category
              ? candidate.highestPower > current.highestPower
              : candidate.category === 'trump'),
        ) ?? false;
      const rest = search(
        withoutCards(remaining, candidate.cards),
        index + 1,
        hasBeaten || beats,
      );
      if (rest) return [candidate, ...rest];
    }
    failed.add(key);
    return null;
  }
  return search(cards, 0, false);
}
