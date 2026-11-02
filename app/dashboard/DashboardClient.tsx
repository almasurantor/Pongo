'use client';

import Link from 'next/link';
import { useRef, useState } from 'react';
import toast from 'react-hot-toast';
import { useRouter } from 'next/navigation';
import { Challenge, Dispute, Match, MatchCancellationRequest, OpponentRankedUsage, Profile, RankedUsage } from '@/lib/types';
import { useDatabaseRefresh } from '@/lib/use-database-refresh';
import RankBadge, { RankProgress } from '@/components/RankBadge';
import DeadlineCountdown from '@/components/DeadlineCountdown';

interface Props {
  user: Profile;
  players: Profile[];
  opponentUsage: OpponentRankedUsage[];
  pendingChallenges: Challenge[];
  activeMatches: Match[];
  cancellationRequests: MatchCancellationRequest[];
  rankedUsage: RankedUsage;
  disputes: Dispute[];
  isAdmin: boolean;
}

export default function DashboardClient({
  user,
  players,
  opponentUsage,
  pendingChallenges,
  activeMatches,
  cancellationRequests,
  rankedUsage,
  disputes,
  isAdmin,
}: Props) {
  const router = useRouter();
  useDatabaseRefresh('home-actions', ['profiles', 'matches', 'challenges', 'disputes', 'match_cancellation_requests', 'rating_events']);
  const [loading, setLoading] = useState<string | null>(null);
  const [playerQuery, setPlayerQuery] = useState('');
  const [selectedCard, setSelectedCard] = useState(0);
  const cardTrackRef = useRef<HTMLDivElement>(null);

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
      if (result.match_id) router.push(`/match/${result.match_id}`);
      else router.refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not update challenge');
      router.refresh();
    }
  };

  const cancelChallenge = async (id: string) => {
    try {
      await post(`/api/challenges/${id}/cancel`, {}, `${id}-cancel`);
      toast.success('Challenge canceled');
      router.refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not cancel challenge');
    }
  };

  const challengePlayer = async (opponentId: string) => {
    try {
      await post('/api/challenges', { opponent_id: opponentId }, `challenge-${opponentId}`);
      toast.success('Challenge sent!');
      router.refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not send challenge');
    }
  };

  const respondCancellation = async (matchId: string, action: 'approve' | 'decline') => {
    try {
      await post(`/api/matches/${matchId}/cancellation`, { action }, `${matchId}-${action}`);
      toast.success(action === 'approve' ? 'Match canceled' : 'Cancellation declined');
      router.refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not respond to cancellation');
      router.refresh();
    }
  };
  const respondDispute = async (id: string, action: 'approve' | 'decline') => {
    try {
      const result = await post(`/api/disputes/${id}/respond`, { action }, `${id}-${action}`);
      toast.success(result.status === 'admin_review' ? 'Dispute escalated; ratings are unchanged' : 'Correction approved and ratings updated');
      router.refresh();
    } catch (error) {
      toast.error(error instanceof Error ? error.message : 'Could not respond to dispute');
      router.refresh();
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
  const usageFor = (playerId: string) => opponentUsage.find((item) => item.opponent_id === playerId);
  const visiblePlayers = players
    .filter((player) => player.display_name.toLowerCase().includes(playerQuery.trim().toLowerCase()))
    .slice(0, 5);
  const dashboardCards = ['Active Matches', 'Friends', 'Challenges'];
  const openCard = (index: number) => {
    const track = cardTrackRef.current;
    const card = track?.children[index] as HTMLElement | undefined;
    if (!track || !card) return;
    track.scrollTo({ left: card.offsetLeft - track.offsetLeft, behavior: 'smooth' });
    setSelectedCard(index);
  };
  const syncSelectedCard = () => {
    const track = cardTrackRef.current;
    if (!track) return;
    const cards = Array.from(track.children) as HTMLElement[];
    const closest = cards.reduce((best, card, index) => (
      Math.abs(card.offsetLeft - track.offsetLeft - track.scrollLeft)
        < Math.abs(cards[best].offsetLeft - track.offsetLeft - track.scrollLeft) ? index : best
    ), 0);
    setSelectedCard(closest);
  };

  return (
    <main className="app-screen min-h-screen bg-gradient-to-br from-white via-accent-gray-50 to-primary-purple/5 px-4 py-6 sm:py-10">
      <div className="app-screen-shell mx-auto max-w-5xl space-y-0 sm:space-y-7">
        <header className="screen-fixed flex items-end justify-between">
          <h1 className="text-3xl font-black sm:text-4xl">{user.display_name}</h1>
          {isAdmin && <Link href="/admin" className="rounded-full bg-accent-black px-4 py-2 text-sm font-bold text-white">Admin</Link>}
        </header>

        <section className="screen-fixed rounded-3xl gradient-purple p-4 text-white shadow-xl sm:p-5">
          <div className="flex items-end justify-between gap-3">
            <div>
              <p className="text-sm font-bold text-white/75">Competitive rank</p>
              <RankBadge elo={user.current_elo} totalGames={totalGames} className="mt-2" />
            </div>
            <div className="text-right"><p className="text-4xl font-black">{user.current_elo}</p><p className="text-sm font-bold text-white/75">ELO rating</p></div>
          </div>
          <div className="mt-4 grid grid-cols-2 gap-3 border-t border-white/20 pt-4 text-center">
            <div><p className="text-xl font-black">{user.total_wins}-{user.total_losses}</p><p className="text-xs text-white/70">Record</p></div>
            <div><p className="text-xl font-black">{winRate}%</p><p className="text-xs text-white/70">Win rate</p></div>
            <div><p className="text-xl font-black">{rankedUsage.daily_used}/{rankedUsage.daily_limit}</p><p className="text-xs text-white/70">Games today</p></div>
            <div><p className="text-xl font-black">{rankedUsage.active_used}/{rankedUsage.active_limit}</p><p className="text-xs text-white/70">Active matches</p></div>
          </div>
          <div className="mt-4 border-t border-white/20 pt-3"><RankProgress elo={user.current_elo} totalGames={totalGames} inverse /></div>
        </section>

        <nav className="screen-fixed grid grid-cols-3 gap-1 rounded-2xl border border-primary-purple/10 bg-white p-1 shadow-sm sm:hidden" aria-label="Dashboard cards">
          {dashboardCards.map((label, index) => (
            <button
              key={label}
              type="button"
              onClick={() => openCard(index)}
              aria-current={selectedCard === index ? 'page' : undefined}
              className={`min-h-10 rounded-xl px-2 text-xs font-black transition active:scale-[.97] sm:text-sm ${selectedCard === index ? 'bg-primary-purple text-white shadow-sm' : 'text-accent-gray-500 hover:bg-primary-purple/5'}`}
            >
              {label}
            </button>
          ))}
        </nav>

        <div
          ref={cardTrackRef}
          onScroll={syncSelectedCard}
          className="screen-flex grid min-h-0 snap-x snap-mandatory auto-cols-[100%] grid-flow-col gap-3 overflow-x-auto overscroll-x-contain scroll-smooth pb-1 [scrollbar-width:none] [&::-webkit-scrollbar]:hidden sm:grid-flow-row sm:grid-cols-3 sm:overflow-visible"
        >
          <section className="mobile-widget scroll-widget h-full min-w-0 snap-start rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-lg dark:border-[#393246] dark:bg-[#1c1828]">
            <div className="mb-3 flex items-center justify-between"><h2 className="text-xl font-black">Active Matches</h2><span className="text-sm font-bold text-accent-gray-500">{rankedUsage.active_used}/{rankedUsage.active_limit}</span></div>
            <div className="widget-scroll scroll-fade space-y-3 pr-1" tabIndex={0} aria-label="Active matches and requests">
              {disputesNeedResponse.map((dispute) => {
                const disputedMatch = dispute.match;
                const requester = disputedMatch?.player_one_id === dispute.opened_by ? disputedMatch.player_one : disputedMatch?.player_two;
                return <article key={dispute.id} className="rounded-2xl border-2 border-amber-300 bg-amber-50 p-4"><p className="text-xs font-black uppercase text-amber-700">Result dispute</p><p className="mt-1 font-black">{requester?.display_name} requested a {dispute.requested_resolution}</p>{dispute.requested_resolution==='correction'&&<p className="mt-2 rounded-xl bg-white p-2 font-black">Proposed: {dispute.proposed_player_one_score}–{dispute.proposed_player_two_score}</p>}<div className="mt-3 grid grid-cols-2 gap-2"><button disabled={loading!==null} onClick={()=>respondDispute(dispute.id,'decline')} className="min-h-11 rounded-xl border-2 border-amber-400 bg-white font-bold text-amber-800 disabled:opacity-50">Escalate</button><button disabled={loading!==null} onClick={()=>respondDispute(dispute.id,'approve')} className="min-h-11 rounded-xl bg-green-600 font-bold text-white disabled:opacity-50">Approve</button></div>{disputedMatch&&<Link href={`/match/${disputedMatch.id}`} className="mt-2 block text-center text-sm font-black text-amber-800">Review</Link>}</article>;
              })}
              {cancellationNeedsResponse.map((request) => {
                const match = activeMatches.find((candidate) => candidate.id === request.match_id);
                if (!match) return null;
                return <article key={request.id} className="rounded-2xl border-2 border-amber-300 bg-amber-50 p-4"><p className="text-xs font-black uppercase text-amber-700">Cancellation requested</p><p className="mt-1 font-black">{opponentFor(match)?.display_name} wants to cancel</p><div className="mt-3 grid grid-cols-2 gap-2"><button disabled={loading !== null} onClick={() => respondCancellation(match.id, 'decline')} className="min-h-11 rounded-xl border-2 border-amber-400 bg-white font-bold text-amber-800 disabled:opacity-50">Decline</button><button disabled={loading !== null} onClick={() => respondCancellation(match.id, 'approve')} className="min-h-11 rounded-xl bg-amber-600 font-bold text-white disabled:opacity-50">Approve</button></div></article>;
              })}
              {activeMatches.map((match) => {
                const request = requestFor(match.id);
                return <Link key={match.id} href={`/match/${match.id}`} className="block rounded-2xl border-2 border-primary-purple/15 bg-white p-4 shadow-sm transition active:scale-[.99]"><p className="text-xs font-black uppercase text-primary-purple">vs {opponentFor(match)?.display_name}</p>{opponentFor(match) && <div className="mt-2"><RankBadge elo={opponentFor(match)!.current_elo} totalGames={opponentFor(match)!.total_wins + opponentFor(match)!.total_losses} compact /></div>}<p className="mt-2 font-bold">{match.verification_mode === 'dual' ? 'Dual report' : 'Ready to score'}</p>{match.expires_at && <DeadlineCountdown deadline={match.expires_at} className="mt-1 block text-sm font-bold text-accent-gray-500" />}{request && <p className="mt-2 rounded-xl bg-amber-50 p-2 text-sm font-bold text-amber-700">{request.requested_by === user.id ? 'Cancellation pending' : 'Response needed'}</p>}</Link>;
              })}
              {!activeMatches.length && !disputesNeedResponse.length && !cancellationNeedsResponse.length && <div className="rounded-2xl bg-accent-gray-50 p-6 text-center text-accent-gray-500">No active matches.</div>}
            </div>
          </section>

          <section className="mobile-widget scroll-widget h-full min-w-0 snap-start rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-lg dark:border-[#393246] dark:bg-[#1c1828]">
            <div className="mb-3 flex items-center justify-between"><h2 className="text-xl font-black">Friends</h2><Link href="/players" className="text-sm font-bold text-primary-purple">View all</Link></div>
            <input type="search" value={playerQuery} onChange={(event) => setPlayerQuery(event.target.value)} placeholder="Search by name" className="mb-3 min-h-11 w-full rounded-2xl border-2 border-accent-gray-200 bg-white px-4 outline-none transition focus:border-primary-purple" />
            <div className="widget-scroll scroll-fade space-y-2 pr-1" tabIndex={0} aria-label="Friends and players">
              {visiblePlayers.map((player) => {
                const usage = usageFor(player.id);
                const remaining = usage?.games_remaining ?? 20;
                return <article key={player.id} className="flex items-center gap-3 rounded-2xl bg-white p-3 shadow-sm"><Link href={`/profile/${player.id}`} className="min-w-0 flex-1"><p className="truncate font-black">{player.display_name}</p><div className="mt-1 flex flex-wrap items-center gap-2"><RankBadge elo={player.current_elo} totalGames={player.total_wins + player.total_losses} compact /><span className="text-xs font-bold text-accent-gray-500">{player.current_elo} ELO</span></div></Link><button type="button" disabled={loading !== null || remaining === 0} onClick={() => challengePlayer(player.id)} className="min-h-10 rounded-xl bg-primary-purple px-3 text-sm font-black text-white disabled:opacity-45">{loading === `challenge-${player.id}` ? 'Sending…' : remaining === 0 ? 'Limit' : 'Challenge'}</button></article>;
              })}
              {!visiblePlayers.length && <div className="rounded-2xl bg-accent-gray-50 p-6 text-center text-accent-gray-500">No players found.</div>}
            </div>
          </section>

          <section className="mobile-widget scroll-widget h-full min-w-0 snap-start rounded-3xl border-2 border-accent-gray-200 bg-white p-4 shadow-lg dark:border-[#393246] dark:bg-[#1c1828]">
            <div className="mb-3 flex items-center justify-between"><h2 className="text-xl font-black">Challenges</h2><span className="text-sm font-bold text-accent-gray-500">{incoming.length + outgoing.length}</span></div>
            <div className="widget-scroll scroll-fade space-y-3 pr-1" tabIndex={0} aria-label="Incoming and outgoing challenges">
              {incoming.map((challenge) => <article key={challenge.id} className="rounded-2xl border-2 border-primary-purple/25 bg-white p-4 shadow-sm"><p className="text-xs font-black uppercase text-primary-purple">Incoming</p><p className="mt-1 text-lg font-black">{challenge.challenger?.display_name}</p>{challenge.challenger && <div className="mt-2"><RankBadge elo={challenge.challenger.current_elo} totalGames={challenge.challenger.total_wins + challenge.challenger.total_losses} compact /></div>}<DeadlineCountdown deadline={challenge.expires_at} className="mt-2 block text-sm font-bold text-accent-gray-500" /><div className="mt-3 grid grid-cols-2 gap-2"><button disabled={loading !== null} onClick={() => respondChallenge(challenge.id, 'decline')} className="min-h-11 rounded-xl border-2 border-accent-gray-300 font-bold disabled:opacity-50">Decline</button><button disabled={loading !== null} onClick={() => respondChallenge(challenge.id, 'accept')} className="min-h-11 rounded-xl gradient-purple font-bold text-white disabled:opacity-50">Accept</button></div></article>)}
              {outgoing.map((challenge) => <article key={challenge.id} className="flex items-center justify-between rounded-2xl bg-white p-4 shadow-sm"><div><p className="text-xs font-black uppercase text-accent-gray-400">Sent</p><p className="font-bold">{challenge.opponent?.display_name}</p>{challenge.opponent && <div className="mt-1"><RankBadge elo={challenge.opponent.current_elo} totalGames={challenge.opponent.total_wins + challenge.opponent.total_losses} compact /></div>}<DeadlineCountdown deadline={challenge.expires_at} className="mt-1 block text-sm font-bold text-accent-gray-500" /></div><button disabled={loading !== null} onClick={() => cancelChallenge(challenge.id)} className="min-h-10 rounded-xl px-3 font-bold text-red-600 disabled:opacity-50">Cancel</button></article>)}
              {!incoming.length && !outgoing.length && <div className="rounded-2xl bg-accent-gray-50 p-6 text-center text-accent-gray-500">No pending challenges.</div>}
            </div>
          </section>
        </div>
      </div>
    </main>
  );
}
