import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import MatchClient from './MatchClient';
import { Dispute, MatchSubmission } from '@/lib/types';

export default async function MatchPage({ params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect('/login');

  const { data: match } = await supabase
    .from('matches')
    .select(`
      *,
      player_one:profiles!matches_player_one_id_fkey(*),
      player_two:profiles!matches_player_two_id_fkey(*)
    `)
    .eq('id', params.id)
    .single();

  if (!match || (match.player_one_id !== user.id && match.player_two_id !== user.id)) {
    redirect('/dashboard');
  }

  const { data: cancellationRequest } = await supabase
    .from('match_cancellation_requests')
    .select('*')
    .eq('match_id', match.id)
    .eq('status', 'pending')
    .maybeSingle();
  const { data: dispute } = await supabase
    .from('disputes')
    .select('*')
    .eq('match_id', match.id)
    .in('status', ['pending', 'admin_review'])
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  const { data: mySubmission } = match.verification_mode === 'dual'
    ? await supabase
      .from('match_submissions')
      .select('*')
      .eq('match_id', match.id)
      .eq('submitted_by', user.id)
      .maybeSingle()
    : { data: null };

  return (
    <MatchClient
      match={match}
      cancellationRequest={cancellationRequest}
      dispute={dispute as Dispute | null}
      mySubmission={mySubmission as MatchSubmission | null}
      currentUserId={user.id}
    />
  );
}
