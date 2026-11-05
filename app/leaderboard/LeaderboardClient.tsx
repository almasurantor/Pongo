'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import RankBadge from '@/components/RankBadge';
import { LeaderboardArchiveEntry, LeaderboardEntry, LeaderboardScope } from '@/lib/types';
import { splitLeaderboardRows } from '@/lib/leaderboards';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import BeaverAvatar from '@/components/BeaverAvatar';

const tabs: { scope: LeaderboardScope; label: string }[] = [
  { scope: 'weekly', label: 'Weekly' },
  { scope: 'monthly', label: 'Monthly' },
  { scope: 'all_time', label: 'All Time' },
];

const dateFormatter = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York',
  month: 'short',
  day: 'numeric',
  year: 'numeric',
});

function dateAtNoon(date: string) {
  return new Date(`${date}T12:00:00-04:00`);
}

function periodLabel(start: string, end: string, scope: LeaderboardScope) {
  if (scope === 'monthly') {
    return new Intl.DateTimeFormat('en-US', { timeZone: 'America/New_York', month: 'long', year: 'numeric' }).format(dateAtNoon(start));
  }
  return `${dateFormatter.format(dateAtNoon(start))} – ${dateFormatter.format(dateAtNoon(end))}`;
}

function StandingCard({ entry, scope, currentUserId, avatarConfig }: { entry: LeaderboardEntry; scope: LeaderboardScope; currentUserId: string; avatarConfig?: unknown }) {
  const mine = entry.player_id === currentUserId;
  const change = Number(entry.net_elo_change);
  return (
    <Link href={`/profile/${entry.player_id}`} className={`app-surface-card block p-3.5 transition active:scale-[.99] ${mine ? 'app-surface-card--active' : ''}`}>
      <div className="grid grid-cols-[3rem_2.75rem_1fr_auto] items-start gap-3">
        <span className={`text-xl font-black ${entry.placement <= 3 ? 'text-primary-purple' : 'text-accent-gray-500'}`}>#{entry.placement}</span>
        <BeaverAvatar config={avatarConfig} className="h-11 w-11 rounded-full" label={`${entry.display_name}'s avatar`} />
        <span className="min-w-0">
          <span className="block truncate font-black">{entry.display_name}{mine && <span className="ml-2 text-xs text-primary-purple">YOU</span>}</span>
          <span className="mt-1 block"><RankBadge elo={entry.current_elo} totalGames={entry.current_rank === 'Unranked' ? 0 : 1} compact /></span>
        </span>
        <span className="text-right">
          {scope === 'all_time' ? (
            <><span className="block text-2xl font-black text-primary-purple">{entry.current_elo}</span><span className="text-xs font-bold text-accent-gray-400">ELO</span></>
          ) : (
            <><span className={`block text-2xl font-black ${change >= 0 ? 'text-green-600' : 'text-red-600'}`}>{change >= 0 ? '+' : ''}{change}</span><span className="text-xs font-bold text-accent-gray-400">NET ELO</span></>
          )}
        </span>
      </div>
      <div className="mt-3 grid grid-cols-2 gap-2 border-t border-accent-gray-100 pt-2.5 text-center">
        <div><p className="font-black">{entry.wins}-{entry.losses}</p><p className="text-[11px] font-bold text-accent-gray-400">RECORD</p></div>
        <div><p className="font-black">{Number(entry.win_rate).toFixed(Number(entry.win_rate) % 1 ? 1 : 0)}%</p><p className="text-[11px] font-bold text-accent-gray-400">WIN RATE</p></div>
      </div>
    </Link>
  );
}

interface Props {
  entries: LeaderboardEntry[];
  archives: LeaderboardArchiveEntry[];
  scope: LeaderboardScope;
  selectedPeriod: string | null;
  currentUserId: string;
  loadError: string | null;
  avatarConfigs: Record<string, unknown>;
}

