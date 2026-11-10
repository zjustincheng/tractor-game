import {
  availableComponents,
  winningComponents,
  cardIdentity,
  cardPoints,
  category,
  chooseBotLead,
  chooseBotPlay,
  chooseBotDeclaration,
  chooseBotBurial,
  validateFollow,
  effectivePower,
  teamAt,
} from '@tractor/rules';
import { robloxBurial } from './roblox-bot.js';
import type {
  BotLeadContext,
  BotPlayContext,
  Card,
  Component,
  Declaration,
  Trump,
} from '@tractor/rules';
import {
  CONTESTED_TRICK_POINTS,
  followGuard,
  isHighTrumpSingle,
  isSidePairWithoutAce,
  isSideAce,
  isSmallProbe,
  leadGuard,
  summarizeFollows,
} from './play-style.js';

export type LeadPolicy = (
  hand: readonly Card[],
  trump: Trump,
  context: BotLeadContext,
) => string[];
export const POLICY_VERSION = 'contextual-leads-v12-play-style';
export const INPUTS = 33;
/** Models with fewer inputs are earlier champions; they keep their old play. */
const STYLE_INPUTS = 33;
export const HIDDEN = 16;
/**
 * L2 norm of one generation's parameter update. Constant, so the policy keeps
 * moving once the gradient is small; variance reduction is the real remedy.
 *
 * The heuristic choice starts with a modest score advantage. This protects
 * early play while allowing learned features to override it after repeated
 * outcome evidence.
 */
export const POLICY_STEP_SIZE = 0.2;
// The handcrafted action is a starting point, not a veto. A large barrier
// made a policy-gradient learner look busy while its greedy decisions never
// changed, even after paired rollouts found better alternatives.
export const BASELINE_PRIOR = 0.35;
/**
 * Softmax temperature for practice play. At 1 the prior gap of 2 left the
 * heuristic move only ~45% of a ten-option lead, so practice was mostly random
 * legal moves and its win/loss signal said little about the policy. Below 1 the
 * learner plays competently and explores around the heuristic instead of
 * replacing it. Greedy evaluation is unaffected: argmax ignores temperature.
 */
export const EXPLORATION_TEMPERATURE = 0.15;
/** Same strength as the ace guard: a nudge beside the outcome signal. */
const STYLE_TEACHER_WEIGHT = 0.05;
export interface PolicyModel {
  input: number[][];
  bias: number[];
  output: number[];
  /** Effective score bonus for the handcrafted baseline action. */
  priorScale: number;
}
export interface LeadOption {
  cardIds: string[];
  features: number[];
  prior: number;
}
export interface PolicyExperience {
  options: LeadOption[];
  chosen: number;
  teacherIndex?: number;
  /** Auxiliary target strength for an offline counterfactual teacher. */
  teacherWeight?: number;
  advantage?: number;
  comparisons?: { better: number; worse: number; weight: number }[];
  /** Temperature this action was sampled at; the gradient must use the same
   * distribution, or the update is off-policy. Defaults to 1. */
  temperature?: number;
}
export type PlayPolicy = (
  hand: readonly Card[],
  lead: readonly Component[],
  trump: Trump,
  context: BotPlayContext,
) => string[];

/** The output layer must start non-zero. Every input and bias gradient in
 * accumulatePolicyGradient is multiplied by model.output[h], so an all-zero
 * output layer freezes the hidden layer at its random initialisation forever. */
export function newPolicy(pick: (max: number) => number): PolicyModel {
  return {
    input: Array.from({ length: HIDDEN }, () =>
      Array.from({ length: INPUTS }, () => (pick(20001) / 10000 - 1) * 0.25),
    ),
    bias: Array(HIDDEN).fill(0),
    output: Array.from(
      { length: HIDDEN },
      () => (pick(20001) / 10000 - 1) * 0.1,
    ),
    priorScale: BASELINE_PRIOR,
  };
}

