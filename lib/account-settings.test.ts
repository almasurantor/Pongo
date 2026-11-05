import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const settings = readFileSync(resolve(process.cwd(), 'components/ProfileSettings.tsx'), 'utf8');
const security = readFileSync(resolve(process.cwd(), 'components/AccountSecurity.tsx'), 'utf8');
const profile = readFileSync(resolve(process.cwd(), 'app/profile/[id]/ProfileClient.tsx'), 'utf8');
const panel = readFileSync(resolve(process.cwd(), 'components/ProfileSettingsPanel.tsx'), 'utf8');
const avatarEditor = readFileSync(resolve(process.cwd(), 'components/AvatarEditor.tsx'), 'utf8');
const confirmDialog = readFileSync(resolve(process.cwd(), 'components/InAppConfirmDialog.tsx'), 'utf8');
const admin = readFileSync(resolve(process.cwd(), 'app/admin/AdminClient.tsx'), 'utf8');
const route = readFileSync(resolve(process.cwd(), 'app/api/account/route.ts'), 'utf8');
const navbar = readFileSync(resolve(process.cwd(), 'components/Navbar.tsx'), 'utf8');

describe('profile account settings', () => {
  it('keeps profile controls in a dedicated settings panel', () => {
    expect(settings).not.toContain('Queue turn sound');
    expect(settings).not.toContain('Queue push reminder');
    expect(navbar).not.toContain('playQueueChime');
    expect(navbar).not.toContain('showQueueNotification');
    expect(profile).toContain('aria-label="Open settings"');
    expect(profile).toContain('<ProfileSettingsPanel');
    expect(profile).toContain('<ThemeSettings embedded />');
    expect(profile).toContain('View Landing Page');
    expect(profile).not.toContain('<AccountSecurity');
    expect(panel).toContain('<ProfileSettings');
    expect(panel).toContain('<AccountSecurity');
    expect(panel).toContain('Log out');
    expect(panel).not.toContain('<ThemeSettings');
    expect(panel).not.toContain('View Landing Page');
    expect(panel).toContain('<InAppConfirmDialog');
    expect(panel).not.toContain('window.confirm');
    expect(avatarEditor).toContain('<InAppConfirmDialog');
    expect(avatarEditor).not.toContain('window.confirm');
    expect(confirmDialog).toContain('role="alertdialog"');
    expect(admin).not.toContain('window.confirm');
    expect(admin).not.toContain('window.prompt');
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
