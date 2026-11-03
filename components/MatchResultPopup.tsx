'use client';

import { useEffect, useMemo, useRef, useState } from 'react';
import { usePathname, useRouter } from 'next/navigation';
import { createClient } from '@/lib/supabase/client';
import { RESULT_POPUP_FADE_MS, RESULT_POPUP_VISIBLE_MS, rememberResultPopupDismissal, wasResultPopupDismissed } from '@/lib/result-popup';

type ResultNotice = { matchId: string; won: boolean };
type ResultEventDetail = { matchId: string; winnerId: string };

export const MATCH_RESULT_EVENT = 'pongo:match-result';

export default function MatchResultPopup() {
  const pathname = usePathname();
  const router = useRouter();
  const supabase = useMemo(() => createClient(), []);
  const [notice, setNotice] = useState<ResultNotice | null>(null);
  const [exiting, setExiting] = useState(false);
  const shownMatch = useRef<string | null>(null);
  const cleanupRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    let active = true;
    let channel: ReturnType<typeof supabase.channel> | null = null;

    const show = (matchId: string, winnerId: string, userId: string) => {
      if (!matchId || shownMatch.current === matchId || wasResultPopupDismissed(matchId)) return;
      shownMatch.current = matchId;
      setNotice({ matchId, won: winnerId === userId });
      setExiting(false);
    };

    void supabase.auth.getSession().then(({ data }) => {
      const userId = data.session?.user.id;
      if (!active || !userId) return;

      const announced = (event: Event) => {
        const detail = (event as CustomEvent<ResultEventDetail>).detail;
        if (detail) show(detail.matchId, detail.winnerId, userId);
      };
      window.addEventListener(MATCH_RESULT_EVENT, announced);

      channel = supabase.channel(`global-match-results-${userId}`)
        .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'matches' }, (payload) => {
          const next = payload.new as { id?: string; status?: string; winner_id?: string; player_one_id?: string; player_two_id?: string };
          if (next.status !== 'confirmed' || !next.id || !next.winner_id) return;
          if (next.player_one_id !== userId && next.player_two_id !== userId) return;
          show(next.id, next.winner_id, userId);
        })
        .subscribe();

      const cleanup = () => window.removeEventListener(MATCH_RESULT_EVENT, announced);
      if (!active) cleanup();
      else cleanupRef.current = cleanup;
    });

    return () => {
      active = false;
      cleanupRef.current?.();
      cleanupRef.current = null;
      if (channel) void supabase.removeChannel(channel);
    };
  }, [supabase]);

  const close = () => {
    if (!notice) return;
    rememberResultPopupDismissal(notice.matchId);
    setExiting(true);
    window.setTimeout(() => {
      setNotice(null);
      setExiting(false);
      if (pathname.startsWith('/match/')) router.replace('/dashboard');
    }, RESULT_POPUP_FADE_MS);
  };

  useEffect(() => {
    if (!notice) return;
    const timer = window.setTimeout(close, RESULT_POPUP_VISIBLE_MS - RESULT_POPUP_FADE_MS);
    return () => window.clearTimeout(timer);
    // Restart only when a different match result is shown.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [notice]);

  if (!notice) return null;
  return (
    <div role="status" aria-live="polite" className={`result-popup-backdrop pointer-events-none fixed inset-0 z-[90] flex items-center justify-center p-4 ${exiting ? 'result-popup-exit' : ''}`}>
      <section className={`result-popup-card pointer-events-auto relative w-full max-w-xs rounded-3xl px-7 py-9 text-center text-white shadow-2xl ${notice.won ? 'bg-gradient-to-br from-green-600 to-emerald-800' : 'bg-gradient-to-br from-slate-700 to-slate-950'}`}>
        <button type="button" onClick={close} aria-label="Close result" className="absolute right-4 top-4 flex h-10 w-10 items-center justify-center rounded-full bg-white/15 text-2xl font-light text-white transition hover:bg-white/25 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-white">×</button>
        <p className="text-6xl" aria-hidden="true">{notice.won ? '🏆' : '🏓'}</p>
        <h2 className="mt-5 text-4xl font-black">{notice.won ? 'Winner' : 'Loser'}</h2>
      </section>
    </div>
  );
}