export function parsePolicy(value: unknown): PolicyModel {
  const model = value as PolicyModel | null;
  const vector = (value: unknown, size: number): value is number[] =>
    Array.isArray(value) &&
    value.length === size &&
    value.every(
      (n) => typeof n === 'number' && Number.isFinite(n) && Math.abs(n) <= 20,
    );
  if (
    !model ||
    !Array.isArray(model.input) ||
    model.input.length !== HIDDEN ||
    ![22, 30, INPUTS].some((size) =>
      model.input.every((row) => vector(row, size)),
    ) ||
    !vector(model.bias, HIDDEN) ||
    !vector(model.output, HIDDEN)
  )
    throw new Error('Invalid learned policy dimensions or coefficients');
  if (
    model.priorScale !== undefined &&
    (typeof model.priorScale !== 'number' ||
      !Number.isFinite(model.priorScale) ||
      model.priorScale < 0 ||
      model.priorScale > 20)
  )
    throw new Error('Invalid learned policy prior scale');
  return {
    input: model.input.map((row) => [
      ...row,
      ...Array(INPUTS - row.length).fill(0),
    ]),
    bias: [...model.bias],
    output: [...model.output],
    priorScale: model.priorScale ?? BASELINE_PRIOR,
  };
}

/** All single-category structures, including smaller structures cut from larger ones.
 * No named strategy filter and no opponents' cards are supplied to the policy. */
export function leadOptions(
  hand: readonly Card[],
  trump: Trump,
  context: BotLeadContext,
): LeadOption[] {
  const baseline = new Set(chooseBotLead(hand, trump, context));
  const handTrumps = hand.filter(
    (card) => category(card, trump) === 'trump',
  ).length;
  return availableComponents(hand, trump).map((component) => {
    const ids = new Set(component.cards.map((card) => card.id));
    const remaining = hand.filter((card) => !ids.has(card.id));
    const suitCards = hand.filter(
      (card) => category(card, trump) === component.category,
    );
    const remainingSuit = remaining.filter(
      (card) => category(card, trump) === component.category,
    );
    const beforeGroups = new Map<string, number>();
    const afterGroups = new Map<string, number>();
    for (const card of hand)
      beforeGroups.set(
        cardIdentity(card),
        (beforeGroups.get(cardIdentity(card)) ?? 0) + 1,
      );
    for (const card of remaining)
      afterGroups.set(
        cardIdentity(card),
        (afterGroups.get(cardIdentity(card)) ?? 0) + 1,
      );
    const brokenSets = [...beforeGroups].filter(
      ([key, size]) =>
        size >= 2 &&
        (afterGroups.get(key) ?? 0) > 0 &&
        afterGroups.get(key)! < size,
    ).length;
    const known = context.knownVoids ?? [];
    const voidCount = (ally: boolean) =>
      new Set(
        known
          .filter(
            (v) =>
              v.category === component.category &&
              v.seat !== context.seat &&
              (teamAt(v.seat) === teamAt(context.seat ?? 0)) === ally,
          )
          .map((v) => v.seat),
      ).size;
    const seen = (context.seenCards ?? []).filter(
      (card) => category(card, trump) === component.category,
    );
    const features = [
      hand.length / 30,
      handTrumps / hand.length,
      Number(context.role === 'attackers'),
      Math.min(2, context.defenderScore / context.swapThreshold),
      (context.playerCount ?? 4) / 10,
      component.cardCount / hand.length,
      component.multiplicity / 5,
      component.rankCount / 13,
      component.highestPower / 30,
      Number(component.category === 'trump'),
      component.cards.reduce((n, card) => n + cardPoints(card), 0) / 100,
      component.cards.filter(
        (card) => card.kind === 'joker' && card.joker === 'big',
      ).length / 5,
      component.cards.filter(
        (card) => card.kind === 'joker' && card.joker === 'small',
      ).length / 5,
      suitCards.length / hand.length,
      Number(remainingSuit.length === 0),
      brokenSets / 5,
      remaining.filter((card) => category(card, trump) === 'trump').length /
        hand.length,
      remaining.reduce((n, card) => n + cardPoints(card), 0) / 200,
      seen.length / 65,
      seen.filter(
        (card) => effectivePower(card, trump) >= component.highestPower,
      ).length / 20,
      voidCount(true) / 5,
      voidCount(false) / 5,
      Number(
        context.dealerSeat !== undefined && context.seat === context.dealerSeat,
      ),
      Number((context.seenCards ?? []).length === 0),
      Number(
        component.category !== 'trump' &&
          component.cards.every((c) => c.kind === 'suited' && c.rank === 'A'),
      ),
      Number(component.category !== 'trump' && remainingSuit.length === 0),
      Number(
        component.category === 'trump' &&
          component.highestPower ===
            Math.min(
              ...hand
                .filter((c) => category(c, trump) === 'trump')
                .map((c) => effectivePower(c, trump)),
            ),
      ),
      Number(component.category !== 'trump' && suitCards.length <= 2),
      Number(component.category !== 'trump' && voidCount(false) > 0),
      Number(
        component.category !== 'trump' &&
          component.highestPower ===
            Math.max(...suitCards.map((c) => effectivePower(c, trump))),
      ),
      Number(isHighTrumpSingle(component.cards, trump)),
      Number(
        isSidePairWithoutAce(component.cards, trump) &&
          hand.some(
            (card) => card.kind === 'suited' && isSideAce([card], trump),
          ),
      ),
      Number(isSmallProbe(component.cards, trump)),
    ];
    return {
      cardIds: [...ids],
      features,
      prior:
        ids.size === baseline.size && [...ids].every((id) => baseline.has(id))
          ? BASELINE_PRIOR
          : 0,
    };
  });
}

