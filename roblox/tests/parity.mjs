// Generate expected results using the website's real TypeScript rules, then run Luau port checks.
// Usage: node --import tsx roblox/tests/parity.mjs /path/to/lua-or-fengari
import { createDeck, deal, shuffle } from '../../packages/rules/src/cards.ts';
import {
  decomposeLead,
  compareComponents,
} from '../../packages/rules/src/components.ts';
import { validateFollow } from '../../packages/rules/src/follow.ts';
import {
  validateGamble,
  winningComponents,
} from '../../packages/rules/src/gamble.ts';
import { homogeneousStructure } from '../../packages/rules/src/structures.ts';
import {
  startTrick,
  playCards,
  nextTrick,
} from '../../packages/rules/src/trick.ts';
import { declarationsForHand } from '../../packages/rules/src/declarations.ts';
import { chooseBotPlay } from '../../packages/rules/src/bot.ts';
import { settleRound } from '../../packages/rules/src/scoring.ts';
import {
  choosePolicyBurial,
  choosePolicyDeclaration,
  choosePolicyLead,
  choosePolicyPlay,
  leadOptions,
  newPolicy,
  playOptions,
} from '../../backend/src/training/learned-policy.ts';
import {
  robloxBurial,
  robloxFollow,
  robloxLead,
} from '../../backend/src/training/roblox-bot.ts';
import { botPlayContext } from '../../backend/src/bot-play-context.ts';
import { category, teamAt } from '../../packages/rules/src/cards.ts';
import { chooseBotBurial } from '../../packages/rules/src/bot.ts';
import {
  chaodiOptions,
  chooseRobloxChaodi,
} from '../../backend/src/training/roblox-rules.ts';
import { existsSync, readFileSync } from 'node:fs';
import { writeFile, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, URL } from 'node:url';
import process from 'node:process';
import console from 'node:console';
const root = fileURLToPath(new URL('../../', import.meta.url));
const out = fileURLToPath(
  new URL('../dist/parity-fixtures.lua', import.meta.url),
);
const lua = (v) => {
  if (v === null || v === undefined) return 'nil';
  if (typeof v === 'string')
    return (
      '"' +
      v
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n') +
      '"'
    );
  if (typeof v !== 'object') return String(v);
  if (Array.isArray(v)) return '{' + v.map(lua).join(',') + '}';
  return (
    '{' +
    Object.entries(v)
      .filter(([, value]) => value !== undefined && value !== null)
      .map(([key, value]) => `[${lua(key)}]=${lua(value)}`)
      .join(',') +
    '}'
  );
};
let seed = 731;
const pick = (n) => {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return seed % n;
};
let identity = 0;
const cards = (ranks, suit = 'clubs') =>
  ranks.map((rank) => ({
    id: `fixture:${++identity}`,
    kind: 'suited',
    rank,
    suit,
  }));
const trump = { level: '2', suit: 'spades' };
const fixtures = {
  declarations: [],
  structures: [],
  follows: [],
  gambles: [],
  winners: [],
  settlements: [],
  rounds: [],
};
function structure(hand, t = trump) {
  fixtures.structures.push({
    cards: hand,
    trump: t,
    expected: decomposeLead(hand, t),
  });
}
function follow(lead, hand, played, t = trump) {
  const components = decomposeLead(lead, t);
  const result = validateFollow(hand, played, components, t);
  fixtures.follows.push({
    hand,
    played,
    lead: components,
    trump: t,
    expected: result.legal
      ? { legal: true, matchesLead: result.matchesLead }
      : { legal: false, code: result.code },
  });
}
for (const ranks of [
  ['3'],
  ['3', '3'],
  ['3', '3', '4', '4'],
  ['3', '3', '3', '4', '4', '4'],
  ['3', '3', '3', '4', '4', '4', '5', '5'],
  ['3', '4', '5'],
  ['J', 'J', 'Q', 'Q', 'K', 'K'],
])
  structure(cards(ranks));
