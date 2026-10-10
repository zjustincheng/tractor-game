import { useEffect, useRef, useState } from 'react';
import type { BotMatchView } from '@tractor/protocol';
import { DecisionClip } from './DecisionClip.js';

type Decision = NonNullable<BotMatchView['playtest']>['review'][number];

export function DecisionFlashcards({
  review,
  busy,
  teach,
}: {
  review: Decision[];
  busy: boolean;
  teach: (id: string, preferredIndex: number) => Promise<boolean>;
}) {
  const [deck, setDeck] = useState(() =>
    review
      .filter((item) => item.clip?.hand && item.preferredIndex === null)
      .map((item) => item.id),
  );
  const [position, setPosition] = useState(0);
  const [skipped, setSkipped] = useState<string[]>([]);
  const [retry, setRetry] = useState(false);
  const activeDeck = deck;
  const item = review.find((item) => item.id === activeDeck[position]);
  return (
    <section className="decision-flashcards" aria-label="Decision flashcards">
      <h4>Teach with flashcards</h4>
      <p>
        One decision at a time. Choose the play you prefer, or skip if you’re
        unsure. Your answer is guidance for the bot, not a scored quiz.
      </p>
      {item ? (
        <>
          <p>
            Card {position + 1} of {activeDeck.length}
            {retry ? ' · skipped cards' : ''}
          </p>
          <DecisionCard
            key={item.id}
            item={item}
            busy={busy}
            teach={teach}
            next={() => setPosition((p) => p + 1)}
            skip={() => {
              setSkipped((old) => [...old, item.id]);
              setPosition((p) => p + 1);
            }}
          />
        </>
      ) : (
        <>
          <p role="status">
            {deck.length
              ? 'You’ve reached the end of these flashcards. No new match needed.'
              : 'No unanswered decisions with complete replay context are available in this match.'}
          </p>
          {skipped.length > 0 && (
            <button
              onClick={() => {
                setRetry(true);
                setDeck(skipped);
                setSkipped([]);
                setPosition(0);
              }}
            >
              Review skipped cards
            </button>
          )}
        </>
      )}
    </section>
  );
}

function DecisionCard({
  item,
  busy,
  teach,
  next,
  skip,
}: {
  item: Decision;
  busy: boolean;
  teach: (id: string, preferredIndex: number) => Promise<boolean>;
  next: () => void;
  skip: () => void;
}) {
  const [choice, setChoice] = useState<number | null>(null);
  const [answered, setAnswered] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const pending = useRef(false);
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    heading.current?.focus();
  }, []);
  const clip = item.clip!;
  const partner = clip.plays.find(
    (p) => p.seat !== clip.seat && p.seat % 2 === clip.seat % 2,
  );
  const blocked = busy || saving;
  async function submit() {
    if (choice === null || pending.current) return;
    pending.current = true;
    setSaving(true);
    setError('');
    try {
      if (choice === item.chosen || (await teach(item.id, choice)))
        setAnswered(true);
      else
        setError(
          'Your answer wasn’t saved. Try again; this card is still here.',
        );
    } catch {
      setError('Your answer wasn’t saved. Try again; this card is still here.');
    } finally {
      pending.current = false;
      setSaving(false);
    }
  }
  return (
    <article className="decision-flashcard">
      <h4 ref={heading} tabIndex={-1}>
        What should Bot {clip.seat + 1} play?
      </h4>
      <p>
        Round {item.round} · Trick {item.trick} ·{' '}
        {item.kind === 'lead' ? 'Lead a new trick' : 'Follow the lead'}.
        Partner: seat {partner ? partner.seat + 1 : 'unknown'}.
      </p>
      <DecisionClip
        clip={clip}
        startAtDecision
        showHand
        allowOutcome={answered}
      />
      <fieldset disabled={blocked || answered}>
        <legend>Your decision</legend>
        <div className="flashcard-options">
          {item.options.map((option, index) => (
            <label key={index} className={choice === index ? 'selected' : ''}>
              <input
                type="radio"
                name={`answer-${item.id}`}
                checked={choice === index}
                onChange={() => setChoice(index)}
              />
              <span>{option.cards.join(' · ') || 'Pass'}</span>
            </label>
          ))}
        </div>
      </fieldset>
      {error && <p role="alert">{error}</p>}
      {answered ? (
        <>
          <p role="status">
            {choice === item.chosen
              ? 'You chose the same play as the bot. No correction was needed.'
              : 'Correction saved. This series’ adaptive policy has been updated.'}
          </p>
          <p>The bot played: {item.options[item.chosen]?.cards.join(' · ')}.</p>
          <button onClick={next}>Next flashcard</button>
        </>
      ) : (
        <div className="clip-controls">
          <button
            disabled={blocked || choice === null}
            onClick={() => void submit()}
          >
            {saving ? 'Saving…' : 'Submit answer'}
          </button>
          <button disabled={blocked} onClick={skip}>
            Skip — not sure
          </button>
        </div>
      )}
    </article>
  );
}
