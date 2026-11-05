import { createClient } from '@/lib/supabase/server';
import { apiError, invalidJsonResponse, readJsonObject } from '@/lib/api-response';
import { NextResponse } from 'next/server';

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const body = await readJsonObject(request);
  if (!body) return invalidJsonResponse();
  const { data, error } = await supabase.rpc('admin_resolve_dispute_v3', {
    p_dispute: id,
    p_resolution: typeof body.resolution === 'string' ? body.resolution : null,
    p_winner: typeof body.winner_id === 'string' ? body.winner_id : null,
    p_winner_score: body.winner_score == null ? null : Number(body.winner_score),
    p_loser_score: body.loser_score == null ? null : Number(body.loser_score),
    p_violation_user: typeof body.violation_user_id === 'string' ? body.violation_user_id : null,
    p_notes: typeof body.notes === 'string' ? body.notes : null,
  });
  if (error) return apiError(error);
  return NextResponse.json(data);
}
