import { redirect } from 'next/navigation';
import CasualScorekeeper from './CasualScorekeeper';
import { getVerifiedUserId } from '@/lib/supabase/verified-user';

export default async function CasualPage() {
  if (!await getVerifiedUserId()) redirect('/login');
  return <CasualScorekeeper />;
}
