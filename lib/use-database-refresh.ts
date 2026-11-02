'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

const DEFAULT_TABLES = ['profiles', 'matches'] as const;

// Refresh only for tables the current screen consumes. Bursts are coalesced,
// and returning to a sleeping phone tab performs one freshness check.
export function useDatabaseRefresh(channelName: string, tables: readonly string[] = DEFAULT_TABLES) {
  const router = useRouter();
  const tableKey = tables.join(',');

  useEffect(() => {
    const supabase = createClient();
    let pending: ReturnType<typeof setTimeout> | undefined;
    let lastRefresh = 0;
    const refresh = () => {
      if (document.visibilityState !== 'visible') return;
      clearTimeout(pending);
      pending = setTimeout(() => {
        lastRefresh = Date.now();
        router.refresh();
      }, 500);
    };

    let channel = supabase.channel(channelName);
    tableKey.split(',').filter(Boolean).forEach((table) => {
      channel = channel.on('postgres_changes', { event: '*', schema: 'public', table }, refresh);
    });
    channel.subscribe();

    const refreshAfterSleep = () => {
      if (document.visibilityState === 'visible' && Date.now() - lastRefresh > 5000) refresh();
    };
    window.addEventListener('focus', refreshAfterSleep);
    document.addEventListener('visibilitychange', refreshAfterSleep);
    return () => {
      clearTimeout(pending);
      window.removeEventListener('focus', refreshAfterSleep);
      document.removeEventListener('visibilitychange', refreshAfterSleep);
      void supabase.removeChannel(channel);
    };
  }, [channelName, router, tableKey]);
}
