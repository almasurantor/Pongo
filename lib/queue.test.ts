import { describe, expect, it } from 'vitest';
import {
  canReportQueueOutcome,
  canRequestQueueSwap,
  needsQueueCheckIn,
  orderedQueueLine,
  queueGameSecondsRemaining,
  queuePlaceFor,
  queueSecondsUntil,
  queueStatusLabel,
  recentCompletedQueueGames,
  type QueueLineMember,
} from './queue';

const member = (userId: string, status: QueueLineMember['status'], position: number): QueueLineMember => ({
  user_id: userId,
  status,
  queue_position: position,
});

describe('live queue presentation rules', () => {
  it('keeps waiting players in FIFO order and puts the called player first', () => {
    const line = orderedQueueLine([
      member('third', 'waiting', 30),
      member('holder', 'king', 10),
      member('called', 'called', 20),
      member('second-waiting', 'waiting', 25),
      member('left', 'left', 5),
    ]);
    expect(line.map((entry) => entry.user_id)).toEqual(['called', 'second-waiting', 'third']);
  });

  it('reports a stable queue position and number of players ahead', () => {
    const members = [
      member('called', 'called', 2),
      member('next', 'waiting', 3),
      member('me', 'waiting', 4),
    ];
    expect(queuePlaceFor(members, 'me')).toEqual({ position: 3, playersAhead: 2 });
    expect(queuePlaceFor(members, 'missing')).toBeNull();
  });

  it('uses database timestamps for the 60-second call and 10-minute game timers', () => {
    const now = Date.parse('2026-11-03T12:00:00Z');
    expect(queueSecondsUntil('2026-11-03T12:00:45Z', now)).toBe(45);
    expect(queueSecondsUntil('2026-11-03T11:59:00Z', now)).toBe(0);
    expect(queueGameSecondsRemaining('2026-11-03T12:06:30Z', now)).toBe(390);
  });

  it('shows match-ready check-in only to the unconfirmed challenger', () => {
    expect(needsQueueCheckIn('called', 'holder', 'next', null)).toBe(false);
    expect(needsQueueCheckIn('called', 'next', 'next', null)).toBe(true);
    expect(needsQueueCheckIn('called', 'next', 'next', '2026-11-03T12:00:00Z')).toBe(false);
    expect(needsQueueCheckIn('playing', 'next', 'next', null)).toBe(false);
    expect(needsQueueCheckIn('called', 'spectator', 'next', null)).toBe(false);
  });

  it('maps every queue state to the compact header status', () => {
    expect(queueStatusLabel(undefined, -1, 0)).toBe('Not in queue');
    expect(queueStatusLabel('waiting', 1, 0)).toBe('In queue · #2');
    expect(queueStatusLabel('king', -1, 0)).toBe('Holding table');
    expect(queueStatusLabel('called', -1, 9)).toBe('Called · 0:09');
    expect(queueStatusLabel('playing', -1, 0)).toBe('Playing');
  });

  it('shows outcome and swap controls only to eligible users', () => {
    expect(canReportQueueOutcome('playing', 'holder', 'holder', 'challenger')).toBe(true);
    expect(canReportQueueOutcome('playing', 'spectator', 'holder', 'challenger')).toBe(false);
    expect(canReportQueueOutcome('called', 'holder', 'holder', 'challenger')).toBe(false);
    const me = member('me', 'waiting', 3);
    expect(canRequestQueueSwap(me, member('behind', 'waiting', 4), false)).toBe(true);
    expect(canRequestQueueSwap(me, member('ahead', 'waiting', 2), false)).toBe(false);
    expect(canRequestQueueSwap(me, member('me', 'waiting', 3), false)).toBe(false);
    expect(canRequestQueueSwap(me, member('behind', 'waiting', 4), true)).toBe(false);
  });

  it('limits player activity to ten completed, score-free outcomes', () => {
    const games = [
      ...Array.from({ length: 12 }, (_, id) => ({ id, status: 'completed' as const })),
      { id: 99, status: 'abandoned' as const },
    ];
    expect(recentCompletedQueueGames(games)).toHaveLength(10);
    expect(recentCompletedQueueGames(games).some((game) => game.status === 'abandoned')).toBe(false);
  });
});
