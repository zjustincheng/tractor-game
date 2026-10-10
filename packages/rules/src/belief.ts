import { category, createDeck } from './cards.js';
import type { Card, Category, PlayerCount, Trump } from './cards.js';
import { samplePossibleDeal } from './belief-deals.js';

export interface PublicBeliefInput {
  playerCount: PlayerCount;
  ownHand: readonly Card[];
  trump: Trump;
  seenCards?: readonly Card[] | undefined;
  knownVoids?: readonly { seat: number; category: string }[] | undefined;
  cardsRemaining?: number | undefined;
  /** Remaining hand size for each seat when sampling from the middle of a trick. */
  cardsRemainingBySeat?: readonly number[] | undefined;
  seat?: number;
}

/** Deterministically samples plausible hidden hands from public information. */
export function samplePossibleHands(
  input: PublicBeliefInput,
  samples = 4,
): Card[][][] {
  const handSize = Math.max(1, input.cardsRemaining ?? input.ownHand.length);
  let state = [...input.ownHand, ...(input.seenCards ?? [])].reduce(
    (hash, card) => {
      for (const char of card.id)
        hash = Math.imul(hash ^ char.charCodeAt(0), 16777619);
      return hash >>> 0;
    },
    2166136261,
  );
  const next = (max: number): number => {
    state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
    return Math.floor((state / 0x100000000) * max);
  };
  const result: Card[][][] = [];
  const seat = input.seat ?? 0;
  for (let i = 0; i < samples; i++) {
    const world = samplePossibleDeal(
      {
        playerCount: input.playerCount,
        seat,
        ownHand: input.ownHand,
        trump: input.trump,
        seenCards: input.seenCards ?? [],
        knownVoids: input.knownVoids ?? [],
        handSizes: Array.from({ length: input.playerCount }, (_, s) =>
          s === seat
            ? input.ownHand.length
            : (input.cardsRemainingBySeat?.[s] ?? handSize),
        ),
      },
      next,
    );
    if (!world) return [];
    result.push(world.hands);
  }
  return result;
}

/**
 * Public-only estimate of whether a seat can be void in a category. It treats
 * every still-unknown card as exchangeable and uses the hypergeometric-style
 * approximation 1-(1-p)^n. It never inspects another player's hand.
 */
export function estimateVoidProbability(
  input: PublicBeliefInput,
  seat: number,
  target: Category,
): number {
  if (
    input.knownVoids?.some(
      (value) => value.seat === seat && value.category === target,
    )
  )
    return 1;
  const removed = new Set(
    [...input.ownHand, ...(input.seenCards ?? [])].map((card) => card.id),
  );
  const unknown = createDeck(input.playerCount).filter(
    (card) => !removed.has(card.id),
  );
  if (!unknown.length) return 0;
  const categoryCount = unknown.filter(
    (card) => category(card, input.trump) === target,
  ).length;
  const handSize = Math.max(1, input.cardsRemaining ?? input.ownHand.length);
  const chanceOfCategory = categoryCount / unknown.length;
  return Math.max(0, Math.min(1, (1 - chanceOfCategory) ** handSize));
}

/** Estimated chance that a teammate can ruff a non-trump lead. */
export function estimatePartnerRuffProbability(
  input: PublicBeliefInput,
  seat: number,
  target: Category,
): number {
  if (target === 'trump') return 0;
  const partner = (seat + 2) % input.playerCount;
  return estimateVoidProbability(input, partner, target);
}
