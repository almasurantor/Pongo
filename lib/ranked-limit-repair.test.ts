import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { DAILY_RANKED_PAIR_LIMIT, DAILY_RANKED_PAIR_LIMIT_MESSAGE } from './ranked-limits';

const queueMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20261104_04_queue_ranked_matches.sql',
), 'utf8');
const repairMigration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20261104_08_restore_three_ranked_games_per_opponent.sql',
), 'utf8');

describe('three Ranked games per opponent repair', () => {
  it('keeps fresh installs and upgraded databases on the same 10/3 limits', () => {
    expect(DAILY_RANKED_PAIR_LIMIT).toBe(3);
    expect(DAILY_RANKED_PAIR_LIMIT_MESSAGE).toContain('3 ranked games');
    expect(queueMigration).toContain('daily_ranked_player_limit=10');
    expect(queueMigration).toContain('daily_ranked_pair_limit=3');
    expect(queueMigration).not.toContain('daily_ranked_pair_limit=10');
    expect(repairMigration).toContain('daily_ranked_player_limit=10');
    expect(repairMigration).toContain('daily_ranked_pair_limit=3');
  });

  it('preflights queue requests and retains acceptance-time enforcement', () => {
    expect(repairMigration).toContain(
      'PERFORM public.assert_ranked_match_eligibility_v4(player_id,opponent);',
    );
    expect(queueMigration).toContain(
      'PERFORM public.assert_ranked_match_eligibility_v4(request.requester_id,request.opponent_id);',
    );
    expect(queueMigration).toContain('ORDER BY id\n  FOR UPDATE;');
  });
});
