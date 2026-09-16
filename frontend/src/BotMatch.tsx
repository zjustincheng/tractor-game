import { useEffect, useState } from 'react';
import { botMatchViewSchema } from '@tractor/protocol';
import type { BotMatchView } from '@tractor/protocol';
import {
  cardPoints,
  category,
  decomposeLead,
  effectivePower,
  PLAYER_COUNTS,
  RANKS,
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
  const [snapshot, setView] = useState<BotMatchView | null>(null);
  const [visiblePlays, setVisiblePlays] = useState(0);
  const [pace, setPace] = useState(650);
  const [paused, setPaused] = useState(false);
  const [dealing, setDealing] = useState(false);
  const [dealtCount, setDealtCount] = useState(0);
  const [count, setCount] = useState(4);
  const [selected, setSelected] = useState<string[]>([]);
  const [pending, setBusy] = useState(false);
  const animating = snapshot !== null && visiblePlays < snapshot.plays.length;
  const busy = pending || animating || dealing;
  const view: BotMatchView | null = !snapshot
    ? null
    : !animating
      ? snapshot
      : {
          ...snapshot,
          phase: snapshot.phase === 'finished' ? 'tricks' : snapshot.phase,
          plays: snapshot.plays.slice(0, visiblePlays),
          seats: snapshot.seats.map((seat) => ({
            ...seat,
            cardCount:
              seat.cardCount +
              snapshot.plays
                .slice(visiblePlays)
                .filter((play) => play.seat === seat.seat)
                .reduce((sum, play) => sum + play.cards.length, 0),
          })),
          nextSeat: null,
          winnerSeat: null,
          trickComplete: false,
          settlement: null,
          history: snapshot.history.filter(
            (item) =>
              item.round !== snapshot.round ||
              item.number !== snapshot.trickNumber,
          ),
          rounds: snapshot.rounds.filter(
            (item) => item.round !== snapshot.round,
          ),
          message: `Bot ${snapshot.plays[visiblePlays]!.seat + 1} is playing…`,
        };
  const [error, setError] = useState('');
  const [clock, setClock] = useState(Date.now());
  const [savedId, setSavedId] = useState(() =>
    localStorage.getItem('tractor-bot-match'),
  );
  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);
  useEffect(() => {
    if (!animating || paused) return;
    const timer = window.setTimeout(
      () =>
        setVisiblePlays((count) =>
          pace === 0 ? snapshot!.plays.length : count + 1,
        ),
      pace,
    );
    return () => window.clearTimeout(timer);
  }, [animating, paused, pace, visiblePlays, snapshot]);
  useEffect(() => {
    if (!dealing || !snapshot) return;
    const timer = window.setInterval(() => {
      setDealtCount((count) => {
        const next = Math.min(snapshot.hand.length, count + 1);
        if (next >= snapshot.hand.length) setDealing(false);
        return next;
      });
    }, 42);
    return () => window.clearInterval(timer);
  }, [dealing, snapshot]);

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
      if (
        path === '/api/bot-matches' ||
        (typeof body === 'object' &&
          body !== null &&
          'action' in body &&
          body.action === 'next-round')
      )
        setDealing(true);
      setDealtCount(0);
      const alreadyShown =
        snapshot?.id === next.id &&
        snapshot.round === next.round &&
        snapshot.trickNumber === next.trickNumber
          ? snapshot.plays.length
          : 0;
      const revealCount =
        alreadyShown + (next.plays[alreadyShown]?.seat === 0 ? 1 : 0);
      setVisiblePlays(
        body === undefined || pace === 0 ? next.plays.length : revealCount,
      );
      setPaused(false);
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
  const displayedHand = dealing ? hand.slice(0, dealtCount) : hand;
  const canPlay = view?.phase === 'tricks' && view.nextSeat === 0;
  const canBury = view?.phase === 'kitty' && view.dealerSeat === 0;
  const teammateSeat = view ? 2 % view.playerCount : 2;
  const yourRole = view
    ? view.attackingTeam === 'A'
      ? 'Attackers'
      : 'Defenders'
    : '';
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
      <div className="bot-controls">
        <label>
          Bot pace{' '}
          <select
            value={pace}
            onChange={(event) => setPace(Number(event.target.value))}
          >
            <option value={1000}>Relaxed</option>
            <option value={650}>Normal</option>
            <option value={200}>Fast</option>
            <option value={0}>Instant</option>
          </select>
        </label>
        {animating && (
          <>
            <button onClick={() => setPaused((value) => !value)}>
              {paused ? 'Resume bot turns' : 'Pause bot turns'}
            </button>
            <button onClick={() => setVisiblePlays(snapshot!.plays.length)}>
              Show remaining plays
            </button>
          </>
        )}
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
          {dealing && (
            <div className="deal-banner" role="status" aria-live="polite">
              <span className="deal-spinner" aria-hidden="true">
                ♠
              </span>
              <strong>Dealing the table…</strong>
              <span>
                Card {dealtCount} of {snapshot?.hand.length ?? 0} ·
                counterclockwise
              </span>
              <progress
                value={dealtCount}
                max={snapshot?.hand.length ?? 1}
                aria-label="Deal progress"
              />
            </div>
          )}
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
              {animating
                ? 'Trick in progress'
                : `Defenders: ${view.defenderScore} / ${view.playerCount * 20} to swap`}
            </span>
            <span>
              Trump:{' '}
              {view.trump
                ? `${view.trump.level} · ${view.trump.suit ?? 'No-suit trump'}`
                : 'Declaring'}
            </span>
          </div>
          <details className="public-tracker">
            <summary>Public cards tracked</summary>
            <div className="tracker-grid">
              {(
                ['clubs', 'diamonds', 'hearts', 'spades', 'jokers'] as const
              ).map((suit) => (
                <span key={suit}>
                  <strong>{view.seenCounts[suit]}</strong>{' '}
                  {suit === 'jokers' ? 'jokers' : suit}
                </span>
              ))}
            </div>
            <div className="rank-tracker" aria-label="Public rank counts">
              {RANKS.map((rank) => (
                <span
                  key={rank}
                  className={view.seenRankCounts[rank] ? 'seen' : ''}
                >
                  <strong>{rank}</strong> {view.seenRankCounts[rank]}
                </span>
              ))}
            </div>
            <small>
              Counts include cards played in completed tricks. Unseen cards may
              still be anywhere.
            </small>
            <div
              className="tracker-odds"
              aria-label="Estimated opponent category odds"
            >
              <strong>Estimated opponent holds</strong>{' '}
              {Object.entries(view.categoryOdds).map(([categoryName, odds]) => (
                <span key={categoryName}>
                  {categoryName}: {Math.round(odds * 100)}%
                </span>
              ))}
            </div>
            {view.knownVoids.length > 0 && (
              <small className="void-notes">
                Known voids:{' '}
                {view.knownVoids
                  .map(
                    (voidInfo) =>
                      `Seat ${voidInfo.seat + 1} has no ${voidInfo.category}`,
                  )
                  .join(' · ')}
              </small>
            )}
          </details>
          <p role="status">{view.message}</p>
          <div
            className="match-identity"
            aria-label="Match identity and levels"
          >
            <div className="identity-card identity-you">
              <span className="identity-label">Your team</span>
              <strong>Team A · You + Seat {teammateSeat + 1}</strong>
              <span className="identity-note">Your teammate</span>
            </div>
            <div className="identity-card identity-level">
              <span className="identity-label">Your level</span>
              <strong>{view.levels.A}</strong>
              <span className="identity-note">First to A wins</span>
            </div>
            <div className="identity-card identity-role">
              <span className="identity-label">This round</span>
              <strong>{yourRole}</strong>
              <span className="identity-note">
                {view.attackingTeam === 'A'
                  ? 'Protect the score'
                  : 'Capture points'}
              </span>
            </div>
            <div className="identity-card identity-opponents">
              <span className="identity-label">Opponents · Team B</span>
              <strong>Level {view.levels.B}</strong>
              <span className="identity-note">
                Seats{' '}
                {Array.from(
                  { length: view.playerCount / 2 },
                  (_, i) => i * 2 + 2,
                ).join(', ')}
              </span>
            </div>
          </div>
          {!animating && (
            <p className="bot-score-detail">
              Defender score: {view.capturedPoints} captured +{' '}
              {view.penaltyPoints} penalties
              {view.settlement ? ` + ${view.settlement.kittyPoints} kitty` : ''}
              . Current trick: {view.trickPoints} points
              {view.trickPenalty
                ? `; penalty ${view.trickPenalty > 0 ? '+' : ''}${view.trickPenalty}`
                : ''}
              .
            </p>
          )}
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
              {displayedHand.map((card) => (
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
          <details className="bot-history">
            <summary>Trick history ({view.history.length})</summary>
            <p>Most recent 100 tricks. Only played cards are shown.</p>
            {[...view.history].reverse().map((trick) => (
              <details key={`${trick.round}-${trick.number}`}>
                <summary>
                  Round {trick.round} · Trick {trick.number} — Seat{' '}
                  {trick.winnerSeat + 1} won {trick.points} points
                </summary>
                <p>
                  Trump: {trick.trump.level} · {trick.trump.suit ?? 'No suit'}.
                  Defenders captured {trick.defenderPoints}; penalty{' '}
                  {trick.penalty}.
                </p>
                {trick.plays.map((play) => (
                  <p key={play.seat}>
                    <strong>Seat {play.seat + 1}: </strong>
                    {play.cards.map(label).join(' · ')}
                  </p>
                ))}
              </details>
            ))}
            {!view.history.length && <p>Completed tricks will appear here.</p>}
          </details>
          {view.rounds.length > 0 && (
            <details className="bot-history">
              <summary>Round history ({view.rounds.length})</summary>
              <p>Most recent 20 rounds.</p>
              {[...view.rounds].reverse().map((round) => (
                <p key={round.round}>
                  Round {round.round}: defenders {round.defenderScore} points.
                  Levels A {round.levels.A} / B {round.levels.B}
                  {round.winner ? ` · Team ${round.winner} won the match` : ''}.
                </p>
              ))}
            </details>
          )}
        </>
      )}
    </section>
  );
}
