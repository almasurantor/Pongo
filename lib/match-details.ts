import { Match, RatingEvent } from '@/lib/types';

export interface StoredRatingSnapshot {
  before: number | null;
  change: number | null;
  after: number | null;
}

const isStoredNumber = (value: number | null | undefined): value is number => (
  typeof value === 'number' && Number.isFinite(value)
);

export function getStoredRatingSnapshot(
  match: Match,
  player: 'player_one' | 'player_two',
  ratingEvent?: RatingEvent,
): StoredRatingSnapshot {
  if (ratingEvent) {
    return {
      before: ratingEvent.rating_before,
      change: ratingEvent.rating_change,
      after: ratingEvent.rating_after,
    };
  }

  const before = match[`${player}_elo_before`];
  const change = match[`${player}_elo_change`];
  return {
    before: isStoredNumber(before) ? before : null,
    change: isStoredNumber(change) ? change : null,
    after: isStoredNumber(before) && isStoredNumber(change) ? before + change : null,
  };
}

export function formatStoredEloChange(change: number) {
  return `${change >= 0 ? '+' : ''}${change}`;
}
