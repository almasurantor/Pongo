import { createClient } from '@/lib/supabase/server';
import { validateMatchScore } from '@/lib/match-result';
import { apiError } from '@/lib/api-response';
import { NextResponse } from 'next/server';

export async function POST(request: Request, { params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json();
  const winnerScore = Number(body.winner_score);
  const loserScore = Number(body.loser_score);
  const validationError = validateMatchScore(winnerScore, loserScore);
  if (validationError || winnerScore <= loserScore) return NextResponse.json({ error: validationError || 'Winner score must be higher' }, { status: 400 });
  if (typeof body.winner_id !== 'string') return NextResponse.json({ error: 'Winner is required' }, { status: 400 });

  const { data, error } = await supabase.rpc('submit_match_report_v2', {
    p_match: params.id,
    p_winner: body.winner_id,
    p_winner_score: winnerScore,
    p_loser_score: loserScore,
  });

  if (error) return apiError(error);
  if (data?.conflicting_reports) {
    return NextResponse.json({ error: 'The independent reports did not match. The match was closed and no ratings changed.' }, { status: 409 });
  }
  if (data?.status === 'expired') {
    return NextResponse.json({ error: 'This match has expired without rating changes.' }, { status: 410 });
  }
  const [{ data: finalizedMatch }, { data: afterStandings }] = await Promise.all([
    supabase.from('matches').select('*').eq('id', params.id).single(),
    supabase.rpc('get_leaderboard_v3', { p_scope: 'all_time', p_period_start: null }),
  ]);
  const placementAfter = (afterStandings || []).find((entry: { player_id: string }) => entry.player_id === user.id)?.placement ?? null;
  return NextResponse.json({
    ...data,
    match: finalizedMatch,
    placement_after: placementAfter,
  });
}
