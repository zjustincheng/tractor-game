import type { CSSProperties, ReactNode } from 'react';
import type { BotMatchView } from '@tractor/protocol';
import type { Card } from '@tractor/rules';
import './game-table.css';
const suits = { clubs: '♣', diamonds: '♦', hearts: '♥', spades: '♠' };
export function CardFace({ card }: { card: Card }) {
  return (
    <>
      <span className="face-corner">
        <b className={card.kind === 'joker' ? 'joker-rank' : undefined}>
          {card.kind === 'joker'
            ? card.joker === 'big'
              ? 'BIG'
              : 'SM'
            : card.rank}
        </b>
        <span>{card.kind === 'joker' ? '★' : suits[card.suit]}</span>
      </span>
      <span className="face-center" aria-hidden="true">
        {card.kind === 'joker' ? '✦' : suits[card.suit]}
      </span>
    </>
  );
}
export function cardColor(card: Card) {
  return (
    card.kind === 'suited'
      ? ['hearts', 'diamonds'].includes(card.suit)
      : card.joker === 'big'
  )
    ? 'red'
    : '';
}
export function GameTable({
  view,
  activeSeat,
  children,
}: {
  view: BotMatchView;
  activeSeat: number | null;
  children: ReactNode;
}) {
  return (
    <div className={`felt-scene seats-${view.playerCount}`}>
      <div className="table-hud">
        <span>
          Round {view.round} · Trick {view.trickNumber}
        </span>
        <div className="table-score">
          <span>
            Us <b>{view.levels.A}</b> · Them <b>{view.levels.B}</b>
          </span>
          <span>
            Trump{' '}
            <b>
              {view.trump
                ? `${view.trump.level} ${view.trump.suit ? suits[view.trump.suit] : '★'}`
                : '—'}
            </b>{' '}
            · Defenders <b>{view.defenderScore}</b>
          </span>
        </div>
      </div>
      <div className="felt-arena" aria-label="Current trick">
        <div className="felt-wordmark" aria-hidden="true">
          拖拉机<span>TRACTOR</span>
        </div>
        {view.seats.map((seat) => {
          const angle =
            Math.PI / 2 - (seat.seat * 2 * Math.PI) / view.playerCount;
          const style = {
            '--x': `${50 + 43 * Math.cos(angle)}%`,
            '--y': `${50 + 41 * Math.sin(angle)}%`,
            '--px': `${50 + 25 * Math.cos(angle)}%`,
            '--mobile-x': seat.seat < view.playerCount / 2 ? '92%' : '8%',
            '--mobile-px': seat.seat < view.playerCount / 2 ? '68%' : '32%',
            '--mobile-y': `${(((seat.seat < view.playerCount / 2 ? view.playerCount / 2 - 1 - seat.seat : seat.seat - view.playerCount / 2) + 0.5) * 100) / (view.playerCount / 2)}%`,
            '--py': `${50 + (view.playerCount > 4 ? 28 : 17) * Math.sin(angle)}%`,
          } as CSSProperties;
          const play = view.plays.find((play) => play.seat === seat.seat);
          return (
            <div key={seat.seat} style={style} className="table-position">
              <div
                className={`table-seat ${activeSeat === seat.seat ? 'active' : ''}`}
                aria-label={`Seat ${seat.seat + 1}, team ${seat.team}, ${seat.cardCount} cards`}
              >
                <span
                  className={`table-avatar team-${seat.team}`}
                  aria-hidden="true"
                >
                  {seat.seat === 0 ? 'You' : seat.seat + 1}
                </span>
                <strong>
                  {seat.seat === 0 ? 'You' : `Bot ${seat.seat + 1}`}
                </strong>
                <small>
                  {seat.cardCount} cards{' '}
                  {seat.seat === view.dealerSeat ? '· Dealer' : ''}
                </small>
              </div>
              {play && (
                <div
                  className={`table-play ${view.winnerSeat === seat.seat ? 'winning' : ''}`}
                  aria-label={`Seat ${seat.seat + 1} played`}
                  key={`${view.round}-${view.trickNumber}-${seat.seat}`}
                >
                  <div className="table-play-cards">
                    {play.cards.map((card) => (
                      <span
                        key={card.id}
                        className={`table-card ${cardColor(card)}`}
                      >
                        <CardFace card={card} />
                      </span>
                    ))}
                  </div>
                  {view.winnerSeat === seat.seat && (
                    <small>{view.trickComplete ? 'Winner' : 'Winning'}</small>
                  )}
                </div>
              )}
            </div>
          );
        })}
      </div>
      {children}
    </div>
  );
}
