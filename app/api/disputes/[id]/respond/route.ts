import { createClient } from '@/lib/supabase/server';
import { apiError } from '@/lib/api-response';
import { NextResponse } from 'next/server';

export async function POST(request: Request, { params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { action } = await request.json();
  if (action !== 'approve' && action !== 'decline') return NextResponse.json({ error: 'Invalid action' }, { status: 400 });
  const { data, error } = await supabase.rpc('respond_match_dispute_v3', {
    p_dispute: params.id,
    p_action: action,
  });
  if (error) return apiError(error);
  return NextResponse.json(data);
}
