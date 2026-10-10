import { useEffect, useMemo, useState } from 'react';

type ReplayEvent = {
  revision: number;
  actor?: 'player' | 'bot' | 'system';
  action: string;
  seat?: number;
  round?: number;
  trick?: number;
  winnerSeat?: number;
  cardIds?: string[];
  detail?: string;
  rating?: string;
  at: number;
};
type ReplayCard = {
  id: string;
  kind: 'suited' | 'joker';
  suit?: string;
  rank?: string;
  joker?: string;
};
type ReplayArchive = {
  format: number;
  id: string;
  replay: {
    rulesVersion: string;
    createdAt: number;
    deals: {
      round: number;
      dealerSeat: number;
      attackingTeam: string;
      hands?: ReplayCard[][];
      kitty?: ReplayCard[];
    }[];
  } | null;
  events: ReplayEvent[];
};

function isArchive(value: unknown): value is ReplayArchive {
  if (!value || typeof value !== 'object') return false;
  const item = value as Partial<ReplayArchive>;
  return (
    item.format === 1 &&
    typeof item.id === 'string' &&
    Array.isArray(item.events) &&
    (item.replay === null || typeof item.replay === 'object')
  );
}
function replayCardLabel(card: ReplayCard) {
  return card.kind === 'joker'
    ? `${card.joker === 'big' ? 'Big' : 'Small'} joker`
    : `${card.rank} ${card.suit}`;
}

