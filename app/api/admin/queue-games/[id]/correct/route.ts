import { apiError } from '@/lib/api-response';
import { createClient } from '@/lib/supabase/server';
import { NextResponse } from 'next/server';

export async function POST(request: Request, { params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  let body: { winner_id?: unknown; reason?: unknown };
  try { body = await request.json(); }
  catch { return NextResponse.json({ error: 'Invalid JSON body' }, { status: 400 }); }

  if (typeof body.winner_id !== 'string' || typeof body.reason !== 'string') {
    return NextResponse.json({ error: 'Winner and correction reason are required' }, { status: 400 });
  }

  const { data, error } = await supabase.rpc('beaver_queue_admin_correct_game_v1', {
    p_game_id: params.id,
    p_winner_id: body.winner_id,
    p_reason: body.reason,
  });
  if (error) return apiError(error);
  return NextResponse.json({ game: data });
}
