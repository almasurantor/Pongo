import { createClient } from '@/lib/supabase/server';
import { redirect } from 'next/navigation';
import LeaderboardClient from './LeaderboardClient';
import { LeaderboardArchiveEntry, LeaderboardEntry, LeaderboardScope } from '@/lib/types';
import { getVerifiedUserId } from '@/lib/supabase/verified-user';

const scopes: LeaderboardScope[] = ['weekly', 'monthly', 'all_time'];

export default async function LeaderboardPage({ searchParams }: { searchParams?: { tab?: string; period?: string } }) {
  const supabase = await createClient();
  const userId = await getVerifiedUserId();
  if (!userId) redirect('/login');

  const scope = scopes.includes(searchParams?.tab as LeaderboardScope)
    ? searchParams!.tab as LeaderboardScope
    : 'weekly';
  const requestedPeriod = scope !== 'all_time' && /^\d{4}-\d{2}-\d{2}$/.test(searchParams?.period || '')
    ? searchParams!.period!
    : null;

  const leaderboardPromise = supabase.rpc('get_leaderboard_v3', {
    p_scope: scope,
    p_period_start: requestedPeriod,
  });
  const archivePromise = scope === 'all_time'
    ? Promise.resolve({ data: [], error: null })
    : supabase.rpc('get_leaderboard_archive_v3', { p_scope: scope, p_limit: 12 });
  const [{ data: entries, error }, { data: archives }, { data: avatarRows }] = await Promise.all([
    leaderboardPromise,
    archivePromise,
    supabase.from('profiles').select('id,avatar_config'),
  ]);
  const avatarConfigs = Object.fromEntries((avatarRows || []).map((row) => [row.id, row.avatar_config]));

  return (
    <LeaderboardClient
      entries={(entries || []) as LeaderboardEntry[]}
      archives={(archives || []) as LeaderboardArchiveEntry[]}
      scope={scope}
      selectedPeriod={requestedPeriod}
      currentUserId={userId}
      loadError={error?.message || null}
      avatarConfigs={avatarConfigs}
    />
  );
}
