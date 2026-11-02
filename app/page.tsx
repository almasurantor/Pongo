import HomePageClient from './HomePageClient';
import { createClient } from '@/lib/supabase/server';

export default async function Home() {
  // Middleware has already resolved the session and redirected authenticated
  // launches before this public landing page can render.
  const supabase = await createClient();
  const [players, matches] = await Promise.all([
    supabase.from('profiles').select('id', { count: 'exact', head: true }),
    supabase.from('match_history').select('id', { count: 'exact', head: true }),
  ]);
  return <HomePageClient playerCount={players.error ? null : players.count}
    matchCount={matches.error ? null : matches.count} />;
}
