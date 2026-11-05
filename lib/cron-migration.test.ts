import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20261104100000_queue_maintenance_worker.sql',
), 'utf8');
const hostedReadonlyVerifier = readFileSync(resolve(
  process.cwd(),
  'scripts/hosted-readonly-verification.mjs',
), 'utf8');
const hostedQueueExpiry = readFileSync(resolve(
  process.cwd(),
  'scripts/hosted-queue-expiry-smoke.mjs',
), 'utf8');
const hostedReleaseVerifier = readFileSync(resolve(
  process.cwd(),
  'scripts/hosted-release-verification.mjs',
), 'utf8');

describe('production maintenance Cron migration', () => {
  it('uses the intended named schedules and exact maintenance wrappers', () => {
    expect(migration).toContain("'pongo-queue-expiration-v1'");
    expect(migration).toContain("'10 seconds'");
    expect(migration).toContain("'SELECT public.run_pongo_queue_maintenance_v1()'");
    expect(migration).toContain("'pongo-ranked-expiration-v1'");
    expect(migration).toContain("'*/5 * * * *'");
    expect(migration).toContain("'SELECT public.run_pongo_ranked_maintenance_v1()'");
  });

  it('fails on missing dependencies or conflicting duplicate commands', () => {
    expect(migration).toContain("to_regprocedure('public.beaver_queue_advance_expired_v1()')");
    expect(migration).toContain("to_regprocedure('public.expire_mobile_ranking_items_v2()')");
    expect(migration).toContain('Conflicting Pongo Cron job exists');
    expect(migration).toContain('installed_count<>3');
  });

  it('keeps workers private while exposing read-only health to authenticated verification', () => {
    expect(hostedReadonlyVerifier).toContain('queueHealth.response.ok');
    expect(hostedReadonlyVerifier).toContain('rankedHealth.response.ok');
    expect(hostedQueueExpiry).toContain("rpc/pongo_queue_maintenance_health_v1");
    expect(hostedReleaseVerifier).toContain("admin.rpc('pongo_queue_maintenance_health_v1')");
    expect(hostedReleaseVerifier).toContain("admin.rpc('pongo_ranked_maintenance_health_v1')");
  });
});
