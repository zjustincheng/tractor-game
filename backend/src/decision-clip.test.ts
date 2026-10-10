import { expect, it } from 'vitest';
import { decisionClip } from './decision-clip.js';
import { newBotMatch } from './bot-match.js';
import type { BotMatch } from './bot-match.js';
import { seededRandom } from './training/self-play.js';

it('recovers a mislabeled seat from physical cards and refuses a mismatched action', () => {
  const match = newBotMatch(4, 0, seededRandom(1));
  const cards = match.state.hands.map((hand) => hand.slice(0, 1));
  match.history = [
    {
      round: 1,
      number: 1,
      trump: { level: '2', suit: 'clubs' },
      winnerSeat: 3,
      points: 0,
      defenderPoints: 0,
      penalty: 0,
      plays: cards.map((cards, seat) => ({ seat, cards, matchesLead: true })),
    },
  ];
  const sample: NonNullable<BotMatch['playtest']>['samples'][number] = {
    id: 'sample',
    seat: 1,
    kind: 'follow',
    round: 1,
    trick: 1,
    experience: {
      chosen: 0,
      options: [
        { cardIds: cards[3]!.map((c) => c.id), features: [], prior: 0 },
      ],
    },
  };
  expect(decisionClip(match, sample)).toMatchObject({
    seat: 3,
    seatCorrected: true,
    decisionIndex: 3,
    hand: null,
  });
  match.replay!.deals = [{ ...match.replay!.deals[0]!, hands: cards }];
  match.rounds = [
    {
      round: 1,
      settlement: {
        defenderScore: 0,
        kittyBasePoints: 0,
        kittyMultiplier: 1,
        kittyPoints: 0,
        outcome: { advancingRole: 'attackers', levels: 1, swapRoles: false },
        levels: { A: 'A', B: '2' },
        attackingTeam: 'A',
        rolesSwapped: false,
        jackReset: false,
        winner: 'A',
      },
    },
  ];
  expect(decisionClip(match, sample)?.hand).toHaveLength(1);
  match.history.push(match.history[0]!);
  expect(decisionClip(match, sample)).toBeNull();
  match.history.pop();
  sample.kind = 'lead';
  expect(decisionClip(match, sample)).toBeNull();
  sample.kind = 'follow';
  sample.experience.options[0]!.cardIds = ['missing'];
  expect(decisionClip(match, sample)).toBeNull();
});
