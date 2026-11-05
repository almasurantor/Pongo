import { apiError, invalidJsonResponse, readJsonObject } from '@/lib/api-response';
import { createClient } from '@/lib/supabase/server';
import { NextResponse } from 'next/server';

export async function POST(request: Request, { params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await readJsonObject(request);
  if (!body) return invalidJsonResponse();
  const action = body.action;
  if (typeof action !== 'string' || !['request', 'approve', 'decline'].includes(action)) {
    return NextResponse.json({ error: 'Action must be request, approve, or decline' }, { status: 400 });
  }

  const rpc = action === 'request'
    ? supabase.rpc('request_match_cancellation_v2', { p_match: id })
    : supabase.rpc('respond_match_cancellation_v2', {
      p_match: id,
      p_approve: action === 'approve',
    });
  const { data, error } = await rpc;
  if (error) return apiError(error);
  if (data?.status === 'expired') {
    return NextResponse.json({ error: 'This match has expired without rating changes.' }, { status: 410 });
  }
  return NextResponse.json(data);
}
