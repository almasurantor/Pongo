'use client';

import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useMemo, useRef } from 'react';
import { APP_HIDDEN_AT_KEY, hasBeenAwayLongEnough } from '@/lib/app-resume';
import { createClient } from '@/lib/supabase/client';

export default function AppResumeRedirect() {
  const pathname = usePathname();
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const pathnameRef = useRef(pathname);
  const redirecting = useRef(false);

  useEffect(() => {
    const navigatedInApp = pathnameRef.current !== pathname;
    pathnameRef.current = pathname;
    if (pathname === '/dashboard') redirecting.current = false;

    // An intentional client-side visit to the landing page starts a fresh
    // active session and must never bounce straight back to the dashboard.
    const intentionalLandingVisit = navigatedInApp && pathname === '/landing';
    if (intentionalLandingVisit) {
      window.localStorage.removeItem(APP_HIDDEN_AT_KEY);
    }

    const recordHidden = () => {
      window.localStorage.setItem(APP_HIDDEN_AT_KEY, String(Date.now()));
    };
    const evaluateResume = async () => {
      if (redirecting.current || document.visibilityState !== 'visible') return;
      const hiddenAt = window.localStorage.getItem(APP_HIDDEN_AT_KEY);
      if (!hasBeenAwayLongEnough(hiddenAt)) {
        window.localStorage.removeItem(APP_HIDDEN_AT_KEY);
        return;
      }
      const { data } = await supabase.auth.getSession();
      window.localStorage.removeItem(APP_HIDDEN_AT_KEY);
      if (!data.session || pathname === '/dashboard') return;
      redirecting.current = true;
      router.replace('/dashboard');
    };
    const visibilityChanged = () => {
      if (document.visibilityState === 'hidden') recordHidden();
      else void evaluateResume();
    };

    if (!intentionalLandingVisit) void evaluateResume();
    document.addEventListener('visibilitychange', visibilityChanged);
    window.addEventListener('focus', evaluateResume);
    window.addEventListener('pagehide', recordHidden);
    return () => {
      document.removeEventListener('visibilitychange', visibilityChanged);
      window.removeEventListener('focus', evaluateResume);
      window.removeEventListener('pagehide', recordHidden);
    };
  }, [pathname, router, supabase]);

  return null;
}
