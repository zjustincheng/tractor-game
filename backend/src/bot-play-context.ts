import { teamAt } from '@tractor/rules';
import type { BotPlayContext, TrickState } from '@tractor/rules';

/** Only public trick information is exposed to a following policy. */
export function botPlayContext(
  trick: TrickState,
  dealerSeat?: number,
): BotPlayContext {
  const seat = trick.nextSeat!;
  const played = new Set(trick.plays.map((play) => play.seat));
  return {
    seat,
    winnerSeat: trick.winnerSeat!,
    winning: trick.plays.find((play) => play.seat === trick.winnerSeat)!
      .components!,
    lastToPlay: trick.plays.length === trick.playerCount - 1,
    trickPoints: trick.trickPoints,
    opponentsRemaining: Array.from(
      { length: trick.playerCount },
      (_, index) => index,
    ).filter(
      (index) =>
        index !== seat && !played.has(index) && teamAt(index) !== teamAt(seat),
    ).length,
    ...(dealerSeat === undefined ? {} : { dealerSeat }),
  };
}
