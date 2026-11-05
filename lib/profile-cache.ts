import type { AvatarConfig } from './avatar';

export const PROFILE_CACHE_KEY = 'pongo-profile-shell-v1';
export const PROFILE_CACHE_MAX_AGE_MS = 7 * 24 * 60 * 60 * 1_000;

export type CachedProfileShell = {
  id: string;
  displayName: string;
  currentElo: number;
  totalGames: number;
  avatarConfig: AvatarConfig | null;
  cachedAt: number;
};

export function readCachedProfileShell(storage: Pick<Storage, 'getItem'>, now = Date.now()): CachedProfileShell | null {
  try {
    const parsed = JSON.parse(storage.getItem(PROFILE_CACHE_KEY) || 'null') as Partial<CachedProfileShell> | null;
    if (!parsed || typeof parsed.id !== 'string' || typeof parsed.displayName !== 'string') return null;
    if (typeof parsed.currentElo !== 'number' || typeof parsed.totalGames !== 'number' || typeof parsed.cachedAt !== 'number') return null;
    if (now - parsed.cachedAt > PROFILE_CACHE_MAX_AGE_MS) return null;
    return parsed as CachedProfileShell;
  } catch {
    return null;
  }
}

export function writeCachedProfileShell(storage: Pick<Storage, 'setItem'>, profile: {
  id: string;
  display_name: string;
  current_elo: number;
  total_wins: number;
  total_losses: number;
  avatar_config?: AvatarConfig | null;
}, now = Date.now()) {
  const value: CachedProfileShell = {
    id: profile.id,
    displayName: profile.display_name,
    currentElo: profile.current_elo,
    totalGames: profile.total_wins + profile.total_losses,
    avatarConfig: profile.avatar_config ?? null,
    cachedAt: now,
  };
  storage.setItem(PROFILE_CACHE_KEY, JSON.stringify(value));
}

export function clearCachedProfileShell(storage: Pick<Storage, 'removeItem'>) {
  storage.removeItem(PROFILE_CACHE_KEY);
}
