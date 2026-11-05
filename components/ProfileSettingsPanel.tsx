'use client';

import { useCallback, useEffect, useState } from 'react';
import AccountSecurity from '@/components/AccountSecurity';
import InAppConfirmDialog from '@/components/InAppConfirmDialog';
import ProfileSettings from '@/components/ProfileSettings';
import { Profile } from '@/lib/types';

export default function ProfileSettingsPanel({ profile, onSaved, onClose, onLogout }: {
  profile: Profile;
  onSaved: (profile: Profile) => void;
  onClose: () => void;
  onLogout: () => void;
}) {
  const [profileDirty, setProfileDirty] = useState(false);
  const [securityDirty, setSecurityDirty] = useState(false);
  const [pendingAction, setPendingAction] = useState<'close' | 'logout' | null>(null);
  const dirty = profileDirty || securityDirty;

  const requestClose = useCallback(() => {
    if (dirty) { setPendingAction('close'); return; }
    onClose();
  }, [dirty, onClose]);

  const requestLogout = useCallback(() => {
    if (dirty) { setPendingAction('logout'); return; }
    onLogout();
  }, [dirty, onLogout]);

  useEffect(() => {
    const previousOverflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    const closeOnEscape = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return;
      if (pendingAction) setPendingAction(null);
      else requestClose();
    };
    window.addEventListener('keydown', closeOnEscape);
    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener('keydown', closeOnEscape);
    };
  }, [pendingAction, requestClose]);

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-[#07152F]/75 backdrop-blur-sm"
      style={{
        paddingTop: 'max(.5rem, env(safe-area-inset-top))',
        paddingRight: 'max(.5rem, env(safe-area-inset-right))',
        paddingBottom: 'max(.5rem, env(safe-area-inset-bottom))',
        paddingLeft: 'max(.5rem, env(safe-area-inset-left))',
      }}
      role="dialog"
      aria-modal="true"
      aria-labelledby="profile-settings-title"
    >
      <section className="flex max-h-full w-full max-w-2xl flex-col overflow-hidden rounded-[2rem] border border-accent-gray-200 bg-accent-gray-50 shadow-2xl dark:border-[#334155] dark:bg-[#0B1120]">
        <header className="flex shrink-0 items-center gap-3 border-b border-accent-gray-200 bg-white px-4 py-3 dark:border-[#334155] dark:bg-[#111827] sm:px-5">
          <button type="button" onClick={requestClose} className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-accent-gray-100 text-xl font-black text-accent-gray-700 dark:bg-[#1E293B] dark:text-white" aria-label="Back to profile">←</button>
          <div className="min-w-0 flex-1"><h2 id="profile-settings-title" className="text-xl font-black">Settings</h2><p className="text-xs text-accent-gray-500">Display name and account security</p></div>
          <button type="button" onClick={requestClose} className="min-h-10 rounded-full px-3 text-sm font-black text-[#2563EB] dark:text-[#93C5FD]">Done</button>
        </header>

        <div className="min-h-0 flex-1 space-y-3 overflow-y-auto overscroll-contain p-3 pb-[max(1rem,env(safe-area-inset-bottom))] sm:p-5">
          <section className="rounded-3xl border border-accent-gray-200 bg-white p-4 shadow-sm dark:border-[#334155] dark:bg-[#111827]">
            <h3 className="mb-3 text-lg font-black">Public profile</h3>
            <ProfileSettings profile={profile} onSaved={onSaved} onDirtyChange={setProfileDirty} />
          </section>

          <section className="rounded-3xl border border-accent-gray-200 bg-white p-4 shadow-sm dark:border-[#334155] dark:bg-[#111827]">
            <AccountSecurity displayName={profile.display_name} onDirtyChange={setSecurityDirty} />
          </section>

          <section className="rounded-3xl border border-accent-gray-200 bg-white p-4 shadow-sm dark:border-[#334155] dark:bg-[#111827]">
            <button type="button" onClick={requestLogout} className="min-h-12 w-full rounded-2xl border border-red-200 font-black text-red-600 dark:border-red-900 dark:text-red-400">Log out</button>
          </section>
        </div>
      </section>
      {pendingAction && (
        <InAppConfirmDialog
          title={pendingAction === 'logout' ? 'Discard changes and log out?' : 'Discard settings changes?'}
          message={pendingAction === 'logout' ? 'Your unsaved settings will be lost before you log out.' : 'Your unsaved display name or security changes will be lost.'}
          cancelLabel="Keep editing"
          confirmLabel={pendingAction === 'logout' ? 'Discard & log out' : 'Discard'}
          onCancel={() => setPendingAction(null)}
          onConfirm={pendingAction === 'logout' ? onLogout : onClose}
        />
      )}
    </div>
  );
}
