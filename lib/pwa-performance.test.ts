import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const serviceWorker = readFileSync(resolve(process.cwd(), 'public/sw.js'), 'utf8');
const queue = readFileSync(resolve(process.cwd(), 'app/queue/QueueClient.tsx'), 'utf8');
const matchResults = readFileSync(resolve(process.cwd(), 'components/MatchResultPopup.tsx'), 'utf8');
const browserClient = readFileSync(resolve(process.cwd(), 'lib/supabase/client.ts'), 'utf8');
const middleware = readFileSync(resolve(process.cwd(), 'middleware.ts'), 'utf8');
const sessionMiddleware = readFileSync(resolve(process.cwd(), 'lib/supabase/middleware.ts'), 'utf8');
const dashboardPage = readFileSync(resolve(process.cwd(), 'app/dashboard/page.tsx'), 'utf8');

describe('native-like PWA performance safeguards', () => {
  it('caches only static same-origin assets and keeps live/auth data network-only', () => {
    expect(serviceWorker).toContain("url.pathname.startsWith('/_next/static/')");
    expect(serviceWorker).toContain("url.pathname.startsWith('/api/')");
    expect(serviceWorker).toContain("url.pathname.startsWith('/auth/')");
    expect(serviceWorker).toContain("request.mode === 'navigate'");
    expect(serviceWorker).not.toContain('self.skipWaiting()');
  });

  it('uses one browser Supabase client and avoids duplicate API middleware auth', () => {
    expect(browserClient).toContain('if (browserClient) return browserClient');
    expect(middleware).toContain('api(?:/|$)');
    expect(middleware).toContain('auth/callback');
    expect(sessionMiddleware).toContain('verifiedHeaders.delete(VERIFIED_USER_HEADER)');
    expect(sessionMiddleware).toContain('verifiedHeaders.set(VERIFIED_USER_HEADER, user.id)');
    expect(dashboardPage).toContain('getVerifiedUserId()');
    expect(dashboardPage).not.toContain('auth.getUser()');
  });

  it('keeps queue correctness realtime-first with a restrained repair check', () => {
    expect(queue).toContain("supabase.channel('beaver-queue-live-v4')");
    expect(queue).toContain('15_000');
    expect(queue).toContain('APP_RESUME_EVENT');
    expect(queue).not.toContain('4000');
    expect(queue).not.toContain('250);');
  });

  it('checks missed match results on resume instead of polling continuously', () => {
    expect(matchResults).toContain("window.addEventListener('focus'");
    expect(matchResults).not.toContain('setInterval');
  });
});
