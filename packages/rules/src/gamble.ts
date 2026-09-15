import { category, effectivePower } from './cards.js';
import type { Card, Trump } from './cards.js';
import {
  availableComponents,
  componentKey,
  matchComponents,
  sameShape,
  withoutCards,
} from './components.js';
import type { Component } from './components.js';
import { gamblePenalty } from './scoring.js';

export function validateGamble(
  components: readonly Component[],
  otherHands: readonly (readonly Card[])[],
  trump: Trump,
  role: 'attackers' | 'defenders',
) {
  const cards = components.flatMap((component) => component.cards);
  if (components.length < 2)
    return {
      reduced: false,
      components: [...components],
      cards,
      returned: [] as Card[],
      penalty: 0,
    };
  const beatable = components.filter((component) =>
    otherHands.some((hand) =>
      availableComponents(
        hand.filter((card) => category(card, trump) === component.category),
        trump,
        component,
      ).some((candidate) => candidate.highestPower > component.highestPower),
    ),
  );
  beatable.sort(
    (a, b) =>
      a.multiplicity - b.multiplicity ||
      a.highestPower - b.highestPower ||
      (componentKey(a) < componentKey(b)
        ? -1
        : componentKey(a) > componentKey(b)
          ? 1
          : 0),
  );
  const weakest = beatable[0];
  if (!weakest)
    return {
      reduced: false,
      components: [...components],
      cards,
      returned: [] as Card[],
      penalty: 0,
    };
  return {
    reduced: true,
    components: [weakest],
    cards: [...weakest.cards],
    returned: withoutCards(cards, weakest.cards),
    penalty: gamblePenalty(role),
  };
}

/** Compare only responses already matched to the entire lead. Any comparable component may beat. */
export function beatsPlay(
  challenger: readonly Component[],
  current: readonly Component[],
): boolean {
  const shapeKey = (component: Component) =>
    `${component.multiplicity}:${component.rankCount}`;
  if (
    challenger.length !== current.length ||
    challenger.map(shapeKey).sort().join('|') !==
      current.map(shapeKey).sort().join('|')
  )
    return false;
  const first = challenger[0];
  const previous = current[0];
  if (!first || !previous) return false;
  if (
    challenger.some((component) => component.category !== first.category) ||
    current.some((component) => component.category !== previous.category)
  )
    return false;
  if (first.category !== previous.category) return first.category === 'trump';
  const strengthKey = (component: Component) =>
    `${shapeKey(component)}:${component.highestPower}`;
  // Preserve the original identical-strength rule before testing cross-component beatability.
  if (
    challenger.map(strengthKey).sort().join('|') ===
    current.map(strengthKey).sort().join('|')
  )
    return false;
  return challenger.some((component) =>
    current.some(
      (incumbent) =>
        sameShape(component, incumbent) &&
        component.highestPower > incumbent.highestPower,
    ),
  );
}

/** An alternate disjoint partition may win even when the first matching partition does not. */
export function winningComponents(
  cards: readonly Card[],
  lead: readonly Component[],
  current: readonly Component[],
  trump: Trump,
): Component[] | null {
  const firstMatch = matchComponents(cards, lead, trump, {
    requireAllCards: true,
  });
  if (!firstMatch) return null;
  if (beatsPlay(firstMatch, current)) return firstMatch;
  const powers = (items: readonly Card[]) =>
    items
      .map((card) => `${category(card, trump)}:${effectivePower(card, trump)}`)
      .sort()
      .join('|');
  if (powers(cards) === powers(current.flatMap((component) => component.cards)))
    return null;
  return matchComponents(cards, lead, trump, {
    requireAllCards: true,
    mustBeat: current,
  });
}
