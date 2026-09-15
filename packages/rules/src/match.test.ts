import { describe, expect, it } from 'vitest';
import {
  createDeck,
  createRound,
  exchangeKitty,
  gameConfig,
  receiveDeclaration,
  advanceDeclaration,
  declarationsForHand,
  shuffle,
} from './index.js';

function round(playerCount: 4 | 6 = 4) {
  return createRound({
    playerCount,
    dealerSeat: 0,
    attackingTeam: 'A',
    shoe: shuffle(createDeck(playerCount), (max) => max - 1),
    firstDeclarationDeadline: 1_000,
  });
}

describe('authoritative declaration and kitty lifecycle', () => {
  it('deals a round with private kitty and equal hands', () => {
    const state = round();
    expect(state.phase).toBe('declaration');
    expect(
      state.hands.every((hand) => hand.length === gameConfig(4).handSize),
    ).toBe(true);
    expect(state.kitty).toHaveLength(8);
    expect(state.trump).toBeNull();
  });
  it('accepts only real level cards and resets the lock deadline on stronger declarations', () => {
    const state = round();
    const candidates = state.hands.flatMap((hand, seat) =>
      declarationsForHand(hand, 4, '2', seat).filter(
        (item) => item.kind === 'suit',
      ),
    );
    const first = candidates[0]!;
    const accepted = receiveDeclaration(state, first.playerSeat, first, 2_000);
    expect(accepted.ok).toBe(true);
    if (!accepted.ok) throw new Error(accepted.message);
    expect(accepted.state.declarationDeadline).toBe(10_000);
    const stronger = candidates.find(
      (item) => item.multiplicity > first.multiplicity,
    );
    if (!stronger) return;
    const result = receiveDeclaration(
      accepted.state,
      stronger.playerSeat,
      stronger,
      3_000,
    );
    expect(result.ok).toBe(true);
    expect(result.ok && result.state.declarationDeadline).toBe(11_000);
    expect(
      receiveDeclaration(
        state,
        first.playerSeat,
        { ...first, cardIds: ['fake'] },
        2_000,
      ),
    ).toMatchObject({ ok: false, code: 'INVALID_DECLARATION' });
  });
  it('does not finalize before the deadline, then uses fallback and another window', () => {
    const state = round();
    expect(advanceDeclaration(state, 999, () => 0)).toMatchObject({
      ok: false,
      code: 'DECLARATION_LOCKED',
    });
    const fallback = advanceDeclaration(state, 1_000, () => 0);
    expect(fallback.ok).toBe(true);
    if (!fallback.ok) throw new Error(fallback.message);
    expect(fallback.state.phase).toBe('declaration');
    expect(fallback.state.declaration).not.toBeNull();
    expect(fallback.state.declarationDeadline).toBe(9_000);
    const locked = advanceDeclaration(fallback.state, 8_999, () => 0);
    expect(locked).toMatchObject({ ok: false, code: 'DECLARATION_LOCKED' });
    const finalized = advanceDeclaration(fallback.state, 9_000, () => 0);
    expect(finalized.ok).toBe(true);
    expect(finalized.ok && finalized.state.phase).toBe('kitty');
    expect(finalized.ok && finalized.state.trump).toMatchObject({
      level: '2',
      suit: expect.any(String),
    });
  });
  it('lets the scheduled dealer bury the kitty even if another player won declaration', () => {
    const state = round(6);
    const declaration = state.hands.flatMap((hand, seat) =>
      declarationsForHand(hand, 6, '2', seat).filter(
        (item) => item.kind === 'suit',
      ),
    )[0]!;
    const declared = receiveDeclaration(
      state,
      declaration.playerSeat,
      declaration,
      2_000,
    );
    if (!declared.ok) throw new Error(declared.message);
    const finalized = advanceDeclaration(declared.state, 10_000, () => 0);
    if (!finalized.ok) throw new Error(finalized.message);
    const dealer = finalized.state.hands[0]!;
    const buried = dealer.slice(0, 6).map((card) => card.id);
    const exchanged = exchangeKitty(finalized.state, buried);
    expect(exchanged.ok).toBe(true);
    if (!exchanged.ok) throw new Error(exchanged.message);
    expect(exchanged.state.phase).toBe('tricks');
    expect(exchanged.state.trick?.leaderSeat).toBe(0);
    expect(
      exchanged.state.hands.every(
        (hand) => hand.length === gameConfig(6).handSize,
      ),
    ).toBe(true);
  });
  it('rejects wrong kitty count, fabricated cards, and pre-kitty exchange', () => {
    const state = round();
    expect(exchangeKitty(state, [])).toMatchObject({
      ok: false,
      code: 'ROUND_NOT_READY',
    });
    const declaration = state.hands.flatMap((hand, seat) =>
      declarationsForHand(hand, 4, '2', seat).filter(
        (item) => item.kind === 'suit',
      ),
    )[0]!;
    const declared = receiveDeclaration(
      state,
      declaration.playerSeat,
      declaration,
      2_000,
    );
    if (!declared.ok) throw new Error(declared.message);
    const finalized = advanceDeclaration(declared.state, 10_000, () => 0);
    if (!finalized.ok) throw new Error(finalized.message);
    expect(exchangeKitty(finalized.state, ['fake'])).toMatchObject({
      ok: false,
      code: 'INVALID_BURY',
    });
  });
});
