import { describe, expect, it } from 'vitest';
import { calculateElo, K_FACTOR, marginMultiplier, predictElo, SCORE_MARGIN_CAP } from './elo';

describe('weighted zero-sum ELO', () => {
  it('uses K=40 and applies no bonus to the minimum valid margin', () => {
    const result = calculateElo(1000, 1000, 11, 9);
    expect(K_FACTOR).toBe(40);
    expect(result.eloChangeA).toBe(20);
    expect(result.breakdown.marginBonus).toBe(0);
    expect(result.breakdown.marginMultiplier).toBe(1);
  });

  it('caps score influence at ten percent', () => {
    expect(SCORE_MARGIN_CAP).toBe(0.1);
    expect(marginMultiplier(11, 0)).toBeCloseTo(1.1);
    expect(marginMultiplier(21, 0)).toBeCloseTo(1.1);
    expect(calculateElo(1000, 1000, 11, 0).eloChangeA).toBe(22);
  });

  it('keeps opponent strength as the primary factor', () => {
    const upset = calculateElo(800, 1200, 11, 9).eloChangeA;
    const expectedWin = calculateElo(1200, 800, 11, 0).eloChangeA;
    expect(upset).toBeGreaterThan(expectedWin * 5);
  });

  it('makes losing to a much stronger opponent inexpensive', () => {
    const prediction = predictElo(800, 1400);
    expect(prediction.lossChange).toBeGreaterThanOrEqual(-2);
    expect(prediction.winChange).toBeGreaterThan(35);
  });

  it('always applies exact inverse changes', () => {
    for (const [a, b, scoreA, scoreB] of [[1000, 1000, 11, 7], [1450, 900, 11, 0], [800, 1700, 12, 10]]) {
      const result = calculateElo(a, b, scoreA, scoreB);
      expect(result.eloChangeA + result.eloChangeB).toBe(0);
      expect(result.newRatingA + result.newRatingB).toBe(a + b);
    }
  });

  it('rejects tied results', () => {
    expect(() => calculateElo(1000, 1000, 11, 11)).toThrow();
  });
});
