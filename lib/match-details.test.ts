import { describe, expect, it } from 'vitest';
import { getStoredRatingSnapshot } from './match-details';
import { Match, RatingEvent } from './types';

const match = {
  player_one_elo_before: 850,
  player_one_elo_change: 24,
  player_two_elo_before: null,
  player_two_elo_change: null,
} as Match;

describe('stored match details', () => {
  it('uses the active rating ledger snapshot when one is available', () => {
    const event = {
      rating_before: 820,
      rating_change: 30,
      rating_after: 850,
    } as RatingEvent;

    expect(getStoredRatingSnapshot(match, 'player_one', event)).toEqual({
      before: 820,
      change: 30,
      after: 850,
    });
  });

  it('uses stored match fields without inventing missing legacy values', () => {
    expect(getStoredRatingSnapshot(match, 'player_one')).toEqual({
      before: 850,
      change: 24,
      after: 874,
    });
    expect(getStoredRatingSnapshot(match, 'player_two')).toEqual({
      before: null,
      change: null,
      after: null,
    });
  });
});
