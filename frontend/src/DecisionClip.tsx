import { useEffect, useState } from 'react';
import type { BotMatchView } from '@tractor/protocol';

type Review = NonNullable<BotMatchView['playtest']>['review'][number];

export function DecisionClip({
  clip,
  reviewDecision = true,
  startAtDecision = false,
  showHand = false,
  allowOutcome = true,
}: {
  clip: NonNullable<Review['clip']>;
  reviewDecision?: boolean;
  startAtDecision?: boolean;
  showHand?: boolean;
  allowOutcome?: boolean;
}) {
  const [cursor, setCursor] = useState(
    startAtDecision ? clip.decisionIndex : 0,
  );
  const [running, setRunning] = useState(false);
  const [outcome, setOutcome] = useState(false);
  const limit =
    outcome || !reviewDecision ? clip.plays.length : clip.decisionIndex;
  useEffect(() => {
    if (!running) return;
    if (cursor >= limit) return;
    const timer = window.setTimeout(() => {
      setCursor(cursor + 1);
      if (cursor + 1 >= limit) setRunning(false);
    }, 900);
    return () => window.clearTimeout(timer);
  }, [cursor, limit, running]);
  return (
    <section
      className="decision-clip"
      aria-label={reviewDecision ? 'Decision replay' : 'Trick replay'}
    >
      {clip.seatCorrected && (
        <p>
          This decision was previously labeled with the wrong bot. The seat
          shown here was recovered from the played cards. Recheck any earlier
          correction in this context.
        </p>
      )}
      <p>
        Trump {clip.trump}
        {reviewDecision ? ` · Reviewing Bot ${clip.seat + 1}` : ''}
      </p>
      <div className="decision-clip-table" aria-label="Trick table">
        {clip.plays.map((play, index) => (
          <div
            key={index}
            className={
              reviewDecision && play.seat === clip.seat ? 'reviewed-seat' : ''
            }
          >
            <strong>
              Seat {play.seat + 1}
              {reviewDecision && play.seat === clip.seat ? ' · decision' : ''}
            </strong>
            {index < cursor ? (
              <div className="clip-cards">
                {play.cards.map((card, i) => (
                  <span key={i}>{card}</span>
                ))}
              </div>
            ) : (
              <p>Waiting to play</p>
            )}
          </div>
        ))}
      </div>
      <p role="status">
        {cursor === clip.plays.length
          ? `Winner: seat ${clip.winnerSeat + 1} · ${clip.points} points`
          : reviewDecision && cursor === clip.decisionIndex
            ? 'Paused before the decision. Choose what the bot should play.'
            : `${cursor} plays shown`}
      </p>
      <div className="clip-controls">
        <button
          onClick={() => {
            setCursor(0);
            setOutcome(false);
            setRunning(!reviewDecision || clip.decisionIndex > 0);
          }}
        >
          {reviewDecision ? 'Replay to decision' : 'Replay trick'}
        </button>
        <button disabled={cursor >= limit} onClick={() => setRunning(!running)}>
          {running ? 'Pause clip' : 'Play clip'}
        </button>
        <button
          disabled={
            cursor >= (allowOutcome ? clip.plays.length : clip.decisionIndex)
          }
          onClick={() => {
            setRunning(false);
            setOutcome(allowOutcome);
            setCursor(cursor + 1);
          }}
        >
          Next play
        </button>
        {allowOutcome && (
          <button
            disabled={cursor >= clip.plays.length}
            onClick={() => {
              setOutcome(true);
              setRunning(true);
            }}
          >
            Show outcome
          </button>
        )}
      </div>
      {reviewDecision && (
        <details open={showHand || undefined}>
          <summary>Bot’s hand before this decision</summary>
          <p>
            {clip.hand?.join(' · ') ??
              'Hand could not be recovered reliably from this recording.'}
          </p>
        </details>
      )}
    </section>
  );
}
