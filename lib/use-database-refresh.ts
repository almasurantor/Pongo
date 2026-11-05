'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { APP_RESUME_EVENT } from '@/lib/app-resume';

const DEFAULT_TABLES = ['profiles', 'matches'] as const;

// Refresh only for tables the current screen consumes. Bursts are coalesced,
// while reconnects and returning to a sleeping phone tab always perform an
// authoritative resync so no database event can be permanently missed.
export function useDatabaseRefresh(channelName: string, tables: readonly string[] = DEFAULT_TABLES) {
  const router = useRouter();
  const tableKey = tables.join(',');

  useEffect(() => {
    const supabase = createClient();
    let pending: ReturnType<typeof setTimeout> | undefined;
    let missedWhileHidden = false;
    const refresh = (immediate = false) => {
      if (document.visibilityState !== 'visible') {
        missedWhileHidden = true;
        return;
      }
      clearTimeout(pending);
      pending = setTimeout(() => {
        missedWhileHidden = false;
        router.refresh();
      }, immediate ? 0 : 100);
    };

    let channel = supabase.channel(channelName);
    tableKey.split(',').filter(Boolean).forEach((table) => {
      channel = channel.on('postgres_changes', { event: '*', schema: 'public', table }, () => refresh());
    });
    channel.subscribe((status) => {
      if (status === 'SUBSCRIBED') refresh(true);
      else if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT' || status === 'CLOSED') missedWhileHidden = true;
    });

    const refreshAfterInterruption = () => {
      if (document.visibilityState === 'visible') refresh(missedWhileHidden);
    };
    window.addEventListener('focus', refreshAfterInterruption);
    window.addEventListener('online', refreshAfterInterruption);
    window.addEventListener(APP_RESUME_EVENT, refreshAfterInterruption);
    document.addEventListener('visibilitychange', refreshAfterInterruption);
    return () => {
      clearTimeout(pending);
      window.removeEventListener('focus', refreshAfterInterruption);
      window.removeEventListener('online', refreshAfterInterruption);
      window.removeEventListener(APP_RESUME_EVENT, refreshAfterInterruption);
      document.removeEventListener('visibilitychange', refreshAfterInterruption);
      void supabase.removeChannel(channel);
    };
  }, [channelName, router, tableKey]);
}
