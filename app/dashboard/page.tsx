import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import DashboardClient from './DashboardClient';
import { OpponentRankedUsage, RankedUsage } from '@/lib/types';

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  const now = new Date().toISOString();
  const [
    { data: players },
    { data: pendingChallenges },
    { data: activeMatches },
    { data: disputes },
    { data: isAdmin },
    { data: usageData },
    { data: opponentUsageData },
  ] = await Promise.all([
    // This single ordered profile query supplies the current profile, rank,
    // and the Home player finder instead of fetching the same rows twice.
    supabase.from('profiles').select('*').order('current_elo', { ascending: false }),
    supabase
      .from('challenges')
      .select(`
        *,
        challenger:profiles!challenges_challenger_id_fkey(*),
        opponent:profiles!challenges_opponent_id_fkey(*)
      `)
      .or(`challenger_id.eq.${user.id},opponent_id.eq.${user.id}`)
      .eq('status', 'pending')
      .gt('expires_at', now)
      .order('created_at', { ascending: false }),
    supabase
      .from('matches')
      .select(`
        *,
        player_one:profiles!matches_player_one_id_fkey(*),
        player_two:profiles!matches_player_two_id_fkey(*)
      `)
      .or(`player_one_id.eq.${user.id},player_two_id.eq.${user.id}`)
      .eq('status', 'ready')
      .gt('expires_at', now)
      .order('created_at', { ascending: false }),
    supabase
      .from('disputes')
      .select(`*, match:matches(*, player_one:profiles!matches_player_one_id_fkey(*), player_two:profiles!matches_player_two_id_fkey(*))`)
      .in('status', ['pending', 'admin_review'])
      .order('created_at', { ascending: false }),
    supabase.rpc('is_admin'),
    supabase.rpc('get_my_ranked_usage_v3'),
    supabase.rpc('get_my_opponent_ranked_usage_v3'),
  ]);

  const profile = (players || []).find((player) => player.id === user.id);
  if (!profile) throw new Error('Your Pongo profile could not be loaded.');

  const activeMatchIds = (activeMatches || []).map((match) => match.id);
  const { data: cancellationRequests } = activeMatchIds.length
    ? await supabase
      .from('match_cancellation_requests')
      .select('*')
      .in('match_id', activeMatchIds)
      .eq('status', 'pending')
    : { data: [] };

  const rankedUsage = (usageData || {
    ranked_day: '',
    daily_used: 0,
    daily_limit: 10,
    daily_remaining: 10,
    active_used: activeMatches?.length || 0,
    active_limit: 3,
    active_remaining: Math.max(3 - (activeMatches?.length || 0), 0),
  }) as RankedUsage;

  return (
    <DashboardClient
      user={profile}
      players={(players || []).filter((player) => player.id !== user.id)}
      opponentUsage={(opponentUsageData || []) as OpponentRankedUsage[]}
      pendingChallenges={pendingChallenges || []}
      activeMatches={activeMatches || []}
      cancellationRequests={cancellationRequests || []}
      rankedUsage={rankedUsage}
      disputes={(disputes || []).filter((dispute) => dispute.match
        && (dispute.match.player_one_id === user.id || dispute.match.player_two_id === user.id))}
      isAdmin={!!isAdmin}
    />
  );
}
