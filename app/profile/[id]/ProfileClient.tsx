'use client';

import Link from 'next/link';
import { useState } from 'react';
import { format } from 'date-fns';
import toast from 'react-hot-toast';
import { createClient } from '@/lib/supabase/client';
import { Match, OpponentRankedUsage, Profile } from '@/lib/types';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import InstallAppHint from '@/components/InstallAppHint';
import RankBadge, { RankProgress } from '@/components/RankBadge';
import ThemeSettings from '@/components/ThemeSettings';
import ProfileSettings from '@/components/ProfileSettings';

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
  const mine = profile.id === currentUserId;
  const totalGames = profile.total_wins + profile.total_losses;
  const winRate = totalGames ? Math.round(profile.total_wins / totalGames * 100) : 0;

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
    window.location.replace('/');
  };

  return (
    <main className="app-screen min-h-screen bg-accent-gray-50 px-4 py-7">
      <div className="app-screen-shell mx-auto w-full max-w-3xl space-y-0 sm:space-y-6">
        <section className="screen-fixed rounded-3xl gradient-purple p-4 text-white shadow-xl sm:p-6">
          <div className="flex items-center gap-4">
            <div className="flex h-16 w-16 shrink-0 items-center justify-center rounded-full bg-white/20 text-2xl font-black">
              {currentProfile.display_name[0].toUpperCase()}
            </div>
            <div className="min-w-0">
              <h1 className="truncate text-3xl font-black">{currentProfile.display_name}</h1>
              <p className="text-sm text-white/70">Member since {format(new Date(profile.created_at), 'MMM yyyy')}</p>
              <RankBadge elo={profile.current_elo} totalGames={totalGames} compact className="mt-2" />
            </div>
          </div>
          <div className="mt-5 grid grid-cols-3 gap-2 text-center">
            <div><p className="text-3xl font-black">#{rank}</p><p className="text-xs text-white/70">Overall</p></div>
            <div><p className="text-3xl font-black">{profile.current_elo}</p><p className="text-xs text-white/70">ELO</p></div>
            <div><p className="text-3xl font-black">{profile.highest_elo}</p><p className="text-xs text-white/70">Peak</p></div>
          </div>
          <div className="mt-4 border-t border-white/20 pt-3"><RankProgress elo={profile.current_elo} totalGames={totalGames} inverse /></div>
        </section>

        <div className="flex min-w-0 flex-col gap-4 sm:gap-6">
        {!mine && (
          <section className="rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-sm sm:p-5">
            <p className={`mb-3 rounded-xl px-3 py-2 text-center text-sm font-bold ${(opponentUsage?.games_remaining ?? 3) > 0 ? 'bg-blue-50 text-blue-700' : 'bg-amber-50 text-amber-700'}`}>
              {opponentUsage?.games_remaining ?? 20} ranked games available today
            </p>
            <button onClick={challenge} disabled={loading || (opponentUsage?.games_remaining ?? 20) === 0} className="min-h-14 w-full rounded-2xl gradient-purple font-black text-white disabled:opacity-50">
              {loading ? 'Sending…' : (opponentUsage?.games_remaining ?? 20) === 0 ? 'Daily limit reached' : 'Challenge'}
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
                <Link href={`/match/${match.id}`} key={match.id} className="grid grid-cols-[2.8rem_1fr_auto] items-center gap-3 rounded-2xl bg-white p-3 shadow-sm">
                  <span className={`text-sm font-black ${won ? 'text-green-600' : 'text-red-600'}`}>{won ? 'WIN' : 'LOSS'}</span>
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

        {mine && (
          <section className="rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-sm sm:p-5" aria-label="Profile settings">
            <div className="space-y-4">
            <div>
              <h2 className="text-xl font-black">Settings</h2>
              <p className="mt-1 text-sm text-accent-gray-500">Your public name and queue reminders.</p>
            </div>
            <ProfileSettings profile={currentProfile} onSaved={setCurrentProfile} />
            <div className="border-t border-accent-gray-200 pt-4 dark:border-[#334155]">
              <ThemeSettings embedded />
            </div>
            <InstallAppHint />
            <button onClick={logout} className="min-h-12 w-full rounded-2xl border-2 border-red-200 font-bold text-red-600">Log out</button>
            </div>
          </section>
        )}
        </div>
      </div>
    </main>
  );
}
