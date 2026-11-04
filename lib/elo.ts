/** Pongo asymmetric ranked ELO: wins use K=70 and losses use K=40. */

const WIN_K_FACTOR = 70;
const LOSS_K_FACTOR = 40;
const K_FACTOR = WIN_K_FACTOR;
const BASE_ELO = 50;

export interface EloBreakdown {
  formulaVersion: 'asymmetric_elo_v2';
  winKFactor: number;
  lossKFactor: number;
  winnerExpected: number;
  loserExpected: number;
  winnerGainRaw: number;
  loserLossRaw: number;
  winnerGain: number;
  loserLossUnclamped: number;
  loserLoss: number;
  floorApplied: boolean;
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

export function calculateElo(
  ratingA: number,
  ratingB: number,
  scoreA: number,
  scoreB: number,
): EloResult {
  if (ratingA < 0 || ratingB < 0) throw new Error('ELO ratings cannot be negative');
  if (scoreA === scoreB) throw new Error('Ranked matches cannot end in a draw');

  const playerAWon = scoreA > scoreB;
  const winnerRating = playerAWon ? ratingA : ratingB;
  const loserRating = playerAWon ? ratingB : ratingA;
  const winnerExpected = expectedScore(winnerRating, loserRating);
  const loserExpected = 1 - winnerExpected;
  const winnerGainRaw = WIN_K_FACTOR * loserExpected;
  const loserLossRaw = LOSS_K_FACTOR * loserExpected;
  const winnerGain = Math.round(winnerGainRaw);
  const loserLossUnclamped = Math.round(loserLossRaw);
  const loserLoss = Math.min(loserRating, loserLossUnclamped);
  const eloChangeA = playerAWon ? winnerGain : -loserLoss;
  const eloChangeB = playerAWon ? -loserLoss : winnerGain;

  return {
    newRatingA: Math.max(0, ratingA + eloChangeA),
    newRatingB: Math.max(0, ratingB + eloChangeB),
    eloChangeA,
    eloChangeB,
    breakdown: {
      formulaVersion: 'asymmetric_elo_v2',
      winKFactor: WIN_K_FACTOR,
      lossKFactor: LOSS_K_FACTOR,
      winnerExpected,
      loserExpected,
      winnerGainRaw,
      loserLossRaw,
      winnerGain,
      loserLossUnclamped,
      loserLoss,
      floorApplied: loserLoss < loserLossUnclamped,
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

export { BASE_ELO, K_FACTOR, LOSS_K_FACTOR, WIN_K_FACTOR };
