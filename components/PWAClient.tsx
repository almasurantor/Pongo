'use client';

import { useEffect, useState } from 'react';
import { CHUNK_RECOVERY_KEY, isChunkLoadFailure } from '@/lib/chunk-recovery';

export default function PWAClient() {
  const [online, setOnline] = useState(true);

  useEffect(() => {
    const syncConnection = () => setOnline(navigator.onLine);
    syncConnection();
    window.addEventListener('online', syncConnection);
    window.addEventListener('offline', syncConnection);

    const recoverChunk = (value: unknown) => {
      if (!isChunkLoadFailure(value) || window.sessionStorage.getItem(CHUNK_RECOVERY_KEY)) return;
      window.sessionStorage.setItem(CHUNK_RECOVERY_KEY, '1');
      window.location.reload();
    };
    const scriptError = (event: ErrorEvent) => recoverChunk(event.error || event.message);
    const rejected = (event: PromiseRejectionEvent) => recoverChunk(event.reason);
    window.addEventListener('error', scriptError);
    window.addEventListener('unhandledrejection', rejected);
    const recoveryReset = window.setTimeout(() => window.sessionStorage.removeItem(CHUNK_RECOVERY_KEY), 10_000);

    if (process.env.NODE_ENV === 'production' && 'serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js', { scope: '/', updateViaCache: 'none' }).catch(() => {
        // The website remains fully functional if registration is unavailable.
      });
    }

    return () => {
      window.removeEventListener('online', syncConnection);
      window.removeEventListener('offline', syncConnection);
      window.removeEventListener('error', scriptError);
      window.removeEventListener('unhandledrejection', rejected);
      window.clearTimeout(recoveryReset);
    };
  }, []);

  if (online) return null;

  return (
    <aside className="fixed inset-x-0 top-0 z-[90] bg-accent-gray-900 px-4 pb-3 pt-[calc(0.75rem+env(safe-area-inset-top))] text-white shadow-xl" role="status">
      <div className="mx-auto flex max-w-3xl items-center justify-between gap-4">
        <div>
          <p className="font-black">Offline</p>
        </div>
        <button type="button" onClick={() => window.location.reload()} className="min-h-11 shrink-0 rounded-xl bg-white px-4 font-bold text-accent-gray-900">
          Retry
        </button>
      </div>
    </aside>
  );
}
