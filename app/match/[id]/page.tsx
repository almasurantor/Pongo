import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import MatchClient from './MatchClient';
import { Dispute, MatchSubmission, RatingEvent } from '@/lib/types';
import { getVerifiedUserId } from '@/lib/supabase/verified-user';

export default async function MatchPage({ params }: { params: Promise<{ id: string }> }) {
  const supabase = await createClient();
  const userId = await getVerifiedUserId();
  if (!userId) redirect('/login');
  const { id } = await params;

  const { data: match } = await supabase
    .from('matches')
    .select(`
      *,
      player_one:profiles!matches_player_one_id_fkey(*),
      player_two:profiles!matches_player_two_id_fkey(*)
    `)
    .eq('id', id)
    .single();

  if (!match || (match.player_one_id !== userId && match.player_two_id !== userId)) {
    redirect('/dashboard');
  }

  const [{ data: cancellationRequest }, { data: dispute }, { data: mySubmission }, { data: ratingEvents }] = await Promise.all([
    supabase
      .from('match_cancellation_requests')
      .select('*')
      .eq('match_id', match.id)
      .eq('status', 'pending')
      .maybeSingle(),
    supabase
      .from('disputes')
      .select('*')
      .eq('match_id', match.id)
      .in('status', ['pending', 'admin_review'])
      .order('created_at', { ascending: false })
      .limit(1)
      .maybeSingle(),
    match.verification_mode === 'dual'
      ? supabase
        .from('match_submissions')
        .select('*')
        .eq('match_id', match.id)
        .eq('submitted_by', userId)
        .maybeSingle()
      : Promise.resolve({ data: null }),
    supabase
      .from('rating_events')
      .select('*')
      .eq('match_id', match.id)
      .eq('is_active', true)
      .in('player_id', [match.player_one_id, match.player_two_id]),
  ]);

  return (
    <MatchClient
      match={match}
      cancellationRequest={cancellationRequest}
      dispute={dispute as Dispute | null}
      mySubmission={mySubmission as MatchSubmission | null}
      ratingEvents={(ratingEvents || []) as RatingEvent[]}
      currentUserId={userId}
    />
  );
}
