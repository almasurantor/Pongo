import { createClient } from '@/lib/supabase/server';
import { apiError, invalidJsonResponse, readJsonObject } from '@/lib/api-response';
import { NextResponse } from 'next/server';

export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const body = await readJsonObject(request);
  if (!body) return invalidJsonResponse();
  if (typeof body.opponent_id !== 'string') return NextResponse.json({ error: 'Opponent is required' }, { status: 400 });
  const { data, error } = await supabase.rpc('create_challenge_v2', { p_opponent: body.opponent_id });
  if (error) return apiError(error);
  return NextResponse.json({ challenge: Array.isArray(data) ? data[0] : data });
}
