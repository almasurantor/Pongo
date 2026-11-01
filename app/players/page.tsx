import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import PlayersClient from './PlayersClient';
import { OpponentRankedUsage } from '@/lib/types';

export default async function PlayersPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/login');
  const [{ data: players }, { data: usage }] = await Promise.all([
    supabase.from('profiles').select('*').order('current_elo', { ascending: false }),
    supabase.rpc('get_my_opponent_ranked_usage_v3'),
  ]);
  return <PlayersClient players={players || []} usage={(usage || []) as OpponentRankedUsage[]} currentUserId={user.id} />;
}
