import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { avatarOptions } from './avatar';

const migration = readFileSync(resolve(
  process.cwd(),
  'supabase/migrations/20261111010000_expand_avatar_options.sql',
), 'utf8');

describe('expanded avatar database constraint', () => {
  it('allows every frontend option while retaining the legacy expressions', () => {
    for (const options of Object.values(avatarOptions)) {
      for (const option of options) expect(migration).toContain(`'${option}'`);
    }
    for (const legacyExpression of ['confident', 'surprised']) {
      expect(migration).toContain(`'${legacyExpression}'`);
    }
  });

  it('validates the additive constraint before removing v1', () => {
    const addV2 = migration.indexOf('ADD CONSTRAINT profiles_avatar_config_v2_check');
    const validateV2 = migration.indexOf('VALIDATE CONSTRAINT profiles_avatar_config_v2_check');
    const dropV1 = migration.indexOf('DROP CONSTRAINT IF EXISTS profiles_avatar_config_v1_check');
    expect(addV2).toBeGreaterThanOrEqual(0);
    expect(validateV2).toBeGreaterThan(addV2);
    expect(dropV1).toBeGreaterThan(validateV2);
  });

  it('does not rewrite or delete profile data or replace the save RPC', () => {
    expect(migration).not.toMatch(/UPDATE\s+public\.profiles/i);
    expect(migration).not.toMatch(/DELETE\s+FROM\s+public\.profiles/i);
    expect(migration).not.toContain('CREATE OR REPLACE FUNCTION public.update_my_avatar_v1');
    expect(migration).toContain("to_regprocedure('public.update_my_avatar_v1(jsonb)')");
  });
});
