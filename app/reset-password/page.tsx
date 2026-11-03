'use client';

import { FormEvent, useMemo, useState } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { authErrorMessage } from '@/lib/auth-errors';
import PasswordField from '@/components/PasswordField';
import PongoLogo from '@/components/PongoLogo';
import PongoWordmark from '@/components/PongoWordmark';

export default function ResetPasswordPage() {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();
  const [password, setPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setError('');
    if (password.length < 6) return setError('Password must be at least 6 characters.');
    if (password !== confirmation) return setError('Passwords do not match.');
    setLoading(true);
    try {
      const { error: updateError } = await supabase.auth.updateUser({ password });
      if (updateError) throw updateError;
      router.replace('/dashboard');
      router.refresh();
    } catch (caught) {
      setError(authErrorMessage(caught, 'Could not update your password. Request a new reset link and try again.'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#0B1120] p-4 text-slate-100">
      <section className="w-full max-w-md rounded-2xl border border-slate-700 bg-[#111827] p-8 shadow-2xl shadow-black/30">
        <div className="flex items-center justify-center gap-3"><PongoLogo alt="" size="lg" priority /><PongoWordmark className="text-4xl" /></div>
        <h1 className="mt-6 text-3xl font-black">Choose a new password</h1>
        <form onSubmit={submit} className="mt-6 space-y-5">
          {error && <div role="alert" className="rounded-xl border border-red-500/50 bg-red-950/40 p-3 text-sm font-semibold text-red-200">{error}</div>}
          <PasswordField id="newPassword" label="New password" value={password} onChange={(event) => setPassword(event.target.value)} minLength={6} required autoComplete="new-password" hint="Must be at least 6 characters" />
          <PasswordField id="confirmNewPassword" label="Confirm new password" value={confirmation} onChange={(event) => setConfirmation(event.target.value)} minLength={6} required autoComplete="new-password" />
          <button disabled={loading} className="min-h-12 w-full rounded-xl gradient-orange font-black text-white disabled:opacity-50">{loading ? 'Saving…' : 'Save new password'}</button>
        </form>
      </section>
    </main>
  );
}
