import { useEffect, useRef, useState } from 'react';
import { BotMatchTable } from './BotMatch.js';
import { RoomMatch } from './RoomMatch.js';
import type { CSSProperties, FormEvent } from 'react';
import {
  advanceLevel,
  cardPoints,
  category,
  effectivePower,
  gameConfig,
  homogeneousStructure,
  PLAYER_COUNTS,
  RANKS,
  scoreOutcome,
  SUITS,
} from '@tractor/rules';
import type { Card, Category, Rank, Suit, Trump } from '@tractor/rules';
import {
  exerciseListSchema,
  exerciseSuccessSchema,
  exerciseViewSchema,
  previewResponseSchema,
} from '@tractor/protocol';
import type {
  ExerciseSummary,
  ExerciseView,
  PreviewRequest,
  PreviewResponse,
} from '@tractor/protocol';

const suitSymbols: Record<Suit, string> = {
  clubs: '♣',
  diamonds: '♦',
  hearts: '♥',
  spades: '♠',
};
const initialSettings: PreviewRequest = {
  playerCount: 4,
  level: '2',
  trumpSuit: 'spades',
};
const categoryOrder: Category[] = [
  'trump',
  'spades',
  'hearts',
  'clubs',
  'diamonds',
];

function cardLabel(card: Card) {
  return card.kind === 'joker'
    ? `${card.joker === 'big' ? 'Big' : 'Small'} joker`
    : `${card.rank} of ${card.suit}`;
}

function PlayingCard({
  card,
  selected,
  onToggle,
}: {
  card: Card;
  selected: boolean;
  onToggle: () => void;
}) {
  const red =
    card.kind === 'joker'
      ? card.joker === 'big'
      : card.suit === 'hearts' || card.suit === 'diamonds';
  return (
    <button
      className={`playing-card ${red ? 'red' : ''} ${selected ? 'selected' : ''}`}
      type="button"
      aria-label={cardLabel(card)}
      aria-pressed={selected}
      onClick={onToggle}
    >
      {card.kind === 'suited' ? (
        <>
          <span className="card-rank">{card.rank}</span>
          <span className="card-suit" aria-hidden="true">
            {suitSymbols[card.suit]}
          </span>
        </>
      ) : (
        <>
          <span className="joker-rank">
            {card.joker === 'big' ? 'BIG' : 'SMALL'}
          </span>
          <span className="joker-symbol" aria-hidden="true">
            ✦
          </span>
          <span className="joker-word">JOKER</span>
        </>
      )}
      {selected && (
        <span className="card-check" aria-hidden="true">
          ✓
        </span>
      )}
    </button>
  );
}

function Table({ preview }: { preview: PreviewResponse | null }) {
  return (
    <div className="table-scene" aria-label="Counterclockwise seating preview">
      <div className="table-felt">
        <div className="table-center">
          <span className="eyebrow">A PLACE AT THE TABLE</span>
          <div className="table-wordmark">拖拉机</div>
          <p>Partners in every other seat.</p>
          <span className="table-direction">
            ↺ &nbsp; Counterclockwise play
          </span>
        </div>
      </div>
      {preview?.seats.map(({ seat, team, cardCount }) => {
        const angle =
          ((90 - (seat * 360) / preview.settings.playerCount) * Math.PI) / 180;
        const style = {
          '--seat-x': `${50 + 41 * Math.cos(angle)}%`,
          '--seat-y': `${50 + 40 * Math.sin(angle)}%`,
        } as CSSProperties;
        return (
          <div
            className={`seat team-${team.toLowerCase()} ${seat === 0 ? 'your-seat' : ''}`}
            key={seat}
            style={style}
          >
            <span className="seat-avatar">
              {seat === 0 ? 'You' : String(seat + 1).padStart(2, '0')}
            </span>
            <span className="seat-name">
              {seat === 0 ? 'Your seat' : `Seat ${seat + 1}`}
            </span>
            <span className="seat-meta">
              Team {team} · {cardCount} cards
            </span>
          </div>
        );
      })}
      <span className="table-note">
        {preview
          ? `${preview.kittyCount} cards in the kitty`
          : 'Preparing the table…'}
      </span>
    </div>
  );
}

