'use client';

import { useEffect, useState } from 'react';

export default function PWAClient() {
  const [online, setOnline] = useState(true);

  useEffect(() => {
    const syncConnection = () => setOnline(navigator.onLine);
    syncConnection();
    window.addEventListener('online', syncConnection);
    window.addEventListener('offline', syncConnection);

    if (process.env.NODE_ENV === 'production' && 'serviceWorker' in navigator) {
      navigator.serviceWorker.register('/sw.js', { scope: '/' }).catch(() => {
        // The website remains fully functional if registration is unavailable.
      });
    }

    return () => {
      window.removeEventListener('online', syncConnection);
      window.removeEventListener('offline', syncConnection);
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
