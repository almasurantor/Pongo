import { describe, expect, it } from 'vitest';
import {
  canRespondToCancellation,
  canTransitionMatch,
  isMatchOverdue,
  isPotentialDuplicate,
  isTerminalMatch,
  nextStreak,
} from './ranking-rules';

describe('ranking lifecycle rules', () => {
  it('updates winning and losing streaks', () => {
    expect(nextStreak(2, true)).toBe(3);
    expect(nextStreak(-2, true)).toBe(1);
    expect(nextStreak(-2, false)).toBe(-3);
    expect(nextStreak(3, false)).toBe(-1);
  });

  it('detects the same result within five minutes regardless of player order', () => {
    const createdAt = new Date('2026-10-01T12:00:00Z');
    expect(isPotentialDuplicate(
      { playerOneId: 'a', playerTwoId: 'b', winnerId: 'a', playerOneScore: 11, playerTwoScore: 8, createdAt },
      { playerOneId: 'b', playerTwoId: 'a', winnerId: 'a', playerOneScore: 8, playerTwoScore: 11, createdAt: new Date(createdAt.getTime() + 120_000) },
    )).toBe(true);
  });

  it('guards terminal states and required review transitions', () => {
    expect(canTransitionMatch('ready', 'confirmed')).toBe(true);
    expect(canTransitionMatch('ready', 'canceled')).toBe(true);
    expect(canTransitionMatch('ready', 'expired')).toBe(true);
    expect(canTransitionMatch('confirmed', 'ready')).toBe(false);
    expect(isTerminalMatch('confirmed')).toBe(true);
    expect(isTerminalMatch('canceled')).toBe(true);
    expect(isTerminalMatch('ready')).toBe(false);
  });

  it('treats the exact deadline as expired', () => {
    const deadline = '2026-10-30T16:00:00.000Z';
    expect(isMatchOverdue(deadline, new Date(deadline))).toBe(true);
    expect(isMatchOverdue(deadline, new Date('2026-10-30T15:59:59.999Z'))).toBe(false);
    expect(isMatchOverdue(null, new Date(deadline))).toBe(false);
  });

  it('only lets the other player respond to a pending cancellation', () => {
    expect(canRespondToCancellation('ready', 'player-a', 'player-b')).toBe(true);
    expect(canRespondToCancellation('ready', 'player-a', 'player-a')).toBe(false);
    expect(canRespondToCancellation('confirmed', 'player-a', 'player-b')).toBe(false);
  });
});
