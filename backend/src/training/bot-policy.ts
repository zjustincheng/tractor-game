import { chooseBotPlay } from '@tractor/rules';
import type { BotPolicy } from '../bot-policy.js';
import {
  choosePolicyLead,
  choosePolicyPlay,
  choosePolicyDeclaration,
  choosePolicyBurial,
} from './learned-policy.js';
import type { PolicyModel, PolicyExperience } from './learned-policy.js';
export function learnedBotPolicy(
  lead: PolicyModel,
  follow: PolicyModel,
  record: {
    lead?: (experience: PolicyExperience) => void;
    follow?: (experience: PolicyExperience) => void;
    declaration?: (experience: PolicyExperience) => void;
    burial?: (experience: PolicyExperience) => void;
  } = {},
  options: { robloxRules?: boolean } = {},
): BotPolicy {
  return {
    lead: (hand, trump, context) =>
      choosePolicyLead(
        lead,
        hand,
        trump,
        { ...context, beliefSearch: false },
        undefined,
        record.lead,
      ),
    follow: (hand, opening, trump, context) =>
      context && opening
        ? choosePolicyPlay(
            follow,
            hand,
            opening,
            trump,
            context,
            undefined,
            record.follow,
          )
        : chooseBotPlay(hand, opening, trump, context),
    declare: (options, hand, level) =>
      choosePolicyDeclaration(
        follow,
        options,
        hand,
        level,
        undefined,
        record.declaration,
      ),
    bury: (cards, size, trump) =>
      choosePolicyBurial(
        follow,
        cards,
        size,
        trump,
        undefined,
        record.burial,
        options.robloxRules === true,
      ),
  };
}
