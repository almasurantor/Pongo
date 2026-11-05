import { describe, expect, it } from 'vitest';
import { readDismissedChallengeIds, rememberDismissedChallenge } from './challenge-popup-dismissal';

function memoryStorage() {
  const values = new Map<string, string>();
  return {
    getItem: (key: string) => values.get(key) ?? null,
    setItem: (key: string, value: string) => values.set(key, value),
  };
}

describe('challenge popup dismissal', () => {
  it('remembers a dismissed challenge for the same player', () => {
    const storage = memoryStorage();
    const dismissed = rememberDismissedChallenge(storage, 'player-a', [], 'challenge-1');
    expect(dismissed).toEqual(['challenge-1']);
    expect(readDismissedChallengeIds(storage, 'player-a')).toEqual(['challenge-1']);
  });

  it('does not suppress a new challenge or another player’s popup', () => {
    const storage = memoryStorage();
    rememberDismissedChallenge(storage, 'player-a', [], 'challenge-1');
    expect(readDismissedChallengeIds(storage, 'player-a')).not.toContain('challenge-2');
    expect(readDismissedChallengeIds(storage, 'player-b')).toEqual([]);
  });

  it('recovers safely from invalid stored data', () => {
    const storage = memoryStorage();
    storage.setItem('pongo:dismissed-challenges:player-a', 'not-json');
    expect(readDismissedChallengeIds(storage, 'player-a')).toEqual([]);
  });
});
