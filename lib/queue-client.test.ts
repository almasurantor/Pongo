import { describe, expect, it } from 'vitest';
import {
  isActiveQueueStatus,
  isQueueBackendHealthy,
  isRetryableQueueError,
  queueErrorMessage,
  queueRankedErrorMessage,
  shouldSendQueueHeartbeat,
} from './queue-client';

describe('queue client safety', () => {
  it('heartbeats only active members and never in response to its own realtime update', () => {
    expect(shouldSendQueueHeartbeat('waiting', 'interval', 0)).toBe(true);
    expect(shouldSendQueueHeartbeat('called', 'focus', 0)).toBe(true);
    expect(shouldSendQueueHeartbeat('king', 'realtime', 0)).toBe(false);
    expect(shouldSendQueueHeartbeat('left', 'interval', 0)).toBe(false);
    expect(shouldSendQueueHeartbeat(null, 'initial', 0)).toBe(false);
  });

  it('opens the heartbeat circuit after three consecutive failures', () => {
    expect(shouldSendQueueHeartbeat('playing', 'interval', 2)).toBe(true);
    expect(shouldSendQueueHeartbeat('playing', 'interval', 3)).toBe(false);
  });

  it('requires the repaired backend version and every RPC grant', () => {
    const healthy = { version: '20261104_05', initialized: true, heartbeat_granted: true, join_granted: true, tick_granted: true, outcome_granted: true, swap_granted: true, afk_granted: true, ranked_granted: true, ranked_requests_ready: true, holder_presence_trigger: true };
    expect(isQueueBackendHealthy(healthy)).toBe(true);
    expect(isQueueBackendHealthy({ ...healthy, version: '20261103_02' })).toBe(false);
    expect(isQueueBackendHealthy({ ...healthy, heartbeat_granted: false })).toBe(false);
    expect(isQueueBackendHealthy({ ...healthy, outcome_granted: false })).toBe(false);
    expect(isQueueBackendHealthy({ ...healthy, swap_granted: false })).toBe(false);
    expect(isQueueBackendHealthy({ ...healthy, afk_granted: false })).toBe(false);
    expect(isQueueBackendHealthy({ ...healthy, ranked_granted: false })).toBe(false);
    expect(isQueueBackendHealthy({ ...healthy, ranked_requests_ready: false })).toBe(false);
    expect(isQueueBackendHealthy({ ...healthy, tick_granted: false })).toBe(false);
    expect(isQueueBackendHealthy({ ...healthy, holder_presence_trigger: false })).toBe(false);
  });

  it('maps database failures to actionable messages without hiding the cause', () => {
    expect(queueErrorMessage({ code: 'PGRST202', message: 'schema cache' })).toContain('20261104_05_queue_ranked_inline_scoring.sql');
    expect(queueErrorMessage({ code: '42501', message: 'permission denied' })).toContain('RPC grants and RLS');
    expect(queueErrorMessage({ code: '23503', message: 'foreign key violation' })).toContain('profile');
    expect(queueErrorMessage({ code: '40P01', message: 'deadlock detected' })).toContain('try again');
    expect(queueErrorMessage({ code: 'XX000', message: 'specific database failure' })).toBe('specific database failure');
  });

  it('uses concise inline copy for the shared per-opponent Ranked limit', () => {
    expect(queueRankedErrorMessage({
      message: 'You have reached the daily limit of 3 ranked games against this opponent',
    })).toBe("You've reached today's 3 ranked games against this player.");
  });

  it('classifies only transient database contention as retryable', () => {
    expect(isRetryableQueueError({ code: '40001' })).toBe(true);
    expect(isRetryableQueueError({ code: 'PGRST202' })).toBe(false);
    expect(isActiveQueueStatus('no_show')).toBe(false);
  });
});
