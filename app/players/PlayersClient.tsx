'use client';

import { useEffect, useRef, useState } from 'react';
import Link from 'next/link';
import toast from 'react-hot-toast';
import { OpponentRankedUsage, Profile } from '@/lib/types';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import RankBadge from '@/components/RankBadge';
import BeaverAvatar from '@/components/BeaverAvatar';
import { DAILY_RANKED_PAIR_LIMIT, DAILY_RANKED_PAIR_LIMIT_MESSAGE } from '@/lib/ranked-limits';

export default function PlayersClient({ players, usage, currentUserId }: { players: Profile[]; usage: OpponentRankedUsage[]; currentUserId: string }) {
  useDatabaseRefresh('players-list', ['profiles']);
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [visibleCount, setVisibleCount] = useState(40);
  const [loadingId, setLoadingId] = useState<string | null>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const filtered = players.filter((player) => player.id !== currentUserId && player.display_name.toLowerCase().includes(debouncedQuery.toLowerCase()));
  const visiblePlayers = filtered.slice(0, visibleCount);
  const usageFor = (playerId: string) => usage.find((row) => row.opponent_id === playerId)
    || { opponent_id: playerId, games_used: 0, games_limit: DAILY_RANKED_PAIR_LIMIT, games_remaining: DAILY_RANKED_PAIR_LIMIT };
  const challenge = async (opponentId: string) => {
    setLoadingId(opponentId);
    try {
      const response = await fetch('/api/challenges', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ opponent_id: opponentId }) });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not send challenge');
      toast.success('Challenge sent!');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not send challenge');
    } finally {
      setLoadingId(null);
    }
  };

  useEffect(() => {
    const timer = window.setTimeout(() => setDebouncedQuery(query.trim()), 180);
    return () => window.clearTimeout(timer);
  }, [query]);

  useEffect(() => {
    const list = listRef.current;
    if (list) list.scrollTop = Number(window.sessionStorage.getItem('pongo-player-list-scroll') || 0);
    return () => {
      document.body.classList.remove('keyboard-open');
      if (list) window.sessionStorage.setItem('pongo-player-list-scroll', String(list.scrollTop));
    };
  }, []);

  const keyboardOpen = () => document.body.classList.add('keyboard-open');
  const keyboardClosed = () => window.setTimeout(() => document.body.classList.remove('keyboard-open'), 120);

  return (
    <main className="app-screen fixed-list-screen min-h-screen bg-accent-gray-50 px-4 py-7">
      <div className="app-screen-shell mx-auto max-w-3xl">
        <div className="screen-fixed">
          <h1 className="text-4xl font-black">Players</h1>
          <input
            type="search"
            value={query}
            onChange={(event) => { setQuery(event.target.value); setVisibleCount(40); }}
            onFocus={keyboardOpen}
            onBlur={keyboardClosed}
            placeholder="Search players"
            autoComplete="off"
            enterKeyHint="search"
            className="mt-5 h-14 w-full rounded-2xl border-2 border-accent-gray-200 bg-white px-5 text-base focus:border-primary-purple focus:outline-none"
          />
        </div>
        <div ref={listRef} onScroll={(event) => window.sessionStorage.setItem('pongo-player-list-scroll', String(event.currentTarget.scrollTop))} className="widget-scroll screen-flex space-y-3 pr-1 sm:mt-5" tabIndex={0} aria-label="Player list">
          {visiblePlayers.map((player) => {
            const rank = players.findIndex((candidate) => candidate.id === player.id) + 1;
            const today = usageFor(player.id);
            return (
              <article key={player.id} className="rounded-2xl border-2 border-accent-gray-200 bg-white p-4 shadow-sm">
                <div className="flex items-start justify-between gap-3">
                  <Link href={`/profile/${player.id}`} className="flex min-h-11 min-w-0 flex-1 items-center gap-3">
                    <BeaverAvatar config={player.avatar_config} className="h-14 w-14 shrink-0 rounded-full" label={`${player.display_name}'s avatar`} />
                    <span className="min-w-0"><span className="block truncate text-lg font-black">{player.display_name}</span>
                    <span className="block text-sm text-accent-gray-500">#{rank} overall · {player.current_elo} ELO · {player.total_wins}-{player.total_losses}</span>
                    <span className="mt-2 block"><RankBadge elo={player.current_elo} totalGames={player.total_wins + player.total_losses} compact /></span></span>
                  </Link>
                  <span className="rounded-full bg-primary-purple/10 px-3 py-1 text-sm font-black text-primary-purple">#{rank}</span>
                </div>
                <p className={`mt-3 rounded-xl px-3 py-2 text-sm font-bold ${today.games_remaining > 0 ? 'bg-blue-50 text-blue-700' : 'bg-amber-50 text-amber-700'}`}>{today.games_used}/{today.games_limit} today · {today.games_remaining} left</p>
                {today.games_remaining === 0 && <p className="mt-2 text-sm font-bold text-amber-700">{DAILY_RANKED_PAIR_LIMIT_MESSAGE}</p>}
                <button onClick={() => challenge(player.id)} disabled={loadingId === player.id || today.games_remaining === 0} className="mt-3 min-h-12 w-full rounded-xl gradient-purple font-bold text-white disabled:opacity-50">{loadingId === player.id ? 'Sending…' : today.games_remaining === 0 ? 'Opponent limit reached today' : 'Challenge'}</button>
              </article>
            );
          })}
          {filtered.length === 0 && <div className="rounded-2xl bg-white p-10 text-center text-accent-gray-500">No players found.</div>}
          {visibleCount < filtered.length && (
            <button type="button" onClick={() => setVisibleCount((count) => count + 40)} className="min-h-12 w-full rounded-2xl border-2 border-primary-purple/20 bg-white font-black text-primary-purple">
              Load more players
            </button>
          )}
        </div>
      </div>
    </main>
  );
}
