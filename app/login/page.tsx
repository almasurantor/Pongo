'use client';

import { useEffect, useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';
import toast from 'react-hot-toast';
import { motion } from 'framer-motion';
import PongoLogo from '@/components/PongoLogo';
import PongoWordmark from '@/components/PongoWordmark';
import PasswordField from '@/components/PasswordField';
import { authErrorMessage } from '@/lib/auth-errors';
import Link from 'next/link';

export default function LoginPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [formError, setFormError] = useState('');
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  useEffect(() => {
    const message = new URLSearchParams(window.location.search).get('error');
    if (message) setFormError(message);
  }, []);

  const handleEmailLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setFormError('');

    try {
      const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
      });

      if (error) throw error;

      toast.success('Logged in successfully!');
      router.replace('/dashboard');
      router.refresh();
    } catch (error: unknown) {
      const message = authErrorMessage(error, 'Failed to log in.');
      setFormError(message);
      toast.error(message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-[#0B1120] p-4 text-slate-100">
      <motion.div
        initial={{ opacity: 0, y: 20 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 0.5 }}
        className="w-full max-w-md"
      >
        <motion.div
          initial={{ scale: 0.95 }}
          animate={{ scale: 1 }}
          transition={{ duration: 0.3 }}
          className="rounded-2xl border border-slate-700 bg-[#111827] p-8 shadow-2xl shadow-black/30"
        >
          <motion.div
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.2 }}
            className="mb-8 text-center"
          >
            <div className="flex items-center justify-center gap-3" aria-label="Pongo">
              <PongoLogo alt="" size="lg" priority />
              <PongoWordmark className="text-4xl" />
            </div>
            <h1 className="mt-5 text-4xl font-bold text-white">Sign in</h1>
          </motion.div>

          <form onSubmit={handleEmailLogin} className="space-y-5 mb-6">
            {formError && <div role="alert" className="rounded-xl border border-red-500/50 bg-red-950/40 p-3 text-sm font-semibold text-red-200">{formError}</div>}
            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.3 }}
            >
              <label htmlFor="email" className="mb-2 block text-sm font-semibold text-slate-200">
                Email
              </label>
              <input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoComplete="email"
                className="w-full rounded-lg border-2 border-slate-600 bg-[#0B1120] px-4 py-3 text-white placeholder:text-slate-500 transition-all focus:border-transparent focus:outline-none focus:ring-2 focus:ring-[#2563EB]"
                placeholder="you@example.com"
              />
            </motion.div>

            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.4 }}
            >
              <PasswordField
                id="password"
                label="Password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                autoComplete="current-password"
                placeholder="••••••••"
              />
              <div className="mt-2 text-right"><Link href="/forgot-password" className="text-sm font-semibold text-[#60A5FA] hover:underline">Forgot password?</Link></div>
            </motion.div>

            <motion.button
              whileHover={{ scale: 1.02 }}
              whileTap={{ scale: 0.98 }}
              type="submit"
              disabled={loading}
              className="w-full py-3 gradient-orange text-white font-semibold rounded-lg shadow-lg transition-all disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {loading ? (
                <span className="flex items-center justify-center">
                  <svg className="animate-spin -ml-1 mr-3 h-5 w-5 text-white" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                  Loading...
                </span>
              ) : (
                'Sign In'
              )}
            </motion.button>
          </form>

          <div className="text-center mt-6">
            <p className="text-sm text-slate-400">
              Don&apos;t have an account?{' '}
              <Link
                href="/signup"
                className="font-semibold text-[#60A5FA] hover:underline"
              >
                Create Account
              </Link>
            </p>
          </div>
        </motion.div>
      </motion.div>
    </div>
  );
}
