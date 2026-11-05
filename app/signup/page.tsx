'use client';

import { useMemo, useState } from 'react';
import { createClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';
import toast from 'react-hot-toast';
import { motion } from 'framer-motion';
import Link from 'next/link';
import PongoLogo from '@/components/PongoLogo';
import PongoWordmark from '@/components/PongoWordmark';
import PasswordField from '@/components/PasswordField';
import { authErrorMessage } from '@/lib/auth-errors';

export default function SignUpPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [displayName, setDisplayName] = useState('');
  const [loading, setLoading] = useState(false);
  const [formError, setFormError] = useState('');
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);

  const handleSignUp = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setFormError('');

    if (password !== confirmPassword) {
      setFormError('Passwords do not match.');
      setLoading(false);
      return;
    }

    if (password.length < 6) {
      setFormError('Password must be at least 6 characters.');
      setLoading(false);
      return;
    }

    try {
      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          emailRedirectTo: `${window.location.origin}/auth/callback?next=/dashboard`,
          data: {
            display_name: displayName || email.split('@')[0],
          },
        },
      });

      if (error) throw error;

      if (data.session) {
        toast.success('Account created!');
        router.replace('/dashboard');
        router.refresh();
      } else if (data.user) {
        const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
        if (signInError) throw signInError;
        toast.success('Account created!');
        router.replace('/dashboard');
        router.refresh();
      }
    } catch (error: unknown) {
      const message = authErrorMessage(error, 'Failed to create account.');
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
            className="text-center mb-8"
          >
            <div className="flex items-center justify-center gap-3" aria-label="Pongo">
              <PongoLogo alt="" size="lg" priority />
              <PongoWordmark className="text-4xl" />
            </div>
            <h1 className="mt-5 text-4xl font-bold text-white">Create account</h1>
          </motion.div>

          <form onSubmit={handleSignUp} className="space-y-5 mb-6">
            {formError && <div role="alert" className="rounded-xl border border-red-500/50 bg-red-950/40 p-3 text-sm font-semibold text-red-200">{formError}</div>}
            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.3 }}
            >
              <label htmlFor="displayName" className="mb-2 block text-sm font-semibold text-slate-200">
                Display Name (Optional)
              </label>
              <input
                id="displayName"
                type="text"
                value={displayName}
                onChange={(e) => setDisplayName(e.target.value)}
                className="w-full rounded-xl border-2 border-slate-600 bg-[#0B1120] px-4 py-3 text-white placeholder:text-slate-500 outline-none transition focus:border-[#3B82F6] focus:ring-2 focus:ring-blue-500/20"
                placeholder="Your name"
              />
            </motion.div>

            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.35 }}
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
                className="w-full rounded-xl border-2 border-slate-600 bg-[#0B1120] px-4 py-3 text-white placeholder:text-slate-500 outline-none transition focus:border-[#3B82F6] focus:ring-2 focus:ring-blue-500/20"
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
                minLength={6}
                autoComplete="new-password"
                placeholder="••••••••"
                hint="Must be at least 6 characters"
              />
            </motion.div>

            <motion.div
              initial={{ opacity: 0, x: -20 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: 0.45 }}
            >
              <PasswordField
                id="confirmPassword"
                label="Confirm Password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                required
                minLength={6}
                autoComplete="new-password"
                placeholder="••••••••"
              />
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
                  Creating Account...
                </span>
              ) : (
                'Create Account'
              )}
            </motion.button>
          </form>

          <div className="text-center mt-6">
            <p className="text-sm text-slate-400">
              Already have an account?{' '}
              <Link
                href="/login"
                className="font-semibold text-[#60A5FA] hover:underline"
              >
                Sign In
              </Link>
            </p>
          </div>
        </motion.div>
      </motion.div>
    </div>
  );
}
