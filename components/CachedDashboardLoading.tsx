'use client';

import { useEffect, useState } from 'react';
import AppScreenSkeleton from '@/components/AppScreenSkeleton';
import BeaverAvatar from '@/components/BeaverAvatar';
import RankBadge from '@/components/RankBadge';
import { CachedProfileShell, readCachedProfileShell } from '@/lib/profile-cache';

export default function CachedDashboardLoading() {
  const [cached, setCached] = useState<CachedProfileShell | null>(null);

  useEffect(() => setCached(readCachedProfileShell(window.localStorage)), []);

  if (!cached) return <AppScreenSkeleton titleWidth="w-48" rows={3} />;

  return (
    <main className="app-screen min-h-screen bg-accent-gray-50 px-4 py-6 sm:py-10" aria-label="Refreshing dashboard">
      <div className="mx-auto max-w-5xl">
        <p className="text-sm font-black uppercase tracking-wide text-primary-purple">Welcome back</p>
        <h1 className="mt-1 truncate text-3xl font-black">{cached.displayName}</h1>
        <section className="mt-5 flex items-center gap-4 rounded-3xl bg-primary-purple p-5 text-white shadow-xl">
          <BeaverAvatar config={cached.avatarConfig} className="h-20 w-20 shrink-0 drop-shadow-lg" label={`${cached.displayName}'s cached avatar`} />
          <div><RankBadge elo={cached.currentElo} totalGames={cached.totalGames} compact /><p className="mt-2 text-sm font-bold text-white/80">Refreshing your latest Pongo activity…</p></div>
        </section>
        <div className="mt-5 space-y-3 animate-pulse"><div className="h-28 rounded-3xl bg-white" /><div className="h-28 rounded-3xl bg-white" /></div>
      </div>
    </main>
  );
}
