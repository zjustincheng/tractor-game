import { randomUUID } from 'node:crypto';
import { teamAt } from '@tractor/rules';
import type { PlayerCount } from '@tractor/rules';
import type { BotMatch } from '../bot-match.js';
import { botPlayContext } from '../bot-play-context.js';
import { reconstructMatch } from './match-learning.js';
import { choosePolicyLead, choosePolicyPlay } from './learned-policy.js';
import type { PolicyExperience } from './learned-policy.js';

/** Build teaching choices from validated historical decisions, without updates. */
export function reviewSamples(match: BotMatch) {
  const playtest = match.playtest;
  if (!playtest || !match.settlement?.winner) return [];
  const candidates: typeof playtest.samples = [];
  for (const round of reconstructMatch(match).rounds) {
    const history = match.history.filter((t) => t.round === round.round);
    round.positions.forEach((position, index) => {
      const { trick } = position;
      const seat = trick.nextSeat!;
      if (seat % 2 === 0) return;
      const recorded = history[Math.floor(index / trick.playerCount)]!;
      const actual = recorded.plays.find((p) => p.seat === seat)!.cards;
      const kind = trick.plays.length === 0 ? 'lead' : 'follow';
      const record = (experience: PolicyExperience) => {
        const chosen = experience.options.findIndex(
          (option) =>
            option.cardIds.length === actual.length &&
            actual.every((c) => option.cardIds.includes(c.id)),
        );
        if (chosen < 0 || experience.options.length < 2) return;
        candidates.push({
          id: randomUUID(),
          seat,
          kind,
          round: round.round,
          trick: recorded.number,
          experience: { ...experience, chosen },
        });
      };
      if (kind === 'lead')
        choosePolicyLead(
          playtest.models.lead,
          trick.hands[seat]!,
          trick.trump,
          {
            seat,
            playerCount: trick.playerCount as PlayerCount,
            cardsRemaining: trick.hands[seat]!.length,
            role:
              teamAt(seat) === trick.attackingTeam ? 'attackers' : 'defenders',
            defenderScore: position.captured,
            swapThreshold: trick.playerCount * 20,
            seenCards: position.seenCards,
            knownVoids: position.knownVoids,
            beliefSearch: false,
            ...(position.dealerSeat === undefined
              ? {}
              : { dealerSeat: position.dealerSeat }),
          },
          undefined,
          record,
        );
      else
        choosePolicyPlay(
          playtest.models.follow,
          trick.hands[seat]!,
          trick.plays[0]!.components!,
          trick.trump,
          botPlayContext(trick, position.dealerSeat),
          undefined,
          record,
        );
    });
  }
  // Spread a bounded deck across the recording, with both leads and follows.
  return (['lead', 'follow'] as const).flatMap((kind) => {
    const pool = candidates.filter((c) => c.kind === kind);
    const count = Math.min(48, pool.length);
    return Array.from(
      { length: count },
      (_, i) => pool[Math.floor((i * pool.length) / count)]!,
    );
  });
}