function hidden(model: PolicyModel, features: number[]): number[] {
  return model.input.map((row, i) =>
    Math.tanh(
      row.reduce(
        (sum, weight, j) => sum + weight * (features[j] ?? 0),
        model.bias[i]!,
      ),
    ),
  );
}

/** Learned score range before the handcrafted option prior is added. This is
 * diagnostic only: it measures whether the network can realistically overcome
 * BASELINE_PRIOR in the current observation. */
export function learnedLogitSpread(
  model: PolicyModel,
  options: readonly LeadOption[],
): number {
  if (options.length < 2) return 0;
  const scores = options.map((option) =>
    hidden(model, option.features).reduce(
      (sum, value, i) => sum + value * model.output[i]!,
      0,
    ),
  );
  return Math.max(...scores) - Math.min(...scores);
}

export function policyProbabilities(
  model: PolicyModel,
  options: LeadOption[],
  temperature = 1,
): number[] {
  // Use identical logits in practice and evaluation. Temperature changes
  // exploration, never the preferred action or the heuristic's score barrier.
  const prior = model.priorScale;
  if (!Number.isFinite(prior))
    throw new Error('Policy model is missing a valid prior scale');
  const scores = options.map((option) => {
    const baselineScore =
      option.prior > 0
        ? prior !== undefined && option.prior === BASELINE_PRIOR
          ? prior
          : option.prior
        : 0;
    return (
      hidden(model, option.features).reduce(
        (sum, value, i) => sum + value * model.output[i]!,
        baselineScore,
      ) / Math.max(1e-6, temperature)
    );
  });
  const maximum = Math.max(...scores);
  const exps = scores.map((score) => Math.exp(score - maximum));
  const total = exps.reduce((sum, n) => sum + n, 0);
  return exps.map((n) => n / total);
}

export function choosePolicyLead(
  model: PolicyModel,
  hand: readonly Card[],
  trump: Trump,
  context: BotLeadContext,
  pick?: (max: number) => number,
  record?: (experience: PolicyExperience) => void,
): string[] {
  const options = leadOptions(hand, trump, context);
  const temperature = pick ? EXPLORATION_TEMPERATURE : 1;
  const probabilities = policyProbabilities(model, options, temperature);
  let chosen = probabilities.indexOf(Math.max(...probabilities));
  if (pick) {
    const draw = pick(0x100000000) / 0x100000000;
    let cumulative = 0;
    chosen = options.length - 1;
    for (let i = 0; i < probabilities.length; i++) {
      cumulative += probabilities[i]!;
      if (draw < cumulative) {
        chosen = i;
        break;
      }
    }
  }
  const styleGuard =
    model.input[0]!.length >= STYLE_INPUTS
      ? leadGuard(
          hand,
          trump,
          options[chosen]!.cardIds,
          options,
          context,
          probabilities,
        )
      : -1;
  if (styleGuard >= 0) chosen = styleGuard;
  const teacherIndex = options.findIndex((option) => option.prior > 0);
  record?.({
    options,
    chosen,
    temperature,
    ...(styleGuard >= 0
      ? { teacherIndex: styleGuard, teacherWeight: STYLE_TEACHER_WEIGHT }
      : context.beliefSearch && teacherIndex >= 0
        ? { teacherIndex }
        : {}),
  });
  return options[chosen]!.cardIds;
}

