export const APP_AWAY_REDIRECT_MS = 15 * 60 * 1_000;
export const APP_HIDDEN_AT_KEY = 'pongo-app-hidden-at';

export function hasBeenAwayLongEnough(hiddenAt: string | null, now = Date.now()) {
  if (!hiddenAt) return false;
  const timestamp = Number(hiddenAt);
  return Number.isFinite(timestamp) && timestamp > 0 && now - timestamp >= APP_AWAY_REDIRECT_MS;
}
