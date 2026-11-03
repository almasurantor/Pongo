import { describe, expect, it } from 'vitest';
import { APP_AWAY_REDIRECT_MS, hasBeenAwayLongEnough } from './app-resume';

describe('installed app resume policy', () => {
  it('preserves the current screen during a short app switch', () => {
    expect(hasBeenAwayLongEnough(String(1_000), 1_000 + APP_AWAY_REDIRECT_MS - 1)).toBe(false);
  });

  it('returns after fifteen minutes away', () => {
    expect(hasBeenAwayLongEnough(String(1_000), 1_000 + APP_AWAY_REDIRECT_MS)).toBe(true);
  });

  it('ignores missing or malformed timestamps', () => {
    expect(hasBeenAwayLongEnough(null)).toBe(false);
    expect(hasBeenAwayLongEnough('not-a-time')).toBe(false);
  });
});
