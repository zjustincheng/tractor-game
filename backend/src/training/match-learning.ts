import { botPlayContext } from '../bot-play-context.js';
import { createHash } from 'node:crypto';
import { isDeepStrictEqual } from 'node:util';
import {
  category,
  compareComponents,
  createDeck,
  gameConfig,
  playCards,
  RULES_VERSION,
  settleRound,
  startTrick,
  teamAt,
} from '@tractor/rules';
import type { Card, PlayerCount } from '@tractor/rules';
import type { BotMatch } from '../bot-match.js';
import { compareAlternatives } from './counterfactual.js';
import { learnedBotPolicy } from './bot-policy.js';
import type { RoundPosition } from './counterfactual.js';
import {
  choosePolicyLead,
  choosePolicyPlay,
  policyProbabilities,
} from './learned-policy.js';
import type { PolicyExperience, PolicyModel } from './learned-policy.js';
import type { PolicyCheckpoint } from './policy-training.js';
import { newOptimizer, updateFromOutcomes } from './policy-update.js';
import { seededRandom } from './self-play.js';

export interface RecordedRound {
  round: number;
  key: string;
  positions: RoundPosition[];
}

/** Rebuild post-burial hands from every accepted play in a complete round.
 * Never guess missing cards or assign an old observation to a similar move. */