export function playOptions(
  hand: readonly Card[],
  lead: readonly Component[],
  trump: Trump,
  context: Parameters<PlayPolicy>[3],
  structuredAlternatives = true,
): LeadOption[] {
  const baseline = chooseBotPlay(hand, lead, trump, context);
  const candidates = [baseline];
  // Offer alternative complete structures as well as singleton responses.
  // validateFollow enforces suit and structure obligations before scoring.
  const count = lead.reduce((sum, component) => sum + component.cardCount, 0);
  if (!structuredAlternatives) {
    if (lead.length === 1 && count === 1)
      for (const card of hand)
        if (validateFollow(hand, [card], lead, trump).legal)
          candidates.push([card.id]);
  } else
    for (const component of availableComponents(hand, trump)) {
      if (
        component.cardCount === count &&
        validateFollow(hand, component.cards, lead, trump).legal
      )
        candidates.push(component.cards.map((card) => card.id));
    }
  const key = (ids: string[]) => [...ids].sort().join('|');
  const unique = new Map(candidates.map((ids) => [key(ids), ids]));
  const ledCategory = lead[0]!.category;
  const result: LeadOption[] = [...unique.values()].map((ids) => {
    const cards = hand.filter((card) => ids.includes(card.id));
    const legal = validateFollow(hand, cards, lead, trump);
    const matchesLead = legal.legal && legal.matchesLead;
    const points = cards.reduce((sum, card) => sum + cardPoints(card), 0);
    const power = cards.reduce(
      (sum, card) => sum + effectivePower(card, trump),
      0,
    );
    return {
      cardIds: ids,
      features: [
        0,
        hand.length / 30,
        Number(teamAt(context.seat) === teamAt(context.winnerSeat)),
        Number(context.lastToPlay),
        lead[0]!.cardCount / 4,
        Number(matchesLead),
        Number(category(cards[0]!, trump) === 'trump'),
        cards.length / 4,
        points / 30,
        power / 100,
        cards.filter((card) => card.kind === 'joker' && card.joker === 'big')
          .length / 2,
        cards.filter((card) => card.kind === 'joker' && card.joker === 'small')
          .length / 2,
        Number(ledCategory === 'trump'),
        Number(cards.some((card) => card.kind === 'joker')),
        Number(context.winning.length > 0),
        Number(key(ids) === key(baseline)),
        Number(cards.every((card) => category(card, trump) !== ledCategory)),
        Number(
          matchesLead &&
            winningComponents(cards, lead, context.winning, trump) !== null &&
            (context.trickPoints ?? 0) > 0 &&
            (context.opponentsRemaining ?? Number(!context.lastToPlay)) > 0 &&
            teamAt(context.seat) !== teamAt(context.winnerSeat),
        ) *
          ((context.trickPoints ?? 0) / 100) *
          ((context.opponentsRemaining ?? Number(!context.lastToPlay)) / 3),
        0,
        0,
        0,
        0,
        (context.trickPoints ??
          context.winning.reduce(
            (sum, component) =>
              sum +
              component.cards.reduce((n, card) => n + cardPoints(card), 0),
            0,
          )) / 100,
        Number(
          matchesLead &&
            winningComponents(cards, lead, context.winning, trump) !== null,
        ),
        (context.opponentsRemaining ?? Number(!context.lastToPlay)) / 5,
        Number(
          context.dealerSeat !== undefined &&
            context.seat === context.dealerSeat,
        ),
        Number(
          cards.every((c) => c.kind === 'suited' && c.rank === 'A') &&
            category(cards[0]!, trump) !== 'trump',
        ),
        (Number(
          matchesLead &&
            winningComponents(cards, lead, context.winning, trump) !== null,
        ) *
          (context.trickPoints ?? 0)) /
          100,
        (Number(teamAt(context.seat) === teamAt(context.winnerSeat)) * points) /
          30,
        Number(
          cards.every(
            (c) =>
              effectivePower(c, trump) ===
              Math.max(
                ...hand
                  .filter((h) => category(h, trump) === category(c, trump))
                  .map((h) => effectivePower(h, trump)),
              ),
          ),
        ),
      ],
      prior: key(ids) === key(baseline) ? BASELINE_PRIOR : 0,
    };
  });
  // Inputs that compare an option with the other legal options.
  const summaries = summarizeFollows(hand, lead, trump, context, result);
  const topOpponentPower = Math.max(
    ...context.winning.map((component) => component.highestPower),
    0,
  );
  const strongestPlain = Math.max(
    ...summaries.filter((s) => s.wins && !s.joker).map((s) => s.power),
    -Infinity,
  );
  const partnerWinning = teamAt(context.seat) === teamAt(context.winnerSeat);
  const hasPlainOption = summaries.some((s) => !s.big);
  for (const [index, summary] of summaries.entries()) {
    const cheaperWinner = summaries.some((s) => s.wins && !s.big);
    const highest = Math.max(
      ...summary.cards.map((card) => effectivePower(card, trump)),
    );
    result[index]!.features.push(
      Number(
        summary.big &&
          hasPlainOption &&
          (partnerWinning ||
            !summary.wins ||
            cheaperWinner ||
            (context.trickPoints ?? 0) < CONTESTED_TRICK_POINTS),
      ),
      summary.wins ? (highest - topOpponentPower) / 15 : 0,
      Number(
        summary.wins && !summary.joker && summary.power === strongestPlain,
      ),
    );
  }
  return result;
}

