import { describe, expect, it } from 'vitest';
import { getRankDetails, rankTierForElo, rankTransition } from './ranks';

describe('competitive ranks', () => {
  it.each([
    [849, 'Iron'],
    [850, 'Bronze'],
    [949, 'Bronze'],
    [950, 'Silver'],
    [1049, 'Silver'],
    [1050, 'Gold'],
    [1149, 'Gold'],
    [1150, 'Platinum'],
    [1249, 'Platinum'],
    [1250, 'Diamond'],
    [1399, 'Diamond'],
    [1400, 'Legend'],
  ])('maps %i ELO to %s', (elo, expected) => {
    expect(rankTierForElo(elo).name).toBe(expected);
  });

  it('calculates progress toward the next tier', () => {
    expect(getRankDetails(1000, 5)).toMatchObject({
      tier: 'Silver',
      nextTier: 'Gold',
      nextTierElo: 1050,
      pointsToNext: 50,
      progressPercent: 50,
      isProvisional: false,
    });
  });

  it('marks the first five completed games as provisional', () => {
    expect(getRankDetails(1000, 2)).toMatchObject({
      isProvisional: true,
      placementGamesRemaining: 3,
    });
    expect(getRankDetails(1000, 5).isProvisional).toBe(false);
  });

  it('recognizes promotions, demotions, and unchanged tiers', () => {
    expect(rankTransition(1049, 1051)).toMatchObject({ direction: 'promotion', afterTier: 'Gold' });
    expect(rankTransition(1251, 1249)).toMatchObject({ direction: 'demotion', afterTier: 'Platinum' });
    expect(rankTransition(1000, 1020)).toMatchObject({ changed: false, direction: null });
  });
});