export function reconstructMatch(match: BotMatch) {
  const rounds: RecordedRound[] = [];
  const skipped: { round: number; reason: string }[] = [];
  // Older live matches hard-coded '2.1'; every recovered play is validated below.
  if (
    !match.replay ||
    ![RULES_VERSION, '2.1'].includes(match.replay.rulesVersion)
  )
    throw new Error('Missing or incompatible replay metadata');
  const lastCompleted = Math.max(0, ...match.rounds.map((r) => r.round));
  const completedRounds = new Set([
    ...match.rounds.map((r) => r.round),
    ...match.replay.deals
      .filter((d) => d.round <= lastCompleted)
      .map((d) => d.round),
  ]);
  for (const round of [...completedRounds].sort((a, b) => a - b)) {
    try {
      const deal = match.replay.deals.find((d) => d.round === round);
      const history = match.history.filter((t) => t.round === round);
      if (!deal || !history.length)
        throw new Error('Trick history was not retained');
      const config = gameConfig(deal.hands.length);
      const playerCount = config.playerCount;
      if (
        history.some(
          (t, i) => t.number !== i + 1 || t.plays.length !== playerCount,
        )
      )
        throw new Error('Incomplete trick history');
      // Failed throw attempts are not stored in CompletedTrick. Their timing
      // and returned cards cannot be reconstructed from accepted plays alone.
      if (history.some((t) => t.penalty !== 0))
        throw new Error('Failed throw context unavailable');
      // Opening declarations may move the dealer after the deal was recorded.
      const dealerSeat = history[0]!.plays[0]!.seat;
      const attackingTeam = teamAt(dealerSeat);
      const levels =
        round === 1
          ? { A: '2' as const, B: '2' as const }
          : match.rounds.find((r) => r.round === round - 1)?.settlement.levels;
      if (!levels) throw new Error('Previous round levels were not retained');
      const deck = createDeck(playerCount);
      const canonical = new Map(deck.map((c) => [c.id, c]));
      const card = (c: Card) => {
        const expected = canonical.get(c.id);
        if (
          !expected ||
          expected.kind !== c.kind ||
          (expected.kind === 'suited' &&
            c.kind === 'suited' &&
            (expected.rank !== c.rank || expected.suit !== c.suit)) ||
          (expected.kind === 'joker' &&
            c.kind === 'joker' &&
            expected.joker !== c.joker)
        )
          throw new Error('Invalid card identity');
        return expected;
      };
      const dealt = [...deal.hands.flat(), ...deal.kitty].map(card);
      if (
        dealt.length !== deck.length ||
        new Set(dealt.map((c) => c.id)).size !== deck.length
      )
        throw new Error('Incomplete or duplicate deal');
      const hands = Array.from({ length: playerCount }, (_, seat) =>
        history
          .flatMap((t) =>
            t.plays.filter((p) => p.seat === seat).flatMap((p) => p.cards),
          )
          .map(card),
      );
      const played = new Set(hands.flat().map((c) => c.id));
      if (
        hands.some((h) => h.length !== config.handSize) ||
        played.size !== config.handSize * playerCount
      )
        throw new Error('Incomplete or duplicate played cards');
      for (let seat = 0; seat < playerCount; seat++) {
        const originallyHeld = [
          ...deal.hands[seat]!,
          ...(seat === dealerSeat ? deal.kitty : []),
        ].map(card);
        const owned = new Set(originallyHeld.map((c) => c.id));
        if (hands[seat]!.some((c) => !owned.has(c.id)))
          throw new Error('Card ownership mismatch');
        // Retain deal order, never future play order, for candidate tie breaks.
        const kept = new Set(hands[seat]!.map((c) => c.id));
        hands[seat] = originallyHeld.filter((c) => kept.has(c.id));
      }
      const kitty = deck.filter((c) => !played.has(c.id));
      let trick = startTrick({
        playerCount,
        hands,
        trump: history[0]!.trump,
        attackingTeam,
        leaderSeat: dealerSeat,
      });
      let captured = 0;
      let seen: Card[] = [];
      const voids = new Map<string, { seat: number; category: string }>();
      const positions: RoundPosition[] = [];
      for (const recorded of history) {
        if (
          recorded.trump.level !== trick.trump.level ||
          recorded.trump.suit !== trick.trump.suit
        )
          throw new Error('Trump changed inside a round');
        for (const play of recorded.plays) {
          positions.push({
            trick,
            exposedCards: (deal.exposedCards ?? []).map((e) => ({
              ...e,
              mayBeBuried: e.seat === dealerSeat,
            })),
            levels,
            kitty,
            captured,
            penalties: 0,
            seenCards: seen,
            knownVoids: [...voids.values()],
            dealerSeat,
          });
          const result = playCards(
            trick,
            play.seat,
            play.cards.map((c) => c.id),
          );
          if (!result.ok || result.reduced)
            throw new Error('Recorded move failed legal replay');
          trick = result.state;
        }
        if (
          trick.winnerSeat !== recorded.winnerSeat ||
          trick.trickPoints !== recorded.points ||
          trick.capturedDefenderPoints !== recorded.defenderPoints
        )
          throw new Error('Replayed trick outcome differs');
        captured += trick.capturedDefenderPoints;
        seen = [...seen, ...trick.plays.flatMap((p) => p.cards)];
        const led = category(trick.plays[0]!.cards[0]!, trick.trump);
        for (const play of trick.plays)
          if (play.cards.some((c) => category(c, trick.trump) !== led))
            voids.set(`${play.seat}:${led}`, {
              seat: play.seat,
              category: led,
            });
        if (trick.hands[0]!.length)
          trick = startTrick({ ...trick, leaderSeat: trick.winnerSeat! });
      }
      if (trick.hands.some((h) => h.length))
        throw new Error('Round did not finish');
      const winning = trick.plays.find((p) => p.seat === trick.winnerSeat)!;
      const settlement = settleRound({
        playerCount,
        attackingTeam,
        levels,
        trickPoints: captured,
        gamblePenaltyPoints: 0,
        finalTrickWinnerTeam: teamAt(trick.winnerSeat!),
        finalWinningCards: winning.cards,
        finalWinningStructure: [...winning.components!].sort(
          compareComponents,
        )[0]!,
        kitty,
      });
      const expectedSettlement = match.rounds.find(
        (r) => r.round === round,
      )?.settlement;
      if (
        !expectedSettlement ||
        !isDeepStrictEqual(settlement, expectedSettlement)
      )
        throw new Error('Replayed round settlement differs');
      const key = createHash('sha256')
        .update(JSON.stringify({ deal, history, levels }))
        .digest('hex');
      rounds.push({ round, key, positions });
    } catch (error) {
      skipped.push({ round, reason: (error as Error).message });
    }
  }
  return { rounds, skipped };
}

/** Re-analyse archived positions with current-model candidates. The old moves
 * were greedy: no fabricated on-policy rewards from a match win or loss. */
