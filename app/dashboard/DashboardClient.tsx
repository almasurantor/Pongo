'use client';

import Link from 'next/link';
import { useState } from 'react';
import toast from 'react-hot-toast';
import { Challenge, Dispute, Match, MatchCancellationRequest, Profile, RankedUsage, RatingEvent } from '@/lib/types';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import RankBadge, { RankProgress } from '@/components/RankBadge';
import { rankTransition } from '@/lib/ranks';
import DeadlineCountdown from '@/components/DeadlineCountdown';

interface Props {
  user: Profile;
  rank: number;
  pendingChallenges: Challenge[];
  activeMatches: Match[];
  cancellationRequests: MatchCancellationRequest[];
  rankedUsage: RankedUsage;
  ratingEvents: RatingEvent[];
  disputes: Dispute[];
  isAdmin: boolean;
}

const deadlineFormatter = new Intl.DateTimeFormat('en-US', {
  timeZone: 'America/New_York',
  month: 'short',
  day: 'numeric',
  hour: 'numeric',
  minute: '2-digit',
  timeZoneName: 'short',
});

export default function DashboardClient({
  user,
  rank,
  pendingChallenges,
  activeMatches,
  cancellationRequests,
  rankedUsage,
  ratingEvents,
  disputes,
  isAdmin,
}: Props) {
  useDatabaseRefresh('home-actions');
  const [loading, setLoading] = useState<string | null>(null);

  const post = async (url: string, body: object, key: string) => {
    setLoading(key);
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      const result = await response.json();
      if (!response.ok) throw new Error(result.error || 'Could not update match');
      return result;
    } finally {
      setLoading(null);
    }
  };

  const respondChallenge = async (id: string, action: 'accept' | 'decline') => {
    try {
      const result = await post(`/api/challenges/${id}/respond`, { action }, `${id}-${action}`);
      toast.success(action === 'accept' ? 'Challenge accepted!' : 'Challenge declined');
      if (result.match_id) window.location.href = `/match/${result.match_id}`;
      else window.location.reload();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not update challenge');
      window.location.reload();
    }
  };

  const cancelChallenge = async (id: string) => {
    try {
      await post(`/api/challenges/${id}/cancel`, {}, `${id}-cancel`);
      toast.success('Challenge canceled');
      window.location.reload();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not cancel challenge');
    }
  };

  const respondCancellation = async (matchId: string, action: 'approve' | 'decline') => {
    try {
      await post(`/api/matches/${matchId}/cancellation`, { action }, `${matchId}-${action}`);
      toast.success(action === 'approve' ? 'Match canceled' : 'Cancellation declined');
      window.location.reload();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not respond to cancellation');
      window.location.reload();
    }
  };
  const respondDispute = async (id: string, action: 'approve' | 'decline') => {
    try {
      const result = await post(`/api/disputes/${id}/respond`, { action }, `${id}-${action}`);
      toast.success(result.status === 'admin_review' ? 'Dispute escalated; ratings are unchanged' : 'Correction approved and ratings updated');
      window.location.reload();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not respond to dispute');
      window.location.reload();
    }
  };

  const opponentFor = (match: Match) => match.player_one_id === user.id ? match.player_two : match.player_one;
  const requestFor = (matchId: string) => cancellationRequests.find((request) => request.match_id === matchId);
  const incoming = pendingChallenges.filter((challenge) => challenge.opponent_id === user.id && new Date(challenge.expires_at).getTime() > Date.now());
  const outgoing = pendingChallenges.filter((challenge) => challenge.challenger_id === user.id && new Date(challenge.expires_at).getTime() > Date.now());
  const cancellationNeedsResponse = cancellationRequests.filter((request) => request.requested_by !== user.id);
  const disputesNeedResponse = disputes.filter((dispute) => dispute.status === 'pending' && dispute.opened_by !== user.id);
  const winRate = user.total_wins + user.total_losses
    ? Math.round(user.total_wins / (user.total_wins + user.total_losses) * 100)
    : 0;
  const totalGames = user.total_wins + user.total_losses;

  return (
    <main className="min-h-screen bg-gradient-to-br from-white via-accent-gray-50 to-primary-purple/5 px-4 py-6 sm:py-10">
      <div className="mx-auto max-w-5xl space-y-7">
        <header className="flex items-end justify-between">
          <div><p className="text-sm font-bold text-accent-gray-500">Welcome back</p><h1 className="text-3xl font-black sm:text-4xl">{user.display_name}</h1></div>
          {isAdmin && <Link href="/admin" className="rounded-full bg-accent-black px-4 py-2 text-sm font-bold text-white">Admin</Link>}
        </header>

        <section className="rounded-3xl gradient-purple p-6 text-white shadow-xl">
          <div className="flex items-end justify-between gap-3"><div><p className="text-sm font-bold text-white/75">Overall placement</p><p className="text-5xl font-black">#{rank}</p></div><div className="text-right"><RankBadge elo={user.current_elo} totalGames={totalGames} compact /><p className="mt-2 text-4xl font-black">{user.current_elo}</p><p className="text-sm font-bold text-white/75">ELO rating</p></div></div>
          <div className="mt-6 grid grid-cols-2 gap-3 border-t border-white/20 pt-5 text-center sm:grid-cols-5">
            <div><p className="text-xl font-black">{user.total_wins}-{user.total_losses}</p><p className="text-xs text-white/70">Record</p></div>
            <div><p className="text-xl font-black">{winRate}%</p><p className="text-xs text-white/70">Win rate</p></div>
            <div><p className="text-xl font-black">{rankedUsage.daily_used}/{rankedUsage.daily_limit}</p><p className="text-xs text-white/70">Games today</p></div>
            <div><p className="text-xl font-black">{rankedUsage.active_used}/{rankedUsage.active_limit}</p><p className="text-xs text-white/70">Active</p></div>
            <div><p className="text-xl font-black">{user.current_streak > 0 ? `W${user.current_streak}` : user.current_streak < 0 ? `L${Math.abs(user.current_streak)}` : '—'}</p><p className="text-xs text-white/70">Streak</p></div>
          </div>
          <div className="mt-5 border-t border-white/20 pt-4"><RankProgress elo={user.current_elo} totalGames={totalGames} inverse /></div>
        </section>

        {(incoming.length > 0 || cancellationNeedsResponse.length > 0 || disputesNeedResponse.length > 0) && (
          <section>
            <h2 className="mb-3 text-xl font-black">Needs your attention</h2>
            <div className="space-y-3">
              {disputesNeedResponse.map((dispute) => {
                const disputedMatch = dispute.match;
                const requester = disputedMatch?.player_one_id === dispute.opened_by ? disputedMatch.player_one : disputedMatch?.player_two;
                return <article key={dispute.id} className="rounded-2xl border-2 border-amber-300 bg-amber-50 p-5"><p className="text-sm font-black uppercase text-amber-700">Result dispute</p><p className="mt-2 text-lg font-black">{requester?.display_name} requested a {dispute.requested_resolution}</p><p className="mt-1 text-sm text-amber-800">Your current result and ratings stay in place unless you approve.</p>{dispute.requested_resolution==='correction'&&<p className="mt-2 rounded-xl bg-white p-2 font-black">Proposed score: {dispute.proposed_player_one_score}–{dispute.proposed_player_two_score}</p>}<div className="mt-4 grid grid-cols-2 gap-3"><button disabled={loading!==null} onClick={()=>respondDispute(dispute.id,'decline')} className="min-h-12 rounded-xl border-2 border-amber-400 bg-white font-bold text-amber-800 disabled:opacity-50">Decline & escalate</button><button disabled={loading!==null} onClick={()=>respondDispute(dispute.id,'approve')} className="min-h-12 rounded-xl bg-green-600 font-bold text-white disabled:opacity-50">Approve</button></div>{disputedMatch&&<Link href={`/match/${disputedMatch.id}`} className="mt-3 block text-center text-sm font-black text-amber-800">Review match</Link>}</article>;
              })}
              {cancellationNeedsResponse.map((request) => {
                const match = activeMatches.find((candidate) => candidate.id === request.match_id);
                if (!match) return null;
                return (
                  <article key={request.id} className="rounded-2xl border-2 border-amber-300 bg-amber-50 p-5">
                    <p className="text-sm font-black uppercase text-amber-700">Cancellation requested</p>
                    <p className="mt-2 text-lg font-black">{opponentFor(match)?.display_name} wants to cancel this match</p>
                    <div className="mt-4 grid grid-cols-2 gap-3">
                      <button disabled={loading !== null} onClick={() => respondCancellation(match.id, 'decline')} className="min-h-12 rounded-xl border-2 border-amber-400 bg-white font-bold text-amber-800 disabled:opacity-50">Decline</button>
                      <button disabled={loading !== null} onClick={() => respondCancellation(match.id, 'approve')} className="min-h-12 rounded-xl bg-amber-600 font-bold text-white disabled:opacity-50">Approve</button>
                    </div>
                  </article>
                );
              })}
              {incoming.map((challenge) => (
                <article key={challenge.id} className="rounded-2xl border-2 border-primary-purple/25 bg-white p-5 shadow-sm">
                  <p className="text-sm font-black uppercase text-primary-purple">New challenge</p>
                  <p className="mt-2 text-lg font-black">{challenge.challenger?.display_name} wants to play</p>
                  {challenge.challenger && <div className="mt-2"><RankBadge elo={challenge.challenger.current_elo} totalGames={challenge.challenger.total_wins + challenge.challenger.total_losses} compact /></div>}
                  <p className="mt-1 text-sm text-accent-gray-500">Expires {deadlineFormatter.format(new Date(challenge.expires_at))}</p>
                  <DeadlineCountdown deadline={challenge.expires_at} className="mt-1 block text-sm font-bold text-accent-gray-500" />
                  <div className="mt-4 grid grid-cols-2 gap-3">
                    <button disabled={loading !== null} onClick={() => respondChallenge(challenge.id, 'decline')} className="min-h-12 rounded-xl border-2 border-accent-gray-300 font-bold disabled:opacity-50">Decline</button>
                    <button disabled={loading !== null} onClick={() => respondChallenge(challenge.id, 'accept')} className="min-h-12 rounded-xl gradient-purple font-bold text-white disabled:opacity-50">Accept</button>
                  </div>
                </article>
              ))}
            </div>
          </section>
        )}

        {incoming.length === 0 && cancellationNeedsResponse.length === 0 && disputesNeedResponse.length === 0 && (
          <section className="rounded-2xl border-2 border-accent-gray-200 bg-white p-7 text-center">
            <p className="text-3xl">✓</p><h2 className="mt-2 text-xl font-black">You’re all caught up</h2><p className="mt-1 text-accent-gray-500">No challenges, cancellation requests, or disputes need your attention.</p>
          </section>
        )}

        <section>
          <div className="mb-3 flex items-center justify-between"><h2 className="text-xl font-black">Active ranked matches</h2><span className="text-sm font-bold text-accent-gray-500">{rankedUsage.active_used}/{rankedUsage.active_limit}</span></div>
          {activeMatches.length ? (
            <div className="grid gap-3 sm:grid-cols-2">
              {activeMatches.map((match) => {
                const request = requestFor(match.id);
                return (
                  <Link key={match.id} href={`/match/${match.id}`} className="rounded-2xl border-2 border-primary-purple/15 bg-white p-5 shadow-sm">
                    <p className="text-sm font-black uppercase text-primary-purple">vs {opponentFor(match)?.display_name}</p>
                    {opponentFor(match) && <div className="mt-2"><RankBadge elo={opponentFor(match)!.current_elo} totalGames={opponentFor(match)!.total_wins + opponentFor(match)!.total_losses} compact /></div>}
                    <p className="mt-2 font-bold">{match.verification_mode === 'dual' ? 'Independent reports required' : 'Submit the first valid final score'}</p>
                    {match.expires_at && <div className="mt-1 text-sm text-accent-gray-500"><p>Expires {deadlineFormatter.format(new Date(match.expires_at))}</p><DeadlineCountdown deadline={match.expires_at} className="font-bold" /></div>}
                    {request && <p className="mt-3 rounded-xl bg-amber-50 p-2 text-sm font-bold text-amber-700">{request.requested_by === user.id ? 'Cancellation awaiting opponent' : 'Cancellation needs your response'}</p>}
                  </Link>
                );
              })}
            </div>
          ) : <div className="rounded-2xl bg-white p-6 text-center text-accent-gray-500">Accept a challenge to start a ranked match.</div>}
        </section>

        {outgoing.length > 0 && (
          <section>
            <h2 className="mb-3 text-xl font-black">Challenges sent</h2>
            <div className="space-y-2">
              {outgoing.map((challenge) => (
                <div key={challenge.id} className="flex items-center justify-between rounded-2xl bg-white p-4 shadow-sm">
                  <div><p className="font-bold">{challenge.opponent?.display_name}</p>{challenge.opponent&&<div className="mt-1"><RankBadge elo={challenge.opponent.current_elo} totalGames={challenge.opponent.total_wins+challenge.opponent.total_losses} compact /></div>}<p className="mt-1 text-sm text-accent-gray-500">Expires {deadlineFormatter.format(new Date(challenge.expires_at))}</p><DeadlineCountdown deadline={challenge.expires_at} className="text-sm font-bold text-accent-gray-500" /></div>
                  <button disabled={loading !== null} onClick={() => cancelChallenge(challenge.id)} className="min-h-10 rounded-xl px-3 font-bold text-red-600 disabled:opacity-50">Cancel</button>
                </div>
              ))}
            </div>
          </section>
        )}

        <Link href="/players" className="block rounded-2xl gradient-purple p-5 text-white shadow-lg"><span className="text-3xl">🎯</span><p className="mt-3 text-lg font-black">Challenge a player</p><p className="mt-1 text-sm text-white/80">Ranked matches begin only after they accept.</p></Link>

        <section>
          <div className="mb-3 flex items-center justify-between"><h2 className="text-xl font-black">Recent rating changes</h2><Link href={`/profile/${user.id}`} className="text-sm font-bold text-primary-purple">View profile</Link></div>
          {ratingEvents.length ? <div className="space-y-2">{ratingEvents.map((event) => {const transition=rankTransition(event.rating_before,event.rating_after);const before=event.rank_before||transition.beforeTier;const after=event.rank_after||transition.afterTier;return <div key={event.id} className="flex items-center justify-between rounded-2xl bg-white p-4 shadow-sm"><div><p className="font-bold">{event.event_kind === 'match_result' ? 'Ranked match' : 'Rating history'}</p><p className="text-sm text-accent-gray-500">{event.rating_before} → {event.rating_after}</p>{before!==after&&<p className={`text-sm font-black ${event.rating_change>0?'text-green-600':'text-amber-700'}`}>{event.rating_change>0?'Promoted':'Demoted'} to {after}</p>}</div><span className={`text-xl font-black ${event.rating_change >= 0 ? 'text-green-600' : 'text-red-600'}`}>{event.rating_change >= 0 ? '+' : ''}{event.rating_change}</span></div>;})}</div> : <div className="rounded-2xl bg-white p-6 text-center text-accent-gray-500">Play your first ranked match.</div>}
        </section>
      </div>
    </main>
  );
}