structure([...cards(['5'], 'clubs'), ...cards(['5'], 'hearts')], {
  level: '5',
  suit: 'spades',
});
structure([...cards(['3'], 'clubs'), ...cards(['3'], 'hearts')]);
const pair = cards(['3', '3']);
const tractor = cards(['3', '3', '4', '4']);
for (const [ranks, indices, lead] of [
  [['6', '6', '7', '9', 'J'], [0, 2, 3, 4], tractor],
  [['6', '6', '7', '9', 'J'], [0, 1, 2, 3], tractor],
  [['3', '3', '5', '5', '7'], [0, 1, 2, 4], tractor],
  [['3', '3', '5', '5', '7'], [0, 1, 2, 3], tractor],
  [['6', '6', '6', '7', '9'], [3, 4], pair],
  [['6', '6', '6'], [0, 1], pair],
  [['6', '6', '7', '7', '9'], [0, 1, 2, 4], tractor],
  [['6', '6', '7', '7', '9'], [0, 1, 2, 3], tractor],
]) {
  const hand = cards(ranks);
  follow(
    lead,
    hand,
    indices.map((i) => hand[i]),
  );
}
const throwCards = cards(['3', '3', '3', '4', '4', '4', '5', '5']);
for (const role of ['attackers', 'defenders']) {
  const components = decomposeLead(throwCards, trump),
    otherHands = [cards(['6', '6'])];
  fixtures.gambles.push({
    components,
    otherHands,
    trump,
    role,
    expected: validateGamble(components, otherHands, trump, role),
  });
}
const gambleLead = decomposeLead(cards(['3', '3', '5']), trump);
for (const [previous, challenger] of [
  [
    ['K', 'K', '3'],
    ['Q', 'Q', 'A'],
  ],
  [
    ['K', 'K', '3'],
    ['K', 'K', '3'],
  ],
]) {
  const current = decomposeLead(cards(previous, 'spades'), trump),
    hand = cards(challenger, 'spades');
  fixtures.winners.push({
    cards: hand,
    lead: gambleLead,
    current,
    trump,
    expected: winningComponents(hand, gambleLead, current, trump),
  });
}
const twoPairs = decomposeLead(cards(['4', '4', 'K', 'K'], 'spades'), trump);
const challenger = cards(['5', '5', 'Q', 'Q'], 'spades');
fixtures.winners.push({
  cards: challenger,
  lead: twoPairs,
  current: twoPairs,
  trump,
  expected: winningComponents(challenger, twoPairs, twoPairs, trump),
});
// Random category samples exercise decomposition and legal/illegal partial follows.
for (let i = 0; i < 140; i++) {
  const t = {
    level: ['2', '5', 'J', 'A'][i % 4],
    suit: i % 5 === 4 ? null : ['clubs', 'diamonds', 'hearts', 'spades'][i % 4],
  };
  const shoe = shuffle(createDeck([4, 6, 8, 10][i % 4]), pick);
  const hand = shoe.slice(0, 14);
  structure(
    hand.filter((c) => c.kind === 'suited' && c.suit === 'clubs'),
    t,
  );
  const leadCards = shoe
    .slice(14)
    .filter((c) => c.kind === 'suited' && c.suit === 'clubs')
    .slice(0, 1 + (i % 6));
  const lead = decomposeLead(leadCards, t);
  if (!lead) continue;
  const ids = chooseBotPlay(hand, lead, t);
  const played = ids.map((id) => hand.find((c) => c.id === id));
  follow(leadCards, hand, played, t);
  follow(leadCards, hand, hand.slice(0, played.length), t);
}
// Full seeded rounds. Commands include actual bot leads and attempted gambles.
for (const playerCount of [4, 6, 8, 10])
  for (let trial = 0; trial < 3; trial++) {
    const t = {
      level: ['2', '5', 'J'][trial],
      suit: trial === 2 ? null : 'spades',
    };
    const { hands, kitty } = deal(
      shuffle(createDeck(playerCount), pick),
      playerCount,
    );
    let state = startTrick({
      playerCount,
      trump: t,
      attackingTeam: 'A',
      leaderSeat: 0,
      hands,
    });
    const quickMatch = trial === 1;
    const record = {
      playerCount,
      quickMatch,
      trump: t,
      hands,
      kitty,
      commands: [],
    };
    const declarations = declarationsForHand(
      hands[0],
      playerCount,
      t.level,
      0,
    ).map((d) => ({
      seat: 1,
      suit: d.kind === 'suit' ? d.suit : undefined,
      joker: d.kind === 'joker' ? d.joker : undefined,
      count: d.multiplicity,
      cardIds: d.cardIds,
    }));
    fixtures.declarations.push({
      playerCount,
      trump: t,
      hands,
      expected: declarations,
    });
    const totals = [0, 0];
    let penalties = 0;
    while (state.status !== 'complete' || state.hands[0].length > 0) {
      const seat = state.nextSeat;
      let ids = chooseBotPlay(
        state.hands[seat],
        state.plays[0]?.components ?? null,
        t,
      );
      if (!state.plays.length && trial === 1) {
        const first = state.hands[seat][0];
        const group = state.hands[seat].filter(
          (c) =>
            c.kind === first.kind &&
            (c.kind === 'joker' || c.suit === first.suit),
        );
        const candidate = group.slice(0, Math.min(8, group.length));
        if (decomposeLead(candidate, t)) ids = candidate.map((c) => c.id);
      }
      const result = playCards(state, seat, ids);
      if (!result.ok) throw new Error(result.message);
      state = result.state;
      penalties += result.penalty;
      if (state.status === 'complete')
        totals[state.winnerSeat % 2] += state.trickPoints;
      record.commands.push({
        seat: seat + 1,
        ids,
        expected: {
          hands: state.hands.map((h) => h.map((c) => c.id)),
          winnerSeat: state.winnerSeat + 1,
          points: [...totals],
          penaltyPoints: penalties,
          reduced: result.reduced,
          played: state.plays.at(-1).cards.map((c) => c.id),
          complete: state.status === 'complete',
        },
      });
      if (state.status === 'complete') {
        if (state.hands[0].length === 0) {
          const winner = state.plays.find((p) => p.seat === state.winnerSeat);
          const input = {
            playerCount,
            attackingTeam: 'A',
            levels: { A: t.level, B: '2' },
            trickPoints: totals[1],
            finalTrickWinnerTeam: state.winnerSeat % 2 === 0 ? 'A' : 'B',
            finalWinningCards: winner.cards,
            finalWinningStructure: [...winner.components].sort(
              compareComponents,
            )[0],
            kitty,
            gamblePenaltyPoints: penalties,
          };
          record.settlement = settleRound(input);
          if (quickMatch)
            record.settlement.winner =
              record.settlement.outcome.advancingRole === 'attackers'
                ? 'A'
                : 'B';
        } else state = nextTrick(state);
      }
    }
    fixtures.rounds.push(record);
  }
