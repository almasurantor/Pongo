import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(resolve(process.cwd(), 'supabase/migrations/20261106010000_match_overtime_emoji_usernames.sql'), 'utf8');
const queueClient = readFileSync(resolve(process.cwd(), 'app/queue/QueueClient.tsx'), 'utf8');

describe('match overtime migration', () => {
  it('serializes decisions on the queue row and permits only one extension', () => {
    expect(migration).toContain('WHERE id=1 FOR UPDATE');
    expect(migration).toContain("normalized_action NOT IN('extend','end')");
    expect(migration).toContain("game_expires_at=extended_until");
    expect(migration).toContain("AND overtime_used=FALSE");
    expect(migration).toContain("extended_until:=clock_timestamp()+INTERVAL '2 minutes'");
  });

  it('uses the existing worker and abandons expired games without a result', () => {
    expect(migration).toContain('CREATE OR REPLACE FUNCTION public.beaver_queue_advance_internal_v1()');
    expect(migration).toContain("COALESCE(holder_name,'Player'),COALESCE(next_name,'Player'),'abandoned'");
    expect(migration).toContain('winner_id,loser_id,reported_by');
    expect(migration).toContain('NULL,NULL,NULL,NULL,NULL,clock_timestamp()');
    expect(migration).not.toContain('cron.schedule');
  });

  it('renders both overtime choices from server timestamps and refreshes through Realtime', () => {
    expect(queueClient).toContain('Need more time?');
    expect(queueClient).toContain('+2 Minutes');
    expect(queueClient).toContain('End Match');
    expect(queueClient).toContain('overtime_prompt_expires_at');
    expect(queueClient).toContain(".on('postgres_changes', { event: '*', schema: 'public', table: 'beaver_queue_table' }");
  });
});
