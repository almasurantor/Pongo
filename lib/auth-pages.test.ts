import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const login = readFileSync(resolve(process.cwd(), 'app/login/page.tsx'), 'utf8');
const signup = readFileSync(resolve(process.cwd(), 'app/signup/page.tsx'), 'utf8');
const sharedBranding = '<PongoLogo alt="" size="lg" priority />';
const sharedWordmark = '<PongoWordmark className="text-4xl" />';

describe('email and password authentication pages', () => {
  it('uses identical Pongo branding on sign in and create account', () => {
    expect(login).toContain(sharedBranding);
    expect(signup).toContain(sharedBranding);
    expect(login).toContain(sharedWordmark);
    expect(signup).toContain(sharedWordmark);
  });

  it('does not offer Google OAuth while preserving email authentication', () => {
    for (const source of [login, signup]) {
      expect(source).not.toContain('signInWithOAuth');
      expect(source).not.toContain('Continue with Google');
      expect(source).not.toContain('>Or</span>');
    }
    expect(login).toContain('signInWithPassword');
    expect(signup).toContain('auth.signUp');
  });

  it('uses the intended display-name example', () => {
    expect(signup).toContain('placeholder="Nathan 🐐"');
    expect(signup).not.toContain('placeholder="Almas 🏓"');
  });
});
