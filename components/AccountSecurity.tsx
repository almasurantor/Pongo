'use client';

import { useEffect, useMemo, useState } from 'react';
import toast from 'react-hot-toast';
import { createClient } from '@/lib/supabase/client';

export default function AccountSecurity({ displayName, onDirtyChange }: { displayName: string; onDirtyChange?: (dirty: boolean) => void }) {
  const supabase = useMemo(() => createClient(), []);
  const [showPassword, setShowPassword] = useState(false);
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [deleteConfirmation, setDeleteConfirmation] = useState('');
  const [showDelete, setShowDelete] = useState(false);
  const [busy, setBusy] = useState('');

  useEffect(() => {
    onDirtyChange?.(Boolean(password || confirmation || deleteConfirmation));
  }, [confirmation, deleteConfirmation, onDirtyChange, password]);

  const changePassword = async () => {
    if (password.length < 8) {
      toast.error('Password must be at least 8 characters.');
      return;
    }
    if (password !== confirmation) {
      toast.error('Passwords do not match.');
      return;
    }
    setBusy('password');
    const { error } = await supabase.auth.updateUser({ password });
    setBusy('');
    if (error) {
      toast.error(error.message);
      return;
    }
    setPassword('');
    setConfirmation('');
    setShowPassword(false);
    toast.success('Password changed');
  };

  const deleteAccount = async () => {
    if (deleteConfirmation !== displayName) return;
    setBusy('delete');
    try {
      const response = await fetch('/api/account', {
        method: 'DELETE',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ confirmation: deleteConfirmation }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not delete account');
      await supabase.auth.signOut({ scope: 'local' });
      window.location.replace('/');
    } catch (error) {
      setBusy('');
      toast.error(error instanceof Error ? error.message : 'Could not delete account');
    }
  };

  return (
    <div className="space-y-4">
      <section className="rounded-2xl bg-accent-gray-50 p-4 dark:bg-[#0B1120]" aria-labelledby="account-security-title">
        <h3 id="account-security-title" className="font-black">Account security</h3>
        <p className="mt-1 text-xs text-accent-gray-500">Update your account password.</p>
        <button type="button" onClick={() => setShowPassword((shown) => !shown)} className="mt-4 min-h-12 w-full rounded-xl border-2 border-[#2563EB]/25 bg-white px-4 font-black text-[#1D4ED8] dark:bg-[#17243C] dark:text-[#93C5FD]">Change password</button>
        {showPassword && <div className="mt-4 space-y-3 rounded-xl border border-accent-gray-200 bg-white p-3 dark:bg-[#17243C]">
          <label className="block text-sm font-black">New password<input type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="new-password" minLength={8} className="mt-2 min-h-12 w-full rounded-xl border-2 border-accent-gray-200 bg-white px-4 font-normal outline-none focus:border-[#2563EB] dark:bg-[#0B1120]" /></label>
          <label className="block text-sm font-black">Confirm new password<input type="password" value={confirmation} onChange={(event) => setConfirmation(event.target.value)} autoComplete="new-password" minLength={8} className="mt-2 min-h-12 w-full rounded-xl border-2 border-accent-gray-200 bg-white px-4 font-normal outline-none focus:border-[#2563EB] dark:bg-[#0B1120]" /></label>
          <button type="button" disabled={busy === 'password'} onClick={() => void changePassword()} className="min-h-12 w-full rounded-xl bg-[#2563EB] font-black text-white disabled:opacity-50">{busy === 'password' ? 'Changing…' : 'Update password'}</button>
        </div>}
      </section>

      <section className="border-t border-accent-gray-200 pt-3 dark:border-[#334155]" aria-label="Account deletion">
        {!showDelete ? <button type="button" onClick={() => setShowDelete(true)} className="text-xs font-bold text-red-600/75 underline-offset-2 hover:text-red-700 hover:underline dark:text-red-400/75">Delete account</button> : <div className="space-y-3 rounded-xl border border-red-200 bg-red-50 p-3 dark:border-red-950 dark:bg-red-950/20">
          <label className="block text-sm font-black text-red-800 dark:text-red-300">Type <span className="select-all">{displayName}</span> to confirm<input value={deleteConfirmation} onChange={(event) => setDeleteConfirmation(event.target.value)} autoComplete="off" className="mt-2 min-h-12 w-full rounded-xl border-2 border-red-300 bg-white px-4 font-normal text-accent-black outline-none focus:border-red-600 dark:bg-[#0B1120] dark:text-white" /></label>
          <div className="grid grid-cols-2 gap-3">
            <button type="button" disabled={Boolean(busy)} onClick={() => { setShowDelete(false); setDeleteConfirmation(''); }} className="min-h-12 rounded-xl border-2 border-accent-gray-200 bg-white font-black dark:bg-[#17243C]">Cancel</button>
            <button type="button" disabled={busy === 'delete' || deleteConfirmation !== displayName} onClick={() => void deleteAccount()} className="min-h-12 rounded-xl bg-red-600 font-black text-white disabled:opacity-40">{busy === 'delete' ? 'Deleting…' : 'Delete account'}</button>
          </div>
        </div>}
      </section>
    </div>
  );
}
