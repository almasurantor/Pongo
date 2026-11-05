export const DAILY_RANKED_PAIR_LIMIT = 3;

export const DAILY_RANKED_PAIR_LIMIT_MESSAGE =
  "You've reached today's 3 ranked games against this player.";

export function rankedLimitMessage(caught: unknown, fallback: string) {
  const raw = caught instanceof Error
    ? caught.message
    : caught && typeof caught === 'object' && 'message' in caught
      ? String(caught.message ?? '')
      : '';

  if (raw.toLowerCase().includes('ranked games against this opponent')) {
    return DAILY_RANKED_PAIR_LIMIT_MESSAGE;
  }
  return raw || fallback;
}
