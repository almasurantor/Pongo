'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';

// Re-fetch server data after database events and after returning to a sleeping phone tab.
// The fallback also covers missed events and temporarily unavailable Realtime.
export function useDatabaseRefresh(channelName: string) {
  const router = useRouter();
  useEffect(() => {
    const supabase = createClient();
    let pending: ReturnType<typeof setTimeout> | undefined;
    const refresh = () => {
      if (document.visibilityState !== 'visible') return;
      clearTimeout(pending);
      pending = setTimeout(() => router.refresh(), 200);
    };
    const channel = supabase.channel(channelName)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'profiles' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'matches' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'rating_events' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'disputes' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'challenges' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'match_cancellation_requests' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'player_integrity' }, refresh)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'integrity_flags' }, refresh)
      .subscribe((status) => { if (status === 'SUBSCRIBED') refresh(); });
    const interval = setInterval(refresh, 60000);
    window.addEventListener('focus', refresh);
    document.addEventListener('visibilitychange', refresh);
    return () => {
      clearTimeout(pending);
      clearInterval(interval);
      window.removeEventListener('focus', refresh);
      document.removeEventListener('visibilitychange', refresh);
      void supabase.removeChannel(channel);
    };
  }, [channelName, router]);
}
