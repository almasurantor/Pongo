import { apiError } from '@/lib/api-response';
import { createClient } from '@/lib/supabase/server';
import { NextResponse } from 'next/server';

export async function POST(_request: Request, { params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const { data, error } = await supabase.rpc('cancel_challenge_v2', { p_challenge: params.id });
  if (error) return apiError(error);
  const challenge = Array.isArray(data) ? data[0] : data;
  if (challenge?.status === 'expired') {
    return NextResponse.json({ error: 'This challenge has already expired.' }, { status: 410 });
  }
  return NextResponse.json({ challenge });
}
