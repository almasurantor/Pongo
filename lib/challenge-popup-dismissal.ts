const KEY_PREFIX = 'pongo:dismissed-challenges:';
const MAX_REMEMBERED = 50;

function storageKey(userId: string) {
  return `${KEY_PREFIX}${userId}`;
}

export function readDismissedChallengeIds(storage: Pick<Storage, 'getItem'>, userId: string): string[] {
  try {
    const value: unknown = JSON.parse(storage.getItem(storageKey(userId)) ?? '[]');
    return Array.isArray(value) ? value.filter((id): id is string => typeof id === 'string').slice(-MAX_REMEMBERED) : [];
  } catch {
    return [];
  }
}

export function rememberDismissedChallenge(storage: Pick<Storage, 'setItem'>, userId: string, ids: string[], challengeId: string) {
  const next = [...ids.filter((id) => id !== challengeId), challengeId].slice(-MAX_REMEMBERED);
  try {
    storage.setItem(storageKey(userId), JSON.stringify(next));
  } catch {
    // The in-memory state still dismisses the popup when storage is unavailable.
  }
  return next;
}
