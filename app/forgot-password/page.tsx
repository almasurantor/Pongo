'use client';

import Link from 'next/link';
import { FormEvent, useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { authErrorMessage } from '@/lib/auth-errors';
import PongoLogo from '@/components/PongoLogo';
import PongoWordmark from '@/components/PongoWordmark';

export default function ForgotPasswordPage() {
  const supabase = useMemo(() => createClient(), []);
  const [email, setEmail] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');
  const [error, setError] = useState('');

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setLoading(true);
    setError('');
    setMessage('');
    try {
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/auth/callback?next=/reset-password`,
      });
      if (resetError) throw resetError;
      setMessage('If an account exists for that email, a password reset link is on its way.');
    } catch (caught) {
      setError(authErrorMessage(caught, 'Could not send the reset link.'));
    } finally {
      setLoading(false);
    }
  };

  return (
    <main className="flex min-h-screen items-center justify-center bg-[#0B1120] p-4 text-slate-100">
      <section className="w-full max-w-md rounded-2xl border border-slate-700 bg-[#111827] p-8 shadow-2xl shadow-black/30">
        <div className="flex items-center justify-center gap-3"><PongoLogo alt="" size="lg" priority /><PongoWordmark className="text-4xl" /></div>
        <h1 className="mt-6 text-3xl font-black">Reset your password</h1>
        <p className="mt-2 text-sm text-slate-400">We’ll email you a secure link to choose a new password.</p>
        <form onSubmit={submit} className="mt-6 space-y-5">
          {error && <div role="alert" className="rounded-xl border border-red-500/50 bg-red-950/40 p-3 text-sm font-semibold text-red-200">{error}</div>}
          {message && <div role="status" className="rounded-xl border border-green-500/50 bg-green-950/30 p-3 text-sm font-semibold text-green-200">{message}</div>}
          <div>
            <label htmlFor="email" className="mb-2 block text-sm font-semibold text-slate-200">Email</label>
            <input id="email" type="email" autoComplete="email" required value={email} onChange={(event) => setEmail(event.target.value)} className="w-full rounded-xl border-2 border-slate-600 bg-[#0B1120] px-4 py-3 text-white outline-none transition focus:border-[#3B82F6] focus:ring-2 focus:ring-blue-500/20" placeholder="you@example.com" />
          </div>
          <button disabled={loading} className="min-h-12 w-full rounded-xl gradient-orange font-black text-white disabled:opacity-50">{loading ? 'Sending…' : 'Send reset link'}</button>
        </form>
        <Link href="/login" className="mt-6 block text-center text-sm font-semibold text-[#60A5FA] hover:underline">Back to sign in</Link>
      </section>
    </main>
  );
}
