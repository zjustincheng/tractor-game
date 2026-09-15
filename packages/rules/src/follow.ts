import { cardIdentity, category } from './cards.js';
import type { Card, Trump } from './cards.js';
import { identityGroups, matchComponents } from './components.js';
import type { Component } from './components.js';

export type FollowError =
  | 'WRONG_CARD_COUNT'
  | 'MUST_FOLLOW_SUIT'
  | 'MUST_MATCH_STRUCTURE'
  | 'MUST_PLAY_SETS';
export type FollowResult =
  | { legal: false; code: FollowError; message: string }
  | { legal: true; matchesLead: boolean; components: Component[] | null };

/** Count set obligations by descending multiplicity, reserving only the lead's set-card budget. */
function setProfile(
  cards: readonly Card[],
  lead: readonly Component[],
  protectLargerSets: boolean,
): number[] {
  const max = Math.max(...lead.map((component) => component.multiplicity));
  const groups = identityGroups(cards).map((group) => ({
    initial: group.length,
    left: group.length,
  }));
  const profile: number[] = [];
  let used = 0;
  for (let tier = max; tier >= 2; tier--) {
    const budget =
      lead
        .filter((component) => component.multiplicity >= tier)
        .reduce((sum, component) => sum + component.cardCount, 0) - used;
    let capacity = Math.floor(budget / tier);
    let count = 0;
    for (const group of groups) {
      if (protectLargerSets && group.initial > tier) continue;
      const take = Math.min(capacity, Math.floor(group.left / tier));
      group.left -= take * tier;
      capacity -= take;
      count += take;
    }
    used += count * tier;
    profile.push(count);
  }
  return profile;
}

/** Legal follow is separate from eligibility to win. Cards must already be resolved from the hand. */
export function validateFollow(
  hand: readonly Card[],
  played: readonly Card[],
  lead: readonly Component[],
  trump: Trump,
): FollowResult {
  const first = lead[0];
  if (!first) throw new Error('A follow requires a lead.');
  const count = lead.reduce((sum, component) => sum + component.cardCount, 0);
  if (played.length !== count)
    return {
      legal: false,
      code: 'WRONG_CARD_COUNT',
      message: `Play exactly ${count} cards.`,
    };
  // The public entry point also rejects duplicate IDs; keep standalone validation safe.
  const handById = new Map(hand.map((card) => [card.id, cardIdentity(card)]));
  if (
    new Set(played.map((card) => card.id)).size !== played.length ||
    played.some((card) => handById.get(card.id) !== cardIdentity(card))
  )
    throw new Error('Follow cards must belong to the hand without duplicates.');
  const suitedHand = hand.filter(
    (card) => category(card, trump) === first.category,
  );
  const suitedPlay = played.filter(
    (card) => category(card, trump) === first.category,
  );
  if (suitedPlay.length !== Math.min(suitedHand.length, count))
    return {
      legal: false,
      code: 'MUST_FOLLOW_SUIT',
      message: `Use ${Math.min(suitedHand.length, count)} cards from the led category before playing other cards.`,
    };

  const uniform = played.every(
    (card) => category(card, trump) === category(played[0]!, trump),
  );
  const components = uniform
    ? matchComponents(played, lead, trump, { requireAllCards: true })
    : null;
  if (suitedHand.length >= count) {
    const fullAvailable = matchComponents(suitedHand, lead, trump, {
      protectLargerSets: true,
    });
    if (fullAvailable && !components)
      return {
        legal: false,
        code: 'MUST_MATCH_STRUCTURE',
        message:
          'Your hand can match the complete led structure. Play a matching structure.',
      };
  }

  // Exhaustion already forces every suited card. Otherwise require all available unprotected sets.
  if (suitedHand.length > count && !components) {
    const required = setProfile(suitedHand, lead, true);
    const supplied = setProfile(suitedPlay, lead, false);
    for (let index = 0; index < required.length; index++) {
      if (supplied[index]! > required[index]!) break;
      if (supplied[index]! < required[index]!)
        return {
          legal: false,
          code: 'MUST_PLAY_SETS',
          message:
            'Include the available sets in the led category before filling with singles.',
        };
    }
  }

  const matchesLead =
    components !== null &&
    (category(played[0]!, trump) === first.category ||
      (suitedHand.length === 0 && category(played[0]!, trump) === 'trump'));
  return {
    legal: true,
    matchesLead,
    components: matchesLead ? components : null,
  };
}
