'use client';

import Link from 'next/link';
import { useEffect, useState } from 'react';
import { format } from 'date-fns';
import toast from 'react-hot-toast';
import { createClient } from '@/lib/supabase/client';
import { Match, OpponentRankedUsage, Profile } from '@/lib/types';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import RankBadge, { RankProgress } from '@/components/RankBadge';
import ThemeSettings from '@/components/ThemeSettings';
import BeaverAvatar from '@/components/BeaverAvatar';
import AvatarEditor from '@/components/AvatarEditor';
import ProfileSettingsPanel from '@/components/ProfileSettingsPanel';
import { clearCachedProfileShell, writeCachedProfileShell } from '@/lib/profile-cache';
import { DAILY_RANKED_PAIR_LIMIT, DAILY_RANKED_PAIR_LIMIT_MESSAGE } from '@/lib/ranked-limits';

interface Props {
  profile: Profile;
  matches: Match[];
  opponentUsage: OpponentRankedUsage | null;
  rank: number;
  currentUserId: string;
}

export default function ProfileClient({ profile, matches, opponentUsage, rank, currentUserId }: Props) {
  useDatabaseRefresh(`profile-${profile.id}`, ['profiles', 'matches', 'rating_events']);
  const supabase = createClient();
  const [loading, setLoading] = useState(false);
  const [currentProfile, setCurrentProfile] = useState(profile);
  const [avatarEditorOpen, setAvatarEditorOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const mine = profile.id === currentUserId;
  const totalGames = profile.total_wins + profile.total_losses;
  const winRate = totalGames ? Math.round(profile.total_wins / totalGames * 100) : 0;

  useEffect(() => {
    if (mine) writeCachedProfileShell(window.localStorage, currentProfile);
  }, [currentProfile, mine]);

  const challenge = async () => {
    setLoading(true);
    try {
      const response = await fetch('/api/challenges', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ opponent_id: profile.id }),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error);
      toast.success('Challenge sent!');
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not send challenge');
    } finally {
      setLoading(false);
    }
  };

  const logout = async () => {
    await supabase.auth.signOut();
    clearCachedProfileShell(window.localStorage);
    window.location.replace('/');
  };

  return (
    <main className="app-screen min-h-screen bg-accent-gray-50 px-4 py-7">
      <div className="app-screen-shell mx-auto w-full max-w-3xl space-y-0 sm:space-y-6">
        <section className="screen-fixed rounded-3xl gradient-purple p-4 text-white shadow-xl sm:p-6">
          <div className="grid grid-cols-[5.75rem_minmax(0,1fr)] items-center gap-3 sm:grid-cols-[7.5rem_minmax(0,1fr)] sm:gap-5">
            <div className="flex min-w-0 flex-col items-center">
              <BeaverAvatar config={currentProfile.avatar_config} className="aspect-square w-full drop-shadow-lg" label={`${currentProfile.display_name}'s Pongo avatar`} />
              {mine && <button type="button" onClick={() => setAvatarEditorOpen(true)} className="mt-1 min-h-8 rounded-full bg-white/20 px-3 text-xs font-black text-white backdrop-blur transition hover:bg-white/30 active:scale-95">Edit</button>}
            </div>
            <div className="min-w-0">
              <h1 className="break-words pr-1 text-[clamp(1.4rem,7vw,2.1rem)] font-black leading-[1.02]">{currentProfile.display_name}</h1>
              <p className="text-sm text-white/70">Member since {format(new Date(profile.created_at), 'MMM yyyy')}</p>
              <RankBadge elo={profile.current_elo} totalGames={totalGames} compact className="mt-2" />
            </div>
          </div>
          <div className="mt-4 grid grid-cols-3 gap-2 text-center">
            <div><p className="text-2xl font-black sm:text-3xl">#{rank}</p><p className="text-xs text-white/70">Overall</p></div>
            <div><p className="text-2xl font-black sm:text-3xl">{profile.current_elo}</p><p className="text-xs text-white/70">ELO</p></div>
            <div><p className="text-2xl font-black sm:text-3xl">{profile.highest_elo}</p><p className="text-xs text-white/70">Peak</p></div>
          </div>
          <div className="mt-4 border-t border-white/20 pt-3"><RankProgress elo={profile.current_elo} totalGames={totalGames} inverse /></div>
        </section>

        <div className="flex min-w-0 flex-col gap-4 sm:gap-6">
        {mine && avatarEditorOpen && <AvatarEditor initialConfig={currentProfile.avatar_config} onSaved={(avatar_config) => setCurrentProfile((current) => ({ ...current, avatar_config }))} onClose={() => setAvatarEditorOpen(false)} />}
        {mine && settingsOpen && <ProfileSettingsPanel profile={currentProfile} onSaved={setCurrentProfile} onClose={() => setSettingsOpen(false)} onLogout={() => void logout()} />}
        {!mine && (
          <section className="rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-sm sm:p-5">
            <p className={`mb-3 rounded-xl px-3 py-2 text-center text-sm font-bold ${(opponentUsage?.games_remaining ?? DAILY_RANKED_PAIR_LIMIT) > 0 ? 'bg-blue-50 text-blue-700' : 'bg-amber-50 text-amber-700'}`}>
              {(opponentUsage?.games_remaining ?? DAILY_RANKED_PAIR_LIMIT) > 0
                ? `${opponentUsage?.games_remaining ?? DAILY_RANKED_PAIR_LIMIT} ranked games available today`
                : DAILY_RANKED_PAIR_LIMIT_MESSAGE}
            </p>
            <button onClick={challenge} disabled={loading || (opponentUsage?.games_remaining ?? DAILY_RANKED_PAIR_LIMIT) === 0} className="min-h-14 w-full rounded-2xl gradient-purple font-black text-white disabled:opacity-50">
              {loading ? 'Sending…' : (opponentUsage?.games_remaining ?? DAILY_RANKED_PAIR_LIMIT) === 0 ? 'Daily limit reached' : 'Challenge'}
            </button>
          </section>
        )}

        <section className="rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="mb-3 text-xl font-black">Performance</h2>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          {[
            { label: 'Record', value: `${profile.total_wins}-${profile.total_losses}` },
            { label: 'Win rate', value: `${winRate}%` },
            { label: 'Streak', value: profile.current_streak > 0 ? `W${profile.current_streak}` : profile.current_streak < 0 ? `L${Math.abs(profile.current_streak)}` : '—' },
            { label: 'Best streak', value: `W${profile.longest_streak}` },
          ].map((stat) => (
            <div key={stat.label} className="rounded-2xl bg-white p-4 text-center shadow-sm">
              <p className="text-2xl font-black">{stat.value}</p>
              <p className="text-xs font-bold text-accent-gray-500">{stat.label}</p>
            </div>
          ))}
          </div>
        </section>

        <section className="min-w-0 rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-sm sm:p-5">
          <h2 className="mb-3 text-xl font-black">Recent games</h2>
          <div className="max-h-[20rem] space-y-2 overflow-y-auto overscroll-contain pr-1 [scrollbar-width:thin] sm:max-h-[24rem]" tabIndex={0} aria-label="Recent games">
            {matches.map((match) => {
              const isPlayerOne = match.player_one_id === profile.id;
              const opponent = isPlayerOne ? match.player_two : match.player_one;
              const playerOneScore = match.player_one_score ?? 0;
              const playerTwoScore = match.player_two_score ?? 0;
              const won = match.winner_id === profile.id;
              const myScore = isPlayerOne ? playerOneScore : playerTwoScore;
              const theirScore = isPlayerOne ? playerTwoScore : playerOneScore;
              const change = (isPlayerOne ? match.player_one_elo_change : match.player_two_elo_change) ?? 0;
              return (
                <Link href={`/match/${match.id}`} key={match.id} className="grid grid-cols-[2.8rem_2.5rem_1fr_auto] items-center gap-3 rounded-2xl bg-white p-3 shadow-sm">
                  <span className={`text-sm font-black ${won ? 'text-green-600' : 'text-red-600'}`}>{won ? 'WIN' : 'LOSS'}</span>
                  <BeaverAvatar config={opponent?.avatar_config} className="h-10 w-10 rounded-full" label={`${opponent?.display_name ?? 'Opponent'} avatar`} />
                  <span className="min-w-0">
                    <span className="block truncate font-black">vs {opponent?.display_name}</span>
                    <span className="text-xs text-accent-gray-500">{myScore}–{theirScore} · {match.confirmed_at ? format(new Date(match.confirmed_at), 'MMM d, yyyy') : ''}</span>
                  </span>
                  <span className={`font-black ${change >= 0 ? 'text-green-600' : 'text-red-600'}`}>{change >= 0 ? '+' : ''}{change}</span>
                </Link>
              );
            })}
            {!matches.length && <div className="rounded-2xl bg-white p-8 text-center text-accent-gray-500">No ranked games yet.</div>}
          </div>
        </section>

        {mine && <section className="space-y-3 rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-sm sm:p-5" aria-label="Profile appearance and links">
          <ThemeSettings embedded />
          <Link href="/landing" className="flex min-h-12 w-full items-center justify-center rounded-2xl bg-[#EFF6FF] px-4 font-black text-[#1D4ED8] transition active:scale-[.99] dark:bg-[#17243C] dark:text-[#93C5FD]">View Landing Page</Link>
        </section>}

        {mine && <button type="button" onClick={() => setSettingsOpen(true)} className="flex min-h-14 w-full items-center justify-between rounded-2xl border-2 border-accent-gray-200 bg-white px-4 text-left font-black shadow-sm transition active:scale-[.99] dark:border-[#334155] dark:bg-[#111827]" aria-label="Open settings"><span className="flex items-center gap-3"><svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5 text-[#2563EB]" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .34 1.88l.06.06-2.83 2.83-.06-.06A1.7 1.7 0 0 0 15 19.4a1.7 1.7 0 0 0-1 .6 1.7 1.7 0 0 0-.4 1.1V21h-4v-.09A1.7 1.7 0 0 0 8.6 19.4a1.7 1.7 0 0 0-1.88.34l-.06.06-2.83-2.83.06-.06A1.7 1.7 0 0 0 4.6 15a1.7 1.7 0 0 0-.6-1 1.7 1.7 0 0 0-1.1-.4H3v-4h.09A1.7 1.7 0 0 0 4.6 8.6a1.7 1.7 0 0 0-.34-1.88l-.06-.06 2.83-2.83.06.06A1.7 1.7 0 0 0 9 4.6a1.7 1.7 0 0 0 1-.6 1.7 1.7 0 0 0 .4-1.1V3h4v.09A1.7 1.7 0 0 0 15.4 4.6a1.7 1.7 0 0 0 1.88-.34l.06-.06 2.83 2.83-.06.06A1.7 1.7 0 0 0 19.4 9c.13.38.34.72.6 1 .3.28.68.42 1.1.4h.09v4h-.09c-.42-.02-.8.12-1.1.4-.26.28-.47.62-.6 1Z"/></svg>Settings</span><span aria-hidden="true" className="text-xl text-accent-gray-400">›</span></button>}

        </div>
      </div>
    </main>
  );
}
