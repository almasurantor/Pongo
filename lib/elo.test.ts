import { describe, expect, it } from 'vitest';
import { BASE_ELO, calculateElo, LOSS_K_FACTOR, predictElo, WIN_K_FACTOR } from './elo';

describe('asymmetric ranked ELO', () => {
  it('uses the 50 ELO baseline and separate win/loss K-factors', () => {
    expect(BASE_ELO).toBe(50);
    expect(WIN_K_FACTOR).toBe(70);
    expect(LOSS_K_FACTOR).toBe(40);
  });

  it('awards +35 and -20 at equal ratings regardless of rank', () => {
    for (const rating of [50, 150, 400, 700, 900]) {
      const result = calculateElo(rating, rating, 11, 9);
      expect(result.eloChangeA).toBe(35);
      expect(result.eloChangeB).toBe(-20);
    }
  });

  it('scales expected wins and upsets from the rating difference', () => {
    const expectedGoldWin = calculateElo(400, 250, 11, 9);
    const silverUpset = calculateElo(400, 250, 9, 11);
    expect(expectedGoldWin.eloChangeA).toBe(21);
    expect(expectedGoldWin.eloChangeB).toBe(-12);
    expect(silverUpset.eloChangeA).toBe(-28);
    expect(silverUpset.eloChangeB).toBe(49);
  });

  it('makes a large upset much more meaningful than an expected win', () => {
    const expectedWin = calculateElo(700, 150, 11, 9);
    const upset = calculateElo(700, 150, 9, 11);
    expect(expectedWin.eloChangeA).toBe(3);
    expect(expectedWin.eloChangeB).toBe(-2);
    expect(upset.eloChangeA).toBe(-38);
    expect(upset.eloChangeB).toBe(67);

    const ironBeatsLegend = calculateElo(50, 900, 11, 9);
    expect(ironBeatsLegend.eloChangeA).toBe(69);
    expect(ironBeatsLegend.eloChangeB).toBe(-40);
  });

  it('is intentionally not zero-sum', () => {
    const result = calculateElo(400, 400, 11, 9);
    expect(result.eloChangeA + result.eloChangeB).toBe(15);
    expect(result.newRatingA + result.newRatingB).toBe(815);
  });

  it('never reduces the loser below zero', () => {
    const result = calculateElo(50, 10, 11, 9);
    expect(result.eloChangeB).toBe(-10);
    expect(result.newRatingB).toBe(0);
    expect(result.breakdown.floorApplied).toBe(true);
  });

  it('exposes asymmetric predictions', () => {
    const prediction = predictElo(400, 400);
    expect(prediction.winChange).toBe(35);
    expect(prediction.lossChange).toBe(-20);
    expect(prediction.expectedScore).toBe(.5);
  });

  it('rejects tied results and negative ratings', () => {
    expect(() => calculateElo(400, 400, 11, 11)).toThrow();
    expect(() => calculateElo(-1, 400, 11, 9)).toThrow();
  });
});