export function ReplayViewer() {
  const [archive, setArchive] = useState<ReplayArchive | null>(null);
  const [cursor, setCursor] = useState(0);
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState(1);
  const [filter, setFilter] = useState<
    'all' | 'player' | 'bot' | 'system' | 'gamble'
  >('all');
  const [message, setMessage] = useState(
    'Choose an exported match JSON file to begin.',
  );
  const visibleEvents = useMemo(
    () =>
      (archive?.events.slice(0, cursor) ?? []).filter(
        (event) =>
          filter === 'all' ||
          (filter === 'gamble'
            ? event.detail === 'validated gamble'
            : event.actor === filter),
      ),
    [archive, cursor, filter],
  );
  const cardNames = useMemo(() => {
    const cards =
      archive?.replay?.deals.flatMap((deal) => [
        ...(deal.hands?.flat() ?? []),
        ...(deal.kitty ?? []),
      ]) ?? [];
    return new Map(
      cards.map((card) => [
        card.id,
        card.kind === 'joker'
          ? `${card.joker === 'big' ? 'Big' : 'Small'} joker`
          : `${card.rank} ${card.suit}`,
      ]),
    );
  }, [archive]);
  const eventGroups = useMemo(() => {
    const groups = new Map<number, ReplayEvent[]>();
    for (const event of visibleEvents) {
      const group = groups.get(event.revision) ?? [];
      group.push(event);
      groups.set(event.revision, group);
    }
    return [...groups.entries()];
  }, [visibleEvents]);
  const tableState = useMemo(() => {
    const currentTrick: { seat: number; cardIds: string[]; actor: string }[] =
      [];
    let round: number | undefined;
    let trick: number | undefined;
    let winnerSeat: number | undefined;
    for (const event of archive?.events.slice(0, cursor) ?? []) {
      if (event.action === 'trick-complete') {
        winnerSeat = event.winnerSeat;
        currentTrick.splice(0, currentTrick.length);
        continue;
      }
      if (event.round !== undefined) round = event.round;
      if (event.trick !== undefined) trick = event.trick;
      if (event.action !== 'play' || !event.cardIds?.length) continue;
      currentTrick.push({
        seat: event.seat ?? (event.actor === 'player' ? 0 : -1),
        cardIds: event.cardIds,
        actor: event.actor ?? 'system',
      });
      winnerSeat = undefined;
    }
    return { currentTrick, round, trick, winnerSeat };
  }, [archive, cursor]);
  const replayStart = archive?.replay?.createdAt ?? archive?.events[0]?.at ?? 0;
  useEffect(() => {
    if (!playing || !archive) return;
    if (cursor >= archive.events.length) {
      setPlaying(false);
      return;
    }
    const timer = window.setTimeout(
      () =>
        setCursor((position) => Math.min(archive.events.length, position + 1)),
      900 / speed,
    );
    return () => window.clearTimeout(timer);
  }, [playing, archive, cursor, speed]);
  async function load(file: File) {
    try {
      const parsed: unknown = JSON.parse(await file.text());
      if (!isArchive(parsed)) throw new Error();
      setArchive(parsed);
      setCursor(parsed.events.length);
      setPlaying(false);
      setMessage('Replay loaded. Use the timeline to review accepted actions.');
    } catch {
      setArchive(null);
      setCursor(0);
      setMessage('That file is not a valid Tractor replay archive.');
    }
  }
  return (
    <div className="app-shell replay-page">
      <header className="site-header">
        <a className="brand" href="/">
          <span className="brand-mark">拖</span>
          <span>
            tractor <small className="brand-subtitle">REPLAY DESK</small>
          </span>
        </a>
        <a className="preview-badge" href="/">
          Back to table
        </a>
      </header>
      <main>
        <section className="replay-intro">
          <p className="eyebrow">MATCH ARCHIVE</p>
          <h1>Review a table at your pace.</h1>
          <p>Watch the cards play out, then inspect each accepted action.</p>
          <label className="replay-upload">
            <span>Choose replay JSON</span>
            <input
              type="file"
              accept="application/json,.json"
              onChange={(event) =>
                event.target.files?.[0] && void load(event.target.files[0])
              }
            />
          </label>
          <p className="replay-message" role="status">
            {message}
          </p>
        </section>
        {archive && (
          <section className="replay-panel" aria-label="Replay timeline">
            <div className="replay-summary">
              <div>
                <span>Match</span>
                <strong>{archive.id.slice(0, 8)}…</strong>
              </div>
              <div>
                <span>Rules</span>
                <strong>{archive.replay?.rulesVersion ?? 'Unknown'}</strong>
              </div>
              <div>
                <span>Rounds dealt</span>
                <strong>{archive.replay?.deals.length ?? 0}</strong>
              </div>
              <div>
                <span>Actions</span>
                <strong>{archive.events.length}</strong>
              </div>
            </div>
            <div className="replay-deals">
              <h2>Deals</h2>
              {archive.replay?.deals.map((deal) => (
                <details key={deal.round} open={deal.round === 1}>
                  <summary>
                    Round {deal.round} · Dealer seat {deal.dealerSeat + 1} ·
                    Team {deal.attackingTeam} attacks
                  </summary>
                  <div className="replay-deal-seats">
                    {(deal.hands ?? []).map((hand, seat) => (
                      <span key={seat}>
                        Seat {seat + 1}: {hand.length} cards
                      </span>
                    ))}
                  </div>
                  {deal.kitty?.length ? (
                    <p>Kitty: {deal.kitty.map(replayCardLabel).join(' · ')}</p>
                  ) : null}
                </details>
              ))}
            </div>
            <div className="replay-controls">
              <button
                type="button"
                onClick={() => {
                  if (cursor >= archive.events.length) setCursor(0);
                  setPlaying((value) => !value);
                }}
                aria-label={playing ? 'Pause replay' : 'Play replay'}
              >
                {playing ? 'Pause' : 'Play'}
              </button>
              <label>
                Speed
                <select
                  value={speed}
                  onChange={(event) => setSpeed(Number(event.target.value))}
                  aria-label="Replay speed"
                >
                  <option value={0.5}>0.5×</option>
                  <option value={1}>1×</option>
                  <option value={2}>2×</option>
                  <option value={4}>4×</option>
                </select>
              </label>
              <button
                type="button"
                onClick={() => {
                  setPlaying(false);
                  setCursor(0);
                }}
                disabled={cursor === 0}
              >
                Beginning
              </button>
              <input
                type="range"
                min="0"
                max={archive.events.length}
                value={cursor}
                onChange={(event) => setCursor(Number(event.target.value))}
                aria-label="Replay position"
              />
              <button
                type="button"
                onClick={() => {
                  setPlaying(false);
                  setCursor(archive.events.length);
                }}
                disabled={cursor === archive.events.length}
              >
                Latest
              </button>
              <span>
                {cursor} / {archive.events.length}
              </span>
            </div>
            <section
              className="replay-table"
              aria-label="Animated replay table"
            >
              <div className="replay-table-heading">
                <strong>
                  {tableState.round === undefined
                    ? 'Match replay'
                    : `Round ${tableState.round}${tableState.trick === undefined ? '' : ` · Trick ${tableState.trick}`}`}
                </strong>
                {tableState.winnerSeat !== undefined && (
                  <span>Trick won by Seat {tableState.winnerSeat + 1}</span>
                )}
              </div>
              <div className="replay-felt">
                {[0, 1, 2, 3].map((seat) => {
                  const play = tableState.currentTrick.find(
                    (item) => item.seat === seat,
                  );
                  const positions = ['south', 'west', 'north', 'east'];
                  return (
                    <div
                      className={`replay-seat ${positions[seat]}`}
                      key={seat}
                    >
                      <span>
                        {seat === 0 ? 'You · Seat 1' : `Seat ${seat + 1}`}
                      </span>
                      <div className="replay-played-cards" aria-live="polite">
                        {play?.cardIds.map((id) => (
                          <span className="replay-playing-card" key={id}>
                            {cardNames.get(id) ?? id}
                          </span>
                        ))}
                      </div>
                    </div>
                  );
                })}
                {tableState.currentTrick.length === 0 && (
                  <p className="replay-table-empty">
                    {cursor === 0
                      ? 'Press Play to watch the match.'
                      : 'Trick complete. Continue to the next play.'}
                  </p>
                )}
              </div>
            </section>
            <div className="replay-filters" aria-label="Filter replay events">
              {(['all', 'player', 'bot', 'system', 'gamble'] as const).map(
                (option) => (
                  <button
                    type="button"
                    className={filter === option ? 'selected' : ''}
                    key={option}
                    onClick={() => setFilter(option)}
                  >
                    {option === 'all'
                      ? 'All actions'
                      : option === 'player'
                        ? 'Your actions'
                        : option === 'bot'
                          ? 'Bot actions'
                          : option === 'system'
                            ? 'Results'
                            : 'Gambles'}
                  </button>
                ),
              )}
            </div>
            <div className="replay-events">
              {eventGroups.length === 0 ? (
                <p>No actions shown yet. Move the timeline forward.</p>
              ) : (
                eventGroups.map(([revision, events]) => (
                  <div className="replay-moment" key={revision}>
                    <span className="replay-moment-label">
                      Moment #{revision}
                    </span>
                    {events.map((event, index) => (
                      <div
                        className={`replay-event ${event.actor ?? 'system'}`}
                        key={`${event.revision}-${index}`}
                      >
                        <span>#{event.revision}</span>
                        <strong>{event.actor ?? 'system'}</strong>
                        <b>{event.action}</b>
                        {event.detail === 'validated gamble' ? (
                          <mark>Gamble</mark>
                        ) : null}
                        {event.rating && event.rating !== 'safe_follow' ? (
                          <mark className={`strategy-${event.rating}`}>
                            {event.rating.replaceAll('_', ' ')}
                          </mark>
                        ) : null}
                        {event.detail ? <small>{event.detail}</small> : null}
                        {event.cardIds?.length ? (
                          <small className="replay-cards">
                            {event.cardIds.map((id) => (
                              <em key={id}>{cardNames.get(id) ?? id}</em>
                            ))}
                          </small>
                        ) : null}
                        <time title={new Date(event.at).toLocaleString()}>
                          +
                          {Math.max(
                            0,
                            Math.round((event.at - replayStart) / 1000),
                          )}
                          s
                        </time>
                      </div>
                    ))}
                  </div>
                ))
              )}
            </div>
          </section>
        )}
      </main>
    </div>
  );
}