for (const playerCount of [4, 6, 8, 10]) {
  const hand = createDeck(playerCount).filter(
    (c) => c.kind === 'joker' || (c.kind === 'suited' && c.rank === 'J'),
  );
  const declarations = declarationsForHand(hand, playerCount, 'J', 0).map(
    (d) => ({
      seat: 1,
      suit: d.kind === 'suit' ? d.suit : undefined,
      joker: d.kind === 'joker' ? d.joker : undefined,
      count: d.multiplicity,
      cardIds: d.cardIds,
    }),
  );
  fixtures.declarations.push({
    playerCount,
    trump: { level: 'J', suit: null },
    hands: [hand],
    expected: declarations,
  });
}
for (const playerCount of [4, 6, 8, 10])
  for (const score of [-20, 0, 10, 40, 60, 79, 80, 120, 160, 200, 360]) {
    const final = cards(['J', 'J'], 'spades');
    const input = {
      playerCount,
      attackingTeam: 'A',
      levels: { A: 'J', B: '10' },
      trickPoints: Math.max(0, score),
      gamblePenaltyPoints: Math.min(0, score),
      finalTrickWinnerTeam: 'B',
      finalWinningCards: final,
      finalWinningStructure: homogeneousStructure(final, {
        level: 'J',
        suit: 'spades',
      }),
      kitty: cards(['5', '10', 'K']),
    };
    fixtures.settlements.push({ input, expected: settleRound(input) });
  }
// Trained-bot port: every input, baseline flag and final choice must match the
// website, using random models and (when available locally) the real champion.
fixtures.policy = { leads: [], plays: [], declarations: [], burials: [] };