function TrickDrills() {
  const [list, setList] = useState<ExerciseSummary[]>([]);
  const [exercise, setExercise] = useState<ExerciseView | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  useEffect(() => {
    void fetch('/api/practice-tricks')
      .then((response) => response.json())
      .then((body) => setList(exerciseListSchema.parse(body).exercises))
      .catch(() => setMessage('Practice drills are unavailable right now.'));
  }, []);
  async function choose(id: string) {
    setBusy(true);
    setMessage('');
    setSelected(new Set());
    try {
      const response = await fetch(`/api/practice-tricks/${id}`);
      if (!response.ok) throw new Error();
      setExercise(exerciseViewSchema.parse(await response.json()));
    } catch {
      setMessage('Could not load that drill.');
    } finally {
      setBusy(false);
    }
  }
  async function submit() {
    if (!exercise || selected.size === 0) return;
    setBusy(true);
    try {
      const response = await fetch(
        `/api/practice-tricks/${exercise.id}/attempt`,
        {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ cardIds: [...selected] }),
        },
      );
      const body = await response.json();
      if (!response.ok) {
        setMessage(body.message ?? 'That selection is not legal.');
        return;
      }
      const result = exerciseSuccessSchema.parse(body);
      setExercise(result.view);
      setSelected(new Set());
      setMessage(result.message);
    } catch {
      setMessage('Could not submit that play.');
    } finally {
      setBusy(false);
    }
  }
  return (
    <section className="drills panel" id="trick-drills">
      <div className="section-heading">
        <div>
          <p className="eyebrow">RULE DRILLS</p>
          <h2>Play the tricky parts.</h2>
          <p className="muted">
            Short, guided situations from the rulebook. The server judges every
            selection.
          </p>
        </div>
        {exercise && (
          <button
            className="text-button"
            type="button"
            onClick={() => {
              setExercise(null);
              setMessage('');
            }}
          >
            All drills
          </button>
        )}
      </div>
      {!exercise ? (
        <div className="drill-list">
          {list.map((item, index) => (
            <button
              type="button"
              className="drill-card"
              key={item.id}
              onClick={() => void choose(item.id)}
              disabled={busy}
            >
              <span className="drill-index">
                {String(index + 1).padStart(2, '0')}
              </span>
              <span>
                <strong>{item.title}</strong>
                <small>{item.description}</small>
              </span>
              <span aria-hidden="true">↗</span>
            </button>
          ))}
        </div>
      ) : (
        <div className="drill-play">
          <div className="drill-copy">
            <span className="drill-tag">DRILL / {exercise.id}</span>
            <h3>{exercise.title}</h3>
            <p>{exercise.description}</p>
            <p className="drill-tip">{exercise.tip}</p>
          </div>
          <div className="drill-hand">
            {exercise.hand.map((card) => (
              <PlayingCard
                key={card.id}
                card={card}
                selected={selected.has(card.id)}
                onToggle={() =>
                  setSelected((old) => {
                    const next = new Set(old);
                    if (next.has(card.id)) next.delete(card.id);
                    else next.add(card.id);
                    return next;
                  })
                }
              />
            ))}
          </div>
          <button
            className="primary-button drill-submit"
            type="button"
            onClick={() => void submit()}
            disabled={busy || selected.size === 0}
          >
            {busy ? 'Checking…' : 'Play selected cards'}
            <span aria-hidden="true">↗</span>
          </button>
          {message && (
            <p className="drill-message" aria-live="polite">
              {message}
            </p>
          )}
        </div>
      )}
    </section>
  );
}