export function learnRecordedRounds(
  checkpoint: PolicyCheckpoint,
  rounds: RecordedRound[],
  progress?: (round: RecordedRound, comparisons: number) => void,
) {
  const processed = new Set(checkpoint.learnedMatchRounds ?? []);
  const lead: PolicyExperience[] = [],
    follow: PolicyExperience[] = [];
  const counts = {
    rounds: 0,
    alreadyLearned: 0,
    positions: 0,
    rollouts: 0,
    comparisons: 0,
  };
  const pick = seededRandom(0x71ac70);
  for (const round of rounds) {
    if (processed.has(round.key)) {
      counts.alreadyLearned++;
      continue;
    }
    const before = counts.comparisons;
    for (const position of round.positions) {
      const { trick } = position;
      const seat = trick.nextSeat!;
      const hand = trick.hands[seat]!;
      let experience: PolicyExperience | undefined;
      const record = (e: PolicyExperience) => {
        experience = e;
      };
      const isLead = trick.plays.length === 0;
      if (isLead)
        choosePolicyLead(
          checkpoint.leadLearner,
          hand,
          trick.trump,
          {
            seat,
            playerCount: trick.playerCount as PlayerCount,
            cardsRemaining: hand.length,
            beliefSearch: false,
            role:
              teamAt(seat) === trick.attackingTeam ? 'attackers' : 'defenders',
            defenderScore: position.captured,
            swapThreshold: trick.playerCount * 20,
            seenCards: position.seenCards,
            knownVoids: position.knownVoids,
            ...(position.dealerSeat === undefined
              ? {}
              : { dealerSeat: position.dealerSeat }),
          },
          undefined,
          record,
        );
      else
        choosePolicyPlay(
          checkpoint.followLearner,
          hand,
          trick.plays[0]!.components!,
          trick.trump,
          botPlayContext(trick, position.dealerSeat),
          undefined,
          record,
        );
      if (!experience || experience.options.length < 2) continue;
      const result = compareAlternatives(
        position,
        experience,
        pick,
        4,
        learnedBotPolicy(checkpoint.leadLearner, checkpoint.followLearner),
      );
      // Follow decisions are the human-identified exploit. Their counterfactual
      // labels were previously diluted by the much larger lead sample. Give
      // exposed-point follow positions a stronger pairwise signal so the model
      // can learn to protect a valuable trick or overtake decisively.
      if (!isLead && experience.comparisons?.length) {
        const pointWeight = position.trick.trickPoints > 0 ? 4 : 2;
        experience.comparisons = experience.comparisons.map((pair) => ({
          ...pair,
          weight: Math.min(1, pair.weight * pointWeight),
        }));
        const best = experience.comparisons
          .slice()
          .sort((a, b) => b.weight - a.weight)[0];
        if (best && best.better !== experience.chosen) {
          experience.teacherIndex = best.better;
          experience.teacherWeight = position.trick.trickPoints > 0 ? 0.2 : 0.1;
        }
      }
      counts.positions++;
      counts.rollouts += result.rollouts;
      counts.comparisons += result.informativePairs;
      if (result.informativePairs) (isLead ? lead : follow).push(experience);
    }
    processed.add(round.key);
    counts.rounds++;
    progress?.(round, counts.comparisons - before);
  }
  // Reset optimizer moments: this is a new offline comparison objective.
  const leadUpdate = updateFromOutcomes(
    checkpoint.leadLearner,
    lead,
    newOptimizer(),
  );
  const followUpdate = updateFromOutcomes(
    checkpoint.followLearner,
    follow,
    newOptimizer(),
  );
  const updated: PolicyCheckpoint = {
    ...checkpoint,
    learner: leadUpdate.model,
    leadLearner: leadUpdate.model,
    followLearner: followUpdate.model,
    leadOptimizer: leadUpdate.optimizer,
    followOptimizer: followUpdate.optimizer,
    learnedMatchRounds: [...processed],
    championLevelMarginSamples: counts.rounds
      ? []
      : (checkpoint.championLevelMarginSamples ?? []),
    championMarginSamples: counts.rounds
      ? []
      : (checkpoint.championMarginSamples ?? []),
  };
  const changedChoices = (
    before: PolicyModel,
    after: PolicyModel,
    examples: PolicyExperience[],
  ) => {
    const choice = (model: PolicyModel, example: PolicyExperience) => {
      const p = policyProbabilities(model, example.options);
      return p.indexOf(Math.max(...p));
    };
    return examples.filter((e) => choice(before, e) !== choice(after, e))
      .length;
  };
  return {
    checkpoint: counts.rounds === 0 ? checkpoint : updated,
    report: {
      ...counts,
      leadExamples: lead.length,
      followExamples: follow.length,
      changedLeadChoices: changedChoices(
        checkpoint.leadLearner,
        leadUpdate.model,
        lead,
      ),
      changedFollowChoices: changedChoices(
        checkpoint.followLearner,
        followUpdate.model,
        follow,
      ),
      leadEpochs: leadUpdate.epochs,
      followEpochs: followUpdate.epochs,
      leadKL: leadUpdate.kl,
      followKL: followUpdate.kl,
    },
  };
}
