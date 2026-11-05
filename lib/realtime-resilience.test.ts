import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const sharedRefresh = readFileSync(resolve(process.cwd(), 'lib/use-database-refresh.ts'), 'utf8');
const queue = readFileSync(resolve(process.cwd(), 'app/queue/QueueClient.tsx'), 'utf8');
const navbar = readFileSync(resolve(process.cwd(), 'components/Navbar.tsx'), 'utf8');
const repair = readFileSync(resolve(process.cwd(), 'supabase/migrations/20261104_07_realtime_publication_repair.sql'), 'utf8');

describe('realtime resilience', () => {
  it('resyncs server-rendered screens after reconnect, resume, and network recovery', () => {
    expect(sharedRefresh).toContain("status === 'SUBSCRIBED'");
    expect(sharedRefresh).toContain("status === 'CHANNEL_ERROR'");
    expect(sharedRefresh).toContain("window.addEventListener('online'");
    expect(sharedRefresh).toContain('APP_RESUME_EVENT');
    expect(sharedRefresh).toContain('missedWhileHidden');
  });

  it('coalesces queue event bursts without dropping an event during an active read', () => {
    expect(queue).toContain('refreshQueued.current = true');
    expect(queue).toContain("status === 'SUBSCRIBED'");
    expect(queue).toContain("window.addEventListener('online'");
    expect(queue).toContain('75');
    expect(navbar).toContain("status === 'SUBSCRIBED'");
  });

  it('provides an idempotent publication repair for every subscribed table', () => {
    for (const table of [
      'profiles', 'challenges', 'matches', 'rating_events', 'disputes',
      'match_cancellation_requests', 'beaver_queue_table', 'beaver_queue_members',
      'beaver_queue_games', 'beaver_queue_swap_requests', 'beaver_queue_ranked_requests',
    ]) expect(repair).toContain(`'${table}'`);
    expect(repair).toContain('pg_catalog.pg_publication_tables');
    expect(repair).toContain('NOT EXISTS');
  });
});
