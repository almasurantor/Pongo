import { describe, expect, it } from 'vitest';
import { authRedirectForPath } from './auth-routing';

describe('PWA startup auth routing', () => {
  it('opens the dashboard for authenticated launches and auth pages', () => {
    expect(authRedirectForPath('/', true)).toBe('/dashboard');
    expect(authRedirectForPath('/login', true)).toBe('/dashboard');
    expect(authRedirectForPath('/signup', true)).toBe('/dashboard');
  });

  it('shows the landing page for a signed-out launch', () => {
    expect(authRedirectForPath('/', false)).toBeNull();
  });

  it('sends expired protected sessions to login', () => {
    expect(authRedirectForPath('/dashboard', false)).toBe('/login');
    expect(authRedirectForPath('/profile/player-id', false)).toBe('/login');
  });

  it('keeps authentication and static support routes public', () => {
    expect(authRedirectForPath('/login', false)).toBeNull();
    expect(authRedirectForPath('/auth/callback', false)).toBeNull();
    expect(authRedirectForPath('/forgot-password', false)).toBeNull();
    expect(authRedirectForPath('/reset-password', false)).toBeNull();
    expect(authRedirectForPath('/manifest.webmanifest', false)).toBeNull();
  });
});

