import { createClient } from '@/lib/supabase/server';
import { apiError } from '@/lib/api-response';
import { NextResponse } from 'next/server';

export async function POST(_request: Request, { params }: { params: { id: string } }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  const { data, error } = await supabase.rpc('admin_review_integrity_flag_v3', { p_flag: params.id });
  if (error) return apiError(error);
  return NextResponse.json({ flag: Array.isArray(data) ? data[0] : data });
}
