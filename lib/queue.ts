export type QueueMemberStatus = 'waiting' | 'called' | 'king' | 'playing' | 'left' | 'no_show';

export interface QueueLineMember {
  user_id: string;
  status: QueueMemberStatus;
  queue_position: number;
}

export interface QueueHistoryEntry {
  status: 'completed' | 'abandoned';
}

export function orderedQueueLine<T extends QueueLineMember>(members: T[]): T[] {
  return members
    .filter((member) => member.status === 'called' || member.status === 'waiting')
    .sort((left, right) => {
      if (left.status !== right.status) return left.status === 'called' ? -1 : 1;
      return left.queue_position - right.queue_position || left.user_id.localeCompare(right.user_id);
    });
}

export function queuePlaceFor<T extends QueueLineMember>(members: T[], userId: string) {
  const line = orderedQueueLine(members);
  const index = line.findIndex((member) => member.user_id === userId);
  return index < 0 ? null : { position: index + 1, playersAhead: index };
}

export function queueSecondsUntil(timestamp: string | null, now: number) {
  return timestamp ? Math.max(0, Math.ceil((new Date(timestamp).getTime() - now) / 1000)) : 0;
}

export function queueGameSecondsRemaining(expiresAt: string | null, now: number) {
  return queueSecondsUntil(expiresAt, now);
}

export function needsQueueCheckIn(
  phase: string | null | undefined,
  userId: string,
  challengerId: string | null,
  challengerConfirmedAt: string | null,
) {
  return phase === 'called'
    && userId === challengerId
    && challengerConfirmedAt === null;
}

export function queueStatusLabel(status: QueueMemberStatus | null | undefined, waitingIndex: number, callSeconds: number) {
  if (!status || status === 'left' || status === 'no_show') return 'Not in queue';
  if (status === 'waiting') return `In queue${waitingIndex >= 0 ? ` · #${waitingIndex + 1}` : ''}`;
  if (status === 'king') return 'Holding table';
  if (status === 'called') return `Called · ${Math.floor(callSeconds / 60)}:${String(callSeconds % 60).padStart(2, '0')}`;
  return 'Playing';
}

export function canReportQueueOutcome(phase: string | null | undefined, userId: string, kingId: string | null, challengerId: string | null) {
  return phase === 'playing' && (userId === kingId || userId === challengerId);
}

export function canRequestQueueSwap(
  me: QueueLineMember | undefined,
  target: QueueLineMember,
  hasPendingRequest: boolean,
) {
  return me?.status === 'waiting'
    && target.status === 'waiting'
    && target.user_id !== me.user_id
    && target.queue_position > me.queue_position
    && !hasPendingRequest;
}

export function recentCompletedQueueGames<T extends QueueHistoryEntry>(games: T[]) {
  return games.filter((game) => game.status === 'completed').slice(0, 10);
}
