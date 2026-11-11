import {
  chooseBotBurial,
  chooseBotDeclaration,
  chooseBotOpeningLead,
  chooseBotPlay,
} from '@tractor/rules';
import type { BotDifficulty, Card, Trump } from '@tractor/rules';
import type { ChaodiCall } from './training/roblox-rules.js';
import type { LeadPolicy, PolicyModel } from './training/learned-policy.js';
import type { BotMatch } from './bot-match.js';

/** Only the existing Sharp heuristic consumes otherHands, for validated throws.
 * Learned policies must ignore that privileged simulator/server argument. */
export type PolicyActionKind = 'lead' | 'follow' | 'declaration' | 'burial';
export interface BotPolicy {
  forSeat?: (match: BotMatch, seat: number) => BotPolicy;
  models?: {
    lead: PolicyModel;
    follow: PolicyModel;
  };
  lead: (
    hand: Parameters<LeadPolicy>[0],
    trump: Parameters<LeadPolicy>[1],
    context: Parameters<LeadPolicy>[2],
    otherHands: readonly (readonly Card[])[],
  ) => string[];
  follow: typeof chooseBotPlay;
  declare: typeof chooseBotDeclaration;
  bury: typeof chooseBotBurial;
  /** Roblox Chao Di: index of the call to make, or null to pass. */
  chaodi?: (
    calls: readonly ChaodiCall[],
    hand: readonly Card[],
    trump: Trump,
    sameTeamAsHolder: boolean,
  ) => number | null;
}

export function heuristicPolicy(difficulty: BotDifficulty): BotPolicy {
  return {
    lead: (hand, trump, context, otherHands) =>
      chooseBotOpeningLead(
        hand,
        otherHands,
        trump,
        { ...context, beliefSearch: difficulty === 'sharp' },
        difficulty,
      ),
    follow: chooseBotPlay,
    declare: chooseBotDeclaration,
    bury: chooseBotBurial,
  };
}
