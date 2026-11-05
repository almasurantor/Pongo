'use client';

import { usePathname, useRouter } from 'next/navigation';
import { useEffect, useRef } from 'react';
import { APP_HIDDEN_AT_KEY, APP_RESUME_EVENT, hasBeenAwayLongEnough } from '@/lib/app-resume';

const REFRESHABLE_APP_PATHS = ['/dashboard', '/leaderboard', '/players', '/profile/', '/match/'];

export default function AppResumeRedirect() {
  const pathname = usePathname();
  const router = useRouter();
  const pathnameRef = useRef(pathname);
  const reconciling = useRef(false);

  useEffect(() => {
    const navigatedInApp = pathnameRef.current !== pathname;
    pathnameRef.current = pathname;
    reconciling.current = false;

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
      if (reconciling.current || document.visibilityState !== 'visible') return;
      const hiddenAt = window.localStorage.getItem(APP_HIDDEN_AT_KEY);
      if (!hasBeenAwayLongEnough(hiddenAt)) {
        window.localStorage.removeItem(APP_HIDDEN_AT_KEY);
        return;
      }
      reconciling.current = true;
      window.localStorage.removeItem(APP_HIDDEN_AT_KEY);
      window.dispatchEvent(new CustomEvent(APP_RESUME_EVENT));
      // Keep the existing screen visible while server-backed, non-live data
      // refreshes. Queue reconciles directly and must not be remounted here.
      if (REFRESHABLE_APP_PATHS.some((prefix) => pathname === prefix || pathname.startsWith(prefix))) {
        router.refresh();
      }
      window.setTimeout(() => { reconciling.current = false; }, 1_000);
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
  }, [pathname, router]);

  return null;
}
