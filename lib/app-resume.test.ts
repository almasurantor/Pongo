import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { APP_AWAY_REVALIDATE_MS, APP_RESUME_EVENT, hasBeenAwayLongEnough } from './app-resume';

const resumeClient = readFileSync(resolve(process.cwd(), 'components/AppResumeRedirect.tsx'), 'utf8');

describe('installed app resume policy', () => {
  it('preserves the current screen during a short app switch', () => {
    expect(hasBeenAwayLongEnough(String(1_000), 1_000 + APP_AWAY_REVALIDATE_MS - 1)).toBe(false);
  });

  it('revalidates after fifteen minutes away', () => {
    expect(hasBeenAwayLongEnough(String(1_000), 1_000 + APP_AWAY_REVALIDATE_MS)).toBe(true);
  });

  it('ignores missing or malformed timestamps', () => {
    expect(hasBeenAwayLongEnough(null)).toBe(false);
    expect(hasBeenAwayLongEnough('not-a-time')).toBe(false);
  });

  it('uses one shared resume event for live screens to reconcile themselves', () => {
    expect(APP_RESUME_EVENT).toBe('pongo:resume');
    expect(resumeClient).toContain('router.refresh()');
    expect(resumeClient).not.toContain("router.replace('/dashboard')");
    expect(resumeClient).not.toContain('auth.getSession()');
  });
});
