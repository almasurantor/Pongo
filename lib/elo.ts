/** Beaver Smash weighted, exactly zero-sum ELO. */

const K_FACTOR = 40;
const BASE_ELO = 500;
const SCORE_MARGIN_CAP = 0.1;
const MIN_WIN_MARGIN = 2;
const FULL_BONUS_MARGIN = 11;

export interface EloBreakdown {
  formulaVersion: 'weighted_elo_v1';
  kFactor: number;
  winnerExpected: number;
  baseDeltaRaw: number;
  baseDelta: number;
  scoreMargin: number;
  marginMultiplier: number;
  marginBonus: number;
  finalDelta: number;
}

export interface EloResult {
  newRatingA: number;
  newRatingB: number;
  eloChangeA: number;
  eloChangeB: number;
  breakdown: EloBreakdown;
}

export interface EloPrediction {
  winChange: number;
  lossChange: number;
  expectedScore: number;
}

export function expectedScore(ratingA: number, ratingB: number): number {
  return 1 / (1 + Math.pow(10, (ratingB - ratingA) / 400));
}

export function marginMultiplier(winnerScore: number, loserScore: number): number {
  const margin = winnerScore - loserScore;
  const progress = Math.min(1, Math.max(0, (margin - MIN_WIN_MARGIN) / (FULL_BONUS_MARGIN - MIN_WIN_MARGIN)));
  return 1 + SCORE_MARGIN_CAP * progress;
}

export function calculateElo(
  ratingA: number,
  ratingB: number,
  scoreA: number,
  scoreB: number,
): EloResult {
  if (scoreA === scoreB) throw new Error('Ranked matches cannot end in a draw');

  const playerAWon = scoreA > scoreB;
  const winnerRating = playerAWon ? ratingA : ratingB;
  const loserRating = playerAWon ? ratingB : ratingA;
  const winnerScore = Math.max(scoreA, scoreB);
  const loserScore = Math.min(scoreA, scoreB);
  const winnerExpected = expectedScore(winnerRating, loserRating);
  const baseDeltaRaw = K_FACTOR * (1 - winnerExpected);
  const baseDelta = Math.round(baseDeltaRaw);
  const multiplier = marginMultiplier(winnerScore, loserScore);
  const finalDelta = Math.round(baseDeltaRaw * multiplier);
  const eloChangeA = playerAWon ? finalDelta : -finalDelta;
  const eloChangeB = -eloChangeA;

  return {
    newRatingA: ratingA + eloChangeA,
    newRatingB: ratingB + eloChangeB,
    eloChangeA,
    eloChangeB,
    breakdown: {
      formulaVersion: 'weighted_elo_v1',
      kFactor: K_FACTOR,
      winnerExpected,
      baseDeltaRaw,
      baseDelta,
      scoreMargin: winnerScore - loserScore,
      marginMultiplier: multiplier,
      marginBonus: finalDelta - baseDelta,
      finalDelta,
    },
  };
}

export function predictElo(rating: number, opponentRating: number): EloPrediction {
  const win = calculateElo(rating, opponentRating, 11, 9);
  const loss = calculateElo(rating, opponentRating, 9, 11);
  return {
    winChange: win.eloChangeA,
    lossChange: loss.eloChangeA,
    expectedScore: expectedScore(rating, opponentRating),
  };
}

export { K_FACTOR, BASE_ELO, SCORE_MARGIN_CAP };
