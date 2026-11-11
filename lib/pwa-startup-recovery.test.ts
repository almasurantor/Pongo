import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { createFetchWithTimeout } from './fetch-with-timeout';

const read = (path: string) => readFileSync(resolve(process.cwd(), path), 'utf8');
const serviceWorker = read('public/sw.js');
const startupRecovery = read('components/StartupRecoveryScript.tsx');
const layout = read('app/layout.tsx');
const manifest = read('app/manifest.ts');
const middleware = read('lib/supabase/middleware.ts');

describe('PWA cold-launch recovery', () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it('runs without application bundles and provides a no-React fallback', () => {
    expect(layout.indexOf('<StartupRecoveryScript />')).toBeLessThan(layout.indexOf('<script dangerouslySetInnerHTML={{ __html: themeScript }} />'));
    expect(startupRecovery).not.toContain("from 'next/script'");
    expect(startupRecovery).toContain('literal inline script');
    expect(startupRecovery).toContain("window.addEventListener('error'");
    expect(startupRecovery).toContain("window.addEventListener('unhandledrejection'");
    expect(startupRecovery).toContain("pathname.indexOf('/_next/static/') === 0");
    expect(startupRecovery).toContain('Pongo could not finish opening');
    expect(startupRecovery).toContain('BOOT_TIMEOUT_MS = 15000');
  });

  it('repairs only deployment caches once and leaves sessions and user storage intact', () => {
    expect(startupRecovery).toContain("key.indexOf('pongo-assets-') === 0");
    expect(startupRecovery).toContain('RECOVERY_WINDOW_MS = 60000');
    expect(startupRecovery).not.toContain('localStorage.clear');
    expect(startupRecovery).not.toContain('sessionStorage.clear');
    expect(startupRecovery).not.toContain('registration.unregister');
  });

  it('activates the shell-only worker and removes obsolete Pongo caches', () => {
    expect(serviceWorker).toContain("const CACHE_PREFIXES = ['pongo-', 'beaver-smash-']");
    expect(serviceWorker).toContain('key !== SHELL_CACHE');
    expect(serviceWorker).not.toContain('pongo-assets-v4');
    expect(serviceWorker).not.toContain("url.pathname.startsWith('/_next/static/')");
  });

  it('keeps the standalone launch URL stable and in scope', () => {
    expect(manifest).toContain("id: '/'");
    expect(manifest).toContain("start_url: '/queue'");
    expect(manifest).toContain("scope: '/'");
    expect(manifest).toContain("display: 'standalone'");
  });

  it('turns a stalled auth verification into a recoverable signed-out request', () => {
    expect(middleware).toContain('AUTH_FETCH_TIMEOUT_MS');
    expect(middleware).toContain('try {');
    expect(middleware).toContain('await supabase.auth.getUser()');
    expect(middleware).toContain('without deleting the');
  });

  it('aborts a network call at its configured deadline', async () => {
    vi.useFakeTimers();
    vi.stubGlobal('fetch', vi.fn((_input: RequestInfo | URL, init?: RequestInit) => new Promise<Response>((_resolve, reject) => {
      init?.signal?.addEventListener('abort', () => reject(init.signal?.reason), { once: true });
    })));

    const pending = createFetchWithTimeout(25)('https://example.test');
    const assertion = expect(pending).rejects.toMatchObject({ name: 'TimeoutError' });
    await vi.advanceTimersByTimeAsync(25);
    await assertion;
  });
});
