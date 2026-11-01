import { LeaderboardEntry } from './types';

export function splitLeaderboardRows(entries: LeaderboardEntry[], currentUserId: string, limit = 10) {
  const topRows = entries.filter((entry) => entry.placement <= limit);
  const currentUserRow = entries.find(
    (entry) => entry.player_id === currentUserId && entry.placement > limit,
  ) ?? null;
  return { topRows, currentUserRow };
}
