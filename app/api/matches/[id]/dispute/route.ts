import { createClient } from '@/lib/supabase/server';
import { validateMatchScore } from '@/lib/match-result';
import { apiError } from '@/lib/api-response';
import { NextResponse } from 'next/server';

const reasons = ['incorrect_score', 'incorrect_winner', 'match_never_happened', 'other'];

export async function POST(request: Request, { params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const body = await request.json();
  if (!reasons.includes(body.reason)) return NextResponse.json({ error: 'Invalid dispute reason' }, { status: 400 });
  if (body.resolution !== 'correction' && body.resolution !== 'void') {
    return NextResponse.json({ error: 'Invalid requested resolution' }, { status: 400 });
  }

  let winnerScore: number | null = null;
  let loserScore: number | null = null;
  let winnerId: string | null = null;
  if (body.resolution === 'correction') {
    winnerScore = Number(body.winner_score);
    loserScore = Number(body.loser_score);
    winnerId = typeof body.winner_id === 'string' ? body.winner_id : null;
    const validation = validateMatchScore(winnerScore, loserScore);
    if (!winnerId || validation || winnerScore <= loserScore) {
      return NextResponse.json({ error: validation || 'A valid corrected result is required' }, { status: 400 });
    }
  }

  const { data, error } = await supabase.rpc('create_match_dispute_v3', {
    p_match: params.id,
    p_reason: body.reason,
    p_requested_resolution: body.resolution,
    p_winner: winnerId,
    p_winner_score: winnerScore,
    p_loser_score: loserScore,
  });
  if (error) return apiError(error);
  return NextResponse.json(data);
}
