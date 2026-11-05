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
  if (typeof body.level !== 'string') {
    return NextResponse.json({ error: 'Integrity level is required' }, { status: 400 });
  }
  const { data, error } = await supabase.rpc('admin_set_player_integrity_v2', {
    p_player: id,
    p_level: body.level,
    p_reason: typeof body.reason === 'string' ? body.reason : null,
  });
  if (error) return apiError(error);
  return NextResponse.json({ integrity: Array.isArray(data) ? data[0] : data });
}