export function App() {
  const [draft, setDraft] = useState<PreviewRequest>(initialSettings);
  const [preview, setPreview] = useState<PreviewResponse | null>(null);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [score, setScore] = useState(0);
  const controller = useRef<AbortController | null>(null);

  async function loadPreview(settings: PreviewRequest) {
    controller.current?.abort();
    const requestController = new AbortController();
    controller.current = requestController;
    setLoading(true);
    setError('');
    try {
      const response = await fetch('/api/practice-preview', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(settings),
        signal: AbortSignal.any([
          requestController.signal,
          AbortSignal.timeout(10000),
        ]),
      });
      if (!response.ok)
        throw new Error('Unable to deal a hand. Please try again.');
      const result = previewResponseSchema.parse(await response.json());
      if (requestController.signal.aborted) return;
      setPreview(result);
      setSelected(new Set());
      setScore(0);
    } catch {
      if (!requestController.signal.aborted)
        setError(
          'Could not reach the table. Check your connection and try dealing again.',
        );
    } finally {
      if (!requestController.signal.aborted) setLoading(false);
    }
  }

  useEffect(() => {
    void loadPreview(initialSettings);
    return () => controller.current?.abort();
  }, []);

  const activeSettings = preview?.settings ?? initialSettings;
  const config = gameConfig(activeSettings.playerCount);
  const draftConfig = gameConfig(draft.playerCount);
  const trump: Trump = {
    level: activeSettings.level,
    suit: activeSettings.trumpSuit,
  };
  const hand = [...(preview?.hand ?? [])].sort(
    (a, b) =>
      effectivePower(b, trump) - effectivePower(a, trump) ||
      a.id.localeCompare(b.id),
  );
  const selectedCards = hand.filter((card) => selected.has(card.id));
  const structure = homogeneousStructure(selectedCards, trump);
  const selectionLabel =
    selected.size === 0
      ? 'Select a few cards to explore your hand.'
      : structure
        ? structure.rankCount > 1
          ? `${structure.rankCount}-rank tractor · ${structure.multiplicity} of each`
          : ({ 1: 'Single', 2: 'Pair', 3: 'Triple', 4: 'Quad' }[
              structure.multiplicity
            ] ?? `${structure.multiplicity} of a kind`)
        : 'Mixed selection · this preview recognizes single structures only';
  const outcome = scoreOutcome(activeSettings.playerCount, score);
  const scoreLevel = advanceLevel(activeSettings.level, outcome.levels);

  function submit(event: FormEvent) {
    event.preventDefault();
    void loadPreview(draft);
  }
  function toggle(id: string) {
    setSelected((previous) => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  return (
    <div className="app-shell">
      <header className="site-header">
        <a className="brand" href="/" aria-label="Tractor home">
          <span className="brand-mark" aria-hidden="true">
            ♠
          </span>
          <span>
            tractor<span className="brand-subtitle">升级 / 拖拉机</span>
          </span>
        </a>
        <div className="header-right">
          <a href="#bot-match">Play against bots</a>
          <a href="#field-notes">
            How it works <span aria-hidden="true">↗</span>
          </a>
          <span className="preview-badge">Solo play</span>
        </div>
      </header>

      <main>
        <section className="page-intro">
          <div>
            <p className="eyebrow">THE PARTNERSHIP CARD GAME</p>
            <h1>Good hands. Better partners.</h1>
            <p>Find your seat, get to know your cards, and learn the climb.</p>
          </div>
          <span className="intro-number" aria-hidden="true">
            02 <span>→ A</span>
          </span>
        </section>
        <div className="workspace">
          <aside className="sidebar">
            <section className="panel settings-panel">
              <p className="eyebrow">SET THE TABLE</p>
              <h2>Your next hand</h2>
              <p className="muted">Try a sample deal at any level.</p>
              <form onSubmit={submit}>
                <fieldset disabled={loading}>
                  <legend>Players</legend>
                  <div className="player-options">
                    {PLAYER_COUNTS.map((count) => (
                      <label
                        className={draft.playerCount === count ? 'chosen' : ''}
                        key={count}
                      >
                        <input
                          type="radio"
                          name="players"
                          value={count}
                          checked={draft.playerCount === count}
                          onChange={() =>
                            setDraft({ ...draft, playerCount: count })
                          }
                        />
                        <span>{count}</span>
                      </label>
                    ))}
                  </div>
                  <div className="select-row">
                    <label>
                      Level
                      <select
                        value={draft.level}
                        onChange={(event) =>
                          setDraft({
                            ...draft,
                            level: event.target.value as Rank,
                          })
                        }
                      >
                        {RANKS.map((rank) => (
                          <option key={rank}>{rank}</option>
                        ))}
                      </select>
                    </label>
                    <label>
                      Trump
                      <select
                        value={draft.trumpSuit ?? 'none'}
                        onChange={(event) =>
                          setDraft({
                            ...draft,
                            trumpSuit:
                              event.target.value === 'none'
                                ? null
                                : (event.target.value as Suit),
                          })
                        }
                      >
                        <option value="none">No suit</option>
                        {SUITS.map((suit) => (
                          <option value={suit} key={suit}>
                            {suitSymbols[suit]}{' '}
                            {suit[0]!.toUpperCase() + suit.slice(1)}
                          </option>
                        ))}
                      </select>
                    </label>
                  </div>
                  <div className="settings-summary">
                    <span>{draftConfig.decks} decks</span>
                    <span>{draftConfig.handSize} cards each</span>
                    <span>{draftConfig.kittySize} in the kitty</span>
                  </div>
                  <button className="primary-button" type="submit">
                    {loading ? 'Dealing…' : 'Deal a sample hand'}
                    <span aria-hidden="true">↗</span>
                  </button>
                </fieldset>
              </form>
              {error && (
                <p className="error-message" role="alert">
                  {error}
                </p>
              )}
              <p className="fine-print">
                Explore cards and structures here. Online rooms and playing
                tricks are not available in this preview.
              </p>
            </section>

            <section className="panel score-panel">
              <p className="eyebrow">LEARN THE CLIMB</p>
              <h2>Every point counts.</h2>
              <p className="muted">Move the score to see who advances.</p>
              <label className="score-label" htmlFor="defender-score">
                Defender points{' '}
                <output htmlFor="defender-score">{score}</output>
              </label>
              <input
                id="defender-score"
                type="range"
                min={-20}
                max={config.interval * 8}
                step={5}
                value={score}
                onChange={(event) => setScore(Number(event.target.value))}
              />
              <div className="range-labels">
                <span>−20</span>
                <span>{config.interval * 8}</span>
              </div>
              <div className="score-result" aria-live="polite">
                <strong>
                  {outcome.advancingRole === 'attackers'
                    ? 'Attackers'
                    : 'Defenders'}{' '}
                  {outcome.levels > 0
                    ? `+${outcome.levels} levels`
                    : 'take over'}
                </strong>
                <span>
                  {outcome.swapRoles
                    ? 'Teams swap roles.'
                    : 'Attackers keep their role.'}{' '}
                  {outcome.levels > 0
                    ? `From level ${activeSettings.level}: ${scoreLevel.level}${scoreLevel.wonMatch ? ' — match won' : ''}.`
                    : ''}
                </span>
              </div>
              <p className="fine-print">
                {config.interval}-point intervals · swap at{' '}
                {config.swapThreshold}. Example assumes the advancing team is on
                level {activeSettings.level}. Teams must stop at J before
                advancing beyond it.
              </p>
            </section>
          </aside>

          <div className="table-column" aria-busy={loading}>
            <section className="table-panel">
              <div className="table-toolbar">
                <div>
                  <span className="status-dot" />
                  Practice table{' '}
                  <span className="toolbar-muted">
                    / {activeSettings.playerCount} seats
                  </span>
                </div>
                <span className="trump-tag">
                  {activeSettings.trumpSuit
                    ? `${suitSymbols[activeSettings.trumpSuit]} ${activeSettings.trumpSuit}`
                    : 'No-suit trump'}{' '}
                  <span>· Level {activeSettings.level}</span>
                </span>
              </div>
              <Table preview={preview} />
              <div className="table-footer">
                <span>
                  <i className="team-dot a" />
                  Team A
                </span>
                <span>
                  <i className="team-dot b" />
                  Team B
                </span>
                <span>Other hands stay private</span>
              </div>
            </section>

            <section className="panel hand-panel" aria-label="Your hand">
              <div className="section-heading">
                <div>
                  <p className="eyebrow">YOUR HAND</p>
                  <h2>{hand.length} cards. A little possibility.</h2>
                </div>
                <span className="hand-point-total">
                  {hand.reduce((sum, card) => sum + cardPoints(card), 0)} points
                  in hand
                </span>
              </div>
              <div className="hand-groups">
                {categoryOrder.map((group) => {
                  const cards = hand.filter(
                    (card) => category(card, trump) === group,
                  );
                  return cards.length ? (
                    <div className="hand-group" key={group}>
                      <h3>
                        {group === 'trump'
                          ? '✦ Trump'
                          : `${suitSymbols[group]} ${group}`}{' '}
                        <span>{cards.length}</span>
                      </h3>
                      <div className="cards">
                        {cards.map((card) => (
                          <PlayingCard
                            key={card.id}
                            card={card}
                            selected={selected.has(card.id)}
                            onToggle={() => toggle(card.id)}
                          />
                        ))}
                      </div>
                    </div>
                  ) : null;
                })}
              </div>
              <div className="selection-bar">
                <div aria-live="polite">
                  <strong>{selected.size} selected</strong>
                  <span>{selectionLabel}</span>
                </div>
                <button
                  type="button"
                  className="text-button"
                  disabled={selected.size === 0}
                  onClick={() => setSelected(new Set())}
                >
                  Clear selection
                </button>
              </div>
            </section>
          </div>
        </div>

        <BotMatchTable />
        <RoomMatch />
        <TrickDrills />

        <section className="field-notes" id="field-notes">
          <div>
            <p className="eyebrow">FIELD NOTES</p>
            <h2>A few things to keep in hand.</h2>
          </div>
          <div className="notes-grid">
            <article>
              <span>01 / THE TEAM</span>
              <h3>Play for your partners.</h3>
              <p>
                Teams alternate around the table. Attackers protect the score;
                defenders capture point cards. Play always moves
                counterclockwise.
              </p>
            </article>
            <article>
              <span>02 / THE CARDS</span>
              <h3>Same face. Stronger together.</h3>
              <p>
                Pairs share a rank and suit. Consecutive pairs make a tractor.
                Level cards become trump, closing the gap in their original
                suits.
              </p>
            </article>
            <article>
              <span>03 / THE CLIMB</span>
              <h3>Start at 2. Reach the ace.</h3>
              <p>
                Fives are worth 5 points; tens and kings are worth 10. Each deck
                adds a 20-point interval. You must stop at J and win there to
                pass it.
              </p>
            </article>
          </div>
        </section>
      </main>
      <footer className="site-footer">
        <span>
          tractor{' '}
          <span className="footer-suits" aria-hidden="true">
            ♣ ♦ ♥ ♠
          </span>
        </span>
        <span>Made for a table full of people.</span>
      </footer>
    </div>
  );
}
