import HomePageClient from '../HomePageClient';
import { getVerifiedUserId } from '@/lib/supabase/verified-user';

export default async function LandingPage() {
  return <HomePageClient authenticated={Boolean(await getVerifiedUserId())} />;
}
