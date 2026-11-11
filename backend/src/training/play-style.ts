import {
  cardPoints,
  category,
  effectivePower,
  validateFollow,
  winningComponents,
  teamAt,
} from '@tractor/rules';
import type {
  BotLeadContext,
  BotPlayContext,
  Card,
  Component,
  Trump,
} from '@tractor/rules';

/**
 * Play-style rules from reviewing the champion's games. Each flaw is a position
 * a human reviewer called a mistake; the guards replace that move and teach the
 * learner why. Only models with the v12 inputs use the guards.
 */
export type LeadFlaw =
  'big-trump-no-plan' | 'pair-before-ace' | 'big-joker-lead';
export type FollowFlaw = 'joker-waste' | 'barely-beat';
type Option = { cardIds: readonly string[] };

/** "A lot of points on the line" for the barely-beat rule. */
export const CONTESTED_TRICK_POINTS = 10;
const SMALL_CARD_POWER = 7;
const ENDGAME_CARDS = 4;

const selected = (hand: readonly Card[], ids: readonly string[]) =>
  hand.filter((card) => ids.includes(card.id));
const power = (cards: readonly Card[], trump: Trump) =>
  cards.reduce((sum, card) => sum + effectivePower(card, trump), 0);
const hasBigJoker = (cards: readonly Card[]) =>
  cards.some((card) => card.kind === 'joker' && card.joker === 'big');
const hasJoker = (cards: readonly Card[]) =>
  cards.some((card) => card.kind === 'joker');

export function isHighTrumpSingle(cards: readonly Card[], trump: Trump) {
  const card = cards[0];
  return (
    cards.length === 1 &&
    !!card &&
    category(card, trump) === 'trump' &&
    (card.kind === 'joker' || card.rank === trump.level)
  );
}
export function isSideAce(cards: readonly Card[], trump: Trump) {
  return cards.every(
    (card) =>
      card.kind === 'suited' &&
      card.rank === 'A' &&
      category(card, trump) !== 'trump',
  );
}
/** A cheap single offered up in the hope a teammate can take the trick. */
export function isSmallProbe(cards: readonly Card[], trump: Trump) {
  const card = cards[0];
  return (
    cards.length === 1 &&
    !!card &&
    card.kind === 'suited' &&
    card.rank !== trump.level &&
    cardPoints(card) === 0 &&
    effectivePower(card, trump) <= SMALL_CARD_POWER
  );
}
export function isSidePairWithoutAce(cards: readonly Card[], trump: Trump) {
  const first = cards[0];
  return (
    cards.length >= 2 &&
    !!first &&
    first.kind === 'suited' &&
    category(first, trump) !== 'trump' &&
    cards.every((card) => card.kind === 'suited' && card.rank === first.rank) &&
    first.rank !== 'A'
  );
}

/** Aces an opponent is known to ruff are not safe to cash. */
function safeAceOptions(
  hand: readonly Card[],
  trump: Trump,
  options: readonly Option[],
  context: BotLeadContext,
): number[] {
  const seat = context.seat ?? 0;
  const result: number[] = [];
  options.forEach((option, index) => {
    const cards = selected(hand, option.cardIds);
    if (!cards.length || !isSideAce(cards, trump)) return;
    const suit = category(cards[0]!, trump);
    const ruffed = (context.knownVoids ?? []).some(
      (entry) => entry.category === suit && teamAt(entry.seat) !== teamAt(seat),
    );
    if (!ruffed) result.push(index);
  });
  return result;
}

/** Measured over 128 matches: forcing an ace from another suit first cost about
 * 1.4 levels a match against Sharp; the same-suit rule cost nothing. */
function sameSuitAces(
  hand: readonly Card[],
  trump: Trump,
  pair: readonly Card[],
  options: readonly Option[],
  aces: readonly number[],
): number[] {
  const suit = category(pair[0]!, trump);
  return aces.filter(
    (index) =>
      category(selected(hand, options[index]!.cardIds)[0]!, trump) === suit,
  );
}

export function leadFlaw(
  hand: readonly Card[],
  trump: Trump,
  chosen: readonly string[],
  options: readonly Option[],
  context: BotLeadContext,
): LeadFlaw | null {
  const cards = selected(hand, chosen);
  const aces = safeAceOptions(hand, trump, options, context);
  if (
    isSidePairWithoutAce(cards, trump) &&
    sameSuitAces(hand, trump, cards, options, aces).length
  )
    return 'pair-before-ace';
  // The big joker is a trick-winner to hold back, except at the very end.
  if (
    cards.length === 1 &&
    hasBigJoker(cards) &&
    hand.length > ENDGAME_CARDS &&
    options.length > 1
  )
    return 'big-joker-lead';
  if (
    !isHighTrumpSingle(cards, trump) ||
    aces.length ||
    hand.length <= ENDGAME_CARDS
  )
    return null;
  const sets = options.some((option) => option.cardIds.length >= 2);
  const probe = options.some((option) =>
    isSmallProbe(selected(hand, option.cardIds), trump),
  );
  return !sets && probe ? 'big-trump-no-plan' : null;
}

