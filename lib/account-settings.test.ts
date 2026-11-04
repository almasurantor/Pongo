import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const settings = readFileSync(resolve(process.cwd(), 'components/ProfileSettings.tsx'), 'utf8');
const security = readFileSync(resolve(process.cwd(), 'components/AccountSecurity.tsx'), 'utf8');
const profile = readFileSync(resolve(process.cwd(), 'app/profile/[id]/ProfileClient.tsx'), 'utf8');
const route = readFileSync(resolve(process.cwd(), 'app/api/account/route.ts'), 'utf8');
const navbar = readFileSync(resolve(process.cwd(), 'components/Navbar.tsx'), 'utf8');

describe('profile account settings', () => {
  it('keeps profile controls simple and puts settings last', () => {
    expect(settings).not.toContain('Queue turn sound');
    expect(settings).not.toContain('Queue push reminder');
    expect(navbar).not.toContain('playQueueChime');
    expect(navbar).not.toContain('showQueueNotification');
    expect(profile).toContain('Manage your public profile and account security.');
    expect(profile).toContain('<AccountSecurity');
    expect(profile.indexOf('<ThemeSettings embedded />')).toBeLessThan(profile.indexOf('aria-label="Profile settings"'));
    expect(profile.indexOf('View Landing Page')).toBeLessThan(profile.indexOf('aria-label="Profile settings"'));
    expect(profile.indexOf('Log out')).toBeLessThan(profile.indexOf('aria-label="Profile settings"'));
    expect(security).toContain('Change password');
    expect(security).not.toContain("signOut({ scope: 'others' })");
    expect(security).not.toContain('Danger Zone');
    expect(security).not.toContain('Completed match records remain');
    expect(security).toContain('Delete account');
  });

  it('guards and anonymizes soft account deletion', () => {
    expect(route).toContain('SUPABASE_SERVICE_ROLE_KEY');
    expect(route).toContain("activeQueueStatuses.includes(queueMember.status)");
    expect(route).toContain('resolve all pending matches and challenges');
    expect(route).toContain('anonymousName');
    expect(route).toContain('deleteUser(user.id, true)');
  });
});
