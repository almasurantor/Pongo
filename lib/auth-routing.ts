const PUBLIC_PREFIXES = ['/landing', '/login', '/signup', '/forgot-password', '/reset-password', '/_next', '/api', '/auth'];
const PUBLIC_FILES = new Set(['/', '/manifest.webmanifest', '/sw.js', '/offline.html']);

export function authRedirectForPath(pathname: string, authenticated: boolean): '/dashboard' | '/' | null {
  const authEntry = pathname === '/'
    || pathname.startsWith('/login')
    || pathname.startsWith('/signup');

  if (authenticated && authEntry) return '/dashboard';
  if (authenticated) return null;

  const publicPath = PUBLIC_FILES.has(pathname)
    || PUBLIC_PREFIXES.some((prefix) => pathname.startsWith(prefix));
  return publicPath ? null : '/';
}