export default function LeaderboardClient({ entries, archives, scope, selectedPeriod, currentUserId, loadError, avatarConfigs }: Props) {
  useDatabaseRefresh('unified-leaderboards', ['rating_events', 'profiles']);
  const [visibleCount, setVisibleCount] = useState(50);
  const { topRows, currentUserRow } = splitLeaderboardRows(entries, currentUserId);
  const visibleTopRows = topRows.slice(0, visibleCount);
  const first = entries[0];
  const activePeriod = first?.period_start && first?.period_end
    ? periodLabel(first.period_start, first.period_end, scope)
    : selectedPeriod ? selectedPeriod : scope === 'all_time' ? 'Permanent ladder' : `Current ${scope === 'weekly' ? 'week' : 'month'}`;

  useEffect(() => setVisibleCount(50), [scope, selectedPeriod]);

  return (
    <main className="app-screen fixed-list-screen min-h-screen bg-gradient-to-br from-white via-accent-gray-50 to-primary-purple/5 px-4 py-6 sm:py-10">
      <div className="app-screen-shell mx-auto max-w-4xl">
        <div className="screen-fixed">
          <h1 className="text-3xl font-black sm:text-4xl">Leaderboard</h1>
          <p className="mt-1 text-accent-gray-600">{scope === 'all_time' ? 'Permanent ELO ranking' : activePeriod}</p>
        </div>

        <nav aria-label="Leaderboard period" className="screen-fixed grid grid-cols-3 rounded-2xl border border-accent-gray-200 p-1 sm:mt-5">
          {tabs.map((tab) => (
            <Link key={tab.scope} href={`/leaderboard?tab=${tab.scope}`} className={`rounded-xl px-3 py-3 text-center text-sm font-black transition ${scope === tab.scope ? 'bg-primary-purple/10 text-primary-purple dark:bg-primary-purple/20 dark:text-primary-purpleLight' : 'text-accent-gray-600 hover:bg-accent-gray-100 dark:hover:bg-accent-gray-800'}`}>
              {tab.label}
            </Link>
          ))}
        </nav>

        <div className="widget-scroll screen-flex pr-1 sm:mt-5" tabIndex={0} aria-label="Leaderboard standings">
          {selectedPeriod && (
          <div className="mb-4 flex items-center justify-between rounded-2xl border border-primary-purple/20 bg-primary-purple/5 p-4">
            <div><p className="text-xs font-black uppercase text-primary-purple">Historical archive</p><p className="font-bold">{activePeriod}</p></div>
            <Link href={`/leaderboard?tab=${scope}`} className="rounded-xl bg-white px-3 py-2 text-sm font-black text-primary-purple">Current</Link>
          </div>
          )}

          {loadError && <div className="mb-4 rounded-2xl border-2 border-red-200 bg-red-50 p-5 font-bold text-red-700">Could not load standings: {loadError}</div>}

        <section className="space-y-2.5">
          {visibleTopRows.map((entry) => <StandingCard key={entry.player_id} entry={entry} scope={scope} currentUserId={currentUserId} avatarConfig={avatarConfigs[entry.player_id]} />)}
          {!topRows.length && !loadError && <div className="app-surface-card p-8 text-center text-accent-gray-500">No ranked results.</div>}
          {visibleCount < topRows.length && (
            <button type="button" onClick={() => setVisibleCount((count) => count + 50)} className="app-surface-card min-h-12 w-full font-black text-primary-purple">
              Load more standings
            </button>
          )}
        </section>

        {currentUserRow && (
          <section className="mt-7">
            <div className="mb-3 flex items-center gap-3"><span className="h-px flex-1 bg-accent-gray-300" /><span className="text-xs font-black uppercase text-accent-gray-500">Your placement</span><span className="h-px flex-1 bg-accent-gray-300" /></div>
            <StandingCard entry={currentUserRow} scope={scope} currentUserId={currentUserId} avatarConfig={avatarConfigs[currentUserRow.player_id]} />
          </section>
        )}

        {scope !== 'all_time' && !selectedPeriod && (
          <section className="mt-7">
            <h2 className="text-2xl font-black">Previous winners</h2>
            <div className="mt-4 grid gap-3 sm:grid-cols-2">
              {archives.map((archive) => (
                <Link key={archive.period_start} href={`/leaderboard?tab=${scope}&period=${archive.period_start}`} className="app-surface-card p-4 transition active:scale-[.99]">
                  <p className="text-xs font-black uppercase text-accent-gray-400">{periodLabel(archive.period_start, archive.period_end, scope)}</p>
                  <div className="mt-3 flex items-center justify-between gap-3">
                    <div className="min-w-0"><p className="truncate font-black">{archive.winner_name}</p><div className="mt-1"><RankBadge elo={archive.winner_current_elo} totalGames={archive.winner_rank === 'Unranked' ? 0 : 1} compact /></div><p className="mt-1 text-sm text-accent-gray-500">{archive.total_players} players</p></div>
                    <div className="text-right"><p className={`text-xl font-black ${Number(archive.winner_net_elo_change) >= 0 ? 'text-green-600' : 'text-red-600'}`}>{Number(archive.winner_net_elo_change) >= 0 ? '+' : ''}{archive.winner_net_elo_change}</p><p className="text-[11px] font-bold text-accent-gray-400">NET ELO</p></div>
                  </div>
                </Link>
              ))}
              {!archives.length && <div className="app-surface-card p-6 text-center text-accent-gray-500 sm:col-span-2">Completed periods will appear here.</div>}
            </div>
          </section>
        )}
        </div>
      </div>
    </main>
  );
}
