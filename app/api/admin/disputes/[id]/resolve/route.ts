import { createClient } from '@/lib/supabase/server';
import { apiError } from '@/lib/api-response';
import { NextResponse } from 'next/server';

export async function POST(request: Request, { params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const body = await request.json();
  const { data, error } = await supabase.rpc('admin_resolve_dispute_v3', {
    p_dispute: params.id,
    p_resolution: body.resolution,
    p_winner: body.winner_id || null,
    p_winner_score: body.winner_score == null ? null : Number(body.winner_score),
    p_loser_score: body.loser_score == null ? null : Number(body.loser_score),
    p_violation_user: body.violation_user_id || null,
    p_notes: body.notes || null,
  });
  if (error) return apiError(error);
  return NextResponse.json(data);
}
