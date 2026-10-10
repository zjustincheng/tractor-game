import type { BotMatch } from './bot-match.js';

/** Recover the actor from physical card IDs; old recordings mislabeled seats. */
export function decisionClip(
  match: BotMatch,
  sample: NonNullable<BotMatch['playtest']>['samples'][number],
) {
  if (sample.kind !== 'lead' && sample.kind !== 'follow') return null;
  const chosen = sample.experience.options[sample.experience.chosen]?.cardIds;
  if (
    !chosen?.length ||
    sample.round === undefined ||
    sample.trick === undefined
  )
    return null;
  const tricks = match.history.filter(
    (t) => t.round === sample.round && t.number === sample.trick,
  );
  if (tricks.length !== 1) return null;
  const trick = tricks[0]!;
  const matches = trick.plays.flatMap((play, index) =>
    play.cards.length === chosen.length &&
    play.cards.every((c) => chosen.includes(c.id)) &&
    (sample.kind === 'lead' ? index === 0 : index > 0)
      ? [index]
      : [],
  );
  if (matches.length !== 1) return null;
  const decisionIndex = matches[0]!;
  const seat = trick.plays[decisionIndex]!.seat;
  const label = (c: (typeof trick.plays)[number]['cards'][number]) =>
    c.kind === 'joker' ? `${c.joker} joker` : `${c.rank} ${c.suit}`;
  // A settled, complete round lets us recover this player's remaining cards.
  const remaining = match.history
    .filter((t) => t.round === sample.round && t.number >= sample.trick!)
    .flatMap((t) =>
      t.plays.filter((p) => p.seat === seat).flatMap((p) => p.cards),
    );
  const ids = new Set(remaining.map((c) => c.id));
  const roundHistory = match.history
    .filter((t) => t.round === sample.round)
    .sort((a, b) => a.number - b.number);
  const deal = match.replay?.deals.find((d) => d.round === sample.round);
  const complete =
    deal &&
    roundHistory.every(
      (t, i) => t.number === i + 1 && t.plays.length === deal.hands.length,
    ) &&
    roundHistory.flatMap((t) =>
      t.plays.filter((p) => p.seat === seat).flatMap((p) => p.cards),
    ).length === deal.hands[seat]?.length;
  const hand =
    complete &&
    match.rounds.some((r) => r.round === sample.round) &&
    ids.size === remaining.length &&
    sample.experience.options.every((o) => o.cardIds.every((id) => ids.has(id)))
      ? remaining.map(label).sort()
      : null;
  return {
    seatCorrected: seat !== sample.seat,
    decisionIndex,
    seat,
    hand,
    trump: `${trick.trump.level}${trick.trump.suit ? ` ${trick.trump.suit}` : ''}`,
    points: trick.points,
    winnerSeat: trick.winnerSeat,
    plays: trick.plays.map((p) => ({
      seat: p.seat,
      cards: p.cards.map(label),
    })),
  };
}
