import { describe, expect, it } from 'vitest';
import { PROFILE_CACHE_KEY, PROFILE_CACHE_MAX_AGE_MS, clearCachedProfileShell, readCachedProfileShell, writeCachedProfileShell } from './profile-cache';

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => { values.set(key, value); },
    removeItem: (key: string) => { values.delete(key); },
  };
}

describe('display-only profile shell cache', () => {
  it('restores recent public profile data', () => {
    const storage = memoryStorage();
    writeCachedProfileShell(storage, { id: 'p1', display_name: 'Player', current_elo: 123, total_wins: 4, total_losses: 2, avatar_config: null }, 1_000);
    expect(readCachedProfileShell(storage, 2_000)).toMatchObject({ id: 'p1', displayName: 'Player', currentElo: 123, totalGames: 6 });
  });

  it('rejects expired or malformed cache entries and clears on logout', () => {
    const storage = memoryStorage();
    storage.setItem(PROFILE_CACHE_KEY, '{bad');
    expect(readCachedProfileShell(storage)).toBeNull();
    writeCachedProfileShell(storage, { id: 'p1', display_name: 'Player', current_elo: 0, total_wins: 0, total_losses: 0 }, 1_000);
    expect(readCachedProfileShell(storage, 1_000 + PROFILE_CACHE_MAX_AGE_MS + 1)).toBeNull();
    clearCachedProfileShell(storage);
    expect(storage.getItem(PROFILE_CACHE_KEY)).toBeNull();
  });
});