// Chao Di: the training port must offer and choose exactly what the game does.
fixtures.chaodi = [];
for (let i = 0; i < 160; i++) {
  const playerCount = [4, 6, 8, 10][i % 4];
  const level = ['2', '5', 'J'][i % 3];
  const { hands } = deal(shuffle(createDeck(playerCount), pick), playerCount);
  const hand = hands[0];
  const currents = [
    {
      kind: 'suit',
      playerSeat: 2,
      level,
      suit: 'hearts',
      multiplicity: 1,
      cardIds: [],
    },
    {
      kind: 'suit',
      playerSeat: 2,
      level,
      suit: 'diamonds',
      multiplicity: 2,
      cardIds: [],
    },
    {
      kind: 'joker',
      playerSeat: 2,
      level,
      joker: 'small',
      multiplicity: 2,
      cardIds: [],
    },
  ];
  const current = currents[i % 3];
  const trump = { level, suit: current.kind === 'suit' ? current.suit : null };
  const calls = chaodiOptions(hand, level, current, 0);
  for (const sameTeam of [true, false]) {
    const choice = chooseRobloxChaodi(calls, hand, trump, sameTeam);
    fixtures.chaodi.push({
      hand,
      playerCount,
      trump,
      current:
        current.kind === 'suit'
          ? { suit: current.suit, count: current.multiplicity }
          : { joker: current.joker, count: current.multiplicity },
      holder: sameTeam ? 3 : 2,
      expectedOptions: calls.map((call) => ({
        seat: 1,
        count: call.count,
        cardIds: call.cardIds,
        ...(call.suit ? { suit: call.suit } : { joker: call.joker }),
      })),
      expectedChoice: choice === null ? 0 : choice + 1,
    });
  }
}
const seatContext = (context) => ({
  ...context,
  seat: context.seat + 1,
  ...(context.dealerSeat === undefined
    ? {}
    : { dealerSeat: context.dealerSeat + 1 }),
  ...(context.winnerSeat === undefined
    ? {}
    : { winnerSeat: context.winnerSeat + 1 }),
  ...(context.knownVoids
    ? {
        knownVoids: context.knownVoids.map((v) => ({
          ...v,
          seat: v.seat + 1,
        })),
      }
    : {}),
});
const options = (list) =>
  list.map((o) => ({ ids: o.cardIds, features: o.features, prior: o.prior }));
