export type QueueMemberStatus = 'waiting' | 'called' | 'king' | 'playing' | 'left' | 'no_show';

export interface QueueLineMember {
  user_id: string;
  status: QueueMemberStatus;
  queue_position: number;
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
