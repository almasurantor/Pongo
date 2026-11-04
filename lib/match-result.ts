export function defaultMatchScores(winnerIsCurrentUser: boolean) {
  return winnerIsCurrentUser
    ? { myScore: 11, theirScore: 9 }
    : { myScore: 9, theirScore: 11 };
}

export function validateMatchScore(playerOneScore: number, playerTwoScore: number): string | null {
  if (!Number.isInteger(playerOneScore) || !Number.isInteger(playerTwoScore)) {
    return 'Scores must be whole numbers';
  }
  if (playerOneScore < 0 || playerTwoScore < 0) return 'Scores must be non-negative';
  if (playerOneScore > 99 || playerTwoScore > 99) return 'Scores cannot exceed 99 points';
  if (playerOneScore === playerTwoScore) return 'Scores cannot be tied';

  const high = Math.max(playerOneScore, playerTwoScore);
  const low = Math.min(playerOneScore, playerTwoScore);
  const difference = high - low;

  if (high < 11) return 'At least one player must reach 11 points';
  if (difference < 2) return 'The winner must lead by at least 2 points';
  if (high > 11 && (low < 10 || difference !== 2)) return 'After 10–10, the winner must lead by exactly 2 points';

  return null;
}
