import { useEffect, useRef, useState } from 'react';
import { DecisionClip } from './DecisionClip.js';
import { DecisionFlashcards } from './DecisionFlashcards.js';
import { savedBotMatches, rememberBotMatch } from './saved-bot-matches.js';
import type { CSSProperties } from 'react';
import { GameTable, CardFace, cardColor } from './GameTable.js';
import {
  BOT_DEAL_CARD_INTERVAL_MS,
  botMatchViewSchema,
} from '@tractor/protocol';
import type { BotMatchView } from '@tractor/protocol';

const TRAINING_UI_ENABLED = import.meta.env.VITE_SHOW_TRAINING_TOOLS === 'true';
import {
  category,
  decomposeLead,
  effectivePower,
  PLAYER_COUNTS,
  RANKS,
  SUITS,
  validateFollow,
} from '@tractor/rules';
import type { Card } from '@tractor/rules';

const symbols = { clubs: '♣', diamonds: '♦', hearts: '♥', spades: '♠' };
const botProfiles = ['You', 'Captain', 'Collector', 'Risk-taker', 'Anchor'];
function seatLabel(seat: number) {
  return seat === 0
    ? 'You'
    : `Bot ${seat + 1} · ${botProfiles[seat] ?? 'Teammate'}`;
}
function label(card: Card) {
  return card.kind === 'joker'
    ? `${card.joker} joker`
    : `${card.rank}${symbols[card.suit]}`;
}
function playUiTone(kind: 'play' | 'win') {
  const AudioContextClass =
    window.AudioContext ??
    (window as typeof window & { webkitAudioContext?: typeof AudioContext })
      .webkitAudioContext;
  if (!AudioContextClass) return;
  const context = new AudioContextClass();
  const oscillator = context.createOscillator();
  const gain = context.createGain();
  oscillator.frequency.value = kind === 'win' ? 660 : 440;
  gain.gain.setValueAtTime(0.04, context.currentTime);
  gain.gain.exponentialRampToValueAtTime(0.001, context.currentTime + 0.12);
  oscillator.connect(gain).connect(context.destination);
  oscillator.start();
  oscillator.stop(context.currentTime + 0.12);
}

