import { describe, expect, it } from 'vitest';
import { splitLeaderboardRows } from './leaderboards';
import { LeaderboardEntry } from './types';

const entry = (placement: number): LeaderboardEntry => ({
  placement,
  player_id: `player-${placement}`,
  display_name: `Player ${placement}`,
  current_elo: 1000,
  current_rank: 'Silver',
  is_provisional: false,
  net_elo_change: 0,
  total_games: 1,
  wins: 1,
  losses: 0,
  win_rate: 100,
  unique_opponents: 1,
  period_start: '2026-10-26',
  period_end: '2026-11-01',
});

describe('leaderboard display selection', () => {
  it('shows the top ten plus the current player when they are outside it', () => {
    const rows = Array.from({ length: 14 }, (_, index) => entry(index + 1));
    const result = splitLeaderboardRows(rows, 'player-13');
    expect(result.topRows).toHaveLength(10);
    expect(result.currentUserRow?.placement).toBe(13);
  });

  it('does not duplicate the current player when they are already in the top ten', () => {
    const rows = Array.from({ length: 12 }, (_, index) => entry(index + 1));
    const result = splitLeaderboardRows(rows, 'player-4');
    expect(result.currentUserRow).toBeNull();
  });
});