/** Index of the replacement lead, or -1. `preference` is the model's opinion. */
export function leadGuard(
  hand: readonly Card[],
  trump: Trump,
  chosen: readonly string[],
  options: readonly Option[],
  context: BotLeadContext,
  preference: readonly number[],
): number {
  const flaw = leadFlaw(hand, trump, chosen, options, context);
  if (!flaw) return -1;
  if (flaw === 'big-joker-lead') {
    const others = options.flatMap((option, index) =>
      hasBigJoker(selected(hand, option.cardIds)) ? [] : [index],
    );
    return others.reduce(
      (best, index) =>
        best < 0 || preference[index]! > preference[best]! ? index : best,
      -1,
    );
  }
  const candidates =
    flaw === 'pair-before-ace'
      ? sameSuitAces(
          hand,
          trump,
          selected(hand, chosen),
          options,
          safeAceOptions(hand, trump, options, context),
        )
      : options.flatMap((option, index) =>
          isSmallProbe(selected(hand, option.cardIds), trump) ? [index] : [],
        );
  return candidates.reduce(
    (best, index) =>
      best < 0 || preference[index]! > preference[best]! ? index : best,
    -1,
  );
}

interface FollowSummary {
  index: number;
  cards: Card[];
  wins: boolean;
  big: boolean;
  joker: boolean;
  power: number;
}
export function summarizeFollows(
  hand: readonly Card[],
  lead: readonly Component[],
  trump: Trump,
  context: BotPlayContext,
  options: readonly Option[],
): FollowSummary[] {
  return options.map((option, index) => {
    const cards = selected(hand, option.cardIds);
    const follow = validateFollow(hand, cards, lead, trump);
    return {
      index,
      cards,
      wins:
        follow.legal &&
        follow.matchesLead &&
        winningComponents(cards, lead, context.winning, trump, {
          largestPatternWins: context.largestPatternWins === true,
        }) !== null,
      big: hasBigJoker(cards),
      joker: hasJoker(cards),
      power: power(cards, trump),
    };
  });
}

const contested = (context: BotPlayContext) =>
  (context.trickPoints ?? 0) >= CONTESTED_TRICK_POINTS &&
  (context.opponentsRemaining ?? Number(!context.lastToPlay)) > 0;

export function followFlaw(
  context: BotPlayContext,
  chosen: FollowSummary,
  all: readonly FollowSummary[],
): FollowFlaw | null {
  const partner = teamAt(context.seat) === teamAt(context.winnerSeat);
  if (chosen.big && all.some((option) => !option.big)) {
    const cheaperWinner = all.some((option) => option.wins && !option.big);
    const worthlessTrick = (context.trickPoints ?? 0) < CONTESTED_TRICK_POINTS;
    if (partner || !chosen.wins || cheaperWinner || worthlessTrick)
      return 'joker-waste';
  }
  if (
    !partner &&
    chosen.wins &&
    !chosen.joker &&
    contested(context) &&
    all.some(
      (option) => option.wins && !option.joker && option.power > chosen.power,
    )
  )
    return 'barely-beat';
  return null;
}

/** Index of the replacement follow, or -1. */
export function followGuard(
  context: BotPlayContext,
  chosenIndex: number,
  all: readonly FollowSummary[],
  preference: readonly number[],
): number {
  const chosen = all[chosenIndex]!;
  const flaw = followFlaw(context, chosen, all);
  if (!flaw) return -1;
  const partner = teamAt(context.seat) === teamAt(context.winnerSeat);
  const strongest = (list: readonly FollowSummary[]) =>
    list.reduce((best, option) => (option.power > best.power ? option : best))
      .index;
  const preferred = (list: readonly FollowSummary[]) =>
    list.reduce((best, option) =>
      preference[option.index]! > preference[best.index]! ? option : best,
    ).index;
  if (flaw === 'barely-beat')
    return strongest(all.filter((option) => option.wins && !option.joker));
  const noBig = all.filter((option) => !option.big);
  const winners = noBig.filter((option) => option.wins);
  if (!partner && winners.length)
    return contested(context) ? strongest(winners) : preferred(winners);
  return preferred(noBig);
}
