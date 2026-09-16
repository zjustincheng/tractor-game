import { useEffect, useMemo, useRef, useState } from 'react';
import type { FormEvent } from 'react';
import {
  roomEventsSchema,
  roomGameViewSchema,
  roomViewSchema,
} from '@tractor/protocol';
import type { Card } from '@tractor/rules';
import type { RoomGameView, RoomView } from '@tractor/protocol';

const tokenKey = 'tractor-room-token';
const codeKey = 'tractor-room-code';
function label(card: Card) {
  return card.kind === 'joker'
    ? `${card.joker === 'big' ? 'Big' : 'Small'} joker`
    : `${card.rank}${card.suit[0]?.toUpperCase()}`;
}

export function RoomMatch() {
  const [room, setRoom] = useState<RoomView | null>(null);
  const [game, setGame] = useState<RoomGameView | null>(null);
  const [code, setCode] = useState(() => localStorage.getItem(codeKey) ?? '');
  const [token, setToken] = useState(
    () => localStorage.getItem(tokenKey) ?? '',
  );
  const [name, setName] = useState('');
  const [playerCount, setPlayerCount] = useState(4);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);
  const [revision, setRevision] = useState(0);
  const [clock, setClock] = useState(() => Date.now());
  const pollSequence = useRef(0);

  const request = async (path: string, body?: unknown) => {
    const response = await fetch(
      path,
      body
        ? {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
          }
        : undefined,
    );
    const payload = await response.json();
    if (!response.ok)
      throw new Error(payload.message ?? 'Room request failed.');
    return payload;
  };
  async function create(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage('');
    try {
      const result = await request('/api/rooms', {
        playerCount,
        displayName: name,
      });
      enter(result.room, result.playerToken);
    } catch (error) {
      setMessage(
        error instanceof Error ? error.message : 'Could not create room.',
      );
    } finally {
      setBusy(false);
    }
  }
  async function join(event: FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage('');
    try {
      const result = await request(
        `/api/rooms/${code.trim().toUpperCase()}/join`,
        { displayName: name },
      );
      enter(result.room, result.playerToken);
    } catch (error) {
      setMessage(
        error instanceof Error ? error.message : 'Could not join room.',
      );
    } finally {
      setBusy(false);
    }
  }
  function enter(nextRoom: RoomView, nextToken: string) {
    setRoom(nextRoom);
    setToken(nextToken);
    setCode(nextRoom.code);
    setRevision(0);
    localStorage.setItem(codeKey, nextRoom.code);
    localStorage.setItem(tokenKey, nextToken);
  }
  useEffect(() => {
    if (!room || !token) return;
    let active = true;
    const poll = async () => {
      const sequence = ++pollSequence.current;
      try {
        const events = roomEventsSchema.parse(
          await request(
            `/api/rooms/${room.code}/events?token=${token}&after=${revision}`,
          ),
        );
        if (!active || sequence !== pollSequence.current) return;
        setRoom(events.room);
        setRevision(events.revision);
        if (events.room.started) {
          const next = roomGameViewSchema.parse(
            await request(`/api/rooms/${room.code}/game?token=${token}`),
          );
          if (active) setGame(next);
        }
      } catch {
        /* transient disconnects are retried on the next poll */
      }
    };
    void poll();
    const timer = window.setInterval(() => void poll(), 1000);
    return () => {
      active = false;
      window.clearInterval(timer);
    };
  }, [room?.code, token, revision]);
  useEffect(() => {
    const timer = window.setInterval(() => setClock(Date.now()), 250);
    return () => window.clearInterval(timer);
  }, []);
  async function command(
    action:
      | 'ready'
      | 'declare'
      | 'advance'
      | 'bury'
      | 'play'
      | 'next-trick'
      | 'next-round',
    cardIds?: string[],
  ) {
    if (!room || !token) return;
    pollSequence.current += 1;
    setBusy(true);
    setMessage('');
    try {
      if (action === 'ready')
        setRoom(
          roomViewSchema.parse(
            await request(`/api/rooms/${room.code}/ready`, {
              token,
              ready: !room.players.find((p) => p.seat === room.viewerSeat)
                ?.ready,
            }),
          ),
        );
      else if (game)
        setGame(
          roomGameViewSchema.parse(
            await request(`/api/rooms/${room.code}/game/commands`, {
              action,
              token,
              revision: game.revision,
              cardIds,
            }),
          ),
        );
      setSelected(new Set());
    } catch (error) {
      setMessage(
        error instanceof Error ? error.message : 'That action was rejected.',
      );
    } finally {
      setBusy(false);
    }
  }
  const selectedIds = useMemo(() => [...selected], [selected]);
  if (!room)
    return (
      <section className="panel room-panel" id="play-room">
        <div className="section-heading">
          <div>
            <p className="eyebrow">PLAY TOGETHER</p>
            <h2>Join a live room.</h2>
            <p className="muted">
              Create a table or enter a six-character room code.
            </p>
          </div>
        </div>
        <form className="room-form" onSubmit={create}>
          <label>
            Name
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              required
              maxLength={32}
            />
          </label>
          <label>
            Seats
            <select
              value={playerCount}
              onChange={(e) => setPlayerCount(Number(e.target.value))}
            >
              {[4, 6, 8, 10].map((count) => (
                <option key={count}>{count}</option>
              ))}
            </select>
          </label>
          <button className="primary-button" disabled={busy}>
            Create room
          </button>
        </form>
        <form className="room-form room-join" onSubmit={join}>
          <label>
            Room code
            <input
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              maxLength={6}
              required
            />
          </label>
          <button className="secondary-button" disabled={busy || !name}>
            Join room
          </button>
        </form>
        {message && <p className="error-text">{message}</p>}
      </section>
    );
  const me = room.players.find((p) => p.seat === room.viewerSeat);
  return (
    <section className="panel room-panel" id="play-room">
      <div className="room-heading">
        <div>
          <p className="eyebrow">LIVE ROOM</p>
          <h2>Room {room.code}</h2>
          <p className="muted">
            Seat {room.viewerSeat + 1} · Share the code with your table.
          </p>
        </div>
        <button
          className="text-button"
          onClick={() => {
            localStorage.removeItem(codeKey);
            localStorage.removeItem(tokenKey);
            setRoom(null);
            setGame(null);
          }}
        >
          Leave
        </button>
      </div>
      <div className="room-players">
        {Array.from({ length: room.playerCount }, (_, seat) => {
          const player = room.players.find((p) => p.seat === seat);
          return (
            <div
              className={`room-player ${player ? 'occupied' : ''}`}
              key={seat}
            >
              <strong>Seat {seat + 1}</strong>
              <span>{player?.displayName ?? 'Waiting…'}</span>
              {player && <small>{player.ready ? 'Ready' : 'Not ready'}</small>}
            </div>
          );
        })}
      </div>
      {!room.started ? (
        <>
          <button
            className="primary-button"
            onClick={() => void command('ready')}
            disabled={busy}
          >
            {me?.ready ? 'Not ready' : 'Ready up'}
          </button>
          <p className="muted">
            Everyone must ready up before the dealer deals.
          </p>
        </>
      ) : game ? (
        <div className="room-game">
          <div className="room-status">
            <strong>
              {game.phase === 'declaration'
                ? 'Trump declaration'
                : game.phase === 'kitty'
                  ? 'Kitty exchange'
                  : `Turn: seat ${(game.nextSeat ?? 0) + 1}`}
            </strong>
            <span>{game.message}</span>
          </div>
          <div className="room-identity" aria-label="Room strategy context">
            <span>
              <strong>Your team</strong> Team{' '}
              {game.viewerSeat % 2 === 0 ? 'A' : 'B'} ·{' '}
              {game.attackingTeam === (game.viewerSeat % 2 === 0 ? 'A' : 'B')
                ? 'Attackers'
                : 'Defenders'}
            </span>
            <span>
              <strong>Levels</strong> A {game.levels.A} · B {game.levels.B}
            </span>
            <span>
              <strong>Defender score</strong> {game.defenderScore}
            </span>
            <span>
              <strong>Dealer</strong> Seat {game.dealerSeat + 1}
            </span>
          </div>
          <div className="room-players room-game-players">
            {game.players.map((player) => (
              <div
                className={`room-player ${player.seat === game.viewerSeat ? 'current' : ''}`}
                key={player.seat}
              >
                <strong>
                  Seat {player.seat + 1}
                  {player.seat === game.viewerSeat
                    ? ' · You'
                    : player.seat === (game.viewerSeat + 2) % game.playerCount
                      ? ' · Partner'
                      : ''}
                </strong>
                <span>{player.displayName}</span>
                <small>{player.cardCount} cards</small>
              </div>
            ))}
          </div>
          {game.plays.length > 0 && (
            <div className="room-trick" aria-label="Current trick">
              <div className="room-trick-heading">
                <strong>
                  {game.trickComplete
                    ? `Trick won by seat ${(game.winnerSeat ?? 0) + 1}`
                    : `Trick · seat ${(game.nextSeat ?? 0) + 1} to play`}
                </strong>
                <span>
                  {game.plays.reduce((sum, play) => sum + play.cards.length, 0)}{' '}
                  cards played
                </span>
              </div>
              <div className="room-plays">
                {game.plays.map((play) => (
                  <div
                    className={`room-play ${play.seat === game.winnerSeat ? 'winning' : ''}`}
                    key={play.seat}
                  >
                    <strong>Seat {play.seat + 1}</strong>
                    <span>{play.cards.map(label).join(' · ')}</span>
                    <small>
                      {play.matchesLead ? 'Matches lead' : 'Cannot win'}
                    </small>
                  </div>
                ))}
              </div>
            </div>
          )}
          {game.phase === 'declaration' && (
            <div
              className="deal-progress"
              aria-label="Synchronized deal progress"
            >
              <span>Dealing from server</span>
              <progress
                max={game.dealingDurationMs}
                value={Math.min(
                  game.dealingDurationMs,
                  Math.max(0, clock - game.dealingStartedAt),
                )}
              />
            </div>
          )}
          {game.declarationOptions.length > 0 && (
            <div className="room-options">
              <p className="eyebrow">AVAILABLE CALLS</p>
              {game.declarationOptions.map((option) => (
                <button
                  className="secondary-button"
                  key={option.cardIds.join('|')}
                  onClick={() => void command('declare', option.cardIds)}
                  disabled={busy}
                >
                  {option.kind === 'joker'
                    ? `${option.joker} jokers`
                    : `${option.multiplicity}× ${option.suit}`}
                </button>
              ))}
              <button
                className="text-button"
                onClick={() => void command('advance')}
                disabled={busy}
              >
                Pass
              </button>
            </div>
          )}
          {game.phase !== 'declaration' && (
            <>
              <div className="room-table">
                <span>
                  Trump:{' '}
                  {game.trump ? (game.trump.suit ?? 'No suit') : 'Undeclared'}
                </span>
                <span>Kitty: {game.kittyCount} cards</span>
              </div>
              <div className="room-hand">
                {game.hand.map((card) => (
                  <button
                    type="button"
                    className={`room-card ${selected.has(card.id) ? 'selected' : ''}`}
                    key={card.id}
                    onClick={() =>
                      setSelected((current) => {
                        const next = new Set(current);
                        if (next.has(card.id)) next.delete(card.id);
                        else next.add(card.id);
                        return next;
                      })
                    }
                  >
                    {label(card)}
                  </button>
                ))}
              </div>
              {game.phase === 'kitty' && game.viewerSeat === 0 && (
                <button
                  className="primary-button"
                  disabled={busy || selected.size !== game.kittyCount}
                  onClick={() => void command('bury', selectedIds)}
                >
                  Bury selected
                </button>
              )}
              {game.phase === 'tricks' && game.nextSeat === game.viewerSeat && (
                <button
                  className="primary-button"
                  disabled={busy || selected.size === 0}
                  onClick={() => void command('play', selectedIds)}
                >
                  Play selected
                </button>
              )}
              {game.phase === 'tricks' && game.trickComplete && (
                <button
                  className="secondary-button"
                  disabled={busy}
                  onClick={() => void command('next-trick')}
                >
                  {game.hand.length === 0 ? 'Finish round' : 'Next trick'}
                </button>
              )}
              {game.phase === 'finished' &&
                game.settlement &&
                !game.settlement.winner && (
                  <button
                    className="primary-button"
                    disabled={busy || game.viewerSeat !== 0}
                    onClick={() => void command('next-round')}
                  >
                    Start next round
                  </button>
                )}
            </>
          )}
        </div>
      ) : (
        <p>Loading game…</p>
      )}
      {message && <p className="error-text">{message}</p>}
    </section>
  );
}
