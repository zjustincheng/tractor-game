import { useEffect, useMemo, useState } from 'react';
import { previewResponseSchema } from '@tractor/protocol';
import type { PreviewResponse } from '@tractor/protocol';
import {
  chooseBotDeclaration,
  declarationsForHand,
  RANKS,
  SUITS,
} from '@tractor/rules';
import type { Suit } from '@tractor/rules';

const suitSymbols: Record<Suit, string> = {
  clubs: '♣',
  diamonds: '♦',
  hearts: '♥',
  spades: '♠',
};

function cardLabel(card: PreviewResponse['hand'][number]) {
  return card.kind === 'joker'
    ? `${card.joker === 'big' ? 'Big' : 'Small'} joker`
    : `${card.rank}${suitSymbols[card.suit]}`;
}

export function TrumpTrainer() {
  const [preview, setPreview] = useState<PreviewResponse | null>(null);
  const [choice, setChoice] = useState<Suit | null>(null);
  const [message, setMessage] = useState('');
  const [busy, setBusy] = useState(false);

  async function deal() {
    setBusy(true);
    setMessage('');
    setChoice(null);
    try {
      const response = await fetch('/api/practice-preview', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ playerCount: 4, level: '2', trumpSuit: null }),
      });
      if (!response.ok) throw new Error();
      setPreview(previewResponseSchema.parse(await response.json()));
    } catch {
      setMessage('Could not deal a trainer hand. Try again.');
    } finally {
      setBusy(false);
    }
  }

  useEffect(() => {
    void deal();
  }, []);

  const options = useMemo(
    () =>
      preview
        ? declarationsForHand(preview.hand, 4, '2', 0).filter(
            (option) => option.kind === 'suit',
          )
        : [],
    [preview],
  );
  const recommended = useMemo(
    () => chooseBotDeclaration(options, preview?.hand ?? [], '2'),
    [options, preview],
  );
  const cardsBySuit = preview
    ? SUITS.map((suit) => ({
        suit,
        cards: preview.hand
          .filter(
            (card): card is Extract<typeof card, { kind: 'suited' }> =>
              card.kind === 'suited' && card.suit === suit,
          )
          .sort((a, b) => RANKS.indexOf(a.rank) - RANKS.indexOf(b.rank)),
      }))
    : [];

  function choose(suit: Suit) {
    setChoice(suit);
    if (recommended?.kind !== 'suit') return;
    setMessage(
      recommended.suit === suit
        ? `Good call. The bot agrees: ${suit} has the best support in this hand.`
        : `The bot would call ${recommended.suit}. Look for its length, pairs, tractors, and high trump cards.`,
    );
  }

  return (
    <section className="panel trump-trainer" id="trump-trainer">
      <div className="section-heading">
        <div>
          <p className="eyebrow">MINI APP / TRUMP TRAINER</p>
          <h2>What would you call?</h2>
          <p className="muted">
            Choose a suit for this level-2 hand, then compare your call with the
            bot’s evaluation.
          </p>
        </div>
        <button
          className="text-button"
          type="button"
          onClick={() => void deal()}
          disabled={busy}
        >
          Deal another hand
        </button>
      </div>
      {preview ? (
        <>
          <div className="trainer-hand" aria-label="Trump trainer hand">
            {cardsBySuit.map(({ suit, cards }) => (
              <div className="trainer-suit" key={suit}>
                <h3>
                  {suitSymbols[suit]} {suit} <span>{cards.length}</span>
                </h3>
                <div className="trainer-cards">
                  {cards.map((card) => (
                    <span key={card.id} className="trainer-card">
                      {cardLabel(card)}
                    </span>
                  ))}
                </div>
              </div>
            ))}
          </div>
          {options.length ? (
            <div className="trainer-options">
              <p className="eyebrow">YOUR CALL</p>
              <div className="trainer-buttons">
                {SUITS.map((suit) => (
                  <button
                    key={suit}
                    type="button"
                    className={choice === suit ? 'selected' : ''}
                    onClick={() => choose(suit)}
                  >
                    {suitSymbols[suit]} {suit}
                  </button>
                ))}
              </div>
              {message && (
                <p className="trainer-message" aria-live="polite">
                  {message}
                </p>
              )}
            </div>
          ) : (
            <p className="muted">
              This hand has no level-2 declaration. Deal another hand to try
              again.
            </p>
          )}
        </>
      ) : (
        <p className="muted">Dealing a hand…</p>
      )}
      {message && !options.length && <p className="error-text">{message}</p>}
    </section>
  );
}
