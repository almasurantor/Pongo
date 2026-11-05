import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import ProfileClient from './ProfileClient';
import { OpponentRankedUsage } from '@/lib/types';
import { getVerifiedUserId } from '@/lib/supabase/verified-user';

export default async function ProfilePage({ params }: { params: Promise<{ id: string }> }) {
  const supabase = await createClient();
  const userId = await getVerifiedUserId();
  if (!userId) redirect('/login');
  const { id } = await params;

  const [{ data: profile }, { data: matches }, { data: rankedPlayers }, { data: opponentUsageRows }] = await Promise.all([
    supabase.from('profiles').select('*').eq('id', id).single(),
    // Full confirmed history, newest first. The client keeps this list compact.
    supabase
      .from('matches')
      .select(`
        *,
        player_one:profiles!matches_player_one_id_fkey(*),
        player_two:profiles!matches_player_two_id_fkey(*)
      `)
      .eq('status', 'confirmed')
      .or(`player_one_id.eq.${id},player_two_id.eq.${id}`)
      .order('confirmed_at', { ascending: false }),
    supabase.from('profiles').select('id').order('current_elo', { ascending: false }),
    supabase.rpc('get_my_opponent_ranked_usage_v3'),
  ]);

  if (!profile) redirect('/dashboard');
  const rank = (rankedPlayers || []).findIndex((player) => player.id === id) + 1;
  const opponentUsage = ((opponentUsageRows || []) as OpponentRankedUsage[]).find((row) => row.opponent_id === id) || null;

  return <ProfileClient profile={profile} matches={matches || []} opponentUsage={opponentUsage} rank={rank || 1} currentUserId={userId} />;
}
