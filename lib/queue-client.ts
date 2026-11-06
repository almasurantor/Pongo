import type { QueueMemberStatus } from './queue';
import { rankedLimitMessage } from './ranked-limits';

export type QueueSyncTrigger = 'initial' | 'interval' | 'focus' | 'realtime';

export interface QueueErrorLike {
  code?: string;
  message?: string;
  details?: string | null;
  hint?: string | null;
}

export interface QueueHealth {
  version?: string;
  initialized?: boolean;
  heartbeat_granted?: boolean;
  join_granted?: boolean;
  outcome_granted?: boolean;
  swap_granted?: boolean;
  afk_granted?: boolean;
  ranked_granted?: boolean;
  ranked_requests_ready?: boolean;
  tick_granted?: boolean;
  holder_presence_trigger?: boolean;
  overtime_granted?: boolean;
}

const ACTIVE_QUEUE_STATUSES: readonly QueueMemberStatus[] = ['waiting', 'called', 'king', 'playing'];

export function isActiveQueueStatus(status: string | null | undefined): status is QueueMemberStatus {
  return ACTIVE_QUEUE_STATUSES.includes(status as QueueMemberStatus);
}

export function shouldSendQueueHeartbeat(
  status: string | null | undefined,
  trigger: QueueSyncTrigger,
  _consecutiveFailures: number,
) {
  // Keep retrying on the bounded 30-second interval. A permanent circuit
  // breaker silently drops an otherwise active player after a transient
  // outage; Realtime-triggered calls remain suppressed to avoid feedback.
  return isActiveQueueStatus(status) && trigger !== 'realtime';
}

export function isQueueBackendHealthy(data: unknown): data is QueueHealth {
  if (!data || typeof data !== 'object') return false;
  const health = data as QueueHealth;
  return health.version === '20261106_01'
    && health.initialized === true
    && health.heartbeat_granted === true
    && health.join_granted === true
    && health.outcome_granted === true
    && health.swap_granted === true
    && health.afk_granted === true
    && health.ranked_granted === true
    && health.ranked_requests_ready === true
    && health.tick_granted === true
    && health.holder_presence_trigger === true
    && health.overtime_granted === true;
}

export function queueErrorMessage(caught: unknown, fallback = 'Unable to update the queue.') {
  const error = caught && typeof caught === 'object' ? caught as QueueErrorLike : {};
  const code = error.code ?? '';
  const raw = error.message ?? (caught instanceof Error ? caught.message : '');
  const normalized = raw.toLowerCase();

  if (code === 'PGRST202' || code === '42883' || normalized.includes('schema cache')) {
    return 'The queue database update is missing. Apply migrations through 20261106010000_match_overtime_emoji_usernames.sql in Supabase, then reload.';
  }
  if (code === '42P01' || normalized.includes('does not exist')) {
    return 'The queue database tables are not installed. Apply the queue migrations before using this page.';
  }
  if (code === '42501' || normalized.includes('permission denied')) {
    return 'Your session cannot access the queue. Sign out and back in; if this continues, verify the queue RPC grants and RLS policies.';
  }
  if (code === '23503' || normalized.includes('player profile not found')) {
    return 'Your player profile is not ready yet. Reload once, then contact an administrator if the problem continues.';
  }
  if (code === '40P01' || code === '40001' || normalized.includes('deadlock')) {
    return 'The queue changed at the same time as your request. Please try again.';
  }
  if (code === '57014' || normalized.includes('statement timeout')) {
    return 'The queue is busy. Wait a moment and try again.';
  }
  if (normalized.includes('sign in required') || normalized.includes('jwt')) {
    return 'Your session expired. Sign in again to use the queue.';
  }
  return raw || fallback;
}

export function queueRankedErrorMessage(caught: unknown) {
  return rankedLimitMessage(
    caught,
    queueErrorMessage(caught, 'Unable to update the Ranked request.'),
  );
}

export function isRetryableQueueError(caught: unknown) {
  const error = caught && typeof caught === 'object' ? caught as QueueErrorLike : {};
  return ['40P01', '40001', '57014'].includes(error.code ?? '');
}
