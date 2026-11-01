import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import ProfileClient from './ProfileClient';
import { OpponentRankedUsage } from '@/lib/types';

export default async function ProfilePage({ params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();

  if (!user) {
    redirect('/login');
  }

  const { data: profile } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', params.id)
    .single();

  if (!profile) {
    redirect('/dashboard');
  }

  // Get match history - last 3 confirmed matches
  const { data: matches } = await supabase
    .from('matches')
    .select(`
      *,
      player_one:profiles!matches_player_one_id_fkey(*),
      player_two:profiles!matches_player_two_id_fkey(*)
    `)
    .eq('status', 'confirmed')
    .or(`player_one_id.eq.${params.id},player_two_id.eq.${params.id}`)
    .order('confirmed_at', { ascending: false })
    .limit(3);

  const [{ data: ratings }, { data: rankedPlayers }, { data: opponentUsageRows }] = await Promise.all([
    supabase.from('rating_events').select('*').eq('player_id', params.id).eq('is_active', true).order('created_at', { ascending: false }).limit(5),
    supabase.from('profiles').select('id').order('current_elo', { ascending: false }),
    supabase.rpc('get_my_opponent_ranked_usage_v3'),
  ]);
  const rank = (rankedPlayers || []).findIndex((player) => player.id === params.id) + 1;
  const opponentUsage = ((opponentUsageRows || []) as OpponentRankedUsage[]).find((row) => row.opponent_id === params.id) || null;

  return <ProfileClient profile={profile} matches={matches || []} ratingEvents={ratings || []} opponentUsage={opponentUsage} rank={rank || 1} currentUserId={user.id} />;
}
