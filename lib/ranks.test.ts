import { describe, expect, it } from 'vitest';
import { getRankDetails, rankTierForElo, rankTransition } from './ranks';

describe('competitive ranks', () => {
  it.each([
    [0, 'Iron'],
    [99, 'Iron'],
    [100, 'Bronze'],
    [199, 'Bronze'],
    [200, 'Silver'],
    [324, 'Silver'],
    [325, 'Gold'],
    [474, 'Gold'],
    [475, 'Platinum'],
    [649, 'Platinum'],
    [650, 'Diamond'],
    [849, 'Diamond'],
    [850, 'Legend'],
  ])('maps %i ELO to %s', (elo, expected) => {
    expect(rankTierForElo(elo).name).toBe(expected);
  });

  it('calculates progress toward the next tier', () => {
    expect(getRankDetails(400, 5)).toMatchObject({
      tier: 'Gold',
      nextTier: 'Platinum',
      nextTierElo: 475,
      pointsToNext: 75,
      progressPercent: 50,
    });
  });

  it('does not use placement games or provisional ranks', () => {
    expect(getRankDetails(50, 0)).not.toHaveProperty('isProvisional');
    expect(getRankDetails(50, 2)).not.toHaveProperty('placementGamesRemaining');
  });

  it('recognizes promotions, demotions, and unchanged tiers', () => {
    expect(rankTransition(324, 325)).toMatchObject({ direction: 'promotion', afterTier: 'Gold' });
    expect(rankTransition(650, 649)).toMatchObject({ direction: 'demotion', afterTier: 'Platinum' });
    expect(rankTransition(350, 400)).toMatchObject({ changed: false, direction: null });
  });
});
