import { describe, expect, it } from 'vitest';
import { formatCountdown, remainingMilliseconds } from './deadlines';

describe('deadline countdowns', () => {
  it('formats day, hour, and sub-hour deadlines', () => {
    expect(formatCountdown(90_000_000)).toBe('1d 1h');
    expect(formatCountdown(3_900_000)).toBe('1h 5m');
    expect(formatCountdown(65_000)).toBe('1m 05s');
  });

  it('never returns negative time', () => {
    expect(remainingMilliseconds('2026-01-01T00:00:00Z', Date.parse('2026-01-02T00:00:00Z'))).toBe(0);
    expect(formatCountdown(0)).toBe('Expired');
  });
});
