export function authErrorMessage(error: unknown, fallback = 'Authentication failed. Please try again.') {
  const raw = error instanceof Error
    ? error.message
    : error && typeof error === 'object' && 'message' in error && typeof error.message === 'string'
      ? error.message
      : '';
  const message = raw.toLowerCase();

  if (message.includes('invalid login credentials')) return 'Email or password is incorrect.';
  if (message.includes('email not confirmed')) return 'This account is awaiting email confirmation. Ask an administrator to disable Confirm email in Supabase Auth settings.';
  if (message.includes('user already registered')) return 'An account with this email already exists. Sign in or reset your password.';
  if (message.includes('password should be')) return 'Password must be at least 6 characters.';
  if (message.includes('rate limit')) return 'Too many attempts. Wait a moment and try again.';
  if (message.includes('network') || message.includes('fetch') || message.includes('timed out') || message.includes('timeout')) return 'Could not reach the sign-in service. Check your connection and try again.';
  return raw || fallback;
}
