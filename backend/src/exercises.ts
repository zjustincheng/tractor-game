import {
  category,
  createDeck,
  playCards,
  RULES_VERSION,
  startTrick,
  teamAt,
} from '@tractor/rules';
import type {
  Card,
  PlayerCount,
  Rank,
  Suit,
  TrickState,
  Trump,
} from '@tractor/rules';
import { exerciseViewSchema } from '@tractor/protocol';

export const exerciseSummaries = [
  {
    id: 'follow-a-pair',
    title: 'Keep the pair together',
    description:
      'You cannot match the whole tractor. Follow with the pair you do have.',
  },
  {
    id: 'use-both-pairs',
    title: 'Two pairs still matter',
    description:
      'Nonconsecutive pairs cannot beat a tractor, but both pairs must be played.',
  },
  {
    id: 'protect-your-triple',
    title: 'Save your triple',
    description:
      'Follow a pair without breaking your triple when other suited cards suffice.',
  },
  {
    id: 'match-the-tractor',
    title: 'A stronger tractor',
    description:
      'When you can match the complete tractor, you must. Can you take the trick?',
  },
  {
    id: 'trump-the-gamble',
    title: 'Trump the whole play',
    description:
      'A pair and a single are on the table. Match both components with trump.',
  },
  {
    id: 'trump-needs-a-match',
    title: 'Four trump cards are not enough',
    description:
      'A quad has the same card count as two consecutive pairs, but a different shape.',
  },
  {
    id: 'failed-gamble',
    title: 'Know when to throw',
    description:
      'Try the eight clubs together. A beatable component makes the gamble shrink.',
  },
] as const;

interface Exercise {
  id: string;
  title: string;
  description: string;
  tip: string;
  viewerSeat: number;
  state: TrickState;
}

/** These are fixed teaching positions, not bots or live rooms. Hidden hands stay on the server. */
export function buildExercise(id: string): Exercise | null {
  const summary = exerciseSummaries.find((item) => item.id === id);
  if (!summary) return null;
  const players: PlayerCount =
    id === 'protect-your-triple' || id === 'failed-gamble'
      ? 6
      : id === 'trump-needs-a-match'
        ? 8
        : 4;
  const trump: Trump = { level: '2', suit: 'spades' };
  let pool = createDeck(players);
  const take = (ranks: string, suit: Suit = 'clubs') =>
    ranks.split(' ').map((rank) => {
      const card = pool.find(
        (item) =>
          item.kind === 'suited' &&
          item.rank === (rank as Rank) &&
          item.suit === suit,
      );
      if (!card)
        throw new Error(
          `Exercise requests an unavailable physical card: ${rank} ${suit}`,
        );
      pool = pool.filter((item) => item.id !== card.id);
      return card;
    });
  const filler = (count: number) => {
    const cards = pool
      .filter((card) => !['clubs', 'trump'].includes(category(card, trump)))
      .slice(0, count);
    if (cards.length !== count)
      throw new Error('Exercise has insufficient filler cards.');
    const ids = new Set(cards.map((card) => card.id));
    pool = pool.filter((card) => !ids.has(card.id));
    return cards;
  };

  if (id === 'failed-gamble') {
    const yourHand = [...take('3 3 3 4 4 4 5 5'), ...take('A', 'hearts')];
    const beatingPair = take('6 6');
    const hands = Array.from({ length: players }, (_, seat) =>
      seat === 0
        ? yourHand
        : seat === 2
          ? [...beatingPair, ...filler(7)]
          : filler(9),
    );
    return {
      ...summary,
      viewerSeat: 0,
      tip: 'Select all eight clubs. The original card count changes if the gamble fails.',
      state: startTrick({
        playerCount: players,
        trump,
        attackingTeam: 'A',
        leaderSeat: 0,
        hands,
      }),
    };
  }

  let lead: Card[];
  let yourHand: Card[];
  let tip: string;
  switch (id) {
    case 'follow-a-pair':
      lead = take('3 3 4 4');
      yourHand = take('6 6 7 9 J');
      tip =
        'Choose both sixes and any two other clubs. A partial structure follows but cannot win.';
      break;
    case 'use-both-pairs':
      lead = take('8 8 9 9');
      yourHand = take('3 3 5 5 7');
      tip =
        'Both threes and both fives are required, even though they are not consecutive.';
      break;
    case 'protect-your-triple':
      lead = take('8 8');
      yourHand = take('6 6 6 7 9');
      tip =
        'Seven and nine are a legal follow. You may keep the triple intact.';
      break;
    case 'match-the-tractor':
      lead = take('6 6 7 7');
      yourHand = take('8 8 9 9 J');
      tip =
        'Select both eights and both nines to follow with a higher tractor.';
      break;
    case 'trump-the-gamble':
      lead = take('K K A');
      yourHand = take('Q Q A 3', 'spades');
      tip =
        'You are void in clubs. A trump pair plus a trump single matches the whole lead.';
      break;
    case 'trump-needs-a-match':
      lead = take('8 8 9 9');
      yourHand = [...take('A A A A', 'spades'), ...take('3', 'hearts')];
      tip =
        'Try the four aces. They are legal to discard while void in clubs, but cannot beat a pair tractor.';
      break;
    default:
      throw new Error('Missing exercise definition.');
  }
  const hands = Array.from({ length: players }, (_, seat) =>
    seat === players - 1
      ? yourHand
      : seat === 0
        ? [...lead, ...filler(yourHand.length - lead.length)]
        : filler(yourHand.length),
  );
  let state = startTrick({
    playerCount: players,
    trump,
    attackingTeam: 'A',
    leaderSeat: 0,
    hands,
  });
  for (let seat = 0; seat < players - 1; seat++) {
    const result = playCards(
      state,
      seat,
      state.hands[seat]!.slice(0, lead.length).map((card) => card.id),
    );
    if (!result.ok || result.reduced)
      throw new Error('Invalid prerecorded exercise position.');
    state = result.state;
  }
  return { ...summary, tip, viewerSeat: players - 1, state };
}

export function exerciseView(exercise: Exercise, state = exercise.state) {
  return exerciseViewSchema.parse({
    id: exercise.id,
    title: exercise.title,
    description: exercise.description,
    tip: exercise.tip,
    rulesVersion: RULES_VERSION,
    settings: {
      playerCount: state.playerCount,
      level: state.trump.level,
      trumpSuit: state.trump.suit,
    },
    viewerSeat: exercise.viewerSeat,
    attackingTeam: state.attackingTeam,
    hand: state.hands[exercise.viewerSeat],
    seats: state.hands.map((hand, seat) => ({
      seat,
      team: teamAt(seat),
      cardCount: hand.length,
    })),
    plays: state.plays.map(({ seat, cards, matchesLead }) => ({
      seat,
      cards,
      matchesLead,
    })),
    nextSeat: state.nextSeat,
    winnerSeat: state.winnerSeat,
    status: state.status,
    penaltyPoints: state.penaltyPoints,
    capturedDefenderPoints: state.capturedDefenderPoints,
    trickPoints: state.trickPoints,
  });
}
