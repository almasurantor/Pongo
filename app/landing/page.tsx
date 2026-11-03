import HomePageClient from '../HomePageClient';
import { createClient } from '@/lib/supabase/server';

export default async function LandingPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  return <HomePageClient authenticated={Boolean(user)} />;
}
