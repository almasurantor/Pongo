import { describe, expect, it } from 'vitest';
import { authRedirectForPath } from './auth-routing';

describe('PWA startup auth routing', () => {
  it('opens the queue for authenticated launches and auth pages', () => {
    expect(authRedirectForPath('/', true)).toBe('/queue');
    expect(authRedirectForPath('/login', true)).toBe('/queue');
    expect(authRedirectForPath('/signup', true)).toBe('/queue');
  });

  it('shows the landing page for a signed-out launch', () => {
    expect(authRedirectForPath('/', false)).toBeNull();
  });

  it('sends signed-out protected visits to the public landing page', () => {
    expect(authRedirectForPath('/dashboard', false)).toBe('/');
    expect(authRedirectForPath('/profile/player-id', false)).toBe('/');
  });

  it('keeps authentication and static support routes public', () => {
    expect(authRedirectForPath('/login', false)).toBeNull();
    expect(authRedirectForPath('/auth/callback', false)).toBeNull();
    expect(authRedirectForPath('/forgot-password', false)).toBeNull();
    expect(authRedirectForPath('/reset-password', false)).toBeNull();
    expect(authRedirectForPath('/landing', false)).toBeNull();
    expect(authRedirectForPath('/landing', true)).toBeNull();
    expect(authRedirectForPath('/manifest.webmanifest', false)).toBeNull();
  });
});