export function choosePolicyPlay(
  model: PolicyModel,
  hand: readonly Card[],
  lead: readonly Component[],
  trump: Trump,
  context: Parameters<PlayPolicy>[3],
  pick?: (max: number) => number,
  record?: (experience: PolicyExperience) => void,
): string[] {
  const options = playOptions(
    hand,
    lead,
    trump,
    context,
    model.input[0]!.length > 22,
  );
  const temperature = pick ? EXPLORATION_TEMPERATURE : 1;
  const probabilities = policyProbabilities(model, options, temperature);
  let chosen = probabilities.indexOf(Math.max(...probabilities));
  if (pick) {
    const draw = pick(0x100000000) / 0x100000000;
    let total = 0;
    chosen = options.length - 1;
    for (let i = 0; i < probabilities.length; i++) {
      total += probabilities[i]!;
      if (draw < total) {
        chosen = i;
        break;
      }
    }
  }
  // Do not donate a point trick when an ace can safely secure it. The learned
  // policy otherwise tends to select the weakest winning card, which lets the
  // next opponent overtake cheaply. This guard applies only while an opponent
  // remains, the partner is not already winning, and an ace is a legal winner.
  const aceProtection =
    (context.trickPoints ?? 0) > 0 &&
    (context.opponentsRemaining ?? Number(!context.lastToPlay)) > 0 &&
    options[chosen]?.features[2] === 0
      ? options.findIndex(
          (option) => option.features[23] === 1 && option.features[26] === 1,
        )
      : -1;
  if (aceProtection >= 0) chosen = aceProtection;
  const styleGuard =
    model.input[0]!.length >= STYLE_INPUTS
      ? followGuard(
          context,
          chosen,
          summarizeFollows(hand, lead, trump, context, options),
          probabilities,
        )
      : -1;
  if (styleGuard >= 0) chosen = styleGuard;
  const teacher = styleGuard >= 0 ? styleGuard : aceProtection;
  record?.({
    options,
    chosen,
    temperature,
    ...(teacher >= 0
      ? {
          teacherIndex: teacher,
          teacherWeight: styleGuard >= 0 ? STYLE_TEACHER_WEIGHT : 0.05,
        }
      : {}),
  });
  return options[chosen]!.cardIds;
}