const randomModels = () => {
  const make = () => {
    const model = newPolicy(pick);
    // Stronger weights than a fresh learner, so choices depart from the prior.
    model.output = model.output.map((v) => v * 12);
    return model;
  };
  return { lead: make(), follow: make() };
};
const championSource = /source = '([^']+)'/.exec(
  readFileSync(
    new URL('../src/server/ChampionModel.luau', import.meta.url),
    'utf8',
  ),
)?.[1];
const championPath = fileURLToPath(
  new URL(
    `../../data/policy-training/${championSource}/checkpoint.json`,
    import.meta.url,
  ),
);
let champion = null;
if (existsSync(championPath)) {
  const saved = JSON.parse(readFileSync(championPath, 'utf8'));
  champion = { lead: saved.leadChampion, follow: saved.followChampion };
  fixtures.policy.champion = champion;
}
for (const playerCount of [4, 6, 8, 10])
  for (let game = 0; game < 2; game++) {
    const models = randomModels();
    const t = {
      level: ['2', 'J'][game],
      suit: game === 1 && playerCount === 6 ? null : 'hearts',
    };
    const { hands, kitty } = deal(
      shuffle(createDeck(playerCount), pick),
      playerCount,
    );
    const size = kitty.length;
    const dealerSeat = 0;
    const burialCards = [...hands[0], ...kitty];
    fixtures.policy.burials.push({
      cards: burialCards,
      size,
      trump: t,
      models,
      baseline: chooseBotBurial(burialCards, size, t),
      roblox: robloxBurial(burialCards, size, t),
      expected: choosePolicyBurial(
        models.follow,
        burialCards,
        size,
        t,
        undefined,
        undefined,
        true,
      ),
      champion:
        champion &&
        choosePolicyBurial(
          champion.follow,
          burialCards,
          size,
          t,
          undefined,
          undefined,
          true,
        ),
    });
    for (let seat = 0; seat < playerCount; seat++) {
      const declarations = declarationsForHand(
        hands[seat],
        playerCount,
        t.level,
        seat,
      );
      if (!declarations.length) continue;
      const native = declarations.map((d) => ({
        seat: seat + 1,
        suit: d.kind === 'suit' ? d.suit : undefined,
        joker: d.kind === 'joker' ? d.joker : undefined,
        count: d.multiplicity,
        cardIds: d.cardIds,
      }));
      const choiceOf = (model) => {
        const picked = choosePolicyDeclaration(
          model,
          declarations,
          hands[seat],
          t.level,
        );
        return picked ? declarations.indexOf(picked) + 1 : 0;
      };
      fixtures.policy.declarations.push({
        options: native,
        hand: hands[seat],
        level: t.level,
        models,
        expected: choiceOf(models.follow),
        champion: champion ? choiceOf(champion.follow) : undefined,
      });
    }
    let state = startTrick({
      playerCount,
      trump: t,
      attackingTeam: 'A',
      leaderSeat: dealerSeat,
      hands,
    });
    const seenCards = [];
    const voids = new Map();
    let captured = 0;
    let penalties = 0;
    let turn = 0;
    while (state.status !== 'complete' || state.hands[0].length > 0) {
      const seat = state.nextSeat;
      const hand = state.hands[seat];
      turn++;
      let ids;
      if (!state.plays.length) {
        const context = {
          seat,
          dealerSeat,
          playerCount,
          cardsRemaining: hand.length,
          role: teamAt(seat) === 'A' ? 'attackers' : 'defenders',
          defenderScore: captured + penalties,
          swapThreshold: playerCount * 20,
          seenCards: [...seenCards],
          knownVoids: [...voids.values()],
        };
        ids = choosePolicyLead(models.lead, hand, t, context);
        if (turn % 4 === 1 || playerCount === 4)
          fixtures.policy.leads.push({
            hand,
            trump: t,
            context: seatContext(context),
            models,
            options: options(leadOptions(hand, t, context)),
            roblox: robloxLead(hand, t),
            expected: ids,
            champion:
              champion && choosePolicyLead(champion.lead, hand, t, context),
          });
      } else {
        const context = botPlayContext(state, dealerSeat);
        const lead = state.plays[0].components;
        ids = choosePolicyPlay(models.follow, hand, lead, t, context);
        if (turn % 4 === 1 || playerCount === 4)
          fixtures.policy.plays.push({
            hand,
            lead,
            trump: t,
            context: seatContext(context),
            models,
            options: options(playOptions(hand, lead, t, context, true)),
            roblox: robloxFollow(hand, lead, t, context),
            expected: ids,
            champion:
              champion &&
              choosePolicyPlay(champion.follow, hand, lead, t, context),
          });
      }
      const result = playCards(state, seat, ids);
      if (!result.ok) throw new Error(result.message);
      state = result.state;
      if (state.status !== 'complete' || state.hands[0].length === 0) {
        if (state.status === 'complete') break;
        continue;
      }
      captured += state.capturedDefenderPoints;
      penalties += state.penaltyPoints;
      const led = category(state.plays[0].cards[0], t);
      for (const play of state.plays) {
        seenCards.push(...play.cards);
        if (play.cards.some((card) => category(card, t) !== led))
          voids.set(`${play.seat}:${led}`, { seat: play.seat, category: led });
      }
      state = nextTrick(state);
    }
  }
for (let i = 0; i < 40; i++) {
  const t = { level: '2', suit: 'hearts' };
  const shoe = shuffle(createDeck(4), pick);
  const hand = shoe.slice(0, 25);
  const clubs = shoe
    .slice(25)
    .filter((c) => c.kind === 'suited' && c.suit === 'clubs' && c.rank !== '2');
  const lead = decomposeLead(clubs.slice(0, 4), t);
  if (!lead || lead.length < 2) continue;
  const models = randomModels();
  const ace = i % 2 === 0;
  const context = {
    seat: 1,
    winnerSeat: 0,
    winning: lead,
    lastToPlay: ace,
    trickPoints: i % 3 === 0 ? 0 : 15,
    opponentsRemaining: ace ? 0 : 1,
    dealerSeat: 2,
  };
  fixtures.policy.plays.push({
    hand,
    lead,
    trump: t,
    context: seatContext(context),
    models,
    options: options(playOptions(hand, lead, t, context, true)),
    roblox: robloxFollow(hand, lead, t, context),
    expected: choosePolicyPlay(models.follow, hand, lead, t, context),
    champion:
      champion && choosePolicyPlay(champion.follow, hand, lead, t, context),
  });
}
await mkdir(fileURLToPath(new URL('../dist/', import.meta.url)), {
  recursive: true,
});
await writeFile(out, 'return ' + lua(fixtures));
const result = execFileSync(
  process.argv[2] || 'lua',
  ['roblox/tests/parity.lua', out],
  { cwd: root, encoding: 'utf8' },
);
console.log(result.trim());
if (!result.includes('PASS:'))
  throw new Error('Native parity runner did not complete');
