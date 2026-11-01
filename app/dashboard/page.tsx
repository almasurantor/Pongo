import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import DashboardClient from './DashboardClient';
import { RankedUsage } from '@/lib/types';

export default async function DashboardPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  // Get user profile
  const { data: profile } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', user.id)
    .single();

  if (!profile) {
    redirect('/login');
  }

  // Rankings are derived directly from current database ratings.
  const { data: players } = await supabase
    .from('profiles')
    .select('*')
    .order('current_elo', { ascending: false });

  // Get pending challenges for current user
  const { data: pendingChallenges } = await supabase
    .from('challenges')
    .select(`
      *,
      challenger:profiles!challenges_challenger_id_fkey(*),
      opponent:profiles!challenges_opponent_id_fkey(*)
    `)
    .or(`challenger_id.eq.${user.id},opponent_id.eq.${user.id}`)
    .eq('status', 'pending')
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false });

  // Phase 1 active matches are accepted challenges awaiting their first score.
  const { data: activeMatches } = await supabase
    .from('matches')
    .select(`
      *,
      player_one:profiles!matches_player_one_id_fkey(*),
      player_two:profiles!matches_player_two_id_fkey(*)
    `)
    .or(`player_one_id.eq.${user.id},player_two_id.eq.${user.id}`)
    .eq('status', 'ready')
    .gt('expires_at', new Date().toISOString())
    .order('created_at', { ascending: false });

  const activeMatchIds = (activeMatches || []).map((match) => match.id);
  const { data: cancellationRequests } = activeMatchIds.length
    ? await supabase
      .from('match_cancellation_requests')
      .select('*')
      .in('match_id', activeMatchIds)
      .eq('status', 'pending')
    : { data: [] };

  const { data: ratingEvents } = await supabase
    .from('rating_events')
    .select('*')
    .eq('player_id', user.id)
    .eq('is_active', true)
    .order('created_at', { ascending: false })
    .limit(5);
  const { data: disputes } = await supabase
    .from('disputes')
    .select(`*, match:matches(*, player_one:profiles!matches_player_one_id_fkey(*), player_two:profiles!matches_player_two_id_fkey(*))`)
    .in('status', ['pending', 'admin_review'])
    .order('created_at', { ascending: false });
  const { data: isAdmin } = await supabase.rpc('is_admin');
  const { data: usageData } = await supabase.rpc('get_my_ranked_usage_v3');
  const rankedUsage = (usageData || {
    ranked_day: '',
    daily_used: 0,
    daily_limit: 10,
    daily_remaining: 10,
    active_used: activeMatches?.length || 0,
    active_limit: 3,
    active_remaining: Math.max(3 - (activeMatches?.length || 0), 0),
  }) as RankedUsage;

  const rank = (players || []).findIndex((player) => player.id === user.id) + 1;

  return (
    <DashboardClient
      user={profile}
      rank={rank || 1}
      pendingChallenges={pendingChallenges || []}
      activeMatches={activeMatches || []}
      cancellationRequests={cancellationRequests || []}
      rankedUsage={rankedUsage}
      ratingEvents={ratingEvents || []}
      disputes={(disputes || []).filter((dispute) => dispute.match
        && (dispute.match.player_one_id === user.id || dispute.match.player_two_id === user.id))}
      isAdmin={!!isAdmin}
    />
  );
}