export function choosePolicyDeclaration(
  model: PolicyModel,
  options: readonly Declaration[],
  hand: readonly Card[],
  level: Declaration['level'],
  pick?: (max: number) => number,
  record?: (experience: PolicyExperience) => void,
): Declaration | null {
  if (!options.length) return null;
  const baseline = chooseBotDeclaration(options, hand, level);
  const choices = [...options, null];
  const leadOptions: LeadOption[] = choices.map((option) => {
    if (!option)
      return {
        cardIds: [],
        prior: baseline === null ? BASELINE_PRIOR : 0,
        features: Array(INPUTS).fill(0),
      };
    const cards = hand.filter((card) => option.cardIds.includes(card.id));
    return {
      cardIds: [...option.cardIds],
      prior:
        baseline?.cardIds.join('|') === option.cardIds.join('|')
          ? BASELINE_PRIOR
          : 0,
      features: [
        0,
        hand.length / 30,
        Number(option.kind === 'joker'),
        option.multiplicity / 5,
        cards.length / 5,
        cards.reduce((sum, card) => sum + cardPoints(card), 0) / 30,
        cards.filter((card) => card.kind === 'joker').length / 5,
        Number(option.kind === 'suit'),
        Number(option.kind === 'joker' && option.joker === 'big'),
        Number(option.kind === 'joker' && option.joker === 'mixed'),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
    };
  });
  const temperature = pick ? EXPLORATION_TEMPERATURE : 1;
  const probabilities = policyProbabilities(model, leadOptions, temperature);
  let chosen = probabilities.indexOf(Math.max(...probabilities));
  if (pick) {
    const draw = pick(0x100000000) / 0x100000000;
    let sum = 0;
    for (let index = 0; index < probabilities.length; index++) {
      sum += probabilities[index]!;
      if (draw < sum) {
        chosen = index;
        break;
      }
    }
  }
  record?.({ options: leadOptions, chosen, temperature });
  return choices[chosen]!;
}

/** Burials offered under the Roblox rules. All of them keep trump and aim to
 * shorten suits; the Roblox bot's own choice comes first and is the baseline. */
export function robloxBurialChoices(
  cards: readonly Card[],
  size: number,
  trump: Trump,
): string[][] {
  const baseline = robloxBurial(cards, size, trump);
  const order = robloxBurial(cards, cards.length, trump);
  const byId = new Map(cards.map((card) => [card.id, card]));
  // Empty the shortest suits outright, then fall back to the Roblox order.
  const suits = new Map<string, string[]>();
  for (const id of order) {
    const group = category(byId.get(id)!, trump);
    if (group !== 'trump') suits.set(group, [...(suits.get(group) ?? []), id]);
  }
  const voiding: string[] = [];
  for (const suit of [...suits.values()].sort((a, b) => a.length - b.length))
    if (voiding.length + suit.length <= size) voiding.push(...suit);
  for (const id of order)
    if (voiding.length < size && !voiding.includes(id)) voiding.push(id);
  // The Roblox order, but point cards go only when nothing else is left.
  const savingPoints = [...order]
    .sort(
      (a, b) =>
        Number(category(byId.get(a)!, trump) === 'trump') -
          Number(category(byId.get(b)!, trump) === 'trump') ||
        Number(cardPoints(byId.get(a)!) > 0) -
          Number(cardPoints(byId.get(b)!) > 0),
    )
    .slice(0, size);
  return [baseline, voiding, savingPoints];
}
/** What a Roblox burial leaves behind, in the slots burial otherwise zeroes. */
function robloxBurialShape(
  cards: readonly Card[],
  selected: readonly Card[],
  trump: Trump,
): number[] {
  const kept = cards.filter((card) => !selected.includes(card));
  const lengths = (from: readonly Card[]) => {
    const counts = new Map<string, number>();
    for (const card of from) {
      const group = category(card, trump);
      if (group !== 'trump') counts.set(group, (counts.get(group) ?? 0) + 1);
    }
    return counts;
  };
  const before = lengths(cards);
  const after = lengths(kept);
  const identities = (from: readonly Card[]) => {
    const counts = new Map<string, number>();
    for (const card of from)
      counts.set(cardIdentity(card), (counts.get(cardIdentity(card)) ?? 0) + 1);
    return counts;
  };
  const remaining = identities(kept);
  const brokenPairs = [...identities(cards)].filter(
    ([identity, count]) => count >= 2 && (remaining.get(identity) ?? 0) === 1,
  ).length;
  return [
    (before.size - after.size) / 4,
    brokenPairs / Math.max(1, selected.length),
    after.size ? Math.min(...after.values()) / 13 : 0,
  ];
}

export function choosePolicyBurial(
  model: PolicyModel,
  cards: readonly Card[],
  size: number,
  trump: Trump,
  pick?: (max: number) => number,
  record?: (experience: PolicyExperience) => void,
  robloxRules = false,
): string[] {
  if (robloxRules) {
    const key = (ids: readonly string[]) => [...ids].sort().join('|');
    const choices = robloxBurialChoices(cards, size, trump);
    const options = [
      ...new Map(choices.map((ids) => [key(ids), ids])).values(),
    ].map((ids, index) => {
      const selected = cards.filter((card) => ids.includes(card.id));
      return {
        cardIds: ids,
        prior: index === 0 ? BASELINE_PRIOR : 0,
        features: [
          0,
          cards.length / 30,
          Number(selected.some((card) => category(card, trump) === 'trump')),
          selected.reduce((sum, card) => sum + cardPoints(card), 0) / 50,
          selected.reduce((sum, card) => sum + effectivePower(card, trump), 0) /
            100,
          selected.filter((card) => card.kind === 'joker').length / 2,
          Number(selected.some((card) => card.kind === 'joker')),
          ...robloxBurialShape(cards, selected, trump),
          ...Array<number>(13).fill(0),
        ],
      };
    });
    const temperature = pick ? EXPLORATION_TEMPERATURE : 1;
    const probabilities = policyProbabilities(model, options, temperature);
    let chosen = probabilities.indexOf(Math.max(...probabilities));
    if (pick) {
      const draw = pick(0x100000000) / 0x100000000;
      let sum = 0;
      for (let index = 0; index < probabilities.length; index++) {
        sum += probabilities[index]!;
        if (draw < sum) {
          chosen = index;
          break;
        }
      }
    }
    record?.({ options, chosen, temperature });
    return options[chosen]!.cardIds;
  }
  const baseline = chooseBotBurial(cards, size, trump);
  const pointSaving = cards
    .slice()
    .sort(
      (a, b) =>
        cardPoints(a) - cardPoints(b) ||
        effectivePower(a, trump) - effectivePower(b, trump),
    )
    .slice(0, size)
    .map((card) => card.id);
  const alternatives = [
    baseline,
    pointSaving,
    [...cards]
      .sort(
        (a, b) =>
          Number(category(a, trump) === 'trump') -
          Number(category(b, trump) === 'trump'),
      )
      .slice(0, size)
      .map((card) => card.id),
  ];
  const options = [
    ...new Map(alternatives.map((ids) => [ids.join('|'), ids])).values(),
  ].map((ids) => {
    const selected = cards.filter((card) => ids.includes(card.id));
    return {
      cardIds: ids,
      prior: ids.join('|') === baseline.join('|') ? BASELINE_PRIOR : 0,
      features: [
        0,
        cards.length / 30,
        Number(selected.some((card) => category(card, trump) === 'trump')),
        selected.reduce((sum, card) => sum + cardPoints(card), 0) / 50,
        selected.reduce((sum, card) => sum + effectivePower(card, trump), 0) /
          100,
        selected.filter((card) => card.kind === 'joker').length / 2,
        Number(selected.some((card) => card.kind === 'joker')),
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
    };
  });
  const temperature = pick ? EXPLORATION_TEMPERATURE : 1;
  const probabilities = policyProbabilities(model, options, temperature);
  let chosen = probabilities.indexOf(Math.max(...probabilities));
  if (pick) {
    const draw = pick(0x100000000) / 0x100000000;
    let sum = 0;
    for (let index = 0; index < probabilities.length; index++) {
      sum += probabilities[index]!;
      if (draw < sum) {
        chosen = index;
        break;
      }
    }
  }
  record?.({ options, chosen, temperature });
  return options[chosen]!.cardIds;
}

export function emptyGradient(): PolicyModel {
  return {
    input: Array.from({ length: HIDDEN }, () => Array(INPUTS).fill(0)),
    bias: Array(HIDDEN).fill(0),
    output: Array(HIDDEN).fill(0),
    priorScale: 0,
  };
}

/** Monte Carlo policy gradient: reward the sampled action relative to the
 * alternatives the SAME policy could have chosen in that same observation.
 * Each completed match has equal weight regardless of its number of leads. */
export function accumulatePolicyGradient(
  model: PolicyModel,
  experiences: PolicyExperience[],
  reward: number,
  gradient: PolicyModel,
): void {
  if (!experiences.length) return;
  for (const experience of experiences) {
    const probabilities = policyProbabilities(
      model,
      experience.options,
      experience.temperature ?? 1,
    );
    experience.options.forEach((option, index) => {
      const coefficient =
        ((experience.advantage ?? reward) *
          (Number(index === experience.chosen) - probabilities[index]!)) /
        (experiences.length * Math.max(1e-6, experience.temperature ?? 1));
      const activation = hidden(model, option.features);
      for (let h = 0; h < HIDDEN; h++) {
        gradient.output[h]! += coefficient * activation[h]!;
        const derivative =
          coefficient * model.output[h]! * (1 - activation[h]! ** 2);
        gradient.bias[h]! += derivative;
        for (let f = 0; f < INPUTS; f++)
          gradient.input[h]![f]! += derivative * (option.features[f] ?? 0);
      }
    });
  }
}

/** Distill a public-belief search choice into the policy without replacing
 * the match-outcome signal. This is deliberately a small auxiliary target. */
export function accumulateTeacherGradient(
  model: PolicyModel,
  experiences: PolicyExperience[],
  gradient: PolicyModel,
  weight = 0.25,
): void {
  const taught = experiences.filter(
    (experience) => experience.teacherIndex !== undefined,
  );
  for (const experience of taught) {
    const probabilities = policyProbabilities(model, experience.options);
    experience.options.forEach((option, index) => {
      const coefficient =
        (weight *
          (Number(index === experience.teacherIndex) - probabilities[index]!)) /
        taught.length;
      const activation = hidden(model, option.features);
      for (let h = 0; h < HIDDEN; h++) {
        gradient.output[h]! += coefficient * activation[h]!;
        const derivative =
          coefficient * model.output[h]! * (1 - activation[h]! ** 2);
        gradient.bias[h]! += derivative;
        for (let f = 0; f < INPUTS; f++)
          gradient.input[h]![f]! += derivative * (option.features[f] ?? 0);
      }
    });
  }
}

export function applyPolicyGradient(
  model: PolicyModel,
  gradient: PolicyModel,
  matches: number,
): PolicyModel {
  if (!matches) return parsePolicy(model);
  const values = [
    ...gradient.output,
    ...gradient.bias,
    ...gradient.input.flat(),
  ].map((n) => n / matches);
  const norm = Math.hypot(...values);
  // Fixed-size normalised step. Math.max(1, norm) was intended to cap the step
  // at POLICY_STEP_SIZE, but norm is always far below 1 here (each coefficient
  // is already divided by experiences.length), so it shrank a gradient that was
  // orders of magnitude too small to ever overcome LeadOption.prior.
  const scale = POLICY_STEP_SIZE / matches / Math.max(1e-8, norm);
  const update = (n: number, g: number) =>
    Math.max(-20, Math.min(20, n + g * scale));
  return {
    input: model.input.map((row, h) =>
      row.map((n, f) => update(n, gradient.input[h]![f]!)),
    ),
    bias: model.bias.map((n, h) => update(n, gradient.bias[h]!)),
    output: model.output.map((n, h) => update(n, gradient.output[h]!)),
    priorScale: model.priorScale,
  };
}