export function BotMatchTable() {
  const [savedMatches, setSavedMatches] = useState(savedBotMatches);
  const matchDetails = useRef<HTMLDetailsElement>(null);
  const trickHistory = useRef<HTMLDetailsElement>(null);
  const [snapshot, setView] = useState<BotMatchView | null>(null);
  const [visiblePlays, setVisiblePlays] = useState(0);
  const [pace, setPace] = useState(650);
  const [paused, setPaused] = useState(false);
  const [clock, setClock] = useState(Date.now());
  const dealtCount =
    snapshot?.dealingStartedAt === null || !snapshot
      ? (snapshot?.hand.length ?? 0)
      : Math.min(
          snapshot.hand.length,
          Math.max(
            0,
            Math.floor(
              (clock - snapshot.dealingStartedAt) / BOT_DEAL_CARD_INTERVAL_MS,
            ),
          ),
        );
  const dealing =
    snapshot?.phase === 'declaration' && dealtCount < snapshot.hand.length;
  const [count, setCount] = useState(4);
  const [playtest, setPlaytest] = useState(false);
  const [quickMatch, setQuickMatch] = useState(false);
  const [feedbackChoice, setFeedbackChoice] = useState<Record<string, number>>(
    {},
  );
  const [difficulty, setDifficulty] = useState<
    'relaxed' | 'standard' | 'sharp' | 'expert'
  >('standard');
  const [selected, setSelected] = useState<string[]>([]);
  const [, setSuggested] = useState(false);
  const [watchBots, setWatchBots] = useState(false);
  const [watchPaused, setWatchPaused] = useState(false);
  const [soundEnabled, setSoundEnabled] = useState(
    () => localStorage.getItem('tractor-sound-enabled') === 'true',
  );
  const [careerWins, setCareerWins] = useState(() =>
    Number(localStorage.getItem('tractor-career-wins') ?? 0),
  );
  const [careerLosses, setCareerLosses] = useState(() =>
    Number(localStorage.getItem('tractor-career-losses') ?? 0),
  );
  const recordedResult = useRef('');
  function toggleSound() {
    setSoundEnabled((enabled) => {
      const next = !enabled;
      localStorage.setItem('tractor-sound-enabled', String(next));
      return next;
    });
  }
  function resetCareerStats() {
    localStorage.removeItem('tractor-career-wins');
    localStorage.removeItem('tractor-career-losses');
    setCareerWins(0);
    setCareerLosses(0);
  }
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
          message: `${seatLabel(snapshot.plays[visiblePlays]!.seat)} is playing…`,
        };
  const [error, setError] = useState('');
  const [savedId, setSavedId] = useState(() =>
    localStorage.getItem('tractor-bot-match'),
  );
  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);
  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      const target = event.target as HTMLElement | null;
      if (
        watchBots ||
        event.repeat ||
        event.ctrlKey ||
        event.metaKey ||
        event.altKey ||
        target?.closest(
          'input, select, textarea, button, a, summary, [contenteditable]',
        )
      )
        return;
      if (event.key === 'Escape') {
        setSelected([]);
        setSuggested(false);
      } else if (
        event.key.toLowerCase() === 's' &&
        !busy &&
        view &&
        !view.playtest
      ) {
        setSelected(view.suggestion);
        setSuggested(true);
      } else if (
        event.key === 'Enter' &&
        !busy &&
        view &&
        (canPlay || canBury)
      ) {
        if (
          selected.length > 0 &&
          !invalidSelection &&
          (!canBury || selected.length === view.kittyCount)
        ) {
          command(canBury ? 'bury' : 'play', selected);
        }
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  });
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
      const text = await response.text();
      let data;
      try {
        data = JSON.parse(text);
      } catch {
        throw new Error(
          response.status === 502 ||
            response.status === 503 ||
            response.status === 504
            ? 'Cannot reach the game server. Check the backend terminal for startup errors, then try again.'
            : `The game server returned an invalid response (HTTP ${response.status}). Try again.`,
        );
      }
      if (!response.ok)
        throw new Error(
          data && typeof data.message === 'string'
            ? data.message
            : 'Could not update the match.',
        );
      const next = botMatchViewSchema.parse(data);
      setDifficulty(next.difficulty);
      if (next.playtest || next.languageModel) setWatchBots(false);
      setClock(Date.now());
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
      if (soundEnabled) playUiTone(next.trickComplete ? 'win' : 'play');
      setSelected([]);
      setSuggested(false);
      setSavedMatches(rememberBotMatch(next));
      setSavedId(next.id);
      return true;
    } catch (failure) {
      setError(
        failure instanceof Error
          ? failure.message
          : 'Could not reach the game server.',
      );
      return false;
    } finally {
      setBusy(false);
    }
  }
  async function exportReplay() {
    if (!view) return;
    try {
      const response = await fetch(`/api/bot-matches/${view.id}/replay`);
      if (!response.ok) throw new Error('Replay export is unavailable.');
      const blob = await response.blob();
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement('a');
      anchor.href = url;
      anchor.download = `tractor-match-${view.id}.json`;
      anchor.click();
      URL.revokeObjectURL(url);
    } catch (failure) {
      setError(
        failure instanceof Error ? failure.message : 'Could not export replay.',
      );
    }
  }
  function exportBehavior() {
    if (!view) return;
    const anchor = document.createElement('a');
    anchor.href = `/api/bot-matches/${view.id}/behavior.csv`;
    anchor.download = `tractor-bot-behavior-${view.id}.csv`;
    anchor.click();
  }
  function exportBehaviorSummary() {
    if (!view) return;
    const anchor = document.createElement('a');
    anchor.href = `/api/bot-matches/${view.id}/behavior-summary.csv`;
    anchor.download = `tractor-bot-summary-${view.id}.csv`;
    anchor.click();
  }
  function exportPlayerActions() {
    if (!view) return;
    const anchor = document.createElement('a');
    anchor.href = `/api/bot-matches/${view.id}/player-actions.csv`;
    anchor.download = `tractor-human-actions-${view.id}.csv`;
    anchor.click();
  }
  const command = (action: string, cardIds?: string[]) => {
    if (view)
      void request(`/api/bot-matches/${view.id}/commands`, {
        action,
        cardIds,
        revision: view.revision,
      });
  };
  // A blind playtest withholds every bot-decision export until the match ends.
  const sealed = Boolean(
    (view?.playtest || view?.languageModel) && !view?.settlement?.winner,
  );
  const remaining = view
    ? Math.max(0, Math.ceil((view.declarationDeadline - clock) / 1000))
    : 0;
  useEffect(() => {
    if (
      !watchBots ||
      watchPaused ||
      !view ||
      view.playtest ||
      view.languageModel ||
      busy ||
      animating ||
      dealing
    )
      return;
    const timer = window.setTimeout(() => {
      if (view.phase === 'kitty' && view.dealerSeat === 0)
        command('bury', view.suggestion);
      else if (view.phase === 'tricks' && view.nextSeat === 0)
        command('play', view.suggestion);
      else if (view.phase === 'tricks' && view.trickComplete)
        command('advance');
      else if (view.phase === 'declaration' && remaining === 0)
        command('advance');
      else if (view.phase === 'finished' && !view.settlement?.winner)
        command('next-round');
      else if (view.phase === 'finished' && view.settlement?.winner)
        setWatchBots(false);
    }, 500);
    return () => window.clearTimeout(timer);
  }, [
    watchBots,
    watchPaused,
    snapshot,
    visiblePlays,
    busy,
    animating,
    dealing,
    remaining,
  ]);
  useEffect(() => {
    if (!view?.settlement?.winner) return;
    const key = `${view.id}:${view.round}`;
    if (recordedResult.current === key) return;
    recordedResult.current = key;
    if (view.settlement.winner === 'B') {
      setCareerLosses((losses) => {
        const next = losses + 1;
        localStorage.setItem('tractor-career-losses', String(next));
        return next;
      });
      return;
    }
    setCareerWins((wins) => {
      const next = wins + 1;
      localStorage.setItem('tractor-career-wins', String(next));
      return next;
    });
  }, [view]);
  const revealedHand = dealing
    ? view!.hand.slice(0, dealtCount)
    : (view?.hand ?? []);
  const hand = [...revealedHand].sort((a, b) => {
    const suitA = a.kind === 'joker' ? SUITS.length : SUITS.indexOf(a.suit);
    const suitB = b.kind === 'joker' ? SUITS.length : SUITS.indexOf(b.suit);
    const rankA = a.kind === 'joker' ? 0 : RANKS.indexOf(a.rank);
    const rankB = b.kind === 'joker' ? 0 : RANKS.indexOf(b.rank);
    return suitA - suitB || rankB - rankA || a.id.localeCompare(b.id);
  });
  const displayedHand = hand;
  const handGroups = [
    ...(view?.trump
      ? [
          {
            key: 'trump',
            label: `✦ trump${view.trump.suit ? ` · ${symbols[view.trump.suit]} ${view.trump.suit}` : ''}`,
            cards: displayedHand
              .filter((card) => category(card, view.trump!) === 'trump')
              .sort(
                (a, b) =>
                  effectivePower(b, view.trump!) -
                  effectivePower(a, view.trump!),
              ),
          },
        ]
      : []),
    ...SUITS.map((suit) => ({
      key: suit,
      label: `${symbols[suit]} ${suit}`,
      cards: displayedHand.filter(
        (card) =>
          card.kind === 'suited' &&
          card.suit === suit &&
          (!view?.trump || category(card, view.trump!) !== 'trump'),
      ),
    })),
    ...(!view?.trump
      ? [
          {
            key: 'jokers',
            label: '★ jokers',
            cards: displayedHand.filter((card) => card.kind === 'joker'),
          },
        ]
      : []),
  ].filter((group) => group.cards.length > 0);
  const declarationOptions =
    view?.declarationOptions.filter((option) =>
      option.cardIds.every((id) => revealedHand.some((card) => card.id === id)),
    ) ?? [];
  const canPlay = view?.phase === 'tricks' && view.nextSeat === 0;
  const canBury = view?.phase === 'kitty' && view.dealerSeat === 0;
  const selectedCards = hand.filter((card) => selected.includes(card.id));
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
    <section id="bot-match" className="game-match" aria-label="Bot match">
      {savedMatches.length > 0 && (
        <details className="saved-bot-matches">
          <summary>
            Saved matches &amp; flashcards ({savedMatches.length})
          </summary>
          <p>
            Reopen a completed match to continue its flashcards, or return to a
            match in progress.
          </p>
          <div className="clip-controls">
            {savedMatches.map((match) => (
              <button
                key={match.id}
                disabled={busy || match.id === view?.id}
                onClick={() => void request(`/api/bot-matches/${match.id}`)}
              >
                {match.completed
                  ? 'Completed match · Flashcards'
                  : 'Saved match'}
                {match.round === null ? '' : ` · Round ${match.round}`} ·{' '}
                {match.id.slice(0, 8)}
                {match.id === view?.id ? ' (open)' : ''}
              </button>
            ))}
          </div>
        </details>
      )}
      <div className={`game-toolbar ${view ? 'match-toolbar' : 'match-setup'}`}>
        {view ? (
          <h2>Tractor</h2>
        ) : (
          <div className="setup-intro">
            <div>
              <p className="eyebrow">YOUR NEXT HAND</p>
              <h2>Take a seat.</h2>
              <p>A quick round or the full climb. Your table, your pace.</p>
            </div>
            <div className="setup-cards" aria-hidden="true">
              <span>
                A<small>♠</small>
              </span>
              <span>
                K<small>♥</small>
              </span>
              <span>
                A<small>♣</small>
              </span>
            </div>
          </div>
        )}
        {!view && (
          <>
            <div className="setup-fields">
              <label>
                Match players{' '}
                <select
                  value={count}
                  disabled={playtest}
                  onChange={(event) => setCount(Number(event.target.value))}
                >
                  {PLAYER_COUNTS.map((n) => (
                    <option key={n}>{n}</option>
                  ))}
                </select>
              </label>
              <label>
                Bot difficulty{' '}
                <select
                  value={difficulty}
                  disabled={playtest}
                  onChange={(event) =>
                    setDifficulty(event.target.value as typeof difficulty)
                  }
                >
                  <option value="relaxed">Relaxed</option>
                  <option value="standard">Standard</option>
                  <option value="sharp">Sharp</option>
                  <option value="expert">Expert (Champion)</option>
                </select>
              </label>
            </div>
            {TRAINING_UI_ENABLED && (
              <div className="setup-modes">
                <label>
                  <input
                    type="checkbox"
                    checked={playtest}
                    onChange={(event) => {
                      setPlaytest(event.target.checked);
                      if (event.target.checked) setCount(4);
                    }}
                  />{' '}
                  Human playtest (fixed partner, hidden opponents)
                  <small>Play, then review decisions and teach the bot.</small>
                </label>
              </div>
            )}
            <div className="setup-modes">
              <label>
                <input
                  type="checkbox"
                  checked={quickMatch}
                  onChange={(event) => setQuickMatch(event.target.checked)}
                />{' '}
                One-round quick match (random starting level)
                <small>
                  One deal at a random level from 2 to A. Normal trump
                  declarations.
                </small>
              </label>
            </div>
            {TRAINING_UI_ENABLED && playtest && (
              <p>
                Four players. Your partner is Standard. Opponents are Sharp or
                the saved champion, revealed after the full match. Play your own
                cards. Suggestions use the Standard policy without seeing
                opponents' hidden hands; autoplay is off.
              </p>
            )}
            <div className="setup-actions">
              <button
                className="primary-action"
                disabled={pending}
                onClick={() =>
                  void request('/api/bot-matches', {
                    playerCount: count,
                    difficulty,
                    playtest,
                    quickMatch,
                  })
                }
              >
                Start bot match
              </button>
              {savedId && (
                <button
                  disabled={pending}
                  onClick={() => void request(`/api/bot-matches/${savedId}`)}
                >
                  Resume bot match
                </button>
              )}
            </div>
          </>
        )}
        {view && (
          <>
            <button
              className="quick-match-action"
              disabled={busy}
              onClick={() =>
                void request('/api/bot-matches', {
                  playerCount: count,
                  difficulty,
                  quickMatch: true,
                })
              }
            >
              New one-round quick match
            </button>
            {view.quickMatch && (
              <p role="status">
                One-round match · starting level {view.levels.A}
              </p>
            )}
            {view.languageModel && (
              <p role="status">
                Language-model opponent: {view.languageModel.model} ·{' '}
                {view.languageModel.decisions} model decisions · Series: you{' '}
                {view.languageModel.record.humanWins}, model{' '}
                {view.languageModel.record.modelWins}
              </p>
            )}
            {TRAINING_UI_ENABLED && view.playtest?.previousPlaytestId && (
              <button
                disabled={busy}
                onClick={() =>
                  void request(
                    `/api/bot-matches/${view.playtest!.previousPlaytestId}`,
                  )
                }
              >
                Back to previous flashcards
              </button>
            )}
            {TRAINING_UI_ENABLED && view.playtest && (
              <p role="status">
                Human playtest · Partner: Standard · Opponents:{' '}
                {view.playtest.opponent ?? 'Hidden until match ends'}
              </p>
            )}
            <button
              disabled={Boolean(view.playtest || view.languageModel)}
              aria-pressed={watchBots}
              onClick={() => {
                setWatchBots(!watchBots);
                setWatchPaused(false);
                setPaused(false);
                setSelected([]);
              }}
            >
              {watchBots ? 'Stop watching' : 'Watch bots play'}
            </button>
            {(watchBots || animating) && (
              <button
                onClick={() => {
                  const next = !(watchPaused || paused);
                  setWatchPaused(next);
                  setPaused(next);
                }}
              >
                {watchPaused || paused ? 'Resume' : 'Pause'}
              </button>
            )}
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
              <button onClick={() => setVisiblePlays(snapshot!.plays.length)}>
                Show remaining plays
              </button>
            )}
            <button aria-pressed={soundEnabled} onClick={toggleSound}>
              {soundEnabled ? 'Sound on' : 'Sound off'}
            </button>
          </>
        )}
      </div>
      {error && (
        <p role="alert" className="game-error">
          {error}
        </p>
      )}
      {view && (
        <>
          <GameTable
            view={view}
            activeSeat={
              animating ? snapshot!.plays[visiblePlays]!.seat : view.nextSeat
            }
          >
            <div className="table-action-area">
              <p role="status">
                {pending
                  ? view.languageModel
                    ? 'Language model thinking… Your move is committed when the turn succeeds.'
                    : 'Updating table…'
                  : watchPaused
                    ? 'Paused'
                    : dealing
                      ? `Dealing · ${dealtCount} / ${snapshot!.hand.length}`
                      : view.phase === 'declaration'
                        ? `Call trump · ${remaining}s`
                        : view.phase === 'kitty'
                          ? `Bury ${view.kittyCount} cards`
                          : view.trickComplete
                            ? view.message
                            : canPlay
                              ? view.plays.length
                                ? `Your turn · follow ${view.plays[0]!.cards.length} cards`
                                : 'Your lead'
                              : view.message}
              </p>
              {!watchBots && (
                <>
                  {view.phase === 'declaration' && (
                    <div className="bot-declaration">
                      <p>
                        {view.declaration
                          ? `Seat ${view.declaration.playerSeat + 1} declared ${view.declaration.multiplicity} × ${view.declaration.suit ?? `${view.declaration.joker} jokers`}.`
                          : 'Waiting for a declaration.'}{' '}
                        Window: {remaining}s
                      </p>
                      <div className="bot-controls">
                        {declarationOptions.map((option, index) => (
                          <button
                            key={index}
                            disabled={pending || animating || remaining === 0}
                            onClick={() => command('declare', option.cardIds)}
                          >
                            Declare {option.multiplicity} ×{' '}
                            {option.suit ?? `${option.joker} jokers`}
                          </button>
                        ))}
                      </div>
                      {!declarationOptions.length && (
                        <p>
                          {dealing
                            ? 'You can call trump as your cards arrive.'
                            : 'No stronger declaration in your hand.'}
                        </p>
                      )}
                      <button
                        disabled={busy || remaining > 0}
                        onClick={() => command('advance')}
                      >
                        Finalize trump
                      </button>
                    </div>
                  )}

                  {(canPlay || canBury) && (
                    <div className="table-actions">
                      <button
                        disabled={busy}
                        onClick={() => {
                          setSelected(view.suggestion);
                          setSuggested(true);
                        }}
                      >
                        Suggest cards
                      </button>
                      <button
                        disabled={busy || !selected.length}
                        onClick={() => setSelected([])}
                      >
                        Clear cards
                      </button>
                      <button
                        className="table-primary"
                        disabled={
                          busy ||
                          invalidSelection ||
                          (canBury
                            ? selected.length !== view.kittyCount
                            : !selected.length)
                        }
                        onClick={() =>
                          command(canBury ? 'bury' : 'play', selected)
                        }
                      >
                        {canBury ? 'Bury selected cards' : 'Play cards'}
                        {selected.length ? ` (${selected.length})` : ''}
                      </button>
                    </div>
                  )}
                  {invalidSelection && <p role="alert">{selectionMessage}</p>}
                  {view.phase === 'tricks' && view.trickComplete && (
                    <button
                      className="table-primary"
                      disabled={busy}
                      onClick={() => command('advance')}
                    >
                      Next trick
                    </button>
                  )}
                </>
              )}
            </div>
            <div className="table-hand-scroll" aria-label="Your match hand">
              <div
                className="table-hand"
                style={
                  { '--hand-count': Math.max(1, hand.length) } as CSSProperties
                }
              >
                {handGroups.flatMap((group) =>
                  group.cards.map((card) => (
                    <button
                      key={card.id}
                      type="button"
                      className={`table-card hand-card ${cardColor(card)} ${group.key === 'trump' ? 'trump-card' : ''}`}
                      aria-label={
                        card.kind === 'suited'
                          ? `${card.rank} of ${card.suit}`
                          : label(card)
                      }
                      aria-pressed={selected.includes(card.id)}
                      disabled={watchBots || busy || !(canPlay || canBury)}
                      onClick={() => {
                        setSuggested(false);
                        setSelected((old) =>
                          old.includes(card.id)
                            ? old.filter((id) => id !== card.id)
                            : [...old, card.id],
                        );
                      }}
                    >
                      <CardFace card={card} />
                      {group.key === 'trump' && (
                        <span className="face-trump" aria-label="Trump">
                          ★
                        </span>
                      )}
                    </button>
                  )),
                )}
              </div>
            </div>
            {view.settlement && (
              <div
                className={`bot-result ${view.settlement.winner ? 'match-won' : 'round-settled'}`}
              >
                <h3>
                  {view.settlement.winner
                    ? `Team ${view.settlement.winner} wins the match!`
                    : `Round ${view.round} results`}
                </h3>
                <div className="settlement-summary">
                  <div>
                    <span>Defender score</span>
                    <strong>{view.settlement.defenderScore}</strong>
                  </div>
                  <div>
                    <span>Kitty points</span>
                    <strong>{view.settlement.kittyPoints}</strong>
                  </div>
                  <div>
                    <span>Kitty multiplier</span>
                    <strong>×{view.settlement.kittyMultiplier}</strong>
                  </div>
                </div>
                <p>
                  New levels: A {view.settlement.levels.A} / B{' '}
                  {view.settlement.levels.B}. Team{' '}
                  {view.settlement.attackingTeam} attacks next.
                  {view.settlement.jackReset ? ' Jack reset applied.' : ''}
                </p>
                {TRAINING_UI_ENABLED && view.playtest?.opponent && (
                  <>
                    <p>
                      Opponent revealed:{' '}
                      {view.playtest.opponent === 'champion'
                        ? view.playtest.feedbackCount
                          ? 'Adaptive policy'
                          : 'Saved champion'
                        : 'Sharp'}
                      . Choose better actions below to teach the adaptive
                      policy.
                    </p>
                    {view.playtest.review.length === 0 && (
                      <button
                        disabled={busy}
                        onClick={() =>
                          void request(`/api/bot-matches/${view.id}/review`, {
                            revision: view.revision,
                          })
                        }
                      >
                        {busy ? 'Preparing…' : 'Start decision flashcards'}
                      </button>
                    )}
                    {view.playtest.review.length > 0 && (
                      <>
                        <DecisionFlashcards
                          key={view.id}
                          review={view.playtest.review}
                          busy={busy}
                          teach={(sampleId, preferredIndex) =>
                            request(`/api/bot-matches/${view.id}/feedback`, {
                              revision: view.revision,
                              sampleId,
                              preferredIndex,
                            })
                          }
                        />
                        <details className="playtest-feedback">
                          <summary>
                            Teach from this match (
                            {
                              view.playtest.review.filter(
                                (item) =>
                                  item.preferredIndex !== null &&
                                  item.preferredIndex !== item.chosen,
                              ).length
                            }
                            /{view.playtest.review.length} decisions corrected)
                          </summary>
                          <p>
                            For each sampled choice, select what you think the
                            bot should have played. Each correction updates this
                            series’ adaptive policy; the saved champion
                            checkpoint stays unchanged. Choose a different
                            action to enable Teach.
                          </p>
                          {view.playtest.review.map((item) => (
                            <div
                              key={item.id}
                              className="playtest-feedback-row"
                            >
                              <div className="playtest-decision-context">
                                <strong>{`Bot ${item.seat + 1} · ${item.kind}`}</strong>
                                {item.round !== null && item.trick !== null && (
                                  <small>
                                    Round {item.round}, trick {item.trick}
                                  </small>
                                )}
                                {item.clip && (
                                  <details className="playtest-clip">
                                    <summary>Watch this trick</summary>
                                    <DecisionClip clip={item.clip} />
                                  </details>
                                )}
                              </div>
                              <select
                                aria-label={`Preferred action for bot ${item.seat + 1} ${item.kind}`}
                                disabled={item.preferredIndex !== null || busy}
                                value={feedbackChoice[item.id] ?? item.chosen}
                                onChange={(event) =>
                                  setFeedbackChoice((old) => ({
                                    ...old,
                                    [item.id]: Number(event.target.value),
                                  }))
                                }
                              >
                                {item.options.map((option, index) => (
                                  <option key={index} value={index}>
                                    {index === item.chosen ? 'Chosen: ' : ''}
                                    {option.cards.length
                                      ? option.cards.join(', ')
                                      : 'Pass'}
                                  </option>
                                ))}
                              </select>
                              <button
                                disabled={
                                  busy ||
                                  item.preferredIndex !== null ||
                                  (feedbackChoice[item.id] ?? item.chosen) ===
                                    item.chosen
                                }
                                onClick={() =>
                                  void request(
                                    `/api/bot-matches/${view.id}/feedback`,
                                    {
                                      revision: view.revision,
                                      sampleId: item.id,
                                      preferredIndex:
                                        feedbackChoice[item.id] ?? item.chosen,
                                    },
                                  )
                                }
                              >
                                {item.preferredIndex !== null
                                  ? 'Learned'
                                  : 'Teach'}
                              </button>
                            </div>
                          ))}
                        </details>
                      </>
                    )}
                    <button
                      disabled={busy}
                      onClick={() =>
                        void request('/api/bot-matches', {
                          playerCount: 4,
                          playtest: true,
                          previousPlaytestId: view.id,
                        })
                      }
                    >
                      Next playtest
                    </button>
                  </>
                )}
                {!view.settlement.winner && (
                  <button disabled={busy} onClick={() => command('next-round')}>
                    Start next round
                  </button>
                )}
                {view.languageModel && view.settlement.winner && (
                  <>
                    <p>
                      This result measures the language-model opponent. Continue
                      this series to retain its observations about your play.
                    </p>
                    <button
                      disabled={busy}
                      onClick={() =>
                        void request('/api/bot-matches', {
                          playerCount: 4,
                          languageModel: true,
                          previousModelMatchId: view.id,
                        })
                      }
                    >
                      Next match with memory
                    </button>
                  </>
                )}
              </div>
            )}
          </GameTable>
          {view.history.length > 0 && (
            <button
              onClick={() => {
                if (matchDetails.current) matchDetails.current.open = true;
                if (trickHistory.current) {
                  trickHistory.current.open = true;
                  trickHistory.current.scrollIntoView({ block: 'start' });
                }
              }}
            >
              Watch recorded tricks
            </button>
          )}
          <details className="table-details" ref={matchDetails}>
            <summary>Match details & settings</summary>
            <div className="game-toolbar">
              <label>
                New match players
                <select
                  value={count}
                  onChange={(event) => setCount(Number(event.target.value))}
                >
                  {PLAYER_COUNTS.map((n) => (
                    <option key={n}>{n}</option>
                  ))}
                </select>
              </label>
              <label>
                New match difficulty
                <select
                  value={difficulty}
                  onChange={(event) =>
                    setDifficulty(event.target.value as typeof difficulty)
                  }
                >
                  <option value="relaxed">Relaxed</option>
                  <option value="standard">Standard</option>
                  <option value="sharp">Sharp</option>
                  <option value="expert">Expert (Champion)</option>
                </select>
              </label>
              <button
                disabled={busy}
                onClick={() => void request(`/api/bot-matches/${view.id}`)}
              >
                Refresh match
              </button>
              <button disabled={sealed} onClick={() => void exportReplay()}>
                Export replay
              </button>
              {TRAINING_UI_ENABLED && view.playtest && (
                <button onClick={exportPlayerActions}>
                  Export my actions CSV
                </button>
              )}
              <button disabled={sealed} onClick={exportBehavior}>
                Export bot behavior CSV
              </button>
              <button disabled={sealed} onClick={exportBehaviorSummary}>
                Export bot summary CSV
              </button>
              <button
                disabled={busy}
                onClick={() =>
                  void request('/api/bot-matches', {
                    playerCount: count,
                    difficulty,
                  })
                }
              >
                New bot match
              </button>
              <button onClick={resetCareerStats}>Reset career record</button>
            </div>
            {TRAINING_UI_ENABLED && view.playtest && sealed && (
              <p>
                Your actions can be exported during the match. Replay and bot
                exports unlock when it ends because they contain hidden match
                information.
              </p>
            )}
            <p>
              {TRAINING_UI_ENABLED && view.playtest
                ? 'Human playtest'
                : `Difficulty: ${view.difficulty}`}{' '}
              · Career: {careerWins} wins / {careerLosses} losses
            </p>
            <p>
              Defenders: {view.capturedPoints} captured · {view.penaltyPoints}{' '}
              penalty adjustment
            </p>
            <details className="bot-history" ref={trickHistory}>
              <summary>
                Trick history ({view.history.length}) · Watch tricks
              </summary>
              <p>
                Open a trick, then choose Watch this trick. Most recent 100
                tricks. Only played cards are shown.
              </p>
              {[...view.history].reverse().map((trick) => (
                <details key={`${trick.round}-${trick.number}`}>
                  <summary>
                    Round {trick.round} · Trick {trick.number} — Seat{' '}
                    {trick.winnerSeat + 1} won {trick.points} points
                  </summary>
                  <p>
                    Trump: {trick.trump.level} · {trick.trump.suit ?? 'No suit'}
                    . Defenders captured {trick.defenderPoints}; penalty{' '}
                    {trick.penalty}.
                  </p>
                  {trick.plays.map((play) => (
                    <p key={play.seat}>
                      <strong>Seat {play.seat + 1}: </strong>
                      {play.cards.map(label).join(' · ')}
                    </p>
                  ))}
                  <details>
                    <summary>Watch this trick</summary>
                    <DecisionClip
                      reviewDecision={false}
                      clip={{
                        seat: 0,
                        seatCorrected: false,
                        decisionIndex: 0,
                        hand: null,
                        trump: `${trick.trump.level} ${trick.trump.suit ?? 'No suit'}`,
                        points: trick.points,
                        winnerSeat: trick.winnerSeat,
                        plays: trick.plays.map((play) => ({
                          seat: play.seat,
                          cards: play.cards.map(label),
                        })),
                      }}
                    />
                  </details>
                </details>
              ))}
              {!view.history.length && (
                <p>Completed tricks will appear here.</p>
              )}
            </details>
            {view.rounds.length > 0 && (
              <details className="bot-history">
                <summary>Round history ({view.rounds.length})</summary>
                <p>Most recent 20 rounds.</p>
                {[...view.rounds].reverse().map((round) => (
                  <p key={round.round}>
                    Round {round.round}: defenders {round.defenderScore} points.
                    Levels A {round.levels.A} / B {round.levels.B}
                    {round.winner
                      ? ` · Team ${round.winner} won the match`
                      : ''}
                    .
                  </p>
                ))}
              </details>
            )}
          </details>
        </>
      )}
    </section>
  );
}
