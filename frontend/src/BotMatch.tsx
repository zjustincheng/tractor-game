import { useEffect, useState } from 'react';
import { botMatchViewSchema } from '@tractor/protocol';
import type { BotMatchView } from '@tractor/protocol';
import {
  cardPoints,
  category,
  decomposeLead,
  effectivePower,
  PLAYER_COUNTS,
  validateFollow,
} from '@tractor/rules';
import type { Card } from '@tractor/rules';

const symbols = { clubs: '♣', diamonds: '♦', hearts: '♥', spades: '♠' };
function label(card: Card) {
  return card.kind === 'joker'
    ? `${card.joker} joker`
    : `${card.rank}${symbols[card.suit]}`;
}

export function BotMatchTable() {
  const [view, setView] = useState<BotMatchView | null>(null);
  const [count, setCount] = useState(4);
  const [selected, setSelected] = useState<string[]>([]);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [clock, setClock] = useState(Date.now());
  const [savedId, setSavedId] = useState(() =>
    localStorage.getItem('tractor-bot-match'),
  );
  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);

  async function request(path: string, body?: unknown) {
    setBusy(true);
    setError('');
    try {
      const response = await fetch(
        path,
        body === undefined
          ? {}
          : {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify(body),
            },
      );
      const data = await response.json();
      if (!response.ok)
        throw new Error(
          typeof data.message === 'string'
            ? data.message
            : 'Could not update the match.',
        );
      const next = botMatchViewSchema.parse(data);
      setView(next);
      setSelected([]);
      localStorage.setItem('tractor-bot-match', next.id);
      setSavedId(next.id);
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : 'Could not reach the game server.',
      );
    } finally {
      setBusy(false);
    }
  }
  const command = (action: string, cardIds?: string[]) => {
    if (view)
      void request(`/api/bot-matches/${view.id}/commands`, {
        action,
        cardIds,
        revision: view.revision,
      });
  };
  const remaining = view
    ? Math.max(0, Math.ceil((view.declarationDeadline - clock) / 1000))
    : 0;
  const hand = [...(view?.hand ?? [])].sort((a, b) => {
    if (!view?.trump) return label(a).localeCompare(label(b));
    return (
      category(a, view.trump).localeCompare(category(b, view.trump)) ||
      effectivePower(a, view.trump) - effectivePower(b, view.trump)
    );
  });
  const canPlay = view?.phase === 'tricks' && view.nextSeat === 0;
  const canBury = view?.phase === 'kitty' && view.dealerSeat === 0;
  const selectedCards = hand.filter((card) => selected.includes(card.id));
  const selectedPoints = selectedCards.reduce(
    (sum, card) => sum + cardPoints(card),
    0,
  );
  let selectionMessage = '';
  let invalidSelection = false;
  if (canPlay && view.trump && selectedCards.length) {
    const leadCards = view.plays[0]?.cards;
    if (leadCards) {
      const result = validateFollow(
        hand,
        selectedCards,
        decomposeLead(leadCards, view.trump)!,
        view.trump,
      );
      invalidSelection = !result.legal;
      selectionMessage = result.legal
        ? result.matchesLead
          ? 'Matches the led structure.'
          : 'Legal follow; this selection cannot win the trick.'
        : result.message;
    } else {
      const components = decomposeLead(selectedCards, view.trump);
      invalidSelection = !components;
      selectionMessage = !components
        ? 'Lead cards must belong to one suit category.'
        : components.length > 1
          ? `Gamble: ${components.length} components. Opponents may force a reduced play and penalty.`
          : 'Homogeneous lead selected.';
    }
  }

  return (
    <section id="bot-match" className="bot-match" aria-labelledby="bot-heading">
      <div className="bot-header">
        <div>
          <p className="eyebrow">Solo table · You are seat 1, team A</p>
          <h2 id="bot-heading">Play a match against bots</h2>
        </div>
        <div className="bot-controls">
          <label>
            Match players{' '}
            <select
              value={count}
              disabled={busy}
              onChange={(event) => setCount(Number(event.target.value))}
            >
              {PLAYER_COUNTS.map((value) => (
                <option key={value} value={value}>
                  {value}
                </option>
              ))}
            </select>
          </label>
          <button
            disabled={busy}
            onClick={() =>
              void request('/api/bot-matches', { playerCount: count })
            }
          >
            {view ? 'New bot match' : 'Start bot match'}
          </button>
          {!view && savedId && (
            <button
              disabled={busy}
              onClick={() => void request(`/api/bot-matches/${savedId}`)}
            >
              Resume bot match
            </button>
          )}
        </div>
      </div>
      <p>
        Play with a bot partner and bot opponents. Select your cards, or use a
        suggested legal play. The first team to reach A wins.
      </p>
      {error && (
        <p role="alert" className="bot-error">
          {error}
        </p>
      )}
      {view && (
        <>
          <div className="bot-scoreboard">
            <strong>
              Round {view.round} · Trick {view.trickNumber}
            </strong>
            <span>
              Levels: A {view.levels.A} / B {view.levels.B}
            </span>
            <span>
              Attackers: {view.attackingTeam} · Dealer: seat{' '}
              {view.dealerSeat + 1}
            </span>
            <span>
              Defenders: {view.defenderScore} / {view.playerCount * 20} to swap
            </span>
            <span>
              Trump:{' '}
              {view.trump
                ? `${view.trump.level} · ${view.trump.suit ?? 'No-suit trump'}`
                : 'Declaring'}
            </span>
          </div>
          <p role="status">{view.message}</p>
          <p className="bot-score-detail">
            Defender score: {view.capturedPoints} captured +{' '}
            {view.penaltyPoints} penalties
            {view.settlement ? ` + ${view.settlement.kittyPoints} kitty` : ''}.
            Current trick: {view.trickPoints} points
            {view.trickPenalty
              ? `; penalty ${view.trickPenalty > 0 ? '+' : ''}${view.trickPenalty}`
              : ''}
            .
          </p>
          <div className="bot-seats">
            {view.seats.map((seat) => (
              <div
                key={seat.seat}
                className={`bot-seat ${view.nextSeat === seat.seat ? 'active' : ''}`}
              >
                <strong>
                  {seat.seat === 0 ? 'You' : `Bot ${seat.seat + 1}`} ·{' '}
                  {seat.team}
                </strong>
                <span>{seat.cardCount} cards</span>
              </div>
            ))}
          </div>
          {view.phase === 'declaration' && (
            <div className="bot-declaration">
              <p>
                {view.declaration
                  ? `Seat ${view.declaration.playerSeat + 1} declared ${view.declaration.multiplicity} × ${view.declaration.suit ?? `${view.declaration.joker} jokers`}.`
                  : 'Waiting for a declaration.'}{' '}
                Window: {remaining}s
              </p>
              <div className="bot-controls">
                {view.declarationOptions.map((option, index) => (
                  <button
                    key={index}
                    disabled={busy || remaining > 8 || remaining === 0}
                    onClick={() => command('declare', option.cardIds)}
                  >
                    Declare {option.multiplicity} ×{' '}
                    {option.suit ?? `${option.joker} jokers`}
                  </button>
                ))}
              </div>
              {!view.declarationOptions.length && (
                <p>No stronger declaration in your hand.</p>
              )}
              <button
                disabled={busy || remaining > 0}
                onClick={() => command('advance')}
              >
                Finalize trump
              </button>
            </div>
          )}
          {view.plays.length > 0 && (
            <div className="bot-trick" aria-label="Current trick">
              {view.plays.map((play) => (
                <div key={play.seat} className="bot-play">
                  <strong>
                    {play.seat === 0 ? 'You' : `Bot ${play.seat + 1}`}
                    {play.seat === view.winnerSeat
                      ? view.trickComplete
                        ? ' · Winner'
                        : ' · Winning'
                      : ''}
                  </strong>
                  <div>
                    {play.cards.map((card) => (
                      <span className="bot-played-card" key={card.id}>
                        {label(card)}
                      </span>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
          {canBury && (
            <p>
              Bury exactly {view.kittyCount} cards. The kitty has been added to
              your hand.
            </p>
          )}
          {canPlay && (
            <p>
              {view.plays.length
                ? `Your turn: follow with ${view.plays[0]!.cards.length} cards.`
                : 'Your lead: choose a structure or gamble from one suit category.'}
            </p>
          )}
          {hand.length > 0 && (
            <div className="bot-hand" aria-label="Your match hand">
              {hand.map((card) => (
                <button
                  type="button"
                  key={card.id}
                  className={`bot-card ${card.kind === 'suited' && (card.suit === 'hearts' || card.suit === 'diamonds') ? 'red' : ''} ${view.trump && category(card, view.trump) === 'trump' ? 'is-trump' : ''}`}
                  aria-label={
                    card.kind === 'suited'
                      ? `${card.rank} of ${card.suit}`
                      : label(card)
                  }
                  aria-pressed={selected.includes(card.id)}
                  disabled={busy || !(canPlay || canBury)}
                  onClick={() =>
                    setSelected((old) =>
                      old.includes(card.id)
                        ? old.filter((id) => id !== card.id)
                        : [...old, card.id],
                    )
                  }
                >
                  {label(card)}
                  {view.trump && category(card, view.trump) === 'trump' && (
                    <small className="bot-trump-label">Trump</small>
                  )}
                </button>
              ))}
            </div>
          )}
          {selectionMessage && (
            <p
              className={invalidSelection ? 'bot-error' : ''}
              aria-live="polite"
            >
              {selectionMessage}
            </p>
          )}
          <div className="bot-controls">
            {(canPlay || canBury) && (
              <>
                <span>
                  {selected.length} selected · {selectedPoints} points
                  {canBury ? ' to bury' : ''}
                </span>
                <button
                  disabled={busy}
                  onClick={() => setSelected(view.suggestion)}
                >
                  Suggest cards
                </button>
                <button
                  disabled={busy || selected.length === 0}
                  onClick={() => setSelected([])}
                >
                  Clear cards
                </button>
                <button
                  disabled={
                    busy ||
                    invalidSelection ||
                    (canBury
                      ? selected.length !== view.kittyCount
                      : selected.length === 0)
                  }
                  onClick={() => command(canBury ? 'bury' : 'play', selected)}
                >
                  {canBury ? 'Bury selected cards' : 'Play cards'}
                </button>
              </>
            )}
            {view.trickComplete && view.phase === 'tricks' && (
              <button disabled={busy} onClick={() => command('advance')}>
                Next trick
              </button>
            )}
            <button
              disabled={busy}
              onClick={() => void request(`/api/bot-matches/${view.id}`)}
            >
              Refresh match
            </button>
          </div>
          {view.settlement && (
            <div className="bot-result">
              <h3>
                {view.settlement.winner
                  ? `Team ${view.settlement.winner} wins the match!`
                  : `Round ${view.round} results`}
              </h3>
              <p>
                Defenders scored {view.settlement.defenderScore}, including{' '}
                {view.settlement.kittyPoints} kitty points (×
                {view.settlement.kittyMultiplier}).
              </p>
              <p>
                New levels: A {view.settlement.levels.A} / B{' '}
                {view.settlement.levels.B}. Team {view.settlement.attackingTeam}{' '}
                attacks next.
                {view.settlement.jackReset ? ' Jack reset applied.' : ''}
              </p>
              {!view.settlement.winner && (
                <button disabled={busy} onClick={() => command('next-round')}>
                  Start next round
                </button>
              )}
            </div>
          )}
        </>
      )}
    </section>
  );
}
