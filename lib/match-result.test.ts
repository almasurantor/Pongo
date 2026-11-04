import { describe, expect, it } from 'vitest';
import { defaultMatchScores, validateMatchScore } from './match-result';

describe('winner score defaults', () => {
  it('starts the selected winner at 11 and the other player at 9', () => {
    expect(defaultMatchScores(true)).toEqual({ myScore: 11, theirScore: 9 });
    expect(defaultMatchScores(false)).toEqual({ myScore: 9, theirScore: 11 });
  });
});

describe('table-tennis score validation', () => {
  it.each([[11, 0], [11, 9], [12, 10], [21, 19]])('accepts %i–%i', (one, two) => {
    expect(validateMatchScore(one, two)).toBeNull();
  });

  it.each([[10, 8], [11, 10], [12, 9], [11, 11], [-1, 11], [100, 98], [11.5, 9]])('rejects %s–%s', (one, two) => {
    expect(validateMatchScore(one, two)).not.toBeNull();
  });
});
