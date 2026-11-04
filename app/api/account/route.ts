import { createClient as createAdminClient } from '@supabase/supabase-js';
import { NextResponse } from 'next/server';
import { createClient } from '@/lib/supabase/server';

const activeQueueStatuses = ['waiting', 'called', 'king', 'playing'];

export async function DELETE(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });

  const body = await request.json().catch(() => ({}));
  const { data: profile, error: profileError } = await supabase
    .from('profiles')
    .select('display_name')
    .eq('id', user.id)
    .single();
  if (profileError || !profile) return NextResponse.json({ error: 'Profile not found' }, { status: 404 });
  if (body.confirmation !== profile.display_name) {
    return NextResponse.json({ error: 'Type your display name exactly to confirm deletion.' }, { status: 400 });
  }

  const [matchesResult, challengesResult, queueResult] = await Promise.all([
    supabase.from('matches').select('id', { count: 'exact', head: true }).eq('status', 'ready').or(`player_one_id.eq.${user.id},player_two_id.eq.${user.id}`),
    supabase.from('challenges').select('id', { count: 'exact', head: true }).eq('status', 'pending').or(`challenger_id.eq.${user.id},opponent_id.eq.${user.id}`),
    supabase.from('beaver_queue_members').select('status').eq('user_id', user.id).maybeSingle(),
  ]);
  if (matchesResult.error || challengesResult.error || queueResult.error) {
    return NextResponse.json({ error: 'Could not verify account activity. Try again later.' }, { status: 503 });
  }
  const matchCount = matchesResult.count;
  const challengeCount = challengesResult.count;
  const queueMember = queueResult.data;
  if ((matchCount ?? 0) > 0 || (challengeCount ?? 0) > 0 || (queueMember && activeQueueStatuses.includes(queueMember.status))) {
    return NextResponse.json({ error: 'Leave the queue and resolve all pending matches and challenges before deleting your account.' }, { status: 409 });
  }

  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!serviceRoleKey) {
    return NextResponse.json({ error: 'Account deletion is not configured. Contact an administrator.' }, { status: 503 });
  }
  const admin = createAdminClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const anonymousName = `Deleted_${user.id.replaceAll('-', '').slice(0, 8)}`;
  const { error: anonymizeError } = await admin.from('profiles').update({ display_name: anonymousName }).eq('id', user.id);
  if (anonymizeError) return NextResponse.json({ error: 'Could not anonymize account.' }, { status: 500 });
  await admin.from('beaver_queue_members').update({ display_name: anonymousName }).eq('user_id', user.id);

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id, true);
  if (deleteError) {
    await admin.from('profiles').update({ display_name: profile.display_name }).eq('id', user.id);
    await admin.from('beaver_queue_members').update({ display_name: profile.display_name }).eq('user_id', user.id);
    return NextResponse.json({ error: 'Could not delete account. Try again later.' }, { status: 500 });
  }
  return NextResponse.json({ deleted: true });
}
