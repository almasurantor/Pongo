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
  const action = body.action;
  if (action !== 'accept' && action !== 'decline') return NextResponse.json({ error: 'Invalid action' }, { status: 400 });
  const { data, error } = await supabase.rpc('respond_challenge_v2', { p_challenge: id, p_action: action });
  if (error) return apiError(error);
  if (data?.status === 'expired') {
    return NextResponse.json(
      { error: 'This challenge has expired. Ask the challenger to send a new one.' },
      { status: 410 },
    );
  }
  return NextResponse.json(data);
}
